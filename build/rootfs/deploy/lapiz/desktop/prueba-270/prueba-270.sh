#!/bin/sh
# prueba-270.sh — orquesta por ssh la prueba de 270 grados del lapiz (ver PRUEBA-270.md). 21-oct-2026. NO EJECUTADO.
#   prueba-270.sh --dry-run   imprime cada orden ssh sin ejecutar nada
#   prueba-270.sh             ejecuta (solo cuando el dueño lo decida); espera Enter para dibujar y restaura SIEMPRE a 0 grados al salir
# Entorno: UKE_HOST (por defecto root@uke), UKE_KEY (por defecto build/rootfs/uke-arch-root), UKE_USER (usuario de escritorio, omarchy), MIN_BAT (20)
# Requiere en la tablet: uke-rotate y uke-pen-sync instalados en /usr/local/bin.
set -u
UKE_HOST=${UKE_HOST:-root@uke}
UKE_USER=${UKE_USER:-omarchy}
MIN_BAT=${MIN_BAT:-20}
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../../../../.." && pwd)
UKE_KEY=${UKE_KEY:-$ROOT/build/rootfs/uke-arch-root}
DRY=0
case ${1:-} in --dry-run) DRY=1 ;; "") ;; *) echo "uso: $0 [--dry-run]"; exit 2 ;; esac

SSH_OPTS="-i $UKE_KEY -o BatchMode=yes -o ConnectTimeout=8"
# t: ejecuta (o imprime) una orden remota
t() {
	if [ "$DRY" = 1 ]; then echo "[dry-run] ssh $SSH_OPTS $UKE_HOST $*"; return 0; fi
	# shellcheck disable=SC2086
	ssh $SSH_OPTS "$UKE_HOST" "$@"
}
# d: orden como usuario de escritorio (hyprctl necesita su sesion)
d() { t "sudo -u $UKE_USER -H $*"; }
die() { echo "prueba-270: $*" >&2; exit 1; }

RESTORE=0
restore() {
	[ "$RESTORE" = 1 ] || return 0
	RESTORE=0
	echo "== restaurando 0 grados =="
	d uke-rotate 0
	d uke-pen-sync
	d uke-pen-sync --status
}
trap 'restore' EXIT
trap 'exit 130' INT TERM

echo "== gates =="
t true || die "sin ssh a $UKE_HOST"
bat=$(t 'cat /sys/class/power_supply/*/capacity 2>/dev/null | head -1'; true)
st=$(t 'cat /sys/class/power_supply/*/status 2>/dev/null | head -1'; true)
if [ "$DRY" = 1 ]; then bat=100; st=Charging; fi
echo "bateria: ${bat:-?} % ($st)"
case ${st:-} in Charging|Full) ;; *) [ "${bat:-0}" -ge "$MIN_BAT" ] 2>/dev/null || die "bateria < $MIN_BAT % y sin cargar" ;; esac
for u in uke-touch uke-lapiz; do
	if [ "$DRY" = 1 ]; then echo "[dry-run] ssh $UKE_HOST systemctl is-active $u"; continue; fi
	[ "$(t "systemctl is-active $u")" = active ] || die "$u no esta activo"
done
t 'command -v uke-rotate && command -v uke-pen-sync >/dev/null' >/dev/null || [ "$DRY" = 1 ] || die "faltan uke-rotate / uke-pen-sync en la tablet"

echo "== estado inicial =="
d uke-rotate status
RESTORE=1   # a partir de aqui, cualquier salida vuelve a 0 grados

echo "== 270 =="
d uke-rotate 270
d uke-pen-sync
d uke-pen-sync --status
d hyprctl getoption input:tablet:transform
d hyprctl getoption input:touchdevice:transform
d hyprctl monitors -j

if [ "$DRY" = 1 ]; then
	echo "[dry-run] (aqui espera Enter para que el dueño dibuje en rnote: diagonal esquina a esquina + cuadrado, con lapiz y con dedo)"
else
	printf 'Dibuja en rnote (diagonal + cuadrado, lapiz y dedo). Enter cuando termines (se restaura 0 grados): '
	read -r _
fi
exit 0
