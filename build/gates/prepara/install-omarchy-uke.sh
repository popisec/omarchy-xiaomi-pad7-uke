#!/usr/bin/env bash
# install-omarchy-uke.sh — instala Omarchy 4 (Hyprland + Quickshell) en el rootfs Arch ARM
# de la Xiaomi Pad 7 "uke", prepara la sesion sin greeter, el teclado en pantalla y los
# arreglos ARM. Pensado para ejecutarse EN LA TABLET (por SSH), NO en el PC.
#
#   Uso:  ./install-omarchy-uke.sh                 # dry-run (por defecto, NO toca nada)
#         sudo ./install-omarchy-uke.sh --go       # ejecuta (pide confirmacion en cada paso)
#         sudo ./install-omarchy-uke.sh --go --noconfirm   # sin preguntas (bajo tu riesgo)
#
#   Flags: --go | --dry-run | --noconfirm | --with-aur | --skip-gate | --skip-net
#          --user <nombre> | --help
#
# Prerrequisitos:
#   1. e2fsck EN FRIO sobre userdata (el ext4 esta podrido; ESTADO-VIVO/F0). El script
#      aborta si dmesg declara errores EXT4 (--skip-gate para forzar, bajo tu responsabilidad).
#   2. Internet en la tablet (WiFi F3 o el gadget con NAT) hacia pkgs.omarchy.org y el mirror
#      de ALARM. El script lo comprueba.
#   3. Este script NO toca boot.img/dtbo: la vuelta atras de userspace es el .gz del rootfs.
#
# Idempotente: cada paso se guarda con un chequeo (pacman -Qq, cmp de ficheros, grep).
# Ver memoria: build/gates/prepara/P6-omarchy-install.md

set -euo pipefail

# ---------------------------------------------------------------------------
# Constantes (verificadas 29-sep-2026; reverificar si falla -> P6 §9)
# ---------------------------------------------------------------------------
OMARCHY_REPO="https://pkgs.omarchy.org/edge/\$arch"
OMARCHY_KEY_FP="40DFB630FF42BCFFB047046CF0134EE680CAC571"
OMARCHY_KEYRING_PKG="omarchy-keyring-20251027-1-any.pkg.tar.zst"
OMARCHY_KEYRING_URL="https://pkgs.omarchy.org/edge/aarch64/${OMARCHY_KEYRING_PKG}"

MIRRORLIST_CONTENT='Server = http://fl.us.mirror.archlinuxarm.org/$arch/$repo
Server = http://nj.us.mirror.archlinuxarm.org/$arch/$repo
Server = http://ca.us.mirror.archlinuxarm.org/$arch/$repo
Server = http://de.mirror.archlinuxarm.org/$arch/$repo
Server = http://mirror.archlinuxarm.org/$arch/$repo'

# Nucleo (trae hyprland/quickshell/uwsm/sddm/sddm deshabilitado por dependencias)
CORE_PKGS=(omarchy-keyring omarchy-settings omarchy)
# Sesion minima + OSK + fuentes + herramientas de prueba (P6 §3)
EXTRA_PKGS=(
  hyprland quickshell uwsm xdg-desktop-portal-hyprland
  pipewire wireplumber pipewire-pulse pipewire-alsa gnome-keyring
  foot xdg-terminal-exec
  noto-fonts ttf-dejavu noto-fonts-emoji
  squeekboard
  brightnessctl pamixer upower wl-clipboard wtype
  bluez bluez-utils sudo
  mesa-utils wayland-utils vulkan-tools vulkan-freedreno glmark2
  grim slurp wlr-randr strace htop
)
AUR_PKGS=(yay base-devel)

DRY_RUN=1
ASSUME_YES=0
WITH_AUR=0
SKIP_GATE=0
SKIP_NET=0
TARGET_USER="omarchy"
UKE_EXT4_MAX_ERRORS="${UKE_EXT4_MAX_ERRORS:-0}"

BK_ROOT="/var/backups/uke"
STAMP="$(date +%Y%m%d-%H%M%S)"
BK_DIR="${BK_ROOT}/${STAMP}"
LOG_FILE="/var/log/uke-install.log"
BOOTSTRAP_DIR="/var/tmp/uke-bootstrap"
SHARE_DIR="/usr/local/share/uke"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
say()  { printf '%s\n' "$*"; }
log()  { printf '[uke] %s\n' "$*"; }
warn() { printf '[uke][AVISO] %s\n' "$*" >&2; }
die()  { printf '[uke][ABORT] %s\n' "$*" >&2; exit 1; }

dry() { [ "$DRY_RUN" -eq 1 ]; }

# Ejecuta (o imprime en dry-run) un comando.
RUN() {
  if dry; then
    printf '[dry-run] '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@" || return $?
  fi
}

# Escribe un fichero desde stdin solo si su contenido cambia. Uso:
#   ensure_file 644 /ruta <<'EOF' ... EOF
ensure_file() {
  local mode="$1" dest="$2" tmp
  tmp="$(mktemp)"
  cat >"$tmp"
  if [ -e "$dest" ] && cmp -s "$dest" "$tmp"; then
    log "sin cambios: $dest"
    rm -f "$tmp"
    return 0
  fi
  if dry; then
    log "[dry-run] escribiria $dest (modo $mode)"
    rm -f "$tmp"
    return 0
  fi
  install -D -m "$mode" "$tmp" "$dest"
  rm -f "$tmp"
  log "escrito: $dest"
}

usage() {
  sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --go)        DRY_RUN=0 ;;
    --dry-run)   DRY_RUN=1 ;;
    --noconfirm) ASSUME_YES=1 ;;
    --with-aur)  WITH_AUR=1 ;;
    --skip-gate) SKIP_GATE=1 ;;
    --skip-net)  SKIP_NET=1 ;;
    --user)      shift; TARGET_USER="${1:?--user necesita un nombre}" ;;
    -h|--help)   usage ;;
    *)           die "opcion desconocida: $1 (usa --help)" ;;
  esac
  shift
done

pacman_do() {
  # pacman interactivo por defecto; --noconfirm solo si se pidio
  if [ "$ASSUME_YES" -eq 1 ]; then
    RUN env OMARCHY_ALLOW_DIRECT_PACMAN=1 pacman "$@" --noconfirm
  else
    RUN env OMARCHY_ALLOW_DIRECT_PACMAN=1 pacman "$@"
  fi
}

want() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# PASO 0 — Gates
# ---------------------------------------------------------------------------
step_gate() {
  say ""
  log "== PASO 0: gates =="

  local arch; arch="$(uname -m)"
  if [ "$arch" != "aarch64" ]; then
    if dry; then
      warn "uname -m = $arch (no es aarch64). En dry-run se continua; con --go se aborta."
    else
      die "esto no es aarch64 ($arch): parece el PC, no la tablet."
    fi
  else
    log "arquitectura: aarch64 OK"
  fi

  [ -r /etc/os-release ] && log "sistema: $(grep -E '^PRETTY_NAME' /etc/os-release | cut -d= -f2-)"
  [ -d "/usr/lib/modules/$(uname -r)" ] || warn "no existe /usr/lib/modules/$(uname -r) (¿kernel correcto?)"

  # Gate EXT4 (P6 §8)
  local errs=0
  if want dmesg; then
    errs="$(dmesg --level=err,warn 2>/dev/null | grep -c 'EXT4-fs error' || true)"
  fi
  log "errores EXT4 en dmesg: ${errs} (umbral ${UKE_EXT4_MAX_ERRORS})"
  if [ "${errs:-0}" -gt "${UKE_EXT4_MAX_ERRORS}" ]; then
    if [ "$SKIP_GATE" -eq 1 ]; then
      warn "GATE EXT4 SUPERADO (${errs} > ${UKE_EXT4_MAX_ERRORS}) pero se continua por --skip-gate"
    else
      die "disco podrido: ${errs} errores EXT4. e2fsck EN FRIO primero (o --skip-gate consciente)."
    fi
  fi

  local fstype optsfirst
  fstype="$(findmnt -no FSTYPE / 2>/dev/null || echo '?')"
  optsfirst="$(findmnt -no OPTIONS / 2>/dev/null | awk -F, '{print $1}')"
  log "raiz: fstype=${fstype} opciones=$(findmnt -no OPTIONS / 2>/dev/null || echo '?')"
  case "$optsfirst" in
    ro) die "la raiz esta montada en solo-lectura; remonta rw antes de instalar" ;;
  esac

  local free_mb; free_mb="$(df -Pm / | awk 'NR==2{print $4}')"
  log "espacio libre en /: ${free_mb} MiB"
  [ "${free_mb:-0}" -ge 4096 ] || warn "menos de 4 GiB libres: pacman puede fallar"

  # Red (necesaria para repos)
  if [ "$SKIP_NET" -eq 0 ]; then
    if want curl; then
      local code
      code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 https://pkgs.omarchy.org/edge/aarch64/omarchy.db 2>/dev/null || echo 000)"
      if [ "$code" = "200" ]; then
        log "red: pkgs.omarchy.org 200 OK"
      else
        warn "red: pkgs.omarchy.org devolvio ${code}"
        dry || die "sin red hacia pkgs.omarchy.org (usa --skip-net para omitir la comprobacion)"
      fi
      code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 http://fl.us.mirror.archlinuxarm.org/aarch64/core/core.db 2>/dev/null || echo 000)"
      log "red: mirror ALARM devolvio ${code}"
      [ "$code" = "200" ] || { dry || die "sin red hacia el mirror de ALARM (--skip-net para omitir)"; }
    else
      warn "no hay curl instalado; no puedo comprobar la red"
    fi
  fi
}

# ---------------------------------------------------------------------------
# PASO 1 — Backup
# ---------------------------------------------------------------------------
step_backup() {
  say ""
  log "== PASO 1: backup del estado previo =="
  if ! dry; then
    mkdir -p "$BK_DIR"
    pacman -Qqe >"${BK_DIR}/pacman-Qqe.txt" 2>/dev/null || warn "pacman -Qqe fallo"
    cp -a /etc/pacman.conf "${BK_DIR}/pacman.conf.orig" 2>/dev/null || true
    cp -a /etc/pacman.d/mirrorlist "${BK_DIR}/mirrorlist.orig" 2>/dev/null || true
    tar czf "${BK_DIR}/etc.tar.gz" --exclude='./pacman.d/gnupg' -C / etc 2>/dev/null || warn "tar de /etc fallo"
    dmesg >"${BK_DIR}/dmesg-before.txt" 2>/dev/null || true
    log "backup en ${BK_DIR}"
    # puntero estable para el hook pre-refresh-pacman
    ln -sfn "$BK_DIR" "${BK_ROOT}/latest"
  else
    log "[dry-run] crearia ${BK_DIR}/{pacman-Qqe.txt,etc.tar.gz,pacman.conf.orig,mirrorlist.orig,dmesg-before.txt}"
  fi
}

# ---------------------------------------------------------------------------
# PASO 2 — pacman.conf + mirrorlist
# ---------------------------------------------------------------------------
step_repos() {
  say ""
  log "== PASO 2: repos (ALARM + omarchy edge/aarch64) =="

  ensure_file 644 /etc/pacman.conf <<'EOF'
# /etc/pacman.conf — uke (Arch Linux ARM + repo Omarchy edge/aarch64)
# Escrito por install-omarchy-uke.sh. Backup del original en /var/backups/uke/<fecha>/
[options]
HoldPkg     = pacman glibc
Architecture = aarch64
CheckSpace
ParallelDownloads = 5
DownloadUser = alpm

SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional

# uke: el kernel viaja en boot.img (7.2.0-rc2-palawan+), no como paquete.
# Ignorarlo evita que un -Syu traiga linux-aarch64 7.2.8 y dispare mkinitcpio -P
# (esta imagen no tiene /boot/Image y Omarchy deja un drop-in con hook plymouth).
IgnorePkg = linux-aarch64 linux-aarch64-headers

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[alarm]
Include = /etc/pacman.d/mirrorlist

[aur]
Include = /etc/pacman.d/mirrorlist

# Omarchy edge/aarch64 (el nucleo del escritorio SOLO existe en edge, no en stable).
# Va el ULTIMO a proposito: con nombres duplicados (hyprland, aquamarine, hyprtoolkit,
# quickshell-git) gana ALARM, el stack verificado en el informe C §4.
# El .db no tiene .sig (404) -> DatabaseOptional; los paquetes SI van firmados.
[omarchy]
SigLevel = Required DatabaseOptional
Server = https://pkgs.omarchy.org/edge/$arch
EOF

  ensure_file 644 /etc/pacman.d/mirrorlist <<EOF
# uke-arch (29-sep-2026: fl.us/nj.us/ca.us/de 200; el redirector va detras)
${MIRRORLIST_CONTENT}
EOF

  # copia estable para el hook pre-refresh-pacman de Omarchy (que reescribe el conf a x86)
  if dry; then
    log "[dry-run] copiaria /etc/pacman.conf y /etc/pacman.d/mirrorlist a ${SHARE_DIR}/ (para el hook)"
  else
    install -D -m 644 /etc/pacman.conf "${SHARE_DIR}/pacman.conf"
    install -D -m 644 /etc/pacman.d/mirrorlist "${SHARE_DIR}/mirrorlist"
    log "copias estables en ${SHARE_DIR}/"
  fi

  # A1-B2: preset de mkinitcpio apuntando a 7.1.6-1-aarch64-ARCH borrado; cualquier
  # hook 90-mkinitcpio (upgrade de mkinitcpio, plymouth) fallaria y con
  # ExitOnHookFailure (pacman >=7.1) mataria el script a mitad. El kernel viaja en
  # boot.img: nadie regenera initramfs aqui (misma razon del IgnorePkg de arriba).
  if ! dry; then
    rm -f /etc/mkinitcpio.d/linux-aarch64.preset
    log "A1-B2: /etc/mkinitcpio.d/linux-aarch64.preset eliminado (si existia)"
  else
    log "[dry-run] eliminaria /etc/mkinitcpio.d/linux-aarch64.preset"
  fi
}

# ---------------------------------------------------------------------------
# PASO 3/4 — keyrings
# ---------------------------------------------------------------------------
step_keyring() {
  say ""
  log "== PASO 3: keyring de pacman + clave de Omarchy =="

  if [ ! -d /etc/pacman.d/gnupg ]; then
    log "no hay /etc/pacman.d/gnupg: pacman-key --init"
    RUN pacman-key --init
  fi
  RUN pacman-key --populate archlinuxarm archlinux

  if pacman -Qq omarchy-keyring >/dev/null 2>&1; then
    log "omarchy-keyring ya instalado"
  else
    log "bootstrap de la clave Omarchy (huella pineada ${OMARCHY_KEY_FP})"
    RUN mkdir -p "$BOOTSTRAP_DIR"
    RUN curl -fsSL -o "${BOOTSTRAP_DIR}/${OMARCHY_KEYRING_PKG}" "$OMARCHY_KEYRING_URL"
    RUN curl -fsSL -o "${BOOTSTRAP_DIR}/${OMARCHY_KEYRING_PKG}.sig" "${OMARCHY_KEYRING_URL}.sig"
    if dry; then
      log "[dry-run] verificaria huella, pacman-key --add/--lsign-key y pacman -U ${OMARCHY_KEYRING_PKG}"
    else
      zstd -dc "${BOOTSTRAP_DIR}/${OMARCHY_KEYRING_PKG}" \
        | tar xO usr/share/pacman/keyrings/omarchy.gpg >"${BOOTSTRAP_DIR}/omarchy.gpg"
      local fp
      fp="$(gpg --show-keys --with-colons "${BOOTSTRAP_DIR}/omarchy.gpg" 2>/dev/null | awk -F: '/^fpr:/{print $10; exit}')"
      [ "$fp" = "$OMARCHY_KEY_FP" ] || die "huella de la clave Omarchy NO coincide: '$fp' != '$OMARCHY_KEY_FP'"
      log "huella verificada: $fp"
      pacman-key --add "${BOOTSTRAP_DIR}/omarchy.gpg"
      pacman-key --lsign-key "$fp"
      pacman_do -U "${BOOTSTRAP_DIR}/${OMARCHY_KEYRING_PKG}"
    fi
  fi
  # carga trusted/revoked (idempotente; tambien lo hace el .INSTALL del paquete)
  RUN pacman-key --populate omarchy
}

# ---------------------------------------------------------------------------
# PASO 5/6 — sync, simulacion y pin
# ---------------------------------------------------------------------------
step_sync_and_check() {
  say ""
  log "== PASO 5: sincronizar DBs y simular resolucion =="
  pacman_do -Sy

  # A1-B1: 42 paquetes del overlay bsdtar viven en disco SIN dueno en la DB -> el
  # -Syu/-S del cierre abortaria con "exists in filesystem". Registrarlos con
  # --overwrite (versiones identicas en ALARM hoy, verificado por A1).
  if ! dry; then
    OVERLAY_PKGS="abseil-cpp busybox chrony db5.3 duktape fake-hwclock git gtest iio-sensor-proxy libdaemon libevdev libgudev libmbim libmm-glib libndp libnewt libnm libpgm libqmi libqrtr-glib libsodium libssc libteam libwacom mobile-broadband-provider-info networkmanager nspr nss pcre pcsclite perl perl-error perl-mailtools perl-timedate polkit protobuf protobuf-c slang sudo wpa_supplicant zeromq zlib-ng"
    log "== PASO 5b: registrar overlay sin dueno (A1-B1) =="
    pacman_do -S --needed --overwrite '\*' $OVERLAY_PKGS
  fi

  if ! dry; then
    local out
    if ! out="$(env OMARCHY_ALLOW_DIRECT_PACMAN=1 pacman -Sp --print-format '%r/%n-%v' "${CORE_PKGS[@]}" "${EXTRA_PKGS[@]}" 2>&1)"; then
      printf '%s\n' "$out" >&2
      die "la resolucion de paquetes fallo (revisa repos/red); NO se instala nada"
    fi
    log "resolucion OK:"
    printf '%s\n' "$out" | sed 's/^/    /'
    printf '%s\n' "$out" >"${BK_ROOT}/resolution-${STAMP}.txt"
  else
    log "[dry-run] pacman -Sp --print-format '%r/%n-%v' ${CORE_PKGS[*]} ${EXTRA_PKGS[*]}"
  fi

  log "== PASO 6: pin omarchy <-> omarchy-settings =="
  if dry; then
    log "[dry-run] comprobar que omarchy y omarchy-settings comparten version base (4.0.4)"
  else
    local a b
    a="$(pacman -Si omarchy 2>/dev/null | awk -F': ' '/^Version/{print $2; exit}')"
    b="$(pacman -Si omarchy-settings 2>/dev/null | awk -F': ' '/^Version/{print $2; exit}')"
    [ -n "$a" ] && [ -n "$b" ] || die "omarchy/omarchy-settings no aparecen en [omarchy]: ¿edge sin publicar?"
    [ "${a%-*}" = "${b%-*}" ] || die "pin roto: omarchy ${a} vs omarchy-settings ${b}"
    log "pin OK: omarchy ${a} / omarchy-settings ${b}"
    local hy qs
    hy="$(pacman -Si hyprland 2>/dev/null | awk -F': ' '/^Version/{print $2; exit}')"
    qs="$(pacman -Si quickshell 2>/dev/null | awk -F': ' '/^Version/{print $2; exit}')"
    log "hyprland resolucionado: ${hy:-?} · quickshell: ${qs:-?} (esperado 0.56.2-3 y 0.3.1-1 de ALARM)"
  fi
}

# ---------------------------------------------------------------------------
# PASO 7/8/9 — instalacion
# ---------------------------------------------------------------------------
step_install() {
  say ""
  log "== PASO 7: pacman -Syu (base rancia -> al dia; guard de Omarchy aun no existe) =="
  pacman_do -Syu

  say ""
  log "== PASO 8: nucleo Omarchy (${CORE_PKGS[*]}) =="
  pacman_do -S --needed "${CORE_PKGS[@]}"

  say ""
  log "== PASO 9: sesion minima + OSK + fuentes + pruebas =="
  pacman_do -S --needed "${EXTRA_PKGS[@]}"

  if [ "$WITH_AUR" -eq 1 ]; then
    log "== PASO 9b: --with-aur (${AUR_PKGS[*]}) =="
    pacman_do -S --needed "${AUR_PKGS[@]}"
  fi
}

# ---------------------------------------------------------------------------
# PASO 10 — post-instalacion (usuario, sesion, OSK, arreglos ARM)
# ---------------------------------------------------------------------------
step_post_user() {
  say ""
  log "== PASO 10a: usuario ${TARGET_USER} y autologin en tty1 =="

  if dry; then
    log "[dry-run] useradd -m -G <grupos existentes> -s /bin/bash ${TARGET_USER}"
    log "[dry-run] getty@tty1 autologin + ~/.bash_profile con uwsm"
    return 0
  fi

  if ! id "$TARGET_USER" >/dev/null 2>&1; then
    local groups="wheel" g
    for g in video render input audio seat rfkill storage power network; do
      getent group "$g" >/dev/null 2>&1 && groups="${groups},${g}"
    done
    useradd -m -G "$groups" -s /bin/bash "$TARGET_USER"
    log "usuario creado: ${TARGET_USER} (grupos: ${groups})"
  else
    local g
    for g in wheel video render input audio seat rfkill storage power network; do
      getent group "$g" >/dev/null 2>&1 && usermod -aG "$g" "$TARGET_USER" 2>/dev/null || true
    done
    log "usuario ${TARGET_USER} ya existia; grupos re-asegurados"
  fi

  # A1-R4: el hook 99-uke-restore-repos (dentro de omarchy-refresh-pacman) hace
  # sudo cp no interactivo; sin NOPASSWD falla silencioso y un omarchy update
  # posterior deja el pacman.conf x86 por los suelos.
  if ! dry; then
    printf '%s\n' "${TARGET_USER} ALL=(root) NOPASSWD: /usr/bin/cp -f /usr/local/share/uke/pacman.conf /etc/pacman.conf" \
      > /etc/sudoers.d/uke-restaurar-repos
    chmod 440 /etc/sudoers.d/uke-restaurar-repos
    log "A1-R4: /etc/sudoers.d/uke-restaurar-repos escrito (NOPASSWD cp del conf)"
  else
    log "[dry-run] escribiria /etc/sudoers.d/uke-restaurar-repos (NOPASSWD cp del conf)"
  fi

  # Contrasena (sudo/consola). Solo si aun no tiene una utilizable.
  local pwstate
  pwstate="$(passwd -S "$TARGET_USER" 2>/dev/null | awk '{print $2}')"
  if [ "$pwstate" = "L" ] || [ "$pwstate" = "NP" ]; then
    printf '%s:%s\n' "$TARGET_USER" "$TARGET_USER" | chpasswd
    log "contrasena inicial = '${TARGET_USER}' (cambiala con passwd)"
  fi

  ensure_file 644 "/etc/systemd/system/getty@tty1.service.d/autologin.conf" <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\\\u' --noclear --autologin ${TARGET_USER} %I \$TERM
EOF

  ensure_file 644 /etc/skel/.bash_profile <<'EOF'
[[ -f ~/.bashrc ]] && . ~/.bashrc

# uke: arranca la sesion uwsm+Hyprland solo en tty1 (tablet sin greeter)
if [ -z "${WAYLAND_DISPLAY:-}" ] && [ "${XDG_VTNR:-1}" = "1" ] && [ "$(tty)" = "/dev/tty1" ]; then
  if uwsm check may-start; then
    exec uwsm start -e -D Hyprland hyprland.desktop
  fi
fi
EOF
  install -m 644 -o "$TARGET_USER" -g "$TARGET_USER" /etc/skel/.bash_profile \
    "$(getent passwd "$TARGET_USER" | cut -d: -f6)/.bash_profile"

  RUN systemctl daemon-reload
  log "autologin escrito. Se aplica al reiniciar o con: systemctl restart getty@tty1"
}

step_post_hypr() {
  say ""
  log "== PASO 10b: config Hyprland de tablet + rendimiento =="
  [ "$DRY_RUN" -eq 0 ] || { log "[dry-run] escribiria uke.lua/uke-perf.lua y anadiria require hypr.uke"; return 0; }

  local home; home="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
  local f dir
  for dir in "${home}/.config/hypr" /etc/skel/.config/hypr; do
    mkdir -p "$dir"
    ensure_file 644 "${dir}/uke.lua" <<'EOF'
-- uke: overrides de tablet (anadido por install-omarchy-uke.sh)
hl.env("GDK_SCALE", "1")

-- Panel o82 2136x3200: 60 Hz y escala entera 1 (144 Hz y scale=2 son inviables en Adreno 732).
-- Si el output no se llama DSI-1, hyprctl lo ignora; uke-monitor-apply lo corrige en runtime.
hl.monitor({ output = "DSI-1", mode = "2136x3200@60", position = "auto", scale = 1 })

-- Teclado en pantalla: toggle manual (ademas del autoshow). La rotacion es F7.
hl.bind("SUPER + K", hl.dsp.exec_cmd("uke-osk toggle"))
hl.bind("SUPER + SHIFT + R", hl.dsp.exec_cmd("uke-monitor-rotate next"))
-- El OSK de layer-shell debe poder dibujarse por encima del lock del shell
hl.layer_rule({ match = { namespace = "squeekboard" }, above_lock = 2 })

-- Rendimiento (C §5.3). En pcall: un nombre de opcion equivocado no debe tumbar la sesion.
local ok, err = pcall(dofile, (os.getenv("HOME") or "/home/omarchy") .. "/.config/hypr/uke-perf.lua")
if not ok then print("[uke] uke-perf.lua no cargado: " .. tostring(err)) end
EOF

    ensure_file 644 "${dir}/uke-perf.lua" <<'EOF'
-- uke: presupuesto grafico para Adreno 732 / panel 2136x3200 (informe C §5.3)
hl.config({
  decoration = { blur = { enabled = false }, shadow = { enabled = false }, rounding = 0 },
  animations = { enabled = false },
  misc = { vfr = true, render_unfocused_fps = 5, disable_autoreload = true },
  render = { new_render_scheduling = true, direct_scanout = 0, use_fp16 = 0 },
  cursor  = { no_hardware_cursors = 1, hide_on_touch = true },
})
EOF

    # carga de hypr.uke al final de hyprland.lua (idempotente, y en pcall para aislar fallos)
    local hl="${dir}/hyprland.lua"
    if [ -f "$hl" ] && ! grep -q 'hypr\.uke' "$hl"; then
      cat >>"$hl" <<'EOF'

-- uke: overrides de tablet (anadido por install-omarchy-uke.sh)
-- pcall: si algo de uke.lua falla, la sesion de Omarchy sigue arrancando
local _uke_ok, _uke_err = pcall(require, "hypr.uke")
if not _uke_ok then print("[uke] hypr.uke no cargado: " .. tostring(_uke_err)) end
EOF
      log "require hypr.uke anadido a $hl"
    elif [ -f "$hl" ]; then
      log "hyprland.lua ya carga hypr.uke: $hl"
    else
      warn "no existe $hl (¿omarchy-settings fuera de skel?); se salta"
    fi
  done
  chown -R "$TARGET_USER:$TARGET_USER" "${home}/.config/hypr" 2>/dev/null || true
}

step_post_osk() {
  say ""
  log "== PASO 10c: OSK (squeekboard por defecto; wvkbd si se compila) + unidades =="

  ensure_file 755 /usr/local/bin/uke-osk <<'EOF'
#!/bin/bash
# uke-osk — control del teclado en pantalla (squeekboard preferido; wvkbd alternativo)
set -u
VK_BIN=""
for c in squeekboard wvkbd-deskintl wvkbd-mobintl wvkbd; do
  if command -v "$c" >/dev/null 2>&1; then VK_BIN="$c"; break; fi
done
[ -n "$VK_BIN" ] || { echo "uke-osk: no hay OSK instalado (squeekboard/wvkbd)" >&2; exit 1; }

RUNDIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
PIDFILE="${RUNDIR}/uke-osk.pid"

sb() { busctl --user call sm.puri.OSK0 /sm/puri/OSK0 sm.puri.OSK0 "$@" >/dev/null 2>&1; }
sb_visible() { busctl --user get-property sm.puri.OSK0 /sm/puri/OSK0 sm.puri.OSK0 Visible 2>/dev/null | grep -q true; }

wvkbd_start() {
  [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null && return 0
  setsid "$VK_BIN" -H 350 -L 350 >/dev/null 2>&1 &
  echo $! >"$PIDFILE"
  sleep 0.8
}
wvkbd_pid() { [ -f "$PIDFILE" ] && cat "$PIDFILE" 2>/dev/null || pgrep -x "$VK_BIN" | head -1; }

start_hidden() {
  case "$VK_BIN" in
    squeekboard)
      pgrep -x squeekboard >/dev/null 2>&1 || setsid squeekboard >/dev/null 2>&1 &
      sleep 1
      sb SetVisible b false || true
      ;;
    *)
      wvkbd_start
      kill -USR1 "$(wvkbd_pid)" 2>/dev/null || true
      ;;
  esac
}
show() {
  case "$VK_BIN" in
    squeekboard) pgrep -x squeekboard >/dev/null 2>&1 || setsid squeekboard >/dev/null 2>&1 & sleep 0.5; sb SetVisible b true ;;
    *) wvkbd_start; kill -USR2 "$(wvkbd_pid)" 2>/dev/null || true ;;
  esac
}
hide() {
  case "$VK_BIN" in
    squeekboard) sb SetVisible b false ;;
    *) kill -USR1 "$(wvkbd_pid)" 2>/dev/null || true ;;
  esac
}
status() {
  case "$VK_BIN" in
    squeekboard) sb_visible && echo "squeekboard visible" || echo "squeekboard oculto" ;;
    *) echo "wvkbd (pid $(wvkbd_pid))" ;;
  esac
}
case "${1:-toggle}" in
  start-hidden) start_hidden ;;
  show)         show ;;
  hide)         hide ;;
  toggle)
    if pgrep -x squeekboard >/dev/null 2>&1 && sb_visible; then hide; else show; fi
    ;;
  status)       status ;;
  *) echo "uso: uke-osk start-hidden|show|hide|toggle|status" >&2; exit 2 ;;
esac
EOF

  ensure_file 755 /usr/local/bin/uke-osk-autoshow <<'EOF'
#!/bin/bash
# uke-osk-autoshow — muestra el OSK cuando la ventana activa es de una clase con texto.
# Hyprland 0.56 NO implementa text-input-v3: no existe "foco de texto" real; esto es
# una heuristica por clase de ventana (documentada en P6 §5.1).
set -u
CLASSES_FILE="${UKE_OSK_CLASSES:-$HOME/.config/uke/osk-classes}"
DEFAULT_CLASSES="foot,kitty,alacritty,ghostty,chromium,Chromium,google-chrome,firefox,firefox-esr,org.gnome.Nautilus,code,Ozone,org.telegram.desktop,Element"
INTERVAL="${UKE_OSK_INTERVAL:-0.7}"
CLASSES="$DEFAULT_CLASSES"
[ -f "$CLASSES_FILE" ] && CLASSES="$(tr '\n' ',' <"$CLASSES_FILE")"

want_osk() {
  [ "${UKE_OSK_PIN:-0}" = "1" ] && return 0
  local cls="$1" c
  [ -n "$cls" ] || return 1
  local IFS=','
  for c in $CLASSES; do
    [ -n "$c" ] || continue
    [ "${cls,,}" = "${c,,}" ] && return 0
  done
  return 1
}

state=""
while :; do
  cls="$(hyprctl activewindow -j 2>/dev/null | jq -r '.class // empty' 2>/dev/null || true)"
  if want_osk "$cls"; then want=1; else want=0; fi
  if [ "$want" != "$state" ]; then
    if [ "$want" = "1" ]; then uke-osk show || true; else uke-osk hide || true; fi
    state="$want"
  fi
  sleep "$INTERVAL"
done
EOF

  ensure_file 755 /usr/local/bin/uke-monitor-apply <<'EOF'
#!/bin/bash
# uke-monitor-apply — detecta el output DSI real y aplica modo/escala/transform.
# Idempotente. Hyprland 0.56: hyprctl keyword ya no vale, se usa hyprctl eval.
set -u
MODE="${UKE_MONITOR_MODE:-2136x3200@60}"
SCALE="${UKE_MONITOR_SCALE:-1}"
if [ "${1:-}" = "rotate" ] || [ "${1:-}" = "next" ]; then
  CURFILE="/run/user/$(id -u)/uke-transform"
  cur=$(cat "$CURFILE" 2>/dev/null || echo 0)
  TRANSFORM=$(( (cur + 1) % 4 ))
  echo "$TRANSFORM" >"$CURFILE"
  echo "uke: transform -> $TRANSFORM (aviso: el tactil necesita su propia transform; F7)"
else
  TRANSFORM="${UKE_MONITOR_TRANSFORM:-0}"
fi
name="$(hyprctl monitors -j 2>/dev/null | jq -r '[.[] | select(.name | test("^DSI"))][0].name // empty' 2>/dev/null || true)"
[ -n "$name" ] || { echo "uke-monitor-apply: no hay output DSI todavia" >&2; exit 0; }
hyprctl eval "hl.monitor({ output = \"$name\", mode = \"$MODE\", position = \"auto\", scale = $SCALE, transform = $TRANSFORM })" >/dev/null 2>&1 || true
echo "uke: $name -> $MODE scale=$SCALE transform=$TRANSFORM"
EOF

  ensure_file 755 /usr/local/bin/uke-f6-verify <<'EOF'
#!/bin/bash
# uke-f6-verify — criterios de "hecho" de F6/P6 §7. Ejecutar DENTRO de la sesion grafica.
set -u
fail=0
ok()   { printf 'OK    %s\n' "$*"; }
bad()  { printf 'FALLA %s\n' "$*"; fail=1; }

for p in omarchy omarchy-settings omarchy-keyring hyprland quickshell uwsm squeekboard foot; do
  if pacman -Qq "$p" >/dev/null 2>&1; then ok "paquete $p ($(pacman -Q "$p" | awk '{print $2}'))"; else bad "paquete $p"; fi
done

if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && command -v hyprctl >/dev/null 2>&1; then
  v="$(hyprctl version 2>/dev/null | head -1)"
  [ -n "$v" ] && ok "$v" || bad "hyprctl version"
  mon="$(hyprctl monitors -j 2>/dev/null | jq -r '.[0].name // empty' 2>/dev/null)"
  case "$mon" in DSI*) ok "monitor $mon";; "") bad "monitor (¿sin output?)";; *) bad "monitor $mon (esperado DSI-*)";; esac
else
  printf 'AVISO sin sesion Hyprland activa (HYPRLAND_INSTANCE_SIGNATURE vacio)\n'
fi

pgrep -af quickshell >/dev/null 2>&1 && ok "shell quickshell vivo" || bad "quickshell no esta corriendo"
if command -v eglinfo >/dev/null 2>&1 && [ -n "${WAYLAND_DISPLAY:-}" ]; then
  egl="$(eglinfo -B 2>/dev/null | grep -A2 'OpenGL ES profile' | tr '\n' ' ')"
  case "$egl" in
    *freedreno*) ok "EGL: $(printf '%s' "$egl" | cut -c1-110)";;
    "")          printf 'AVISO eglinfo sin datos\n';;
    *)           bad "EGL sin freedreno (¿llvmpipe?): $(printf '%s' "$egl" | cut -c1-110)";;
  esac
fi
pgrep -x squeekboard >/dev/null 2>&1 || pgrep -af wvkbd >/dev/null 2>&1 \
  && ok "OSK presente" || printf 'AVISO OSK no arrancado (uke-osk start-hidden)\n'

errs="$(dmesg --level=err,warn 2>/dev/null | grep -c 'EXT4-fs error' || true)"
printf 'INFO  errores EXT4 en dmesg: %s\n' "$errs"

if [ "$fail" -eq 0 ]; then echo "uke-f6-verify: TODO OK"; else echo "uke-f6-verify: HAY FALLOS"; fi
exit "$fail"
EOF

  ensure_file 644 /etc/systemd/user/uke-monitor.service <<'EOF'
[Unit]
Description=uke: aplica modo/escala del panel DSI
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/uke-monitor-apply boot

[Install]
WantedBy=graphical-session.target
EOF

  ensure_file 644 /etc/systemd/user/uke-osk.service <<'EOF'
[Unit]
Description=uke: teclado en pantalla (precargado oculto)
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/uke-osk start-hidden

[Install]
WantedBy=graphical-session.target
EOF

  ensure_file 644 /etc/systemd/user/uke-osk-autoshow.service <<'EOF'
[Unit]
Description=uke: muestra el OSK segun la ventana activa (heuristica)
After=graphical-session.target uke-osk.service
PartOf=graphical-session.target

[Service]
Restart=on-failure
ExecStart=/usr/local/bin/uke-osk-autoshow

[Install]
WantedBy=graphical-session.target
EOF

  if [ "$DRY_RUN" -eq 0 ]; then
    local home; home="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
    local w="${home}/.config/systemd/user/graphical-session.target.wants"
    mkdir -p "$w"
    ln -sfn /etc/systemd/user/uke-osk.service "${w}/uke-osk.service"
    ln -sfn /etc/systemd/user/uke-osk-autoshow.service "${w}/uke-osk-autoshow.service"
    ln -sfn /etc/systemd/user/uke-monitor.service "${w}/uke-monitor.service"
    chown -R "$TARGET_USER:$TARGET_USER" "${home}/.config/systemd" 2>/dev/null || true
    ensure_file 644 "${home}/.config/uke/osk-classes" <<'EOF'
foot
kitty
alacritty
ghostty
chromium
firefox
code
EOF
    chown -R "$TARGET_USER:$TARGET_USER" "${home}/.config/uke" 2>/dev/null || true
    log "unidades de usuario habilitadas por symlink (sin gestor de usuario vivo aun)"
  fi
}

step_post_arm_fixes() {
  say ""
  log "== PASO 10d: arreglos ARM (A §9.6 / F6 §4) =="

  # 1) hook pre-refresh-pacman: restaura NUESTROS repos si omarchy-refresh-pacman los pisa
  ensure_file 755 /etc/skel/.config/omarchy/hooks/pre-refresh-pacman.d/99-uke-restore-repos <<'EOF'
#!/bin/bash
# uke: omarchy-refresh-pacman copia el pacman.conf/mirrorlist x86 de Omarchy y rompe pacman
# en aarch64 (A §8 / C §7.3). Este hook corre justo despues de esa copia y restaura los repos.
sudo cp -f /usr/local/share/uke/pacman.conf /etc/pacman.conf
sudo cp -f /usr/local/share/uke/mirrorlist /etc/pacman.d/mirrorlist
echo "uke: repos ALARM+omarchy restaurados tras pre-refresh-pacman"
EOF
  if [ "$DRY_RUN" -eq 0 ]; then
    local home_h; home_h="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
    install -D -m 755 -o "$TARGET_USER" -g "$TARGET_USER" \
      /etc/skel/.config/omarchy/hooks/pre-refresh-pacman.d/99-uke-restore-repos \
      "${home_h}/.config/omarchy/hooks/pre-refresh-pacman.d/99-uke-restore-repos"
  fi

  # 2) wrapper tolerante de omarchy-pkg-add (upstream aborta TODA la transaccion con un nombre malo)
  if [ ! -e /usr/bin/omarchy-pkg-add ]; then
    warn "no existe /usr/bin/omarchy-pkg-add (¿omarchy no instalado?)"
  else
    if [ ! -e /usr/bin/omarchy-pkg-add.orig ]; then
      RUN cp -a /usr/bin/omarchy-pkg-add /usr/bin/omarchy-pkg-add.orig
    fi
    ensure_file 755 /usr/bin/omarchy-pkg-add <<'EOF'
#!/bin/bash
# uke: wrapper tolerante (original en /usr/bin/omarchy-pkg-add.orig).
# Upstream aborta la transaccion entera si UN nombre no resuelve (A §9, leccion 6);
# aqui se instala lo resoluble y se avisa de lo demas sin tumbar el flujo.
set -u
pac() { if [ "$(id -u)" -eq 0 ]; then pacman "$@"; else sudo pacman "$@"; fi; }
resolvable=(); missing=()
for pkg in "$@"; do
  pac -Qq "$pkg" >/dev/null 2>&1 && continue
  # -Sp resuelve tambien provides (p. ej. localsend -> localsend-bin)
  if pac -Sp --print-format '%n' "$pkg" >/dev/null 2>&1; then resolvable+=("$pkg"); else missing+=("$pkg"); fi
done
if [ "${#resolvable[@]}" -gt 0 ]; then
  pac -S --needed --noconfirm "${resolvable[@]}" || echo "uke-pkg-add: fallo instalando ${resolvable[*]}" >&2
fi
for pkg in "${missing[@]:-}"; do
  [ -n "$pkg" ] || continue
  if [ "$(id -u)" -ne 0 ] && command -v yay >/dev/null 2>&1; then
    yay -S --needed --noconfirm -- "$pkg" || echo "uke-pkg-add: '$pkg' no instalable (AUR)" >&2
  else
    echo "uke-pkg-add: '$pkg' no existe en los repos de pacman; se omite" >&2
  fi
done
exit 0
EOF
    log "wrapper omarchy-pkg-add instalado (.orig guardado)"
  fi

  # 3) marcador de kernel: omarchy-update-restart busca vmlinuz y un paquete dueno del fichero;
  #    en ALARM el kernel viaja en boot.img, asi que sin esto pide reiniciar para siempre.
  if [ "$DRY_RUN" -eq 0 ]; then
    if pacman -Qq uke-kernel-marker >/dev/null 2>&1; then
      log "uke-kernel-marker ya instalado"
    elif want bsdtar && want zstd; then
      local krel d
      krel="$(uname -r)"
      d="${BOOTSTRAP_DIR}/uke-kernel-marker"
      rm -rf "$d"; mkdir -p "$d/usr/lib/modules/${krel}"
      printf 'uke: marcador; el kernel real viaja en boot.img (7.2.0-rc2-palawan+)\n' \
        >"$d/usr/lib/modules/${krel}/vmlinuz"
      cat >"$d/.PKGINFO" <<EOF
pkgname = uke-kernel-marker
pkgbase = uke-kernel-marker
pkgver = 1.0-1
pkgdesc = Marca el kernel de boot.img para omarchy-update-restart
url = https://omarchy-uke.example/   # marcador local, no es un host real
builddate = $(date +%s)
packager = uke
size = 84
arch = any
license = custom
EOF
      ( cd "$d" && bsdtar -cf - .PKGINFO usr | zstd -q -c >"${BOOTSTRAP_DIR}/uke-kernel-marker-1.0-1-any.pkg.tar.zst" )
      pacman_do -U "${BOOTSTRAP_DIR}/uke-kernel-marker-1.0-1-any.pkg.tar.zst"
    else
      warn "sin bsdtar/zstd: no puedo crear uke-kernel-marker"
    fi
  else
    log "[dry-run] crearia e instalaria uke-kernel-marker (vmlinuz marcador en /usr/lib/modules/$(uname -r))"
  fi

  # 4) migraciones ya vienen selladas en /etc/skel/.local/state/omarchy/migrations/*.sh (paquete omarchy)
  log "migraciones: selladas por el propio paquete omarchy (skel). Nada que hacer."
}

# ---------------------------------------------------------------------------
# PASO 11 — verificacion
# ---------------------------------------------------------------------------
step_verify() {
  say ""
  log "== PASO 11: verificacion =="
  if dry; then
    log "[dry-run] uke-f6-verify (paquetes, ficheros, units) + recuento EXT4 post"
    return 0
  fi
  local errs; errs="$(dmesg --level=err,warn 2>/dev/null | grep -c 'EXT4-fs error' || true)"
  log "errores EXT4 tras la instalacion: ${errs}"
  # A1-R5: no acumular cache (un reintento tras fallo duplicaria la descarga)
  pacman_do -Sc --noconfirm 2>/dev/null || true

  local missing=0 p
  for p in omarchy omarchy-settings omarchy-keyring hyprland quickshell uwsm squeekboard foot; do
    if pacman -Qq "$p" >/dev/null 2>&1; then
      log "OK  $(pacman -Q "$p")"
    else
      warn "FALTA $p"; missing=1
    fi
  done
  for f in /usr/share/omarchy/version /usr/local/bin/uke-osk /usr/local/bin/uke-osk-autoshow \
           /usr/local/bin/uke-f6-verify /etc/systemd/user/uke-osk.service; do
    [ -e "$f" ] && log "OK  $f" || { warn "FALTA $f"; missing=1; }
  done
  [ "$missing" -eq 0 ] || die "verificacion con fallos"
  say ""
  log "LISTO. Siguiente: reiniciar la tablet (o systemctl restart getty@tty1) y en la sesion:"
  log "  hyprctl version ; hyprctl monitors -j | jq -r '.[0].name' ; eglinfo -B | grep -A2 'OpenGL ES'"
  log "  uke-f6-verify (si esta instalado) · uke-osk toggle"
}

# ---------------------------------------------------------------------------
main() {
  say "=== install-omarchy-uke.sh — $(dry && echo 'DRY-RUN (nada se ejecuta)' || echo 'EJECUCION REAL') ==="

  if ! dry; then
    [ "$(id -u)" -eq 0 ] || die "con --go hay que ser root (sudo)"
    mkdir -p "$(dirname "$LOG_FILE")"
    exec > >(tee -a "$LOG_FILE") 2>&1
    log "log: $LOG_FILE"
  fi

  step_gate
  step_backup
  step_repos
  step_keyring
  step_sync_and_check
  step_install
  step_post_user
  step_post_hypr
  step_post_osk
  step_post_arm_fixes
  step_verify

  say ""
  if dry; then
    say "=== DRY-RUN terminado. Nada se ha tocado. Ejecuta con: sudo $0 --go ==="
  else
    say "=== Instalacion terminada. Backup: ${BK_DIR} ==="
  fi
}

main "$@"
