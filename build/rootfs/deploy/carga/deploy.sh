#!/bin/bash
# deploy.sh — instala y verifica la pila de carga del kernel senemos en la tablet.
# Mecanismo: tar | ssh (SIN scp). NO se ejecuta solo: requiere orden del dueño.
#
#   deploy.sh pc                 gates en el PC (sintaxis, shas del firmware, permisos). Sin tablet.
#   deploy.sh check              pre-vuelo SOLO LECTURA en la tablet (uke-carga-verify.sh --pre).
#   deploy.sh install [--with-gadget-late]
#                                pc + pre-vuelo informativo + copia ficheros + repara firmware + enable.
#                                NO arranca el ADSP (eso es `start`). --with-gadget-late añade el gadget USB
#                                tardío (solo hace falta si el DT trae usb-psy-name, o sea kernel v1).
#   deploy.sh start              pre-vuelo DURO (si falla no arranca) + systemctl start uke-carga + verify.
#   deploy.sh verify [--watch N SEG]   checklist (uke-carga-verify.sh) en la tablet.
#   deploy.sh mods [MODROOT] [--dry-run]
#                                OPCIONAL: sube SOLO los .ko de la cadena de carga (+deps) desde
#                                modroot y corre depmod. Úsalo si el modroot completo aún no está
#                                instalado en /lib/modules/<release>. Con --dry-run no toca la tablet
#                                (usa UKE_REL=<release> si no hay tablet).
#   deploy.sh rollback           desinstala los ficheros y el enable (no para el ADSP si ya corre).
#   deploy.sh stage DIR [--with-gadget-late]   extrae el árbol en DIR (raíz montada de una imagen, o prueba en seco)
#                                y crea los symlinks de enable; sin ssh.
#
# Variables: UKE_HOST (def. root@192.168.42.129), UKE_KEY (def. build/rootfs/uke-arch-root).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
R=$(cd "$HERE/../../../.." && pwd)
KEY=${UKE_KEY:-$R/build/rootfs/uke-arch-root}
HOST=${UKE_HOST:-root@192.168.42.129}
SSHOPTS=(-i "$KEY" -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=no
	-o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
TREE=$HERE/rootfs
FWSRC=$R/charge/firmware
FWSUM=$R/charge/adsp-fw.sha256
CHAIN=${UKE_CHAIN:-"qrtr qrtr_smd qcom_pd_mapper pmic_glink qcom_battmgr qcom_q6v5_pas"}
B40=42c86837570fabc9cf1504a1f596b7d56305f44e3bbccd3a431be8bf5882b352

say() { printf '\n=== %s\n' "$*"; }
die() { echo "ABORTO: $*" >&2; exit 1; }
rs() { timeout "${2:-90}" ssh "${SSHOPTS[@]}" "$HOST" "$1"; }

tree_members() { # lista NUL de ficheros del árbol (sin directorios), filtrable
	local gl=0
	[ "${WITH_GADGET_LATE:-0}" = 1 ] && gl=1
	(cd "$TREE" && if [ "$gl" = 1 ]; then
		find . -mindepth 1 ! -type d -print0
	else
		find . -mindepth 1 ! -type d ! -name 'uke-usb-gadget-late*' -print0
	fi)
}
tree_tar() { tree_members | tar -C "$TREE" --null --no-recursion --owner=0 --group=0 --numeric-owner -cf - -T -; }

pc_gates() {
	say "PC: gates"
	local f bad=0
	for f in "$TREE"/usr/local/sbin/*.sh "$HERE"/tests/*.sh; do
		[ -f "$f" ] || continue
		sh -n "$f" 2>/dev/null || { echo "  sintaxis MALA: $f"; bad=1; }
	done
	bash -n "$HERE/deploy.sh" || bad=1
	for f in "$TREE"/usr/local/sbin/*.sh; do
		[ -x "$f" ] || { echo "  sin +x: $f"; bad=1; }
	done
	[ "$bad" = 0 ] && echo "  sintaxis y permisos OK"
	if (cd "$FWSRC" && sha256sum -c "$FWSUM" --quiet 2>/dev/null); then
		echo "  firmware del PC: 56/56 shas OK"
	else
		echo "  firmware del PC con shas MALAS"; bad=1
	fi
	grep -q "$B40" "$FWSUM" && grep -q "$B40" "$TREE/usr/local/sbin/uke-carga-start.sh" \
		&& echo "  sha de adsp.b40 coherente (manifiesto == loader)" \
		|| { echo "  sha de adsp.b40 INCOHERENTE entre manifiesto y loader"; bad=1; }
	[ "$bad" = 0 ] || die "gates del PC en rojo"
}

ssh_up() {
	[ -f "$KEY" ] || die "falta la clave $KEY"
	rs true 15 >/dev/null 2>&1 || die "sin SSH a $HOST (RNDIS/NCM 192.168.42.129)"
}

tablet_rel() {
	local rel
	rel=$(rs 'uname -r') || die "no pude leer uname -r"
	case "$rel" in
	*senemos*) echo "$rel" ;;
	*) die "la tablet corre '$rel', no un kernel senemos (esta pila es solo para él)" ;;
	esac
}

cmd_check() {
	say "tablet: pre-vuelo (solo lectura)"
	ssh_up
	tablet_rel
	timeout 90 ssh "${SSHOPTS[@]}" "$HOST" 'sh -s -- --pre' < "$TREE/usr/local/sbin/uke-carga-verify.sh"
}

fw_repair() {
	say "firmware: ritual anti-corrupción en la tablet"
	tar -C "$(dirname "$FWSUM")" --owner=0 --group=0 --numeric-owner -cf - "$(basename "$FWSUM")" \
		| rs 'umask 022; tar -C /usr/lib/firmware -xpf -' || die "no pude copiar adsp-fw.sha256"
	local out bad
	out=$(rs 'cd /lib/firmware && sha256sum -c adsp-fw.sha256 2>&1 | grep -v ": OK$"' 60)
	if [ -z "$out" ]; then
		echo "  56/56 OK, nada que reparar"
		return 0
	fi
	echo "$out" | head -10
	bad=$(echo "$out" | sed -nE 's/^(sha256sum: )?(adsp(_dtb)?\.(b[0-9][0-9]|mdt)):.*/\2/p' | sort -u)
	[ -n "$bad" ] || die "firmware malo pero no pude extraer nombres (revisa a mano)"
	echo "  reparando desde el PC: $(echo $bad)"
	# shellcheck disable=SC2086
	(cd "$FWSRC" && tar --owner=0 --group=0 --numeric-owner -cf - $bad) \
		| rs 'umask 022; tar -C /usr/lib/firmware -xpf -; sync' || die "falló la copia del firmware"
	rs 'cd /lib/firmware && sha256sum -c adsp-fw.sha256 --quiet' 60 \
		&& echo "  firmware reparado: 56/56 OK" || die "firmware sigue malo tras reparar"
}

cmd_install() {
	WITH_GADGET_LATE=0
	[ "${1:-}" = "--with-gadget-late" ] && WITH_GADGET_LATE=1
	pc_gates
	say "tablet: contacto y pre-vuelo"
	ssh_up
	local rel
	rel=$(tablet_rel) || exit 1
	echo "  tablet: $rel"
	# Informativo: instalar ficheros es inocuo (el servicio se auto-bloquea con exit 4 si faltan módulos o
	# firmware, y modprobe.d impide el autoload de qcom_q6v5_pas). El bloqueo duro está en `start`.
	timeout 90 ssh "${SSHOPTS[@]}" "$HOST" 'sh -s -- --pre' < "$TREE/usr/local/sbin/uke-carga-verify.sh" \
		|| echo "  (pre-vuelo con FALLA: corrígelo antes de 'start'; p. ej. 'deploy.sh mods' o instalar el modroot)"
	say "tablet: copia de ficheros (tar | ssh)"
	tree_tar | rs 'umask 022; tar -C / -xpf -' || die "falló el tar | ssh"
	rs 'chmod 0755 /usr/local/sbin/uke-carga-start.sh /usr/local/sbin/uke-carga-verify.sh; chmod 0755 /usr/local/sbin/uke-usb-gadget-late.sh 2>/dev/null; true'
	fw_repair
	say "tablet: systemd"
	local units="uke-carga.service"
	[ "$WITH_GADGET_LATE" = 1 ] && units="$units uke-usb-gadget-late.service"
	rs "systemctl daemon-reload && systemctl enable $units && systemctl reset-failed uke-adsp.service 2>/dev/null; \
	    echo -n 'uke-carga enabled: '; systemctl is-enabled uke-carga.service; \
	    echo -n 'uke-adsp (viejo) condicion: '; systemctl show -p ConditionResult uke-adsp.service; \
	    systemd-analyze verify uke-carga.service 2>&1 | head -5; true"
	echo
	echo "Instalado y habilitado; el ADSP NO se ha arrancado. Siguiente: deploy.sh start"
}

cmd_start() {
	say "tablet: arranque de la pila de carga"
	ssh_up
	tablet_rel >/dev/null
	echo "-- pre-vuelo duro (si falla, NO se arranca el ADSP)"
	timeout 90 ssh "${SSHOPTS[@]}" "$HOST" 'sh -s -- --pre' < "$TREE/usr/local/sbin/uke-carga-verify.sh" \
		|| die "pre-vuelo en rojo: no arranco la pila (ver FALLA arriba)"
	rs 'systemctl start uke-carga.service; echo "systemctl start rc=$?"; systemctl --no-pager -l status uke-carga.service | head -12; journalctl -u uke-carga -b --no-pager | tail -50' 300
	cmd_verify
}

cmd_verify() {
	say "tablet: verificación"
	ssh_up
	if [ "${1:-}" = "--watch" ]; then
		rs "/usr/local/sbin/uke-carga-verify.sh --watch ${2:-6} ${3:-30}" 900
	else
		rs '/usr/local/sbin/uke-carga-verify.sh --post' 120
	fi
}

cmd_rollback() {
	say "tablet: rollback (no para el ADSP)"
	ssh_up
	rs 'systemctl disable uke-carga.service uke-usb-gadget-late.service 2>&1; \
	    rm -f /etc/systemd/system/uke-carga.service /etc/systemd/system/uke-usb-gadget-late.service \
	          /etc/systemd/system/uke-adsp.service.d/10-senemos-off.conf /etc/modprobe.d/uke-carga.conf \
	          /usr/local/sbin/uke-carga-start.sh /usr/local/sbin/uke-carga-verify.sh /usr/local/sbin/uke-usb-gadget-late.sh; \
	    rmdir /etc/systemd/system/uke-adsp.service.d 2>/dev/null; systemctl daemon-reload; echo rollback hecho'
}

cmd_stage() {
	local d=${1:-}
	[ -n "$d" ] && [ -d "$d" ] || die "uso: deploy.sh stage DIR (DIR debe existir; p. ej. la raíz montada de la imagen)"
	WITH_GADGET_LATE=0
	[ "${2:-}" = "--with-gadget-late" ] && WITH_GADGET_LATE=1
	say "stage en $d"
	tree_tar | tar -C "$d" -xpf - || die "extracción falló"
	mkdir -p "$d/etc/systemd/system/multi-user.target.wants"
	ln -sf /etc/systemd/system/uke-carga.service "$d/etc/systemd/system/multi-user.target.wants/uke-carga.service"
	[ "$WITH_GADGET_LATE" = 1 ] && ln -sf /etc/systemd/system/uke-usb-gadget-late.service \
		"$d/etc/systemd/system/multi-user.target.wants/uke-usb-gadget-late.service"
	echo "  extraído y habilitado por symlink. El firmware (/lib/firmware) NO va aquí: debe estar ya en la imagen"
	echo "  (rootfs-uke-l76-8g.img lo trae, 56 ficheros + adsp-fw.sha256)."
}

cmd_mods() {
	local modroot="" dry=0 a rel f rels=() list out
	for a in "$@"; do
		case "$a" in
		--dry-run) dry=1 ;;
		*) modroot=$a ;;
		esac
	done
	modroot=${modroot:-$R/build/kernel-pokes/senemos-build/modroot}
	if [ "$dry" = 1 ] && [ -n "${UKE_REL:-}" ]; then
		rel=$UKE_REL
	else
		ssh_up
		rel=$(tablet_rel) || exit 1
	fi
	[ -f "$modroot/lib/modules/$rel/modules.dep" ] \
		|| die "no hay $modroot/lib/modules/$rel/modules.dep (¿modroot v2 listo? el release debe coincidir con la tablet: $rel)"
	say "mods: cadena $CHAIN en $modroot ($rel)"
	list=""
	for a in $CHAIN; do
		out=$(modprobe -d "$modroot" -S "$rel" --show-depends "$a" 2>&1) || die "no resuelvo $a: $out"
		list="$list"$'\n'"$(echo "$out" | awk '/^insmod/{print $2}')"
	done
	list=$(echo "$list" | awk 'NF && !s[$0]++')
	if [ -z "$list" ]; then
		echo "  la cadena resolvió a 0 .ko (todo built-in): nada que subir"
		return 0
	fi
	for f in $list; do
		local vm
		vm=$(modinfo -F vermagic "$f" | cut -d' ' -f1)
		[ "$vm" = "$rel" ] || die "vermagic de $f = '$vm' != $rel"
		rels+=("${f#"$modroot"/}")
		echo "  ${f#"$modroot"/}  (vermagic OK)"
	done
	for f in modules.builtin modules.builtin.modinfo modules.order; do
		[ -f "$modroot/lib/modules/$rel/$f" ] && rels+=("lib/modules/$rel/$f")
	done
	if [ "$dry" = 1 ]; then
		echo "  --dry-run: no se toca la tablet (${#rels[@]} ficheros)"
		return 0
	fi
	say "mods: tar | ssh a /usr/lib/modules y depmod -a $rel"
	(cd "$modroot" && tar --owner=0 --group=0 --numeric-owner -cf - "${rels[@]}") \
		| rs 'umask 022; tar -C /usr -xpf -' || die "falló la copia de módulos"
	rs "depmod -a $rel && echo depmod OK && modprobe -n -v qcom_q6v5_pas" 120
}

case "${1:-}" in
pc) pc_gates ;;
check) cmd_check ;;
install) shift; cmd_install "$@" ;;
start) cmd_start ;;
verify) shift; cmd_verify "$@" ;;
mods) shift; cmd_mods "$@" ;;
rollback) cmd_rollback ;;
stage) shift; cmd_stage "$@" ;;
*) sed -n '2,24p' "$0"; exit 64 ;;
esac
