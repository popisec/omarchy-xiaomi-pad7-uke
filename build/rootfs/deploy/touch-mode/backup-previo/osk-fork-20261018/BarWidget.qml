import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// UKE FORK: izquierdo = teclado, derecho = girar 90 grados (uke-rotate next), central = ES/US.
BarWidget {
  id: root
  moduleName: "omarkyy.tablet"
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: "Izq.: teclado · Der.: girar 90° · Medio: ES/US"
    // Draw the keyboard instead of relying on an optional icon-font glyph.
    iconComponent: Component {
      Item {
        Rectangle {
          anchors.centerIn: parent
          width: 20; height: 14
          radius: 2
          color: "transparent"
          border.width: 1
          border.color: button.foreground
          Grid {
            x: 3; y: 3
            columns: 5; spacing: 1
            Repeater {
              model: 10
              delegate: Rectangle { width: 2; height: 2; color: button.foreground }
            }
          }
          Rectangle { x: 5; y: 10; width: 10; height: 1; color: button.foreground }
        }
      }
    }
    onPressed: function(mouseButton) {
      var action = mouseButton === Qt.RightButton ? "rotate" : mouseButton === Qt.MiddleButton ? "layout" : "keyboard"
      Quickshell.execDetached(["omarchy-shell", "omarkyy.tablet", action])
    }
  }
}
