#!/usr/bin/python3 -I
"""merge-shell.py TABLETA.json PORTATIL.json SALIDA.json — shell.json de la tablet con la barra del portatil.

- `bar` entero del portatil (barra uke.serpbar, layout, apariencia), tal cual.
- Los widgets que solo tiene la tablet se anaden al layout en su misma seccion: asi siguen activados (en Omarchy un
  bar-widget esta activo si esta en el layout). serpbar no usa ese layout para dibujar; los dibuja desde sus ajustes.
- Equivalencias: omarchy.network -> uke.network (copia con QR; las dos a la vez se pelearian por el IPC
  omarchy.network) y omarchy.elsewhen -> uke.elsewhen (no hay elsewhen first-party en el 4.0.6), con sus ajustes.
- `plugins` (ajustes de omafind) del portatil con las carpetas a indexar cambiadas a las de la tablet.
- `dock` del portatil (inerte en la tablet: no hay dock first-party en el 4.0.6).
- `idle` y lo demas, de la tablet (el reposo lo gestiona la sesion de bateria)."""
import json, sys

tab = json.load(open(sys.argv[1], encoding="utf-8"))
lap = json.load(open(sys.argv[2], encoding="utf-8"))
out = json.loads(json.dumps(tab))

RENAME = {"omarchy.network": "uke.network", "omarchy.elsewhen": "uke.elsewhen"}
TABLET_DIRS = ["Documents", "Downloads", "Music", "Notas", "Pictures", "Videos"]

bar = json.loads(json.dumps(lap["bar"]))
lay = bar["layout"]
for sec, items in lay.items():
    if isinstance(items, list):
        for it in items:
            if isinstance(it, dict) and it.get("id") in RENAME:
                it["id"] = RENAME[it["id"]]
# uke.elsewhen: idioma fijado al generar; °C y 24 h como en el portatil (es_ES)
for it in lay.get("centerEnd", []):
    if it.get("id") == "uke.elsewhen":
        it.update({"units": "C", "hour24": True})

have = {it.get("id") for items in lay.values() if isinstance(items, list) for it in items if isinstance(it, dict)}
added = []
for sec, items in tab["bar"].get("layout", {}).items():
    if not isinstance(items, list):
        continue
    for it in items:
        if isinstance(it, dict) and it.get("id") and it["id"] not in have:
            keep = {k: v for k, v in it.items() if not k.startswith("powerbar")}
            lay.setdefault(sec if sec in lay else "right", []).append(keep)
            have.add(it["id"]); added.append(it["id"])
out["bar"] = bar

plugins = json.loads(json.dumps(lap.get("plugins", [])))
for p in plugins:
    if p.get("id") == "radimsem.omafind":
        vol = (p.get("roots") or [{}])[0].get("volume", "")
        p["roots"] = [{"path": "/home/omarchy/" + d, "volume": vol, "excludes": []} for d in TABLET_DIRS]
        p["setupDone"] = False          # el motor y el modelo se preparan en la tablet
out["plugins"] = plugins
if "dock" in lap:
    out["dock"] = lap["dock"]

json.dump(out, open(sys.argv[3], "w", encoding="utf-8"), ensure_ascii=False, indent=2)
print("bar del portatil:", bar.get("id"), "| anadidos de la tablet:", ", ".join(added) or "-")
