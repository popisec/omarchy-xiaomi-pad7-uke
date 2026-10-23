# Guía de uso y mantenimiento del Xiaomi Focus Pen en uke

Para el dueño. Estado de referencia: **20-oct-2026 (informe `build/gates/revision/LAPIZ-20261018.md` §30)**. Escrita sin tablet: nada de lo de aquí se ha vuelto a ejecutar el 21-oct. Lo no comprobado va marcado **[SIN VERIFICAR]**.

Los comandos se ejecutan **en la tablet** (como root, por `ssh -i build/rootfs/uke-arch-root -o BatchMode=yes root@uke`), salvo los de `systemctl --user` y `hyprctl`, que van como usuario `omarchy`.

## 1. Qué funciona hoy y qué no

Instalado de forma permanente el 20-oct (§30) y validado por ti en la tablet.

| Cosa | Estado | Respaldo |
|---|---|---|
| Posición del lápiz por toda la pantalla | Funciona (error mediano ~26/21360 en X e Y tras la corrección; en los bordes la calibración es más débil: nunca se vieron las esquinas) | §28, §30 |
| Presión | Funciona (0..8191, llega por Bluetooth; solo se envía con la punta apoyada) | §24, §28, §30 |
| Punta (tinta) | La decide el chip táctil, no el Bluetooth | §28 |
| Botón pequeño | Funciona (con el lápiz en pantalla llega como botón del lápiz `BTN_STYLUS`) | §30 |
| Dos botones grandes | Funcionan, pero **como teclas** PageUp / PageDown (nodo `uke Focus Pen Buttons`), no como botones del lápiz. Motivo: `BTN_STYLUS2` hacía caer `quickshell` (SIGSEGV de Qt, §28) y `BTN_STYLUS3` no es estándar en libinput | §27, §28; `desktop/botones.json` |
| Rotación 90° y 180° | Probada por ti: el lápiz sale bajo la punta | §30 |
| Rotación 270° | **Funciona** (probada por el dueño el 21-oct: dibuja bajo la punta) | §31 |
| Inclinación | **NO**. No está decodificada; el nodo no la anuncia. rnote y libinput funcionan sin ella | §27, §28 |
| Rechazo de palma | **NO por defecto** (`--palm-hold 0`). Existe un parche con `MT_TOOL_PALM`, pero se dejó desactivado; con la palma apoyada escribir y luego pellizcar funciona según tu prueba | §30; `desktop/README.md` §3 |
| Goma | No existe (no se anuncia `BTN_TOOL_RUBBER`) | `desktop/README.md` §4 |
| Carga del lápiz desde la tablet | **Sin medir** en Linux | §28, §30 |
| Conexión automática al pegarlo | **Pendiente**: hoy lo conecta un bucle de `bluetoothctl connect` del servicio `uke-lapiz`, no el evento del cargador | §28, §30 |

Regla práctica del informe: **sesiones largas de lápiz solo con cargador de pared y batería > 30 %** (el 20-oct la tablet se apagó sola al 1–2 %, §26/§28).

## 2. Uso diario

**Cómo se conecta.** Hay dos servicios: `uke-touch` (el demonio táctil, arrancado con `--pen`) y `uke-lapiz` (cliente Bluetooth del lápiz, MAC `02:00:5E:00:00:07`, `uke_lapiz_ble.py`). `uke-lapiz` intenta conectar con `bluetoothctl connect` hasta que lo logra y hace el mismo saludo de 15 comandos que Android.

- **Despegarlo** de la tablet: el cliente BLE avisa al demonio, que activa el modo lápiz del chip (`BF 04 00 01 00` + `7B 01`, ambos con confirmación) y aparece el nodo `uke Focus Pen`. Es lo que hace Android (§22; README).
- **Pegarlo**: se envía `BF 04 00 00 00` y el chip vuelve a modo normal. Entre pegar/despegar el aviso real es `53 01 xx` (hall) del lápiz. El valor «pegado» = 1 es **hipótesis sin calibrar** (`HALL_ATTACHED` en `uke_lapiz_ble.py`).
- **«Aviso verde»**: en el repo no hay ninguna notificación verde del lápiz. Lo único «verde» documentado es `uke-bt` (el servicio de Bluetooth de la tablet) en `docs/historia/ESTADO-VIVO.md`. **[SIN VERIFICAR]** a qué aviso te refieres; si es otro, dímelo y lo documento.

**Si no responde**, por orden (de lo menos a lo más intrusivo):
1. Comprueba batería de la tablet y del lápiz, y que el lápiz esté despegado y sobre la pantalla (los frames de lápiz solo llegan con el lápiz físicamente sobre el panel, README).
2. Mira el estado (sección 4). Si `uke-lapiz` no está activo o no hay conexión BLE, `systemctl restart uke-lapiz` (solo toca el cliente Bluetooth, no el táctil).
3. Si el dedo funciona pero el lápiz no: espera ~10 s (el demonio reintenta el modo lápiz y se rearma solo, ~3 rearmes por sesión es lo esperado, §30).
4. Si falla el **táctil** también: ve a la sección 7 **antes** de reiniciar nada.
5. Si el Bluetooth de la tablet no tiene controlador (`uke-bt` rojo), es el problema de BT mudo, ajeno al lápiz; ver `docs/historia/ESTADO-VIVO.md` y `BT-MUDO-20261019.md`.

## 3. Botones y aplicaciones

| Botón | Lápiz sobre la pantalla (en rango) | Lápiz lejos de la pantalla | Verificado |
|---|---|---|---|
| Punta | `BTN_TOUCH` + `ABS_PRESSURE` | — | Dibujo con presión: **sí** (§30) |
| Pequeño | `BTN_STYLUS` por `uke Focus Pen` | `F19` por `uke Focus Pen Buttons` | **Sí** (§30). Efecto en cada app: ver abajo |
| Grande arriba | `PageUp` (siempre, también en rango) | `PageUp` | Pulsaciones sí (§29 bis: 12 pulsaciones sin fallos); utilidad en apps **[SIN VERIFICAR]** |
| Grande abajo | `PageDown` (siempre) | `PageDown` | Pulsaciones sí (15 en la sesión de 15 min); idem |

Nota (verificado en `uke_pen.py`, `TABLET_BUTTONS = {"small"}` y `btn_route`): los grandes salen **siempre** como teclas, estén en rango o no; solo el pequeño va por el nodo de tableta cuando el lápiz está en rango. El §27 del informe describe el diseño anterior.

Aplicaciones (cómo asignar el botón pequeño). Ninguna configuración dentro de las apps está comprobada en la tablet:
- **rnote**: Ajustes → atajos del botón del lápiz (existen desde rnote 0.4.0; opción para desactivarlos desde 0.11.0, según el changelog citado en `desktop/README.md`). Asignar p. ej. borrador. **[SIN VERIFICAR]** en la tablet. Dibujo con presión: usado el 20-oct (§28 cita rnote vivo, §30 dibujo OK).
- **Xournal++**: Preferencias → dispositivos → «Pen button 1». **[SIN VERIFICAR]** (README de `desktop/` ya lo marca).
- **Krita**: atajo de «clic derecho» por eventos de ratón o Canvas Input Settings. **[SIN VERIFICAR]**; la doc de Krita solo menciona «Use Mouse Events for Right and Middle clicks».
- **Hyprland**: `F19` queda libre (ejemplo comentado en `desktop/hyprland-pen.lua`). PageUp/PageDown no se atan: son teclas globales y romperían el desplazamiento con teclado.

## 4. Comprobar el estado, paso a paso

En la tablet:

1. **Servicios activos**
   ```
   systemctl is-active uke-touch uke-lapiz
   ```
   Esperable: `active` y `active`. Si responde `inactive` en `uke-lapiz`, mira si existe `/etc/uke/no-pen` (la unidad no arranca si existe, `ConditionPathExists=!`).
2. **Interruptor puesto o no**
   ```
   ls -l /etc/uke/no-pen
   ```
   Esperable: «No existe el fichero» (lápiz activado).
3. **Demonio táctil con lápiz**
   ```
   journalctl -u uke-touch --since -10min | tail -40
   ```
   Esperable: línea `modo lapiz activo: socket /run/uke-lapiz.sock`. Mala señal: `modo lapiz NO disponible (...)` (el táctil sigue sin lápiz), `ERROR en ... modo lapiz DESACTIVADO`, `chip mudo ... -> desactivar` o `SIN ACK`. Al despegar el lápiz: `lapiz: activar modo lapiz del chip -> ok`. Cada 30 s hay una línea de estadísticas («30 s: frames válidos ...», y `lapiz:` con contadores).
4. **Cliente Bluetooth**
   ```
   journalctl -u uke-lapiz --since -10min | tail -40
   ```
   Esperable: sin reinicios repetidos (la unidad tiene `Restart=on-failure`, `RestartSec=5`). El formato exacto de las líneas del cliente **[SIN VERIFICAR]**.
5. **Conexión BLE**
   ```
   bluetoothctl info 02:00:5E:00:00:07 | grep -i connected
   ```
   Esperable: `Connected: yes` con el lápiz despegado. (Comando estándar de BlueZ; la MAC sale de `uke_lapiz_ble.py`.)
6. **Dispositivos de entrada en Hyprland** (como `omarchy`)
   ```
   hyprctl devices
   ```
   Esperable: una tableta (`uke-focus-pen`, nombre en minúsculas y guiones según `desktop/hyprland-pen.lua`) y el teclado `uke Focus Pen Buttons`. **Nombre exacto [SIN VERIFICAR]**.
7. **Rotación del lápiz** (como `omarchy`)
   ```
   uke-pen-sync --status
   ```
   Imprime las opciones `input:tablet:output`, `transform` y `region_size` (script `desktop/uke-pen-sync`). Esperable: `output` DSI-1 y `transform` acorde a la rotación (0 normal, 1 = 90°, 2 = 180°, 3 = 270°). Para ver qué aplicaría sin tocar: `uke-pen-sync --dry-run`.
8. **Sincronía automática**
   ```
   systemctl --user status uke-pen-sync.path
   ```
   Esperable: `active (waiting)`. Se dispara al cambiar `~/.local/state/uke-rotate/deg`.

## 5. Interruptores y marcha atrás

- **Apagar el lápiz sin reflashear**: `touch /etc/uke/no-pen` y luego `systemctl restart uke-touch` (el drop-in `pen.conf` lo mira al arrancar el servicio; que haga falta el reinicio lo deduzco del script, **[SIN VERIFICAR]**). El táctil sigue con el demonio original. Para volver: `rm /etc/uke/no-pen && systemctl restart uke-touch && systemctl start uke-lapiz`.
  - Limitación conocida (§28): con `no-pen` el chip **puede quedar en modo lápiz** y el demonio original pierde dedos con el lápiz cerca.
- **Desinstalar**: desde el PC, `build/rootfs/deploy/lapiz/install-lapiz.sh --uninstall` (quita `uke-lapiz.service`, `pen.conf` y la sincronización de rotación `uke-pen-sync`; luego reiniciar `uke-touch`). Con `--dry-run` solo muestra lo que haría. No quita `uke-pen-sync` ni sus unidades de usuario **[SIN VERIFICAR: el script solo borra la unidad del servicio y el drop-in]**.
- La instalación hace copia en `/root/lapiz-bak-<fecha>` de los ficheros anteriores.

**Qué NO hacer:**
- **No reiniciar el chip táctil** a mano ni reiniciar `uke-touch` en caliente mientras haya fallo sin guardar logs (sección 7).
- **No flashear** ni tocar el par de arranque/slots por temas de lápiz: no hace falta y el proyecto lo prohíbe sin ledger y sha pre-registrado.
- No ejecutar `lapiz-penenable.*` ni `lapiz-penswitch-test.*` (pausan `uke-touchd` con SIGSTOP; README: «NO ejecutar sin autorización»).
- Evitar sesiones con batería baja y sin cargador de pared (§26).
- No activar `BTN_STYLUS2` ni `UHID`/ratón aéreo (§27/§28).

## 6. Los 6 problemas conocidos (§30, «Pendiente»)

| # | Problema | Estado |
|---|---|---|
| 1 | **Inclinación** | Sin integrar. Hay un modelo v2 en `thp_tilt.py`; falta una sesión con 5 puntos de pantalla (§27, §28, §30) |
| 2 | **Rechazo de palma estilo Android** | Desactivado por defecto; parche `desktop/uke-touchd-palm.patch` sin verificar en hardware (§28, §30; `desktop/README.md` §3) |
| 3 | ~~Rotación 270°~~ | **Resuelto**: validada el 21-oct (§31) |
| 4 | **Rearmes del modo lápiz** (~3 por sesión) | El chip sale del modo lápiz y se recupera solo; causa no identificada (§30). Ver §29/§29 bis |
| 5 | **Auto-conexión por carga** | Hoy la hace un bucle `bluetoothctl connect`; la vía por el evento del cargador necesitaría un `.ko` fuera de árbol, sin hacer (§28) |
| 6 | **Carga inversa** | Nada medido en Linux (§28). Prueba propuesta: lápiz < 80 %, pegarlo y registrar su % por BLE y `current_now` cada minuto |

Arreglos ya hechos y que conviene conocer: táctil muerto ~55 s tras ráfagas de lápiz (§29 bis), dedo muerto/pellizco roto con la palma apoyada (§30, puntos 2 y 3).

## 7. Si falla el pellizco o el táctil tras usar el lápiz

Hecho clave: los fallos de ese tipo ya ocurrieron (§29, §29 bis, §30) y **se diagnosticaron con logs**. Si reinicias antes, pierdes la evidencia.

1. **No reinicies** `uke-touch`, ni la tablet. Si el dedo no responde, usa SSH/Tailscale.
2. **Guarda los logs primero** (en la tablet; `/root`, no `/tmp`, que es tmpfs):
   ```
   journalctl -u uke-touch --since -10min > /root/lapiz-fallo-$(date +%Y%m%d-%H%M%S)-touch.log
   journalctl -u uke-lapiz --since -10min > /root/lapiz-fallo-$(date +%Y%m%d-%H%M%S)-lapiz.log
   journalctl -b -k --since -10min > /root/lapiz-fallo-$(date +%Y%m%d-%H%M%S)-kernel.log
   ```
   Apunta la hora aproximada del fallo y qué estabas haciendo (botón pulsado, palma apoyada, pellizco tras escribir, rotación).
3. Añade, si puedes: `systemctl is-active uke-touch uke-lapiz`, `grep -i -E "touch|NT36532" /proc/interrupts` (para ver si el chip sigue dando IRQ; en §29 bis daba ~120/s con el demonio dormido).
4. **Recién entonces** recupera: `systemctl restart uke-touch`. Si sigue mal, `touch /etc/uke/no-pen && systemctl restart uke-touch` (modo sin lápiz, sección 5).
5. **Avisa** con: hora, logs guardados (rutas), qué botón/gesto precedió, batería de tablet y lápiz, y si estaba con cargador. El análisis lo retoma la sesión del proyecto con `LAPIZ-20261018.md` §29/§29 bis (el volcado de pilas se activa con `LAPIZ_STACKS=<fichero>`, ver §29).

## Lo que no he podido verificar (resumen)
Todo es lectura de ficheros del repo; sin tablet no se ha ejecutado nada. Dudas: el «aviso verde»; nombres exactos de dispositivos en `hyprctl devices`; formato de líneas de `journalctl -u uke-lapiz`; reinicio necesario tras `no-pen`; ajustes en rnote/Xournal++/Krita; `HALL_ATTACHED` sin calibrar.

## 8. Novedades preparadas el 21-oct-2026 (en el repo, NO desplegadas en la tablet)
Todo esto está commiteado y probado en el PC (suite de 100 tests + simulaciones), pero **no se ha instalado**: hace falta `install-lapiz.sh` con tu autorización.
- **Arreglos de robustez** (commit e60bc34): ya no puede quedarse una tecla pegada si el Bluetooth cae (tope de 15 s por botón), un cliente BLE muerto se da por caído a los 15 s, la presión corrupta se ignora y se acaba la cascada de rearmes si se pierde el «presión 0» (parada a los 5 s).
- **Prueba de 270°** (ya hecha el 21-oct, OK; se conserva el guion): lista en `desktop/prueba-270/` (guion `PRUEBA-270.md` y script `prueba-270.sh` con `--dry-run`; restaura 0° al salir). Por código 270° es coherente con el dedo; falta confirmarlo con el lápiz.
- **Rechazo de palma estilo Android** (opcional, desactivado): `desktop/palma-android/` (activar con `--palm-android`; ver su README). 64 tests y 66 escenarios de simulación; latencia añadida ~44–66 ms solo con el lápiz cerca. Límite: una palma que llega <64 ms antes del lápiz puede dar un clic suelto. **No lo actives sin probarlo.**
- **Inclinación**: modelo v3 en `thp_tilt.py`, NO integrado. Entre sesiones el error es de 5–7° en el eje X y el eje Y solo está validado en +10…+40°. Para integrarlo falta una captura en 5 puntos de la pantalla (45 barridos); detalles en `build/android/lapiz-20261019/analisis/TILT-DECODIFICACION.md`.
- **Binarios del fabricante**: no están en el repo; copia con sha256 en `~/backups/uke-vendor-blobs-20261021/` (índice: `build/android/lapiz-20261019/LEEME-BINARIOS.md`).
