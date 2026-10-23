# La barra del portátil en la tablet uke — 22-oct-2026 (sesión plugins-tablet)

Orden del dueño, literal: «quiero que se porte la barra entera que tengo en este sistema, tal cual, misma estética».
Turnos cortos con `uke-turno` (21:34–21:47). Todo reproducible con `build/rootfs/deploy/serpbar-tablet/deploy.sh`.
Dudas: `docs/historia/DUDAS-PLUGINS.md`.

## 1. Qué tiene el portátil (medido 22-oct)

- **Barra**: `uke.serpbar`, la barra de ilyamiro portada vía serpantinum. Usa su propio tema (preset Tokyo, Adwaita Mono)
  sobre el tema de Omarchy `catppuccin` y un fondo `wallhaven-8g5gej`.
- **Módulos** (`~/.config/omarchy/serpbar/settings.json`):
  - izquierda: ajustes, buscar, 8 escritorios, música (MPRIS), Navidrome y bandeja;
  - centro: hora, fecha y 3 indicadores circulares (sysmon);
  - derecha: omaplug, OmaScale, omafind y hyprmoncfg, y después Wi-Fi, Bluetooth, volumen y batería.
- **Plugins**: uke.serpbar, uke.bitwarden, cjkaufman.omascale, omaplug, backmeupplz.navidrome, crmne.hyprmoncfg,
  radimsem.omafind y p0werj0int.powerbar. *First-party* de Omarchy `dev`: elsewhen, dock y remote-session.
- Ninguno lleva binarios ELF. Lo que sí depende de la arquitectura está fuera de los plugins:
  - `/usr/bin/hyprmoncfg` (paquete AUR `hyprmoncfg-bin`, Go);
  - el `llama-server` de omafind, que se compila en cada máquina.

## 2. Copia de seguridad (antes de tocar nada)

`deploy.sh backup` hace un tar de `shell.json`, `plugins/`, el estado de serpbar y serpantinum y `current/`.
- En la tablet: `~omarchy/.local/share/uke-plugins/barra-20261022-213430.tar.gz`.
- En el PC: `~/backups/uke-barra-20261022-213430/`.
- Las dos copias tienen el mismo sha256, `64be86345f53…`.
- Para volver: `deploy.sh revert`.

## 3. Paquetes (ALARM `extra`, con `pacman -S --print` antes)

- **Instalados**: `cava` 1.0.0, `ddcutil` 3.0.2 (con `i2c-tools`), `matugen` 4.2.0, `wf-recorder` 0.6.0 y `xdg-terminal-exec` 0.14.3.
  - Son nuevos y no actualizan nada.
  - El hook de `ddcutil` deja `i2c-dev` en `modules-load.d`. No se cargó ningún módulo (`lsmod`) y dmesg quedó limpio.
- **No instalado**: `gpu-screen-recorder`, que da 404 en los 5 espejos. No hice `-Sy` para no actualizar a medias.
- **`hyprmoncfg-bin` 1.24.0** (la misma versión que el portátil):
  - Paquete local construido con `makepkg` en la tablet desde `serpbar-tablet/hyprmoncfg-bin/PKGBUILD`, una copia del AUR fijada a la 1.24.0.
  - Usa el tarball oficial `linux_arm64` con sha256 `e0d308d3…` (sacado del `checksums.txt` de la release).
  - Binarios Go estáticos para aarch64. El daemon `hyprmoncfgd` está **sin activar** (ver dudas).

## 4. Copia y adaptación (`deploy.sh apply`)

**Copiado tal cual:**
- los plugins serpbar, hyprmoncfg y omafind;
- `~/.config/omarchy/serpbar/` y `~/.config/serpantinum`, y el estado `~/.local/state/{omarchy/serpbar,serpantinum}`;
- `backgrounds/catppuccin` y `~/Wallpapers`, con el enlace `current/background` apuntando al mismo fondo;
- las rutas `~` cambiadas a `/home/omarchy`.
- Sin credenciales: el script se niega si encuentra `token/password/secret/apikey`.

**`shell.json`** (`merge-shell.py`):
- `bar` entero del portátil;
- los widgets de la tablet añadidos al layout para que sigan activos: `uke.launcher`, `uke.bateria`, `omarkyy.tablet`, `uke.navidrome`;
- `omarchy.network` → `uke.network` (Wi-Fi con QR) y `omarchy.elsewhen` → `uke.elsewhen` (en español, °C, 24 h);
- los ajustes de omafind con las carpetas de la tablet, y el `dock` del portátil (inerte en la tablet);
- **`idle` de la tablet**, sin tocar: es de la sesión de batería.

**Adaptaciones** (`adapt-serpbar.py`, idempotente, marca `uke-tablet`):
- **Widgets de la tablet como módulos de serpbar**, cada uno con su icono y la acción de su botón de Omarchy: lanzador, teclado,
  Bitwarden (candado abierto o cerrado), Wi-Fi QR y batería exacta (icono de perfil y vatios). Van en un grupo nuevo a la derecha.
- **Ancho.** La tablet tiene 1600 px lógicos (escala 2) frente a 1920. Con todo dentro, el grupo derecho tapaba el reloj y los indicadores.
  Medido con capturas en 5 iteraciones, el resultado es:
  - altura 42 (el portátil, 40; 48 y 44 no cabían);
  - 5 escritorios en vez de 8;
  - música a `mediaWidth` 80, el mínimo de su deslizador;
  - nombres de Wi-Fi y Bluetooth recortados a 96 px;
  - vatios sin % en la batería exacta.
- **Bluetooth**: serpbar detectaba «sobremesa» con `ls /sys/class/power_supply/BAT*` y escondía la píldora. La batería de la tablet
  se llama `battery`, así que ahora se busca cualquier `type=Battery` (BtFace y WifiFace).

## 5. Comparativa y pruebas

- `capturas-barra-portatil-20261022/barras-lado-a-lado.png`: la barra del portátil a 1920 px y la de la tablet a 1600 px lógicos.
  Mismo estilo, colores, fuentes, píldoras y orden. Diferencias: 5 escritorios, el grupo de la tablet, nombres más cortos y los iconos de bandeja de cada equipo.
- `pantallas-lado-a-lado.png`: las dos pantallas completas.
- **Toques** (uinput + `grim`; `mosaico-toques-19.png`). Abren con el dedo:
  - ajustes, búsqueda y música (guía de serpantinum);
  - Navidrome (formulario de conexión);
  - reloj (calendario y el tiempo: 15 °C en Pontevedra);
  - sysmon (CPU, RAM y temperatura);
  - omaplug, OmaScale y el asistente de omafind;
  - lanzador, teclado, Bitwarden y Wi-Fi QR (panel de Omarchy);
  - Wi-Fi, Bluetooth y volumen (paneles de serpantinum) y el panel de batería.
- La batería exacta cambia el perfil: devuelto a «ahorro».
- hyprmoncfg abre su panel, pero vacío (sin daemon).
- Journal de la shell: solo bucles de binding de serpbar (también en el portátil), lecturas de cachés que no existían aún y
  `PowerProfilesDaemon` ausente (la tablet usa `uke-perfil`). No hay errores de carga.

## 6. Incidente

A las 21:44:43 cerré la sesión gráfica con el segundo toque de la prueba de batería: el panel lateral se abre encima de la píldora
y su botón «Logout» queda justo debajo.
- **Se perdió**: Firefox, Nextcloud y el `notas_sync` en curso.
- **Recuperación** (21:46, con turno): `systemctl restart sddm`. La GPU ya estaba abierta por el saludo, así que no era el primer arranque de riesgo. El autologin volvió (sesión 1291, tty1).
- **Vuelve solo**: `notas-sync.timer` relanza la sincronización cada 2 min, y Nextcloud y udiskie arrancan desde el autostart.
- **Avisos**: sesión principal y, por el panel restaurado abierto, immich-sp-re.
- **Duda 1**: confirmación en «Logout».

## 7. Pendiente

- omafind: `deploy.sh omafind` (compila `llama-server` en la tablet, desprendido y con `nice`) y `deploy.sh omafind-roots`. Necesita turno.
- Las decisiones del dueño: «Logout», `hyprmoncfgd` y altura 42 frente a 48.
