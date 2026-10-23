# GPU-PORT-INV — investigación del lado PORT PROPIO (6-oct-2026, ledger #535)

> Investigador: subagente port-side. 100 % offline (tablet no tocada). Fuentes: FLASH-LEDGER.md
> (entradas GPU #263→#534), docs/historia/revision/GPU-OFENSIVA-20261003.md, docs/historia/revision/REV-GPU-DISPLAY-20261005.md,
> docs/historia/ESTADO-VIVO.md / docs/historia/PLAN-PANTALLA.md, build/cm3-ladder/, árbol `build/kernel-pokes/k52-tree/`
> (inventariado y diff-ado contra k18-tree) y el dtbo EN LA TABLET
> `build/bootimg/s269-boot-dtbo-touch.img` (extraído y decompilado).

---

## a) Línea temporal de la batalla GPU (nº de entrada del ledger)

### Génesis (21–28 sep)
| # | Hallazgo | Estado |
|---|---|---|
| #263 | Auditoría FASE 3 GPU: camino = msm DRM mainline + Turnip, "cero parches de kernel"; DTB con `&gpu` okay + zap `qcom/uke/` | base |
| #279–#282 | Overlay GPU standalone; probe del GPU por configfs en caliente (gpucc→palawan-gpucc OK, kgsl-smmu OK, adreno bound-en-espera) | historia |
| #283 | WEDGE nocturno: hang duro del probe con icc resuelto; variable = `separate_gpu_kms=1` | cerrado |
| #387–#388 | s185: init completo pero hw_init cuelga; el fw del GMU NO se cargaba (catálogo pedía nombre pelado y estaba en `qcom/`) → fw a raíz de `/lib/firmware` → el cuelgue se mueve tras fw_load | arreglado |
| #389–#390 | El cuelgue está DENTRO de `a6xx_gmu_start`, al SOLTAR EL RESET del CM3 | pared original |
| #391 | OPP del GMU arreglado (phandle colgante del dtbo) | arreglado |
| #395 | El fw del CM3 vive detrás del SMMU del GPU (SID 5) | hecho clave |

### Ofensiva octubre (1–3 oct)
| # | Hallazgo (ciclo) | Pared / estado |
|---|---|---|
| #447 | KILLER unificado pantalla+GPU localizado; K18 en build | — |
| #448 | s263+K20: el release del CM3 ya NO wedgea el bus (máquina viva) | pista |
| #449 | K22 (fw en initramfs) + K23 (fix ioremap); machine-check por ioremap corto | lección r3 |
| #454/#455 | 3 auditorías: `dtcm-magic=0x40050001` NO prueba que el CM3 corra (lectura pre-release, `&0x1ff=0x1≠0x100`); parseo del fw: bloque icache en `0x4000` EXISTE (H3 refutada); nace el caminador `uke_k19_walk_to` | método |
| #456 (K24) | `uke_gmu_shared=0` bajo s260 → el GPU ni probea; `hung_task_panic=0` verificado (consume 2, no 7 reintentos) | vía attach cerrada por ahí |
| #458 (K25) | **CAUSA RAÍZ -34**: `gmu init ret=-ERANGE`; unwind oops (`pc=0x10000000c`) | muro -ERANGE |
| #459 (K26) | s263 → `-EBUSY`; fondo: `uke_gmu_shared` era NO-OP (se creó dominio propio siempre) | — |
| #460 (K27) | fix "compartir de verdad" (3 ficheros) — luego REVERTIDO (#465: premisa `gpu->vm` NULL falsa, `msm_gpu.c:974` ya lo crea) | revertido |
| #463 | `video=DSI-1:d` FUERZA OFF (`drm_modes.c:2007`); quitarlo cuelga el arranque (DPU) | entendido |
| #465–#467 (K30) | `-ERANGE` PERSISTE con dominio propio. CAUSA RAÍZ: ventana VM del GMU hardcodeada `0x0..0x80000000` + iovas fijos bajos (icache `0x4000`, dummy `0x60000000`, debug `0x60400000`) vs quirk TTBR1 (apertura ≥4 GB, `io-pgtable-arm.c:592-600` `iaext→-ERANGE`) | arreglado en K35 |
| #470 | INVALIDACIÓN: el confusor `uke_gmu_shared` nunca se aplicó en K30/K33 (medición inválida) | re-medido |
| #474–#476 (K34) | el cuelgue sin `:d` es el DPU pidiendo el SQE; el fw GPU NUNCA estuvo disponible; K34 lo hornea en el initramfs (P90 OK) | arreglado |
| #477–#478 (K35) | con `msm.uke_gmu_shared=0`: **el GMU MAPEA** sus 3 BOs sin `-ERANGE` (cadena TTBR1/K31 confirmada)… y cuelga DESPUÉS, en el CM3 | muro -ERANGE CAÍDO |
| #479–#480 (K37) | escalera del CM3 a WARN: **`S0-dtcmR → S1-rst1 → S2-gen9 → S3-rst0` y ahí muere**. El cuelgue ORIGINAL localizado | MURO S3-rst0 |
| #482 (K38 control) | con `:d` llega IGUAL a S3-rst0 (`:d` exonerado); **P132: SID5 (CM3) va a SU PROPIO CB (cbndx=1)** — candidato "SID5 sin reprogramar" REFUTADO; P133: dominio del GMU SIN quirk TTBR1 | refutados |
| #484 | C4: mi hipótesis "el driver no configura el CM3" FALSA — `a6xx_gmu_fw_start` escribe `CM3_BOOT_CONFIG=0x02` (:1391) y `CM3_CFG=0x4052` (:1419) | refutada |
| #485 (K39) | **P141: NO hay fallo de traducción** en el primer fetch (fault handler en dominio propio, 3 dominios armados). El mapeo está BIEN. Bloqueo de observabilidad: `[missed 9753 bytes]` SIEMPRE tras S3-rst0 | refutados |
| #486–#490 (K40/K41) | el ABL pisa la cmdline AL FINAL (gana el último token); tope de 4096 B en el host; parche de tope de consola funciona | observabilidad |
| #491–#494 (K42/K43) | `uke_poke→pr_err`: la escalera corría SIEMPRE; muerte en dump→S3-rst0 (4.118–4.212 s) en TODOS los boots ⇒ **el muro es ESTRUCTURAL, no de timing** | confirmado |
| #499 (K44) | 12 lecturas de registros del CM3 pre-release: **P191 todo SANE** (bootcfg=0x2, cfg=0x4052, vectores ITCM reales `10007f80/00000105`, icache/dcache/sysbus=1/1/1, hfi ok, fence=0). El CM3 muere sin rastro legible por el host | refuta "config/vectores malos" |
| #500 (K44b) | `arm_smmu.uke_kgsl_keep=1` (conservar estado BL/TZ del TCU): muere IGUAL ⇒ TCU indiferente; quedan TBU/TZ | refutada |
| #515 | Ofensiva sin flashear: **TBU gpu_qtb@3de8000 ARCHIVADO** (los 9 TBUs del vendor fallan probe en Android y funciona; mainline comparable arranca sin nodos TBU); **warm-boot/TCM-retention REFUTADA** (el camino FRÍO corre y el fw se carga). DELTA NUEVO: **hub_clk real 400 MHz vs 200 vendor** (clk_set_rate ignora rc); ACTLR 0x32b del vendor a TODOS los SIDs vs upstream solo al GPU; poll FW_INIT_RESULT usa DTCM STALE; DT: rscc doble reclamación, mboxes=aop caído, secure CB2/SID2 vs mainline SID1, zap real 8 KB @0x9899a000 | 2 paredes menos |
| #516 | Síntesis 3 subagentes → **plan C1–C6** (idéntico a docs/historia/revision/GPU-OFENSIVA-20261003.md) | plan vivo |
| #525-pre | ARSENAL C1/C2 PRE-CONSTRUIDO y NO EJECUTADO: `s267-boot-dtbo-esd-gpuon.img` (`b52d19de…`, GPU okay) + `boot-ukek49-c1-dump.img` (`455eaa58…`, +`msm.uke_smmu_dump=1`) + `boot-ukek49-c2-shared1.img` (`c541f2ca…`, sin `gmu_shared=0`) | **pendiente de correr** |
| #528 | Ronda revisora Android: ACD del vendor ON (`acd=1`, IFPC 6366 entradas); zap: el package YA lo lleva (F1 falsa alarma); **fixes F1–F5 aplicados a palawan-linux `uke-fixes-20261005`** (NO a k18/k52) | ver §d |
| #532 | Saga bisects: vuelta a la DORADA; REGLA NUEVA: avances por **cherry-picks de UNO en uno sobre k18-tree** con boot tras cada uno; la dorada = k18-tree + Image.gz solo, sin módulos | método vigente |
| #533 | Incremento 1: dtbo **s269** (`8893fe37…`) táctil novatek@0 con fixup tlmm; **GPU sigue OFF** (fragment@1711); hallazgo ABL: fragments con phandles LITERALES se ignoran | tablet |
| #534 | Incremento 2: batería OK; **boot_a = k52b2 (`18c749ea…`, kernel `5276fe0f…` construido desde k52-tree con receta dorada + grupo A batería)**, dtbo_a = s269. **ORDEN DEL DUEÑO para el incremento 3: GPU** — cherry-pick 603b37730 (hub 200) sobre k52-tree + CM3/GMU con receta dorada, GPU-off→GPU-on paso a paso | ESTADO ACTUAL |

## b) El muro actual: CM3/GMU en `S3-rst0`

**Qué es exactamente**: `a6xx_gmu.c:709` escribe `REG_A6XX_GMU_CM3_SYSRESET = 0` (suelta el reset
del CM3, `uke_poke("S3-rst0")`), lo que dispara el **primer fetch del icache** del CM3 por el
SMMU del GPU (SID 5 → CB1 del dominio propio del GMU). Entre `S3-rst0` y el veredicto del poll
(`S4-pollOK/FAIL`, `gmu_poll_timeout` 100 ms–100 s) la máquina muere EN SECO (sin panic, sin oops,
sin hung-task); muerte medida en 4.118–4.212 s de uptime, 100 % reproducible (K37/K39/K43/K44/K44b).

**Última evidencia viva**: K44 (#499-ter) — los 12 registros del CM3 pre-release devuelven EXACTO
lo que el driver escribió (todo sane); K43 (#494) — la escalera corre COMPLETA (F1→F4, H7, P1–P3)
y la muerte cae en dump→S3-rst0 con la misma ventana temporal siempre.

**Refutado por medición (no volver a estos)**: tabla CB1 sin la página (K24–K26, WALK); quirk
TTBR1 en dominio propio (P133, K35); SID5 sin reprogramar (P132); fallo de traducción del fetch
(P141, fault handler); config/vectores del CM3 (K44 A–E); relojes del CM3 sin encender
(`clk_bulk_prepare_enable` OK); `:d` como causa (#482); timing de consola (#494); TCU/keep BL
(K44b); TBU gpu_qtb (#515, archivado con el dmesg vendor propio); warm-boot/TCM retention (#515);
fw del GMU distinto (byte-idéntico al stock); GME no existe.

**Hipótesis VIVAS (plan C1–C6, docs/historia/revision/GPU-OFENSIVA-20261003.md)**:
- **C1** (WALK del CB1 con `msm.uke_smmu_dump=1`, kernel K44+): PA REAL del fetch del icache —
  cierra el único modo de fallo NO excluido: traducción VÁLIDA a un PA MALO. **Arsenal
  pre-construido (#525-pre), NUNCA EJECUTADO.**
- **C2** (A/B sin `msm.uke_gmu_shared=0`): posible MÁQUINA VIVA en el muro (stall vs wedge);
  arsenal pre-construido, nunca ejecutado.
- **C3** (hub 200 MHz): delta medido 400 vs 200 (fix F2/603b37730 listo en palawan-linux).
- **C4** (ACTLR 0x32b del CB5 del GMU como el vendor): 1 línea en arm-smmu-qcom, sin hacer.
- **C5** (migas: poll FW_INIT_RESULT con DTCM STALE → falso-FAIL posible; qmp_send(acd)): sin hacer.
- **C6** (diff formal DT portado vs base-uke vs sm8650): hecho a medias offline (#515/#516).
- Bomba latente C6: DT pide `qcom/uke/gen71100_zap.mbn` — **hoy YA desactivada**: el package
  `uke-gpu-firmware` instala las 4 rutas (PKGBUILD:42-49, verificado).

## c) Inventario GPU de k52-tree (lo que hay HOY)

**k52-tree == k18-tree en FUENTE** (diff recursivo completo: 0 diferencias de código; solo
artefactos de build `.o`/`.mod` del k52b en drivers/power/supply y drivers/soc/qcom). El k52b2
flasheado (#534) es k52-tree + config k52-bateria (grupo A QRTR/RPMSG/Q6V5/pd_mapper =y) con la
receta dorada (build-k49.sh: clang 23.1.1, KBUILD_BUILD_*=uke/palawan, SOLO Image.gz).

`drivers/gpu/drm/msm/adreno/` (38 ficheros, sin sondas nuevas vs k18):
- **a6xx_gmu.c — 141 marcadores UKE**: `uke_poke()` (pr_err desde K43) con la escalera completa
  `G1-bind/G2-initOK/G3-icc/H5-boot/F1-fwloop/F2-itcm/F2-dtcm/F3-loopOK/F4-verOK/H7-fw/
  P1-initres/P2-qtbl/P3-pwrOK/S0-dtcmR/S1-rst1/S2-gen9/K19-dumpOK/S3-rst0/S4-pollOK|FAIL`;
  `UKE-K19` volcado kgsl-smmu + `UKE-K24` caminador `uke_k19_walk_to` (`WALK iova=…`) tras
  `module_param(uke_smmu_dump)` (default 0, K25); `UKE-CM3DBG` (clks core/hub reales +
  dtcm-magic con veredicto OK/STALE); `UKE-K44` A–E y `K44'` (12 lecturas CM3 pre-release /
  post-pollOK); `module_param(uke_gmu_shared)` (default 1; la cmdline dorada lo fuerza a 0).
- **adreno_device.c**: `UKE-K42` pr_warn en G1-bind + pokes G2/G3.
- **arm-smmu.c**: `uke_kgsl_keep` (default 1 en árbol; cmdline dorada =0), 249 líneas UKE
  (SMMU diferido, K18-keep). **arm-smmu-qcom.c**: 51 líneas UKE (K31/K33 TTBR1, K38 attach
  SME→CBnDx). **uke-panic-fb.c** (pinta el sello/fb en panic).
- **Catálogo A732**: `a6xx_catalog.c:1618` `chip_ids 0x43030b00`, family ADRENO_7XX_GEN2,
  fw `gen71100_{sqe.fw,gmu.bin}`, zapfw `gen71100_zap.mbn`, gmem 1.5 MB, `gmu_chipid 0x70b0000`,
  quirks cached-coherent/hw-apriv/preemption. **EXISTS — el fork conoce el chip.**
- **drivers/clk/qcom/gpucc-palawan.c**: `ftbl_gpu_cc_ff_clk_src` (:155-158) = 
  `F(200000000, P_GPLL0_OUT_MAIN, 3, 0, 0)` → **pre_div 3**. GPLL0 corre a 1200 MHz (ABL) ⇒
  hub queda a 400 MHz. **El fix 603b37730 (pre_div 6) NO está aplicado** (gpucc byte-idéntico
  entre k18 y k52 — verificado por diff).
- **arch/arm64/boot/dts/qcom/xiaomi-uke.dts**: `&gpu { status = "okay" }` (:550-552) y
  `&gpu_zap_shader { firmware-name = "qcom/uke/gen71100_zap.mbn" }` (:554-556). OPPs: el
  `gpu_opp_table` de palawan.dtsi sigue con **1000 (:2456) y 1100 (:2462)** además de los 9
  niveles vendor 255–950 ⇒ **F4 NO aplicado**; sin `qcom,opp-acd-level` (F3 pendiente a propósito).
- **build/cm3-ladder/**: harness de 28-sep (apply-and-build.sh, measure-cm3.sh, test-ladder.c,
  uke-cm3-ladder.diff, INFORME-CM3.md) — SUPERADO por la escalera `uke_poke` in-kernel.

## d) Fixes GPU de la ronda Android (F1–F5) — estado POR ÁRBOL

Verificado: `palawan-linux` rama `uke-fixes-20261005` = `cc3a3dad8` (vadc) ← `760160d41` (pd_mapper
lamma) ← `5702c18ac` (DT táctil+BT+wpss+adsp+**F4 OPP**) ← `603b37730` (**F2 hub**) sobre
`d1c7ef2e0`. k18-tree/k52-tree NO descienden de esa rama (diff de 23 ficheros, BUILD-RECIPE-DORADA §0).

| Fix | Qué | palawan-linux (uke-fixes-20261005) | k18-tree / k52-tree |
|---|---|---|---|
| F1 | ruta zap `qcom/uke/` | N/A (es de PACKAGE, no de kernel) | **HECHO por otro lado**: `build/pkg/uke-gpu-firmware/PKGBUILD:44-49` instala zap en `qcom/uke/`, `qcom/palawan/`, `qcom/` y raíz; package instalado en rootfs v8 (#530). Bomba latente desactivada |
| F2 | hub 200 MHz (gpucc pre_div 3→6) | **APLICADO** — commit `603b37730` (1 fichero, gpucc-palawan.c) | **NO** (pre_div sigue en 3) → **CHERRY-PICK PENDIENTE #1** |
| F4 | OPPs 1000/1100 fuera (SKU bina a 950) | **APLICADO** — dentro de `5702c18ac` (xiaomi-uke.dts, bloque `&gpu_opp_table /delete-node/`) | **NO** (palawan.dtsi las conserva) → cherry-pick parcial PENDIENTE (el bloque GPU es separable del resto del commit) |
| F3 | ACD on (tabla `qcom,opp-acd-level`) | NO a propósito (post-soak) | NO (valores documentados: 950/900/835→0xa8285ffd, 736/684/633→0x88295ffd, 500→0xa8295ffd, 353→0x882c5ffd) |
| F5 | panel o82 | nada que hacer ahora | idem |

Ojo al cherry-pickear `5702c18ac` entero: arrastra ADSP/WiFi/BT/táctil-DT y reserved-memory.
Para un incremento PURE GPU basta el hunk `&gpu_opp_table` (+ opcionalmente nada más); el resto
ya entró por vías propias (táctil vía s269, batería vía k52b).

**Lo que NO está en ningún árbol**: C4 (ACTLR CB5), C5 (migas poll-stale/acd), sonda C1 ya está
(`uke_smmu_dump` + WALK) — solo hace falta cmdline.

## e) Ruta de encendido propuesta (incremento 3, orden del dueño #534)

Base: tablet en k52b2 (boot_a `18c749ea…`) + s269 (dtbo_a `8893fe37…`) + v8. Receta canónica:
BUILD-RECIPE-DORADA.md (k52-tree + build-k49.sh + config k52-bateria + initramfs uke-k34-fw +
cmdline dorada 517 B; Image.gz solo, NUNCA modules_install; cherry-picks de UNO en uno con boot
tras cada uno).

1. **Cherry-pick F2 (603b37730) sobre k52-tree** → build "k53" con la receta → dd boot_a por SSH
   (patrón #534: `dd` a `/dev/disk/by-partlabel/boot_a`, sha leído de vuelta) → boot de control
   (GPU sigue off en DT, nada que wedgeee). Gate de build: `F(200000000, P_GPLL0_OUT_MAIN, 6, 0, 0)`
   en el binario.
2. **Cherry-pick del hunk F4** (`/delete-node/ opp-1000000000/opp-1100000000` de 5702c18ac) sobre
   k52-tree → mismo build k53 (el DTS va embebido en… OJO: en la dorada el DT viaja en el DTBO, no
   en el boot.img — el hunk F4 en el árbol solo importa si se regenera dtbo; para el dtbo va mejor
   como fragmento nuevo del payload). Recomendación: aplicar F4 en el **dtbo s270** (abajo), no en
   el árbol del kernel.
3. **dtbo s270 = s269 − fragment@1711** (patrón EXACTO de s267 = s266 − @1711, gates G2 de
   mkdtbo-s267.py reutilizables sobre s269.dts). Sin tocar @1420: ver análisis abajo. Gates:
   fundido con GPU `okay`, novatek@0 intacto, panel o82 intacto, `fdtoverlay` verde, dt_table
   1 entrada. `dd` a dtbo_a por SSH + reboot (rollback inmediato: dd de s269 de vuelta, medido 3×
   el 6-oct).
   **Lo que hace CADA fragmento en s269** (payload extraído y decompilado; 4 fragments apuntan a
   `/soc/qcom,kgsl-3d0@3d00000`, se aplican en ORDEN del FDT):
   - **@903** (primero): solo `reg-names` mainline (7 nombres).
   - **@1420**: `status = "disabled"` (GPU off — HERENCIA s262).
   - **@1450**: mainline-ización completa + `status = "okay"`: compatible
     `qcom,adreno-43030b00`/`qcom,adreno`, reg 7 regiones (kgsl 0x3d00000, rscc 0x3d50000,
     cx_dbgc, cx_mem 0x3d9e000, qdss…), `iommus <kgsl-smmu 0 0>` (SID 5), interconnects VACÍO
     (truco v3b anti-icc), clocks/clock-names vaciados, OPP propia `gpu_opp_uke` de 9 niveles
     255–950 (SIN 1000/1100: **el dtbo ya implementa F4 de facto**), `qcom,gmu` → GMU mainline
     (reg gmu 0x3d68000+0x37000, gmu_pdc, rscc; 7 clks con hub y demet; cx/gx; opp 220/550).
   - **@1711** (ÚLTIMO): `status = "disabled"` de nuevo.
   **Aparente contradicción y quién gana**: @1420 (disabled) vs @1450 (okay) NO es la pelea
   decisiva — @1450 va DESPUÉS de @1420 en el FDT y lo pisa (GPU quedaría ON). La última palabra
   la tiene **@1711**, que aparece al FINAL del FDT y re-desactiva. En un solo DTB overlay los
   fragments se aplican secuencialmente en orden de aparición ⇒ **gana el ÚLTIMO: @1711 ⇒ GPU OFF
   en s269** (gate G2 de mkdtbo-s269.py lo asiente). Por eso s270 = quitar SOLO @1711 (como s267):
   @1420 queda cubierto por @1450 y el GPU sube con toda la re-config mainline.
4. **Arranque con GPU ON + gates en vivo**:
   - Si el CM3 vuelve a morir en S3-rst0 (lo esperado): consola ACM + lector2 armados ANTES del
     reboot; leer la escalera: `UKE-CM3DBG: clks core=220000195 hub=200000000` ← **NUEVO gate C3**
     (si sigue 400, el cherry no llegó o GPLL0 no es 1200 en este boot — gate G3-1 de REV-GPU-DISPLAY).
   - Si la máquina SOBREVIVE: por SSH (`192.168.42.129`): `dmesg | grep -E 'UKE-POKE|UKE-CM3DBG|
     adreno|gmu'` → buscar `S4-pollOK` (CM3 vivo), `Loaded GMU firmware v4.5.x`, `card0`/
     `renderD128`, y `/sys/kernel/debug/clk/clk_summary | grep gpu_cc` (hub 200000000,
     cx_gmu 220000000). Después `ls /dev/dri` + ausencia de `Unable to load qcom/uke/
     gen71100_zap.mbn` (zap: el package ya lo lleva).
   - Si muere con hub=200 (muro intacto): **C1 en caliente** — repack SOLO cmdline del k53 con
     `msm.uke_smmu_dump=1` (el WALK ya está en el árbol; sin rebuild) + s270 → leer el PA real del
     fetch (`WALK iova=0x4000 … phys=`). Después **C2**: repack sin `msm.uke_gmu_shared=0`.
   - Si C1/C2 no cierran: C4 (ACTLR 0x32b del CB5 en arm-smmu-qcom, 1 línea, build nuevo) y C5
     (migas poll-stale + qmp acd), como rankeó #516.
5. **Rollback en cualquier punto**: `dd if=s269-boot-dtbo-touch.img of=/dev/disk/by-partlabel/
   dtbo_a` por SSH (GPU off ⇒ arranque garantizado con k52b2). Si boot_a wedges en bucle: el ABL
   drena reintentos → fastboot → watcher flashea el par anterior (patrón rollback-watcher #534);
   `hung_task_panic=0` en la cmdline dorada ya limita cada wedge a ~2 reintentos.
6. **Después del S4-pollOK**: zap (ya servido) → modetest/vulkaninfo → ACD F3 solo tras soak
   (valores del DT vendor ya extraídos) → pantalla (VSP/VSN + táctil TDDI que ya está conectado).

---

## Resumen en 5 líneas (el muro)

1. El muro es el **CM3 del GMU**: al soltar su reset (`S3-rst0`, `a6xx_gmu.c:709`) el primer fetch
   del icache mata el SoC en seco, reproducible 100 % (ventana 4.118–4.212 s, K37→K44b).
2. Todo lo de antes está REFUTADO con medición: -ERANGE/TTBR1 (K35 lo pasó), SID5/CB (P132), fallo
   de traducción (P141), config CM3 (K44 todo-sane), TCU (K44b), TBU/warm-boot (#515).
3. Quedan VIVAS C1 (WALK: PA válido→malo; arsenal `s267`+`c1-dump` de #525-pre SIN EJECUTAR),
   C2 (A/B shared=1), C3 (hub 400→200), C4 (ACTLR CB5), C5 (poll-stale/acd).
4. En k52-tree (≡ k18-tree) ya hay TODO el instrumental (escalera uke_poke, WALK, K44, A732 en
   catálogo, DT GPU okay+zap); FALTAN: cherry-pick `603b37730` (hub 200) y opcionalmente el hunk
   F4 de `5702c18ac` (el dtbo ya lleva OPP 9-niveles sin 1000/1100).
5. Encendido: k53=603b37730 → **s270 = s269 − fragment@1711** (el que re-desactiva; @1420 es
   inocuo porque @1450 lo pisa) por dd → gates por SSH/consola (hub=200000000, S4-pollOK, fw GMU
   v4.5.x, card0); si muere → C1 (`msm.uke_smmu_dump=1`, solo cmdline) y C2; rollback = dd de s269.
