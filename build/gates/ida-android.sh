#!/bin/bash
# ida-android.sh — IDA a Android (slot b) para la REFERENCIA DE AUDIO de los FS19xx. BORRADOR del PC (19-oct-2026). **DESTRUCTIVO con --go**: borra userdata+metadata
# (el rootfs Linux). Solo el dueño pone la tablet en fastboot a mano y da la orden de cada fase; filas #662-#666 del ledger hermano.
#   --check          (tablet en Linux, solo lectura por SSH) imagenes del slot b == flash-b/, boot_a/dtbo_a vigentes, misc a ceros, copia de userdata verificada, bateria, espacio.
#   --fastboot-check (tablet en fastboot, solo getvar) producto, slot actual, retry/unbootable, bateria >= 3700 mV, is-userspace.
#   --go             DESTRUCTIVO. Exige:  --backup-sha <sha256 de la imagen reparada>  y  --confirm BORRAR-USERDATA
#                    erase userdata; erase metadata; flash misc (8 KiB de ceros: el BCB actual es `boot-recovery --prompt_and_wipe_data --reason=fs_mgr_mount_all`, medido el 19-oct, y
#                    mandaria Android a recovery / abortaria magiskinit); set_active b. NO escribe boot_b/init_boot_b/dtbo_b (ya son los stock, medido el 19-oct).
#   --plan           imprime el guion completo (no ejecuta nada).
set -u
R=$(cd "$(dirname "$0")/../.." && pwd); KEY=$R/build/rootfs/uke-arch-root; HOSTIP=${HOSTIP:-192.168.42.129}; SSHO="-i $KEY -o BatchMode=yes -o ConnectTimeout=8"
FB=$R/build/android/flash-b; BK=/var/tmp/uke-userdata-backup; BKIMG=${BKIMG:-$BK/userdata-20261019-105504-fsck.img}; LOG=$R/build/logs/ida-android-$(date +%Y%m%d-%H%M%S).log
say() { printf '[ida-android %s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "$LOG"; }; die() { say "ABORTADO: $*"; exit 2; }
rssh() { ssh $SSHO root@"$HOSTIP" "$@"; }
mode=${1:-}; shift || true
rdsha() { rssh "dd if=/dev/disk/by-partlabel/$1 bs=1M count=$(( ($2 + 1048575) / 1048576 )) status=none | head -c $2 | sha256sum | cut -c1-64"; }
case "$mode" in
--check)
	[ "$(rssh uname -r 2>/dev/null)" ] || die "sin SSH (la tablet debe estar en Linux)"
	bad=0
	for t in boot_b:boot-stock.img init_boot_b:init-boot-b-MAGISK.img vendor_boot_b:vendor-boot-stock.img dtbo_b:dtbo-b-stock.img vbmeta_b:vbmeta-b-dump.img vbmeta_system_b:vbmeta-system-b-dump.img; do
		p=${t%%:*}; f=$FB/${t##*:}; sz=$(stat -c %s "$f"); a=$(sha256sum "$f" | cut -c1-64); b=$(rdsha $p $sz)
		[ "$a" = "$b" ] && say "OK   $p == $(basename $f) (${a:0:16}…)" || { say "DIFIERE $p: tablet ${b:0:16}… vs repo ${a:0:16}… → habria que flashearla"; bad=1; }
	done
	ba=$(rdsha boot_a 100663296); case "$ba" in fc9309a3953e8c423b30647b27a151aa740e6473757642ae922ec9cc0aaab88f) say "OK   boot_a == v4 (fc9309a3…) (slot a de Linux: NO se toca)";; f3d3bc82b19e3a59bd5cab3351dc0a8317117a446f9e6f1d25e349ad1249d99b) say "OK   boot_a == v5/ouke5 (f3d3bc82…) (slot a de Linux: NO se toca)";; *) say "AVISO boot_a ni v4 ni v5: ${ba:0:16}…";; esac
	da=$(rdsha dtbo_a 25165824); [ "$da" = 27e61d21fd6a0858135e322eef9e8a223f6612ad24b1913fd7d9d680d602b3d8 ] && say "OK   dtbo_a == stock (27e61d21…)" || say "AVISO dtbo_a != stock: ${da:0:16}…"
	mz=$(rssh "dd if=/dev/disk/by-partlabel/misc bs=8192 count=1 status=none | sha256sum | cut -c1-64"); [ "$mz" = "$(head -c 8192 /dev/zero | sha256sum | cut -c1-64)" ] && say "OK   misc (BCB) a ceros" || say "AVISO misc NO esta a ceros (${mz:0:16}…: BCB boot-recovery --prompt_and_wipe_data): la ida lo limpia con 'fastboot flash misc misc-zeros-8192.img' (fila nueva)"
	[ -f "$BKIMG" ] && [ -f "$BKIMG.sha256" ] || die "falta la copia verificada $BKIMG"
	ex=$(cut -c1-64 "$BKIMG.sha256"); real=$(sha256sum "$BKIMG" | cut -c1-64); [ "$ex" = "$real" ] && say "OK   copia de userdata (reparada) presente y con su sha: ${real:0:16}…" || { say "LA COPIA NO COINCIDE con su .sha256"; bad=1; }
	say "bateria: $(rssh 'cat /sys/class/power_supply/qcom-battmgr-bat/voltage_now /sys/class/power_supply/qcom-battmgr-bat/status' | tr '\n' ' ') (>= 3700000 uV y cargador)"
	say "uke_fs_play=$(rssh cat /sys/module/uke_fs19xx/parameters/uke_fs_play 2>/dev/null) ; modulos de prueba: $(rssh "lsmod | grep -cE 'uke_audio_e[3-8]|uke_fs19xx'")"
	[ $bad = 0 ] && say "RESULTADO: listo para la ida (sin flashes en slot b)" || say "RESULTADO: HAY DIFERENCIAS: revisar antes";;
--fastboot-check)
	command -v fastboot >/dev/null || die "falta fastboot"; fastboot devices | grep -q . || die "ningun dispositivo en fastboot"
	g() { fastboot getvar "$1" 2>&1 | head -1; }
	for v in product current-slot slot-retry-count:a slot-retry-count:b slot-unbootable:a slot-unbootable:b is-userspace battery-voltage; do say "$(g $v)"; done
	bv=$(fastboot getvar battery-voltage 2>&1 | head -1 | grep -o '[0-9]\+' | head -1); [ "${bv:-0}" -ge 3700 ] && say "bateria OK (${bv} mV)" || say "BATERIA INSUFICIENTE (${bv:-?} mV; hace falta >= 3700): no continuar";;
--go)
	bsha=""; conf=""; while [ $# -gt 0 ]; do case "$1" in --backup-sha) bsha=$2; shift 2;; --confirm) conf=$2; shift 2;; *) die "opcion desconocida $1";; esac; done
	[ "$conf" = BORRAR-USERDATA ] || die "falta --confirm BORRAR-USERDATA"
	[ -f "$BKIMG" ] || die "falta la copia $BKIMG"; real=$(sha256sum "$BKIMG" | cut -c1-64); [ "$bsha" = "$real" ] || die "--backup-sha no coincide con la copia (real $real)"
	fastboot devices | grep -q . || die "ningun dispositivo en fastboot"
	bv=$(fastboot getvar battery-voltage 2>&1 | head -1 | grep -o '[0-9]\+' | head -1); [ "${bv:-0}" -ge 3700 ] || die "bateria ${bv:-?} mV < 3700"
	say "GO destructivo con la copia $real; slot b = Android stock (medido)"
	fastboot erase userdata  2>&1 | tee -a "$LOG"; [ "${PIPESTATUS[0]}" = 0 ] || die "erase userdata fallo"
	fastboot erase metadata  2>&1 | tee -a "$LOG"; [ "${PIPESTATUS[0]}" = 0 ] || die "erase metadata fallo"
	M=$R/build/gates/misc-zeros-8192.img; [ "$(sha256sum "$M" | cut -c1-64)" = 9f1dcbc35c350d6027f98be0f5c8b43b42ca52b7604459c0c42be3aa88913d47 ] || die "misc-zeros-8192.img con sha inesperado"
	fastboot flash misc "$M" 2>&1 | tee -a "$LOG"; [ "${PIPESTATUS[0]}" = 0 ] || die "flash misc fallo"
	fastboot --set-active=b  2>&1 | tee -a "$LOG"; [ "${PIPESTATUS[0]}" = 0 ] || die "set_active b fallo"
	say "hecho: erase userdata+metadata + set_active b. Siguiente (el dueño): fastboot reboot cuando quiera."
	;;
--plan)
	cat <<'PLAN'
GUION DE LA IDA A ANDROID (cada fase la autoriza el dueño; filas #662-#666 del ledger hermano; slot b YA es Android stock: medido el 19-oct, 0 flashes en slot b)
 0. Previo (hecho): copia verificada de userdata (#662 PASA). Avisar a las sesiones BT/batería/lápiz/WiFi/etc.: la tablet queda fuera de Linux 1-3 h.
 1. Tablet en Linux:  build/gates/ida-android.sh --check            (solo lectura; todo OK o no se sigue)
 2. El DUEÑO pone la tablet en fastboot a mano (cargador conectado).
 3. build/gates/ida-android.sh --fastboot-check                     (solo getvar: slot, retry, bateria >= 3700 mV)
 4. build/gates/ida-android.sh --go --backup-sha <sha de la reparada> --confirm BORRAR-USERDATA     [DESTRUCTIVO: erase userdata, erase metadata, flash misc (ceros 8 KiB), set_active b]
 5. fastboot reboot. Android arranca sobre userdata vacia: asistente (DUEÑO, ~15-30 min), activar opciones de desarrollador + ADB (+ ADB inalambrico), root Magisk ya en init_boot_b.
 6. adb push build/android/audio-ref-capture.sh /data/local/tmp/ ; (opcional un tone.wav) ; adb shell 'su -c "sh /data/local/tmp/audio-ref-capture.sh 25"' mientras el DUEÑO reproduce un sonido; adb pull.
 7. VUELTA: tablet a fastboot; fastboot flash userdata <img reparada>; fastboot --set-active=a (doble a/b/a si hace falta); fastboot reboot;  build/gates/backup-userdata.sh --restore-plan IMG imprime los comandos.
 8. Post: SSH, misc a ceros si Android dejo bootonce-bootloader (ciclo aparte), ritual adsp.b40, uke-audio/uke-bt/uke-wifi; avisar a las sesiones.
PLAN
	;;
*) sed -n 2,11p "$0"; exit 1;;
esac
