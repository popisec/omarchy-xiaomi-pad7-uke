# BISECT-L4-BUILD (2026-10-09) — peldaños restantes sobre L0, SIN flashear

> Solo PC. Tablet VIVA en L0 (#561 HABLA); PROHIBIDO flashear/tocarla.
> Gemelos preparan L1/L2/L3 en paralelo — NO se tocan sus árboles/copias/ficheros.
> Todo el trabajo, en copias propias de L0. Fichero NUEVO, escritura incremental.

Base: `build/kernel-pokes/k52-L0-tree/` (L0 == k52b2 validado #561) + cpio 6-oct +
`build/kernel-config/k52L0-bateria.config`. Oráculo L0: Image 41490944 B.

## 0. Mapa L4 (1 flash = 1 variable)

- L4a = L0 + D2-solo (hunk3 de k68-d2solo.diff, SIN G10/G8, SIN poll, SIN D1/D3/C1).
- L4b = L0 + poll-vendor (hunk2 de k66-d1d2-vendorpoll.diff, re-plantado; G10/G8 declarado N/A-sobre-L0, SIN D1/D2/D3/C1).
- L4c = L0 + D3-solo (sub-hunk de k65-cx-viable.diff, solo opp_set_rate + testigo, SIN D1/D2).
- NO-L4d: L0+D1-solo NO se construye (celda del gemelo L2; no duplicar).

## 1. Árboles propios (copias de L0, gemelos intactos)

`cp -a k52-L0-tree` → `k52-L4a-tree`, `k52-L4b-tree`, `k52-L4c-tree` (9-oct, ~1,8 GB c/u).
Gemelos intactos: `k52-tree` (k70) y `k52-L1-tree` (UKE-L1 ×6) ni tocados ni leídos
para escribir (solo `grep -c` de verificación + sitio poll de referencia).
Disco: 70 GB libres; 16c/8 GB RAM libre → builds en paralelo con `-j2` (techo RAM).

## 2. Diffs versionados (1 por peldaño)

Regla: lado-plus reutilizado, contexto adaptado a L0-stock, testigos originales
(UKE-K68/K66/K65: la forense binaria distingue peldaños por presencia/ausencia).

- Verbatim: `patch -p1 --dry-run` sobre L0 de los hunks originales
  k68-hunk3 (`@@ -2306,21`), k66-hunk1 (`@@ -866,9`), k66-hunk2
  (`@@ -1066,9`) → **1/1 FAILED los tres** (cadena k65→k66→k67→k68:
  sus contextos citan el bloque predecesor, ausente en L0-stock).
  Contrapueba: k65-cx-viable.diff (contexto stock) SÍ aplica en L0
  (`Hunk #1 succeeded at 1791`); no se aplica entero porque arrastraría D1+D2.
- `k52L4a-d2solo.diff` (1 hunk): minus = rates stock, plus = bloque K68-D2
  verbatim (comentario + `hub 200M` + 2 testigos + `pr_flush`).
- `k52L4b-pollvendor.diff` (1 hunk): minus = heurística cold/warm if/else
  stock, plus = criterio vendor fijo + testigo `UKE-K66: poll` (testigo verbatim;
  comentario con cabecera L4b).
  G10/G8 (k66-hunk1) declarado **N/A sobre L0**: no tiene marco (las líneas
  `0x1f9cd/cf=0xf` que repara solo existen dentro del frame K64, revertido en
  L0); mainline-L0 ya programa chipid/log reales (`a6xx_gmu.c:1474-1480`,
  `REG_A7XX_GMU_GENERAL_10/8`). Su marco real es K64 = dominio del gemelo L1;
  variante L1+G10/G8+poll redactable a petición (no construida: árbol ajeno).
  Verificación fuente: `val <= 0x20010004` ×0 en L4b-tree, ×1 en L0/L4a/L4c.
- `k52L4c-d3solo.diff` (1 hunk): rates stock intactos + `dev_pm_opp_set_rate`
  220M + testigo `UKE-K65: D3` verbatim + `pr_flush` (SIN D1/D2).
  Porqué: D3 nunca medido solo; k66-silencio (#555) lo exoneró como asesino
  único pero la autopsia W3 predice abort en resume → celda D3∧¬(D1∨D2∨K64).
- NO-L4d (L0+D1-solo): no construido, celda del gemelo L2 (L1+D1). No duplicar.
- Fugas fuente ×0 en los tres árboles (D1/D3/C1/G10/poll/K61–K64/s3_stage).

## 3. Builds + gates reales en binario (K43 single-backslash)

Scripts `build-k52L4{abc}.sh` (clon L0 + must/mustnt por peldaño + `UKE-K17` en
must; negativas de familia K55–K64/C1/C3/K70/L1/GENERAL_10/register_config).
K43 verificado a nivel de byte (`od -c`: `\ x 0 1 4`, 1 sola barra en los 3).
Nota: el diff L0↔L1 mostraba `\\\\x014` en L1 por duplicado de la capa de
visualización JSON; `od -c` confirma que L1 también lleva 1 sola barra.
Sin bug que reportar. Configs `k52L4{abc}-bateria.config` = bytes de L0
(`cmp` OK; INITRAMFS_SOURCE → cpio 6-oct `ebc2de46…`).

Resultado 9-oct ~23:10 (desprendidos 22:3x, `-j2` ×3 en paralelo bajo
contención con los builds de los gemelos; sin OOM ni errores):
- L4a DONE: Image 41490944 B (= L0 = k52b2-oráculo); `UKE-K17`×1,
  `UKE-K68: D2 hub…`×1, `UKE-K68: SIN-D1…`×1; cero MARCADOR/ABORT.
  Image sha `7e1dcaa2…8b155`, Image.gz `3a317a23…5cfdd`.
- L4b DONE: mismo tamaño; `UKE-K66: poll vendor…`×1; cero MARCADOR/ABORT.
  Image `22e4566f…66ad8`, Image.gz `08226e5e…5725cc`.
- L4c DONE: mismo tamaño; `UKE-K65: D3…`×1; cero MARCADOR/ABORT.
  Image `1aacd591…980c7c`, Image.gz `7554995d…b94622`.
WALK×8/MAPPING×2/POKE implícito en los tres (perfil L0 completo en verde;
el conteo fino MAPPING×15 lo re-verifica G3 del repack).

## 4. Repack (SIN flash) + sha

Scripts `repack-k52L4{abc}.py` (clon k52L0: G0 apunta al árbol propio, G3 con
perfil por peldaño + testigos propios, G2/G6 = cmdline byte-idéntica a k64
580 B, G4/G5/G7/G8 iguales). Sintaxis OK ×3. Invocación prevista (PC, sin flash):
`repack-k52L4x.py --dsid --out boot-uke-k52L4x.img --kernel <Image.gz L4x>`
`--cmdline-append '<10 tokens k64>' --cmdline-require 'msm.uke_gmu_shared=0,arm_smmu.uke_kgsl_keep=0'`
(require-2: elección propia documentada; el gate real es G6 byte-identidad).
Ejecutados 9-oct ~23:1x (PC, SIN flash), G0–G8 verdes ×3:
- L4a `boot-uke-k52L4a.img` 100663296 B sha256
  `2a736ec72b3f3e8a88650b0db4f9071575f17ccaf9dba4b8759205cb4713967d`
  (G3: crudo 41490944 B, POKE=113, cpio @35402360 = k52b2, cmdline = k64).
- L4b `boot-uke-k52L4b.img` sha256
  `781f7f9d9fe2977373e93035067ca25fc72b3ac1e82405f5bf06b1df7d4b9a24`
  (idem G3 con testigo poll).
- L4c `boot-uke-k52L4c.img` sha256
  `cd3af08415695a2c3e636b89d77a2cb9d57c3fbea9770b946220dd062af46849`
  (idem G3 con testigo D3).

## 5. Filas ledger (REDACTADAS, sin ejecutar; tablet no se toca)

Formato #561. Presupuesto: #561 gastó la nº9 (7º override); L1–L3 reclaman las
siguientes en su orden → números L4 **a coordinar**, propuestos nº10/11/12
(8º/9º/10º override). Orden de flash propuesto: L4a → L4b → L4c (de menos a
más riesgo predicho). Pre-flash (coordinador): batería ≥3700 mV, slots,
lector ACM rearmado, k52b2-intercalado, pstore+ACM, n≥2 si calla.

### #56X — L4a PRE-REGISTRO (L0+D2-solo)
Artefacto `boot-uke-k52L4a.img` sha256
`2a736ec72b3f3e8a88650b0db4f9071575f17ccaf9dba4b8759205cb4713967d`
(repack G0–G8 verdes;
cmdline 580 B = k64; perfil L0 + `UKE-K68: D2…`×1 + `SIN-D1…`×1; sin
D1/D3/poll/G10/G8/C1/familia). Variable vs L0: solo hub 200M. Criterios:
Habla ⇒ D2 inocuo en solitario. Calla con testigos D2 ⇒ D2 mata solo.
Calla sin testigos ⇒ muerte pre-código igual que k65–k70 (D2 no rescata).

### #56X — L4b PRE-REGISTRO (L0+poll-vendor; G10/G8 N/A-sobre-L0)
Artefacto `boot-uke-k52L4b.img` sha256
`781f7f9d9fe2977373e93035067ca25fc72b3ac1e82405f5bf06b1df7d4b9a24`
(perfil L0 + testigo poll
×1; G10/G8 ausentes por diseño, ver §2). Variable vs L0: solo criterio poll
fijo vendor. Criterios: Habla ⇒ poll-vendor inocuo. Calla ⇒ el criterio
vendor mata en este SoC (reabrir rama warm/babeface).

### #56X — L4c PRE-REGISTRO (L0+D3-solo; riesgo predicho por autopsia W3)
Artefacto `boot-uke-k52L4c.img` sha256
`cd3af08415695a2c3e636b89d77a2cb9d57c3fbea9770b946220dd062af46849`
(perfil L0 + testigo D3 ×1;
sin D1/D2). Variable vs L0: solo voto CX-OPP 220M. Criterios: Habla ⇒ D3
inocuo solo (autopsia W3 refutada, reabrir vía D3). Calla ⇒ autopsia
confirmada por medida directa (D3 aborta en resume).

## 6. Incidencias

- Generador de scripts con `x.upper()` escribió `k52-LA-tree` en comentarios/SRC
  (3 ficheros); cazado por `grep` antes de lanzar, corregido con `sed`.
  Idem `k52-L4A-tree` en G0 de los repacks; corregido pre-ejecución.
  Los builds corrieron contra los árboles correctos (ver SRC en §3 + G0 verde).
- Falsa alarma K43-en-L1: el diff en pantalla sugería doble-backslash en
  `build-k52L1.sh`; `od -c` demuestra 1 sola barra en L0, L1 y L4a/b/c.
  Causa: duplicado de barras de la capa de visualización. Sin bug; no se tocó
  el fichero del gemelo.
- Diffs manuales iniciales con `@@` mal contados (`patch: malformed`);
  regenerados con `diff -u` tras aplicar por ancla única en Python.
- Carga 22 en 16c durante los builds (gemelos compilando L1–L3 a la vez);
  `-j2` ×3 aguantó sin OOM (5–8 GB libres). Sin prisa y sin errores.
- Tablet: cero comandos `fastboot/adb` en toda la sesión; solo lectura del
  ledger hermano (#561) y de `boot-uke-k64-vendorcfg.img` (cmdline, PC).
