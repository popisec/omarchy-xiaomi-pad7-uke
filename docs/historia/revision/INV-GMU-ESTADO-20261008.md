# INV-GMU-ESTADO #543 — Mapa del estado del dominio GMU que deja el vendor antes de soltar el reset, y plan k61

**Fecha**: 8-oct-2026. **Tipo**: ingeniería inversa OFFLINE. 0% tablet, 0% compilación.
**Fuentes**: `build/evidencia/android-full/extracted-full/` (01-gpu, 15-common, 14-dt/dt-live),
`build/evidencia/android-full-gaps/` (h1–h4), DT vivo Android desempaquetado en `/tmp/inv-gmu/dt-live`
(espejo de `14-dt/dt-live.tar.gz`), nuestro DT fusionado `/var/tmp/uke-s272/m272.dtb` (descompilado),
árbol kernel `build/kernel-pokes/k52-tree/` (k60 + pokes), vendor-clk `~/proyectos/ubuntu-uke/vendor-src/cliffs/`,
ledger #535–#542.
**Complementario a**: `docs/historia/revision/DISENO-K61-20261008.md` + `docs/historia/revision/k61-gmu-staged.diff` (mismo commit 0338954) — ese
doc diseña las sondas kernel y el S3 escalonado; este aporta el MAPA del vendor que se quiere
replicar, las diferencias DT accionables y las correcciones de dirección que aquel necesita (§6.4).

---

## 1. Resumen ejecutivo

1. **La física del dominio en el vendor en estado estable** (con GPU en mínimo, 255 MHz, pwrlevel 8):
   - GX y CX GDSC **OFF** (regulador `enable=0`; el dominio colapsa en idle vía IFPC del GMU fw).
   - `gpu_cc_cx_gmu_clk` 220 MHz, `gpu_cc_hub_cx_int_clk`/`gpu_cc_hub_aon_clk` 200 MHz y
     `gcc_ddrss_gpu_axi_clk` **siempre ON** con consumidor `qcom,gmu@3d69000`; `gpu_cc_ahb` 200 MHz
     (gated en idle, ON con GPU activa), `gpu_cc_hlos1_vote_gpu_smmu` y `gpu_cc_memnoc_gfx` gated
     fuera de actividad (IFPC las recorta).
   - El estado "de partida" del CM3 lo fabrica **XBL/AOP + el propio fw del GMU**, no hay escrituras
     RSC/PDC del CPU en cold boot (k60 ya neutro ⇒ correcto).
2. **El vendor NO usa genpd para el GMU**: `vddcx-supply`/`vdd-supply` = reguladores GDSC
   (`gdsc@3d9908c` CX / `gdsc@3d99034` GX). Nosotros usamos `power-domains = <&gpucc 0 1>`.
   **Mismos registros físicos** (GDSCR CX 0x3D9908C, GX 0x3D99034, CX hw_ctrl 0x3D990A0 — verificado
   contra el syscon/reg del DT vivo), camino de software distinto.
3. **El desfase de clock-ids GPUCC (-2) entre el header vendor y nuestro `qcom,palawan-gpucc.h` está
   TOTALMENTE curado** tras s272: los índices del nodo gmu y del nodo smmu en m272 son coherentes
   con NUESTRO enum (AHB=0, CX_GMU=7, CXO=9, HUB_CX_INT=0x12, HLOS1=0xF, DEMET=0xA) y GCC es
   idéntico en ambos árboles (DDRSS_GPU_AXI=0x12, MEMNOC=0x20, SNOC_DVM=0x21). No queda ninguna
   colisión conocida de ids en el dominio GPU.
4. **Diferencias DT accionables restantes** (candidatas de causa física, en orden): (a) la
   **kgsl-smmu no vota CX** (vendor: `vdd-supply` regulator con usecount 3; nosotros: ni PD ni
   regulador — mainline sm8650 la ata a `gpu_cc_cx_gdsc`), (b) **sin voto interconnect del GPU**
   (`interconnects` vacío en msm_gpu; vendor vota `gem_noc 17 → mc_virt 512`; el port lo vació
   adrede en la era GPU-off por el wedge #286, y sin `.bcms` un voto sería solo contable), (c)
   **`qcom,qmp` en el nodo equivocado** (GPU en vez de GMU: s271), (d) sin **SIDs de contexto
   vendor** (`qcom,kgsl-iommu` children: gfx3d_user SID0 / gfx3d_secure SID2; el SID2 no existe en
   nuestro árbol — bomba post-CM3, no causa del freeze), (e) sin ACD (`qcom,acd-level` ×9 del
   vendor extraídos — §2.4; **no replicar aún**: §7).
5. **CORRECCIÓN a DISENO-K61 §3.1.d**: `GPU_CC_GX_GDSCR` del XML está en word 0x24403 ⇒ byte
   0x9100C ⇒ **phys 0x3D9100C = GFX3D_AON_BCR** (tabla de resets de `gpucc-palawan.c`), NO el
   GDSCR. El GDSCR real (vendor DT + driver GDSC) es **0x3D99034** (GX) y **0x3D9908C** (CX), o en
   words GPU-relativas para `gmu_read`: **0x240D** (GX) y **0x2423** (CX). La sonda ENV-GDSC tal
   como está escrita leería un BCR (inofensivo pero falso). Detalle en §6.4.

---

## 2. Inventario del dominio GMU del vendor (captura Android)

### 2.1 Clocks GPU del dominio (clk_summary, idéntico en 01-gpu y 15-common; estado: GPU idle pwrlevel 8)

Tabla completa de los 39 relojes gpu_cc/gcc del dominio. Columnas vendor: `enable_cnt prepare_cnt rate enable_state consumidor`.

| Clock | enable_cnt | prepare_cnt | rate | ON | Consumidor(es) |
|---|---|---|---|---|---|
| gpu_cc_cx_gmu_clk | 0 | 0 | 220 MHz | **Y** | qcom,gmu@3d69000 |
| gpu_cc_hub_cx_int_clk | 0 | 0 | 200 MHz | **Y** | qcom,gmu@3d69000 |
| gpu_cc_hub_aon_clk | 0 | 0 | 200 MHz | **Y** | (deviceless — AON del hub) |
| gpu_cc_hub_clk_src | 0 | 0 | 200 MHz | **Y** | (padre de los dos anteriores; ← gpu_cc_pll0 510 MHz) |
| gpu_cc_pll0 | 0 | 0 | 510 MHz | N | (padre hub_clk_src) |
| gpu_cc_pll1 | 0 | 0 | 440 MHz | N | (padre gmu_clk_src) |
| gpu_cc_gmu_clk_src | 0 | 0 | 220 MHz | N | (padre cx_gmu; 440/2) |
| gpu_cc_ahb_clk | 0 | 0 | 200 MHz | N | gmu + kgsl-3d0 + kgsl-smmu |
| gpu_cc_crc_ahb_clk | 0 | 0 | 200 MHz | N | (deviceless) |
| gpu_cc_cxo_clk | 0 | 0 | 19,2 MHz | N | qcom,gmu@3d69000 |
| gpu_cc_xo_clk_src | 0 | 0 | 19,2 MHz | **Y** | (deviceless) |
| gpu_cc_xo_div_clk_src | 0 | 0 | 4,8 MHz | **Y** | (deviceless) |
| gpu_cc_freq_measure_clk | 0 | 0 | 4,8 MHz | N | (deviceless) |
| gpu_cc_demet_div_clk_src | 0 | 0 | 19,2 MHz | **Y** | (deviceless) |
| gpu_cc_cx_accu_shift_clk | 0 | 0 | 19,2 MHz | N | (deviceless) |
| gpu_cc_ff_clk_src | 0 | 0 | 19,2 MHz | N | (deviceless) |
| gpu_cc_cx_ff_clk | 0 | 0 | 19,2 MHz | N | (deviceless) |
| gcc_ddrss_gpu_axi_clk | 0 | 0 | 0 (no rate) | **Y** | **qcom,gmu@3d69000** (AXI GPU→DDRSS) |
| gcc_gpu_memnoc_gfx_clk | 0 | 0 | 0 | N | gmu + kgsl-3d0 + kgsl-smmu |
| gcc_gpu_snoc_dvm_gfx_clk | 0 | 0 | 0 | N | kgsl-3d0 + kgsl-smmu |
| gcc_qmip_gpu_ahb_clk | 0 | 0 | 0 | N | (deviceless) |
| gpu_cc_hlos1_vote_gpu_smmu_clk | 0 | 0 | 0 | N | 3da0000.kgsl-smmu |
| gpu_cc_memnoc_gfx_clk | 0 | 0 | 0 | N | (deviceless en esta captura) |
| gpu_cc_mnd1x_0_gfx3d_clk / mnd1x_1 | 0 | 0 | 0 | N | (deviceless) |
| gpu_cc_sleep_clk | 0 | 0 | 0 | N | (deviceless) |
| gpu_cc_debug_mux | 0 | 0 | 0 | **Y** | (deviceless) |
| measure_only_gpu_cc_{gx,cx}_gfx3d, demet, cxo_aon, measure_only_gcc_gpu_cfg_ahb | 0 | 0 | 1 kHz | Y | (medidores internos) |
| gpu_cc_cx_gfx3d_clk / cx_gfx3d_slv_clk | — | — | — | — | (existen en árbol, gated) |

Claves de estado (muestras runtime h2/h3, GPU activa 255 MHz busy 7%): mismos patrones —
`cx_gmu` 220 ON, `hub_cx_int`/`hub_aon` 200 ON, `ddrss_gpu_axi` ON, `hlos1` N, `memnoc_gfx` N.

### 2.2 Reguladores del dominio GPU (regulator_summary 15-common)

| Regulador (GDSC) | enable | usecount | Consumers | Parent (jerarquía) |
|---|---|---|---|---|
| `gpu_cc_cx_gdsc` (reg 0x3D9908C, retain-regs, clk_dis_wait_val=8, no-status-check-on-disable, hw_ctrl 0x3D990A0) | 0 | **3** | `3d68000.qcom,gmu-vddcx`, `3da0000.qcom,kgsl-iommu-vddcx`, `3da0000.kgsl-smmu-vdd` | `pm_v8_s6_level` (CX rail) ← parent `pm_v6c_s1_level` |
| `gpu_cc_gx_gdsc` (reg 0x3D99034, retain-regs, support-cfg-gdscr, parent `pm_v6c_s6_gfx_voter_level`) | 0 | **1** | `3d68000.qcom,gmu-vdd` | ← `pm_v6c_s6_gfx_voter_level` (MXC/GFX) |

Interpretación: en el vendor **TRES consumidores votan CX vía regulador** (gmu, kgsl-iommu, smmu).
En nuestro árbol: cero consumidores de regulador; CX se enciende por genpd desde el gmu
(`power-domains`), y **la SMMU no vota nada** (ver §4.2, diff #1).

### 2.3 Nodo GMU vendor (`/soc/qcom,gmu@3d69000` — DT vivo) — props completas

| Prop | Valor (crudo) | Decodificado |
|---|---|---|
| compatible | `qcom,gen7-gmu` | — |
| reg | `<0x03d68000 0x37000> <0x0b280000 0x10000> <0x03d40000 0x10000>` | gmu (incluye gpucc 3d90000 y GDSCs), gmu_pdc, gmu_ao_blk_dec0 |
| reg-names | `gmu, gmu_pdc, gmu_ao_blk_dec0` | 3 rangos |
| clock-names | `gmu_clk, cxo_clk, axi_clk, memnoc_clk, ahb_clk, hub_clk` | 6 |
| clocks | `<0x175 9> <0x175 0xb> <0x16e 0x12> <0x16e 0x20> <0x175 2> <0x175 0x14>` | gpucc{GMU=9, CXO=0xb, AHB=2, HUB_CX_INT=0x14} + gcc{DDRSS_GPU_AXI=0x12, MEMNOC=0x20} — **numeración vendor** (ver §4.4) |
| regulator-names | `vddcx, vdd` | — |
| vddcx-supply | `<0x1bd>` | gdsc@3d9908c = **CX GDSC (regulador)** |
| vdd-supply | `<0x401>` | gdsc@3d99034 = **GX GDSC (regulador)** |
| interrupts | `<0 0x130 4> <0 0x131 4>` | HFI = GIC_SPI 304, GMU = GIC_SPI 305 (level-high) — idénticos a los nuestros |
| interrupt-names | `hfi, gmu` | — |
| iommus | `<0x1c1 5 0>` | kgsl-smmu, **SID 5**, arg2=0 — idéntico al nuestro |
| mboxes / mbox-names | `<0x3b3 0>` / `aop` | **AOP QMP** — presente TAMBIÉN en nuestro m272 |
| qcom,gmu-freq-table | `<0x0d1cef00 0x40> <0x20c85580 0x80>` | 220 MHz/lvl 64, 550 MHz/lvl 128 — idéntico |
| qcom,ipc-core | `<0x00400000 0x14>` | IPC log: **0x14**, nuestro: 0x140000 (difiere; prop no consumida por mainline) |
| qcom,iommu-dma | `"disabled"` | idéntico al nuestro |
| (sin) status / memory-region / operating-points-v2 / power-domains | — | **el vendor no declara ninguna de las cuatro** |

El nombre del nodo (`3d69000`) no coincide con `reg[0]` (0x3d68000): el platform-device vendor se
llama `3d68000.qcom,gmu` (dmesg + regulator_summary). Nuestro árbol conserva exactamente ese reg[0].

### 2.4 GPU vendor (`qcom,kgsl-3d0@3d00000`) — props relevantes al GMU

- compatible `qcom,adreno-gpu-gen7-11-0` + `qcom,kgsl-3d0`; `qcom,gpu-model = "Adreno732"`;
  `qcom,chipid = <0x43030b00>` (idéntico a nuestro opp/compatible base).
- reg (7 rangos): `kgsl_3d0_reg_memory` 3d00000+40000, **`rscc` 3d50000+10000**, `cx_dbgc`
  3d61000+800, **`cx_misc` 3d9e000+1000**, qdss_etr/gfx/tmc. (Nuestro: mismo mapa con 4º rango
  `cx_mem` 3d9e000+**2000** — mismo bloque, 2 KB vs 1 KB.)
- clocks: `gcc_gpu_memnoc_gfx (gcc 0x20)`, `gcc_gpu_snoc_dvm_gfx (gcc 0x21)`, `gpu_cc_ahb (gpucc 2)`,
  `apb_pclk (<0x23>=aoss_qmp)` — **nosotros: `clocks; clock-names;` VACÍOS** (los 3 primeros los
  cubre el bulk del nodo smmu; `apb_pclk` es debug/QDSS).
- interconnects: `<0x1a2 0x11 0x188 0x200>` = `gem_noc 17 → mc_vict 512` (MASTER_GFX3D→SLAVE_EBI1,
  **numeración vendor de ids**), name `gpu_icc_path`. **Nuestro: `interconnects;` VACÍO.**
- `qcom,gpu-pwrlevels`: 9 niveles (0x190…0x38 = 950…255 MHz, mismas freqs y levels que nuestra
  opp-table), `qcom,initial-pwrlevel = <8>` (el mínimo); **cada nivel lleva `qcom,acd-level`**
  (tabla completa §5.3) y `qcom,bus-freq/min/max` (índices a `qcom,bus-table-ddr`, tabla idéntica
  a la nuestra).
- zap-shader → memory-region 0x29e = `gpu_microcode_region@9899a000` (idéntico).
- `qcom,tzone-names` gpuss-0..3, `qcom,ubwc-mode=4`, `qcom,min-access-length=0x20`,
  `qcom,gpu-qdss-stm <0x161c0000 0x40000>`, `qcom,bus-table-ddr` (10 entradas) y `bus-table-cnoc`
  (2): **idénticos** a los nuestros.
- **SIN** `power-domains` y **SIN** `iommus` (el attach lo hace el nodo `qcom,kgsl-iommu@3da0000`).

### 2.5 debugfs kgsl del vendor (01-gpu + h1)

`acd_calibrate=0`, `ifpc_hyst=5760` (**= 0x1680 — exactamente el word bajo de
`GMU_PWR_COL_HYST = 0x000a1680` de mainline**: el vendor usa la MISMA histeresis IFPC que nuestro
árbol ya tiene como constante), `active_cnt=0` (captura en idle). `gmu-log`: el dd devolvió vacío
(nodo ausente en esa captura) — no hay log del CM3 disponible.

---

## 3. Registros del dominio que el vendor escribe antes de soltar el reset

### 3.1 Lo que NUESTRO k60 (k52-tree) escribe en resume — secuencia completa con valores

Todos los offsets son words GPU-relativas (física = 0x3D00000 + word×4; acceso real vía ventana
`gmu` 0x3D68000+0x37000 con `mmio_offset`=0x68000) o words RSCC-relativas (física = 0x3D50000 + w×4).

| # | Punto | Registro (offset) | Valor escrito | Fuente |
|---|---|---|---|---|
| 1 | resume H1/H2 | pm_runtime gmu + `gxpd` get | genpd CX ON (GDSCR 0x3D9908C b0=1); GX: `gdsc_gx_do_nothing_enable` (**no escribe**) | `a6xx_gmu_resume` |
| 2 | resume H3 | clk_bulk 7 clocks + core 200 MHz + hub 200 MHz | enables de AHB/CX_GMU/CXO/AXI/MEMNOC/HUB_CX_INT/DEMET (halts 0x90C8/0x90E4/0x90F4/0x9198/0x7000/0x90FC + gcc) | id. |
| 3 | fw_start | `GPU_GMU_CX_GMU_CX_FALNEXT_INTF` (0x1fa5*) y `CX_FAL_INTF` | 1 / 1 (veto FAL10) | `a6xx_gmu_fw_start` |
| 4 | fw_start | `CX_MISC_TCM_RET_CNTL` (cx_misc 0x39 → phys 0x3D9E0E4) | 1 (TCM retention ON) | id. |
| 5 | fw_start H6 | `GMU_RSCC_CONTROL_REQ` (0x23b07) | BIT(1) → poll `RSCC_CONTROL_ACK` b1 → poll RSCC `SEQ_BUSY_DRV0`==0 → volver a 0. **SOLO si hubo `rpmh_stop` previo** (en cold boot el bit PDC_SLEEP no está ⇒ **no-op**) | `a6xx_rpmh_start` |
| 6 | fw_start H7 cold | ITCM/DTCM por `fw_load`: bloques del binario → `GMU_CM3_ITCM_START` (0x1b400+), `GMU_CM3_DTCM_START` (0x1c400+), BOs icache/dcache/dummy por IOVA | contenido de `gen71100_gmu.bin` | `a6xx_gmu_fw_load` |
| 7 | fw_start P1 | `GMU_CM3_FW_INIT_RESULT` (0x1f81c) | 0 | `a6xx_gmu_fw_start` |
| 8 | fw_start P1 | `GMU_CM3_BOOT_CONFIG` (0x1f801) | **0x02** | id. |
| 9 | fw_start P2 | `GMU_HFI_QTBL_ADDR` (0x1f985) / `GMU_HFI_QTBL_INFO` (0x1f984) | iova HFI (0x10000-sized BO; K-log: `hfi=…`) / 1 | id. |
| 10 | fw_start P2 | `GMU_AHB_FENCE_RANGE_0` (0x23b11) | BIT(31) \| (0x32<<18) \| 0x8a0 = **0x8C808A0** (esperado K44 E) | id. |
| 11 | fw_start P2 | `GMU_CM3_CFG` (0x1f82d) | **0x4052** | id. |
| 12 | fw_start | `A7XX_GMU_GENERAL_10` | gmu_chipid **0x70B0000** | id. (a6xx_info) |
| 13 | fw_start | `A7XX_GMU_GENERAL_8` | log.iova[31:12] \| (log.size/4K−1) | id. |
| 14 | fw_start | gbif_cx (`a640_gbif`) escrituras GPU antes del wake | tabla del catálogo | id. |
| 15 | fw_start P3 | `GMU_SYS_BUS_CONFIG` (0x1f40f) / `GMU_ICACHE_CONFIG` (0x1f400) / `GMU_DCACHE_CONFIG` (0x1f401) | **1 / 1 / 1** y RETURN (a7xx no toca IFPC ni RPMH_CTRL) | `a6xx_gmu_power_config` |
| 16 | start S1/S2 | `GMU_CM3_SYSRESET` (0x1f800) | 1, luego (tras GENERAL_9=0 y re-assert) **0 en S3** | `a6xx_gmu_start` |
| 17 | start S2 | `A7XX_GMU_GENERAL_9` (log wptr) | 0 | id. |
| 18 | hfi_start | `GMU_HFI_CTRL_INIT` (0x1f986) | 1 (poll `HFI_CTRL_STATUS`) | `a6xx_gmu_hfi_start` |
| 19 | post-boot | `GMU_AO_HOST_INTERRUPT_CLR/MASK` (0x23b04/0x23b06), `GMU_GMU2HOST_INTR_CLR/MASK` (0x1f991/0x1f993) | ~0 / ~IRQ_MASK | resume |
| — | **NO escrito** | `GMU_RSCC_SEQ_MEM_0_DRV0` (RSCC 0x180+) uCode, `PDC_GPU_ENABLE_PDC`, TCS PDC | **0 escrituras** (k60 neutralizó `a6xx_gmu_rpmh_init`) | #542 ✓ |
| — | **NO escrito** | `GMU_PWR_COL_INTER_FRAME_CTRL` (0x1f8c0), `GMU_RPMH_CTRL` | 0 escrituras (a7xx early-return) | §3.2 |
| — | **NO escrito** | ACD (qmp_send `acd`) | 0 (qmp_get NULL — s271 en nodo equivocado) | #541-4 ✓ |

### 3.2 Lo que el VENDOR escribe distinto (inferencia de alta confianza)

| Registro/dominio | Vendor | Nuestro | Confianza y evidencia |
|---|---|---|---|
| **IFPC** (`GMU_PWR_COL_INTER_FRAME_CTRL` b17/b16 + HYST 0x1f8c1) | **IFPC ENABLED** (hyst 0x1680) | no escrito (GMU_IDLE_STATE_ACTIVE; el quirk IFPC existe en el catálogo pero NO en nuestro chip 0x43030b00) | `ifpc_hyst=5760` debugfs + #535 "IFPC=1" |
| **ACD** (AOP qmp `class: gpu, res: acd, val: 1` + tabla ACD al fw vía HFI) | **ON** con `qcom,acd-level` por pwrlevel (tabla §5.3) | NADA (sin tabla ni qmp) | #535 "ACD=1 estables"; DT §5.3 |
| **votos de rail** (CX/MX/GFX por RPMh vía **AOP mbox** del propio gmu) | votos por nivel del devfreq (bus-tables + vdd-class de gpucc `vdd_cx/vdd_mx/vdd_mxc-supply` → `pm_v6c_s1_level`/…) | CX solo por genpd GDSC; rails sin votante explícito (quedan al nivel de XBL) | §2.2 + jerarquía regulator_summary |
| **SMMU**: SMR0=SID0→CB0 y SMR1=SID5→CB1, S2CR=0x1 **antes de soltar el reset** | programado por kgsl vendor | **IGUAL ahora** (C1/k55: SME(0)→CB0, SME(1)→CB1, S2CR=0x00000001 — "EXACTO al vendor") | #535/#536 |
| GX GDSC | regulador `enable` real desde el driver | genpd no-op (por diseño mainline: GX lo gobierna el fw; GX "no gobernable desde CPU" en ambos) | §2.2 + #535 |
| RSC/PDC/AOP uCode | **0 escrituras CPU en cold** (lo configura AOP) | 0 escrituras (k60) — **ya réplica exacta** | #541-2/#542 |

**Lectura**: la secuencia MMIO del CM3 (BOOT_CONFIG/CFG/HFI/fence/ITCM) es la misma semántica en
ambos mundos (mismo fw). Las diferencias de ESCRITURA del vendor se concentran en **energía y
dominio** (IFPC, ACD, rails vía AOP, CX votado por la SMMU) — coherente con la conclusión #542 de
que el muro es "estado hardware del dominio (energía/relojes/interconexión)".

---

## 4. Diferencias DT vendor-vs-port, prop a prop

### 4.1 GMU (`qcom,gmu@3d69000`)

| Prop | Vendor (vivo) | Nuestro (m272) | Veredicto |
|---|---|---|---|
| compatible | `qcom,gen7-gmu` | igual | ✓ |
| reg / reg-names | 3 rangos (gmu, gmu_pdc, gmu_ao_blk_dec0) | 4 rangos (+ **rscc 3d50000+10000**) | port ✓ necesario (mainline a7xx `ioremap_byname("rscc")`; vendor lo mapea como reg[1] de kgsl-3d0) |
| clocks | 6, ids vendor: gmu=9, cxo=0xb, axi=gcc 0x12, memnoc=gcc 0x20, ahb=2, hub=0x14 | 7, ids nuestro-enum: ahb=0, gmu=7(CX_GMU), cxo=9(CXO), axi=gcc 0x12, memnoc=gcc 0x20, hub=0x12(HUB_CX_INT), **demet=0xa extra** | ✓ consistente con nuestro driver (§4.4); demet extra = inofensivo (bulk) |
| power-domains | **AUSENTE** | `<&gpucc 0> <&gpucc 1>` (cx, gx) | modelo distinto (genpd vs regulador); físicamente mismos GDSCR |
| regulator-names + vddcx/vdd-supply | vddcx=0x1bd, vdd=0x401 | **idéntico** (props heredadas, NO consumidas por mainline) | ✓ (DISENO-K61 §3.1.b dice "no existe xxx-supply en el nodo": **imprecisión** — existen, pero no se consumen) |
| operating-points-v2 | AUSENTE | `gmu_opp_table` (220/550) | port ✓ (mainline la requiere para pwrlevels) |
| qcom,gmu-freq-table | 220/64, 550/128 | idéntico | ✓ |
| interrupts / iommus / mboxes(aop) / qcom,iommu-dma | — | **idénticos** | ✓ |
| qcom,ipc-core | `<0x400000 0x14>` | `<0x400000 0x140000>` | DIFF menor (prop muerta en mainline; no tocar) |
| memory-region / status | AUSENTE / AUSENTE | AUSENTE / AUSENTE | ✓ |

### 4.2 SMMU private (`kgsl-smmu@3da0000`) — la tabla accionable

| Prop | Vendor (vivo) | Nuestro (m272) | DIFF y acción |
|---|---|---|---|
| compatible | `qcom,qsmmu-v500`, `qcom,adreno-smmu` | `qcom,palawan-smmu-500`, `qcom,adreno-smmu`, `qcom,smmu-500`, `arm,mmu-500` | DIFF esperada (arm-smmu vs driver vendor). SME/CB ya cuadran con el vendor (k55). Sin acción. |
| reg / reg-names | `<3da0000 40000> <3de6000 40>` base, tcu-base | idéntico | ✓ |
| #iommu-cells / #global-interrupts / #address/size-cells / ranges / dma-coherent / qcom,use-3-lvl-tables | 2 / 1 / 1/1 / vacía / vacía / vacía | idéntico | ✓ |
| interrupts | 26 specifiers: global 0x2a1 + CB 0x2a5..0x2af (11) + 0x1a6, 0x1dc, 0x23e, 0x23f, 0x240, 0x241, 0x293, 0x295, 0x298, 0x299, 0x29a, 0x29c, 0x29d, 0x2bb | **idéntico celda a celda** | ✓ |
| clocks (ids) | gpucc **0x11** hlos1, gcc 0x20 memnoc, gcc 0x21 snoc, gpucc **0x02** ahb | gpucc **0xf** hlos1, gcc 0x20/0x21, gpucc **0x0** ahb | ✓ s272 ya curó el desfase -2 (era el bug #541-1) |
| clock-names | hlos1, memnoc, snoc_dvm, ahb | idéntico | ✓ |
| **power-domains** | **AUSENTE** (el CX lo vota `vdd-supply` REGULADOR, usecount 3 en runtime) | **AUSENTE** | **DIFF #1 — ACCIÓN k61**: mainline sm8650 declara `power-domains = <&gpucc GPU_CC_CX_GDSC>`; nosotros ni PD ni regulador ⇒ la isla TCU no vota CX desde probe |
| vdd-supply | `<0x1bd>` (CX gdsc como regulador) | `<0x1bd>` presente pero **sin consumidor en arm-smmu** | DIFF #1b (misma pieza) |
| qcom,regulator-names | `vdd` | `vdd` | ✓ (inerte) |
| qcom,actlr | `<0 0x3ff 0x32b>` | idéntico | ✓ |
| gpu_qtb@3de8000 | base+debugchain 3de8000/3dec000, stream-id-range `<0 0x400>`, iova-width `<0x31>` (49 bits), num-qtb-ports 2, icc `<gem_noc 0 mc_virt 512>` | **idéntico** (phandle 0x3e1 incluido) | ✓ |

**SUS/SIDs numéricos del vendor (tal cual)**: GMU = **SID 5** (`iommus <&kgsl_smmu 5 0>`);
gfx3d_user = **SID 0**; gfx3d_secure = **SID 2** (children de `qcom,kgsl-iommu@3da0000`,
compatible `qcom,kgsl-smmu-v2`, reg 3da0000+40000, ambos `qcom,iommu-dma="disabled"`);
rango TBU GPU = **0..0x3ff**; actlr = stream 0 → `0x3ff/0x32b`. **Nuestro árbol no tiene ni el
nodo `qcom,kgsl-iommu` ni el SID 2** (nuestro GPU = `<&kgsl_smmu 0 0>` por `iommus` propio).
El SID2/secure es post-CM3 (#541-5): NO para k61.

### 4.3 GPU (`qcom,kgsl-3d0@3d00000`)

| Prop | Vendor | Nuestro | DIFF |
|---|---|---|---|
| compatible | `qcom,adreno-gpu-gen7-11-0`/`qcom,kgsl-3d0` | `qcom,adreno-43030b00`/`qcom,adreno` | esperada (DRM vs kgsl) |
| qcom,gmu | AUSENTE (lookup por driver) | `<0x482>` → gmu | port ✓ |
| **qcom,qmp** | AUSENTE | `<0x23>` = **aoss_qmp — EN EL NODO GPU** | **DIFF #2 — ACCIÓN k61**: moverlo al nodo GMU (a6xx_gmu_init hace `qmp_get(gmu->dev)`; hoy = NULL). Sin `qcom,opp-acd-level` no envía nada: seguro. |
| **interconnects** | `<gem_noc 17 0> <mc_virt 512 0>` real | **VACÍO** (name `gfx-mem` solo) | **DIFF #3 — APLAZADA (s274)**: ver §6.3/#286 |
| clocks | 4 (memnoc, snoc, ahb, apb_pclk=aoss_qmp) | VACÍO | DIFF aceptable (bulk de la smmu cubre 3; apb es debug) |
| reg[3] | `cx_misc` 3d9e000+**1000** | `cx_mem` 3d9e000+**2000** | nombre/longitud; mismo bloque (driver busca "cx_mem" ✓) |
| opp/pwrlevels | 9 pwrlevels + `qcom,acd-level` ×9 + bus-freq + initial=8 | opp-table 9 OPPs (hz+level, **sin acd, sin bw, sin required-opps**) | DIFF #4 (ACD) y #3b (sin bw en OPPs) |
| bus tables, zap, tzone, qdss-stm, ubwc, chipid, cooling | idénticos | idénticos | ✓ |

### 4.4 GPUCC (`clock-controller@3d90000`) — verificación del desfase de ids

| Prop | Vendor | Nuestro |
|---|---|---|
| compatible | `qcom,cliffs-gpucc` + `syscon` | `qcom,palawan-gpucc` |
| reg / reg-name | `<3d90000 0xa000>` / `cc_base` | idéntico |
| clocks | `<0x16c 0> <0x16c 1> <0x16e 0x1e> <0x16e 0x1f>` bi_tcxo, ao, gpll0, gpll0_div | idéntico |
| supplies | vdd_cx=0x147 (pm_v6c_s1_level), vdd_mxc=0x148, vdd_mx=0x14c | idéntico |
| #power-domain-cells | **AUSENTE** (GDSCs=reguladores) | `<1>` (GDSCs=genpd) |

**Mapa de índices GPUCC** (definitivo, de `qcom,gpucc-cliffs.h` vs `qcom,palawan-gpucc.h`):
`AHB 2↔0, CB 3↔1, CRC_AHB 4↔2, CX_ACCU 5↔3, CX_FF 6↔4, CX_GFX3D 7↔5, CX_GFX3D_SLV 8↔6,
CX_GMU 9↔7, CXO_AON 10↔8, CXO 11↔9, DEMET 12↔10, DEMET_DIV 13↔11, FF 14↔12, FREQ_MEAS 15↔13,
GMU_SRC 16↔14, **HLOS1 17↔15**, HUB_AON 18↔16, HUB_SRC 19↔17, HUB_CX_INT 20↔18, MEMNOC 21↔19,
MND1X 22/23↔20/21, PLL0/1 0/1↔22/23, SLEEP 24↔24, XO_SRC 25↔25, XO_DIV 26↔26`. Regla: **vendor =
nuestro + 2** (PLLs al final en el nuestro). GCC: **idéntico** (DDRSS_GPU_AXI=18=0x12,
MEMNOC=32=0x20, SNOC_DVM=33=0x21, CFG_AHB=29). GDSCRs (vendor DT = driver GDSC = verdad física):
CX `0x3D9908C`, GX `0x3D99034`, CX hw_ctrl `0x3D990A0`, GX clamp `0x3D99504`; resets: GX_BCR
0x9030, GFX3D_AON_BCR 0x910C, GMU_BCR 0x9164, ACD_BCR 0x9180, GX_ACD_IROOT_BCR 0x958C.
Halts: AHB 0x90C8, CX_GMU 0x90E4, HUB_CX_INT 0x90F4, MEMNOC 0x90FC, HUB_AON 0x9198, HLOS1 0x7000.

---

## 5. Anexos de estado

### 5.1 IRQs del dominio (idénticos en ambos árboles)
GPU 3d00000 = GIC_SPI 300 (kgsl_3d0_irq) · HFI = 304 · GMU = 305 · SMMU global = 673 (0x2a1) +
25 CB. Todos level-high (type 4).

### 5.2 Ventanas MMIO físicas del dominio
`3d00000+40000` (GPU) · `3d50000+10000` (RSCC) · `3d61000+800` (CX_DBGC) · `3d68000+37000` (GMU;
incluye gpucc 3d90000+0xa000 y GDSCs 0x3d99xxx) · `3d9e000+1000` (CX_MISC) · `3da0000+40000`
(SMMU base) · `3de6000+40` (TCU) · `3de8000/3dec000` (QTB) · `0b280000+10000` (PDC/GMU_PDC) ·
`03d40000+10000` (AO_BLK_DEC0) · QDSS 10048000/10900000/10b05000.

### 5.3 Tabla ACD del vendor (por pwrlevel; **NO habilitar en k61** — §7)

| lvl (CX) | freq | qcom,acd-level |
|---|---|---|
| 0x190 | 950 MHz | 0x5FFD28A8 |
| 0x180 | 900 MHz | 0x5FFD28A8 |
| 0x140 | 835 MHz | 0x5FFD28A8 |
| 0x100 | 736 MHz | 0x5FFD8829 |
| 0x0E0 | 684 MHz | 0x5FFD8829 |
| 0x0C0 | 633 MHz | 0x5FFD8829 |
| 0x080 | 500 MHz | 0x5FFD29A8 |
| 0x040 | 353 MHz | 0x5FFD2C88 |
| 0x038 | 255 MHz | 0x5FFD2F88 |

Formato mainline equiv.: `qcom,opp-acd-level` en cada OPP del nodo GPU (lo consume
`a6xx_gmu_acd_probe` → HFI ACD table + `qmp_send("{class: gpu, res: acd, val: 1}")`).

### 5.4 Estado de arranque del vendor (dmesg)
probe gmu+kgsl ~5,89 s (150 ms sin fw), sqe 5,89 → gmu.bin 5,91 (ueventd, `/vendor/firmware`) →
zap 6,03–6,05 (`/odm/firmware`) → service `gpu` 6,15. Fw: `gen71100_sqe.fw`, `gen71100_gmu.bin`,
`gen71100_zap.mbn` (md5 idénticos a los nuestros, #540).

---

## 6. PLAN k61 (réplica del estado del dominio + validación en un boot)

Base: **k60 + s272**. Restricciones respetadas: sin leer la ventana SMMU +0x20000 (dump=0), sin
rpmh/PDC (`a6xx_gmu_rpmh_init` neutralizado). Kernel-side de sondas/S3 escalonado = `docs/historia/revision/DISENO-K61-20261008.md`
(mismo commit); este plan añade el lado DT/estado y CORRIGE dos detalles de aquel (§6.4).

### 6.1 dtbo **s273** (fragmentos sobre s272)

| # | Fragmento | Diff textual | Riesgo |
|---|---|---|---|
| F1 | **PD CX en la kgsl-smmu** (réplica del `vdd-supply` vendor; tal cual mainline sm8650) | en `/soc/kgsl-smmu@3da0000`: `power-domains = <0x175 0x00>;` (0x175=gpucc, idx 0=CX_GDSC) + `power-domain-names = "cx";` | BAJO: posible -EPROBE_DEFER si gpucc aún no probeó (reorden benigno); el arm-smmu ya hace dev_pm_domain_attach genérico |
| F2 | **qcom,qmp al nodo GMU** | QUITAR `qcom,qmp = <0x23>;` de `/soc/qcom,kgsl-3d0@3d00000`; AÑADIR `qcom,qmp = <0x23>;` en `/soc/qcom,gmu@3d69000` | BAJO: sin `qcom,opp-acd-level` el acd_probe devuelve 0 ANTES de usar qmp (`enable_by_level==0 → return 0`); solo desbloquea el path y da log |
| F3 | (NO en s273) ICC del GPU | aplazado a s274 | — |

**No tocar**: ipc-core, demet, opp sin acd, compatibles del smmu, SID2 (post-CM3), opp del gmu.

### 6.2 kernel **k61** (sobre k60, solo `a6xx_gmu.c` + samplers)

- **P1 — samplers pre-S3** (solo registros conocidos-buenos: ventana GMU/RSCC/CX_MISC/GPUCC;
  CERO SMMU): los ENV del DISENO-K61 (§3.1) con las DIRECCIONES CORREGIDAS de §6.4, más:
  - `ENV-RSCC`: `GPU_RSCC_RSC_STATUS0_DRV0` (rscc+0x004), `RSCC_SEQ_BUSY_DRV0` (rscc+0x101),
    `RSCC_SEQ_MEM_0_DRV0[0..4]` (rscc+0x180..0x184) — el estado que **XBL/AOP dejó** (vendor:
    secuenciador de AOP, CPU no escribe; si leemos 0s, confirma que tampoco el vendor lo tiene
    pre-cargado por CPU).
  - `ENV-GMU-CFG`: `BOOT_CONFIG`(0x1f801), `CM3_CFG`(0x1f82d), `FENCE_RANGE_0`(0x23b11),
    `PWR_COL_INTER_FRAME_CTRL/HYST`(0x1f8c0/1), `SPTPRAC_PWR_CLK_STATUS`(0x1f8d0).
  - `ENV-CX_MISC`: `TCM_RET_CNTL` (0x3D9E0E4) antes/después del write de fw_start.
- **P2 — réplicas de estado** (las únicas variables físicas nuevas): CX votado desde el probe de
  la SMMU (F1) y qmp presente en el GMU (F2). **Cero escrituras MMIO nuevas** respecto a k60.
- **P3 — gates**: K44/K44' A-E, S0–S4 + pr_flush(120) como siempre; S3 escalonado del DISENO-K61.

### 6.3 Peldaño **s274** (solo si k61+s273 sigue en freeze seco con S3 ejecutado)

ICC real del GPU: (a) re-añadir `[17] = &qnm_gpu` a `cliffs_gem_noc_nodes` en
`drivers/interconnect/qcom/palawan.c`, (b) `interconnects = <&gem_noc 17 0 &mc_virt 512 0>` en el
nodo GPU (ids VENDOR: el driver cliffs indexa con ids del DTB stock), (c) opcionalmente bw por
`opp-avg-kBps/opp-peak-kBps` en la opp-table. **Advertencia**: hoy `cliffs_gem_noc`/`cliffs_mc_virt`
van **SIN `.bcms`** ⇒ un voto sería solo-contable (sin commit RPMh); el commit real es lo que
reabre el wedge #286. Secuencia recomendada: primero qnm_gpu sin bcms (no-op físico, valida el
camino de resolución), luego bcms. Cada peldaño = un boot.

### 6.4 CORRECCIONES a `docs/historia/revision/DISENO-K61-20261008.md` (bloqueantes para su ENV)

1. **ENV-GDSC**: el doc propone leer `REG_A6XX_GPU_CC_GX_GDSCR` en word **0x24403** (phys
   0x3D9100C). Ese offset del XML `a6xx_gmu.xml:237` **no es el GDSCR en palawan**: 0x3D9100C =
   **GFX3D_AON_BCR** (tabla de resets de `gpucc-palawan.c:573`). GDSCR reales (vendor DT +
   driver GDSC, doble fuente): **GX = 0x3D99034 = word GPU-relativa 0x240D**, **CX = 0x3D9908C =
   word 0x2423**. b31=ON, b11=CLD_KEEP (retention) se mantienen.
2. **ENV-PD**: el doc dice que el nodo GMU "no tiene xxx-supply" — el m272 SÍ lleva
   `vddcx-supply`/`vdd-supply` (heredadas, inertes). La técnica propuesta (genpd status de
   cxpd/gxpd) sigue siendo la correcta; solo corregir la descripción.
3. **ENV-GATE hlos1 (d2)**: correcto (0x3D97000 = gpucc+0x7000, word 0x25C00/byte 0x2F000 dentro
   de la ventana gmu) — mantener.

### 6.5 Matriz de decisión de un boot k61+s273

| Observación | Lectura |
|---|---|
| Freeze antes de S3 (sin S3-rst0) | F1 reordenó probes: revisar defer del smmu; separar F1/F2 |
| S3-rst0 y ahora S4-pollOK o fallo GRACIOSO | la réplica CX/TCU desbloqueó el muro → iterar HFI |
| Freeze seco en S3 como siempre | CX-PD+qmp no eran la pieza → peldaño s274 (ICC), y re-lectura de ENV-RSCC/ENV-GDSC vs §2.1/§2.2 |
| ENV-GDSC CX b31=0 pre-S3 | el genpd CX del gmu NO encendió → bug de attach (nuevo discriminador) |
| ENV-GATE hlos1 bit0=1 + freeze | la TCU tenía reloj y aun así muere ⇒ causa no-reloj (energía/interconexión) |

---

## 7. RIESGOS de replicar diferencias

| Diferencia | Riesgo | Veredicto |
|---|---|---|
| **ACD real** (`qcom,opp-acd-level` ×9 + `qmp_send acd:1`) | **CATASTRÓFICO-POSIBLE**: en el vendor ACD la aplica el AOP con su cadena de ferro/votos completa y con GX no gobernable; activarla desde nuestro kernel sin ACD_BCR/GX_ACD_IROOT controlados puede dejar el reloj GFX con adaptación activa que el CPU no puede ni ver ni parar (reset duro instantáneo, peor que el actual) | **PROHIBIDO en k61**. Tabla documentada (§5.3) para fase posterior CON AOP vivo |
| **ICC con `.bcms`** (commit RPMh temprano) | reabre el wedge #286 (consumidores vendor en defer al resolver icc en boot) | APLAZADO a s274, escalonado (sin bcms → con bcms) |
| PD CX en smmu | -EPROBE_DEFER del smmu en boot (reorden de probes; UART/UFS podrían deferir detrás) | BAJO — s273; reversible quitando el fragmento |
| qmp en GMU | sin acd-levels no envía NADA (`enable_by_level==0` sale antes) | MÍNIMO |
| Escribir IFPC/RPMH_CTRL a mano antes de S3 | el fw gen7 los gestiona post-boot vía HFI; pre-inyectarlos con el CM3 en reset = estado que el vendor NO deja el CPU (y `GMU_RPMH_CTRL` con votos activos sin RSC preparado = votes huérfanos) | **NO hacer** en k61 |
| SID2/secure CB | necesario para el zap/post-CM3, irrelevante para el freeze | Fase post-CM3 |

---

## 8. Conclusión

El vendor deja, antes de soltar S3-rst0: CX con **tres votantes** (gmu, kgsl-iommu, smmu — todos
regulador), GX al estado de XBL, hub 200 MHz con cx_int+aon ON, CX_GMU 220 MHz,
DDRSS_GPU_AXI ON, la TCU/SMMU con el voto CX puesto y SMR0/SMR1→CB0/CB1 con S2CR=0x1, sin uCode
RSC/PDC escrito por CPU, ACD activado por AOP, IFPC gestionado por el fw, y un voto ICC
MASTER_GFX3D→SLAVE_EBI1 del devfreq. Nuestro k60+s272 ya replica: clocks (ids curados), SMR/S2CR,
fw, secuencia CM3, neutralización RSC/PDC. **Faltan por replicar**: el voto CX de la SMMU (F1),
el qmp en su sitio (F2) y —escalonado— el voto ICC (s274); todo lo demás (ACD, IFPC, rails por
vdd-class) es fase posterior o gestionado por el fw/AOP una vez el CM3 viva.
