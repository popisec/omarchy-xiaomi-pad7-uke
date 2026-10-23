#!/bin/bash
# test-bootguard.sh — prueba la maquina de estados de uke-bootguard en un directorio temporal
# (sin systemd-run, sin sync, sin tocar /etc ni /var). Se puede correr en el PC o en la tablet.
# Uso: test-bootguard.sh [ruta/a/uke-bootguard]
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)
G=${1:-$HERE/root/usr/local/sbin/uke-bootguard}
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export UKE_GUARD_STATE=$T/state UKE_GUARD_ETC=$T/etc UKE_GUARD_NO_RUN=1 UKE_GUARD_MAX=2
mkdir -p "$T/etc"
fail=0
t() { # t "descripcion" esperado_rc comando...
	local d=$1 want=$2; shift 2
	"$@" >"$T/out" 2>&1; local rc=$?
	if [ "$rc" = "$want" ]; then printf '  OK   %s (rc=%s)\n' "$d" "$rc"; else printf '  FALLO %s (rc=%s esperado %s)\n' "$d" "$rc" "$want"; sed 's/^/       /' "$T/out"; fail=1; fi
}
has() { [ -e "$UKE_GUARD_STATE/$1" ] ; }
chk() { local d=$1; shift; if "$@"; then printf '  OK   %s\n' "$d"; else printf '  FALLO %s\n' "$d"; fail=1; fi; }

echo "== arranque limpio =="
UKE_BOOT_ID=boot1 t "begin wifi (primera vez)" 0 "$G" begin wifi
chk "pending creado" has wifi.pending
UKE_BOOT_ID=boot1 t "begin wifi otra vez en el MISMO boot (re-ejecucion manual)" 0 "$G" begin wifi
chk "sin fallos contados" test ! -e "$UKE_GUARD_STATE/wifi.fails"
UKE_BOOT_ID=boot1 t "ok wifi" 0 "$G" ok wifi
chk "pending borrado" test ! -e "$UKE_GUARD_STATE/wifi.pending"

echo "== un arranque sin 'ok' (cuelgue) y luego otro bueno =="
UKE_BOOT_ID=boot2 t "begin wifi (boot2, se cuelga: nunca llega ok)" 0 "$G" begin wifi
UKE_BOOT_ID=boot3 t "begin wifi (boot3): 1 fallo, se reintenta" 0 "$G" begin wifi
chk "fallos=1" test "$(cat "$UKE_GUARD_STATE/wifi.fails")" = 1
UKE_BOOT_ID=boot3 t "ok wifi (boot3 sobrevive)" 0 "$G" ok wifi
chk "fallos borrados" test ! -e "$UKE_GUARD_STATE/wifi.fails"

echo "== dos arranques colgados seguidos -> disparada =="
UKE_BOOT_ID=boot4 t "begin desktop (boot4, cuelga)" 0 "$G" begin desktop
UKE_BOOT_ID=boot5 t "begin desktop (boot5, 1 fallo, reintenta; cuelga)" 0 "$G" begin desktop
UKE_BOOT_ID=boot6 t "begin desktop (boot6, 2 fallos -> omite)" 1 "$G" begin desktop
chk "tripped existe" has desktop.tripped
UKE_BOOT_ID=boot7 t "begin desktop (boot7 sigue omitido)" 1 "$G" begin desktop
UKE_BOOT_ID=boot7 t "begin wifi no se ve afectado" 0 "$G" begin wifi
UKE_BOOT_ID=boot7 t "ok wifi" 0 "$G" ok wifi
t "reset desktop" 0 "$G" reset desktop
UKE_BOOT_ID=boot8 t "begin desktop tras reset" 0 "$G" begin desktop
UKE_BOOT_ID=boot8 t "ok desktop" 0 "$G" ok desktop

echo "== interruptores manuales =="
touch "$UKE_GUARD_ETC/no-wifi"
UKE_BOOT_ID=boot9 t "no-wifi omite wifi" 1 "$G" begin wifi
UKE_BOOT_ID=boot9 t "no-wifi NO omite desktop" 0 "$G" begin desktop
UKE_BOOT_ID=boot9 t "ok desktop" 0 "$G" ok desktop
rm -f "$UKE_GUARD_ETC/no-wifi"
touch "$UKE_GUARD_ETC/safe-mode"
UKE_BOOT_ID=boot10 t "safe-mode omite wifi" 1 "$G" begin wifi
UKE_BOOT_ID=boot10 t "safe-mode omite desktop" 1 "$G" begin desktop
chk "safe-mode no deja pending" test ! -e "$UKE_GUARD_STATE/wifi.pending"
rm -f "$UKE_GUARD_ETC/safe-mode"

echo "== bt: tercer componente, independiente de wifi y desktop =="
UKE_BOOT_ID=bt1 t "begin bt (primera vez)" 0 "$G" begin bt
chk "bt.pending creado" has bt.pending
UKE_BOOT_ID=bt1 t "ok bt" 0 "$G" ok bt
chk "bt.pending borrado" test ! -e "$UKE_GUARD_STATE/bt.pending"
UKE_BOOT_ID=bt2 t "begin bt (bt2, se cuelga: nunca llega ok)" 0 "$G" begin bt
UKE_BOOT_ID=bt3 t "begin bt (bt3): 1 fallo, reintenta; se cuelga otra vez" 0 "$G" begin bt
chk "bt.fails=1" test "$(cat "$UKE_GUARD_STATE/bt.fails")" = 1
UKE_BOOT_ID=bt4 t "begin bt (bt4): 2 fallos -> omite" 1 "$G" begin bt
chk "bt.tripped existe" has bt.tripped
UKE_BOOT_ID=bt4 t "bt disparada NO afecta a wifi" 0 "$G" begin wifi
UKE_BOOT_ID=bt4 t "ok wifi" 0 "$G" ok wifi
UKE_BOOT_ID=bt4 t "bt disparada NO afecta a desktop" 0 "$G" begin desktop
UKE_BOOT_ID=bt4 t "ok desktop" 0 "$G" ok desktop
t "reset bt" 0 "$G" reset bt
chk "reset bt borra bt.tripped y bt.fails" test ! -e "$UKE_GUARD_STATE/bt.tripped" -a ! -e "$UKE_GUARD_STATE/bt.fails"
UKE_BOOT_ID=bt5 t "begin bt tras reset" 0 "$G" begin bt
UKE_BOOT_ID=bt5 t "ok bt" 0 "$G" ok bt
touch "$UKE_GUARD_ETC/no-bt"
UKE_BOOT_ID=bt6 t "no-bt omite bt" 1 "$G" begin bt
chk "no-bt no deja bt.pending" test ! -e "$UKE_GUARD_STATE/bt.pending"
UKE_BOOT_ID=bt6 t "no-bt NO omite wifi" 0 "$G" begin wifi
UKE_BOOT_ID=bt6 t "ok wifi" 0 "$G" ok wifi
rm -f "$UKE_GUARD_ETC/no-bt"
touch "$UKE_GUARD_ETC/safe-mode"
UKE_BOOT_ID=bt7 t "safe-mode omite bt" 1 "$G" begin bt
rm -f "$UKE_GUARD_ETC/safe-mode"
echo "== audio: cuarto componente, independiente de wifi, desktop y bt =="
UKE_BOOT_ID=au1 t "begin audio (primera vez)" 0 "$G" begin audio
chk "audio.pending creado" has audio.pending
UKE_BOOT_ID=au1 t "ok audio" 0 "$G" ok audio
chk "audio.pending borrado" test ! -e "$UKE_GUARD_STATE/audio.pending"
UKE_BOOT_ID=au2 t "begin audio (au2, se cuelga)" 0 "$G" begin audio
UKE_BOOT_ID=au3 t "begin audio (au3): 1 fallo, reintenta; se cuelga otra vez" 0 "$G" begin audio
UKE_BOOT_ID=au4 t "begin audio (au4): 2 fallos -> omite" 1 "$G" begin audio
chk "audio.tripped existe" has audio.tripped
UKE_BOOT_ID=au4 t "audio disparada NO afecta a bt" 0 "$G" begin bt
UKE_BOOT_ID=au4 t "ok bt" 0 "$G" ok bt
t "reset audio" 0 "$G" reset audio
chk "reset audio borra audio.tripped y audio.fails" test ! -e "$UKE_GUARD_STATE/audio.tripped" -a ! -e "$UKE_GUARD_STATE/audio.fails"
touch "$UKE_GUARD_ETC/no-audio"
UKE_BOOT_ID=au6 t "no-audio omite audio" 1 "$G" begin audio
chk "no-audio no deja audio.pending" test ! -e "$UKE_GUARD_STATE/audio.pending"
UKE_BOOT_ID=au6 t "no-audio NO omite bt" 0 "$G" begin bt
UKE_BOOT_ID=au6 t "ok bt" 0 "$G" ok bt
rm -f "$UKE_GUARD_ETC/no-audio"
touch "$UKE_GUARD_ETC/safe-mode"
UKE_BOOT_ID=au7 t "safe-mode omite audio" 1 "$G" begin audio
rm -f "$UKE_GUARD_ETC/safe-mode"
statuslist() { "$G" status | grep -q "^  $1 "; }
for c in wifi desktop bt audio; do chk "status lista $c" statuslist "$c"; done
UKE_BOOT_ID=bt8 "$G" begin bt >/dev/null; UKE_BOOT_ID=bt9 "$G" begin bt >/dev/null; UKE_BOOT_ID=bt10 "$G" begin bt >/dev/null
chk "(preparacion) bt disparada" has bt.tripped
t "reset all" 0 "$G" reset all
chk "reset all limpia tambien bt" test ! -e "$UKE_GUARD_STATE/bt.tripped" -a ! -e "$UKE_GUARD_STATE/bt.fails" -a ! -e "$UKE_GUARD_STATE/bt.pending"

echo "== validacion y utilidades =="
t "begin sin nombre -> uso (2)" 2 "$G" begin
t "nombre invalido" 2 "$G" begin '../etc'
t "status" 0 "$G" status
t "reset all" 0 "$G" reset all
[ "$fail" = 0 ] && echo "TODO OK" || echo "HAY FALLOS"
exit "$fail"
