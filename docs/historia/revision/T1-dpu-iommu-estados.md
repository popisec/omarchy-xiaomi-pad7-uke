# T1 — Revisión dpu/IOMMU: -22 (K12) → -19 (K13) → recomendación K14

Fecha: 30-sep-2026 · Revisor: T1 (sin tablet; solo código, diffs y logs en disco).
Árbol: `/var/tmp/uke-k13-tree/` (7.2-rc2 + K1-K13). Patches: `build/gates/patches/`.
Consola: `~/proyectos/out/uke-k13-console.log` · Bind exitoso de referencia: `build/gates/k10-bind-exitoso-dmesg.log`.
DT fusionado: `/var/tmp/k8-check/merged.dtb` (base + payload-s258, 29-sep — OJO: es ANTERIOR al s260; lo uso para el mdss padre y los nodos vendor, y verifico el s260 aparte).

---

## 0. Veredicto ejecutivo

1. El **-22 de K12 está verificado al nivel de instrucción**: `iommu_attach_device()` devuelve -EINVAL porque el grupo del dpu tiene ≠1 dispositivo — `drivers/iommu/iommu.c:2205-2207`, ANTES de `attach_dev` (por eso K12 no tuvo migas "CB reservado").
2. **CORRECCIÓN al dato del orquestador**: el grupo no es de 2, es de **≥3**. Además de mdss padre (s231) y display-controller (s260), el nodo vendor legacy **`soc:qcom,smmu_sde_unsec_cb` lleva LA MISMA banda `iommus = <0x129 0x1c00 0x02>`** (merged.dts línea 27135), no tiene driver en el árbol, y aun así entra al grupo durante el pase de bind del SMMU (medido: k10 log línea 3170, "Adding to iommu group 6").
3. **El -19 de "K13" NUNCA EXISTIÓ**: ambos `-19` de la consola (13,973 / 14,019 s) pertenecen a boots del kernel **#82 stock (26-sep)** — el banner lo demuestra (líneas 1 y 12420 de la captura). El kernel K13 (#17, 30-sep 12:11) jamás llegó al DPU en esa captura: sus 14+ boots mueren con la consola a ~0,05 s (patrón wedge CM3 persistente); solo se ve el texto crudo del arming del initramfs (~4 s) flushed del buffer del gadget. La inferencia "el fallback attach_group cambia la visibilidad del IOMMU" queda **refutada por la evidencia del banner**.
4. **K14 recomendado (único cambio, sin recompilar)**: **s261' = dtbo que borra `iommus` de `/soc/display-subsystem@ae00000` Y de `/soc/qcom,smmu_sde_unsec_cb`**, dejando el display-controller como único dueño de `0x1c00/0x2` → grupo de 1 → `iommu_attach_device` pasa con el **kernel K12 tal cual ya construido**. La s261 original (solo mdss) NO basta: quedaría grupo de 2 (unsec_cb + dpu) y el -22 persistiría.

---

## 1. Traza del -22 de K12 (verificada, file:line)

```
dpu_kms_hw_init                     disp/dpu1/dpu_kms.c:1181   rc=_dpu_kms_mmu_init()
_dpu_kms_mmu_init                   disp/dpu1/dpu_kms.c:1109   msm_kms_init_vm(dev, dev->dev->parent)
msm_kms_init_vm                     msm/msm_kms.c:180
  device_iommu_mapped(mdp_dev)      include/linux/device.h:916 = (dev->iommu_group != NULL)
  → iommu_dev = mdp_dev (ae01000)   msm/msm_kms.c:193-194      (mdss_dev tb mapeado, da igual: mdp tiene prioridad)
msm_iommu_disp_new                  msm/msm_iommu.c:807
msm_iommu_new                       msm/msm_iommu.c:732
  device_iommu_mapped ok            msm/msm_iommu.c:738        (el grupo EXISTE; no es -19)
  iommu_paging_domain_alloc         msm/msm_iommu.c:741
  iommu_attach_device(domain, dev)  msm/msm_iommu.c:758
    group = dev->iommu_group        drivers/iommu/iommu.c:2194
    mutex_lock(group->mutex)        iommu.c:2204
    ret = -EINVAL                   iommu.c:2205
    if (list_count_nodes(&group->devices) != 1)   iommu.c:2206  ← **AQUÍ MUERE: grupo con 3 dispositivos**
      goto out_unlock               iommu.c:2207               (NUNCA llega a __iommu_attach_group ni a attach_dev)
  ret=-22 → free domain, ERR_PTR    msm/msm_iommu.c:798-801
"dpu_kms_mmu_init failed: -22"      dpu_kms.c:1183
```

Confirmaciones cruzadas:
- El -22 salta **antes de `arm_smmu_attach_dev`** (arm-smmu.c:2546) — cuadra con que K12 no tuviera migas "CB reservado"/write_sme del dominio del display (solo la reclamación del SME en el probe).
- La miga K12 "ESCRIBIR SME idx=8 SMR=0x80021c00" (arm-smmu.c:2373) es del **probe del maestro**, no del attach del dominio: ver §2.

### 2. Cómo se forma el grupo (mecanismo exacto, con la corrección de los 3 miembros)

El orden por dispositivo en `iommu_init_device()` (iommu.c:469) es:
1. **iommu.c:511** `ops->probe_device` = `arm_smmu_probe_device` (arm-smmu.c:2808) → llama **`arm_smmu_master_alloc_smes(dev)` EN EL PROBE** (arm-smmu.c:2865) → `find_sme` (arm-smmu.c:2129) reclama SME para la banda 0x1c00/0x2 y `arm_smmu_write_sme` escribe el SMR (→ la miga "ESCRIBIR SME idx=8 SMR=0x80021c00" de K12, arm-smmu.c:2373).
2. **iommu.c:522** `ops->device_group` = `arm_smmu_device_group` (arm-smmu.c:2912): lee `s2crs[idx].group` (2921-2934). El primero crea grupo (`generic_device_group`, 2941) y lo recuerda (2944-2946). **Todo maestro posterior cuyo `find_sme` reutilice el MISMO SME (match exacto id/mask, arm-smmu.c:2156-2158) CAE EN EL MISMO GRUPO.**
3. `__iommu_probe_device` (iommu.c:627) monta el grupo y su **default domain** (iommu.c:677-689 → `iommu_setup_default_domain`, iommu.c:3148). Tipo: `qcom_smmu_def_domain_type` (arm-smmu-qcom.c:740-757) = **IDENTITY para todo menos WLAN** → S2CR BYPASS (`arm_smmu_attach_dev_identity`, arm-smmu.c:2615-2620). Inofensivo: el BL no tenía mapeo vivo para 0x1c00 (los vivos del K10 log son 0x60/0x480/0x481/0x100b/0xb6).

Miembros que comparten `0x1c00/0x2` en el DT fusionado (base+s260):
| Nodo | Origen | Evidencia |
|---|---|---|
| `soc:qcom,smmu_sde_unsec_cb` | **vendor base DT** (merged.dts:27135, `iommus = <0x129 0x1c00 0x02>`, con `qcom,iommu-earlymap`) | k10 log:3170 "Adding to iommu group 6" — entra al grupo **aun sin driver**: `iommu_init_device` ejecuta `dev->bus->dma_configure` para dispositivos sin driver (iommu.c:479-491). 0 lectores de la compatible en el árbol (grep `qcom,smmu_sde` → nada). |
| `display-subsystem@ae00000` (mdss padre) | **s231** (merged.dts:857) | — |
| `display-controller@ae01000` (dpu) | **s260** (INFORME-K12 §3: fragment@1709, diff semántico de 1 línea vs s258) | — |

→ grupo de **3**. El core lo soporta perfectamente como grupo (default domain IDENTITY compartida); lo único que no tolera es `iommu_attach_device()` con count≠1 (iommu.c:2206).

---

## 3. El "-19 de K13" — lo que la consola dice realmente

Estructura de `~/proyectos/out/uke-k13-console.log` (23997 líneas, 16 banners "Linux version"):

| Líneas | Kernel | Qué se ve |
|---|---|---|
| 1-12370 | **`7.2.0-rc2-palawan+ #82 Sat Sep 26 17:01:40`** (stock msm) | boot COMPLETO: cmdline, ITS, kgsl-smmu 0,315 s, defer timeout 13,9 s → **`dpu_kms_mmu_init failed: -19` @13,973070** (línea 152) → oops double-fini (§7). Consola viva 14 s. |
| 12371-12419 | **`7.2.0-rc2-palawan #17 Wed Sep 30 12:11:57`** (K13) | 7 stubs idénticos de 6 líneas: banner… "failed to reserve memory for node 'deuke" **CORTADA a mitad de línea**, fusionada con el texto crudo "UKE-K11 armando probe por sysfs". |
| 12420-23948 | **#82 otra vez** | boot completo → **`-19` @14,019515** (línea 12573) → oops. |
| 23949-fin | **#17 (K13)** | más stubs de 6 líneas, reboot loop. |

Conclusiones:
- **Los dos -19 son del #82 (26-sep), no del K13.** Firma exacta del stock: sin arming nadie bindea apps-smmu → dpu sin fwspec/grupo (`of_iommu.c:31-37`: sin ops registradas no hay fwspec) → `device_iommu_mapped` falso para mdp Y mdss → `msm_kms.c:197-199` "no IOMMU, bailing out" → **-ENODEV (-19)** (o `msm_iommu.c:738-739` si llegara). Es el mismo -19 del "kernel bueno sin parches".
- **El K13 (#17) jamás llegó a `dpu_kms_mmu_init` en esta captura**: 14+ boots, 0 líneas de kernel tras ~0,05 s, 0 migas UKE-K13 en el fichero (grep = 0). El texto "UKE-K11 armando probe por sysfs" es un `echo` **directo a /dev/ttyGS0** del initramfs (INFORME-K11-BUILD.md:76) — su presencia interleaved prueba que al menos un boot K13 llegó al arming (~4 s), pero el wedge se llevó la consola: patrón "el wedge PERSISTE entre reboots suaves" ya documentado en #P36.
- **Refutación explícita de "algo del k13.diff afecta a device_iommu_mapped/probe ANTES de msm_iommu_new"**: el patch k13 (1) añade `pr_info` en `init_domain_context` (arm-smmu.c, solo corre al atachear un dominio TRANSLATED con CB — jamás en los primeros 100 ms), (2) migas en `msm_kms.c`/`msm_iommu.c` (primer punto alcanzable: ~4 s, en el probe del dpu), (3) el fallback `iommu_attach_group` que **solo corre DESPUÉS de un -EINVAL con grupo>1** (msm_iommu.c:779) — es imposible que elimine un grupo aún no creado o anterior al probe. Nada de eso puede matar la consola a 0,05 s.
- Hipótesis alternativa del encargo ("en ese boot el SMMU no se bindeó") es plausible COMO MECANISMO de un -19 (arming fallido/wedge pre-arming → sin grupo → msm_kms.c:197) pero **no hace falta**: los -19 medidos son del #82.
- Timing arming/bind de referencia (k10 log): defer del probe (línea 1081-1082), arming tardío → "preserved 0 boot mappings" @435,385678 (línea 3131). En K11+ el arming horneado lo adelanta a ~4 s; el dpu re-probea a ~4,1 s (#P32).

**Estado real de K13: NO MEDIDO.** No hay ni un boot válido que demuestre o refute el fallback.

---

## 4. ¿Cómo maneja el core un grupo multi-dispositivo? (pregunta 3)

- **Group**: se crea una vez por banda compartida (arm-smmu.c:2912-2946, vía iommu.c:511→522); "Adding to iommu group N" se imprime en `iommu.c:1307`.
- **Default domain del grupo**: una sola, IDENTITY aquí (arm-smmu-qcom.c:755; S2CR BYPASS por arm-smmu.c:2615-2620). Convive sin problema con N dispositivos.
- **`device_iommu_mapped` = solo `dev->iommu_group != NULL`** (device.h:916-919). SÍ — el -22 de K12 NO vino de la falta de grupo ni del mapeo: vino del **attach** (iommu.c:2206). La hipótesis del orquestador era correcta en esencia; solo el recuento era 3 y no 2 (unsec_cb).
- **`iommu_attach_group()` NO tiene check de count** (iommu.c:2384-2394 → `__iommu_group_set_domain` → `__iommu_attach_device` por dispositivo → `arm_smmu_attach_dev`, que instala S2CRs TRANS con CB real, arm-smmu.c:2587-2588). Para una banda de traducción COMPARTIDA (una sola SME para el display) es la semántica correcta: mdss y dpu compartenPhysicalmente la misma traducción.
- El fallback del k13 (msm_iommu.c:779-797) implementa exactamente eso y está bien escrito: `-EINVAL` → contar dispositivos (`iommu_group_for_each_dev`) → si >1, `iommu_attach_group`. Nunca llegó a ejecutarse en un boot capturado.

---

## 5. Hipótesis rankeadas del estado final (con TEST y FIX)

**H1 — 85%: "K13 no llegó a probarse" (wedge CM3 persistente + captura muerta).** Los -19 son del #82; el K13 bootloopea mudo. TEST: re-armar la captura ANTES del boot (regla #P36) y boot K13 en frío → buscar migas `UKE-K13: msm_kms_init_vm: iommu_dev=...` y `iommu_attach_group rc=`. FIX: ninguno en kernel; operativo (power-cycle + captura).

**H2 — 80% (verificada en K12): grupo de banda 0x1c00 con 3 miembros → -EINVAL en iommu.c:2206.** TEST: en el dmesg de un boot con SMMU bindeado, `Adding to iommu group N` con el MISMO N para `soc:qcom,smmu_sde_unsec_cb`, `ae00000.display-subsystem` y `ae01000.display-controller`. FIX A: s261' (§6). FIX B: k13 (attach_group), requiere boot válido.

**H3 — 15% (si algún día K13 da -19 REAL): en ese boot el apps-smmu no llegó a bindear** (arming no ejecutado o wedge pre-arming) → sin grupo → msm_kms.c:197-199 -ENODEV. TEST: migas de arming/bind a ~4 s: "UKE-K11: armando probe a Ns", "arm_smmu_device_probe ENTRANDO, dev=15000000.apps-smmu", "preserved N boot mappings" (referencia k10 log:3131). FIX: reintentar arming/captura; el horneado ya existe.

**H4 — 5%: "el fallback k13 rompe la visibilidad del IOMMU" — REFUTADA.** El fallback corre solo tras -EINVAL de un grupo ya existente (msm_iommu.c:779); `iommu_attach_group` no toca la formación de grupos ni el probe (iommu.c:2384-2394). No puede convertir -22 en -19.

**H5 — contingencia si s261' sigue fallando:** (a) algún otro nodo comparte la banda → TEST: decompilar el fusionado post-s261' y exigir EXACTAMENTE 1 nodo con `<0x1c00 0x2>`; (b) fallo posterior al attach (alloc_context_bank, fault en el primer scanout = riesgo G1 del wedge) → TEST: migas nuevas "ESCRIBIR SME idx=8 … S2CR nominal" + "CB reservado" (no salían en K12) y ausencia de `dpu_kms_mmu_init failed`. FIX: escalera `uke_write_mask` (#P32) / plan B kernel.

---

## 6. RECOMENDACIÓN ÚNICA K14

**s261' (solo DT) + kernel K12 tal cual ya construido + re-armar la captura ANTES del boot. Sin recompilar.**

El dtbo s261' se genera con la MISMA cadena del s260 (`build/bootimg/mkdtbo-s260.py`) añadiendo 2 fragmentos de borrado:

1. `target-path = "/soc/display-subsystem@ae00000"` → `__overlay__ { /delete-property/ iommus; };`  *(deshacer el experimento s231)*
2. `target-path = "/soc/qcom,smmu_sde_unsec_cb"` → `__overlay__ { /delete-property/ iommus; };`  *(el fake CB vendor que comparte 0x1c00)*

(Opcional, no necesario: `qcom,smmu_sde_sec_cb` lleva `0x1c01/0x0` — banda DISTINTA, no interfiere.)

Resultado: `display-controller@ae01000` queda como **único** nodo con `<0x1c00 0x2>` → un solo SME → **grupo de exactamente 1** → `iommu_attach_device` pasa limpio (iommu.c:2206) → `arm_smmu_attach_dev` escribe S2CR(8)→CB del paging domain del msm → `msm_gem_vm_create` → `Initialized msm` → **card0**.

**¿Qué rompería? Nada observable:**
- El mdss no hace DMA (agregador: clks/irq/resets; el upstream palawan NO pone iommus en el mdss padre — s231 era propio y hoy estorba).
- `smmu_sde_unsec_cb` NO tiene driver en el árbol (0 hits) y su `qcom,iommu-earlymap` no tiene soporte: solo servía para arrastrar el grupo.
- fw_devlink: esos enlaces consumer→apps-smmu ya se ignoraban por timeout ("deferred probe timeout, ignoring dependency", consola 13,9 s).
- Semántica HW idéntica a K12 hasta el attach (SME 8, SMR 0x80021c00, S2CR BYPASS del default): el único cambio es que el attach DEJA de ser rechazado.

**Ojo: la s261 original (borrar SOLO el mdss padre) NO basta** — quedaría {unsec_cb, dpu} = grupo de 2 → -22 persiste. Por eso s261' lleva los dos borrados.

**Plan B (solo si s261' falla por otra causa)**: kernel con el fallback `iommu_attach_group` (el diff k13 de msm_iommu.c, ya escrito) — pero exige antes resolver wedge+captura, porque K13 no tiene ni un boot válido.

**Gates pre-flash** (como el G3 de K12): `fdtoverlay` base.dtb + s261' → decompilar → verificar EXACTAMENTE 1 nodo con `<0x129 0x1c00 0x2>` (display-controller), 0 en mdss/unsec_cb, resto del árbol sin cambios semánticos.

**Checklist de éxito en consola (boot K14):**
1. ~4 s: arming → probe apps-smmu completo → "Adding to iommu group N" SOLO para `ae01000.display-controller` (ni ae00000 ni smmu_sde_unsec_cb).
2. ~4,1 s: dpu re-probe → `UKE-K12: handoff no-vivo sid=0x1c00 → attach normal` → `ESCRIBIR SME idx=8 SMR=0x80021c00` → **migas NUEVAS de CB reservado** (no salían en K12: es la señal de que el attach pasó el check del grupo).
3. SIN `dpu_kms_mmu_init failed` → `[drm] Initialized msm` → card0 → fbcon.
4. Si -19: el SMMU no bindeó (arming) → H3. Si -22: el grupo sigue >1 → re-grep del fusionado (H5a).

Rollback: dtbo s260 `6fbb5173…` + boot K12 `7c6bfe0d…` (ROLLBACK.md).

---

## 7. Anexo: oops secundario (no bloquea K14)

Cualquier fallo de `dpu_kms_hw_init` después del `drm_atomic_private_obj_init` (dpu_kms.c:1157, antes de `_dpu_kms_mmu_init` en :1181) cae en `dpu_kms_destroy` (dpu_kms.c:905→918) → `drm_atomic_private_obj_fini` (dpu_kms.c:405) → **oops** "Unable to handle kernel paging request dead000000000108", pc `drm_atomic_private_obj_fini+0x2c` — visto en AMBOS boots #82 tras el -19 (líneas 154-160 y 12575+ de la captura). En K11 el sistema sobrevivió (#P32). Follow-up opcional: mover `drm_atomic_private_obj_init` después de `_dpu_kms_mmu_init` o blindar `_dpu_kms_hw_destroy`, para que un fallo futuro no ensucie la diagnosis con un oops/reinicio.
