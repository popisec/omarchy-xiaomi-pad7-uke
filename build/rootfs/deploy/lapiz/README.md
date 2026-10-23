# Focus Pen (M80P) en la Xiaomi Pad 7 «uke» — código de Linux

Estado a 20-oct-2026: **53 pruebas offline** (`PYTHONPATH=. python3 -m unittest test_lapiz test_uke_pen test_uke_lapiz_ble test_touchd_pen_smoke -v`).
La versión de commit `7dd843e` se desplegó UNA vez en la tablet el 19-oct (`/usr/local/share/uke/lapiz/` y `/usr/local/share/uke/tactil/uke-touchd-pen.py`; el `uke-touchd.py`
original no se toca) y se ejecutó una sesión con `lapiz-pen-session.sh`; **sus resultados no se han podido recuperar aún** (la tablet dejó de responder por USB al acabar).
Tras la revisión independiente del 20-oct (`build/android/lapiz-20261019/analisis/REVISION-MODO-INTEGRADO.md`) el código se corrigió (§23 del informe) pero **la versión corregida
NO está desplegada**: la de la tablet es la anterior. Informe: `build/gates/revision/LAPIZ-20261018.md` §13–§23.

| Fichero | Qué es | Estado |
|---|---|---|
| `thp_pen.py` | frame de lápiz (magic 0x509) → X, Y, contacto | validado offline con la captura de Android (error mediano ~30/60 de 21360/31999); en Linux se vieron 128 frames y decodificó |
| `lapiz_ble.py` | handshake BLE (15 comandos), presión (informe 5), botones (teclado) | handshake idéntico byte a byte al de Android; en Linux el lápiz ACKea los 15 |
| `uke_pen.py` | modo lápiz del chip (BF 04 + 7B 01 con ACK), máquina de estados, uinput `uke Focus Pen`, socket `/run/uke-lapiz.sock`; `PenRuntime` aísla todos los errores (un fallo del lápiz desactiva el lápiz, nunca el táctil) | offline; versión antigua desplegada una vez |
| `uke_lapiz_ble.py` | cliente BLE (bluetoothctl) → mensajes al socket; analizador por líneas completas, eco del hall filtrado, `connected` tras el handshake | solo el analizador está probado; `HALL_ATTACHED` sin calibrar |
| `uke-touchd-pen.patch` | parche **opcional** de `uke-touchd.py` (`--pen`; no se aplica al original, se despliega como copia `uke-touchd-pen.py`); aplica limpio y compila | el demonio original lo mantiene la sesión del táctil |
| `uke_pen.py` (botones) | con el lápiz en rango salen como `BTN_STYLUS/2/3`; fuera de rango, como teclas `F19/PgUp/PgDn` por el nodo `uke Focus Pen Buttons` (modo presentador, como Android) | offline |
| `systemd/`, `install-lapiz.sh` | unidades `uke-lapiz.service` y drop-in `pen.conf` (demonio parcheado con `--pen`; interruptor `/etc/uke/no-pen`) e instalador con `--dry-run`/`--uninstall` y copia de seguridad | **INSTALADO el 20-oct-2026** (autorizado por el dueño; reinstalado tras restaurar userdata a las 23:05). Estado y validación: ver `GUIA-USO.md` e informe §30 |
| `lapiz-handshake.py`, `lapiz-hid-listen.sh`, `lapiz-run*.sh`, `lapiz-connect-run.sh` | scripts de prueba manual en Linux | usados el 19-oct |
| `lapiz-penenable.py/.sh`, `lapiz-penswitch-test.*` | pruebas que pausan `uke-touchd` (SIGSTOP) | NO ejecutar sin autorización; superadas por la integración en el demonio |
| `lapiz-thp-capture.*`, `thp-parse.py`, `thp-pen-load.py` | capturas/análisis de frames THP | análisis offline (usa `frames8k.bin` del scratchpad) |

Lo que Android hace y confirmado: al despegar el lápiz (BLE conectado): `[BF 04 00 01 00]`, ~22 ms, `[7B 01]` (id 1), ambos con ACK; al pegar solo `[BF 04 00 00 00]`;
nunca `7C` ni `pen_switch 0`. Frames 0x509 solo con el lápiz físicamente sobre la pantalla y emitiendo (informes de presión por BLE).
Pendiente: calibrar `HALL_ATTACHED`, la inclinación (sin decodificar) y la primera prueba real con `--pen` (ventana larga, sin pausar el demonio).

## Estado tras las tres críticas independientes (20-oct, ver LAPIZ-20261018.md §28)
- **Corregido offline** (sin desplegar): la punta la decide el contacto del chip y la presión BLE solo se emite con contacto (suelo `PRESSURE_FLOOR`) y vuelve a 0 al levantar; filtro de saltos de posición;
  corrección armónica del sesgo de Y (error mediano ~60 → ~26); sin ejes de inclinación anunciados; marcas de tiempo monotónicas en el log; el cliente BLE reenvía el estado completo, sin `char0025`; SIGTERM como indicador.
- **Pendiente (necesita tablet/decisión del dueño):** rotación del nodo de lápiz (`input:tablet:*` de Hyprland frente a `uke-rotate`), cancelación de toque con `MT_TOOL_PALM` y palma, quirks de libinput (`AttrPressureRange`, `AttrTabletSmoothing`), consumo del cliente BLE (`AcquireNotify`),
  rearme tras un fallo, el interruptor `no-pen` (el chip sigue en modo lápiz), inclinación (segunda rejilla en `F+0x7E4`: TILT_X prometedor), y lo de fondo: conexión por el evento del cargador y **carga inversa** (no medida en Linux).
- **Regla práctica:** ninguna sesión del lápiz sin cargador de pared y batería >30 % (el 20-oct la tablet se apagó sola al 1–2 %).

## Integracion con el escritorio (20-oct, offline, NO instalada): `desktop/`
Rotacion (`input.tablet` + `uke-pen-sync`), quirks/udev de libinput, parche de palma `MT_TOOL_PALM` y tabla de botones; 12 pruebas (`cd desktop && PYTHONPATH=..:. python3 -m unittest test_desktop`). Ver `desktop/README.md` (URLs con fecha y lista de lo no verificado).
