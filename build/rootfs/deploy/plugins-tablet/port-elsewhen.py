#!/usr/bin/python3 -I
"""port-elsewhen.py SRC DST [--lang=es|en] — genera el plugin de usuario `uke.elsewhen` (reloj mundial con globo) a partir del
`omarchy.elsewhen` de Omarchy (MIT, Jason Fried) del portatil (rama dev), para el Omarchy 4.0.6 de la tablet.

La 4.0.6 no tiene `Commons.I18n` ni `Style.duration()` (llegaron despues). Se calzan:
  - Commons.I18n.t / tn / formatNumber / formatLocale -> UkeI18n.js (catalogo en + es-MX del propio Omarchy)
  - Style.duration(x) -> (x)
  - moduleName/ipcTarget -> uke.elsewhen (no hay primer-party con ese nombre en la tablet)
Idempotente: borra DST y lo regenera. Aborta si algun anclaje no aparece."""
import json, os, re, shutil, sys

args = [a for a in sys.argv[1:] if not a.startswith("--lang=")]
src, dst = args[0], args[1]
# Idioma fijado al generar (una libreria JS no es reactiva y los textos se evaluan antes que cualquier ajuste).
LANG = next((a.split("=", 1)[1] for a in sys.argv[1:] if a.startswith("--lang=")), "es")
LANG = "es-MX" if LANG.startswith("es") else "en"
i18n = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(src.rstrip("/"))))), "default", "i18n")
if not os.path.isdir(i18n):
    sys.exit("no encuentro default/i18n junto al arbol de Omarchy: " + i18n)

shutil.rmtree(dst, ignore_errors=True)
shutil.copytree(src, dst)

def keys_used():
    out = set()
    for f in os.listdir(dst):
        if f.endswith((".qml", ".js")):
            out |= set(re.findall(r'\btn?\("([a-zA-Z]+\.[a-zA-Z.]+)"', open(os.path.join(dst, f), encoding="utf-8").read()))
    return out

used = keys_used()
cat = {}
for lang in ("en", "es-MX"):
    d = json.load(open(os.path.join(i18n, lang, "shell.json"), encoding="utf-8"))
    cat[lang] = {k: d[k] for k in sorted(used) if k in d}
missing = used - set(cat["en"])
if missing:
    sys.exit("claves sin traduccion en en/shell.json: " + ", ".join(sorted(missing)))

# Reglas de plural minimas (en y es: one si n == 1).
js = """.pragma library
// uke: sustituto de Commons.I18n (Omarchy dev) para el Omarchy 4.0.6 de la tablet. Generado por port-elsewhen.py.
var catalogs = %s
var lang = "@LANG@"
var formatLocale = lang === "es-MX" ? "es-ES" : "en-US"
function setLanguage(code) {
  lang = String(code || "").indexOf("es") === 0 ? "es-MX" : "en"
  formatLocale = lang === "es-MX" ? "es-ES" : "en-US"
  return formatLocale
}
function pick(v, count) {
  if (typeof v === "string") return v
  if (v && typeof v === "object") return (count === 1 && v.one) ? v.one : v.other
  return undefined
}
function t(key, fallback) {
  var v = pick(catalogs[lang][key], 2)
  if (typeof v !== "string" || v === "") v = pick(catalogs.en[key], 2)
  return typeof v === "string" && v !== "" ? v : (fallback !== undefined ? fallback : key)
}
function tn(key, count, fallback) {
  var v = pick(catalogs[lang][key], count)
  if (typeof v !== "string" || v === "") v = pick(catalogs.en[key], count)
  return typeof v === "string" && v !== "" ? v : (fallback !== undefined ? fallback : key)
}
function formatNumber(value, decimals) {
  var s = decimals === undefined ? String(value) : Number(value).toFixed(decimals)
  return lang === "es-MX" ? s.replace(".", ",") : s
}
""" % json.dumps(cat, ensure_ascii=False, indent=1)
js = js.replace("@LANG@", LANG)
open(os.path.join(dst, "UkeI18n.js"), "w", encoding="utf-8").write(js)

n_i18n = n_dur = 0
for f in sorted(os.listdir(dst)):
    p = os.path.join(dst, f)
    if not f.endswith(".qml"):
        continue
    s = open(p, encoding="utf-8").read()
    o = s
    s, k = re.subn(r"\bCommons\.I18n\.|(?<![\w.])I18n\.", "UkeI18n.", s); n_i18n += k
    s, k = re.subn(r"\bStyle\.duration\(([^()]*)\)", r"(\1)", s); n_dur += k
    if "UkeI18n." in s and 'import "UkeI18n.js"' not in s:
        last = list(re.finditer(r"^import [^\n]*\n", s, re.M))
        if not last:
            sys.exit("no pude anadir el import en " + f)
        e = last[-1].end()
        s = s[:e] + 'import "UkeI18n.js" as UkeI18n\n' + s[e:]
    if s != o:
        open(p, "w", encoding="utf-8").write(s)

p = os.path.join(dst, "Panel.qml")
s = open(p, encoding="utf-8").read()
for a, b in (('moduleName: "omarchy.elsewhen"', 'moduleName: "uke.elsewhen"'),
             ('ipcTarget: "omarchy.elsewhen"', 'ipcTarget: "uke.elsewhen"'),
             # El KeyboardPanel de 4.0.6 no tiene contenido perezoso (content/loadedContent/ensureContent).
             ("  KeyboardPanel {\n    id: panel\n", "  UkeKeyboardPanel {\n    id: panel\n"),
             # ShellIpc (dev) = IpcHandler + registro en el socket propio del shell; en 4.0.6 basta IpcHandler.
             ("  ShellIpc {\n    target: root.ipcTarget", "  IpcHandler {\n    target: root.ipcTarget"),
             ("  readonly property var formatLocale: Qt.locale(UkeI18n.formatLocale)",
              "  // uke: idioma fijado por port-elsewhen.py --lang (en lugar del I18n de Omarchy dev).\n"
              "  readonly property var formatLocale: Qt.locale(UkeI18n.formatLocale)")):
    if s.count(a) != 1:
        sys.exit("ancla no encontrada en Panel.qml: " + a)
    s = s.replace(a, b)
open(p, "w", encoding="utf-8").write(s)

shutil.copy(os.path.join(os.path.dirname(os.path.abspath(__file__)), "UkeKeyboardPanel.qml"), dst)

# Tactil: objetivos de >= 48 px logicos y nada que dependa solo del hover.
TOUCH = 48
for f, a, b in (
    ("CitySearch.qml", "    height: field.implicitHeight\n", f"    height: Math.max(field.implicitHeight, {TOUCH})\n"),
    ("CitySearch.qml", "    id: field\n    visible: search.active\n",
     f"    id: field\n    visible: search.active\n    height: Math.max(implicitHeight, {TOUCH})\n"),
    ("CityMatches.qml", "      implicitHeight: Style.spacing.popupRowHeight\n",
     f"      implicitHeight: Math.max(Style.spacing.popupRowHeight, {TOUCH})\n"),
    # La X de quitar ciudad solo salia con el puntero encima: ahora tambien en la fila tocada (picked).
    ("CityRow.qml", "    size: fontSize + (Style.space(22) - fontSize) * 0.85\n",
     "    size: Math.max(fontSize + (Style.space(22) - fontSize) * 0.85, 40)\n"),
    ("CityRow.qml", "    opacity: row.removable && (rowHover.hovered || removeButton._hot) ? 1 : 0\n",
     "    opacity: row.removable && (rowHover.hovered || removeButton._hot || row.picked) ? 1 : 0\n"),
):
    p = os.path.join(dst, f)
    s = open(p, encoding="utf-8").read()
    if s.count(a) != 1:
        sys.exit(f"ancla tactil no encontrada en {f}: {a.strip()[:60]}")
    open(p, "w", encoding="utf-8").write(s.replace(a, b))

m = json.load(open(os.path.join(dst, "manifest.json"), encoding="utf-8"))
m["id"] = "uke.elsewhen"
m["name"] = "Elsewhen (uke)"
m["description"] = m["description"] + " Portado a la tablet uke (Omarchy 4.0.6)."
json.dump(m, open(os.path.join(dst, "manifest.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=2)

left = [f for f in os.listdir(dst) if f.endswith(".qml") and re.search(r"(?<!Uke)I18n\.|Style\.duration", open(os.path.join(dst, f), encoding="utf-8").read())]
if left:
    sys.exit("quedan usos sin calzar en: " + ", ".join(left))
print(f"uke.elsewhen generado: {n_i18n} I18n, {n_dur} Style.duration, {len(used)} claves")
