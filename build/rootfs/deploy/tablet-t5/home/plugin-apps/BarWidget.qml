import QtQuick
import qs.Ui

BarWidget {
  id: root
  moduleName: "uke.apps"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰀻"   // nf-md-apps (U+F003B)
    horizontalMargin: 9
    onPressed: function(button) {
      if (!root.bar) return
      root.bar.run("/usr/local/bin/uke-drawer-toggle")
    }
  }
}
