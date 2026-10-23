// SPDX-License-Identifier: GPL-2.0
/* E8a: tarjeta TDM con el codec real uke_fs19xx, sin pines. Ver dts/uke-audio-e8a-card-fs19xx.dtso. */
#define UKE_OVL_NAME "uke_audio_e8a"
#define UKE_OVL_DESC "uke: overlay de DT de audio E8a (tarjeta TDM + FS19xx, sin pines)"
#define UKE_OVL_REFUSE_IF_PATH "/sound"
#include "uke-ovl.h"
