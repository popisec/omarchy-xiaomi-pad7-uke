#!/bin/bash
# boot/deploy.sh — instala en la tablet (ouke4) la persistencia de E2d: modulos, servicio y (aparte) armado. NO carga NADA.
#
# SIN --go ni --check: SOLO verifica el arbol local (shas de los .ko, vermagic == release ouke4, sintaxis, tests con mocks) e imprime el plan
#                      sin abrir ninguna conexion.
# --check (sin --go):  lectura por SSH: nada se escribe, nada se carga.
# --go + partes:       ejecuta SOLO las partes elegidas (al menos una). NADA de lo que instala se carga ni se arranca:
#   --module    uke_audio_e2d.ko, uke_audio_e3.ko, uke_audio_e4a.ko y uke_audio_e4b.ko (estos tres SIN usar al arrancar) -> /lib/modules/<krel>/extra/, snd-q6apm-uke.ko -> /lib/modules/<krel>/updates/snd-q6apm.ko,
#               /etc/modprobe.d/uke-audio.conf, depmod -a <krel>
#   --service   uke-audio.service (SIN habilitar) + uke-audio-up.sh + la version de uke-bootguard de build/rootfs/deploy/arranque (con 'audio')
#               + /etc/uke/LEEME; daemon-reload
#   --arm       systemctl enable uke-audio.service + uke-bootguard reset audio (el audio arrancara en cada arranque). Hazlo SOLO tras probar
#               `uke-audio-up.sh` a mano (la carga en caliente ya esta medida; en frio NO).
#   --revert    deshabilita y borra lo instalado por este script (servicio, script, uke-audio.conf, uke_audio_e2d.ko y el snd-q6apm de updates/) + depmod
# Rollback del boot: no aplica (no toca boot_a). Apagarlo sin reflashear: touch /etc/uke/no-audio  (o /etc/uke/safe-mode).
# NUNCA toca: la blacklist de apr (uke-carga.conf), uke-carga/uke-wifi/uke-bt, remoteproc, /dev/ttyACM0, el slot ni el boot.img.
set -u
set -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
A=$(cd "$HERE/.." && pwd)
R=$(cd "$A/../../../.." && pwd)
HOSTIP=${HOSTIP:-192.168.42.129}; KEY=$R/build/rootfs/uke-arch-root
KREL=7.2.9-senemos.1.4054.3-ouke4
GO=0; CHECK=0; MODULE=0; SERVICE=0; ARM=0; REVERT=0
say() { printf '[deploy-audio %s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { say "ABORTADO: $*"; exit 2; }
while [ $# -gt 0 ]; do
	case "$1" in
		--go) GO=1 ;; --check) CHECK=1 ;; --module) MODULE=1 ;; --service) SERVICE=1 ;; --arm) ARM=1 ;; --revert) REVERT=1 ;;
		--host) shift; HOSTIP=$1 ;; --key) shift; KEY=$1 ;;
		-h|--help) awk 'NR>1 && /^set -u/{exit} NR>1' "$0"; exit 0 ;;
		*) die "opcion desconocida: $1" ;;
	esac; shift
done
PARTS=$((MODULE + SERVICE + ARM + REVERT))
[ "$REVERT" = 1 ] && [ $((MODULE + SERVICE + ARM)) -gt 0 ] && die "--revert no se combina con instalar"
[ "$GO" = 1 ] && [ "$PARTS" = 0 ] && die "--go sin partes: elige --module --service --arm (o --revert)"
SSHO="-i $KEY -o BatchMode=yes -o ConnectTimeout=8"

# ---------------------------------------------------------------- verificacion LOCAL (siempre)
say "== verificacion local =="
for f in out/uke_audio_e2d.ko out/uke_audio_e3.ko out/snd-q6apm-uke.ko boot/root/usr/local/sbin/uke-audio-up.sh boot/root/etc/systemd/system/uke-audio.service boot/root/etc/modprobe.d/uke-audio.conf; do
	[ -s "$A/$f" ] || die "falta $f"
done
for k in uke_audio_e2d uke_audio_e3 uke_audio_e4a uke_audio_e4b snd-q6apm-uke; do
	vm=$(modinfo -F vermagic "$A/out/$k.ko" | cut -d' ' -f1)
	[ "$vm" = "$KREL" ] || die "$k.ko vermagic '$vm' != $KREL (¿reconstruiste con otro arbol? build-module.sh / q6apm-port/build.sh)"
	say "  ok  $k.ko vermagic $vm ($(sha256sum "$A/out/$k.ko" | cut -c1-16))"
done
bash -n "$HERE/root/usr/local/sbin/uke-audio-up.sh" && say "  ok  uke-audio-up.sh sintaxis"
"$HERE/harness/test-audio-up.sh" > /tmp/uke-audio-test.$$ 2>&1 && say "  ok  harness/test-audio-up.sh ($(tail -1 /tmp/uke-audio-test.$$))" || { tail -15 /tmp/uke-audio-test.$$; rm -f /tmp/uke-audio-test.$$; die "falla la prueba con mocks"; }
rm -f /tmp/uke-audio-test.$$
bash "$R/build/rootfs/deploy/arranque/deploy.sh" check >/dev/null 2>&1 && say "  ok  arranque/deploy.sh check (guarda con 'audio')" || die "arranque/deploy.sh check falla"
grep -q '^KNOWN=.*\baudio\b' "$R/build/rootfs/deploy/arranque/root/usr/local/sbin/uke-bootguard" || die "uke-bootguard del repo no conoce 'audio'"

P_MOD="no"; P_SRV="no"; P_ARM="no"
[ "$MODULE" = 1 ] && P_MOD="SI: uke_audio_e2d.ko (extra/), snd-q6apm-uke.ko (updates/snd-q6apm.ko), uke-audio.conf, depmod (NO carga nada)"
[ "$SERVICE" = 1 ] && P_SRV="SI: uke-audio.service (SIN enable), uke-audio-up.sh, uke-bootguard (con 'audio'), LEEME, daemon-reload"
[ "$ARM" = 1 ] && P_ARM="SI: systemctl enable uke-audio.service + uke-bootguard reset audio (el audio arrancara en cada arranque)"
cat <<EOP

PLAN (tablet $HOSTIP, release exigida $KREL):
  1. --module  : $P_MOD
  2. --service : $P_SRV
  3. --arm     : $P_ARM
  REVERT=$REVERT  CHECK=$CHECK  GO=$GO
EOP
if [ "$GO" = 0 ] && [ "$CHECK" = 0 ]; then
	say "Nada ejecutado (sin --go ni --check: no se abrio ninguna conexion). Para aplicar:  $0 --go --module [--service] [--arm]"; exit 0
fi

# ---------------------------------------------------------------- remoto
rssh() { ssh $SSHO root@"$HOSTIP" "$@"; }
rem_state() {
	rssh 'uname -r; echo "uke-audio.service: $(systemctl is-enabled uke-audio.service 2>&1 | head -1) / $(systemctl is-active uke-audio.service 2>&1 | head -1)";
	      modinfo -n snd-q6apm 2>&1; ls /lib/modules/'"$KREL"'/extra /lib/modules/'"$KREL"'/updates 2>&1 | head -12;
	      for r in /sys/class/remoteproc/remoteproc*; do echo "$(cat $r/name) $(cat $r/state) rec=$(cat $r/recovery)"; done;
	      lsmod | grep -E "^(apr|snd_q6apm|q6prm|uke_audio)" | cut -d" " -f1 | tr "\n" " "; echo; cat /sys/class/power_supply/qcom-battmgr-bat/status'
}
[ "$(rssh uname -r 2>/dev/null)" = "$KREL" ] || die "la tablet no esta en $KREL (o sin SSH)"
if [ "$GO" = 0 ]; then say "== --check remoto (solo lectura) =="; rem_state; exit 0; fi

if [ "$REVERT" = 1 ]; then
	say "== --revert =="
	rssh "systemctl disable uke-audio-amps.service 2>&1 | tail -1; systemctl disable uke-audio.service 2>&1 | tail -1; rm -fv /etc/systemd/system/uke-audio-amps.service /etc/systemd/system/uke-audio-amps.service.d/e9a.conf /usr/local/sbin/uke-audio-amps-up.sh /etc/systemd/system/uke-audio.service /usr/local/sbin/uke-audio-up.sh /etc/modprobe.d/uke-audio.conf /lib/modules/$KREL/extra/uke_audio_e2d.ko /lib/modules/$KREL/extra/uke_audio_e3.ko /lib/modules/$KREL/extra/uke_audio_e4a.ko /lib/modules/$KREL/extra/uke_audio_e4b.ko /lib/modules/$KREL/updates/snd-q6apm.ko; depmod -a $KREL; systemctl daemon-reload; sync; echo 'NO se descarga nada cargado: usa uke-audio-up.sh --down antes si estaba arriba'"
	rem_state; exit 0
fi
if [ "$MODULE" = 1 ]; then
	say "== 1. modulos =="
	scp $SSHO "$A/out/uke_audio_e2d.ko" root@"$HOSTIP":/root/uke_audio_e2d.ko >/dev/null || die "scp e2d"
	scp $SSHO "$A/out/uke_audio_e3.ko" root@"$HOSTIP":/root/uke_audio_e3.ko >/dev/null || die "scp e3"
	scp $SSHO "$A/out/uke_audio_e4a.ko" root@"$HOSTIP":/root/uke_audio_e4a.ko >/dev/null || die "scp e4a"
	scp $SSHO "$A/out/uke_audio_e4b.ko" root@"$HOSTIP":/root/uke_audio_e4b.ko >/dev/null || die "scp e4b"
	scp $SSHO "$A/out/snd-q6apm-uke.ko" root@"$HOSTIP":/root/snd-q6apm-uke.ko >/dev/null || die "scp q6apm"
	scp $SSHO "$HERE/root/etc/modprobe.d/uke-audio.conf" root@"$HOSTIP":/etc/modprobe.d/uke-audio.conf >/dev/null || die "scp conf"
	rssh "set -e; K=$KREL; mkdir -p /lib/modules/\$K/extra /lib/modules/\$K/updates; install -m644 /root/uke_audio_e2d.ko /lib/modules/\$K/extra/uke_audio_e2d.ko; install -m644 /root/uke_audio_e3.ko /lib/modules/\$K/extra/uke_audio_e3.ko; install -m644 /root/uke_audio_e4a.ko /lib/modules/\$K/extra/uke_audio_e4a.ko; install -m644 /root/uke_audio_e4b.ko /lib/modules/\$K/extra/uke_audio_e4b.ko; install -m644 /root/snd-q6apm-uke.ko /lib/modules/\$K/updates/snd-q6apm.ko; chmod 644 /etc/modprobe.d/uke-audio.conf; depmod -a \$K; sync;
	      echo \"snd-q6apm viene de: \$(modinfo -n snd-q6apm)\"; sha256sum /lib/modules/\$K/updates/snd-q6apm.ko /lib/modules/\$K/extra/uke_audio_e2d.ko /lib/modules/\$K/extra/uke_audio_e3.ko | cut -c1-16"
fi
if [ "$SERVICE" = 1 ]; then
	say "== 2. servicio =="
	tar -C "$HERE/root" --owner=0 --group=0 --numeric-owner --no-recursion -cf - etc/systemd/system/uke-audio.service usr/local/sbin/uke-audio-up.sh | rssh 'tar -x --no-same-owner -C / && chmod 0755 /usr/local/sbin/uke-audio-up.sh && chmod 0644 /etc/systemd/system/uke-audio.service'
	tar -C "$R/build/rootfs/deploy/arranque/root" --owner=0 --group=0 --numeric-owner -cf - usr/local/sbin/uke-bootguard etc/uke/LEEME | rssh 'tar -x --no-same-owner -C / && chmod 0755 /usr/local/sbin/uke-bootguard'
	rssh 'systemctl daemon-reload; systemd-analyze verify --man=no /etc/systemd/system/uke-audio.service 2>&1 | sed "s/^/  verify: /" || true; echo "uke-audio.service: $(systemctl is-enabled uke-audio.service 2>&1 | head -1) (NO habilitado)"'
fi
if [ "$ARM" = 1 ]; then
	say "== 3. ARMAR =="
	rssh '[ -f /etc/systemd/system/uke-audio.service ] && [ -x /usr/local/sbin/uke-audio-up.sh ] || { echo "falta el servicio: aplica --service" >&2; exit 1; }
	      grep -q "^KNOWN=.*\baudio\b" /usr/local/sbin/uke-bootguard || { echo "uke-bootguard no conoce audio: aplica --service" >&2; exit 1; }
	      modinfo -n snd-q6apm | grep -q /updates/ || { echo "snd-q6apm de updates/ no instalado: aplica --module" >&2; exit 1; }
	      systemctl enable uke-audio.service; /usr/local/sbin/uke-bootguard reset audio; echo "ARMADO: el audio arrancara en cada arranque (apagarlo: touch /etc/uke/no-audio)"'
fi
say "== estado final =="; rem_state
echo "Para probar a mano (con orden del dueño): ssh ... /usr/local/sbin/uke-audio-up.sh   (y --down para descargar)"
