import QtQuick
import qs.Ui

// Boton de la barra: alterna el lanzador (mismo icono que uke.apps).
BarWidget {
  id: root
  moduleName: "uke.launcher"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰀻"   // nf-md-apps (U+F003B)
    horizontalMargin: 9
    onPressed: function(mouseButton) {
      if (!root.bar) return
      if (mouseButton !== Qt.LeftButton) return   // nunca clic derecho
      root.bar.run("omarchy-shell -q uke.launcher toggle")
    }
  }
}
