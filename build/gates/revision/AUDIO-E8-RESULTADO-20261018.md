# AUDIO — E8-0/1/2 ejecutados: el bus I²C de los amps funciona y los 4 FS19xx contestan DEVID 0x2900 — 18-oct-2026

Autorizado por el dueño. Vigía + `dmesg -w` a fichero (`build/logs/audio/e8-20261018-dmesg.log`, sin commit: ignorado) + ACM. 0 oops/faults; ADSP running, Charging. (WiFi `wlan0` llevaba caído desde ~18:05, antes de E8-1, ajeno a estos pasos.)

## Resultados (MEDIDOS)
1. **E8-0** ficheros copiados (shas coinciden): `uke_fs19xx.ko`, `uke_audio_e7i2c.ko`, `e8a`, `e8b`, `/lib/firmware/fs19xx.fsm`.
2. **E8-1 (1.er intento, FALLÓ)**: con el overlay de solo `status="okay"` el dispositivo `88c000.i2c` se crea pero `geni_i2c` no lo enlaza ni lo difiere. Causa (lecturas): el nodo conserva la forma Android — `compatible "qcom,i2c-geni"` (el driver casa `qcom,geni-i2c`), `clock-names "se-clk"` (pide `se`), `dmas` de 6 celdas (gpi-dma usa 3). El parche kernel 0001 tampoco lo reescribe. Overlay corregido (`dts/uke-audio-e7-amps-i2c.dtso`: compat, clock-names, `dmas = <&gpi_dma1 0/1 3 3>`, `status` en fragmento posterior). **Segundo intento OK**: `rmmod` del viejo, `insmod` del nuevo, sin forzar el probe ⇒ `i2c-4` («Geni-I2C», 100 kHz) con `4-0034…4-0037`.
3. **E8-2 (1.er intento, ENXIO en los 4)**: el módulo se cargó solo (udev, alias `of:…foursemi,fs16xx` tras `depmod`) con `uke_fs_play=0`. Causa: el `reset-gpio` se pidió con `GPIOD_ASIS` (entrada) y el pulso no se manejaba (el vendor lo pide como salida a nivel bajo). **Corregido** (`GPIOD_OUT_LOW` si `uke_fs_reset`). Pistas descartadas con evidencia de Android (`build/android/cosecha-20261017/01-dmesg.txt`): `fsm_vddd` no existe y Android usa regulador *dummy*; los pines en `gpio` en reposo también los muestra el bus KTZ.
4. **E8-2 (2.º intento, OK)**: `modprobe uke_fs19xx uke_fs_play=0` ⇒ los 4 amps: `DEVID 0x2900` (igual que Android: «Found DEVID: 2900»), preset validado (51 comunes + 150 de escena), `pos` = 8/2/4/1 para 0x34/0x35/0x36/0x37 (coincide con el RE). Familia 0x29xx ⇒ secuencia de arranque con soporte. **Solo se hizo: pulso de reset + lectura del registro 0x03.**

## E8-3 (MEDIDO, 21:04): tarjeta con el códec real, silencio, `uke_fs_play=0` — PASA
- `rmmod uke_audio_e7a` (primera descarga de una tarjeta sana): rc 0, tarjeta retirada; aparecieron 3 `CMD timeout` del APM (opcode 0x100100d, ~15 s) al cerrar el grafo y el aviso de fuga de `of_node` del overlay; sin oops.
- `insmod uke_audio_e8a`: `uke-fs19xx-codec: DAI fs16xx-aif con 4 amp(s); uke_fs_play=0 vol=0x40 tope=0x80` y tarjeta `UKE` con los mandos `FS19XX Volume` (64, 0..255) y `FS19XX Scene`.
- Mezclador `PRIMARY_TDM_RX_0 Audio Mixer MultiMedia1` on + `aplay` de `/dev/zero` 48 kHz S16 2 canales: `state: RUNNING`; **`mute=0 ignorado` / `mute=1 ignorado (uke_fs_play=0): los amps no se tocan`** y ni una línea de «amps habilitados» ⇒ el DAI no escribe en los amps con el parámetro a 0. (Entre medias la tablet hizo un suspend/resume normal.) 0 oops/faults, ADSP running, Charging.
- Aviso: el cierre del grafo del ADSP tarda (3×5 s de timeout) al retirar una tarjeta; no es nuevo del códec.

## Estado final
`uke_audio_e7i2c` (corregido), `uke_fs19xx` (`0bc38fd2…`) y `uke_audio_e8a` cargados; `i2c-4` activo; tarjeta e8a en RAM (se pierde al reiniciar). Los amps están fuera de reset, **sin configurar** (no se escribió ningún registro).

## Siguiente
- E8-3 hecho (arriba).
- Antes de `uke_fs_play=1`: E3c + E7b (reloj TDM real) y revisar el parche 0001 (hay que añadirle la reescritura de compat/clock-names/dmas o seguir con el overlay).
