#!/usr/bin/env bash
# mic-abierta.sh — mitigacion del CHASQUIDO de arranque de la captura (M7, e25): el transitorio (~50 ms, 5-28 dB sobre el suelo) ocurre al ABRIR hw:UKE,2; ninguna variante de mezclador lo quita.
# Hipotesis a validar en la tablet: con el PCM siempre abierto el chasquido ocurre una vez (al arrancar PipeWire) y no al abrir cada app. Coste: ADC/bias del micro encendidos de continuo (medir
# consumo: sesion bateria). La variante se GENERA de 51-uke-mic.conf (una sola fuente): suspension 0 + pause-on-idle=false + always-process.
#   --render   escribe la conf variante por stdout (para tests)       --check   estado remoto (solo lectura)
#   --go       instala la variante en /etc/pipewire/pipewire.conf.d/51-uke-mic.conf (guarda la base en /root/uke-mic/51-uke-mic.conf.base). SOLO FICHEROS: surte efecto al reiniciar PipeWire (usuario).
#   --revert   restaura la base guardada (o copia la base del repo)
# HOSTIP por entorno (defecto Tailscale `uke`). Pedir la tablet antes de --go/--revert/--check.
set -u
HERE=$(cd "$(dirname "$0")" && pwd); R=$(cd "$HERE/../../../../.." && pwd); KEY=$R/build/rootfs/uke-arch-root; HOSTIP=${HOSTIP:-${UKE_HOST:-uke}}
render() { sed -e 's/session\.suspend-timeout-seconds = 5/session.suspend-timeout-seconds = 0\n            node.pause-on-idle = false\n            node.always-process = true/' -e '1s/^/# VARIANTE «micro siempre abierta» generada por mic-abierta.sh (suspension 0, pause-on-idle=false, always-process=true: sin esto el nodo nace suspendido y el PCM no se abre hasta que hay cliente); base en 51-uke-mic.conf\n/' "$HERE/51-uke-mic.conf"; }
SSHO="-i $KEY -o BatchMode=yes -o ConnectTimeout=8"; rssh() { ssh $SSHO root@"$HOSTIP" "$@"; }
case "${1:-}" in
--render) render; grep -q 'pause-on-idle = false' < <(render) || { echo "no se aplico la sustitucion" >&2; exit 2; } ;;
--check) rssh 'grep -nE "suspend-timeout|pause-on-idle" /etc/pipewire/pipewire.conf.d/51-uke-mic.conf; ls -l /root/uke-mic/51-uke-mic.conf.base 2>&1' ;;
--go) T=$(mktemp); render > "$T"; grep -q 'pause-on-idle = false' "$T" || { echo "no se aplico la sustitucion" >&2; exit 2; }
	rssh 'mkdir -p /root/uke-mic; [ -e /root/uke-mic/51-uke-mic.conf.base ] || cp -a /etc/pipewire/pipewire.conf.d/51-uke-mic.conf /root/uke-mic/51-uke-mic.conf.base' && scp $SSHO "$T" root@"$HOSTIP":/etc/pipewire/pipewire.conf.d/51-uke-mic.conf >/dev/null && rssh 'chmod 644 /etc/pipewire/pipewire.conf.d/51-uke-mic.conf; sync; echo instalada; echo "reiniciar PipeWire del usuario para aplicar"'; rm -f "$T" ;;
--revert) if rssh '[ -s /root/uke-mic/51-uke-mic.conf.base ] && cp -a /root/uke-mic/51-uke-mic.conf.base /etc/pipewire/pipewire.conf.d/51-uke-mic.conf'; then echo "restaurada desde la base guardada"
	else echo "sin base guardada: copio la del repo"; scp $SSHO "$HERE/51-uke-mic.conf" root@"$HOSTIP":/etc/pipewire/pipewire.conf.d/ >/dev/null && echo "restaurada desde el repo" || { echo "FALLO al restaurar" >&2; exit 2; }; fi
	rssh 'chmod 644 /etc/pipewire/pipewire.conf.d/51-uke-mic.conf; sync; grep -c "pause-on-idle" /etc/pipewire/pipewire.conf.d/51-uke-mic.conf' | sed 's/^0$/verificado: sin pause-on-idle (base)/;s/^[1-9]$/AVISO: la conf remota sigue siendo la variante/' ;;
*) echo "uso: $0 --render|--check|--go|--revert" >&2; exit 2 ;;
esac
