# BARRIDO-W2-K65-DISEÑO — kernel 'CX viable' D1+D2+D3 (2026-10-09)

> Tablet en silencio, PROHIBIDO flashear. Solo PC: parche + build + verificación.
> Estado: DISEÑO + PARCHE + BUILD EN CURSO (ver §7).

## 0. Auditoría de la consigna recibida

La receta canónica citada (`k18-tree` + `build-k49.sh`) es **obsoleta para esta
rama**: `k18-tree/drivers/gpu/drm/msm/adreno/a6xx_gmu.c` NO contiene `UKE-K61`
ni `UKE-K64` (grep: 0 resultados), mientras que el k64 verificado en binario
(FASE2 §0: `UKE-K64: register_config COMPLETADO` en strings) salió de
`k52-tree` → `k52-build/Image` (9-oct 02:02, 3 ocurrencias `UKE-K64`).
**Base real del k65: `k52-tree` + `k52-bateria.config`, script nuevo
`build-k65.sh` clonado de `build-k52.sh`.** Compilar sobre k18-tree habría
perdido K61 (testigos P3/stage) y K64 (vendor_config) y el experimento no sería
comparable con k64.

## 1. Fallo conceptual de D1+D2+D3: NO hay bloqueo, un residual

Revisado el diseño FASE2 §6 antes de compilar:

- **D1 (gmu 220M)**: sólido. 220M está en `ftbl_gpu_cc_gmu_clk_src`
  (`gpucc-palawan.c:175-180`); `clk_set_rate(220M)` es exacto, sin floor.
- **D2 (hub 200M)**: sólido con residual menor. El hub cuelga de
  `ftbl_gpu_cc_ff_clk_src = {200M}` → 200M exacto; el 150M actual da -EINVAL
  (retorno ignorado: el código sigue igual). Residual: el padre
  `ff_clk_src/GPLL0` no se vota explícitamente; si XBL lo dejó abajo, el rate
  real no pegará — **el testigo CM3DBG ya existente
  (`UKE-CM3DBG: clks core=%lu hub=%lu`) lo delatará en el primer boot**.
  No bloquea el experimento; siguiente iteración votaría el padre.
- **D3 (esquina CX LOW_SVS explícita)**: viable host-side sin tocar DT ni
  reguladores. Cadena verificada en este árbol:
  `gmu_opp_table` (220M level `0x40`, 550M level `0x80`) +
  `drivers/opp/core.c:1178-1197` (`_set_opp_level` → propaga
  `dev_pm_domain_set_performance_state(dev, level)` al genpd CX **aunque no
  haya `required-opps`** —y no los hay en el DT fusionado—) +
  niveles ARC Qualcomm (`0x40` = LOW_SVS, `0x80` = SVS: el mismo encoding que
  `a6xx_gmu_get_arc_level` coteja contra `cx.lvl` del cmd-db).
  Por tanto `dev_pm_opp_set_rate(gmu->dev, 220M)` = voto LOW_SVS sobre el rail
  CX vía rpmhpd, que es exactamente lo que el vendor consigue con su arco RPMH
  explícito + RDPM 220000. Orden correcto: el voto se fija en `a6xx_gmu_resume`
  (H3-clk), muy anterior al release S3 dentro de `fw_start → a6xx_gmu_start`,
  y nada posterior lo pisa (`set_initial_bw/freq` solo tocan el OPP del
  dispositivo GPU = rail GX, no el del GMU).
- **No toca**: SYSRESET (solo lo tocan K61-stage y el flujo original),
  SMMU (cero MMIO nuevo), ACD/AOP, GDSC on/off, `register_config` (K64 intacto).

Veredicto: **el diseño D1+D2+D3 es conceptualmente sano; se compila.**

## 2. Parche

`build/gates/patches/k65-cx-viable.diff` — aplica con `patch -p1` sobre
`k52-tree` (que ya lleva K61+K64). Un solo hunk en `a6xx_gmu_resume`,
sustituye las dos `clk_set_rate` (200M/150M) por el bloque K65:

- D1: `clk_set_rate(gmu->core_clk, 220000000)` + testigo pr_err con rc.
- D2: `clk_set_rate(gmu->hub_clk, 200000000)` incondicional (colapsa el
  ternario a740: ambas ramas vendor son 200M) + testigo pr_err con rc.
- D3: `dev_pm_opp_set_rate(gmu->dev, 220000000)` (fija OPP 220M → level 0x40
  → performance-state LOW_SVS en el genpd CX) + testigo pr_err con rc.
- `pr_flush(120, false)` tras los testigos (disponible en esta TU: lo usan
  K61/K64; garantiza pstore+UART antes de cualquier freeze posterior).
- Sin includes nuevos (`<linux/pm_opp.h>` ya está, l.11). Sin tocar SYSRESET
  ni SMMU. Los rc NO abortan: el experimento debe medir D1/D2 aunque D3 falle.

Testigos (todos `pr_err` = nivel 3 < tope K41 = 4: pasan a consola+dmesg,
mismo mecanismo validado por K43 `\x013UKE-POKE`):

- `UKE-K65: D1 gmu clk_set 220M rc=%d`
- `UKE-K65: D2 hub clk_set 200M rc=%d`
- `UKE-K65: D3 cx LOW_SVS opp_set_rate 220M rc=%d`

## 3. Build

- Script: `docs/historia/gates-palawan/build-k65.sh` (clon de `build-k52.sh`: misma fuente
  `k52-tree`, misma config `k52-bateria.config`, mismo cpio K34-fw,
  `MAKE=/usr/bin/make ARCH=arm64 LLVM=1`, `Image.gz`, sin `modules_install`).
  Única diferencia: `O=k65-build` (dir limpio: build completo ~14 min) y tres
  gates de marcador K65 extra (§2).
- Lanzado detached 9-oct ~03:05 (pid 382610, `setsid nohup`,
  log `build/logs/build-k65.log`); Image producido 04:06. El wrapper abortó
  en gates por los 8 marcadores SMMU-migrados (§4) — el binario se verificó
  manualmente (25/25 OK) y el log lleva la anotación.
- Pre-chequeo TU: `a6xx_gmu.o` compila (solo warning preexistente K61
  `frame-larger-than` en `uke_k61_rescue_write`, sin relación con K65).
## 4. Verificación del Image — COMPLETA 9-oct (~04:10)

- Build limpio `k65-build` terminó: `Image` **41490944 B** (mismo tamaño que el
  k64: la instrumentación añadida no engorda el binario),
  `Image.gz` 16708334 B.
  sha256 `01677ce3c65355e08d6f08b24b8833561773fef657ffc6e0317b7e132308c`
  (Image), `7b01d8f01f383e95508ed22853ef5324631fd333aeb425679d44a3baf3c954ab`
  (Image.gz).
- `patch -p1 --dry-run -R k65-cx-viable.diff` sobre el árbol: OK ⇒ **lo
  compilado == lo versionado**.
- Gate binario del `\x013UKE-POKE` (el exigido): **presente x1, forma warn
  `\x014` ausente** ⇒ los testigos K65 (`pr_err`) pasarán el tope K41.
- Gates de marcadores (`build-k65.sh`, re-ejecutados contra el Image):
  **25/25 OK**, incluidos `UKE-K65: D1/D2/D3` (x1 cada uno), `UKE-K64:
  register_config COMPLETADO`, `UKE-K44`, `\x013UKE-POKE`, `uke_smmu_dump` y
  `mustnt` ausentes (`0x200000;`, `\x014UKE-POKE`, `uke_k19_dump_desc(e[4]`).
- Incidencia honesta del build limpio: 8 marcadores SMMU-viejos (K19-dump +
  caminador K25) **ya no existen en fuente** — el driver SMMU migró al layout
  upstream (`drivers/iommu/arm/arm-smmu/`) entre el 6 y el 9-oct y ese código
  no migró. **El k64 (verificado en su Image: 0 ocurrencias)** YA sale sin ellos
  — ojo: el k64 nunca llegó a flashearse (#554 lo confiesa; #550b era inferencia),
  luego k64 y k65 son comparables en binario pero #550b NO es medida de arranque. Los gates de `build-k65.sh`
  se actualizaron a la instrumentación SMMU que sí vive en el árbol
  (arming/handoff/K18/K25-DESACTIVADO/K38/K32/K33); la resurrección del
  volcado queda fuera del alcance K65 (requeriría port, no parche mínimo).
## 5. Repack LISTO sin flashear (receta para el dueño; NO ejecutada)

Comando (el Image ya está verificado §4; listo para ejecutar cuando el dueño
abra sesión de flash):

```bash
python3 docs/historia/gates-palawan/repack-k18.py \
  --kernel build/kernel-pokes/k65-build/arch/arm64/boot/Image.gz \
  --out build/bootimg/boot-uke-k65-cxviable.img \
  --dsid \
  --cmdline-append "memmap=0x2B00000\$0xE3940000,loglevel=4,msm.uke_gmu_shared=0,arm_smmu.uke_kgsl_keep=0,hung_task_panic=0,printk.always_kmsg_dump=0,plymouth.enable=0,msm.uke_s3_stage=3,msm.uke_rescue=1,msm.uke_probe_hold_ms=5000" \
  --cmdline-require "msm.uke_s3_stage=3,msm.uke_rescue=1"
```
objetivo es **byte-idéntica a la del k64** (580 B —corrección W6: el informe decía
  492 B por offset erróneo; los repacks k65–k68 certifican 580 B—, medida del
`boot-uke-k64-vendorcfg.img`): variante `--dsid` (370 B con `video=DSI-1:d`)
+ los 10 tokens de arriba. `stage=3` reproduce el flujo k64 exacto (poll
100 ms original): comparación directa; si no congela, era D1/D2/D3. Segundo
boot recomendado: mismo img con `stage=2` (autopsia K61) — requiere repack
gemelo o edición de cmdline, a criterio del dueño.

Gates que deberá pasar (todos en `repack-k18.py`, nada manual):
- G0: shas de base/K13/K13dsid registrados.
- G1: cabecera v4/1584, ramdisk 0, gzip @4096.
- G2: cmdline final 580 B (el informe decía 492 B: errata, ver §arriba) con los tokens exigidos, sin duplicados.
- G3: `Image` crudo ≈ 41355776 ± 256 KiB + **marcadores K65 presentes**
  (los añade `build-k65.sh`, pero el repack los re-verifica).
- G4: marcadores del árbol (UKE-POKE, o82, mdss, smmu…).
- G5/G6/G7: kernel @4096 con `kernel_size` actualizado, **tamaño exacto
  100663296 B** (= stock, se llena la partición entera), cabecera+cmdline
  (0..4096) y cola intactas byte a byte.
- G8: publica `boot-uke-k65-cxviable.img` + **sha256 que VA AL LEDGER antes
  de cualquier escritura** (ver §6).

## 6. Fila de ledger pre-registrada (redactada; sha pendiente del build)

> Pegar al ledger del hermano ANTES de ejecutar cualquier flash. Nada de lo
> de abajo se ha ejecutado. Tablet en silencio: sin sesión viva, sin consola.

**K65-CXVIABLE — PRE-REGISTRO: boot con estado CX viable (D1+D2+D3).**
**Artefacto.** `build/bootimg/boot-uke-k65-cxviable.img` sha256 `PENDIENTE`
(100663296 B exactos, cmdline 580 B idéntica a k64 salvo kernel —corregido W6—).
**Una sola variable vs k64:** GMU 220M + hub 200M + voto CX LOW_SVS
(`k65-cx-viable.diff` sobre `k52-tree`); K64-vendor_config, P3-stages y resto
intactos. Nada más cambia.
**Comando (NO ejecutado).** `fastboot flash boot_a|boot_b
build/bootimg/boot-uke-k65-cxviable.img` · verificación por arranque:
consola ACM + pstore; buscar `UKE-K65: D1/D2/D3 … rc=0`, `UKE-CM3DBG:
clks core=220000000 hub=200000000`, y el desenlace en S3 (`S4-pollOK` vs
congelación como k64 #550b).
**Criterios.**
- ÉXITO DISCRIMINANTE: aparecen los 3 testigos K65 con rc=0, rates 220M/200M,
  y el boot **supera S3** (S4-pollOK o HFI vivo) ⇒ era D1/D2/D3; el
  golden-state dirá cuál pesa más.
- FALLO INFORMATIVO: congela igual con testigos OK ⇒ el estado viable lo pone
  XBL/AOP fuera del driver (conclusión #550b en pie); no re-flashear sin
  rediseño.
- FALLO TÉCNICO: algún rc!=0 o rates pegados a 19.2M/heredado ⇒ el voto no
  aplicó; volver a PC, no insistir en la tablet.
**Coste en reintentos.** 1 escritura fastboot + 1-2 arranques (stage=3, luego
opcional stage=2). Registrar los 4 `slot-retry-count` antes y después.
## 7. Bitácora

- ~03:0x: diseño D1+D2+D3 auditado (sin fallo conceptual bloqueante; residual
  D2 documentado §1). Desviación justificada de la consigna: base `k52-tree`
  (el `k18-tree` citado no lleva K61/K64).
- ~03:0x: `k65-cx-viable.diff` v1 (hunk mal contado) → v2 (19 líneas `+`,
  `dry-run` OK) → aplicado al árbol.
- ~03:0x: pre-chequeo `a6xx_gmu.o` OK; `build-k65.sh` creado (clon k52 + 3
  gates K65); lanzamiento detached pid 382610.
- ~03:05–04:06: build limpio (~60 min, 3551 TUs).
- 04:06: wrapper aborta en 8 gates SMMU-migrados; binario por lo demás
  completo (K65 x3 presentes).
- ~04:10: causa raíz confirmada (migración SMMU 6→9 oct; k64 igual);
  `build-k65.sh` actualizado; gates re-ejecutados **25/25 OK**; árbol ==
  diff versionado; shas registrados §4. Repack pendiente del dueño ( §5 ),
  flash PROHIBIDO en esta sesión.
