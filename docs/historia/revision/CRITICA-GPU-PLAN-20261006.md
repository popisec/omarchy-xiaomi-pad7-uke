# CRITICA-GPU-PLAN — revisión HARDWARE de la fase GPU-CM3 (6-oct-2026, pre-#538)

> Revisor: crítico hardware. 100 % offline (tablet NO tocada; cero adb/fastboot).
> Método: lectura COMPLETA de `build/kernel-pokes/k52-tree/drivers/gpu/drm/msm/adreno/a6xx_gmu.c`
> (3052 líneas), más los caminos que alimentan S3: `a6xx_gpu.c` (probe/resume/destroy,
> pm_resume), `a6xx_hfi.c` (tablas HFI), `a6xx_catalog.c` + `adreno_gpu.h` (clasificación del
> chip), `drivers/clk/qcom/gpucc-palawan.c` (completo), `a6xx_gpu.h` (cx_misc), el DT FINAL
> fusionado que corre la tablet (`/var/tmp/uke-s270/m270.dts` y overlay `s270.dts`), y la
> **cmdline REAL del k55 extraída hoy del bootimg en disco**
> (`build/bootimg/boot-uke-k55-cbwin.img`, header offset 64, sin tocar nada).
> No duplica la crítica operativa (docs/historia/revision/CRITICA-GPU-OPS-20261006.md: sysctls, dd, fastboot) — la
> referencia donde cruza.

---

## 0. Dos hechos del enunciado que la evidencia corrige (y cambian el plan)

**C0.1 — k55 NO corrió con `gmu_shared=1`.** La cmdline del bootimg k55
(`boot-uke-k55-cbwin.img`, extraída hoy, offline) lleva **`msm.uke_gmu_shared=0`** (dominio
IOMMU PROPIO del GMU vía los parches K33/K38 de arm-smmu-qcom) **y `msm.uke_smmu_dump=1`**
(volcado K19/K24 + ventanas CB STD `+0x8000` del k55 **ACTIVO**). Consecuencias:

- Todo razonamiento sobre "el vm del GMU comparte el mmu del GPU (SID5, mismo CB1 que el
  GPU)" es **VOID para el boot #536**: con `=0`, `a6xx_gmu_memory_probe` (`a6xx_gmu.c:2114`)
  crea `msm_iommu_new` propio; el CB1 que el dump vio con `SME(1)→TRANS→CB1` es **del dominio
  del GMU**, no del GPU. (La premisa compartida vale solo si el próximo experimento borra
  `msm.uke_gmu_shared=0` de la cmdline.)
- **El discriminador CB1/WALK YA CORRIÓ** en el boot #536: el log de ese boot contiene
  `WALK iova=0x4000 ...` (¿MAPPING ENCONTRADO phys=…? ¿NO HAY MAPPING AQUI?), las líneas
  `CB0/CB1 STD +0x8000: SCTLR/TTBR0` y `UKE-CM3DBG: clks core=… hub=…`. **Ese log es el dato
  más caro del plan y ya existe** — recuperarlo (host-stream del #536, journalctl o pstore de
  la tablet por SSH) es la PRIMERA acción, antes de cualquier flash. Lo llamamos **G0**.

**C0.2 — el veredicto "STALE" de S0 no habla del boot en curso.** El discriminador
(`a6xx_gmu.c:662-694`) lee `DTCM+0xff8` en **S0, ANTES de escribir rst=1** (S1): es el DTCM
de la ejecución ANTERIOR (para el boot #536, el leftover de **Android**; la corrección 1-oct
del propio código lo admite: `val=0x40050001` ya se malinterpretó una vez). El ÚNICO testigo
vivo del boot actual es el poll S4 (`:766`, 100 µs × 100 ms). "STALE + poll FAIL" solo
demuestra "el fw del intento anterior no dejó magic" cuando hay ≥2 intentos en la misma
vida del driver (re-arms); en un solo boot frío es consistente con leftovers y NO es
evidencia contra el CM3 de ese boot. El plan G1 debe alinear índices (veredicto de S0 del
intento N ⇒ intento N−1) y, para un testigo dtcm del MISMO boot, hace falta relectura en el
error-path (k56, §3).

---

## 1. Secuencia mainline completa antes de S3 (lo que hay, en orden, con línea)

Caminos: `a6xx_gmu_resume` (:1795) → `a6xx_gmu_fw_start` (:1403) → `a6xx_gmu_start` (:655).

| # | Paso | Línea | Qué hace / qué puede fallar en nuestro árbol |
|---|------|-------|----------------------------------------------|
| H1 | `pm_runtime_get_sync(gmu->dev)` | :1808 | device-link PM → `cxpd` → **CX GDSC ON** vía genpd (`gpu_cc_cx_gdsc`, gpucc-palawan.c:516, VOTABLE+RETAIN_FF). **Ya está hecho por el framework**; el MMIO vivo de K44 lo prueba. |
| H2 | `a6xx_gmu_gxpd_get` | :1811, gpucc:536 | `gdsc_gx_do_nothing_enable` — **NO-OP real** en cliffs: la GDSC GX no se toca desde CPU (y sus `.resets` ACD_BCR/GX_ACD_IROOT_BCR tampoco se disparan nunca). GX queda como la dejara el boot anterior (tras reboot: colapsada). |
| H3 | rates + `clk_bulk_prepare_enable` | :1815-1823 | core: pide 200 MHz → **redondea a 220** (ftbl gmu_clk_src 19.2/220/550, gpucc:175; igual que Android idle: 220). hub: gen71100 ES `ADRENO_7XX_GEN2` = **a740_family** (a6xx_catalog.c:1619, adreno_gpu.h:565) → mainline YA pide 200; el cherry F2 (aplicado: gpucc:156 tiene pre_div 6) es lo que hace el 200 **alcanzable**. 7 clks (ahb, gmu, cxo, axi, memnoc, hub=hub_cx_int, demet). `hub_aon` NO va en la lista — igual que mainline sm8650, no es hueco. |
| H3' | log rates reales | :1829 | `UKE-CM3DBG: clks core=… hub=…` — G1 debe leerlo del log existente, no re-medir. |
| H4 | `a6xx_gmu_secure_init` | :1833, :1686 | Para gen71100 **no hace nada** (ni a750 ni a8xx ni a740 puntual): sin SCM, sin fuses. No es candidata. |
| H5 | `a6xx_gmu_set_initial_bw` | :1841 | `dev_pm_opp_set_opp` sobre OPPs **sin `opp-peak-kBps`** e `interconnects` VACÍO (m270.dts nodo GPU): cero voto de DDR previo al boot. Post-boot el HFI manda la tabla BW **hardcodeada a740** (`a740_build_bw_table`, a6xx_hfi.c:799) porque `nr_gpu_bws=1`. Irrelevante para S3, relevante para G4. |
| H6 | IRQ GMU enable + mask | :1844-1847 | OK. WDOG/FENCE_ERR ya atentas (pero ver §3: un wedge de bus no genera IRQ). |
| H7 | cold/warm | :1850-1862 | a7xx: lee `A7XX_CX_MISC_TCM_RET_CNTL == 1` → **WARM** (¡y el propio fw_start escribió ese 1 en el intento anterior, :1424-1427!). Crítico para re-arms (§4). |
| P0 | FAL10 veto | :1415-1421 | `CX_FALNEXT_INTF/CX_FAL_INTF=1`. OK. |
| P0' | TCM retention | :1424-1427 | `TCM_RET_CNTL=1` (a7xx, cx_misc sobre `cx_mem` 0x3d9e000). Es lo que convierte el intento N en warm para N+1. |
| P1 | `a6xx_rpmh_start` | :1429, :1064 | **NO-OP en cold boot**: solo corre si `GMU_STATUS_PDC_SLEEP` (:1069), que solo pone `a6xx_rpmh_stop` (:1117) tras un apagado exitoso. ⇒ **La secuencia PDC/RSC de despertar NO se ejecuta antes de S3**; lo único que corrió fue `a6xx_gmu_rpmh_init` en PROBE (:1125: seqmem a740 + `PDC_ENABLE_PDC=0x80000001` en 0xb280000, pdc_in_aop=true para a7xx, :1144-1146 — no se mapea `gmu_pdc_seq`). |
| P2 | `a6xx_gmu_fw_load` (solo COLD) | :1436-1447, :1320 | ITCM/DTCM por MMIO (bases 0x0/0x10004000 a7xx, :1329-1335) y **el cuerpo del fw (bloque @0x4000) al BO icache en DRAM**, visible al CM3 solo vía SMMU SID5. El "Loaded GMU firmware v4.5.1" (:1380) es una lectura MMIO del GMU — NO prueba ejecución. Pokes F1-F4 solo en este camino: **su ausencia = warm boot** (detector gratis). |
| P3 | registros del CM3 | :1450-1511 | FW_INIT_RESULT=0, BOOT_CONFIG=0x02, HFI_QTBL, FENCE_RANGE (a7xx 0x8a0/0x32, :1462-1464), CM3_CFG=0x4052, chipid `0x70b0000` (catálogo :1637) → rama a7xx GENERAL_10/GENERAL_8 (:1501-1505). K44 (#499) verificó lectura-sane de todo esto. |
| P4 | gbif_cx | :1514-1515 | `a640_gbif` por catálogo (:1636). Mainline-estándar. |
| P5 | `a6xx_gmu_power_config` | :1524, :1258 | ICACHE/DCACHE/SYS_BUS=1 y **return early en a7xx** (:1269): sin hysteresis IFPC ni `RPMH_CTRL` enable. Gen71100 no tiene quirk IFPC (catálogo :1626-1628) → `idle_level=ACTIVE` (:2852): HFI IFPC no se mandará (coherente). |
| S0-S4 | `a6xx_gmu_start` | :655-788 | S0 lee DTCM stale y **de ahí salen mask/reset_val del poll** (:665-671; 0x40050001 → `mask=0x1ff, reset_val=0x100`); S1 rst=1; S2; K44 A-E; **[en k55: volcado SMMU completo con `pr_flush(120ms) POR LÍNEA` — segundos de delay inyectados aquí]**; S3 rst=0 (:758); poll 100 ms (:766). |

**Agujeros reales del lado fork (no hay guardias UKE que salten la secuencia; los hallazgos):**

1. **`qcom,qmp` NO existe en el nodo GMU final** (m270.dts: el overlay @906 no lo añade; el
   nodo vendor trae `mboxes=aop` que mainline ignora). ⇒ `gmu->qmp = ERR`,
   `a6xx_gmu_acd_probe` sale por :2586-2587 sin llamar a `qmp_send` → **AOSS NUNCA se
   entera de que ACD pasa a off**; conserva el `acd=1` de Android (captura #527/#535) con un
   kernel+fw que operan ACD-less. Pieza EXTERNA que ni reseteamos (ACD_BCR/GX_ACD_IROOT_BCR
   viven como `.resets` de una GDSC do-nothing, gpucc:530-532) ni re-configuramos.
2. **GX GDSC = do-nothing** (gpucc:536): el arranque del fw depende de que él suba el rail GX
   él mismo (así es mainline en todos los a7x soportados), pero en cliffs eso pasa por
   AOSS/ACD → converge con (1).
3. **RSCC con offsets a740-family sobre el RSC de un gen71100** (seqmem `REG_A7XX_…_A740`,
   :1178-1179): no afecta cold boot (P1 es no-op), pero escrituras de probe en 0x3d50000 con
   offsets no validados contra el vendor son un riesgo diferido (sleep/wake) y una variable
   no controlada.
4. `gpu_cc_sleep_clk` con `enable_reg = 0x9168` = **el CMD_RCG de `gpu_cc_gmu_clk_src`**
   (gpucc:507 vs :183; x1e80100 usa su propio halt_reg 0x9134): typo de port. `clk_bulk`
   puede escribir BIT(0) del CMD del RCG del reloj del GMU en cada enable/disable de esa
   branch (bit UPDATE). Baja probabilidad de daño, pero es una escritura cruzada en el
   bloque que gobierna el core del GMU: anotarla y (k56+) corregirla a 0x90dc.

---

## 2. Ranking de causas del "ITCM cargado pero no ejecuta"

Testigos actuales: K44 A-E todo-sane pre-release (#499), poll FAIL, dtcm STALE (con el sesgo
C0.2). Refutados con medición: config/vectores CM3, fault-limpio con handler armado (P141),
SID5 sin reprogramar (P132), TCU/keep (K44b), TBU gpu_qtb (#515), warm-por-BL (#515),
`-ERANGE`/TTBR1 (K35). Ranking con el código en la mano:

**#1 — Fetch del icache con mapping defectuoso (traducción válida a PA malo, o CB no
seleccionada por el TBU).** Anclas: el cuerpo del fw NO va a ITCM — vive en DRAM y el CM3 lo
consume vía SMMU SID5 (P2, :1370-1372); K44 solo prueba que el primer bloque (ITCM, :1358)
llegó a la RAM del CM3. Un fault LIMPIO está refutado (P141, handler armado y silencio), pero
eso deja justo la variante que no salta handler con rastro legible o que congela el AHB (§3).
**Estado: la respuesta YA se midió en el boot #536** — el WALK del dump k55 (cmdline
`msm.uke_smmu_dump=1`) imprimió si el descriptor de 0x4000 existe en el CB1 del dominio
propio del GMU. **G0 la recupera sin gastar un boot.** Si el WALK dijo "MAPPING ENCONTRADO
phys=…", esta causa cae al #3; si dijo "NO HAY MAPPING AQUI", es LA causa.

**#2 — FW estancado en init dependiente de GX/ACD por herencia AOSS (`acd=1` de Android).**
Anclas: §1.1-1.2 (qmp ausente → sin notify; GX do-nothing; ACD BCRs nunca disparados);
Android arranca el MISMO fw v4.5.1 con ACD=1 (hecho #527/#535). El fw mainline-esperado
opera ACD-off mientras el microcontrolador AOSS cree lo contrario: es el único actor del
sistema cuyo estado no controlamos ni reseteamos y que toca el clocking del dominio GX que
el propio fw intenta gobernar al arrancar (el GX NO es gobernable desde CPU — hecho #527).
Falsable **sin kernel nuevo** (experimento dtbo-only, §5-G3.1).

**#3 — Falso-FAIL del poll (C5) + dtcm magic por otra vía.** Solo sobrevive si el fw de esta
GPU señaliza éxito sin escribir `FW_INIT_RESULT=0x100` ni el magic DTCM — dos testigos
independientes en contra. `mask/reset_val` vienen del STALE (:665-671) y son una convención
downstream, no un contrato del fw. Barata de enterrar: relectura de DTCM+FW_INIT_RESULT+
FENCE_STATUS+SPTPRAC en el error-path (k56, §5-G3.2).

**#4 — Timing/rails (familia del freeze).** Explica la RAZA (§3), no el timeout estable de
k55: CX está viva (MMIO responde), hub/core rates nominales e iguales a Android. Solo se
activa cuando algo no ha asentado al llegar S3.

**#5 — RSCC/PDC offsets de a740 en gen71100.** No toca cold boot (P1 no-op). Diferido a
sleep/wake y a la estabilidad de larga duración; no gastar kernels aquí.

**Descartadas por el código sin gastar boot:** "CX GDSC off" (H1 la enciende por genpd y el
MMIO de K44 lo prueba), "hub/core rate malo" (220/200 = exacto al Android idle; el UKE-CM3DBG
del log #536 lo asienta), "warm-boot salta fw_load en el PRIMER boot" (F1-F4 presentes en el
log #536 = cold; #515 ya lo cerró), "sin votes RPMh del GMU" (power_config es no-op a7xx por
diseño mainline).

---

## 3. La raza freeze/timeout (y si el volcado k55 es inocuo)

**Mecanismo del freeze (k53/k54, firma "S3 y silencio, sin USB/panic"):** S3 suelta el CM3;
su primer fetch cruza GMU-AHB → TBU(SID5). Si la transacción queda **stall/pendiente** (TBU a
medio armar, rail/clock asentando), el `readl` del poll (`gmu_poll_timeout` → `readl_poll`)
cuelga la CPU en D-state **para siempre**: la CPU no vuelve, no hay IRQ que la rescate (el
WDOG del GMU es interrupción del GMU, que ya no atiende el bus), softlockup/RCU no ven una
CPU en una carga MMIO que no retorna ⇒ muerte seca. El AHB fence (P3) solo vallala ventana
0x8a0..0x32 de transacciones del GMU — **no cubre el fetch por SMMU** — y FENCE_ERR es IRQ
del GMU: si el wedge es del esclavo AHB, nadie imprime.

**¿El volcado k55 cambió el estado? NO como escritura; SÍ como tiempo — y eso es
experimentalmente decisivo.** Los reads del dump (sCR0/sGFAR/ID0-ID1/SMR/S2CR/CB SCTLR/TTBR,
ventanas legacy y STD +0x8000) son read-only y **ninguno es clear-on-read** (no se lee GFSR
ni status de fault) ⇒ no alteran SMMU ni CM3. PERO cada línea `UKE_K19_LOG` hace
`pr_flush(120, false)` (:353-356) y el volcado imprime decenas de líneas ENTRE S2 y S3
(:751-756): **el k55 pasó S3 con segundos de delay inyectado**; k53/k54 congelaron sin él.
Correlación perfecta con la hipótesis temporal de §2-#4. Consecuencias para el plan:

- El N=5 sobre k55 (dump siempre ON por cmdline) mide el mundo "con delay" — no transfiere
  al mundo limpio. 
- **A/B barato sin rebuild**: repack de SOLO cmdline del k55 quitando `msm.uke_smmu_dump=1`
  → si congela, el delay/reads es la variable de la raza; si pasa, la raza es bimodal por
  boot y el "estructural 100 % repro" de K42/K43 ya no vale en esta configuración
  (k55+s270+gmu_shared=0+hub200). El inverso (msleep explícito pre-S3, k56 de 1 línea) es el
  experimento controlado si el A/B cmdline resulta ambiguo.
- Nota fina: `module_param(uke_smmu_dump)` es 0444 — en runtime NO se puede conmutar; solo
  cmdline (built-in: `msm.uke_smmu_dump=…`) o rebuild.

---

## 4. El re-arm por unbind/bind: revisión de código y veredicto

**Software: limpio.** `adreno_remove` (adreno_device.c:293) → `a6xx_destroy` (a6xx_gpu.c:2300)
→ `a6xx_gmu_remove` (a6xx_gmu.c:2664): `pm_runtime_force_suspend`, detach cxpd/gxpd, `qmp_put`,
`iounmap`, `a6xx_gmu_memory_free` (detach del mmu propio, :2034), `free_irq` ×2, `put_device`.
El re-probe rehace clocks/IRQs/BOs/cxpd/rscc-desde-devm desde cero (los fixes K32 del unwind
están en :2064-2080). El driver bound al nodo es **`adreno`** (adreno_device.c:424-429, `.name
= "adreno"`) — el `msm` del plan es el master DRM (OPS ya lo marcó; validar con `readlink
/sys/bus/platform/devices/3d00000.qcom,kgsl-3d0/driver` antes del primer unbind).

**Hardware: tres fugas que envenenan el intento N≥2.**

1. **`CM3_SYSRESET` queda en 0 tras un timeout.** El error-path de `a6xx_gmu_start`/resume
   (:766-787, :1891-1901) NUNCA re-asserta el reset; `a6xx_gmu_stop` no corre. En el
   re-bind, H3 re-enciende los clocks (:1818) y el CM3 — congelado solo por falta de reloj —
   **reanuda el fetch ANTES de que el driver llegue a S1** (:696), contra un CB1 recién
   re-attachado (pagetable vacío unos µs) ⇒ el freeze puede REAPARECER desplazado a H3/
   UKE-CM3DBG y el dataset lo leería como "la raza también existe en H3". Además K44-A
   imprime rst DESPUÉS de S1 (siempre 1): **no puede detectar la fuga**.
2. **`TCM_RET_CNTL=1` persiste ⇒ el intento 2 es WARM, no cold.** Si CX GDSC no colapsa entre
   intentos (el kgsl-smmu es TAMBIÉN consumidor de `GPU_CC_CX_GDSC` en el DT y puede tener el
   genpd vivo), H7 (:1850-1852) lee 1 → `GMU_WARM_BOOT` → **se salta `fw_load`**: CM3 contra
   icache-BO recién allocado SIN fw. Intento 2+ = configuración estructuralmente distinta
   (STALE garantizado por construcción, no por la raza). Detector gratis: **ausencia de
   F1-fwloop/F2/F3 en el log del intento** — registrarla por intento.
3. **El veredicto dtcm del intento N describe el N−1** (C0.2): alineación obligatoria del
   dataset; un STALE en N+1 tras un OK en N ya no sería anomalía.

**Veredicto (instrumento):** VÁLIDO SOLO CON REFORMAS. Sin tocar código: sustituir los 5
re-arms por **5 reboots** (cada boot frío reproduce exactamente el estado inicial del #536:
mismo leftover de Android, cold boot, dump=1 si la cmdline lo mantiene) y aceptar ~2-3 min
por trial con la conversión-panic de OPS armada a mano. Con un kernel k56 barato (3 líneas:
assert `SYSRESET=1` tras mapear mmio en `a6xx_gmu_init`; loguear `status` warm/cold en H5;
bloque K44'' — relectura dtcm/FW_INIT_RESULT/FENCE_STATUS/SPTPRAC — en el error-path del
poll) el re-arm se vuelve cuantificable de verdad. Tal cual está el plan (N=5 re-arms sobre
k55 sin k56), **no cuantifica la raza: mezcla cold/warm y trials con el CM3 fugado**.

---

## 5. Agujeros del plan y orden G0→G4 revisado

**Cortar (refutados por el código, queman kernel sin poder mover el fallo):**
- G3(a) "forzar CX GDSC on antes de S3" — ya lo hace el framework en H1 (genpd→CX GDSC) y el
  MMIO vivo de K44 lo prueba. No hay experimento ahí.
- G3(c) "reordenar PDC seq" — `a6xx_rpmh_start` es no-op en cold boot (sin `PDC_SLEEP`) y
  `rpmh_init` corrió en probe (G8/G9 vistos en logs): mover piezas de una secuencia que no
  participa del camino del boot.
- G3(d) "activar/forzar ACD off" — el driver YA opera ACD-off (`enable_by_level=0`,
  gpu_opp_uke sin `qcom,opp-acd-level`); el delta real es el **estado heredado del AOSS**
  que no notificamos por falta de `qcom,qmp` en el DT.
- G2 "verificar si PDC/CX se ejecutan antes de S3" — respuesta de código (P1 no-op; CX sí,
  H1). No gastar medición: la parte viva de G2 es regulator_summary/clk_summary (ya en G1).

**Orden propuesto (máxima info por riesgo de congelar):**

1. **G0 (NUEVO, coste cero, ANTES de G1):** recuperar el log del boot #536 (host-stream,
   journalctl/pstore por SSH) y extraer: veredicto del WALK `iova=0x4000` (CB1 del dominio
   propio), `CB0/CB1 STD` SCTLR/TTBR, `UKE-CM3DBG clks core/hub`, presencia de fault
   arm-smmu (sid=5), F1-F4. Este log puede cerrar la causa #1 o recortar el ranking entero
   SIN flashear nada.
2. **G1 (ajustado):** capturas pasivas tal cual (dmesg, clk_summary, regulator_summary,
   interrupts) MÁS: `/proc/cmdline` y `/sys/module/*/parameters/{uke_gmu_shared,uke_smmu_dump}`
   (probar módulos `msm` y `adreno`) — fijar qué configuración corrió de verdad;
   `grep -E "context fault|Unhandled|FENCE"` en dmesg. **QUITAR la lectura devmem de GMU
   tras el fallo**: el error-path ya hizo `clk_bulk_disable_unprepare` (:1895) — leer MMIO
   del GMU con relojes cortados es comprar un freeze gratis (regla r3). Lo que G1 quiere ver
   ahí exige el K44'' en-kernel (k56).
   **N=5: reemplazar re-arms por 5 reboots** (o k56 con las 3 líneas de §4). Registrar por
   trial: warm/cold (F1 presente/ausente), veredicto S0, S4, freeze/SSH-vivo.
3. **G2 (recortado):** comparación clk vs Android resuelta en el log existente (hub 200
   exacto, gmu 220 = Android idle, cxo/ahb extra-on inofensivo, hub_aon ausente = igual que
   mainline). Solo añadir: GDSC cx/gx en regulator_summary tras el fallo (¿CX sigue on?).
4. **G3 re-priorizado (3 experimentos):**
   - **G3.1 — ACD-off explícito vía AOSS, DTBO-ONLY (s271 = s270 + fragment nuevo):** añadir
     `qcom,qmp = <&aoss_qmp>` al nodo gmu (el OPP table ya da `enable_by_level=0`) →
     `acd_probe` enviará `{class: gpu, res: acd, val: 0}` (:2593) y AOSS deja de heredar el
     `acd=1` de Android. Coste: un dd de dtbo (rollback s270 medido 3×). Ataca la causa #2
     directamente; si el fw arranca, causa cerrada; si no, refutada sin kernel nuevo.
   - **G3.2 — k56 "instrumento" (3 líneas, nada conductual):** assert SYSRESET=1 en
     `a6xx_gmu_init` (mata la fuga §4.1), `status` warm/cold en H5, y K44'' en el error-path
     del poll (relectura DTCM/FW_INIT_RESULT/AHB_FENCE_STATUS/SPTPRAC_PWR_CLK_STATUS con
     relojes aún vivos). No intenta arreglar: convierte CADA intento en testigo del MISMO
     boot y hace el re-arm cuantificable. Es el habilitador de cualquier N≥2 fiable.
   - **G3.3 — A/B de la raza por cmdline (sin rebuild):** k55 con/sin `msm.uke_smmu_dump=1`
     (repack de cmdline). Decide si el delay pre-S3 es la variable del freeze (§3) y da el
     N-efectivo para calibrar cuántos boots hacen falta. Si A/B dice "delay manda", el
     siguiente kernel conductual es el msleep explícito pre-S3 (misma k56 que G3.2).
   - (Queda en reserva, NO antes de G0/G3.1: ACD-ON con los valores F3 ya extraídos
     (0xa8285ffd/0x88295ffd/0xa8295ffd/0x882c5ffd) — también dtbo-only — para replicar el
     estado exacto de Android si G3.1 no cierra.)
5. **G4 (con advertencia):** si llega `S4-pollOK`, no celebrar aún: el fw despertará con
   tabla BW hardcodeada a740 (`nr_gpu_bws=1`) y SIN votos ICC del GPU (`interconnects`
   vacío) — vigilar errores QTB/axon/fence en los primeros minutos antes de apilar
   modetest/pantalla encima.

---

## Resumen en 5 líneas

1. La cmdline REAL del k55 (extraída del bootimg) desmiente dos premisas del plan: corrió con
   `uke_gmu_shared=0` (dominio propio: el CB1 es del GMU, no compartido) y con
   `uke_smmu_dump=1` (el discriminador CB1/WALK YA midió — recuperar ese log es G0, coste 0).
2. El veredicto "STALE" de S0 habla del intento ANTERIOR; en un solo boot frío no es
   evidencia contra el CM3 de ese boot: el único testigo vivo es el poll S4.
3. El N=5 por unbind/bind tal cual está REFUTADO como medición: SYSRESET queda en 0 (el CM3
   fetch-ea al re-encender relojes, antes de S1), `TCM_RET_CNTL=1` persiste (intento ≥2 =
   WARM sin fw_load) y el veredicto va desfasado un intento. Reboots limpios, o k56 con
   assert+K44''+log warm/cold.
4. Tres experimentos G3 del plan son no-ops por el código (CX GDSC ya se enciende; PDC no
   corre en cold; ACD ya está off en el driver): el delta real es el AOSS heredado con
   `acd=1` de Android — y se ataca DTBO-ONLY añadiendo `qcom,qmp` al nodo gmu (G3.1).
5. La raza freeze/timeout tiene un correlato mecánico: el volcado k55 inyecta segundos de
   delay pre-S3 (pr_flush×línea) y k55 fue el que no congeló — el A/B de cmdline (sin
   rebuild) decide si el muro es temporal o estructural en esta configuración.
