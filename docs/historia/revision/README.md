# `docs/historia/revision/` — los informes de ciclo archivados

Aquí están los **292 informes de ciclo** que ya no están en el área activa
(`build/gates/revision/`): los que se cerraron en su momento, los intentos que no
salieron, y las pruebas que quedaron atrás.

**No se borran.** Son el registro de lo que se midió, y varios documentos
vivos siguen citando (con su ruta completa, para que no se pierdan al mover
nada).

## Por qué están aquí y no en `build/gates/revision/`

`build/gates/revision/` es el área **viva**: los informes del ciclo en curso y
los que la documentación de la raíz cita. Son los que se leen para saber
**qué funciona hoy**. Los 292 que no los cita nadie se leen **cuando se busca
algo concreto**: un error de una medición, un intento fallido, el por qué de
una decisión.

## El paquete completo

Los 519 ficheros de los 469 informes de ciclo (los 292 de aquí + los 227 que quedan activos) están
también como un único paquete en el release:

**[`evidencia-omarchy-uke-2026-10.tar.gz`](https://github.com/popisec/omarchy-xiaomi-pad7-uke/releases/download/v0.2.0/evidencia-omarchy-uke-2026-10.tar.gz)**
(2,3 MB, `sha256 dcdaf14e2f51d28f32a26be2dd1b04fe91fc83dcc1acb96ead657f370277dbaf`)

Dentro, con la misma estructura de antes:

```
build/gates/revision/            <- los 227 activos
build/gates/revision/archivados/ <- los 292 de aquí
```

## Cómo se busca en ellos

```sh
# un fichero concreto
grep -rl "0x801001" docs/historia/revision/ | head

# por fecha y tema
ls docs/historia/revision/ | grep -iE "^(AUDIO|WIFI|PANEL|CAMARA|BT).*2026101[789]"

# qué se midió tal cual (cifras con unidad)
grep -rhoE "[0-9]+[.,]?[0-9]* (ms|s|mV|mA|Hz|MB|GB|°C|%)" docs/historia/revision/ | sort | uniq -c | sort -rn | head
```
