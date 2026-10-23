# INFORME-K16-BUILD — boot-ukek16.img (kernel K13 + SPLIT de grupos IOMMU display + migas UKE-K16)

Fecha: 30-sep-2026 noche. **Trabajo sin tablet** hasta el flash #P44. Patrón de build: mv+symlinks
de INFORME-K13 §3 (`/var/tmp/uke-k13-{tree,build}` → renombrados a `uke-k16-*`, symlinks de
compatibilidad k12-*/k13-* repuntados; árbol K13 pristine preservado en
`build/kernel-pokes/k13-tree/` por rsync verificado). Compile: `make -C /var/tmp/uke-k16-tree
O=/var/tmp/uke-k16-build ARCH=arm64 LLVM=1 MAKE=/usr/bin/make -j16 Image.gz` desprendido → rc=0,
0 errores (log `/var/tmp/uke-k16/build.log`).

## Corrección de diseño aplicada (vs K16-DISENO.md)

1. **`generic_single_device_group()` NO sirve** (descubierto al implementar, confirmado en
   `drivers/iommu/iommu.c:1603`): devuelve el grupo **singleton por IOMMU** (`iommu->singleton_group`),
   no por dispositivo final — dpu+mdss+unsec_cb (los tres en el apps-smmu) habrían caído en el
   MISMO grupo y el comportamiento habría sido idéntico a K13. El parche usa
   **`iommu_group_alloc()`** (exportada, iommu.c) = grupo FRESCO por dispositivo.
2. El bloque se inserta tras `mutex_lock(&stream_map_mutex)` con **early-return SIN grabar
   `s2crs[idx].group`** (su único lector es la fusión de abajo; grabarlo volvería a fundir a los
   siguientes vía `iommu_group_ref_get`). Si el alloc falla, cae al camino K13 sin split.
3. Gating completo: `uke_disp_split && uke_handoff_activo(smmu)` (incluye `uke_smmu_es_apps` +
   `uke_handoff != 0`): el split no toca al kgsl-smmu.
4. El SID se extrae con `FIELD_GET(ARM_SMMU_SMR_ID, fwspec->ids[j])` (los ids llevan la máscara
   SMR empaquetada en los bits altos: `ARM_SMMU_SMR_MASK = GENMASK(31,16)`).
5. **Re-encuadre honesto de la hipótesis** (crítica técnica pre-flash): con la cmdline K13
   (`uke_write_mask=0`) K16 no programa nada nuevo en el HW del SMMU respecto de K13 — los DSI
   hosts no son masters IOMMU (sin `iommus` en el DTB fusionado) y un SMR con máscara `0x2`
   cubre 0x1c00+0x1c01 con UNA traducción. **K16 se flashea como CONTROL experimental barato**
   (mide el efecto del estado CORE: dpu solo en paging, mdss/unsec_cb de vuelta a default) y el
   peldaño siguiente (rung `uke_write_mask=0x1c0`) va construido: `boot-ukek16-wm.img`.

## Entregables y shas

| fichero | bytes | sha256 |
|---|---|---|
| **`build/bootimg/boot-ukek16.img`** (principal, 96 MiB) | 100663296 | **`f0688feb22966bcab6f6165b3b43df918e51fdbf59c1d4b7b340e2a5e5497d8f`** |
| **`build/bootimg/boot-ukek16-wm.img`** (peldaño c', sin recompilar) | 100663296 | **`1e27b33673d5b360bc00e77f730cb0ef9a9279d36d002e731ea4c9496be5a1ad`** |
| kernel = Image.gz build K16 | 16578528 gz (+1119 vs K13) / 41355776 crudo (+0: el parche cabe en padding) | `5f6534e43c16ce4f…` (gz) |
| parche | 2 hunks / arm-smmu.c | `build/gates/patches/k16-disp-split.diff` (`d101e056c6a61904…`) — valida contra copia pristine (`patch --dry-run` OK) |
| repack | `/var/tmp/uke-k16/repack-k16.py` (`--wm` = variante) | log `build/bootimg/repack-k16-report.txt` + `repack-k16-wm-report.txt` |
| rollback | `build/backup-par-bueno/boot-ukek13-dsid.img` (`e0ee47dc…`) + `s260` (`6fbb5173…`) — shas en SHA-BUENOS §PAR VIGENTE 30-sep | |

## Gates del repack (TODOS VERDES — repack-k16-report.txt)

G0 entradas (s240 `e3c60969…` / K13 `d71ea2b5…` / cpio `cb10ff40…`) + **gate de frescura**
(arm-smmu.c más viejo que Image.gz). G1 cabecera v4/1584, ramdisk 0, gzip @4096. G2 cmdline
356 B == K13 byte a byte, **SIN `video=`**, sin probe, 4 tokens `uke_`, tokens obligatorios
×1. G3 kernel: crudo 41355776 (+0), UKE-POKE=113, UKE-K12=1, UKE-K13=11, **UKE-K16 miga=1**,
**`arm_smmu.uke_disp_split`=1** (token completo; gate corregido durante el build: el primer
intento exigía ≥2 ocurrencias — falso, la tabla de params guarda el nombre con prefijo
`arm_smmu.`), "PINADO sin estar vivo"=0, UKE-K11=0, blob cpio @35336040 == cpio K12/K13,
ukeinit con 6 migas UKE-K11 y arming antes de switch_root. G4/G5 ensamblado y forma/AVB
(AVB0@35438592, AVBf@100663232). G6 delta vs s240 confinado a kernel_size@8+cmdline+kernel;
**vs K13: cmdline IDÉNTICA (0 B)**. G7 publicación + relectura. G8 unpack_bootimg
(kernel extraído == Image.gz K16) + avbtool (Footer 1.0, VBMeta @35454976/1728 == K13).

## Consola esperada (#P44, t = escalera K13 real)

| t | línea esperada |
|---|---|
| 0,44 s | `UKE-POKE: apps-smmu …: primer probe DIFFERIDO` (desarmado) |
| 3,57 s | `S118 ACMOK: /dev/ttyGS0 presente` |
| ~4,0 s | arming (UKE-K11) → barrido → `FIN barrido: PINADOS=1` (o 5) |
| ~4,1 s | **2-3× `UKE-K16: display sid=0x1c00 -> grupo PROPIO rc=0 (split)`** ← LA MIGA NUEVA (mdss + dpu; 3ª si unsec_cb probea). SIN ella el experimento es inválido (param/cmdline no aplicados) |
| ~4,1 s | `UKE-K13: msm_iommu_new: iommu_attach_device rc=…` — **sin el fallback de grupo** (grupo de 1) |
| ~4,1 s | `Initialized msm 1.13.0` + card0 (como K13+dsid) |
| luego | **modeset del panel en el boot** (sin `video=DSI-1:d`): fbcon pinta o wedge |

## Desenlaces (a)-(d) + (c')

- (a) VIVE + fbcon pinta → FOTO + `modes` → power-cycle en frío + 2ª foto = PANTALLA.
- (b) VIVE sin pintar → SSH: `status`/`modes` + modetest BAJO CONTROL (desechable; en K13
  `modetest -c` mató 2×).
- (c) Wedge → grep `context fault|global fault|smmu` ANTES de concluir rails → **peldaño c'**:
  `fastboot flash boot_b build/bootimg/boot-ukek16-wm.img` (mismo kernel, cmdline con
  `uke_write_mask=0x1c0` = attach_sme+install_s2cr+ctxbank escritos en HW). Si sigue →
  rails/reset SOLO con GO del dueño.
- (d) Muerte nueva → migas + consola; techo 1 retry; luego restaurar K13-dsid.
- Tras CUALQUIER wedge: power-cycle físico (persiste entre reboots suaves, #P34-bis/#P38).

Riesgos residuales declarados: (1) el control puede reproducir el wedge (esperado por la
crítica técnica) — su valor es descartar el estado CORE con 1 flash; (2) 2-3 migas UKE-K16
según probea unsec_cb (K13 midió grupo de 2: mdss+dpu); (3) relink/utsversion → binario no
byte a byte K13 (esperado); (4) el detach/teardown con grupos no grabados en s2crs no está
ejercitado en la serie — la miga rc y el dmesg lo dirán si se usa uke_disp_split=0 en caliente.

## RESULTADO DEL CICLO #P44 (30-sep 22:29-22:41) — desenlace (c) en ambas variantes

| artefacto | ciclos | desenlace |
|---|---|---|
| boot-ukek16.img (f0688feb…) | 7 | muerte muda ~4,1 s; **-22 = 0**; kms PASADO (adreno_request_fw 4,15 s en 6/7) |
| boot-ukek16-wm.img (1e27b336…) | 7 | idéntico con `uke_write_mask=0x1c0` aplicado (verificado en cmdline de consola) |
| rollback K13-dsid (e0ee47dc…) | 1 | VIVE, SSH OK, card0+renderD128 (verificado 22:41) |

**Lectura**: el split eliminó el -22 del core (control válido pese a las migas perdidas por
la consola — ventana 3,95-4,18 s ilegible, regla dura 12), pero el modeset mata igual en las
tres configuraciones SMMU ⇒ **familia SMMU REFUTADA como asesina** (lo predijo la crítica
técnica pre-flash). El asesino está en el camino del panel (rails/reset/GPIO/DSI). Detalle
operacional: cada serie agotó retry b hasta 0/unbootable — `fastboot set_active b` lo
resetea. Log completo: `build/logs/uke-k16-console-ciclo44.log` (14 boots).
