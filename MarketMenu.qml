import QtQuick
import qs.Ui
import qs.Commons
import qs.Commons as Commons

// Right-click menu of the market ticker, built from the same Omarchy panel
// parts as the stock bar popups: the currencies prices can be shown in (add
// with +, remove with the × on a currency), then the watchlist with a symbol
// search (type to search, ↑/↓ to pick, Enter to add or remove).
KeyboardPanel {
  id: menu

  property var ticker: null

  readonly property color fg: bar && bar.foreground !== undefined ? bar.foreground : Commons.Color.popups.text
  readonly property color dim: Qt.darker(fg, 1.4)
  readonly property string fontFamily: bar && bar.fontFamily ? bar.fontFamily : Style.font.family
  readonly property bool searchMode: !!ticker && ticker.query.trim() !== ""
  readonly property var rows: !ticker ? [] : (searchMode ? ticker.results : ticker.watchlist)
  readonly property real rowHeight: Style.space(34)
  readonly property int visibleRows: 8
  readonly property string message: {
    if (!ticker) return ""
    if (searchMode) {
      if (ticker.searching && rows.length === 0) return "Searching…"
      if (ticker.searchFailed) return "Search unavailable"
      if (rows.length === 0) return "No matches"
      return ""
    }
    return rows.length === 0 ? "Watchlist is empty" : ""
  }

  readonly property string glyphMarkets: String.fromCodePoint(0xF081F)  // md-finance
  readonly property string glyphAdd: String.fromCodePoint(0xF0415)      // md-plus
  readonly property string glyphAdded: String.fromCodePoint(0xF012C)    // md-check
  readonly property string glyphRemove: String.fromCodePoint(0xF0156)   // md-close

  // Currencies: up to three fill the row. With more, the row scrolls sideways
  // and the next currency peeks in at the edge.
  readonly property real currencySpacing: Style.spacing.xs
  readonly property int currencyCount: ticker ? ticker.currencies.length : 0
  readonly property real currencyCellWidth: currencyCount > 3
    ? (currencyRow.width - currencySpacing * 3) / 3.4
    : (currencyRow.width - currencySpacing * 2) / 3
  // Adding a currency: the field under the row, and the cursor in its matches.
  property bool addingCurrency: false
  property int currencyCursor: 0
  readonly property var currencySuggestions: {
    if (!ticker || !addingCurrency) return []
    var query = currencyField.text.trim().toUpperCase()
    if (query === "") return []
    var matches = []
    var known = ticker.knownCurrencies
    for (var i = 0; i < known.length; i++) {
      var entry = known[i]
      if (ticker.hasCurrency(entry.code)) continue
      var name = String(entry.name).toUpperCase()
      var rank = entry.code === query ? 0 : entry.code.indexOf(query) === 0 ? 1
        : name.indexOf(query) === 0 ? 2 : name.indexOf(query) > 0 ? 3 : -1
      if (rank >= 0) matches.push({ rank: rank, entry: entry })
    }
    matches.sort(function(a, b) { return a.rank - b.rank })
    return matches.slice(0, 5).map(function(match) { return match.entry })
  }

  focusTarget: searchField
  contentWidth: fittedContentWidth(Style.space(380))
  contentHeight: fittedContentHeight(content.implicitHeight, Style.space(720))

  onOpenChanged: {
    if (!open) return
    searchField.text = ""
    addingCurrency = false
    currencyField.text = ""
    Qt.callLater(function() { if (menu.ticker) menu.showCurrency(menu.ticker.selectedCurrency) })
  }

  // Scrolls the currency row just enough to show a currency.
  function showCurrency(code) {
    if (!ticker) return
    for (var i = 0; i < ticker.currencies.length; i++) {
      if (ticker.currencies[i].code !== code) continue
      var left = i * (currencyCellWidth + currencySpacing)
      var right = left + currencyCellWidth
      if (left < currencyFlick.contentX) currencyFlick.contentX = left
      else if (right > currencyFlick.contentX + currencyFlick.width) currencyFlick.contentX = right - currencyFlick.width
      return
    }
  }

  function startAddingCurrency() {
    if (!ticker) return
    ticker.loadKnownCurrencies()
    currencyField.text = ""
    currencyCursor = 0
    addingCurrency = true
    currencyField.forceActiveFocus()
  }

  function stopAddingCurrency() {
    addingCurrency = false
    currencyField.text = ""
    searchField.forceActiveFocus()
  }

  // The field stays open, so several currencies can be added in a row.
  function addCurrency(entry) {
    if (!ticker || !entry) return
    ticker.addCurrency(entry)
    currencyField.text = ""
    currencyCursor = 0
    Qt.callLater(function() { menu.showCurrency(entry.code) })
  }

  function moveCursor(delta) {
    if (!ticker || rows.length === 0) return
    var next = ticker.cursorIndex < 0 ? (delta > 0 ? 0 : rows.length - 1) : ticker.cursorIndex + delta
    ticker.cursorIndex = Math.max(0, Math.min(rows.length - 1, next))
    list.positionViewAtIndex(ticker.cursorIndex, ListView.Contain)
  }

  function activateCursor() {
    if (!ticker || ticker.cursorIndex < 0 || ticker.cursorIndex >= rows.length) return
    var row = rows[ticker.cursorIndex]
    if (searchMode) ticker.toggleResult(row)
  }

  function removeCursor() {
    if (!ticker || searchMode || ticker.cursorIndex < 0 || ticker.cursorIndex >= rows.length) return
    ticker.removeSymbol(rows[ticker.cursorIndex].symbol)
    ticker.cursorIndex = Math.min(ticker.cursorIndex, ticker.watchlist.length - 1)
  }

  Column {
    id: content
    width: parent.width
    spacing: Style.space(14)

    // Keep the field in step when the query is reset from the ticker side.
    Connections {
      target: menu.ticker
      function onQueryChanged() {
        if (menu.ticker && searchField.text !== menu.ticker.query) searchField.text = menu.ticker.query
      }
      function onSelectedCurrencyChanged() {
        if (menu.ticker) menu.showCurrency(menu.ticker.selectedCurrency)
      }
    }

    // ---------- Hero ----------
    Item {
      width: parent.width
      implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

      Text {
        id: heroIcon
        textFormat: Text.PlainText
        text: menu.glyphMarkets
        color: menu.fg
        font.family: menu.fontFamily
        font.pixelSize: Style.font.display
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Column {
        id: heroLabels
        anchors.left: heroIcon.right
        anchors.leftMargin: Style.space(14)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Text {
          text: "Markets"
          color: menu.fg
          font.family: menu.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
          width: parent.width
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          visible: text !== ""
          text: menu.ticker ? menu.ticker.feedStatus : ""
          color: menu.dim
          font.family: menu.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1.2
          width: parent.width
          elide: Text.ElideRight
        }
      }
    }

    // ---------- Currency ----------
    PanelSeparator { foreground: menu.fg }

    Column {
      width: parent.width
      spacing: Style.space(10)

      Item {
        width: parent.width
        implicitHeight: Math.max(currencyHeader.implicitHeight, addCurrencyButton.height)

        PanelSectionHeader {
          id: currencyHeader
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "CURRENCY"
          foreground: menu.fg
          fontFamily: menu.fontFamily
        }

        GlyphButton {
          id: addCurrencyButton
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          glyph: menu.addingCurrency ? menu.glyphRemove : menu.glyphAdd
          onActivated: menu.addingCurrency ? menu.stopAddingCurrency() : menu.startAddingCurrency()
        }
      }

      Item {
        id: currencyRow
        width: parent.width
        height: currencyFlick.height

        Flickable {
          id: currencyFlick
          width: parent.width
          height: currencyPills.height
          contentWidth: currencyPills.width
          contentHeight: currencyPills.height
          flickableDirection: Flickable.HorizontalFlick
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentWidth > width
          clip: true

          Row {
            id: currencyPills
            spacing: menu.currencySpacing

            Repeater {
              model: menu.ticker ? menu.ticker.currencies : []
              delegate: CurrencyPill {}
            }
          }

          // Most mice only scroll vertically; turn that into sideways.
          WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: function(event) {
              var delta = event.angleDelta.x !== 0 ? event.angleDelta.x : event.angleDelta.y
              var end = Math.max(0, currencyFlick.contentWidth - currencyFlick.width)
              currencyFlick.contentX = Math.max(0, Math.min(end, currencyFlick.contentX - delta / 2))
              event.accepted = true
            }
          }
        }

        // Fades on the side that has more currencies past it.
        Rectangle {
          anchors.left: parent.left
          width: Style.space(28)
          height: parent.height
          visible: !currencyFlick.atXBeginning
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Commons.Color.popups.background }
            GradientStop { position: 1; color: "transparent" }
          }
        }

        Rectangle {
          anchors.right: parent.right
          width: Style.space(28)
          height: parent.height
          visible: !currencyFlick.atXEnd
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 1; color: Commons.Color.popups.background }
          }
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(4)
        visible: menu.addingCurrency

        TextField {
          id: currencyField
          width: parent.width
          placeholderText: "Add a currency: code or name"
          foreground: menu.fg
          font.family: menu.fontFamily
          onTextChanged: menu.currencyCursor = 0

          Keys.onPressed: function(event) {
            var count = menu.currencySuggestions.length
            if (event.key === Qt.Key_Escape) {
              if (text !== "") text = ""
              else menu.stopAddingCurrency()
              event.accepted = true
            } else if (event.key === Qt.Key_Down) {
              menu.currencyCursor = Math.min(Math.max(0, count - 1), menu.currencyCursor + 1); event.accepted = true
            } else if (event.key === Qt.Key_Up) {
              menu.currencyCursor = Math.max(0, menu.currencyCursor - 1); event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              if (count > 0) menu.addCurrency(menu.currencySuggestions[Math.min(menu.currencyCursor, count - 1)])
              event.accepted = true
            }
          }
        }

        Repeater {
          model: menu.currencySuggestions
          delegate: CurrencySuggestion {}
        }

        Text {
          visible: currencyField.text.trim() !== "" && menu.currencySuggestions.length === 0
          text: menu.ticker && menu.ticker.knownCurrencies.length === 0 ? "Loading…" : "No matches"
          color: menu.dim
          font.family: menu.fontFamily
          font.pixelSize: Style.font.body
        }
      }
    }

    // ---------- Watchlist ----------
    PanelSeparator { foreground: menu.fg }

    Column {
      width: parent.width
      spacing: Style.space(10)

      PanelSectionHeader {
        text: "WATCHLIST"
        foreground: menu.fg
        fontFamily: menu.fontFamily
      }

      TextField {
        id: searchField
        width: parent.width
        placeholderText: "Search stocks, ETFs, crypto"
        foreground: menu.fg
        font.family: menu.fontFamily
        onTextChanged: if (menu.ticker) menu.ticker.query = text

        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (text !== "") text = ""
            else if (menu.ticker) menu.ticker.close()
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            menu.moveCursor(1); event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            menu.moveCursor(-1); event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            menu.activateCursor(); event.accepted = true
          } else if (event.key === Qt.Key_Delete && !menu.searchMode) {
            menu.removeCursor(); event.accepted = true
          }
        }
      }

      Item {
        width: parent.width
        height: menu.rowHeight * menu.visibleRows

        ListView {
          id: list
          anchors.fill: parent
          clip: true
          model: menu.rows
          spacing: 0
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height
          delegate: QuoteRow {}
        }

        Text {
          anchors.centerIn: parent
          visible: menu.message !== ""
          text: menu.message
          color: menu.dim
          font.family: menu.fontFamily
          font.pixelSize: Style.font.body
        }
      }
    }
  }

  component QuoteRow: CursorSurface {
    id: row
    required property var modelData
    required property int index

    readonly property bool watched: menu.searchMode ? (!!menu.ticker && menu.ticker.isWatched(modelData.symbol)) : true

    width: ListView.view ? ListView.view.width : 0
    height: menu.rowHeight
    hasCursor: !!menu.ticker && menu.ticker.cursorIndex === index
    foreground: menu.fg
    fill: Style.hoverFillFor(menu.fg, Commons.Color.accent)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: menu.searchMode ? Qt.PointingHandCursor : Qt.ArrowCursor
      onContainsMouseChanged: if (containsMouse && menu.ticker) menu.ticker.cursorIndex = row.index
      onClicked: if (menu.searchMode && menu.ticker) menu.ticker.toggleResult(row.modelData)
    }

    Row {
      id: rowInner
      anchors.fill: parent
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(4)
      spacing: Style.space(8)

      readonly property real actionWidth: Style.space(26)
      readonly property real metaWidth: meta.implicitWidth

      Text {
        id: primary
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, rowInner.width - rowInner.actionWidth - rowInner.metaWidth - rowInner.spacing * 3)
        text: menu.searchMode ? row.modelData.symbol : row.modelData.label
        color: menu.fg
        font.family: menu.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, rowInner.width - primary.width - rowInner.actionWidth - rowInner.metaWidth - rowInner.spacing * 3)
        text: menu.searchMode ? row.modelData.name : ""
        color: menu.dim
        font.family: menu.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        id: meta
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        text: (menu.searchMode
          ? [row.modelData.exchange, row.modelData.type].filter(function(part) { return !!part }).join(" · ")
          : row.modelData.symbol).toUpperCase()
        color: menu.dim
        font.family: menu.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.2
      }

      Rectangle {
        id: action
        width: rowInner.actionWidth
        height: rowInner.actionWidth
        anchors.verticalCenter: parent.verticalCenter
        radius: Style.cornerRadius
        color: actionArea.containsMouse ? Style.hoverFillFor(menu.fg, Commons.Color.accent) : "transparent"

        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: menu.searchMode ? (row.watched ? menu.glyphAdded : menu.glyphAdd) : menu.glyphRemove
          color: menu.searchMode && !row.watched ? menu.dim : menu.fg
          opacity: !menu.searchMode && !row.hasCursor && !actionArea.containsMouse ? 0.45 : 1
          font.family: menu.fontFamily
          font.pixelSize: Style.font.subtitle
        }

        MouseArea {
          id: actionArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onContainsMouseChanged: if (containsMouse && menu.ticker) menu.ticker.cursorIndex = row.index
          onClicked: {
            if (!menu.ticker) return
            if (menu.searchMode) menu.ticker.toggleResult(row.modelData)
            else menu.ticker.removeSymbol(row.modelData.symbol)
          }
        }
      }
    }
  }

  component GlyphButton: Rectangle {
    id: glyphButton
    property string glyph: ""
    signal activated()

    width: Style.space(26)
    height: Style.space(26)
    radius: Style.cornerRadius
    color: glyphArea.containsMouse ? Style.hoverFillFor(menu.fg, Commons.Color.accent) : "transparent"

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: glyphButton.glyph
      color: menu.fg
      font.family: menu.fontFamily
      font.pixelSize: Style.font.subtitle
    }

    MouseArea {
      id: glyphArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: glyphButton.activated()
    }
  }

  component CurrencyPill: Item {
    id: pill
    required property var modelData
    readonly property bool removable: !!menu.ticker && menu.ticker.currencies.length > 1

    width: menu.currencyCellWidth
    height: pillButton.implicitHeight

    HoverHandler { id: pillHover }

    Button {
      id: pillButton
      anchors.fill: parent
      text: pill.modelData.symbol && pill.modelData.symbol !== pill.modelData.code
        ? pill.modelData.symbol + "  " + pill.modelData.code : pill.modelData.code
      fontSize: Style.font.caption
      foreground: menu.fg
      fontFamily: menu.fontFamily
      horizontalPadding: Style.spacing.sm
      verticalPadding: Style.spacing.controlPaddingY
      bordered: true
      active: !!menu.ticker && menu.ticker.selectedCurrency === pill.modelData.code
      onClicked: if (menu.ticker) menu.ticker.chooseCurrency(pill.modelData.code)
    }

    // Remove, shown on hover. The last currency can't be removed.
    Text {
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      visible: pill.removable && (pillHover.hovered || removeArea.containsMouse)
      textFormat: Text.PlainText
      text: menu.glyphRemove
      color: removeArea.containsMouse ? menu.fg : menu.dim
      font.family: menu.fontFamily
      font.pixelSize: Style.font.caption

      MouseArea {
        id: removeArea
        anchors.fill: parent
        anchors.margins: -Style.space(4)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: if (menu.ticker) menu.ticker.removeCurrency(pill.modelData.code)
      }
    }
  }

  component CurrencySuggestion: CursorSurface {
    id: suggestion
    required property var modelData
    required property int index

    width: parent ? parent.width : 0
    height: menu.rowHeight
    hasCursor: menu.currencyCursor === index
    foreground: menu.fg
    fill: Style.hoverFillFor(menu.fg, Commons.Color.accent)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse) menu.currencyCursor = suggestion.index
      onClicked: menu.addCurrency(suggestion.modelData)
    }

    Row {
      anchors.left: parent.left
      anchors.right: symbolText.left
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(8)

      Text {
        id: codeText
        textFormat: Text.PlainText
        text: suggestion.modelData.code
        color: menu.fg
        font.family: menu.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }

      Text {
        width: Math.max(0, parent.width - codeText.width - parent.spacing)
        textFormat: Text.PlainText
        text: suggestion.modelData.name
        color: menu.dim
        font.family: menu.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }
    }

    Text {
      id: symbolText
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: suggestion.modelData.symbol
      color: menu.dim
      font.family: menu.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }
}
