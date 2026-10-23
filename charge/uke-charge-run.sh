#!/bin/bash
# uke-charge-run.sh — EL GUION DE UN COMANDO (se corre en el PC cuando la
# tablet vuelva por RNDIS/USB). Despliega el stack de carga y da el veredicto.
#
# Lo que hace:
#   1. Espera SSH (RNDIS 192.168.42.129, clave build/rootfs/uke-arch-root).
#   2. Lee `uname -r` y elige charge/mods-<release> EXACTO (gate: si no hay
#      variante para ese release, PARA y lo dice — no se fuerza nada).
#   3. Copia .ko -> /usr/local/share/uke/mods/ (fuera de udev/kmod),
#      firmware -> /lib/firmware/ (verifica 49 segmentos),
#      loader + .service, daemon-reload, enable, start.
#   4. Imprime el VEREDICTO: status / current_now / charge_type.
#
# Uso: charge/uke-charge-run.sh [deploy|verdict]
#   deploy  = pasos 1-4 (defecto). verdict = solo paso 4 (re-sondeo rápido).
set -u
R="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
KEY=$R/build/rootfs/uke-arch-root
H=root@192.168.42.129
SSHOPTS="-i $KEY -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
MODE=${1:-deploy}

say() { printf '\n=== %s\n' "$*"; }
ssh_t() { timeout "${2:-30}" ssh $SSHOPTS $H "$1" 2>&1; }
have_ssh() { timeout 8 ssh $SSHOPTS $H 'true' >/dev/null 2>&1; }

[ -f "$KEY" ] || { echo "falta la clave $KEY"; exit 1; }

say "1. contacto SSH"
for i in $(seq 1 36); do
	have_ssh && { echo "  ssh vivo"; break; }
	[ "$i" = "36" ] && { echo "sin SSH tras 3 min: reset físico (Power 12-15 s)"; exit 1; }
	sleep 5
done

say "2. release del kernel y selección de módulos"
REL=$(ssh_t 'uname -r')
echo "  tablet: $REL"
MODSRC=$R/charge/mods-$REL
if [ "$MODE" = "verdict" ]; then :; else
	[ -d "$MODSRC" ] || { echo "NO HAY variante para $REL (hay: $(ls -d $R/charge/mods-* 2>/dev/null | xargs -n1 basename))"; exit 1; }
	for ko in "$MODSRC"/*.ko; do
		v=$(modinfo -F vermagic "$ko")
		[ "$v" = "$REL SMP preempt mod_unload aarch64" ] \
			|| { echo "VERMAGIC ROTO en $ko: $v"; exit 1; }
	done
	echo "  mods-$REL: $(ls "$MODSRC"/*.ko | wc -l) .ko, vermagic OK"
fi

if [ "$MODE" != "verdict" ]; then
	say "3. despliegue"
	scp -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
		-i "$KEY" "$MODSRC"/*.ko "$H:/tmp/uke-mods-stage/" 2>/dev/null || {
		ssh_t 'mkdir -p /tmp/uke-mods-stage /usr/local/share/uke/mods'
		scp -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
			-i "$KEY" "$MODSRC"/*.ko "$H:/tmp/uke-mods-stage/" || exit 1
	}
	ssh_t 'mkdir -p /usr/local/share/uke/mods; cp -f /tmp/uke-mods-stage/*.ko /usr/local/share/uke/mods/; ls /usr/local/share/uke/mods/'
	nfw=$(ls "$R"/charge/firmware/adsp.b?? 2>/dev/null | wc -l)
	echo "  firmware en proyecto: $nfw segmentos"
	ssh_t 'n=$(ls /lib/firmware/adsp.b?? 2>/dev/null | wc -l); echo "  firmware en tablet: $n segmentos"'
	scp -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
		-i "$KEY" "$R"/charge/firmware/adsp.mdt "$R"/charge/firmware/adsp_dtb.mdt \
		"$R"/charge/firmware/adsp.b?? "$R"/charge/firmware/adsp_dtb.b?? "$H:/lib/firmware/" \
		|| { echo "scp firmware falló (¿tablet sin espacio?)"; exit 1; }
	scp -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
		-i "$KEY" "$R/charge/adsp-fw.sha256" "$H:/lib/firmware/adsp-fw.sha256" \
		|| echo "  AVISO: no se copió adsp-fw.sha256 (el loader quedará en modo aviso, sin verificar)"
	scp -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
		-i "$KEY" "$R/charge/uke-adsp-load.sh" "$H:/usr/local/sbin/uke-adsp-load.sh" || exit 1
	scp -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
		-i "$KEY" "$R/charge/uke-adsp.service" "$H:/etc/systemd/system/uke-adsp.service" || exit 1
	ssh_t 'chmod +x /usr/local/sbin/uke-adsp-load.sh; systemctl daemon-reload; systemctl enable uke-adsp.service; systemctl start uke-adsp.service; sleep 5; systemctl is-active uke-adsp.service'
fi

say "4. VEREDICTO"
ssh_t 'echo "--- remoteproc:"; for r in /sys/class/remoteproc/remoteproc*; do [ -e "$r" ] && echo "  $(cat $r/name 2>/dev/null) state=$(cat $r/state 2>/dev/null)"; done
echo "--- power_supply:"; ls /sys/class/power_supply/ 2>/dev/null || echo "  (VACÍO)"
for p in /sys/class/power_supply/qcom-battmgr-*; do [ -e "$p" ] || continue
  echo "-- $(basename $p): status=$(cat $p/status 2>/dev/null) current_now=$(cat $p/current_now 2>/dev/null) charge_type=$(cat $p/charge_type 2>/dev/null) capacity=$(cat $p/capacity 2>/dev/null) voltage_now=$(cat $p/voltage_now 2>/dev/null)"
done
echo "--- PDR:"; dmesg | grep -i "charger_pd" | tail -n 2'
say "FIN (criterio verde: status=Charging + current_now>0 + charge_type=Fast, cf. ledger #406)"
