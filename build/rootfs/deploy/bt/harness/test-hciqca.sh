#!/bin/bash
# test-hciqca.sh — prueba EN EL PC (sin tablet) el material de hciqca/: que el parche aplica a las fuentes ouke5/ouke6, que bt-medir.sh produce el registro
# esperado con mocks (dmesg/modinfo/uke-bt-up.sh simulados: orden aleatorio, restauracion final, deteccion de hci_uart sin parche) y que analiza-medicion.py da
# las cifras correctas (se contrastan con un calculo independiente). Uso: test-hciqca.sh
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd); BT=$(cd "$HERE/.." && pwd); R=$(cd "$BT/../../../.." && pwd)
M=$BT/hciqca/bt-medir.sh; A=$BT/hciqca/analiza-medicion.py; P=$BT/hciqca/hci_qca-uke-tiempos.patch
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0; ck() { local d=$1; shift; if "$@"; then printf '  OK   %s\n' "$d"; else printf '  FALLO %s\n' "$d"; fail=1; fi; }
echo "== el parche aplica (dry-run) a las fuentes de cada kernel =="
for t in senemos-ouke5 senemos-ouke6; do
	K=$R/build/kernel-pokes/$t/linux-7.2.9
	[ -e "$K/drivers/bluetooth/hci_qca.c" ] || { echo "  (sin $t: omitido)"; continue; }
	ck "$t: patch --dry-run -p1" bash -c "cd '$K' && patch --dry-run -p1 -s < '$P'"
done
ck "el parche solo toca drivers/bluetooth/hci_qca.c" test "$(grep -c '^+++ ' "$P")" = 1
ck "los valores por defecto son los de serie (50, 50, sin sondeo)" bash -c "grep -q 'uke_bt_low_ms = 50;' '$P' && grep -q 'uke_bt_boot_ms = 50;' '$P' && grep -q '^+static unsigned int uke_bt_swctrl_ms;' '$P'"
echo "== bt-medir.sh: argumentos y plan =="
ck "sintaxis" bash -n "$M"
out=$("$M" --dry-run -n 5 -c "50:50:0 50:200:0" 2>&1); rc=$?
ck "--dry-run: rc 0 y plan de 10 ciclos" bash -c "test $rc = 0 && grep -q '10 ciclos' <<<'$out'"
ck "--dry-run lista las opciones de modprobe" bash -c "grep -q 'uke_bt_low_ms=50 uke_bt_boot_ms=200 uke_bt_swctrl_ms=0' <<<'$out'"
"$M" --dry-run -n 0 >/dev/null 2>&1; ck "-n 0: rc 1" test $? = 1
"$M" --dry-run -c "basura" >/dev/null 2>&1; ck "configuracion invalida: rc 1" test $? = 1
"$M" --nada >/dev/null 2>&1; ck "opcion desconocida: rc 1" test $? = 1
echo "== bt-medir.sh con mocks (3 rondas x 3 configuraciones) =="
mkdir -p "$T/bin"; : > "$T/dmesg"; : > "$T/calls"; echo 0 > "$T/n"
cat > "$T/bin/id" <<'S'
#!/bin/bash
echo 0
S
cat > "$T/bin/modinfo" <<'S'
#!/bin/bash
[ -e "$MOCK/sin-parche" ] || echo "uke_bt_boot_ms:WCN6750: ms de espera"
S
printf '#!/bin/bash\ncat "$MOCK/dmesg"\n' > "$T/bin/dmesg"
for c in sync sleep; do printf '#!/bin/bash\nexit 0\n' > "$T/bin/$c"; done
printf '#!/bin/bash\necho 4\n' > "$T/bin/nproc"
printf '#!/bin/bash\n[ "$1" = route ] && echo "default via 192.0.2.19 dev wlan0"\nexit 0\n' > "$T/bin/ip"
cat > "$T/up" <<'S'
#!/bin/bash
# uke-bt-up.sh simulado: --down no hace nada; --service anade al dmesg falso un resultado segun las opciones
echo "$* [opts=${UKE_BT_HCI_OPTS:-} cycles=${UKE_BT_CYCLES:-}]" >> "$MOCK/calls"
[ "$1" = --service ] || exit 0
n=$(( $(cat "$MOCK/n") + 1 )); echo "$n" > "$MOCK/n"
B=$(sed -n 's/.*uke_bt_boot_ms=\([0-9]*\).*/\1/p' <<<"${UKE_BT_HCI_OPTS:-}"); S=$(sed -n 's/.*uke_bt_swctrl_ms=\([0-9]*\).*/\1/p' <<<"${UKE_BT_HCI_OPTS:-}")
{
	echo "[  100.0] Bluetooth: hci0: setting up wcn6750"
	if [ "${B:-50}" -ge 200 ] || [ $((n % 2)) = 0 ]; then :; else echo "[  102.1] Bluetooth: hci0: command 0xfc00 tx timeout"; echo "[  102.2] Bluetooth: hci0: Retry BT power ON:0"; fi
	[ "${S:-0}" -gt 0 ] && echo "[  100.1] Bluetooth: hci0: uke: SW_CTRL=1 a los $((40000 + n * 100)) us de subir BT_EN"
	echo "[  103.0] Bluetooth: hci0: QCA setup on UART is completed"
} >> "$MOCK/dmesg"
echo "uke-bt-up: VERDE"; exit 0
S
chmod +x "$T/bin/"* "$T/up"
export MOCK=$T BT_UP=$T/up PATH=$T/bin:$PATH
"$M" -n 3 -c "50:50:0 50:200:0 50:50:300" -o "$T/medir.log" > "$T/out.txt" 2>&1; rc=$?
ck "rc 0" test "$rc" = 0
ck "9 lineas CICLO" test "$(grep -c '^CICLO' "$T/medir.log")" = 9
ck "cada configuracion aparece 3 veces" bash -c "test \$(grep -c 'cfg=50:50:0 ' '$T/medir.log') = 3 && test \$(grep -c 'cfg=50:200:0 ' '$T/medir.log') = 3 && test \$(grep -c 'cfg=50:50:300 ' '$T/medir.log') = 3"
ck "las opciones llegan a uke-bt-up.sh con UKE_BT_CYCLES=1 en las mediciones" bash -c "grep -q '^--service \[opts=uke_bt_low_ms=50 uke_bt_boot_ms=200 uke_bt_swctrl_ms=0 cycles=1\]' '$T/calls'"
ck "con boot_ms=200 el 1.er intento siempre acierta (timeouts=0)" bash -c "! grep 'cfg=50:200:0 ' '$T/medir.log' | grep -v 'timeouts=0 ok=1'"
ck "se registra rise_us solo en la configuracion con sondeo" bash -c "grep 'cfg=50:50:300 ' '$T/medir.log' | grep -qv 'rise_us=-' && ! grep 'cfg=50:50:0 ' '$T/medir.log' | grep -qv 'rise_us=-'"
ck "restauracion final: --down y --service con UKE_BT_CYCLES=3 y sin opciones" bash -c "tail -n 2 '$T/calls' | head -1 | grep -q '^--down' && tail -n 1 '$T/calls' | grep -q '^--service \[opts= cycles=3\]'"
ck "imprime el resumen rapido" grep -q 'resumen rapido' "$T/out.txt"
touch "$T/sin-parche"; "$M" -n 1 -o "$T/x.log" >/dev/null 2>"$T/err.txt"; rc=$?
ck "hci_uart sin parche: rc 2 y mensaje claro, sin tocar nada" bash -c "test $rc = 2 && grep -q 'NO es el parcheado' '$T/err.txt'"
rm -f "$T/sin-parche"
echo "== analiza-medicion.py contra un calculo independiente =="
python3 - "$T/sint.log" <<'PY'
import sys, random
random.seed(7); L = []
def add(cfg, n, f1, rec, mute, rises=None):
    kinds = ['f1'] * f1 + ['rec'] * rec + ['mute'] * mute; assert len(kinds) == n
    for i, k in enumerate(kinds):
        t, ok = (0, 1) if k == 'f1' else ((1, 1) if k == 'rec' else (4, 0))
        r = '-' if rises is None else str((30000 if k == 'f1' else 80000) + i * 10)
        L.append(f"CICLO ronda={i + 1} cfg={cfg} rc=0 timeouts={t} ok={ok} rise_us={r} dur_s=4.0")
add('50:50:0', 20, 10, 8, 2)
add('50:300:0', 20, 19, 1, 0)
add('50:50:300', 20, 11, 7, 2, rises=True)
open(sys.argv[1], 'w').write('# sintetico\n' + '\n'.join(L) + '\n')
PY
out=$(python3 -I "$A" "$T/sint.log" 2>&1)
ck "control: 20 ciclos, 10 de 1.er intento OK (50 %), 2 mudos" bash -c "grep -E '^50:50:0 ' <<<'$out' | grep -qE '20 +10 +50% .* 2 '"
ck "50:300:0: 19 de 20 (95 %), 0 mudos" bash -c "grep -E '^50:300:0 ' <<<'$out' | grep -qE '20 +19 +95%'"
PEXP=$(python3 -I -c "
from math import comb
a,b,c,d=19,1,10,10
n1,n2,k=a+b,c+d,a+c
pr=lambda x: comb(n1,x)*comb(n2,k-x)/comb(n1+n2,k)
p0=pr(a); print('%.3f' % sum(pr(x) for x in range(max(0,k-n2),min(n1,k)+1) if pr(x)<=p0*(1+1e-9)))")
ck "p de Fisher de 50:300:0 vs control = $PEXP (calculo independiente)" bash -c "grep -E '^50:300:0 ' <<<'$out' | grep -q ' $PEXP\$'"
ck "veredicto: 50:300:0 MEJORA y 50:50:300 no" bash -c "grep -q '50:300:0: MEJORA' <<<'$out' && ! grep -q '50:50:300: MEJORA' <<<'$out'"
ck "SW_CTRL: separa 1.er intento OK (mediana ~30 ms) y MAL (~80 ms)" bash -c "grep -q '1.er intento OK :.*mediana=3' <<<'$out' && grep -q '1.er intento MAL:.*mediana=8' <<<'$out'"
[ "$fail" = 0 ] && echo "TODO OK" || echo "HAY FALLOS"
exit "$fail"
