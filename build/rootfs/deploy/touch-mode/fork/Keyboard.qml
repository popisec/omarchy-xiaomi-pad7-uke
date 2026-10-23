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
  // REWORK 20-oct-2026: el texto se entrega como TEXTO (commit_string del input method; respaldo por teclas en el demonio),
  // no como keycodes del keymap: acentos/Unicode no dependen de teclas muertas del cliente (GTK4 las perdia).
  // Las teclas muertas (´ ` ¨ ^) se componen aqui; las especiales y combinaciones (Ctrl+C...) van como teclas reales.
  readonly property string layoutName: tabletService ? tabletService.layout : "es"
  readonly property bool inputReady: tabletService ? tabletService.daemonReady : false
  property string pendingDead: ""        // acute | grave | diaeresis | circumflex
  property var popupKey: null            // tecla con ventana de variantes abierta (pulsacion larga)
  property var popupChars: []
  property int popupIndex: -1
  property real popupX: 0
  property real popupY: 0
  property var pressKeyObj: null         // tecla con alternativas pulsada y aun sin entregar
  property bool longFired: false
  property string inputError: ""
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

  // Tecla: c = codigo evdev fisico (posicion ISO-ES/ANSI), n = caracter, s = con Shift, a = con AltGr,
  // d/sd = tecla muerta (sin/con Shift), k = especial (se envia como tecla), m = modificador, w = ancho, l = etiqueta.
  function mk(ch, c) { return {n: ch, s: ch.toUpperCase(), c: c, letter: true} }
  readonly property var esRows: [
    [ {l:"Esc",k:1,c:1}, {n:"º",s:"ª",a:"\\",c:41},
      {n:"1",s:"!",a:"|",c:2}, {n:"2",s:"\"",a:"@",c:3}, {n:"3",s:"·",a:"#",c:4},
      {n:"4",s:"$",a:"~",c:5}, {n:"5",s:"%",a:"½",c:6}, {n:"6",s:"&",a:"¬",c:7},
      {n:"7",s:"/",a:"{",c:8}, {n:"8",s:"(",a:"[",c:9}, {n:"9",s:")",a:"]",c:10},
      {n:"0",s:"=",a:"}",c:11}, {n:"'",s:"?",a:"\\",c:12},
      {n:"¡",s:"¿",c:13}, {l:"⌫",k:1,c:14,w:1.6} ],
    [ {l:"Tab",k:1,c:15,w:1.4}, mk("q",16), mk("w",17), {n:"e",s:"E",a:"€",c:18,letter:true}, mk("r",19), mk("t",20),
      mk("y",21), mk("u",22), mk("i",23), mk("o",24), mk("p",25),
      {n:"`",s:"^",d:"grave",sd:"circumflex",a:"[",c:26}, {n:"+",s:"*",a:"]",c:27},
      {l:"Del",k:1,c:111,w:1.4} ],
    [ {l:"Caps",m:"caps",w:1.5}, mk("a",30), mk("s",31), mk("d",32), mk("f",33), mk("g",34),
      mk("h",35), mk("j",36), mk("k",37), mk("l",38), {n:"ñ",s:"Ñ",c:39,letter:true},
      {n:"´",s:"¨",d:"acute",sd:"diaeresis",a:"{",c:40}, {n:"ç",s:"Ç",a:"}",c:43,letter:true}, {l:"Enter",k:1,c:28,w:1.8} ],
    [ {l:"Shift",m:"shift",w:1.6}, {n:"<",s:">",c:86}, mk("z",44), mk("x",45), mk("c",46), mk("v",47), mk("b",48),
      mk("n",49), mk("m",50), {n:",",s:";",c:51}, {n:".",s:":",c:52},
      {n:"-",s:"_",c:53}, {l:"Shift",m:"shift",w:2.0} ],
    [ {l:"Ctrl",m:"ctrl",w:1.2}, {l:"Super",m:"super",w:1.2}, {l:"Alt",m:"alt",w:1.1}, {l:"🎙",mic:1,w:1.4},
      {l:"",k:1,c:57,w:5.2}, {l:"AltGr",m:"altgr",w:1.2},
      {l:"←",k:1,c:105}, {l:"↓",k:1,c:108}, {l:"↑",k:1,c:103}, {l:"→",k:1,c:106} ]
  ]
  readonly property var usRows: [
    [ {l:"Esc",k:1,c:1}, {n:"`",s:"~",c:41},
      {n:"1",s:"!",c:2}, {n:"2",s:"@",c:3}, {n:"3",s:"#",c:4},
      {n:"4",s:"$",c:5}, {n:"5",s:"%",c:6}, {n:"6",s:"^",c:7},
      {n:"7",s:"&",c:8}, {n:"8",s:"*",c:9}, {n:"9",s:"(",c:10},
      {n:"0",s:")",c:11}, {n:"-",s:"_",c:12},
      {n:"=",s:"+",c:13}, {l:"⌫",k:1,c:14,w:1.6} ],
    [ {l:"Tab",k:1,c:15,w:1.5}, mk("q",16), mk("w",17), mk("e",18), mk("r",19), mk("t",20),
      mk("y",21), mk("u",22), mk("i",23), mk("o",24), mk("p",25),
      {n:"[",s:"{",c:26}, {n:"]",s:"}",c:27},
      {n:"\\",s:"|",c:43,w:1.5} ],
    [ {l:"Caps",m:"caps",w:1.7}, mk("a",30), mk("s",31), mk("d",32), mk("f",33), mk("g",34),
      mk("h",35), mk("j",36), mk("k",37), mk("l",38), {n:";",s:":",c:39},
      {n:"'",s:"\"",c:40}, {l:"Enter",k:1,c:28,w:2.3} ],
    [ {l:"Shift",m:"shift",w:2.1}, mk("z",44), mk("x",45), mk("c",46), mk("v",47), mk("b",48),
      mk("n",49), mk("m",50), {n:",",s:"<",c:51}, {n:".",s:">",c:52},
      {n:"/",s:"?",c:53}, {l:"Shift",m:"shift",w:2.1} ],
    [ {l:"Ctrl",m:"ctrl",w:1.2}, {l:"Super",m:"super",w:1.2}, {l:"Alt",m:"alt",w:1.1}, {l:"🎙",mic:1,w:1.4},
      {l:"",k:1,c:57,w:5.2}, {l:"Del",k:1,c:111,w:1.2},
      {l:"←",k:1,c:105}, {l:"↓",k:1,c:108}, {l:"↑",k:1,c:103}, {l:"→",k:1,c:106} ]
  ]
  readonly property var rows: layoutName === "es" ? esRows : usRows

  // Variantes de pulsacion larga (la primera = lo que sale al soltar sin deslizar). Valen en ES y US.
  readonly property var alts: ({
    a:"áàâäãå", e:"éèêë€", i:"íìîï", o:"óòôöõ", u:"úüùû", n:"ñń", c:"çćč", s:"šś", y:"ýÿ", z:"žź", l:"ł",
    "?":"¿", "!":"¡", ".":"…", "-":"–—", "'":"´’‘", "\"":"«»“”", "$":"€£¥¢", "/":"÷", "=":"≠≈", "+":"±",
    "0":"°º", "1":"½¹", "2":"²", "3":"³", "<":"≤«", ">":"≥»", "%":"‰", "*":"×•", "¡":"!", "¿":"?"
  })
  readonly property var deadChars: ({acute:"´", grave:"`", diaeresis:"¨", circumflex:"^"})
  readonly property var deadMap: ({
    acute: {a:"á",e:"é",i:"í",o:"ó",u:"ú",y:"ý",c:"ć",n:"ń",s:"ś",z:"ź",A:"Á",E:"É",I:"Í",O:"Ó",U:"Ú",Y:"Ý",C:"Ć",N:"Ń",S:"Ś",Z:"Ź"},
    grave: {a:"à",e:"è",i:"ì",o:"ò",u:"ù",A:"À",E:"È",I:"Ì",O:"Ò",U:"Ù"},
    diaeresis: {a:"ä",e:"ë",i:"ï",o:"ö",u:"ü",y:"ÿ",A:"Ä",E:"Ë",I:"Ï",O:"Ö",U:"Ü",Y:"Ÿ"},
    circumflex: {a:"â",e:"ê",i:"î",o:"ô",u:"û",A:"Â",E:"Ê",I:"Î",O:"Ô",U:"Û"}
  })

  function resetModifiers() {
    ctrlActive = shiftActive = altActive = superActive = capsActive = altgrActive = false
    pendingDead = ""
    stopRepeat()
    cancelPress()
  }
  // ESCRITORIO-TACTIL 22-oct-2026: siempre acoplado (ancho completo, abajo); 40 % de alto en horizontal, 34 % en vertical.
  // Sin pie de ayuda ni asa de redimensionar: ese alto va a las teclas (5 filas de ~70 px logicos = ~10 mm).
  readonly property real dockFraction: targetScreen.width > targetScreen.height ? 0.40 : 0.34
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
    keyboardHeight = Math.max(minimumHeight, Math.min(Math.round(targetScreen.height * root.dockFraction), targetScreen.height - 72))
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
  function same(a, b) { return !!a && !!b && a.c === b.c && a.n === b.n && a.l === b.l }
  function stopRepeat() {
    repeatHandler = null
    repeatKey = null
  }
  function send(line) { if (tabletService) tabletService.send(line) }
  function bits() {
    return (ctrlActive ? 1 : 0) | (shiftActive ? 2 : 0) | (altActive ? 4 : 0) | (superActive ? 8 : 0) | (altgrActive ? 32 : 0)
  }
  function clearOneShots() { ctrlActive = shiftActive = altActive = superActive = altgrActive = false }

  // ---- entrega ----
  function flushDead() {                      // una tecla muerta pendiente se escribe sola
    if (pendingDead) { send("T " + deadChars[pendingDead]); pendingDead = "" }
  }
  function commitChar(ch) {
    if (pendingDead) {
      var comp = deadMap[pendingDead][ch]
      var dead = pendingDead
      pendingDead = ""
      if (comp) { send("T " + comp); return }
      send("T " + deadChars[dead] + (ch === " " ? "" : ch))
      return
    }
    send("T " + ch)
  }
  function charFor(key) {
    var ch
    if (altgrActive && key.a) return key.a
    var up = shiftActive !== (capsActive && !!key.letter)
    if (up && key.s) ch = key.s
    else ch = key.n
    if (!up && capsActive && key.letter) ch = key.s
    return ch
  }
  readonly property string dictState: tabletService ? tabletService.dictState : ""
  // mayuscula automatica (el demonio dice "caps 1" al empezar frase si el campo lo pide): Shift de un solo uso
  property bool autoShift: false
  function setAutoCaps(on) {
    if (on && !shiftActive && !capsActive) { shiftActive = true; autoShift = true }
    else if (!on && autoShift) { shiftActive = false; autoShift = false }
  }
  function clearAutoShift() { autoShift = false }
  Connections {
    target: root.tabletService
    function onCapsHint(on) { root.setAutoCaps(on) }
  }
  Loader { id: clickLoader; active: !!root.tabletService && root.tabletService.sound; source: "Click.qml" }
  function click() { if (clickLoader.item) clickLoader.item.play() }
  function activate(key, forceChar) {
    if (key.mic) { flushDead(); if (tabletService) tabletService.toggleDictation(); return }   // dictado por voz (offline)
    if (key.m) { toggleModifier(key.m); return }
    if (key.k) {                              // especial: tecla real (Retroceso, Enter, flechas, Tab, Espacio...)
      if (key.c === 57 && !ctrlActive && !altActive && !superActive) { commitChar(" "); clearAutoShift(); return }   // espacio como texto: el demonio autocorrige
      if (key.c === 14 && pendingDead) { pendingDead = ""; return }
      flushDead()
      send("K " + key.c + " " + (bits() | (capsActive ? 16 : 0)))
      return
    }
    var combo = ctrlActive || altActive || superActive
    if (combo) {                              // Ctrl+C, Alt+Tab...: tecla fisica con modificadores
      flushDead()
      send("K " + key.c + " " + (bits() | (capsActive ? 16 : 0)))
      return
    }
    if (forceChar !== undefined) { commitChar(forceChar); return }
    var dead = shiftActive && key.sd ? key.sd : (!shiftActive && !altgrActive && key.d ? key.d : "")
    if (dead) {
      if (pendingDead === dead) { commitChar(deadChars[dead]); return }   // ´´ -> ´
      flushDead()
      pendingDead = dead
      return
    }
    commitChar(charFor(key))
  }
  function altsFor(key) {
    if (!key.n || ctrlActive || altActive || superActive) return ""
    var a = alts[key.n]
    if (!a) return ""
    var arr = Array.from(a)
    var up = shiftActive !== capsActive
    return up && key.letter ? arr.map(function(c) { return c.toUpperCase() }).join("") : a
  }
  // pulsacion de una tecla con variantes: se escribe al SOLTAR (o al pulsar otra); si se mantiene 380 ms
  // sale una ventana de variantes: soltar sobre la tecla = primera variante, deslizar a otra = esa.
  function cancelPress() { longTimer.stop(); pressKeyObj = null; longFired = false; popupKey = null; popupChars = []; popupIndex = -1 }
  function flushPress() {
    if (pressKeyObj && !longFired) activate(pressKeyObj)
    cancelPress()
  }
  Timer {
    id: longTimer
    interval: 320
    onTriggered: {
      if (!root.pressKeyObj) return
      var a = root.altsFor(root.pressKeyObj)
      if (a === "") return
      root.longFired = true
      root.popupKey = root.pressKeyObj
      root.popupChars = Array.from(a)
      root.popupIndex = -1
      root.placePopup()
    }
  }
  property var popupAnchor: null           // item visual de la tecla (para colocar la ventana)
  readonly property real popupCell: Math.max(56, Math.min(88, keyboardWidth / 14))
  readonly property real popupHeight: Math.max(60, Math.min(90, keyboardHeight * 0.2))
  function placePopup() {
    if (!popupAnchor) return
    var p = popupAnchor.mapToItem(frame, 0, 0)
    var w = popupChars.length * popupCell
    popupX = Math.max(4, Math.min(p.x + popupAnchor.width / 2 - w / 2, frame.width - w - 4))
    popupY = p.y - popupHeight - 4
    if (popupY < 4) popupY = p.y + popupAnchor.height + 4
  }
  function popupHit(sx, sy) {
    var p = frame.mapFromItem(null, sx, sy)
    if (p.y < popupY - 30 || p.y > popupY + popupHeight + 30) return -1
    var i = Math.floor((p.x - popupX) / popupCell)
    return i >= 0 && i < popupChars.length ? i : -1
  }
  function pressKey(key, handler, anchor) {
    click()
    stopRepeat()
    flushPress()
    if (!inputReady) return
    // letras (y teclas con variantes) se escriben al SOLTAR: asi un trazo de swipe no deja escrita su primera letra
    if (!key.m && !key.k && (altsFor(key) !== "" || key.letter)) {
      pressKeyObj = key
      popupAnchor = anchor
      longFired = false
      longTimer.restart()
      return
    }
    activate(key)
    if (key.m) return
    if ([14, 111, 105, 106, 103, 108].indexOf(key.c) !== -1 && key.k) {
      repeatKey = key
      repeatTimer.interval = 350
      repeatHandler = handler
    }
  }
  function moveKey(key, sx, sy) {
    if (same(popupKey, key)) popupIndex = popupHit(sx, sy)
  }
  function releaseKey(key, sx, sy) {
    if (same(pressKeyObj, key)) {
      if (!longFired) activate(key)
      else {
        var i = popupHit(sx, sy)
        var chars = popupChars
        if (i >= 0) activate(key, chars[i])
        else if (popupIndex >= 0) activate(key, chars[popupIndex])
        else activate(key, chars[0])
      }
      cancelPress()
    }
    if (same(repeatKey, key)) stopRepeat()
    // One-shot modifiers survive the whole hold, not the next unrelated tap.
    if (!key.m) { clearOneShots(); autoShift = false }
  }
  Timer {
    id: repeatTimer
    repeat: true
    running: root.opened && root.inputReady && root.repeatHandler !== null && root.repeatHandler.active
    onTriggered: {
      if (!root.repeatKey || !root.repeatHandler || !root.repeatHandler.active) {
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
    function onActiveToplevelChanged() { root.stopRepeat(); root.pendingDead = "" }
  }
  function hintLabel(key) {
    if (altgrActive || shiftActive) return ""
    if (key.k || key.m) return ""
    if (key.d) return key.s
    return key.s && !key.letter ? key.s : ""
  }
  function label(key) {
    if (key.mic) return dictState === "rec" ? "■ Parar" : dictState === "busy" ? "…" : "🎙 Voz"
    if (key.c === 57 && key.k) return layoutName === "es" ? "español" : "English"
    if (key.l) return key.l
    if (altgrActive && key.a) return key.a
    var up = shiftActive !== (capsActive && !!key.letter)
    return up && key.s ? key.s : key.n
  }
  function isDeadActive(key) {
    if (!pendingDead) return false
    return (key.d === pendingDead && !shiftActive) || (key.sd === pendingDead && shiftActive)
  }
  function altsHint(key) {
    if (key.k || key.m || ctrlActive || altActive) return ""
    return alts[key.n] ? "" : ""
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
      id: frame
      anchors.fill: parent
      color: root.background
      radius: 0
      border.width: 1
      border.color: Color.popups.border

      Item {
        id: header
        // ESCRITORIO-TACTIL 22-oct-2026: la cabecera es la barra de sugerencias (3 casillas, la del medio = la mejor);
        // sin sugerencias muestra el estado (dictado, errores). A la derecha: ES/US, autocorreccion, sonido, girar, cerrar.
        x: 8; y: 4
        width: parent.width - 16; height: 44
        readonly property var sugs: root.tabletService ? root.tabletService.suggestions : []
        readonly property real toolsWidth: 4 * 74 + 4 * 6 + 48
        Text {
          anchors.left: parent.left
          anchors.leftMargin: 6
          anchors.verticalCenter: parent.verticalCenter
          visible: header.sugs.length === 0
          text: root.dictState === "rec" ? "● Grabando… habla y toca «■ Parar» (o × para cancelar)" : root.dictState === "busy" ? "Transcribiendo (sin conexión)…" : root.inputError || (root.tabletService && root.tabletService.dictMsg ? "Dictado: " + root.tabletService.dictMsg : "") || (root.tabletService && root.tabletService.error ? root.tabletService.error : (root.inputReady ? (root.pendingDead ? root.deadChars[root.pendingDead] + " + letra" : (root.tabletService && root.tabletService.lastFix ? (root.tabletService.lastFix.indexOf("palabra nueva") === 0 ? root.tabletService.lastFix : "Corregido: " + root.tabletService.lastFix + "  ·  ⌫ lo deshace") : "")) : "Reconectando teclado…"))
          width: parent.width - header.toolsWidth - 12
          elide: Text.ElideRight
          textFormat: Text.PlainText
          color: root.inputError ? Color.urgent : root.foreground
          opacity: 0.8
          font.family: Style.font.family
          font.pixelSize: 15
        }
        Row {
          id: sugRow
          visible: header.sugs.length > 0
          anchors.left: parent.left
          height: parent.height
          width: parent.width - header.toolsWidth - 12
          spacing: 4
          Repeater {
            // orden visual: [2a, 1a, 3a] como en los moviles (la mejor en el centro)
            model: header.sugs.length >= 2 ? [1, 0, 2] : [0]
            delegate: Rectangle {
              required property var modelData
              readonly property int idx: modelData
              readonly property string word: idx < header.sugs.length ? header.sugs[idx] : ""
              width: (sugRow.width - 8) / 3; height: sugRow.height
              radius: 6
              color: sugTap.pressed ? Color.accent : (idx === 0 ? root.keyBackground : "transparent")
              visible: word !== ""
              Text {
                anchors.centerIn: parent
                width: parent.width - 10
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: parent.word
                color: sugTap.pressed ? Color.background : root.foreground
                font.family: Style.font.family
                font.pixelSize: 19
                font.bold: parent.idx === 0
              }
              TapHandler { id: sugTap; onTapped: { root.click(); if (root.tabletService) root.tabletService.pickSuggestion(parent.idx) } }
            }
          }
        }
        Row {
          anchors.right: parent.right
          anchors.rightMargin: 54
          anchors.verticalCenter: parent.verticalCenter
          spacing: 6
          Repeater {
            model: ["layout", "auto", "sound", "rotate"]
            delegate: Rectangle {
              required property string modelData
              width: 74; height: 38; radius: 6
              readonly property bool on: modelData === "auto" ? (root.tabletService && root.tabletService.autocorrect) : modelData === "sound" ? (root.tabletService && root.tabletService.sound) : false
              color: on ? Qt.tint(root.keyBackground, Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.35)) : root.keyBackground
              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: modelData === "layout" ? (root.layoutName === "es" ? "ES·US" : "US·ES") : modelData === "auto" ? (parent.on ? "Abc✓" : "Abc✗") : modelData === "sound" ? (parent.on ? "🔊" : "🔇") : "⟳ 90°"
                color: root.foreground
                font.pixelSize: 14
              }
              TapHandler {
                onTapped: {
                  if (!root.tabletService) return
                  if (modelData === "layout") root.tabletService.toggleLayout()
                  else if (modelData === "auto") root.tabletService.setAutocorrect(!root.tabletService.autocorrect)
                  else if (modelData === "sound") root.tabletService.setSound(!root.tabletService.sound)
                  else root.tabletService.rotate("next")
                }
              }
            }
          }
        }
        Rectangle {
          anchors.right: parent.right
          width: 48; height: parent.height
          radius: 6
          color: closeMouse.pressed ? root.keyBackground : "transparent"
          Text {
            anchors.centerIn: parent
            text: "×"
            color: root.foreground
            font.pixelSize: 26
          }
          MouseArea { id: closeMouse; anchors.fill: parent; onClicked: { if (root.dictState === "rec") { root.tabletService.cancelDictation(); return } root.dismiss() } }
        }
      }
      Column {
        id: keysColumn
        x: 8; y: 52
        width: parent.width - 16
        height: parent.height - y - 8
        spacing: root.keyGap
        // ---- swipe (ESCRITORIO-TACTIL 22-oct-2026, 2.a ronda): si el dedo se mueve mas de ~0,6 teclas desde una letra antes
        // de la pulsacion larga, es un trazo: se anulan la tecla y su repeticion, se apuntan las letras que cruza y las
        // esquinas (giro > 55 grados tras recorrer media tecla) y al soltar se manda "W [^] teclas" al demonio.
        PointHandler {
          id: swipeTracker
          enabled: root.inputReady
          property bool swiping: false
          property var keys: []
          property var pts: []
          property real sx: 0
          property real sy: 0
          property real lx: 0
          property real ly: 0
          property real ldir: NaN
          property real sinceCorner: 0
          readonly property real unit: keysColumn.width / 14
          function letterAt(px, py) {
            var row = keysColumn.childAt(px, py)
            if (!row || !row.children) return ""
            var k = row.childAt(px - row.x, py - row.y)
            return k && k.modelData && k.modelData.letter ? k.modelData.n : ""
          }
          function addKey(l, corner) {
            if (l === "") return
            var last = keys.length ? keys[keys.length - 1] : null
            if (last && last.l === l) { if (corner) last.c = true; return }
            keys.push({ l: l, c: !!corner })
          }
          onActiveChanged: {
            if (active) {
              swiping = false; keys = []; pts = []
              sx = lx = point.position.x; sy = ly = point.position.y; ldir = NaN; sinceCorner = 0
              return
            }
            if (swiping) {
              addKey(letterAt(lx, ly), true)
              var toks = keys.map(function(k, i) { return (k.c || i === 0 ? "*" : "") + k.l })
              if (toks.length >= 2) root.send("W " + ((root.shiftActive !== root.capsActive) ? "^ " : "") + toks.join(" "))
              root.clearOneShots(); root.autoShift = false
              trail.requestPaint()
            }
            swiping = false; pts = []
            trail.requestPaint()
          }
          onPointChanged: {
            if (!active) return
            var x = point.position.x, y = point.position.y
            if (!swiping) {
              if (root.longFired || root.ctrlActive || root.altActive || root.superActive || root.altgrActive) return
              if (Math.hypot(x - sx, y - sy) < unit * 0.6) return
              var first = letterAt(sx, sy)
              if (first === "") return
              swiping = true
              root.cancelPress(); root.stopRepeat(); root.pendingDead = ""
              addKey(first, true)
              pts = [Qt.point(sx, sy)]
            }
            var step = Math.hypot(x - lx, y - ly)
            if (step < unit * 0.25) return
            var dir = Math.atan2(y - ly, x - lx)
            sinceCorner += step
            var corner = false
            if (!isNaN(ldir)) {
              var d = Math.abs(((dir - ldir + Math.PI * 3) % (Math.PI * 2)) - Math.PI)
              if (d > 0.96 && sinceCorner > unit * 0.5) { corner = true; sinceCorner = 0 }
            }
            // la esquina es la tecla donde el dedo giro (el punto anterior), no la actual
            if (corner) addKey(letterAt(lx, ly), true)
            addKey(letterAt(x, y), false)
            ldir = dir; lx = x; ly = y
            var p = pts; p.push(Qt.point(x, y)); pts = p
            trail.requestPaint()
          }
        }
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
                readonly property bool latched: (modelData.m ? root.modifierActive(modelData.m) : false) || root.isDeadActive(modelData) || (!!modelData.mic && root.dictState !== "")
                color: modelData.mic && root.dictState === "rec" ? Color.urgent : (latched || keyPoint.active ? Color.accent : root.keyBackground)
                border.width: 1
                border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15)
                Text {
                  anchors.centerIn: parent
                  width: parent.width - 12
                  height: parent.height - 12
                  horizontalAlignment: Text.AlignHCenter
                  verticalAlignment: Text.AlignVCenter
                  text: root.label(keyButton.modelData)
                  color: keyButton.latched || keyPoint.active ? Color.background : root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Math.max(12, Math.min(28, keyButton.height * 0.38))
                  fontSizeMode: Text.Fit
                  minimumPixelSize: 10
                }
                Text {
                  anchors.top: parent.top
                  anchors.right: parent.right
                  anchors.margins: Math.max(3, Math.min(7, keyButton.height * 0.12))
                  visible: text !== "" && !root.shiftActive && !root.altgrActive
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
                  visible: !!keyButton.modelData.a && !root.altgrActive && !root.shiftActive && root.layoutName === "es" && !keyButton.modelData.k
                  text: keyButton.modelData.a || ""
                  color: root.foreground
                  opacity: 0.45
                  font.family: Style.font.family
                  font.pixelSize: Math.max(9, Math.min(13, keyButton.height * 0.2))
                }
                PointHandler {
                  id: keyPoint
                  enabled: true
                  property real lastX: 0
                  property real lastY: 0
                  onPointChanged: {
                    lastX = point.scenePosition.x; lastY = point.scenePosition.y
                    if (active) root.moveKey(keyButton.modelData, lastX, lastY)
                  }
                  onActiveChanged: {
                    if (active) { lastX = point.scenePosition.x; lastY = point.scenePosition.y; root.pressKey(keyButton.modelData, keyPoint, keyButton) }
                    else root.releaseKey(keyButton.modelData, lastX, lastY)
                  }
                }
              }
            }
          }
        }
      }
      Canvas {                                      // estela del trazo de swipe (solo pinta mientras se desliza)
        id: trail
        x: keysColumn.x; y: keysColumn.y; width: keysColumn.width; height: keysColumn.height
        z: 15
        visible: swipeTracker.swiping
        onPaint: {
          var ctx = getContext("2d")
          ctx.clearRect(0, 0, width, height)
          var p = swipeTracker.pts
          if (!swipeTracker.swiping || p.length < 2) return
          ctx.strokeStyle = Color.accent; ctx.lineWidth = 7; ctx.lineCap = "round"; ctx.lineJoin = "round"; ctx.globalAlpha = 0.75
          ctx.beginPath(); ctx.moveTo(p[0].x, p[0].y)
          for (var i = 1; i < p.length; i++) ctx.lineTo(p[i].x, p[i].y)
          ctx.stroke()
        }
      }
      Rectangle {                                   // ventana de variantes (pulsacion larga)
        id: popupBox
        visible: root.popupKey !== null
        z: 20
        x: root.popupX; y: root.popupY
        width: root.popupChars.length * root.popupCell
        height: root.popupHeight
        radius: 8
        color: root.background
        border.width: 2
        border.color: Color.accent
        Row {
          anchors.fill: parent
          Repeater {
            model: root.popupChars
            delegate: Rectangle {
              required property var modelData
              required property int index
              width: root.popupCell; height: root.popupHeight
              radius: 6
              color: (root.popupIndex === index || (root.popupIndex < 0 && index === 0)) ? Color.accent : "transparent"
              Text {
                anchors.centerIn: parent
                text: modelData
                color: (root.popupIndex === index || (root.popupIndex < 0 && index === 0)) ? Color.background : root.foreground
                font.family: Style.font.family
                font.pixelSize: root.popupHeight * 0.5
              }
            }
          }
        }
      }
    }
  }
}
