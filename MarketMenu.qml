import QtQuick
import qs.Ui
import qs.Commons
import qs.Commons as Commons

// Right-click menu of the market ticker, built from the same Omarchy panel
// parts as the stock bar popups: display currency, then the watchlist with a
// symbol search (type to search, ↑/↓ to pick, Enter to add or remove).
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

  focusTarget: searchField
  contentWidth: fittedContentWidth(Style.space(380))
  contentHeight: fittedContentHeight(content.implicitHeight, Style.space(720))

  onOpenChanged: if (open) searchField.text = ""

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

      PanelSectionHeader {
        text: "CURRENCY"
        foreground: menu.fg
        fontFamily: menu.fontFamily
      }

      Grid {
        id: currencyRow
        width: parent.width
        columns: 3
        spacing: Style.spacing.xs
        readonly property real cellWidth: (width - spacing * (columns - 1)) / columns

        Repeater {
          model: [
            { code: "USD", symbol: "$" },
            { code: "CAD", symbol: "C$" },
            { code: "TRY", symbol: "₺" }
          ]

          Button {
            required property var modelData
            width: currencyRow.cellWidth
            text: modelData.symbol + "  " + modelData.code
            fontSize: Style.font.caption
            foreground: menu.fg
            fontFamily: menu.fontFamily
            horizontalPadding: Style.spacing.sm
            verticalPadding: Style.spacing.controlPaddingY
            bordered: true
            active: !!menu.ticker && menu.ticker.selectedCurrency === modelData.code
            onClicked: if (menu.ticker) menu.ticker.chooseCurrency(modelData.code)
          }
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
}
