#!/bin/bash
# h2-test.sh — ciclo H2: ¿es el volcado SMMU el wedge?
#
# QUÉ DECIDE. En `a6xx_gmu_start()` el volcado SMMU corría entre S2-gen9 y S3-rst0, EN
# CADA resume. K25 lo tiene APAGADO por defecto (uke_smmu_dump=0). Este script:
#   1. abre `/dev/dri/card0` UNA vez (lo que dispara la escalera del GMU),
#   2. captura la consola ACM y `dmesg` por SSH si la máquina sobrevive,
#   3. decide con las predicciones P5-P8 del ledger #458.
#
# POR QUÉ el volcado tiene que ir a la consola y no a pstore: pstore no sobrevive a un
# power-cycle (medido en #450). Y por qué NO se usa `eglinfo`: recorre la misma escalera
# pero no añade nada; `modetest -c` es el mínimo que abre el nodo DRM.
#
# REGLAS QUE RESPETA
#   - la consola ACM SIEMPRE tiene un lector (si el kernel escribe sin lector, los
#     write() se bloquean y el cuelgue ni se registra);
#   - UN solo intento de apertura (cada apertura cuesta un reintento de slot);
#   - sondeo ESPACiado (>=5 s): el sondeo a 0,3 s dispara el MaxStartups de sshd y
#     fabrica "zombis" falsos (lección de #450);
#   - no se da por hecho que el volcado está off: se exige el marcador en el log (P8).
set -u
R="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
LOG=/var/tmp/uke-sesion-console.log
CMD=${1:-"modetest -c"}

say() { echo "[$(date +%H:%M:%S)] $*"; }

say "=== H2: un intento de apertura de DRM ==="
say "comando: $CMD"
off=$(stat -c%s "$LOG" 2>/dev/null || echo 0)

# Lanzarlo DESPRENDIDO y con una sola apertura: si wedgea, el script no se queda
# colgado esperando y no pierde la captura.
say "--- lanzando (desprendido, una sola apertura)"
timeout 120 build/gates/uke-ssh.sh "$CMD" > build/logs/h2-drm.log 2>&1 &
DRMPID=$!

# Vigilar la consola: si aparece S3-rst0 y luego sigue, la máquina sobrevivio.
deadline=$(( $(date +%s) + 200 ))
sobrevive=0
while [ "$(date +%s)" -lt "$deadline" ]; do
	nuevo=$(tail -c +$((off + 1)) "$LOG" 2>/dev/null | tr -d '\r')
	marcos=$(printf '%s' "$nuevo" | grep -acE 'S3-rst0|S4-poll|UKE-K25|UKE-K19' || true)
	vivos=$(printf '%s' "$nuevo" | grep -acE 'ufshcd-qcom|devfreq' || true)
	# si el kernel sigue emitiendo cosas del fondo, esta vivo
	if [ "${vivos:-0}" -gt 6 ]; then sobrevive=1; break; fi
	if printf '%s' "$nuevo" | grep -aq 'UKE-K25: volcado SMMU DESACTIVADO'; then
		say "  (visto el marcador de volcado OFF)"
	fi
	sleep 6
done

kill "$DRMPID" 2>/dev/null || true
wait "$DRMPID" 2>/dev/null || true

say "=== veredicto ==="
nuevo=$(tail -c +$((off + 1)) "$LOG" 2>/dev/null | tr -d '\r')
printf '%s' "$nuevo" > build/evidencia/h2-ventana.log

say "P8 — el volcado esta OFF? (marcador UKE-K25):"
printf '%s' "$nuevo" | grep -a 'UKE-K25' | tail -2 | sed 's/^/    /' || true
printf '%s\n' "$nuevo" | grep -qa 'UKE-K25' && say "  SI (P8 cumplida)" || say "  NO (P8 NO cumplida)"

say "P5/P6 — hasta donde llego la escalera:"
printf '%s' "$nuevo" | grep -aE 'S1-rst1|S2-gen9|K19-dumpOK|S3-rst0|S4-poll' | tail -8 | sed 's/^/    /'
if printf '%s' "$nuevo" | grep -aq 'S3-rst0'; then
	say "  >> LLEGO a S3-rst0"
	if [ "$sobrevive" = 1 ]; then
		say "  >> P5: H2 CONFIRMADA — llego a S3 y la maquino SIGUE VIVA (el volcado era el wedge)"
	else
		say "  >> P6: H2 REFUTADA — llego a S3 pero murio igualmente (el problema es el CM3)"
	fi
elif printf '%s' "$nuevo" | grep -aq 'S2-gen9'; then
	say "  >> se quedo en S2 (no llego a S3)"
else
	say "  >> no se ve la escalera (revisar la captura completa)"
fi

say "SSH vivo ahora?"
timeout 15 bash -c 'cat < /dev/null > /dev/tcp/192.168.42.129/22' 2>/dev/null \
	&& say "  SI (puede haber sesion)" || say "  no"
say "DONE H2-TEST"