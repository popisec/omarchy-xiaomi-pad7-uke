#!/bin/bash
# uke-desenmascarar-journald.sh — revertir las máscaras que dejó `uke-fsck-flujo.sh`.
#
# POR QUÉ ESTE SCRIPT. El flujo de fsck (A.2 de P7) necesita que nada tenga fds de
# escritura en `/` para poder hacer `remount,ro`, y el bloqueo era `systemd-journald`
# resucitando por socket-activation. El arreglo fue **parar Y enmascarar** las units,
# y eso escribe enlaces a `/dev/null` en **`/etc/systemd/system`, que es PERSISTENTE**.
#
#   OJO: `/etc/systemd/system/systemd-journald.{service,socket}` y
#   `systemd-journald-dev-log.socket` -> /dev/null        (mascaras del fsck)
#   OJO: `systemd-timesyncd.service` y `systemd-networkd-wait-online.service` -> /dev/null
#         (los enmascara el script "por si acaso"; NO estaban enmascarados antes)
#
#   Si no se revierten, el sistema arranca **sin journald** => sin logs, y `systemctl`
#   queje de "Unit systemd-journald.service is masked". Eso NO es el estado bueno.
#
# USO (por SSH, con la tablet viva):  bash /root/uke-desenmascarar-journald.sh
# VERIFICACION que hace al final: ningún enlace a /dev/null en esas units.
set -u
say() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

UNITS="systemd-journald.service systemd-journald.socket \
       systemd-journald-dev-log.socket systemd-journald-dev-log.service \
       systemd-timesyncd.service systemd-networkd-wait-online.service"

say "--- estado ANTES:"
for u in $UNITS; do printf '  %-44s %s\n' "$u" "$(systemctl is-enabled "$u" 2>&1 | head -1)"; done

say "--- desenmascarando y arrancando"
for u in $UNITS; do
	systemctl unmask "$u" 2>/dev/null
	systemctl daemon-reload 2>/dev/null
done
systemctl unmask systemd-journald.service systemd-journald.socket 2>/dev/null
systemctl daemon-reload 2>/dev/null
systemctl start systemd-journald.socket systemd-journald.service 2>/dev/null
# timesyncd/wait-online: solo si estaban enabled antes (comprobado: no lo estaban -> no los
# arrancamos, los dejamos como los deja el sistema por defecto)
systemctl start systemd-timesyncd.service 2>/dev/null

say "--- estado DESPUES:"
for u in $UNITS; do printf '  %-44s %s\n' "$u" "$(systemctl is-enabled "$u" 2>&1 | head -1)"; done

# quitar los enlaces a /dev/null que dejo el fsck (unmask - ya lo hace, pero por si el
# enlace sigue por el .wants/ o por cache)
for u in $UNITS; do
	f="/etc/systemd/system/$u"
	[ -L "$f" ] && [ "$(readlink "$f")" = "/dev/null" ] && { rm -f "$f"; say "  (limpiado enlace huerfano $f)"; }
done

say "--- journald vivo? $(pgrep -x systemd-journald >/dev/null && echo SI || echo NO)"
say "--- logs escribiendo? $(journalctl -n 1 --no-pager 2>&1 | head -1)"
say "=== FIN ==="