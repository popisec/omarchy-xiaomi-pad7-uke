#!/usr/bin/env bash
# uke-acm-term.sh — speaks to the tablet's serial console (ACM) *as a terminal would*.
#
# WHY THIS EXISTS. The Arch image boots and shows `uke-arch login: Arch Linux ARM` on
# ttyGS0, but logging in by typing the user and password plainly does not work: the getty
# and systemd's password prompt emit a Device Status Report `ESC[6n` (cursor position
# query) and then WAIT for the answer. The ACM gadget is a pipe, not a terminal, so it
# never answers, and the prompt blocks until `login: timed out after 60 seconds`
# (measured, 27-sep-2026). This script watches the capture for pending DSRs and answers
# them the way a real terminal does (`ESC[<row>;<col>R`), which is what unblocks the
# prompt. It then drives the login and a list of commands.
#
# Usage:
#   uke-acm-term.sh login [user] [pass]
#   uke-acm-term.sh run 'cmd1' 'cmd2' ...
set -u
LOG=/tmp/opencode/console-uke.log
DEV=/dev/ttyACM0
OFF=0

send()  { printf '%b' "$1" > "$DEV" 2>/dev/null; }
newlog(){ OFF=$(stat -c%s "$LOG" 2>/dev/null || echo 0); }
fresh() { tail -c +"$OFF" "$LOG" 2>/dev/null; }

# Answer a DSR if the newly captured bytes contain one. $1 = "all" to also look back.
answer_dsr() {
    local txt
    txt="$(fresh)"
    [ "${1:-}" = "all" ] && txt="$(tail -c 600 "$LOG" 2>/dev/null)"
    # OJO (1-oct-2026): esto estaba como grep -qa '\033\[6n\|\^\[\[6n' y NUNCA
    # funciono: en BRE (grep sin -E) "\0" no es un escape valido, y con -E este grep
    # tampoco acepta "\x1b" (avisa "\ sobrante despues de x").grep devolvia 1
    # siempre => la deteccion de DSR era un no-op, que es justo lo que desbloquea el
    # prompt del getty. Ahora se busca el ESC como caracter literal con grep -F.
    local esc
    esc="$(printf '\033')"
    if printf '%s' "$txt" | grep -qaF "$esc[6n" || printf '%s' "$txt" | grep -qa '\^\[\[6n'; then
        send '\033[20;1R'
        return 0
    fi
    return 1
}

# wait_for <regex> <seconds>
wait_for() {
    local re="$1" secs="${2:-30}" i
    for i in $(seq 1 "$secs"); do
        if fresh | grep -qaE "$re"; then return 0; fi
        answer_dsr >/dev/null
        sleep 1
    done
    return 1
}

do_login() {
    local user="${1:-root}" pass="${2:-${UKE_ROOT_PASS:-$(cat "${HOME}/.config/omarchy-uke/root-tablet.pass" 2>/dev/null)}}"
    newlog
    echo "--- esperando prompt de login ---"
    for i in $(seq 1 25); do
        fresh | grep -qa "login:" && break
        answer_dsr >/dev/null; send '\n'; sleep 1.5
    done
    fresh | grep -qa "login:" && echo "  prompt visto" || echo "  (sin prompt visible)"
    send "$user\n"; sleep 1.5; answer_dsr
    if wait_for "assword" 12; then echo "  prompt de password visto"; else echo "  (no llego a password)"; fi
    answer_dsr
    send "$pass\n"; sleep 2; answer_dsr
    if wait_for "Password:|incorrect" 2; then :; fi
    sleep 3; answer_dsr
    echo "--- resultado del login ---"
    fresh | cat -v | grep -avE "ufshcd-qcom|devfreq|drm|msm|ufshc" | tail -8
    if fresh | cat -v | grep -qaE 'root@|~ #'; then echo "  >>> SHELL CONSEGUIDA"; else echo "  >>> sin shell"; fi
}

do_run() {
    local c
    for c in "$@"; do
        newlog
        send "$c\n"; sleep 1
        wait_for "." 6
        answer_dsr
        sleep 1
        echo "### $c"
        fresh | cat -v | grep -avE "ufshcd-qcom|devfreq|dvfs failed" | tail -25
        echo
    done
}

case "${1:-}" in
    login) shift; do_login "${1:-root}" "${2:-${UKE_ROOT_PASS:-$(cat "${HOME}/.config/omarchy-uke/root-tablet.pass" 2>/dev/null)}}" ;;
    run)   shift; do_run "$@" ;;
    *) echo "uso: $0 login [user] [pass] | $0 run 'cmd' ..." ;;
esac
