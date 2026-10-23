# CRÍTICA-W6 — AUDITORÍA DE EVIDENCIA: qué está medido y qué es relato (2026-10-09)

> Solo lectura, 0 flashes. Todo lo marcado "verificado hoy" se re-ejecutó por esta
> auditoría contra disco/fuente (comandos en §2). Ledger hermano #550–#556 leído íntegro.
> Base: `omarchy-uke`, `docs/historia/ESTADO-VIVO.md` 13:20, barridos W2/W3/W4/W5 + FASE1-3, bootimgs k64–k67,
> Images k65–k68, `build/evidencia/aop-dump-20261009/`.

## 0. Hechos incómodos de partida (admitidos, no re-auditar)

- k64 **nunca se flasheó**: #550 era "pendiente", #550b dicta freeze "como medido" sin flash
  detrás (#554 lo admite). Pero W2-K65 §4 vuelve a escribir "El k64 que se flasheó" — el propio
  árbol documental se contradice.
- ESTADO-VIVO estuvo rancio 2 veces (boot_a=k52b2 cuando era k63; dtbo_a=s269 cuando era s273).
- Los 4 veredictos de subagentes (#552) viven SOLO en el ledger (interrumpidos antes de escribir).
- Informes W2 citan "492 B" de cmdline medidos en offset erróneo (real: 580 B, §1.4).
- El coordinador acepta self-reports de gates (25/25, 28/28) sin re-ejecutarlos (§2).

## 1. TABLA — clasificación de cada afirmación clave de hoy

| # | Afirmación | Veredicto | Prueba (medida hoy por esta auditoría) |
|---|---|---|---|
| 1 | k65 en silencio pre-USB (4 min, 0 bytes) | **RELATO sin medida** | Sin artefacto en disco: no hay log del lector, ni foto fastboot, ni timestamps. El bootimg k65 SÍ existe y es el correcto (embebido: `UKE-K65`x3 + `UKE-K64`x3, `dec_len` 41490944 — medida directa), pero el *resultado* es testimonio del coordinador. 0 bytes no se pueden archivar; "lector armado" sin `tee` a fichero no produce evidencia. |
| 2 | k66 en silencio igual (6+ min) → "D3 exonerado" | **RELATO + INFERENCIA encadenada** | Mismo problema que (1): sin artefacto. El binario es correcto (embebido: `UKE-K66`x7, `SIN-D3`x1, D3 ausente — verificado por descompresión zlib). La exoneración de D3 cuelga de DOS testimonios (silencio k65 + silencio k66); si un silencio tuvo otra causa (slot/botones/lector con 4 escrituras en un día), cae en cascada. |
| 3 | k67 en silencio igual (4+ min) → "D2 exonerado, D1 nº1" | **RELATO + INFERENCIA encadenada** | Idem: binario correcto (`UKE-K67`x3 incl. D1+`SIN-D2`+`SIN-D3`, `UKE-K66`x4 heredados G10/G8/poll — medido en Image), resultado sin artefacto. Tercer eslabón de la misma cadena testimonial. |
| 4 | D3 inútil por GDSC (el voto CX nunca llega al RPMH) | **MEDIDA DIRECTA (fuente)** | Re-verificado hoy: `palawan.dtsi` → `power-domains = <CX_GDSC>, <GX_GDSC>`; `gdsc.c` NO define `set_performance_state` (solo `power_on/off`); `common.c:450-457` devuelve 0 sin emitir nada. D3 = no-op **por construcción del DT**. Sólido, independiente de los silencios. |
| 5 | D3 mataba vía oops `clk_round_rate(ERR_PTR)` | **INFERENCIA SÓLIDA, ya refutada como causa única** | Cadena verificada en fuente: `opp/core.c:1440` llama `clk_round_rate(opp_table->clk)` sin guarda IS_ERR; `clk/clk.c:1783` solo filtra NULL; `core.c:1543` deja `clk = ERR_PTR(-ENODEV)`; `adreno_gpu.c:1217` fija clkname para el dev GPU, NO para `gmu->dev`. Pero el oops **nunca se observó** (sin consola/pstore/kmsg) y k66-sin-D3 calla igual (si se cree (2)). Fue el asesino más probable de W3; hoy es hipótesis muerta como causa única. |
| 6 | cmdline 580 B byte-idéntica k64–k67 | **MEDIDA DIRECTA (corrige errata)** | Medido hoy: 580 B, sha `12559c46…`, idéntica en k64/k65/k66/k67 (extracción `mem=2048M…probe_hold_ms=5000`). Los "492 B" de W2/W3/W4 son **errata de offset** — los gates G2 que dicen "492 B" no miden lo que dicen medir. |
| 7 | cpio == k64 (initramfs intacto) | **MEDIDA DIRECTA con matiz documental** | `.config` k65/k66/k67 → `uke-k34-fw-initramfs.cpio.gz` (`f82876…`) idéntico en los tres; repack G3 = blob embebido byte-idéntico al del k64. Matiz: los scripts mezclan shas K22 (`08780e35…`)/K12 (`cb10ff40…`) en comentarios — ruido documental, el gate G3 es lo que manda. |
| 8 | AOP = ELF32 RISC-V sin path gfx (idea E "respondida") | **MEDIDA DIRECTA + INFERENCIA con matiz** | Medido: 524288 B, `aop_a==aop_b` (`3353ea91…`), `e_machine=0xf3` (EM_RISCV, NO Hexagon `0xa4`), entry `0x13200000` fuera de todo LOAD. Matiz honesto: "sin path gfx" está mal dicho — `gfx.lvl/vrm.gfx/gfx.mol/gfx.tmr` SÍ existen (14 hits `gfx`) y `gfx.lvl@0x30050` coincide con el cmd-db vivo al byte. Lo correcto (W3-AOP lo dice bien en §2): el AOP **arbitra rails por nombre** (incl. gfx), sin lógica GPU-específica ni call site dedicado a gfx. |
| 9 | k68-D2-solo pendiente (parche listo, build en marcha) | **MEDIDA DIRECTA** | `k68-build/Image` existe (41490944 B, `UKE-K68`x6, `UKE-K65/66/67`x0, `SIN-D`x1); **no hay bootimg k68** (repack no ejecutado); árbol `k52-tree` hoy en estado k68. "Pendiente" es verdad y verificable. |
| 10 | golden-state Android medido (cmd-db + clk/genpd/regulator) | **MEDIA-MEDIDA (inflado)** | `golden-state-full.txt` (47 l.) y `-k52b2.txt` (18 l.): el **cmd-db SÍ está medido** (`gfx.lvl=[…38 40 80…]`, `gfx.mol=0x38`, `cx.mol=0x40`=LOW_SVS — coherente con opp mínimo s269 255 MHz). Pero `clk_summary/pm_genpd_summary/regulator_summary` están **VACÍOS** (`No such file or directory` — ese kernel no lleva debugfs). "Golden-state completo" es relato; lo medido = cmd-db + dmesg-head. |
| 11 | Gates 25/25 (k65), 28/28 (k66/k67/k68) | **SELF-REPORTS (ver §2)** | k65: `build-k65.log` existe pero el wrapper abortó en gates; 25/25 = re-ejecución manual declarada. k66/k67: **sin build log en disco**. k68: sin bootimg que lo respalde aún. Sustancia re-verificable por marcadores (§2, comandos R1–R3). |
| 12 | "k64 que se flasheó" (W2-K65 §4) / comparabilidad k64–k65 | **RELATO (contradice #554)** | Toda la comparativa "k65 vs k64, una sola variable" pende de un baseline fantasma: el Image k64 existe (`k52-build/Image` 02:02) pero jamás hay evidencia de flash. Si el k64 jamás corrió, "k65 muere ANTES que k64" no tiene término de comparación medido. |

## 2. SELF-REPORTS aceptados sin verificación + re-verificación barata (0 flashes)

Cada comando se ejecutó hoy salvo R7 (requiere tablet viva). `R=~/proyectos/omarchy-uke`.

| Self-report aceptado | Fuente | Re-verificación (comando exacto) | Resultado hoy |
|---|---|---|---|
| k65 25/25 gates | W2-K65 §4 (wrapper abortó; "verificado manualmente") | `R1: grep -a -o "UKE-K65[^\"]*" R/build/kernel-pokes/k65-build/arch/arm64/boot/Image` → debe dar D1/D2/D3 x1; `patch -p1 --dry-run -R build/gates/patches/k65-cx-viable.diff` en k52-tree | ✅ D1/D2/D3 x1 c/u; K64 x3 intacto |
| k66 28/28 + 4 mustnt | W3-K66 §4 (sin build log) | `R2: [misma forma] grep -a -o "UKE-K66[^\"]*" …/k66-build/…/Image`; negativos `UKE-K65`x0, `opp_set_rate` ausente en resume | ✅ K66 x7, K65 x0, SIN-D3 x1 |
| k67 28/28 + 7 mustnt | W4-K67 (sin build log) | `R3: grep -a -o "UKE-K6[78][^\"]*" …/k67-build/…/Image`; `hub set_rate` x0 en fuente | ✅ K67 x3 (D1+SIN-D2+SIN-D3), K66 x4 heredados |
| k68 28/28 + 10 mustnt | W5 (sin bootimg) | `R4: for s in UKE-K65 UKE-K66 UKE-K67 UKE-K68; do grep -c -a "$s" R/build/kernel-pokes/k68-build/arch/arm64/boot/Image; done; ls R/build/bootimg \| grep k68` | ✅ 0/0/0/6, **sin bootimg** (pendiente real) |
| "repack G0–G8 verdes" k65/k66/k67 | ledger #553/#555/#556 | `R5: ls R/build/bootimg/repack-boot-uke-k6*-report.txt` + re-descomprimir embebido: `python3 -c "import zlib; d=open('IMG','rb').read(); i=d.find(b'\x1f\x8b\x08'); dec=zlib.decompressobj(16+zlib.MAX_WBITS).decompress(d[i:]); print(len(dec), dec.count(b'UKE-K6X'))"` | ✅ reports existen; embebidos 41490944 B con identidad correcta (k64:K64x3; k65:K65x3; k66:K66x7; k67:K67x3) |
| cmdline "492 B idéntica" | W2/W3/W4 | `R6: python3 -c "d=open('IMG','rb').read(); i=d.find(b'mem=2048M'); j=d.find(b'\x00',i); print(len(d[i:j]))"` en k64–k67 + comparar sha | ⚠️ **580 B, NO 492** — errata confirmada; igualdad k64–k67 SÍ (sha `12559c46…`) |
| cpio "== k64" | W2/W3/W4 + ledger | `R7a: grep ^CONFIG_INITRAMFS_SOURCE R/build/kernel-pokes/k6{5,6,7}-build/.config; sha256sum R/build/init/uke-k34-fw-initramfs.cpio.gz` | ✅ los tres → K34-fw `f82876…` |
| D3-no-vota (GDSC) | W3-K66 §1a | `R8: grep -A2 power-domains R/build/kernel-pokes/k52-tree/arch/arm64/boot/dts/qcom/palawan.dtsi \| grep -B1 -A2 gmu -i; grep -c set_performance_state R/build/kernel-pokes/k52-tree/drivers/clk/qcom/gdsc.c; sed -n '450,457p' R/build/kernel-pokes/k52-tree/drivers/base/power/common.c` | ✅ GDSC puros + `return 0` silencioso — el self-report era correcto |
| oops clk_round_rate | W3-K66 §1b | `R9: sed -n '1438,1442p' R/build/kernel-pokes/k52-tree/drivers/opp/core.c; sed -n '1783,1785p' R/build/kernel-pokes/k52-tree/drivers/clk/clk.c; grep -n "opp_set_clkname" R/build/kernel-pokes/k52-tree/drivers/gpu/drm/msm/adreno/adreno_gpu.c` | ✅ cadena en fuente intacta; oops nunca observado (sin traza) |
| AOP RISC-V / rails | W3-AOP | `R10: sha256sum R/build/evidencia/aop-dump-20261009/aop_{a,b}.bin; python3 -c "d=open('…/aop_a.bin','rb').read(); print(hex(int.from_bytes(d[18:20],'little')))"`; `strings …/aop_a.bin \| grep -c gfx` | ✅ `3353ea91…` x2, `0xf3`, 14 hits gfx |
| golden-state "completo" | #554 + W3-AOP | `R11: cat R/build/evidencia/aop-dump-20261009/golden-state-k52b2.txt; wc -l R/build/evidencia/aop-dump-20261009/golden-state-*.txt` | ⚠️ cmd-db SÍ; clk/genpd/regulator VACÍOS |
| 4 subagentes #552 (AOP/XBL, premisa E, vendor público, historial) | ledger #552 (solo ledger) | `R12: re-lanzar cada uno con orden de guardar incremental a build/gates/revision/`; mientras tanto: `find R -name "*aop*"`, shas vendor-claim sin clon en repo (scratch sin `OnePlus/SM7675` verificable hoy) | ❌ no re-verificado — vive solo en ledger |
| Silencios k65/k66/k67 | ledger #553/#555/#556 | **No existe re-verificación 0-flash del resultado.** Lo verificable hoy es solo la identidad del flasheado (R5). El revival exige: botones → fastboot → `fastboot getvar all` + reflash con lector LOGUEADO (ver plan P4). | ❌ testimonio puro |

## 3. LAS 3 MENTIRAS más probables que hoy damos por verdad

1. **"#550b: k64 congela también" como hecho medido.** k64 no tiene flash detrás (#554 lo
   confiesa; W2-K65 §4 lo desmiente en la práctica al decir "el k64 que se flasheó").
   Todo el edificio "k65 muere ANTES que k64 / una sola variable vs k64" compara contra un
   fantasma. Coste de la mentira: MÁXIMO — invalida el baseline de 3 experimentos.
2. **"cmdline 492 B byte-idéntica".** Medida en offset erróneo; real 580 B (sha `12559c46…`).
   No cambia el fondo (son idénticas entre sí), pero los gates G2 que rezan "492 B" certifican
   algo que no midieron — y si un gate no mide lo que dice, ¿cuáles otros tampoco?
3. **La cadena de exoneraciones D3 (k66) → D2 (k67) → "D1 nº1".** Tres silencios sin artefacto,
   con 4 escrituras en un día, slots tocados (B retry 6), dtbo s273 experimental a bordo y lector
   sin log. Basta que UN silencio tuviera causa operativa (flash parcial, slot, batería 4013 mV,
   error humano bajo presión) para que dos exoneraciones sean circulares y D1 sea un falso
   culpable. El plan-C (enable-path) ya lo intuye; la crítica lo exige como hipótesis al mismo
   nivel que D1, no como fallback.

(Candidata nº4: "golden-state medido" con 3 de 4 secciones vacías; la comparación vendor-vs-vivo
de pwrlevels/corners que viene depende de datos que aún no existen.)

## 4. PLAN de re-verificación (0 flashes, ordenado por coste)

- [ ] **P0 — re-ejecutar R1–R11** (arriba) en una sola pasada y pegar outputs a este fichero
  (~15 min, PC). Dueño: coordinador antes de cualquier flash.
- [ ] **P1 — corregir la errata 492→580 B** en W2/W3/W4 + gates G2 (`repack-k6*.py`, `build-k6*.sh`):
  que el gate mida `len(cmdline)==580` y `sha==12559c46…`. Si G2 decía 492 y pasaba en verde,
  auditar qué comparaba realmente.
- [ ] **P2 — re-lanzar los 4 subagentes #552 con guardado incremental obligatorio**
  (un informe a `build/gates/revision/` cada uno antes de cualquier conclusión en chat).
  Sin esto, #552 sigue siendo rumor con prestigio de ledger.
- [ ] **P3 — golden-state de verdad**: re-capturar con debugfs habilitado (o admitir que ese
  kernel no lo lleva y buscar clk/genpd/regulator por otra vía: `clk_summary` vía sysfs,
  `rpmh` traces, DT + vendor dtsi). Hasta entonces, prohibir "el golden-state dice…".
- [ ] **P4 — protocolo anti-testimonio para el próximo flash** (k68 o repetición k66):
  lector con `tee` a `build/logs/consola-kXX-$(date +%s).log`, `fastboot getvar all` antes y
  después, foto/timestamp de cada paso, `dd boot_a | sha256sum` post-flash por SSH si arranca.
  Un silencio solo cuenta como dato si el log del lector existe y muestra 0 bytes con
  timestamps de ≥4 min.
- [ ] **P5 — experimento que rompería la mentira nº1**: flashear k64-vendorcfg (ya empaquetado,
  `cc8f896a…`) con protocolo P4. Si k64 habla (USB/consola/S3-stage), el baseline revive y la
  cadena D1/D2/D3 se reinterpreta; si calla con log, #550b queda por fin medido. Es 1 escritura.
- [ ] **P6 — elevar plan-C (enable-path diferido) a hipótesis principal alternativa** en el
  diseño k68/next: rates fijados + `clk_bulk_prepare_enable`/S1 tras USB vivo, de modo que la
  próxima muerte deje traza en vez de silencio.

* traits de cierre: lo sólido de hoy (medido de verdad) = bootimgs k64–k67 con identidad
correcta, cmdline 580 B idéntica, cpio K34-fw común, D3-no-op por GDSC, AOP RISC-V con
gfx.lvl arbitrado por nombre, cmd-db vivo, k68-Image listo sin bootimg. Lo que NO es sólido =
todo veredicto que empiece por "en silencio igual".*
