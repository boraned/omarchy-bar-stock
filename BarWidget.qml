import QtQuick
import qs.Commons
import qs.Ui

// The ticker as a widget in a section of the Omarchy bar.
BarWidget {
  id: root
  moduleName: "omarchy-bar-stock"

  // Lets `omarchy-shell shell summon|hide omarchy-bar-stock` open and close
  // the menu: the bar looks for these on the widget root.
  readonly property bool opened: ticker.opened
  function open() { ticker.open() }
  function close() { ticker.close() }

  implicitWidth: Math.max(160, Number(setting("width", 480)) || 480)
  implicitHeight: barSize

  MarketTicker {
    id: ticker
    anchors.fill: parent
    anchors.topMargin: Math.round(root.barSize * 0.15)
    anchors.bottomMargin: Math.round(root.barSize * 0.15)
    bar: root.bar
    fontFamily: root.bar && root.bar.fontFamily ? root.bar.fontFamily : Style.font.family
  }
}
