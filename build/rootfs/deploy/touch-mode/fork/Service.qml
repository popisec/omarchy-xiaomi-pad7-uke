import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

// UKE FORK de omarkyy.tablet (alertxsto, MIT, 69639aa) — REWORK 20-oct-2026 (build/gates/revision/OSK-REWORK-20261020.md).
// Un unico demonio persistente (osk-daemon: input method v2 + teclado virtual) que este servicio vigila:
// lo reinicia con espera creciente si muere, lo comprueba (ping) cada vez que se muestra el teclado (tras suspender,
// tras recargar el shell...) y encola las pulsaciones mientras reconecta. El giro lo hace /usr/local/bin/uke-rotate.
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
  // estado del demonio
  property bool daemonReady: false
  property bool imAvailable: false
  property bool imActive: false
  property string lastVia: ""          // ime | keys (como se entrego el ultimo texto)
  property int restarts: 0
  property bool pinned: false          // abierto a mano (gesto/boton): el auto-ocultar no lo cierra hasta que un campo lo reclame
  property var queue: []
  // ESCRITORIO-TACTIL 22-oct-2026: sugerencias/autocorreccion (en el demonio), clic sonoro, teclado precargado
  property var suggestions: []
  property string lastFix: ""
  property bool autocorrect: true      // ~/.local/state/uke-touch-mode/autocorrect
  property bool sound: false           // ~/.local/state/uke-touch-mode/sound (QtMultimedia solo se carga si esta activo)
  property bool kbVisible: false
  signal capsHint(bool on)
  readonly property string stateDir: "$HOME/.local/state/uke-touch-mode"
  function saveFlag(name, on) { Quickshell.execDetached(["sh", "-c", "mkdir -p " + stateDir + " && echo " + (on ? "1" : "0") + " > " + stateDir + "/" + name]) }
  function setAutocorrect(on) { autocorrect = on; saveFlag("autocorrect", on); send("C " + (on ? 1 : 0)) }
  function setSound(on) { sound = on; saveFlag("sound", on) }
  function pickSuggestion(i) { send("S " + i) }

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
  function toggleKeyboard() { if (kbVisible) hideKeyboard(); else { pinned = true; showKeyboard() } }
  // El teclado se crea una vez (precargado al arrancar) y despues solo se muestra/oculta: aparece sin instanciar ~70 teclas.
  function showKeyboard() {
    if (!kbVisible) { kbVisible = true; if (keyboardLoader.item) keyboardLoader.item.open("{}"); else keyboardLoader.active = true }
    ensureAlive()
  }
  function hideKeyboard() { kbVisible = false; pinned = false; lastFix = ""; if (keyboardLoader.item) keyboardLoader.item.close() }

  // ---- demonio ----
  function send(line) {
    if (daemonReady && daemon.running) { daemon.write(line + "\n"); return true }
    if (queue.length < 64) queue.push(line)
    return false
  }
  function ensureAlive() {
    if (!daemon.running) { restartTimer.stop(); daemon.running = true; return }
    if (daemonReady) { pongTimer.restart(); daemon.write("P\n") }
  }
  function restartDaemon() { daemonReady = false; if (daemon.running) daemon.running = false; else { restartTimer.stop(); daemon.running = true } }
  function onDaemonLine(line) {
    if (line === "ready") {
      daemonReady = true; restarts = 0; error = ""
      daemon.write("C " + (autocorrect ? 1 : 0) + "\n")
      var q = queue; queue = []
      for (var i = 0; i < q.length; i++) daemon.write(q[i] + "\n")
    } else if (line === "bound") { imAvailable = true }
    else if (line === "unavailable") { imAvailable = false }
    else if (line === "active") { imActive = true; pinned = false; hiddenByEmpty = false; hideDelay.stop(); if (autoMode && !noAutoApp()) showKeyboard() }
    else if (line === "inactive") { imActive = false; hiddenByEmpty = false; suggestions = []; if (autoMode && !pinned) hideDelay.restart() }
    else if (line === "pong") pongTimer.stop()
    else if (line === "sug" || line.indexOf("sug ") === 0) suggestions = line.length > 4 ? line.substring(4).split("|") : []
    else if (line === "caps 1" || line === "caps 0") capsHint(line === "caps 1")
    else if (line.indexOf("fix ") === 0) { lastFix = line.substring(4).replace(" ", " → "); fixClear.restart() }
    else if (line.indexOf("learn ") === 0) { lastFix = "palabra nueva: " + line.substring(6); fixClear.restart() }
    else if (line.indexOf("via ") === 0) lastVia = line.substring(4)
    else if (line.indexOf("err ") === 0) error = line.substring(4)
  }
  Process {
    id: daemon
    command: ["sh", decodeURIComponent(Qt.resolvedUrl("osk-backend.sh").toString().replace(/^file:\/\//, ""))]
    stdinEnabled: true
    stdout: SplitParser { onRead: function(line) { root.onDaemonLine(line) } }
    stderr: SplitParser { onRead: function(line) { root.error = line } }
    onExited: function(code, status) {
      root.daemonReady = false
      root.imActive = false
      pongTimer.stop()
      restartTimer.interval = Math.min(8000, 400 * Math.pow(2, root.restarts))
      root.restarts++
      restartTimer.start()
    }
  }
  Timer { id: restartTimer; onTriggered: daemon.running = true }
  Timer { id: pongTimer; interval: 900; onTriggered: root.restartDaemon() }
  Component.onCompleted: daemon.running = true

  // ---- dictado (22-oct-2026, build/rootfs/deploy/dictado): 1er toque graba, 2º toque transcribe OFFLINE e inserta ----
  // uke-dictar run: graba del micro hasta leer una linea por stdin ("stop" o "cancel"), transcribe y saca "texto <...>".
  readonly property string dictBin: "/usr/local/bin/uke-dictar"
  property string dictState: ""        // "" | rec | busy
  property string dictMsg: ""
  function toggleDictation() {
    if (dictState === "") {
      dictMsg = ""; dictState = "rec"; dictator.running = true; ensureAlive()
    } else if (dictState === "rec") {
      dictState = "busy"; dictator.write("stop\n")
    }
  }
  function cancelDictation() { if (dictState === "rec") { dictState = "busy"; dictator.write("cancel\n") } }
  Process {
    id: dictator
    command: [root.dictBin, "run"]
    stdinEnabled: true
    stdout: SplitParser { onRead: function(line) {
      if (line.indexOf("texto ") === 0) { var t = line.substring(6); if (t !== "") root.send("T " + t) }
      else if (line.indexOf("info ") === 0) root.dictMsg = line.substring(5)
      else if (line.indexOf("err ") === 0) root.dictMsg = line.substring(4)
    } }
    onExited: function(code, status) {
      root.dictState = ""
      if (code !== 0 && root.dictMsg === "") root.dictMsg = "dictado fallo (codigo " + code + ")"
    }
  }
  Timer { interval: 120000; running: root.dictState === "rec"; onTriggered: root.toggleDictation() }   // tope de grabacion

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
  // Respaldo: si se cierra la ultima ventana (o muere la app) sin que el compositor mande "inactive", el teclado
  // automatico se quedaba colgado. Sin ventana enfocada -> se oculta (solo en modo automatico y no abierto a mano).
  Connections {
    target: Hyprland
    function onActiveToplevelChanged() { if (root.autoMode && !root.pinned && !Hyprland.activeToplevel) hideDelay.restart() }
    // ESCRITORIO-TACTIL 22-oct-2026 (medido): al pasar a un escritorio VACIO Hyprland 0.56 no manda deactivate (el foco de
    // teclado se queda en la superficie oculta) y el teclado seguia visible. Ventana activa vacia -> ocultar; al volver a una
    // ventana con el campo aun activo (el demonio no repite "active") -> mostrar otra vez.
    function onRawEvent(event) {
      if (event.name !== "activewindowv2" || !root.autoMode || root.pinned) return
      if (event.data === "" || event.data === ",") { if (root.kbVisible) { root.hiddenByEmpty = true; hideDelay.restart() } }
      else if (root.hiddenByEmpty) { root.hiddenByEmpty = false; if (root.imActive && !root.noAutoApp()) { hideDelay.stop(); root.showKeyboard() } }
    }
  }
  property bool hiddenByEmpty: false
  // Apps que activan text-input sin un campo de verdad (GTK4 con set_key_capture_widget para «escribir para buscar»:
  // Komikku y otras de GNOME; medido por resto-apps el 22-oct): en ellas el teclado no sale solo, solo a mano.
  // Lista en ~/.local/state/uke-touch-mode/no-auto (un app id por linea; se crea con Komikku).
  property var noAutoIds: []
  function activeAppId() {
    try { var t = ToplevelManager.activeToplevel; return t ? String(t.appId || "") : "" } catch (e) { return "" }
  }
  function noAutoApp() { var id = activeAppId(); return id !== "" && noAutoIds.indexOf(id) !== -1 }
  Process {
    id: noAutoReader
    command: ["sh", "-c", "f=" + root.stateDir + "/no-auto; [ -f $f ] || { mkdir -p " + root.stateDir + " && printf '%s\\n' '# apps sin teclado automatico (un app id por linea)' info.febvre.Komikku > $f; }; grep -v '^#' $f"]
    running: true
    stdout: SplitParser { onRead: function(line) { var v = line.trim(); if (v) { var a = root.noAutoIds.slice(); a.push(v); root.noAutoIds = a } } }
  }
  Timer { id: fixClear; interval: 4000; onTriggered: root.lastFix = "" }
  Timer { id: hideDelay; interval: 250; onTriggered: root.hideKeyboard() }
  Process {
    id: flagsReader
    command: ["sh", "-c", "cd " + root.stateDir + " 2>/dev/null && for f in autocorrect sound; do [ -f $f ] && echo $f=$(cat $f); done"]
    running: true
    stdout: SplitParser { onRead: function(line) {
      var kv = line.trim().split("=")
      if (kv[0] === "autocorrect") { root.autocorrect = kv[1] !== "0"; root.send("C " + (root.autocorrect ? 1 : 0)) }
      else if (kv[0] === "sound") root.sound = kv[1] === "1"
    } }
  }
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
  Timer { interval: 1500; running: true; onTriggered: keyboardLoader.active = true }   // precarga, tras arrancar el shell
  Loader {
    id: keyboardLoader
    active: false
    source: "Keyboard.qml"
    onLoaded: {
      item.shell = {hide: function(id) { root.hideKeyboard() }}
      item.manifest = root.manifest
      item.tabletService = root
      item.keyboardWidth = root.keyboardWidth
      item.keyboardHeight = root.keyboardHeight
      item.resized.connect(function(width, height) {
        root.keyboardWidth = width
        root.keyboardHeight = height
      })
      if (root.kbVisible) item.open("{}")
    }
  }
  IpcHandler {
    target: "omarkyy.tablet"
    function keyboard(): void { root.toggleKeyboard() }
    function show(): void { root.pinned = true; root.showKeyboard() }
    function hide(): void { root.hideKeyboard() }
    function rotate(): void { root.rotate("next") }
    function rotateTo(deg: string): void { root.rotate(deg) }
    function layout(): void { root.toggleLayout() }
    function auto(): void { root.setAuto(!root.autoMode) }
    function restart(): void { root.restartDaemon() }
    function inputmode(m: string): void { root.send("M " + m) }
    function type(text: string): void { root.send("T " + text) }
    function key(code: string, bits: string): void { root.send("K " + code + " " + bits) }
    function dictate(): void { root.toggleDictation() }
    function dictateCancel(): void { root.cancelDictation() }
    function pick(i: string): void { root.pickSuggestion(parseInt(i)) }
    function autocorrectToggle(): void { root.setAutocorrect(!root.autocorrect) }
    function soundToggle(): void { root.setSound(!root.sound) }
    function status(): string { return JSON.stringify({keyboard: root.kbVisible, app: root.activeAppId(), noAuto: root.noAutoIds, loaded: !!keyboardLoader.item, sugs: root.suggestions, autocorrect: root.autocorrect, sound: root.sound, fix: root.lastFix, auto: root.autoMode, layout: root.layout, rotation: root.rotationDeg, busy: root.busy, error: root.error, daemon: root.daemonReady, im: root.imAvailable, imActive: root.imActive, via: root.lastVia, restarts: root.restarts, dict: root.dictState, dictMsg: root.dictMsg}) }
  }
}
