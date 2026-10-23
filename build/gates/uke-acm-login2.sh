#!/usr/bin/env bash
# uke-acm-login2.sh — login por la consola ACM de la tablet, a prueba de bloqueos.
#
# POR QUÉ ESTA VERSIÓN (la anterior se colgaba):
#  1. Escribir en /dev/ttyACM0 **puede bloquearse para siempre** si el lado tablet no está
#     leyendo entrada (buffer del gadget lleno ⇒ NAK ⇒ el write() del host no termina). Por
#     eso TODA escritura va con `timeout 3` en un subshell aparte: si se cuelga, se le mata
#     y el script sigue. Ésta es exactamente la trampa que avisa la regla del "único lector"
#     del proyecto, y por eso este script nunca puede dejar el ACM bloqueado.
#  2. El getty acepta entrada (medido: imprimió "Login incorrect", o sea leyó usuario y clave
#     y los rechazó), pero la entrada encolada de intentos anteriores contamina la secuencia.
#     Se limpia con Ctrl-C (0x03) y Ctrl-U (0x15) antes de cada intento.
#  3. systemd/getty emiten ESC[6n (cursor position request) y esperan respuesta. Se responde
#     como lo haría un terminal real (ESC[<fila>;<col>R) cada vez que aparece en la captura.
#
# la contraseña de root NO va en el repo (rotada 22-oct-2026): se lee de $UKE_ROOT_PASS o de ~/.config/omarchy-uke/root-tablet.pass.
set -u
LOG=/tmp/opencode/console-uke.log
DEV=/dev/ttyACM0
USER_=${1:-root}
PASS=${2:-${UKE_ROOT_PASS:-$(cat "${HOME}/.config/omarchy-uke/root-tablet.pass" 2>/dev/null)}}

put() { timeout 3 bash -c "printf '%b' '$1' > $DEV" 2>/dev/null; }
off=0
newlog() { off=$(stat -c%s "$LOG" 2>/dev/null || echo 0); }
fresh() { tail -c +"$off" "$LOG" 2>/dev/null; }
DSR=$'\033[6n'
dsr() { if fresh | LC_ALL=C grep -qaF "$DSR"; then put '\033[20;1R'; sleep 0.3; return 0; fi; return 1; }

echo "### login en $DEV como '$USER_'"
for intento in 1 2 3; do
    newlog
    echo "--- intento $intento ---"
    # limpiar la linea: Ctrl-U y Ctrl-C
    put '\025'; put '\003'; sleep 1; dsr
    # pidiendo el prompt
    put '\n'; sleep 1.5; dsr
    if ! fresh | grep -qa "login:"; then
        put '\n'; sleep 1.5
    fi
    # usuario
    put "$USER_\n"; sleep 2; dsr
    if fresh | grep -qa "assword"; then
        put "$PASS\n"; sleep 3; dsr
    else
        echo "  no llego al prompt de password"
    fi
    sleep 3; dsr
    echo "  --- lo visto ---"
    fresh | cat -v | grep -avE "ufshcd-qcom|devfreq|dvfs failed|^ *$" | tail -8
    if fresh | cat -v | grep -qaE '\[root@|~ #'; then
        echo "  >>> SHELL CONSEGUIDA"
        exit 0
    fi
    if fresh | grep -qa "Login incorrect"; then echo "  (password rechazada)"; fi
    if fresh | grep -qa "timed out";     then echo "  (el getty expiro: duermo a que vuelva)"; sleep 20; fi
done
echo ">>> SIN SHELL tras 3 intentos"
exit 1
