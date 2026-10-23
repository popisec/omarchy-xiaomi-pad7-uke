# FORENSE-BUILD-20261006 — por qué la dorada k49 ARRANCA y los rebuilds mueren a ~17 s

Sesión #532, 6-oct-2026. 100% offline (cero adb/fastboot). Todas las rutas absolutas.

## 0. Resumen ejecutivo

1. La dorada **no fue construida desde `palawan-linux`**: salió de
   `build/kernel-pokes/k18-tree/` (gitignored, sin `.git`), un árbol con el
   acumulado K18→K49. La config embebida es idéntica en ambos (extraída con
   `extract-ikconfig`: **diff vacío**), las flags del compilador también
   (`.cmd` normalizados: **diff vacío**), y el initramfs embebido es
   **byte-idéntico** (cmp OK, 1104021 B). Lo que difiere es el CÓDIGO (23
   ficheros), los MÓDULOS (la dorada no lleva ninguno; mis rebuilds instalaron
   847 en la tablet) y los strings de release (`uke@palawan` falsificado por
   KBUILD_BUILD_USER/HOST; `+` = repo git sucio).
2. La muerte ~17 s **no es un panic del kernel dorado vs mío**: es el
   `deferred probe timeout` (`CONFIG_DRIVER_DEFERRED_PROBE_TIMEOUT=10`)
   forzando el sondeo de drivers que el estado vendor-boot no soporta, más la
   carga de módulos CORESIGHT (`=m`) por el coldplug de systemd. En bisectD/E
   la secuencia `qcom_wdt (builtin check)` → `cs_system_cfg` →
   `coresight-cti 10010000.cti` → ráfaga `CTI initialized` (sys0..sys13) →
   `coresight-tmc … deferred probe timeout` muere **en silencio a 17,07 s**
   (última línea `cti_sys11/12: CTI initialized`). En bisectC (cmdline 255 B)
   la misma fuerza-muerte fue visible: `dpu_kms_mmu_init failed: -19` →
   `Unable to handle kernel paging request @ dead000000000108` (13,91 s).
   La dorada sobrevive AL MISMO timeout porque su lista pendiente eran solo
   `arm-scmi.0.auto` y `soc:gpio_key` (13,80 s) y porque en su rootfs no hay
   `/lib/modules/7.2.0-rc2-palawan` (prueba dura: `modprobe@fuse.service` corre
   y NO hay línea `fuse: init` en 181 s de dmesg).

## 1. Receta real de la dorada (tarea 1)

- Wrapper: `docs/historia/gates-palawan/build-k49.sh` (el log build-k49.log es su salida).
- Comando exacto: `cd build/kernel-pokes/k18-tree && export MAKE=/usr/bin/make
  ARCH=arm64 LLVM=1 KBUILD_BUILD_USER=uke KBUILD_BUILD_HOST=palawan &&
  make O=…/k49-build olddefconfig && make O=…/k49-build -j4 Image.gz`
  (tras `cp build/kernel-config/k49-pantalla.config $O/.config`).
- SIN CROSS_COMPILE (LLVM=1). `-j4`, no `-j16`. Compila SOLO `Image.gz`
  (nunca modules/modules_install).
- Fuente: `k18-tree` = k13-tree + ACUMULADO K25..K49 (varios cambios SOLO en el
  árbol, hueco #492-errata). Gitignored (`omarchy-uke/.gitignore:28`).
- `.cmd` verificados (init/main.o, kernel/sched/core.o, mm/page_alloc.o,
  uke-panic-fb.o, arm-smmu.o): flags IDÉNTICAS entre dorada y rebuild tras
  normalizar rutas (`clang --target=aarch64-linux-gnu -fintegrated-as
  -fno-PIE …`; el mismo set completo).
- Cronología del 3-oct en build-k49.log: build 15:02:33→15:16 (Image
  41421312 B, banner interno #1 15:16:02), gates de marcadores FALLARON por
  desajuste de versión del script (exigía `K49-crtc-en/K49-7nm-en/K49-pll-prep`;
  el árbol lleva `K47-*`), re-run 15:17 abortó en el gate de frescura
  (`Image -nt .config`) tras tocar `.config`. La Image de 15:16 es la dorada:
  el repack-boot-ukek49-esd-plyoff-report.txt G0 la certify
  (Image.gz 16688015 B, sha `d353356e30d4665b…` = el que sigue en
  k49-build/arch/arm64/boot/Image.gz hoy).
- ¿Quién construyó? ESTA máquina (`pc-build`, hostname real actual, que
  coincide con los banners de mis builds). `uke@palawan` es puro
  KBUILD_BUILD_USER/HOST del wrapper; "palawan" es el nombre del repo fuente
  (`~/gpu-work/palawan-linux`), no una máquina ni contenedor. Toolchain
  idéntico: clang/LLD 23.1.1 en ambos (la dorada fue el primer k-build tras el
  upgrade del 2-oct: `.config.old` de k49-build aún dice 22.1.8).
- Dato corregido del enunciado: el kernel embebido en la dorada mide
  **16688015 B** (no 16559711): repack report G0 y `kernel_size@8`.

## 2. Diff binario dorada vs rebuild (tarea 2)

| Magnitud | Dorada (k49-build) | Rebuild (build-uke #5) |
|---|---|---|
| vmlinux | 423192064 B, BuildID `b5dbf337ff6ae4fef78e21f3f63cdcc6aff9928e` | 422935416 B (−256648), BuildID `01c0f69c43b809738ac5b8c89534ab5b672ed372` |
| Image crudo | 41421312 B, sha `65b760c7f6258f0e…` | 41421312 B (mismo tamaño, contenido distinto), sha `3cfaec63d5640279…` |
| Image.gz | 16688015 B, sha `d353356e30d4665b…` (= embebido en boot-ukek49-esd-plyoff.img) | 16661626 B |
| ELF | PIE aarch64, debug_info, not stripped — idéntico en forma | idéntico |
| Secciones (readelf -S) | 59 | 59, nombres idénticos (diff vacío) |
| Config embebida (extract-ikconfig) | 256577 B | **idéntica byte a byte**; además == `.config` de cada dir |
| Banner | `7.2.0-rc2-palawan (uke@palawan) … #1 Sat Oct 3 15:16:02` | `7.2.0-rc2-palawan+ (usuario@pc-build) … #5 Tue Oct 6 13:23:13` |
| vermagic módulos | `7.2.0-rc2-palawan SMP preempt mod_unload aarch64` | `7.2.0-rc2-palawan+ …` (y 847 .ko en build-uke, incl. coresight-cti/tmc/stm, fuse) |
| Initramfs embebido (.init.ramfs) | 1104021 B | **byte-idéntico** (cmp vacío; = uke-k34-fw cpio sha `ebc2de46…`) |
| DTB | ninguno en k49-build (el del boot viene de la base K13-dsid; dts SIN touch/ADSP) | xiaomi-uke.dtb 94708 B (con nodo touch novatek SPI y `remoteproc_adsp` cliffs) |

Causa de los ~250 KB de vmlinux: código distinto (el árbol dorado lleva mucho
más instrumentation/fix código), no flags ni config.

## 3. La config embebida manda (tarea 3) — y NO difiere

`extract-ikconfig` sobre ambos vmlinux → **diff vacío**, y cada uno ==
su `.config` en disco (nada de config "cocinada" distinta). Sospechosos
revisados en la config común: `CONFIG_DRIVER_DEFERRED_PROBE_TIMEOUT=10`
(el temporizador de la fuerza-muerte), `CONFIG_CORESIGHT=m` (+CTI/TMC/STM `m`),
`CONFIG_QCOM_WDT=y`, `CONFIG_FUSE_FS=m`, `CONFIG_LOCALVERSION="-palawan"`,
`# CONFIG_LOCALVERSION_AUTO is not set`.

Comparación de la ventana 15-20 s (dorado estable vs mi boot muerto):
- Dorada (t1, 181 s de dmesg): a 13,80 s el timeout diferido re-sondea SOLO
  `arm-scmi.0.auto` y `soc:gpio_key` (inofensivos); 15-19 s solo ruido UFS;
  en TODO el dmesg: CERO líneas `fuse:`, `coresight`, `CTI initialized`,
  `cs_system_cfg`, `QTEE`, `deferred probe timeout`. Nada carga; sigue vivo
  hasta el audit de sshd a 181 s.
- Mi boot (bisectE, cmdline dorada 517B + mask adsp): initramfs lento (S123 a
  15,6 s vs 6,03 s dorado), systemd 16,09 s, coldplug 16,4 s, y a 17,056-17,072 s:
  `qcom_wdt: module is already loaded` → `cs_system_cfg: CoreSight
  Configuration manager initialised` → `qcomtee: QTEE version 5.2.0` →
  `coresight-cti 10010000.cti: Limiting HW MaxTrig…` → `coresight-tmc …:
  deferred probe timeout, ignoring dependency` → ráfaga `CTI initialized`
  sys0…sys12 → **silencio para siempre**. Con `fuse: init (API version 7.45)`
  a 16,375 s (módulo cargado de verdad: hay `/lib/modules`).
- bisectC (mismo binario #5, cmdline 255 B): muerte VISIBLE a 13,91 s —
  timeout → `msm_dpu ae01000.display-controller: deferred probe timeout` →
  `clk: couldn't set disp_cc_mdss_vsync_clk (-22)` → `dpu_kms_mmu_init
  failed: -19` → `Unable to handle kernel paging request @ dead000000000108`
  (oops con trace; panic=10 → reboot).

## 4. Hipótesis de muerte ~17 s (tarea 4), rankeadas

- **(e) OPERATIVA — MÓDULOS EN LA ROOTFS + timing del coldplug: PRINCIPAL (probada).**
  La dorada no fabrica módulos y la rootfs v8 no tiene `/lib/modules` para su
  release → NINGÚN `=m` carga jamás (fuse incluido). Mis bisect installs
  cargaron `fuse`, `cs_system_cfg`, `qcomtee`, `coresight-cti/tmc/stm`
  (vermagic `palawan+`, de los 847 .ko de build-uke, mtime 6-oct 00:00). El
  sondeo del hardware coresight (con SMMU apps sin bindear y el SoC en estado
  vendor-boot; el propio `qcom_wdt` builtin ya falló -EBUSY a 0,37 s en la
  dorada) mata la máquina sin panic (SError/lockup). Evidencia directa:
  secuencia exacta 17,056→17,072 s y última línea `CTI initialized`.
  Contra-evidencia descartada: el boot viejo del 2-oct (kernel `uke@palawan`
  #2 clang 22.1.8, con `UKE-K11` armado por sysfs y apps-smmu sondeado a 3,9 s)
  vivió 371,5 s y apagó limpio — el SMMU sondeado NO mata por sí solo; los
  módulos tampoco existían entonces.
- **(b) CÓDIGO — árbol ≠ árbol: SECUNDARIA / COFACTORA (probada como real).**
  23 ficheros difieren; en la dorada el apps-smmu se difiere SIEMPRE
  (`uke_smmu_probe`, "primer probe DIFFERIDO… Arranque sano"), printk lleva el
  tope de consola (UKE_CONSOLE_LOGLEVEL_MAX=4), uke-panic-fb a pr_err, y todo
  el bloque display/GPU lleva los fixes K19-K49. Mi árbol trae otros cambios
  (#528: touch SPI+novatek, ADSP cliffs en DTS, pd_mapper `qcom,lamma`,
  UFS/ICC, gpucc). El crash de bisectC (dpu_kms_mmu_init −19 → paging fault)
  y el sondeo fallido de novatek (-22) son de ESTA familia: código mío que la
  dorada no tiene, pisando hardware en estado vendor. Los 4 commits NO quedan
  exonerados como clase; lo que queda exonerado es que expliquen la muerte
  coresight de D/E (esa ocurre con config idéntica y con drivers idénticos:
  es el módulo + el timeout).
- **(a) CONFIG: REFUTADA.** Embebida byte-idéntica.
- **(c) ENTORNO DE BUILD: REFUTADA como causa codegen.** Flags idénticas
  (.cmd), mismo clang/lld 23.1.1, misma máquina. Lo único que cambió son los
  strings de release (KBUILD_BUILD_*/localversion/`+`), sin efecto funcional.
- **(d) INITRAMFS: REFUTADA.** Byte-idéntico (cmp de `.init.ramfs`).

Mecánica fina del "por qué ~17 s y no antes": el tiempo lo ponen el
initramfs/ukeinit (mío tarda ~10 s más en llegar a switch_root con la cmdline
de 517 B) + coldplug (16,4 s) + timeout diferido de 10 s desde initcalls_done;
en boots con cmdline corta la misma fuerza-muerte golpeó antes y salió por dpu
(bisectC). La "muerte silenciosa a los 17 s" y el "oops de dpu a 13,9 s" son
la MISMA fuerza (timeout + coldplug) con víctimas distintas.

## 5. Receta (tarea 5)

`build/gates/BUILD-RECIPE-DORADA.md` (escrito hoy). Núcleo: fuente k18-tree
EXACTA + wrapper build-k49.sh (KBUILD_BUILD_*, -j4, solo Image.gz) + config
k49-pantalla.config + cpio uke-k34-fw + repack-k18.py sobre base K13-dsid, y
regla operativa dura: jamás instalar `/lib/modules/7.2.0-rc2-palawan*` en la
tablet. Verificación: extract-ikconfig diff vacío, Image 41421312 B, banner
sin `+` y con `uke@palawan #1`, initramfs cmp OK, dmesg esperado sin
`fuse:`/`coresight`.

## 6. Respuestas cortas

- ¿Otra máquina/contenedor? **No**: host real `pc-build` en ambos;
  `uke@palawan` es falsificación del wrapper.
- ¿Las configs eran idénticas? **Sí** (embebidas byte a byte); el `+` y el
  `#N` son metadata de release, no config.
- ¿Reproducible? **Sí, con la receta §5** — equivalente (config/flags/
  initramfs/código idénticos); bit-idéntico imposible por la fecha/hora del
  banner (`#1 <timestamp>`), como la propia dorada demuestra.
