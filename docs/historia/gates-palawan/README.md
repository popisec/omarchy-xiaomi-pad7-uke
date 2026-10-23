# `docs/historia/gates-palawan/` — la escalera del linaje «palawan»

Los **163 scripts** del linaje de kernel propio («palawan»), del 26-sep al
17-oct: `build-k*.sh` (41), `repack-k*.py` (90), `flash-k*.sh` y
`auto-flash-*.sh`.

**No son codigo duplicado.** Cada uno es una receta distinta con sus propios
gates: los testigos que ese kernel debe tener (`G3`), el perfil de la config, el
cmdline, el arbol de fuentes y los shas que comprueba. Por eso **no** se han
colapsado en un unico script parametrizado: hacerlo perderia los gates, que es
justo lo que hace que valgan.

Se archivan enteros (nada se borra) y las referencias de todo el repo se han
reescrito a esta ruta.

El linaje vigente es el de «senemos» (MCC45TR + parches propios): sus scripts
estan en [`../../build/gates/`](../../build/gates/README.md), y su receta
reproducible en [`../../build/gates/senemos/`](../../build/gates/senemos/README.md).
