# AUDIO — altavoces internos: CIERRE (20-oct-2026)

**Hecho:** suenan por los altavoces internos y el dueño lo confirma tras un **arranque en frío en ouke5** (boot de las 12:32 hora tablet), sin intervención: `uke-audio` y `uke-audio-amps` active (VERDES), `snd-q6apm` desde `updates/`, PipeWire/WirePlumber activos, `uke-speakers` predeterminado (prioridad 1000 > nulo 100; el BT, 1010, gana si se conecta). Tono 1 kHz −6 dBFS en el archivo (−18 dBFS efectivos tras la cadena) a volumen de sesión 1,0: oído. Sin oops/faults; vigía OK.

## Causa raíz del mudo original
Tabla PLL de los FS19xx leída con desplazamiento de palabras ([0..2] en vez de [2..4]); para BCLK 6,144 MHz Android escribe `A1=0x0260 A2=0x0540 A3=0x0018` (traza I²C de Android, `AUDIO-ANDROID-REFERENCIA-RESULTADO-20261019.md`). Corregido en `fs19xx/uke_fs19xx.c`.

## Qué queda persistente
- Etapa 1 `uke-audio.service` (APM/PRM) + etapa 2 `uke-audio-amps.service` (e7i2c → e3+LPI → fs19xx → e8b, mezclador ON), habilitadas; guarda `uke-bootguard audio`; interruptores `/etc/uke/no-audio-amps`, `no-audio`, `safe-mode`.
- `/etc/modprobe.d/uke-audio-amps.conf`: `uke_fs_play=1 uke_fs_vol=224 uke_fs_volmax=224` (tope duro 0xE0).
- `/etc/pipewire/pipewire.conf.d/51-uke-speakers.conf`: sumidero `uke-speakers` (ganancia ×0,25, límite ±0,3, `hw:UKE,0` S16/48 k estéreo sin mmap, `nofail`).
- ouke5: `.ko` en `out-ouke5/`, `updates/` y gates `ouke[45]` instalados; ouke4 intacto para rollback.

## Lecciones
1. Sin `nofail` la conf de PipeWire tumbaba PipeWire (y BT) si la tarjeta no estaba al login. 2. En ouke5 hay que instalar `updates/` y gates ANTES del flash: si no, el primer arranque queda mudo. 3. El volumen de sesión de WirePlumber persiste (cúbico): 0,30 dejó el tono a ≈ −49 dBFS (inaudible). 4. `pkill -f` con patrón que casa con la propia orden mata el shell.

## Riesgos que siguen abiertos
- **Sin FSADSP** (excursión/térmica de Android): solo protegen `uke_fs_volmax=0xE0` y el limitador ±0,3 (≈ −10,5 dBFS pico). Música continua sin medir temperatura: subir niveles con medida.
- Solo la fila 6,144 MHz de la tabla PLL está verificada contra Android; S24 sigue prohibido (tira el ADSP).
- Si la tarjeta aparece después de arrancar PipeWire, reiniciar pipewire de la sesión.
- Fuera del audio, visto en ouke5: `/dev/fuse` no existe (xdg-document-portal falla); WARN de `dpu_crtc_debugfs_state_show` al leer debugfs; `fake-hwclock`/`shadow` failed tras la vuelta de Android (sin revisar).
