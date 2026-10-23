# BISECT-L3 — build L3 = L0 + C1 (voto RDPM fail-open, SIN rates, SIN K64)

> Solo PC. Tablet VIVA en L0 (#561 HABLA); PROHIBIDO flashear/tocarla. Este fichero
> prepara parche + build + verificación + repack + fila ledger REDACTADA, SIN flash.
> Estado: §0–§1 cerradas; §2 build en marcha (§2.3).

## 0. Definición (2026-10-09)

- L3 = L0 + C1. Pregunta: ¿el voto CX solo es inocuo?
- Base: `build/kernel-pokes/k52-L0-tree/` directo (NO depende de L1/L2).
- Copia propia: `build/kernel-pokes/k52-L3-tree/` = `cp -a k52-L0-tree` (L0 intacto).
- Diff: `build/gates/patches/k52L3-C1solo.diff` (adaptación de `k69-planC-C1.diff`
  al contexto L0; testigos renombrados UKE-C1→UKE-L3 para distinguir de k69).
- Config: `build/kernel-config/k52L3-bateria.config` (= k52L0: cpio 6-oct).
- Build: `docs/historia/gates-palawan/build-k52L3.sh` (clon de build-k52L0.sh; gates L0 + L3,
  K43 single-backslash).
- Repack: `docs/historia/gates-palawan/repack-k52L3.py` (clon de repack-k52L0.py; G3 perfil L0+L3).
- Artefacto: `build/bootimg/boot-uke-k52L3.img` (cmdline 580 B = k64; cpio k52b2).
- Flash: NO EJECUTADO (fila ledger §5 redactada, pendiente de pre-registro real).

## 1. Parche (hecho, verificado)

- R0. `cp -a k52-L0-tree k52-L3-tree` (L0 intacto: `grep UKE-L3|UKE-C1` en L0 = 0).
- Hallazgo honesto: `patches/k69-planC-C1.diff` NO aplica limpio sobre L0
  (`patch -p1 --dry-run`: hunk1 FAILED at 18 — espera los includes K61 que L0
  no tiene; hunk2 solo con fuzz 2 y contexto K68). Por eso NO se aplica tal cual:
  se adapta a `patches/k52L3-C1solo.diff` (64 l., 2 hunks, `dry-run` limpio en
  copia virgen): hunk1 `#include <linux/io.h>` tras `drm_gem.h` (contexto L0);
  hunk2 bloque de voto tras `uke_poke("H2-gx")`, antes de `Use a known rate`,
  con testigos renombrados UKE-C1→UKE-L3 / `H2-cxvoto`→`H2-L3voto` (el `ausente
  (fail-open, sin MMIO)` se conserva literal para equivalencia con k69).
- Semántica idéntica a C1: voto MHz heredado en `rdpm_cx+0xf14` + `wmb()` solo
  si el recurso existe (E0 esperado: ausente → `pr_err` + sigue); SIN rates
  (core/hub = stock L0 200M/150M intactos abajo), SIN K64 (`register_config`
  ausente: gateado en mustnt).
- Config `k52L3-bateria.config` = copia byte-idéntica de k52L0 (`cmp` OK;
  INITRAMFS_SOURCE → cpio 6-oct `uke-k34-fw-k52b2-initramfs.cpio.gz`).
- Scripts: `build-k52L3.sh` (clon de build-k52L1.sh; gates L0 + 5 L3 en must,
  mustnt L3 = K55–K63 + K64/`register_config` + K65–K68 + K70 + UKE-C1/
  H2-cxvoto + C3 + s3_stage/rescue + D1/D2/D3/SIN-D2/SIN-D3 + poll + G10/G8;
  K43 single-backslash: bytes `5c 78 30 31` + `3` presente / `01 34` ausente)
  y `repack-k52L3.py` (clon de repack-k52L0.py; KERNEL→k52L3-build,
  fuentes→k52-L3-tree, G3 = perfil k52b2 + UKE-L3x3 + H2-L3voto + veto
  H2-cxvoto; OUT `boot-uke-k52L3.img`).

## 2. Build (en marcha)

- 2.1 Una sola variable en fuente: `diff -rq k52-L0-tree k52-L3-tree` = SOLO
  `drivers/gpu/drm/msm/adreno/a6xx_gmu.c` (50 l. de diff: include + bloque L3).
- 2.2 Comando: `./docs/historia/gates-palawan/build-k52L3.sh` → desprendido pid 54313, 9-oct
  ~22:3x; log `build/logs/build-k52L3.log`. O=`k52L3-build` limpio (recompila
  entera, ~12 min como L0).
- 2.3 Resultado: VERDE 22:55:16 (log `build-k52L3.log:4779-4818`). Image 41490944 B
  (= L0/k52b2 al byte en tamaño) `22bfa64e…`, Image.gz `74d3a74b…`. Gates sobre
  Image crudo: perfil L0 intacto (K19/GEO/CB/WALKx8/MAPPINGx2/K17/K32/K33/K38/
  K41/K42/K44/K47/K49) + K43 single-backslash (`01 33` x1 presente, `01 34` x0
  ausente) + 5/5 L3 (`UKE-L3: voto`/`ausente`/`writel`/`ioremap FAIL`/
  `H2-L3voto` x1). Verificación independiente en binario: 18/18 VERDE
  (UKE-L3x3, H2-L3votox1, K43 errx1/warnx0, K19x21, WALKx8, C1x0, cxvotox0,
  K64x0, register_configx0, K65–K68x0, K70x0, s3_stagex0, G10x0).

## 3. Repack (verde, sin flash)

- Comando (PC): `repack-k52L3.py --dsid --cmdline-append "<10 tokens k64>"
  --cmdline-require "msm.uke_s3_stage=3,msm.uke_rescue=1" --out
  boot-uke-k52L3.img --kernel k52L3-build/.../Image.gz`.
- G0–G8 verdes: G0 entradas + 4 fuentes k52-L3-tree sin cambios posteriores;
  G3 crudo 41490944 B, POKE=113 (= L0: el poke extra no duplica `UKE-POKE`),
  perfil k52b2 (K19x21+K17+WALKx8+MAPPINGx15, familia K55–K70 ausente) +
  voto L3 (UKE-L3x3+H2-L3voto, forma-k69 ausente) + initramfs @35402360
  byte-idéntico al del k52b2 (mismo offset que L0: S constante); G6 cmdline
  byte-idéntica a k64 (580 B); G8 unpack_bootimg rc=0.
- Artefacto: `build/bootimg/boot-uke-k52L3.img` (100663296 B)
  sha256 `a149079123ff6b87a56eed8bbad58ab8b788052a622693b7a3d8c287a396dcf0`
  (reporte `build/bootimg/repack-boot-uke-k52L3-report.txt`).

## 4. Verificación (gates de verdad en binario)

- Build: 33/33 must+mustnt sobre Image crudo (log 4779–4811) + K43
  single-backslash (`01 33`x1/`01 34`x0, bytes `5c 78 30 31` en fuente).
- Independiente (este fichero, §2.3): 18/18 VERDE.
- Repack: G0–G8 verdes sobre Image.gz real (no self-report: conteos y
  byte-identidad medidos).
- L0 intacto: `k52-L0-tree` sin `UKE-L3`/`UKE-C1` (0); `k52-tree` (k70) intacto.

## 5. Fila ledger L3 — REDACTADA, NO PRE-REGISTRADA, SIN FLASH

> Pegar al ledger del hermano (`docs/FLASH-LEDGER.md`) como pre-registro ANTES
> de cualquier flash futuro. Hoy la tablet queda VIVA en L0: NADA de abajo
> ejecutado.

### #56x — L3-BISECT PRE-REGISTRO (9-oct): L0 + voto CX fail-open, sin rates.

**Artefacto.** `omarchy-uke/build/bootimg/boot-uke-k52L3.img`
sha256 `a149079123ff6b87a56eed8bbad58ab8b788052a622693b7a3d8c287a396dcf0`
(100663296 B; repack-k52L3.py G0–G8 verdes; cmdline 580 B = k64; cpio K34-fw
6-oct byte-idéntico al del k52b2 @35402360; kernel 41490944 B = L0 en tamaño;
perfil k52b2 + UKE-L3x3 + H2-L3voto; K64/register_config/D1/D2/D3/poll/G10/G8
y forma-k69 UKE-C1/H2-cxvoto ausentes en binario).
**Variable vs L0:** SOLO el voto CX pre-rate (MHz heredado → `rdpm_cx+0xf14`,
fail-open si ausente = caso E0 esperado); rates stock L0, SIN K64.
**Comando (NO ejecutado).** `fastboot flash boot_a` + reboot; buscar
`UKE-L3: voto CX pre-rate`, `PRESENTE`/`ausente(fail-open, sin MMIO)`, desenlace.
**Criterios.** Habla + `ausente` ⇒ voto inocuo (a por L4/D2-solo). `PRESENTE` +
habla ⇒ hay rdpm_cx y el voto no mata. Calla (n≥2, k52b2-intercalado,
pstore+ACM) ⇒ el voto CX solo no explica nada o la muerte es pre-código
(ver CRITICA-W6-HIPOTESIS §2–3: C5/enable constante en L0–L3).
**Presupuesto/gates al pre-registrar:** nº de escritura siguiente libre
(tras #561: verificar), batería ≥3700 mV, slots registrados, lector rearmado
con UN solo lector, dueño presente, tablet en fastboot, k52b2-intercalado
antes/después.
