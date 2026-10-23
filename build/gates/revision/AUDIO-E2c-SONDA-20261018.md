# AUDIO — sonda spf_core: **EL APM RESPONDE con src_port 3** — 18-oct-2026 15:47

Autorizado por el dueño. Gate: 3898 mV, Charging, ADSP/WPSS running; vigía + `ssh dmesg -w` + lector ACM; `dmesg -n 7`. Kernel v4 (ouke4). Logs: `build/logs/audio/spf-20261018-*.log`.
Procedimiento: `modprobe apr` **sin** overlay e2 (solo los servicios vendor `spf_core:2:3`, `audio-pkt:2:17`, `q6prm:2:7`); `insmod uke_spfcore_probe.ko cmdhdr=1`; rmmod; `insmod … cmdhdr=0`.

## Resultado (MEDIDO)
| Variante | Resultado |
|---|---|
| `cmdhdr=1`, **src_port=3** (spf_core), dest APM=1 | `gpr_send_pkt rc=40` → **RX 0,8 ms después: `src=2:1 dest=3:3 opcode=0x02001007 (APM_CMD_RSP_GET_SPF_STATE) payload w0=0x00000001`** → el APM está listo (estado 1) |
| `cmdhdr=0`, src_port=3 | `rc=24`, **sin respuesta** en 5 s (0 paquetes) |
| (E2/E2b/E2c) `cmdhdr=1`, **src_port=1** (q6apm mainline) | `CMD timeout` ×3 |
Reversa: rmmod sonda y `apr`; ADSP running, Charging, wlan0 UP, sin faults. (Quedan cargados `fastrpc` (refcnt colgado) y `uke_bt_b`, ajenos.)

## Conclusión
**H-GPR-src CONFIRMADA** (con el matiz de lo medido: la combinación que funciona es src_port 3 + cabecera `apm_cmd_header`; src_port 1 + cabecera falla; sin cabecera falla). El SPF del ADSP de Xiaomi solo contesta a los puertos de origen que su gpr-lite registra (3 spf_core, 7 prm, 0x17 audio-pkt) — o no enruta el 1. **No hacía falta FastRPC ni heap ni PD: los 3 ciclos anteriores estaban mal dirigidos** (el PD ya estaba UP; ver DIAGNOSTICO §1). Ciclo de esta hipótesis: 1 (con éxito).

## Camino a los altavoces (siguiente, todo SIN flash salvo lo indicado)
1. **Parche de `snd-q6apm` (módulo, no flash):** `audioreach_alloc_apm_cmd_pkt()`/`apm_pkt` usan `GPR_APM_MODULE_IID` fijo como src_port (`audioreach.c:290`); usar el `svc_id` del dispositivo GPR de q6apm. Overlay: `service@3 qcom,q6apm` **y retirar el `spf_core` vendor** (mismo id 3) con `status="disabled"` (o reg propio si el firmware acepta más puertos: probar reg=3,7,0x17 u otros). Análogo para q6prm (vendor `q6prm` reg 7 `qcom,audio_prm`): src_port 7.
2. Recompilar `snd-q6apm.ko`/`q6prm.ko` contra ouke4 (módulos externos con el fuente parcheado) y repetir E2 para ver `apm is up` y el probe de q6prm/q6apm.
3. Luego E3 (relojes PRM/LPI), E4 (DAIs con SMMU 0x801001/0x1061: ya admitidos en v4), E5–E7 según el plan (TDM de los altavoces y driver FS19xx siguen siendo el trabajo grande).
Pendiente de decidir con el dueño: el parche se hace como **módulo externo** (`uke-q6apm`) o como parche del árbol con `reg` por DT.
