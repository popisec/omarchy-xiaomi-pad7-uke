import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// UKE FORK de omarkyy.tablet (alertxsto, MIT, 69639aa). Sin acelerometro ni modo tableta:
// el giro lo hace /usr/local/bin/uke-rotate (monitor + tactil) y el teclado tiene distribucion ES/US.
Item {
  id: root
  property var shell: null
  property var manifest: null
  property bool busy: false
  property string error: ""
  property string layout: "es"          // es | us (persistido en ~/.local/state/uke-touch-mode/layout)
  property int rotationDeg: 0
  readonly property string rotateBin: "/usr/local/bin/uke-rotate"
  readonly property string stateFile: "$HOME/.local/state/uke-touch-mode/layout"
  property bool autoMode: true         // el teclado sale solo al enfocar un campo de texto y se va al soltarlo (como Android)
  readonly property string autoFile: "$HOME/.local/state/uke-touch-mode/auto"
  property real keyboardWidth: 1240
  property real keyboardHeight: 420

  function rotate(arg) {
    if (busy) return false
    error = ""
    busy = true
    rotator.command = [rotateBin, arg || "next"]
    rotator.running = true
    return true
  }
  function setLayout(name) {
    if (name !== "es" && name !== "us") return
    layout = name
    Quickshell.execDetached(["sh", "-c", "mkdir -p \"$(dirname " + stateFile + ")\" && echo " + name + " > " + stateFile])
  }
  function toggleLayout() { setLayout(layout === "es" ? "us" : "es") }
  function setAuto(on) {
    autoMode = on
    Quickshell.execDetached(["sh", "-c", "mkdir -p \"$(dirname " + autoFile + ")\" && echo " + (on ? "1" : "0") + " > " + autoFile])
  }
  function toggleKeyboard() { keyboardLoader.active = !keyboardLoader.active }
  function showKeyboard() { keyboardLoader.active = true }
  function hideKeyboard() { keyboardLoader.active = false }

  Process {
    id: rotator
    stdout: SplitParser { onRead: function(line) {
      var m = /(\d+) grados/.exec(line)
      if (m) root.rotationDeg = parseInt(m[1])
    } }
    stderr: SplitParser { onRead: function(line) { root.error = line } }
    onExited: function(code, status) {
      root.busy = false
      if (code !== 0 && !root.error) root.error = "uke-rotate fallo (codigo " + code + ")"
    }
  }
  Process {
    id: autoReader
    command: ["sh", "-c", "cat " + root.autoFile + " 2>/dev/null"]
    running: true
    stdout: SplitParser { onRead: function(line) { root.autoMode = line.trim() !== "0" } }
  }
  // Detector de campos de texto (input method v2): "active" = hay un campo enfocado, "inactive" = ya no.
  Process {
    id: ime
    command: ["sh", Qt.resolvedUrl("ime-backend.sh").toString().replace(/^file:\/\//, "")]
    running: root.autoMode
    stdout: SplitParser { onRead: function(line) {
      if (line === "active") { hideDelay.stop(); root.showKeyboard() }
      else if (line === "inactive") hideDelay.restart()
      else if (line === "unavailable") root.error = "Otro input method (squeekboard) ocupa el seat: auto-teclado desactivado"
    } }
    stderr: SplitParser { onRead: function(line) { root.error = line } }
    onExited: function(code, status) { if (root.autoMode && code !== 0 && !root.error) root.error = "ime-helper salio con codigo " + code }
  }
  // Respaldo: si se cierra la ultima ventana (o muere la app) sin que el compositor mande "inactive", el teclado
  // automatico se quedaba colgado. Sin ventana enfocada -> se oculta (solo en modo automatico).
  Connections {
    target: Hyprland
    function onActiveToplevelChanged() { if (root.autoMode && !Hyprland.activeToplevel) hideDelay.restart() }
  }
  Timer { id: hideDelay; interval: 250; onTriggered: root.hideKeyboard() }
  Process {
    id: layoutReader
    command: ["sh", "-c", "cat " + root.stateFile + " 2>/dev/null"]
    running: true
    stdout: SplitParser { onRead: function(line) {
      var v = line.trim()
      if (v === "es" || v === "us") root.layout = v
    } }
  }
  Process {
    id: statusReader
    command: [root.rotateBin, "status"]
    running: true
    stdout: SplitParser { onRead: function(line) {
      var m = /guardado: (\d+) grados/.exec(line)
      if (m) root.rotationDeg = parseInt(m[1])
    } }
  }
  Loader {
    id: keyboardLoader
    active: false
    source: "Keyboard.qml"
    onLoaded: {
      item.shell = {hide: function(id) { keyboardLoader.active = false }}
      item.manifest = root.manifest
      item.tabletService = root
      item.keyboardWidth = root.keyboardWidth
      item.keyboardHeight = root.keyboardHeight
      item.resized.connect(function(width, height) {
        root.keyboardWidth = width
        root.keyboardHeight = height
      })
      item.open("{}")
    }
  }
  IpcHandler {
    target: "omarkyy.tablet"
    function keyboard(): void { root.toggleKeyboard() }
    function show(): void { root.showKeyboard() }
    function hide(): void { root.hideKeyboard() }
    function rotate(): void { root.rotate("next") }
    function rotateTo(deg: string): void { root.rotate(deg) }
    function layout(): void { root.toggleLayout() }
    function auto(): void { root.setAuto(!root.autoMode) }
    function status(): string { return JSON.stringify({keyboard: keyboardLoader.active, auto: root.autoMode, layout: root.layout, rotation: root.rotationDeg, busy: root.busy, error: root.error}) }
  }
}
