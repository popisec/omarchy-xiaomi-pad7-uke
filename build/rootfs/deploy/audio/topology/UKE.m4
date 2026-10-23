# SPDX-License-Identifier: BSD-3-Clause
# Topologia AudioReach de la Xiaomi Pad 7 «uke» (SM7675 = cliffs ≙ sm8650). ESBOZO DE E0, 18-oct-2026.
#
# DERIVADA DE SM8550-HDK.m4 (linux-msm/audioreach-topology, commit 35e482d209ec, Linaro Ltd 2023, BSD-3-Clause),
# que es EXACTAMENTE el fuente con el que el CMakeLists upstream genera qcom/sm8650/SM8650-{QRD,MTP,HDK}-tplg.bin
# (comprobado 18-oct: no hay .m4 propio de sm8650, el informe AUDIO-SENEMOS §3.3.6 lo daba por inexistente y
# la linea "SM8550-HDK;SM8650-QRD;qcom/sm8650" de su CMakeLists lo desmiente).
# Nombre del fichero en la tablet: /lib/firmware/qcom/sm8650/UKE-tplg.bin
#   (topology.c:1320 => qcom/<driver_name>/<card->name>-tplg.bin; driver_name "sm8650" por el compat
#    qcom,sm8650-sndcard y card->name = `model = "UKE"` del DT, ver dts/uke-audio-e5-card.dtso).
#
# CAMBIOS RESPECTO A SM8550-HDK.m4 (todo lo demas es identico, incluidos los IIDs de los subgrafos conservados,
# para que `diff` de los .conf generados sea legible):
#   - SIN WSA_CODEC_DMA_RX_0: la uke no tiene WSA (qcom,wsa-max-devs = 0; amplificadores FS19xx por TDM).
#   - SIN DISPLAY_PORT_RX_0 ni MultiMedia6: sin nodos DP de audio en el DT; se anadiran con la etapa de DP.
#   - Se conservan: MultiMedia1/2 (reproduccion), 3/4 (captura), 5 (compress), RX_CODEC_DMA_RX_0 (WCD, E6),
#     TX_CODEC_DMA_TX_3 (WCD/DMIC por SWR TX, E5), VA_CODEC_DMA_TX_0 (DMIC por el macro VA) y PRIMARY_MI2S_RX
#     (candidato a "sumidero sin cableado conocido" de la etapa E4; la tarjeta del DT NO tiene enlace a el).
#
# QUE NO HAY (y por que esta topologia no vale para los altavoces):
#   - TDM. Los 4 altavoces cuelgan de TDM1 del LPAIF_VA (TDM-LPAIF_VA-RX-PRIMARY, 4 canales, 48 kHz, 32 bit:
#     odm-resourcemanager_cliffs_mtp.xml:821-834). Ni audioreach/*.m4 tiene subgrafo/modulo TDM ni
#     sound/soc/qcom/qdsp6/audioreach.c lo implementa (`grep -i tdm` vacio). Los parametros del modulo TDM
#     (interfaz, slots, indices) solo estan en el ACDB `Forte` del vendor (odm_b dentro de `super`), sin extraer.
#     Eso es la etapa E7; aqui solo hay un hueco documentado (abajo).
#   - Nada de proteccion de altavoz (FSADSP del vendor) ni efectos Misound.
#
# Compilar:  m4 -I topology/src topology/UKE.m4 > UKE.conf && alsatplg -c UKE.conf -o UKE-tplg.bin
# (build.sh lo hace y comprueba que el .bin se redecodifica). Los avisos de `alsatplg` «undefined sink/source
# widget/stream 'X Playback/Capture'» son NORMALES: esos widgets los crean los DAIs de q6apm-lpass-dais en el
# kernel (los mismos avisos salen con el SM8550-HDK.m4 upstream sin tocar).
include(`audioreach/audioreach.m4')
include(`audioreach/stream-subgraph.m4')
include(`audioreach/device-subgraph.m4')
include(`util/route.m4')
include(`util/mixer.m4')
include(`audioreach/tokens.m4')
#
# Stream SubGraph  for MultiMedia Playback
#
#  ______________________________________________
# |               Sub Graph 1                    |
# | [WR_SH] -> [PCM DEC] -> [PCM CONV] -> [LOG]  |- Kcontrol
# |______________________________________________|
#
dnl UKE_CH (18-oct-2026): canales de MultiMedia1 y del backend TDM del altavoz. Defecto 2 (build normal); m4 -DUKE_CH=4 genera UKE-tplg-4ch.bin
dnl   (diagnostico del mapa canal->slot->altavoz de los 4 FS19xx). Las demas rutas no cambian.
ifdef(`UKE_CH',,`define(`UKE_CH', 2)')dnl
dnl UKE_FMT: formato PCM de MultiMedia1 y del backend TDM (defecto S16_LE; -DUKE_FMT=S32_LE genera UKE-tplg-s32.bin: dato de 32 bit como Android)
ifdef(`UKE_FMT',,`define(`UKE_FMT', `S16_LE')')dnl
dnl Playback MultiMedia1
STREAM_SG_PCM_ADD(audioreach/subgraph-stream-vol-playback.m4, FRONTEND_DAI_MULTIMEDIA1,
	UKE_FMT, 48000, 48000, UKE_CH, UKE_CH,
	0x00004001, 0x00004001, 0x00006001, `110000')
dnl Playback MultiMedia2
STREAM_SG_PCM_ADD(audioreach/subgraph-stream-vol-playback.m4, FRONTEND_DAI_MULTIMEDIA2,
	`S16_LE', 48000, 48000, 2, 2,
	0x00004002, 0x00004002, 0x00006010, `110000')
dnl Capture MultiMedia3
STREAM_SG_PCM_ADD(audioreach/subgraph-stream-capture.m4, FRONTEND_DAI_MULTIMEDIA3,
	`S16_LE', 48000, 48000, 1, 2,
	0x00004003, 0x00004003, 0x00006020, `110000')
dnl Capture MultiMedia4
STREAM_SG_PCM_ADD(audioreach/subgraph-stream-capture.m4, FRONTEND_DAI_MULTIMEDIA4,
	`S16_LE', 48000, 48000, 1, 2,
	0x00004004, 0x00004004, 0x00006030, `110000')
dnl Playback MultiMedia5
STREAM_SG_PCM_ADD(audioreach/subgraph-compress-stream-vol-playback.m4, FRONTEND_DAI_MULTIMEDIA5,
	`S16_LE', 48000, 48000, 2, 2,
	0x0000400a, 0x0000400a, 0x00006040, `110000')
dnl (HDK: MultiMedia6 para DisplayPort RX 0 -- quitado, ver cabecera)
#
#
# Device SubGraphs
#
#         ___________________
#        |   Sub Graph 2     |
# Mixer -| [LOG] -> [EP]     |
#        |___________________|
#
dnl DEVICE_SG_ADD(stream, stream-dai-id, stream-index,
dnl 	format, min-rate, max-rate, min-channels, max-channels,
dnl	interface-type, interface-index, data-format,
dnl	sg-iid-start, cont-iid-start, mod-iid-start
dnl (HDK: WSA_CODEC_DMA_RX_0 con IIDs 0x4005/0x4005/0x6050 -- quitado, ver cabecera)
dnl
dnl Primary MI2S Playback  [E4: candidato a sumidero sin cableado conocido; sin enlace en la tarjeta]
DEVICE_SG_ADD(audioreach/subgraph-device-i2s-playback.m4, `Primary', PRIMARY_MI2S_RX,
	`S16_LE', 48000, 48000, 2, 2,
	LPAIF_INTF_TYPE_LPAIF, I2S_INTF_TYPE_PRIMARY, SD_LINE_IDX_I2S_SD0, DATA_FORMAT_FIXED_POINT,
	0x00004006, 0x00004006, 0x00006060, `PRIMARY_MI2S_RX')
dnl
dnl WCDRX Playback  [E6: CODEC_DMA RX0 -> rx-macro -> SWR RX -> WCD9395]
DEVICE_SG_ADD(audioreach/subgraph-device-codec-dma-playback.m4, `RX_CODEC_DMA_RX_0', RX_CODEC_DMA_RX_0,
	`S16_LE', 48000, 48000, 2, 2,
	LPAIF_INTF_TYPE_RXTX, CODEC_INTF_IDX_RX0, 0, DATA_FORMAT_FIXED_POINT,
	0x00004007, 0x00004007, 0x00006070)
dnl
dnl VA Capture  [DMIC por el macro VA; pines por resolver]
DEVICE_SG_ADD(audioreach/subgraph-device-codec-dma-capture.m4, `VA_CODEC_DMA_TX_0', VA_CODEC_DMA_TX_0,
	`S16_LE', 48000, 48000, 1, 2,
	LPAIF_INTF_TYPE_VA, CODEC_INTF_IDX_TX0, 0, DATA_FORMAT_FIXED_POINT,
	0x00004008, 0x00004008, 0x00006080)
dnl
dnl WCDTX Capture  [E5: CODEC_DMA TX3 <- tx-macro <- SWR TX <- WCD9395 (+ ruta `handset-mic` del vendor, DEC2/TX_AIF1_CAP)]
DEVICE_SG_ADD(audioreach/subgraph-device-codec-dma-capture.m4, `TX_CODEC_DMA_TX_3', TX_CODEC_DMA_TX_3,
	`S16_LE', 48000, 48000, 1, 2,
	LPAIF_INTF_TYPE_RXTX, CODEC_INTF_IDX_TX3, 0, DATA_FORMAT_FIXED_POINT,
	0x00004009, 0x00004009, 0x00006090)
dnl
dnl (HDK: DISPLAY_PORT_RX_0 con IIDs 0x4010/0x4010/0x60B0 -- quitado, ver cabecera)
dnl
dnl E7a (18-oct-2026): TDM1 de LPAIF_VA = backend TDM-LPAIF_VA-RX-PRIMARY de los 4 FS19xx. Subgrafo [LOG -> TDM_SINK 0x0700100E] con los
dnl   IDs/parametros del ACDB Forte (AUDIO-ACDB-20261018.md); el kernel (parche 0006) envia TDM_INTF_CFG (4 slots x 32 bit, slot_mask = (1<<canales)-1,
dnl   sync interna, short-sync-bit, retraso 1 BCLK) + HW_EP_MF_CFG + FRAME_SIZE_FACTOR. DAI: PRIMARY_TDM_RX_0 = "Primary TDM0 Playback".
dnl   Fuentes en topology/uke/ (derivadas de module_i2s.m4 / subgraph-device-i2s-playback.m4, BSD-3-Clause, Linaro).
dnl UKE_CHAIN=1 (m4 -DUKE_CHAIN=1 -> UKE-tplg-chain.bin): subgrafo de dispositivo TDM con MFC -> SAL -> LOG -> TDM_SINK (cadena del ACDB de Android); defecto: LOG -> TDM_SINK
DEVICE_SG_ADD(ifdef(`UKE_CHAIN', `subgraph-device-tdm-playback-chain.m4', `subgraph-device-tdm-playback.m4'), `Primary TDM0', PRIMARY_TDM_RX_0,
	UKE_FMT, 48000, 48000, UKE_CH, UKE_CH,
	LPAIF_INTF_TYPE_VA, I2S_INTF_TYPE_PRIMARY, 0, DATA_FORMAT_FIXED_POINT,
	0x00004011, 0x00004011, 0x000060C0, `PRIMARY_TDM_RX_0')

STREAM_DEVICE_PLAYBACK_MIXER(PRIMARY_MI2S_RX, ``PRIMARY_MI2S_RX'', ``MultiMedia1'', ``MultiMedia2'', ``MultiMedia5'')
STREAM_DEVICE_PLAYBACK_MIXER(PRIMARY_TDM_RX_0, ``PRIMARY_TDM_RX_0'', ``MultiMedia1'', ``MultiMedia2'', ``MultiMedia5'')
STREAM_DEVICE_PLAYBACK_MIXER(RX_CODEC_DMA_RX_0, ``RX_CODEC_DMA_RX_0'', ``MultiMedia1'', ``MultiMedia2'', ``MultiMedia5'')

STREAM_DEVICE_PLAYBACK_ROUTE(PRIMARY_MI2S_RX, ``PRIMARY_MI2S_RX Audio Mixer'', ``MultiMedia1, stream0.logger1'', ``MultiMedia2, stream1.logger1'', ``MultiMedia5, stream4.logger1'')
STREAM_DEVICE_PLAYBACK_ROUTE(PRIMARY_TDM_RX_0, ``PRIMARY_TDM_RX_0 Audio Mixer'', ``MultiMedia1, stream0.logger1'', ``MultiMedia2, stream1.logger1'', ``MultiMedia5, stream4.logger1'')
STREAM_DEVICE_PLAYBACK_ROUTE(RX_CODEC_DMA_RX_0, ``RX_CODEC_DMA_RX_0 Audio Mixer'', ``MultiMedia1, stream0.logger1'', ``MultiMedia2, stream1.logger1'', ``MultiMedia5, stream4.logger1'')

dnl STREAM_DEVICE_CAPTURE_MIXER(stream-index, kcontro1, kcontrol2... kcontrolN)
STREAM_DEVICE_CAPTURE_MIXER(FRONTEND_DAI_MULTIMEDIA3, ``VA_CODEC_DMA_TX_0'',``TX_CODEC_DMA_TX_3'' )
STREAM_DEVICE_CAPTURE_MIXER(FRONTEND_DAI_MULTIMEDIA4, ``VA_CODEC_DMA_TX_0'',``TX_CODEC_DMA_TX_3'' )
dnl STREAM_DEVICE_CAPTURE_ROUTE(stream-index, mixer-name, route1, route2.. routeN)
STREAM_DEVICE_CAPTURE_ROUTE(FRONTEND_DAI_MULTIMEDIA3, ``MultiMedia3 Mixer'', ``VA_CODEC_DMA_TX_0, device110.logger1'', ``TX_CODEC_DMA_TX_3, device120.logger1'')
STREAM_DEVICE_CAPTURE_ROUTE(FRONTEND_DAI_MULTIMEDIA4, ``MultiMedia4 Mixer'', ``VA_CODEC_DMA_TX_0, device110.logger1'', ``TX_CODEC_DMA_TX_3, device120.logger1'')
