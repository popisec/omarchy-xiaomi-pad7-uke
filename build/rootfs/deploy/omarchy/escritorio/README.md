# Barra y tema del escritorio del dueño copiados a la tablet (18-oct-2026)

Origen: `~/.omarchy-home/.config/omarchy/` del PC (Omarchy dev 4a9c83d, 17-oct). Destino: `/home/omarchy/.config/omarchy/`
(copia previa: `/root/omarchy-config-antes-escritorio-<epoch>.tgz` en la tablet).
- Plugins (QML/scripts, sin binarios ELF; sin los `.bak`): p0werj0int.powerbar 0.9.6 (barra "islands", grande, animaciones,
  sombras, bordes 12), omaplug 1.6.6, radimsem.omafind 0.5.1, crmne.hyprmoncfg 2.9.0, cjkaufman.omascale 1.0.0,
  backmeupplz.navidrome 0.2.1. No se copian al repo (terceros, ~60 MB).
- Tema catppuccin (overlay de themes/), backgrounds/, shell.toml (fuente 14) y `shell.json` = el del PC con:
  `idle.lock = 31536000` (sin contraseña/teclado), sin `dock` ni `omarchy.elsewhen` (no existen en Omarchy 4.0.4 de la tablet).
- `omarchy theme set catppuccin` + `omarchy restart shell` (como omarchy con el entorno de quickshell).
- Arreglos necesarios: `qt6-imageformats` (Qt no abría los fondos .webp → fondo negro); pacman: keyring inicializado
  (archlinuxarm + omarchy) y `DisableSandbox` en pacman.conf (el kernel no tiene Landlock).
- Avisos del log tras el cambio: nulls de arranque en paneles, IPC duplicados y `Bar.qml[2002] Cannot assign [undefined]`
  (posible diferencia dev↔4.0.4); la barra se ve bien. fcitx5 no instalado (omarchy-fcitx5.service falla en bucle).
- **El dueño confirma que la barra se ve bien en la tablet (18-oct ~10:50).**
