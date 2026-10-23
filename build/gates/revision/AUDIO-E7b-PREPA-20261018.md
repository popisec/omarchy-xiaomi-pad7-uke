# AUDIO — E7b preparado en el PC: pines TDM gpio6-9 del LPI (primeras ESCRITURAS al TLMM del LPASS) — 18-oct-2026

**No se tocó la tablet.** Requisitos cumplidos: E3b (votos PRM), **E3c-3 (lectura MMIO del TLMM LPI OK, `CFG(gpio13)=0x401`)**, E7a (grafo TDM_SINK con `hw_ptr` a 48 kHz), E8-2/3 (4 FS19xx por I²C y tarjeta e8a). Tarjeta a usar: **`e8b`** (códec real `uke_fs19xx`, `uke_fs_play=0`) o `e7b` (códec ficticio): ambas aplican `pinctrl-0 = <&uke_tdm1_active>`.

## Qué escribe exactamente (derivado de `pinctrl-lpass-lpi.c` y del estado `uke_tdm1_active`)
Por cada pin 6, 7, 8, 9, al sondear la tarjeta:
1. `set_mux`: lectura-modificación-escritura de `CFG` (campo FUNC = 2 = `i2s1_clk/ws/data`).
2. `config_set`: **escribe `VALUE` (OUT=1)** y luego RMW de `CFG` con drive 8 mA (valor 3), bias disable (gpio9: pull-down) y **OE=1**. El estado lleva `output-high`: los pines pasan a **salida a nivel alto**, estáticos hasta que el ADSP/LPAIF mueva BCLK/WS/DATA.
`CFG` esperado tras aplicar (a verificar, partiendo del reposo medido `0x401` en gpio13): gpio6/7/8 ≈ `0x6C8` (bit10 conservado | OE 0x200 | drive 3<<6 | func 2<<2), gpio9 ≈ `0x6C9` (pull-down). Los bits exactos se comprobarán con lectura.
Son **8 escrituras de registro de 32 bit** (2 por pin: `VALUE`, `CFG`, más la del mux) a las direcciones `0x6e80000 + 0x1000·pin`, con los votos PRM activos (el driver hace `pm_runtime_resume_and_get` antes de cada una).

## Qué leer antes y después (solo lectura, `e3c/read-pins.sh`)
- **Antes**: `bash -s < e3c/read-pins.sh` ⇒ CFG de gpio6..9 (reposo; esperado ≈ `0x401`/`0x40x`).
- **Después** de cargar `e8b`: el mismo script ⇒ CFG de gpio6..9; comparar con lo esperado.
- (Opcional) **Con PCM de silencio** corriendo 3 s: no hay forma de ver la señal sin osciloscopio; se confirma solo que `hw_ptr` avanza y que no hay faults.

## Procedimiento propuesto (cada paso con autorización del dueño; ACM un lector, vigía, doble captura, `dmesg -n 7`)
- **E7b-0** (lectura): `read-pins.sh` ⇒ anotar los 4 CFG.
- **E7b-1**: `rmmod uke_audio_e8a` (tarjeta actual; tarda ~15 s por 3 `CMD timeout` del APM al cerrar el grafo, medido en E8-3), `insmod uke_audio_e8b.ko` ⇒ primeras escrituras al TLMM. Esperado: tarjeta `UKE`, `DAI fs16xx-aif con 4 amp(s)`, sin errores de pinctrl.
- **E7b-2** (lectura): `read-pins.sh` ⇒ CFG de gpio6..9.
- **E7b-3** (opcional, aparte): PCM de silencio 3 s con `uke_fs_play=0`.
Los **FS19xx NO se configuran** (`uke_fs_play=0`): no hay escrituras I²C en esta etapa.

## Riesgos
| # | Riesgo | Prob./impacto | Mitigación / nota |
|---|---|---|---|
| 1 | Escritura MMIO al LPASS cuelga el bus | baja / alto (reset físico, sin watchdog) | lecturas ya medidas OK con los mismos votos (E3c-3); el driver vota antes de cada acceso; las escrituras son a registros de configuración de pines |
| 2 | Pines 6-9 usados por otra cosa (DMIC1/2 de la tablet) | baja-media / bajo | sin consumidor en Linux; en el DT de Android son el TDM de los amps; reversible solo por reinicio |
| 3 | Conflicto de ownership de pinmux (otro cliente ya los reclama) | baja / bajo | el core falla con error y la tarjeta no sondea; sin daño |
| 4 | Pines a nivel alto estático hacia 4 FS19xx fuera de reset sin configurar | baja / bajo | niveles lógicos 1,8 V típicos en entradas BCLK/WS; los amps están en estado de reset de registro (sin `0x10`/`0x11` escritos) |
| 5 | **Sin reversa limpia**: descargar la tarjeta suelta la reserva del pin pero **no restaura** `CFG`/`VALUE`/función | cierta / bajo | el reposo vuelve al **reiniciar** (el LPASS se resetea con el ADSP); no se añadió estado `sleep` para no escribir más; las lecturas postreversa lo documentan |
| 6 | Retirada de la tarjeta (rmmod e8a) con timeouts del APM ~15 s | media / bajo | medido en E8-3: sin oops; si hubiera oops/ASoC colgado, no `rmmod`: avisar |
| 7 | Interferir con otra sesión (BT/PipeWire) | baja | esta etapa no toca BT ni la shell; la sesión BT suspende/reinicia la tablet a menudo: coordinar |

## No cubre
Señal real en los amps (necesita `uke_fs_play=1` y un volumen seguro: otra decisión); mapa canal→slot→altavoz; que el BCLK de 6,144 MHz sea el que esperan los FS19xx con el PLL de la tabla (INFERIDO del vendor/ACDB); mediciones eléctricas (no hay osciloscopio).

## E7b-0 EJECUTADO (MEDIDO, 21:10) — lecturas de reposo, solo lectura
`read-pins.sh`: `CFG(gpio6) = CFG(gpio7) = CFG(gpio8) = CFG(gpio9) = 0x00000401` (pull-down, función gpio, entrada; idéntico a gpio13). Votos PRM a 0 al terminar; ADSP running, Charging; vigía y capturas vivos; sin faults nuevos. Es la línea base «antes» de E7b-1.

## E7b-1 INTENTO 1 (MEDIDO, 21:11) — NO avanzó: el overlay e8a no se puede retirar (no es el último)
`rmmod uke_audio_e8a` ⇒ `OF: overlay: node_overlaps_later_cs: #3 overlaps with #6 @/__symbols__`, `overlay #3 is not topmost`, `of_overlay_remove: -16; el overlay SIGUE aplicado (el modulo se descarga igual)`. Causa: los overlays se retiran en orden inverso al de aplicación y e3 (#6, que añade símbolos) se cargó **después** de e8a. Consecuencia: la tarjeta e8a sigue viva (sin pines) y su módulo cargador ya no existe, así que **no hay forma de quitarla sin reiniciar**; e8b no puede aplicarse encima (mismos nodos `sound` y `fs19xx-codec`). Sin oops, ADSP/carga bien, nada escrito en los pines.
**Corrección de procedimiento (aplica a E7b y siguientes):** orden de carga **e2d (servicio) → e7i2c → e3 + driver LPI → tarjeta (e8a/e8b)**, de modo que la tarjeta sea siempre el último overlay y se pueda retirar con `rmmod`. Si hay que quitar e3 antes: `modprobe -r pinctrl_sm8650_lpass_lpi pinctrl_lpass_lpi` y `rmmod uke_audio_e3` (solo si es el último).
**Siguiente paso necesario:** reiniciar la tablet (sync + reboot) y repetir con ese orden. Tras el reinicio `uke-audio.service` levanta e2d y el driver `uke_fs19xx` no está en carga automática salvo que exista `i2c-4`.

## E7b-1 EJECUTADO tras reinicio (MEDIDO, 21:12-21:15) — PASA: primeras escrituras al TLMM del LPASS, sin cuelgue
- **Reinicio** (sync + `systemctl reboot`, avisada la sesión BT): `uke-audio` VERDE en frío («APM estado 1», 7 s), `uke-wifi` y `uke-carga` active, `uke-bt` **AMARILLO** («hci0 existe pero no vi el fin del setup en 90 s»; lo gestiona la sesión BT), `wlan0` **DOWN** (ya lo estaba antes del reinicio, desde ~18:05; ajeno a audio; a revisar por el dueño/sesión WiFi). Vigía y dmesg rearmados; **el lector ACM se había caído con el reinicio y se rearmó** (`e7b-20261018-acm.log`).
- Carga con el orden corregido: `insmod uke_audio_e7i2c` (i2c-4, 4 FS19xx con `DEVID 0x2900`, autocarga de `uke_fs19xx`), `insmod uke_audio_e3` + `modprobe pinctrl-sm8650-lpass-lpi` (runtime `suspended`).
- **Antes**: `CFG(gpio6..9) = 0x401` (los 4).
- `insmod uke_audio_e8b`: tarjeta `UKE` con `DAI fs16xx-aif con 4 amp(s); uke_fs_play=0`, overlay id 5 (el último). Sin errores de pinctrl, sin faults.
- **Después**: `CFG(gpio6) = CFG(gpio7) = CFG(gpio8) = 0x6c8`, `CFG(gpio9) = 0x6c9` — **exactamente lo predicho** (bit10 | OE | drive 8 mA | función 2; gpio9 con pull-down). Las 8 escrituras MMIO (mux + VALUE + CFG ×4) se hicieron con los votos PRM sin ningún problema.
- ADSP running, Charging (batería 3777 mV y bajando poco a poco con cargador), 0 oops/faults.
- No se reprodujo audio ni se tocó ningún registro de los amps (`uke_fs_play=0`). BCLK/WS/DATA están ahora como salida a nivel alto estático; el reloj solo se moverá con un PCM abierto.
Estado de la tablet: e2d (servicio), e7i2c, e3 + driver LPI, uke_fs19xx, **e8b** (último overlay, retirable con `rmmod uke_audio_e8b`). Reversa de pines: solo reiniciando.

## E7b-2 EJECUTADO (MEDIDO, 21:16): PCM de silencio con e8b y los pines TDM en función 2
Mezclador `PRIMARY_TDM_RX_0 Audio Mixer MultiMedia1` on + `aplay` de `/dev/zero` (48 kHz, S16, 2 canales, 6 s): `state: RUNNING`, `hw_ptr` 118559 → 174719 en ~1 s con lecturas intercaladas. **Durante el stream** (insmod/rmmod de `uke_lpi_rd` ×4, solo lectura): `CFG(gpio6..8) = 0x6c8`, `CFG(gpio9) = 0x6c9`, sin cambios respecto a antes del stream. `uke-fs19xx-codec: mute=0/1 ignorado (uke_fs_play=0): los amps no se tocan`. 0 oops/faults, ADSP running, Charging (3782 mV). El BCLK/WS/DATA del TDM se mueve ahora por los pines hacia los 4 FS19xx **sin configurar** (no hay medida eléctrica posible sin instrumento; se confirma solo el lado Linux/ADSP).
Siguiente (decisión del dueño, riesgo físico): `uke_fs_play=1` con volumen bajo (`uke_fs_vol`, tope `uke_fs_volmax=0x80`) y silencio ≤ 3 s; luego −40 dBFS ≤ 3 s.

## E8-4a EJECUTADO (MEDIDO, 21:18): los 4 FS19xx habilitados con silencio, `uke_fs_play=1`, vol 0x20 — PASA
`uke_fs_vol=32`, `uke_fs_play=Y` (tope 0x80), mezclador on, `aplay /dev/zero` 3 s: **`amps habilitados: rc 0 (vol 0x20, escena 0)`** ⇒ `reg_init` (danza de reset, sondeo 0x0E, `0x14`, 51 comunes + escena 0) y `start_up` (I²S, PLL 6,144 MHz, `0x11`=0xEF, volumen **antes** de salir de standby, `0x10`=0, `0x30`=0x210, lógica de `0x4C`) completaron en **los 4 amps sin ningún error de I²C**; a los 3 s `amps parados` (`shut_down`). `uke_fs_play` devuelto a `N`. Sin oops/faults, ADSP running, Charging (3780 mV), temperatura de batería 23 °C. Sin sonido audible esperado (silencio). Nada de calor ni ruido anormal reportado por Linux (no hay sensor en los amps; vendor lleva monitor térmico que aquí no existe).
Siguiente (riesgo físico): el WAV de −40 dBFS (≤ 3 s) con `uke_fs_play=1`, volumen bajo; escucha del dueño.

## E8-4b EJECUTADO (21:19): WAV 1 kHz −40 dBFS, 2,8 s, `uke_fs_play=1`, vol 0x20 — lado Linux OK; resultado auditivo PENDIENTE del dueño
`aplay` rc 0; `amps habilitados: rc 0 (vol 0x20, escena 0)` → `amps parados` (2,8 s); sin errores de I²C, 0 oops/faults, ADSP running, Charging; `uke_fs_play` vuelto a `N`. (El SSH cayó ~30 s justo antes por la prueba de suspensión de la sesión BT; se repitió al volver.) Qué se oyó: lo dirá el dueño.
