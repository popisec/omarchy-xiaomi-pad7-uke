#!/bin/bash
# verify.sh [pre|post] -- comprobaciones SOLO LECTURA en la tablet (root). exit = numero de FALLOS.
#   pre  : antes de instalar (kernel, RAM, espacio, firmware de la GPU, red de rescate, estado de la DRM)
#   post : despues de instalar+configurar (binarios, ldd, DB de pacman, usuario, sddm, migraciones, modos)
set -uo pipefail
MODE=${1:-post}
U=${DESKTOP_USER:-omarchy}
RD=${RD:-/root/uke-omarchy}
fails=0; warns=0
ok() { printf '  OK     %s\n' "$*"; }
warn() { printf '  WARN   %s\n' "$*"; warns=$((warns + 1)); }
bad() { printf '  FALLO  %s\n' "$*"; fails=$((fails + 1)); }
sec() { printf '\n== %s ==\n' "$*"; }

# sha256 del firmware de la GPU (vendor_a:/firmware de ESTA tablet; el zap no es el del repo qrd8635). Ver manifest/README del informe.
FW_GMU=435c7bac9a328b8a100df930b84b65b4d579e42be44785d0e60e3729291bb864
FW_SQE=b6df660d109504dbea5a266910b037a33d893a11c6de52f524a5fd112008c401
FW_ZAP=0c86e4ae6ed618101949965df451510a3216e0f0de1aef4920bd1888a15ea8e6

sec "sistema"
echo "  kernel: $(uname -r) | $(uname -m) | uptime: $(uptime -p)"
mem=$(awk '/MemTotal/{print $2}' /proc/meminfo)
[ "$mem" -ge 6000000 ] && ok "MemTotal $((mem / 1024)) MiB" || bad "MemTotal $((mem / 1024)) MiB (<6000: OOM seguro)"
free=$(df -Pm / | awk 'NR==2{print $4}')
if [ "$MODE" = pre ]; then [ "$free" -ge 2800 ] && ok "libres $free MiB" || bad "libres $free MiB (<2800)"; else ok "libres $free MiB"; fi
grep -o 'systemd.unit=[^ ]*' /proc/cmdline | sed 's/^/  cmdline: /'
grep -oE 'msm[._]*separate_gpu_kms=[0-9]|msm\.[a-z_]+=[^ ]*' /proc/cmdline | sed 's/^/  cmdline: /'
systemctl is-active systemd-networkd >/dev/null 2>&1 && ok "systemd-networkd activo (SSH por usb0)" || bad "systemd-networkd no activo"
systemctl is-enabled NetworkManager >/dev/null 2>&1 && warn "NetworkManager enabled: pelea con networkd por usb0" || ok "NetworkManager sin habilitar"
ip -br a show usb0 2>/dev/null | sed 's/^/  /' || warn "sin usb0"

sec "GPU: firmware (el kernel lo pide a /lib/firmware/qcom/...; adreno_request_fw prueba qcom/ y luego la raiz)"
for pair in "gen71100_gmu.bin:$FW_GMU" "gen71100_sqe.fw:$FW_SQE" "gen71100_zap.mbn:$FW_ZAP"; do
  f=${pair%%:*}; h=${pair#*:}
  for d in /lib/firmware/qcom /lib/firmware; do
    if [ -f "$d/$f" ]; then
      [ "$(sha256sum "$d/$f" | cut -d' ' -f1)" = "$h" ] && ok "$d/$f sha ${h:0:12}" || bad "$d/$f sha DISTINTO"
    else warn "$d/$f no existe"; fi
  done
done

sec "GPU: estado del kernel (no implica nada hasta que la GPU haya probado)"
ls -l /dev/dri 2>&1 | sed 's/^/  /'
for d in /sys/class/drm/card[0-9]*; do
  [[ ${d##*/} == *-* ]] && continue
  echo "  ${d##*/}: driver=$(grep -m1 DRIVER= "$d/device/uevent" 2>/dev/null | cut -d= -f2) conectores=$(ls -d "$d"/"${d##*/}"-* 2>/dev/null | wc -l)"
done
# (sin `grep -q` en tuberia: con pipefail el SIGPIPE de dmesg daria falso negativo)
gl=$(dmesg | grep -iE 'adreno|gmu|a7xx' | tail -6)
if [ -n "$gl" ]; then ok "dmesg con lineas adreno/gmu:"; printf '%s\n' "$gl" | sed 's/^/     /'; else warn "dmesg sin adreno/gmu: la GPU no ha probado (¿gpucc-cliffs.ko cargado? ¿modulos instalados + depmod?)"; fi
dmesg | grep -iE 'gpu.*(fault|timeout|hang)|a6xx.*(error|fail)|gmu.*(fail|timeout)' | tail -4 | sed 's/^/  PROBLEMA: /'
lsmod 2>/dev/null | grep -iE 'gpucc|qcom_aoss|^msm' | sed 's/^/  lsmod: /'

if [ "$MODE" = pre ]; then
  sec "paquetes: base antes de instalar"
  echo "  registrados en pacman: $(pacman -Qq | wc -l)"
  for p in libdrm cairo; do pacman -Q "$p" >/dev/null 2>&1 && echo "  ya instalado: $(pacman -Q "$p") (los de modetest de L76R se saltan solos con --needed)"; done
  [ -e /var/lib/pacman/db.lck ] && warn "db.lck presente"
  ok "preflight terminado (solo lectura)"
  echo; echo "RESULTADO pre: fallos=$fails avisos=$warns"; exit "$fails"
fi

sec "binarios de la sesion"
for b in Hyprland start-hyprland hyprctl quickshell sddm sddm-greeter-qt6 uwsm uwsm-app grim slurp hyprlock hypridle foot kitty; do
  command -v "$b" >/dev/null 2>&1 && ok "$b -> $(command -v "$b")" || { case $b in grim|slurp|hyprlock|hypridle|foot|kitty) warn "falta $b (extra)";; *) bad "falta $b";; esac; }
done
for b in /usr/bin/Hyprland /usr/bin/quickshell /usr/bin/sddm /usr/bin/sddm-greeter-qt6 /usr/bin/Xwayland /usr/bin/hyprlock; do
  [ -x "$b" ] || continue
  nf=$(ldd "$b" 2>&1 | grep -c 'not found')
  [ "$nf" = 0 ] && ok "ldd $b: sin 'not found'" || { bad "ldd $b: $nf librerias sin resolver"; ldd "$b" 2>&1 | grep 'not found' | sed 's/^/       /'; }
done
ft=$(file -L /usr/bin/Hyprland 2>/dev/null); case $ft in *"ARM aarch64"*) ok "Hyprland es ELF aarch64" ;; *) warn "no se pudo confirmar aarch64 ($ft)" ;; esac

sec "Mesa/freedreno"
ls /usr/lib/dri/msm_dri.so /usr/lib/dri/kms_swrast_dri.so /usr/lib/gbm/dri_gbm.so /usr/lib/libEGL_mesa.so.0 2>&1 | sed 's/^/  /'
ls /usr/lib/libgallium-*.so >/dev/null 2>&1 && ok "libgallium: $(ls /usr/lib/libgallium-*.so | tr '\n' ' ')" || bad "falta libgallium (mesa)"
[ -f /usr/share/vulkan/icd.d/freedreno_icd.aarch64.json ] && ok "vulkan-freedreno presente" || warn "sin vulkan-freedreno (no hace falta para Hyprland/GLES)"
command -v eglinfo >/dev/null 2>&1 && warn "eglinfo presente (mesa-utils): usalo como usuario con la sesion viva" || warn "sin eglinfo (mesa-utils): la prueba GL sale de hyprland.log + fdinfo"

sec "pacman"
n=$(pacman -Qq | wc -l); echo "  registrados: $n"
if [ -f "$RD/nombres.txt" ]; then
  miss=0; while read -r p; do [ -n "$p" ] && { pacman -Q "$p" >/dev/null 2>&1 || { bad "no registrado: $p"; miss=1; }; }; done <"$RD/nombres.txt"
  [ "$miss" = 0 ] && ok "los $(wc -l <"$RD/nombres.txt") paquetes de la lista estan registrados"
fi
out=$(pacman -Qk 2>&1 | grep -v ' 0 missing files' | head -8); [ -z "$out" ] && ok "pacman -Qk: 0 ficheros faltantes en toda la DB" || { warn "pacman -Qk:"; echo "$out" | sed 's/^/     /'; }
for h in 90-mkinitcpio-install.hook 60-mkinitcpio-remove.hook; do [ "$(readlink /etc/pacman.d/hooks/$h 2>/dev/null)" = /dev/null ] && ok "hook $h anulado" || warn "hook $h activo"; done

sec "usuario $U, sddm, migraciones"
if getent passwd "$U" >/dev/null; then
  ok "$(id "$U")"
  home=$(getent passwd "$U" | cut -d: -f6)
  [ "$(stat -c %U "$home")" = "$U" ] && ok "home $home de $U" || bad "home $home no es de $U"
  [ -f "$home/.config/hypr/hyprland.lua" ] && ok "~/.config/hypr/hyprland.lua (skel)" || bad "falta ~/.config/hypr/hyprland.lua"
  nm=$(ls "$home/.local/state/omarchy/migrations" 2>/dev/null | wc -l); tot=$(ls /usr/share/omarchy/migrations/*.sh 2>/dev/null | wc -l)
  [ "$nm" = "$tot" ] && ok "migraciones selladas $nm/$tot (omarchy-migrate --pending vacio)" || bad "migraciones selladas $nm/$tot: omarchy-migrate abortaria con red/pacman"
else bad "no existe el usuario $U"; fi
cat /etc/sddm.conf.d/*.conf 2>/dev/null | grep -vE '^(#|$)' | sed 's/^/  sddm.conf.d: /'
grep -q "^User=$U" /etc/sddm.conf.d/20-uke-autologin.conf 2>/dev/null && ok "autologin User=$U Session=omarchy" || bad "autologin no configurado"
[ -f /usr/local/share/wayland-sessions/omarchy.desktop ] && ok "sesion omarchy.desktop" || bad "falta omarchy.desktop"
[ -f /usr/share/wayland-sessions/hyprland.desktop ] && ok "hyprland.desktop (lo usa uwsm)" || bad "falta /usr/share/wayland-sessions/hyprland.desktop"
systemctl is-enabled sddm >/dev/null 2>&1 && ok "sddm enabled" || bad "sddm no enabled"
getent passwd sddm >/dev/null && ok "usuario sddm creado (sysusers)" || bad "sin usuario sddm"
for w in /usr/local/bin/omarchy-pkg-add /usr/local/bin/omarchy-update-restart; do [ -x "$w" ] && ok "wrapper $w" || warn "falta wrapper $w"; done
[ "$(readlink /etc/os-release)" = "" ] && grep -q '^ID=omarchy' /etc/os-release && ok "/etc/os-release = Omarchy (omarchy-settings)" || warn "/etc/os-release no es el de Omarchy"
ls /usr/share/fonts 2>/dev/null | tr '\n' ' ' | sed 's/^/  fuentes: /'; echo
fc-list 2>/dev/null | grep -ci 'JetBrainsMono' | sed 's/^/  JetBrainsMono nerd (variantes): /'

echo; echo "RESULTADO post: fallos=$fails avisos=$warns"
exit "$fails"
