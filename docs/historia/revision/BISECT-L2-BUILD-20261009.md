# BISECT-L2 — build (L1 + D1-solo, sin flashear) — 2026-10-09

> Solo PC. Tablet VIVA en L0; PROHIBIDO flashear/tocarla. Este fichero es NUEVO
> (gemelo construye L1 en `docs/historia/revision/BISECT-L0-20261009.md` §4 / su propio fichero; no tocarlo).
> Estado: §1–§3 cerradas y VERIFICADAS en binario (build OK 9-oct 22:53,
> `DONE L2-BUILD-OK`); §4 redactado con G3-L2 obligatorio (repack NO ejecutado).

## 0. Definición

- L2 = L1 + D1-solo (estilo K70: `clk_set_rate(core,220M)` + testigos, SIN D2/D3).
- Celda D1∧¬K64 si L1 vive; si L1 calla, L2 no informa (matiz C5/enable en BISECT-L0 §5).
- 1 flash = 1 variable; SIN repack ejecutado con flash, SIN flash en este fichero.

## 1. Base L1-equivalente propia (el L1 del gemelo aún no tiene binario)

Hecho verificado 9-oct ~22:4x: el árbol del gemelo `k52-L1-tree` YA lleva K64
(6× `UKE-L1`, mtime 22:18) pero `build/logs/build-k52L1.log` NO existe
(binario L1 inexistente). Según receta: NO espero, NO toco su árbol/copia.

Mi base propia, toda en rutas `*L2*` (cero escrituras fuera):

- R0. `cp -a k52-L0-tree k52-L2-tree` (1,8 GB). Verificado: `diff` L0↔L2 virgen
  = vacío; 0× UKE-L1/UKE-K67/UKE-K70/UKE-L2.
- R1. `patch -p1` con el diff K64 DEL GEMELO
  `build/gates/patches/k52L1-k64solo.diff` (única dependencia del gemelo;
  leído, no modificado; su árbol/copia intactos).
  Dry-run limpio (hunk1 fuzz 1, offset −1; hunk2 limpio); aplicado: 6× UKE-L1,
  mismo conteo que el árbol del gemelo. Referencia intermedia guardada en
  `/tmp/a6xx_gmu-L2base-K64.c` (solo para generar el diff D1 versionado).
- R2. Diferencia declarada vs L1 del gemelo: NINGUNA en fuente tras R1 salvo
  el hunk D1 de §2. Verificado por `diff` L1-gemelo↔L2-mío: fuera del hunk D1,
  cero líneas distintas (lectura del árbol del gemelo, sin tocarlo).
  `diff` L0↔mi-base: solo líneas del hunk K64 (6× UKE-L1 + función
  `uke_l1_vendor_config` + llamada tras P3-pwrOK).

## 2. Hunk D1-solo (testigo propio UKE-L2)

- Origen: D1 de `build/gates/patches/k67-d1solo.diff` (hunk `@@ -2306,21`),
  con la FORMA de `build/gates/patches/k70-planC-C2.diff` (contexto stock;
  hunks G10/G8 chipid/log y poll-vendor DESCARTADOS; C1/D2/D3 ausentes).
- Versionado como `build/gates/patches/k52L2-d1solo.diff`, generado por
  `diff -U4` base+K64→L2 (no escrito a mano): verificado FWD (aplica sobre
  base+K64 en /tmp) y REVERSO (`patch -R --dry-run` limpio sobre mi árbol).
- Contenido (1 hunk, `@@ -1828,11 +1828,22 @@`, sitio H2-gx):
  stock `clk_set_rate(core,200M)+hub-condicional` →
  `ret = clk_set_rate(core,220M)` + 3 `pr_err` UKE-L2
  (`D1 gmu clk_set 220M rc=%d` / `SIN-D2 (hub en rate XBL…)` /
  `SIN-D3 (voto CX eliminado…)`) + `pr_flush(120,false)`.
  El hub NO se toca (queda en rate heredado XBL); SIN voto OPP.
- Fuente limpia: 4× UKE-L2 (1 comentario + 3 testigos);
  0× `UKE-K65:/K66:/K67:/K68:/K70/UKE-C1/poll vendor` en fuente
  (los 4 `GENERAL_10/8` que casa grep son macros mainline
  `REG_A{7,8}XX_GMU_GENERAL_{10,8}`, idénticas en L0 — no son testigos
  y no llegan al binario como texto).
- Ojo documentado: el `ret =` reutiliza el `ret` que luego pisa
  `clk_bulk_prepare_enable` (igual que k70; los rc NO abortan por diseño).

## 3. Build (CERRADO — OK 9-oct 22:53:16, `DONE L2-BUILD-OK`)

- Script: `docs/historia/gates-palawan/build-k52L2.sh` (clon de `build-k52L1.sh` del gemelo).
  Cambios: rutas `k52-L2-tree/k52L2-build/k52L2-bateria.config/build-k52L2.log`;
  must +3 UKE-L2; mustnt V2-L2 (se RETIRA `D1 gmu` — el testigo L2 lo contiene;
  la ausencia de D1 ajeno la cubren `UKE-K65:/K67:/K70`; se mantienen
  `D2 hub/D3 cx/poll vendor/GENERAL_10/GENERAL_8`); `DONE L2-BUILD-OK`.
  K43 single-backslash verificado a nivel de byte (`od -c`): must
  `b'\x013UKE-POKE'` (1× `\`, bytes `01 33…` = forma pr_err real) y mustnt
  `b'\x014UKE-POKE'` (1× `\`, bytes `01 34…` = forma pr_warn, ausente exigida)
  — idéntico al L0 que pasó gates (log L0 l.4797: `GATE OK x1` + byte `01` real).
- Dos erratas heredadas CORREGIDAS (cosmética, gates iguales): la cola del
  script decía cpio K22/`DONE L0-BUILD-OK`; ahora cpio K34-fw 6-oct (el que
  exige el gate `INITRAMFS_SOURCE`) y `DONE L2-BUILD-OK`.
- Config: `build/kernel-config/k52L2-bateria.config` = copia byte-idéntica de
  la L1 del gemelo (`cmp` OK; apunta al cpio K34-fw 6-oct con fw GPU dentro).
- Lanzado 9-oct ~22:4x desprendido (el make en primer plano es no-op conocido).

### 3.1 Verificación (EJECUTADA de verdad sobre el binario — TODO OK)

- V1. Gates del propio script (`build/logs/build-k52L2.log` l.4779–4819):
  Image 41490944 B + nuevo que .config; 33× `GATE OK` (perfil L0 + UKE-L1×3
  l.4807–4809 + UKE-L2×3 l.4810–4812 + K43 l.4797 con byte `01` real);
  cero `FALTA/AUN ESTA/ABORT` (el script habría abortado por `set -e`/`fail`).
- V2. `sha256sum`: Image `8baf230c…754`, Image.gz `3f823351…896`;
  cpio embebido `ebc2de46…bc` = cpio 6-oct de BISECT-L0 §3.2 R5 ✓.
- V3. Re-verificación independiente (no solo el script) L2↔L1-gemelo (lectura,
  sin tocar nada del gemelo)↔oráculo k52b2:
  tamaños L2=L1=k52b2=41490944 B exactos; L2 = L1 + exactamente 3 strings
  (UKE-L2 D1/SIN-D2/SIN-D3 ×1; en L1 ×0); UKE-L1×3 en ambos; K43 err ×1 en
  ambos, warn ×0; negativos V2-L2 NINGUNO presente; banner idéntico
  (`7.2.0-rc2-palawan (uke@palawan) (clang 23.1.1, LLD 23.1.1)`);
  POKE=113, K19=21, WALK=8 en ambos. L2 declarado == L1 + D1-solo.

## 4. Repack + flash + ledger (REDACTADOS, sin ejecutar)

- Repack (PC, permitido pero NO ejecutado hasta V1–V3 OK):
  `python3 docs/historia/gates-palawan/repack-k52L0.py --kernel build/kernel-pokes/k52L2-build/arch/arm64/boot/Image.gz --out boot-uke-k52L2.img`
  (flags `--kernel/--out` verificados: existen, l.66–70 del script).
  OBLIGATORIO antes: clonar a `repack-k52L2.py` con G3-L2, porque el G3-L0
  actual RECHAZARÍA el kernel L2 por diseño: exige `register_config` ausente
  (repack-k52L0.py l.248) y el hunk K64 lo trae en sus 3 testigos UKE-L1
  (medido en fuente §1). G3-L2 = G3-L0 íntegro (POKE=113, K19×21, K17×1,
  WALK×8, MAPPING×15, tamaño ±256 KiB) + positivos `UKE-L1/K64`×3 y
  `UKE-L2`×3 + negativos V2-L2 (familia K55–K70/C1/C3/s3_stage/rescue
  ausente, SALVO `register_config` y `K64` vía testigos L1, y SALVO D1-220M
  vía testigo L2). Sin ese clon, NO hay repack.
- Flash: PROHIBIDO en este turno. Cuando toque (otro turno, tablet disponible):
  1 flash = 1 variable, k52b2-intercalado antes/después, pstore ADEMÁS de ACM,
  n≥2 si calla, retry+batería registrados (BISECT-L0 §4).
- Fila ledger (hermano `~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md`,
  REDACTADA, no escrita — no hay escritura que pre-registrar):
  `#562? L2 = L1+D1-solo | boot-uke-k52L2.img <sha> | D1∧¬K64 si L1 vive |
  ACM+pstore, n≥2 si calla | pre-registro ANTES del flash, nunca después`.
