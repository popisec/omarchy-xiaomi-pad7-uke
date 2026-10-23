# T3 — teclado en pantalla (squeekboard) en la uke
Informe: `build/gates/revision/T3-OSK-20261018.md`.

- `deploy.sh status|apply|revert` — instala squeekboard, unidad de usuario `uke-osk.service` (en `/etc/systemd/user`, habilitada para `omarchy`), gsettings (OSK activado, fuente `es`), enmascara `omarchy-fcitx5.service`. No toca autostart.lua/bindings.lua/boot.
- `root/usr/local/bin/uke-osk-toggle [toggle|show|hide|status]` — D-Bus `sm.puri.OSK0` (`SetVisible b`, propiedad `Visible`). Funciona como root por SSH (reejecuta como omarchy). Para barra/gesto: invocar `uke-osk-toggle` (equivale a `busctl --user call sm.puri.OSK0 /sm/puri/OSK0 sm.puri.OSK0 SetVisible b true|false`).
- Layout español: viene incrustado en squeekboard (`es_wide`, con ñ y tecla Áá para acentos); no hace falta layout propio.
