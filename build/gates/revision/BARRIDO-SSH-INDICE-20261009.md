# BARRIDO-SSH — Índice de la oleada (2026-10-09)

> Documentalista/historiador. Oleada BARRIDO-SSH = ciclo GPU-on por SSH
> (ledger hermano #535–#551, 6–9 oct 2026). Testbed estable: k52b2+s269+v8.2.
> Tablet al cierre: en fastboot (slot a, retry 7:7, batería 4028 mV).
> Regla: NO repetir lo REFUTADO sin evidencia nueva. No tocar la tablet. No flashear.

## Fuentes

- Hermano: `~/proyectos/ubuntu-permanente/docs/{FLASH-LEDGER.md (#535–#551),REFUTADO.md,LECCIONES.md}`
- Revisión: `build/gates/revision/{INV-KGSL-RE,INV-GMU-BIN,VIAS-GPU,INV-GMU-ESTADO,INV-PERSIST,DISENO-K61}-20261008.md`
- Estado: `docs/historia/ESTADO-VIVO.md` (#550), `NOTAS-OMARCHY.md` (cierre 6–9 oct)

---
## 1. La oleada #535–#542: GPU-on por SSH, 7 experimentos (6–8 oct)

- **#535** (inventarios + C1): volcado K24 del SMMU private del GMU. Veredicto inicial:
  24/24 SMR inválidos (S2CR=0x20000=FAULT), CBs con basura de bus. Hipótesis: S1 del GMU
  nunca configurado, o SMMU sin alimentar. Siguiente: instrumentar camino iommu (k55).
- **#536** (k55, primer boot VIVO con GPU-on): el volcado completo corrige a #535 —
  SME(0)→CB0 y SME(1)→CB1 con S2CR=1, EXACTO al vendor; los CB leían basura por mirar la
  ventana +0x20000 equivocada (mainline usa +0x8000). El CM3 no ejecuta (dtcm STALE),
  poll expira con gracia, userspace vive. Foco → por qué el fw no llega al CM3.
- **#537** (restauración testbed + lecciones de operación): wedge del puerto USB 3-3
  (bulk stalla, fix authorized 0→1); timeout userdata 150 s; fix en vivo del rootfs
  tiene que llegar al staging; `fastboot continue` como herramienta; lector ACM en bucle.
- **#538** (críticas GPU + k56 + mina initramfs): CX GDSC/PDC/ACD-off refutados por código;
  s271 (qmp al GMU); hallazgo: /dev/sd* en initramfs es RACE (UFS huérfano) → fix ukeinit.
- **#539** (rescate telnet + doble causa raíz + cosecha k56): `fastboot continue` como
  herramienta; bind manual ufshcd-qcom revive sda*; sda32 NO es nuestro rootfs (GPT del
  experimento Android); sda30=rescue con forklogs. K56: COLD confirmado, hub=200,
  SME(1)→CB1, pero volcado a +0x20000 da EXTERNAL ABORT 0x96000010 (bus blocked, no basura).
- **#539b** (k57 + ukeinit fijo listos): volcado desactivado → GPU-on seco; cpio k34-fw
  con espera UFS 30 s + bind manual.
- **#540** (INV-CM3 offline): dtcm-magic STALE es FALSO (0x40050001 pre-cargado del binario);
  causa raíz propuesta: SID5 en dominio default vacío (hack K20 muerto por s269 GPU→SID0).
  K58 (uke_gmu_shared=0 + poll COLD) empaquetado.
- **#541** (críticas convergentes): desmontan #540 — CB1 YA era dominio propio (k58 no-op);
  29/29 boots murieron en ventana del poll sin S4 jamás. Causa física #1: clock-ids vendor
  en kgsl-smmu (HLOS1_VOTE jamás encendida → fetch CM3 cuelga). #2: uCode+PDC en bloque AOP.
  #3: kgsl-smmu sin power-domain CX. #4: qmp de s271 cayó en nodo GPU, no GMU (qmp_send nunca
  corrió). #5: sin SID secure (bomba post-CM3). s272 corrige clocks.
- **#542** (cierre ciclo): k59+s272 congela igual (TCU-sola refutada); k60 (rpmh/PDC
  neutralizado) congela igual (RSC/PDC refutado). Conclusión: muro S3-rst0 FÍSICO del
  dominio GMU; vía productiva = RE del estado del dominio vivo en Android, no más parches
  a ciegas. Restaurar testbed, fase nueva de RE.

---
## 2. La fase nueva #543–#552: RE del dominio + cierre del ciclo CM3 (8–9 oct)

- **#543** (INV-GMU-ESTADO + DISENO-K61): 10 diferencias DT vendor-vs-port rankeadas;
  accionables F1 (kgsl-smmu sin voto CX), F2 (qcom,qmp en nodo equivocado), F3-aplazada
  (GPU sin voto ICC, desactivado adrede por wedge #286). k61 = kernel por STAGES
  (stage 0 solo sondas, 1 release 50 ms, 2 release 200 ms + autopsia, 3 flujo normal).
  s273 = F1+F2.
- **#543b** (k61 stage=2 + s273): CONGELA también. Freeze en el write S3 o el fetch,
  NO en el poll. Evidencia esperada en ramoops/rescue.
- **#544** (canales rotos + v8.2): ramoops SÍ registró pero nadie montaba pstorefs;
  rescue ENOENT (nodos UFS tardíos, carrera #538); forklog-15s jamás pudo volcar boot
  de 4,1 s; power-cycle destruye ramoops (XBL pisa 0xa7000000). v8.2: fstab pstore +
  nodos estáticos sda30/sda32. Rediseño: hold 30 s + workqueue + watchdog HW (reset
  caliente preserva ramoops) + volcador cada 5 s + lector ACM pre-armado.
- **#545** (v8.2 en vivo + pstore muerto confirmado): flash-only (sda30+UKE61RSC) única
  vía real de persistencia.
- **#546** (k62 congeló; canario a disco equivocado): minor 259:14 ≠ 259:16 real —
  minors inestables entre boots (#421). k63: validar por TAMAÑO o by-partlabel.
- **#547** (INV-GMU-BIN): ITCM = STUB 476 B. Reset→breadcrumb DTCM+0xff7 (stage 0x01);
  2 polls cache-ops 0x1f404/05/09/0a (stages 0x14/15/16); scatter-loader → bl 0x4008
  (primer fetch fuera ITCM). Discriminador: 0xffffffff=nunca ejecutó; 0x…114/1415=
  polls; 0x01141516=murió en fetch SMMU 0x4000. Bonus bug: ucode_check_version rechaza
  gen71100_sqe.fw. PLAN-PANTALLA #547 listo.
- **#548–#548e** (k63, 5 intentos): freeze seco idéntico ×5; ACM 0 bytes (el gadget muere
  con el SoC); breadcrumb en DTCM ilegible sin boot completo; lectura por USB CERRADA.
  Vías: (a) UART física (no disponible), (b) DTCM desde kernel GPU-off (no fiable),
  (c) rescate partlabel por workqueue (k63 no lo tiene; k64 sí). GPU-on pausada.
- **#549** (VIAS-GPU): GPU-on se arma a 4,03 s, UFS publica a 4,15 s → rescate pierde
  por 150 ms DE DISEÑO. Ranking: V9 (canales, 2-4 h, riesgo ~0) > V5 (watchdog HW,
  reset caliente) > V7 (parchear gmu.bin: P1 sin body, P2 polls NOP). V1 (RE .ko),
  V3/V6/V4 bloqueadas.
- **#549b–#549f** (P1/P2/P3, parche directo al binario):
  P1 (sin body) CONGELA → no es el body. P2 (polls NOPeados) CONGELA → no son los polls.
  P3 (scatter NOPeado, CM3 en WFI sin tocar SMMU) CONGELA → **el release S3-rst0 MATA
  EL SoC POR SÍ SOLO**. Cierre del ciclo GPU-on por software-APSS.
- **#550** (k64 empaquetado): replica register_config vendor (0x1f8f0/f1, 0x1f984,
  base+0=0x3c45, 0x1f9cd-d0=0xf, RSC wake, FENCE_R0), stage=3, gmu original.
- **#550b** (k64 resultado): CONGELA TAMBIÉN. Conclusión: el estado viable lo configura
  el AOP firmware (o XBL), no el driver host. Vía APSS agotada con evidencia
  (8 kernels, 10 teorías refutadas, RE vendor + binario completas).
- **#551** (cierre documental): 30 informes en revision/ (3–8 oct) + recetas + artefactos,
  todo commiteado en ambos repos.
- **#552** (4 subagentes, correcciones al plan — ¡informes PERDIDOS, viven solo en ledger!):
  1. Claim AOP = hipótesis por eliminación, NO hecho: sin medición positiva del estado
     AOP/XBL en S3. Piezas host sin cerrar (voto CX kgsl-smmu, qmp en nodo equivocado,
     ICC sin .bcms — k61 las llevaba y murió antes de medir). Discriminador: k61 stage=0
     + ENV vs Android vivo. 2. NO hay binario AOP en disco (solo zap 12 KB); aop_a/b
     (512 KiB) SIN dump — paso 1 = dump por lectura. 3. Fuentes vendor cliffs SÍ públicas:
     OnePlus SM7675 (adreno_a6xx_gmu.c + cliffs dtsi + pwrlevels) y Xiaomi uke-v-oss
     (gpucc-cliffs.c). Plan: (1º) golden-state en Android vivo (clk/genpd/regulator +
     ftrace 3D); (2º, paralelo) clonar repos y comparar pwrlevels — **sospechoso nº1:
     LOW_SVS 220 MHz vs SVS 550 MHz**. DESCARTADOS: emulación AOP (300-1000 h),
     Trace32 (10-25 k€). 4. Historial hermano: ~25 temas, todo APSS refutado; abiertos
     de coste bajo: s273 + k61 por stages. Cabos: xbl/tz/aop nunca dumpeados,
     gmu_chipid 0x70b0000 sin validar. MÍNIMO PARA HOY (sin flashear): golden-state
     Android + clones vendor.

---
## 3. INV-KGSL-RE: secuencia vendor completa (msm_kgsl.ko, md5 e2b2828f…)

- Cadena gen7_gmu_boot: CX-GDSC → clks bulk → AHB-timeout+CX-timer → RSCC wake
  (0x3b07←2, poll ACK, ←0) → load_fw (bulk a ITCM 0x1b400/DTCM 0x1c400, dsb) →
  register_config (17 writes) → irq_en → SYSRESET=0 + poll FW_INIT_RESULT&0x1ff==0x100.
- Vendor-only reales (tras rectificación §8: RSCC 0x3b11 = FENCE_RANGE_0, no vendor-only):
  0x1f8f0/f1=1 (primeras), 0x1f984=1, 0x1f985=runtime, 0x1f9cd–d0=(base|0xf),
  base GMU+0←0x3c45.
- Vendor NO aserta SYSRESET=1, NO lee NADA entre cfg y rst0, programa HFI/fences
  DESPUÉS del reset. Mainline: double-assert rst1 + ~20 lecturas + fences antes.
- §8 (respuesta final): las lecturas NO son causa primaria (K63 baliza 0x01141516 =
  CM3 arranca, pasa polls, muere en fetch SMMU 0x4000). Réplica prioritaria: 0x1f8f0/f1.
  → k64 replicó TODO el register_config y congeló igual (#550b): la secuencia host
  tampoco es la causa. Causa restante: estado AOP/XBL o mapeo SMMU del icache.

---
## 4. INV-GMU-BIN: anatomía del gen71100_gmu.bin (80680 B, md5 a02e73fe…)

- Contenedor: 11 cabeceras TOC (size=0) + 4 payloads (DEADBEEF). Bloque 11 = stub ITCM
  476 B; bloque 12 = body icache 79900 B (@0x4000); bloques 13/14 = params DTCM.
- 0x40050001 en DTCM+0xff8 = dato PRE-CARGADO (versión fw), no evidencia de ejecución.
- Stub: reset@0x104 → breadcrumb +0xff7 (stage 0x01) → MSP/VTOR → caches+2 polls
  (0x1f405→poll 0x1f40a; 0x1f404→poll 0x1f409, stages 0x14/15/16) → scatter-loader
  (memcpy/memzero desde body 0x11be8..) → bl 0x4008 (PRIMER fetch fuera ITCM).
- Tabla discriminadora del breadcrumb (+0xff7): ffffffff=nunca ejecutó;
  …01=reset sin MMIO; …0114=poll-1 (bloque 0x7d02c sin reloj); …011415=poll-2;
  0x01141516=fetch SMMU 0x4000; …04=HardFault. NMI/HardFault → stages 3/4 → WFI.
- Parches P1/P2/P3 verificados en bytes: bl 0x4008 @fileoff 0xd4; branches polls
  @0x174/0x196. Resultado P1/P2/P3 (#549c/e/f): CONGELA en los tres →
  ni body, ni polls, ni scatter: el release mata el SoC solo.
- Bug latente: ucode_check_version rechaza gen71100_sqe.fw (-EPERM, bloqueará hw_init
  cuando el CM3 viva; a6xx_gpu.c:1006).

---
## 5. VIAS-GPU: ranking ejecutado y estado (V9→V6)

Orden recomendado V9→V5→V7→V1→V8→V2→V4→V3→V6. Ejecutado en la oleada:
- **V9 HECHA** (k62b cpio k34: pstore temprano + volcador 5 s + watchdog 12 s + nodos
  estáticos; v8.2 con fstab pstore). Arming GPU-on 4,03 s vs sda 4,15 s (margen 150 ms).
- **V5 HECHA** (watchdog HW en k62b): el freeze siguió seco — ni el WDT resucita:
  compatible con freeze de dominio APSS-global.
- **V7 HECHA** (P1/P2/P3): las 3 fronteras cerradas → release mata el SoC solo.
- **V1 HECHA** (INV-KGSL-RE): secuencia vendor completa + k64. Réplica tampoco basta.
- Pendientes/baratas: V8 (minería fork s154/s155/s157 — checklist pre-S3),
  V2-parte-barata (confronta rails/clks Android-vs-ENV con captura existente, 0 tablet).
- Bloqueadas: V3 (EROFS sin mkfs.erofs verificado / riesgo), V6 (sin firehose palawan),
  V4 (sin UART identificada en la uke; stdout-path=GENI @a94000, hsuart@888000).

---
## 6. INV-GMU-ESTADO: mapa del dominio vendor (estado estable, GPU idle 255 MHz)

- Física vendor: GX/CX GDSC OFF en idle (colapso vía IFPC del fw); cx_gmu 220 MHz ON,
  hub_cx_int/hub_aon 200 MHz ON, ddrss_gpu_axi ON; hlos1/memnóc gated; ahb gated.
- Estado de partida del CM3 lo fabrican XBL/AOP + fw, NO el CPU en cold boot
  (k60 neutro = réplica exacta en RSC/PDC).
- Clock-ids vendor=nuestro+2, curado tras s272; GCC idéntico. GDSCR: CX 0x3D9908C,
  GX 0x3D99034 (corrección a DISENO-K61: 0x3D9100C es GFX3D_AON_BCR, no GDSCR).
- Diffs accionables: F1 voto CX kgsl-smmu (s273), F2 qmp→nodo GMU (s273),
  F3 ICC GPU (aplazada s274, wedge #286), ACD **PROHIBIDO** en k61 (tabla §5.3
  documentada para fase con AOP vivo), SID2 post-CM3, IFPC/RPMH_CTRL no tocar pre-S3.
- k61+s273 congeló igual (#543b) → CX-PD+qmp tampoco eran la pieza.
- Secuencia MMIO del CM3 idéntica en ambos mundos (mismo fw); diferencias de escritura
  concentradas en energía/dominio (IFPC, ACD, rails vía AOP, CX votado por SMMU).

---
## 7. INV-PERSIST: por qué el k61 no dejó rastro + rediseño (aplicado en k62b/v8.2)

- Ramoops @0xa7000000 SÍ registró (postcore 0,039 s, consola sincrónica) pero murió con
  la DRAM: la recuperación es power-cycle frío (XBL pisa la zona), y nadie montaba
  pstorefs (lectura imposible). uke-prevlog con firma equivocada. uke_rescue perdió la
  carrera UFS (~150 ms). forklog-15s jamás pudo volcar un boot de 4,1 s.
- Rediseño aplicado: hold del probe (msm.uke_probe_hold_ms), rescue con reintentos por
  partlabel (k63; k64 con workqueue), watchdog HW → reset caliente, volcador kmsg→sda30
  cada 5 s, lector ACM pre-armado, v8.2 (fstab pstore + nodos estáticos).
- Resultado: ni con todo eso hubo autopsia (freeze mata gadget+canales) — pero el
  diseño de canales queda como infraestructura para cualquier ciclo futuro.

## 8. DISENO-K61: sondas ENV + S3 escalonado (docs/historia/revision/k61-gmu-staged.diff, 459 líneas)

- ENV pre-S3 (tras P3-pwrOK): 7 clocks GMU (rate/on/count), genpd cx/gx, CCF de la SMMU,
  GDSCR (CORREGIDOS: GX word 0x240D=0x3D99034, CX word 0x2423=0x3D9908C — el 0x24403 del
  diseño original lee GFX3D_AON_BCR), gate hlos1 en registro (gpucc+0x7000, word 0x25C00),
  SPTPRAC, ENV-RSCC (estado XBL/AOP), ENV-GMU-CFG, ENV-CX_MISC.
- Stages: 0 = fail-closed (ENV + abort -EAGAIN, cero riesgo); 1 = release 50 ms + 1
  lectura + re-assert; 2 = 200 ms + autopsia 6 bracketed; 3 = flujo normal + poll.
- Whitelist: SMMU/QTB/PDC/rscc-writes PROHIBIDOS (abort k56 0x96000010); bracketed reads
  (nombre flushed antes del readl) convierten freeze en punto exacto del mapa.
- k61 stage=2 + s273 congeló (#543b) sin autopsia legible → la evidencia ENV nunca se leyó.
- Reutilizable HOY sin flashear: stage=0 como discriminador solo-lectura (propuesta #552:
  ENV completo vs Android vivo) — exige un flash, no dumps nuevos.

---
## 9. Tabla REFUTADO (ciclo CM3/GMU #535–#550b) — no repetir sin evidencia nueva

| # | Hipótesis muerta | Quién la mata |
|---|---|---|
| F-CB1 | Sin S1 del GMU: SMR en FAULT, sin mapeo | k55 (#536): SME→CB0/CB1 con S2CR=1, exacto al vendor; ventana mal mirada |
| F-TCU | Gate HLOS1 apagada por clock-ids vendor | k59+s272 (#542): freeze igual con clocks curados |
| F-PDC | uCode/PDC en bloque AOP por CPU | k60 (#542): freeze igual con rpmh neutralizado |
| F-ACD | ACD heredado de Android | Críticas #538 (qmp nunca corrió) + paridad cold-boot; réplica prohibida (riesgo) |
| F-STALE | dtcm STALE = fw no llega | #540: 0x40050001 pre-cargado del binario, falso discriminador |
| F-SHARED | SID5 en dominio vacío; fix uke_gmu_shared | #541: CB1 ya era dominio propio (k58 no-op); 29/29 muertes en poll sin S4 |
| F-BODY | El body del fw (fetch @0x4000) es el asesino | P1 (#549c): congela sin body |
| F-POLLS | Polls cache-ops 0x1f404/05/09/0a cuelgan | P2 (#549e): congela con polls NOPeados |
| F-SCATTER | Scatter-fetch SMMU del body | P3 (#549f): congela con CM3 en WFI sin tocar SMMU |
| F-REGCFG | 8 registros vendor-only + RSC wake + FENCE | k64 (#550b): congela con register_config replicado |
| F-CXPD | Voto CX de la kgsl-smmu (F1) | k61+s273 (#543b): congela igual |
| F-QMP | qcom,qmp en nodo equivocado (F2) | k61+s273 (#543b): congela igual (mismo experimento) |
| F-RST1 | Ventana de lecturas rst1→rst0 mata | INV-KGSL-RE §8: K63 baliza 0x01141516 = CM3 pasa polls; lecturas completaron |
| F-FWPROC | Firmware incompatible/procedencia | md5 idénticos ROM stock (#498, #540); 6 copias iguales (R-57 hermano) |
| F-CANALES | "Sin autopsia no se puede" (canales) | V9/V5 aplicadas (k62b): el freeze siguió seco; canales quedan como infra |

Herencia del hermano (REFUTADO.md R-01–R-57 + LECCIONES.md): nada de lo software-APSS
re-auditable se repite; cabos del hermano aún abiertos: xbl/tz/aop nunca dumpeados,
gmu_chipid 0x70b0000 sin validar en silicio.

## 10. Tabla ABIERTO (coste bajo, sin dumps nuevos, sin flashear)

| # | Cuestión | Cómo se cierra (solo disco/PC) | Estado en disco |
|---|---|---|---|
| A-GOLDEN | Golden-state Android vs ENV-k61: clk/genpd/regulator + ftrace 3D | Confronta captura existente (android-full/extracted-full) vs mapa INV-GMU-ESTADO | Captura presente; informe pendiente |
| A-PWR | pwrlevels vendor vs k64: LOW_SVS 220 MHz vs SVS 550 MHz (sospechoso nº1, #552) | Clonar OnePlus SM7675 + Xiaomi uke-v-oss, comparar freq-table/opp | **Pendiente clon (otro subagente)** |
| A-AOPDUMP | Dump aop_a/b (512 KiB c/u) por lectura | Paso 1 antes de cualquier RE del AOP | Dir `evidencia/aop-dump-20261009/` VACÍA (creada 9-oct 02:50) |
| A-V8FORK | Minería fork s154/s155/s157: checklist pre-S3 | 1-2 h PC, 0 tablet (V8) | No hecho en la oleada |
| A-V2B | Confronta rails/clks Android-vs-ENV (parte barata V2) | 2-4 h PC con captura existente | No hecho |
| A-SQE | Bug ucode_check_version rechaza gen71100_sqe.fw (-EPERM) | Parche 1 línea cuando el CM3 viva | Anotado (INV-GMU-BIN §5, deuda ESTADO-VIVO) |
| A-PANTALLA | PLAN-PANTALLA #547 ejecutable por SSH | Sin reflashear, testbed estable | Pendiente de ventana con dueño |
| A-K61S0 | k61 stage=0 (fail-closed) + ENV vs Android vivo | 1 flash cuando haya fastboot (fuera de esta oleada) | Diseñado, no ejecutado |

## 11. Ranking de blancos de RE con lo disponible HOY en disco

Verificado en disco 9-oct (md5 iguales a los citados en los informes):

1. **msm_kgsl.ko** (HECHO, INV-KGSL-RE): `build/evidencia/kgsl-vendor/msm_kgsl.ko`
   (md5 `e2b2828fcc9e7c4a7fa4daf69c98988b` ✓). Resta por exprimir: kgsl_iommu_start/
   setup_context/fault_block (estado SMMU-SID5/CB1 del vendor) y orígenes runtime de
   0x1f9cd–d0/0x1f984-5 (V1 pendiente, 6-16 h PC, 0 tablet). Prioridad ALTA.
2. **gen71100_gmu.bin** (HECHO, INV-GMU-BIN): `build/pkg/uke-gpu-firmware/gen71100_gmu.bin`
   (md5 `a02e73fe916137b2c974951c314fac2d` ✓) + gmu-P1/P2.bin en evidencia/.
   Resta: lectura a fondo del BODY (init post-0x4008: ¿re-valida caches? ¿toca
   0x1f8ec/0x1f990/RSCC/SMMU-CB0?). Prioridad MEDIA (P1-P3 ya cerraron stub).
3. **DT stock vs s269/s273**: `build/evidencia/stock-dt/` (stock0-3.dtb + dts ✓) vs
   `build/bootimg/mkdtbo-s269.py`, `mkdtbo-s273.py` + `s269/s273-repack-report.txt` ✓.
   Diff dirigido: nodo GMU/GPU/SMMU/GPUCC + pwrlevels/opp + bus-tables. 0 tablet.
   Prioridad ALTA (barato, alimenta A-PWR sin esperar clones).
4. **gpucc/pwrlevels vendor** (OnePlus SM7675 + Xiaomi uke-v-oss): **NO EN DISCO**
   (solo `~/proyectos/ubuntu-uke/vendor-src/cliffs/gpucc-cliffs.c` de sep; sin
   adreno_a6xx_gmu.c ni dtsi de pwrlevels). Bloqueado hasta el clon del otro subagente.
   Al llegar: diff freq-table/opp/acd-level/bus-freq vs k64 + mapa clock-ids. Prioridad
   ALTA en cuanto exista.
5. **Captura Android golden-state** (ya en disco): `build/evidencia/android-full/
   extracted-full/` (00-meta/01-gpu/14-dt/15-common ✓). Confronta ENV sin tablet.
   Prioridad ALTA.

## 12. Cierre de la oleada

- Ciclo CM3/GMU cerrado en #550b: 8 kernels (k53–k64), 10+ teorías refutadas con
  parche directo al binario o réplica exacta, RE vendor + binario completas.
- Vía APSS agotada con evidencia. Siguiente: golden-state + clones vendor (A-GOLDEN,
  A-PWR) y, con fastboot del dueño, testbed k52b2+s269+v8.2 + PLAN-PANTALLA.
- Tablet: en fastboot (slot a, retry 7:7, 4028 mV). NO tocada por este informe.
