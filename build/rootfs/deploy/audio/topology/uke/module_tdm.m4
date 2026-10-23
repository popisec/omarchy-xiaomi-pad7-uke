# uke (18-oct-2026), derivado de audioreach/module_i2s.m4 (Linaro, BSD-3-Clause): modulo TDM de AudioReach
# Copyright, Linaro Ltd, 2021-2024
# SPDX-License-Identifier: BSD-3-Clause
# (MODULE_ID_TDM_SINK/SOURCE, pcm_tdm_api.h de AudioReach graph services). El kernel (parche 0006) lo carga con los MISMOS tokens que I2S.
include(`util/util.m4') dnl
define(`MODULE_ID_TDM_SINK', `0x0700100E') dnl
define(`MODULE_ID_TDM_SOURCE', `0x0700100F') dnl
dnl AR_MODULE_TDM_RX(index, sgidx, container-idx, iid, maxip-ports, max-op-ports, src-port, dst-port,
dnl hw-if-type, hw-if-idx, fmt, sd-line-idx, dev-name, dst-iid)
define(`AR_MODULE_TDM_RX',
`'
`SectionVendorTuples."NAME_PREFIX.tdm_rx$1_tuples" {'
`        tokens "audioreach_tokens"'
`'
`        tuples."word.u32_data" {'
`                AR_TKN_U32_MODULE_INSTANCE_ID STR($4)'
`                AR_TKN_U32_MODULE_ID STR(MODULE_ID_TDM_SINK)'
`                AR_TKN_U32_MODULE_MAX_IP_PORTS STR($5)'
`                AR_TKN_U32_MODULE_MAX_OP_PORTS STR($6)'
`                AR_TKN_U32_MODULE_SRC_OP_PORT_ID STR($7)'
`                AR_TKN_U32_MODULE_DST_IN_PORT_ID STR($8)'
`                AR_TKN_U32_MODULE_SRC_INSTANCE_ID STR($4)'
`                AR_TKN_U32_MODULE_DST_INSTANCE_ID STR($14)'
`                AR_TKN_U32_MODULE_HW_IF_TYPE STR($9)'
`                AR_TKN_U32_MODULE_HW_IF_IDX STR($10)'
`                AR_TKN_U32_MODULE_FMT_DATA STR($11)'
`                AR_TKN_U32_MODULE_SD_LINE_IDX STR($12)'
`        }'
`}'
`'
`SectionData."NAME_PREFIX.tdm_rx$1_data" {'
`        tuples "NAME_PREFIX.tdm_rx$1_tuples"'
`}'
`'
`SectionWidget."NAME_PREFIX.tdm_rx$1" {'
`        index STR($1)'
`        type "aif_in"'
`        no_pm "true"'
`        stream_name "$13 Playback"'
`        subseq "10"'
`        data ['
`                "NAME_PREFIX.sub_graph$2_data"'
`                "NAME_PREFIX.container$3_data"'
`                "NAME_PREFIX.tdm_rx$1_data"'
`        ]'
`}') dnl
