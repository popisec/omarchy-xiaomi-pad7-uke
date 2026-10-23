# BISECT-L6-BUILD — L5 + 11 pokes UKE-L6 en el tramo ciego, SIN flashear — 2026-10-10

> Solo PC. PROHIBIDO flashear/tocar la tablet — encargo solo-PC: árbol + diff
> + build + repack redactado SIN ejecutar + fila ledger redactada SIN escribir.
> El coordinador flashea. Fichero NUEVO; gemelos y sus árboles, copias y
> ficheros, NI tocados NI leídos para escribir.
> Estado: §1–§2 cerradas y VERIFICADAS en binario (build OK 10-oct 00:54:46,
> `DONE L6-BUILD-OK`); §3–§4 redactados con G3-L6 obligatorio (repack NO ejecutado).

## 0. Definición

- L6 = L5 + 11 pokes `UKE-L6` (pr_err + pr_flush(120,false) + uke_poke) en el
  tramo ciego `msm_open → load_gpu → adreno_load_gpu → … → a6xx_gmu_resume`,
  donde L5 cuelga en duro al abrir /dev/dri/card0 sin dejar ni un testigo
  (H1-rpm nunca salió: uke_poke sin flush no sobrevive al cuelgue en la ACM).
- 1 flash = 1 variable; SIN repack ejecutado con flash, SIN flash en este fichero.
- Lectura prevista: el ÚLTIMO `UKE-L6:` visible en la ACM nombra el punto del
  cuelgue (fw-enter/fw-exit-ok/ucode-enter/ucode-exit-ok/rpm-enter/rpm-exit-ok/
  hwinit-enter/gmu-pm-resume-enter/pm-resume-enter/gmu-resume-enter;
  open-enter como centinela de entrada).

## 1. Los 11 pokes (CERRADA — dry-run limpio FWD + REV)

- Árbol propio: `cp -a k52-L5-tree k52-L6-tree` (solo rutas `*L6*`, cero
  escrituras fuera). 11 inserciones, cada una `uke_poke + pr_err + pr_flush`:
  - `msm_drv.c`: include `uke-poke.h` + `L6-open` (entrada de msm_open).
  - `adreno/adreno_gpu.c`: include `uke-poke.h` + `L6-fw-in` (entrada de
    adreno_load_fw) + `L6-fw-ok` (salida, tras el bucle de request_fw).
  - `adreno/adreno_device.c` (ya traía uke-poke.h): `L6-ucode-in/ok` alrededor
    de `gpu->funcs->ucode_load` + `L6-rpm-in/ok` alrededor de
    `pm_runtime_get_sync` (ok solo en camino de éxito, tras el `ret < 0`).
  - `msm_gpu.c`: include `uke-poke.h` + `L6-hwinit-in` (primera línea de
    msm_gpu_hw_init, antes del WARN_ON).
  - `adreno/a6xx_gpu.c`: `L6-gmupm` (entrada de a6xx_gmu_pm_resume) +
    `L6-pm` (entrada de a6xx_pm_resume) = discriminador de qué vía corre.
  - `adreno/a6xx_gmu.c`: `L6-gmures` (entrada de a6xx_gmu_resume ANTES del
    `WARN(!initialized)` y del primer `pm_runtime_get_sync(gmu->dev)`).
- Versionado como `build/gates/patches/k52L6-openpokes.diff` (generado por
  `diff -U4` L5→L6 sobre `drivers/gpu/drm/msm`, no escrito a mano; 6 ficheros,
  11 hunks). Verificado: FWD (`patch -p1 --dry-run` sobre réplica de los 6
  ficheros L5-stock en /tmp: OK) y REVERSO (`patch -R --dry-run` sobre mi
  árbol: OK).

## 2. Build (CERRADO — OK 10-oct 00:54:46, `DONE L6-BUILD-OK`)

- Script: `docs/historia/gates-palawan/build-k52L6.sh` (clon de `build-k52L5.sh`; rutas
  `k52-L6-tree/k52L6-build/k52L6-bateria.config/build-k52L6.log`; must = perfil
  L0 + K17 + 3 L5 + 11 L6; mustnt V2-L5 intacto — `UKE-L1` no colisiona con
  `UKE-L6:`; `DONE L6-BUILD-OK`).
- Config: `build/kernel-config/k52L6-bateria.config` = bytes de L5 (`cmp` OK;
  INITRAMFS_SOURCE → cpio K34-fw 6-oct con fw GPU dentro).
- Lanzado 10-oct 00:41:41 desprendido (`-j4`). Compilación real
  00:41:46→00:54:46 (~13 min).

### 2.1 Verificación (EJECUTADA de verdad sobre el binario — TODO OK)

- V1. Gates del propio script (`build/logs/build-k52L6.log` l.4779–4821):
  Image 41490944 B + nuevo que .config; 42× `GATE OK` (perfil L0 + K17 + L5
  ×3 + L6 ×11, cada L6 ×1); cero `FALTA/AUN ESTA/ABORT` (`set -e`/`fail`
  habrían abortado). K43 byte-level OK (err ×1 l.4797, warn ×0).
- V2. `sha256sum`: Image `6ee4ce19…7af83f`, Image.gz `cad2ca50…eb0c61eb0`;
  cpio embebido `ebc2de46…bc` = cpio 6-oct de BISECT-L0 §3.2 R5 ✓.
- V3. Re-verificación independiente: tamaño L6=L5=41490944 B exactos;
  POKE=113 (= L5: los 11 uke_poke nuevos NO lo mueven, el conteo no es por
  call-site — medido, no supuesto); K19=21, K17=1, WALK=8, MAPPING=15,
  K13=11; D1/D2/D3 ×1 c/u; `UKE-L6:` ×11 total; tags `L6-*` ×1 c/u (11/11);
  los 30 negativos V2-L5 ×0 todos.

## 3. Repack + flash + ledger (REDACTADOS, sin ejecutar)

- Repack (PC, permitido pero NO ejecutado — y SIGUE sin ejecutar por encargo
  solo-PC): clonado a `docs/historia/gates-palawan/repack-k52L6.py` con G3-L6 (G0 apunta a
  `k52-L6-tree` y vigila 9 fuentes: las 4 de L5 + las 5 tocadas por L6 —
  a6xx_gpu/adreno_device/adreno_gpu/msm_drv/msm_gpu; G3 = perfil k52b2
  POKE=113/K13=11/K16/P82≥20/S0/K18 + K19×21/K17×1/WALK×8/MAPPING×15 + 3
  testigos L5 ×1 + 11 UKE-L6 ×1 + 30 negativos V2-L5; G2/G6 = cmdline
  byte-idéntica a k64 580 B, G4/G5/G7/G8 iguales). Sintaxis verificada
  (`py_compile` OK).
  Invocación prevista (PC, sin flash, la ejecuta el coordinador):
  `python3 docs/historia/gates-palawan/repack-k52L6.py --dsid --out boot-uke-k52L6.img
  --kernel build/kernel-pokes/k52L6-build/arch/arm64/boot/Image.gz
  --cmdline-append '<10 tokens k64>' --cmdline-require
  'msm.uke_gmu_shared=0,arm_smmu.uke_kgsl_keep=0'`
  (require-2 heredado de L4/L5; el gate real es G6 byte-identidad).
  Sin ese repack ejecutado con G0–G8 verdes, NO hay flash.
- Flash: PROHIBIDO en este turno (solo-PC). Cuando toque (otro turno,
  coordinador, tablet ya en fastboot): 1 flash = 1 variable,
  k52b2-intercalado antes/después, pstore ADEMÁS de ACM, n≥2 si calla,
  retry+batería registrados (BISECT-L0 §4). Rollback en disco:
  `boot-uke-k52L0.img`.
- Fila ledger (hermano `~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md`,
  REDACTADA, no escrita — no hay artefacto que pre-registrar: el repack no se ejecutó):
  `#56X? L6 = L5+11 pokes UKE-L6 tramo ciego | boot-uke-k52L6.img <sha-tras-repack-G0-G8> |
  open/fw/ucode/rpm/hwinit/pm-disc/gmures-preWARN, pr_err+flush (ACM) |
  ACM+pstore, n≥2 si calla | Ultimo UKE-L6 visible = punto del cuelgue.
  gmures-enter sin H1-rpm ⇒ muere en pm_runtime_get_sync(gmu->dev).
  Sin ningun UKE-L6 ⇒ muere antes de adreno_load_fw (open/load_gpu) |
  pre-registro ANTES del flash, nunca despues`.

## 4. Ficheros (solo rutas propias; árboles ajenos intactos)

- NUEVOS: `build/gates/patches/k52L6-openpokes.diff`,
  `docs/historia/gates-palawan/build-k52L6.sh`, `docs/historia/gates-palawan/repack-k52L6.py` (redactado,
  sin ejecutar), `build/kernel-config/k52L6-bateria.config` (= L5),
  `build/kernel-pokes/k52-L6-tree/` (gitignored) y `k52L6-build/` (+ este informe).
- `git status`: solo untracked nuevos propios. Única modificación tracked
  (`build/bootimg/repack-k18-report.txt`, 00:05) es PREVIA y ajena a este
  turno (mi sesión empezó 00:39; ningún repack ejecutado por mí). Tablet no
  tocada; ningún árbol ajeno modificado.
