# PLAN-C3 — ENABLES DIFERIDOS TRAS USB (2026-10-09, solo PC, sin flashear)

> Solo PC: diseño + diff C3 versionado con dry-run. PROHIBIDO flashear/tocar la
> tablet (colgada en k70; 8 escrituras hoy). NO compilado aquí: el build lo hará
> el coordinador. Estado: DISEÑO + DIFF k71-c3-defer LISTOS, PENDIENTES DE
> DRY-RUN (§5). Punto de partida: base+K64+C1+D1 (árbol k70) + PLAN-C §C3.

## 0. Veredicto anticipado: C3 es viable (no hace falta alternativa)

k52b2 es la prueba de existencia: arranca siempre a USB/SSH con la GPU dormida
en rates XBL. Su mecanismo es un **fallo gracioso del resume** (escala K61,
`uke_s3_stage=0` → `a6xx_gmu_start` devuelve `-EAGAIN` antes de S3 →
`adreno_load_gpu` devuelve NULL → `priv->gpu=NULL` → el boot sigue sin GPU).
C3 reproduce ese mismo estado final, pero **una etapa antes** (a la entrada del
`pm_resume`, sin tocar ni siquiera los dominios CX/GX) y añade el bring-up
manual con USB vivo. No hay inviabilidad conceptual; el §4 recoge de todos
modos qué significa cada desenlace, incluido "C3 también calla".

## 1. Punto exacto del stub (fichero:línea, chip 0x43030b00)

Cadena de llamadas verificada en k52-tree (uke = `0x43030b00` → `a6xx_catalog.c:1618`,
`.funcs = &a7xx_gpu_funcs` → `a6xx_gpu.c:2874-2875` `.pm_resume = a6xx_gmu_pm_resume`):

```
msm_open → load_gpu → adreno_load_gpu (adreno_device.c:69)
  → pm_runtime_get_sync(&pdev->dev)
    → adreno_runtime_resume (adreno_device.c:323)
      → a6xx_gmu_pm_resume (a6xx_gpu.c:2132)          ← STUB AQUÍ
        → a6xx_gmu_resume (a6xx_gmu.c:2290)
          → [C1 voto] → [D1 220M] → enables → secure_init
          → a6xx_gmu_fw_start (a6xx_gmu.c:1892)
            → [G10/G8 chipid] → P3 power_config → K64 register_config (:2016)
            → env_probe (:2020) → a6xx_gmu_start (S0..S4) → hfi_start
```

- **Único caller de `a6xx_gmu_resume`**: `a6xx_gpu.c:2144`. El camino wrapper
  (`a6xx_pm_resume`, sin `a6xx_gmu_resume`) no aplica al 732 (su compatible GMU
  `qcom,adreno-gmu-732.0` no es `qcom,adreno-gmu-wrapper`, `a6xx_gpu.c:2711`).
- **El stub va en la PRIMERA línea útil de `a6xx_gmu_pm_resume`** (`a6xx_gpu.c`,
  tras `int ret;`, antes de `gpu->needs_hw_init = true;`): si `uke_c3_defer != 0`,
  `pr_err` + `pr_flush` + `uke_poke("C3-defer")` y `return -EAGAIN`. Sin locks
  (`gmu.lock` ni se toma), sin `pm_runtime_get_sync(gmu->dev)`, sin `gxpd_get`,
  sin tracepoint: invisible a todos los subsistemas.
- **Cobertura del stub**: todo lo que k65–k70 añadieron al camino caliente queda
  DESPUÉS del punto de corte y por tanto NO ejecuta en diferido: C1 (voto RDPM),
  D1 (core 220M), `clk_bulk_prepare_enable`, K64 (`fw_start:2016`), env_probe,
  G10/G8, S0–S4, HFI. El `bind` (`adreno_bind` → `a6xx_gpu_init` → `a6xx_gmu_init`)
  queda INTACTO a propósito (ver §3: fallar el bind mataría todo el DRM).
- `-EAGAIN` y no otro código: es el mismo que devuelve el stage0 de K61, luego
  el camino de unwind (`adreno_load_gpu:135-140` → NULL → `priv->gpu=NULL`) es
  el ya probado por k52b2 en cada boot. `adreno_runtime_resume` lo propaga tal
  cual (`adreno_device.c:326-329`); el núcleo de runtime-PM no lo reintenta solo:
  cada `open("/dev/dri/card0")` posterior reintenta `load_gpu` (base del trigger).
- Módulo sysfs/cmdline: todo `adreno-y` se enlaza en `msm.o` (`msm/Makefile:165,168`,
  `KBUILD_MODNAME="msm"`), luego los params viven en
  `/sys/module/msm/parameters/uke_c3_*` y en cmdline como `msm.uke_c3_*`
  (convención ya documentada en `a6xx_gmu.c:699`: `msm.uke_s3_stage=2`).
  Sin cmdline nueva: `uke_c3_defer` vale **1 por defecto** (fail-closed como K61);
  `msm.uke_c3_defer=0` en cmdline = boot control no-diferido.

## 2. Trigger manual: sysfs + workqueue (elegido sobre debugfs)

- **Por qué sysfs y no debugfs**: `CONFIG_DEBUG_FS=y` existe, pero el
  `debugfs_init` de adreno solo corre tras un `load_gpu` con éxito
  (`adreno_device.c:126-131`) —callejón sin salida si la GPU nunca sube— y
  debugfs puede no estar montado en la rootfs. Los `module_param` sysfs existen
  siempre, con permisos propios, y se descubren sin adivinar:
  `ls /sys/module/msm/parameters/ | grep uke_` (ahí ya vive `uke_s3_stage`).
- **ABI** (todo en `a6xx_gpu.c`, ~90 líneas con comentarios):
  - `uke_c3_defer` (0644, defecto 1): `echo 0 > .../uke_c3_defer` desarma; el
    siguiente `open` de card0 corre el camino REAL (fallback sin código nuevo).
  - `uke_c3_fire` (0644, `module_param_cb`): `echo 1 > .../uke_c3_fire` desarma
    Y ejecuta el bring-up en workqueue (réplica exacta de
    `adreno_load_gpu:107-124` menos fw —el fw ya quedó cargado en cada open
    fallido del boot, igual que un ciclo suspend/resume nunca recarga fw—:
    `pm_runtime_enable` si `disable_depth>0` + `pm_runtime_get_sync` (→ resume
    real con sus testigos Z4/H*/S*) + `msm_gpu_hw_init` bajo `gpu->lock`,
    ref PM RETENIDA para inspeccionar la GPU). `echo 0 > .../uke_c3_fire`
    con GPU arriba = `pm_runtime_put_sync` + re-arma `defer=1` (release).
    Workqueue y no inline: el `store` sysfs vuelve al instante y el operador
    mira `dmesg -w`; si el bring-up cuelga el bus, la sesión SSH que disparó
    no queda colgada dentro del write.
  - Estado interno `uke_c3_state` (0=armado, 1=disparando, 2=arriba, 3=hw-fail)
    + `uke_c3_gpu` (stash en `a6xx_gpu_init` antes de `return gpu;`, con
    `INIT_WORK` y banner `UKE-C3: ARMED`). Guardas: doble FIRE → "ignorado";
    FIRE sin bind → aborta con testigo; carrera FIRE vs `open` concurrente →
    benigna (runtime-PM serializa el resume, `gpu->lock` serializa `hw_init`,
    `needs_hw_init` lo hace idempotente).
- **Testigos con USB vivo** (todos `pr_err` + `pr_flush`, visibles por
  `dmesg` por SSH sin pstore ni lector ACM):
  - Boot diferido: `UKE-C3: ARMED` (bind) + un `UKE-C3: DEFER` por cada open
    (si hay tormenta de DEFERs = userspace reintentando = prueba de que el
    boot llegó a userspace, no un problema).
  - FIRE: `C3-firing` (poke) → `UKE-C3: FIRE` → `Z4-gmuresume` → `H1..H10`
    (incl. `H2-cxvoto`, `H3-clk`, `H6-rsc`, `H8-cm3`) → `S0..S4` → `G10/G8` →
    `UKE-C3: FIRE resume rc=` → `UKE-C3: FIRE hw_init rc=` + `C3-hwOK/FAIL`.
  - Procedimiento: SSH-A `dmesg -w | tee /tmp/c3-fire.log`; SSH-B
    `echo 1 > /sys/module/msm/parameters/uke_c3_fire`; la última línea antes
    del silencio localiza la fase asesina CON USB VIVO. Si cuelga: reset duro
    → pstore trae el último testigo (todos hacen `pr_flush`).

## 3. Riesgos: qué rompe arrancar sin GMU, y fallar-vs-fingir

- **DPU/pantalla**: NADA. El stub no toca el `bind`: `adreno_bind` devuelve 0
  como hoy (`a6xx_gpu_init` + `a6xx_gmu_init` intactos), `component_bind_all`
  completa, `msm_drm_kms_init` + DPU/DSI corren igual. Solo falta el
  acelerador: `priv->gpu=NULL` hasta el FIRE (igual que k52b2, que expone
  card0+renderD128 sin GPU). El compositor puede ir por CPU o quejarse en
  userspace; los gates de C3 son SSH + USB, no la pantalla.
- **¿Fallar el bind? NO.** Un `adreno_bind` con error aborta
  `component_bind_all` (`msm_drv.c:156-158` → `err_put_dev`): se pierde el DRM
  ENTERO (sin card0, sin KMS/display, sin camino de FIRE). C3 necesita el DRM
  vivo con la GPU ausente; eso solo lo da fallar tarde (open), no pronto (bind).
- **¿Fingir éxito (`return 0` con GMU apagado)? NO. Decisión: FALLAR con
  `-EAGAIN`.** Justificación en 4 puntos: (i) k52b2/stage0 prueban que el
  estado "resume-fallido-gracioso" bootea —el `return 0` fingido NO está
  probado por nada; (ii) con 0 fingido seguirían `msm_devfreq_resume`,
  `a6xx_llc_activate` y sobre todo `msm_gpu_hw_init → hw_init` (decenas de
  `gpu_write`/`gmu_write` sobre dominios apagados) = MMIO no probado que puede
  ser el mismo hang que perseguimos; (iii) `-EAGAIN` deja `needs_hw_init`
  pendiente, luego el FIRE recorre el camino 100% original (fidelidad máxima
  del diagnóstico); (iv) cada `open` reintenta, así el desarme solo ya es
  trigger (fallback sin código).
- **Riesgos residuales del diff** (~90L, solo `a6xx_gpu.c`): typo sin compilar
  (mitigado: dry-run §5 + incluye explícitos `module.h`/`printk.h`/`workqueue.h`/
  `pm_runtime.h`; `a6xx_gpu.c` hoy tiene 0 `pr_err`); `disable_depth` leído
  directo (campo público de `dev_pm_info`, válido con `CONFIG_PM`); tormenta
  de opens de userspace (solo spam de log, y además es evidencia); FIRE que
  cuelga el bus con SSH vivo (ES el experimento: capturar `dmesg -w` + pstore).
- **Límite honesto**: C3 no cubre un hang en el `bind` (`clocks_probe`,
  `memory_alloc`, `rpmh_init`, pokes G7/G8/G9) ni fuera de la GPU (DPU, clk,
  interconnect, repack). Si el boot C3 calla igual, el asesino es pre-resume
  (árbol de decisión en §4).

## 4. Recetas REDACTADAS sin ejecutar (las ejecuta el coordinador)

Diff versionado (archivo NUEVO, NO aplicado al tree):
`build/gates/patches/k71-c3-defer.diff` — toca SOLO
`drivers/gpu/drm/msm/adreno/a6xx_gpu.c` en 3 hunks: (1) includes C3 + bloque C3
tras `#define GPU_PAS_ID 13` (params `uke_c3_defer`/`uke_c3_fire`,
`uke_c3_fire_fn`, setter con `schedule_work` + release); (2) stub al inicio de
`a6xx_gmu_pm_resume`; (3) stash `uke_c3_gpu` + `INIT_WORK` + banner en
`a6xx_gpu_init`. Convención de paths `-p1` como `k70-planC-C2.diff`.

Build (clon de `build-k70.sh`, NO ejecutado aquí):

```bash
cp docs/historia/gates-palawan/build-k70.sh build/gates/build-k71.sh
# en build-k71.sh: s/K70/C3/ ; s/k70/k71/ ; O=k71-build ; SRC=k52-tree (ya lleva
# base+K64+C1+D1); el diff C3 se APLICA al tree antes del make:
#   patch -p1 --dry-run < build/gates/patches/k71-c3-defer.diff && \
#   patch -p1 < build/gates/patches/k71-c3-defer.diff   # dentro de k52-tree
# gates C3 (añadir a los de K70): UKE-C3, uke_c3_defer, uke_c3_fire, C3-defer,
# C3-hwOK ; mustnt: nada nuevo (no se tocan rates/votos).
./build/gates/build-k71.sh   # ~60 min, lo hace el coordinador
```

Verificación (gates, sin flashear):

```bash
grep -c 'UKE-C3' k71-tree.../a6xx_gpu.c      # 16 (diff trae 16)
grep -c 'module_param_cb' .../a6xx_gpu.c     # 1
grep -c 'schedule_work' .../a6xx_gpu.c       # 1
# Image ~41 MB + sha256 al ledger; strings Image | grep -c UKE-C3 (16)
```

Repack + flash (mañana, 1 slot = escritura nº9: requiere override del dueño,
presupuesto de hoy agotado en 8):

```bash
cp docs/historia/gates-palawan/repack-k70.py build/gates/repack-k71.py  # s/k70/k71/
# cmdline PLAIN 580 B = k64 (SIN msm.uke_c3_* : el defecto armado=1 basta)
# cpio = k64 ; G0–G8 verdes
# boot: SSH <60 s + `cat /sys/module/msm/parameters/uke_c3_defer` (=1) +
# dmesg con `UKE-C3: ARMED` y `UKE-C3: DEFER`
```

Fila ledger #561 REDACTADA (pendiente de build+flash del coordinador):

```
#561 k71/C3 (PLAN-C3) — resume diferido (-EAGAIN) + FIRE manual tras USB.
Esperado: bootea a SSH (≡k52b2), GPU ausente, DEFER por open. FIRE: fases por
dmesg. Resultado: ___. Último testigo FIRE: ___. Decisión: si FIRE cuelga en
fase X → X es el asesino (nuevo kernel con X diferido); si FIRE SUBE → el
asesino era timing/orden pre-USB (revisar D1/D2/C1 con USB vivo); si C3 calla
igual → asesino PRE-resume: siguiente paso k64-baseline (la #550b nunca tuvo
flash: mentira nº1) o bisectriz de la base acumulada tras k52b2; pre-gate
barato sin build: `msm.skip_gpu=1` en cmdline (solo repack) para "cero código
GPU" puro (pero sin fase 2: no trae FIRE).
```

## 5. Dry-run de este turno (sin compilar)

- `patch -p1 --dry-run` del diff contra copia en scratch de `a6xx_gpu.c`:
  `rc=0`, **cero fuzz / cero offset** (3 hunks, 144 líneas).
- Aplicado de verdad sobre la copia scratch: byte-idéntico al fichero
  construido por anclajes (`cmp` OK). Símbolos nuevos: `module_param_cb` ×1,
  `schedule_work` ×1, `INIT_WORK` ×1, `return -EAGAIN` ×1, `UKE-C3` ×16.
- Balance del añadido: llaves 0, paréntesis 0.
- Tree intacto: sin `.orig`/`.rej` en `k52-tree` (todo el trabajo en scratch;
  el diff es archivo nuevo sin aplicar). Incidencia: el primer redactado del
  diff metió el bloque C3 dentro de la cabecera del hunk 1 (dry-run con fuzz 2
  y hunks perdidos); reconstruido por anclajes exactos + `diff -U3` canónico.
- NO ejecutado (lo hace el coordinador): build k71 (~60 min), gates sobre
  Image, repack-k71, flash (escritura nº9, override del dueño), fila #561.
