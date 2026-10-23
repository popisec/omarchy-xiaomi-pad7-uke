import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

// Ventana del lanzador: una capa overlay a pantalla completa. Se crea al abrir
// (LazyLoader en Service.qml) y se destruye al cerrar.
PanelWindow {
  id: win

  required property var service

  // ---- ventana ----
  screen: service.targetScreen
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "uke-launcher"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand   // el OSK sale al tocar el buscador

  // ---- tema ----
  readonly property color bgColor: Qt.rgba(Commons.Color.menu.background.r, Commons.Color.menu.background.g, Commons.Color.menu.background.b, 0.97)
  readonly property color fg: Commons.Color.menu.text
  readonly property color accentColor: Color.accent
  readonly property string fam: Style.font.menuFamily

  // ---- medidas tactiles ----
  readonly property int margin: 40
  readonly property int barH: 68                    // buscador y boton cerrar
  readonly property int minCell: 160
  readonly property int cols: Math.max(2, Math.floor((width - margin * 2) / minCell))
  readonly property int cellW: Math.floor((width - margin * 2) / cols)
  readonly property int cellH: 184
  readonly property int iconSize: 92
  readonly property int nameSize: Math.max(15, Style.font.heading)

  // ---- datos ----
  property var index: []        // [{entry, name, key, search}] ordenado por nombre
  property var apps: []         // filtrado actual (lo que ve la rejilla)
  property string query: ""
  property var hidden: ({})     // ids ocultos (launcher.hides + OnlyShowIn/NotShowIn)
  property var pendingHidden: ({})

  function norm(s) {
    return String(s || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase()
  }
  function stripDesktop(id) {
    var v = String(id || "").trim()
    return v.slice(-8) === ".desktop" ? v.slice(0, -8) : v
  }

  // Indice de todas las apps visibles, ordenado por nombre (con locale).
  function rebuildIndex() {
    var vals = DesktopEntries.applications.values || []
    var rows = []
    for (var i = 0; i < vals.length; i++) {
      var e = vals[i]
      if (!e || e.noDisplay || !e.name) continue
      if (win.hidden[String(e.id)] === true) continue
      var kw = ""
      try { kw = e.keywords ? e.keywords.join(" ") : "" } catch (x) {}
      rows.push({
        entry: e,
        name: String(e.name),
        key: String(e.name).toLowerCase(),
        nname: norm(e.name),
        search: norm(e.name + " " + (e.genericName || "") + " " + kw)
      })
    }
    rows.sort(function(a, b) { return a.key.localeCompare(b.key) })
    win.index = rows
    win.refilter()
  }

  // Todas las palabras de la busqueda deben aparecer; primero las que empiezan por ella.
  function refilter() {
    var terms = norm(win.query).trim().split(/\s+/).filter(function(t) { return t.length > 0 })
    if (terms.length === 0) { win.apps = win.index; return }
    var out = []
    for (var i = 0; i < win.index.length; i++) {
      var r = win.index[i]
      var ok = true
      for (var j = 0; j < terms.length && ok; j++) if (r.search.indexOf(terms[j]) < 0) ok = false
      if (ok) out.push({ r: r, rank: r.nname.indexOf(terms[0]) === 0 ? 0 : 1 })
    }
    out.sort(function(a, b) { return a.rank - b.rank })   // sort estable: conserva el orden por nombre
    win.apps = out.map(function(o) { return o.r })
    grid.positionViewAtBeginning()
  }

  function iconSource(icon) {
    var v = String(icon || "")
    if (v.charAt(0) === "/") return Util.fileUrl(v)
    if (v.indexOf("file://") === 0 || v.indexOf("image://") === 0) return v
    var found = v && service ? service.iconIndex[v] : ""
    if (found) return Util.fileUrl(found)
    var p = v ? Quickshell.iconPath(v, true) : ""
    if (p.length > 0) return p
    var fb = service ? (service.iconIndex["application-x-executable"] || service.iconIndex["org.gnome.TextEditor"] || "") : ""
    return fb ? Util.fileUrl(fb) : ""
  }

  function closeLauncher() { win.service.close() }

  Component.onCompleted: win.rebuildIndex()

  // Cambios en las apps instaladas mientras esta abierto.
  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() { win.rebuildIndex() }
  }

  // ---- apps ocultas: misma fuente que AppLibrary (solo al abrir, sin vigilar) ----
  FileView {
    path: Quickshell.env("OMARCHY_PATH") + "/default/omarchy/launcher.hides"
    printErrors: false
    onLoaded: {
      var next = {}
      var lines = String(text()).split(/\n/)
      for (var i = 0; i < lines.length; i++) {
        var id = win.stripDesktop(lines[i])
        if (id) next[id] = true
      }
      for (var k in win.hidden) next[k] = true
      win.hidden = next
      win.rebuildIndex()
    }
  }
  Process {
    command: ["bash", Quickshell.env("OMARCHY_PATH") + "/shell/services/hidden-entries.sh",
      [Quickshell.env("XDG_CURRENT_DESKTOP"), Quickshell.env("XDG_SESSION_DESKTOP"), Quickshell.env("DESKTOP_SESSION")]
        .filter(function(v) { return String(v || "").length > 0 }).join(":")]
    running: true
    stdout: SplitParser {
      onRead: function(line) {
        var id = win.stripDesktop(line)
        if (id) win.pendingHidden[id] = true
      }
    }
    onExited: {
      var next = {}
      for (var k in win.hidden) next[k] = true
      for (var j in win.pendingHidden) next[j] = true
      win.hidden = next
      win.rebuildIndex()
    }
  }

  // ---- contenido ----
  FocusScope {
    id: content
    anchors.fill: parent
    focus: true
    opacity: 0
    Component.onCompleted: opacity = 1
    Behavior on opacity { NumberAnimation { duration: 120 } }

    Keys.onEscapePressed: win.closeLauncher()

    Rectangle {
      id: bg
      anchors.fill: parent
      color: win.bgColor
      // toque en el fondo (fuera de la rejilla) -> cerrar
      TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: win.closeLauncher()
      }
    }

    // --- cabecera: buscador + cerrar ---
    Item {
      id: topBar
      x: win.margin; y: 28
      width: parent.width - win.margin * 2
      height: win.barH

      Rectangle {
        id: searchBox
        anchors { left: parent.left; right: closeBtn.left; rightMargin: 20; verticalCenter: parent.verticalCenter }
        height: win.barH
        radius: height / 2
        color: Util.alpha(win.fg, 0.08)
        border.width: search.activeFocus ? 2 : 1
        border.color: search.activeFocus ? win.accentColor : Util.alpha(win.fg, 0.25)

        Text {
          id: lens
          textFormat: Text.PlainText
          anchors { left: parent.left; leftMargin: 24; verticalCenter: parent.verticalCenter }
          text: "󰍉"
          color: win.fg
          opacity: 0.7
          font.family: win.fam
          font.pixelSize: 28
        }

        TextInput {
          id: search
          anchors { left: lens.right; leftMargin: 14; right: clearBtn.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
          color: win.fg
          selectionColor: Util.alpha(win.accentColor, 0.45)
          selectedTextColor: win.fg
          font.family: win.fam
          font.pixelSize: 26
          clip: true
          focus: false                       // no autoenfocar: evita que salga el OSK
          selectByMouse: false
          inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
          onTextChanged: { win.query = text; win.refilter() }
          onAccepted: {
            if (win.apps.length > 0) win.service.launch(win.apps[0].entry)
          }
          Keys.onEscapePressed: {
            if (text !== "") text = ""
            else win.closeLauncher()
          }

          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            visible: search.text === "" && !search.preeditText
            text: "Buscar aplicaciones"
            color: win.fg
            opacity: 0.5
            font: search.font
          }
        }

        // toque en cualquier parte del buscador -> foco (y teclado en pantalla)
        TapHandler {
          acceptedButtons: Qt.LeftButton
          onTapped: { search.forceActiveFocus(); Qt.inputMethod.show() }
        }

        // borrar texto (zona tactil grande)
        Item {
          id: clearBtn
          anchors { right: parent.right; verticalCenter: parent.verticalCenter }
          width: win.barH; height: win.barH
          visible: search.text !== ""
          Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: "󰅙"
            color: win.fg
            opacity: 0.7
            font.family: win.fam
            font.pixelSize: 28
          }
          TapHandler {
            acceptedButtons: Qt.LeftButton
            onTapped: { search.text = ""; search.forceActiveFocus() }
          }
        }
      }

      // cerrar (grande, arriba a la derecha)
      Rectangle {
        id: closeBtn
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        width: win.barH; height: win.barH
        radius: width / 2
        color: closeTap.pressed ? Util.alpha(win.accentColor, 0.35) : Util.alpha(win.fg, 0.12)
        Text {
          textFormat: Text.PlainText
          anchors.centerIn: parent
          text: "󰅖"
          color: win.fg
          font.family: win.fam
          font.pixelSize: 34
        }
        TapHandler {
          id: closeTap
          acceptedButtons: Qt.LeftButton
          onTapped: win.closeLauncher()
        }
      }
    }

    // --- rejilla de apps ---
    GridView {
      id: grid
      x: win.margin
      y: topBar.y + topBar.height + 24
      width: parent.width - win.margin * 2
      height: parent.height - y - 24
      clip: true
      cellWidth: win.cellW
      cellHeight: win.cellH
      model: win.apps
      cacheBuffer: win.cellH * 2
      reuseItems: true
      boundsBehavior: Flickable.DragOverBounds
      flickDeceleration: 2500

      // fondo dentro del contenido: un toque en un hueco vacio de la rejilla cierra
      Item {
        parent: grid.contentItem
        z: -1
        width: grid.contentWidth
        height: Math.max(grid.contentHeight, grid.height)
        TapHandler {
          acceptedButtons: Qt.LeftButton
          onTapped: win.closeLauncher()
        }
      }

      // Cerrar con un gesto hacia abajo estando arriba del todo
      onDraggingChanged: {
        if (!dragging && contentY - originY < -110) win.closeLauncher()
      }
      onFlickStarted: {
        if (verticalVelocity < -900 && contentY - originY <= 1) win.closeLauncher()
      }

      delegate: Item {
        id: cell
        required property var modelData
        width: win.cellW
        height: win.cellH

        Rectangle {
          id: tile
          anchors { fill: parent; margins: 6 }
          radius: 18
          color: tap.pressed ? Util.alpha(win.accentColor, 0.28) : "transparent"
          scale: tap.pressed ? 0.96 : 1.0

          Image {
            id: icon
            anchors { top: parent.top; topMargin: 14; horizontalCenter: parent.horizontalCenter }
            width: win.iconSize; height: win.iconSize
            sourceSize: Qt.size(win.iconSize, win.iconSize)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            source: win.iconSource(cell.modelData.entry.icon)
          }

          Text {
            textFormat: Text.PlainText
            anchors {
              top: icon.bottom; topMargin: 10
              left: parent.left; right: parent.right
              leftMargin: 6; rightMargin: 6
            }
            text: cell.modelData.name
            color: win.fg
            font.family: win.fam
            font.pixelSize: win.nameSize
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
          }

          TapHandler {
            id: tap
            acceptedButtons: Qt.LeftButton
            onTapped: win.service.launch(cell.modelData.entry)
          }
        }
      }
    }

    // sin resultados
    Text {
      textFormat: Text.PlainText
      anchors.centerIn: grid
      visible: win.apps.length === 0
      text: win.query !== "" ? "Sin resultados para “" + win.query + "”" : "No hay aplicaciones"
      color: win.fg
      opacity: 0.6
      font.family: win.fam
      font.pixelSize: 24
    }
  }
}
