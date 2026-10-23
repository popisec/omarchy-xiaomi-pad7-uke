# BARRIDO FASE 3 — RE estática con material en disco (2026-10-09)

Objetivo: exprimir lo que hay en disco HOY sin tocar la tablet (consola y flash las tiene FASE 1).
Caso: S3-rst0 (soltar reset del CM3 congela el SoC). Ref: #550b.
Material: `build/pkg/uke-gpu-firmware/gen71100_gmu.bin` (80680 B),
`build/evidencia/gmu-P1.bin`, `gmu-P2.bin`, `gen71100_sqe.fw`, `gen71100_zap.mbn` (12088 B),
DT stock `build/evidencia/stock-dt/stock2-Cliffs7P-uke.dts` (21323 L),
dtbo s269 vigente (`/var/tmp/uke-s269/s269.dts` = payload de `s269-boot-dtbo-touch.img`,
`m9.dts` = merged base+s269), KGSL-RE (`docs/historia/revision/INV-KGSL-RE-20261008.md`), GMU-BIN (`docs/historia/revision/INV-GMU-BIN-20261008.md`).

## 1. Diff binario gen71100_gmu.bin (G) vs gmu-P1 vs gmu-P2

| fichero | bytes | sha256 (12) |
|---|---|---|
| G `gen71100_gmu.bin` | 80680 | `435c7bac9a32` |
| P1 `gmu-P1.bin` | 80680 | `a1e7b254a512` |
| P2 `gmu-P2.bin` | 80680 | `cefe886563c1` |

Estructura contenedor IDÉNTICA en los tres (15 bloques: 11 TOC size=0 + 4 payloads
`type=0xefbeadde`; bloques 11/12/13/14 = ITCM stub 476 B / icache-BO 79900 B / DTCM 40 B / DTCM params 24 B).
`cmp -l` (nº byte decimal 1-based, valores octal):

- G vs P1 — 4 bytes: `213 3 376 / 214 360 347 / 215 370 376 / 216 377 347`
  = fileoff `0xd4..0xd7` = **ITCM+0x14** (CM3 `0x14`).
- G vs P2 — 4 bytes en 2 grupos: `373 373 0 / 374 321 277` y `407 373 0 / 408 321 277`
  = fileoff `0x174..0x175` (**ITCM+0xb4**) y `0x196..0x197` (**ITCM+0xd6**).
- P1 vs P2 — 8 bytes (suma de ambos).

### Qué son esos bytes (anclas de INV-GMU-BIN §2)

- **ITCM+0x14**: G = `f0 03 f8 ff` = `bl 0x4008` (tras el scatter-loader, **llamada al body
  del icache**). P1 = `e7 fe e7 fe` = dos `b .` (spin infinito).
  → **P1 = "el stub jamás salta al body"**: copia/scatter + polls de cache se ejecutan,
  el fetch SMMU de `0x4000` nunca ocurre. Breadcrumb esperado si llega: `0x01141516`
  con CM3 vivo girando en ITCM.
- **ITCM+0xb4 (POLL-1, `0x1f40a`)**: G = `fb d1` = `bne` (repite `while((*0x1807d028&1)!=1)`).
  P2 = `00 bf` = `nop` → **una sola lectura, sigue aunque done=0**.
- **ITCM+0xd6 (POLL-2, `0x1f409`)**: idéntico parche `d1fb`→`bf00`.

### Secciones HFI / power / votos GX / RSCC que difieren: NINGUNA

- Body icache (bloque 12, 79900 B, con `HandleHfiCommand`, `beginVoteGxOn`,
  `GmuPwrGxBwVote`, `GmuPwrRequestPowerOn`, `GmuPwrQueryGxPowerState`,
  `beginHmPwrCollapse/On`, `abortPwrCollapse`): **bit a bit idéntico** en G/P1/P2.
- Bloques DTCM 13 (40 B ceros) y 14 (params: breadcrumb `0xffffffff`, magic `0x40050001`,
  `0x40000024`, `0x20060001`): idénticos.
- `strings -n 6`: 305 líneas en cada uno, `diff` vacío → **cero strings exclusivos**.

### Veredicto (1): ¿qué cambió entre parches y toca power/votos GX/RSCC?

No. Los tres firmwares son el mismo fw con **microparches de control de flujo en el stub**,
no de power: P1 discrimina *fetch-SMMU vs hang-AHB* (si P1 ya no mata el SoC, la muerte
estaba en el fetch del body `0x4000`/SID5→CB1; si mata igual, el hang es anterior:
polls `0x1f409/0a` o el primer MMIO del bloque cache). P2 discrimina *polls* (si P2
sobrevive, el bloque cache-ops/GDSCR llega sin reloj y el `done` nunca se pone).
Correlato boot: `boot-uke-k62b-p1.img` / `k62c-p1` (P1), `k62d-p2` (P2), `k62e-p3`
(**P3 no está en disco: laguna, pedir a FASE 1 o al dueño del k62e qué bin llevó**).

## 2. Diff DT stock vs s269 acotado al dominio GMU/GPU

Base: `stock2-Cliffs7P-uke.dts`. s269 = `s269.dts` (nº fragmento + línea) y merged `m9.dts`.
s269 NO toca qmp_aop, gfxlvl, GDSCs ni cmd-db: deltas solo en gmu / kgsl-3d0 / kgsl-smmu / gpucc.

### 2a. Nodo GMU `qcom,gmu@3d69000`

Stock L15381-15399 (`compatible = "qcom,gen7-gmu"`, phandle `0x482`):

| prop | stock | s269 |
|---|---|---|
| reg / reg-names (L15396-15397) | 3 regiones: `gmu 3d68000`, `gmu_pdc b280000`, `gmu_ao_blk_dec0 3d40000` (SIN rscc) | frag@906 (L14684-14697): 4 regiones + `rscc 3d50000 10000`, `reg-names + rscc` |
| clocks (L15389-15390) | 6: gmu/cxo/axi/memnoc/ahb/hub `<175 09, 175 0b, 16e 12, 16e 20, 175 02, 175 14>` | frag@906: 7 renombrados ahb/gmu/cxo/axi/memnoc/hub/**demet** `<175 00, 07, 09, 16e 12, 16e 20, 175 12, 175 0a>` |
| power-domains | AUSENTE | frag@906: `cx + gx` = `<0x175 0x00 0x175 0x01>` |
| operating-points | AUSENTE (`qcom,gmu-freq-table = 220MHz/0x40 550MHz/0x80` L15388) | frag@907 (L14698+): `gmu_opp_table` opp-220MHz/0x40 + opp-550MHz/0x80 (mismos niveles) |
| mbox / smmu | `mboxes = <0x3b3 0>` aop (L15384), `iommus = <0x1c1 0x05>` SID5 (L15387) | sin cambio |
| vdd / vddcx (L15391) | `vdd=<0x401>` (=`gpu_cc_gx_gdsc`), `vddcx=<0x1bd>` (=`gpu_cc_cx_gdsc`) | sin cambio |
| frag@905 (L14677) | — | vacío (placeholder, no-op) |

### 2b. Nodo GPU `qcom,kgsl-3d0@3d00000`

Stock L11697+ (`status = "ok"`, `compatible = "qcom,adreno-gpu-gen7-11-0"`,
`qcom,initial-pwrlevel = 8` L11698, pwrlevels stock 9 niveles con `acd-level`):

| prop | stock | s269 |
|---|---|---|
| reg-names (L11713) | `... "cx_dbgc", "cx_misc", ...` (reg[3] `3d9e000/1000`) | frag@903 (L14660-14666): `cx_misc`→**`cx_mem`**; frag@1450 (L15142-15144): reg[3] `3d9e000/**2000**` |
| compatible | gen7-11-0 (L11716) | frag@1450: **`qcom,adreno-43030b00`, `qcom,adreno`** (compat uke) |
| clocks/interconnects (L11702-11709) | 4 clocks gcc/gpucc, `interconnects gpu_icc_path` | frag@1450: **clocks BORRADOS**, `interconnects` borrado → `gfx-mem`, +`iommus = <0x1c1 0 0>` SID0, +`qcom,gmu = <0x482>`, +`gpu_opp_uke` 9 niveles (255→950 MHz, levels 0x38→0x190) |
| status | `ok` (L11714) | frag@1420 (L15099-15105) `disabled` → frag@1450 `okay` → **frag@1711 (L15376-15382) `disabled` (ÚLTIMO: gana; merged m9 GPU disabled ✓ G2 mkdtbo)** |

### 2c. kgsl-smmu / gpucc / GDSC / qmp_aop / gfxlvl

- `kgsl-smmu@3da0000`: stock L13128 (`qcom,qsmmu-v500`, clocks con `gpu_cc_hlos1_vote_gpu_smmu`,
  `vdd=<0x1bd>`=cx_gdsc, `qcom,actlr`, qtb `gpu_qtb@3de8000` stream-id 0..0x400).
  s269 frag@902 (L14652-14659): solo relabel `compatible = "qcom,palawan-smmu-500", ...`.
- `gpucc@3d90000`: stock L11440 (`qcom,cliffs-gpucc`, vdd_cx/mx/mxc = 0x147/0x14c/0x148).
  s269 frag@904 (L14668-14676): `qcom,palawan-gpucc` + `#power-domain-cells = 1`.
- GDSC (stock L13709-13780): `gpu_cc_cx_gdsc@3d99108` ok (parent 0x147),
  `gpu_cc_gx_gdsc@3d9905c` ok (parent **0x1d0 = gfx voter**), **`gx_clkctl_gx_gdsc@3d68024`
  status = "disabled"** (L13769-13780, GDSC del clock-ctl del GMU apagado de stock).
  s269: **no toca ningún GDSC** (hereda stock tal cual).
- `qmp_aop` stock L11617-11624 (`qcom,qmp-mbox`, `qcom,qmp = <0x23>`, label aop);
  `rpmh-regulator-gfxlvl` stock L6534-6548 (`gfx.lvl` → `pmxr2230_s4_level`, phandle 0x14a);
  `aop_cmd_db_region@81c60000` stock L168-169 (`qcom,cmd-db`): **los tres sin delta en s269**
  (s269 solo toca `ldob8` de display en frag@1410, irrelevante para GPU).

### Implicación para S3-rst0

El s269 deja la GPU **disabled**: el crash S3-rst0 solo aparece con los overlays k5x/k6x
que la re-habilitan. Al re-habilitar hay que heredar sí o sí frag@906 (power-domains
cx/gx + región rscc + clock demet) y frag@907; los puntos de riesgo que el DT revela:
(i) `gx_clkctl_gx_gdsc` viene **disabled de stock** y nada lo enciende;
(ii) `cx_misc→cx_mem` + tamaño ×2 cambia la ventana que el driver usa para TCM/retención;
(iii) el voto GX cuelga de `gfx.lvl` (pmxr2230_s4) vía el voter `0x1d0`, intacto en s269.

## 3. Plan de triaje del dump AOP (cuando FASE 1 lo entregue)

Volcado esperado FASE 1: `aop_a` (512 KiB) + `aop_config_a` (512 KiB) leídos por fastboot.
Referencias ya en disco: `uke_eea_global_images_OS3.0.303.0.WOZEUXM_16.0/images/aop.mbn`
(319272 B, ELF32 `e_machine = 0xf3` = QDSP6/Hexagon, entry `0x13200000`, 11 phdrs) y
`aop_devcfg.mbn` (21636 B, también ELF32). Alcance conocido por strings (VIAS-GPU V2):
`aop_apps/mpss/adsp/cdsp/wpss`, `mmcx.lvl`, `vrm.mmcx`, `cx_ret_fsm`, `CX_GT_MOL`, `AOPABT`.

1. **Magic**: `xxd -l 64` — ¿ELF (`7f 45 4c 46`) con `e_machine` QDSP6 (0xf3) como el
   `aop.mbn` de la ROM, o MBN puro Qualcomm, o solo tabla de certs? `readelf -h -l`.
   Si el dump trae cabecera abl/fastboot distinta, recortar al ELF interior por `e_phoff`.
2. **Parse cabecera en python** (struct `<IIII...`): recorrer phdrs, listar segmentos
   LOAD (vaddr/filesz), volcar cada uno a fichero separado; desensamblar el segmento de
   código como Hexagon (capstone `CS_ARCH_HEXAGON` si disponible; si no, solo análisis
   de literales/strings por segmento).
3. **grep dirigido** por segmento: `gfx|gx|cx_|mmcx|pdc|rsc|qmp|rpmh|cmd-db|aop|vote|arc|
   lvl|collapse|retention|buses|clk` (case-insens) + `strings -n 5` completo del segmento
   de datos; anotar fileoff+vaddr de cada hit.
4. **Correlación con cmd-db del DT**: `aop_cmd_db_region@81c60000` (stock L168) y
   resource-names del DT (`gfx.lvl` L6536, `cx.lvl` L6324, `mmcx.lvl` L6433, `mx.lvl`,
   `ebi.lvl`): cada `*.lvl` que aparezca en el dump es un rail que AOP arbitra; marcar
   cuáles toca el path GPU (gfx/cx/mmcx) y con qué niveles (comparar con `opp-level`
   del DT: GMU 0x40/0x80, GPU 0x38..0x190).
5. **Correlación con KGSL-RE**: si el dump muestra secuencia AOP para GX/CX en cold boot,
   contrastar con `gen7_rscc_wakeup_sequence` y el unlock `RSCC 0x3b11←0x80c808a0`
   (INV-KGSL-RE §3-4): ¿el vendor hereda de AOP un estado que nuestro port no pide?

- **Criterio de éxito**: secuencia votable GX/CX atribuida a AOP (o prueba documentada de
  que AOP no toca GX y el rail lo lleva solo el driver/APSS) → cierra o refuta VIAS V2.
- **Criterio de parada**: si el dump es **solo certs/headers sin código ni tablas**
  (precedente `gen71100_zap.mbn`: 12088 B, `readelf` 1 LOAD de 0x3f4 + resto certs
  Xiaomi/SecTools, `strings` solo CAs) → parar, refutar V2-por-RE-directa y pasar a
  réplica de efectos por DT/driver.

## 4. Blanco de RE nº1 para la oleada 2

**`beginVoteGxOn` + `GmuPwrGxBwVote` + `HandleHfiCommand` en el body icache del
`gen71100_gmu.bin` (bloque 12, fileoff `0x2ac`, CM3 `0x4000`, 79900 B).**

Justificación: P1/P2 (stub, §1) ya discriminan el hang *temprano* (polls cache vs fetch
SMMU); lo que sigue sin saberse es lo que el fw exige al host **una vez vivo**: qué voto
GX/BW emite primero, por qué vía (HFI QTBL vs RSCC directo `0x1808c1a8`/`0x1809481e`,
literales ya avistados en el body — INV-GMU-BIN §3b) y en qué orden respecto al primer
comando HFI. Eso decide si S3-rst0 es "falta de voto GX previo del host" o "hang del
bloque cache", y fija los valores a replicar en `fw_start`. Descartados: vendor-only
`0x1f8f0/f1` (ya identificados en KGSL-RE §8: son experimento de 2 líneas, no RE);
AOP (bloqueado hasta el dump de FASE 1, §3); QTBL/HFI del DT (ya conocido, §2).
Criterio de éxito: localizar la **primera escritura del body a RSCC/GX y su orden
respecto a `GmuSetupIpcCore/Mem` + primer HFI**, con fileoff+dirección CM3 citados.
