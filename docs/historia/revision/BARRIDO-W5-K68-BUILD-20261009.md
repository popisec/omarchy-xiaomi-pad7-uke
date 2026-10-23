# BARRIDO-W5-K68-BUILD — D2-solo: construcción + verificación (solo PC, 2026-10-09)

> PROHIBIDO flashear/tocar la tablet (colgada, presupuesto superado).
> Solo PC. Fichero NUEVO (no toca los de W4).

## 1. Estado real del árbol (verificado, no dado por bueno)

## 2. Ruta a k68 verificada en scratch (árbol real intacto hasta §3)

- Copia del `a6xx_gmu.c` real a scratch: `-R k67` dry-OK + aplicado →
  intermedio = k65 exacto (`UKE-K65` x4: comentario+D1+D2+D3; cero
  K66/K67/K68; sin poll/G10/G8; `opp_set_rate` presente = D3 vivo).
- Sobre el intermedio: forward `k68` dry-OK + aplicado → estado k68:
  positivos `UKE-K68: D2 hub` x1, `SIN-D1` x1, `SIN-D3` x1,
  `poll vendor` x1, `GENERAL_10 chipid=` x2, `GENERAL_8 log=` x1;
  negativos `UKE-K65/K66/K67` x0, `clk_set_rate(core` x0,
  `opp_set_rate` x0, `UKE-K68: D1/D3` x0.
- `patch -p1 --dry-run -R k68-d2solo.diff` sobre el k68-aplicado → **OK**
  (puerta de linaje del futuro build, clon de k66 §4 / k67 §4).

## 3. Mutación trazable del árbol real (cada paso con dry-run antes)

- Backup pre-mutación (fuera del repo, convención k67 §7):
  `scratch/k68/a6xx_gmu.k67-aplicado.c` sha256
  `57cae7db…baf0f` (= árbol k67 verificado §1).
- Paso 1: dry-run `-R k67` OK → aplicado real → intermedio = k65 exacto
  (`UKE-K65` x4, cero K66/K67/K68).
- Paso 2: dry-run forward `k68` OK sobre el intermedio → aplicado real →
  estado k68 (testigos §2; `core_clk` x0, `opp_set_rate` x0).
- Puerta de linaje sobre el árbol real: `dry-run -R k68` → **OK**
  (lo compilado == lo versionado).
- Backup post-mutación: `scratch/k68/a6xx_gmu.k68-aplicado.c` sha256
  `c40b92bd…04e429e4e`.
- NOTA: el árbol compartido queda en estado k68; el estado k67 previo es
  recuperable (`-R k68` + `+k67`, ambos diffs versionados). El `k67-build`
  ya compilado no se ve afectado (sus .o/Image están congelados).

## 4. Build k68 (incremental k67-build → k68-build, receta build-k68.sh)

- Receta: `docs/historia/gates-palawan/build-k68.sh` (clon de `build-k67.sh`; cabecera,
  gates must K68 —D2 x1, SIN-D1 x1, SIN-D3 x1, poll x1, G10 x2, G8 x1—
  y 10 mustnt —warn-poke, e4, 0x200000, K65-D1/D2/D3, K66-D1/D2, K67:,
  K66:—; `bash -n` OK). Corrección manual obligada: el `sed` ciego dejaba
  gates D1/K66 del gemelo; reescritos a D2/K68 + negativos de hermanas.
- Base: `cp -a k67-build → k68-build` (3.2 G) + make incremental (~1 min:
  solo `a6xx_gmu.c` + relink).
- Resultado: `Image` **41490944 B** (idéntico a k64/k65/k66/k67),
  `Image.gz` 16708319 B; **28/28 must + 10 mustnt ausentes** (incluidos
  `UKE-K68: D2` x1, `SIN-D1` x1, `SIN-D3` x1, poll/G10x2/G8 K68, K64;
  `uke_smmu_dump` x2 como en k67 —el gate exige ≥1—).
- Puerta de linaje: `patch -p1 --dry-run -R k68-d2solo.diff` sobre el árbol
  real → **OK** (lo compilado == lo versionado).
- Shas FINALES (segundo link tras re-chequeo de warnings; el primer link
  gateado dio `c4196009…/70e3c971…`, superseded por timestamp `utsversion.h`,
  mismo código): Image
  `2245fd172490bab1bdef9c291e7d0bbea7a4a6971589f1b7afc9c5d7b2b309a9`,
  Image.gz
  `f49cc8ec968c5ec98c30ead266c41fa9f0fb0813ef49655a638decfab7b5c79a`.
  Re-gateado el Image final en lectura: 28 must + 10 mustnt OK.
- Warnings: recompilación aislada de `a6xx_gmu.o` sin warnings nuevos
  (solo el preexistente K61 `frame-larger-than` de la familia, sin nueva
  clase). Initramfs embebido = cpio K22 `08780e35…` (gate del script).

## 5. Repack LISTO sin ejecutar (receta para el dueño; NO ejecutada)

Receta (NO ejecutar: `repack-k68.py` creado y verificado por
`py_compile`, G3 previo contra el Image.gz en solo-lectura OK;
al ejecutar, clona el flujo k67 con `KERNEL=k68-build/.../Image.gz`,
`OUT=boot-uke-k68-d2solo.img`, G3 = D2-K68 x1 + SIN-D1 x1 + SIN-D3 x1 +
poll x1 + G10 x2 + G8 x1 + K64-register_config x1, negativos
K65-D1/D3 + K66-D1/D2 + K67:/K66:, `UKE-POKE`=113):

```bash
python3 docs/historia/gates-palawan/repack-k18.py \
  --kernel build/kernel-pokes/k68-build/arch/arm64/boot/Image.gz \
  --out build/bootimg/boot-uke-k68-d2solo.img \
  --dsid \
  --cmdline-append "memmap=0x2B00000\$0xE3940000,loglevel=4,msm.uke_gmu_shared=0,arm_smmu.uke_kgsl_keep=0,hung_task_panic=0,printk.always_kmsg_dump=0,plymouth.enable=0,msm.uke_s3_stage=3,msm.uke_rescue=1,msm.uke_probe_hold_ms=5000" \
  --cmdline-require "msm.uke_s3_stage=3,msm.uke_rescue=1"
```

Cmdline byte-idéntica a k64/k65/k66/k67 (492 B); `stage=3` reproduce el
flujo exacto: comparación directa k67-vs-k68 (una sola variable: D1↔D2
intercambiados; k66-vs-k68: D1 fuera). Gates G0-G8 del script, tamaño
exacto 100663296 B, sha al ledger antes de escribir. Segundo boot
recomendado: mismo img con `stage=2`. Trazas a buscar: `UKE-K68: D2 …
rc=`, `SIN-D1`, `GENERAL_10 … OK`, `UKE-CM3DBG: clks core=<heredado>
hub=200000000` (core heredado NO-220M = firma de k68).
**NADA de esto ejecutado: ni repack, ni flash, ni reboot.**

## 6. Fila de ledger pre-registrada (redactada; NADA ejecutado)

**K68-D2SOLO — PRE-REGISTRO: D2 sin D1 ni D3 + poll vendor + G10/G8.**
**Artefacto.** `build/bootimg/boot-uke-k68-d2solo.img` sha256 `PENDIENTE`
(repack no ejecutado; Image.gz `f49cc8ec…5a638dec` verificado §4).
**Variables vs k67:** D1↔D2 intercambiados (única variable; gemelo
invertido); vs k66: D1 eliminado (única variable); poll/G10/G8/K64/P3-stages
intactos salvo renombre K66→K68. **Comando (NO ejecutado).**
`fastboot flash boot_a|boot_b build/bootimg/boot-uke-k68-d2solo.img` ·
verificación: consola ACM + pstore; buscar `UKE-K68: D2 … rc=`, `SIN-D1`,
`SIN-D3`, `UKE-CM3DBG: clks core=<XBL> hub=200000000`, desenlace S3.
**Criterios** (W4-K68 §1): H3-clk/S3 ⇒ D2 viable, D1 era el problema;
silencio igual + k67 vivo ⇒ D2 asesino; silencio en ambos ⇒ enable-path
o combinación (plan-C W4-K68 §4). **Coste.** 1 escritura + 1-2 arranques.
Registrar los 4 `slot-retry-count`.

## 7. Bitácora y cierre

- El árbol NO estaba en estado inconsistente: un solo estado lógico (k67);
  la vía `-R k67 → +k68` aplicó limpio en scratch y en real, con dry-run
  antes de cada paso y backups fuera del repo
  (`a6xx_gmu.k67-aplicado.c 57cae7db…`, `a6xx_gmu.k68-aplicado.c c40b92bd…`).
- k68 compiló limpio al primer intento incremental; no hubo que parar.
- Ficheros creados: `docs/historia/gates-palawan/build-k68.sh`,
  `docs/historia/gates-palawan/repack-k68.py`, `build/kernel-pokes/k68-build/` (Image +
  Image.gz verificados), este informe. Fichero modificado: un solo
  `a6xx_gmu.c` del árbol (k67→k68 trazable); ningún informe W4 tocado.
- Confirmación de no-contacto con la tablet: ningún `fastboot`, `adb`,
  repack ni reboot ejecutado en esta sesión (solo `patch --dry-run`/`patch`,
  `make`, `sha256sum`, `grep`, gates de lectura).

- `k52-tree/drivers/gpu/drm/msm/adreno/a6xx_gmu.c` contiene:
  `UKE-K66` (hunks 1-2: GENERAL_10/8 + poll vendor) + `UKE-K67`
  (hunk3: D1-solo, solo `clk_set_rate(core_clk,220M)`, sin hub ni opp).
- Dry-runs (cwd = `build/kernel-pokes/k52-tree`):
  `patch -p1 --dry-run -R k67-d1solo.diff` → **OK**;
  `patch -p1 --dry-run -R k66-d1d2-vendorpoll.diff` → **FAIL**
  (hunk #3 FAILED at 2306, 1/3);
  `patch -p1 --dry-run -R k65-cx-viable.diff` → **FAIL**
  (hunk #1 FAILED at 2308, 1/1);
  `patch -p1 --dry-run k68-d2solo.diff` → **FAIL** (3/3, árbol ocupado).
- Veredicto: el árbol lleva **UN solo estado lógico = k67**
  (no "k65+k66+k67 apilados": los hunks 1-2 de k66/k67 son byte-idénticos
  y el hunk3 es mutuamente excluyente). La afirmación del encargo de que
  "k52-tree lleva aplicados k65+k66+k67" queda **corregida**: lo que hay
  es k67 aplicado; k65/k66 están superados, no presentes.
- Ruta a k68 verificada en dry-run: `-R k67` restaura el estado k65
  (hunk3 = D1+D2+D3, hunks 1-2 prístinos) y sobre él `+k68` aplica limpio.
  El informe W4-K68 §5 decía lo mismo vía k66; verificado aquí que vía
  k67 es idéntico (mismo intermedio k65).
