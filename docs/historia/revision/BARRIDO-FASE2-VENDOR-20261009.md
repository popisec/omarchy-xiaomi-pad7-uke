# BARRIDO FASE 2 — vendor cliffs vs k64/mainline (2026-10-09)

> Clones en `~/.hermes/profiles/coder/cache/scratch/vendor/` (fuera del repo).
> Rutas abajo como `OP:` (OnePlus) y `MI:` (Xiaomi). Tablet no tocada.
> k64 = `build/bootimg/boot-uke-k64-vendorcfg.img` (#550, congela igual #550b).

## 0. Fuentes y estado de clones

| Repo | Rama / commit | Estado |
|---|---|---|
| `OnePlusOSS/android_kernel_modules_and_devicetree_oneplus_sm7675` | `oneplus/sm7675_u_14.0.1_oneplus_ace3v` | OK, sparse (graphics-kernel + graphics-devicetree/gpu) |
| `MiCode/Xiaomi_Kernel_OpenSource` | `uke-v-oss`, commit `5712080a4` | OK, full depth-1 (76.239 ficheros) |

El SoC es cliffs: `qcom,chipid = <0x43030b00>` idéntico en vendor y stock
(`OP:…/gpu/cliffs-gpu.dtsi:28`, `build/evidencia/stock-dt/stock2-Cliffs7P-uke.dts:11707`).
GPU = Adreno 735 / gen7_11_0 (`OP:…/gpu/cliffs-gpu.dtsi:4,26`,
`OP:…/graphics-kernel/adreno-gpulist.h:2417-2438` con `gmufw_name = "gen71100_gmu.bin"` —
el mismo binario que el nuestro, md5 ya verificado en INV-GMU-BIN).

Qué replicó k64 (verificado en el binario, no de memoria):
`strings /var/tmp/k64-Image` (extraído del bootimg, gzip-member @4096) contiene
`UKE-K64: register_config COMPLETADO`,
`UKE-K64: register_config vendor (0x1f8f0=1 0x1f8f1=1 0x1f984=1 base=0x3c45)` y
`UKE-K64: RSC wake rc=%d status=%#x`, sobre base k61-staged + breadcrumb k63
(marcadores `UKE-K61:…`, `UKE-K63: BREADCRUMB=…` presentes).
O sea: k64 replicó las **constantes** vendor-only + wake RSC, pero NO los registros
runtime (0x1f985, 0x1f9cd–d0, 0x1f9ce/cf de INV-KGSL-RE §4 filas 5,10–13).

## 1. Tabla de pwrlevels vendor (GPU) — coincide con la nuestra

`OP:…/gpu/cliffs7-gpu-pwrlevels.dtsi` (9 niveles, `initial-pwrlevel = <8>`, l.2):
950/Turbo_L0, 900, 835, 736, 684, 633, 500/SVS, 353/Low_SVS, **255/Low_SVS_D1** (ll.12–125).
El stock del uke es idéntico: `initial-pwrlevel = <0x08>` (stock2:11698),
mismas 9 freqs en hex (950M=0x389fd980 … 255M=0x0f32fdc0, stock2:11771–11857).
Nuestro DT fusionado también: `gpu_opp_uke` con las mismas 9 freqs
255…950 MHz (`/var/tmp/uke-s272/s272.dts`, fragment@1450, ll.~15150–15200).
La variante `cliffs-` (no-7) añade Turbo_L2 1100M + Turbo_L1 1000M
(`OP:…/gpu/cliffs-gpu-pwrlevels.dtsi:2-47`); el uke usa la variante `-7`. Sin ACD:
ningún `qcom,opp-acd-level` en nuestro DT y el core gen7_11_0 no lista
ADRENO_ACD en features (`adreno-gpulist.h:2420-2427`).
**Conclusión: pwrlevels GPU no es delta.** El "LOW_SVS 220 MHz" del aviso #552 no es
un pwrlevel de GPU: es la **freq-table del GMU** (§2).

## 2. GMU freq-table vendor: 220 MHz / 550 MHz — DELTA REAL

- DT vendor: `qcom,gmu-freq-table = <220000000 LOW_SVS>, <550000000 SVS>`
  (`OP:…/gpu/cliffs-gpu.dtsi:153-154`); stock uke igual en crudo
  `<0xd1cef00 0x40 0x20c85580 0x80>` = <220M, 550M> (stock2:15388).
- Consumo en driver: `gen7_gmu_clk_probe` lee la tabla a `gmu->freqs/vlvls[2]`
  (`OP:…/graphics-kernel/adreno_gen7_gmu.c:2378-2398`); sin tabla, default
  `GMU_FREQ_MIN=200M / MAX=500M` (`kgsl_gmu_core.h:102-103`).
- Arranque vendor: `gen7_gmu_enable_clks(dev, 0)` → RDPM `freqs[0]/1000` +
  `clk_set_rate(gmu_clk, freqs[0]=220M)` + `clk_set_rate(hub, hub_freq)`
  (ll.1862–1894).
- Nuestro DT fusionado SÍ lleva la tabla en formato OPP:
  `gmu_opp_table { opp-220000000 lvl 0x40; opp-550000000 lvl 0x80; }`
  (s272.dts fragment@907, ll.14702–14718), y mainline construye sus freqs de ahí
  (`k52-tree/drivers/gpu/drm/msm/adreno/a6xx_gmu.c:3012-3013`).
- **Pero mainline ignora la tabla al arrancar**: `a6xx_gmu_resume` fuerza
  `clk_set_rate(core_clk, 200000000)` y hub 200M/150M (k52 `a6xx_gmu.c:2308-2311`).
- La tabla del RCG no tiene 200M en ningún mundo:
  `ftbl_gpu_cc_gmu_clk_src = {19.2M, 220M, 550M}` idéntica en
  `MI:drivers/clk/qcom/gpucc-cliffs.c:215-220` y `k52:gpucc-palawan.c:175-180`.
  `clk_set_rate(200M)` → `qcom_find_freq_floor` = **19.2 MHz (XO)**
  (semántica floor verificada en `k52:drivers/clk/qcom/common.c:67-79`).
  Hub 150M sobre tabla `{200M}` (`k52:gpucc-palawan.c:198-211`) → floor NULL →
  **-EINVAL, el hub se queda al rate heredado de XBL/AOP (desconocido)**.
- Hub vendor A735 = **200 MHz** (`adreno-gpulist.h:2448`, core gen7_11_0).
- **Delta neto**: vendor arranca GMU a gmu 220M + hub 200M;
  mainline/k64 arranca a gmu **19.2M efectivos** + hub **heredado incierto**.

## 3. Secuencia init CM3 vendor (opensource = .ko en el path boot)

`gen7_gmu_boot` (`adreno_gen7_gmu.c:1997-2060`) es paso a paso la cadena del .ko
(INV-KGSL-RE §1): request_state → CX GDSC → `enable_clks(0)` → rscc_wake →
load_fw → register_config → irq_enable → device_start → hfi_start.
- `device_start` (ll.347–370): SYSRESET=0 (l.357) + wmb + poll
  `FW_INIT_RESULT BIT(8) mask GENMASK(8,0)` (ll.362–363). Sin SYSRESET=1 previo.
- `rscc_wakeup` (ll.393–426): REQ←BIT(1), poll ACK, +poll SEQ_BUSY (ll.415–419),
  REQ←0; skip si nunca durmió (ll.399–401).
- `register_config` opensource (ll.937–1009): FAL veto (947–948), INIT_RESULT=0,
  BOOT_CONFIG=2, HFI_QTBL_ADDR/INFO pre-reset (954–956), FENCE 0x32/0x8a0 (958–960),
  CM3_CFG=0x4052, GBIF_HALT=0, vrb/log/chipid (GENERAL_11/9/10/8), power_config,
  BCL condicional. **grep de `0x1f8f0/0x1f984/0x1f9cd/base+0` en todo el árbol
  opensource: sin resultados** — los extras del .ko (filas 1,2,5,6,9–13 de
  INV-KGSL-RE §4) son de una revisión cerrada/nueva, no están en este snapshot.
- Solo `first_boot` (NO el path boot) añade, y por ese orden:
  ACD por mbox ANTES de la GDSC (l.1905), `scm_gpu_init_cx_regs` (1930),
  voto DDR mínimo pre-start (1938–1940) y PDC/RSC ucode POST-start (1946–1953).
- ACD en A735: no-op real — el core no tiene el feature (no hay `mbox_request`
  sin `acd_probe`, ll.2287–2328) y el mensaje sería `{class: gpu, res: acd…}`
  (ll.1838–1860).

## 4. Mapa GDSC/clocks + votos qmp_aop

- Vendor DT GMU (`cliffs-gpu.dtsi:125-163` = stock2 GMU): `vddcx=gpu_cc_cx_gdsc`,
  `vdd=gpu_cc_gx_gdsc`; 6 clocks gmu/cxo/axi/memnóc/ahb/hub; `iommus` **SID5**;
  `mboxes=<qmp_aop>`; `ipc-core 0x400000/0x140000`. kgsl-smmu con
  `vddcx-supply` (CX GDSC, l.110) — el F1 que cubre s273.
- `MI:gpucc-cliffs.c`: PLL1 440M alimenta gmu_src (div /2 → 220M);
  `cx_gmu_clk` es rama AON con SET_RATE_PARENT (ll.392–408);
  `hlos1_vote_gpu_smmu` en gpucc+0x7000 BIT(0) (ll.446–457);
  always-on 0x9004/0x900c en probe (ll.627–628); GDSCs no definidos aquí
  (vienen de nodos DT/regulator). Sin `vdd_data` en el palawan nuestro
  (grep vacío en `k52:gpucc-palawan.c`) → **mainline no vota corners desde
  relojes**; el voto CX vendor es arco RPMH explícito LOW_SVS construido de la
  freq-table (`adreno_gen7_rpmh.c:272-292`: `cx_votes = freqs/1000`).
- `MI:gcc-cliffs.c`: ddrss_gpu_axi (1564–1577), memnoc (1697–1711),
  snoc_dvm (1713–1725): ramas votadas, sin tabla de rates.
- qmp_aop: en A735 no hay tráfico AOP del driver (sin feature ACD);
  nuestro `qcom,qmp` en GMU (s273 @1715) solo serviría a un ACD que está
  desactivado. No es delta útil.

## 5. Deltas exactos vendor → k64/mainline

| # | Vendor hace | k64/mainline | Estado |
|---|---|---|---|
| D1 | gmu_clk = 220M (tabla) | floor a **19.2M XO** | VIVO, §2 |
| D2 | hub_clk = 200M (gpulist A735) | set 150M → **-EINVAL, heredado XBL** | VIVO, §2 |
| D3 | voto CX **LOW_SVS** explícito (arco RPMH + RDPM 220000) | genpd on sin nivel; palawan sin vdd_data | VIVO, §4 |
| D4 | reg_config runtime 0x1f985/0x1f9cd-d0/0x1f9ce-cf | no replicados (k64 solo constantes) | ABIERTO pero no-S3 (P3) |
| D5 | `cx_timer_init` + `ahb_timeout_detect` en boot (.ko §1 pasos 4-5) | ausentes en mainline/k64 | Menor, sin mecanismo de freeze |
| D6 | FAL veto, GBIF_HALT=0, vrb/log/chipid, BCL (opensource) | mainline parcial (chipid/GBIF difieren) | Cubierto por k64-congela |
| — | 8 constantes vendor-only + RSC wake | **k64 las replicó y congeló igual** | REFUTADO #550b |
| — | HFI QTBL pre-reset, FENCE_R0 0x80c808a0, BOOT_CONFIG=2, CM3_CFG, caches=1 | común ambos mundos | No deltas (INV-KGSL-RE §8) |
| — | pwrlevels GPU, OPP, freqs 255…950, initial 255M | idénticos | No delta (§1) |
| — | ACD/AOP, DDR pre-vote, PDC/RSC ucode | no-op o post-S3 en ambos | No explican S3 |

## 6. Veredicto

- **Qué NO explica S3-rst0**: todo lo que solo afecta al CM3 *después* de soltar
  el reset (body, polls, scatter, HFI, mapeo SMMU, runtime regs D4) — excluido por
  P1/P2/P3 (con el CM3 en WFI sin tocar bus, el SoC muere igual) — más las
  constantes register_config (refutado directo por k64, #550b), ACD/AOP (el vendor
  A735 tampoco lo usa), GDSC on/off y SMMU (H1–H3 + K63 demuestran isla viva y
  fw ejecutando).
- **Qué SÍ puede explicar S3-rst0 (un solo bucket físico, 3 caras)**:
  el estado energía+reloj de la isla CX en el instante del release —
  **D1 (gmu a 19.2M en vez de 220M) + D2 (hub heredado incierto en vez de 200M) +
  D3 (esquina CX sin voto explícito en vez de LOW_SVS)**. Los tres son
  compatibles con toda la evidencia (K63: el CM3 llega a ejecutar; P3: el release
  mata aunque el CM3 no haga nada; k64: el register_config no era la pieza) y
  ninguno está refutado. No se puede discriminar entre ellos solo desde el host.
- **Siguiente experimento discriminante (todo host-side, 0 AOP)**:
  fijar `gmu_clk=220M + hub_clk=200M` (tasas de la tabla real) + voto de esquina
  CX explícito a LOW_SVS antes del release, con el stub P3 como testigo:
  si deja de congelar, era D1/D2/D3; si congela igual, el estado viable lo pone
  XBL/AOP fuera del alcance del driver (conclusión #550b en pie).
  El golden-state Android (rates+corners reales en vivo) diría cuál de las tres
  caras pesa más, sin flashear.
