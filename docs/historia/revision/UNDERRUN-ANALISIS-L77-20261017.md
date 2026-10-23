# UNDERRUN-ANALISIS-L77 — underrun de INTF en cada frame con L76R (DPU 10.1 "palawan", DSC + widebus + split)

> 17-oct-2026. Solo lectura: sin adb, fastboot ni ssh, sin flash y sin commits. Este fichero es lo único escrito
> (más un DT fusionado temporal en el scratchpad).
> Fuentes: **D** = `l76r-dmesg-20261017.txt`; **RW** = `docs/historia/revision/l76r-dpu-regwrites-20261017.txt` (hw_log de 3 commits de plano
> a 1369 s); **ST** = `docs/historia/revision/l76r-drm-state-durante-modetest.txt`; **VE** = `vendor-harvest-20261017b/kprobe/sde-enable-writes.txt`;
> **VR** = `.../kprobe/sde-regwrites-decoded.txt`; **VD** = `.../dpu/sde-blocks-raw-awake.txt`; **K** = `build/kernel-pokes/k52-L16-tree`;
> **m288** = DT vivo (DT vendor + s288), fusionado con `fdtoverlay` igual que en PARIDAD-CLK-ICC; **LED** = FLASH-LEDGER #646-#654.
> Etiquetas: [MEDIDO] = dato de log o dump · [CÓDIGO] = leído en K · [INFERIDO] = deducción no medida.

## 0. Veredicto corto

1. **El underrun es real y se produce uno por frame**, pero el contador solo avanza en ventanas cortas. Con
   `has_idle_pc=true` (catálogo palawan), cada vez que el encoder pasa a IDLE, unos 58 ms después del último kickoff,
   se ejecuta `_dpu_encoder_irq_disable`, que da de baja **a la vez** la IRQ de vsync y la de underrun
   (K `dpu_encoder.c:1080`, `dpu_encoder_phys_vid.c:719-727`, `IDLE_TIMEOUT` en `dpu_encoder.h:20`). Por eso salen
   21/22: hay un underrun en cada frame observado, no 21 en total. [CÓDIGO + MEDIDO]
2. **Es un problema nuevo de L76.** L67 dio **0** underruns con el mismo plano, el mismo ICC y el mismo handoff
   (B3 §3). L71, L73 y L74 dieron "1/1", es decir, uno al arrancar en cada INTF. L76R da uno por frame. Los cambios
   que L76 mete en el lado DPU son solo tres:
   - **C4**: ENC_DF_CTRL con `initial_lines` 3 + BIT(12).
   - **C7**: TIMING_ENGINE solo en INTF1.
   - **C2**: periodo del INTF 571→572, que no altera nada.

   C4 y C7 son paridad vendor **parcial**. El vendor acompaña C4 de INTF_CONFIG **bit23 + prog-fetch**
   (`0x80800000`, `PROG_FETCH_START 0x0014272d`) y de **DSC_CLK_CTRL `0xc0000000`**. Acompaña C7 de
   SPLIT_DISPLAY_UPPER/LOWER = 0 y usa **dos SSPP** (DMA3/DMA4). Nosotros tenemos SW_TRG_MUX BIT(4)/BIT(8) y **un
   solo SSPP en multirect paralelo** (DMA0), que reparte su fetch entre LM0 y LM1. [MEDIDO + CÓDIGO]
3. **El fetch no da errores.** Cada commit escribe `VBIF_XIN_CLR_ERR <= 0x0`, y eso significa que
   `VBIF_XIN_PND_ERR | VBIF_XIN_SRC_ERR == 0` (K `dpu_hw_vbif.c:46-54`). Tampoco hay ni un fault del SMMU. El display
   queda en el CB 69 en modo TRANS (D:2833-2842). Si falla el fetch, falla por **ritmo** (ancho de banda, QoS o
   acoplamiento entre los dos LM), no por traducción. [MEDIDO + CÓDIGO]
4. **Hallazgo estructural: el voto ICC del display es un no-op.** `mdp0-mem` = `<0x188 3 0x188 0x200>` y el phandle
   0x188 es `qcom,cliffs-mc_virt` (m288:15711-15716). Ese provider se registra **sin `.bcms`**
   (K `drivers/interconnect/qcom/palawan.c:1855-1860`, "SIN bcms: cero commits RPMh"). Los 4,26 GB/s que se ven en
   `interconnect_summary` nunca llegan a RPMh, y la ruta mmss_noc (`qnm_mdp`) ni existe. El vendor vota
   qnm_mdp→llcc a 2,5 GB/s de pico, más ebi, más rscc. Nuestro plano XR24 lineal pide unos 3,3-3,9 GB/s; la capa
   UBWC del vendor, alrededor de la mitad. Encaja con la conclusión de #654 ("fetch"), **pero no explica por sí solo
   que L67 diera 0**. [CÓDIGO + DT]
5. **El "estado atómico durante modetest" NO se capturó con el plano activo.** ST muestra `plane-0 crtc=(null) fb=0`,
   `crtc-0 plane_mask=0` y `resource mapping sspp` sin dueño. Los campos `sspp[0..1]` que salen son restos. Además
   `sspp[1] multirect_index=solo` contradice RW (rect1 con `MULTIRECT_OPMODE 0x3`). Hay que repetir la captura con
   modetest parado en el `getchar()`. Lo bueno es que ST prueba un estado útil: **el CRTC sigue activo sin planos**
   cuando se retira el fb (§5, Z3).

**Orden para L77**:
1. Antes de flashear, las pruebas zero-flash Z1-Z5 (§5), que separan "aguas abajo" (C4/C7/DSC/INTF) de "fetch"
   (BW/QoS/multirect).
2. Si no se pueden hacer: **L77a = solo cmdline** (`msm.uke_l76_dsc_df=0 msm.uke_l76_te_master_only=0`, repack sin
   build). Vuelve a la semántica DPU de L67 y deja las mejoras DSI de L76. Es lo que más probabilidad tiene de quitar
   el underrun.
3. **L77b**: paridad vendor **completa** del trío DSC/INTF y del split.
4. **L77c**: ICC real.

---

## 1. Qué significa un underrun de INTF en DPU 10 con DSC + widebus + split

### 1.1 El camino de datos de cada mitad (vertical, 1600 px por LM)

```
DDR/LLCC ─(SMMU CB69)─ NoC mmss (qnm_mdp, 2 canales) ─ VBIF (xin 1 = DMA0) ─┐
                                                                          SSPP DMA0  rect0 → LM0 ─ PP0 ─ DSC0 (DCE0 enc0) ─ INTF1 ─ DSI0
                                                                          (multirect rect1 → LM1 ─ PP1 ─ DSC1 (DCE0 enc1) ─ INTF2 ─ DSI1
                                                                           paralelo)   source split: ambos rects van a ambos LM, cada LM recorta por x
```
- El INTF es el **sumidero de ritmo fijo**: pclk 158,56 MHz, línea de 572 ticks, ventana de datos
  `DISPLAY_DATA_HCTL 0x012a0020`, es decir 267 ticks por línea activa. En cada tick pide una palabra de **48 bits**
  (widebus, `INTF_CONFIG2 0x1011` = WIDEN | DATA_HCTL_EN | DCE_DATA_COMPRESS). Eso son 1600 B comprimidos por
  línea (2 slices × chunk 800).
- El DSC no saca nada hasta tener `initial_lines` líneas de entrada (ENC_DF_CTRL[7:0]). Luego empuja chunks al
  búfer de salida (`ob_max_addr` 599).
- **Underrun de INTF** = dentro de la ventana de datos el INTF pidió una palabra y la FIFO de salida del DSC
  (antes, la de PP/LM) estaba vacía. Manda el color de underflow (`INTF_UNDERFLOW_COLOR` = 0, negro) y deja la IRQ
  enclavada. La IRQ salta **una vez por frame**, al primer hueco; no cuenta palabras.
- Que ocurra **en cada frame** apunta a algo sistemático. Hay cuatro mecanismos posibles:
  - (a) **arranque de frame mal alineado**: el DSC espera más líneas de las que le llegan antes de que se abra la
    ventana de datos del INTF. Entonces la primera línea activa falla siempre, con fase fija respecto al vsync.
  - (b) **ritmo medio insuficiente** en algún punto del fetch (BW, QoS, reloj). Falla a mitad de frame, con fase
    variable.
  - (c) **acoplamiento entre mitades**: un recurso compartido (el SSPP en multirect) se para porque una de las dos
    ramas no drena al mismo ritmo, por ejemplo si INTF2 no sigue bien al maestro. Se paran **las dos**.
  - (d) un bloque que **no produce nada** (DSC sin reloj, fetch nunca arrancado). Fallaría todo el frame y en ambos
    INTF.
- Nosotros vemos underrun en **ambos** INTF ([0,26] y [0,28]), negro con luz y `frame_done` 0. En vídeo,
  frame_done no discrimina.

### 1.2 Por qué 21/22 son "uno por frame"
`dpu_encoder_phys_vid_irq_enable` registra vsync y underrun. `ENTER_IDLE` con `is_vid_mode` llama a
`_dpu_encoder_irq_disable`, que los da de baja a los dos (K `dpu_encoder.c:1059-1085`, `dpu_encoder_off_work`
`:1615-1624`, `idle_pc_supported = caps->has_idle_pc` `:2656`, palawan `.has_idle_pc = true`). Así que solo se
cuentan los frames de la ventana de unos 58 ms tras cada kickoff. Los commits de modetest son pocos (D:7279-7300,
3 a 182,4 s y 4 a 201,7 s). Que vsync dé 22 y underrun 21 = **fallan prácticamente todos los frames observados**.
El primer underrun de cada enable además dispara `msm_disp_snapshot_state` (K `dpu_encoder.c:1506-1507`):
deja un **devcoredump** con todos los registros DPU, que caduca a los 5 min (Z5).

---

## 2. Hechos nuevos de esta revisión

| # | Hecho | Fuente | Tipo |
|---|---|---|---|
| H1 | `mdp0-mem` va a `qcom,cliffs-mc_virt`, que se registra **sin BCM**. `icc_set_bw` del DPU y `MIN_IB_BW` del mdss no generan ningún comando RPMh. Tampoco hay ruta mmss_noc (`qcom,cliffs-mmss_noc` no tiene driver en el árbol). Tampoco se programa la QoS NoC del puerto MDP (qosbox `0xad000/0xae000` de `palawan_mmss_noc`, que no se instancia). | m288:15711-15716; K palawan.c:1846-1860, 1885-1903 | DT + CÓDIGO |
| H2 | Sin errores VBIF en los commits (`VBIF_XIN_CLR_ERR <= 0x0` ×3, RW:202,384,...) y sin fault SMMU en todo D. El display queda en CB 69 TRANS, S2CR idx 2 = SID 0x1c00/0x2. | RW; D:2833-2842; K dpu_hw_vbif.c:46-54 | MEDIDO |
| H3 | Contador de underrun = ventanas de idle_pc (§1.2) → 1:1 con vsync | K | CÓDIGO |
| H4 | La matriz L67=0, L71/L73/L74 = 1/1 y L76R ≈ 1/frame aísla los deltas DPU de L76: **C4** (initial_lines 3 + bit12) y **C7** (TE solo maestro) | LED #646-#654; PLAN-KERNEL:81-85; L76-PREP §1 | MEDIDO |
| H5 | Trío vendor "DSI + compresión": ENC_DF_CTRL bit12 + **INTF_CONFIG bit23 + prog-fetch** (`0x60800000`→`0x80800000`, `PROG_FETCH_START 0x14272d` = (vtotal−1)·htotal+1 = 1 línea antes del fin de frame) + **DSC_CLK_CTRL `0xc0000000`** (solo en DSC0/1; en DSC2 vale 0). Nosotros solo tenemos bit12. | VE INTF_CONFIG/PROG_FETCH; VD 0x81f0c/0x81f8c; K dpu_hw_intf.c:123,258, encoder_phys_vid.c:184-262 | MEDIDO + CÓDIGO |
| H6 | Topología SSPP: el vendor usa **DMA3 + DMA4** (MDP 0x2a000/0x2c000, xin 13/14), cada uno de 1600×2136, `MULTIRECT_OPMODE 0`, UBWC (`format 0x800237ff`, `ubwc_ctrl 0x40000000`, `FETCH_CONFIG 0xc0087`, IOVA 0xf8022000…). Nosotros, con `dpu_use_virtual_planes=true` (K dpu_kms.c:56), usamos **DMA0 en multirect paralelo** (rect0 + rect1 = 3200 px por un único SSPP y un único xin): XR24 lineal (`format 0x236FF`), IOVA 0x3000. | VR; RW | MEDIDO |
| H7 | Split en TOP: vendor `SPLIT_DISPLAY_EN=1`, `UPPER=0`, `LOWER=0`, `SSPP_SPARE=1`. Mainline en vídeo con maestro INTF_1 escribe `LOWER=BIT(8)` (INTF_2_SW_TRG_MUX), `UPPER=BIT(4)`, `SPARE=1`. Con C7, el INTF2 vive como esclavo **con un split que no es el del vendor**. | VR:210-213; K dpu_hw_top.c:25-61 | MEDIDO + CÓDIGO |
| H8 | El reloj MDP calculado por mainline es `vtotal·hdisplay·fps·1,05` = 931 MHz, sin dividir por los 2 LM. Se recorta a `max_core_clk_rate` = 514 MHz, igual que el vendor. | K dpu_core_perf.c:92-113; D "K48-opp-rate 514000000" | CÓDIGO (sin medir en vivo tras el commit) |
| H9 | MMCX: el DT vendor fija `pm_v8_s6_level qcom,init-voltage-level = 0x180` (TURBO) con proxy-consumer (m288:~7436-7449). No consta que el driver del port lo honre. El DPU no tiene `mmcx-supply`, `power-domains` ni `required-opps`. | m288; PARIDAD-CLK-ICC D-04 | DT |

---

## 3. Causas posibles, ordenadas por probabilidad para *este* síntoma

Leyenda de probabilidad: **A** alta · **M** media · **B** baja · **X** descartada con datos.

| # | Causa | P | A favor (nuestros datos) | En contra | Vendor (registro = valor) |
|---|---|---|---|---|---|
| 1 | **C4 incoherente**: `initial_lines=3` + bit12 sin INTF bit23 ni prog-fetch. El DSC espera 3 líneas y el INTF abre su ventana de datos sin el arranque anticipado que el vendor programa. La primera línea activa falla en cada frame (mecanismo a). | **A** | Aparece justo con L76; L67 (initial_lines 2, sin bit12) = 0. Falla en ambos INTF, en cada frame. bit12 no tiene nombre en mainline y el vendor nunca lo usa sin bit23/prog-fetch. | El resto del DSC y del INTF es vendor bit a bit. Con prog-fetch off, el fetch arranca en el vsync, 148 líneas antes; si el pipeline no fuera "pull", 3 líneas sobrarían [INFERIDO]. | `ENC_DF_CTRL 0x095c1203` + `INTF_CONFIG 0x80800000` + `PROG_FETCH_START 0x0014272d` + `DSC_CLK_CTRL 0xc0000000` |
| 2 | **C7 + split mainline + multirect compartido**: INTF2 con TE=0 sigue al maestro a través de un `SPLIT_DISPLAY_*` que no es el del vendor (SW_TRG_MUX). Si INTF2/LM1 drena con otra fase, el único SSPP que alimenta los dos LM se para y caen las dos ramas (mecanismo c). | **A** | También aparece con L76. Underrun en INTF1 **e** INTF2. El vendor solo funciona con TE-maestro si tiene UPPER/LOWER=0 y dos SSPP. L67-L74 (TE en ambos) no tuvieron underrun por frame. | INTF2 corre: su IRQ de underrun salta, así que el esclavo arranca. El vendor tiene SPARE=1 igual que nosotros. | `INTF_2 TIMING_ENGINE_EN=0`, `SPLIT_DISPLAY_EN=1`, `UPPER/LOWER=0`; SSPP DMA3/DMA4 sin multirect |
| 3 | **Ancho de banda sin votar**: ICC no-op (H1), sin mmss_noc ni QoS NoC del MDP, y XR24 lineal (unas 2 veces lo que mueve el vendor con UBWC). Mecanismo b. | **M-A** | Probado en código y DT que no hay voto. Sin errores VBIF (la inanición no deja errores). La conclusión de #654 apunta al fetch. | L67 dio 0 underruns con el mismo no-op. Salvo que el nivel DDR que dejan BL/AOP varíe entre arranques, que no está medido, el ICC no es lo que cambió. | `qnm_mdp-qns_llcc` peak 2 500 000; `llcc_mc-ebi` peak 800 000; `qnm_mdp_disp-ebi_disp` (rscc) hasta 26,5 GB/s avg; reg-bus 14→310 MB/s (kB/s) |
| 4 | **QoS del SSPP distinto del vendor** (danger/safe/creq) | B-M | LUTs con "FIXME" en el catálogo palawan. El vendor usa otras. | Solo muerde con contención, no en cada frame si el ritmo sobra. Danger/safe están activos (`QOS_CTRL=1`). | DMA: `DANGER 0xffff`, `SAFE 0xfff0` (UBWC) / DT lineal `0xff00`, `CREQ 0x0011223344556666`, `CDP 0xf`. Nuestro: `0x3FFFF` / `0xFE00` / `0x0011222222335777` / `0x9` |
| 5 | **DSC sin reloj** (`DSC_CLK_CTRL`) | B | El vendor lo escribe en los DSC activos y mainline nunca. | Si fuera un enable de reloj imprescindible, L67-L74 tampoco habrían tenido salida y sin embargo no dieron underrun por frame. Más bien parece un "force-on" de gating. | `DSC_CLK_CTRL 0xc0000000` en DSC0 y DSC1 (VD 0x81f0c/0x81f8c) |
| 6 | **MMCX sin voto** (DPU a 514 MHz con tensión desconocida) | B-M | Ni el DPU ni el dispcc votan MMCX. El vendor sube 56→384 antes de los relojes. | Una subtensión suele dar corrupción o cuelgue, no un underrun limpio 1:1. El DT pide init-level 384 (H9). | `pm_v8_s6_level` 384 y `pm_v6c_s1_mmcx_sup_level` ON en cada wake |
| 7 | **CTL/flush**: el DSC se reprograma y se hace flush (`CTL_DSC_FLUSH 0x3`, bit22) en **cada** kickoff; el vendor solo lo hace en el enable | B | RW: cada commit de plano reescribe los 40 registros del DSC + DSC_CTL/CFG + flush. Escribir ENC_DF_CTRL/DSC_CFG a mitad de frame podría reiniciar el encoder [INFERIDO]. | Solo hay unos pocos commits y aun así falla en cada frame de la ventana. Upstream lo hace igual en otras plataformas DSC. | flush por frame `0x220220c0` (sin bit22); DSC solo en el enable (`0xa0c200c0`, `0x104=3`, `0x110=6`, `0x100=1`) |
| 8 | INTF_CONFIG bit23 / prog-fetch **por sí solos** (sin C4) | B | Mismo trío que en #1 | L67-L74 sin bit23 ni prog-fetch y sin underrun por frame | véase #1 |
| 9 | SMMU/IOVA 0x3000 / VBIF halt | **X-B** | IOVA muy baja (el vendor usa 0xf8…), CB nuevo sin TLBI global (F4 silenciada). | Sin errores VBIF (H2), sin faults, `CTL_FETCH_PIPE_ACTIVE=0x1` = DMA0 correcto (K fetch_tbl), memtypes programados (`K48-res-vbif-ok`). Un fallo de traducción daría basura o errores, no un underrun limpio. | IOVA 0xf8022000 / 0xfc022000 / 0xfe022000 |
| 10 | MDP clk | X | — | 514 MHz igual que el vendor (H8; falta confirmar en vivo con `core_clk_rate`) | 514 MHz (600 transitorio) |
| 11 | CTL actives / PP-DSC mux / LM fuera de rango | X | — | Iguales: `CTL_TOP 0xf0000000`, `INTF_ACTIVE 6`, `INTF_MASTER 2`, `DSC_ACTIVE 3`, `MERGE_3D 0`, `DSC_CTL 0/1`, `INTF_MUX 0xf0000/0xf0001`, `LM_OUT_SIZE 0x08580640` ×2, `LM_OP_MODE 0x2 / 0x80000002`, `BLEND0_OP 0x100` | mismos valores (VE) |
| 12 | VBIF OT limit / QoS remap | X | — | El vendor tampoco escribe OT (0 escrituras `LIM_CONF` en VR). El remap RT del xin 1 es `{4,4,5,5,5,5,5,6}` en ambos. | `VBIF_XINL_QOS_*_REMAP`: xin 1/4/5/9/13/14 = 4,4,5,5,5,5,5,6 |

---

## 4. Escrituras SDE del vendor en el encendido frente a lo que programa mainline

VE = 819 escrituras de la ventana de enable; los SSPP se toman de VR, que cubre frames con capas. Los bloques
vendor son relativos a MDSS (offset MDP + 0x1000). Mucho de lo que el vendor programa va por REG_DMA y no aparece
aquí (README del harvest).

| Bloque | Registro (vendor) | Vendor | Mainline (K / RW) | ¿Lo escribimos? |
|---|---|---|---|---|
| VBIF | AMEMTYPE_CONF0/1 (0x160/0x164) | `0x33333333` | `dpu_vbif_init_memtypes` memtype 3 ×16 | **sí** (igual) |
| VBIF | OUT_AXI_ASHARED/AINNERSHARED (0x170/0x174) | 0 | no se escriben (reset 0 presumible) | no (inocuo) |
| VBIF | XINL_QOS_RP/LVL_REMAP | rt {4,4,5,5,5,5,5,6} por xin activo | igual para el xin 1 cuando hay modeset | sí |
| VBIF | OUT_RD/WR_LIM | **no se escribe** | no (sm8650_vbif sin OTLIM) | igual |
| MDSS | UBWC_STATIC/CTRL_2/PREDICTION (0x144/0x150/0x154) | `0x103e/0x3/0x1` | msm_mdss ubwc (irrelevante en lineal) | — |
| TOP | UIDLE_CTL / FAL10_VETO / WD | `0x80800046` / `0x80000001` / … | no (uidle off) | no (más seguro así) |
| TOP | PPB0/1_CONFIG/CNTL | 0 | no | no (reset) |
| TOP | **SPLIT_DISPLAY_UPPER/LOWER** | **0 / 0** | **BIT(4) / BIT(8)** en vídeo (K dpu_hw_top.c:46-53) | **DISTINTO** |
| TOP | SPLIT_DISPLAY_EN / SSPP_SPARE | 1 / 1 | 1 / 1 | igual |
| CTL | TOP / INTF_ACTIVE / INTF_MASTER / DSC_ACTIVE / MERGE_3D / WB / CWB / CDM | `0xf0000000` / 6 / 2 / 3 / 0 / 0 / 0 / 0 | idem (K dpu_hw_ctl.c:570-624) | igual |
| CTL | FETCH_PIPE_ACTIVE | `0x18` (DMA3 \| DMA4) | `0x1` (DMA0) | estructura igual |
| CTL | flush del enable | `0x18=0xa0c200c0`, `0x104=3`, `0x110=6`, **`0x100(MERGE_3D_FLUSH)=1`** | INTF/DSC flush; sin MERGE_3D_FLUSH (merge 3D no usado) | casi igual (MERGE_3D_FLUSH: inocuo) |
| CTL | flush por frame | `0x220220c0` **sin DSC** | `0x4208C0` **con DSC (bit22) + `CTL_DSC_FLUSH 0x3`** en cada commit | **DISTINTO** |
| CTL | DSPP_n_FLUSH | `0x800000bd/0x8000003d/0x1` | no (sin DSPP) | no (irrelevante) |
| LM | OUT_SIZE, OP_MODE, BLEND0_OP, NOISE_LAYER | `0x08580640`, 2 / `0x80000002`, `0x100`, **0** | igual; **NOISE_LAYER no se escribe** | NOISE: no (reset 0 presumible) |
| DSPP | hsic/ltm/igc | usados | no | no (irrelevante) |
| PP | `+0xe0` (dither) | 0 | no se escribe (sin dither a 8 bpc) | igual en la práctica |
| DSC | CMN_MAIN_CNF, ENC (28 regs), DSC_CTL, DSC_CFG | `0x101`, vendor, 0/1, `0x1001` | iguales (RW) | igual |
| DSC | DSC_4HS_MERGE_EN/CFG (+0x10/+0x14) | 0 | no se escriben | no (reset 0 presumible) |
| DSC | **DSC_CLK_CTRL (+0xc)** | **`0xc0000000`** (dump, vía REG_DMA) | nunca | **NO** |
| DSC | DSC_DATA_IN_SWAP (+0x8) | `0x2c688` (= reset) | no | igual (reset) |
| INTF | HSYNC, VPER, VPULSE, DHCTL, V_START/END, CONFIG2, DATA_HCTL, MUX, PANEL_FORMAT, FLC_EN | vendor | iguales (marcadores UKE-L76-INTF) | igual |
| INTF | ACTIVE_HCTL/ACTIVE_V_* | escritos, pero sin EN, así que sin efecto | 0 | inocuo |
| INTF | **INTF_CONFIG** | **`0x60800000` → `0x80800000`** (bit23 + bit31) | RMW con el valor heredado; solo toca 29/30/31; prog-fetch OFF (vbp+vsw 148 > 24) | **NO** (bit23 y bit31) |
| INTF | **PROG_FETCH_START** | **`0x0014272d`** | no (fetch desactivado) | **NO** |
| INTF | TIMING_ENGINE_EN | INTF1 = 1, INTF2 = 0 | igual desde C7 | igual |
| INTF | VSYNC_TIMESTAMP_CTRL (0x210) | `0x11` | no | no (irrelevante para underrun) |
| SSPP | topología | DMA3 + DMA4, 1600 px cada uno, `MULTIRECT_OPMODE 0` | DMA0 multirect paralelo (`0x170 <= 1/3`) | **DISTINTO** |
| SSPP | DANGER/SAFE/CREQ_0/CREQ_1 | `0xffff/0xfff0/0x44556666/0x112233` | `0x3FFFF/0xFE00/0x22335777/0x112222` | **DISTINTO** (valor) |
| SSPP | QOS_CTRL | 0→1 en cada actualización | 1 | equivalente |
| SSPP | CDP / FETCH_CONFIG / EXCL_REC / DECIMATION / FILL_LEVEL_SCALE | `0xf` / `0xc0087` / 0 / 0 / 0 | `0x9` / — (lineal) / — / — / — | lineal: inocuo |
| SSPP | SSPP_CLK_CTRL (0x330) | 5→4 | 5→4 | igual |

Lo que el vendor escribe y nosotros **no**, por relevancia para el underrun: **INTF_CONFIG bit23 + bit31 con
PROG_FETCH_START**, **DSC_CLK_CTRL `0xc0000000`**, **SPLIT_DISPLAY_UPPER/LOWER = 0** (nosotros escribimos otro
valor), QoS LUT vendor, y "DSC solo en el enable" (nosotros lo hacemos en cada kickoff). Fuera del MMIO del DPU
faltan también los **votos ICC** (H1) y **MMCX** (H9).

---

## 5. Pruebas zero-flash por SSH: sin escribir MMIO, sin flash y sin tocar boot

En todas: `D=/sys/kernel/debug/dri/1` (msm-kms, "minor 1" en D:2904). Solo hay lecturas de debugfs (`readl`) y
commits DRM normales. modetest queda parado en su `getchar()`, así que la captura se hace desde otra shell.

| Id | Prueba (comando) | Qué discrimina |
|---|---|---|
| **Z0** | Mientras modetest tiene el plano: `cat $D/state`. Comprobar `plane-0 crtc=crtc-0` y `sspp=` con dueño. | Sustituye a ST, que no es válido |
| **Z1** | `modetest -M msm -s 36@85:#0 -v` (page-flip continuo, plano XR24 completo: las IRQ quedan vivas sin idle). Leer `status` del encoder dos veces con 2 s de separación. | Tasa real: Δunderrun ≈ Δvsync ≈ 240/2 s = **por frame** confirmado |
| **Z2** | Durante Z1: `cat $D/debug/danger/danger_status` y `safe_status` varias veces | **SSPP DMA0 en danger alto y sostenido → fetch hambriento** (causas 3-4). Danger 0 con underrun → **aguas abajo** (1, 2, 5, 7) |
| **Z3** | **Sin plano**: salir de modetest. `atomic_remove_fb` deja el CRTC activo sin planos, como prueba ST. Lanzar commits sin plano (p.ej. `modetest -M msm -P 43@85:64x64` y salir, varias veces) y medir Δunderrun en la ventana posterior a cada retirada. Alternativa: el helper atómico de Z4 en modo "none". | **Pieza clave.** Si sigue habiendo underrun **sin fetch** → C4/C7/DSC/INTF (L77a/L77b). Si desaparece → fetch (BW/QoS/multirect: L77c o L77-SSPP) |
| **Z4** | Helper atómico mínimo (compilado en el PC con libdrm, que ya está instalada; 600 commits a 120 Hz). Modos: (a) ningún plano; (b) plano 1600×2136 en x=0 (solo LM0, rect solo); (c) en x=1600 (solo LM1/INTF2); (d) 64×64; (e) dos planos, izquierda y derecha. Mirar en `state` que son **dos SSPP** y no multirect. Con modetest puro: `modetest -M msm -P 43@85:1600x2136+0+0`, `…+1600+0`, `…64x64`. | (b) limpio y (c) sucio → **INTF2 esclavo (C7)**. (b) y (c) limpios pero el completo sucio → **multirect compartido** (causa 2 / L77-SSPP). (d) sucio → aguas abajo. (e) limpio → topología SSPP |
| **Z5** | `cat $D/kms > kms.txt` (snapshot síncrono de **todos** los bloques: CTL, INTF, PP, SSPP, LM, TOP, DSC enc+ctl de 0x10, VBIF 0x1074) dos veces, con 1 s de separación, durante Z1. Además `ls /sys/class/devcoredump/` y `cat …/data` en los 5 min siguientes al primer underrun de un enable nuevo. | Mide de golpe: INTF_CONFIG real (bit23 y bit31), `DSC_CLK_CTRL`, TOP 0x2f4/0x2f8/0x3f0/0x28, **INTF1 vs INTF2 `FRAME_COUNT` (0xac) y `LINE_COUNT` (0xb0)**: si avanzan en lockstep, el esclavo C7 está bien; si derivan o se paran, C7 roto. También `VBIF_XIN_PND/SRC_ERR`, el estado de halt y la QoS SSPP en vivo. Se compara con VD línea a línea |
| **Z6** | `echo 1 > /sys/kernel/tracing/events/dpu/dpu_enc_underrun_cb/enable` y lo mismo con `dpu_enc_vblank_cb` (tracefs, no es MMIO). Medir Δt vsync→underrun en Z1. | **Fase fija ≈ 0,53 ms** (= 148 líneas × 3,607 µs, primera línea activa) → arranque de frame: **C4** o prefetch. **Fase variable** a mitad de frame → **ancho de banda** |
| **Z7** | `modetest -M msm -s 36@85:#0@RG16 -v` (RGB565, la mitad de BW). Si el driver del panel expone otros modos, también un modo de menor refresco. | El underrun baja o desaparece al reducir BW → causa 3. No cambia nada → 1/2/5 |
| **Z8** | `cat $D/debug/core_perf/core_clk_rate`; `grep -iE "mdp\|hf_axi\|mdss" /sys/kernel/debug/clk/clk_summary`; `grep -iE "mmcx\|s6_level\|mxc" /sys/kernel/debug/regulator/regulator_summary`; `cat /sys/kernel/debug/interconnect/interconnect_summary` | Confirma H8 (514 MHz), `gcc_disp_hf_axi` ON, el nivel MMCX real (causa 6) y que el "voto" ICC solo existe en software (H1) |
| Z9 | No usar `perf_mode` ni `fix_core_*_vote` para "subir el ICC": los votos son no-op (H1), así que no discriminan nada. `disable_danger` **escribe registros**, así que tampoco. | — |

**Árbol de decisión**:
- Z3 o Z4(a/d) **con underrun** → aguas abajo:
  - Z6 en fase fija → **L77a** (o L77b).
  - Z5 muestra INTF2 desfasado → C7 → `te_master_only=0`.
- Z3/Z4 **sin underrun** y el plano completo con underrun → fetch:
  - Z4(b, c) limpios → multirect: L77-SSPP.
  - Z2 danger alto o Z7 mejora → BW: L77c.

---

## 6. L77 concreto (orden = probabilidad de quitar el underrun)

**Criterio común de PASA**:
- Con el plano 3200×2136 mantenido (Z1, page-flip 10 s), `underrun` del encoder-0 en ambos phys = 0. Como mucho
  1 al arrancar, como en L71-L74.
- `vsync` avanza unas 120/s.
- `danger_status` de DMA0 ≤ 1.
- **Imagen** = patrón de modetest en el panel. Ojo: underrun 0 es **necesario pero no suficiente** (L67 dio 0 y
  siguió en negro).

### L77a — bisección por cmdline (sin build, solo repack con `--cmdline-append`)
- **Cambio**: `msm.uke_l76_dsc_df=0 msm.uke_l76_te_master_only=0`. Los dos parámetros existen como `0444`
  (K `dpu_hw_dsc_1_2.c:89-92`, `dpu_encoder_phys_vid.c:670-672`) y msm es built-in.
- Quedan intactos L73-L75 y los C1/C2/C5 DSI de L76 (widebus, RGB101010, defer VID, PPS w=3200).
- **Marcadores**:
  - `UKE-L76-DSC: DSC0 ENC_DF_CTRL=0x095c0202 … quirk=0` (×2).
  - `UKE-L76: INTF1 TE ON role=1` **y** `UKE-L76: INTF2 TE ON role=2` (el formato del pr_info con te_on=1 ya
    existe).
- **Por qué primero**: devuelve el DPU a la semántica de L67 (0 underruns), sin código nuevo.
- **Bisección si PASA**: L77a1 con solo `te_master_only=0` y L77a2 con solo `dsc_df=0`. Si se quiere gastar un único
  flash, se hace primero L77a1 (C7), porque Z4(c) y Z5 pueden haberlo señalado ya.

### L77b — paridad vendor COMPLETA del trío y del split (si L77a quita el underrun pero no da imagen, o si Z6 da fase fija)
Por orden de probabilidad, todo detrás de params `uke_l77_*` (por defecto 1) con readback en un marcador:
1. **INTF_CONFIG bit23 + prog-fetch vendor**.
   - `dpu_hw_intf.c`, `dpu_hw_intf_setup_timing_engine` (antes de `DPU_REG_WRITE(c, INTF_CONFIG, intf_cfg)`):
     `if (p->compression_en && !dp_intf && intf->mdss_ver->core_major_ver >= 10) intf_cfg |= BIT(23);`
   - `dpu_encoder_phys_vid.c`, `programmable_fetch_config`: con DSC en DSI, forzar `vfp_fetch_lines = 1`. Da
     `fetch_start = (vtotal-1)*htotal+1 = 0x0014272d` y `INTF_CONFIG |= BIT(31)`.
   - Marcador: `UKE-L77-INTF: INTF%d CONFIG=0x%08x (v 0x80800000) PFS=0x%08x (v 0x0014272d)`.
2. **DSC_CLK_CTRL**: `dpu_hw_dsc_1_2.c`, en `dpu_hw_dsc_config_1_2` tras escribir `DSC_CFG`:
   `DPU_REG_WRITE(hw, sblk->ctl.base + DSC_CLK_CTRL, 0xc0000000)`. Escribir 0 en `dpu_hw_dsc_disable_1_2`.
   Marcador: `UKE-L77-DSC: DSC%d CLK_CTRL=0x%08x (v 0xc0000000)`.
3. **Split vendor en vídeo**: `dpu_hw_top.c`, `dpu_hw_setup_split_pipe`: con `cfg->mode == INTF_MODE_VIDEO`,
   `lower_pipe = upper_pipe = 0`. `SSPP_SPARE` sigue en 1, igual que el vendor. Imprescindible si se mantiene C7.
   Marcador: `UKE-L77-SPLIT: EN=1 UP=0x0 LOW=0x0 SPARE=1`.
4. **DSC solo en el enable**: `dpu_encoder.c`, en `dpu_encoder_prepare_for_kickoff`, llamar a
   `dpu_encoder_prep_dsc()` solo si `drm_atomic_crtc_needs_modeset` o en el primer kickoff tras enable (flag en
   `dpu_enc`). Marcador: con hw_log, los commits de plano **sin** `CTL_DSC_FLUSH` ni bit22.

Con 1-4, C4 (`dsc_df=1`) y C7 (`te_master_only=1`) quedan como en el vendor. Es la combinación **coherente**; L76R
era una mezcla.

### L77c — ancho de banda real (si Z2/Z7 señalan fetch, o si L77a/b no lo quitan)
1. **BCM en `cliffs_mc_virt`**: `drivers/interconnect/qcom/palawan.c:1855`, añadir
   `.bcms = cliffs_mc_virt_bcms` con `&bcm_mc0, &bcm_acv` y `.num_bcms`. Riesgo histórico: el pánico de #156 por
   commit temprano bajo Gunyah (comentario :1858-1859). Mitigación: votar el init a 0 (`get_bw` → 0) y dejar que el
   primer voto real lo haga `msm_mdss_enable`.
   Marcadores:
   - `UKE-L77-ICC: cliffs_mc_virt bcms=2`.
   - En `trace rpmh:rpmh_send_msg`, comandos a las direcciones BCM MC0/ACV en el enable del display.
2. **Ruta mmss_noc**:
   - Añadir `qcom,cliffs-mmss_noc` (nodo vendor `qnm_mdp` id 21 → `qns_mem_noc_hf`, BCM MM0) y la parte gem_noc
     `qnm_mnoc_hf` → `qns_llcc` (BCM SH0) a la tabla cliffs.
   - Overlay s289: `interconnects = <&mmss_noc 21 &mc_virt 512>` (como `qcom,sde-data-bus0` vendor
     `<0x1bf 0x15 0x1a2 0x22b>`).
   - Con eso también se programa la QoS NoC (qosbox `0xad000/0xae000`).
   - Marcador: `interconnect_summary` con `qnm_mdp` avg/peak distintos de 0 y trace rpmh MM0/SH0.
3. **QoS LUT vendor** (`catalog/dpu_10_1_palawan.h`, `palawan_perf_data`):
   - `danger_lut_tbl = {0xffff, 0xffff, 0x0}`, `safe_lut_tbl = {0xff00, 0xfff0, 0xffff}`.
   - `qos_lut_tbl[LINEAR] = kaanapali_qos_linear` (`0x0011223344556666`, igual al CREQ vendor).
   - `cdp`: sin cambios.
   - Marcador: hw_log `QOS_DANGER_LUT <= 0xFFFF`, `QOS_CREQ_LUT_0 <= 0x44556666`.

### L77-SSPP — topología vendor (solo si Z4(b, c, e) acusan el multirect)
- `dpu_plane.c`: en la asignación virtual, no usar `dpu_plane_try_multirect_parallel` cuando los dos pipes van a
  LM distintos (param `uke_l77_no_mr_split=1`). Así el RM coge otro SSPP para la mitad derecha, como el vendor con
  DMA3/DMA4.
- Marcador: `state` con `sspp[0]=sspp_8 solo`, `sspp[1]=sspp_9 solo` (u otro DMA) y `CTL_FETCH_PIPE_ACTIVE` con
  dos bits.

### L77-MMCX (solo si Z8 muestra MMCX < 384 o sin consumidor)
- Overlay: `mmcx-supply = <&pm_v8_s6_level>` en `mdss_mdp_ml`.
- `dpu_kms_init`: `regulator_get(dev, "mmcx")` + `regulator_set_voltage(r, 384, INT_MAX)` + `enable`, antes de
  `dev_pm_opp_set_rate`.
- Marcador: `UKE-L77-MMCX: level=384` y la línea correspondiente en `regulator_summary`.

**Recomendación de secuencia**:
1. Z0-Z8, en una sola sesión SSH de unos 20 min.
2. El flash que indique el árbol del §5. Si no hay sesión previa: L77a con los dos knobs.
3. Si L77a da 0 underruns y sigue negro, L77b (paridad coherente).
4. L77c en paralelo, como el riesgo estructural que es: los votos ICC no llegan a RPMh.

---

## 7. Resumen (≤350 palabras)

Un underrun de INTF quiere decir que, dentro de la ventana de datos (267 palabras de 48 bits por línea), el INTF no
encontró dato a la salida del DSC. El hueco puede venir del DSC, del PP/LM o del fetch del SSPP. El 21/22 es uno por frame: con `has_idle_pc` las IRQ de vsync y underrun se dan de baja unos 58 ms
después de cada commit, así que solo cuentan esas ventanas.

Hechos nuevos:
- (1) El voto ICC del display es un **no-op**: `mdp0-mem` va a `qcom,cliffs-mc_virt`, que se registra sin BCM, y
  no hay ruta mmss_noc.
- (2) No hay errores VBIF (`XIN_CLR_ERR <= 0`) ni faults SMMU.
- (3) El estado atómico capturado **no** tenía el plano activo.
- (4) El underrun por frame nace en L76: L67 daba 0 y L73/L74 1/1. Los deltas DPU de L76 son **C4**
  (initial_lines 3 + bit12) y **C7** (TE solo maestro), los dos de paridad vendor **parcial**. El vendor acompaña
  C4 de INTF_CONFIG bit23 + prog-fetch (`0x80800000`, `0x14272d`) y de DSC_CLK_CTRL `0xc0000000`. Acompaña C7 de
  split UPPER/LOWER=0 y usa dos SSPP. Nosotros usamos un solo DMA0 en multirect, con XR24 lineal (unas 2 veces el BW
  del UBWC del vendor).

Causas por orden:
1. C4 incoherente: falla el arranque de frame.
2. C7 con split mainline y multirect compartido.
3. Ancho de banda sin votar.
4. QoS LUT.
5. DSC_CLK_CTRL.
6. MMCX.
7. Reflush del DSC en cada commit.

Descartados: SMMU, reloj MDP, CTL/mux/LM, OT.

Pruebas zero-flash, sin MMIO:
- Sin plano, media pantalla, plano diminuto y dos planos: separan aguas abajo de fetch.
- `danger_status`.
- `cat dri/1/kms` y devcoredump (INTF_CONFIG, DSC_CLK_CTRL, split y contadores INTF1/INTF2).
- tracefs para la fase vsync→underrun.
- RGB565.
- Relojes, MMCX e ICC.

L77:
- **a)** solo cmdline, `msm.uke_l76_dsc_df=0 msm.uke_l76_te_master_only=0`.
- **b)** paridad coherente: bit23 + prog-fetch, DSC_CLK_CTRL, split 0/0, DSC solo en el enable.
- **c)** BCM en cliffs_mc_virt, ruta mmss_noc y QoS vendor.
- Después, según las pruebas: dos SSPP y MMCX.

Criterio: underrun 0 con page-flip continuo y patrón visible. Underrun 0 no garantiza imagen (L67).
