import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import qs.Commons

Item {
  id: root
  property var shell: null
  property var manifest: null
  property var tabletService: null
  property bool opened: false
  property bool ctrlActive: false
  property bool shiftActive: false
  property bool altActive: false
  property bool superActive: false
  property bool capsActive: false
  property bool altgrActive: false
  // UKE FORK: distribucion (es|us) que manda Service.qml; pulsacion larga de vocal = acento agudo.
  readonly property string layoutName: tabletService ? tabletService.layout : "es"
  property var accentKey: null
  property bool accentFired: false
  property string inputError: ""
  property bool inputReady: false
  property var repeatKey: null
  property var repeatHandler: null
  property var targetScreen: Quickshell.screens[0]
  property real positionX: 0
  property real positionY: 0
  property real keyboardWidth: 1240
  property real keyboardHeight: 420
  readonly property real minimumWidth: Math.min(640, targetScreen.width - 24)
  readonly property real minimumHeight: Math.min(240, targetScreen.height - 72)
  readonly property real keyGap: Math.max(3, Math.min(6, keyboardWidth * 0.005))
  signal resized(real width, real height)
  readonly property color background: Color.popups.background
  readonly property color foreground: Color.popups.text
  readonly property color keyBackground: Qt.tint(background, Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12))

  // l: label, t: letter, k: base US keysym, s: shifted label, m: modifier, w: width.
  // Modifiers latch in the UI; the native backend applies them to each complete
  // stroke, then releases them. The compositor receives real evdev keycodes.
  readonly property var rows: layoutName === "es" ? esRows : usRows
  // l: etiqueta; t: letra; k: nombre de tecla; c: codigo evdev explicito; sl/al: etiqueta con Shift/AltGr; acc: vocal acentuable (pulsacion larga).
  // Posiciones fisicas ISO-ES (xkb "es"): 41 º/ª, 12 ' ?, 13 ¡ ¿, 26 ` ^ (muerta), 27 + *, 39 ñ, 40 ´ ¨ (muerta), 43 ç, 86 < >.
  readonly property var esRows: [
    [ {l:"Esc",k:"Escape"}, {l:"º",c:41,sl:"ª",al:"\\"},
      {l:"1",k:"1",sl:"!",al:"|"}, {l:"2",k:"2",sl:"\"",al:"@"}, {l:"3",k:"3",sl:"·",al:"#"},
      {l:"4",k:"4",sl:"$",al:"~"}, {l:"5",k:"5",sl:"%",al:"€"}, {l:"6",k:"6",sl:"&",al:"¬"},
      {l:"7",k:"7",sl:"/"}, {l:"8",k:"8",sl:"("}, {l:"9",k:"9",sl:")"},
      {l:"0",k:"0",sl:"="}, {l:"'",c:12,sl:"?"},
      {l:"¡",c:13,sl:"¿"}, {l:"Backspace",k:"BackSpace",w:1.6} ],
    [ {l:"Tab",k:"Tab",w:1.4}, {t:"q"}, {t:"w"}, {t:"e",acc:true,al:"€"}, {t:"r"}, {t:"t"},
      {t:"y"}, {t:"u",acc:true}, {t:"i",acc:true}, {t:"o",acc:true}, {t:"p"},
      {l:"`",c:26,sl:"^",al:"["}, {l:"+",c:27,sl:"*",al:"]"},
      {l:"Del",k:"Delete",w:1.4} ],
    [ {l:"Caps",m:"caps",w:1.5}, {t:"a",acc:true}, {t:"s"}, {t:"d"}, {t:"f"}, {t:"g"},
      {t:"h"}, {t:"j"}, {t:"k"}, {t:"l"}, {t:"ñ",c:39},
      {l:"´",c:40,sl:"¨",al:"{"}, {t:"ç",c:43,al:"}"}, {l:"Enter",k:"Return",w:1.8} ],
    [ {l:"Shift",m:"shift",w:1.6}, {l:"<",c:86,sl:">"}, {t:"z"}, {t:"x"}, {t:"c"}, {t:"v"}, {t:"b"},
      {t:"n"}, {t:"m"}, {l:",",k:"comma",sl:";"}, {l:".",k:"period",sl:":"},
      {l:"-",c:53,sl:"_"}, {l:"Shift",m:"shift",w:2.0} ],
    [ {l:"Ctrl",m:"ctrl",w:1.3}, {l:"Super",m:"super",w:1.4}, {l:"Alt",m:"alt",w:1.1},
      {l:"Space",k:"space",w:4}, {l:"AltGr",m:"altgr",w:1.3}, {l:"Home",k:"Home"}, {l:"End",k:"End"},
      {l:"←",k:"Left"}, {l:"↓",k:"Down"}, {l:"↑",k:"Up"}, {l:"→",k:"Right"} ]
  ]
  readonly property var usRows: [
    [ {l:"Esc",k:"Escape"}, {l:"`",k:"grave",s:"asciitilde"},
      {l:"1",k:"1",s:"exclam"}, {l:"2",k:"2",s:"at"}, {l:"3",k:"3",s:"numbersign"},
      {l:"4",k:"4",s:"dollar"}, {l:"5",k:"5",s:"percent"}, {l:"6",k:"6",s:"asciicircum"},
      {l:"7",k:"7",s:"ampersand"}, {l:"8",k:"8",s:"asterisk"}, {l:"9",k:"9",s:"parenleft"},
      {l:"0",k:"0",s:"parenright"}, {l:"-",k:"minus",s:"underscore"},
      {l:"=",k:"equal",s:"plus"}, {l:"Backspace",k:"BackSpace",w:1.6} ],
    [ {l:"Tab",k:"Tab",w:1.5}, {t:"q"}, {t:"w"}, {t:"e"}, {t:"r"}, {t:"t"},
      {t:"y"}, {t:"u"}, {t:"i"}, {t:"o"}, {t:"p"},
      {l:"[",k:"bracketleft",s:"braceleft"}, {l:"]",k:"bracketright",s:"braceright"},
      {l:"\\",k:"backslash",s:"bar",w:1.5} ],
    [ {l:"Caps",m:"caps",w:1.7}, {t:"a"}, {t:"s"}, {t:"d"}, {t:"f"}, {t:"g"},
      {t:"h"}, {t:"j"}, {t:"k"}, {t:"l"}, {l:";",k:"semicolon",s:"colon"},
      {l:"'",k:"apostrophe",s:"quotedbl"}, {l:"Enter",k:"Return",w:2.3} ],
    [ {l:"Shift",m:"shift",w:2.1}, {t:"z"}, {t:"x"}, {t:"c"}, {t:"v"}, {t:"b"},
      {t:"n"}, {t:"m"}, {l:",",k:"comma",s:"less"}, {l:".",k:"period",s:"greater"},
      {l:"/",k:"slash",s:"question"}, {l:"Shift",m:"shift",w:2.1} ],
    [ {l:"Ctrl",m:"ctrl",w:1.4}, {l:"Super",m:"super",w:1.5}, {l:"Alt",m:"alt",w:1.2},
      {l:"Space",k:"space",w:4}, {l:"Home",k:"Home"}, {l:"End",k:"End"},
      {l:"←",k:"Left"}, {l:"↓",k:"Down"}, {l:"↑",k:"Up"}, {l:"→",k:"Right"},
      {l:"Del",k:"Delete"} ]
  ]
  readonly property var shiftedLabels: ({
    asciitilde:"~", exclam:"!", at:"@", numbersign:"#", dollar:"$", percent:"%",
    asciicircum:"^", ampersand:"&", asterisk:"*", parenleft:"(", parenright:")",
    underscore:"_", plus:"+", braceleft:"{", braceright:"}", bar:"|", colon:":",
    quotedbl:'"', less:"<", greater:">", question:"?"
  })
  readonly property var keycodes: ({
    Escape:1, grave:41, "1":2, "2":3, "3":4, "4":5, "5":6, "6":7,
    "7":8, "8":9, "9":10, "0":11, minus:12, equal:13, BackSpace:14,
    Tab:15, q:16, w:17, e:18, r:19, t:20, y:21, u:22, i:23, o:24,
    p:25, bracketleft:26, bracketright:27, backslash:43,
    a:30, s:31, d:32, f:33, g:34, h:35, j:36, k:37, l:38,
    semicolon:39, apostrophe:40, Return:28, z:44, x:45, c:46, v:47,
    b:48, n:49, m:50, comma:51, period:52, slash:53, space:57,
    Home:102, End:107, Left:105, Down:108, Up:103, Right:106, Delete:111
  })

  function resetModifiers() {
    ctrlActive = shiftActive = altActive = superActive = capsActive = altgrActive = false
    stopRepeat()
    cancelAccent()
  }
  // UKE FORK: por defecto el teclado va ACOPLADO: ancho completo, pegado a las esquinas inferiores
  // y con ~44 % de la altura. Se puede seguir moviendo/redimensionando (el tamaño no se recuerda).
  function clampPosition() {
    positionX = Math.max(0, Math.min(positionX, targetScreen.width - panel.implicitWidth))
    positionY = Math.max(36, Math.min(positionY, targetScreen.height - panel.implicitHeight))
  }
  function clampSize() {
    keyboardWidth = Math.max(minimumWidth, Math.min(keyboardWidth, targetScreen.width))
    keyboardHeight = Math.max(minimumHeight, Math.min(keyboardHeight, targetScreen.height - 72))
    clampPosition()
  }
  function dock() {
    keyboardWidth = targetScreen.width
    keyboardHeight = Math.max(minimumHeight, Math.min(Math.round(targetScreen.height * 0.44), targetScreen.height - 72))
    positionX = 0
    positionY = targetScreen.height - keyboardHeight
  }
  function anchorBottom() {     // tras girar la pantalla se vuelve a acoplar
    if (!opened) return
    dock()
  }
  Connections {
    target: root.targetScreen
    function onWidthChanged() { root.anchorBottom() }
    function onHeightChanged() { root.anchorBottom() }
  }
  function open(payloadJson) {
    var focused = Hyprland.focusedMonitor
    targetScreen = Quickshell.screens.find(function(s) { return focused && s.name === focused.name }) || Quickshell.screens[0]
    dock()
    resetModifiers()
    inputError = ""
    opened = true
  }
  function close() {
    opened = false
    inputReady = false
    resetModifiers()
  }
  function dismiss() {
    close()
    if (shell) shell.hide(manifest.id)
  }
  function modifierActive(name) {
    switch (name) {
      case "ctrl": return ctrlActive
      case "shift": return shiftActive
      case "alt": return altActive
      case "super": return superActive
      case "caps": return capsActive
      case "altgr": return altgrActive
    }
    return false
  }
  function toggleModifier(name) {
    switch (name) {
      case "ctrl": ctrlActive = !ctrlActive; break
      case "shift": shiftActive = !shiftActive; break
      case "alt": altActive = !altActive; break
      case "super": superActive = !superActive; break
      case "caps": capsActive = !capsActive; break
      case "altgr": altgrActive = !altgrActive; break
    }
  }
  function stopRepeat() {
    repeatHandler = null
    repeatKey = null
  }
  // UKE FORK: vocal en ES = se escribe al SOLTAR; si se mantiene > 420 ms sale acentuada (tecla muerta ´ + vocal).
  function cancelAccent() { accentTimer.stop(); accentKey = null; accentFired = false }
  function flushAccent() {
    if (accentKey && !accentFired) activate(accentKey)
    cancelAccent()
  }
  function activateAccented(key) {
    if (!inputReady) return
    input.write("40 " + (altgrActive ? 32 : 0) + "\n")     // tecla muerta ´ de la distribucion ES
    activate(key)
  }
  Timer {
    id: accentTimer
    interval: 420
    onTriggered: {
      if (root.accentKey && !root.accentFired) {
        root.accentFired = true
        root.activateAccented(root.accentKey)
      }
    }
  }
  function pressKey(key, handler) {
    stopRepeat()
    flushAccent()
    if (key.acc && layoutName === "es") {
      accentKey = key
      accentFired = false
      accentTimer.restart()
      return
    }
    activate(key)
    if (!inputReady || key.m) return
    if (["BackSpace", "Delete", "Left", "Right", "Up", "Down"].indexOf(key.k) !== -1) {
      repeatKey = key
      repeatTimer.interval = 350
      repeatHandler = handler
    }
  }
  function releaseKey(key) {
    if (accentKey === key) {
      if (!accentFired) activate(key)
      cancelAccent()
    }
    if (repeatKey === key) stopRepeat()
    // One-shot modifiers survive the whole hold, not the next unrelated tap.
    if (!key.m) ctrlActive = shiftActive = altActive = superActive = altgrActive = false
  }
  Timer {
    id: repeatTimer
    repeat: true
    running: root.opened && root.inputReady && root.repeatHandler !== null && root.repeatHandler.pressed
    onTriggered: {
      if (!root.repeatKey || !root.repeatHandler || !root.repeatHandler.pressed) {
        root.stopRepeat()
        return
      }
      root.activate(root.repeatKey)
      interval = 45
    }
  }
  Connections {
    target: Hyprland
    function onFocusedWorkspaceChanged() { root.stopRepeat() }
    function onActiveToplevelChanged() { root.stopRepeat() }
  }
  function shiftLabel(key) { return key.sl || (key.s ? shiftedLabels[key.s] : "") }
  function hintLabel(key) {
    if (altgrActive) return ""
    if (key.acc && layoutName === "es") return "´"
    return shiftLabel(key)
  }
  function label(key) {
    if (key.t) return key.t.toUpperCase()
    if (altgrActive && key.al) return key.al
    return shiftActive && shiftLabel(key) ? shiftLabel(key) : key.l
  }
  function activate(key) {
    if (!inputReady) return
    if (key.m) { toggleModifier(key.m); return }
    var code = key.c !== undefined ? key.c : keycodes[key.t || key.k]
    var mods = (ctrlActive ? 1 : 0) | (shiftActive ? 2 : 0) |
               (altActive ? 4 : 0) | (superActive ? 8 : 0) | (capsActive ? 16 : 0) | (altgrActive ? 32 : 0)
    input.write(code + " " + mods + "\n")
  }
  onLayoutNameChanged: { cancelAccent(); if (inputReady) input.write("L " + layoutName + "\n") }
  Process {
    id: input
    command: ["sh", decodeURIComponent(Qt.resolvedUrl("input-backend.sh").toString().replace(/^file:\/\//, ""))]
    running: root.opened
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(line) {
        if (line === "ready") { root.inputReady = true; input.write("L " + root.layoutName + "\n") }
      }
    }
    stderr: SplitParser { onRead: function(line) { root.inputError = line } }
    onExited: function(code, status) {
      root.inputReady = false
      root.stopRepeat()
      if (root.opened && !root.inputError)
        root.inputError = "Input backend stopped; close and reopen the keyboard."
    }
  }

  // A small non-focusable layer surface; no full-screen dimmer or reserved
  // desktop area. Only this window receives pointer/touch events. No idle timers.
  PanelWindow {
    id: panel
    visible: root.opened
    screen: root.targetScreen
    anchors { top: true; left: true }
    margins { top: root.positionY; left: root.positionX }
    implicitWidth: root.keyboardWidth
    implicitHeight: root.keyboardHeight
    color: "transparent"
    WlrLayershell.namespace: "omarchy-keyboard"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.background
      radius: 0
      border.width: 1
      border.color: Color.popups.border

      Item {
        id: header
        x: 10; y: 6
        width: parent.width - 20; height: 36
        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: root.inputError || (root.tabletService && root.tabletService.error ? root.tabletService.error : (root.inputReady ? "Teclado  ·  arrastra para mover  ·  modificadores de un toque" : "Preparando teclado…"))
          width: parent.width - 250
          elide: Text.ElideRight
          color: root.inputError ? Color.urgent : root.foreground
          font.family: Style.font.family
          font.pixelSize: 14
        }
        Row {
          anchors.right: parent.right
          anchors.rightMargin: 52
          spacing: 6
          Repeater {
            model: ["layout", "rotate"]
            delegate: Rectangle {
              required property string modelData
              width: 90; height: 34; radius: 5
              color: root.keyBackground
              Text {
                anchors.centerIn: parent
                text: modelData === "layout" ? (root.layoutName === "es" ? "ES · US" : "US · ES") : "⟳ 90°"
                color: root.foreground
                font.pixelSize: 13
              }
              TapHandler {
                onTapped: {
                  if (!root.tabletService) return
                  if (modelData === "layout") root.tabletService.toggleLayout()
                  else root.tabletService.rotate("next")
                }
              }
            }
          }
        }
        MouseArea {
          anchors.fill: parent
          anchors.rightMargin: 250
          property real startX
          property real startY
          property real pointerX
          property real pointerY
          onPressed: function(mouse) {
            startX = root.positionX; startY = root.positionY
            pointerX = root.positionX + mouse.x; pointerY = root.positionY + mouse.y
          }
          onPositionChanged: function(mouse) {
            if (!pressed) return
            var nextX = root.positionX + mouse.x
            var nextY = root.positionY + mouse.y
            root.positionX = startX + nextX - pointerX
            root.positionY = startY + nextY - pointerY
            root.clampPosition()
          }
        }
        Rectangle {
          anchors.right: parent.right
          width: 44; height: parent.height
          radius: 5
          color: closeMouse.pressed ? root.keyBackground : "transparent"
          Text {
            anchors.centerIn: parent
            text: "×"
            color: root.foreground
            font.pixelSize: 24
          }
          MouseArea { id: closeMouse; anchors.fill: parent; onClicked: root.dismiss() }
        }
      }
      Column {
        x: 10; y: 48
        width: parent.width - 20
        height: parent.height - y - 30
        spacing: root.keyGap
        Repeater {
          model: root.rows
          delegate: Row {
            id: keyRow
            required property var modelData
            width: parent.width
            height: (parent.height - parent.spacing * 4) / 5
            spacing: root.keyGap
            readonly property real totalWeight: modelData.reduce(function(sum, k) { return sum + (k.w || 1) }, 0)
            readonly property real unitWidth: (width - spacing * (modelData.length - 1)) / totalWeight
            Repeater {
              model: keyRow.modelData
              delegate: Rectangle {
                id: keyButton
                required property var modelData
                width: keyRow.unitWidth * (modelData.w || 1)
                height: keyRow.height
                radius: 7
                readonly property bool latched: modelData.m ? root.modifierActive(modelData.m) : false
                color: latched || keyTap.pressed ? Color.accent : root.keyBackground
                border.width: 1
                border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15)
                Text {
                  anchors.centerIn: parent
                  width: parent.width - 12
                  height: parent.height - 12
                  horizontalAlignment: Text.AlignHCenter
                  verticalAlignment: Text.AlignVCenter
                  text: root.label(keyButton.modelData)
                  color: keyButton.latched || keyTap.pressed ? Color.background : root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Math.max(12, Math.min(24, keyButton.height * 0.36))
                  fontSizeMode: Text.Fit
                  minimumPixelSize: 10
                }
                Text {
                  anchors.top: parent.top
                  anchors.right: parent.right
                  anchors.margins: Math.max(3, Math.min(7, keyButton.height * 0.12))
                  visible: text !== "" && !root.shiftActive
                  text: root.hintLabel(keyButton.modelData)
                  color: root.foreground
                  opacity: 0.55
                  font.family: Style.font.family
                  font.pixelSize: Math.max(9, Math.min(13, keyButton.height * 0.2))
                }
                Text {
                  anchors.bottom: parent.bottom
                  anchors.right: parent.right
                  anchors.margins: Math.max(3, Math.min(7, keyButton.height * 0.12))
                  visible: !!keyButton.modelData.al && !root.altgrActive && !root.shiftActive && root.layoutName === "es"
                  text: keyButton.modelData.al || ""
                  color: root.foreground
                  opacity: 0.45
                  font.family: Style.font.family
                  font.pixelSize: Math.max(9, Math.min(13, keyButton.height * 0.2))
                }
                TapHandler {
                  id: keyTap
                  enabled: root.inputReady
                  gesturePolicy: TapHandler.WithinBounds
                  onPressedChanged: {
                    if (pressed) root.pressKey(keyButton.modelData, keyTap)
                    else root.releaseKey(keyButton.modelData)
                  }
                  onCanceled: root.releaseKey(keyButton.modelData)
                }
              }
            }
          }
        }
      }
      Text {
        x: 12
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        text: root.layoutName === "es" ? "Mantén una vocal para acentuarla · Borrar y flechas repiten · AltGr: @ # € [ ] { }" : "Hold Backspace or arrows to repeat"
        color: root.foreground
        opacity: 0.65
        font.family: Style.font.family
        font.pixelSize: 11
      }
      Rectangle {
        id: resizeHandle
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 4
        width: 36
        height: 24
        radius: 4
        color: resizeMouse.pressed ? root.keyBackground : "transparent"
        Text {
          anchors.centerIn: parent
          text: "◢"
          color: root.foreground
          font.pixelSize: 17
        }
        MouseArea {
          id: resizeMouse
          anchors.fill: parent
          cursorShape: Qt.SizeFDiagCursor
          property real startWidth
          property real startHeight
          property real startPointerX
          property real startPointerY
          onPressed: function(mouse) {
            root.stopRepeat()
            startWidth = root.keyboardWidth
            startHeight = root.keyboardHeight
            startPointerX = root.positionX + resizeHandle.x + mouse.x
            startPointerY = root.positionY + resizeHandle.y + mouse.y
          }
          onPositionChanged: function(mouse) {
            if (!pressed) return
            var pointerX = root.positionX + resizeHandle.x + mouse.x
            var pointerY = root.positionY + resizeHandle.y + mouse.y
            root.keyboardWidth = startWidth + pointerX - startPointerX
            root.keyboardHeight = startHeight + pointerY - startPointerY
            root.clampSize()
          }
          onReleased: root.resized(root.keyboardWidth, root.keyboardHeight)
        }
      }
    }
  }
}
