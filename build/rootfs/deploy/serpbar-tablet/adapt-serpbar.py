#!/usr/bin/python3 -I
"""adapt-serpbar.py BUNDLE — adapta a la tablet uke una copia de la barra del portatil (uke.serpbar + sus ajustes).

BUNDLE es un HOME en miniatura con .config/omarchy/plugins/uke.serpbar y .config/omarchy/serpbar/settings.json
(lo prepara deploy.sh desde el portatil). Cambios minimos, sin tocar el aspecto:
  1. Registra como modulos de serpbar los widgets propios de la tablet (no existen en el portatil):
     uke.launcher (lanzador tactil), omarkyy.tablet (teclado en pantalla), uke.bitwarden, uke.network (Wi-Fi con QR)
     y uke.bateria (% exacto, W y perfil). Cada uno con su icono y la misma accion que su widget de Omarchy.
  2. Los pone en un grupo nuevo a la derecha, antes de wifi/bt/vol/bat, con la misma pildora que los demas.
  3. Altura de la barra en la pantalla de la tablet (bar.monitors.DSI-1) para que las pildoras se toquen con el dedo,
     y 5 escritorios en vez de 8 para que todo quepa en 1600 px logicos (el portatil tiene 1920).
Idempotente (marca «uke-tablet»). Aborta si algun anclaje no aparece (p. ej. tras actualizar serpbar)."""
import json, os, sys

B = sys.argv[1]
P = os.path.join(B, ".config/omarchy/plugins/uke.serpbar")
SETTINGS = os.path.join(B, ".config/omarchy/serpbar/settings.json")
TOUCH_BAR_HEIGHT = 42          # px logicos (escala 2; el portatil usa 40). 48 y 44 no caben en 1600 px de ancho (medido 22-oct)
TABLET_IDS = ["uke.launcher", "omarkyy.tablet", "uke.bitwarden", "uke.network", "uke.bateria"]

def patch(rel, pairs):
    p = os.path.join(P, rel)
    s = open(p, encoding="utf-8").read()
    pairs = [(a, b) for a, b in pairs if b not in s]      # idempotente por cambio
    if not pairs:
        print(f"{rel}: ya adaptado"); return
    for a, b in pairs:
        if s.count(a) != 1:
            sys.exit(f"{rel}: ancla no encontrada ({s.count(a)}x): {a[:70]!r}")
        s = s.replace(a, b)
    open(p, "w", encoding="utf-8").write(s)
    print(f"{rel}: adaptado")

# 1a. Bar.qml del adaptador: registrar los modulos de la tablet.
patch("Bar.qml", [(
    """            { id: "radimsem.omafind", name: "Buscar archivos (omafind)", icon: String.fromCodePoint(0xF0C7C), face: launcher }
        ]""",
    """            { id: "radimsem.omafind", name: "Buscar archivos (omafind)", icon: String.fromCodePoint(0xF0C7C), face: launcher },
            // uke-tablet: widgets propios de la tablet (no estan en el portatil)
            { id: "uke.launcher", name: "Lanzador", icon: String.fromCodePoint(0xF003B), face: face },
            { id: "omarkyy.tablet", name: "Teclado en pantalla", icon: String.fromCodePoint(0xF030C), face: face },
            { id: "uke.bitwarden", name: "Bitwarden", icon: String.fromCodePoint(0xF033E), face: face },
            { id: "uke.network", name: "Wi-Fi (QR)", icon: String.fromCodePoint(0xF0433), face: face },
            { id: "uke.bateria", name: "Bateria exacta", icon: String.fromCodePoint(0xF0079), face: face }
        ]""")])

# 1b. PluginFace.qml: icono/estado/accion de cada uno (el widget de Omarchy sigue cargado e invisible debajo).
patch("dist/quickshell/bar/faces/plugin/PluginFace.qml", [
    ("""        case "crmne.hyprmoncfg": {""",
     """        // uke-tablet: widgets propios de la tablet
        case "uke.launcher":
            return { icon: String.fromCodePoint(0xF003B), active: false, label: "", max: 0 }
        case "omarkyy.tablet":
            return { icon: String.fromCodePoint(0xF030C), active: false, label: "", max: 0 }
        case "uke.bitwarden":
            return { icon: String.fromCodePoint(x && x.unlocked ? 0xF0FC6 : 0xF033E), active: !!x && x.unlocked === true, label: "", max: 0 }
        case "uke.network":
            return { icon: String.fromCodePoint(0xF0433), active: false, label: "", max: 0 }
        case "uke.bateria": {
            var pf = x ? String(x.perfil || "balanced") : "balanced"
            var ic = { "power-saver": 0xF032A, "balanced": 0xF029A, "performance": 0xF04C5 }[pf] || 0xF029A
            // Solo los vatios: el % ya lo da la pildora «bat» de serpbar y la barra no cabe en 1600 px logicos
            var lb = x && x.pct !== "" ? Math.abs(x.wAvg || 0).toFixed(1) + "W" : ""
            return { icon: String.fromCodePoint(ic), active: !!x && x.estado === "Charging", label: lb, max: 60 }
        }
        case "crmne.hyprmoncfg": {"""),
    ("""    function togglePanel() {
        if (w) {""",
     """    // uke-tablet: los widgets de la tablet que no son paneles hacen lo mismo que su boton de Omarchy.
    readonly property var tabletActions: ({
        "uke.launcher": ["omarchy-shell", "-q", "uke.launcher", "toggle"],
        "omarkyy.tablet": ["omarchy-shell", "omarkyy.tablet", "keyboard"],
        "uke.bitwarden": ["omarchy-shell", "shell", "summon", "uke.bitwarden", "{}"],
        "uke.bateria": ["/usr/local/bin/uke-perfil", "cycle"]
    })
    function togglePanel() {
        if (tabletActions[widgetId]) {
            Quickshell.execDetached(tabletActions[widgetId])
            if (w && typeof w.refresh === "function") w.refresh()
            return
        }
        if (w) {"""),
])

# 1c. WifiFace: en la tablet el Wi-Fi muestra el SSID (el portatil va por cable y pone «Connected»). Se corta antes
# (96 en vez de 160) para que la barra quepa en 1600 px logicos sin tapar los indicadores del centro.
patch("dist/quickshell/bar/faces/wifi/WifiFace.qml", [(
    "            maxWidth: s(root.isCompact ? 156 : 160)\n",
    "            maxWidth: s(root.isCompact ? 92 : 96)  // uke-tablet: SSID mas corto para caber en 1600 px\n")])

# 1c-bis. Lo mismo para el Bluetooth: en la tablet el lapiz esta siempre conectado y la pildora muestra su nombre.
patch("dist/quickshell/bar/faces/bt/BtFace.qml", [(
    "            maxWidth: s(root.isCompact ? 156 : 160)\n",
    "            maxWidth: s(root.isCompact ? 92 : 96)  // uke-tablet: nombre del dispositivo mas corto\n")])

# 1d. BtFace/WifiFace deciden «portatil o sobremesa» con /sys/class/power_supply/BAT*; la bateria de la tablet se llama
# «battery», asi que se tomaba por sobremesa y se escondia la pildora del Bluetooth. Se busca cualquier type=Battery.
for rel in ("dist/quickshell/bar/faces/bt/BtFace.qml", "dist/quickshell/bar/faces/wifi/WifiFace.qml"):
    patch(rel, [("if ls /sys/class/power_supply/BAT* 1> /dev/null 2>&1; then",
                 "if grep -qsx Battery /sys/class/power_supply/*/type; then  # uke-tablet: bateria sin nombre BAT*")])

# 2 y 3. Ajustes de serpbar: grupo de la tablet y altura en DSI-1.
st = json.load(open(SETTINGS, encoding="utf-8"))
right = st["bar"]["modules"]["right"]
mods = ["omarchy:" + i for i in TABLET_IDS]
if mods not in right:
    sysgroup = next((i for i, g in enumerate(right) if isinstance(g, list) and "wifi" in g), len(right))
    right.insert(sysgroup, mods)
st["bar"].setdefault("monitors", {})["DSI-1"] = {"height": TOUCH_BAR_HEIGHT}
# La tablet usa 5 escritorios (los de su barra anterior); con 8 puntos la barra no cabe en 1600 px logicos.
st["bar"]["workspaceCount"] = 5
# Texto de la musica al minimo de su propio deslizador (80; el portatil usa el valor por defecto, 120).
st["bar"]["mediaWidth"] = 80
json.dump(st, open(SETTINGS, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
print("settings.json: grupo de la tablet + DSI-1 height", TOUCH_BAR_HEIGHT)
