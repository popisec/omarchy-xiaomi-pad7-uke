#!/bin/bash
# uke-captura-ladder.sh — se lleva el dmesg (y el pstore) en la ventana de vida del
# arranque, resistiendo el desbordamiento del USB ACM.
#
# POR QUE ESTE SCRIPT (1-oct-2026, medido en el arranque del K23b).
# El K23b arranca, llega a los 4,0 s (donde corre la escalera del GMU y el volcado del
# SMMU) y a los ~30 s cuelga -> hung_task_panic -> panic -> reboot. En medio:
#   - el bucle se repite cada ~34 s (medido: 15:43:13, 15:43:47, 14:21, 14:55);
#   - la consola ACM **desborda**: "[missed 4685 bytes]" y 67 lineas "missed" sueltas en el log
#     acumulado, justo en la ventana 4,0-4,2 s que es la que decide. La cola del gadget
#     se pierde cuando el reset corta el flujo, y por USB no es fiable (LECCIONES
#     ronda 428->429 del hermano: "la consola pierde la cola de lineas").
#   - pero hay red: el gadget NCM levanta y **sshd responde** durante esa ventana.
#     Medido: el gadget a los 15:43:13 y SSH contestando a los 15:43:18.
# Y sobre todo: **ramoops/pstore** (CONFIG_PSTORE_RAM=y, CONFIG_PSTORE_CONSOLE=y,
# CONFIG_PSTORE_DEFAULT_KMSG_BYTES=10240, y el nodo `ramoops_region` en el
# reserved-memory del DT vendor) => cada pánico deja las ultimas 10 KB del log del kernel
# en una region persistente que **sobrevive al reinicio**. Con el bucle de 34 s se
# acumulan varios registros.
#
# ESTRATEGIA (en este orden, y par en cuanto se consiga):
#   1. poll agresivo del puerto 22 (cada 0,3 s): en cuanto responde, un solo comando
#      que se lleva dmesg + pstore + estado drm/kgsl.
#   2. repetir hasta 3 veces: cada iteracion del bucle rescue una cosa (el pstore del
#      panic anterior, por ejemplo).
#   3. lo que no se consiga por ssh, se queda en la consola (que se lee despues).
#
# USO:  build/gates/uke-captura-ladder.sh [segundos]      (default 420 = 7 min)
set -u
R="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
SSH=$R/build/gates/uke-ssh.sh
HOST=192.168.42.129
VENTANA=${1:-420}
OUT=$R/build/logs
mkdir -p "$OUT"
say() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

CMD='dmesg -n 7 2>/dev/null; echo "=== UPTIME $(cut -d" " -f1 /proc/uptime) ==="; dmesg | tail -400; echo "=== PSTORE ==="; ls -la /sys/fs/pstore/ 2>/dev/null; for f in /sys/fs/pstore/*; do [ -f "$f" ] && { echo "--- $f"; tail -c 20000 "$f"; }; done 2>/dev/null; echo "=== DRM/KGSL ==="; cat /sys/bus/platform/devices/3d00000.qcom,kgsl-3d0/power/runtime_status 2>/dev/null; ls /sys/class/drm/ 2>/dev/null; cat /sys/class/drm/card0-DSI-1/status 2>/dev/null'

fin=$(($(date +%s) + VENTANA))
n=0
while [ "$(date +%s)" -lt "$fin" ]; do
	# sondeo TCP directo: mas rapido que un ssh que espera timeout
	if timeout 1 bash -c "</dev/tcp/$HOST/22" 2>/dev/null; then
		n=$((n+1))
		f="$OUT/ladder-captura-$n-$(date +%H%M%S).log"
		say "intento $n: el puerto 22 responde, capturando -> $(basename "$f")"
		if timeout 25 "$SSH" "$CMD" > "$f" 2>&1; then
			say "  capturados $(wc -l < "$f") lineas"
			grep -aqE 'GEO ID0=|S3-rst0' "$f" && { say "  >>> ESTA EL VOLCADO. Fin de la captura."; exit 0; }
		else
			say "  la conexion SSH se corto (normal: el zombi llega a ~30 s)"
		fi
	else
		printf '.'
	fi
	# OJO (1-oct-2026, session #454): esto era `sleep 0.3` y es una TRAMPA. El sondeo
	 # TCP cada 0.3 s abre taladro de conexiones que dispara el MaxStartups de sshd, que
	 # CIERRA la conexion durante el banner -> "kex_exchange_identification: Connection
	 # reset by peer". O sea: el script fabricaba el "zombi" que luego diagnosticabamos,
	 # y nos hacia perder horas persiguiendo una tablet que estaba SANA (ledger #450).
	 # El intervalo es de 5 s como minimo; 30 s para dejar respirar a sshd del todo.
	sleep "${UKE_LADDER_INTERVAL:-5}"
done
say "fin de la ventana de $VENTANA s; capturas: $(ls -1 "$OUT"/ladder-captura-* 2>/dev/null | wc -l)"
exit 1
