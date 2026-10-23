# AUDIO — E2b: cómo se arranca el PD de audio (investigación en el PC; la tablet solo se leyó) — 18-oct-2026

Alcance: solo lectura (capturas de Android del repo, fuentes del kernel senemos, `/proc/device-tree` de la tablet, README/fuentes públicas de `quic/fastrpc`). No se tocó el ADSP.

## 1. Hallazgo: la hipótesis H-E2a queda **fuertemente apoyada**
- `build/android/coldboot-20261017/logcat-30s.txt:2093`: el demonio de Android hace
  `remote_handle_open: Successfully opened handle … for '":;./\createstaticpd:audiopd on domain 0` → **`audioadsprpcd audiopd` ejecuta `createstaticpd:audiopd` por FastRPC: crea en el ADSP el PD estático «audiopd»**, y luego registra el listener `adsp_default_listener` (servidor `apps_std` de ficheros, línea 2176) y el `geteventfd`.
  Antes (líneas 1971-1999) reintenta cada 25 ms mientras «fastRPC device driver is disabled». `.rc` de Android: se lanza en `early-init` (`vendor.qti.audio-adsprpc-service.rc`).
- Cronología del dmesg de Android (`cosecha-20261017/01-dmesg.txt:8155-8205`): ADSP up 6,921 → `gpr_send_pkt: q6 state is down` (6,943) → `audioadsprpcd` 6,972 + PDR `audio_pd` UP 6,971 → **APM responde a 6,993**.
- En la tablet nadie crea ese PD: el `audio_pd` solo lo anuncia «UP» el pd-mapper del kernel (parche 0028), y E2 vio el `CMD timeout` del `APM_CMD_GET_SPF_STATE` (AUDIO-E2-20261018.md). **Corrige el plan §7.2** (que inferían que `audioadsprpcd` no hacía falta).
- Matiz honesto: que el APM viva *dentro* de ese PD es inferencia; la prueba definitiva es el experimento E2b (ver §4).

## 2. Qué exige hacer lo mismo en Linux (todo LECTURA salvo marca)
Kernel (mainline `drivers/misc/fastrpc.c`, módulo `fastrpc.ko` presente en ouke3, hoy sin cargar; sin `/dev/fastrpc*`):
1. **Nodo DT** `qcom,fastrpc` bajo `glink-edge` (plantilla `sm8650.dtsi:4505-4562`): `label="adsp"`, `qcom,glink-channels="fastrpcglink-apps-dsp"`, `qcom,non-secure-domain`, `memory-region`, `qcom,vmids` y `compute-cb@N`.
   El nodo vendor existente `qcom,msm_fastrpc_rpmsg` (compat `qcom,msm-fastrpc-rpmsg`, canal `fastrpcglink-apps-dsp`, ya creado como rpmsg device sin driver) **no casa** con `qcom,fastrpc`: habría que cambiarle `compatible` y añadirle propiedades por overlay (INFERIDO viable; el probe del rpmsg lee propiedades en vivo).
2. **Heap remoto**: `FASTRPC_IOCTL_INIT_CREATE_STATIC` (`fastrpc.c:1385-1430`) pasa al ADSP `remote_heap` y, si hay `qcom,vmids`, hace `qcom_scm_assign_mem` de esa región a los VMID. Android usa `adsp_heap_region` (12 MiB, alineada 4 MiB, `shared-dma-pool`, presente en el DT vivo de la tablet) y `qcom,adsp-remoteheap-vmid = <22 37>`. **Riesgo**: reasignar memoria a VMIDs seguros con parámetros equivocados = violación XPU/pérdida de la región (cuelgue). Es lo más delicado.
3. **Compute-CBs y SMMU**: sin al menos un `compute-cb` el driver no abre sesión. Los de ADSP en Android (cb10-14) usan SIDs `0x1003/0x80+0x1043/0x20`, `0x1004/0x80+0x1044/0x20`, `0x1005…`, `0x1006…`, `0x1007/0x40+0x1067+0x1087`. `qcom_uke_smmu_alloc_context_bank()` (`arm-smmu-qcom.c:816-841`) **rechaza cualquier SID fuera de su lista blanca** ⇒ **flash obligatorio** (parche nuevo tipo 0002, con la misma lógica que ya hay para el audio de E4). No hay camino en caliente.
4. `pd-mapper`/PDR: tras crear el PD, el PDR real de `audio_pd` debería seguir; E2 ya mostró que `apr` registra `q6apm` al primer UP.
Userspace: `quic/fastrpc` (BSD-3, `src/dsprpcd.c`: `adsprpcd`, build `USE_ADSP`; el help menciona `audiopd`; el demonio carga `libadsp_default_listener.so`; reintenta cada 100 ms; sale solo con `AEE_ECONNREFUSED`/`ENOMEM`). **No hay paquete** (`pacman -Ss fastrpc` vacío): se compila (autotools) y se instala con `libadsp_default_listener`. La necesidad de las libs Hexagon de `/vendor/dsp` (`dsp_b`) en el listener es **desconocida**: en Android el listener solo sirvió `sns_tppe.so` para sensores en esta captura; para audio no se vio ninguna. NO VERIFICADO.

## 3. Evaluación
| Pieza | ¿Flash? | Riesgo | Notas |
|---|---|---|---|
| Parche SMMU para SIDs de los compute-cb del ADSP (`0x1003…0x1087`) | **sí** (1 ciclo) | medio (arranque en `panic` si se rompe `uke-abl.c`; este parche es solo de `arm-smmu-qcom.c`) | se puede unir al de E4 (`0x801001`, `0x1061`) en **un solo flash** |
| Overlay `fastrpc` + `adsp_heap_region` + vmids | no | **alto**: `qcom_scm_assign_mem` a VMIDs 22/37 | probar primero **sin `qcom,vmids`** (el código lo permite: `vmcount=0` salta el assign, `fastrpc.c:1385`) — el ADSP quizá acepte el heap sin VMID, INFERIDO |
| Compilar/instalar `adsprpcd` | no | nulo (PC/rootfs) | cruzado o en la tablet |
| Ejecutar `adsprpcd audiopd` | no | alto (primer DMA FastRPC + posible fallo del ADSP) | con vigía, E2' demostró recuperación ~2 s |

## 4. Plan E2b propuesto (cada paso con riesgo pide autorización)
1. **PC, sin riesgo** (puedo hacerlo ya): parche `0004-arm-smmu-qcom-fastrpc-adsp-sids.patch` (lista blanca + arnés), overlay `uke-audio-e2b-fastrpc.dtso` (sin `qcom,vmids` en la primera prueba), compilar `quic/fastrpc` aarch64 y empaquetarlo, módulo cargador `uke_audio_e2b`.
2. **Flash** de un `boot` nuevo con 0004 (+0002 de E4 si el dueño quiere un solo flash): fila de ledger #… pre-registrada, sha, gates (≥3700 mV, ≤2 escrituras/día, fastboot manual del dueño, consola armada).
3. En caliente: overlay → `modprobe fastrpc` → `adsprpcd audiopd` con vigía. Éxito = PDR/`q6apm` responde (`apm is up` / `APM_CMD_RSP_GET_SPF_STATE`).
4. Si falla: techo 3 ciclos y nota «refutada»; rollback por `rmmod`/`stop-start`; boot anterior en el slot b/backup.
Ciclos de hipótesis H-E2a gastados: 1/3.

## 5. Alternativa sin flash a considerar
Ninguna para el PD (SIDs). La salida de sonido inmediata sigue siendo A2DP (línea BT, ya funciona). Mientras tanto no hay riesgo para la tablet.
