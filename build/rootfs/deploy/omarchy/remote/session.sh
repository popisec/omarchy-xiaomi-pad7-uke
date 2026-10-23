#!/bin/bash
# session.sh <start|stop|status|shot [fichero]|evidence|gpu-mode default|swrast|split|perf on|off>
# Corre EN LA TABLET (root). deploy.sh lo envia a $RD/session.sh y uke-setup.sh post lo deja en /usr/local/sbin/uke-session.
#
# Escalera de la prueba (ver informe): 1) gpu-mode swrast + start  => prueba panel+sesion SIN tocar la GPU;
# 2) stop, gpu-mode default + start => Hyprland/quickshell sobre freedreno (Adreno 732, chip 0x43030b00).
# El primer open de la GPU es el momento de riesgo historico (cuelgue en a6xx_gmu_start): por eso se separa.
set -uo pipefail
U=${DESKTOP_USER:-omarchy}
uid=$(id -u "$U" 2>/dev/null) || { echo "no existe el usuario $U"; exit 2; }
gid=$(id -g "$U")
home=$(getent passwd "$U" | cut -d: -f6)
xdg=/run/user/$uid
MARK="# uke-managed"

sig() { ls -t "$xdg/hypr" 2>/dev/null | head -1; }
wld() { (cd "$xdg" 2>/dev/null && ls -d wayland-[0-9]* 2>/dev/null | grep -v '\.lock$' | head -1); }
as_user() {
  runuser -u "$U" -- env XDG_RUNTIME_DIR="$xdg" HYPRLAND_INSTANCE_SIGNATURE="$(sig)" WAYLAND_DISPLAY="$(wld)" "$@"
}
hpid() { pgrep -u "$uid" -x Hyprland | head -1; }

gpu_lines() {
  echo "-- /dev/dri:"; ls -l /dev/dri 2>&1 | sed 's/^/   /'
  echo "-- drivers DRM:"
  for d in /sys/class/drm/card[0-9]* ; do
    [[ ${d##*/} == *-* ]] && continue
    printf '   %s driver=%s conectores=%s\n' "${d##*/}" "$(grep -m1 DRIVER= "$d/device/uevent" 2>/dev/null | cut -d= -f2)" \
      "$(ls -d "$d"/"${d##*/}"-* 2>/dev/null | wc -l)"
  done
  echo "-- dmesg GPU (adreno/gmu/gpucc/zap):"
  dmesg 2>/dev/null | grep -iE 'adreno|a7xx|gen7|gmu|gpucc|kgsl|zap|msm_gpu|\[drm\].*(gpu|Loaded)|fault|iommu.*gpu' | tail -25 | sed 's/^/   /'
  [ -n "$(dmesg 2>/dev/null | grep -iE 'adreno|gmu' | head -1)" ] || echo "   (sin lineas adreno/gmu: la GPU NO ha probado; Mesa caera a llvmpipe)"
  echo "-- gpucc cargado:"; lsmod 2>/dev/null | grep -iE 'gpucc|^msm' | sed 's/^/   /' || true
}

status() {
  echo "== sddm: $(systemctl is-active sddm 2>&1) | enabled: $(systemctl is-enabled sddm 2>&1) | default.target: $(systemctl get-default 2>&1)"
  loginctl list-sessions --no-legend 2>/dev/null | sed 's/^/   sesion: /'
  for p in sddm Hyprland quickshell uwsm; do printf '   %-10s %s\n' "$p" "$(pgrep -d, -x "$p" 2>/dev/null || echo -)"; done
  echo "== MemAvailable: $(awk '/MemAvailable/{print int($2/1024)" MiB"}' /proc/meminfo) | libres /: $(df -Pm / | awk 'NR==2{print $4" MiB"}')"
  if [ -n "$(hpid)" ]; then
    echo "== hyprctl monitors:"; as_user hyprctl monitors 2>&1 | sed 's/^/   /' | head -20
    echo "== hyprctl version:"; as_user hyprctl version 2>&1 | head -3 | sed 's/^/   /'
  else echo "== Hyprland NO esta vivo"; fi
  echo "== journal sddm:"; journalctl -b -u sddm --no-pager 2>/dev/null | tail -12 | sed 's/^/   /'
  echo "== journal omarchy-shell (quickshell):"; journalctl -b -t omarchy-shell --no-pager 2>/dev/null | tail -8 | sed 's/^/   /'
  echo "== log de sesion sddm:"; tail -n 15 "$home/.local/share/sddm/wayland-session.log" 2>/dev/null | sed 's/^/   /'
  echo "== OOM:"; dmesg 2>/dev/null | grep -iE 'out of memory|oom-kill|Killed process' | tail -3 | sed 's/^/   /'
  echo "(sin lineas = no hubo OOM)"
}

evidence() {
  local p; p=$(hpid)
  [ -n "$p" ] || { echo "Hyprland no esta vivo"; return 1; }
  echo "== GPU en uso por Hyprland (pid $p):"
  local fd t
  for fd in /proc/"$p"/fd/*; do
    t=$(readlink "$fd" 2>/dev/null)
    case $t in /dev/dri/*) echo "  fd $(basename "$fd") -> $t"; grep -E '^drm-(driver|pdev|client-id|engine-gpu|total-memory|resident-memory)' "/proc/$p/fdinfo/$(basename "$fd")" 2>/dev/null | sed 's/^/     /' ;; esac
  done
  echo "== librerias de render mapeadas:"
  grep -oE '[^ ]*(msm_dri|kms_swrast_dri|libgallium[^ ]*|libvulkan_freedreno[^ ]*|libgbm[^ ]*|libEGL[^ ]*|libGLES[^ ]*)' "/proc/$p/maps" 2>/dev/null | sort -u | sed 's/^/  /'
  echo "== hyprland.log (render):"
  grep -hiE 'renderer|llvmpipe|freedreno|adreno|msm|gbm|egl|gles|swrast|drm' "$xdg/hypr/$(sig)/hyprland.log" 2>/dev/null | head -25 | sed 's/^/  /'
  echo "(llvmpipe/swrast en el log o kms_swrast_dri en maps = NO es la GPU; drm-driver: msm + drm-engine-gpu creciendo = SI)"
  echo "== fdinfo del GPU (2 muestras a 3 s, ns de motor):"
  for _ in 1 2; do
    for fd in /proc/"$p"/fd/*; do
      case $(readlink "$fd" 2>/dev/null) in /dev/dri/*) grep -hE '^drm-engine-gpu' "/proc/$p/fdinfo/$(basename "$fd")" 2>/dev/null ;; esac
    done | sed 's/^/  /'
    sleep 3
  done
}

start() {
  echo "== antes de arrancar: estado de la GPU"; gpu_lines
  echo "== modo GPU actual: $( [ -f "$home/.config/uwsm/env-hyprland" ] && grep -m1 'gpu-mode=' "$home/.config/uwsm/env-hyprland" || echo 'default (hardware)')"
  systemctl reset-failed sddm.service 2>/dev/null
  echo "== systemctl start sddm (autologin $U)"
  systemctl start sddm.service
  local i
  for i in $(seq 1 90); do [ -n "$(hpid)" ] && break; sleep 1; done
  if [ -z "$(hpid)" ]; then echo "Hyprland NO arranco en 90 s"; status; return 1; fi
  echo "Hyprland vivo (pid $(hpid)) tras ${i}s"
  for i in $(seq 1 40); do pgrep -u "$uid" -x quickshell >/dev/null && break; sleep 1; done
  pgrep -u "$uid" -x quickshell >/dev/null && echo "quickshell vivo tras ${i}s" || echo "quickshell NO esta vivo (sin el no hay fondo ni barra)"
  sleep 5
  status
}

stop() { systemctl stop sddm.service && echo "sddm parado"; }

shot() {
  local out=${1:-/tmp/uke-shot.png}
  [ -n "$(hpid)" ] || { echo "Hyprland no esta vivo"; return 1; }
  as_user grim "$out" && ls -l "$out"
}

gpu_mode() {
  local mode=${1:-} f="$home/.config/uwsm/env-hyprland" kms="" gpu="" c n
  install -d -o "$U" -g "$gid" -m 755 "$home/.config/uwsm"
  case $mode in
    default) [ -f "$f" ] && grep -q "$MARK" "$f" && { rm -f "$f"; echo "gpu-mode=default: sin variables (hardware)"; } || echo "gpu-mode=default: ya estaba" ;;
    swrast)
      cat >"$f" <<EOF
$MARK  gpu-mode=swrast  (uke-session gpu-mode default para quitarlo)
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=llvmpipe
export MESA_LOADER_DRIVER_OVERRIDE=kms_swrast
EOF
      chown "$U:$gid" "$f"; echo "gpu-mode=swrast: llvmpipe + kms_swrast (la GPU no se abre)" ;;
    softpipe)
      # 17-oct: llvmpipe muere con SIGILL en la uke: LLVM toma la CPU por /proc/cpuinfo (CPU part 0xd80 =
      # cortex-a520, ARMv9.2 => SVE2 implicito) y el JIT emite SVE, pero el firmware oculta SVE (Features sin
      # sve/sve2; medido en el core: 'index z3.s, #0, #1'). softpipe + DRAW_USE_LLVM=0 = Mesa sin JIT LLVM.
      cat >"$f" <<EOF
$MARK  gpu-mode=softpipe  (uke-session gpu-mode default para quitarlo)
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=softpipe
export DRAW_USE_LLVM=0
export MESA_LOADER_DRIVER_OVERRIDE=kms_swrast
EOF
      chown "$U:$gid" "$f"; echo "gpu-mode=softpipe: softpipe (sin JIT) + kms_swrast (la GPU no se abre)" ;;
    split)
      for c in /sys/class/drm/card[0-9]*; do
        n=${c##*/}; [[ $n == *-* ]] && continue
        if ls -d "$c"/"$n"-* >/dev/null 2>&1; then kms=/dev/dri/$n; else gpu=/dev/dri/$n; fi
      done
      [ -n "$kms" ] && [ -n "$gpu" ] || { echo "split: no hay dos nodos (kms='$kms' gpu='$gpu'); con separate_gpu_kms=0 usa 'default'"; return 1; }
      cat >"$f" <<EOF
$MARK  gpu-mode=split  kms=$kms gpu=$gpu
export AQ_DRM_DEVICES=$gpu:$kms
EOF
      chown "$U:$gid" "$f"; echo "gpu-mode=split: AQ_DRM_DEVICES=$gpu:$kms (primero = el que renderiza)" ;;
    *) echo "uso: gpu-mode default|swrast|softpipe|split"; return 1 ;;
  esac
}

perf() {
  local lua="$home/.config/hypr/uke-perf.lua" lnf="$home/.config/hypr/looknfeel.lua"
  [ -f "$lnf" ] || { echo "falta $lnf (¿primer login hecho?)"; return 1; }
  case ${1:-} in
    on)
      cat >"$lua" <<'EOF'
-- uke: aligerar la sesion mientras la GPU/panel se validan (uke-session perf on|off)
hl.config({
  animations = { enabled = false },
  decoration = { blur = { enabled = false }, shadow = { enabled = false } },
  misc = { vfr = true },
})
EOF
      chown "$U:$gid" "$lua"
      grep -q '>>> uke-perf' "$lnf" || printf '\n-- >>> uke-perf\npcall(dofile, (os.getenv("HOME") or "") .. "/.config/hypr/uke-perf.lua")\n-- <<< uke-perf\n' >>"$lnf"
      echo "perf on (efectivo en el proximo login o con hyprctl reload)" ;;
    off)
      sed -i '/-- >>> uke-perf/,/-- <<< uke-perf/d' "$lnf"; rm -f "$lua"; echo "perf off" ;;
    *) echo "uso: perf on|off"; return 1 ;;
  esac
}

case "${1:-}" in
  start) start ;;
  stop) stop ;;
  status) status ;;
  gpu) gpu_lines ;;
  shot) shot "${2:-}" ;;
  evidence) evidence ;;
  gpu-mode) gpu_mode "${2:-}" ;;
  perf) perf "${2:-}" ;;
  *) sed -n '2,8p' "$0"; exit 1 ;;
esac
