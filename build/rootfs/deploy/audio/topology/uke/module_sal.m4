# uke (19-oct-2026), derivado de audioreach/module_mfc.m4 (Linaro, BSD-3-Clause): modulo SAL de AudioReach (0x07001010).
# Copyright, Linaro Ltd, 2021-2024
# SPDX-License-Identifier: BSD-3-Clause
# El kernel (audioreach_sal_set_media_format) le envia PARAM_ID_SAL_OUTPUT_CFG con el ancho de bit de salida; no lleva mas tokens que el MFC.
include(`util/util.m4') dnl
define(`MODULE_ID_SAL', `0x07001010') dnl
dnl AR_MODULE_SAL(index, sgidx, container-idx, iid, maxip-ports, max-op-ports, src-port, dst-port, dst-iid)
define(`AR_MODULE_SAL',
`'
`SectionVendorTuples."NAME_PREFIX.sal$1_tuples" {'
`        tokens "audioreach_tokens"'
`'
`        tuples."word.u32_data" {'
`                AR_TKN_U32_MODULE_INSTANCE_ID STR($4)'
`                AR_TKN_U32_MODULE_ID STR(MODULE_ID_SAL)'
`                AR_TKN_U32_MODULE_MAX_IP_PORTS STR($5)'
`                AR_TKN_U32_MODULE_MAX_OP_PORTS STR($6)'
`                AR_TKN_U32_MODULE_SRC_OP_PORT_ID STR($7)'
`                AR_TKN_U32_MODULE_DST_IN_PORT_ID STR($8)'
`                AR_TKN_U32_MODULE_SRC_INSTANCE_ID STR($4)'
`                AR_TKN_U32_MODULE_DST_INSTANCE_ID STR($9)'
`        }'
`}'
`'
`SectionData."NAME_PREFIX.sal$1_data" {'
`        tuples "NAME_PREFIX.sal$1_tuples"'
`}'
`'
`SectionWidget."NAME_PREFIX.sal$1" {'
`        index STR($1)'
`        type "src"'
`        no_pm "true"'
`        subseq "10"'
`        data ['
`                "NAME_PREFIX.sub_graph$2_data"'
`                "NAME_PREFIX.container$3_data"'
`                "NAME_PREFIX.sal$1_data"'
`        ]'
`}') dnl
