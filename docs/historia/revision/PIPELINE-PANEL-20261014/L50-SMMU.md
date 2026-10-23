# L50-SMMU — ¿Es traducible el fetch del cmd-DMA del DSI? (14-oct-2026)

> Solo lectura: árbol `build/kernel-pokes/k52-L16-tree`, captura `out/CAPTURA-MUERTE-*.log`
> (muerte display-ON de hoy), SSH de lectura al boot vivo actual (sin DCS aún), ledger hermano.
> **MEDIDO** = visto en log/código/sysfs. **HIPÓTESIS** = marcado como tal.

## 1. VEREDICTO: NO — el fetch del cmd-DMA no es traducible con `uke_keep_boot=1` + `wmask=0`

El IOVA del `tx_gem` (tablas solo en RAM) nunca llega al HW: el CB nuevo (69) no se programa
y el S2CR del display no se actualiza. El primer fetch SMMU del display en todo el boot es
justo este DCS, y cae en el contexto del BL. Detalle y fixes en §5.

## 2. De dónde sale `priv->kms->vm` y su attach (MEDIDO)

- `dpu_kms` pide la VM con el padre mdss como fallback: `dpu_kms.c:1111`
  (`msm_kms_init_vm(dpu_kms->dev, parent)`), `_dpu_kms_mmu_init` en `:1107-1116`.
- `msm_kms_init_vm` (`msm_kms.c:183-233`): usa `mdp_dev` si está mapeado, si no el `mdss_dev`
  (`:191-201`); log K13 en `:209-212`; crea el mmu con `msm_iommu_disp_new` (`:214`).
- DT base: `iommus=<0x1c00 0x2>` SOLO en el mdss (`palawan.dtsi:3357/3379`; igual
  `sm8550.dtsi:4081`, `sm8650.dtsi:5606`; hijos DPU/DSI/PHY sin `iommus`).
- DT vivo (s260+s261): el DPU es dueño único (`/proc/device-tree/.../display-controller@ae01000/iommus`
  = `<phandle 0x1c00 0x2>` por SSH; `dsi@ae94000/ae96000` SIN `iommus`; `iommus` del mdss vacía).
  Por eso el log dice `iommu_dev=ae01000.display-controller (mdp=mapeado mdss=no)` (dmesgw:2806).
- `msm_iommu_new` (`msm_iommu.c:732-817`): dominio paging propio + handler K39 (`:759-768`) +
  `iommu_attach_device`; `msm_iommu_disp_new` (`:819-829`) lo cambia al handler de display.
  Log vivo: `UKE-K39` + `UKE-K38: attach ... sid=7168 -> cbndx=69` (dmesgw:2807/2814).

## 3. SID del cmd-DMA y qué deja `uke_keep_boot` (MEDIDO)

- El cmd-DMA no tiene stream propio: ningún nodo DSI declara `iommus` (árbol + DT vivo).
  Su fetch sale con el SID del subsistema display **0x1c00 mask 0x2** (banda única del mdss;
  fwspec `0x21c00` en el attach, dmesgw:2814). La emisión HW exacta del SID no es
  observable sin fault-log → HIPÓTESIS apoyada (un solo mapeo SMMU para todo el display).
- `uke_keep_boot=1` + `uke_reset_mask=12` + `wmask=0x0` (cmdline dmesgw:163; params vivos
  `0/Y/12/2/0` por SSH): fase2 y fase3 OMITIDAS (dmesgw:1817-1819), `test_smr_masks` omitido
  (`:1827`), y F4/F5/F6/F7/quirk/attach/install/ctxbank SILENCIADOS (`:1810`, `:1820-1826`).
  Efectivo: **cero escrituras SMMU nuevas en todo el boot** (solo fase1 sGFSR, incondicional).
- Barrido handoff: `PIN SMR(2) HW=0x80021c00 id=0x1c00 mask=0x2` (dmesgw:1799) → idx 2 del BL
  intocable. El S2CR(2) del BL **nunca se lee** (letal #P13, `:1795`) → el CB del BL es ilegible.
- Display en el attach: `find_sme(...0x1c00...) -> 20` + `UKE-K12: handoff no-vivo -> attach normal`
  pero `wmask[attach_sme]: SILENCIADO` (dmesgw:1904-1909): el mapeo nuevo queda SOLO en RAM.
- Dominio nuevo: `CB 69 reservado DESDE ARRIBA` (`:2809`), `write_context_bank idx=69` (`:2810`)
  pero `wmask[ctxbank]: SILENCIADA ... NO se escriben CBAR/CBA2R/TCR/TTBR/MAIR/SCTLR` (`:2811`);
  `install_s2cr idx=20 type=0 cbndx=69` (`:2812`) pero `wmask[install_s2cr]: SILENCIADO ...
  el HW sigue con el S2CR del BL` (`:2813`).

## 4. Mismatch exacto + por qué el silencio es total

- **Mismatch (MEDIDO)**: HW traduce SID 0x1c00 con `S2CR(2)`=valor del BL → CB del splash
  (índice y tablas desconocidos, ilegibles). Las tablas del kernel (VM `mdp_kms`, CB69, TTBR
  con `tx_gem` en IOVA `0x1000/0x2000` — verificado mapeado en
  `/sys/kernel/debug/dri/ae01000.display-controller/gem` por SSH: `vmas: [mdp_kms ... mapped]`)
  existen solo en RAM. IOVA 0x1000 en el contexto del BL = fault (o fetch físico si bypass).
- Es el **primer tráfico SMMU del display en todo el boot** (antes solo MMIO a dominios con
  reloj; todo pasó: `L49-*-ok`, `K47-pwr-OK`, reset K48). Ventana de muerte = [host-xfer,
  commit `REG_DSI_DMA_*` (`dsi_host.c:2379-2386`), wait 200 ms] → encaja con fetch intraducible.
- Silencio explicado (mitad MEDIDO, mitad HIPÓTESIS): `S4-DIAG`=0 y `fault`=0 en ambas
  capturas (grep: 0 líneas) ⇒ la CPU murió antes del print del timeout. El handler K39/disp
  vive en el dominio NUEVO (CB69, sin HW) — un fault en el CB del BL no tiene handler Linux
  que lo imprima (MEDIDO el attach; HIPÓTESIS la ruta del fault). Escalado a freeze → reset
  PMIC `0x80100` (HIPÓTESIS; coherente con NOC colgado por fetch sin respuesta).
- Nota honesta: `type=identity` en los 20 grupos (incluido el 17 del display, por SSH) es el
  `default_domain` (`iommu.c:999-1011`), no el dominio attacheado — MEDIDO pero no probatorio;
  no sostiene el veredicto.
- Refutación previa #445 (hermano, 30-sep): refutó "SMMU asesina del **modeset del boot ~4 s**"
  (era el CM3/GMU, ledger #447). La muerte de hoy es a ~1389 s en el **primer DCS**, punto que
  entonces jamás se alcanzó. No colisionan.

## 5. `tx_gem` y handlers (MEDIDO en código)

- `dsi_tx_buf_alloc_6g` (`dsi_host.c:1246-1270`): `msm_gem_kernel_new(..., msm_host->vm=priv->kms->vm...)`
  → IOVA de la VM del KMS; error → `NULL` + código (sin IOVA bogus). `v2` (`:1272-1285`) es
  `dma_alloc_coherent` (paddr, sin IOMMU de KMS).
- Los 3 ops 6G usan el par `_6g` (`dsi_cfg.c:263-296`); `v2` solo en el handler fósil apq8064
  (`:251-259`). Versión leída del HW (`dsi_get_version` `:40-81`, `dsi_get_config` `:202-241`):
  **coincide siempre** con `dsi_dma_base_get_6g` (`:1426-1436` = `msm_gem_get_and_pin_iova`).
- `msm_gem_get_and_pin_iova*` (`msm_gem.c:528-573`): solo escribe `*iova` si `ret==0`;
  `dsi_cmd_dma_tx` (`:1447+`) aborta con `pr_err` si falla — ausente en la captura ⇒ el IOVA
  salió (de tablas RAM) OK. `xfer_prepare` (`:2135-2145`) falla en voz alta si no hay tx buf.

## 6. Fixes rankeados (mecanismo + riesgo + gate)

- **F0 (0 escrituras, antes de todo)**: un `pr_err` con el `dma_base` en `dsi_cmd_dma_tx`
  (`:1449`). Cierra en el boot mortal lo hoy inferido (IOVA~0x1000 de tablas RAM).
- **F1 (recomendado, 1 escritura)**: `arm_smmu.uke_write_mask=0x180` (bits 7+8 =
  `INST_S2CR|CTXBANK`, `arm-smmu.h:622-624`): programa CB69 + apunta S2CR(20)→CB69. El PIN
  blinda los 5 idx del BL; el resto de maestros siguen RAM-only. Criterio: userspace + DCS
  completo o S4-DIAG visible. Riesgo MEDIO (CB mal formado = cuelgue; recuperación standard).
- **F2 (diagnóstico, 1 escritura)**: S2CR del display a BYPASS un ciclo: si el DCS completa
  (basura al panel, sin muerte) ⇒ causa-traducción confirmada. No es fix (el scanout exige
  traducción). Riesgo MEDIO-BAJO.
- **F3 (último recurso)**: quitar `uke_keep_boot` (reprogramación total). Riesgo ALTO: el
  probe completo colgaba el boot (origen de keep_boot; R-39/R-40 hermano). Solo con red de
  recuperación total.
- **NO hacer**: MMIO/`/dev/mem` en runtime (reglas); `unbind/bind` del display en vivo para
  re-attachar (los params son 0644 —`arm-smmu.c:264/290/415/894`— pero el attach ya ocurrió;
  el cambio pide reboot, no write sysfs).
- Gate común: batería ≥3700, slots leídos pre/post, ≤2 escrituras/día, ACM lector único +
  vigía, `fastboot boot` preferido si cabe por tamaño (R-12: usa dtbo del slot), rollback
  L49 + s287. K16-wm (`0x1c0`=bits 6,7,8) murió a 4 s en OTRA era (killer GMU) — sin dato
  sobre DCS con CB traductor: el experimento F1 es inédito.

## 7. NO verificado

SID emitido en el cable por el motor cmd-DMA; contenido/índice del CB del BL (ilegible #P13);
ruta exacta del escalado fault→freeze→`0x80100`; valor de `dma_base` en el boot mortal (→F0).
