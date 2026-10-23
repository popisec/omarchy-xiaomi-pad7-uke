// SPDX-License-Identifier: GPL-2.0
/* M0 micro: tarjeta combinada UKE = altavoces TDM (FS19xx) + captura WCD. ALTERNATIVA a uke_audio_e8b: descargar e8b antes. Ver dts/uke-audio-e9a-card-fs19xx-wcd-capture.dtso. */
#define UKE_OVL_NAME "uke_audio_e9a"
#define UKE_OVL_DESC "uke: overlay de DT de audio E9a (tarjeta TDM + FS19xx + captura WCD)"
#define UKE_OVL_REFUSE_IF_PATH "/sound"
#include "uke-ovl.h"
