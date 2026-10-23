// SPDX-License-Identifier: GPL-2.0
/* E4c: tarjeta minima (backend PRIMARY_MI2S_RX + codec spdif-dit ficticio). Requiere e2d, e4a, e4b. Ver dts/uke-audio-e4c-card.dtso. */
#define UKE_OVL_NAME "uke_audio_e4c"
#define UKE_OVL_DESC "uke: overlay de DT de audio E4c (tarjeta minima, primera DMA)"
#define UKE_OVL_REFUSE_IF_PATH "/sound"
#include "uke-ovl.h"
