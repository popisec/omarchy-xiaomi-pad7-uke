# R4 — Nuevas vías y estado del arte (apps-smmu / pantalla / GPU) — 29-sep-2026

Investigación hecha **sin tablet** (prohibido fastboot/adb/ssh): solo web + disco local
(`~/gpu-work`, `~/proyectos`, este repo). Todas las afirmaciones llevan URL; lo
medido en este proyecto se cita por fichero local. Lo que no pude verificar se marca
**[NO VERIFICADO]** y por qué.

**Método / obstáculos de acceso** (para poder repetir):
- `lore.kernel.org`, `git.kernel.org`, `patchwork.kernel.org` y `wiki.postmarketos.org` están
  detrás de **Anubis** (PoW JS). Resuelto con un cliente propio que hace el PoW
  (`sha256(randomData+nonce)` con `difficulty` bytes nulos) y canjea
  `/.within.website/x/cmd/anubis/api/pass-challenge` → búsquedas de lore funcionando
  (`/var/tmp/r4/loreget.py`, `/var/tmp/r4/lores.py`, `/var/tmp/r4/loremsg.sh`).
- `chromium-review.googlesource.com` (Gerrit) y `gitlab.com`/`gitlab.freedesktop.org` responden;
  **fd.o (mesa) exige un formulario con honeypot explícito → no se ha tocado** (mesa no
  verificado). `gsmarena.com` y `xdaforums.com` tienen shield (403) → **[NO VERIFICADO]**.
- Bing RSS devuelve resultados degradados desde esta red; GitHub API y codeberg API son las
  fuentes que sí rinden.

---

## 0. Titulares (lo que cambia el plan)

1. **Upstream (mainline master = `7.3.0-rc5` hoy, posterior a nuestro 7.2-rc2) NO tiene NADA de
   cliffs, palawan, lamma ni SM7675.** Ni pinctrl, ni gcc/dispcc, ni catálogo DPU, ni GPU A735,
   ni compatible SMMU, ni IDs de SoC. Todo vive **fuera del árbol**, en el proyecto comunitario
   Codeberg `palawan-mainline/linux`.
   Versión comprobada: https://raw.githubusercontent.com/torvalds/linux/master/Makefile
   (`VERSION=7 PATCHLEVEL=3 EXTRAVERSION=-rc5`); base del fork local
   `~/gpu-work/palawan-linux/Makefile` (`7.2.0-rc2`).
2. `qcom,qsmmu-v500` es **nombre exclusivo del BSP vendor**: mainline nunca lo usó y el binding
   `arm,smmu.yaml` ni lo lista. No hay "razón de diseño" que excluya el hardware: mainline usa
   `qcom,<soc>-smmu-500` + `qcom,smmu-500` + `arm,mmu-500` y elige impl-data por tabla. La
   comunidad ya renombró el nodo (`qcom,palawan-smmu-500` / `qcom,sm8635-smmu-500`).
3. **El mecanismo que necesita nuestro problema existe, es de Qualcomm, y es del mismo SoC**:
   `arm_smmu_handoff_cbs()` + `s2crs[].pinned` + `__arm_smmu_alloc_cb()` en el kernel Android
   del SM8635/cliffs (lineage-23.0 = android14-6.1). **No está en mainline ni en nuestro fork**
   (grep en disco: 0 ocurrencias de `handoff-smrs`). Encaja exactamente con el mapa de minas
   medido (#P8–#P16): nunca escribe los registros vivos del bootloader y aun así bindea.
4. **Nadie más tiene pantalla en esta tableta con mainline**: el único port Linux vivo es el del
   **Pad 7 *Pro*** (muyu, SM8635, philmb3487+Zubtsov) y **no tiene nodos mdss/dpu** todavía;
   están en PCIe/WiFi. El árbol Codeberg palawan/lamma sí trae mdss+dpu (con
   `iommus = <&apps_smmu 0x1c00 0x2>`) pero **sin evidencia publicada de bring-up real**.
5. Nomenclatura: **`cliffs`** = familia vendor (nuestra máquina: `qcom,cliffs`, soc_id vivo
   **643 = CLIFFS7P**); **`pineapple`** = familia mainline del SM8650 (el device tree Android de
   uke usa `TARGET_BOOTLOADER_BOARD_NAME=pineapple`); **`kiwi` NO es el SoC** — en el cmdline
   Android `kiwi`/`kiwi_v2` es la **ruta de firmware del WLAN (WCN6750)**.
6. GPU: el **kgsl-smmu (3da0000) ya bindea y es independiente del apps-smmu** (dmesg vivo),
   pero la GPU A735 **tampoco está upstream** (mainline no tiene 0x43030b00 en `a6xx_catalog.c`):
   el soporte A735/gmu-735 también es del árbol Codeberg.

---

## 1. Estado del arte upstream para cliffs/SM7675 (con veredicto por comprobación)

Forma de comprobar: descarga directa de ficheros de `torvalds/linux@master` (**7.3.0-rc5** hoy,
https://raw.githubusercontent.com/torvalds/linux/master/Makefile) + listado de
directorios por API + búsquedas en lore (con el PoW resuelto). El árbol local del proyecto
(`~/gpu-work/palawan-linux`, 7.2-rc2 + parches) se usó como contraste.

| Qué busqué | Resultado en mainline/master | Fuente (URL) |
|---|---|---|
| `qcom,sm7675-dpu` / catálogo DPU cliffs | **NO**. Catálogo DPU: solo sm8650 (10.0), sm8750, kaanapali, glymur, eliza, milos… | https://api.github.com/repos/torvalds/linux/contents/drivers/gpu/drm/msm/disp/dpu1/catalog |
| `qcom,sm7675-mdss` / `palawan-mdss` | **NO**. sm8650-mdss existe (`qcom,sm8650-mdss`), y es justo el que la comunidad documenta para Palawan | https://raw.githubusercontent.com/torvalds/linux/master/arch/arm64/boot/dts/qcom/sm8650.dtsi |
| dispcc / gcc / tlmm / pinctrl cliffs o palawan | **NO**. `Kconfig.msm` no tiene `PINCTRL_CLIFFS/PALAWAN/LAMMA`; no existen `pinctrl-cliffs.c`, `gcc-palawan.c` | https://raw.githubusercontent.com/torvalds/linux/master/drivers/pinctrl/qcom/Kconfig.msm · 404 en `.../pinctrl-cliffs.c` y `.../gcc-palawan.c` |
| DT de SoC palawan/lamma/sm7635/sm7675 | **NO** existen (`palawan.dtsi`, `lamma.dtsi`, `sm7635.dtsi` → 404) | https://raw.githubusercontent.com/torvalds/linux/master/arch/arm64/boot/dts/qcom/palawan.dtsi (404) |
| IDs de SoC | `QCOM_ID_SM7635 = 636`; **no hay 614 (CLIFFS) ni 643 (CLIFFS7P) ni SM8635/SM7675** | https://raw.githubusercontent.com/torvalds/linux/master/include/dt-bindings/arm/qcom,ids.h |
| Compatibles SMMU qcom | Hasta `qcom,sm8750-smmu-500` (más eliza/glymur/kaanapali/milos/hawi/maili/nord/shikra). **No hay `qsmmu-v500`, ni palawan, ni sm8635/sm7675** | https://raw.githubusercontent.com/torvalds/linux/master/Documentation/devicetree/bindings/iommu/arm,smmu.yaml |
| Driver `arm-smmu-qcom` | Tabla `qcom_smmu_impl_of_match[]` sin `qsmmu-v500`; fallback por `qcom,smmu-500` | https://raw.githubusercontent.com/torvalds/linux/master/drivers/iommu/arm/arm-smmu/arm-smmu-qcom.c |
| GPU A735 (0x43030b00) / `gmu-735` | **NO** en `a6xx_catalog.c` (sí 0x43030c00…). Es decir: la GPU de esta tableta no está upstream | https://raw.githubusercontent.com/torvalds/linux/master/drivers/gpu/drm/msm/adreno/a6xx_catalog.c |
| Series 2025-2026 en lore | **0 resultados** para `sm7675`, `palawan`, `lamma`, `handoff-smrs`. `sm8635`: 16 mensajes (nov-2025, no mergeados). `sm7635`: ruido de `sm7635-ipa` (estable) | https://lore.kernel.org/all/?q=sm7675 · ?q=palawan · ?q=lamma · ?q=handoff-smrs · ?q=sm8635 (buscador propio con PoW) |
| linux-next directo | **[NO VERIFICADO]** git.kernel.org está tras Anubis. Mitigación: master (posterior a 7.2-rc2) no lo tiene; una serie mergeada en drm/msm o arm-msm ya aparecería en master | — |

**Lo que SÍ existe (y es la referencia real): proyecto comunitario Codeberg `palawan-mainline`.**

- Repo kernel: https://codeberg.org/palawan-mainline/linux — descripción "Mainline kernel for
  Qualcomm Palawan / Lamma platforms", ramas `palawan/v7.1` y **`palawan/v7.2-rc2`**
  (https://codeberg.org/api/v1/repos/palawan-mainline/linux/branches). Es el **origen del fork
  del proyecto** (`git remote -v` en `~/gpu-work/palawan-linux`).
- Qué añade (lista de commits de la rama, https://codeberg.org/api/v1/repos/palawan-mainline/linux/commits?sha=palawan/v7.2-rc2):
  `dt-bindings: arm: qcom: Document Palawan SoC and board`, `dt-bindings: arm-smmu: qcom: Add
  compatible for Palawan SoC`, `dt-bindings: display/msm: qcom,sm8650-dpu: Document Palawan DPU`,
  `drm/msm/dpu: Add Palawan support`, `drm/msm: mdss: Add support for Palawan`,
  `dt-bindings: display/msm: qcom,sm8650-mdss: Document Palawan MDSS`, `clk: qcom:
  dispcc-sm8550: Add support for Palawan DISPCC`, `dt-bindings: clock: qcom: Document the
  Palawan Global Clock Controller` + GCC/GPUCC/CAMCC/VIDEOCC/TCSRCC, `interconnect`,
  `drm/msm/adreno: Add Adreno 735 support`, `gmu: Document Adreno 732/735`, UFS/UFS-PHY,
  IPA, remoteproc PAS, `arm64: dts: qcom: Add initial Palawan dtsi` / `lamma dtsi` +
  `palawan-qrd.dts` / `lamma-qrd.dts` (jun-2026).
- **No hay serie en lore** para nada de esto (0 hits de "palawan"/"lamma") ⇒ es trabajo
  out-of-tree en curso, no un merge perdido. El binding que llevan parcheado es local:
  `qcom,palawan-smmu-500` en `arm,smmu.yaml`
  (https://codeberg.org/palawan-mainline/linux/raw/branch/palawan/v7.2-rc2/Documentation/devicetree/bindings/iommu/arm,smmu.yaml).
- El repo hermano de firmware (blobs QRD8635) y **u-boot**: https://codeberg.org/palawan-mainline/u-boot
  está **vacío** (size 0) — no hay bootloader mainline; se sigue dependiendo del ABL (coincide
  con el informe B del proyecto).

---

## 2. El apps-smmu en otros ports: mecanismos "preserve/handoff/keep" y portabilidad

### 2.1 El mecanismo real: `qcom,handoff-smrs` (Qualcomm BSP; NO upstream)

Existe implementado en el **kernel Android del propio SoC** (y en BSPs Qualcomm):

- Kernel Xiaomi SM8635 (mismo linaje que la tablet, android14-6.1 / "lineage-23.0"):
  https://github.com/Xiaomi-Pad-7-Pro-Resources/android_kernel_xiaomi_sm8635 →
  `drivers/iommu/arm/arm-smmu/arm-smmu.c` (raw:
  https://raw.githubusercontent.com/Xiaomi-Pad-7-Pro-Resources/android_kernel_xiaomi_sm8635/lineage-23.0/drivers/iommu/arm/arm-smmu/arm-smmu.c).
  Función **`arm_smmu_handoff_cbs()`** + opción **`qcom,multi-match-handoff-smr`**.
- Espejo BSP Qualcomm (CodeLinaro, msm-5.15 `cervinia/dev-5.15`):
  https://github.com/CodeLinaro-mirror/le_kernel_msm-5.15/blob/cervinia/dev-5.15/drivers/iommu/arm/arm-smmu/arm-smmu.c
- Historia del parche (2 commits concretos, con sus diffs):
  - `arm-smmu: use smr match for handoff-smrs` — https://github.com/CodeLinaro-mirror/le_kernel_msm-5.15/commit/8fa3cecff06e7aeba00e0f463714c4ad09dcca30
    (pasa de "conservar por índice de SMR" a "conservar por match id/mask": evita romper si
    ABL y HLOS numeran distinto).
  - `arm-smmu: Correct the index for handoff smrs` — https://github.com/CodeLinaro-mirror/le_kernel_msm-5.15/commit/18d1a0b7a412ee821aa92f0dc2e54ced8bb79611

**Mecanismo exacto** (leído en el código, líneas citadas en la copia local `/var/tmp/r4/xiaomi-arm-smmu.c`):

1. En probe, si el DT tiene `qcom,handoff-smrs = <id mask id mask …>`, `arm_smmu_handoff_cbs()`
   (línea ~3016) recorre los SMR **vivos** del hardware y, para los que **son subconjunto** de la
   lista (test `(handoff.mask & smr.mask) == smr.mask && !((handoff.id ^ smr.id) & ~handoff.mask)`),
   guarda `smmu->smrs[i] = smrs; smmu->s2crs[i].pinned = true;` y reserva su CB
   (`bitmap_set(context_map, cbndx, 1)`), copiando `type/privcfg/cbndx` del S2CR vivo.
2. `__arm_smmu_alloc_cb()` (~401): si algún SME del maestro está `pinned`,
   **devuelve el CB del bootloader** en vez de asignar uno nuevo ⇒ el attach **no reescribe el
   S2CR** (`arm_smmu_domain_add_master()` hace `continue` si tipo y cbndx coinciden) ⇒ cero
   escrituras a registros vivos en el camino del display.
3. `arm_smmu_free_sme()` (~1780) y `arm_smmu_destroy_domain_context()` (~1574) respetan `pinned`
   (no liberan el CB, no invalidan el SMR).
4. Todo lo que NO está en `qcom,handoff-smrs` se comporta como en mainline: el reset lo barre.

**Nuestra DT vendor lo trae literalmente**: `apps-smmu@15000000` en el DT stock
(`~/gpu-work/w15-dt/stockuke.dts:13180-13194`) declara
`compatible = "qcom,qsmmu-v500"`, `qcom,use-3-lvl-tables` y
**`qcom,handoff-smrs = <0x1c00 0x02>`** — es decir, el vendor protege exactamente el **SID del
display** (0x1c00, mask 0x2). El SID del UFS (0x60) **no** está protegido: por eso el vendor
puede resetear sin matar el arranque a los 0.543 s (#P16) y por eso nuestro barrido tardío (con
UFS en vuelo) sí mata.

**Portabilidad a 7.2-rc2**: alta. Es un port de ~120 líneas dentro de `arm-smmu.c` + un campo
`pinned` (y `cbndx`) en `struct arm_smmu_s2cr` (`arm-smmu.h`), sin tocar el resto. Dos matices
medidos aquí:
- La versión vendor **lee S2CR(i)** de las entradas vivas; en nuestros binds tardíos leer
  `S2CR(0)` mató (#P13). → Portar la lógica pero **sin leer S2CR**: con el match por SMR basta
  para no barrer; el CB del BL solo hace falta para el truco "reutiliza cbndx" (paso 2), y puede
  delegarse a una segunda fase, ya con el display en la mano.
- El reset debe además tratar `pinned` como intocable (equivalente a nuestro `uke_keep_boot`,
  #P11, pero **selectivo por SID** en vez de "todo el reset").

**¿Lo han intentado en mainline?** No: `handoff-smrs` tiene **0 resultados en lore** (todas las
listas, https://lore.kernel.org/all/?q=handoff-smrs). Es código que Qualcomm nunca envió.

### 2.2 El otro mecanismo vendor: dominios por dispositivo (`qcom,iommu-dma`)

`arm_smmu_setup_default_domain()` (mismo fichero vendor) lee **`qcom,iommu-dma`** del nodo del
cliente: `"bypass"` (identidad, sin traducción), `"fastmap"`, `"atomic"`, `"disabled"`. El DT
stock lo usa como mínimo en coresight (`~/gpu-work/w15-dt/stockuke.dts:4845-4847`).
Es el equivalente Android de "este maestro va en identidad", y es **soportado por el vendor**
(no un hack). En mainline esto se corresponde con `IOMMU_DOMAIN_IDENTITY`
(S2CR_TYPE_BYPASS) y con `iommu.passthrough`/`arm_smmu.disable_bypass`; de hecho **el cmdline
Android de la tablet ya pasa `arm-smmu.disable_bypass=0`** (bootconfig stock:
`build/bootimg/cmdline-orig.txt`), señal de que el BSP cuenta con bypass disponible.

### 2.3 Lo que hay en mainline (y por qué no sirve)

- `arm_smmu_rmr_install_bypass_smr()` en `arm-smmu.c` (líneas 2070-2116 de
  https://raw.githubusercontent.com/torvalds/linux/master/drivers/iommu/arm/arm-smmu/arm-smmu.c)
  conserva mapeos del bootloader **solo vía IORT/RMR (ACPI)**; para DT no hay camino. Nuestro
  fork ya lo tiene (imprime "preserved 0 boot mappings", exactamente lo que vimos en el dmesg de
  kgsl-smmu: `~/proyectos/omarchy-uke/build/evidencia/2026-09-28/dmesg-arch.txt:0.321657`).
- No existe en mainline ninguna pieza "keep/preserve" para SMMUv2 por DT.
- **ChromeOS**: búsqueda en Gerrit (`project:chromiumos/third_party/kernel arm-smmu`,
  https://chromium-review.googlesource.com/q/project:chromiumos/third_party/kernel+arm-smmu) —
  no aparece ningún "preserve boot mappings"/handoff para arm-smmu v2 (los hits son SMMUv3
  MediaTek o merges). El único parche relevante y **mergeado** que sí encontré es de ordenación
  de probes: `iommu/arm-smmu: Defer probe of clients after smmu device bound`
  (CL 6267947, https://chromium-review.googlesource.com/c/chromiumos/third_party/kernel/+/6267947)
  — útil conceptualmente para el asunto "quién probea antes", pero no preserva mapeos.
  → **Conclusión: no hay parche ChromeOS portable; el patrón Qualcomm `handoff-smrs` es el único
  implementado, y vive downstream.**

---

## 3. `qcom,qsmmu-v500`: quién la usa, quién la bindea, y qué usa SM7675/SM8635 en realidad

| Nodo | Compatible | Driver que lo bindea |
|---|---|---|
| **uke vendor** `apps-smmu@15000000` | `"qcom,qsmmu-v500"` (solo) | En Android: su `arm-smmu-qcom` con of_match vendor. En mainline **NO bindea** (ni el binding ni la tabla lo conocen) → de ahí K1/A′ |
| **uke vendor** `kgsl-smmu@3da0000` (GPU) | `"qcom,qsmmu-v500", "qcom,adreno-smmu"` | `arm-smmu` + impl qcom/adreno (sí bindea: `3da0000.kgsl-smmu: probing hardware configuration…`, dmesg vivo 0.321 s) |
| **SM8550** mainline | `"qcom,sm8550-smmu-500", "qcom,smmu-500", "arm,mmu-500"` | `arm-smmu-qcom` (impl0) |
| **SM8650** mainline | `"qcom,sm8650-smmu-500", "qcom,smmu-500", "arm,mmu-500"` | idem |
| **GPU** SM8550/SM8650 | `+ "qcom,adreno-smmu"` | impl adreno |
| **palawan** (Codeberg) | `"qcom,palawan-smmu-500", "qcom,smmu-500", "arm,mmu-500"` | mainline con el binding parcheado por ellos |
| **SM8635** (muyu, port vivo) | `"qcom,sm8635-smmu-500", "qcom,smmu-500", "arm,mmu-500"` | mainline con compatible propio (sin `handoff-smrs`, sin `use-3-lvl-tables`) |

Fuentes: sm8550.dtsi / sm8650.dtsi de mainline (raw, ver §1), `arm,smmu.yaml` de mainline,
`arm-smmu-qcom.c` de mainline; muyu: https://gitlab.com/philmb3487/muyu6.17-dt/-/raw/main/sm8635.dtsi
(nodo `apps_smmu`); palawan:
https://codeberg.org/palawan-mainline/linux/raw/branch/palawan/v7.2-rc2/arch/arm64/boot/dts/qcom/palawan.dtsi
(línea 4335); stock vendor: `~/gpu-work/w15-dt/stockuke.dts:13180`.

**Lectura:** no hay "exclusión por diseño" del hardware; hay **convención de nombres**. Mainline
exige compatible por SoC documentado en el YAML (y desaconseja añadir más entradas a la tabla),
mientras el BSP vendor publica un nombre genérico `qsmmu-v500` que mainline nunca adoptó. Por eso
el camino "limpio" no es añadir el `of_match` en el kernel (K1), sino **cambiar el DT** (lo que
A′ intentaba) o **adoptar el nombre que la comunidad ya usa** (`qcom,palawan-smmu-500`, que es
exactamente el nodo que llevan en su `palawan.dtsi`).

**Comparación útil:** en mainline el `mdss` del SM8650 (pineapple, misma familia) usa
`iommus = <&apps_smmu 0x1c00 0x2>` (sm8650.dtsi:5671) — **el mismo SID/mask que la casa pone en
`qcom,handoff-smrs` y que la comunidad pone en `palawan.dtsi:3379`.** Es decir: el display de
toda la familia va por el SID 0x1c00 mask 0x2, y en SM8650 mainline eso funciona con el
apps-smmu bindeado normalmente.

---

## 4. Comunidad Xiaomi Pad 7 / uke: ¿alguien tiene pantalla o GPU con mainline?

**Respuesta corta: no para la pantalla. Para Linux "que funcione" solo hay Android/GKI 6.1 y un
snapshot Debian.**

1. **postmarketOS**: existe página, en obras, sin estado de hardware:
   https://wiki.postmarketos.org/wiki/Xiaomi_Pad_7_(xiaomi-uke) (hoy redirige a wiki.nura.eco).
   Chipset declarado: **Snapdragon 7+ Gen 3 (SM7675)**; `category`/`booting`/`status_screen` en
   blanco (última edición 27-sep-2026, es decir, contemporánea a este proyecto — probablemente
   escrita desde aquí: no es corroboración independiente). **No hay paquete `device-xiaomi-uke`
   en pmaports** (búsqueda en GitLab de pmOS: `device/testing` sin xiaomi nuevo; la API de
   pmaports devuelve 401 sin token, [NO VERIFICADO] el árbol completo).
2. **Pad 7 Pro (muyu, SM8635)** — el port Linux más avanzado de la familia:
   - Hilo de presentación: *SM8635 Porting Effort - PCI-E Card Doesn't Show Up* (nov-2025) —
     https://lore.kernel.org/all/xAsYX3yZX3laVVaqB8tdxUoTWM3jFlYudJ7j62r-6redf_OJgS_eY2mEypJ0Ma8B26RKeCqQU2G7pYTKapYx0M0rPAEvdpA2oyOs4XA8tcE=@proton.me/
     con respuesta de **Dmitry Baryshkov** (mantenedor upstream qcom):
     https://lore.kernel.org/all/wtyikmhzyizezs45yqubflxivxj2iyk6dkutn643v7iokvqfcy@fxmysaq26gg5/
   - Wiki del port: http://muyuwiki.ca (**[NO VERIFICADO]**: hoy solo devuelve 308 a
     `http://137.220.53.30/mediawiki`, que no responde a mis peticiones).
   - Device tree: https://gitlab.com/philmb3487/muyu6.17-dt — ficheros `sm8635.dtsi` +
     `sm8635-muyu.dts`, `model = "Xiaomi Pad 7 Pro"`, `compatible = "qcom,sm8635-muyu",
     "qcom,sm8635"`. **No contiene nodos `mdss`, `dpu` ni panel** (grep exhaustivo): su bring-up
     no ha llegado a pantalla. Sí declara `apps_smmu@15000000` = `qcom,sm8635-smmu-500` +
     `qcom,smmu-500` + `arm,mmu-500`, `reg 1 MiB`, **sin** `handoff-smrs`.
   - Autor principal: Philippe Michaud-Boudreault (philmb3487) con **Alexandr Zubtsov
     (devizure/USUARIO@example.invalid)**, el mismo que firma los commits de Codeberg.
3. **Otros intentos del Pad 7 Pro/uke**:
   - `[PATCH] dt-bindings: arm: qcom,ids: Add SoC IDs for SM8635 family` (nov-2025):
     https://lore.kernel.org/all/9nTdr-7UlyytB3d5Iz0IEGrAAzjPipf4NEiZvLMmpk9OmCmRuL346OxjZgpLkLdG7dFYE_rj-5aibg7bhYHrQmjwo1e096-2IGhfi1rKglE=@proton.me/
   - `[PATCH] Add support for General Clock Controller for SM8635` (nov-2025) y revisión de
     Krzysztof Kozlowski: https://lore.kernel.org/all/f10a13af-c4e7-47df-9e9d-7efed30b2147@kernel.org/
     → **ninguno mergeado** (en master no hay IDs SM8635 ni gcc-sm8635).
4. **Ecosistema Android de uke (referencia de partida, no mainline)**:
   - `vember31/android_device_xiaomi_uke-me` (LineageOS 23.2): BoardConfig declara
     **kernel 6.1 GKI prebuilt**, `inherit sm8635-common`, `TARGET_BOOTLOADER_BOARD_NAME =
     pineapple` — https://github.com/vember31/android_device_xiaomi_uke-me/blob/lineage-23.2/BoardConfig.mk
   - Org con todo el árbol del kernel: https://github.com/Xiaomi-Pad-7-Pro-Resources
     (`android_kernel_xiaomi_sm8635` [lineage-23.0], `…-devicetrees`, `…-modules`,
     `android_kernel_common_android14-6.1`).
   - `AbhinavBan/android_kernel_xiaomi_uke` está **vacío** (size 0).
   - Snapshot Linux "de usuario": https://github.com/StampyCat889/Linux-UKE (Debian+GNOME,
     release v0.1-test 24-ago-2026; usa slot A; menciona drivers GPU/audio/touch — es un
     userspace sobre kernel GKI vendor, no mainline; no publica cómo compila el kernel).
   - Guía GKI: https://github.com/HuangJunLin8/uke_gki_kernel.

**Conclusión §4**: el único Linux con pantalla en la familia es **Android GKI 6.1 + driver
display vendor** (`techpack`, ver §5). En mainline, nadie tiene display en uke/muyu; la única
referencia mainline de display para la familia es el **DT de palawan de Codeberg** (sin
evidencia publicada de que hayan validado pantalla).

---

## 5. Kernel de referencia para display de cliffs (BSP) y nomenclatura final

### 5.1 Fuentes BSP concretas

- **Kernel Android del SoC (el que usa la tablet)**: `Xiaomi-Pad-7-Pro-Resources/android_kernel_xiaomi_sm8635`,
  rama **`lineage-23.0`** (base Qualcomm **android14-6.1**, GKI 2.0 con módulos vendor):
  https://github.com/Xiaomi-Pad-7-Pro-Resources/android_kernel_xiaomi_sm8635
  - `drivers/iommu/arm/arm-smmu/arm-smmu.c` = el `handoff-smrs` (§2.1).
  - Aquí está el display vendor (`techpack/display`, driver `sde`) y el `kgsl`. **[NO VERIFICADO
    byte a byte]**: listé el repo (existe `drivers/`, y el árbol es android14-6.1 completo);
    el mismo linaje aparece en mirrors de comunidad (p.ej. `peridot-dev/android_kernel_xiaomi_sm8635`,
    https://github.com/peridot-dev/android_kernel_xiaomi_sm8635).
  - Device trees vendor: https://github.com/Xiaomi-Pad-7-Pro-Resources/android_kernel_xiaomi_sm8635-devicetrees
    (directorios `qcom/`, `bindings/`).
- **Espejo Qualcomm (msm-5.15, "cervinia")**: https://github.com/CodeLinaro-mirror/le_kernel_msm-5.15
  (`drivers/iommu/arm/arm-smmu/*`, con los commits de handoff).
- **Alternativa de más valor para nosotros**: el árbol Codeberg (palawan/lamma) ya trae el
  display **en mainline**: `drm/msm/dpu: Add Palawan support`, `drm/msm: mdss: Add support for
  Palawan`, `clk: qcom: dispcc-sm8550: Add support for Palawan DISPCC` (commits de jun-2026;
  https://codeberg.org/palawan-mainline/linux/commits/branch/palawan/v7.2-rc2).

### 5.2 Nomenclatura (cliffs vs kiwi vs pineapple) — con evidencia

| Nombre | Qué es | Evidencia |
|---|---|---|
| `cliffs` | Nombre **vendor** de la familia SoC. DT stock: raíz `compatible = "qcom,cliffs"`, model "Qualcomm Technologies, Inc. Cliffs SoC"; overlays `qcom,cliffs-mtp`, `qcom,cliffs-rpmh-clk`, `qcom,cliffs-pdc`, `qcom,cliffs-llcc`, `qcom,cliffs-pinctrl` | `~/gpu-work/w15-dt/stockuke.dts:4-5` y nodos citados; y el propio fork (`drivers/pinctrl/qcom/pinctrl-cliffs.c`) |
| `CLIFFS7P` (643) / `CLIFFS` (614) / `SG_CLIFFS7P` (700) | IDs de socinfo vendor. **La tablet viva reporta soc_id = 643 "CLIFFS7P"** (msm-id `0x283` consumido por el ABL) | Tabla vendor: `{ 643, "CLIFFS7P" }` en https://github.com/peridot-dev/android_kernel_xiaomi_sm8635/commit/67568e2de13251f28eaacf64343305e19020c854 ; msm-id del proyecto: `~/gpu-work/palawan-linux/arch/arm64/boot/dts/qcom/xiaomi-uke.dts` (comentario T-A2) y `PRE-REGISTRO` #P3 |
| `palawan` | Nombre **mainline comunitario** de la variante GPU A735 (gmu-735) — el Pad 7 **Pro**. Inexistente en mainline real | codeberg `palawan.dtsi` (gpu `qcom,adreno-43030b00`, `gmu-735.0`); muyu = `qcom,sm8635-muyu` |
| `lamma` | Variante "differently fused palawan" (gmu-732, OPP propias, `lamma-llcc`); es la que el proyecto usa para uke | `lamma.dtsi` (Codeberg; copia local `…/qcom/lamma.dtsi:1-9`, `&gmu { compatible = "qcom,adreno-gmu-732.0" }`); `xiaomi-uke.dts` ("SoC SM7675 = lamma") |
| `pineapple` | Familia **mainline** del SM8650 (el hermano "grande" de cliffs) | mainline `sm8650.dtsi`; y device tree Android de uke: `TARGET_BOOTLOADER_BOARD_NAME` = "pineapple" (https://github.com/vember31/android_device_xiaomi_uke-me/blob/lineage-23.2/BoardConfig.mk) |
| `kiwi` / `kiwi_v2` | **NO es el SoC**: es el chip/ruta de firmware del **WLAN (WCN6750)**: `firmware_class.path=…/image/kiwi,…,/vendor/firmware/wlan/qca_cld/kiwi_v2` | cmdline stock en `build/bootimg/cmdline-orig.txt`; los blobs WLAN del proyecto viven en `lib/firmware/ath11k/WCN6750/…` y `lib/firmware/qca6750/…` (`build/gates/firmware-wlan.sha256`) |

**Discrepancia abierta (importante, pero no bloquea):** el DTBO vendor dice
`"Qualcomm Technologies, Inc. Uke based on SM8635"` y el DT base declara `Adreno735`
(chipid `0x43030b00`), mientras la ficha pública/pmOS dice **SM7675**. El dato *vivo* del equipo
es soc_id 643 CLIFFS7P. Como palawan=SM8635=Pad 7 Pro (muyu) y lamma=SM7675 (uke) según la
comunidad, lo probable es que Xiaomi haya **reutilizado el DT base de la familia** (de ahí
"SM8635"/A735 en el blob compartido) y que el SoC real de uke sea SM7675/lamma — pero **está sin
confirmar con una fuente externa de fichas** ([NO VERIFICADO] GSMArena bloquea). Consecuencia
práctica: **para el display y el SMMU da igual** (mismo `apps-smmu@15000000`, mismo SID
`0x1c00/0x2`, misma DISPCC/DPU base SM8650), pero conviene no construir afirmaciones firmes
sobre SM7675 en documentación de usuario.

---

## 6. Alternativas exóticas si el SMMU nunca bindea (rankeadas y con evidencia)

### 6.1 "DPU sin iommu" (quitar `iommus` del nodo) — **NO es viable tal cual**
El msm moderno exige IOMMU **por diseño**: `msm_kms_init_vm()` en
`drivers/gpu/drm/msm/msm_kms.c` (~línea 190) hace
`if (device_iommu_mapped(mdp_dev)) … else if (device_iommu_mapped(mdss_dev)) … else { drm_info(dev, "no IOMMU, bailing out\n"); return ERR_PTR(-ENODEV); }`
(ruta local: `~/gpu-work/palawan-linux/drivers/gpu/drm/msm/msm_kms.c:190-198`).
Es exactamente lo que nuestros logs muestran. Para ir por aquí habría que **implementar un
`msm_mmu` "no-op/identidad"** (direcciones físicas directas) y aceptar que el DPU haga DMA sin
traducción — ver 6.2. Es una *feature* de driver, no un parche de una línea, y no existe
upstream.

### 6.2 Bypass/identidad para el maestro del display — **estructural, con precedente vendor**
- Precedente real: Qualcomm soporta por DT `qcom,iommu-dma = "bypass"` (identidad) por cliente
  (`arm_smmu_setup_default_domain()`; ejemplo en el DT stock para coresight, `stockuke.dts:4845`).
- Mainline tiene `IOMMU_DOMAIN_IDENTITY` (bypass S2CR) y el fork **ya lleva un parche UKE
  "dominio por defecto IDENTITY para TODOS los maestros"**
  (`~/gpu-work/palawan-linux/drivers/iommu/arm/arm-smmu/arm-smmu-qcom.c:584`).
- El cmdline Android usa `arm-smmu.disable_bypass=0` (`build/bootimg/cmdline-orig.txt`).
- **Pero**: el camino de msm (`msm_iommu_disp_new` → `iommu_map` sobre el dominio) está pensado
  para traducción; con identidad, `iommu_map` no crea mapeos y el gem/vm de display puede fallar.
  **[NO VERIFICADO]**: no he encontrado ningún dispositivo qcom corriendo display mainline
  *sin* apps-smmu bindeado; y los únicos "sin SMMU" que hay en mainline son SoCs antiguos con
  `msm_iommu`/gpummu (otra generación, 32-bit).
- Conclusión: es la vía "no-SMMU" menos mala, pero requiere tocar msm (`no-op mmu`) y no tiene
  respaldo comunitario. **Ranking 3º**.

### 6.3 hyp/TZ como requisito
No hay requisito de hypervisor: el kgsl-smmu (AP-owned) bindea sin hyp (`dmesg-arch.txt:0.321`).
Lo que sí hay es **protección TZ/XPU** sobre registros del apps-smmu: nuestra medición (#P13:
leer S2CR(0) mata; escribir vivos mata) sólo se explica con accesos privilegiados/protegidos o
con DMA de fondo (no hay fuente web que lo documente; es medición propia). El BSP convive con
ello **haciendo el reset antes de que haya DMA del kernel** (#P16) y **sin tocar lo vivo**.

### 6.4 Ventana temporal (ya en marcha, K7) — **la vía más barata, y probablemente parte de la
solución final**: el dmesg Android (`build/evidencia/…`, cita en `PRE-REGISTRO-PANTALLA.md` #P16)
muestra bind+reset a **0.543 s** y el primer group del UFS 7 ms después. Nuestros binds a 38–90 s
son los que tienen el disco volando por un SMR vivo. Ordenación de probe también tiene parche
upstream/ChromeOS mergeado (CL 6267947, §2.3).

---

## 7. RANKING FINAL

### 7.1 Para **pantalla completa** (vías "de verdad", no apaños)

**1º — Vía H: portar la semántica `handoff` del BSP vendor + reset selectivo + bind temprano.**
- Qué es: implementar en el fork 7.2-rc2 (a) `arm_smmu_cfg_probe`-time: leer SMRs vivos y marcar
  como `pinned` los que casen con `qcom,handoff-smrs` del DT **sin leer S2CR**; (b) reset que no
  escribe `pinned` (equivalente a `uke_keep_boot` pero **selectivo por SID**, no global);
  (c) reutilización del CB del BL para el attach (paso 2 del mecanismo) o attach diferido del
  display tras el primer mapeo; y (d) bind en la ventana Android (~1 s).
- Por qué 1º: es el **único mecanismo en producción sobre este mismo SoC**; explica *todas*
  nuestras minas (#P8–#P16); su código de referencia está en el kernel del SoC (lineage-23.0) y
  en CodeLinaro; y es ~120 líneas auto-contenidas, upstream-ables si algún día se propone.
- Riesgo residual: la lectura de S2CR del vendor → **no portarla**; el `handoff` por match de SMR
  es suficiente para no barrer lo vivo.
- URLs: kernel del SoC
  https://raw.githubusercontent.com/Xiaomi-Pad-7-Pro-Resources/android_kernel_xiaomi_sm8635/lineage-23.0/drivers/iommu/arm/arm-smmu/arm-smmu.c ·
  commits cualitativos
  https://github.com/CodeLinaro-mirror/le_kernel_msm-5.15/commit/8fa3cecff06e7aeba00e0f463714c4ad09dcca30
  y https://github.com/CodeLinaro-mirror/le_kernel_msm-5.15/commit/18d1a0b7a412ee821aa92f0dc2e54ced8bb79611 ·
  DT stock con `qcom,handoff-smrs = <0x1c00 0x02>` (`~/gpu-work/w15-dt/stockuke.dts:13186`).

**2º — Vía C: alinearse con el árbol comunitario palawan/lamma (y preguntarles).**
- Qué es: adoptar la DT/driver-data de Codeberg tal cual (`qcom,palawan-smmu-500` +
  `qcom,smmu-500` + `arm,mmu-500`; `mdss iommus = <&apps_smmu 0x1c00 0x2>`;
  `qcom,palawan-mdss`/`dpu`, dispcc sobre sm8550) y **abrir conversación** con Zubtsov
  (USUARIO@example.invalid) y philmb3487: ¿bindean el apps-smmu en QRD8635? ¿lo han visto
  sobrevivir con el reset vanilla? ¿por qué su DT no lleva `handoff-smrs`?
- Por qué 2º: es *upstream-grade* (todo lo que hagamos les sirve), evita divergir y puede venir
  con la respuesta ya masticada; pero **no hay evidencia publicada de pantalla funcionando** en
  su hardware (su DT de muyu no tiene display), así que no es una solución por sí sola.
- URLs: https://codeberg.org/palawan-mainline/linux (ramas y commits de jun-2026) ·
  `palawan.dtsi` (mdss/dpu/smmu) https://codeberg.org/palawan-mainline/linux/raw/branch/palawan/v7.2-rc2/arch/arm64/boot/dts/qcom/palawan.dtsi ·
  hilo/handles: https://lore.kernel.org/all/xAsYX3yZX3laVVaqB8tdxUoTWM3jFlYudJ7j62r-6redf_OJgS_eY2mEypJ0Ma8B26RKeCqQU2G7pYTKapYx0M0rPAEvdpA2oyOs4XA8tcE=@proton.me/ ·
  https://gitlab.com/philmb3487/muyu6.17-dt

**3º — Vía I: identidad/bypass sólo para el SID del display + `msm_mmu` no-op (o, si se logra
bindear, `IOMMU_DOMAIN_IDENTITY` para mdss/dpu).**
- Qué es: no tocar nunca los registros vivos: dominio identidad para el maestro del display
  (precedente vendor `qcom,iommu-dma = "bypass"`, y parche UKE-IDENTITY ya presente) y, si msm se
  niega a mapear, añadir un `msm_mmu` "no-op" que devuelva direcciones físicas (con `mem=2048M`
  es factible).
- Por qué 3º: rompe suposiciones de msm (hay que escribir código de driver nuevo), no hay
  dispositivo conocido que lo use en mainline y el beneficio es sólo desbloquear el display
  mientras el SMMU siga sin bindear; útil como plan B si H y C fallan.
- URLs: `msm_kms.c` (requisito de IOMMU) https://raw.githubusercontent.com/torvalds/linux/master/drivers/gpu/drm/msm/msm_kms.c ·
  `arm-smmu.c` (RMR/IORT bypass, sólo ACPI) https://raw.githubusercontent.com/torvalds/linux/master/drivers/iommu/arm/arm-smmu/arm-smmu.c ·
  ejemplo vendor de bypass en DT stock `stockuke.dts:4845`.

**Descartado explícitamente**: reset parcial por fases (`uke_reset_mask=0xc`) — funciona
(#P11/P15) pero deja estado sucio y depende de carreras: sirve de diagnóstico, no de solución.
"Quitar `iommus` del DPU" tampoco: msm balea en `msm_kms.c:198` (evidencia arriba).

### 7.2 Para **GPU**

**1º — Mantener el camino kgsl-smmu actual + adoptar el soporte A735 de Codeberg.**
El kgsl-smmu **no depende del apps-smmu**: ya probea y bindea en la tablet
(`dmesg-arch.txt:0.321401` "arm-smmu 3da0000.kgsl-smmu: probing hardware configuration…" +
"Adding to iommu group 0/1" y `msm_dpu … bound 3d00000.qcom,kgsl-3d0`). El A735 (chipid
`0x43030b00`) y `gmu-735.0` **no están en mainline** (`a6xx_catalog.c`: no hay `43030b00`) pero
**sí en el árbol Codeberg** (`drm/msm/adreno: Add Adreno 735 support`; el fork ya tiene la entrada
en `a6xx_catalog.c:1618`). Mantener: OPP/GPUCC de lamma/palawan + firmware vendor `gen71100_*`
(paquete propio `build/pkg/uke-gpu-firmware`, zap firmado por SKU).
URLs: https://raw.githubusercontent.com/torvalds/linux/master/drivers/gpu/drm/msm/adreno/a6xx_catalog.c (no A735) ·
commits Codeberg (A735/gmu-732+735) https://codeberg.org/palawan-mainline/linux/commits/branch/palawan/v7.2-rc2

**2º — Corregir la ficha del SoC para las OPP/LLCC (lamma vs palawan).**
Si el silicio real es lamma (SM7675) las OPP de A732 y `lamma-llcc` son las correctas; si es
palawan (SM8635/A735) hay que usar las de palawan. La ambigüedad (§5.2) puede estar causando
"symptoms" en GMU/OPP. Se puede discriminar en caliente (leer el chipid de la GPU por
kgsl/dmesg y compararlo con `a6xx_catalog.c`), sin tocar la pantalla.
URLs: `lamma.dtsi` vs `palawan.dtsi` (Codeberg), tabla de chipids mainline arriba.

**3º — Firmware/paquete**: mantener el empaquetado propio (`gen71100_gmu.bin`, `gen71100_sqe.fw`,
`gen71100_zap.mbn`) con los SHA ya publicados, y no mezclar el ZAP del QRD (avisado en
`firmware-gpu.sha256`). Si se necesita el firmware "oficial" para freedreno/mesa, la vía es
linux-firmware (no comprobable hoy desde aquí: fd.o bloquea).

---

## 8. Anexo — índice de URLs citadas

Upstream / lore
- https://lore.kernel.org/all/?q=sm7675 · ?q=palawan · ?q=lamma · ?q=handoff-smrs · ?q=sm8635 · ?q=sm8650-mdss
- https://lore.kernel.org/all/xAsYX3yZX3laVVaqB8tdxUoTWM3jFlYudJ7j62r-6redf_OJgS_eY2mEypJ0Ma8B26RKeCqQU2G7pYTKapYx0M0rPAEvdpA2oyOs4XA8tcE=@proton.me/
- https://lore.kernel.org/all/wtyikmhzyizezs45yqubflxivxj2iyk6dkutn643v7iokvqfcy@fxmysaq26gg5/
- https://lore.kernel.org/all/9nTdr-7UlyytB3d5Iz0IEGrAAzjPipf4NEiZvLMmpk9OmCmRuL346OxjZgpLkLdG7dFYE_rj-5aibg7bhYHrQmjwo1e096-2IGhfi1rKglE=@proton.me/
- https://lore.kernel.org/all/Uczku8TWm_yEdSMe9v2PZC6eDhmbXxr6yhqW6poltQ_xP52gQ5ZYRsiXGlkYxfVQGQjVhr0Bl86ncNVVx8aPe0JtRtK1uYZeN3LNXH-xE7o=@proton.me/
- https://lore.kernel.org/all/f10a13af-c4e7-47df-9e9d-7efed30b2147@kernel.org/
- https://raw.githubusercontent.com/torvalds/linux/master/{Documentation/devicetree/bindings/iommu/arm,smmu.yaml, include/dt-bindings/arm/qcom,ids.h, drivers/iommu/arm/arm-smmu/arm-smmu.c, drivers/iommu/arm/arm-smmu/arm-smmu-qcom.c, drivers/pinctrl/qcom/Kconfig.msm, drivers/gpu/drm/msm/adreno/a6xx_catalog.c, drivers/gpu/drm/msm/msm_kms.c, arch/arm64/boot/dts/qcom/sm8650.dtsi, arch/arm64/boot/dts/qcom/sm8550.dtsi}
- https://api.github.com/repos/torvalds/linux/contents/drivers/gpu/drm/msm/disp/dpu1/catalog
- https://chromium-review.googlesource.com/q/project:chromiumos/third_party/kernel+arm-smmu
- https://chromium-review.googlesource.com/c/chromiumos/third_party/kernel/+/6267947

Comunidad / BSP
- https://codeberg.org/palawan-mainline/linux · /u-boot (vacío) · /firmware-qualcomm-qrd8635
- https://codeberg.org/api/v1/repos/palawan-mainline/linux/branches · …/commits?sha=palawan/v7.2-rc2
- https://codeberg.org/palawan-mainline/linux/raw/branch/palawan/v7.2-rc2/arch/arm64/boot/dts/qcom/palawan.dtsi
- https://codeberg.org/palawan-mainline/linux/raw/branch/palawan/v7.2-rc2/Documentation/devicetree/bindings/iommu/arm,smmu.yaml
- https://gitlab.com/philmb3487/muyu6.17-dt (sm8635.dtsi, sm8635-muyu.dts) · http://muyuwiki.ca
- https://github.com/Xiaomi-Pad-7-Pro-Resources/{android_kernel_xiaomi_sm8635, android_kernel_xiaomi_sm8635-devicetrees, android_kernel_common_android14-6.1}
- https://raw.githubusercontent.com/Xiaomi-Pad-7-Pro-Resources/android_kernel_xiaomi_sm8635/lineage-23.0/drivers/iommu/arm/arm-smmu/arm-smmu.c
- https://github.com/peridot-dev/android_kernel_xiaomi_sm8635/commit/67568e2de13251f28eaacf64343305e19020c854
- https://github.com/CodeLinaro-mirror/le_kernel_msm-5.15/commit/8fa3cecff06e7aeba00e0f463714c4ad09dcca30 · …/18d1a0b7a412ee821aa92f0dc2e54ced8bb79611
- https://wiki.postmarketos.org/wiki/Xiaomi_Pad_7_(xiaomi-uke)
- https://github.com/vember31/android_device_xiaomi_uke-me · https://github.com/StampyCat889/Linux-UKE · https://github.com/HuangJunLin8/uke_gki_kernel · https://github.com/AbhinavBan/android_kernel_xiaomi_uke (vacío)

Evidencia local usada
- `build/gates/PRE-REGISTRO-PANTALLA.md` (#P8–#P16, serie K1–K6)
- `build/evidencia/2026-09-28/dmesg-arch.txt` (kgsl-smmu 0.321 s; "Uke based on SM8635")
- `build/bootimg/cmdline-orig.txt` (`kiwi_v2`, `arm-smmu.disable_bypass=0`)
- `~/gpu-work/w15-dt/stockuke.dts` (apps_smmu 13180, handoff-smrs 13186, kgsl-smmu 13149, bypass 4845)
- `~/gpu-work/palawan-linux/` (fork 7.2-rc2; `arm-smmu-qcom.c:584` IDENTITY; `msm_kms.c:198`; `a6xx_catalog.c:1618`; `xiaomi-uke.dts` msm-id 643)
- `~/proyectos/ubuntu-uke/stock/dtbase/base-uke.dts` (Adreno735 / chipid 0x43030b00)
