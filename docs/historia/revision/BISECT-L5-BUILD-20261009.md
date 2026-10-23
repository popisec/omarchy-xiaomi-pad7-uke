# BISECT-L5-BUILD — combinación L0 + D1 + D2 + D3 (≈ k65 sin K64/C1/poll), SIN flashear — 2026-10-09

> Solo PC. Tablet en fastboot (slots 5:6, batt 3884, aviso 9-oct ~23:43);
> PROHIBIDO flashear/tocarla — encargo solo-PC: repack + fila redactados SIN
> ejecutar. El coordinador flashea. Fichero NUEVO; gemelos y sus árboles,
> copias y ficheros, NI tocados NI leídos para escribir.
> Estado: §1–§2 cerradas y VERIFICADAS en binario (build OK 9-oct 23:57:33,
> `DONE L5-BUILD-OK`); §3–§4 redactados con G3-L5 obligatorio (repack NO ejecutado).

## 0. Definición

- L5 = L0 + D1 + D2 + D3 juntos (≈ k65 SIN K64, sin C1, sin poll-vendor,
  sin G10/G8). Si L0–L4 hablan todos (#561–#567: K64/D1/C1/D2/poll/D3
  inocentes por separado), L5 mide la interacción: habla ⇒ ni siquiera la
  combinación mata (el asesino está en lo COMÚN); calla con los 3 testigos ⇒
  combinación culpable; calla sin testigos ⇒ muerte pre-código.
- 1 flash = 1 variable; SIN repack ejecutado con flash, SIN flash en este fichero.

## 1. Combinación de los 3 diffs (CERRADA — dry-run limpio FWD + REV)

- Orígenes (los 3 son 1-hunk sobre `a6xx_gmu.c`, sitio H2-gx):
  `build/gates/patches/k52L2-d1solo.diff` (`@@ -1828`, D1 core 220M),
  `build/gates/patches/k52L4a-d2solo.diff` (`@@ -1789`, D2 hub 200M),
  `build/gates/patches/k52L4c-d3solo.diff` (`@@ -1792`, D3 OPP 220M).
- SOLAPE REAL D1⊕D2 (verificado, no supuesto): ambos borran las MISMAS 2
  líneas stock (`clk_set_rate(core,200M)` + `hub-condicional`) — ver minus
  idénticos con `grep '^-\tclk_set_rate'`. Prueba: D2-original aplica sobre
  L0-stock (dry-run OK); D1-original TRAS D2 aplicado → `Hunk #1 FAILED at
  1828`. D3 es compatible (no borra rates: conserva stock y añade el OPP
  después; su contexto igual caduca tras la fusión, por eso tampoco se
  concatena). Conclusión: los 3 diffs NO se concatenan; se fusionan.
- Árbol propio: `cp -a k52-L0-tree k52-L5-tree` (solo rutas `*L5*`, cero
  escrituras fuera). Edición = 1 hunk fusionado `@@ -1787,12 +1787,26 @@`:
  bloque `core220M + hub200M + OPP220M + pr_flush`, con los 3 testigos
  discriminadores VERBATIM (`UKE-L2: D1…`, `UKE-K68: D2…`, `UKE-K65: D3…`).
  Las líneas `SIN-D2/SIN-D1/SIN-D3` de los diffs-solo se ELIMINAN por falsas
  en combinación (declarado en el comentario del hunk).
- Versionado como `build/gates/patches/k52L5-d1d2d3.diff` (generado por
  `diff -U4` L0→L5, no escrito a mano). Verificado: FWD
  (`patch -p1 --dry-run` sobre réplica L0-stock en /tmp: OK) y REVERSO
  (`patch -R --dry-run` sobre mi árbol: OK).
- Fuente limpia: 3 positivos ×1; negativos específicos ×0
  (`UKE-K65: D1/D2`, `UKE-K66:`, `UKE-K67:`, `SIN-D2/SIN-D3/SIN-D1`,
  `K68-GENERAL_10/G8/poll`, `UKE-C1/K70/C3/L1/K64`, `register_config`,
  `s3_stage/rescue`, `poll vendor`). Únicos `GENERAL_10` en fuente: macros
  mainline `REG_A{7,8}XX_GMU_GENERAL_10` (idénticas en L0, no testigos).

## 2. Build (CERRADO — OK 9-oct 23:57:33, `DONE L5-BUILD-OK`)

- Script: `docs/historia/gates-palawan/build-k52L5.sh` (clon de `build-k52L2.sh`; rutas
  `k52-L5-tree/k52L5-build/k52L5-bateria.config/build-k52L5.log`; must +K17
  +3 L5; mustnt V2-L5 — se RETIRAN los genéricos `D1 gmu/D2 hub/UKE-K65:/
  UKE-K68:` porque los testigos L5 los contienen; el D ajeno lo cubren
  `UKE-K65: D1/D2`, `UKE-K66:`, `UKE-K67:`, `SIN-*`, `K68-G10/G8/poll`;
  `DONE L5-BUILD-OK`). K43 single-backslash verificado a nivel de byte
  (must `b'\x013UKE-POKE'` ×1, mustnt `b'\x014UKE-POKE'` ×1).
- Config: `build/kernel-config/k52L5-bateria.config` = bytes de L0 (`cmp` OK;
  INITRAMFS_SOURCE → cpio K34-fw 6-oct con fw GPU dentro).
- Lanzado 9-oct 23:45 desprendido (`-j4`; el make en primer plano es no-op
  conocido). Compilación real 23:45:10→23:57:33 (~12 min).

### 2.1 Verificación (EJECUTADA de verdad sobre el binario — TODO OK)

- V1. Gates del propio script (`build/logs/build-k52L5.log` l.4779–4817):
  Image 41490944 B + nuevo que .config; 31× `GATE OK` (perfil L0 l.4780–4806
  + `UKE-K17` l.4807 + L5 ×3 l.4808–4810 + K43 l.4797 con byte `01` real);
  cero `FALTA/AUN ESTA/ABORT` (el script habría abortado por `set -e`/`fail`).
- V2. `sha256sum`: Image `3751c974…fdf8`, Image.gz `e6dc39bc…b184`;
  cpio embebido `ebc2de46…bc` = cpio 6-oct de BISECT-L0 §3.2 R5 ✓.
- V3. Re-verificación independiente (no solo el script): tamaño
  L5=L0=L2=L4a=L4c=41490944 B exactos; POKE=113, K19=21, WALK=8, MAPPING=15;
  K43 err ×1, warn ×0; testigos L5 ×1 c/u (D1/D2/D3), K17 ×1; los 25
  negativos V2-L5 ×0 todos; banner idéntico
  (`7.2.0-rc2-palawan (uke@palawan) (clang 23.1.1, LLD 23.1.1)`).
  Cruce L2↔L5: L2 = D1 ×1 + D2 ×0 + D3 ×0; L5 = D1 ×1 + D2 ×1 + D3 ×1 ⇒
  **L5 declarado == L2 + D2 + D3** (y == L0 + D1 + D2 + D3).

## 3. Repack + flash + ledger (REDACTADOS, sin ejecutar)

- Repack (PC, permitido pero NO ejecutado hasta V1–V3 OK — y SIGUE sin
  ejecutar por encargo solo-PC): clonado a `docs/historia/gates-palawan/repack-k52L5.py`
  con G3-L5 (G0 apunta a `k52-L5-tree`; G3 = perfil k52b2
  POKE=113/K13=11/K16/P82≥20/S0/K18 + K19×21/K17×1/WALK×8/MAPPING×15 + 3
  testigos L5 ×1 + 30 negativos V2-L5; G2/G6 = cmdline byte-idéntica a k64
  580 B, G4/G5/G7/G8 iguales). Sintaxis verificada (`py_compile` OK).
  Invocación prevista (PC, sin flash, la ejecuta el coordinador):
  `python3 docs/historia/gates-palawan/repack-k52L5.py --dsid --out boot-uke-k52L5.img
  --kernel build/kernel-pokes/k52L5-build/arch/arm64/boot/Image.gz
  --cmdline-append '<10 tokens k64>' --cmdline-require
  'msm.uke_gmu_shared=0,arm_smmu.uke_kgsl_keep=0'`
  (require-2: elección propia heredada de L4; el gate real es G6 byte-identidad).
  Sin ese repack ejecutado con G0–G8 verdes, NO hay flash.
- Flash: PROHIBIDO en este turno (solo-PC). Cuando toque (otro turno,
  coordinador, tablet ya en fastboot): 1 flash = 1 variable,
  k52b2-intercalado antes/después, pstore ADEMÁS de ACM, n≥2 si calla,
  retry+batería registrados (BISECT-L0 §4). Rollback en disco:
  `boot-uke-k52L0.img`.
- Fila ledger (hermano `~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md`,
  REDACTADA, no escrita — no hay artefacto que pre-registrar: el repack no se ejecutó):
  `#56X? L5 = L0+D1+D2+D3 | boot-uke-k52L5.img <sha-tras-repack-G0-G8> |
  combinacion ≈ k65-sin-K64 (SIN C1/poll/G10/G8) | ACM+pstore, n≥2 si calla |
  Habla ⇒ ni la combinacion mata (asesino en lo COMUN). Calla con 3 testigos ⇒
  combinacion culpable. Calla sin testigos ⇒ muerte pre-codigo |
  pre-registro ANTES del flash, nunca despues`.

## 4. Ficheros (solo rutas propias; árboles ajenos intactos)

- NUEVOS: `build/gates/patches/k52L5-d1d2d3.diff`,
  `docs/historia/gates-palawan/build-k52L5.sh`, `docs/historia/gates-palawan/repack-k52L5.py` (redactado,
  sin ejecutar), `build/kernel-config/k52L5-bateria.config` (= L0),
  `build/kernel-pokes/k52-L5-tree/` (gitignored) y `k52L5-build/` (+ este informe).
- `git status`: solo untracked nuevos (los `*L3*/*L4*` listados son de los
  gemelos; no tocados). Tablet no tocada; ningún árbol ajeno modificado.
