#!/bin/bash
# uke-audio-up.sh — levanta la pila AudioReach de la uke (E2d): overlay de DT con q6apm (reg 3) y q6prm (reg 7) + apr (que autocarga
# snd-q6apm parcheado, q6prm y q6prm-clocks). Lo lanza uke-audio.service (--service) y se puede usar a mano.
# Medido en caliente el 18-oct-2026 (AUDIO-E2d-RESULTADO-20261018.md): `estado APM (async) = 1` a 1 ms y relojes LPASS_HW_* registrados.
# NO VERIFICADO EN FRIO (arranque limpio): el primer uso real al arrancar es con orden del dueño.
#
#   uke-audio-up.sh [--service]  espera ADSP running, `modprobe uke_audio_e2d` (overlay) y `modprobe apr`; espera
#                                'uke: estado APM (async) = 1' y q6prm_clocks. exit 0 VERDE | 2 AMARILLO (cargado, sin ver el estado) | 3 ROJO | 1 requisito
#   uke-audio-up.sh --down       descarga en orden inverso (q6prm_clocks q6prm snd_q6apm apr, luego el overlay)
#   uke-audio-up.sh --status     solo lectura
# Requisitos: kernel senemos con release ouke4 u ouke5; uke_audio_e2d.ko y el snd-q6apm parcheado (updates/) instalados con vermagic del kernel en marcha;
# /dev sin overlay e2 (alternativo: no se mezclan). `apr` sigue en la blacklist de autoload (uke-carga.conf): solo se carga por nombre, aqui.
# Para pruebas en el PC (harness/test-audio-up.sh): UKE_AUDIO_ROOT = prefijo falso de /proc /sys /etc /var, UKE_AUDIO_PATH = PATH con mocks.
set -u
PATH=${UKE_AUDIO_PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin}
ROOT=${UKE_AUDIO_ROOT:-}
LOG=$ROOT/var/log/uke-audio.log
RPROC=$ROOT/sys/class/remoteproc
WAIT_ADSP=${UKE_AUDIO_WAIT_ADSP:-60}
WAIT_APM=${UKE_AUDIO_WAIT_APM:-75}   # el modulo reintenta cada ~6 s (uke_retries=15): en frio el SPF tarda en contestar

say() { local m="uke-audio-up: $*"; printf '%s %s\n' "$(date +%H:%M:%S)" "$m"; printf '%s %s\n' "$(date -u +%FT%TZ)" "$m" >> "$LOG" 2>/dev/null; return 0; }
loaded() { grep -q "^$1 " "$ROOT/proc/modules"; }
adsp_state() { local r; for r in "$RPROC"/remoteproc*; do [ "$(cat "$r/name" 2>/dev/null)" = adsp ] && { cat "$r/state"; return; }; done; echo none; }
dmesg_a() { dmesg 2>/dev/null | grep -iE 'uke_audio|qcom-apm|qcom-prm|q6prm|qcom,apr|uke: ' | tail -"${1:-12}"; }

cmd_status() {
	echo "kernel $(uname -r)  adsp=$(adsp_state)"
	grep -E '^(uke_audio_e2d|apr|snd_q6apm|q6prm|q6prm_clocks|snd_q6dsp_common|fastrpc) ' "$ROOT/proc/modules" | cut -d' ' -f1-3 | sed 's/^/  mod: /'
	echo "  snd-q6apm viene de: $(modinfo -n snd-q6apm 2>/dev/null)"
	echo "  ultimas lineas relevantes de dmesg:"; dmesg_a 10 | sed 's/^/    /'
	return 0
}

cmd_down() {
	[ "$(id -u)" = 0 ] || { echo "hace falta root" >&2; return 1; }
	local m
	for m in uke_audio_e9a uke_audio_e8b uke_audio_e5 uke_fs19xx uke_audio_e7i2c; do
		loaded "$m" && { say "la etapa 2 sigue cargada ($m): usa uke-audio-amps-up.sh --down primero (o reinicia con sync); NO descargo la etapa 1 bajo una tarjeta viva"; return 1; }
	done
	sync
	# orden inverso a la carga: tarjetas/overlays opcionales, DAIs (bedais/dais cuelgan de q6apm), q6prm, q6apm, apr, overlay base
	for m in uke_audio_e7b uke_audio_e7a uke_audio_e4c uke_audio_e3 snd_soc_sc8280xp q6prm_clocks q6prm q6apm_dai q6apm_lpass_dais snd_q6apm apr uke_audio_e2d; do
		if loaded "$m"; then modprobe -r "$m" && say "$m descargado" || { say "ROJO: no pude descargar $m"; return 3; }; fi
	done
	sync
	return 0
}

cmd_up() {
	[ "$(id -u)" = 0 ] || { echo "hace falta root" >&2; return 1; }
	case "$(uname -r)" in *senemos*ouke[45]*) ;; *) say "kernel $(uname -r) no es senemos ouke4/ouke5: no hago nada"; return 1 ;; esac
	local krel; krel=$(uname -r)
	local f
	for f in uke_audio_e2d snd-q6apm; do
		modinfo -n "$f" >/dev/null 2>&1 || { say "no encuentro el modulo $f (¿deploy.sh --module? ¿depmod?)"; return 1; }
	done
	case "$(modinfo -n snd-q6apm 2>/dev/null)" in */updates/*) ;; *) say "snd-q6apm NO es el parcheado (updates/): sin el, q6apm usa src_port 1 y el APM no responde"; return 1 ;; esac
	[ "$(modinfo -F vermagic uke_audio_e2d 2>/dev/null | cut -d' ' -f1)" = "$krel" ] || { say "uke_audio_e2d no esta compilado para $krel"; return 1; }
	for f in uke_audio_e2 uke_audio_e2b uke_audio_e2c; do
		loaded "$f" && { say "ya esta cargado $f (overlay alternativo): descarga primero"; return 1; }
	done
	loaded uke_audio_e2d && { say "uke_audio_e2d ya cargado: nada que hacer (--down para recargar)"; return 0; }
	rm -f "$ROOT/run/uke-audio-apm-ok"
	local i
	for i in $(seq 1 "$WAIT_ADSP"); do [ "$(adsp_state)" = running ] && break; sleep 1; done
	[ "$(adsp_state)" = running ] || { say "el ADSP no esta running tras ${WAIT_ADSP}s (uke-carga): no cargo nada"; return 1; }
	say "ADSP running, kernel $krel; cargo el overlay e2d y apr"
	local mark; mark=$(dmesg 2>/dev/null | wc -l)
	sync
	modprobe uke_audio_e2d || { say "ROJO: modprobe uke_audio_e2d fallo (dmesg: $(dmesg_a 3 | tr '\n' '|'))"; return 3; }
	modprobe apr || { say "ROJO: modprobe apr fallo; retiro el overlay (dmesg: $(dmesg_a 3 | tr '\n' '|'))"; modprobe -r uke_audio_e2d; return 3; }
	say "overlay y apr cargados; espero 'estado APM (async) = 1' (hasta ${WAIT_APM}s)"
	local new
	for i in $(seq 1 "$WAIT_APM"); do
		new=$(dmesg 2>/dev/null | tail -n +$((mark + 1)))
		if grep -q 'uke: estado APM (async) = 1' <<<"$new"; then
			if loaded q6prm_clocks; then mkdir -p "$ROOT/run" 2>/dev/null; : > "$ROOT/run/uke-audio-apm-ok"; say "VERDE: APM estado 1 y q6prm_clocks cargado"; return 0; fi
			sleep 1; loaded q6prm_clocks && { mkdir -p "$ROOT/run" 2>/dev/null; : > "$ROOT/run/uke-audio-apm-ok"; say "VERDE: APM estado 1 y q6prm_clocks cargado"; return 0; }
			say "AMARILLO: APM estado 1 pero q6prm_clocks no cargo (¿q6prm diferido?): $(dmesg_a 6 | tr '\n' '|')"; return 2
		fi
		sleep 1
	done
	# no hay 'estado = 1' al vencer el plazo: con CMD timeout (el SPF nunca contesto) es ROJO; sin ninguna linea, AMARILLO
	if grep -q 'CMD timeout for \[1001021\]' <<<"$new"; then
		say "ROJO: APM_CMD_GET_SPF_STATE sin respuesta tras ${WAIT_APM}s y reintentos (CMD timeout): $(dmesg_a 6 | tr '\n' '|')"; return 3
	fi
	say "AMARILLO: cargado pero no vi el estado del APM en ${WAIT_APM}s: $(dmesg_a 6 | tr '\n' '|')"; return 2
}

case "${1:---service}" in
	--service|--up) cmd_up; exit $? ;;
	--down) cmd_down; exit $? ;;
	--status) cmd_status; exit 0 ;;
	-h|--help) awk 'NR>1 && /^set -u/{exit} NR>1' "$0"; exit 0 ;;
	*) echo "uso: $0 [--service|--down|--status]" >&2; exit 1 ;;
esac
