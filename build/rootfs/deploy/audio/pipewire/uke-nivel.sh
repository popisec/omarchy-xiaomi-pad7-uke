#!/bin/bash
# uke-nivel.sh ESCALON — sube/baja el nivel de los altavoces EN CALIENTE (sin reiniciar PipeWire ni recargar modulos). Se ejecuta EN la tablet como root.
#   0  Mult 0.25  Max 0.30  amps 0xE0   (el .conf; -12 dB, el mas conservador)
#   1  Mult 0.126 Max 0.25  amps 0xF3   (= Android, volumen de medios 80/150 «paso 5»: -18 dB, amps a 0xF3 FIJO como Android)
#   2  Mult 0.251 Max 0.40  amps 0xF3   (= Android 100/150: -12 dB)
#   3  Mult 0.479 Max 0.60  amps 0xF3   (= Android 122/150: -6,4 dB)
#   4  Mult 0.966 Max 0.70  amps 0xF3   (= Android 150/150 en ganancia, -0,3 dB, pero con el pico limitado a 0,70 hasta medir la termica; SIN FSADSP: exige `--yes`, vuelve solo al escalon 2 a los 60 s (`--no-revert` lo evita) y solo con el dueño presente)
# Curva leida de /odm/etc/audio_policy_engine_stream_volumes.xml (STREAM_MUSIC/speaker, indices 0..150) y ACDB (volumen del grafo -3 dB por paso); ver AUDIO-ANDROID-FSADSP-RESULTADO-20261020.md.
# Android regula en el ADSP/AudioFlinger y deja los amps a 0xF3; el limite de pico (Max) es NUESTRA red de seguridad: Android tiene el FSADSP (excursion/termica por bateria+temperatura) y el limitador de SAL.
# Mult/Max = ganancia y limite de pico de la cadena `uke-speakers` (51-uke-speakers.conf); amps = uke_fs_vol/uke_fs_volmax de uke_fs19xx
# (se aplica al siguiente arranque del PCM: parar y volver a reproducir). NO persiste: tras reiniciar PipeWire/la tablet vuelve al escalon del .conf (0).
# `--estado` muestra los valores actuales.
set -u
U=omarchy; ID=$(id -u $U); export XDG_RUNTIME_DIR=/run/user/$ID
P=/sys/module/uke_fs19xx/parameters
pw() { runuser -u $U -- "$@" 2>&1 | grep -v 'mod.rt'; }
node() { runuser -u $U -- pw-cli ls Node 2>/dev/null | awk '/^\tid /{id=$2} /node.name = "uke-speakers"/{print id}' | tr -d ,; }
N=$(node); [ -n "$N" ] || { echo "no encuentro el nodo uke-speakers (¿PipeWire?)"; exit 1; }
YES=0; REVERT=1; STEP=""
for a in "$@"; do case "$a" in --yes) YES=1;; --no-revert) REVERT=0;; *) STEP=$a;; esac; done
case "${STEP:---estado}" in
	--estado) pw pw-cli e "$N" Props | grep -A1 -E '"(gain_l:Mult|lim_l:Max)"' | grep -E 'String|Float' | paste - - ; echo "amps: vol=$(cat $P/uke_fs_vol) volmax=$(cat $P/uke_fs_volmax)"; exit 0 ;;
	0) M=0.25; X=0.30; V=224 ;;
	1) M=0.126; X=0.25; V=243 ;;
	2) M=0.251; X=0.40; V=243 ;;
	3) M=0.479; X=0.60; V=243 ;;
	4) M=0.966; X=0.70; V=243
	   [ "$YES" = 1 ] || { echo "el escalon 4 exige --yes (sin FSADSP: proteccion termica solo por tu vigilancia); vuelve solo al 2 a los 60 s (--no-revert lo evita)" >&2; exit 1; } ;;
	*) echo "uso: $0 0|1|2|3|4 [--yes] [--no-revert] | --estado" >&2; exit 1 ;;
esac
# 1) comprobar ANTES de tocar nada que la cadena es alcanzable (pw-cli responde): si no, no se toca ni el amp
runuser -u $U -- pw-cli e "$N" Props >/dev/null 2>&1 || { echo "pw-cli no responde sobre el nodo $N: no toco nada" >&2; exit 1; }
V0=$(cat $P/uke_fs_vol); VM0=$(cat $P/uke_fs_volmax)
setamp() { # setamp V: el tope de los amps primero hacia arriba, ultimo hacia abajo (uke_fs_vol se recorta a volmax)
	if [ "$1" -ge "$(cat $P/uke_fs_volmax)" ]; then echo "$1" > $P/uke_fs_volmax; echo "$1" > $P/uke_fs_vol; else echo "$1" > $P/uke_fs_vol; echo "$1" > $P/uke_fs_volmax; fi
}
setchain() { runuser -u $U -- pw-cli s "$N" Props "{ params = [ \"gain_l:Mult\" $1 \"gain_r:Mult\" $1 \"lim_l:Max\" $2 \"lim_r:Max\" $2 \"lim_l:Min\" -$2 \"lim_r:Min\" -$2 ] }" >/dev/null 2>&1; }
if [ "$V" -gt "$V0" ]; then
	# SUBIENDO los amps: primero el amp y despues la cadena; si la cadena falla, se devuelve el amp a lo anterior
	setamp "$V"; setchain "$M" "$X" || { setamp "$V0"; [ "$VM0" -ge "$V0" ] && echo "$VM0" > $P/uke_fs_volmax; echo "no pude fijar la cadena: amps devueltos a $V0" >&2; exit 1; }
else
	# BAJANDO (o igual): primero la cadena y despues los amps
	setchain "$M" "$X" || { echo "no pude fijar la cadena: no toco los amps" >&2; exit 1; }; setamp "$V"
fi
echo "escalon $STEP: Mult $M, limite ±$X, amps vol=$V (se aplica al siguiente PCM)"
if [ "$STEP" = 4 ] && [ "$REVERT" = 1 ]; then
	systemd-run --quiet --collect --on-active=60 --unit=uke-nivel-revert --description="uke-nivel: vuelta al escalon 2 tras 60 s en el 4" "$0" 2 >/dev/null 2>&1 \
		&& echo "(volvera solo al escalon 2 a los 60 s; --no-revert para evitarlo)" || echo "AVISO: no pude programar la vuelta automatica al escalon 2: bajalo tu" >&2
fi
