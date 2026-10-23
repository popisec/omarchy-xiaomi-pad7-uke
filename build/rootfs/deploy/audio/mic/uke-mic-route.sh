#!/bin/bash
# uke-mic-route.sh — ruta MINIMA de mezclador para el micro de la uke (M0 del plan MICROFONO-20261020.md). BORRADOR del PC, NO probado. Se ejecuta EN la tablet (root) DESPUES de M2
# (tarjeta e9a cargada: existen los controles del WCD9395 y del tx-macro). Solo toca CONTROLES DE MEZCLADOR (no carga modulos, no reinicia nada).
#   --list           muestra los controles de captura que existen (TX DEC*, TX SMIC MUX*, ADC*, MIC BIAS, MultiMedia3...).
#   --dry MIC        (tambien dual-A-B, p. ej. dual-1-4: dos micros a la vez, canal 0 = AMICA y canal 1 = AMICB) imprime los `amixer cset` que haria (MIC = amic1..amic5 (ruta mainline: ADC1+SWR_MIC0, unica que funciona en M3) | amic3-vendor | estereo-vendor (numeracion del vendor: dan EIO en M3)) y marca los que NO existen. No escribe.
#   --apply MIC      los aplica (con -c ${CARD:-UKE}); los que no existen se avisan y se saltan (no aborta).
#   --off            deja los ADC en CHn_AMIC_DISABLE y los muxes a ZERO.
# Valores: `amic1`/`amic4` = QRD (alsa-ucm-conf, kernel mainline: SWR_MIC0 + ADC1); `amic3-vendor` = ruta `main-mic` de Android (SWR_MIC8, ADC3 CH3_AMIC3, DEC5);
# `estereo-vendor` = `handset-dmic-endfire` de Android (AMIC1 + AMIC5, SWR_MIC4 + SWR_MIC9). La numeracion SWR_MIC del vendor ((puerto-1)*4+(canal-1)) puede NO coincidir con
# mainline (`qcom,tx-port-mapping = <2 2 3 4>`): por eso M3 barre las opciones y mide RMS (ver el plan).
set -u
CARD=${CARD:-UKE}; A=${AMIXER:-amixer}
cs() { # cs "control" valor
	if $A -c "$CARD" cget name="$1" >/dev/null 2>&1; then
		if [ "$MODE" = apply ]; then $A -c "$CARD" cset name="$1" "$2" >/dev/null && echo "  ok  $1 = $2" || echo "  FALLO $1 = $2"; else echo "  cset name='$1' $2"; fi
	else echo "  (no existe) $1"; fi
}
common() { cs 'MultiMedia3 Mixer TX_CODEC_DMA_TX_3' 1; }
amic_qrd() { # amic_qrd N   (N = 1 o 4)
	common
	cs 'ADC1_MIXER Switch' 1; cs 'ADC1 MUX' "CH1_AMIC$1"; cs 'ADC1 Switch' 1; cs 'ADC1 Volume' 10; cs 'TX0 MODE' ADC_ULP
	cs 'TX DEC0 MUX' SWR_MIC; cs 'TX SMIC MUX0' SWR_MIC0; cs 'TX_AIF1_CAP Mixer DEC0' 1; cs 'TX_DEC0 Volume' 100
}
amic3_vendor() {
	common
	cs 'TX DEC5 MUX' SWR_MIC; cs 'TX SMIC MUX5' SWR_MIC8; cs 'TX_AIF1_CAP Mixer DEC5' 1
	cs 'ADC3 MUX' CH3_AMIC3; cs 'ADC3 ChMap' SWRM_TX3_CH1; cs 'TX2 MODE' ADC_LP; cs 'ADC3_MIXER Switch' 1; cs 'AMIC3_MIXER Switch' 1; cs 'TX_DEC5 Volume' 102
}
estereo_vendor() {
	common
	cs 'TX DEC1 MUX' SWR_MIC; cs 'TX SMIC MUX1' SWR_MIC4; cs 'TX_AIF1_CAP Mixer DEC1' 1; cs 'ADC1 MUX' CH1_AMIC1; cs 'ADC1 ChMap' SWRM_TX2_CH1; cs 'TX0 MODE' ADC_LP; cs 'ADC1 Volume' 8
	cs 'TX DEC3 MUX' SWR_MIC; cs 'TX SMIC MUX3' SWR_MIC9; cs 'TX_AIF1_CAP Mixer DEC3' 1; cs 'ADC4 MUX' CH4_AMIC5; cs 'ADC4 ChMap' SWRM_TX3_CH2; cs 'TX3 MODE' ADC_LP
}
dual() { # dual A B: canal 0 = AMICA por ADC1/DEC0/SWR_MIC0; canal 1 = AMICB por ADC2/DEC1/SWR_MIC1 (SWR_INPUT0/1 = ADC1/2_OUTPUT con qcom,tx-port-mapping <2 2 3 4>); AMICn 1..5 (ADC2 admite 1..5 como ADC1)
	common
	cs 'ADC1_MIXER Switch' 1; cs 'ADC1 MUX' "CH1_AMIC$1"; cs 'ADC1 Switch' 1; cs 'ADC1 Volume' 10; cs 'TX0 MODE' ADC_ULP
	cs 'TX DEC0 MUX' SWR_MIC; cs 'TX SMIC MUX0' SWR_MIC0; cs 'TX_AIF1_CAP Mixer DEC0' 1; cs 'TX_DEC0 Volume' 100
	cs 'ADC2_MIXER Switch' 1; cs 'ADC2 MUX' "CH2_AMIC$2"; cs 'ADC2 Switch' 1; cs 'ADC2 Volume' 10; cs 'TX1 MODE' ADC_ULP
	cs 'TX DEC1 MUX' SWR_MIC; cs 'TX SMIC MUX1' SWR_MIC1; cs 'TX_AIF1_CAP Mixer DEC1' 1; cs 'TX_DEC1 Volume' 100
}
off() {
	for n in 1 2 3 4; do cs "ADC$n MUX" "CH${n}_AMIC_DISABLE"; cs "ADC$n Switch" 0; done
	for n in 0 1 2 3 4 5 6 7; do cs "TX SMIC MUX$n" ZERO; cs "TX_AIF1_CAP Mixer DEC$n" 0; done
	cs 'MultiMedia3 Mixer TX_CODEC_DMA_TX_3' 0
}
case "${1:-}" in
	--list) $A -c "$CARD" controls | grep -E "TX DEC|TX SMIC|TX_DEC|TX_AIF1|ADC[0-9]|AMIC|MIC BIAS|MultiMedia3|TX[0-9] MODE|SWR" ;;
	--dry|--apply) MODE=${1#--}; case "${2:-}" in dual-[1-5]-[1-5]) d=${2#dual-}; dual "${d%-*}" "${d#*-}";; amic1) amic_qrd 1;; amic2) amic_qrd 2;; amic3) amic_qrd 3;; amic4) amic_qrd 4;; amic5) amic_qrd 5;; amic3-vendor) amic3_vendor;; estereo-vendor) estereo_vendor;; *) echo "uso: $0 $1 amic1|amic2|amic3|amic4|amic5|amic3-vendor|estereo-vendor" >&2; exit 1;; esac ;;
	--off) MODE=apply; off ;;
	*) echo "uso: $0 --list | --dry MIC | --apply MIC | --off" >&2; exit 1 ;;
esac
