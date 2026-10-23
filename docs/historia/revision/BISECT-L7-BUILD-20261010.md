# BISECT-L7-BUILD — L6 + 7 pokes UKE-L7 en el tramo K44→S3, SIN flashear — 2026-10-10

> Solo PC. PROHIBIDO flashear/tocar la tablet — encargo solo-PC: árbol + diff
> + build + repack redactado SIN ejecutar + fila ledger redactada SIN escribir.
> El coordinador flashea. Fichero NUEVO; gemelos y sus árboles, copias y
> ficheros, NI tocados NI leídos para escribir.
> Estado: §1–§2 cerradas y VERIFICADAS en binario (build OK 10-oct 01:21:49,
> `DONE L7-BUILD-OK`); §3–§4 redactados con G3-L7 obligatorio (repack NO ejecutado).

## 0. Definición

- L7 = L6 + 7 pokes `UKE-L7` (uke_poke + pr_err + pr_flush(120,false)) en el
  tramo `K44→S3` de `a6xx_gmu_start()`, donde la traza ACM del L6 muere: el
  resume llega a `UKE-K44 A: rst=1 bootcfg=2 cfg=0x4052 initres=0` y calla
  antes de `S3-rst0`.
- 1 flash = 1 variable; SIN repack ejecutado con flash, SIN flash en este fichero.
- Lectura prevista: el ÚLTIMO `UKE-L7:` visible en la ACM nombra el punto del
  cuelgue (k44b-ok/k44c-ok/k44d-ok/k44e-ok/k25-ok/pre-rst/post-rst).
  Discriminador write-vs-poll: `pre-rst` sale + `post-rst` no ⇒ mata el
  `gmu_write(SYSRESET,0)`; `post-rst` sale + `S4` no ⇒ mata el poll S4;
  `k44X-ok` ausente ⇒ mata la lectura K44-X (bus colgado en ese registro).

## 1. Los 7 pokes (CERRADA — dry-run limpio FWD + REV)

- Árbol propio: `cp -a k52-L6-tree k52-L7-tree` (solo rutas `*L7*`, cero
  escrituras fuera). 7 inserciones en `drivers/gpu/drm/msm/adreno/a6xx_gmu.c`
  (ya traía `uke-poke.h` por L6: sin includes nuevos), cada una
  `uke_poke + pr_err + pr_flush`:
  - tras K44-B (`L7-k44b`), tras K44-C (`L7-k44c`), tras K44-D (`L7-k44d`),
    tras K44-E (`L7-k44e`, conservando el `pr_flush` K44 previo: flush antes
    y después de E);
  - tras el bloque K25 (`L7-k25ok`, después de `uke_poke("K19-dumpOK")`);
  - ANTES del `gmu_write(SYSRESET,0)` (`L7-pre-rst`);
  - ENTRE el write y el poke S3 (`L7-post-rst`).
- Versionado como `build/gates/patches/k52L7-s2s3.diff` (generado por
  `diff -U4` L6→L7, no escrito a mano; 1 fichero, 2 hunks). Verificado:
  FWD (`patch -p1 --dry-run` en `k52-L6-tree`: OK) y REVERSO
  (`patch -p1 -R --dry-run` en `k52-L7-tree`: OK).

## 2. Build (CERRADO — OK 10-oct 01:21:49, `DONE L7-BUILD-OK`)

- Script: `docs/historia/gates-palawan/build-k52L7.sh` (clon de `build-k52L6.sh`; rutas
  `k52-L7-tree/k52L7-build/k52L7-bateria.config/build-k52L7.log`; must = perfil
  L0 + K17 + 3 L5 + 11 L6 + 7 L7; mustnt V2-L5 intacto — `UKE-L1` no colisiona
  con `UKE-L7:`; `DONE L7-BUILD-OK`).
- Config: `build/kernel-config/k52L7-bateria.config` = bytes de L6 (`cmp` OK;
  INITRAMFS_SOURCE → cpio K34-fw 6-oct con fw GPU dentro).
- Lanzado 10-oct 01:07:56 desprendido (`-j4`). Compilación real
  01:08:01→01:21:49 (~14 min).

### 2.1 Verificación (EJECUTADA de verdad sobre el binario — TODO OK)

- V1. Gates del propio script (`build/logs/build-k52L7.log` l.4780–4828):
  Image 41490944 B + nuevo que .config; 49× `GATE OK` (perfil L0 + K17 + L5
  ×3 + L6 ×11 + L7 ×7, cada L7 ×1); cero `FALTA/AUN ESTA/ABORT` (`set -e`/`fail`
  habrían abortado). K43 byte-level OK (puerta del script en verde).
- V2. `sha256sum`: Image `de482567…3f114d9`, Image.gz `773a973b…71523f`;
  cpio embebido `ebc2de46…bc` = cpio 6-oct de BISECT-L0 §3.2 R5 ✓.
- V3. Re-verificación independiente: tamaño L7=L6=L5=41490944 B exactos;
  POKE=113 (= L6: los 7 uke_poke nuevos NO lo mueven, el conteo no es por
  call-site — medido, no supuesto); K19=21, K17=1, WALK=8, MAPPING=15,
  K13=11; D1/D2/D3 ×1 c/u; `UKE-L6:` ×11 total; `UKE-L7:` ×7 total;
  tags `L6-*` ×1 c/u (11/11) y `L7-*` ×1 c/u (7/7: k44b/k44c/k44d/k44e/
  k25ok/pre-rst/post-rst); los 30 negativos V2-L5 ×0 todos.

## 3. Repack + flash + ledger (REDACTADOS, sin ejecutar)

- Repack (PC, permitido pero NO ejecutado — y SIGUE sin ejecutar por encargo
  solo-PC): clonado a `docs/historia/gates-palawan/repack-k52L7.py` con G3-L7 (G0 apunta a
  `k52-L7-tree` y vigila las mismas 9 fuentes que L6 — el único fichero que
  cambia L6→L7 es `a6xx_gmu.c`, ya vigilado; G3 = perfil k52b2
  POKE=113/K13=11/K16/P82≥20/S0/K18 + K19×21/K17×1/WALK×8/MAPPING×15 + 3
  testigos L5 ×1 + 11 UKE-L6 ×1 + 7 UKE-L7 ×1 + 30 negativos V2-L5; G2/G6 =
  cmdline byte-idéntica a k64 580 B, G4/G5/G7/G8 iguales). Sintaxis verificada
  (`py_compile` OK). POKE=113 confirmado en el binario L7 real (§2.1 V3), no
  supuesto.
  Invocación prevista (PC, sin flash, la ejecuta el coordinador):
  `python3 docs/historia/gates-palawan/repack-k52L7.py --dsid --out boot-uke-k52L7.img
  --kernel build/kernel-pokes/k52L7-build/arch/arm64/boot/Image.gz
  --cmdline-append '<10 tokens k64>' --cmdline-require
  'msm.uke_gmu_shared=0,arm_smmu.uke_kgsl_keep=0'`
  (require-2 heredado de L4/L5/L6; el gate real es G6 byte-identidad).
  Sin ese repack ejecutado con G0–G8 verdes, NO hay flash.
- Flash: PROHIBIDO en este turno (solo-PC). Cuando toque (otro turno,
  coordinador, tablet ya en fastboot): 1 flash = 1 variable,
  k52b2-intercalado antes/después, pstore ADEMÁS de ACM, n≥2 si calla,
  retry+batería registrados (BISECT-L0 §4). Rollback en disco:
  `boot-uke-k52L0.img`.
- Fila ledger (hermano `~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md`,
  REDACTADA, no escrita — no hay artefacto que pre-registrar: el repack no se ejecutó):
  `#56X? L7 = L6+7 pokes UKE-L7 tramo K44→S3 | boot-uke-k52L7.img <sha-tras-repack-G0-G8> |
  k44b/c/d/e-ok + k25-ok + pre/post-rst, pr_err+flush (ACM) |
  ACM+pstore, n≥2 si calla | Ultimo UKE-L7 visible = punto del cuelgue.
  pre-rst sin post-rst ⇒ mata el write SYSRESET=0. post-rst sin S4 ⇒ mata el poll.
  Sin ningun UKE-L7 nuevo (solo K44-A) ⇒ mata la lectura K44-B (ITCM) |
  pre-registro ANTES del flash, nunca despues`.

## 4. Ficheros (solo rutas propias; árboles ajenos intactos)

- NUEVOS: `build/gates/patches/k52L7-s2s3.diff`,
  `docs/historia/gates-palawan/build-k52L7.sh`, `docs/historia/gates-palawan/repack-k52L7.py` (redactado,
  sin ejecutar), `build/kernel-config/k52L7-bateria.config` (= L6),
  `build/kernel-pokes/k52-L7-tree/` (gitignored) y `k52L7-build/` (+ este informe).
- `git status`: solo untracked nuevos propios (+ untracked previos ajenos a
  este turno: L3/L4, k69, cpio init — anteriores a mi sesión). Única
  modificación tracked (`build/bootimg/repack-k18-report.txt`) es PREVIA y
  ajena. `boot-uke-k52L7.img` NO existe (repack sin ejecutar). Tablet no
  tocada (cero adb/fastboot en este turno); ningún árbol ajeno modificado.
