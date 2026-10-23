#!/usr/bin/env bash
# uke-telnet.sh — ejecuta comandos en la tablet por telnet (puerto 23), que es el canal
export LC_ALL=C
# que el init del proyecto hermano garantiza ANTES del switch_root ("el canal de
# desarrollo nunca se pierde"). Es un shell BusyBox ash como root, sin password.
#
# Uso:  uke-telnet.sh 'uname -m' 'cat /etc/os-release'
# O:    echo -e "cmd1\ncmd2" | uke-telnet.sh
set -u
HOST=192.168.42.129
MARK='@@@END@@@'

if [ $# -gt 0 ]; then
    { for c in "$@"; do printf '%s\n' "$c"; sleep 0.4; done
      printf 'echo %s\n' "$MARK"; sleep 2; } | timeout 45 nc "$HOST" 23 2>/dev/null
else
    cat | { cat; printf 'echo %s\n' "$MARK"; sleep 2; } | timeout 45 nc "$HOST" 23 2>/dev/null
fi \
 | tr -d '\r' \
 | sed 's/\x1b\[[0-9;]*[A-Za-z]//g' \
 | awk -v m="$MARK" 'index($0,m){exit} {print}'
