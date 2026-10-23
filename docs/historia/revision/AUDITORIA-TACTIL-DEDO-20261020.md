# Auditoria del demonio tactil del dedo (uke-touchd.py + thp_algo.py) - 20-oct-2026

Alcance: solo lectura sobre `build/rootfs/deploy/tactil/` (no se ha editado nada ahi ni en `touch-mode`; no se ha tocado la tablet).
Referencias de linea = ficheros originales a fecha de hoy (`uke-touchd.py` 339 lineas, `thp_algo.py` 158).
Medidas en el PC (x86, Python 3.14) con los 1289 frames reales de Android (`build/android/perif-20261017/touch-dedo/frames.tar`,
860 con dedo, 429 en reposo). Lo que no se pudo medir en la tablet va marcado **[hipotesis]**.

## Resumen de hallazgos (por prioridad)

| # | Sev. | Hallazgo | Parche |
|---|------|----------|--------|
| 1 | Alta | Chip vivo pero sin IRQ: el demonio queda mudo para siempre (y con `--no-fwload` ni mira) | 0003 |
| 2 | Alta | Cualquier `OSError` (SPI, uinput lleno) o `TimeoutExpired` de la carga mata el demonio sin soltar dedos; SIGTERM sin limpieza | 0003 |
| 3 | Media-alta | Toque fantasma (slots atascados) si el chip se reinicia / pierde firmware con un dedo apoyado | 0003 |
| 4 | Media | CPU con dedo: `feed()` cuesta 1,93 ms/frame (x180 fps = ~35 % de un nucleo); en reposo `quick_idle` 274 us/frame | 0001 |
| 5 | Media | Sin rechazo de palma: una mano apoyada da varios toques fantasma (picos locales >=600 en la misma mancha) | 0002 |
| 6 | Media **[hipotesis]** | Bordes: la franja de ~27 px de cada lado es inalcanzable por construccion | sin parche |
| 7 | Baja | `TOUCH_MAJOR` = nodos de un 3x3 (1..9), no area real; sin PRESSURE | sin parche |
| 8 | Baja | Tracking voraz por orden de pico; centroide 3x3 centrado en el nodo pico (error mediana 10 px) | sin parche |
| 9 | Info | Faltantes frente a Android (modos del IC, sensibilidad, doze, gestos) | - |

## 1. CPU (pregunta 1)

Bucle (`uke-touchd.py:267-335`): en reposo duerme hasta `next_idle` (60 Hz) y vacia los flancos acumulados (`:288`); con dedo o 500 ms
tras levantarlo procesa todos (180/s). Por frame: 2 `ioctl` SPI (`:48-59`: seleccion de pagina + lectura de `n+2`), `string_at` (copia
5120 B, `:59`), `frombytes` (copia 4800 B, `:317`), `quick_idle`/`feed`.

Medido (PC, mediana sobre toda la captura):

| Camino | Original | Con 0001 |
|---|---|---|
| `quick_idle` (reposo) | 274 us/frame | **44 us** (6x) |
| `feed` con dedo (`quick_idle` + `feed`) | 1931 us/frame | **429 us** (4,5x) |
| captura completa (1289 frames) | 2,61 s | 0,60 s |

Causas (perfil con cProfile):
- `thp_algo.py:83-102` `quick_idle`: `max(mutual)` sobre 2400 elementos = 78 us + actualizacion de la base de 2400 nodos cada 16 frames
  (1,3 ms / 16 = 81 us por frame). Arreglo: comparar solo el **byte alto** (`tobytes()[1::2].translate(tabla)`: 10 us; el filtro exacto con
  `max()` solo si hay candidato) y base cada 32 frames con paso `min(1, alpha*every)`.
- `thp_algo.py:109-157` `feed`: construye `d` (2400 restas) y recorre otra vez los 2400 nodos para adaptar la base **en cada frame**
  (65 % del tiempo de `feed`, 1,77 s de 2,50 s en el perfil), y `_peaks` recorre 2400 nodos en Python. Arreglo: candidatos por byte alto
  (media 11 por frame), restas al vuelo en pico/centroide, base 1 de cada 4 frames (mismo `alpha*4`; los nodos tocados siguen excluidos).
- La tablet va a ritmo similar al PC: el README mide 36 % de un nucleo con `feed` en cada frame, coherente con 2-2,7 ms/frame de la medida de aqui.
  Estimacion con 0001: dedo ~35 % -> ~8 %; reposo: el coste de algoritmo desaparece (<1 %) y lo que quede del 10 % medido el 19-oct
  sera SPI+despertares **[hipotesis: medir con `strace -c`/`perf` en la tablet]**.

¿Leer menos en reposo? Cada lectura son **5120 B** (no 4864 como dice el README): `EVENT_BUF` + 0x100 de relleno descartado (`:310`,
`THP_OFF` como `off`) + 64 B de cabecera + 4800 B de rejilla = 2,13 ms de bus a 19,2 MHz por frame (60 Hz en reposo = 13 % del bus,
180 Hz con dedo = 38 %). Se pueden ahorrar los 256 B iniciales leyendo desde `EVENT_BUF+THP_OFF` (mismo `page`, `addr & 0x7F` = 0; -5 %);
no lo incluyo como parche porque no se puede verificar sin el chip. Leer solo parte de la rejilla no es seguro: cada fila suelta cuesta
2 transferencias y un dedo cubre ~2-3 filas. La palanca real seria un comando al IC para bajar la tasa de escaneo en reposo (ver #9).

## 2. Robustez (pregunta 2)

- **#1 IRQ muda** (`:301-308`): sin IRQ en 3 s solo se comprueba `fw_alive`; si el firmware esta vivo, `last_frame = now` y se sigue
  esperando sin hacer nada. Si la linea IRQ se pierde (o el chip entra en un modo mudo, como el "chip mudo" ya visto en el lapiz,
  commit `1fa0a24`) el tactil queda muerto hasta reiniciar. Con `--no-fwload` (`:303`) ni siquiera se mira. Arreglo (0003): leer el contador
  de frame de la cabecera (`F+4`) dos comprobaciones seguidas; si avanza sin flancos => "IRQ perdida", pasar a sondeo a `--hz`
  (deduplicando por contador); si en sondeo el contador se congela 3 s => comprobar firmware / recargar. Deteccion >= 6 s.
- **#2 Excepciones**: `spi.read` (`:310`), `fw_alive` (`:189`), `os.write` en uinput (`:158`, abierto `O_NONBLOCK`: EAGAIN si se llena) y
  `subprocess.run(... timeout=60)` (`:195`) no capturan nada: el demonio muere, uinput se destruye con un dedo puesto y systemd
  relanza a los 5 s (`Restart=on-failure`). Arreglo (0003): captura de `OSError`/`TimeoutExpired`; SPI con backoff y salida limpia
  tras 50 fallos seguidos; fallo de write => se pierde el frame y el siguiente libera todos los slots (`resync`); `signal` para
  SIGTERM/SIGINT que sale por `finally` soltando dedos y `UI_DEV_DESTROY`.
- **#3 Slots atascados**: la rama de recarga (`:292-297`) hace `tr.reset()` pero no `ui.frame([])` (solo lo hace la rama de cambio de
  generacion, `:284-286`); si el firmware se pierde con un dedo apoyado, el ultimo toque queda pulsado en Hyprland. Ademas, los frames
  con cabecera mala (`:312-313`) no sueltan nada nunca. Arreglo (0003): liberar antes de recargar y tras 10 frames malos seguidos con dedo apoyado.
- Panel apagado: bien cubierto (`touch_reset_state`, `:171-186`, `:278-296`); carga 0,2-0,3 s. Un punto menor: `sfd` registrado con
  `POLLPRI|POLLERR` sin `POLLIN` esta bien para sysfs.
- Captura de Android: 5 de 1289 frames con cabecera mala (0,4 %); el daemon los cuenta y los ignora (correcto).

## 3. Calidad tactil (pregunta 3)

Validacion existente (reproducida hoy): 1224 dedos, 4 FP, 1 FN, error mediana 10 px / p90 31 px / max 35 px. Con 0001 y 0002: **identico**
(1224/4/1, mediana 96 -> 96, p90 307 -> 306 en escala x10). Frente al original, las salidas de 0001 coinciden en numero de toques en
los 1289 frames; hay diferencias de posicion de hasta ~43 px en algun frame por la base decimada (`docs/historia/revision/parches-tactil/cmp_equivalencia.py`; el criterio
objetivo, la validacion contra el HAL de Xiaomi, no cambia).

- **Ids**: estables en la captura (7 ids distintos para 7 toques reales). Emparejamiento voraz por orden de pico (`:142-155`): al cruzarse
  dos dedos a menos de `track_dist=2,5` nodos pueden intercambiarse ids; mejor asignacion global (baja prioridad).
- **Jitter**: mediana 0,09-0,2 px/frame en dedo quieto, p90 0,2-1 px: no hace falta filtro.
- **Palma (#5)**: no hay rechazo (`thp_algo.py` solo mira picos). Dedos reales miden 4-13 nodos conectados (>=420 sobre la base);
  una rejilla sintetica de palma (110 nodos con textura) da **3 toques fantasma** con el codigo actual. Ojo: Android tampoco rechaza
  en el framework (`mEnablePalmRejection: 0`, `palm_sensor=0`, `RESUMEN.md` de pantalla-tactil-20261019), asi que esto es mejora, no
  paridad. 0002 descarta toda mancha conexa de >= 40 nodos (parametro `palm_nodes`, 0 = desactivado); en datos reales no cambia nada.
- **Bordes (#6, hipotesis)**: la coordenada es `(r+0,5)*X_MAX/40` con `rc` en [0,39] (`thp_algo.py:158`), es decir X en [267, 21093]
  de 21360: ~27 px de panel (~2 mm) de cada borde inalcanzables, y el centroide 3x3 recortado en la fila 0/39 sesga hacia dentro.
  Importa para gestos de borde y la parte baja del OSK. La captura de Android no tiene toques en bordes (X 2640-18923, Y 1849-30034),
  asi que no hay verdad para calibrarlo: hace falta que el dueno pase el dedo por los 4 bordes con `--verbose` y comparar con la
  posicion fisica (o extrapolar con un vecino virtual). No lo parcheo sin esa medida.
- **Multitoque**: hasta 10 (`max_touch`, = `NSLOTS`). Dos dedos a menos de ~2 nodos (8 mm) se funden en un pico.
- **Area (#7)**: `TOUCH_MAJOR = min(64, n)` con `n` = nodos >= 420 del 3x3 (1..9, `uke-touchd.py:148`, `thp_algo.py:79`); Android publica
  0-255 y PRESSURE. Ninguna app critica lo usa hoy; si se quiere, publicar el tamano de la mancha (`_blob` de 0002 ya lo calcula).

## 4. Que hace Android y el demonio no (pregunta 4)

Evidencia: `build/android/pantalla-tactil-20261019/RESUMEN.md`, `docs/historia/revision/PERIF-TACTIL-20261017.md` (lineas 23-81).
- El driver Novatek (`nt36532_touch`, fw 0x11) deja el IC en modo THP y el **HAL de Xiaomi** calcula coordenadas; lo unico que replica
  este demonio. El framework `xiaomi_touch` expone al IC, via comandos custom, **modos** (activo/game/panel-orien/report-rate),
  `aim-sensitivity`, `edge-filter`, `tap-stability`, `tolerance`, `up-threshold`, `expert-mode` (arrays `mi_tp,*`), 3 perfiles
  `touch-game-param-config*`, `touch_doze_analysis`, `xm_htc_*` (gesture, game_mode, charger, scan_freq) y `ro.vendor.display.touch.idle.enable=true`.
  El demonio no envia ningun comando: el chip escanea siempre a ~180 Hz (medido 19-oct) con la configuracion por defecto del fw.
  Posible ahorro de CPU/bus/energia: tasa de escaneo en reposo (idle/doze) por comando al IC **[hipotesis, requiere el protocolo
  del comando, no capturado]**; y el 'idle' tendria el mismo efecto que `idle-div` pero en el IC.
- Android compensa latencia con `persist.sys.touch.predict_time.value=33` (prediccion en el framework) y sube el refresco con
  `set_touch_timer_ms=200`; en Linux no hay equivalente (Hyprland/Qt no predicen).
- Sin gestos de despertar (doble toque), sin modo guante/charger, sin la calibracion de linea base del IC (aqui la base es software
  adaptativa; con el panel apagado el chip pierde el firmware, ya cubierto por la recarga).
- Dispositivo uinput: sin `ABS_MT_PRESSURE` ni `ABS_MT_TOOL_TYPE`; el id de bus es inventado (`0x18`, `uke-touchd.py:121`), irrelevante.

## Parches (en `build/gates/revision/parches-tactil/`, aplicar desde `build/rootfs/deploy/tactil/` con `patch -p1`)

| Parche | Fichero | Que hace |
|---|---|---|
| `docs/historia/revision/parches-tactil/0001-thp_algo-feed-rapido.patch` | thp_algo.py | candidatos por byte alto, restas al vuelo, base decimada (4,5-6x menos CPU, validacion identica) |
| `docs/historia/revision/parches-tactil/0002-thp_algo-rechazo-palma.patch` | thp_algo.py | **requiere 0001 antes**; rechazo de palma por componente conexa >= 40 nodos |
| `docs/historia/revision/parches-tactil/0003-touchd-robustez.patch` | uke-touchd.py | independiente: IRQ perdida -> sondeo, errores SPI/uinput/timeout, SIGTERM limpio, liberar dedos al recargar |

Verificacion offline (hecha el 20-oct sobre copia de los ficheros actuales, que son identicos a los originales):
- `patch --dry-run` de 0001 y 0003 sobre los ficheros del repo: limpio. 0002 sobre el original falla (depende de 0001, por diseno); aplicados
  en secuencia 0001, 0002, 0003 el resultado compila y coincide byte a byte con la copia de trabajo.
- `docs/historia/revision/parches-tactil/test_thp_algo.py <dir> [--palm]`: reposo, un dedo, ids estables, dos dedos, levantar, palma (original: 3 toques fantasma; con 0002: 0).
- `docs/historia/revision/parches-tactil/test_touchd_mock.py <dir>`: `main()` con SPI/uinput/GPIO falsos: (A) IRQ muda con contador avanzando => "IRQ perdida", paso a sondeo
  en 6,5 s y toques emitidos; (B) EIO continuo => `SystemExit` tras 50 intentos. No cubre uinput real ni SIGTERM real **[sin probar en tablet]**.
- `docs/historia/revision/parches-tactil/cmp_equivalencia.py <dirA> <dirB>`: tiempo y diferencias de salida entre dos versiones de thp_algo sobre los frames de Android
  (hay que extraer `frames.tar` y ajustar la ruta `../fr/frames` en el script).
- `thp_validate.py --fast` con 0001+0002: 1224 / 4 FP / 1 FN, igual que el original.

Para desplegar: copiar a la tablet, `systemctl restart uke-touch`, mirar `journalctl -u uke-touch` (mensajes "IRQ perdida", "error SPI"),
y medir CPU con el procedimiento del README (30 s de `/proc/<pid>/stat`) en reposo y con un dedo moviendose. Un solo cambio por ciclo
(regla del proyecto): aconsejo 0001 -> medir -> 0003 -> 0002.
