#!/bin/bash
# uke-audio-amps-up.sh — segunda etapa del audio de la uke (E8): los 4 amplificadores FS19xx y la tarjeta ALSA «UKE» (altavoces internos).
# Requiere la etapa 1 (uke-audio-up.sh: overlay e2d + apr + q6apm parcheado con APM estado 1). La lanza uke-audio-amps.service (--service).
# Orden (medido en caliente el 19-oct-2026, AUDIO-E8-SUENA-20261019.md): e7i2c (bus I2C 88c000) -> e3 (pines LPI) + pinctrl-sm8650-lpass-lpi
#   -> uke_fs19xx (4 amps; el preset fs19xx.fsm se pide con request_firmware) -> e8b (tarjeta con los pines TDM) -> mezclador PRIMARY_TDM_RX_0 ON.
# Los parametros de uke_fs19xx (uke_fs_play, uke_fs_vol, uke_fs_volmax) vienen de /etc/modprobe.d/uke-audio-amps.conf (el modulo no escribe en los amps hasta que
# suena un PCM con uke_fs_play=Y; al parar los deja en reposo). Volumen: tope duro uke_fs_volmax, NO hay proteccion FSADSP (excursion/termica) como en Android.
#
#   uke-audio-amps-up.sh [--service]  carga la etapa 2.  exit 0 VERDE | 2 AMARILLO (cargado sin tarjeta/mezclador) | 3 ROJO | 1 requisito/omitido
#   uke-audio-amps-up.sh --down       rmmod en orden inverso (NO usar tras un oops: reiniciar)
#   uke-audio-amps-up.sh --status     solo lectura
# Interruptores: touch /etc/uke/no-audio-amps (solo esta etapa) | /etc/uke/no-audio | /etc/uke/safe-mode.
set -u
PATH=${UKE_AUDIO_PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin}
ROOT=${UKE_AUDIO_ROOT:-}
LOG=$ROOT/var/log/uke-audio.log
WAIT_PROBE=${UKE_AUDIO_WAIT_PROBE:-20}
WAIT_CARD=${UKE_AUDIO_WAIT_CARD:-20}
# Tarjeta a cargar: uke_audio_e8b (altavoces, por defecto) o uke_audio_e9a (altavoces + captura del WCD9395: carga ANTES uke_audio_e5 = codec, macros y SoundWire). Solo UNA tarjeta "UKE" a la vez.
CARD_MOD=${UKE_AUDIO_CARD_MOD:-uke_audio_e8b}
# Con e9a: si el codec WCD9395 no se puede cargar/adjuntar, por defecto se cae a la tarjeta de altavoces e8b (sin micro; exit 2 AMARILLO) en vez de dejar la tablet SIN audio. UKE_AUDIO_FALLBACK=0 lo desactiva (ROJO).
FALLBACK=${UKE_AUDIO_FALLBACK:-1}
# Ruta de mezclador del micro que se aplica tras cargar e9a (p. ej. amic1; vacio = ninguna). La captura solo arranca cuando un cliente abre el PCM: la ruta en si no enciende nada.
MIC_ROUTE=${UKE_AUDIO_MIC_ROUTE:-}
MIC_ROUTE_BIN=${UKE_AUDIO_MIC_ROUTE_BIN:-/usr/local/sbin/uke-mic-route.sh}
DEGRADED=0
APM_OK=$ROOT/run/uke-audio-apm-ok            # lo escribe la etapa 1 SOLO en VERDE (APM vivo); sin el, esta etapa no monta ASoC (colgaria)
GUARD=$ROOT/var/lib/uke/guard                 # contador propio de la etapa 2: `uke-bootguard begin|ok audio-amps`
E9A_HANG=$ROOT/var/lib/uke/e9a-hang           # marcador: e9a colgo/fallo un arranque; mientras exista se usa e8b (borrarlo para reintentar)
MIXER=${UKE_AUDIO_MIXER:-PRIMARY_TDM_RX_0 Audio Mixer MultiMedia1}

say() { local m="uke-audio-amps-up: $*"; printf '%s %s\n' "$(date +%H:%M:%S)" "$m"; printf '%s %s\n' "$(date -u +%FT%TZ)" "$m" >> "$LOG" 2>/dev/null; return 0; }
loaded() { grep -q "^$1 " "$ROOT/proc/modules"; }
dmesg_a() { dmesg 2>/dev/null | grep -iE 'uke-fs19xx|uke_audio_e[378]|fs19xx|UKE.*card|lpass-lpi' | tail -"${1:-10}"; }

# Tarjeta tardia: si PipeWire de la sesion ya corria cuando aparecio la tarjeta UKE, el nodo ALSA `uke-alsa-sink` (conf 51-uke-speakers.conf, `nofail`)
# no se creo. Entonces, y solo entonces, se reinicia pipewire de ESE usuario (corta un instante su audio, p. ej. BT). Al arrancar la tablet no hay PipeWire
# aun y no hace nada. Desactivar: UKE_AUDIO_PW_REFRESH=0.
pw_nodes_ok() { # pw_nodes_ok "$nodes": estan los nodos que deben existir
	grep -q 'uke-alsa-sink' <<<"$1" || return 1
	[ "$CARD_MOD" != uke_audio_e9a ] || [ -z "$MIC_ROUTE" ] || [ ! -f "$ROOT/etc/pipewire/pipewire.conf.d/51-uke-mic.conf" ] || grep -q 'uke-mic' <<<"$1"
}
pw_refresh() {
	[ "${UKE_AUDIO_PW_REFRESH:-1}" = 1 ] || return 0
	[ -f "$ROOT/etc/pipewire/pipewire.conf.d/51-uke-speakers.conf" ] || return 0
	local u id nodes t
	for u in $(ps -o user= -C pipewire 2>/dev/null | tr -d ' ' | sort -u); do
		[ -n "$u" ] && [ "$u" != root ] || continue
		id=$(id -u "$u" 2>/dev/null) || continue
		nodes=$(XDG_RUNTIME_DIR=/run/user/$id timeout 10 runuser -u "$u" -- pw-cli ls Node 2>/dev/null)
		pw_nodes_ok "$nodes" && continue
		say "PipeWire de $u ya corria sin los nodos uke-alsa-sink/uke-mic: lo reinicio"
		XDG_RUNTIME_DIR=/run/user/$id timeout 10 runuser -u "$u" -- systemctl --user reset-failed pipewire.socket pipewire pipewire-pulse.socket pipewire-pulse wireplumber >/dev/null 2>&1
		XDG_RUNTIME_DIR=/run/user/$id timeout 30 runuser -u "$u" -- systemctl --user restart pipewire.socket pipewire-pulse.socket pipewire pipewire-pulse wireplumber >/dev/null 2>&1 \
			|| say "AVISO: no pude reiniciar pipewire de $u"
		for t in 1 2 3 4 5; do
			sleep 1; nodes=$(XDG_RUNTIME_DIR=/run/user/$id timeout 10 runuser -u "$u" -- pw-cli ls Node 2>/dev/null)
			pw_nodes_ok "$nodes" && break
		done
		pw_nodes_ok "$nodes" || say "AVISO: tras reiniciar PipeWire de $u siguen sin existir los nodos uke-alsa-sink/uke-mic"
	done
	return 0
}
# ruta de micro (solo con e9a) y refresco de PipeWire: tambien en AMARILLO
post_card() {
	if [ "$CARD_MOD" = uke_audio_e9a ] && [ -n "$MIC_ROUTE" ] && [ -x "$MIC_ROUTE_BIN" ]; then
		"$MIC_ROUTE_BIN" --apply "$MIC_ROUTE" >/dev/null 2>&1 && say "ruta de micro $MIC_ROUTE aplicada (la captura solo arranca al abrir hw:UKE,2)" || say "AVISO: no pude aplicar la ruta de micro $MIC_ROUTE"
	fi
	pw_refresh
}

cmd_status() {
	echo "kernel $(uname -r)"
	grep -E '^(uke_audio_e7i2c|uke_audio_e3|pinctrl_sm8650_lpass_lpi|uke_fs19xx|uke_audio_e5|uke_audio_e8b|uke_audio_e9a) ' "$ROOT/proc/modules" | cut -d' ' -f1-3 | sed 's/^/  mod: /'
	echo "  tarjetas: $(cat "$ROOT"/proc/asound/cards 2>/dev/null | tr '\n' ' ')"
	echo "  ultimas lineas relevantes de dmesg:"; dmesg_a 10 | sed 's/^/    /'
	return 0
}

cmd_down() {
	[ "$(id -u)" = 0 ] || { echo "hace falta root" >&2; return 1; }
	sync
	local m
	for m in uke_audio_e9a uke_audio_e8b uke_audio_e5 uke_fs19xx pinctrl_sm8650_lpass_lpi uke_audio_e3 uke_audio_e7i2c; do
		if loaded "$m"; then modprobe -r "$m" && say "$m descargado" || { say "ROJO: no pude descargar $m (si hubo oops: reiniciar)"; return 3; }; fi
	done
	sync; return 0
}

cmd_up() {
	[ "$(id -u)" = 0 ] || { echo "hace falta root" >&2; return 1; }
	[ -e "$ROOT/etc/uke/no-audio-amps" ] && { say "interruptor no-audio-amps: omito"; return 1; }
	case "$(uname -r)" in *senemos*ouke[45]*) ;; *) say "kernel $(uname -r) no es senemos ouke4/ouke5: no hago nada"; return 1 ;; esac
	local f
	[ "${UKE_AUDIO_NEED_APM:-1}" = 0 ] || [ -e "$APM_OK" ] || { say "la etapa 1 no dejo el marcador de APM vivo ($APM_OK): no monto ASoC (colgaria); omito"; return 1; }
	if [ "$CARD_MOD" = uke_audio_e9a ]; then
		local reason=""
		if [ -e "$E9A_HANG" ]; then reason="e9a desactivada tras un fallo anterior (borra $E9A_HANG para reintentar)"
		elif [ "$(cat "$GUARD/audio-amps.fails" 2>/dev/null || echo 0)" -gt 0 ]; then reason="el intento anterior de la etapa 2 no se completo (cuelgue/reset)"; mkdir -p "$(dirname "$E9A_HANG")" 2>/dev/null; : > "$E9A_HANG"
		elif ! { modinfo -n uke_audio_e5 >/dev/null 2>&1 && modinfo -n uke_audio_e9a >/dev/null 2>&1; }; then reason="faltan uke_audio_e5.ko o uke_audio_e9a.ko"; fi
		if [ -n "$reason" ]; then say "AMARILLO: $reason: uso e8b (solo altavoces)"; CARD_MOD=uke_audio_e8b; DEGRADED=1; fi
	fi
	for f in uke_audio_e7i2c uke_audio_e3 pinctrl-sm8650-lpass-lpi uke_fs19xx uke_audio_e8b; do
		modinfo -n "$f" >/dev/null 2>&1 || { say "no encuentro el modulo $f (¿deploy-amps.sh --module? ¿depmod?)"; return 1; }
	done
	[ -s "$ROOT/lib/firmware/fs19xx.fsm" ] || { say "falta /lib/firmware/fs19xx.fsm"; return 1; }
	[ -s "$ROOT/lib/firmware/qcom/sm8650/UKE-tplg.bin" ] || { say "falta UKE-tplg.bin"; return 1; }
	# etapa 1 imprescindible: APM vivo (sin ella e8b/ASoC no tienen cliente y el montaje cuelga)
	for f in uke_audio_e2d snd_q6apm q6prm_clocks; do
		loaded "$f" || { say "etapa 1 (uke-audio-up.sh) no esta completa: falta $f"; return 1; }
	done
	for f in uke_audio_e2 uke_audio_e2b uke_audio_e2c; do loaded "$f" && { say "overlay alternativo $f cargado: no sigo"; return 1; }; done
	loaded uke_audio_e8b && [ "$CARD_MOD" != uke_audio_e8b ] && { say "uke_audio_e8b (otra tarjeta UKE) ya cargado: no cargo $CARD_MOD (reiniciar)"; return 1; }
	loaded "$CARD_MOD" && { say "ya cargado $CARD_MOD: nada que hacer (--down para recargar)"; return 0; }
	sync
	local m mark; mark=$(dmesg 2>/dev/null | wc -l)
	for m in uke_audio_e7i2c uke_audio_e3 pinctrl-sm8650-lpass-lpi uke_fs19xx; do
		modprobe "$m" || { say "ROJO: modprobe $m fallo (dmesg: $(dmesg_a 4 | tr '\n' '|')); no cargo la tarjeta"; return 3; }
		say "$m cargado"
	done
	local i
	for i in $(seq 1 "$WAIT_PROBE"); do
		dmesg 2>/dev/null | tail -n +$((mark + 1)) | grep -q 'uke-fs19xx.*amps\|uke-fs19xx-codec' && break
		sleep 1
	done
	loaded uke_fs19xx || { say "ROJO: uke_fs19xx no quedo cargado"; return 3; }
	if [ "$CARD_MOD" = uke_audio_e9a ]; then
		wcd_ok=1
		modprobe uke_audio_e5 || { say "ROJO: modprobe uke_audio_e5 fallo (dmesg: $(dmesg_a 4 | tr '\n' '|'))"; wcd_ok=0; }
		if [ "$wcd_ok" = 1 ]; then
			say "uke_audio_e5 cargado: espero que el WCD9395 se adjunte por SoundWire (hasta ${WAIT_PROBE}s)"
			for i in $(seq 1 "$WAIT_PROBE"); do
				[ "$(grep -lE '^(Attached|Alert)' "$ROOT"/sys/bus/soundwire/devices/sdw:*/status 2>/dev/null | wc -l)" -ge 2 ] && break
				sleep 1
			done
			if [ "$(grep -lE '^(Attached|Alert)' "$ROOT"/sys/bus/soundwire/devices/sdw:*/status 2>/dev/null | wc -l)" -ge 2 ]; then say "WCD9395 adjunto (2 esclavos SoundWire Attached)"
			else say "ROJO: los 2 esclavos SoundWire del WCD9395 no se adjuntaron"; wcd_ok=0; fi
		fi
		if [ "$wcd_ok" = 0 ]; then
			[ "$FALLBACK" = 1 ] || { say "no cargo la tarjeta e9a (UKE_AUDIO_FALLBACK=0)"; return 3; }
			say "AMARILLO: sin micro; cargo la tarjeta de altavoces e8b para no dejar la tablet sin audio"; CARD_MOD=uke_audio_e8b; DEGRADED=1
		fi
	fi
	modprobe "$CARD_MOD" || { say "ROJO: modprobe $CARD_MOD fallo (dmesg: $(dmesg_a 4 | tr '\n' '|'))"; return 3; }
	say "$CARD_MOD cargado: espero la tarjeta UKE (hasta ${WAIT_CARD}s)"
	for i in $(seq 1 "$WAIT_CARD"); do
		grep -q 'UKE' "$ROOT/proc/asound/cards" 2>/dev/null && break
		sleep 1
	done
	grep -q 'UKE' "$ROOT/proc/asound/cards" 2>/dev/null || { say "AMARILLO: cargado pero no aparece la tarjeta UKE: $(dmesg_a 6 | tr '\n' '|')"; post_card; return 2; }
	amixer -c UKE cset name="$MIXER" on >/dev/null 2>&1 || { say "AMARILLO: tarjeta UKE sin el mezclador '$MIXER'"; post_card; return 2; }
	post_card
	if [ "$DEGRADED" = 1 ]; then say "AMARILLO: tarjeta UKE (altavoces) lista; micro NO disponible"; return 2; fi
	say "VERDE: tarjeta UKE y mezclador listos (amps en reposo hasta que suene un PCM)"
	return 0
}

case "${1:---service}" in
	--service|--up) cmd_up; exit $? ;;
	--down) cmd_down; exit $? ;;
	--status) cmd_status; exit 0 ;;
	-h|--help) awk 'NR>1 && /^set -u/{exit} NR>1' "$0"; exit 0 ;;
	*) echo "uso: $0 [--service|--down|--status]" >&2; exit 1 ;;
esac
