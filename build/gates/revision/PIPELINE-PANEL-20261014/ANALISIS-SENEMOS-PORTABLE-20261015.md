# ANÁLISIS SENEMOS/uke-fedora/palawan → qué portar (15-oct-2026)

Fuentes: `github.com/MCC45TR/senemos-uke-kernel-mainline` (commit `c79cb7f0c3bc`, 14-oct-2026),
`github.com/linuxgamer/uke-fedora` (commit `5e7514166f44`, 11-oct-2026), palawan commit
`0d9f7fdf720ae9f4ecfbee4fadaf1e3b5c442e95`. **Nadie tiene display nativo funcionando**:
senemos 7.2.9 llega a KDE por simpledrm/framebuffer del firmware ("native display has not been
enabled or tested", `src/display/README.md`); sus objetos 7.2.10 son "Hardware unvalidated";
uke-fedora marca cada patch display "not hardware validated on Uke". Todo lo de abajo es
candidato sin validación HW — portar con ese rótulo (GPL: citar autor/repo/commit, §origen).

| # | Artefacto | Veredicto | Pri / Riesgo | Diff contra nosotros |
|---|---|---|---|---|
| 1 | Hunk byte-clock DSC (`dsi_host.c`, senemos `patches/display/7.2.10/0001-…patch:658`; origen linuxgamer `0011-dsi-dsc-input-depth-byte-clock.patch`): `if (msm_host->dsc) bpp = msm_host->dsc->bits_per_component * 3;` | **[PORTAR YA]** | P1 / bajo (4 líneas, solo rama DSC) | No lo tenemos (`dsi_host.c:644` usa siempre `format`=24). **Verificado aritméticamente**: pclk/host 158.5584 MHz → stock 118.9188 MHz vs parche 148.6485 MHz ≈ vendor 148.645. **SÍ es la explicación del 118,9 vs 148,6.** Matiz: el mensaje del donante dice "1 189 188 000 vs 1 189 190 000" porque en su 7.2.10 el pclk ya redondea distinto; en NUESTRO 7.2-rc2 el salto es 118,92→148,65 (cálculo propio arriba, no su mensaje). Su `tests/dsi-clock-contract.sh` fija lane=1189188000 = byte×8 parcheado: reutilizar como test. |
| 2 | `panel-xiaomi-o82.c` (senemos, 349 lín; base linuxgamer `cf4f9317` + patrón nt35950) | **[PORTAR SI]** por piezas | P2 / medio | (a) `mode_flags = VIDEO\|LPM` **sin NON_CONTINUOUS** (línea 295) — coincide con nuestro K48-A (lp11-init vendor) pero nuestro `panel-xiaomi-o82-dualdsi.c:835` **aún lleva el flag**: quitarlo es 1 línea. (b) Reset: `gpiod_direction_output(reset,0)` en probe + secuencia 0→1→0→1 en prepare (lín 164-173); nosotros 1→0→1→0 con release2 15 ms (L39d/S3). (c) Supplies `vddio/vsp/vsn` con `set_voltage` explícito (1.9/5.8/5.8 V, linuxgamer lín 217-234); nosotros igual + `vci` L19 opcional (S1) — compatible. (d) DCS por `host->ops->transfer` directo a AMBOS hosts en prepare (lín 60-80), **bypass del manager sync**; nosotros `dual_dcs_write_buffer_multi`. Su comentario: en modo sync DSI0 se hace ACK sin transmitir y DSI1 dispara ambos links — si nuestro DDIC está mudo a BTA, esta es una variable a probar. (e) Sin backlight propio: reutiliza KTZ pareado por DT — igual que nosotros. (f) Todo DCS en prepare + `off` en unprepare; sin `enable/` interno 0x51. |
| 3 | `o82-data.h` (53 KB): 2 variantes × (on/switch/off) + `o82_modes[7]` | **[REFERENCIA]** (+test ya) | P2 / bajo | 42_02_0b_120_on = **108 cmds** vs nuestros 104+cola: misma familia, comparar byte a byte pendiente (herramienta: su `o82-data.cpp` + `tests/o82-data-contract.sh`). `switch_commands` (4 cmds: ff/10,fb/01,b2/91,b3/40) = cambio de grupo de timing en runtime — nosotros no lo tenemos (solo exponemos 120 Hz; TODO 144/90). Modos: clocks **804988/967428/1097712 = idénticos a los nuestros** (derivada DRM, no override OEM). Su propio README avisa: "The common OEM bit-clock override needs reconciliation for the 90/144 Hz groups" — **el override por modo NO existe en ningún repo**: hueco abierto en ambos. |
| 4 | `dpu_10_1_sm7675.h` (derivado de palawan `dpu_10_1_palawan.h@0d9f7fdf`) | **[PORTAR SI]** | P3 / medio-alto | Nosotros NO tenemos catálogo sm7675: `dpu_hw_catalog.c` llega a `dpu_10_0_sm8650.h`, `dpu_kms.c` sin entrada sm7675; nuestro DT usa fallback palawan (`palawan-dpu`, `palawan-mdss`, phy `palawan-dsi-phy-4nm`+fallback sm8650). Su catálogo: DPU A10.1, INTF_1/INTF_2→DSI0/DSI1, 3 DSC `NATIVE_42x`, XIN {0,4,1,5,9,13,14}, VBIF sm8650, perf sc7180. Difiere del fallback sm8650 en INTF/DSC/topología dual-DSI. Solo afecta cuando el DPU nativo escanee (hoy vamos por inherit/simpledrm); portar = añadir `.h` + 3 hunks de registro (ver su patch). No es causa del negro-con-luz (el DSI/byte-clock manda primero). |
| 5 | `uke-dispcc-votes.c` + `cliffs-display-icc.h` | **[REFERENCIA]** (votos) / **[NO]** (ICC) | P4 / medio | Votos: tablas OEM cliffs (PLL ≤2 GHz, MDP ≤600, byte ≤358M, pixel ≤625M) + proxy-vote sin segundo escritor RPMh — filosofía idéntica a nuestro FIX-A1b; byte/pixel cubren 148,6/158,6 con margen. ICC: rutas `mdp0-mem`+`cpu-cfg` (MASTER_MDP 21, SLAVE 524) sobre provider existente — **nuestro DT ya lleva `mdp0-mem via mc_virt`** (comentario `xiaomi-uke.dts:525`); no portar nodos paralelos (ellos mismos lo prohíben). |
| 6 | `uke-mdss-handoff.c` + `uke-display-smmu.c` | **[NO]** (filosofía incompatible) | P5 / alto si se porta | Ellos: **preservar splash del ABL** (no reset `msm_mdss_reset`, VBIF halt+DRAIN, retirar solo SMR 1c00/mask-2, ACTLR=1, dominios nuevos en otro CB). Nosotros: BCR-gateado + `uke_disp_reclaim` quirúrgico tras abort L51 (FIX-A1b). Su enfoque exige display vivo del firmware y DT `qcom,sm7675-mdss/boot-smmu` que no tenemos; mezclar ambos reclaim = riesgo L51. Tomar solo la idea de verificar el bit de reset por `regmap_read(0x8000)` tras assert. |
| 7 | `sm7675-uke-native-display.dtso` (grafo offline dual-DSI) | **[REFERENCIA]** | P3 / medio | Grafo completo y coherente: `qcom,sm7675-mdss/dpu/dsi-ctrl/phy-4nm`, dual-DSI master+sync, supplies L8B/vsp/vsn, reset TLMM 2, PHY v5.2 vdds L1B, OPPs MDP, `iommus 1c00/2` en DPU (no en MDSS), dispcc `sm7675` con parents a PLLs de cada PHY. Contra nuestro `fase4-display.dts` (inactivo, TODO): el suyo desactiva el stock y cuelga TODO del `uke_mdss` aislado + test `native-display-dt-contract.sh` (fdtoverlay + asserts de phandles). No aplicar como overlay aún; usar como plantilla cuando activemos DPU nativo. OJO: su overlay **apaga el framebuffer** (`stdout-path` fuera) — en nuestra fase actual eso nos dejaría ciegos. |
| 8 | Estado de donantes | — | — | Ningún sm7675 tiene panel nativo funcionando en ningún repo (ver cabecera). El único display vivo en todas partes es firmware-framebuffer. No hay "él lo tiene andando" que copiar. |

## PLAN DE PORTS (próximos ciclos, 1 variable por ciclo)

1. **L68 = hunk byte-clock DSC** (P1): en `build/kernel-pokes/k52-L16-tree/drivers/gpu/drm/msm/dsi/dsi_host.c:644`,
   tras `u32 bpp = …;` añadir `if (msm_host->dsc) bpp = msm_host->dsc->bits_per_component * 3;`
   (+ comentario "DSC input depth, not RGB888 container"). Gate: byte medido 148,65 MHz;
   test: su `dsi-clock-contract.sh` adaptado (lane 1189188000). Procedencia: linuxgamer
   `0011-…patch` (autor donante, "Experimental… not hardware validated") vía senemos `0001-…patch`.
2. **L69 = quitar `MIPI_DSI_CLOCK_NON_CONTINUOUS`** de `panel-xiaomi-o82-dualdsi.c:835-837`
   (ya justificado por K48-A; senemos lín 295 lo confirma). Gate: DSI clock continuo en LP11 desde power_on.
3. **L70 = comparata byte-a-byte init 104 vs 108** (host-only, 0 flashes): decodificar su `o82-data.h`
   42_02_0b_120_on con `o82-data.cpp` y difear contra nuestra secuencia; portar solo bytes divergentes
   con evidencia OEM. Incluye evaluar sus 4 `switch_commands` como vía a 90/144 Hz.
4. **L71 = DCS directo dual-host (bypass sync manager)**: variante de `o82_send` (senemos lín 60-80)
   tras PPS+L68 si el DDIC sigue mudo — ataca "ret=0 en lecturas" por el otro extremo del link.
5. **Fondo = catálogo DPU sm7675** (P3): cuando el DSI dé ACTIVE_H/contenido, añadir `dpu_10_1_sm7675.h`
   + registro (3 hunks de su patch) con compatible nuevo, sin tocar fallback palawan.

Riesgo global: todo lo senemos es "Hardware unvalidated" (su README, 14-oct-2026) — cada port
lleva ese rótulo en el commit + rollback como siempre. Siguiente ciclo recomendado: **L68 (1 variable:
solo el hunk byte-clock)**.
