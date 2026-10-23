# Android a nivel de sistema: cmdline, init_boot/vendor_boot, display y hand-off del bootloader

> Fecha: 2026-10-13. Ámbito: `~/proyectos/omarchy-uke` (uke, SM7675).
> Fuentes primarias: `stock/images/{init_boot,vendor_boot}.img` (sha en `stock/images/SHA256SUMS`),
> DT decompilado `build/evidencia/android-snap/dt-r15/`, snapshot en vivo
> `build/evidencia/android-snap/extracted-r15/uke-r15-20260625-114251/`
> (`07-sys/dmesg-FULL.txt` 13648 líneas, `07-sys/getprop.txt`, `03-display/`),
> `stock/modules/*.ko`, `stock/firmware/`, `stock/dtbo/stock.dtb`,
> `docs/UBUNTU-BOOT.md` en `~/proyectos/ubuntu-uke/`.
> Descompresión con `unpack_bootimg` + `lz4`/`cpio`, solo lectura. Sin commit, sin tocar la tablet.

## 0. Resumen ejecutivo

1. **La cmdline de Android viene del ABL, no de las imágenes.** `init_boot.img` trae cmdline vacía;
   `vendor_boot.img` trae solo 3 tokens (`video=vfb… swinfo… mtdoops… bootconfig`) + `bootconfig`
   con 6 claves `androidboot.*`. Los 54 tokens del `/chosen/bootargs` del DT los compone el ABL
   en cada arranque (incluye valores por-boot: `boot_index`, `pureason`, `hwid.*_adc`, `initrd_size`).
2. **Mainline no pierde ningún token de Android**: el ABL concatena la cmdline de la cabecera
   del `boot.img` DESPUÉS de la suya, así que todo lo de Android se hereda y mainline solo
   añade/overridea. Ver tabla §1.
3. **`msm_drm.dsi_display0=qcom,mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid:` es el selector de panel.**
   El dtbo trae DOS variantes o82 (fragment@95 = `42_02_0b` CSOT, fragment@96 = `36_02_0a` TM);
   la cmdline decide cuál hace bind. Esta unidad es CSOT
   (`nvt_parse_dt: lcd_id_value = 1, this panel is CSOT`, dmesg r15 línea ~4844).
4. **El display se levanta en dos tiempos**: DRM/DSI/panel a t=3.75–3.84 s en kernel
   (`msm_drm` + `cont_splash`), y la pila userspace después
   (composer 6.06 s → surfaceflinger 6.42 s → bootanim 8.80 s, según `ro.boottime.*`).
5. **No hay firmware de display que mainline no cargue**: el DPU/DSI no pide ningún fichero
   por `request_firmware` en todo el dmesg. Los `display_id_*.xml` / `DPU*.xml` son configs
   del composer HAL en userspace, no firmware del kernel. El único firmware con carga
   observada es el de GPU (`gen71100_sqe.fw`, `gen71100_gmu.bin`, `gen71100_zap.mbn` vía
   ueventd desde `/vendor/firmware/`, dmesg 6.13–6.30 s).
6. **El splash sobrevive por `cont_splash`**: el ABL deja el framebuffer del logo en
   `splash_region` (0xE3940000, 43 MiB, 44 032 KiB, mapeada y reutilizable por el kernel),
   y `msm_drm` la adopta (`[drm] cont_splash enabled in 1 of 1 display(s)`, t=3.836 s)
   en vez de resetear el MDSS/DSI. Mainline ya apunta aquí:
   `memmap=0x2B00000$0xE3940000` (L29, 43 MiB exactos) + `msm.uke_skip_mdss_reset=1`.
7. **`panel_event_notifier.ko` NO habla con SurfaceFlinger**: es un bus kernel pub/sub
   (3 símbolos: `register/unregister/trigger`) para eventos blank/unblank/ESD. Sus
   consumidores son `msm_drm`, backlight (`qcom-spmi-wled`, `qpnp-lcdb-regulator` vía
   charger), `leds-qti-flash`, `mi_fp`, `qti_amoled_ecm`, y el touch de Xiaomi
   (`xiaomi_register_panel_notifier_work`, dmesg 3.87 s). SF se entera por DRM/HWC, no por aquí.

## 1. La cmdline que pasa Android (54 tokens, `/chosen/bootargs` de dt-r15)

Fuente: `build/evidencia/android-snap/dt-r15/chosen/bootargs` (captura r15, `boot_index=480`).
Columna "Mainline": qué hace la cmdline vigente de mainline (L29, 592 B, leída de
`build/bootimg/boot-uke-k52L29.img @44`, verificado 2026-10-12) con cada token.
El ABL concatena la cmdline de cabecera tras la suya ⇒ **todo lo de abajo se hereda salvo
override explícito por clave**.

| # | Token Android | Qué es | Mainline L29 |
|---|---|---|---|
| 1 | `loglevel=6` | nivel printk | OVERRIDE `loglevel=4` |
| 2 | `kpti=0` | sin mitigación Meltdown | hereda |
| 3 | `log_buf_len=256K` | (luego redefinido, ver #45) | hereda |
| 4 | `swiotlb=noforce` | SWIOTLB | hereda |
| 5 | `loop.max_part=7` | loop | hereda |
| 6 | `pcie_ports=compat` | PCIe | hereda |
| 7 | `irqaffinity=0-2` | afinidad IRQs | hereda |
| 8 | `cpufreq.default_governor=performance` | governor en arranque | hereda |
| 9 | `sysctl.kernel.sched_pelt_multiplier=4` | scheduler | hereda |
| 10 | `kasan=off` | KASAN off | hereda |
| 11 | `cgroup.memory=nokmem,nosocket` | memcg | hereda |
| 12 | `disable_dma32=on` | zona DMA | hereda |
| 13 | `kernel.panic_on_rcu_stall=1` | RCU | hereda |
| 14 | `fw_devlink.strict=1` | probe estricto (mainline lo relaja, ver +12) | hereda (pero añade `fw_devlink=permissive`) |
| 15 | `service_locator.enable=1` | QMI service locator | hereda |
| 16 | `rcupdate.rcu_expedited=1` | RCU | hereda |
| 17 | `rcu_nocbs=0-7` | RCU | hereda |
| 18 | `no-steal-acc` | ARM | hereda |
| 19 | `printk.console_no_auto_verbose=0` | printk | hereda |
| 20 | `can.stats_timer=0` | CAN | hereda |
| 21 | `ftrace_dump_on_oops` | ftrace | hereda |
| 22 | `firmware_class.path=/vendor/firmware_mnt/image,/vendor/firmware_mnt/image/kiwi,/vendor/vm-system/oemvm/boot,/vendor/vm-system/trustedvm/boot,/vendor/firmware,/vendor/firmware/wlan/qca_cld/kiwi_v2` | **rutas de firmware** (primero `firmware_mnt/image` = partición modem montada; cae a `/vendor/firmware`) | hereda (mainline añade su path por sysfs en su init) |
| 23 | `pci-msm-drv.pcie_sm_regs=0x1D07000,0x1040,0x1048,0x3000,0x1` | PCIe MSM | hereda |
| 24 | `video=vfb:640x400,bpp=32,memsize=3072000` | **fb virtual** (vfb, NO el panel; viene también en la cmdline de vendor_boot) | hereda |
| 25 | `swinfo.fingerprint=uke:14/OS3.0.303.0.WOZEUXM:user` | huella ROM | hereda |
| 26 | `mtdoops.fingerprint=uke:14/OS3.0.303.0.WOZEUXM:user` | idem pstore | hereda |
| 27 | `bootconfig` | activa bootconfig (las `androidboot.*` van en vendor_boot) | hereda |
| 28 | `bootinfo.pureason=0x40001` | motivo power-up (**por-boot**, mainline vio `0x800001`) | hereda (valor distinto por arranque) |
| 29 | `bootinfo.pdreason=0x2` | motivo power-down | hereda |
| 30 | `msm_sharedmem.cma_already_panic=0` | sharedmem | hereda |
| 31 | `debug_ext.initrd_size=35314` | tamaño initrd (**por-boot**; cambia con el ramdisk) | hereda (valor distinto por arranque) |
| 32 | `spidev.bufsiz=16384` | SPI | hereda |
| 33 | `hwid.hwid_value=1638400` | HWID | hereda |
| 34 | `hwid.project=11` | proyecto (uke) | hereda |
| 35 | `hwid.build_adc=51228` | ADC (**por-unidad**, mainline vio 51232) | hereda (varía) |
| 36 | `hwid.project_adc=77` | ADC (**por-unidad**, mainline vio 81) | hereda (varía) |
| 37 | `msm_drm.dsi_display0=qcom,mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid:` | **SELECTOR DE PANEL** (nodo:config; config vacía = topo por defecto) | **hereda — crítico, mainline NO lo redefine** |
| 38 | `msm_drm.oled_wp=99807e` | white-point del panel (verificado en vivo: `display wp info is 99807e`, dmesg 6.55 s) | hereda |
| 39 | `msm_drm.debugpolicy=0x20` | política ramdump DRM | hereda |
| 40 | `msm_drm.build_id=c3` | build id panel | hereda |
| 41 | `rootwait` | espera root | hereda |
| 42 | `ro` | root RO | hereda |
| 43 | `init=/init` | **init de Android** (first_stage en init_boot ramdisk) | mainline usa `rdinit=/ukeinit` (el ABL concatena; `rdinit` gana para el arranque, `init=` queda para después) |
| 44 | `silent_boot.mode=nonsilent` | modo silent | hereda |
| 45 | `log_buf_len=2M` | redefine #3 | hereda |
| 46 | `loglevel=6` | (repite #1) | OVERRIDE `loglevel=4` |
| 47 | `console=ttynull` | consola nula | mainline añade `console=tty0` + `console=ttyGS0,115200` (todas reciben output; la última es `/dev/console`) |
| 48 | `block2mtd.block2mtd=/dev/block/by-name/oops,2097152` | pstore en partición oops | hereda |
| 49 | `mtdoops.mtddev=0` | idem | hereda |
| 50 | `mtdoops.record_size=2097152` | idem | hereda |
| 51 | `mtdoops.dump_oops=1` | idem | hereda |
| 52 | `printk.always_kmsg_dump=1` | vuelca kmsg a pstore | OVERRIDE `printk.always_kmsg_dump=0` (L29) |
| 53 | `mtdoops.boot_mode=0` | idem | hereda |
| 54 | `mtdoops.boot_index=480` | contador (**por-boot**) | hereda (valor distinto por arranque) |

### 1.1 Tokens que mainline AÑADE (L29, 33 tokens — ninguno existía en Android)

Base histórica (desde s240-mem2g): `mem=2048M rdinit=/ukeinit panic=10
memmap=0x1A12800$0xE3940000 console=tty0 fbcon=map:0 hung_task_timeout_secs=20
hung_task_panic=1 watchdog_thresh=10 console=ttyGS0,115200 fw_devlink=permissive
clk_ignore_unused pd_ignore_unused arm-smmu.disable_bypass=0`.
Añadidos de la campaña actual: `arm_smmu.uke_smr_max=0 arm_smmu.uke_keep_boot=1
arm_smmu.uke_attach_log=2 arm_smmu.uke_reset_mask=12 memmap=0x2B00000$0xE3940000
loglevel=4 msm.uke_gmu_shared=0 arm_smmu.uke_kgsl_keep=0 hung_task_panic=0
printk.always_kmsg_dump=0 plymouth.enable=0 msm.uke_s3_stage=3 msm.uke_rescue=1
msm.uke_probe_hold_ms=5000 msm.uke_skip_mdss_reset=1`.

Notables para display:
- `memmap=0x2B00000$0xE3940000` (43 MiB en 0xE3940000) = **reserva EXACTA de la
  `splash_region`** (0xE3940000+0x2B00000, ver §5). El `memmap` viejo
  (`0x1A12800` = 27 MiB) era parcial; el L29 lo clava al tamaño real.
  (Ojo: con doble `memmap` + `mem=2048M` conviene revisar solapes; fuera de ámbito.)
- `msm.uke_skip_mdss_reset=1` = no resetear el MDSS al hacer probe (no tocar lo que dejó el ABL).
- `video=DSI-1:d` (citado en rondas viejas, report k52L29: "SIN video=DSI-1:d") **ya no se usa** en L29.

**Conclusión §1**: mainline no necesita replicar nada de Android mientras añada su cmdline
a la cabecera (el ABL la concatena). El único riesgo sería un `boot.img` que REEMPLACE la
cmdline del ABL: entonces habría que reponer como mínimo #37 (`dsi_display0`), #38–#40
(`oled_wp`, `debugpolicy`, `build_id`), #22 (`firmware_class.path`) y #24 (`video=vfb`).

## 2. init_boot.img: el first_stage de Android

`stock/images/init_boot.img` (8 388 608 B, sha `5228e6e2…`): header v4, **kernel_size=0**
(sin kernel), cmdline vacía, ramdisk lz4 de 2 308 998 B → cpio con:

```
init_boot ramdisk (cpio, 8618 bloques):
├── init                          ELF aarch64 estático, "for Android 34"  ← first_stage init
├── debug_ramdisk/                (vacío)
├── second_stage_resources/       (vacío)
├── system/bin/snapuserd{,_ramdisk}
├── system/etc/init/snapuserd.rc
├── system/etc/ramdisk/build.prop
└── dev/ mnt/ proc/ sys/ metadata/ (+ system/)
```

**No hay nada de display aquí**: ni `.rc` de display, ni módulos, ni firmware. Este ramdisk
solo sabe montar y pasar a segunda fase. El `/init` es el init de Android (first_stage):
carga `modules.load` del vendor_boot, monta particiones según `fstab.qcom` y hace
`exec /system/bin/init` (second_stage). Mainline lo pisa con `rdinit=/ukeinit` + su
initramfs concatenado (ver UBUNTU-BOOT.md §1 y B-arranque §4.1/§6: el `/init` del vendor
sobrescribe por O_TRUNC, de ahí el nombre `/ukeinit`).

## 3. vendor_boot.img: el vendor ramdisk (aquí vive el arranque de display en kernel)

`stock/images/vendor_boot.img` (100 663 296 B, sha `3ee6d4ac…`): header v4 `VNDRBOOT`,
cmdline de cabecera = `video=vfb:640x400,bpp=32,memsize=3072000 swinfo.fingerprint=…
mtdoops.fingerprint=… bootconfig`, `bootconfig` (205 B):

```
androidboot.hardware=qcom
androidboot.memcg=1
androidboot.usbcontroller=a600000.dwc3
androidboot.load_modules_parallel=true
androidboot.vendor.qspa=true
androidboot.hypervisor.protected_vm.supported=false
```

Contenido:

```
vendor_boot (descomprimido con unpack_bootimg + lz4 + cpio, 134260 bloques):
├── dtb                        1 885 961 B (base GKI+qcom: MDSS/DSI Ctrl/PHY, SIN panel —
│                              el panel viene del dtbo, ver §5)
├── vendor_ramdisk00           lz4 → cpio:
│   ├── first_stage_ramdisk/fstab.qcom   (system/system_ext/product/mi_ext + overlays)
│   └── lib/modules/  354 .ko + modules.load + modules.load.recovery +
│                      modules.dep + modules.alias + modules.softdep + modules.blocklist
└── vendor-ramdisk-by-name/ramdisk_ -> ../vendor_ramdisk00
```

### 3.1 Orden de carga: el display YA está en first_stage

`lib/modules/modules.load` (el que consume el first_stage init, `androidboot.load_modules_parallel=true`)
termina así (cola real del fichero):

```
…(pila rpmh/clk/pinctrl/usb/ufs/smmu)…
dump_display.ko                 ← t=0.22 s en dmesg r15 ("crash_record_init init")
…
msm_drm.ko                      ←
msm_ext_display.ko              ← junto a sync_fence.ko, msm_hw_fence.ko,
sync_fence.ko                   ← msm-mmrm.ko, smcinvoke_dlkm.ko
msm_hw_fence.ko
msm-mmrm.ko
smcinvoke_dlkm.ko
swinfo.ko
```

Es decir: **Android carga `msm_drm` en first_stage**, antes de montar `/system`.
`msm_kgsl` (GPU) **NO** está en `modules.load`: se carga en segunda fase desde
vendor_dlkm (dmesg: probe KGSL t=2.97–3.02 s, firmware t=6.13–6.30 s).
Secuencia medida en r15: `dispcc/gpucc` t=0.48 s → KGSL t≈3.0 s → `msm_drm` probe
t=3.75 s → `cont_splash` t=3.836 s → touch NVT t=3.844 s (`lcd_id=CSOT`).

### 3.2 Árbol de módulos de display en vendor_boot

| Módulo | Rol | En modules.load |
|---|---|---|
| `msm_drm.ko` | DRM MSM (MDSS/SDE/DSI/panel/mi_disp) | sí (cola) |
| `msm_ext_display.ko` | display externo/DP (dependencia de msm_drm) | sí |
| `panel_event_notifier.ko` | bus de eventos de panel (dependencia de msm_drm) | sí (vía `insmod` de 2ª fase para wled/charger; cargado t≈3.7 s) |
| `dump_display.ko` | vuelca estado display a `dump_display_region` en panic | sí (cabeza, t=0.22 s) |
| `dispcc-pineapple.ko` + `dispcc-volcano.ko` | clocks display | sí (t=0.48 s) |
| `drm_display_helper.ko`, `drm_dp_aux_bus.ko` | helpers DRM/DP | sí (deps) |
| `sync_fence.ko`, `msm_hw_fence.ko`, `msm-mmrm.ko` | fences/mmrm (deps de msm_drm) | sí |
| `qcom-spmi-wled.ko`, `qpnp-lcdb-regulator.ko`, `qpnp-amoled-regulator.ko` | backlight/regulación panel | 2ª fase (vendor_dlkm) |
| `msm_kgsl.ko` | GPU (NO display, pero compone vía HWC) | **no** (2ª fase) |
| `lt9611uxc.ko` | bridge HDMI (esta tablet no lo usa) | 2ª fase |

`msm_drm.ko` del vendor_boot es **byte a byte el mismo** que `stock/modules/msm_drm.ko`
(md5 `6d71c6f3ec912ec8204b8673f65cb081` ambos).

## 4. El arranque de display en Android: del kernel a SurfaceFlinger

### 4.1 Kernel (t=3.75–3.87 s, dmesg r15)

```
3.751683  mi_disp_core_init: mi disp_core driver initialized!
3.753–3.756  DSI PLL/PHY/Ctrl 0+1: Probe successful (dual-DSI)
3.759–3.829  parse del panel o82_42_02_0b: 1600x2136, modos 120/144/90/60/50/48/30,
             topología lm:2 comp_enc:2 intf:2 (dual-DSI + DSC)
3.809091  Successfully bind display panel 'qcom,mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid'
3.811880  mdss_mdp: bound dsi-display-primary (+ smmu_sde, wb x2, rscc, dp_display)
3.829850  ESD irq registrada (doble)
3.836406  [drm] Initialized msm_drm 1.4.0 … on minor 0
3.836411  [drm] cont_splash enabled in 1 of 1 display(s)     ← el splash sobrevive
3.844526+ NVT-ts touch: lcd_id_value=1 → CSOT; ktz8866 backlight dual probe OK
3.868844  xiaomi_register_panel_notifier_work (touch se suscribe a eventos de panel)
```

### 4.2 Userspace (tiempos `ro.boottime.*`, ns desde arranque)

| Servicio (`init.svc.*`) | Estado r15 | boottime | Qué es |
|---|---|---|---|
| `vendor_qti_graphics_boot` | stopped (one-shot) | 2.24 s | script early-boot de gráficos QTI |
| `vendor_sys_qti_display` | stopped (one-shot) | 5.24 s | setup sys de display QTI |
| `qti_display_boot` | stopped (one-shot) | 5.22 s | boot display QTI (enciende composer path) |
| `vendor.qti.hardware.display.allocator` | running (pid 1671) | 6.06 s | **HAL allocator** (gralloc) |
| `vendor.qti.hardware.display.composer` | running (pid 1679) | 6.06 s | **HAL composer/HWC** (el que compone) |
| `vendor.displayfeatureaidl-hal` | running (pid 1750) | 6.17 s | HAL displayfeature Xiaomi |
| `surfaceflinger` | running (pid 1876) | 6.42 s | **SurfaceFlinger** |
| `panel-info-sh` | stopped (one-shot) | 6.47 s | script que lee panel-id/wp |
| `gpu` | running (pid 1868) | 6.40 s | servicio GPU |
| `bootanim` | stopped | 8.80 s | **bootanimation** (primera imagen que SUSTITUYE al splash) |
| `displayfeature` | running (pid 2749) | 9.60 s | features Xiaomi (fod/hbm/dc…) |
| `wifidisplayhalservice` | running | 9.27 s | WFD (no panel) |

No hay ningún servicio `splash`: **el "splash service" es la ausencia de reset** —
entre t=0 (logo ABL) y t=8.8 s (bootanim) la pantalla muestra el framebuffer heredado
vía `cont_splash`, y SurfaceFlinger lo adopta sin parpadeo. Los `.rc` de estos servicios
viven en `/vendor/etc/init/` (partición vendor, fuera de las imágenes de boot;
aquí se infieren por `getprop`, ya que super.img no está extraída en este entorno).

## 5. Firmware: el display NO pide firmware; la GPU sí

- **DPU/DSI/panel: cero `request_firmware` en 13 648 líneas de dmesg.** Los únicos
  fallos de carga son `regulatory.db` (wifi) y `vpu30_2v.mbn` (video), ambos denegados
  por SELinux y reintentados por ueventd — ninguno de display. El panel se configura
  por DT (dtbo) + DCS por DSI, sin binarios.
- **`display_id_*.xml`, `DPU*.xml`, `qdcm_calib_*.json`, `mdss_dsi_o82_*_mi.xml`,
  LUT/`.dlc` en `stock/firmware/` son artefactos de userspace** (composer HAL / ppd /
  calibración QDCM), no firmware del kernel. Ejemplo: `DPU10__.xml` = 70 parámetros
  SDE (ancho de banda, line buffer, perf) que consume el HAL; `display_id_*.xml` =
  mapas de brillo por panel. Mainline no necesita ninguno para encender el panel.
- **GPU (referencia, no display)**: `kgsl-3d` + `adreno-gen7-gmu` piden
  `gen71100_sqe.fw` → `gen71100_gmu.bin` → `gen71100_zap.mbn`; el kernel los busca en
  `firmware_class.path` (primero `/vendor/firmware_mnt/image`, denegado -13) y ueventd
  los sirve de `/vendor/firmware/` (dmesg 6.13–6.30 s). Confirma el inventario
  (INVENTARIO-VENDOR-UKE.md addendum): el set gen71100 está completo en la ROM.
- **`firmware_mnt/image` se puebla en vivo** desde el modem (NON-HLOS), como ya anotó
  NOTAS-FRENTE-1.md §"sigue necesitando tablet". Para display es irrelevante.

## 6. El hand-off del bootloader: qué deja el ABL

### 6.1 Regiones reservadas (dt-r15 `reserved-memory/`, `#address-cells=2`)

| Región | Dirección | Tamaño | Attr | Uso |
|---|---|---|---|---|
| `splash_region` (`cont_splash_region`) | **0xE3940000** | **0x2B00000 (43 MiB / 44 032 KiB)** | map, non-reusable | **framebuffer del logo ABL**; el kernel la mapea (`OF: reserved mem … map`) y `msm_drm` la escanea como `cont_splash` |
| `dump_display_region@816e0000` | 0x816E0000 | 0x800 (2 KiB) | nomap | `dump_display.ko` (`compatible = "xiaomi,dump_display"`, panic-notifier + `crash_record_init`) vuelca el estado del display aquí en pánico |
| `non_secure_display_region` | dinámico | 0xA400000 (164 MiB) | shared-dma-pool, reusable | heap DMA de display |
| `demura_region_0/1` | 0/0 | 0 | — | reservadas pero de tamaño 0 (demura desactivado en esta variante) |
| `ramoops_region` | 0xA7000000 | 0x400000 (4 MiB) | ramoops | pstore/ukecons (NO sobrevive reset) |
| `linux,cma` | dinámico | 0x2000000 (32 MiB) | default | CMA |

Cálculo del splash: 1600×2136×4 B ≈ 13.7 MiB por frame; 43 MiB ≈ 3 frames
(doble/triple buffer del logo + Demura). Mainline L29 lo reserva entero con
`memmap=0x2B00000$0xE3940000`.

### 6.2 Cómo mapea Android la memoria del splash

1. ABL pinta el logo y describe `splash_region` en el DT que pasa al kernel.
2. El kernel la reserva (`OF: reserved mem … map non-reusable`) — visible para
   `msm_drm` como `cont_splash`.
3. `msm_drm` al hacer bind **no resetea** el pipeline (ver `msm.uke_skip_mdss_reset=1`
   en mainline, que replica este comportamiento) y marca
   `cont_splash enabled in 1 of 1 display(s)`.
4. El primer commit real lo hace el composer/SurfaceFlinger (~6 s) y el bootanim
   (8.8 s) sustituye el logo sin parpadeo porque el modo/timing ya estaba programado.

### 6.3 Selección de panel: cmdline + dtbo

- `stock/dtbo/stock.dtb`: `fragment@95` = `qcom,mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid`
  (CSOT), `fragment@96` = `…36_02_0a…` (TM); `fragment@87` = `qcom,dsi-display-primary`
  con `panel = <&…42_02_0b>, <&…36_02_0a>, …`.
- La cmdline `#37` elige el primero de la lista (`…42_02_0b…:` con config vacía).
  Sin ese token, `msm_drm` no sabría qué panel bindear (hay 2 o82 + otros de otros
  proyectos en el dtbo: vtdr6130, n16t, r66451).
- `vendor_boot` DTB base trae MDSS/DSI Ctrl/PHY pero **ningún nodo de panel**:
  todo el panel vive en el overlay del dtbo.

## 7. Los .ko vendor de display (`modinfo`)

Vermagic común: `6.1.68-android14-11-g57741a5144df-dirty SMP preempt mod_unload
modversions aarch64` (msm_drm/msm_kgsl; panel_event_notifier/dump_display usan la
variante `-maybe-dirty`). Kernel Android r15 en vivo: `6.1.138-android14-11-…`
(ver UBUNTU-BOOT.md §9: el vermagic hay que parchearlo para kernels propios).

### `msm_drm.ko` (6 105 320 B, md5 `6d71c6f3…` = vendor_boot ≡ stock/modules)

- `depends`: qcom_ipc_logging, drm_display_helper, hdcp_qseecom_dlkm, gh_rm_drv,
  gh_irq_lend, gh_mem_notifier, gh_msgq, altmode-glink, dwc3-msm, wcd_usbss_i2c,
  msm_ext_display, sync_fence, msm_hw_fence, llcc-qcom, qcom-scm,
  **panel_event_notifier**, qcom_va_minidump, pinctrl-msm, spmi-pmic-arb, msm-mmrm,
  qcom_rpmh, metis, mem_buf_dev, qcom_iommu_util, msm_dma_iommu_mapping, smem,
  pm8941-pwrkey, miev (+ `import_ns: DMA_BUF`).
- `alias`: `qcom,msm-hdcp / mdp4 / mdss / sde-kms / smmu_sde_{,nrt}_{sec,unsec}` (+`C*`).
- `parm` (los que Android usa en cmdline marcados con ★):
  `★dsi_display0`, `★dsi_display1`, `★oled_wp`, `★sec_oled_wp`, `★build_id`,
  `★debugpolicy`, `sec_cell_id`, `cell_id`, `modeset` (KMS on), `dumpstate`,
  `vram`, `reglog`, `sdecustom`.
- **Parámetros que Android pasa y mainline hereda**: `dsi_display0`, `oled_wp=99807e`,
  `debugpolicy=0x20`, `build_id=c3`. Ninguno cambia el comportamiento de encendido
  salvo `dsi_display0` (selección de panel) y `modeset=0` (que Android NO usa —
  apaga KMS; no tocar).

### `msm_kgsl.ko` (3 532 384 B)

- `depends`: msm_sysstats, mem_buf_dev, miev, clk-qcom, qcom-dcvs, mist,
  secure_buffer, qcom-scm, mdt_loader, minidump, qcom_va_minidump, msm_hw_fence,
  socinfo, llcc-qcom, cmd-db, qcom_iommu_util, msm_performance, qcom_aoss, metis,
  coresight. `alias`: `qcom,kgsl-3d0`. `parm`: `gpu_speed_bin_override`,
  `gpu_sku_override`, `preempt_enable`. **Android no le pasa ningún parámetro**
  (ni en cmdline ni en modules.load: `args ''`). Pide 3 firmwares (§5).

### `panel_event_notifier.ko` (15 448 B) y `dump_display.ko`

- Ambos: `depends:` (vacío), `intree: Y`, sin parms, sin aliases.
- `panel_event_notifier`: 3 símbolos (`register/unregister/trigger`) — ver §8.
- `dump_display`: `compatible "xiaomi,dump_display"`, `crash_record_init`,
  registrado en `panic_notifier_list`; escribe en `dump_display_region` (2 KiB).

## 8. `panel_event_notifier.ko`: qué hace

- Es el **bus kernel de eventos de panel de Qualcomm** (no un driver de hardware:
  sin `compatible`, sin probe, sin parámetros). API: `panel_event_notifier_register`
  (por tag: `Invalid panel notifier tag`, `Invalid client handle`), `unregister`,
  `panel_event_notification_trigger` (protegido por `panel_event_notifier_entries_lock`).
- **Dirección del flujo: DRM → suscriptores kernel.** Lo dispara `msm_drm`/mi_disp
  en blank/unblank/ESD; lo consumen (vía `modules.dep`): `msm_drm`, `leds-qti-flash`,
  `qcom-spmi-wled`, `qpnp-lcdb-regulator` (cadena charger), `qcom-hv-haptics`,
  `mi_fp`, `qti_amoled_ecm`, `mi_thermal_interface`, y el touch
  (`xiaomi_register_panel_notifier_work`, dmesg 3.87 s: el touch espera al panel).
- **NO notifica a SurfaceFlinger**: SF vive en userspace y se entera por
  DRM (`drmModeAtomicCommit`/uevents) y por el composer HAL. Implicación para
  mainline: si el panel genera eventos (ESD irq doble registrada, §4.1), el
  consumidor que los necesita es el backlight/touch, no el compositor.

## 9. Archivos leídos y comandos (reproducibilidad)

```
# cmdline Android (DT) y mainline vigente
cat build/evidencia/android-snap/dt-r15/chosen/bootargs
python3 -c "d=open('build/bootimg/boot-uke-k52L29.img','rb').read();print(d[44:44+1536].split(b'\0')[0].decode())"
cat build/bootimg/cmdline-orig.txt            # cmdline fusionada ABL+mainline (época s244)
# imágenes (solo lectura, /tmp/opencode/uke-android-init/)
unpack_bootimg --boot_img stock/images/init_boot.img --out init_boot_out
unpack_bootimg --boot_img stock/images/vendor_boot.img --out vendor_boot_out
lz4 -dc vendor_boot_out/vendor_ramdisk00 | cpio -idmv   # 354 .ko + fstab.qcom
cat x-vendor/lib/modules/modules.load | tail -12        # msm_drm en first_stage
modinfo stock/modules/{msm_drm,msm_kgsl,panel_event_notifier}.ko
strings stock/modules/panel_event_notifier.ko | grep panel_event_notifier_
dtc -I dtb -O dts stock/dtbo/stock.dtb | grep -E "o82_|dsi-display-primary"
# snapshot en vivo r15
grep -E "cont_splash|bind display panel|splash_region" extracted-r15/…/07-sys/dmesg-FULL.txt
grep -E "init.svc.*(surfaceflinger|composer|display|bootanim)|ro.boottime" extracted-r15/…/07-sys/getprop.txt
grep -iE "loading /vendor/firmware.*(sqe|gmu|zap)|Direct firmware load" extracted-r15/…/07-sys/dmesg-FULL.txt
```

Docs hermanos consultados: `INVENTARIO-VENDOR-UKE.md` (firmware GPU/zap, display
userspace), `NOTAS-FRENTE-1.md` (extracción super, `firmware_mnt` dinámico),
`docs/UBUNTU-BOOT.md` (init_boot vs vendor_boot, `rdinit`, LEY RAMDISK_SZ, vermagic).
