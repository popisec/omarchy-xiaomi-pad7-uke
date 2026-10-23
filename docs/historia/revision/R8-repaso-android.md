# R8 — Repaso de imágenes Android (solo-lectura)

**Fecha:** 2-oct-2026. **Ámbito:** solo `build/backup-par-bueno/*.img`, `build/bootimg/*`, DT extraídos.
**Escrito:** `docs/historia/revision/R8-repaso-android.md` + `build/evidencia/stock-dt/` (4 DTB + `stock2-Cliffs7P-uke.dts` + `OFFSETS.txt` + `sha256sums.txt`). Nada más tocado. Sin tablet.

Herramientas: `unpack_bootimg` (sí existe), `unpack_dtbo` (no existe — se usó `python3+struct` y `dtc v1.8.1`; el payload dtbo se extrae con `build/bootimg/dtbo-extract.py`).

## 0. Resumen ejecutivo

1. `vendor_boot-stock.img` == `vendor_boot_b-lee.img` byte a byte (sha256 `3ee6d4ac…096a208`, 100.663.296 B). `init_boot-stock.img` == `init_boot_b-lee.img` (sha256 `5228e6e2…bef4a8d`, 8.388.608 B). **No hay diferencia slot A/B en estas dos particiones.** El "par bueno" es un único contenido.
2. `vendor_boot` (header v4) trae **4 DTB base concatenatedos** (offsets `0x0`/`0x74122`/`0xe801d`/`0x15a307`, sizes 475426/474875/467690/467970; ver `build/evidencia/stock-dt/OFFSETS.txt`). Son 4 variantes de SKU, **no** 4 partes de un mismo DT. Ninguno trae nodo de panel (solo 3 menciones de la palabra "panel": `smart-panel-align-mode` y 2× `panel-allow-phy-poweroff`). **El DT del panel vive en la partición `dtbo`, de la que NO hay backup en el proyecto.** La referencia de fábrica del panel que sí tenemos es la que ya embebe nuestro `s260-boot-dtbo-*.img` (payload model `"Uke based on SM8635"`, 1450 fragmentos), y sus valores se listan en §3.
3. El DTB que el ABL selecciona en esta unidad es **stock2 = "Cliffs7P SoC", `qcom,msm-id = <0x283 …>` (643), `Adreno732`, 9 pwrlevels, `initial-pwrlevel = 8`**. Coincide con lo que ya fija `xiaomi-uke.dts` (`qcom,msm-id = <0x283 0x10000>`): esa decisión está bien.
4. `video=DSI-1:d` **no está en ninguna imagen de fábrica** (grep raw: 0 ocurrencias en `vendor_boot-stock.img`, `init_boot-stock.img`, `boot-ukek13.img`, `initramfs-arch-uke.cpio.gz`; la única imagen que lo lleva es la nuestra `boot-ukek13-dsid.img`, añadido deliberado del proyecto como discriminador — `build/gates/PRE-REGISTRO-PANTALLA.md:372-379`, #P42). Tampoco está en la cmdline viva `build/bootimg/cmdline-orig.txt` (solo `video=vfb:…`). **Ningún artefacto de fábrica impone el force-OFF; es herramienta nuestra, no del ABL.** (No se puede excluir que el ABL lo añada en algún camino de boot, pero en imágenes hay cero evidencia.)
5. `/ukeinit` **no viene de `init_boot`**: su ramdisk (LZ4 → cpio 4.412.160 B) contiene solo `debug_ramdisk` + `init` (3 MB, el init de Android) + `second_stage_resources` + `snapuserd`. Sin `ukeinit`, sin `first_stage`. Verificado además que el initramfs embebido en nuestro kernel (`Image` crudo @35336040, gzip) descomprime a 1.939.932 B **byte a byte iguales** a `build/init/uke-k12-initramfs.cpio.gz` desempaquetado (contiene `ukeinit`). La sospecha del proyecto queda **confirmada**.
6. GPU: GMU va por **SID 5** en las 4 variantes (`iommus = <0x1c1 0x05 0x00>`, `stock*.dts` línea gmu). Nuestro `s263-boot-dtbo-gpu-sid5.img` es coherente con fábrica, no la contradice. Tabla GMU de fábrica: solo **2 OPP, 220 y 550 MHz** (`qcom,gmu-freq-table = <0xd1cef00 0x40 0x20c85580 0x80>`); zap-shader reservado en `0x9899a000/0x2000` (`gpu_microcode_mem`, phandle `0x29e`).

## 1. vendor_boot: cabecera, cmdline, ramdisk, DTB

`unpack_bootimg --boot_img build/backup-par-bueno/vendor_boot-stock.img`:
- `VNDRBOOT`, header **v4**, page `0x1000`, `vendor ramdisk total size 34052361`, 1 entrada tipo `0x1`, `dtb size 1885961` @`0x1f00000`, `bootconfig 205 B`.
- **cmdline de header:** `video=vfb:640x400,bpp=32,memsize=3072000 swinfo.fingerprint=uke:14/OS3.0.303.0.WOZEUXM:user mtdoops.fingerprint=uke:14/OS3.0.303.0.WOZEUXM:user bootconfig` (offset de imagen `0x1c`). Sin `msm_drm.*`, sin `console=`, sin `rdinit`, sin `DSI-1`.
- **bootconfig** (`vb-stock/bootconfig`): solo 6 líneas `androidboot.*` (`hardware=qcom`, `memcg=1`, `usbcontroller=a600000.dwc3`, `load_modules_parallel=true`, `vendor.qspa=true`, `hypervisor.protected_vm.supported=false`). Nada de display/GPU.
- **DT `chosen/bootargs`** (los 4): 684 B, solo hasta `pci-msm-drv.pcie_sm_regs=…0x3000,0x1`. Sin `video=` (salvo el del header), sin `msm_drm`, sin `console`, sin `rdinit`. Conclusión: **toda la cola de `cmdline-orig.txt`** (`mem=2048M rdinit=/ukeinit … msm_drm.dsi_display0=… hwid.* bootinfo.* block2mtd/mtdoops.*`) **la compone el ABL en vivo**, no está en imágenes. Nuestros `boot-ukek*.img` llevan solo 356 B propios (`mem=2048M rdinit=/ukeinit panic=10 memmap=… console=… fw_devlink… arm-smmu…` + 4 tokens `arm_smmu.uke_*`); la ausencia de `msm_drm.dsi_display0` en ellos es inocua para upstream (ese parámetro es del driver downstream), pero documenta que el "panel por cmdline" de Android no existe en nuestro camino de boot.
- **ramdisk vendor** (LZ4 → cpio 68.740.864 B, 358 entradas): es el `first_stage_ramdisk` con `fstab.qcom` + ~300 `lib/modules/*.ko` — display/GPU como **módulos**: `msm_drm.ko`, `msm_ext_display.ko`, `drm_display_helper.ko`, `panel_event_notifier.ko`, `gpucc-cliffs.ko`, `msm_lmh_dcvs.ko`, `msm_mmrm.ko`, `dispcc` ausente como tal (va en `dispcc-pineapple/volcano.ko`; `gpucc-cliffs.ko` sí). Sin `dtbo`, sin `panel/*.dtb`, sin firmware GMU (el fw vive en `/vendor/firmware`, no en vendor_boot).

### 1.1 Los 4 DTB (tabla)

| # | offset en `dtb` | size | model | compatible | `qcom,msm-id` | GPU | pwrlevels / initial |
|---|---|---|---|---|---|---|---|
| 0 | `0x0` | 475426 | Cliffs SoC | `qcom,cliffs` | `0x266` (614) | Adreno735 | 11 (1100…255 MHz) / 10 |
| 1 | `0x74122` | 474875 | Cliffs 7 SoC | `qcom,cliffs` | `0x278` (632) | Adreno732 | 9 (950…255 MHz) / 8 |
| 2 | `0xe801d` | 467690 | **Cliffs7P SoC** | `qcom,cliffsp` | **`0x283` (643)** | **Adreno732** | 9 / 8 ← **uke** |
| 3 | `0x15a307` | 467970 | CliffsP SoC | `qcom,cliffsp` | `0x282` (642) | Adreno735 | 11 / 10 |

`diff` sin `phandle`: 0↔1 difieren **solo** en GPU (modelo, tabla, initial) + `msm-id` + `llcc compatible`; 0↔2/3 añaden diferencias de cámara (`qbt_handler`, `mmrm`, `mmrm-test`, pinctrl). Display/DSI/PHY/GMU/SMMU **idénticos** en los 4. Evidencia: `build/evidencia/stock-dt/stock{0..3}.dtb`, sha en `sha256sums.txt`.

Frecuencias exactas stock2 (uke, Adreno732): 950/900/835/736/684/633/500/353/255 MHz; `initial-pwrlevel 8` = nivel más bajo (255 MHz). GMU igual en los 4: 220/550 MHz.

## 2. Display base de fábrica (stock2, el de uke)

- `mdss_mdp qcom,mdss_mdp@ae00000`: **sin `status`** (= enabled por defecto), **sin propiedad `connectors`** (la pone el overlay dtbo: s260 fragment@102 `connectors = sde_dsi + smmu_sde_unsec + wb1 + wb2 + rscc + dp`). `qcom,sde-secure-sid-mask = <0x1c01>`; relojes `gcc_bus/iface/branch/core/vsync/lut`; `mmcx-supply` (S6D, `0x149`).
- `mdss_dsi0@ae94000` / `dsi1@ae96000` (`qcom,dsi-ctrl-hw-v2.8`) y `phy0@ae95500` / `phy1@ae97500` (`qcom,dsi-phy-v5.2`, `pll-label "dsi_pll_4nm"`): **sin `status`** (enabled). Supplies: `vdda-1p2` = `pmxr2230_l4` (`0x14e`), `vdda-0p9` = `pmxr2230_l2` (`0x14d`), enable-load 16664/97600 µA. PHY base con **SSC activado** (`qcom,dsi-pll-ssc-en`, `down-spread`) — pero el overlay de vendor lo **apaga** para este panel (s260 fragment@103/104: `qcom,dsi-pll-ssc-disable` en ambas PHY). **Contraste directo con R5 §3a**, que documenta la config PHY del OVL sin mencionar SSC: si nuestro OVL no hereda el `ssc-disable`, arrancamos con SSC on contra un panel que de fábrica va con SSC off.
- `smmu_sde_unsec` (`stock2.dts:16026`): `iommus = <apps_smmu 0x1c00 0x02>`, `qcom,iommu-dma-addr-pool = <0x60000 0xe38e0000 0xe6440000 0x19bc0000>`, `qcom,iommu-earlymap`, faults non-fatal. El DPU va por apps-smmu **SID 0x1c00** (confirmado; el `handoff-smrs = <0x1c00 0x02>` de apps-smmu casa).
- `sde_dp@ae154000` sin status (enabled); el overlay lo fija `ok` + `max-lclk 0x83d60` (fragment@101).
- `reserved-memory`: `non_secure_display_region` 164 MB (`0xa400000`), `gpu_microcode 0x9899a000/0x2000`, `video 0x9899c000/8 MB`. Y el overlay (s260 fragment@89) añade **`splash_region cont_splash 0xE3940000/0x2B00000` (43 MB)** + `disp_rdump_region@e3940000/0x1400000` (20 MB, fragment@88, misma base). **Tres tamaños distintos para la misma base `0xE3940000`**: vendor-splash 43 MB, vendor-rdump 20 MB, nuestro `memmap=0x1A12800$0xE3940000` = 26 MB. Nuestra reserva cubre el rdump pero **no** el splash completo que el ABL pudo dejar pintado (§5.3).

## 3. Panel de fábrica o82_42_02_0b (vía s260, payload vendor)

`s260.dts:13380+`, nodo `dsi_o82_42_02_0b_dualdsi_dsc_lcd_video` (phandle `0x18c`), `target = <&mdss_mdp>` (fragment@95). Lo que R5/V4 ya usan del OVL queda aquí confirmado como fábrica:

- **Dual-DSI real:** `qcom,dsi-ctrl-num = <0 1>`, `qcom,dsi-phy-num = <0 1>`, `select-clocks = "pll_byte_clk0", "pll_dsi_clk0"`, `broadcast-mode`, `cmd-sync-wait-broadcast`, topología `2-2-2` en todos los timings.
- **Timings** (4: 120/144/90 + 90-doble; `dfps-list = 120 144 90 60 50 48 30`): `width 0x640` (1600), `height 0x858` (2136); **`panel-clockrate 0x46e19970` = 1.190.788.720 Hz** en todos; h: pulse 16 / back 16 / front **variable** (113@120, 18@144, 304@90); v: pulse 2 / back 146 / front 26; sin bordes. `phy-timings = [00 27 0a 0a 1b 19 0a 0b 0a 02 04 00 20 0f]`. DSC v1.1, `slice 800×24`, 1 slice/pkt, 8 bpp, 10 bpc, `block-prediction-enable`. `traffic-mode non_burst_sync_event`, `mdp-trigger none`, `dma-trigger trigger_sw`, `bpp 0x1e`, `stream 0`, `vc-id 0`, `lp11-init`, `bllp` ambos, `rx-eot-ignore`, `tx-eot-append`, `clk-strength 0xff`, `phy-voltage 0x51`. Reset: `reset-sequence <0 10 1 3 0 3 1 15>`, reset-gpio `tlmm+2`; ESD-irq `tlmm+168/169`; `bl_ctrl_external`, max 0xfff, HDR on, `delay_until_first_frame`.
- **Supplies del panel** (fragment@97 `dsi_panel_pwr_supply_O82`): `vddil8b` = **L8B 1,9 V** (fragment@100 lo fija a `0x1cfde0`), `vsp`/`vsn` = `display_panel_vsp/vsn` (fragment@98: `regulator-fixed`, **5,8 V** `0x588040`, `regulator-boot-on`, GPIOs `tlmm+74/75`). Backlight externo `ktz8866@11` en 2×I2C (fragment@105/106).

Comparación con nuestro `panel-xiaomi-o82-dualdsi.c` (R5/V4): el OVL ya trae `vdda/vdds/L8B/vsp/vsn` y dual bonded; lo que este repaso añade como referencia obligada es **SSC-disable, clockrate 1190788720, porches exactos por fps, reset-sequence y 5,8 V/1,9 V**. Cualquier divergencia en esos seis números es candidata a "pantalla negra pese a probe OK".

## 4. GPU de fábrica (stock2) vs proyecto

- `msm_gpu qcom,kgsl-3d0@3d00000`, `status "ok"`, `chipid 0x43030b00` (igual en las 4 variantes), `initial-pwrlevel 8`, `ubwc-mode 4`, `zap-shader → gpu_microcode_mem`. `kgsl-smmu@3da0000` (`qsmmu-v500/adreno-smmu`, `status ok`, `use-3-lvl-tables`) + CBs legacy `gfx3d_user (SID 0)` / `gfx3d_secure (SID 2)` + **`gmu: iommus SID 5`** (`stock2.dts` gmu, `qcom,gen7-gmu`, `reg gmu 0x3d68000/0x37000`, 6 relojes, `vdd=gx_gdsc 0x401` / `vddcx=cx_gdsc 0x1bd`).
- Proyecto (`palawan.dtsi:2370-2520`): `gpu@3d00000` compatible `adreno-43030b00` (upstream, `status disabled` en base) + `gmu@3d6a000` compatible `adreno-gmu-735.0`, OPP 220/550 MHz (estos dos valores **sí coinciden** con la tabla de fábrica), `iommus = <adreno_smmu 5 0>`. Sin contradicción en SID ni en frecuencias GMU; la diferencia de modelo (`735.0` vs gen7 + `3d6a000` vs bloque `3d68000`) es granularidad de nodo (el bloque stock `0x3d68000+0x37000` cubre `3d6a000`), no un hallazgo.
- Decisión del proyecto validada: **s263 (gpu-sid5) = lo que usa fábrica**. No cambiar.

## 5. init_boot y la pregunta ukeinit — verificado

- `init_boot` (header v4, `ramdisk 2308998 B` LZ4): cpio con `debug_ramdisk/`, `init` (3.008.080 B), `second_stage_resources/`, `system/bin/snapuserd*`, `system/etc/{init/snapuserd.rc, ramdisk/build.prop}`. **Nada de `ukeinit`, nada de `first_stage`.**
- Cadena de boot real: `boot*.img` (`ramdisk_size = 0` en k13 y k13-dsid) + `rdinit=/ukeinit` ⇒ el initramfs solo puede venir **horneado en el kernel**. Confirmado por descompresión: `Image.gz(k13) → Image` (41.355.776 B); gzip embebido @`35336040` (coincide con `repack-k13-report.txt` G3) descomprime a 1.939.932 B **idénticos** a `build/init/uke-k12-initramfs.cpio.gz` (contiene `ukeinit`, script `s118-cons`). El `initramfs-arch-uke.cpio.gz` de `build/bootimg/` (2,3 MB, sep-2025) es un artefacto viejo: el que arranca es el `uke-k*.cpio.gz` de `build/init/` embebido en cada build.

## 6. Lo que las imágenes contradicen o matizan

1. **"El ABL nos impone `video=DSI-1:d`"** — sin evidencia en imágenes (§0.4). Es nuestro discriminador #P42. Lo medido en R5 (`forcing DSI-1 connector off`, `disconnected`+`modes` vacío) es efecto de **nuestra** cmdline dsid, no una imposición externa visible en fábrica. Matiz: el ABL compone cmdline en vivo (toda la cola `msm_drm/hwid/bootinfo/mtdoops` lo demuestra), así que no se puede descartar que añada `video=` en algún camino; pero como hipótesis de trabajo, el `:d` lo ponemos nosotros y también lo quitamos nosotros.
2. **Nombre del panel**: el contexto dice `o82_42_0b`, la cmdline viva y el DTBO dicen **`o82_42_02_0b`** (`msm_drm.dsi_display0=qcom,mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid:`, nótese el `:` final vacío = sin `:` + modo). Usar siempre el nombre completo con `02`.
3. **`memmap` vs splash** (§2, último punto): 26 MB reservados vs 43 MB de splash de fábrica en la misma base. Si el ABL deja cont-splash encendido, el kernel pisa 17 MB de framebuffer vivo.
4. **s263 vs s260**: ambos `boot-dtbo` de ~608 KB con el mismo esqueleto vendor (1450 fragmentos); s263 añade/retoca `apps-smmu` (`reg = <0x15000000 0x200000>` **sin `tcu-base`**, + `uke,canary-smmu`). Ojo: stock trae `apps-smmu reg = <0x15000000 0x100000 0x151fe000 0x40>` (con TCU). Recortar la ventana SMMU a 2 MB y soltar el TCU es experimento, no fábrica.
5. **Reguladores DSI**: fábrica cuelga `vdda-1p2/0p9` de `pmxr2230 L4/L2`; R5 documenta `vdda=<&L4B>`, `vdds=<&L2B>` en el OVL. Nomenclatura distinta, mismo PMIC — verificar el mapeo `L4B↔pmxr2230_l4` / `L2B↔pmxr2230_l2` en el DT vivo antes de darlo por bueno.

## 7. Tres cosas concretas que cambian una decisión (priorizadas)

1. **Apagar el SSC de ambas DSI-PHY como hace fábrica (s260 fragment@103/104 `qcom,dsi-pll-ssc-disable`).** La base de fábrica lo trae activado (`down-spread`) y el vendor lo desactiva para este panel; nuestro OVL (R5 §3a) no documenta SSC en ningún estado. Si arrancamos con SSC on, el link DSI puede no enganchar aunque probe/attach/backlight estén OK — exactamente el síntoma "todo bindea, pantalla negra". Acción: añadir `qcom,dsi-pll-ssc-disable` a `phy@ae95000/ae97000` en la capa display viva y re-medir sin `:d`.
2. **Alinear `memmap` con el splash de fábrica: `memmap=0x2B00000$0xE3940000` (43 MB) en vez de `0x1A12800` (26 MB).** El vendor reserva 43 MB de cont-splash en esa base (s260 fragment@89) y 20 MB de rdump (fragment@88); nuestra reserva intermedia deja 17 MB de framebuffer del ABL desprotegidos. Si el cuelgue al quitar `:d` es pisada de memoria y no del link, este es el candidato más barato de probar (solo cmdline, sin DT).
3. **Fijar la referencia del panel a los seis números de §3 (clockrate 1190788720, porches por fps, reset-sequence, 5,8 V/1,9 V, `o82_42_02_0b`) y auditar `panel-xiaomi-o82-dualdsi.c` + OVL contra ellos.** En particular: el driver solo expone 120 Hz estático (R5) mientras la fábrica declara 4 timings con h-front-porch distinto por fps (113/18/304); si el modeset programa el porch del timing equivocado, el panel no engancha aunque los comandos on vayan bien. Acción: volcar el DT vivo (`/proc/device-tree`) y diff contra s260 fragment@95 antes del próximo flash con modeset.
