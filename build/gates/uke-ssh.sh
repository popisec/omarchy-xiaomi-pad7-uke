#!/usr/bin/env bash
# uke-ssh.sh — ejecutar comandos en la tablet por SSH.
#
# POR QUÉ EXISTE. Durante horas el único acceso fue la consola serie (ACM), y resultaba inutilizable:
# el getty agota su LoginTimeout, nadie lee ttyGS0, y las escrituras al gadget dan EAGAIN. Desde
# V4 hay SSH (verificado), y eso cambia el proyecto: el diagnóstico ya no cuesta un power cycle
# ni un flash de 8 GiB.
#
# POR QUÉ SE MANDA A `bash -s` Y NO UN HEREDOC. Los comandos se escriben tal cual en el stdin y el
# remoto los ejecuta con `bash -s` (`-T` quita la tty, así que bash lee de stdin). Así el texto
# llega LITERAL: los paréntesis, las comillas y los pipelines pasan intactos sin escapar nada. Y
# como no se puede incrustar texto arbitrario en una línea de shell, los separadores van
# NUMERADOS (`### CMD n`) y este script imprime por su cuenta a qué comando corresponde cada
# número.
#
# (Tres versiones anteriores fallaron aquí, y por eso está el aviso: (1) `echo "--- $ cmd"` en
# local: cualquier `(` reventaba el shell remoto con "syntax error near unexpected token `('";
# (2) `printf %q`: escapaba `;` como `\;`, que llegaba LITERAL al comando y no separaba nada;
# (3) `cat <<'UKE_EOF'` sobre ssh: `cat` IMPRIME el heredoc, no lo ejecuta, y salía el texto de
# los comandos sin ejecutar ninguno.)
#
# Uso:  ./uke-ssh.sh 'comando' ['comando2' ...]
#       ./uke-ssh.sh -i            # solo info de conexión
set -u
KEY="$(cd "$(dirname "$0")" && pwd)/../rootfs/uke-arch-root"
HOST=192.168.42.129
SSHOPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
         -o ConnectTimeout=8 -o LogLevel=ERROR -o ServerAliveInterval=15
         -i "$KEY" "root@$HOST")

if [ "${1:-}" = "-i" ]; then
    ping -c1 -W2 "$HOST" >/dev/null 2>&1 && echo "ping: OK" || echo "ping: SIN RESPUESTA"
    timeout 12 ssh "${SSHOPTS[@]}" 'echo "ssh: OK — $(uname -m) $(uname -r) — uptime $(uptime -p | cut -d" " -f2-)"' 2>&1
    exit $?
fi
[ $# -eq 0 ] && { echo "uso: $0 'comando' [...]" ; exit 2; }

n=0
for c in "$@"; do n=$((n + 1)); printf '  [CMD %d] %s\n' "$n" "$c"; done
printf -- '---- salida de la tablet ----\n'

{
    n=0
    for c in "$@"; do
        n=$((n + 1))
        printf 'echo "### CMD %d"\n' "$n"
        printf '%s\n' "$c"
    done
    printf 'echo "### fin"\n'
    sleep 0.5
} | timeout 180 ssh -T "${SSHOPTS[@]}" bash -s 2>&1 | sed 's/\r$//'
