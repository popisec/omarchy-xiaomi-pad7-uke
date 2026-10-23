#!/usr/bin/env bash
# drain-to-fastboot.sh — mete la tablet en fastboot agotando el contador de reintentos
# del slot. Es la unica via programatica que queda: el ABL de la uke IGNORA el BCB de
# `misc` (LECCIONES.md:60 del proyecto hermano, medido hoy) y no hay adbd en la imagen.
# No es destructivo: al caer en fastboot, `fastboot set_active a` devuelve el contador a 7.
#
# Por que funciona: el slot nunca se marca "successful" (la imagen no trae qbootctl), asi que
# cada arranque consume un reintento. Al llegar a 0, el ABL cae a fastboot.
set -u
LOG="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"/build/gates/drain-fastboot.log
SSH=(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
      -o ConnectTimeout=6 -o LogLevel=ERROR -i "$HOME/.ssh/id_ed25519" root@192.168.42.129)
say() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"; }

for i in $(seq 1 12); do
    if fastboot devices 2>/dev/null | grep -q fastboot; then
        say "*** FASTBOOT alcanzado en la iteracion $i ***"
        exit 0
    fi
    if ping -c1 -W1 192.168.42.129 >/dev/null 2>&1; then
        say "iter $i: tablet en Ubuntu (uptime $(timeout 6 "${SSH[@]}" 'cut -d. -f1 /proc/uptime' 2>/dev/null || echo '?')) -> reinicio"
        timeout 15 "${SSH[@]}" 'sync; echo 1 > /proc/sys/kernel/sysrq; echo b > /proc/sysrq-trigger' >/dev/null 2>&1
    else
        say "iter $i: sin ping (arrancando o ya en fastboot)"
    fi
    # esperar a que vuelva a estar accesible, o a que aparezca en fastboot
    for t in $(seq 1 30); do
        fastboot devices 2>/dev/null | grep -q fastboot && break
        ping -c1 -W1 192.168.42.129 >/dev/null 2>&1 && break
        sleep 5
    done
    sleep 3
done

if fastboot devices 2>/dev/null | grep -q fastboot; then
    say "*** FASTBOOT alcanzado ***"
else
    say "NO se ha alcanzado fastboot en 12 iteraciones: hace falta Power + Vol- (fisico)"
fi
exit 1
