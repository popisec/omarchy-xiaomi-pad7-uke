# AUDIO — revisión crítica (4 subagentes, 21-oct-2026) y correcciones

Cuatro revisores de SOLO LECTURA (seguridad HW/nivel, arranque/despliegue, DT/parches de kernel, higiene/documentación). **Nada se aplicó en la tablet**: las correcciones están hechas en el PC, con los harnesses en verde, y se instalan en UN ciclo (ver «Ciclo pendiente»).

## Corregido en el PC (commits de esta fecha)
| # | Hallazgo (gravedad) | Corrección |
|---|---|---|
| R2-1 | **CRÍTICO** contador bootguard `audio` compartido: el `ok` de la etapa 1 borraba el fallo de la 2 y esta podía colgar el arranque en bucle | etapa 2 con contador propio **`audio-amps`** (`uke-audio-amps.service`; el interruptor `no-audio-amps` ya coincidía); tras un intento sin completar o con `e9a-hang`, **degrada a e8b** (`/var/lib/uke/e9a-hang`, se borra a mano para reintentar) |
| R2-2 | ALTO la etapa 2 no exigía APM vivo | la etapa 1 escribe `/run/uke-audio-apm-ok` solo en VERDE; la etapa 2 lo exige |
| R2-3 | ALTO drop-in e9a sin los .ko = sin audio | antes del gate, si faltan `uke_audio_e5/e9a.ko` se degrada a e8b (AMARILLO); `deploy-mic --revert` quita también el drop-in; `deploy.sh --revert` quita la etapa 2 |
| R2-4 | ALTO ventana por conteo de líneas de dmesg | la espera del probe de `uke_fs19xx` usa una marca previa a la carga |
| R2-5 | ALTO timeout ajustado | `uke-audio.service` TimeoutStartSec 240 s |
| R2-6/7 | MEDIO retorno temprano sin ruta/pw_refresh; `pw_refresh` sin `timeout`/varios usuarios | ruta de micro + `pw_refresh` también en AMARILLO; `pw_refresh` recorre usuarios con `timeout`, recomprueba tras reiniciar |
| R2-9 | MEDIO `--down` de la etapa 1 bajo una tarjeta viva | la etapa 1 se niega si hay módulos de la etapa 2 cargados |
| R2-16 | `Alert` no contaba como adjunto | `Attached|Alert` cuentan (Alert es un estado válido) |
| R2-11..15 | `HOSTIP` ignorado en deploy.sh/deploy-ouke5-pre.sh; salidas silenciadas; mkdir/comprobaciones | `HOSTIP` por entorno; errores visibles; `deploy-persist-e9a` comprueba bootguard y fsm |
| R1-A1 | ALTO con `uke_fs_play=0` en caliente los amps no se paraban | **PARAR siempre se atiende** (`mute` y `ctl off`); solo ARRANCAR exige `uke_fs_play=Y` |
| R1-A2 | ALTO error I²C en la parada daba el amp por apagado | `a->on` solo baja si la parada fue limpia; 1 reintento; `fs_streaming` sigue activo si queda algún amp habilitado (error visible) |
| R1-B1 | MEDIO «tope duro» modificable | `FS_VOL_HARD = 243` (0xF3) **de compilación**, `uke_fs_vol/uke_fs_volmax` con callback que recorta y **reaplica en caliente** (bajar el tope baja el volumen sonando) |
| R1-B3/B4/B6 | escena a medias tras error; EN=0xEF sin apagar si falla el volumen; sin `.shutdown` | `cur_mask` solo si no hay error (si hay, `inited=false`); EN←0 best effort; `.shutdown` en el driver I²C y el de plataforma |
| R1-B2/B5 | `uke-nivel.sh` escalón 4 sin red; orden amp/cadena | escalón 4 exige `--yes`, pico **0,70**, vuelta automática al escalón 2 a los 60 s (`systemd-run`), pw-cli se comprueba antes de tocar los amps y el orden es seguro (sube: amp→cadena con restitución; baja: cadena→amp) |
| R3-1 | ALTO UAF del `delayed_work` de q6apm (parche 0005) | **parche 0009** (`cancel_delayed_work_sync` en remove y en los errores del probe, flag de inicialización) en `q6apm-port/build.sh` |
| R3-2 | `check-overlays.py` no pasaba por la tarjeta que se despliega | `build.sh` lo ejecuta también sobre la cadena e2d+e3+e5-codec+e9a (acepta `regulator-fixed` built-in y `uke,fs19xx-codec` del módulo propio) |
| R3-4 | chequeo vacuo (e8b+e9a se fusionan) | `uke-ovl.h` con `UKE_OVL_REFUSE_IF_PATH "/sound"` en e4c/e7a/e7b/e8a/e8b/e9a: rechaza (-EEXIST) una segunda tarjeta |
| R3-5 | scripts de build apuntaban a ouke3/4 | defectos = ouke5 (`KB`, `KT`, `OUT=out-ouke5`) y **abortan si vermagic ≠ kernel.release del árbol** |
Binarios reconstruidos (vermagic ouke5, en `out-ouke5/`): `uke_fs19xx` 2bafe13f…, `snd-q6apm-uke` be7eeecb…, `uke_audio_e8a/e8b/e9a` con el rechazo. Harness: etapa 1 24/24, etapa 2 54/54, mic 15/15, altavoces OK.

## Pendiente (no corregido o necesita la tablet)
- **A3** (arranque/parada de los amps respecto al BCLK; `mute_unmute_on_trigger`): medir el orden «amps habilitados/parados» frente al q6apm antes de tocar; hipótesis no verificada.
- **A4/A5** nodo crudo `uke-alsa-sink` (visible, prioridad 10) y posible sumidero ACP: en M3 `wpctl status` NO mostró sumidero ACP de UKE (solo «Built-in Audio» sin sumidero); el nodo crudo sigue siendo seleccionable. Opciones: mantenerlo abierto, ocultarlo, permisos `/dev/snd`. Decisión pendiente.
- **R3-6** BOB (regulador fijo sin voto en RPMh): probar captura con la pantalla apagada (DPMS off) y tras suspensión.
- **R3-8** WARN `gpiod_set_value` en `wcd939x_probe` (reset LPI que puede dormir): parche externo menor, baja prioridad.
- **R4-1** versionados del fabricante: los dos `fs19xx.fsm`, `libfsalgocal-strings.txt`, XML de política/mezclador del OEM: decidir con el dueño (`git rm --cached` + `~/backups`).
- **R4** logs duplicados de dmesg, MAC/serial en logs, bullets de `docs/historia/ESTADO-VIVO.md` obsoletos, `e23` sin trackear.
- **B2** protección térmica real (no hay FSADSP): vigilar `battery/temp` y bajar de escalón; sin medir.

## Ciclo pendiente en la tablet (necesita «tuya», reinicio con sync)
Instalar (`deploy-persist-e9a.sh --go`, `deploy-ouke5-pre.sh --go`, bootguard sin cambios: el contador es un nombre nuevo) → reiniciar → comprobar: tarjeta e9a por defecto, `uke_fs_volmax` recortado a 243, parada con `uke_fs_play=0`, `uke-mic` creado solo, contador `audio-amps` (`uke-bootguard status audio-amps`), y medir el chasquido inicial de la captura.
