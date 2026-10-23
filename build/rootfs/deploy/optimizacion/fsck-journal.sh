#!/bin/bash
# fsck-journal.sh — rootfs de la uke: backup + e2fsck en "frio" (+ journal opcional). 23-oct-2026, sesion ram-optim.
# Motivo: dumpe2fs -h /dev/sda32 -> "not clean with errors", 10 errores desde el arranque v7 (22-oct 23:35), y el ext4 SIN has_journal.
# Mismo flujo que fsck-resize.sh del 21-oct (que funciono): parar el escritorio, journald enmascarado en RUNTIME, remount ro, e2fsck, sysrq-b.
#
#   pre      : solo lectura. Gates: USB vivo, bateria, espacio en el PC, estado del fs, turnos, quien esta conectado.
#   backup   : tar del rootfs al PC (solo lectura en la tablet). Excluye lo regenerable (Steam, ~/.cache, cache de pacman).
#   fsck     : SOLO por USB (192.168.42.129). Para escritorio/red, enmascara journald (--runtime), remount ro, e2fsck -fn/-fy x2/-fn.
#              NO reinicia. Deja la tablet en ro: el siguiente paso es 'journal' (opcional) y luego 'reboot'.
#   journal  : (opcional, decision del dueno) tune2fs -O has_journal con el fs limpio y montado ro, y e2fsck -fn de nuevo.
#              OJO: el /ukeinit actual monta 'ro,noload' => el kernel NO carga el journal (fs/ext4/super.c:5517-5537); queda inerte
#              hasta un boot.img con ukeinit sin 'noload' (ciclo de flash aparte). Inerte = no cambia el comportamiento.
#   reboot   : sync + sysrq s,b. Exige consola ACM con UN lector armado (uke-console-cap.sh) y el dueno delante.
#   post     : solo lectura. Estado del fs, features, errores EXT4, unidades fallidas, servicios clave.
# Un paso cada vez; cada uno se para si su gate falla.
set -u
HERE=$(cd "$(dirname "$0")" && pwd); R=$(cd "$HERE/../../../.." && pwd)
KEY=${UKE_KEY:-$R/build/rootfs/uke-arch-root}
USB=root@192.168.42.129; HOST=${UKE_HOST:-$USB}
DEV=/dev/sda32
S() { timeout "${T:-900}" ssh -i "$KEY" -o BatchMode=yes -o ConnectTimeout=8 "$HOST" "$@"; }
BK=${UKE_BK:-$HOME/backups/uke-rootfs-$(date +%Y%m%d).tar.zst}
LOG=$R/build/logs/fsck-journal-$(date +%Y%m%d-%H%M).log
need_usb() { [ "$HOST" = "$USB" ] || { echo "ABORTADO: '$1' solo por USB ($USB): se para la red de la tablet"; exit 2; }
	# 23-oct 02:17: una "prueba de gate" ejecuto 'fsck' de verdad (el HOST por defecto ya es el USB) y paro el escritorio.
	# Desde entonces, los pasos que escriben exigen confirmacion interactiva en un terminal.
	[ -t 0 ] || { echo "ABORTADO: '$1' exige terminal interactivo (confirmacion del dueno)"; exit 2; }
	read -r -p "Paso '$1' en la tablet: escribe '$1-SI' para seguir: " ok; [ "$ok" = "$1-SI" ] || { echo cancelado; exit 2; }; }
case "${1:-}" in
pre)
	echo "== PC: espacio en $(dirname "$BK")"; df -h "$(dirname "$BK")" | tail -1
	avail=$(df -BG --output=avail "$(dirname "$BK")" | tail -1 | tr -dc 0-9); [ "$avail" -ge 15 ] || echo "FALLA: <15 GB libres en el PC"
	S 'echo "== tablet: $(uname -r) up $(cut -d. -f1 /proc/uptime)s"
	   echo "bateria $(cat /sys/class/power_supply/qcom-battmgr-bat/capacity)% $(cat /sys/class/power_supply/qcom-battmgr-bat/status)"
	   dumpe2fs -h '$DEV' 2>/dev/null | grep -E "state|features|FS Error count|Last error time"
	   findmnt -no OPTIONS /; df -h / | tail -1
	   ls -d /run/uke-turno-*.d 2>/dev/null | while read d; do echo "TURNO $d: $(head -1 $d/dueno)"; done
	   echo "sesiones ssh root: $(pgrep -c sshd-session)"; who'
	;;
backup)
	mkdir -p "$(dirname "$BK")"
	# 23-oct: el PC estaba al 99 % (14 GB libres para ~12 GiB sin comprimir). Vigilante: si el disco del PC baja de
	# MINFREE_GB, mata el tar remoto y borra el backup a medias (que no se llene el disco del PC). Nivel zstd por ZLVL.
	MINFREE_GB=${MINFREE_GB:-4}
	( while sleep 5; do f=$(df -BG --output=avail "$(dirname "$BK")" | tail -1 | tr -dc 0-9)
	    [ "$f" -lt "$MINFREE_GB" ] && { echo "ABORTADO: PC con ${f} GB libres (<${MINFREE_GB})"; pkill -f "zstd -T4 -${ZLVL:-9}"; exit 1; }; done ) &
	W=$!
	S "tar -C / --one-file-system --exclude=./proc --exclude=./sys --exclude=./dev --exclude=./run --exclude=./tmp \
	   --exclude=./home/omarchy/.local/share/Steam --exclude=./home/omarchy/.cache --exclude=./var/cache/pacman/pkg \
	   --exclude=./swapfile -cf - ." | zstd -T4 -${ZLVL:-9} > "$BK"; ps=("${PIPESTATUS[@]}")
	kill $W 2>/dev/null
	# tar en un fs vivo da 1 («file changed as we read it»): aceptable; >1 o zstd !=0 = fallo
	[ "${ps[0]}" -le 1 ] && [ "${ps[1]}" -eq 0 ] || { echo "backup FALLO (ssh/tar=${ps[0]} zstd=${ps[1]}): borro $BK"; rm -f "$BK"; exit 1; }
	zstd -t "$BK" && sha256sum "$BK" | tee "$BK.sha256" && ls -la "$BK" ;;
fsck) need_usb fsck; mkdir -p "$(dirname "$LOG")"
	S 'set -u; echo "gate: dispositivo '$DEV' = $(findmnt -no SOURCE /)"
	[ "$(findmnt -no SOURCE /)" = '$DEV' ] || { echo ABORTADO: / no es '$DEV'; exit 2; }
	echo "== parar escritorio y red (USB sigue: usb0 es de networkd)"
	systemctl stop sddm.service user@1001.service 2>&1 | tail -2
	for u in uke-touch uke-lapiz uke-gestures uke-idle-guard uke-bateria-log uke-camaras-lente tailscaled NetworkManager wpa_supplicant bluetooth udisks2 upower earlyoom systemd-coredumpd chronyd uke-navidrome-fwd; do systemctl stop $u.service 2>/dev/null; done
	systemctl mask --runtime --now systemd-journald.service systemd-journald.socket systemd-journald-dev-log.socket systemd-journald-audit.socket 2>&1 | tail -1
	sync; sleep 1
	if ! mount -o remount,ro /; then echo "remount ro FALLO (EBUSY): quien escribe:"; fuser -vm / 2>&1 | head -40; exit 3; fi
	findmnt -no OPTIONS /
	echo "== inventario (-fn)"; e2fsck -fn '$DEV' 2>&1 | tail -25; echo "rc_inv=${PIPESTATUS[0]}"
	for i in 1 2; do echo "== reparacion $i (-fy)"; e2fsck -f -y '$DEV' 2>&1 | tail -12; echo "rc$i=${PIPESTATUS[0]}"; done
	echo "== verificacion (-fn)"; e2fsck -fn '$DEV' 2>&1 | tail -4; echo "rc_ver=${PIPESTATUS[0]}"
	dumpe2fs -h '$DEV' 2>/dev/null | grep -E "state|FS Error count|features"
	echo "LISTO: la tablet queda en ro y sin escritorio. Siguiente: journal (opcional) y reboot."' 2>&1 | tee "$LOG" ;;
journal) need_usb journal
	S 'set -u; [ "$(findmnt -no OPTIONS / | cut -d, -f1)" = ro ] || { echo "ABORTADO: / no esta en ro (haz fsck antes)"; exit 2; }
	dumpe2fs -h '$DEV' 2>/dev/null | grep -q "^Filesystem state: *clean$" || { echo "ABORTADO: fs no limpio"; exit 2; }
	dumpe2fs -h '$DEV' 2>/dev/null | grep -q has_journal && { echo "ya tiene journal"; exit 0; }
	tune2fs -O has_journal '$DEV'; echo rc_tune=$?
	e2fsck -fn '$DEV' 2>&1 | tail -3; echo "rc_ver=${PIPESTATUS[0]}"
	dumpe2fs -h '$DEV' 2>/dev/null | grep -E "state|features|Journal size"' 2>&1 | tee -a "${LOG%.log}-journal.log" ;;
reboot) need_usb reboot
	read -r -p "Consola ACM armada con UN lector (uke-console-cap.sh) y dueno delante? escribe SI: " ok; [ "$ok" = SI ] || exit 2
	S 'sync; sync; echo s > /proc/sysrq-trigger; sleep 2; echo b > /proc/sysrq-trigger' ;;
post) S 'uname -r; findmnt -no OPTIONS /; dumpe2fs -h '$DEV' 2>/dev/null | grep -E "state|features|FS Error count|Mount count|Last checked"
	journalctl -b 0 -k --no-pager | grep -E "EXT4-fs" | head; systemctl --failed --no-legend
	for u in sddm sshd tailscaled NetworkManager uke-touch uke-zram earlyoom systemd-journald; do printf "%s=%s " $u $(systemctl is-active $u); done; echo; swapon --show' ;;
*) echo "uso: $0 pre|backup|fsck|journal|reboot|post"; exit 2 ;;
esac
