# AUDIO — E3d preparado en el PC: validar que leer `VALUE.IN` refleja el pad (gpio16 como salida GPIO) — 18-oct-2026

**No se tocó la tablet.** Motivo: D2-1/D3-1 midieron «0 unos, 0 transiciones» en gpio6-9 con el PCM en marcha, y de ahí se concluyó «no sale reloj». Esa conclusión solo vale si leer `VALUE.IN` con el pin en función alternativa refleja el nivel del pad; **no está comprobado**. E3d lo comprueba con un pin libre donde sí sabemos qué debería leerse.

## Qué hay
`e3c/uke_lpi_io.c` → `out/uke_lpi_io.ko` (sha `ce389f79…`, vermagic ouke4); `e3c/deploy.sh` ahora copia también este `.ko` (solo ficheros). `uke_lpi_rd.ko` sin cambios (`104c376d…`).

## Qué hace (con los votos PRM activos, igual que el driver LPI)
- **Lista blanca de pin {15,16,17,18}** (defecto 16): en el DT de Android **ninguna** de esas líneas aparece en ningún estado de pinctrl del LPI (revisado: gpio13 tiene el estado `wsa_spkr_en1` con `status=disabled`, y 14 es `tx_swr_data2`; por eso no se usan). No toca gpio6-9 (TDM), 0-5, 12 (reset del WCD) ni 13.
- Con `uke_lpi_go=0` (defecto): **solo lecturas** de `CFG` y `VALUE` del pin.
- Con `uke_lpi_go=1`: guarda `CFG`/`VALUE`; escribe `VALUE.OUT=0` y luego `CFG` con función GPIO y `OE=1` (valor antes que OE); alterna `OUT` 1/0 `uke_lpi_cycles` veces (defecto 2000) leyendo `IN` tras cada escritura; cuenta cuántas veces `IN` sigue a `OUT` y las transiciones; **restaura `CFG` y `VALUE` originales** (primero CFG, luego VALUE) y los imprime.
- Esperado si la lectura sirve: `IN siguió a OUT en 4000 de 4000 lecturas`, transiciones ≈ 3999; restaurado = el valor de «antes».

## Procedimiento propuesto (autorización del dueño; vigía + doble captura; ACM un lector)
- **E3d-0** `e3c/deploy.sh --go` (solo ficheros).
- **E3d-1 «seco»**: `insmod uke_lpi_io.ko` (go=0): imprime `CFG/VALUE` de gpio16 (esperable ≈ `0x401`-like). `rmmod uke_lpi_io`.
- **E3d-2**: `insmod uke_lpi_io.ko uke_lpi_go=1`; leer la línea del resultado; `rmmod`. Reversa: ya restaura; si algo fallara, reiniciar (el LPASS vuelve a su reposo).

## Riesgos
| # | Riesgo | Prob./impacto | Nota |
|---|---|---|---|
| 1 | Escribir a un registro del TLMM LPI cuelga el bus | muy baja / alto | las 8 escrituras de E7b a los mismos registros (otros pines) ya pasaron sin problema |
| 2 | gpio16 está cableado a algo y se maneja ~1 ms | baja / bajo | sin ninguna función en el DT de Android; salida a 2 mA durante milisegundos |
| 3 | La restauración no deja el pin como estaba | baja / bajo | se escriben exactamente `cfg0` y `val0` leídos antes; se imprime el valor tras restaurar |

## Qué decide el resultado
- **IN sigue a OUT** ⇒ la lectura es válida: gpio6-9 realmente no conmutan; pasamos a probar el reloj IBIT por PRM y los otros juegos de pines.
- **IN no sigue a OUT** (p. ej. siempre 0) ⇒ las medidas D2-1/D3-1 no demuestran nada; habría que medir de otra forma (otro registro, o el estado del amp).

## E3d-0..2 EJECUTADO (MEDIDO, 23:50) — la prueba NO valida la lectura de IN
- E3d-0: ficheros copiados (shas coinciden). Vigía y capturas vivos, 0 oops.
- E3d-1 (go=0): `gpio16 antes: CFG=0x00000401 VALUE=0x00000000`.
- E3d-2 (go=1): `gpio16: 4000 escrituras OUT, IN siguió a OUT en 2000 de 4000 lecturas, transiciones=0; restaurado CFG=0x00000401 VALUE=0x00000000`. **IN valió siempre 0** (las 2000 «coincidencias» son las lecturas con OUT=0): con el pin en GPIO y OE=1, escribir `OUT=1` **no se refleja en `VALUE.IN`**. Restauración exacta, sin oops.
- **Consecuencia:** el método de D2-1/D3-1 (leer `VALUE.IN` para detectar toggling) **no queda validado**; con este pin y este modo `IN` no refleja el nivel (o el pin no está cableado, o la lectura de `IN` exige otro modo/reloj). **Las conclusiones «no sale reloj por gpio6-9» quedan SIN base** (retiradas hasta validar la medida).
- Preparada una 2.ª prueba en el módulo (`uke_lpi_io.ko` nuevo en `out/`; el commit anterior llevaba por error el binario viejo: corregido en el siguiente commit): imprime `VALUE` crudo tras OUT=1/0 y lee `IN` con el pin como **entrada con pull-up / pull-down / sin pull** (IN debe ser 1 con pull-up y 0 con pull-down si el camino de lectura funciona). Pendiente de autorización.

## E3d-2b EJECUTADO (MEDIDO, 23:52): VALUE.IN sigue en 0 incluso con pull-up
`gpio16 VALUE crudo tras OUT=1: 0x00000002, tras OUT=0: 0x00000000; como entrada: pull-up 0x00000000, pull-down 0x00000000, sin pull 0x00000000`; restaurado `CFG=0x401 VALUE=0`; 0 oops.
- **Las escrituras sí llegan** (el bit OUT se lee de vuelta: 0x2), pero **el bit IN (bit 0) no sube ni con el pin como entrada con pull-up**: para gpio16 `IN` no refleja el pad (pin sin pad/bonding útil, o el camino de entrada exige otra condición).
- Conclusión: **gpio16 no sirve para validar y la medida de D2-1/D3-1 (VALUE.IN de gpio6-9) sigue sin base**; no demuestra ni que haya reloj ni que no.
- Siguiente opción barata: repetir la misma prueba en 15, 17 y 18 (misma lista blanca, solo escrituras de registros de pines sin función conocida). Si `IN` sube con pull-up en alguno, ese pin valida el método y se puede usar el mismo test de pull-up sobre gpio9 (restaurando) para comprobar que `IN` funciona en los pads TDM. Si en ninguno sube, `VALUE.IN` no es un instrumento útil en este LPI y hay que medir de otra forma (otros registros de estado del LPAIF/ADSP, o inferir por el amp).

## E3d-3 EJECUTADO (MEDIDO, 23:52): gpio15, 17 y 18 igual — `VALUE.IN` NO es un instrumento utilizable
En los tres: `VALUE crudo tras OUT=1: 0x2, tras OUT=0: 0x0; como entrada: pull-up 0x0, pull-down 0x0, sin pull 0x0`; `IN siguió a OUT en 2000 de 4000, transiciones=0`; restaurados `CFG=0x401 VALUE=0` exactos; 0 oops. **En ningún pin libre `IN` refleja el pad** (ni con pull-up). Conclusión firme: **leer `VALUE.IN` en este LPI no sirve para medir señales**; las lecturas de D2-1/D3-1 no demuestran nada sobre BCLK/WS/DATA. Se retiran esas conclusiones (ver nota en `AUDIO-E8-DIAG2-PREPA`): **no sabemos si sale reloj por gpio6-9**.

## Instrumento alternativo (preparado en el PC): A/B de los registros de los amps CON y SIN BCLK
Los FS19xx son el sensor: detectan el reloj (PLL/I²S) y cambian registros de estado. Si con el amp habilitado **sin PCM** (sin BCLK) los registros son distintos que con el PCM en marcha, el reloj **sí** llega a los amps; si son idénticos, no llega.
- `fs19xx/uke_fs19xx.c` (nuevo `.ko`, sha `1daa2692…`): debugfs `uke_fs19xx/ctl` (solo escritura; **exige `uke_fs_play=Y`**): `on` arranca los 4 amps sin PCM (48 kHz, BCLK 6,144 MHz, vol/escena de los parámetros), `off` los para.
- `fs19xx/diag-noclk.sh` (en la tablet): vol 0x20, `on`; **A)** volcado de registros sin PCM; **B)** PCM de silencio 5 s y volcado a los 2,5 s; `off`; **C)** parados; restaura `uke_fs_play=N`.
- Seguridad: silencio, vol 0x20 (~−110 dB bajo el máximo, inaudible aunque hubiera señal), ≤ ~8 s con los amps habilitados; sin sensor térmico, el dueño atento.
- Procedimiento: **D4-0** cambiar el módulo (rmmod e8b ≈15 s de timeouts del APM, rmmod uke_fs19xx, copiar el `.ko`, depmod, modprobe, insmod e8b); **D4-1** `bash -s < fs19xx/diag-noclk.sh`.

## D4-0/D4-1 EJECUTADOS (MEDIDO, 23:54) — **el BCLK SÍ llega a los 4 amps y el PLL engancha** (INFERIDO por el A/B de registros)
D4-0: módulo nuevo (`uke_fs19xx` con debugfs `ctl`, sha `1daa2692…`) cargado, tarjeta e8b recargada, 4 amps `DEVID 0x2900`. D4-1 (`diag-noclk.sh`, vol 0x20, silencio, amps habilitados ≈8 s): `ctl on (sin PCM): rc 0` → volcado A → PCM de silencio → volcado B → `ctl off`; 0 oops/faults, `uke_fs_play` devuelto a `N`. Volcado completo: `build/logs/audio/e8-diag-noclk-20261018.txt` (sin commit: ignorado).
Diferencias A (amps ON, SIN BCLK) → B (amps ON, CON PCM/BCLK):
| Amp | Registros que cambian |
|---|---|
| 0x34 | `00` 0200→**0240**, `01` 0128→012b, `0A` 0045→0044, `0C` 00fe→**0069**, `19` 8426→**84a6** |
| 0x35, 0x36, 0x37 | `00` 0200→**0240**, `0C` 00fe→**0069**, `19` 8426→**84a6** |
Los **mismos tres cambios en los cuatro amps** al aparecer el BCLK (bit 0x40 del estado `0x00`, `0x0C` de 0xFE a 0x69, bit 7 de `0x19`): **los amps detectan el reloj** (el pad gpio6 SÍ saca el BCLK y el LPAIF lo genera a 6,144 MHz) y su PLL/I²S reaccionan. Esto **corrige** la lectura de D2-1/D3-1 (que era inválida): **los pines y el reloj están bien**.
## Qué queda (el silencio ya no es reloj ni volumen)
Con reloj presente y los amps habilitados a 0xF3 con tono, no se oye nada: lo que falta es **datos/slot/configuración del amp**:
1. **Slots**: el PCM de 2 canales llena solo los slots 0-1; cada amp lee su slot (`reg 0x1A` por amp = 0x00/0x11/0x22/0x33; `info[16]` 8/2/4/1). Hay que **llenar los 4 slots** (topología de 4 canales ya preparada) y ver cuál suena.
2. **Línea de datos**: el DATA sale por gpio8/9; ¿cuál lleva qué amps y está activa en el ADSP (lane/SD)?
3. Configuración del amp (p. ej. `0x4C`/escena, modo de entrada I²S vs TDM en el preset) distinta de la de Android: comparar el estado de registros con el de Android (no disponible: solo hay `reg_dump` del vendor en el código).
4. Comparar B con **tono** frente a B con **silencio** (¿algún registro de «señal presente» cambia?): barato, mismo script con el WAV.
Siguiente propuesto: **(4)** y luego **el test de 4 canales** (topología `UKE-tplg-4ch.bin` + WAV secuencial, ya copiados a la tablet) con vol 0xF3.

## Test de 4 canales (MEDIDO, 23:56): nada audible en ningún canal; topología restaurada
`UKE-tplg-4ch.bin` en uso, PCM de 4 canales aceptado, WAV secuencial (canal k en [2k, 2k+1.5) s, −40 dBFS) con vol 0xF3 y los 4 amps habilitados (`rc 0`): **el dueño no oyó nada en ningún canal**. Restaurada la topología original (`UKE-tplg.bin` sha `c3ff8ed1…` desde `UKE-tplg.orig.bin`; el PCM de 4 canales vuelve a rechazarse, como debe), e8b recargada, `uke_fs_play=N`. 0 oops.

## Nueva hipótesis principal (estimación, no medida): el contenido de prueba es demasiado débil
Todas las pruebas usaron un tono a **−40 dBFS** (1 % de amplitud). Con el volumen en 0xF3 (≈ −6 dB bajo el máximo del amp, si el paso es de 0,5 dB) la salida queda ≈ 46 dB bajo la plena escala del altavoz: a 1 m eso es del orden de **40-45 dB SPL**, cercano al ruido de una habitación; una pista normal (pico −12…−20 dBFS) está 20-28 dB más alta. **Que no se oiga un tono a −40 dBFS no demuestra que el amp esté mudo** (el reloj llega, ver D4-1; el registro de volumen y el estado se comportan).
- Preparado en el PC (`e4c/make-wav-level.sh NIVEL OUT.wav`): WAV de 1 kHz de 2 s a **−30, −24 y −18 dBFS** (rango permitido −60…−12). Escalera propuesta: −30 → −24 → −18 dBFS, vol 0xF3, 2 s por escalón, el dueño **escuchando a unos 20-30 cm del altavoz (no pegado al oído)** y parando al primer sonido. Riesgo físico: a −18 dBFS y 0xF3 es un nivel normal de música; sin FSADSP ni monitor térmico, ≤ 2 s por escalón y volumen del escalón anterior inaudible/ moderado.
