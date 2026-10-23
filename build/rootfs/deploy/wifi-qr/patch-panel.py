#!/usr/bin/python3 -I
"""patch-panel.py PANEL.qml — anade a la copia usuario del panel de red de Omarchy un boton «Escanear QR»
(cabecera, junto a «Mostrar QR»/velocidad/interruptor). Idempotente; aborta si no encuentra los anclajes
(p. ej. tras una actualizacion de Omarchy que cambie el panel)."""
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
if "uke-wifi-qr" in s:
    print("ya parcheado"); sys.exit(0)

def rep(old, new, count=1):
    global s
    if s.count(old) != count:
        sys.exit(f"ancla no encontrada ({s.count(old)}x): {old[:60]!r}")
    s = s.replace(old, new)

rep("""  readonly property int qrHeaderIndex: canShareWifi ? 0 : -1
  readonly property int speedHeaderIndex: canRunSpeedTest ? (canShareWifi ? 1 : 0) : -1
  readonly property int toggleHeaderIndex: canToggleWifi ? (canShareWifi ? 1 : 0) + (canRunSpeedTest ? 1 : 0) : -1
  readonly property int headerActionCount: (canShareWifi ? 1 : 0) + (canRunSpeedTest ? 1 : 0) + (canToggleWifi ? 1 : 0)
""", """  // uke: boton «Escanear QR» (anadir Wi-Fi) al principio de la cabecera.
  readonly property bool canScanQr: networkManagerAvailable && wifiStationAvailable
  readonly property int scanHeaderIndex: canScanQr ? 0 : -1
  readonly property int qrHeaderIndex: canShareWifi ? (canScanQr ? 1 : 0) : -1
  readonly property int speedHeaderIndex: canRunSpeedTest ? (canScanQr ? 1 : 0) + (canShareWifi ? 1 : 0) : -1
  readonly property int toggleHeaderIndex: canToggleWifi ? (canScanQr ? 1 : 0) + (canShareWifi ? 1 : 0) + (canRunSpeedTest ? 1 : 0) : -1
  readonly property int headerActionCount: (canScanQr ? 1 : 0) + (canShareWifi ? 1 : 0) + (canRunSpeedTest ? 1 : 0) + (canToggleWifi ? 1 : 0)
  readonly property bool scanHeaderHasCursor: cursorActive && focusSection === "header" && headerIndex === scanHeaderIndex
""")
rep("""    if (headerIndex === qrHeaderIndex) summonWifiQr()
    else if (headerIndex === speedHeaderIndex)""", """    if (headerIndex === scanHeaderIndex) scanWifiQr()
    else if (headerIndex === qrHeaderIndex) summonWifiQr()
    else if (headerIndex === speedHeaderIndex)""")
rep("""    function showQr() { root.summonWifiQr(true) }
""", """    function showQr() { root.summonWifiQr(true) }
    function scanQr() { root.scanWifiQr() }
""")
rep("""  function summonWifiQr(forceDetect) {""", """  // uke: anadir Wi-Fi leyendo un QR (region de pantalla / imagen / camara). Desacoplado del panel.
  function scanWifiQr() {
    controller.hide()
    cancelPasswordPrompt()
    Quickshell.execDetached(["/usr/local/bin/uke-wifi-qr"])
  }

  function summonWifiQr(forceDetect) {""")
rep("""          Button {
            id: qrAction
""", """          Button {
            id: scanAction
            visible: root.canScanQr
            iconText: "@GLYPH@"
            tooltipText: "Add Wi-Fi by scanning a QR"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            iconSize: Style.font.subtitle * 1.5
            horizontalPadding: Style.space(5)
            verticalPadding: Style.space(2)
            hasCursor: root.scanHeaderHasCursor
            Layout.alignment: Qt.AlignVCenter
            onHovered: function(on) { if (on) root.setHeaderCursor(root.scanHeaderIndex) }
            onClicked: root.scanWifiQr()
          }

          Button {
            id: qrAction
""")
s = s.replace("@GLYPH@", chr(0xF0433))  # nf-md-qrcode-scan

# uke (22-oct-2026): al reescanear plugins la barra se destruye antes que el panel y cada delegado que lee
# root.bar.* lanza un TypeError (~60 avisos por rescan). Se leen por alias que toleran bar == null.
rep("""  readonly property color hoverFill:""", """  // uke: alias que toleran bar == null durante el desmontaje (evita TypeError en el journal).
  readonly property color barFg: bar ? bar.foreground : "transparent"
  readonly property string barFont: bar ? bar.fontFamily : ""
  readonly property color barUrgent: bar ? bar.urgent : "transparent"
  readonly property color hoverFill:""")
for k, v in (("foreground", "barFg"), ("fontFamily", "barFont"), ("urgent", "barUrgent")):
    s = s.replace("root.bar." + k, "root." + v)
open(p, "w", encoding="utf-8").write(s)
print("parcheado")
