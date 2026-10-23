#!/usr/bin/env bash
# deploy.sh — despliega el Bluetooth (WCN6750) en el rootfs Arch de la Xiaomi Pad 7 'uke' por SSH, con `tar | ssh`
# (el rootfs NO tiene sftp-server). Etapas B1/B2-B4/B7 de build/gates/revision/BT-SENEMOS-20261018.md.
#
# SIN --go ni --check: SOLO verifica el arbol local (manifiesto, shas, vermagic, dtbo embebido, sintaxis) e imprime el
#                      plan. NO abre ninguna conexion (ni ssh, ni red).
# --check (sin --go):  lectura por SSH: nada se escribe, nada se carga.
# --go + partes:       ejecuta SOLO las partes elegidas (hay que elegir al menos una). NADA de lo que instala se carga:
#                      cargar los modulos (B2-B4) es una orden aparte del dueño, a mano (uke-bt-up.sh o modprobe).
#
# PARTES (se pueden combinar)
#   --fw            B1: msbtfw12.mbn + msnv12.bin (se LEEN de build/android/, NO se copian al repo; se comprueba su sha256
#                   contra las constantes de este script y contra root/usr/lib/firmware/uke-bt-fw.sha256) -> /usr/lib/firmware/qca/
#                   + el manifiesto uke-bt-fw.sha256. No toca msbtfw11/msnv11 ni nada mas de qca/.
#   --pkgs          B1: pacman -S --needed bluez bluez-utils bluetui en la tablet (usa SU red WiFi). Antes hace una vista previa
#                   (--print) y ABORTA si la transaccion actualizaria un paquete YA instalado (nada de actualizaciones parciales).
#                   No habilita bluetooth.service.
#   --module        instala uke_bt_{uart,b,a}.ko en /usr/lib/modules/<krel>/extra/ + depmod -a. NO carga nada. Comprueba que el
#                   vermagic de los .ko == el krel del arbol de build y que /usr/lib/modules/<krel> existe en la tablet.
#   --service       instala uke-bt.service (SIN habilitar) + uke-bt-up.sh + la version de uke-bootguard de build/rootfs/deploy/arranque
#                   (con 'bt' en KNOWN) + daemon-reload.
#   --bdaddr A      fija la direccion BD en /etc/modprobe.d/uke-bt.conf (`options uke_bt_b|uke_bt_a bdaddr=A`). A = AA:BB:CC:DD:EE:FF
#                   (unicast) o `random` (se genera una localmente administrada). La direccion NO se versiona: va de este
#                   script a la tablet y solo a la tablet. EXIGE confirmacion interactiva (hay que reescribirla en el terminal).
#   --bdaddr-file F igual, leyendola de un fichero de 6 bytes (p.ej. el .bt_nv.bin de persist; que el orden del fichero sea el
#                   de la direccion impresa es INFERIDO por el sufijo e5 37, informe §2.3).
#   --replace-bdaddr  permite sustituir un uke-bt.conf que ya tenga OTRA direccion (por defecto aborta).
#   --arm           B7: systemctl enable uke-bt.service + uke-bootguard reset bt (el BT arrancara en cada arranque). Hazlo SOLO
#                   tras B4 verde. Exige que esten fw, modulos, servicio y guarda en la tablet.
#   --daily         D1 (BT-DIARIO-PLAN-20261018.md): drop-in bluetooth.service.d/10-uke-bt.conf (After=/Wants= uke-bt.service),
#                   AutoEnable=true explicito en /etc/bluetooth/main.conf (copia previa .uke-bak) y systemctl enable bluetooth.service.
#                   NO arranca bluetooth.service. Exige uke-bt.service, uke-bt-up.sh y bluez en la tablet.
#   --sleep         D2: gancho systemd-sleep uke-bt-sleep + ayudante uke-bt-resume (apagar el adaptador al suspender y reconectar al
#                   reanudar). Toca la RUTA DE SUSPENSION: probar antes con `rtcwake -m freeze -s 20`.
#   --wait          D4b: espera ACOTADA (<= 25 s; hasta 70 s solo mientras uke-bt siga reintentando el encendido; siempre sale con 0) antes de arrancar el escritorio hasta que org.bluez este en el bus:
#                   uke-bt-wait + drop-in uke-desktop.service.d/20-uke-bt.conf (ExecStartPre con '-'). Motivo: el panel de BT del shell
#                   (Quickshell.Bluetooth) no se reengancha a BlueZ si arranca antes que bluetoothd (medido, tambien en frio).
#   --hciqca        BT-MUDO (hciqca/): instala el hci_uart.ko PARCHEADO (tiempos del WCN6750 ajustables; defaults = serie) en /usr/lib/modules/<krel>/updates/ (Arch: /usr/lib/depmod.d/search.conf = «updates extramodules built-in»:
#                   updates/ SI se prefiere al de serie, extra/ NO — verificado en la tablet el 21-oct; para quitarlo: --revert) y hciqca/bt-medir.sh + consumo/bt-consumo.sh (herramientas de medida) en /usr/local/sbin/. NO carga nada: el hci_uart de serie cargado en
#                   memoria no se sustituye hasta descargarlo (uke-bt-up.sh --down). Exige haber corrido hciqca/build-hciqca.sh (out-hciqca/hci_uart.ko).
#   --hciqca-conf "OPCIONES"
#                   fija las opciones PERSISTENTES del hci_uart parcheado en /etc/modprobe.d/uke-bt-hci.conf (`options hci_uart OPCIONES`), p. ej.
#                   "uke_bt_boot_ms=200". Solo se aceptan uke_bt_low_ms|uke_bt_boot_ms|uke_bt_swctrl_ms = entero 0-2000. Exige el parcheado instalado (--hciqca).
#                   Se usa SOLO tras decidir con bt-medir.sh qué valor conviene (BT-MUDO-FIX-20261021.md); --revert lo borra.
#   --revert        deshabilita y borra lo instalado por este script (servicio, script, .ko, uke-bt.conf, firmware rev 12, drop-in,
#                   gancho de sueño; restaura main.conf desde .uke-bak y deshabilita bluetooth.service). No desinstala paquetes ni
#                   toca la blacklist de hci_uart ni uke-bootguard.
#
# OTRAS OPCIONES
#   --go | --check     ver arriba            --host H --key K   (por defecto 192.168.42.129 y build/rootfs/uke-arch-root)
#   --regen-manifest   regenera MANIFEST.sha256 (tras editar el arbol; build.sh tambien lo hace) y sale
# Variables: UKE_HOST UKE_USER UKE_KEY UKE_SSH_OPTS KB (arbol de build del kernel).
#
# NUNCA toca: la blacklist de hci_uart, uke-wifi.service, /sys/kernel/debug, /dev/ttyACM0, el slot ni el boot.img.
set -Eeuo pipefail
trap 'echo "deploy.sh: ERROR en linea $LINENO (ultimo comando: $BASH_COMMAND)" >&2' ERR

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
R=$(cd "$HERE/../../../.." && pwd)
TREE=$HERE/root
KB=${KB:-$R/build/kernel-pokes/senemos-ouke5/build}
# Directorio de los .ko/.dtbo a instalar (relativo a este script o absoluto): out (por defecto, release ouke5) o out-ouke4 (copia de respaldo del kernel ouke4;
# con el: KB=build/kernel-pokes/senemos-build UKE_BT_OUT=out-ouke4). La release la fija el arbol KB; el vermagic de los .ko tiene que coincidir (si no, se aborta).
OUTD=${UKE_BT_OUT:-out}; case "$OUTD" in /*) KODIR=$OUTD ;; *) KODIR=$HERE/$OUTD ;; esac
FWDIR=$R/build/android
KEY=${UKE_KEY:-$R/build/rootfs/uke-arch-root}
HOST=${UKE_HOST:-192.168.42.129}
SSHUSER=${UKE_USER:-root}
AR=$R/build/rootfs/deploy/arranque
FW_MBN_SHA=3efbd7fa985702982ba3f2fb4e4e37dab2de51b26fa5574d6165f1cd4ec5506d
FW_NV_SHA=52553c8a4041d4c564e55046c010609198fb3636a21d5a87a8e2df55023c0476
ADSP_B40_PREFIX=42c86837            # ritual anti-corrupcion del proyecto (docs/historia/ESTADO-VIVO.md): sha256 de /lib/firmware/adsp.b40
MODS="uke_bt_uart uke_bt_b uke_bt_a"
GO=0 CHECK=0 REGEN=0 FW=0 PKGS=0 MODULE=0 SERVICE=0 ARM=0 DAILY=0 SLEEP=0 WAIT=0 HCIQCA=0 HQCONF="" REVERT=0 REPLACE_BD=0 BDADDR="" BDFILE=""

while [ $# -gt 0 ]; do
	case "$1" in
	--go) GO=1 ;;
	--check) CHECK=1 ;;
	--fw) FW=1 ;;
	--pkgs) PKGS=1 ;;
	--module) MODULE=1 ;;
	--service) SERVICE=1 ;;
	--arm) ARM=1 ;;
	--daily) DAILY=1 ;;
	--sleep) SLEEP=1 ;;
	--wait) WAIT=1 ;;
	--hciqca) HCIQCA=1 ;;
	--hciqca-conf) HQCONF=${2:?--hciqca-conf "uke_bt_boot_ms=200"}; shift ;;
	--revert) REVERT=1 ;;
	--bdaddr) BDADDR=${2:?--bdaddr AA:BB:CC:DD:EE:FF|random}; shift ;;
	--bdaddr-file) BDFILE=${2:?--bdaddr-file FICHERO}; shift ;;
	--replace-bdaddr) REPLACE_BD=1 ;;
	--regen-manifest) REGEN=1 ;;
	--host) HOST=${2:?--host H}; shift ;;
	--key) KEY=${2:?--key K}; shift ;;
	-h|--help) awk 'NR>1 && /^set -Eeuo/{exit} NR>1' "${BASH_SOURCE[0]}"; exit 0 ;;
	*) echo "argumento no reconocido: $1 (usa --help)" >&2; exit 2 ;;
	esac
	shift
done

# shellcheck disable=SC2206
SSH_BASE=(ssh -i "$KEY" -o BatchMode=yes -o ConnectTimeout=8 -o ServerAliveInterval=5 -o ServerAliveCountMax=3 ${UKE_SSH_OPTS:-})
S() { "${SSH_BASE[@]}" "$SSHUSER@$HOST" "$@"; }
say() { printf '[deploy-bt %s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { echo "deploy.sh: $*" >&2; exit 2; }

# ------------------------------------------------------------------ regenerar manifiesto
regen_manifest() {
	(cd "$HERE" && { find dts module harness hciqca consumo root -type f -print0 | sort -z | xargs -0 sha256sum; ls out/*.dtbo out/*.ko out-*/*.dtbo out-*/*.ko 2>/dev/null | xargs -r sha256sum; sha256sum check-bt.py; } > MANIFEST.sha256)
}
if [ "$REGEN" = 1 ]; then regen_manifest; say "MANIFEST.sha256 regenerado ($(wc -l < "$HERE/MANIFEST.sha256") ficheros)"; exit 0; fi

PARTS=$((FW + PKGS + MODULE + SERVICE + ARM + DAILY + SLEEP + WAIT + HCIQCA + REVERT))
[ -n "$BDADDR$BDFILE" ] && PARTS=$((PARTS + 1))
[ -n "$HQCONF" ] && PARTS=$((PARTS + 1))
[ -n "$BDADDR" ] && [ -n "$BDFILE" ] && die "--bdaddr y --bdaddr-file son excluyentes"
if [ -n "$HQCONF" ]; then
	for tok in $HQCONF; do
		case "$tok" in uke_bt_low_ms=[0-9]|uke_bt_low_ms=[0-9][0-9]|uke_bt_low_ms=[0-9][0-9][0-9]|uke_bt_low_ms=[0-9][0-9][0-9][0-9]|uke_bt_boot_ms=[0-9]|uke_bt_boot_ms=[0-9][0-9]|uke_bt_boot_ms=[0-9][0-9][0-9]|uke_bt_boot_ms=[0-9][0-9][0-9][0-9]|uke_bt_swctrl_ms=[0-9]|uke_bt_swctrl_ms=[0-9][0-9]|uke_bt_swctrl_ms=[0-9][0-9][0-9]|uke_bt_swctrl_ms=[0-9][0-9][0-9][0-9]) ;;
			*) die "--hciqca-conf: opcion no permitida '$tok' (solo uke_bt_low_ms|uke_bt_boot_ms|uke_bt_swctrl_ms=entero 0-9999)" ;; esac
		[ "${tok#*=}" -le 2000 ] || die "--hciqca-conf: $tok supera 2000 ms"
	done
fi
[ "$REVERT" = 1 ] && [ $((FW + PKGS + MODULE + SERVICE + ARM + DAILY + SLEEP + WAIT + HCIQCA)) -gt 0 -o -n "$HQCONF" ] && die "--revert no se combina con instalar"
[ "$GO" = 1 ] && [ "$PARTS" = 0 ] && die "--go sin partes: elige --fw --pkgs --module --service --bdaddr --arm --daily --sleep --wait --hciqca --hciqca-conf (o --revert); ver --help"

# ------------------------------------------------------------------ verificacion LOCAL (siempre; sin red)
say "== verificacion local (sin red) =="
[ -f "$HERE/MANIFEST.sha256" ] || die "falta MANIFEST.sha256 (ejecuta build.sh)"
(cd "$HERE" && sha256sum -c --quiet MANIFEST.sha256) || die "el arbol no casa con MANIFEST.sha256 (¿editado? build.sh o --regen-manifest)"
say "  MANIFEST.sha256 OK ($(wc -l < "$HERE/MANIFEST.sha256") ficheros: dts, modulos, .dtbo, .ko, root/)"
KREL=$(cat "$KB/include/config/kernel.release" 2>/dev/null) || die "no encuentro $KB/include/config/kernel.release"
for f in msbtfw12.mbn:$FW_MBN_SHA msnv12.bin:$FW_NV_SHA; do
	n=${f%%:*}; want=${f#*:}
	[ -f "$FWDIR/$n" ] || die "falta el firmware $FWDIR/$n"
	got=$(sha256sum < "$FWDIR/$n" | cut -d' ' -f1)
	[ "$got" = "$want" ] || die "$n: sha256 $got != esperado $want"
	grep -q "^$want  usr/lib/firmware/qca/$n\$" "$TREE/usr/lib/firmware/uke-bt-fw.sha256" || die "$n: uke-bt-fw.sha256 no lleva ese sha"
done
say "  firmware (leido de build/android, NO copiado al repo): msbtfw12.mbn ${FW_MBN_SHA:0:12}…  msnv12.bin ${FW_NV_SHA:0:12}…  == uke-bt-fw.sha256"
REFVM="$KREL SMP preempt mod_unload aarch64"
for m in $MODS; do
	[ -s "$KODIR/$m.ko" ] || die "falta $OUTD/$m.ko (ejecuta build.sh)"
	vm=$(modinfo -F vermagic "$KODIR/$m.ko")
	[ "$vm" = "$REFVM" ] || die "$m.ko: vermagic '$vm' != '$REFVM' (¿$OUTD/ es de otro kernel? usa KB=<arbol de build de ese kernel> o UKE_BT_OUT=out-ouke4 para el kernel ouke4)"
done
say "  modulos: vermagic == $REFVM"
if [ "$HCIQCA" = 1 ]; then
	HQ=$HERE/out-hciqca/hci_uart.ko
	[ -s "$HQ" ] || die "falta out-hciqca/hci_uart.ko (ejecuta hciqca/build-hciqca.sh)"
	[ "$(modinfo -F vermagic "$HQ")" = "$REFVM" ] || die "out-hciqca/hci_uart.ko: vermagic '$(modinfo -F vermagic "$HQ")' != '$REFVM'"
	modinfo -F parm "$HQ" | grep -q '^uke_bt_boot_ms:' || die "out-hciqca/hci_uart.ko no es el parcheado (falta el parametro uke_bt_boot_ms)"
	bash -n "$HERE/hciqca/bt-medir.sh" || die "hciqca/bt-medir.sh: sintaxis"
	bash -n "$HERE/consumo/bt-consumo.sh" || die "consumo/bt-consumo.sh: sintaxis"
	say "  hciqca: hci_uart.ko parcheado con vermagic == $REFVM y parametros uke_bt_*; bt-medir.sh y bt-consumo.sh con sintaxis OK"
fi
OBJCOPY=$(command -v llvm-objcopy || command -v objcopy || true)
if [ -n "$OBJCOPY" ]; then
	tmpd=$(mktemp -d); trap 'rm -rf "$tmpd"' EXIT
	for pair in uke_bt_uart:uke-bt-uart-only uke_bt_b:uke-bt-B uke_bt_a:uke-bt-A; do
		"$OBJCOPY" --dump-section=.uke_ovl="$tmpd/${pair%%:*}.blob" "$KODIR/${pair%%:*}.ko" "$tmpd/x.ko"
		cmp -s "$tmpd/${pair%%:*}.blob" "$KODIR/${pair#*:}.dtbo" || die "${pair%%:*}.ko: el dtbo embebido no es $OUTD/${pair#*:}.dtbo"
	done
	say "  dtbo embebido en cada .ko == out/*.dtbo"
else
	say "  AVISO: sin llvm-objcopy/objcopy: no se comprueba el dtbo embebido (lo hace build.sh)"
fi
for f in "$HERE/deploy.sh" "$TREE/usr/local/sbin/uke-bt-up.sh" "$TREE/usr/lib/systemd/system-sleep/uke-bt-sleep" "$TREE/usr/local/sbin/uke-bt-resume" "$TREE/usr/local/sbin/uke-bt-wait"; do bash -n "$f" || die "sintaxis de $f"; done
[ -f "$TREE/etc/systemd/system/bluetooth.service.d/10-uke-bt.conf" ] && [ -f "$TREE/etc/systemd/system/uke-desktop.service.d/20-uke-bt.conf" ] || die "faltan los drop-ins (bluetooth.service / uke-desktop.service)"
say "  sintaxis deploy.sh/uke-bt-up.sh/uke-bt-sleep/uke-bt-resume OK; drop-in presente"
(cd "$AR/root" && sha256sum -c --quiet ../MANIFEST.sha256) || die "arranque/MANIFEST.sha256 desfasado"
grep -qE '^KNOWN="([a-z]+ )*bt( [a-z]+)*"$' "$AR/root/usr/local/sbin/uke-bootguard" || die "uke-bootguard (arranque/root) no conoce 'bt'"
say "  uke-bootguard (arranque/root) conoce 'bt'; manifiesto de arranque OK"
[ -f "$KEY" ] || say "  AVISO: no existe la clave SSH $KEY"

# ------------------------------------------------------------------ direccion BD (solo local; confirmacion antes de tocar nada)
BD=""
mkbd() { # mkbd -> imprime una direccion unicast localmente administrada
	local b0; b0=$(od -An -N1 -tu1 /dev/urandom | tr -d ' ')
	printf '%02x:%s\n' $(( (b0 & 0xFE) | 0x02 )) "$(od -An -N5 -tx1 /dev/urandom | tr -s ' ' ':' | sed 's/^://; s/:$//')"
}
valid_bd() { [[ "$1" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]] && [ $((16#${1:0:2} & 1)) = 0 ] && [ "${1//[0:]/}" != "" ]; }
resolve_bd() {
	if [ -n "$BDFILE" ]; then
		[ -f "$BDFILE" ] && [ "$(stat -c %s "$BDFILE")" = 6 ] || die "--bdaddr-file: $BDFILE no es un fichero de 6 bytes"
		BD=$(od -An -tx1 -v "$BDFILE" | tr -s ' ' ':' | sed 's/^://; s/:$//')
	elif [ "$BDADDR" = random ]; then BD=$(mkbd)
	else BD=$BDADDR; fi
	BD=$(tr 'A-F' 'a-f' <<<"$BD")
	valid_bd "$BD" || die "direccion BD invalida '$BD' (AA:BB:CC:DD:EE:FF, unicast y no nula)"
}
confirm_bd() {
	local ans
	[ -t 0 ] && [ -r /dev/tty ] || die "--bdaddr necesita confirmacion INTERACTIVA del dueño (terminal): no se puede confirmar sin tty"
	echo "  Direccion BD que se fijara en la tablet (solo alli; no se versiona): $BD"
	read -r -p "  Para confirmar, escribela otra vez (otra cosa = abortar): " ans < /dev/tty
	[ "${ans,,}" = "$BD" ] || die "direccion no confirmada: no se hace nada"
}

# ------------------------------------------------------------------ plan
say "== plan =="
P_FW="no"; P_PKGS="no"; P_MOD="no"; P_SRV="no"; P_BD="no"; P_ARM="no"; P_DAILY="no"; P_SLEEP="no"; P_WAIT="no"; P_HCIQCA="no"; P_HQCONF="no"
[ "$FW" = 1 ] && P_FW="SI: msbtfw12.mbn + msnv12.bin (de build/android) -> /usr/lib/firmware/qca/ + uke-bt-fw.sha256; sha256 a ambos lados; sync"
[ "$PKGS" = 1 ] && P_PKGS="SI: vista previa de pacman; si no actualiza nada instalado, pacman -S --needed bluez bluez-utils bluetui"
[ "$MODULE" = 1 ] && P_MOD="SI: ${MODS// /, } (.ko) -> /usr/lib/modules/$KREL/extra/ + depmod -a $KREL; NO se carga ninguno"
[ "$SERVICE" = 1 ] && P_SRV="SI: uke-bt.service (SIN enable), uke-bt-up.sh, uke-bootguard (con 'bt'), daemon-reload"
[ -n "$BDADDR$BDFILE" ] && P_BD="SI: /etc/modprobe.d/uke-bt.conf (modo 600) con la direccion ${BDADDR:-leida de $BDFILE}; confirmacion interactiva; sustituir una existente distinta: $([ "$REPLACE_BD" = 1 ] && echo si || echo NO)"
[ "$ARM" = 1 ] && P_ARM="SI: systemctl enable uke-bt.service + uke-bootguard reset bt (B7: el BT arrancara en cada arranque; solo tras B4 verde)"
[ "$DAILY" = 1 ] && P_DAILY="SI: bluetooth.service.d/10-uke-bt.conf (After=/Wants= uke-bt.service) + AutoEnable=true en main.conf (copia .uke-bak) + systemctl enable bluetooth.service; NO se arranca"
[ "$SLEEP" = 1 ] && P_SLEEP="SI: system-sleep/uke-bt-sleep + uke-bt-resume (apagar el adaptador al suspender, reconectar al reanudar); prueba obligada: rtcwake -m freeze -s 20"
[ -n "$HQCONF" ] && P_HQCONF="SI: /etc/modprobe.d/uke-bt-hci.conf = options hci_uart $HQCONF (persistente: lo usara cada encendido del BT)"
[ "$HCIQCA" = 1 ] && P_HCIQCA="SI: out-hciqca/hci_uart.ko (parcheado) -> /usr/lib/modules/$KREL/updates/ + depmod -a $KREL (borra el residuo de extra/); bt-medir.sh y bt-consumo.sh -> /usr/local/sbin/; NO se carga nada"
[ "$WAIT" = 1 ] && P_WAIT="SI: uke-bt-wait + uke-desktop.service.d/20-uke-bt.conf (el escritorio espera <= 25 s a org.bluez; nunca bloquea)"
cat <<EOF
  destino : $SSHUSER@$HOST  (clave $KEY)   kernel objetivo (arbol de build): $KREL
  0. lectura previa en la tablet: root, herramientas, espacio, kernel, adsp.b40 == $ADSP_B40_PREFIX…, WiFi (wpa_state, ping, ath11k), manifiesto del WiFi
  1. --fw      : $P_FW
  2. --pkgs    : $P_PKGS
  3. --module  : $P_MOD
  4. --service : $P_SRV
  5. --bdaddr  : $P_BD
  6. --arm     : $P_ARM
  6b. --daily  : $P_DAILY
  6c. --sleep  : $P_SLEEP
  6d. --wait   : $P_WAIT
  6e. --hciqca : $P_HCIQCA
  6f. --hciqca-conf : $P_HQCONF
  7. al final: la misma lectura que en 0 y comparacion (si el WiFi o adsp.b40 cambian, lo dice)
  REVERT=$REVERT (--revert: deshabilita y borra servicio, script, .ko, uke-bt.conf y firmware rev 12)
  El Bluetooth NO se enciende aqui. Primer encendido = B4: cargar a mano (modprobe uke_bt_b; modprobe hci_uart) con ACM, 'dmesg -n 7' y ssh dmesg -w.
EOF

if [ "$GO" = 0 ] && [ "$CHECK" = 0 ]; then
	say "Nada ejecutado (sin --go ni --check: no se abrio ninguna conexion). Para aplicar:  $0 --go --fw [--pkgs] [--module] [--service] [--bdaddr A|random] [--arm]"
	exit 0
fi

# ------------------------------------------------------------------ lectura remota (preflight / --check / comparacion final)
snapshot() {
	S 'bash -s' <<'REMOTE'
echo "kernel=$(uname -r) uptime=$(cut -d' ' -f1 /proc/uptime)s"
echo "adsp.b40=$(sha256sum /lib/firmware/adsp.b40 2>/dev/null | cut -c1-8)"
echo "wifi=$(wpa_cli -i wlan0 status 2>/dev/null | sed -n 's/^wpa_state=//p')"
gw=$(ip route 2>/dev/null | awk '/^default/{print $3; exit}')
echo "gw_ping=$([ -n "$gw" ] && ping -c 2 -W 2 "$gw" >/dev/null 2>&1 && echo ok || echo FALLA)"
echo "ath11k_dmesg=$(dmesg 2>/dev/null | grep -c ath11k)"
echo "wifi_fw=$( (cd / && sha256sum -c --quiet usr/lib/firmware/uke-wifi-fw.sha256 >/dev/null 2>&1) && echo ok || echo FALLA)"
echo "bt_modulos_cargados=$(grep -E '^(uke_bt_[a-z]+|hci_uart|btqca|btbcm|bluetooth) ' /proc/modules | cut -d' ' -f1 | tr '\n' ',' | sed 's/,$//')"
echo "sys_class_bluetooth=$(ls /sys/class/bluetooth 2>/dev/null | tr '\n' ',' | sed 's/,$//')"
REMOTE
}
remote_check() {
	snapshot | sed 's/^/  /'
	S 'bash -s' <<'REMOTE'
echo "  --- firmware"
for f in msbtfw12.mbn msnv12.bin msbtfw11.mbn msnv11.bin; do printf '  %-14s %s\n' "$f" "$(sha256sum /usr/lib/firmware/qca/$f 2>/dev/null | cut -c1-16 || true)"; done
[ -f /usr/lib/firmware/uke-bt-fw.sha256 ] && ( (cd / && sha256sum -c --quiet usr/lib/firmware/uke-bt-fw.sha256 >/dev/null 2>&1) && echo "  uke-bt-fw.sha256: OK" || echo "  uke-bt-fw.sha256: NO casa") || echo "  uke-bt-fw.sha256: no instalado"
echo "  --- paquetes"; for p in bluez bluez-utils bluez-libs bluetui; do printf '  %-12s %s\n' "$p" "$(pacman -Q $p 2>&1 | head -1)"; done
echo "  --- modulos (instalados; ninguno se carga aqui)"
k=$(uname -r)
for m in uke_bt_uart uke_bt_b uke_bt_a hci_uart btqca btbcm bluetooth; do printf '  %-12s %s\n' "$m" "$(modinfo -n $m 2>&1 | head -1)"; done
for m in uke_bt_uart uke_bt_b uke_bt_a; do f=/usr/lib/modules/$k/extra/$m.ko; [ -f $f ] && printf '  %-12s vermagic: %s\n' "$m" "$(modinfo -F vermagic $f)"; done
echo "  --- guarda y servicio"
grep -q '^KNOWN=.*\bbt\b' /usr/local/sbin/uke-bootguard 2>/dev/null && echo "  uke-bootguard conoce bt: si" || echo "  uke-bootguard conoce bt: NO"
[ -x /usr/local/sbin/uke-bt-up.sh ] && echo "  uke-bt-up.sh: instalado" || echo "  uke-bt-up.sh: no"
echo "  uke-bt.service: $(systemctl is-enabled uke-bt.service 2>&1 | head -1) / $(systemctl is-active uke-bt.service 2>&1 | head -1)"
ls /etc/uke 2>/dev/null | grep -E '^(no-bt|safe-mode)$' | sed 's/^/  interruptor presente: \/etc\/uke\//' || true
/usr/local/sbin/uke-bootguard status bt 2>/dev/null | sed 's/^/  /' || true
echo "  --- wrapper QUP1 (la UART mainline hace DMA por su SID 0x423)"
g=/sys/bus/platform/devices/8c0000.qcom,qupv3_1_geni_se/iommu_group
[ -e $g ] && echo "  iommu_group: $(basename "$(readlink -f $g)")" || echo "  iommu_group: AUSENTE"
echo "  --- dia a dia (D1/D2)"
echo "  bluetooth.service: $(systemctl is-enabled bluetooth.service 2>&1 | head -1) / $(systemctl is-active bluetooth.service 2>&1 | head -1)"
[ -f /etc/systemd/system/bluetooth.service.d/10-uke-bt.conf ] && echo "  drop-in bluetooth.service.d: presente ($(systemctl show bluetooth.service -p After -p Wants | tr ' ' '\n' | grep -c uke-bt) refs a uke-bt)" || echo "  drop-in bluetooth.service.d: no"
echo "  main.conf AutoEnable: $(grep -E '^AutoEnable=' /etc/bluetooth/main.conf 2>/dev/null || echo 'sin fijar (defecto true)')"
[ -x /usr/lib/systemd/system-sleep/uke-bt-sleep ] && echo "  gancho uke-bt-sleep: instalado" || echo "  gancho uke-bt-sleep: no"
[ -x /usr/local/sbin/uke-bt-wait ] && [ -f /etc/systemd/system/uke-desktop.service.d/20-uke-bt.conf ] && echo "  espera del escritorio (uke-bt-wait): instalada" || echo "  espera del escritorio (uke-bt-wait): no"
echo "  --- blacklist y direccion"
grep -q '^blacklist hci_uart' /etc/modprobe.d/uke-senemos-guard.conf 2>/dev/null && echo "  blacklist hci_uart: presente (debe estarlo)" || echo "  blacklist hci_uart: AUSENTE"
if [ -f /etc/modprobe.d/uke-bt.conf ]; then echo "  uke-bt.conf: $(sed -n 's/.*bdaddr=\(..:..:..:..\):\(..:..\).*/bdaddr=XX:XX:XX:XX:\2 (enmascarada)/p' /etc/modprobe.d/uke-bt.conf | head -1)"; else echo "  uke-bt.conf: no existe"; fi
echo "  rfkill: $(rfkill list 2>/dev/null | tr '\n' ' ' | cut -c1-120)"
REMOTE
}
if [ "$CHECK" = 1 ] && [ "$GO" = 0 ]; then
	say "== --check remoto (solo lectura) =="
	remote_check
	exit 0
fi

# ------------------------------------------------------------------ --go
BD_TAIL=""
[ -n "$BDADDR$BDFILE" ] && { resolve_bd; BD_TAIL=${BD#*:*:*:*:}; confirm_bd; }

say "== 0. lectura previa en la tablet =="
S 'bash -s' <<REMOTE
set -e
[ "\$(id -u)" = 0 ] || { echo "no soy root en la tablet" >&2; exit 1; }
for b in tar sha256sum systemctl depmod modinfo modprobe awk; do command -v "\$b" >/dev/null || { echo "FALTA en la tablet: \$b" >&2; exit 1; }; done
[ $PKGS = 0 ] || command -v pacman >/dev/null || { echo "FALTA pacman" >&2; exit 1; }
free=\$(df -Pk / | awk 'NR==2{print \$4}'); [ "\$free" -ge 20480 ] || { echo "poco espacio en /: \${free} KB" >&2; exit 1; }
mount | grep -E ' / ' | grep -q '[( ,]ro[, )]' && { echo "/ esta montado SOLO LECTURA: aborto" >&2; exit 1; }
[ $((MODULE + HCIQCA)) = 0 ] || [ -d /usr/lib/modules/$KREL ] || { echo "no existe /usr/lib/modules/$KREL en la tablet (¿otro kernel?)" >&2; exit 1; }
a=\$(sha256sum /lib/firmware/adsp.b40 2>/dev/null | cut -c1-8)
[ "\$a" = "$ADSP_B40_PREFIX" ] || { echo "RITUAL: adsp.b40 = '\$a' != $ADSP_B40_PREFIX (corrupcion del rootfs sin journal): aborto, repara antes" >&2; exit 1; }
echo "tablet: kernel \$(uname -r), uptime \$(cut -d' ' -f1 /proc/uptime)s, libres \${free} KB, adsp.b40 \$a OK"
REMOTE
snapshot > "$HERE/.snap-before" 2>/dev/null || true
trap 'rm -f "$HERE/.snap-before" "$HERE/.snap-after"; [ -n "${tmpd:-}" ] && rm -rf "$tmpd"' EXIT
sed 's/^/  antes: /' "$HERE/.snap-before"

if [ "$REVERT" = 1 ]; then
	say "== --revert =="
	S 'bash -s' <<'REMOTE'
set -u
for m in uke_bt_b uke_bt_a uke_bt_uart hci_uart; do grep -q "^$m " /proc/modules && { echo "AVISO: $m esta cargado: descarga con uke-bt-up.sh --down antes de revertir" >&2; exit 1; }; done
systemctl disable uke-bt.service 2>&1 | tail -1
systemctl disable bluetooth.service 2>&1 | tail -1
rm -fv /etc/systemd/system/bluetooth.service.d/10-uke-bt.conf; rmdir /etc/systemd/system/bluetooth.service.d 2>/dev/null || true
rm -fv /usr/lib/systemd/system-sleep/uke-bt-sleep /usr/local/sbin/uke-bt-resume /var/lib/uke/bt-last
rm -fv /etc/systemd/system/uke-desktop.service.d/20-uke-bt.conf /usr/local/sbin/uke-bt-wait; rmdir /etc/systemd/system/uke-desktop.service.d 2>/dev/null || true
[ -f /etc/bluetooth/main.conf.uke-bak ] && { mv -fv /etc/bluetooth/main.conf.uke-bak /etc/bluetooth/main.conf; }
rm -fv /etc/systemd/system/uke-bt.service /usr/local/sbin/uke-bt-up.sh /etc/modprobe.d/uke-bt.conf /usr/lib/firmware/uke-bt-fw.sha256 \
	/usr/lib/firmware/qca/msbtfw12.mbn /usr/lib/firmware/qca/msnv12.bin
k=$(uname -r); for m in uke_bt_uart uke_bt_b uke_bt_a hci_uart; do rm -fv /usr/lib/modules/$k/extra/$m.ko; done; rm -fv /usr/lib/modules/$k/updates/hci_uart.ko; rm -fv /usr/local/sbin/bt-medir.sh /usr/local/sbin/bt-consumo.sh /etc/modprobe.d/uke-bt-hci.conf
depmod -a "$k"; systemctl daemon-reload; /usr/local/sbin/uke-bootguard reset bt 2>/dev/null; sync
echo "revertido (paquetes bluez* y la blacklist de hci_uart intactos)"
REMOTE
else
	if [ "$FW" = 1 ]; then
		say "== 1. firmware rev 12 -> /usr/lib/firmware/qca/ =="
		{
			tar -C "$FWDIR" --owner=0 --group=0 --numeric-owner --mode='u=rw,go=r' --transform='s,^,usr/lib/firmware/qca/,' -cf - msbtfw12.mbn msnv12.bin
		} | S 'tar -xpf - --no-overwrite-dir -C / && sync'
		tar -C "$TREE" --owner=0 --group=0 --numeric-owner --mode='u=rw,go=r' -cf - usr/lib/firmware/uke-bt-fw.sha256 | S 'tar -xpf - --no-overwrite-dir -C / && sync'
		S 'cd / && sha256sum -c usr/lib/firmware/uke-bt-fw.sha256 && sync'
	fi
	if [ "$PKGS" = 1 ]; then
		say "== 2. paquetes (vista previa y, si es seguro, instalacion) =="
		S 'bash -s' <<'REMOTE'
set -eu
pre=$(pacman -S --needed -p --print-format '%n %v' bluez bluez-utils bluetui)
echo "$pre" | sed 's/^/  transaccion: /'
bad=""; for n in $(echo "$pre" | awk 'NF{print $1}'); do pacman -Qq "$n" >/dev/null 2>&1 && bad="$bad $n"; done
[ -z "$bad" ] || { echo "ABORTO: la transaccion actualizaria paquetes YA instalados:$bad (nada de actualizaciones parciales; hazlo a mano)" >&2; exit 1; }
pacman -S --needed --noconfirm bluez bluez-utils bluetui
echo "bluetooth.service: $(systemctl is-enabled bluetooth.service 2>&1 | head -1) (no se habilita)"
sync
REMOTE
	fi
	if [ "$MODULE" = 1 ]; then
		say "== 3. modulos cargadores -> /usr/lib/modules/$KREL/extra/ (NO se cargan) =="
		(cd "$KODIR" && tar --owner=0 --group=0 --numeric-owner --mode='u=rw,go=r' --transform="s,^,usr/lib/modules/$KREL/extra/," -cf - uke_bt_uart.ko uke_bt_b.ko uke_bt_a.ko) \
			| S 'tar -xpf - --no-overwrite-dir -C / && sync'
		S "bash -s" <<REMOTE
set -eu
depmod -a "$KREL"
for m in $MODS; do
	vm=\$(modinfo -F vermagic /usr/lib/modules/$KREL/extra/\$m.ko)
	[ "\$vm" = "$REFVM" ] || { echo "vermagic de \$m en la tablet: '\$vm'" >&2; exit 1; }
	modprobe -S $KREL --show-depends \$m | sed "s/^/  \$m: /"
done
sync
echo "depmod OK; modulos instalados, ninguno cargado"
REMOTE
	fi
	if [ "$SERVICE" = 1 ]; then
		say "== 4. servicio + guion + guarda (sin habilitar) =="
		{
			tar -C "$TREE" --owner=0 --group=0 --numeric-owner --no-recursion -cf - etc/systemd/system/uke-bt.service usr/local/sbin/uke-bt-up.sh
		} | S 'tar -xpf - --no-overwrite-dir -C / && sync'
		tar -C "$AR/root" --owner=0 --group=0 --numeric-owner -cf - usr/local/sbin/uke-bootguard | S 'tar -xpf - --no-overwrite-dir -C / && sync'
		S 'bash -s' <<'REMOTE'
set -eu
chmod 0755 /usr/local/sbin/uke-bt-up.sh /usr/local/sbin/uke-bootguard
chmod 0644 /etc/systemd/system/uke-bt.service
systemctl daemon-reload
systemd-analyze verify --man=no /etc/systemd/system/uke-bt.service 2>&1 | sed 's/^/  verify: /' || true
mkdir -p /var/lib/uke/guard
grep -q '^KNOWN=.*\bbt\b' /usr/local/sbin/uke-bootguard && echo "uke-bootguard conoce bt"
/usr/local/sbin/uke-bootguard status bt | sed 's/^/  /'
echo "uke-bt.service: $(systemctl is-enabled uke-bt.service 2>&1 | head -1) (NO habilitado)"
sync
REMOTE
	fi
	if [ -n "$BD" ]; then
		say "== 5. direccion BD -> /etc/modprobe.d/uke-bt.conf (modo 600) =="
		S "bash -s" <<REMOTE
set -eu
c=/etc/modprobe.d/uke-bt.conf
if [ -f \$c ]; then
	old=\$(sed -n 's/.*bdaddr=\\([0-9a-fA-F:]*\\).*/\\1/p' \$c | head -1)
	if [ "\$old" = "$BD" ]; then echo "uke-bt.conf ya tiene esa direccion: no se toca"; exit 0; fi
	[ $REPLACE_BD = 1 ] || { echo "ABORTO: uke-bt.conf ya existe con OTRA direccion (usa --replace-bdaddr para sustituirla)" >&2; exit 1; }
	cp -p \$c \$c.bak
fi
umask 077
printf '%s\n' "# generado por build/rootfs/deploy/bt/deploy.sh; NO se versiona. Direccion BD del controlador (la lee el cargador del overlay)." \
	"options uke_bt_b bdaddr=$BD" "options uke_bt_a bdaddr=$BD" > \$c.new
mv \$c.new \$c; chmod 600 \$c; sync
echo "uke-bt.conf escrito (bdaddr=XX:XX:XX:XX:$BD_TAIL)"
REMOTE
	fi
	if [ "$ARM" = 1 ]; then
		say "== 6. ARMAR (B7): uke-bt.service enabled =="
		S 'bash -s' <<'REMOTE'
set -eu
k=$(uname -r)
(cd / && sha256sum -c --quiet usr/lib/firmware/uke-bt-fw.sha256) || { echo "firmware rev 12 no casa: aplica --fw" >&2; exit 1; }
modinfo -n uke_bt_b >/dev/null 2>&1 || { echo "falta el modulo uke_bt_b: aplica --module" >&2; exit 1; }
[ -f /etc/systemd/system/uke-bt.service ] && [ -x /usr/local/sbin/uke-bt-up.sh ] || { echo "falta el servicio: aplica --service" >&2; exit 1; }
grep -q '^KNOWN=.*\bbt\b' /usr/local/sbin/uke-bootguard || { echo "uke-bootguard no conoce bt: aplica --service" >&2; exit 1; }
grep -q '^blacklist hci_uart' /etc/modprobe.d/uke-senemos-guard.conf || { echo "falta la blacklist de hci_uart: no armo" >&2; exit 1; }
[ -f /etc/modprobe.d/uke-bt.conf ] || echo "AVISO: sin uke-bt.conf (--bdaddr): el controlador quedaria sin configurar"
/usr/local/sbin/uke-bootguard reset bt
systemctl enable uke-bt.service
sync
echo "ARMADO: uke-bt.service enabled; el BT arrancara en cada arranque (apagarlo: touch /etc/uke/no-bt)"
REMOTE
	fi
	if [ "$DAILY" = 1 ]; then
		say "== 8. DIA A DIA (D1): bluetooth.service habilitado tras uke-bt, AutoEnable=true =="
		tar -C "$TREE" --owner=0 --group=0 --numeric-owner --mode='u=rw,go=r' --no-recursion -cf - etc/systemd/system/bluetooth.service.d etc/systemd/system/bluetooth.service.d/10-uke-bt.conf \
			| S 'tar -xpf - --no-overwrite-dir -C / && sync'
		S 'bash -s' <<'REMOTE'
set -eu
command -v bluetoothctl >/dev/null && [ -x /usr/lib/bluetooth/bluetoothd ] || { echo "falta bluez: aplica --pkgs" >&2; exit 1; }
[ -f /etc/systemd/system/uke-bt.service ] && [ -x /usr/local/sbin/uke-bt-up.sh ] || { echo "falta uke-bt.service: aplica --service" >&2; exit 1; }
chmod 0755 /etc/systemd/system/bluetooth.service.d; chmod 0644 /etc/systemd/system/bluetooth.service.d/10-uke-bt.conf
c=/etc/bluetooth/main.conf
[ -f $c ] || { echo "falta $c" >&2; exit 1; }
[ -f $c.uke-bak ] || cp -p $c $c.uke-bak
if grep -q '^AutoEnable=' $c; then sed -i 's/^AutoEnable=.*/AutoEnable=true/' $c
else sed -i '/^\[Policy\]/a AutoEnable=true' $c; fi
grep -q '^AutoEnable=true$' $c || { echo "no pude fijar AutoEnable=true" >&2; exit 1; }
systemctl daemon-reload
systemd-analyze verify --man=no /etc/systemd/system/uke-bt.service 2>&1 | sed 's/^/  verify: /' || true
systemctl enable bluetooth.service 2>&1 | tail -2
sync
echo "bluetooth.service: $(systemctl is-enabled bluetooth.service 2>&1 | head -1) / $(systemctl is-active bluetooth.service 2>&1 | head -1) (NO arrancado por este script)"
echo "  orden: $(systemctl show bluetooth.service -p After -p Wants | tr ' ' '\n' | grep uke-bt | tr '\n' ' ')"
echo "  main.conf: $(grep -E '^AutoEnable=' $c) (copia previa: $c.uke-bak)"
REMOTE
	fi
	if [ "$SLEEP" = 1 ]; then
		say "== 9. SUEÑO (D2): gancho uke-bt-sleep + uke-bt-resume =="
		tar -C "$TREE" --owner=0 --group=0 --numeric-owner --no-recursion -cf - usr/lib/systemd/system-sleep/uke-bt-sleep usr/local/sbin/uke-bt-resume \
			| S 'tar -xpf - --no-overwrite-dir -C / && sync'
		S 'bash -s' <<'REMOTE'
set -eu
chmod 0755 /usr/lib/systemd/system-sleep/uke-bt-sleep /usr/local/sbin/uke-bt-resume
bash -n /usr/lib/systemd/system-sleep/uke-bt-sleep && bash -n /usr/local/sbin/uke-bt-resume
mkdir -p /var/lib/uke
ls -la /usr/lib/systemd/system-sleep/ | sed 's/^/  /'
sync
echo "gancho de sueño instalado: PRUEBA OBLIGADA antes de fiarse: suspender 20 s con alarma RTC y el auricular conectado (ver BT-DIARIO-PLAN, etapa D2)"
REMOTE
	fi
	if [ "$WAIT" = 1 ]; then
		say "== 10. ESPERA DEL ESCRITORIO (D4b): uke-bt-wait + drop-in de uke-desktop.service =="
		tar -C "$TREE" --owner=0 --group=0 --numeric-owner --no-recursion -cf - usr/local/sbin/uke-bt-wait etc/systemd/system/uke-desktop.service.d etc/systemd/system/uke-desktop.service.d/20-uke-bt.conf \
			| S 'tar -xpf - --no-overwrite-dir -C / && sync'
		S 'bash -s' <<'REMOTE'
set -eu
[ -f /etc/systemd/system/uke-desktop.service ] || { echo "falta uke-desktop.service (deploy/arranque)" >&2; exit 1; }
chmod 0755 /usr/local/sbin/uke-bt-wait /etc/systemd/system/uke-desktop.service.d; chmod 0644 /etc/systemd/system/uke-desktop.service.d/20-uke-bt.conf
bash -n /usr/local/sbin/uke-bt-wait
systemctl daemon-reload
echo "  ExecStartPre efectivo de uke-desktop.service: $(systemctl show uke-desktop.service -p ExecStartPre | grep -o 'uke-bt-wait' | head -1)"
systemctl cat uke-desktop.service | grep -E '^(ExecStartPre|ExecCondition|ExecStart)=' | sed 's/^/  /'
sync
echo "espera del escritorio instalada (efecto en el PROXIMO arranque; no se arranca nada)"
REMOTE
	fi
	if [ "$HCIQCA" = 1 ]; then
		say "== 11. hci_uart PARCHEADO (tiempos del WCN6750) + bt-medir.sh + bt-consumo.sh =="
		# UN solo archivo tar (el `tar -xpf -` remoto lee solo el primero si se concatenan varios); modo 0755 para ambos: el .ko no necesita bit x pero es inocuo
		tar --owner=0 --group=0 --numeric-owner --mode='u=rwx,go=rx' \
			--transform="s,^hci_uart.ko$,usr/lib/modules/$KREL/updates/hci_uart.ko," --transform="s,^bt-medir.sh$,usr/local/sbin/bt-medir.sh," --transform="s,^bt-consumo.sh$,usr/local/sbin/bt-consumo.sh," \
			-cf - -C "$HERE/out-hciqca" hci_uart.ko -C "$HERE/hciqca" bt-medir.sh -C "$HERE/consumo" bt-consumo.sh | S 'tar -xpf - --no-overwrite-dir -C / && sync'
		S "bash -s" <<REMOTE
set -eu
k=$KREL
[ -f /usr/lib/modules/\$k/updates/hci_uart.ko ] || { echo "no llego hci_uart.ko" >&2; exit 1; }
rm -fv /usr/lib/modules/\$k/extra/hci_uart.ko   # residuo de un primer intento: extra/ no se busca (search.conf) y no debe confundir
chmod 0644 /usr/lib/modules/\$k/updates/hci_uart.ko; chmod 0755 /usr/local/sbin/bt-medir.sh /usr/local/sbin/bt-consumo.sh
vm=\$(modinfo -F vermagic /usr/lib/modules/\$k/updates/hci_uart.ko)
[ "\$vm" = "$REFVM" ] || { echo "vermagic de hci_uart.ko en la tablet: '\$vm'" >&2; exit 1; }
depmod -a "\$k"
echo "  modinfo -k \$k -n hci_uart: \$(modinfo -k \$k -n hci_uart)"
case "\$(modinfo -k \$k -n hci_uart)" in */updates/hci_uart.ko) ;; *) echo "depmod no resuelve hci_uart a updates/ (revisa /usr/lib/depmod.d/search.conf)" >&2; exit 1 ;; esac
modinfo -k "\$k" -F parm hci_uart | grep -q '^uke_bt_boot_ms:' || { echo "depmod no prefiere el hci_uart parcheado" >&2; exit 1; }
bash -n /usr/local/sbin/bt-medir.sh; bash -n /usr/local/sbin/bt-consumo.sh
grep -q '^hci_uart ' /proc/modules && echo "AVISO: hci_uart ya esta cargado (el de serie): el parcheado se usara al descargarlo y volver a cargarlo (uke-bt-up.sh --down)"
sync
echo "hci_uart parcheado instalado (defaults = serie); nada cargado. Medir: bt-medir.sh --help"
REMOTE
	fi
	if [ -n "$HQCONF" ]; then
		say "== 12. opciones persistentes del hci_uart parcheado =="
		S "bash -s" <<REMOTE
set -eu
modinfo -k $KREL -F parm hci_uart | grep -q '^uke_bt_boot_ms:' || { echo "el hci_uart parcheado no esta instalado en la tablet: usa --hciqca" >&2; exit 1; }
printf '# uke: tiempos de encendido del WCN6750 (BT-MUDO-FIX-20261021.md; las pone deploy.sh --hciqca-conf)\noptions hci_uart %s\n' "$HQCONF" > /etc/modprobe.d/uke-bt-hci.conf
chmod 0644 /etc/modprobe.d/uke-bt-hci.conf
sync
echo "  /etc/modprobe.d/uke-bt-hci.conf: \$(tail -n 1 /etc/modprobe.d/uke-bt-hci.conf)"
echo "opciones fijadas; surten efecto en el proximo modprobe de hci_uart (proximo encendido del BT)"
REMOTE
	fi
fi

say "== 7. lectura final y comparacion =="
snapshot > "$HERE/.snap-after" 2>/dev/null || true
sed 's/^/  despues: /' "$HERE/.snap-after"
diffs=$(diff <(grep -vE '^kernel=' "$HERE/.snap-before") <(grep -vE '^kernel=' "$HERE/.snap-after") || true)
if [ -z "$diffs" ]; then say "  WiFi, ath11k, adsp.b40 y modulos BT: IGUAL que antes"; else say "  OJO, cambios respecto a antes (vigila WiFi/ath11k):"; echo "$diffs" | sed 's/^/    /'; fi
say "== hecho. Siguiente (a mano, con orden del dueño, con ACM + ssh dmesg -w abiertos) =="
cat <<EOF
  $0 --check                                   # lectura: que quedo instalado
  ssh -i $KEY $SSHUSER@$HOST 'dmesg -n 7; sync; /usr/local/sbin/uke-bt-up.sh --status'
  B3 (solo UART):  UKE_BT_VARIANT=u /usr/local/sbin/uke-bt-up.sh      (descargar: ... --down)
  B4 (primer encendido del chip, variante B):  /usr/local/sbin/uke-bt-up.sh
  Si el SSH muere: es un wedge. Al volver: journalctl -b -1 -k, /var/log/uke-bt.log, pstore; uke-bootguard status bt.
EOF
