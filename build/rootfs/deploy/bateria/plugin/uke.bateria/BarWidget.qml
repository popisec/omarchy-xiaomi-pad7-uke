import QtQuick
import Quickshell.Io
import qs.Ui

// % exacto (charge_counter/charge_full), W (media movil de 5 lecturas) y perfil.
// Clic izquierdo: siguiente perfil (Ahorro > Equilibrado > Rendimiento). Clic derecho: refresca.
BarWidget {
  id: root
  moduleName: "uke.bateria"

  property string pct: ""
  property real watts: 0
  property real wAvg: 0
  property var wHist: []
  property int estS: -1
  property string estado: ""
  property string perfil: "balanced"
  property bool ok: true
  readonly property var icons: ({ "power-saver": "󰌪", "balanced": "󰊚", "performance": "󰓅" })
  readonly property var names: ({ "power-saver": "Ahorro", "balanced": "Equilibrado", "performance": "Rendimiento" })

  function fmtTime(s) {
    if (s < 0) return "--"
    var h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60)
    return h > 0 ? h + " h " + m + " min" : m + " min"
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    horizontalMargin: 7
    text: root.pct === "" ? "" :
      (root.icons[root.perfil] || "󰊚") + " " + root.pct + "%" +
      (root.estado === "Charging" ? " 󱐋" : "") + " " + Math.abs(root.wAvg).toFixed(1) + "W"
    tooltipText: root.pct === "" ? "" :
      root.pct + "% exacto" + (root.ok ? "" : " (el firmware no concuerda: dato dudoso)") + "\n" +
      root.estado + " · " + Math.abs(root.wAvg).toFixed(2) + " W" +
      (root.estS >= 0 ? "\n" + (root.estado === "Charging" ? "llena en " : "quedan ~") + root.fmtTime(root.estS) : "") +
      "\nPerfil: " + (root.names[root.perfil] || root.perfil) + "  (clic = siguiente)"
    onPressed: function(b) {
      if (!root.bar) return
      if (b === Qt.RightButton) { poll.running = true; return }
      root.bar.run("/usr/local/bin/uke-perfil cycle")
      refreshSoon.restart()
    }
  }

  Process {
    id: poll
    command: ["/usr/local/bin/uke-bateria-lectura", "--short"]
    stdout: SplitParser {
      onRead: function(line) {
        var f = line.split("|")
        if (f.length < 6) return
        root.pct = parseFloat(f[0]).toFixed(1)
        var w = f[1] === "" ? 0 : parseFloat(f[1])
        var h = root.wHist.concat([w]); if (h.length > 5) h.shift()
        root.wHist = h; root.wAvg = h.reduce(function(a, b) { return a + b }, 0) / h.length
        root.estS = f[2] === "" ? -1 : parseInt(f[2])
        root.estado = f[3]; root.perfil = f[4] || "balanced"; root.ok = f[5] === "1"
      }
    }
  }
  Timer { interval: 10000; running: true; repeat: true; triggeredOnStart: true; onTriggered: if (!poll.running) poll.running = true }
  Timer { id: refreshSoon; interval: 2500; onTriggered: poll.running = true }
}
