#!/usr/bin/env bash
# deploy.sh -- Omarchy (Hyprland 0.56 + quickshell + sddm autologin) y la GPU en la uke, POR SSH y OFFLINE.
#
# Fuente: build/stage-escritorio (paquetes aarch64 ya descargados) + manifest/ (cierre calculado en el PC).
# Transporte: tar | ssh 'tar -x' (scp/sftp no sirven en este rootfs -medido el 17-oct-; tar|ssh no depende de ellos).
# Clave/host como build/gates/uke-ssh.sh: root@192.168.42.129 con build/rootfs/uke-arch-root.
#
# *** Cualquier subcomando que ESCRIBA en la tablet es DRY-RUN salvo que pases --go. ***
# *** Los de solo lectura (preflight, verify, status, gpu, evidence) y los del PC (plan, check) corren siempre. ***
#
# Uso:  deploy.sh <subcomando> [args] [--go] [--user U] [--sudo-nopasswd] [--boot-desktop] [--overwrite-all]
#
#   PC (sin red)      plan                 tandas, tamanos y lo que haria cada paso
#                     check                stage completo + sha256 de los 342 .pkg + bash -n de los scripts remotos
#   lectura (ssh)     preflight            verify.sh pre: kernel, RAM, espacio, firmware GPU, red de rescate
#                     verify               verify.sh post: binarios, ldd, DB pacman, usuario, sddm, migraciones
#                     status | gpu | evidence | shot     estado de la sesion / GPU / pruebas de que renderiza la GPU
#   escritura (--go)  all                  preflight + pre + install all + post + verify   (NO arranca la sesion)
#                     setup-pre | install [N|all] | setup-post | undo
#                     start | stop         systemctl start/stop sddm (autologin al usuario del escritorio)
#                     gpu-mode default|swrast|softpipe|split   |  perf on|off  |  boot-desktop on|off
#
# Orden recomendado el dia D (tras: SSH vivo, modulos del kernel v2 instalados y depmod hecho):
#   ./deploy.sh check && ./deploy.sh preflight && ./deploy.sh all --go
#   ./deploy.sh gpu-mode swrast --go && ./deploy.sh start --go && ./deploy.sh status && ./deploy.sh shot
#   ./deploy.sh stop --go && ./deploy.sh gpu-mode default --go && ./deploy.sh start --go && ./deploy.sh evidence
set -euo pipefail

R="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
D=$R/build/rootfs/deploy/omarchy
STAGE=${STAGE:-$R/build/stage-escritorio}
KEY=${UKE_KEY:-$R/build/rootfs/uke-arch-root}
HOST=${UKE_HOST:-192.168.42.129}
RD=${RD:-/root/uke-omarchy}
DESKTOP_USER=${DESKTOP_USER:-omarchy}
MAN=$D/manifest/instalar.tsv
GO=0
SUDO_NOPASSWD=0
BOOT_DESKTOP=0
OVERWRITE_ALL=0
BATCH_TIMEOUT=${BATCH_TIMEOUT:-2700}

SSH_OPTS=(-i "$KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR
          -o ConnectTimeout=8 -o ServerAliveInterval=15 -o ServerAliveCountMax=6 -o BatchMode=yes -o IdentitiesOnly=yes)
rsh() { ssh "${SSH_OPTS[@]}" "root@$HOST" "$@"; }       # lee stdin (para tar | rsh)
rsh_n() { ssh -n "${SSH_OPTS[@]}" "root@$HOST" "$@"; }  # no lee stdin (bucles)

say() { printf '%s\n' "$*"; }
die() { printf 'ABORTA: %s\n' "$*" >&2; exit 2; }
step() { printf '\n##### %s\n' "$*"; }

# ---- argumentos ----
args=()
while [ $# -gt 0 ]; do
  case $1 in
    --go) GO=1 ;;
    --user) DESKTOP_USER=$2; shift ;;
    --sudo-nopasswd) SUDO_NOPASSWD=1 ;;
    --boot-desktop) BOOT_DESKTOP=1 ;;
    --overwrite-all) OVERWRITE_ALL=1 ;;
    -h|--help) sed -n '2,32p' "$0"; exit 0 ;;
    *) args+=("$1") ;;
  esac
  shift
done
CMD=${args[0]:-help}
ARG1=${args[1]:-}

# Las operaciones que escriben en la tablet piden --go; si no, solo se dice lo que se haria.
mut() {
  if [ "$GO" = 1 ]; then return 0; fi
  say "DRY-RUN: $*   (anade --go para ejecutarlo)"
  return 1
}

ENVV="RD=$RD DESKTOP_USER=$DESKTOP_USER SUDO_NOPASSWD=$SUDO_NOPASSWD BOOT_DESKTOP=$BOOT_DESKTOP OVERWRITE_ALL=$OVERWRITE_ALL"
# Ejecuta un script del PC en la tablet leyendolo por stdin (no deja ficheros): bash -s -- args
remote_script() { local s=$1; shift; rsh "env $ENVV bash -s -- $*" <"$D/remote/$s"; }

batches() { awk -F'\t' '!/^#/ && NF>=9 {print $1}' "$MAN" | sort -un; }
n_batches() { batches | wc -l; }

need_ssh() {
  [ -f "$KEY" ] || die "falta la clave $KEY"
  rsh_n 'echo "ssh OK: $(uname -m) $(uname -r) | $(uptime -p)"' || die "sin SSH a root@$HOST (mira build/gates/uke-ssh.sh -i; gadget USB/NCM, cable, kernel v2)"
}

# ----------------------------------------------------------------------------------------------------------
cmd_plan() {
  step "PLAN (solo PC; no se toca nada)"
  [ -f "$MAN" ] || die "falta $MAN: python3 -I $D/tools/gen-manifest.py"
  cat "$D/manifest/resumen.txt"
  cat <<EOF

Pasos de 'all' (cada uno es un subcomando y se puede repetir: todo es idempotente):
  1. preflight   solo lectura: aarch64, MemTotal>=6 GB (L57 sin mem=2048M), libres>=2,8 GiB, firmware gen71100_* (sha), red de rescate
  2. setup-pre   copia de /etc ($RD y /var/backups/uke-omarchy), anula hooks mkinitcpio, arregla /home/alarm (root:root 0700)
  3. install N   por tanda: tar|ssh -> sha256 -> df-gate -> 'pacman -U --needed --noconfirm [--overwrite *]' -> pacman -Qk -> borra los .pkg
  4. setup-post  useradd $DESKTOP_USER (skel de omarchy-settings + 106 migraciones selladas), sddm autologin Session=omarchy,
                 PAM sddm como upstream, wrappers omarchy-pkg-add / omarchy-update-restart, systemctl enable sddm
  5. verify      binarios, ldd, DB de pacman, usuario, autologin, migraciones
  (la sesion NO arranca sola: el cmdline trae systemd.unit=multi-user.target) -> start, o al arranque con
                 uke-desktop.service: build/rootfs/deploy/arranque/deploy.sh apply --go (boot-desktop on|off lo (des)habilita)

Fuera de alcance a proposito: NetworkManager (no se habilita: competiria con networkd por usb0 = el SSH),
subidas de base (systemd/openssh/openssl: ver manifest/no-incluidos.tsv), zram/swap, WiFi/BT/audio, tactil.
EOF
}

cmd_check() {
  step "CHECK (solo PC)"
  local bad=0 n=0 f
  [ -d "$STAGE" ] || die "falta $STAGE"
  [ -f "$MAN" ] || die "falta $MAN"
  [ -f "$KEY" ] && printf '  OK   clave %s (%s)\n' "$KEY" "$(stat -c %a "$KEY")" || { echo "  FALLO falta la clave $KEY"; bad=1; }
  while IFS=$'\t' read -r b l file name ver cs is ovl sha; do
    case $b in \#*|"") continue ;; esac
    n=$((n + 1))
    [ -f "$STAGE/$file" ] || { echo "  FALLO no existe $STAGE/$file"; bad=1; }
  done <"$MAN"
  echo "  OK   filas en el manifiesto: $n; tandas: $(n_batches)"
  echo "  ...  sha256 de los $n paquetes contra manifest/instalar.tsv (unos segundos)"
  if awk -F'\t' '!/^#/ && NF>=9 {print $9 "  " $3}' "$MAN" | (cd "$STAGE" && sha256sum -c --quiet); then
    echo "  OK   sha256 de todos los paquetes"
  else echo "  FALLO sha256"; bad=1; fi
  for f in deploy.sh remote/batch.sh remote/uke-setup.sh remote/verify.sh remote/session.sh tools/gen-manifest.py tools/elf-check.py; do
    case $f in
      *.py) python3 -I -c "import ast,sys; ast.parse(open('$D/$f').read())" && echo "  OK   sintaxis $f" || { echo "  FALLO $f"; bad=1; } ;;
      *) bash -n "$D/$f" && echo "  OK   bash -n $f" || { echo "  FALLO bash -n $f"; bad=1; } ;;
    esac
  done
  if command -v shellcheck >/dev/null 2>&1; then
    shellcheck -S warning -e SC2086,SC2016,SC1090,SC2034,SC2155,SC2317 "$D"/deploy.sh "$D"/remote/*.sh >/dev/null 2>&1 && echo "  OK   shellcheck (warning)" || echo "  AVISO shellcheck con observaciones (no bloquea)"
  fi
  for f in omarchy-pkg-add omarchy-update-restart seal-migrations-uke.sh; do
    [ -f "$D/files/$f" ] && echo "  OK   files/$f" || { echo "  FALLO falta files/$f"; bad=1; }
  done
  grep -q '^ninguno' <(sed -n '/^PROBLEMAS:/,$p' "$D/manifest/resumen.txt" | tail -n +2) && echo "  OK   manifest/resumen.txt: PROBLEMAS = ninguno" || { echo "  FALLO el resumen del manifiesto lista problemas"; bad=1; }
  [ "$bad" = 0 ] && echo "CHECK OK" || { echo "CHECK CON FALLOS"; return 1; }
}

# ----------------------------------------------------------------------------------------------------------
push_support() {
  mut "enviar scripts, wrappers y lista de nombres a $RD" || return 0
  local t; t=$(mktemp -d)
  mkdir -p "$t/files"
  cp "$D"/remote/batch.sh "$D"/remote/uke-setup.sh "$D"/remote/verify.sh "$D"/remote/session.sh "$t/"
  cp "$D"/files/* "$t/files/"
  cp "$D/manifest/nombres.txt" "$t/nombres.txt"
  tar -C "$t" -cf - . | rsh "mkdir -p $RD/pkgs $RD/log $RD/state && tar -xf - -C $RD && chmod 0755 $RD/*.sh"
  rm -rf "$t"
  say "  soporte enviado a $RD"
}

cmd_install_batch() {
  local N=$1 files=() names=() f nm vr rest tmp pend
  [ -f "$MAN" ] || die "falta $MAN"
  step "tanda $N: ¿que falta ya en la tablet?"
  # nombre+version de la tanda -> la tablet responde cuales NO estan exactamente a esa version
  pend=$(awk -F'\t' -v n="$N" '!/^#/ && $1==n {print $4 " " $5}' "$MAN" | rsh \
    'while read -r n v; do [ "$(pacman -Q "$n" 2>/dev/null | cut -d" " -f2)" = "$v" ] || echo "$n"; done') || die "ssh fallo preguntando por la tanda $N"
  if [ -z "$pend" ]; then say "  tanda $N: todo instalado ya (nada que enviar)"; return 0; fi
  tmp=$(mktemp)
  awk -F'\t' -v n="$N" 'NR==FNR {p[$1]=1; next} /^#/ {print; next} $1==n && ($4 in p) {print}' <(printf '%s\n' "$pend") "$MAN" >"$tmp"
  while IFS=$'\t' read -r b l f nm vr cs is ovl sha; do
    case $b in \#*|"") continue ;; esac
    files+=("$f"); names+=("$nm")
  done <"$tmp"
  local mb; mb=$(awk -F'\t' '!/^#/ {s+=$6} END {printf "%.1f", s/1048576}' "$tmp")
  say "  pendientes: ${#files[@]} paquetes, $mb MiB comprimidos"
  if ! mut "tanda $N: enviar ${#files[@]} paquetes ($mb MiB) por tar|ssh y lanzar batch.sh $N con setsid+nohup"; then rm -f "$tmp"; return 0; fi
  rsh "rm -f $RD/state/batch-$N.rc; mkdir -p $RD/pkgs $RD/log $RD/state; cat > $RD/batch-$N.tsv" <"$tmp"
  tar -C "$STAGE" -cf - -- "${files[@]}" | rsh "tar -xf - -C $RD/pkgs"
  rm -f "$tmp"
  rsh_n "env RD=$RD OVERWRITE_ALL=$OVERWRITE_ALL setsid nohup bash $RD/batch.sh $N >/dev/null 2>&1 </dev/null & echo lanzada" >/dev/null
  say "  batch.sh $N lanzado en la tablet (log: $RD/log/batch-$N.log). Sondeando..."
  local t0 rc="" fails=0 last="" cur
  t0=$(date +%s)
  while :; do
    if rc=$(rsh_n "cat $RD/state/batch-$N.rc 2>/dev/null" 2>/dev/null); then fails=0; else fails=$((fails + 1)); rc=""; fi
    if [ -n "$rc" ]; then break; fi
    [ "$fails" -ge 30 ] && die "30 sondeos seguidos sin SSH: pacman SIGUE en la tablet; al volver: deploy.sh status-batch $N"
    cur=$(rsh_n "tail -n 1 $RD/log/batch-$N.log 2>/dev/null" 2>/dev/null || true)
    [ -n "$cur" ] && [ "$cur" != "$last" ] && { printf '  [%4ds] %s\n' "$(($(date +%s) - t0))" "$cur"; last=$cur; }
    [ $(($(date +%s) - t0)) -gt "$BATCH_TIMEOUT" ] && die "tanda $N sin terminar tras ${BATCH_TIMEOUT}s (sigue en la tablet)"
    sleep 6
  done
  say "  tanda $N: rc=$rc"
  if [ "$rc" != 0 ]; then
    rsh_n "tail -n 40 $RD/log/batch-$N.log" || true
    case $rc in
      10) say "  -> sha256 no cuadra: repite 'install $N' (re-envia)" ;;
      20) say "  -> conflicto de ficheros fuera del overlay conocido: NO se pisa solo; mira $RD/log/batch-$N.pacman" ;;
      42) say "  -> sin espacio: nada se toco; libera y repite" ;;
    esac
    return "$rc"
  fi
  rsh_n "tail -n 2 $RD/log/batch-$N.log" || true
}

cmd_install() {
  local which=${1:-all} N
  need_ssh
  push_support
  if [ "$which" = all ]; then
    for N in $(batches); do cmd_install_batch "$N" || return $?; done
  else cmd_install_batch "$which"; fi
}

cmd_setup() {   # pre | post | undo
  local what=$1
  need_ssh
  push_support
  mut "ejecutar uke-setup.sh $what en la tablet" || return 0
  rsh "env $ENVV bash $RD/uke-setup.sh $what"
}

cmd_all() {
  step "preflight"; cmd_preflight || die "preflight con fallos: no se instala nada"
  step "setup-pre"; cmd_setup pre
  step "install all"; cmd_install all
  step "setup-post"; cmd_setup post
  step "verify"; cmd_verify || true
  cat <<EOF

LISTO (la sesion NO esta arrancada). Siguiente:
  $0 gpu-mode swrast --go && $0 start --go && $0 status && $0 shot      # 1) panel+sesion sin abrir la GPU
  $0 stop --go && $0 gpu-mode default --go && $0 start --go && $0 evidence  # 2) sobre freedreno
EOF
}

cmd_preflight() { step "preflight (solo lectura)"; need_ssh; remote_script verify.sh pre; }
cmd_verify() { step "verify (solo lectura)"; need_ssh; rsh "env $ENVV RD=$RD bash -s -- post" <"$D/remote/verify.sh"; }

session() {     # session.sh <args> ; lectura si $RO=1
  need_ssh
  if [ "${RO:-0}" != 1 ]; then mut "uke-session $*" || return 0; fi
  rsh "env $ENVV bash -s -- $*" <"$D/remote/session.sh"
}

cmd_shot() {
  need_ssh
  mkdir -p "$D/out"
  local out; out="$D/out/shot-$(date +%Y%m%d-%H%M%S).png"
  rsh "env $ENVV bash -s -- shot /tmp/uke-shot.png" <"$D/remote/session.sh"
  rsh_n 'cat /tmp/uke-shot.png' >"$out"
  say "capturada: $out ($(stat -c %s "$out") B)"
  if command -v magick >/dev/null 2>&1; then
    say "  media de luminancia 0..1: $(magick "$out" -colorspace Gray -format '%[fx:mean]' info: 2>/dev/null)  (≈0 = todo negro)"
  elif python3 -I -c 'import PIL' 2>/dev/null; then
    python3 -I - "$out" <<'PY'
import sys
from PIL import Image, ImageStat
im = Image.open(sys.argv[1]).convert("L")
print("  media de luminancia 0..255: %.1f  (≈0 = todo negro)" % ImageStat.Stat(im).mean[0])
PY
  fi
  say "OJO: grim lee el framebuffer de la GPU/compositor: que NO sea negro NO prueba que el panel lo muestre (14-oct: captura buena y panel negro). Prueba = el dueno lo ve + foto."
}

# ----------------------------------------------------------------------------------------------------------
case $CMD in
  help) sed -n '2,32p' "$0" ;;
  plan) cmd_plan ;;
  check) cmd_check ;;
  preflight) cmd_preflight ;;
  verify) cmd_verify ;;
  all) if [ "$GO" = 1 ]; then cmd_all; else say "DRY-RUN de 'all':"; cmd_plan; say; say "(anade --go; los subcomandos sueltos tambien admiten --go)"; fi ;;
  setup-pre) cmd_setup pre ;;
  setup-post) cmd_setup post ;;
  undo) cmd_setup undo ;;
  install) cmd_install "${ARG1:-all}" ;;
  status) RO=1 session status ;;
  gpu) RO=1 session gpu ;;
  evidence) RO=1 session evidence ;;
  shot) cmd_shot ;;
  status-batch) need_ssh; rsh_n "cat $RD/state/batch-${ARG1:?N}.rc 2>/dev/null; tail -n 30 $RD/log/batch-${ARG1}.log 2>/dev/null" ;;
  start) session start ;;
  stop) session stop ;;
  gpu-mode) session gpu-mode "${ARG1:?uso: gpu-mode default|swrast|softpipe|split}" ;;
  perf) session perf "${ARG1:?uso: perf on|off}" ;;
  boot-desktop) need_ssh; mut "boot-desktop ${ARG1:?on|off}" && { push_support; rsh "env $ENVV bash $RD/uke-setup.sh boot-desktop $([ "$ARG1" = on ] && echo 1 || echo 0)"; } || true ;;
  *) die "subcomando desconocido: $CMD (deploy.sh help)" ;;
esac
