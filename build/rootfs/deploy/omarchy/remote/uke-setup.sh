#!/bin/bash
# uke-setup.sh <pre|post|undo> -- corre EN LA TABLET (root). Lo envia deploy.sh por `ssh 'cat > ...'`.
#
#   pre   ANTES de instalar paquetes: gates (aarch64, RAM, espacio), copia de /etc, lista de paquetes, hooks
#         de mkinitcpio neutralizados, home de alarm arreglado.
#   post  DESPUES de instalar: usuario del escritorio, autologin sddm (Session=omarchy, como L57), PAM como
#         upstream, wrappers offline de Omarchy, migraciones selladas, servicio sddm habilitado.
#   undo  deshace SOLO la configuracion (autologin, enable, wrappers). No desinstala paquetes ni borra usuarios.
#
# Variables (las pone deploy.sh): RD DESKTOP_USER SUDO_NOPASSWD BOOT_DESKTOP ROOT (solo para pruebas en el PC).
# Todo es idempotente; cada paso imprime OK / SKIP / WARN / FALLO.
set -uo pipefail
ROOT=${ROOT:-}
RD=${RD:-/root/uke-omarchy}
U=${DESKTOP_USER:-omarchy}
SUDO_NOPASSWD=${SUDO_NOPASSWD:-0}
BOOT_DESKTOP=${BOOT_DESKTOP:-0}
MIN_MEM_KB=${MIN_MEM_KB:-6000000}      # la L57 solo fue estable con 7,2 GiB (mem=2048M => OOM); con 1,6 GiB no se instala
MIN_FREE_MB=${MIN_FREE_MB:-2800}       # netos ~1,8 GiB + tandas en transito + margen
BK=$ROOT/var/backups/uke-omarchy
rc=0
ok() { printf '  OK     %s\n' "$*"; }
skip() { printf '  SKIP   %s\n' "$*"; }
warn() { printf '  WARN   %s\n' "$*"; }
fail() { printf '  FALLO  %s\n' "$*"; rc=1; }
die() { printf '  ABORTA %s\n' "$*"; exit 2; }
sec() { printf '\n== %s ==\n' "$*"; }

pre() {
  sec "pre: gates"
  [ "$(uname -m)" = aarch64 ] || die "no es aarch64"
  [ "$(id -u)" = 0 ] || [ -n "$ROOT" ] || die "hay que ser root"
  local mem free
  mem=$(awk '/MemTotal/{print $2}' "$ROOT/proc/meminfo" 2>/dev/null || echo 0)
  if [ "${mem:-0}" -lt "$MIN_MEM_KB" ]; then
    [ "${FORCE_LOWMEM:-0}" = 1 ] && warn "MemTotal ${mem} kB < ${MIN_MEM_KB} (FORCE_LOWMEM=1)" || die "MemTotal ${mem} kB < ${MIN_MEM_KB}: Hyprland+quickshell mueren por OOM (D16/L57). Quita mem=2048M del cmdline."
  else ok "MemTotal $((mem / 1024)) MiB"; fi
  free=$(df -Pm "$ROOT/" | awk 'NR==2{print $4}')
  [ "$free" -ge "$MIN_FREE_MB" ] && ok "libres ${free} MiB (>= $MIN_FREE_MB)" || die "libres ${free} MiB < $MIN_FREE_MB MiB"
  if grep -q 'mem=2048M' "$ROOT/proc/cmdline" 2>/dev/null; then die "cmdline lleva mem=2048M"; fi
  [ -e "$ROOT/var/lib/pacman/db.lck" ] && warn "db.lck presente (se limpia en la tanda si no hay pacman vivo)"

  sec "pre: copia de seguridad"
  mkdir -p "$BK" "$RD/log" "$RD/state" "$RD/pkgs"
  local ts; ts=$(date +%Y%m%d-%H%M%S)
  tar -C "$ROOT/" -czf "$BK/etc-$ts.tar.gz" etc 2>/dev/null && ok "etc -> $BK/etc-$ts.tar.gz" || warn "tar de /etc fallo"
  if command -v pacman >/dev/null 2>&1; then
    pacman -Qq >"$RD/pkg-antes.txt" 2>/dev/null && ok "pkg-antes.txt ($(wc -l <"$RD/pkg-antes.txt") paquetes registrados)"
  fi

  sec "pre: hooks de pacman que NO aplican a la uke"
  # El kernel viaja en boot.img (initramfs embebido): /boot esta vacio y mkinitcpio -P solo da errores.
  # plymouth instala usr/lib/initcpio/* y dispararia 90-mkinitcpio-install.hook en cada tanda.
  # Un enlace a /dev/null en /etc/pacman.d/hooks anula el hook del mismo nombre (mecanismo documentado de alpm-hooks(5)).
  mkdir -p "$ROOT/etc/pacman.d/hooks"
  for h in 90-mkinitcpio-install.hook 60-mkinitcpio-remove.hook; do
    ln -sfn /dev/null "$ROOT/etc/pacman.d/hooks/$h" && ok "hook $h anulado"
  done

  sec "pre: home de alarm"
  # El rootfs v8 trae /home/alarm como root:root 0700 (visto tambien el 14-oct): sin esto la sesion de alarm no puede escribir.
  if [ -d "$ROOT/home/alarm" ] && getent passwd alarm >/dev/null 2>&1; then
    if [ "$(stat -c %u "$ROOT/home/alarm")" != "$(id -u alarm)" ]; then
      chown -R alarm:alarm "$ROOT/home/alarm" && ok "chown -R alarm:alarm /home/alarm"
    else skip "/home/alarm ya es de alarm"; fi
  fi
  sec "pre: la red de rescate no se toca"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl is-active systemd-networkd >/dev/null 2>&1 && ok "systemd-networkd activo (usb0 192.168.42.129 = el SSH)" || warn "systemd-networkd NO activo"
    systemctl is-enabled NetworkManager >/dev/null 2>&1 && warn "NetworkManager esta enabled: gestionaria usb0 y cortaria el SSH" || ok "NetworkManager no habilitado (NO se habilita: sin WiFi, y compite con networkd por usb0)"
  fi
  return "$rc"
}

seal_migrations() {
  # Misma semantica que upstream: el marcador por migracion (omarchy-migrate: "si no existe el marcador, corre").
  # Un usuario NUEVO nace sellado por /etc/skel (el paquete omarchy trae las 106 semillas). Para un usuario anterior
  # (alarm) se crean aqui. Offline NO se ejecuta ninguna: 1781984677 (snapper) fallaria seguro y atascaria
  # omarchy-migrate y cada `omarchy update`; ~25 hacen `omarchy-pkg-add` y sin red abortarian la tanda entera.
  local u=$1 home gid n=0 f b sd
  home=$(getent passwd "$u" | cut -d: -f6); gid=$(id -g "$u")
  sd="$ROOT$home/.local/state/omarchy/migrations"
  install -d -o "$u" -g "$gid" -m 755 "$ROOT$home/.local/state" "$ROOT$home/.local/state/omarchy" "$sd"
  for f in "$ROOT"/usr/share/omarchy/migrations/*.sh; do
    [ -f "$f" ] || continue
    b=${f##*/}
    [ -e "$sd/$b" ] && continue
    install -o "$u" -g "$gid" -m 644 /dev/null "$sd/$b" && n=$((n + 1))
  done
  ok "migraciones: $n marcadores creados ($(ls "$sd" | wc -l) en total de $(ls "$ROOT"/usr/share/omarchy/migrations/*.sh | wc -l))"
  # Las que SI interesaria ejecutar cuando haya red (borrar su marcador y correr `omarchy-migrate` como el usuario):
  #   1781793381 udiskie | 1782002156 NM (OJO: retira networkd; solo con perfil usb0 en NM) | 1784568652 mask NM-wait-online
  #   1784914435 wifi powersave off | 1788124236 sshd hardening (verificar authorized_keys ANTES)
}

post() {
  sec "post: paquetes imprescindibles"
  local p miss=0
  for p in omarchy omarchy-settings omarchy-keyring hyprland quickshell sddm uwsm mesa xdg-desktop-portal-hyprland pipewire wireplumber; do
    pacman -Q "$p" >/dev/null 2>&1 || { fail "falta $p"; miss=1; }
  done
  [ "$miss" = 0 ] && ok "todos presentes" || die "instala primero (deploy.sh install all)"

  sec "post: usuario $U"
  if getent passwd "$U" >/dev/null; then skip "ya existe ($(id "$U"))"; else
    useradd -m -s /bin/bash -c "Omarchy" "$U" && ok "useradd -m $U (hereda /etc/skel de omarchy-settings: hypr/*.lua, shell.json, semillas)" || { fail "useradd"; return 2; }
  fi
  local g
  for g in wheel video render input audio; do
    getent group "$g" >/dev/null && usermod -aG "$g" "$U" 2>/dev/null
  done
  ok "grupos: $(id -nG "$U")"
  if [ "$(stat -c %U "$ROOT/home/$U" 2>/dev/null)" != "$U" ]; then chown -R "$U:$U" "$ROOT/home/$U" && ok "home de $U corregido"; fi
  # Usuario ya existente (p.ej. DESKTOP_USER=alarm, el de L57): no hereda /etc/skel; copia SIN pisar lo suyo.
  if [ ! -f "$ROOT/home/$U/.config/hypr/hyprland.lua" ]; then
    cp -rn "$ROOT"/etc/skel/. "$ROOT/home/$U/" && chown -R "$U:$(id -g "$U")" "$ROOT/home/$U" && ok "skel de omarchy-settings copiado a /home/$U (sin pisar)"
  fi
  seal_migrations "$U"

  sec "post: sddm (autologin como L57)"
  install -d "$ROOT/etc/sddm.conf.d"
  # 20-: despues de 10-theme.conf y 10-wayland.conf de omarchy-settings (que NO se tocan).
  cat >"$ROOT/etc/sddm.conf.d/20-uke-autologin.conf" <<EOF
# uke: autologin del escritorio Omarchy (misma receta que L57: Session=omarchy; sddm busca
# omarchy.desktop en /usr/local/share/wayland-sessions, ruta que trae omarchy-settings).
[Autologin]
User=$U
Session=omarchy
Relogin=false
EOF
  ok "/etc/sddm.conf.d/20-uke-autologin.conf (User=$U Session=omarchy)"
  if [ -f "$ROOT/usr/local/share/wayland-sessions/omarchy.desktop" ]; then
    ok "omarchy.desktop: $(grep '^Exec=' "$ROOT/usr/local/share/wayland-sessions/omarchy.desktop")"
  else fail "falta /usr/local/share/wayland-sessions/omarchy.desktop (lo trae omarchy-settings)"; fi
  # Upstream (install/login/sddm.sh): quitar pam_gnome_keyring de /etc/pam.d/sddm (login con password); el autologin no lo usa.
  if [ -f "$ROOT/etc/pam.d/sddm" ] && grep -q 'pam_gnome_keyring' "$ROOT/etc/pam.d/sddm"; then
    sed -i -e '/-auth.*pam_gnome_keyring\.so/d' -e '/-password.*pam_gnome_keyring\.so/d' "$ROOT/etc/pam.d/sddm" && ok "pam.d/sddm: keyring del greeter fuera (como upstream)"
  else skip "pam.d/sddm ya limpio"; fi

  sec "post: wrappers offline de Omarchy (PATH: /usr/local/bin precede a /usr/bin; /usr/bin intacto)"
  install -d "$ROOT/usr/local/bin" "$ROOT/usr/local/sbin"
  [ -f "$RD/files/omarchy-pkg-add" ] && install -m 0755 "$RD/files/omarchy-pkg-add" "$ROOT/usr/local/bin/omarchy-pkg-add" && ok "omarchy-pkg-add tolerante (nombre irresoluble => aviso, no aborta migrate/update)" || warn "falta files/omarchy-pkg-add"
  [ -f "$RD/files/omarchy-update-restart" ] && install -m 0755 "$RD/files/omarchy-update-restart" "$ROOT/usr/local/bin/omarchy-update-restart" && ok "omarchy-update-restart (kernel externo = boot.img: sin prompt de reinicio eterno)" || warn "falta files/omarchy-update-restart"
  [ -f "$RD/files/seal-migrations-uke.sh" ] && install -m 0755 "$RD/files/seal-migrations-uke.sh" "$ROOT/usr/local/bin/seal-migrations-uke" && ok "seal-migrations-uke (para cuando haya red: ejecuta lo util, sella lo que no)" || true
  [ -f "$RD/session.sh" ] && install -m 0755 "$RD/session.sh" "$ROOT/usr/local/sbin/uke-session" && ok "uke-session (start/stop/status/shot/gpu-mode)" || true

  if [ "$SUDO_NOPASSWD" = 1 ]; then
    install -d "$ROOT/etc/sudoers.d"
    printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$U" >"$ROOT/etc/sudoers.d/90-uke-$U" && chmod 0440 "$ROOT/etc/sudoers.d/90-uke-$U" && ok "sudo sin password para $U (SUDO_NOPASSWD=1; el usuario no tiene password)"
  else skip "sudo: $U sin password y sin regla (administra root por SSH; SUDO_NOPASSWD=1 para abrirlo)"; fi

  sec "post: servicios"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable sddm.service >/dev/null 2>&1 && ok "sddm.service enabled (alias display-manager)" || fail "systemctl enable sddm"
    systemctl daemon-reload >/dev/null 2>&1 || true
    local def; def=$(systemctl get-default 2>/dev/null)
    ok "default.target = $def ; el cmdline del boot.img trae systemd.unit=multi-user.target => sddm NO arranca solo salvo uke-desktop.service (deploy/arranque; boot-desktop on) o uke-session start"
    systemctl is-enabled NetworkManager >/dev/null 2>&1 && warn "NetworkManager enabled (revisa: compite con networkd por usb0)" || ok "NetworkManager sigue sin habilitar"
    boot_desktop "$BOOT_DESKTOP"
  fi
  return "$rc"
}

boot_desktop() {
  # 18-oct: el escritorio al arranque ya NO es un enlace directo sddm -> multi-user.target (no tenia interruptor
  # de seguridad). Ahora lo hace uke-desktop.service (build/rootfs/deploy/arranque: ordenado tras uke-carga y
  # uke-wifi, interruptores /etc/uke/no-desktop|safe-mode, guarda uke-bootguard). Esta funcion solo lo (des)habilita.
  local want=$1 old=$ROOT/etc/systemd/system/multi-user.target.wants/sddm.service
  local new=$ROOT/etc/systemd/system/multi-user.target.wants/uke-desktop.service
  [ -L "$old" ] && { rm -f "$old"; ok "retirado el enlace antiguo multi-user.target.wants/sddm.service (sin interruptor de seguridad)"; }
  if [ "$want" = 1 ]; then
    if [ -f "$ROOT/etc/systemd/system/uke-desktop.service" ] && [ -x "$ROOT/usr/local/sbin/uke-bootguard" ]; then
      mkdir -p "$ROOT/etc/systemd/system/multi-user.target.wants"
      ln -sfn /etc/systemd/system/uke-desktop.service "$new" && ok "uke-desktop.service enabled: sddm arrancara en el arranque (apagarlo: touch /etc/uke/no-desktop)"
    else
      warn "faltan uke-desktop.service/uke-bootguard: ejecuta build/rootfs/deploy/arranque/deploy.sh apply --go (BOOT_DESKTOP=1 no hace nada sin ellos)"
    fi
  else
    [ -L "$new" ] && { rm -f "$new"; ok "uke-desktop.service ya no cuelga de multi-user.target"; } || skip "el escritorio no arranca solo (arranque manual con uke-session start)"
  fi
}

undo() {
  sec "undo: solo configuracion"
  rm -f "$ROOT/etc/sddm.conf.d/20-uke-autologin.conf" && ok "autologin fuera"
  boot_desktop 0
  command -v systemctl >/dev/null 2>&1 && { systemctl stop sddm.service 2>/dev/null; systemctl disable sddm.service >/dev/null 2>&1; ok "sddm parado y disabled"; }
  rm -f "$ROOT/usr/local/bin/omarchy-pkg-add" "$ROOT/usr/local/bin/omarchy-update-restart" "$ROOT/usr/local/bin/seal-migrations-uke" "$ROOT/usr/local/sbin/uke-session" && ok "wrappers fuera"
  rm -f "$ROOT/etc/sudoers.d/90-uke-$U"
  skip "paquetes y usuario $U se dejan (userdel -r $U / pacman -Rns a mano; rollback del sistema = reflash de la imagen con sha conocido)"
}

case "${1:-}" in
  pre) pre ;;
  post) post ;;
  undo) undo ;;
  boot-desktop) boot_desktop "${2:-0}" ;;
  *) sed -n '2,12p' "$0"; exit 1 ;;
esac
exit "$rc"
