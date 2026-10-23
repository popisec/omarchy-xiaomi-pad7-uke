#!/bin/bash
# offline-test.sh — prueba EN EL PC (sin tablet, sin red, sin root) de la lógica de
# uke-carga-start.sh / uke-carga-verify.sh / uke-usb-gadget-late.sh sobre un /sys y un
# modprobe FALSOS en un directorio temporal. No toca nada fuera de él.
# Uso: bash tests/offline-test.sh   (código 0 = todos los casos como se esperaba)
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
R=$(cd "$HERE/../../../.." && pwd)
SB=$HERE/rootfs/usr/local/sbin
FW=$R/charge/firmware
T=$(mktemp -d "${TMPDIR:-/tmp}/uke-carga-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
REL_OK=7.2.9-senemos.1.4054.3-ouke1

# ---- modprobe falso: registra la llamada y simula efectos ----
mkdir -p "$T/bin"
cat > "$T/bin/modprobe" <<'EOF'
#!/bin/bash
# $FAKE_DIR/scn = escenario; registra en $FAKE_DIR/modprobe.log
D=$FAKE_DIR
echo "$1" >> "$D/modprobe.log"
[ "$1" = "$FAKE_FAIL_MOD" ] && { echo "modprobe: ERROR: could not insert '$1'" >&2; exit 1; }
case "$1" in
qcom_q6v5_pas)
	# parche 0033: al probar, auto-arranca el ADSP (asíncrono)
	r=$D/sys/class/remoteproc/remoteproc0
	mkdir -p "$r"
	echo adsp > "$r/name"; echo adsp.mdt > "$r/firmware"
	case "$FAKE_ADSP" in
	auto)  echo offline > "$r/state"; ( sleep 1; echo running > "$r/state" ) >/dev/null 2>&1 & ;;
	manual) echo offline > "$r/state"
		( while :; do [ "$(cat "$r/state")" = start ] && { echo running > "$r/state"; echo manual-start >> "$D/events.log"; break; }; sleep 0.2; done ) >/dev/null 2>&1 & ;;
	never) echo offline > "$r/state" ;;
	crashed) echo crashed > "$r/state"
		( while :; do s=$(cat "$r/state"); [ "$s" = stop ] && echo offline > "$r/state"; [ "$s" = start ] && { echo running > "$r/state"; echo crash-recover >> "$D/events.log"; break; }; sleep 0.2; done ) >/dev/null 2>&1 & ;;
	esac
	if [ "$FAKE_PSY" != none ]; then
		p=$D/sys/class/power_supply/qcom-battmgr-bat
		( sleep 2; mkdir -p "$p"; echo "$FAKE_PSY" > "$p/status"; echo 3912345 > "$p/voltage_now"; echo 530000 > "$p/current_now"; echo 42 > "$p/capacity" ) >/dev/null 2>&1 &
	fi
	;;
esac
exit 0
EOF
chmod +x "$T/bin/modprobe"

mk_env() { # prepara $T/env fresco: fw (symlinks), mods, sys
	rm -rf "$T/env"
	mkdir -p "$T/env/fw" "$T/env/mods" "$T/env/sys/class" "$T/env/run"
	for f in "$FW"/*; do ln -s "$f" "$T/env/fw/$(basename "$f")"; done
	cp "$R/charge/adsp-fw.sha256" "$T/env/fw/adsp-fw.sha256"
	: > "$T/env/mods/modules.dep"
	: > "$T/env/modprobe.log"; : > "$T/env/events.log"
}
run_start() { # $1=adsp mode $2=psy status; env extra por variables del caso
	FAKE_DIR=$T/env FAKE_ADSP=${1:-auto} FAKE_PSY=${2:-Charging} FAKE_FAIL_MOD=${FAKE_FAIL_MOD:-} \
	UKE_REL=${UKE_REL:-$REL_OK} UKE_SYS=$T/env/sys UKE_FWDIR=$T/env/fw UKE_MODDIR=$T/env/mods \
	UKE_MODPROBE=$T/bin/modprobe UKE_KMSG=/dev/null UKE_RUN=$T/env/run \
	UKE_T_AUTO=${UKE_T_AUTO:-3} UKE_T_RUN=${UKE_T_RUN:-8} UKE_T_PSY=${UKE_T_PSY:-6} \
	sh "$SB/uke-carga-start.sh" > "$T/env/out.log" 2>&1
	echo $?
}
expect() { # $1=nombre $2=esperado $3=obtenido
	if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "  PASA  $1"; else FAIL=$((FAIL + 1)); echo "  FALLA $1 (esperado '$2', obtenido '$3')"; [ -f "$T/env/out.log" ] && tail -8 "$T/env/out.log" | sed 's/^/        /'; fi
}
calls() { tr '\n' ' ' < "$T/env/modprobe.log" | sed 's/ $//'; }

echo "== A. auto-boot (0033) + Charging -> verde =="
mk_env; rc=$(run_start auto Charging)
expect "A exit 0" 0 "$rc"
expect "A orden de carga (pas el último)" "qrtr qrtr_smd qcom_pd_mapper pmic_glink qcom_battmgr qcom_q6v5_pas" "$(calls)"
grep -q '^result=VERDE' "$T/env/run/uke-carga.status" && expect "A status file" ok ok || expect "A status file" ok "no VERDE"

echo "== B. adsp.b40 corrupto: NO se carga ningún módulo, exit 4 =="
mk_env; rm "$T/env/fw/adsp.b40"; head -c 1000 /dev/urandom > "$T/env/fw/adsp.b40"; rc=$(run_start auto Charging)
expect "B exit 4" 4 "$rc"; expect "B 0 modprobe (ni pas ni nada)" "" "$(calls)"
grep -q 'adsp.b40 con sha MALA' "$T/env/out.log" && expect "B mensaje b40" ok ok || expect "B mensaje b40" ok falta

echo "== B2. adsp.b40 ausente =="
mk_env; rm "$T/env/fw/adsp.b40"; rc=$(run_start auto Charging)
expect "B2 exit 4" 4 "$rc"; expect "B2 0 modprobe" "" "$(calls)"

echo "== B3. otro segmento corrupto (solo lo ve el manifiesto) =="
mk_env; rm "$T/env/fw/adsp.b09"; head -c 1000 /dev/urandom > "$T/env/fw/adsp.b09"; rc=$(run_start auto Charging)
expect "B3 exit 4" 4 "$rc"; expect "B3 0 modprobe" "" "$(calls)"

echo "== C. sin modules.dep =="
mk_env; rm "$T/env/mods/modules.dep"; rc=$(run_start auto Charging)
expect "C exit 4" 4 "$rc"; expect "C 0 modprobe" "" "$(calls)"

echo "== D. kernel palawan: no hace nada =="
mk_env; rc=$(UKE_REL=7.2.0-rc2-palawan run_start auto Charging)
expect "D exit 0" 0 "$rc"; expect "D 0 modprobe" "" "$(calls)"

echo "== E. auto-boot no llega: UN echo start manual =="
mk_env; rc=$(run_start manual Charging)
expect "E exit 0" 0 "$rc"; expect "E start manual hecho" "manual-start" "$(cat "$T/env/events.log")"

echo "== E2. ADSP crashed (recovery off): stop+start =="
mk_env; rc=$(run_start crashed Charging)
expect "E2 exit 0" 0 "$rc"; expect "E2 recuperado" "crash-recover" "$(cat "$T/env/events.log")"

echo "== F. ADSP nunca arranca -> exit 5 =="
mk_env; rc=$(UKE_T_RUN=6 UKE_T_AUTO=2 run_start never Charging)
expect "F exit 5" 5 "$rc"

echo "== G. batería sin cargar (Discharging) -> amarillo 2 =="
mk_env; rc=$(run_start auto Discharging)
expect "G exit 2" 2 "$rc"

echo "== H. sin power_supply -> rojo 3 =="
mk_env; rc=$(UKE_T_PSY=3 run_start auto none)
expect "H exit 3" 3 "$rc"

echo "== I. falla qrtr_smd: se aborta ANTES del ADSP =="
mk_env; rc=$(FAKE_FAIL_MOD=qrtr_smd run_start auto Charging)
expect "I exit 4" 4 "$rc"; expect "I pas NO cargado" "qrtr qrtr_smd" "$(calls)"

echo "== J. ADSP ya running (idempotencia): no recarga pas =="
mk_env; mkdir -p "$T/env/sys/class/remoteproc/remoteproc0"; r=$T/env/sys/class/remoteproc/remoteproc0
echo adsp > $r/name; echo running > $r/state; echo adsp.mdt > $r/firmware
mkdir -p "$T/env/sys/class/power_supply/qcom-battmgr-bat"; p=$T/env/sys/class/power_supply/qcom-battmgr-bat
echo Charging > $p/status; echo 3900000 > $p/voltage_now
rc=$(run_start auto Charging)
expect "J exit 0" 0 "$rc"; expect "J sin qcom_q6v5_pas" "qrtr qrtr_smd qcom_pd_mapper pmic_glink qcom_battmgr" "$(calls)"

echo "== K. gadget tardío: UDC aparece, se crea y enlaza g1 =="
K=$T/k; mkdir -p "$K/sys/class/udc/fake.udc" "$K/sys/kernel/config/usb_gadget"
UKE_SYS=$K/sys UKE_CFG=$K/sys/kernel/config/usb_gadget UKE_T_UDC=3 sh "$SB/uke-usb-gadget-late.sh" > "$K/out.log" 2>&1; rc=$?
expect "K exit 0" 0 "$rc"
expect "K g1/UDC enlazado" fake.udc "$(cat "$K/sys/kernel/config/usb_gadget/g1/UDC" 2>/dev/null)"
[ -L "$K/sys/kernel/config/usb_gadget/g1/configs/c.1/acm.usb0" ] && [ -L "$K/sys/kernel/config/usb_gadget/g1/configs/c.1/ncm.usb0" ] \
	&& expect "K acm+ncm en c.1" ok ok || expect "K acm+ncm en c.1" ok falta
echo "== K2. gadget ya enlazado por el initramfs: no toca =="
K2=$T/k2; mkdir -p "$K2/sys/class/udc/fake.udc" "$K2/sys/kernel/config/usb_gadget/g1"; echo fake.udc > "$K2/sys/kernel/config/usb_gadget/g1/UDC"
UKE_SYS=$K2/sys UKE_CFG=$K2/sys/kernel/config/usb_gadget UKE_T_UDC=2 sh "$SB/uke-usb-gadget-late.sh" > "$K2/out.log" 2>&1; rc=$?
expect "K2 exit 0" 0 "$rc"; grep -q 'ya hay un gadget enlazado' "$K2/out.log" && expect "K2 no-op" ok ok || expect "K2 no-op" ok falta
echo "== K3. sin UDC (dwc3 diferido): exit 1 =="
K3=$T/k3; mkdir -p "$K3/sys/class/udc" "$K3/sys/kernel/config/usb_gadget"
UKE_SYS=$K3/sys UKE_CFG=$K3/sys/kernel/config/usb_gadget UKE_T_UDC=2 sh "$SB/uke-usb-gadget-late.sh" > "$K3/out.log" 2>&1; rc=$?
expect "K3 exit 1" 1 "$rc"

echo "== L. verify --post / --watch sobre sysfs falso (con dmesg/systemctl de pega) =="
mk_env
mkdir -p "$T/vbin"
cat > "$T/vbin/dmesg" <<'EOF'
#!/bin/sh
echo "[   20.1] remoteproc remoteproc0: remote processor 3000000.remoteproc is now up"
echo "[   21.0] PDR: Indication received from msm/adsp/charger_pd, state: 0x1fffffff"
EOF
cat > "$T/vbin/systemctl" <<'EOF'
#!/bin/sh
[ "$2" = uke-carga.service ] && echo active || echo inactive
EOF
chmod +x "$T/vbin/"*
V=$T/venv; mkdir -p "$V/sys/class/remoteproc/remoteproc0" "$V/sys/class/power_supply/qcom-battmgr-bat" "$V/sys/class/power_supply/qcom-battmgr-usb" "$V/sys/class/udc/x.udc"
for m in qrtr qrtr_smd qcom_pd_mapper pmic_glink qcom_battmgr qcom_q6v5_pas qcom_sysmon qcom_glink_smem; do mkdir -p "$V/sys/module/$m"; done
r=$V/sys/class/remoteproc/remoteproc0; echo adsp > $r/name; echo running > $r/state; echo adsp.mdt > $r/firmware
p=$V/sys/class/power_supply/qcom-battmgr-bat; echo Charging > $p/status; echo 3900000 > $p/voltage_now; echo 700000 > $p/current_now; echo 40 > $p/capacity
echo 1 > $V/sys/class/power_supply/qcom-battmgr-usb/online
UKE_PATH="$T/vbin:$PATH" UKE_REL=$REL_OK UKE_SYS=$V/sys UKE_FWDIR=$T/env/fw sh "$SB/uke-carga-verify.sh" --post > "$V/post.log" 2>&1; rc=$?
expect "L --post exit 0" 0 "$rc"
grep -c '^\[FALLA\]' "$V/post.log" | grep -q '^0$' && expect "L --post 0 FALLA" ok ok || { expect "L --post 0 FALLA" ok falla; cat "$V/post.log" | sed 's/^/        /'; }
# watch con voltaje que baja -> debe dar FALLA
( for v in 3900000 3890000 3880000; do sleep 0.7; echo $v > $p/voltage_now; done ) &
UKE_PATH="$T/vbin:$PATH" UKE_REL=$REL_OK UKE_SYS=$V/sys sh "$SB/uke-carga-verify.sh" --watch 3 1 > "$V/watch.log" 2>&1; rc=$?
expect "L --watch voltaje baja => exit 1" 1 "$rc"
wait
# watch con voltaje que sube -> OK
echo 3900000 > $p/voltage_now
( for v in 3910000 3920000; do sleep 0.7; echo $v > $p/voltage_now; done ) &
UKE_PATH="$T/vbin:$PATH" UKE_REL=$REL_OK UKE_SYS=$V/sys sh "$SB/uke-carga-verify.sh" --watch 3 1 > "$V/watch2.log" 2>&1; rc=$?
expect "L --watch voltaje sube => exit 0" 0 "$rc"
wait
# kernel equivocado
UKE_PATH="$T/vbin:$PATH" UKE_REL=7.2.0-rc2-palawan UKE_SYS=$V/sys UKE_FWDIR=$T/env/fw sh "$SB/uke-carga-verify.sh" --post > "$V/bad.log" 2>&1; rc=$?
expect "L kernel palawan => exit 1" 1 "$rc"

echo
echo "== RESULTADO: $PASS pasan, $FAIL fallan =="
[ "$FAIL" -eq 0 ]
