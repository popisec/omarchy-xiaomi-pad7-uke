#!/bin/bash
# test-ciclo.sh — prueba EN EL PC (sin tablet) ciclo-prueba.sh con un ssh/fuser SIMULADOS: compuertas (host USB, lector ACM, release==vermagic, bateria, adaptador),
# plan sin ssh, orden y argumentos de las etapas, parada ante el fallo de una etapa (set -e no actua dentro de `|| die`), veredicto de la suspension (VERDE/ROJO) y
# que el analisis corre sobre los registros recogidos. Uso: test-ciclo.sh
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd); BT=$(cd "$HERE/.." && pwd); C=$BT/ciclo-prueba.sh
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; mkdir -p "$T/bin"
fail=0; ck() { local d=$1; shift; if "$@"; then printf '  OK   %s\n' "$d"; else printf '  FALLO %s\n' "$d"; fail=1; fi; }
VM=$(modinfo -F vermagic "$BT/out/uke_bt_b.ko" | cut -d' ' -f1)
# --- ssh simulado: responde por patron; SIM_* regulan el estado de la "tablet" ---
cat > "$T/bin/ssh" <<'SIM'
#!/bin/bash
while [[ "${1:-}" == -* ]]; do case "$1" in -i|-o) shift 2 ;; *) shift ;; esac; done
shift; cmd="$*"; echo "ssh: $cmd" >> "$SIM_LOG"
case "$cmd" in
	"uname -r") [ "${SIM_DOWN:-0}" = 1 ] && exit 255; echo "${SIM_KREL:-$SIM_VM}" ;;
	cap=*) echo "${SIM_BAT:-80 Discharging}"; echo "active active "; echo "${SIM_POW:-1}" ;;
	true) [ "${SIM_NOBACK:-0}" = 1 ] && exit 255; exit 0 ;;
	"ss -Htn"*) echo "${SIM_SSHN:-1}" ;;
	"cat > /run/uke-bt-susp.sh"*) cat > "$SIM_LOG.script" ;;
	"test -e /run/uke-bt-susp-rc") [ "${SIM_NOBACK:-0}" = 1 ] && exit 255; exit 0 ;;
	"systemd-inhibit --list"*) echo "WHO ... WHAT WHY MODE"; echo "uke-idle-guard 0 root 1 sleep:idle sesion SSH abierta block" ;;
	"bt-medir.sh"*) [ "${SIM_FAIL_MEDIR:-0}" = 1 ] && { echo "bt-medir: fallo simulado"; exit 3; }; echo "medido" ;;
	"cat /root/medir-"*) python3 - <<'PY'
import random
random.seed(7)
for r in range(1, 21):
    for cfg in ("50:50:0", "50:150:0", "50:300:0", "50:50:300"):
        ok1 = random.random() < (0.5 if cfg == "50:50:0" else 0.8)
        print(f"CICLO ronda={r} cfg={cfg} rc=0 timeouts={0 if ok1 else 1} ok=1 rise_us={'-' if cfg != '50:50:300' else 20000} dur_s=7")
PY
	;;
	"for m in \$(bluetoothctl devices Connected"*"wc -l") echo "${SIM_CONN:-1}" ;;
	"wc -l < /var/log/uke-bt.log") echo 100 ;;
	systemd-run*) echo "ssh-lanzado" >> "$SIM_LOG" ;;
	"echo \"RC_SUSPEND="*) echo "RC_SUSPEND=${SIM_RC:-0}"; echo "inhibidores block restantes: ${SIM_INH:-0}"; printf '%s\n' "${SIM_SUSP_LOG}"; echo "pm_wakeup_irq=  suspend_ok=3 suspend_fail=0"; echo "CONECTADOS=${SIM_CONN:-1}" ;;
	*) echo "(comando no previsto en el simulador: $cmd)" >> "$SIM_LOG"; exit 0 ;;
esac
SIM
cat > "$T/bin/fuser" <<'S'
#!/bin/bash
[ "${SIM_ACM:-1}" = 1 ] && echo 4242; exit 0
S
cat > "$T/deploy" <<'S'
#!/bin/bash
echo "deploy $*" >> "$SIM_LOG"; exit "${SIM_FAIL_DEPLOY:-0}"
S
chmod +x "$T/bin/ssh" "$T/bin/fuser" "$T/deploy"
export PATH=$T/bin:$PATH SIM_LOG=$T/log SIM_VM=$VM CICLO_DEPLOY=$T/deploy CICLO_ESPERA=0 CICLO_PAUSA=0 CICLO_ASENTAR=0 UKE_ACM=$T/acm
newlog() { : > "$T/log"; rm -rf "$T/o"; export CICLO_OUT=$T/o; }
nssh() { grep -c '^ssh: ' "$T/log"; }
run() { "$C" "$@" > "$T/out" 2>&1; echo $? > "$T/rc"; }
rc() { cat "$T/rc"; }
SLEEP_OK=$'2026-10-21T10:00:00Z uke-bt-sleep: pre: conectados=1, de audio guardados=1 (los demas se reconectan solos); apago el adaptador\n2026-10-21T10:00:27Z uke-bt-sleep: post: reanudacion lanzada (systemd-run)\n2026-10-21T10:00:30Z uke-bt-resume: adaptador encendido\n2026-10-21T10:00:35Z uke-bt-resume: reconexion de 00:11:22:XX:XX:XX OK'

echo "== plan y argumentos =="
newlog; run; ck "sin --go: rc 0 y CERO llamadas a ssh" bash -c "test $(rc) = 0 && test $(nssh) = 0 && grep -q 'solo plan' '$T/out'"
newlog; run --etapas "deploy medir carga suspension consumo" --rondas 12; ck "el plan lista las 5 etapas con las rondas pedidas" bash -c "grep -q 'deploy .*--go --service --sleep --hciqca' '$T/out' && grep -q 'bt-medir.sh -n 12' '$T/out' && grep -q 'suspension :' '$T/out' && grep -q 'consumo    :' '$T/out'"
newlog; run --etapas "deploy nada"; ck "etapa desconocida: rc 1" test "$(rc)" = 1
newlog; run --rondas 0; ck "--rondas 0: rc 1" test "$(rc)" = 1
newlog; run --rondas abc; ck "--rondas abc: rc 1" test "$(rc)" = 1
newlog; run --nada; ck "opcion desconocida: rc 1" test "$(rc)" = 1

echo "== compuertas (--check) =="
newlog; run --check; ck "todo bien: rc 0, 'compuertas OK'" bash -c "test $(rc) = 0 && grep -q 'compuertas OK' '$T/out'"
newlog; UKE_HOST=100.64.0.10 run --check; ck "host Tailscale: ALTO (rc 1) sin ssh" bash -c "test $(rc) = 1 && grep -q 'debe ser el USB' '$T/out' && test $(nssh) = 0"
newlog; UKE_HOST=100.64.0.10 CICLO_HOST_OK=1 run --check; ck "host Tailscale con CICLO_HOST_OK=1: pasa" test "$(rc)" = 0
newlog; SIM_ACM=0 run --check; ck "sin lector ACM: ALTO antes de ningun ssh" bash -c "test $(rc) = 1 && grep -q 'no hay lector' '$T/out' && test $(nssh) = 0"
newlog; SIM_KREL=7.2.9-otra run --check; ck "release != vermagic: ALTO" bash -c "test $(rc) = 1 && grep -q 'vermagic' '$T/out'"
newlog; SIM_BAT="20 Discharging" run --check; ck "bateria 20 % descargando: ALTO" bash -c "test $(rc) = 1 && grep -q 'bateria 20' '$T/out'"
newlog; SIM_BAT="20 Charging" run --check; ck "bateria 20 % cargando: pasa" test "$(rc)" = 0
newlog; SIM_POW=0 run --check; ck "adaptador apagado: ALTO" bash -c "test $(rc) = 1 && grep -q 'no esta encendido' '$T/out'"
newlog; SIM_DOWN=1 run --check; ck "ssh que no responde: ALTO 'no hay SSH'" bash -c "test $(rc) = 1 && grep -q 'no hay SSH' '$T/out'"

echo "== --go: etapas deploy medir carga =="
newlog; run --go --rondas 20; ck "rc 0 y orden deploy -> medir -> carga" bash -c "test $(rc) = 0 && test \"\$(grep -E '^(deploy|ssh: bt-medir)' '$T/log' | head -1)\" = 'deploy --go --service --sleep --hciqca'"
ck "bt-medir con -n 20 (control+3), y dos veces con -w y -l sobre 50:50:0" bash -c "grep -q 'bt-medir.sh -n 20 -o' '$T/log' && grep -q 'bt-medir.sh -c 50:50:0 -n 30 -w -o' '$T/log' && grep -q 'bt-medir.sh -c 50:50:0 -n 30 -l -o' '$T/log'"
ck "registros recogidos y analizados (Wilson/Fisher) para medir, wifi y cpu" bash -c "ls '$T/o'/medir.log '$T/o'/medir-wifi.log '$T/o'/medir-cpu.log >/dev/null && grep -q 'Fisher\|fisher' '$T/o'/medir-analisis.txt && test -s '$T/o'/medir-wifi-analisis.txt && test -s '$T/o'/medir-cpu-analisis.txt"
ck "el analisis ve las 4 configuraciones" bash -c "for c in 50:50:0 50:150:0 50:300:0 50:50:300; do grep -q \"\$c\" '$T/o/medir-analisis.txt' || exit 1; done"
echo "== fallos: la etapa que falla PARA el ciclo =="
newlog; SIM_FAIL_DEPLOY=1 run --go; ck "deploy falla: rc 1, no se llama a bt-medir" bash -c "test $(rc) = 1 && ! grep -q 'bt-medir' '$T/log' && grep -q 'etapa deploy fallo' '$T/out'"
newlog; SIM_FAIL_MEDIR=1 run --go --etapas "medir carga"; ck "bt-medir falla: rc 1 y NO sigue con la carga" bash -c "test $(rc) = 1 && grep -q 'etapa medir fallo' '$T/out' && ! grep -q ' -w -o' '$T/log' && ! grep -q 'etapa carga' '$T/out'"
newlog; SIM_ACM=0 run --go; ck "con compuerta en rojo --go no ejecuta nada (ni deploy)" bash -c "test $(rc) = 1 && ! test -s '$T/log'"

echo "== etapa suspension =="
newlog; run --go --etapas suspension; ck "sin --con-auriculares: rc 1" bash -c "test $(rc) = 1 && grep -q 'exige --con-auriculares' '$T/out' && ! grep -q 'ssh-lanzado' '$T/log'"
newlog; SIM_CONN=0 run --go --etapas suspension --con-auriculares; ck "sin dispositivo de AUDIO conectado (p. ej. solo el lapiz): rc 1, no suspende" bash -c "test $(rc) = 1 && grep -q 'de AUDIO conectado' '$T/out' && ! grep -q 'ssh-lanzado' '$T/log'"
newlog; SIM_SUSP_LOG="$SLEEP_OK" run --go --etapas suspension --con-auriculares; ck "caso VERDE: rc 0, dormida 27 s, 'VERDE'" bash -c "test $(rc) = 0 && grep -q 'dormida entre.*: 27 s' '$T/out' && grep -q VERDE '$T/out' && grep -q 'ssh-lanzado' '$T/log'"
ck "la suspension se lanza desprendida (systemd-run) con un guion que hace sync, espera a los inhibidores block, rtcwake -m no -s 25, systemctl suspend y deja su codigo" bash -c "grep -q 'systemd-run --unit=uke-bt-susp-test --collect /run/uke-bt-susp.sh' '$T/log' && bash -n '$T/log.script' && test \$(grep -n '^sync' '$T/log.script' | cut -d: -f1) -lt \$(grep -n 'block' '$T/log.script' | head -1 | cut -d: -f1) && grep -q '^rtcwake -m no -s 25' '$T/log.script' && grep -q '^systemctl suspend' '$T/log.script' && grep -q 'uke-bt-susp-rc' '$T/log.script' && test \$(grep -n 'block' '$T/log.script' | head -1 | cut -d: -f1) -lt \$(grep -n '^rtcwake' '$T/log.script' | cut -d: -f1)"
newlog; SIM_SUSP_LOG="$SLEEP_OK" SIM_SSHN=3 run --go --etapas suspension --con-auriculares; ck "otra sesion SSH abierta (captura dmesg -w): ALTO, no lanza la suspension (uke-idle-guard la bloquearia)" bash -c "test $(rc) = 1 && grep -q '2 sesion(es) SSH' '$T/out' && ! grep -q 'systemd-run --unit=uke-bt-susp-test' '$T/log'"
newlog; SIM_SUSP_LOG="$SLEEP_OK" SIM_SSHN=3 CICLO_SSH_OK=1 run --go --etapas suspension --con-auriculares; ck "con CICLO_SSH_OK=1 pasa esa compuerta" test "$(rc)" = 0
newlog; SIM_SUSP_LOG="$SLEEP_OK" SIM_RC=1 SIM_INH=2 run --go --etapas suspension --con-auriculares; ck "systemctl suspend rechazado (rc 1, el caso del inhibidor): ROJO con la causa y el listado de inhibidores" bash -c "test $(rc) = 1 && grep -q 'systemctl suspend NO se ejecuto (RC_SUSPEND=1)' '$T/out' && grep -q 'inhibidores block restantes: 2' '$T/out' && grep -q 'uke-idle-guard' '$T/out'"
newlog; SIM_SUSP_LOG="${SLEEP_OK/10:00:27Z/10:00:01Z}" run --go --etapas suspension --con-auriculares; ck "despertar prematuro (1 s): ROJO, rc 1" bash -c "test $(rc) = 1 && grep -q 'ROJO: la suspension duro 1 s' '$T/out'"
newlog; SIM_SUSP_LOG="${SLEEP_OK/reconexion de 00:11:22:XX:XX:XX OK/reconexion de 00:11:22:XX:XX:XX NO tras 6 intentos}" run --go --etapas suspension --con-auriculares; ck "sin reconexion OK: ROJO, rc 1" bash -c "test $(rc) = 1 && grep -q 'no registro' '$T/out'"
newlog; SIM_SUSP_LOG="$SLEEP_OK" SIM_NOBACK=1 CICLO_PAUSA=0 run --go --etapas suspension --con-auriculares; ck "la tablet no vuelve por SSH: rc 1 tras 30 intentos" bash -c "test $(rc) = 1 && grep -q 'no vuelve por SSH' '$T/out'"

echo "== etapa consumo =="
newlog; run --go --etapas consumo; ck "lanza bt-consumo.sh --sin-suspension desprendido (systemd-run) y explica el resto" bash -c "test $(rc) = 0 && grep -q 'systemd-run --unit=uke-bt-consumo --collect bt-consumo.sh --sin-suspension' '$T/log' && grep -q 'USB' '$T/out'"

echo "== codigo =="
ck "sintaxis de ciclo-prueba.sh" bash -n "$C"
ck "ninguna orden de escritura directa en la tablet fuera de las etapas (solo deploy.sh, bt-medir, bt-consumo, rtcwake/suspend)" bash -c "! grep -nE 'dd |fastboot|mkfs|reboot|rm -[rf]' '$C' | grep -v 'rm -f /run/uke-bt-susp-rc /run/uke-bt-susp-info'"
[ "$fail" = 0 ] && echo "TODO OK" || { echo "HAY FALLOS"; exit 1; }
