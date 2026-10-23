import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons

// Servicio del lanzador tactil. Solo guarda el estado abierto/cerrado y el IPC;
// la ventana y la rejilla (Launcher.qml) existen unicamente mientras esta abierto.
Item {
  id: root
  property var shell: null
  property var manifest: null

  property bool opened: false
  property var targetScreen: null     // monitor con foco al abrir

  // Monitor enfocado de Hyprland -> QuickshellScreen (null = el compositor decide).
  function focusedScreen() {
    var name = ""
    try { name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "" } catch (e) {}
    var list = Quickshell.screens
    for (var i = 0; i < list.length; i++) if (list[i].name === name) return list[i]
    return list.length > 0 ? list[0] : null
  }

  // Indice de iconos "nombre -> ruta" como AppLibrary de Omarchy (Quickshell.iconPath devuelve vacio en este shell):
  // se escanea una vez, al primer open, y se reutiliza. SVG antes que PNG (se queda el primero por nombre).
  property var iconIndex: ({})
  property var pendingIndex: ({})
  property bool iconsScanned: false
  Process {
    id: iconScan
    command: ["bash", "-c", 'dirs="$HOME/.icons $HOME/.local/share/icons"; IFS=":"; for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do dirs="$dirs $d/icons"; done; unset IFS; for ext in svg png; do for base in $dirs; do [[ -d $base ]] && find "$base" \\( -path "*/apps/*" -o -path "*/devices/*" \\) -name "*.$ext" 2>/dev/null; done; find /usr/share/pixmaps -maxdepth 1 -name "*.$ext" 2>/dev/null; done']
    stdout: SplitParser { onRead: function(line) {
      var v = String(line).trim(); var f = v.slice(v.lastIndexOf("/") + 1); var dot = f.lastIndexOf(".")
      var n = dot > 0 ? f.slice(0, dot) : f
      if (n && root.pendingIndex[n] === undefined) root.pendingIndex[n] = v
    } }
    onExited: { root.iconIndex = root.pendingIndex; root.pendingIndex = ({}); root.iconsScanned = true }
  }
  function open() {
    if (opened) return
    if (!iconsScanned && !iconScan.running) iconScan.running = true
    targetScreen = focusedScreen()
    opened = true
  }
  function close() { opened = false }
  function toggle() { if (opened) close(); else open() }

  // Mismo mecanismo que AppLibrary.launch de Omarchy (scope bajo app-graphical.slice;
  // gtk-launch resuelve el id, con sufijo .desktop). Util.execArgv no pasa por shell.
  function launch(entry) {
    if (!entry || !entry.id) return
    Util.execArgv(["uwsm-app", "--", "gtk-launch", String(entry.id) + ".desktop"])
    close()
  }

  LazyLoader {
    active: root.opened
    Launcher { service: root }
  }

  IpcHandler {
    target: "uke.launcher"
    function toggle(): void { root.toggle() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function status(): string { return (root.opened ? "open" : "closed") + " iconos=" + Object.keys(root.iconIndex).length }
  }
}
