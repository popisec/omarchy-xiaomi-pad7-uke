#!/bin/bash
# uke-fsck-flujo.sh — e2fsck del rootfs de la tablet con el flujo PROBADO (A.2 de P7).
#
# POR QUÉ ESTE SCRIPT Y NO UNA LÍNEA SUELTA
#   §A.2 de `prepara/P7-fsck-f9.md` es la vía recomendada; `prepara/P7-fsck-f9.md` §A.1
#   (`systemd-fsck-root` al siguiente arranque) está REFUTADA medida: el unit lleva
#   `ConditionPathIsReadWrite=!/`, el init (`ukeinit`) remonta rw él mismo y no hace fsck
#   ni mira `/forcefsck` ⇒ un reboot NO repara nada. Por eso el `remount,ro` es obligatorio.
#
#   El §A.2.4 de P7 queda REFUTADO en vivo por el ledger #446 del hermano (ledger este
#   proyecto = docs/LEDGER-OMARCHY.md). APRENDIZAJES MEDIDOS que este script aplica:
#     1) "journald resurrecta por socket y bloquea el remount ro" (ledger #446). OJO: parar
#        `systemd-journald` NO basta — el socket lo vuelve a levantar. Hay que parar Y
#        enmascarar socket+service (probado aquí: con el stop solo, rc=32 EBUSY).
#     2) "con / en ro los hijos de sshd mueren en kex: monitorear el fsck desde UNA sesión
#        persistente" (ledger #446). Por eso el fsck va DESPRENDIDO (setsid+nohup) con el
#        log en tmpfs: si la sesión cae, el fsck sigue y el log se lee al reconectar.
#     3) MEDIDO 1-oct-2026 (corrige la línea previa que decía "puede tardar minutos"): el
#        ciclo COMPLETO tardó ~2 s con rc 3→0→0→0. Motivo: el fs ocupa la partición entera
#        (105,8 GiB) pero solo tiene **4,4 GB usados** ⇒ `-f` recorre 1,6 M bloques, no 27 M.
#        Aun asi puede ser de minutos si `used` crece; por eso el sondeo va espaciado.
#     4) MEDIDO: el fichero de rc debe ir a tmpfs (ver nota de RC mas abajo).
#
# REGLAS QUE RESPETA
#   - dispositivo por ETIQUETA (`by-partlabel/userdata`), nunca por letra de /dev/sdX (el
#     /dev cambia entre arranques; hoy el montaje es /dev/sdb32).
#   - log en tmpfs (/dev/shm), NUNCA en el fs que se repara (si no, el propio log ensucia).
#   - inventario `-fn` antes de escribir; 2 pasadas `-fy`; cierre = `-fn` ×2 con rc=0.
#   - NO remonta rw al final ni rebootea solo: con / en ro la copia en memoria del superbloque
#     queda vieja tras el fsck, así que el reboot lo hace el operador, no el script.
#
# USO EN LA TABLET
#   setsid nohup bash /root/uke-fsck-flujo.sh >/dev/null 2>&1 &
#   tail -f /dev/shm/e2fsck-fy.log          # o: cat /root/uke-fsck-rc.txt
set -u
LOG=/dev/shm/e2fsck-fy.log
# OJO (1-oct-2026): el rc va a tmpfs TAMBIEN, no a /root. En el primer intento lo puse en
# /root/uke-fsck-rc.txt y salio VACIO: el paso 5 corre ya con / en ro, y `echo >> /root/...`
# falla en silencio (no hay `set -e` a proposito, para que el script llegue al final y logged).
# Cualquier fichero de salida tiene que ir a tmpfs mientras / este ro.
RC=/dev/shm/e2fsck-rc.txt
DEV=/dev/disk/by-partlabel/userdata

say() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >> "$LOG"; }
: > "$LOG"
: > "$RC"

say "=== flujo e2fsck arrancado (A.2: remount ro + e2fsck -fy) ==="
say "dispositivo: $DEV"
say "montaje: $(findmnt -no SOURCE,FSTYPE,OPTIONS / 2>/dev/null)"
say "tamano del fs: $(df -h --output=size /dev/disk/by-partlabel/userdata 2>/dev/null | tail -1)"

[ -b "$DEV" ] || { say "ABORT: no existe $DEV"; exit 1; }

# ---- PASO 1: inventario de 0 riesgo --------------------------------------------
say ""
say "--- PASO 1: e2fsck -fn (inventario, 0 riesgo)"
e2fsck -fn "$DEV" >> "$LOG" 2>&1
say "rc inventario = $?"

# ---- PASO 2:JORGE EL EBUSY (leccion #446) --------------------------------------
# Parar journald no basta: systemd lo resucita por el socket y vuelve a tener fds de
# escritura en el fs, y el remount,ro falla con EBUSY. Hay que enmascarar socket+service.
say ""
say "--- PASO 2:ulls de escritura fuera (journald enmascarado + auditd + timesync)"
for u in systemd-journald.socket systemd-journald.service \
         systemd-journald-dev-log.socket systemd-journald-dev-log.service \
         systemd-timesyncd.service systemd-networkd-wait-online.service; do
	[ -e "/etc/systemd/system/$u" ] || [ -e "/usr/lib/systemd/system/$u" ] || continue
	systemctl stop "$u" 2>/dev/null
	systemctl mask  "$u" 2>/dev/null
	say "  parado y enmascarado: $u"
done
systemctl stop auditd 2>/dev/null && say "  parado auditd (escribe audit.log en el fs)"
pkill -x systemd-journald 2>/dev/null && say "  pkill systemd-journald"
sleep 1
sync
say "journald vivo ahora? $(pgrep -x systemd-journald >/dev/null && echo SI || echo no)"
say "sync hecho"

# ---- PASO 3: ro ------------------------------------------------------------------
# `norecovery` porque la raiz corre SIN journaling desde el 27-sep (P7: el init monta
# `ro,noload` y el remount rw no carga el journal). Sin esto el fsck puede no ser
# idempotente respecto a lo que el kernel tiene en memoria.
say ""
say "--- PASO 3: remount ro,norecovery"
mount -o remount,ro,norecovery / >> "$LOG" 2>&1
rc_mount=$?
say "rc remount = $rc_mount -> $(findmnt -no OPTIONS / 2>/dev/null)"
if [ "$rc_mount" -ne 0 ]; then
	say "ABORT: sin ro no se puede reparar de forma segura (e2fsck aborta con rc=8 sobre rw)."
	say "       No se ha escrito nada en el fs. Diagnostico de quien bloquea:"
	fuser -vm / 2>&1 | sed 's/^/       /' >> "$LOG"
	say "=== FIN (abortado en paso 3) ==="
	exit 3
fi

# ---- PASO 4: dos pasadas de reparacion ------------------------------------------
for p in 1 2; do
	say ""
	say "--- PASO 4.$p: e2fsck -f -y (pasada $p)  [puede tardar minutos]"
	e2fsck -f -y "$DEV" >> "$LOG" 2>&1
	say "rc pasada $p = $?"
	sync
done

# ---- PASO 5: verificacion (criterio de cierre: -fn x2 con rc=0) -----------------
say ""
say "--- PASO 5: verificacion e2fsck -fn x2"
for v in 1 2; do
	e2fsck -fn "$DEV" >> "$LOG" 2>&1
	rc=$?
	say "rc verificacion $v = $rc"
	echo "$rc" >> "$RC"
done

say ""
say "=== FIN. El fs sigue en ro y NO se ha rebooteado."
say "    Siguiente paso del operador: reiniciar para que el kernel lea el fs reparado."
say "    NO remontar rw antes de reiniciar (superbloque en memoria quedaria viejo)."
sync