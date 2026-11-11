import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Scrolling market and FX quotes for the Omarchy bar. Right-click opens the
// Markets menu (display currency and watchlist) at the click point.
Item {
  id: ticker
  clip: true
  // The bar host; the right-click menu is an Omarchy KeyboardPanel on it.
  property var bar: null
  property string fontFamily: Style.font.family
  property string selectedCurrency: "USD"
  property string feedStatus: ""
  property string richTicker: "<font color='#57d68d'><b>LOADING</b></font> market quotes…   "
  property real scrollOffset: 0
  property string trend: "neutral"

  // Right-click menu state: open flag, saved watchlist, search.
  property bool opened: false
  property var watchlist: []
  property string query: ""
  property var results: []
  property bool searching: false
  property bool searchFailed: false
  property int cursorIndex: -1
  property var pendingEdits: []
  readonly property string watchlistScript: localFilePath(Qt.resolvedUrl("market-feed/watchlist.py"))

  function money(value, digits) {
    if (value === null || value === undefined || !isFinite(Number(value))) return "—"
    var fixed = Number(value).toFixed(digits).split(".")
    var integer = fixed[0]
    var sign = ""
    if (integer.charAt(0) === "-") {
      sign = "-"
      integer = integer.slice(1)
    }
    return sign + integer.replace(/\B(?=(\d{3})+(?!\d))/g, ".")
      + (digits > 0 ? "," + fixed[1] : "")
  }

  function escapeHtml(value) {
    return String(value).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\"/g, "&quot;")
  }

  function updateTicker(raw) {
    if (!raw || !raw.currency || !Array.isArray(raw.assets)) throw new Error("bad market response")
    // Follow the S&P 500 rather than an arbitrary snapshot of crypto prices.
    var benchmark = raw.assets.find(function (item) { return item.symbol === "^GSPC" })
    var indexChange = benchmark && benchmark.change_pct !== null && benchmark.change_pct !== undefined ? Number(benchmark.change_pct) : NaN
    ticker.trend = raw.status === "OFFLINE" || !isFinite(indexChange) ? "neutral" : indexChange >= 0 ? "up" : "down"
    ticker.feedStatus = String(raw.status || "")
    if (raw.currency.target) ticker.selectedCurrency = String(raw.currency.target)
    var oldCycle = Math.max(1, marquee.implicitWidth / 4)
    var phase = ticker.scrollOffset % oldCycle
    var rate = raw.currency.rate === null ? null : Number(raw.currency.rate)
    var symbol = escapeHtml(raw.currency.symbol || "")
    var status = escapeHtml(raw.status || "OFFLINE")
    var statusColor = status === "LIVE" ? "#57d68d" : status === "PARTIAL" ? "#f2c14e" : "#ff6b6b"
    var html = status === "LIVE" ? "" : "<font color='" + statusColor + "'><b>" + status + "</b> " + escapeHtml(raw.message || "market data unavailable") + "</font>  ◈  "
    var quotes = raw.assets.concat(raw.currencies || [])
    for (var i = 0; i < quotes.length; i++) {
      var item = quotes[i]
      if (i > 0) html += "  ◈  "
      var value = item.price === null || item.price === undefined ? null : Number(item.price)
      var change = item.change_pct === null || item.change_pct === undefined ? NaN : Number(item.change_pct)
      var converted = item.direct_target ? value : (value !== null && isFinite(rate) && rate > 0 ? value * rate : null)
      var movement = isNaN(change) ? "#f5f7fa" : change >= 0 ? "#57d68d" : "#ff6b6b"
      var digits = Math.max(0, Math.min(6, Number(item.digits) || 0))
      html += "<font color='#f5f7fa'><b>" + escapeHtml(item.label || item.symbol || "Asset") + "</b></font> "
      html += "<font color='" + movement + "'><b>" + (item.is_currency_pair ? "" : symbol) + money(converted, digits) + "</b></font>"
      if (!isNaN(change)) html += " <font color='" + movement + "'>" + (change >= 0 ? "↑" : "↓") + Math.abs(change).toFixed(2) + "%</font>"
    }
    // One continuous quote stream; category labels and the LIVE/in-currency
    // banner are intentionally omitted.
    ticker.richTicker = html + "&nbsp;&nbsp;&nbsp;&nbsp;"
    ticker.scrollOffset = phase
  }

  function localFilePath(url) {
    var value = String(url)
    if (value.indexOf("file://") !== 0) throw new Error("expected a local file URL")
    return decodeURIComponent(value.substring(7))
  }

  function open() {
    query = ""
    results = []
    cursorIndex = -1
    opened = true
    listProc.running = true
  }

  function close() { opened = false }

  function refreshFeedNow() {
    feed.running = false
    refreshFeed.restart()
  }

  // Watchlist edits run one at a time, in order; the feed refreshes after.
  function edit(args) {
    pendingEdits = pendingEdits.concat([args])
    if (!editProc.running) runNextEdit()
  }

  function runNextEdit() {
    if (pendingEdits.length === 0) {
      listProc.running = true
      refreshFeedNow()
      return
    }
    editProc.command = ["python3", ticker.watchlistScript].concat(pendingEdits[0])
    pendingEdits = pendingEdits.slice(1)
    editProc.running = true
  }

  function chooseCurrency(code) {
    if (code === selectedCurrency) return
    selectedCurrency = code
    edit(["currency", code])
  }

  function isWatched(symbol) {
    var wanted = String(symbol).toUpperCase()
    for (var i = 0; i < watchlist.length; i++)
      if (String(watchlist[i].symbol).toUpperCase() === wanted) return true
    return false
  }

  function addSymbol(result) {
    if (!result || isWatched(result.symbol)) return
    watchlist = watchlist.concat([{ symbol: result.symbol, label: result.label }])
    edit(["add", result.symbol, result.name || result.label || ""])
  }

  function removeSymbol(symbol) {
    var wanted = String(symbol).toUpperCase()
    watchlist = watchlist.filter(function(item) { return String(item.symbol).toUpperCase() !== wanted })
    edit(["remove", symbol])
  }

  function toggleResult(result) {
    if (!result) return
    if (isWatched(result.symbol)) removeSymbol(result.symbol)
    else addSymbol(result)
  }

  onQueryChanged: {
    cursorIndex = query.trim() === "" ? -1 : 0
    searchFailed = false
    if (query.trim() === "") {
      results = []
      searching = false
      searchDebounce.stop()
    } else {
      searching = true
      searchDebounce.restart()
    }
  }

  Timer {
    id: searchDebounce
    interval: 280
    onTriggered: ticker.runSearch()
  }

  // One search in flight; a query typed meanwhile runs when it finishes.
  function runSearch() {
    if (searchProc.running) { searchProc.again = true; return }
    searchProc.requested = ticker.query.trim()
    if (searchProc.requested === "") return
    searchProc.command = ["python3", ticker.watchlistScript, "search", searchProc.requested]
    searchProc.running = true
  }

  Process {
    id: searchProc
    property string requested: ""
    property bool again: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (searchProc.requested !== ticker.query.trim()) return
        var found = null
        try { found = JSON.parse(String(text || "null")) } catch (e) { found = null }
        ticker.searching = false
        ticker.searchFailed = !Array.isArray(found)
        ticker.results = Array.isArray(found) ? found : []
        if (ticker.cursorIndex >= ticker.results.length) ticker.cursorIndex = ticker.results.length - 1
      }
    }
    onExited: {
      if (!again) return
      again = false
      Qt.callLater(ticker.runSearch)
    }
  }

  Process {
    id: listProc
    command: ["python3", ticker.watchlistScript, "list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        let data = null
        try { data = JSON.parse(String(text || "null")) } catch (e) { data = null }
        if (!data || !Array.isArray(data.assets) || ticker.pendingEdits.length > 0 || editProc.running) return
        ticker.watchlist = data.assets
      }
    }
  }

  Process {
    id: editProc
    onExited: ticker.runNextEdit()
  }

  Process {
    id: feed
    command: ["python3", ticker.localFilePath(Qt.resolvedUrl("market-feed/fetch_markets.py"))]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { ticker.updateTicker(JSON.parse(String(text || "{}"))) }
        catch (e) {
          ticker.trend = "neutral"
          ticker.feedStatus = "OFFLINE"
          ticker.richTicker = "<font color='#ff6b6b'><b>MARKET FEED ERROR</b></font>  retrying…   "
        }
      }
    }
  }
  Timer { id: refreshFeed; interval: 800; onTriggered: if (ticker.visible) feed.running = true }
  Timer { interval: 120000; repeat: true; running: ticker.visible; onTriggered: if (!feed.running) feed.running = true }
  // Ease the marquee so quotes remain readable while still moving continuously.
  Timer { interval: 30; repeat: true; running: ticker.visible; onTriggered: ticker.scrollOffset += 1 }
  Component.onCompleted: if (ticker.visible) feed.running = true
  onVisibleChanged: {
    if (visible) feed.running = true
    else ticker.close()
  }

  Rectangle {
    anchors.fill: parent
    radius: 15
    color: ticker.trend === "up" ? "#20382f" : ticker.trend === "down" ? "#392831" : "#24273a"
    clip: true
    Behavior on color { ColorAnimation { duration: 800 } }
    Item {
      id: marqueeViewport
      anchors.fill: parent
      anchors.leftMargin: 12
      anchors.rightMargin: 12
      clip: true
      Text {
        id: marquee
        x: -(ticker.scrollOffset % Math.max(1, implicitWidth / 4))
        anchors.verticalCenter: parent.verticalCenter
        text: ticker.richTicker + ticker.richTicker + ticker.richTicker + ticker.richTicker
        textFormat: Text.RichText
        font.family: ticker.fontFamily
        font.pixelSize: Math.min(Style.font.body, Math.max(1, parent.height - 2))
        color: "#f5f7fa"
        width: implicitWidth
        wrapMode: Text.NoWrap
      }
    }
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.RightButton
      onClicked: function(mouse) {
        menuAnchor.x = Math.round(mouse.x)
        if (ticker.opened) ticker.close()
        else ticker.open()
      }
    }
  }

  // KeyboardPanel centres its card on the anchor, so an anchor one card wide
  // starting at the click puts the card's left edge where the click was.
  Item {
    id: menuAnchor
    y: 0
    width: marketMenu.contentWidth
    height: ticker.height
  }

  MarketMenu {
    id: marketMenu
    ticker: ticker
    anchorItem: menuAnchor
    owner: ticker
    bar: ticker.bar
    open: ticker.opened && !!ticker.bar
  }
}
