# L48-PREP — Traza fina del bind del DPU + migas + veredicto FASE-1 (14-oct-2026)

> Subagente preparador del ciclo L48. Solo lectura en tablet y árbol
> (`build/kernel-pokes/k52-L16-tree` NO tocado; parche generado en /tmp).
> Base: `docs/historia/revision/PIPELINE-PANEL-20261014/BRIEF.md`, `H2-CRASH-CAPTURADO-20261014.md`, `docs/historia/revision/PIPELINE-PANEL-20261014/CRITICA-L47.md`,
> resultado L47 (FALLA-A: H2-fbdev refutado), dumps `out/h2-dumps/uke-48.txt.gz`
> (boot caído) y `uke-6780.txt.gz` (control display-off vivo), árbol vivo,
> `docs/historia/revision/ROADMAP-PANTALLA-20261013.md` §FASE 1, `docs/historia/revision/ANDROID-POWER-DPU-20261013.md`,
> `AUDITORIA-METODO-20261013.md` §E9.

## 0. Corrección importante al encargo (evidencia en mano)

El encargo dice «el asesino está en el bring-up del DPU (hw init + resume),
antes de cualquier commit». La evidencia del dump matiza: **el bind COMPLETA**.
`uke-48` muestra `[drm] Initialized msm-kms 1.13.0 … on minor 1` (línea 46.984940),
que lo imprime `drm_dev_register`, DESPUÉS de que `dpu_kms_hw_init` retornara 0
(`msm_drm_kms_init` → irq_install → `mode_config_reset`, todo ejecutado).
La muerte llega después (~50 s según ACM del orquestador, sin más migas y con
cero `atom-tail`). Conclusión honesta: **la herida puede estar en el bind
(efecto retardado), pero el punto de muerte está después de `Initialized`**.
L48 bracketea AMBOS: subdivide el bind (por si la herida deja firma) + añade
corchete temporal post-bind (para acotar la muerte). Si las K48 del bind salen
todas, el veredicto es FALLA-POST, no FALLA-BIND — y eso también es un resultado.

## 1. Qué he leído (fichero:línea de lo relevante)

- `drivers/gpu/drm/msm/disp/dpu1/dpu_kms.c:1140-1301` (`dpu_kms_hw_init`),
  `:1303-1330` (`dpu_kms_init`, siembra OPP), `:1388-1436` (`dpu_dev_probe`),
  `:1458-1503` (`dpu_runtime_resume`), `:441-446` (`enable_commit`).
- `drivers/gpu/drm/msm/msm_kms.c:180-229` (`msm_kms_init_vm`), `:275-352`
  (`msm_drm_kms_init`), `:392-400` (`msm_drm_kms_post_init`).
- `drivers/gpu/drm/msm/msm_mdss.c:232-280` (`msm_mdss_enable`), `:310-330`
  (`msm_mdss_reset` + gate inherit), `:383` (reset corre en `msm_mdss_init`,
  i.e. en el probe temprano, NO en el bind).
- `drivers/gpu/drm/msm/msm_drv.c:1057-1060` (`msm_drm_bind`), orden en
  `msm_drm_init` (kms_init → kms_init-drm → `drm_dev_register` → post_init).
- `drivers/clk/qcom/clk-rcg2.c:1388-1397` (set_rate con clock OFF = solo
  cachea `parked_cfg`), `:1423-1446` (`shared_enable` escribe `parked_cfg`
  + UPDATE, incondicional), `:1516-1545` (`shared_init` aparca a safe-source
  en el probe).
- `drivers/clk/qcom/dispcc-sm8550.c:633-648` (SRC `disp_cc_mdss_mdp_clk_src`,
  `clk_rcg2_shared_ops`), `:587-612` (ftbl palawan, incluye 514000000),
  `:1446-1465` (rama `disp_cc_mdss_mdp_clk` con `CLK_SET_RATE_PARENT`),
  `:1644-1654` (`mdss_gdsc`).
- `arch/arm64/boot/dts/qcom/palawan.dtsi:3357-3382` (mdss: `power-domains =
  MDSS_GDSC` + `resets = CORE_BCR`), `:3390-3415` (mdss_mdp: 5 clocks
  nrt_bus/iface/lut/core/vsync, OPP `mdp_opp_table`), `:3446-3472` (OPP
  200/325/375/**514** MHz).
- `drivers/gpu/drm/msm/disp/dpu1/dpu_vbif.c:248-261` (`dpu_vbif_init_memtypes`,
  sin guards), `dpu_hw_vbif.c:57-83` (`set_mem_type`: RMW a
  `VBIF_OUT_AXI_AMEMTYPE_CONF0/1`).
- `drivers/soc/qcom/uke-panic-fb.c:240-257` (`uke_poke`: `pr_err` + pintado;
  SÍ sale por ACM/dmesg), `include/linux/uke-poke.h`.
- Dumps: `uke-48` líneas ~46.976-46.987 (bind completo) y `uke-6780:165-166`
  (cmdline control con `video=DSI-1:d` + `pd_ignore_unused` +
  `clk_ignore_unused`), `uke-6780:2948` (`Initialized msm-kms minor 1` a
  47.05 s en el control = el bind también completa con display-off).

## 2. Traza fina del bind (lo que hace, paso a paso, file:line)

Gatillo (igual en ambos brazos): `o82_probe` → `devm_mipi_dsi_attach` →
`dsi_host_attach` → `component_add` → `try_to_bring_up_aggregate_device` →
`msm_drm_bind` (`msm_drv.c:1057`) → `msm_drm_init`. La traza del WARN lo
confirma (`uke-48`: `o82_probe+0x418 → … → msm_drm_bind → msm_drm_init →
msm_drm_kms_init+0xec → dpu_kms_hw_init+0x140`).

| # | Paso | Sitio | Efecto HW |
|---|---|---|---|
| 1 | `dpu_kms_init` | `dpu_kms.c:1303-1330` | `opp_find_freq_floor(ULONG_MAX)` = 514 M → `dev_pm_opp_set_rate` (`:1317`): rama `core` → propaga al SRC (`CLK_SET_RATE_PARENT`) → clocks OFF ⇒ **solo cachea `parked_cfg`=514** (+ vota MMCX `rpmhpd_opp_nom` por `required-opps`). Luego `msm_kms_init`, `pm_runtime_enable`. |
| 2 | `hw_init` entra | `dpu_kms.c:1140-1165` | `K47-dpu-hw-in` (`:1142`); `pm_runtime_resume_and_get` (`:1165`) |
| 3 | Resume del PADRE primero | `msm_mdss.c:232-280` | `msm_mdss_enable`: votos icc (`:242-246`), `clk_bulk_prepare_enable` AHB/HF_AXI/**MDP_CLK** (`:256`) — **aquí ocurre el PRIMER `shared_enable` del SRC**: escribe `parked_cfg` (=514 sembrado en paso 1) + UPDATE. Luego lectura MMIO `REG_MDSS_HW_VERSION` + setup UBWC (`:269-276`). |
| 4 | Resume del DPU | `dpu_kms.c:1458-1503` | `K47-dpu-res` (`:1460`); inherit=OFF en L47 (cero líneas `P82-INHERIT` en `uke-48`) ⇒ `clk_bulk_prepare_enable` 5 clocks (`:1479`; SRC ya ON, sin escritura RCG) ⇒ `dpu_vbif_init_memtypes` (`:1497`, 16 RMW a VBIF) ⇒ loop encoders (todos `!enabled` → no-op, `dpu_encoder.c:virt_runtime_resume`) |
| 5 | Vuelta en `hw_init` | `dpu_kms.c:1169-1301` | `readl` revision (`:1169`, OK `0xa0010000` en dump) → `_dpu_kms_mmu_init` (`:1184` → `msm_kms_init_vm`: iommu_dev=`ae01000` mdp-mapeado/mdss-no + WARN `iommu_set_fault_handler` **benigno: 6× en el control vivo `uke-6780`**) → UBWC/rm/mdptop/vbif/perf/intr (solo structs + lecturas) → `_dpu_kms_drm_obj_init` (`:1277`) → 2º `dpu_vbif_init_memtypes` (`:1288`) → `put_sync` → return 0 |
| 6 | irq install | `msm_kms.c:338-340` | `pm_runtime_get_sync` → **resume#2** (`K47-dpu-res` + pasos de §4 otra vez) → `msm_irq_install` (escribe regs INTR MDP) → `put_sync`; `mode_config_reset` |
| 7 | Registro | `msm_drv.c` (`drm_dev_register`) | `[drm] Initialized msm-kms 1.13.0 … minor 1` (46.984940 ✓) |
| 8 | post_init | `msm_kms.c:392-400` | `poll_init` + `drm_client_setup` (**no-op** con `FBDEV_EMULATION=n`) |
| 9 | Retorno del bind | — | Burst `sync_state` (46.985-46.987: disp_cc/gcc + GDSCs `adf*/af*` — **normal**: resolución de deferred-probe, también en el control) |
| 10 | **Muerte ~50 s** | ACM (orquestador) | Silencio, cero `atom-tail`, reset `pureason=0x80100` |

Candidatos, ordenados con honestidad:

| # | Candidato | Estado |
|---|---|---|
| C1 | Siembra OPP 514 → `parked_cfg` (ROADMAP FASE 1 / parked_cfg=0) | **CERRADO en código** (§3). `K48-opp-rate` lo confirma en vivo en este mismo ciclo. |
| C2 | Doble reescritura VBIF sobre scanout ABL vivo (`:1288` + `:1497`, inherit OFF, sin guards; el vendor lo salta con doble guard `ANDROID-POWER-DPU` §2) | Vivo pero débil (muerte 3 s después, sin fault en log). |
| C3 | GDSC `MDSS_GDSC` / MMCX (power-up en el resume del padre, `palawan.dtsi:3377`) | Sin señal; aparcado. El enable de GDSC no escribe RCG. |
| C4 | Reset BCR (`msm_mdss.c:383`) | Corre en el **probe temprano** (`msm_mdss_init`), igual en ambos brazos; NO discrimina. Aparcado. |
| C5 | Actor post-bind con conector enabled (userspace/sddm, servicio tardío) | Vivo: es lo único que difiere `:d` vs no-`:d` tras un bind idéntico. `K48-alive` lo acota; `atom-tail`=0 ya excluye commit vía `commit_tail`. |
| C6 | Causa no-display / flaky (slot, batería, entorno) | Vivo por descarte: L48 = L47 + migas inertes; si L48 vive, L47 fue entorno. |

## 3. Veredicto FASE-1: NO se propone `l48-fase1.diff` (con evidencia)

Cadena verificada en el árbol actual:

1. `dpu_kms_init` (`dpu_kms.c:1313-1317`) hace `dev_pm_opp_find_freq_floor(dev,
   ULONG_MAX)` → OPP más alto = **514 MHz** (`palawan.dtsi:3464-3472`) →
   `dev_pm_opp_set_rate(dev, 514M)` sobre el clock `core`
   (`devm_pm_opp_set_clkname(dev,"core")` en el probe, `dpu_kms.c:1404`).
2. La rama `core` (`DISP_CC_MDSS_MDP_CLK`) lleva `CLK_SET_RATE_PARENT`
   (`dispcc-sm8550.c:1453-1465`) ⇒ el set_rate propaga al SRC.
3. A esa hora los clocks están OFF (el primer enable es el paso 3 de §2) ⇒
   `__clk_rcg2_shared_set_rate` solo cachea `parked_cfg`
   (`clk-rcg2.c:1388-1394`), sin tocar el HW.
4. El primer `shared_enable` (paso 3) escribe de vuelta ese `parked_cfg`=514
   (`clk-rcg2.c:1437`) — exactamente el mecanismo del vendor
   (`ANDROID-POWER-DPU` §7, capas 1+2). El propio `msm_mdss_enable` lo asume
   en su comentario TODO (`msm_mdss.c:248-255`: «exercised after the correct
   OPP has been set in one of the MDPn or DPU drivers»).
5. Entre el park de `shared_init` (probe dispcc, `parked_cfg`=CFG del ABL
   = 514-equivalente) y el bind no hay ningún otro consumidor del SRC
   (mdss/dpu/dsi entran todos por el aggregate-bind a ~47 s).

⇒ **E9 es correcto y FASE-1a/1c son redundantes con el código actual**:
sembrar el SRC desde código repetiría lo que el OPP ya hace. La prueba en
vivo viaja GRATIS en este ciclo (`K48-opp-rate`, §4 M4): si lee `514000000`,
FASE-1 queda cancelada con evidencia medida; si lee otra cosa, FASE-1 revive
y L49 = sembrar el SRC (patrón ROADMAP §1a). **Un cambio por ciclo: L48 solo
instrumenta.**

## 4. Migas propuestas (`l48-migas.diff`, 10 hunks, 3 ficheros, `patch -p1` OK)

Verificado `patch -p1 --dry-run` sobre copia limpia (en /tmp, árbol intacto).
Líneas = post-parche (lado b). Todas inertes (`uke_poke` = `pr_err` + pintado
lock-free, falsado como asesino en X9 s166/s167; el heartbeat añade 1
`delayed_work` sin locks).

| Tag | Fichero:línea (b) | Qué bracketea |
|---|---|---|
| `K48-opp-rate core=%lu` | `dpu_kms.c:1324-1331` (en `dpu_kms_init`, tras `dev_pm_opp_set_rate`) | **La siembra**: con clocks OFF, `clk_get_rate("core")` recalcula desde `parked_cfg`. Esperado `514000000`. Decide FASE-1 en vivo. |
| `K48-mdss-en-in` / `K48-mdss-en-ok` | `msm_mdss.c:237` / `:264` (entrada y tras `clk_bulk_prepare_enable` de `msm_mdss_enable`) | Resume del PADRE (corre antes que el del DPU; aquí va el 1er `shared_enable` del SRC + votos icc + lectura UBWC). |
| `K48-res-clk-in` / `K48-res-clk-ok` | `dpu_kms.c:1493` / `:1500` (antes/después de `clk_bulk_prepare_enable` en `dpu_runtime_resume`) | El enable de los 5 clocks del DPU. |
| `K48-hw-resume-ok` | `dpu_kms.c:1169` (tras `pm_runtime_resume_and_get` en `hw_init`) | Resume#1 completo (padre+hijo). |
| `K48-hw-mmu-ok` | `dpu_kms.c:1192` (tras `_dpu_kms_mmu_init`) | IOMMU/VM (tras el WARN benigno). |
| `K48-res-vbif-ok` / `K48-res-enc-ok` | `dpu_kms.c:1515` / `:1520` (tras `dpu_vbif_init_memtypes` y tras el loop de encoders en el resume) | Escrituras VBIF + resume de encoders. |
| `K48-hw-vbif-ok` | `dpu_kms.c:1293` (tras el 2º `dpu_vbif_init_memtypes` en `hw_init`) | 2ª escritura VBIF. |
| `K48-post-init` | `msm_kms.c:420` (entrada de `msm_drm_kms_post_init`) | Bind registrado; arma el heartbeat. |
| `K48-alive-1/2/3` | `msm_kms.c:402-411` (`delayed_work`: +3 s, +8 s, +15 s tras post_init) | **Corchete temporal**: el último impreso en el ACM acota la muerte. |

Orden esperado en el ACM (bind ~47 s): `K48-opp-rate core=514000000` →
`K47-dpu-hw-in` → `K48-mdss-en-in` → `K48-mdss-en-ok` → `K48-res-clk-in` →
`K48-res-clk-ok` → `K48-res-vbif-ok` → `K48-res-enc-ok` →
`K48-hw-resume-ok` → revision → K13/mmu/WARN → `K48-hw-mmu-ok` → …
→ `K48-hw-vbif-ok` → [resume#2: `K48-res-*` otra vez] → `Initialized` →
`K48-post-init` → (`K47-tx-alloc`×2 donde caigan) → sync_state →
`K48-alive-{1,2,3}`.
Regla de lectura (E6 bien aplicado): la última miga = «murió EN o DESPUÉS»;
`K48-res-*` sale **×2 por bind** (resume#1 de `hw_init` + resume#2 de
`irq_install`), igual que `K47-dpu-res` ×2 en L47 — no leer duplicados como
dos enables.

## 5. Criterio prefijado de L48 (5 ramas, excluyentes)

- **PASA** (vive >6 min SIN `atom-tail`): bind + post-bind estables con
  conector enabled. L48 = L47 + migas inertes ⇒ la muerte L47 no reproduce:
  atribuir a entorno (slot/batería), NO al display. Siguiente: vci/DCS con
  modeset userspace en OTRO ciclo (aquí: solo observar, sin modetest).
- **FALLA-COMMIT** (`atom-tail` SÍ + muerte): un userspace modeseteó; el
  asesino está en el enable-path del commit. Siguiente: relectura de las
  K47 hasta la última + clocks/GDSC del commit.
- **FALLA-POST** (`post-init` SÍ, muerte sin `atom-tail`): asesino post-bind
  independiente del commit. `alive-1` ausente = muerte <3 s tras
  `Initialized`; `alive-1/2/3` = ventanas 3/8/15 s. Siguiente: cazar el actor
  de la ventana (sddm, servicio tardío, GDSC/VBIF retardado).
- **FALLA-BIND** (falta alguna K48 hasta `post-init`): la herida SÍ está en
  el bind; última miga = punto (§4). Si además `K48-opp-rate ≠ 514000000` ⇒
  **FASE-1 revive** y L49 = sembrar el SRC.
- **FALLA-TEMPRANA** (muerte <20 s o sin `K47-dpu-hw-in`): otra muerte
  (estilo L33/L39); no concluye sobre el display; comparar contra control
  display-off del mismo día.

## 6. Runbook (1 escritura)

1. Pre-vuelo (solo lectura): `fastboot getvar all` (4 `slot-retry-count` +
   `unbootable` + mV; gate: mV ≥3700, si `slot-retry-count:b` <3 el día es
   solo-lectura); confirmar ningún slot `unbootable` (H2 dejó `a:6→0`); leer
   `ESTADO-ACTUAL.md` + últimas filas del ledger hermano (semáforo
   inter-proyecto); ACM **lector único** armado antes del flash
   (`bin/uke-console-cap.sh`) + dumper k22b activo; `touch
   /tmp/uke-fastboot-watch.pause` durante el flash.
2. Build L48 = L47 + `l48-migas.diff` (gates del repack: 12 tags K48 ×1 en
   `strings` del Image; cmdline display-ON 566 B sin `video=DSI-1:d`;
   `FBDEV_EMULATION=n` se mantiene — variable única: instrumento).
3. Flash: **1 escritura a `boot_a`**; `dtbo_a` s287 se queda. Fila del ledger
   **pre-registrada con sha256 ANTES de flashear**; verificación por lectura
   al tamaño exacto tras flashear.
4. Observación: doble captura (ACM continuo + dumper 20 s); SSH: NO modetest,
   NO tocar nada; esperar ≥6 min (o hasta el reset). Registrar mV final y
   slots después.
5. Rollback prefijado: si FALLA con slot tocado, reflash L45 (`83647c45…`) a
   `boot_a` (2ª escritura del día, contar en ledger) y parar.

## 7. Riesgos

- **Slots**: H2 quemó `a` hasta `unbootable`; hoy ya van varias escrituras
  (#618+). Si el pre-vuelo muestra retries bajos, L48 se mueve a mañana —
  escrito aquí para que no se negocie en caliente.
- **La muerte cae a ~50 s**: las K48 del bind (segundo 47) siempre se
  capturan; el resto lo acota `alive` en el ACM. Si el ACM pierde la cola
  (115200 lossy), el dumper de 68 s no existirá igual que en L47 — la rama
  FALLA-POST exige el ACM, no el dumper.
- **E6**: 12 señales inertes no mueven el punto de muerte (pokes falsados en
  X9; el `delayed_work` no toca locks ni HW). No ensanchar: ni GDSC, ni
  `msm_atomic_commit`, ni VBIF-gates en este ciclo.
- **REFUTADO/LECCIONES**: revisados en lo aplicable (R-12 `fastboot boot`
  usa dtbo del slot — por eso se flashea `boot_a` de verdad; R-42 sin
  recuperación automática — vigía físico obligatorio; regla 4 doble captura;
  regla 5 `sync` antes de reset).

## 8. Presupuesto

L48 = **1 escritura** (`boot_a`); `dtbo_a` s287 intacto; rollback L45 = 2ª
escritura solo si procede (§6.5). Sin `l48-fase1.diff` (ver §3; se genera en
L49 solo si `K48-opp-rate` lo pide).

## 9. Qué NO hacer

Flashear otra cosa; añadir variables funcionales (VBIF-skip, GDSC, OPP,
`panel_inherit`, DT); modetest/sddm a mano en este ciclo; leer `/dev/ttyACM0`
con dos lectores; compilar/flashear desde esta preparación (esto es solo el
dossier + diff).
