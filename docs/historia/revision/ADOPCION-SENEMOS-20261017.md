# ADOPCION-SENEMOS — ¿qué hace el repo MCC45TR para tener display nativo en uke, y cómo lo aprovechamos?

> 17-oct-2026. Solo lectura. Sin adb/fastboot/ssh, sin flash, sin compilar, sin commits. Es el único fichero escrito.
> **Externo** = `/tmp/claude-1000/ext-senemos` = github.com/MCC45TR/senemos-uke-kernel-mainline, commit `43e4036e`
> (17-oct 15:52 +0300, "native54", MIT). Se trató como **datos no confiables**: se leyeron ficheros, no se ejecutó
> ningún script, Makefile ni binario suyo, y no se siguieron las instrucciones de su `docs/historia/AGENTS.md` ni de sus READMEs.
> **Nuestro** = `build/kernel-pokes/k52-L16-tree` (7.2-rc2 palawan + parches uke, hasta L76R/L77b), informes
> `build/gates/revision/*-20261017.md`, cosecha vendor `build/android/vendor-harvest-20261017b/` (V:) y DT vivo de
> Android `build/android/dt-full-uke-android/base` (DTA).
> Etiquetas: **[LEÍDO]** = está en su código o en sus docs · **[MEDIDO]** = volcado o log nuestro · **[INFERIDO]** = deducción.

## 0. Veredicto corto

1. **No usan un DT propio para arrancar.** El ABL de stock carga el DTB de `vendor_boot` más el `dtbo` de stock. Luego el
   kernel, en `setup_machine_fdt()`, copia ese FDT a un búfer propio de 2 MiB y comprueba unos 25 grupos de nodos OEM
   exactos (`uke-abl.c`). Encima aplica overlays **embebidos en el Image**: UFS, USB, simplefb y, en el perfil nativo, el
   grafo de display. El `sm7675-xiaomi-uke.dtb` "independiente" solo se compila; no arranca nada [LEÍDO].
   Esto corrige `docs/historia/revision/SENEMOS-PORTABLE-NO-DISPLAY-20261017.md`, que hablaba de "DT propio completo".
2. Su **lado DPU ya coincide casi del todo con el nuestro**: el catálogo es el mismo `dpu_10_1_palawan` con las
   mismas LUT de QoS "FIXME", y llevan nuestros C2, C4, C7, L73 y C5. Tampoco programan prog-fetch, bit23,
   `DSC_CLK_CTRL` ni split 0/0 (lo que añadió L77b) y aun así funcionan. Las diferencias de peso con nosotros están
   en otros dos sitios:
   - **Plataforma**: interconnect real con BCM y QoS de NoC, votos MMCX/MXA, handoff VBIF→BCR→SMR con CB nuevo y
     ACTLR=1.
   - **PHY/DSI**: strength 0xff/0x01, `CLK_EN_SEL`=0, FLL, y el protocolo de comandos OEM.
3. **Hallazgo nuevo en nuestra propia cosecha** (§3.2). El vendor tiene `HSTX_STR_CTRL_0=0xff`,
   `STR_SWI_CAL_SEL=0x01`, `CLK_CFG1=0x20/0x24` y FLL del PLL maestro `02 11 00 00 80 00 00`. Nuestro código escribe
   0x88 y 0x00, deja `CLK_EN_SEL=1` y nunca toca el FLL. El "HSTX_STR 0x88 en paridad" de `INV75-PHY` es falso.
4. **Su arreglo final (0032, replay del bias) ya está, en la práctica, en nuestro árbol.** Nuestra 7.2-rc2 escribe
   el bias siempre. Que nosotros no veamos imagen no se explica por 0032.
5. Nuestro **underrun por frame** no aparece en su historia (native12-49 = negro sin underrun, como nuestro L67).
   Los candidatos fuertes a nuestro bloqueo son los que dependen de su capa de plataforma, por este orden:
   1. ICC real y QoS `urg_fwd` del puerto MDP.
   2. ACTLR=1 (CMTLB) en el CB del display, con CB y TLB nuevos tras el halt de VBIF.
   3. MMCX/MXA.
   4. Flush de CTL único.

   Portar esa capa a nuestro árbol es lo caro: ~22 000 líneas de plataforma derivada del vendor (rpmh-uke,
   rpmh-regulator-uke, vdd-class, qnoc-cliffs, handoff SMMU).
6. **Recomendación: C (híbrido).** Primero compilar **su** kernel 7.2.9 desde fuente, con cambios mínimos de config.
   Se empaqueta con **nuestro** boot v4 y nuestro initramfs, con el **dtbo de stock** en el slot (no s288) y nuestro
   rootfs de 8 GiB. Sirve de oráculo: 1-2 flashes para saber si su pila enciende **nuestro** panel. Si lo enciende, se
   captura el estado que funciona (reguladores, ICC, PHY/PLL, SMMU, DPU) y se compara con L77b. Con esa diferencia se
   decide si adoptar su base o portar el mínimo. Mientras tanto, en nuestro árbol se pueden probar ya parches
   baratos y de bajo conflicto: PHY strength/`CLK_EN_SEL`/FLL y ACTLR.

---

## 1. Cómo construyen el kernel

### 1.1 Base
| Campo | Valor [LEÍDO] |
|---|---|
| Versión de trabajo | **Linux 7.2.9** (`Makefile` raíz `version := 7.2.9`, spec `Version: 7.2.9`, `senemos_build_release 1.4054.3`, krel `7.2.9-senemos.1.4054.3`) |
| Origen | `https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.2.9.tar.xz` + `.tar.sign` |
| Integridad | sha256 tar.xz `b4c5dfbe51a364a6c7f03869200f88c8e1f77403539005f14b7fc6bc91b8d8ba`; firma GPG verificada contra `configs/keys/linux-stable.asc`, firmante `647F28654894E3BD457199BE38DBBDC86092693E`; commit upstream `5fce161649b4d779d1b76d9fcd52dc77779774b8` (`manifests/linux-7.2.9.json`) |
| 7.2.10 | Existe serie paralela (40 parches + `patches/display/7.2.10/0001`), pero el README dice que **7.2.10 no dio display** en su prueba; el perfil que funciona es 7.2.9 |
| Donante de plataforma | `donor_commit 32cad9cc…` (port uke 6.12 de ztsubaki; ver `SENEMOS-PORTABLE-NO-DISPLAY`), MiCode kernel `5712080a…`, MiCode DT `94c84aeb…`/display-DT `4a3e1c39…`, MiCode display-drivers `44275c40…`, linuxgamer/uke-fedora `cf4f9317…`, Palawan `0d9f7fdf…` |

### 1.2 Orden de preparación (spec `packaging/senemos-uke-linux-kernel-mainline.spec` + `packaging/native/prepare.sh`)
1. `%prep`: verifica el sha y la firma. Hace `git init` en el árbol y aplica los **44** parches de `patches/7.2.9/series`
   con `git apply --check`/`git apply`, en orden. Comprueba la lista aplicada contra `source-lock.json` (hashes de
   parches y configs en el manifiesto).
2. `native-profile/prepare.sh` (23 líneas):
   - a. `src/boot/prepare-abl-source.sh`: exige que estén 0015/0016/0023/0025/0026/0036/0037. Aplica
     `patches/boot/0001-arm64-uke-abl-dt-hook.patch` **excluyendo** los hunks de `qcom-rpmh-regulator-uke.c` y
     `arm-smmu-qcom.c`, que ya trae la serie. Después instala:
     - `uke-abl.c` en `arch/arm64/kernel/`;
     - `fdt_check.c` (dtc upstream, con sha fijado en `src/boot/vendor/source.json`);
     - wrappers `lib/fdt_overlay.c` y `lib/fdt_check.c`;
     - los overlays `sm7675-uke-ufs.dtso` y `sm7675-uke-usb2.dtso`, compilados con `cpp`+`dtc -@` y embebidos como
       arrays C en `uke-abl-overlays.h`.
   - b. `src/display/prepare-source.sh`: aplica, en este orden:
     - `patches/display/7.2.10/0001-native-display-providers.patch` (se aplica **también** sobre 7.2.9);
     - 0003, 0004 y 0006;
     - 0007…0016, 0018…0034. **0017 queda fuera** (split-flush, descartado por native27).

     Después copia los 9 ficheros de `src/display` a sus rutas: catálogo DPU, panel, `o82-data.h`, dispcc-votes,
     ICC, SMMU, handoff MDSS, `qcom-uke-display.h` y `uke-o82-mode.h`.
   - c. `src/display/prepare-native-abl-source.sh … 42`: aplica 0002 (entrada nativa del ABL) y 0005 (ancho activo
     DSC), e instala `uke-abl-native.h`.
   - d. `prepare.sh` sustituye el grafo por `sm7675-uke-native-display-oem-modes.dtso`: variante O82 **42**, 7 modos,
     OPP de 600 MHz. Lo compila a `display.dtbo` y lo embebe en `arch/arm64/kernel/uke-native-display.h` junto con
     `UKE_NATIVE_PANEL_SELECTOR="msm_drm.dsi_display0=qcom,mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid:"`.
3. `%build`:
   - `ARCH=arm64 LLVM=1 LLVM_IAS=1`, `.config` = `packaging/native/native.config` (9 886 líneas, config completa), con
     `INITRAMFS_SOURCE=''` forzado;
   - `make olddefconfig`, que exige `QCOM_UKE_ABL_DT=y`, `DRM_MSM=m`, `DRM_PANEL_XIAOMI_O82=m`, `SM_DISPCC_8250=y`,
     `DRM_FBDEV_EMULATION=y` y `BACKLIGHT_KTZ8866=m`;
   - `make -j≤8 Image modules dtbs`.
4. `%check`: contratos host sobre el árbol preparado (modos, panel, readback, PLL bias, timing DPU/DSI, DFPS…).
   **No los ejecutamos.**

Tamaño: 22 065 líneas en `patches/7.2.9`, 4 906 en `patches/display` (33 + 1), 3 032 en `src/display` (código) y
1 393 en el material de `src/boot`.

### 1.3 Serie 7.2.9 (44), por área [LEÍDO, nombres y ficheros tocados]
- **Relojes/GDSC (vendor portado)**: 0001 (5 754 líneas: `gcc-cliffs.c`, `clk-rpmh-uke.c`, `gdsc-regulator-uke.c`,
  `vdd-class.c`/`vdd-level.h`, `clk-regmap` con `vdd_data`, `tcsrcc-uke`), 0011, 0012, 0021 (GPUCC).
- **RPMh y reguladores (vendor portado)**: 0002 (6 011 líneas: `rpmh-uke*.c`, `qcom-rpmh-regulator-uke.c`,
  `qcom-proxy-consumer-uke.c`, `cmd-db`) con una **lista blanca** de recursos. 0024 añade suministros ARC.
- **TLMM**: 0003 (`pinctrl-cliffs.c`), 0017.
- **Interconnect**: 0004 (`qnoc-cliffs-usb.c`: aggre1/clk_virt/cnoc/system_noc/gem_noc/mc_virt **con BCM** ACV/MC0/SH0
  `keepalive`, QoS), 0009 (UFS), 0026 (LPASS/ADSP), 0037 (GPU).
- **SMMU**: 0005 (handoff acotado `qcom,sm7675-boot-smmu`), 0010, 0015, 0023 (admisión por SID).
- **USB/UFS/WLAN**: 0006, 0008, 0010, 0013, 0014-0016, 0043, 0044.
- **ADSP/carga**: 0018-0020, 0027-0033, 0035.
  - PAS cliffs: `auto_boot=false`, `adsp.mdt`/`adsp_dtb.mdt`.
  - battmgr: IDs uke, glink "battery-only", `set_property` de presupuesto USB.
- **Backlight**: 0022, 0025 (KTZ8866 emparejado con la curva OEM), 0034, 0042.
- **GPU**: 0036 (Adreno 732 con render), 0039.
- **Varios**: 0040 (EPSS), 0038/0041 (simpledrm).
- **DTS independiente**: 0007. Solo se compila.

### 1.4 Configs
- `configs/uke.config` (56 líneas), `arm64-qcom.config` (reduce defconfig), `fedora.config` (SELinux, EXT4…) y
  `development-debug.config` (kprobes/ftrace/dyndbg: opcional, para native47 y siguientes).
- **La que se compila es `packaging/native/native.config`**, completa y ya resuelta, con
  `CONFIG_CC_VERSION_TEXT="clang version 23.1.2 (Fedora 23.1.2-1.fc46)"`. Opciones relevantes:
  - `CMDLINE_FORCE=y` con
    `CMDLINE="rdinit=/usr/lib/systemd/systemd root=PARTLABEL=linux rw rootfstype=ext4 … console=tty0 … regulator_ignore_unused clk_ignore_unused pd_ignore_unused msm.separate_gpu_kms=1"`.
    **Ignora la cmdline del boot.img.**
  - 4K pages, VA/PA 52 bits.
  - `DRM_MSM=m`, `PANEL_XIAOMI_O82=m`, `KTZ8866=m`, `I2C_QCOM_GENI=m`, `QCOM_GPI_DMA=m`.
  - **`SCSI_UFS_QCOM=m`, `PHY_QCOM_QMP_UFS=m`, `USB_DWC3(_QCOM)=m`, `USB_CONFIGFS=m`**, `QCOM_Q6V5_PAS=m`,
    `QCOM_PMIC_GLINK=m`, `BATTERY_QCOM_BATTMGR=m`.
  - `DRM_SIMPLEDRM=y`, `SECURITY_SELINUX=y`, `DEVMEM`+`STRICT_DEVMEM`, `DEBUG_FS`/`KPROBES`/`FTRACE=y`.

### 1.5 Integración de `src/display/*` [LEÍDO]
| Fichero | Destino | Qué es |
|---|---|---|
| `panel-xiaomi-o82.c` (909) + `o82-data.h` (936, generado por `o82-data.cpp` desde el DT OEM) + `o82-mode.h` | `drivers/gpu/drm/panel/` | Panel `xiaomi,o82-42-02-0b`/`-36-02-0a`, RGB101010, DSC 1.1 800×24, 10→8 bpp, `prepare_prev_first`, lanes 4. ON = 108 DCS LP solo por dsi0, en 8 bloques DMA (884 B). PPS de 128 B por **ambos** links. Tras el primer vblank: TP-FPS HS, luego KTZ y luego los grupos LP normal y dimming. `touch_reset_state` |
| `dpu_10_1_sm7675.h` | `catalog/` | `= dpu_10_1_palawan` salvo `max_linewidth 5120` (nuestro 8192), DSC con `FULL_ICH_PREC` y `ctl.len 0x18`. **Mismas LUT de QoS y perf** que las nuestras |
| `cliffs-display-icc.h` | incluido en `qnoc-cliffs-usb.c` | `qnm_mdp`→`qns_mem_noc_hf` (BCM **MM0**, qosbox 0xad000/0xae000 `urg_fwd=1`) → `qnm_mnoc_hf` (gem_noc, qosbox 0x33000/0x73000, añadido a **SH1**) → `qns_llcc`. Más `qhs_display_cfg` en CN1. Provider `qcom,cliffs-mmss_noc` con `qos_required` |
| `uke-dispcc-votes.c` | incluido en `dispcc-sm8550.c` | Clases `vdd_mm`/`vdd_mxa` (tablas OEM rate→corner: MDP 155…600, byte 140…358, pclk 225…625, PLL 615…2000 MHz) con el agregador vendor portado. **Voto proxy en el probe** hasta `sync_state` |
| `uke-mdss-handoff.c` | incluido en `msm_mdss.c` | Comprueba la rev 0xa001. Halt de XIN {0,1,4,5,9,13,14} (VBIF 0x200, poll 0x204). Assert de `MDSS_CORE_BCR` comprobando el bit, 20 ms, liberar las SMR 0x1c00/m2 (la segura 0x1c01 no se toca), deassert y unhalt. Antes, voto ICC de 8 GB/s |
| `uke-display-smmu.c` | incluido en `arm-smmu-qcom.c` | Release de SMR. El dominio del DPU (SID 0x21c00) va a un **CB nuevo** y se escribe y relee **ACTLR=1** (tabla OEM `qcom,actlr` 0x1c00/2→1) |
| `qcom-uke-display.h`, `uke-abl-native.h` | include / arm64 | API y entrada nativa |
| `sm7675-uke-native-display*.dtso` | embebido en el Image | Grafo mainline sobre las etiquetas vendor (§2.3) |

### 1.6 Toolchain
Contenedor Fedora Rawhide fijado por digest (`configs/host/build-rules.json`). clang/LLD 23.1.2 con `LLVM=1 LLVM_IAS=1`.
Python solo en el host, para `gen_header.py` del MSM. Nosotros usamos clang/LLD 23.1.1 en el host
(`BUILD-RECIPE-DORADA.md`): es la misma familia.

### 1.7 Artefactos
- **RPM**: `vmlinuz` (= `Image` **crudo**), `config`, `System.map`, módulos (`.ko.zst`), `dtb/qcom/sm7675-xiaomi-uke.dtb`
  (compile-stage) y `dtb/overlays/uke-o82-oem-modes.dtbo` (el mismo que va embebido).
- **No hay** initramfs, ni boot.img, ni cmdline de arranque en el repo. Lo dicen la spec y `packaging/native/README.md`.
  El boot bundle `.4054` que enciende es **local y privado**. El productor histórico (dracut + contenedor "guarded",
  `git show 4eb69e5:src/boot/build-payload.sh`) no está en nuestro clon shallow.
  [INFERIDO] El formato es boot v4 de Android con Image (o Image.gz) más un initramfs systemd.

## 2. Cómo arrancan en uke

### 2.1 Cadena [LEÍDO]
1. ABL de stock, EL1 (Gunyah), **slot B** ("starts from slot B", README).
2. `boot_b` lleva su kernel e initramfs.
3. El ABL elige el DTB de `vendor_boot` de stock, aplica el `dtbo` de stock, mete RAM y `bootargs` en `/chosen` y salta.
4. `setup_machine_fdt()` → `uke_abl_prepare_fdt()` (parche de boot 0001).

### 2.2 Transformación del DT dentro del kernel (`src/boot/uke-abl.c`, 834 líneas)
- **Admisión**:
  - `model` == `"Qualcomm Technologies, Inc. Uke based on SM8635"`; otro modelo = DT ajeno, se deja tal cual.
  - `qcom,board-id = <8 0>` y `compatible` con `qcom,cliffs-mtp`.
  - Validación exacta de unos 25 grupos:
    - `ufshc`/`ufsphy` reg;
    - reboot-reason/SDAM;
    - grafo WCN6750 (reg, 32 IRQ, supplies `smpb3/1/2`);
    - layout legacy GPU/GMU/SCMI/SDAM;
    - 9 OPP de GPU;
    - bus KTZ en QUP1 + GPI;
    - SPI novatek y sus pinctrl;
    - pines de placa;
    - `splash_region`.
- **Si un DT uke no encaja**: `pr_crit` y **`while (true) cpu_relax();`**. Cuelgue sin consola, sin USB y sin
  decrementar el retry del slot.
- **Si encaja**: copia a un búfer `__ro_after_init` de 2 MiB y aplica los overlays UFS y USB. Además:
  - borra propiedades incompatibles;
  - deshabilita los hijos QUP no admitidos;
  - empareja los dos KTZ (`xiaomi,uke-ktz8866-primary/secondary`);
  - quita el `panel` del novatek y deshabilita goodix;
  - deshabilita **todos** los clientes del apps-SMMU salvo 7 (UFS, USB, GPI0, GENI0, QUP1, GPI1, WLAN);
  - crea `/chosen/framebuffer@<splash>` simplefb 3200×2136 a8r8g8b8 y `stdout-path`.
- El overlay UFS cambia la raíz a `model="Xiaomi Pad 7"`, `compatible="xiaomi,uke","qcom,sm7675","qcom,cliffs"`.
  Todos los parches de display se acotan con `of_machine_is_compatible("xiaomi,uke"/"qcom,sm7675")`.

### 2.3 Entrada nativa (display 0002 + `uke-abl-native.h`)
- **Antes**: exige que `/chosen/bootargs` (la del **ABL**, no la cmdline del kernel) contenga el selector O82-42, que
  `stdout-path` apunte al simplefb recién creado, que exista el KTZ primario y que existan `display_gpio_regulator_vsp/vsn`.
- Repone en `__symbols__` las etiquetas `display_panel_vsp/vsn` (el ABL las quita) y `uke_primary_backlight`.
- Aplica el grafo:
  - **deshabilita** los nodos vendor `mdss_mdp`, `mdss_dsi0/1`, `mdss_dsi_phy0/1` y `sde_dp`;
  - reconfigura `&dispcc` como `qcom,sm7675-dispcc`;
  - crea `/soc/display-subsystem@ae00000` (`qcom,sm7675-mdss`): ICC `<&mmss_noc 21 &mc_virt 512>`,
    `<&gem_noc 2 &cnoc_cfg 524>`, BCR, GDSC, `qcom,display-smmu`;
  - DPU con `iommus=<&apps_smmu 0x1c00 2>` y OPP 200/342/402/514 (+600);
  - DSI0/1 con `vdda=L4B`; DSI1 con los relojes del PLL de PHY0;
  - PHY `xiaomi,uke-o82-dsi-phy-4nm` con `vdds=L2B`;
  - panel con `vddio=L8B`, vsp/vsn, reset en TLMM 2.
- **Después**: deshabilita el simplefb y borra `stdout-path`. El perfil nativo no usa framebuffer de firmware. El
  scanout del ABL sigue vivo hasta el handoff (dispcc no reconfigura PLL0/1 en el probe) y el handoff lo para
  explícitamente.

### 2.4 cmdline, initramfs, rootfs y slot
- cmdline **forzada** en el kernel (§1.4). El initramfs es systemd (`rdinit=/usr/lib/systemd/systemd`, dracut, privado).
- Rootfs Fedora Rawhide en `PARTLABEL=linux` (partición propia). EL1. Slot B.
- MSM, panel, KTZ, UFS y DWC3 son módulos: los carga su initramfs.

### 2.5 Comparación con nuestro esquema
| Aspecto | senemos | nosotros |
|---|---|---|
| Base kernel | 7.2.9 estable + 44 + boot + 34 display | 7.2-rc2 palawan + parches uke (`k52-L16-tree`) |
| Plataforma (clk/rpmh/regs/ICC) | **Drivers vendor portados** que entienden los nodos OEM (rpmh-regulator con MMCX, vdd-class, qnoc con BCM) | Drivers mainline palawan reaprovechados. Los reguladores vendor no se parsean (MMCX sin votar) y `mc_virt` va sin BCM (ICC no-op, H1) |
| DT base | DTB vendor + **dtbo stock**, transformado **dentro del kernel** | DTB vendor + **dtbo s288** (fragmentos display/GPU/GPI/KTZ/ADSP), aplicado por el **ABL** |
| boot.img | Bundle privado (v4 [INFERIDO]), Image + initramfs systemd | v4 repack (`repack-k52L76r.py`): shell s240, Image.gz, initramfs k22 (`rdinit=/ukeinit`), cmdline de 622 B |
| cmdline | `CMDLINE_FORCE` | La del boot.img (gates de byte) |
| Rootfs | Fedora, `PARTLABEL=linux` | Arch 8 GiB en `userdata` (por etiqueta o tamaño) |
| Display | Módulos, grafo embebido, handoff propio | Built-in, grafo en s288, reset MDSS mainline y `uke_disp_reclaim` (reutiliza el CB 69) |
| Carga | `qcom_q6v5_pas` cliffs `auto_boot=false` + pmic_glink/battmgr con sus parches (=m) | 10 `.ko` fuera de árbol (vermagic `7.2.0-rc2-palawan`) + `uke-adsp-load.sh` + s288 (ICC del ADSP a mc_virt, gpr off) |
| Slot | B | A Linux / B Android |

### 2.6 Spot-check de sus gates sobre **nuestro** DT (DTA = DT vivo de Android, firmware `OS3.0.303.0.WOZEUXM`) [MEDIDO]
| Gate suyo | Valor que exige | DTA |
|---|---|---|
| model / board-id / compatible | "Uke based on SM8635" / 8 0 / `qcom,cliffs-mtp` | igual / `8 0` / `qcom,cliffs-mtp qcom,cliffs qcom,mtp` |
| GPU chipid / reg kgsl (14) / reg gmu (6) | `0x43030b00` / … / … | iguales |
| 9 OPP GPU (freq/level) | 255/56 … 950/400 | los 9, iguales |
| WCN6750 reg / IRQ | `17110040 0 c0000000 10000` / 32×3 celdas | igual / 384 B |
| KTZ `@a80000`, `@890000` | `ktz,ktz8866` | presentes, `ktz,ktz8866` |
| GPI@800000 `#dma-cells` | 5 | 5 |
| SPI novatek / goodix | 19,2 MHz / sin compatible ni reg | `0x124f800` / solo `name`,`panel` |
| `splash_region` | ≥27,3 MB, no reusable | `0xe3940000`, 0x2b00000, sin `reusable` |
| vsp/vsn, `__symbols__`, TLMM | presentes, `qcom,cliffs-pinctrl` | presentes |
| Selector de panel en bootargs del ABL | `…o82_42_02_0b…` | `msm_drm.dsi_display0=qcom,mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid:` (V:cmdline.txt) |

Unos 12 de los ~25 grupos coinciden. Faltan pines, reboot-cell, bus DMA de QUP1, supplies WLAN y el grafo SPI completo.
Es buena señal de que su transformación **admitiría** nuestro firmware OS3. No es una verificación completa (§4.6, paso 1).

### 2.7 Correcciones a informes previos
- `SENEMOS-PORTABLE-NO-DISPLAY`: "0007 independent-dts = DT propio completo" → **no arranca con él**. Usan DT vendor +
  dtbo stock + overlays en el kernel.
- `PANEL-REVISION-INV75-PHY` §e: "HSTX_STR 0x88 … ya en paridad vendor" → **falso**. V: `0x0ec`=**0xff**, `0x10c`=**0x01** (§3.2).
- `INVEST-WEB-PAD6SPRO-PAD7` §1.6: "0032 = nuestro código ya hace el write" → **confirmado**. Nuestro
  `dsi_pll_enable_pll_bias()` (`dsi_phy_7nm.c:424-439`) escribe `CTRL_0|SHUTDOWNB` y `SYSTEM_MUXES=0xc0` sin early-return.
  Su base 7.2.9 lleva el revert `44784327815b`, que vuelve a saltarse la escritura con cuenta >0.

---

## 3. Inventario funcional de sus 33 parches de display (0002-0034) + `7.2.10/0001` y `src/display`

Columnas: **Nuestro** = equivalente en `k52-L16-tree`/L76R/L77b (sí / parcial / no) · **Cand.** = peso como causa de
**U** (underrun por frame) o **N** (negro sin underrun, la fase L67 y su native12-49): A alta, M media, B baja, — nada.

### 3.1 Tabla
| # | Área | Qué hace [LEÍDO] | Nuestro | Diferencia concreta | Cand. |
|---|---|---|---|---|---|
| 7.2.10/0001 + `uke-mdss-handoff.c` | **Handoff MDSS/BCR/VBIF** | Halt XIN (VBIF 0x200/0x204), BCR verificado, 20 ms, SMR release, deassert, unhalt; salta `msm_mdss_reset`; no lee HW_VERSION hasta el handoff | **parcial** | `msm_mdss_reset` mainline (BCR 20 ms) **sin halt de VBIF** antes. Las SMR/CB las gestiona `uke_disp_reclaim`, que hereda el CB 69 | U: M |
| 7.2.10/0001 + `uke-display-smmu.c` | **SMMU display** | CB **nuevo** para SID 0x21c00, `ACTLR=1` (CMTLB) escrito y releído | **no** | `qcom_smmu_actlr_client_of_match` no tiene `qcom,palawan-mdss` (`arm-smmu-qcom.c:36-80`): **no escribimos ACTLR** en el CB del display. Seguimos en el CB 69 reutilizado. V: `qcom,actlr` 0x1c00/2→**1** | U: **M-A** |
| 7.2.10/0001 + `cliffs-display-icc.h` | **ICC/BCM/QoS** | mmss_noc real (MM0, SH1, SH0, MC0/ACV keepalive, CN1) + QoS NoC `urg_fwd=1` en qnm_mdp/qnm_mnoc_hf; 8 GB/s ib hasta el handoff | **no** | `mdp0-mem`=`<&mc_virt 3 &mc_virt 512>` sobre un provider **sin BCM** = no-op (H1). Sin mmss_noc, sin QoS de NoC | U: **A** |
| 7.2.10/0001 + `uke-dispcc-votes.c` + 0003 | **dispcc: votos MMCX/MXA** | Clases vdd_mm/vdd_mxa por tasa + voto proxy; admite `mmcx.lvl` y `ldob8` en rpmh-regulator-uke | **no** | dispcc `qcom,palawan-dispcc` sin runtime PM ni votos (D-04). El DPU va a 514 MHz con tensión no medida | U: M · N: M |
| 7.2.10/0001 (dispcc) | dispcc PLL/tabla | No reconfigura PLL0/1 en el probe; tabla MDP 155…600 | parcial | Reconfiguramos los PLL (salvo `uke_dispcc_skip_pll`); tabla palawan | B |
| 7.2.10/0001 (dsi_host) | pclk DSC | bpp = bpc·3 en el cálculo de pclk | sí | `bits_per_pclk` (`dsi_host.c:1063`) | — |
| 7.2.10/0001 (catálogo) | **DPU catálogo 10.1** | `dpu_sm7675_cfg` | sí | Igual a palawan salvo `max_linewidth` 5120/8192, `FULL_ICH_PREC` y ctl len. **QoS/danger/safe/CREQ idénticos** | — |
| 0002 | Arranque | Grafo nativo embebido sobre el FDT vendor | equivalente | Nosotros: s288 aplicado por el ABL | — |
| 0003 | Supplies | `mmcx.lvl`, `ldob8` admitidos | no aplica | Nuestro árbol no tiene ese driver de reguladores (§1.3) | ver ICC/MMCX |
| 0004 | Diagnóstico DSI | Volcado de estado de error crudo | parcial | S4-DIAG propio | — |
| 0005 | DSC ancho activo | `DIV_ROUND_UP` (427) | **sí** | C2 | — |
| 0006 | DSC RC | flb 13, `range_max_qp[0]` 8 | **sí** | L73 | — |
| 0007 | DSC ICH | `ENC_DF_CTRL` bit12 si bpc>8 | **sí** | C4 (quirk o82) | — |
| 0008 | Secuencia | Host y PHY en pre_enable; vídeo tras prepare (ON+PPS) | **sí** (≈) | C5 | — |
| 0009 | DSC initial lines | Modelo OEM: 3 líneas | **sí** | C4 | — |
| 0010 | PHY timing | 14 celdas OEM (ventana 1,189187-1,189191 GHz) | **sí** | L75 | — |
| 0011 | Lecturas DSI | Contexto DMA por link en lecturas | no | Diagnóstico | — |
| 0012 | Diagnóstico RX | Cabecera RX inválida | no | Diagnóstico | — |
| 0013 | **PHY strength** | `STR_SWI_CAL_SEL=0x01`, `HSTX_STR_CTRL_0=0xff` | **no** | Escribimos **0x00/0x88** (`dsi_phy_7nm.c:1068-1077`, sin override V5_2). V: **0x01/0xff** en ambas PHY | N: **M-A** |
| 0014 | **PHY retime** | Tras los relojes de los dos hosts: toggle `RBUF_CTRL` 0→1 en ambas PHY y `CLK_EN_SEL=0` | **parcial** | `RBUF_CTRL=1` en vco_prepare, pero `CLK_EN_SEL` queda **a 1** (`dsi_pll_enable_global_clk`, :471-476). V: `CLK_CFG1`=**0x20/0x24** | N: M |
| 0015 | Timing master | TE solo en el INTF maestro | **sí** | C7. L77b-a lo revirtió **sin efecto** en el underrun | — |
| 0016 | Host clk pre/post | `CLKOUT_TIMING` del host = 0 | **sí** | C5 | — |
| 0017 | Split-flush | SSPP_SPARE | — | **Excluido por ellos** (native27 negativo) | — |
| 0018 | **PHY FLL** | 7 valores FLL OEM antes de arrancar el PLL maestro | **no** | Mainline nunca escribe FLL. V PLL maestro: `02 11 00 00 80 00 00` = **exactamente** sus 7 valores | N: M |
| 0019 | **DSI broadcast** | Prepara DMA en los dos hosts y dispara slave1→master0; espera ambos | **no** | 2 commits SW (`CMD_DMA_CTRL` sin BROADCAST; REGDIFF #8) | N: B-M |
| 0020 | **CTL único** | Un solo flush del CTL compartido con `split_flush_en` | **no** | Doble submit por frame; DSC reprogramado y con flush en cada kickoff (UNDERRUN §4) | U: B-M |
| 0021 | Diagnóstico MISR | Debugfs MDP MISR | parcial | MISR L74 | — |
| 0022 | **Planificación DSI** | `DMA_SCHEDULE_CTRL` en línea 2285, solo el grupo de 120 Hz | **no** | — | N: B-M |
| 0023 | TP-FPS | 4 HS (`FF10`,`FB01`,`B291`,`B340`) en 1 DMA, tras el primer vblank | **parcial** | Solo B2/B3 dentro del ON (pos. 105/106); no repetimos con vídeo | N: M |
| 0024 | ON en grupos | 108 DCS LP en 8 bloques DMA (884 B) | **no** | Envío individual (L76 C5: long 0x39) | N: B-M |
| 0025 | HS timer | `HS_TX_TO` 0xbb80, resolución 4 | **sí** | 0x4bb80 (L74) | — |
| 0026 | Diagnóstico FIFO/PLL | Traza | no | — | — |
| 0027 / 0030 | Relojes en xfer | No reprogramar los rates en las transferencias (activas y pre-vídeo) | **no** | `msm_dsi_host_xfer_prepare` llama a `link_clk_set_rate` en cada xfer (`dsi_host.c:~2436`) | N: B |
| 0028 | Limpieza overflow | W1C de overflow HS tras los comandos | no | — | N: B |
| 0029 | **BLOCK_DMA** | `TRIG_CTRL` bit12 = 0 (como OEM) | **no** | L76 lo mantiene a 1 (REGDIFF #10) | N: B |
| 0031 | Grupos LP post-start | Normal (`FF10`,`13 00`) + dimming (`FF27`,`D128`,`FF10`,`532C`) en LP tras el primer frame | **no** | — | N: M |
| 0032 | **Bias replay** | Reescribe el bias con cuenta >0 | **sí** (≈) | Nuestra rc2 escribe siempre (§2.7). `SYSTEM_MUXES` del maestro: V 0x00, suyo y nuestro 0xc0 | — |
| 0033 / 0034 | Modos / refresco en vivo | 7 modos OEM, DFPS seamless | no | No hacen falta para la primera luz | — |

### 3.2 Hallazgo: PHY/PLL vendor frente a nuestro código (V: `full-dsi{0,1}-phy-reg.txt`, PLL en +0x500) [MEDIDO + CÓDIGO]
| Registro | V dsi0 | V dsi1 | Nuestro (código) | senemos |
|---|---|---|---|---|
| CMN_CLK_CFG1 (0x014) | 0x20 | 0x24 | `CLK_EN|CLK_EN_SEL` = 0x3x | 0014 → 0x20/0x24 (medido en native20) |
| CMN_RBUF_CTRL (0x01c) | 0x01 | 0x01 | 1 tras vco_prepare | toggle 0→1 |
| GLBL_HSTX_STR_CTRL_0 (0x0ec) | **0xff** | **0xff** | **0x88** | 0013: 0xff |
| GLBL_STR_SWI_CAL_SEL_CTRL (0x10c) | **0x01** | **0x01** | **0x00** | 0013: 0x01 |
| PLL_SYSTEM_MUXES (0x528) | 0x00 | 0xc0 | 0xc0 / 0xc0 | 0xc0 (0032) |
| PLL_FLL_CONFIG…FAST_PWRUP (0x6d4-0x6f0), maestro | `02 11 00 00 80 00 00` | (esclavo: `8b 05 02 14 00 02 4f`) | **no se escribe** (queda lo del ABL o el reset) | 0018: `02 11 00 00 80 00 00` |

Nunca hemos leído la PHY ni el PLL de nuestro lado (REGDIFF solo comparó vendor con vendor en 0x800 frente a 0x000).
Son tres parches pequeños y aislados. En su historia ninguno bastó por sí solo (native18, native20 y native28 siguieron
en negro), pero los tres van en la pila que funciona.

### 3.3 Lo que senemos NO hace (y nosotros sí): no hace falta para que haya imagen
- **INTF_CONFIG bit23 + prog-fetch (`0x0014272d`)**: el catálogo tiene `prog_fetch_lines_worst_case=24`. Con
  vbp+vsw = 148 queda off.
- **`DSC_CLK_CTRL 0xc0000000`**, **split UPPER/LOWER 0/0**: los tres son L77b.
- **LUT QoS vendor** (L77c punto 3): llevan las mismas FIXME que nosotros.
- **Dos SSPP en vez de multirect**: corren 7.2.9 con `dpu_use_virtual_planes` por defecto y la misma lógica de
  `dpu_plane.c`, así que un plano XR24 a pantalla completa sale en DMA0 multirect igual que el nuestro [INFERIDO]. La
  hipótesis L77-SSPP pierde peso.

### 3.4 Candidatos a nuestro bloqueo
**Underrun por frame**: con C4/C7 descartados por #657 y el DPU ya igual al suyo, lo que queda diferente está
**fuera del MMIO del DPU**:
1. **ICC real + QoS de NoC del MDP** (`urg_fwd`), con un voto que llegue de verdad a RPMh (MM0/SH0/MC0/ACV). Si la
   NoC ignora la urgencia o el DDR/LLCC está bajo, el DPU pasa hambre sin dejar error en VBIF (H2). **A.**
2. **ACTLR=1 (CMTLB) en el CB del display** y CB/TLB nuevos tras halt + BCR, frente a nuestro CB 69 heredado sin
   ACTLR. Los fallos de TLB en scanout lineal de 3200×2136 dan latencia, no fault. **M-A.**
3. **MMCX/MXA**: 514 MHz sin voto de tensión. **M.**
4. **Handoff sin halt de VBIF** antes del BCR. **M-B.**
5. **CTL único** frente a doble flush y reflush del DSC por commit. **B-M.**

**Negro sin underrun** (lo que vendrá después aunque quitemos el underrun, como L67 y su native12-49):
1. PHY strength 0xff/0x01, `CLK_EN_SEL`=0 y FLL (§3.2).
2. Protocolo DSI OEM: broadcast escalonado, ON en grupos, TP-FPS HS tras el vblank, grupos LP post-start,
   `BLOCK_DMA`=0, `DMA_SCHEDULE`.
3. Backlight emparejado de los dos KTZ (D-11). Lo hacen en la serie 7.2.9 (0025) y en la transformación del DT.

---

## 4. Recomendación

### 4.1 (A) Portar sus parches y ficheros a nuestro 7.2-rc2
Ficheros que tocan sus parches de display, frente a la densidad de cambios nuestros (marcas `uke|UKE-|Lnn|Knn` en el
fichero) [MEDIDO]:

| Fichero | Parches suyos que lo tocan | Marcas nuestras / líneas | Conflicto esperado |
|---|---|---|---|
| `dsi/dsi_host.c` | 19 | 86 / 3 008 | **muy alto** (L65-L76 en las mismas funciones: xfer, timing, widebus, PPS) |
| `dsi/dsi_manager.c` | 9 | 12 / 629 | alto (C5 reescribió pre_enable y enable igual que 0008) |
| `dsi/phy/dsi_phy_7nm.c` | 7 | 5 / 1 610 | **bajo-medio** (0013/0014/0018 entran casi limpios; 0010 ya está como L75) |
| `dpu1/dpu_encoder_phys_vid.c` | 5 | 23 / 855 | alto (C2/C7, marcas L76-INTF) |
| `dpu1/dpu_encoder.c` | 3 | 6 / 2 956 | medio (0020) |
| `dpu1/dpu_hw_dsc_1_2.c` | 2 | 23 / 458 | alto, pero **ya equivalente** (C4) |
| `msm_mdss.c` | 1 | 6 / 598 | medio (handoff) |
| `clk/qcom/dispcc-sm8550.c` | 1 | 6 / 1 855 | medio. **Bloqueante**: `uke-dispcc-votes.c` necesita el marco vdd-class/clk-regmap de su 0001 (5 754 líneas) y el regulador vendor de su 0002 (6 011). Alternativa mainline: un `rpmhpd` cliffs (`mmcx.lvl`/`mxa.lvl` por cmd-db) + `power-domains`/`required-opps` en s289 |
| `iommu/arm-smmu/arm-smmu-qcom.c`, `arm-smmu.c` | 1 (+ su 0005) | 52 / 1 098 y **581 / 4 330** | **muy alto** (nuestro handoff K-series es otro diseño; su release de SMR depende de su `qcom_uke_smmu_impl`) |
| `interconnect/qcom/palawan.c` (frente a su `qnoc-cliffs-usb.c`) | 1 | 2 / 1 929 | Reimplementar mmss_noc + BCM en palawan.c. Riesgo conocido: el pánico #156 por commit temprano bajo Gunyah. Ellos votan con BCM `keepalive` en el mismo firmware |
| `panel/` | panel nuevo | `panel-xiaomi-o82-dualdsi.c` (1 062) | Sustituir o fusionar (compatibles y bindings distintos) |

Coste [INFERIDO]: 2-4 semanas de port y muchos flashes. Y sobre todo **fidelidad incierta**: lo más sospechoso (ICC,
MMCX, handoff, SMMU) vive en su capa de plataforma, que no tenemos.

### 4.2 (B) Compilar SU kernel y empaquetarlo con NUESTRO boot
Qué hace falta:
1. **Fuente**: 7.2.9 verificado (sha y firma de §1.1), los 44 parches, boot 0001 (con las exclusiones), los 34 de
   display (sin 0017) y `src`, exactamente en el orden de §1.2. Los pasos de preparación son triviales (apply/install,
   `cpp`/`dtc`/`od`), así que **conviene reimplementarlos en un script nuestro** y no ejecutar los suyos. Si se
   ejecutan los suyos, que sea solo tras revisión y con el visto bueno del dueño.
2. **Deltas de config** sobre `native.config` (mínimos, documentados):
   - `CMDLINE_FORCE=n`, o `CONFIG_CMDLINE` con nuestro `rdinit=/ukeinit …`;
   - `selinux=0`;
   - **built-in** de lo que nuestro initramfs busybox no puede cargar:
     - `SCSI_UFS_QCOM`, `PHY_QCOM_QMP_UFS` (raíz);
     - `USB_DWC3`, `USB_DWC3_QCOM`, `USB_PHY_QCOM_UKE`, `USB_REPEATER_QCOM_UKE`, `USB_CONFIGFS` + `F_RNDIS/NCM/ACM`,
       `LIBCOMPOSITE` (SSH y consola ACM);
     - `I2C_QCOM_GENI`, `QCOM_GPI_DMA`, `DRM_MSM`, `DRM_PANEL_XIAOMI_O82`, `BACKLIGHT_KTZ8866` (display sin depender
       del rootfs).

   La alternativa es un initramfs con sus módulos y kmod. **Cambiar `=m`→`=y` altera el orden de probe**: es un riesgo
   bajo, pero es una diferencia con su binario probado.
3. **Cambiar el cuelgue de §2.2 por `panic()`**: una línea en nuestra copia. Con `panic=10`, cada fallo reinicia y gasta
   un retry del slot A; cuando se agoten, el ABL vuelve a B (Android).
4. **Empaquetado**:
   - `repack-senemos.py`, clon de `repack-k52L76r.py`: shell s240, `Image.gz` suyo, initramfs k22 y una cmdline
     **nueva y corta**;
   - no sirven los gates de 622 B (la cadena L57..L74 lleva parámetros `arm_smmu.uke_*`/`msm.uke_*` que su kernel no
     tiene; en el mejor caso se ignoran).
5. **dtbo: STOCK en el slot que se use.** s288 es incompatible: reescribe nodos de display, KTZ, GPI, GPU y ADSP que
   su transformación exige intactos, y crea `/soc/display-subsystem@ae00000`, el mismo nodo que crea su overlay. Hay
   que sacar el dtbo stock (el `dtbo_b` de Android o el del paquete OS3.0.303.0) con sha. El backup `dtbo_a` del 17-oct
   **es s288**.
6. **Rootfs**: el Arch de 8 GiB, más `/usr/lib/modules/7.2.9-senemos.*` (`depmod`), modetest y libdrm.
7. **Carga**: **nuestros `.ko` no valen** (vermagic distinto). Su kernel trae PAS cliffs (`auto_boot=false`) y
   pmic_glink/battmgr parcheados (=m), con los mismos nombres de firmware (`adsp.mdt`/`adsp_dtb.mdt`). Hay que adaptar
   `uke-adsp-load.sh`: `modprobe` de sus módulos y `echo start` al remoteproc. s288 deja de hacer falta, porque
   ICC LPASS (0026) y gpr (0027) ya van en su serie. Red de seguridad: carga off-mode del ABL.

Coste: 1-2 días de PC y 1-2 flashes. No hay que portar código para responder a "¿su pila enciende nuestro panel?".

### 4.3 (C) Híbrido
Hacer **B una vez como oráculo**:
- **Si hay imagen**: capturar su estado que funciona y compararlo con L77b sobre el mismo aparato: `regulator_summary`
  (MMCX/MXA), `interconnect_summary` y la traza `rpmh`, `clk_summary`, el snapshot `dri/*/kms` (DSI, PHY+PLL, INTF,
  DSC, CTL, VBIF), el SMMU (CB/ACTLR, si su debugfs lo da) y dmesg. Con eso hay dos caminos:
  - **adoptar su base** (rebase de lo nuestro no-display: táctil, BT, audio, WiFi RE, sobre 7.2.9-senemos);
  - o **portar a nuestro árbol solo lo que la diferencia señale**.
- **Si no hay imagen**: su solución no se traslada tal cual a nuestra unidad o firmware (OS3 frente a su OS2 global
  [LEÍDO, `UFS-BRINGUP`]). Hay que buscar en el firmware, y nos ahorramos semanas de port.

### 4.4 Decisión argumentada: **C**, empezando ya por B
- La diferencia que importa está en plataforma (§3.4), justo lo más caro de portar (A). B la prueba entera sin portar.
- El riesgo de compatibilidad DT es acotable antes de flashear (§2.6 y paso 1).
- Sus validaciones admiten nuestro DT en todo lo comprobado. Coinciden la variante de panel (42) y la dirección de splash.
- A sigue teniendo sentido para tres parches aislados, en paralelo y sin esperar a B: PHY 0013/0014/0018 y ACTLR para
  `qcom,palawan-mdss`. Entran limpios en `dsi_phy_7nm.c` y `arm-smmu-qcom.c`, y se verifican con readback.

### 4.5 Riesgos
| Riesgo | Detalle | Mitigación |
|---|---|---|
| **Código externo** | 22 k + 5 k + 3 k líneas sin revisar. Todo en `drivers/`, `include/`, `arch/arm64` (setup.c, uke-abl.c), `lib/Makefile` y `Documentation`. Nada en `net/` core, `fs/`, `kernel/` ni `security/`. No hay binarios en el repo | Compilar desde fuente en el commit fijado `43e4036e`. Revisión dirigida de: `set_property` USB de battmgr (0033), lista blanca de reguladores (0002/0003), escrituras SDAM de reboot-mode, UFS (0008-0010), debugfs MISR (root) y `uke-abl.c` |
| **Cuelgue en la transformación del DT** | `while(true)` sin consola ni retry | Paso 1 (checker propio) + `panic()` en nuestra copia |
| **dtbo** | s288 incompatible. Volver a L-series = reflashear s288 | Stock con sha; registrar en el ledger |
| **Firmware** | Suyo: POCO Pad X1 (OS2 global [LEÍDO]). Nuestro: OS3.0.303.0.WOZEUXM. El ABL o el DT pueden diferir | §2.6 + paso 1 sobre el DTB de `vendor_boot` + dtbo stock reales |
| **Initramfs/módulos** | UFS, USB y MSM son `=m` en su config | Deltas `=y` (§4.2.2) o initramfs con módulos |
| **Carga** | Pila distinta, ADSP manual, "battery-only" | Loader adaptado; gate `Charging` con cargador de pared; off-mode del ABL |
| **UFS/datos** | Su UFS ha montado raíz rw en su unidad. Nuestro `userdata` lleva el rootfs | Rootfs regenerable (`mk-rootfs-l76.sh`); sin datos únicos |
| **Slots** | Ellos usan B. B es nuestro Android de vuelta | Usar **A** (dtbo_a stock + boot_a suyo) y dejar B intacto |
| **Cmdline del ABL** | La entrada nativa necesita el selector en `/chosen/bootargs` | Comprobado en V:cmdline.txt. Gate: `grep o82_42 /proc/device-tree/chosen/bootargs` en el primer arranque |
| **Reproducibilidad** | Su `.4054` local no es el binario de COPR. Nuestro build tampoco será su binario | Aceptado: es un oráculo de fuente, no de binario |

### 4.6 Plan por pasos y criterios
| Paso | Qué | PASA si |
|---|---|---|
| 0 (ya, sin flash, L77b en la tablet) | Ampliar Z5/Z8 de `UNDERRUN-ANALISIS-L77`: del snapshot `dri/1/kms` leer PHY/PLL (`0x014`, `0x0ec`, `0x10c`, `0x6d4-0x6f0`, `0x528`) en ambas PHY; `regulator_summary` (MMCX); `interconnect_summary` | Se confirman o descartan, medidas en nuestro lado, las diferencias de §3.2 y D-04 |
| 1 (PC) | Checker **propio**, escrito desde la especificación de `uke-abl.c` y `uke-abl-native.h` sin ejecutar su código, sobre el merge real `vendor_boot` OS3 + dtbo stock. Alternativa con el visto bueno del dueño: compilar su `uke-abl.c` en modo host (tiene rama `#else` libfdt) en un sandbox | Los ~25 grupos y la entrada nativa admiten el DT. dtbo stock identificado con sha |
| 2 (PC) | Árbol 7.2.9 preparado con un script nuestro (§4.2.1), deltas de config (§4.2.2-3), build con clang 23 | Build limpio. `QCOM_UKE_ABL_DT=y`. Cadena `"isolated native display graph prepared"` presente en el Image. Banner `7.2.9-senemos…` |
| 3 (PC) | `repack-senemos.py` + rootfs con sus módulos + loader de carga adaptado. Ledger pre-registrado | shas fijados. Gates de cmdline nuevos |
| 4 (flash, dueño) | `dtbo_a`=stock, `boot_a`=senemos, `set_active a`, lector ACM | (i) SSH; (ii) `Uke ABL DT: … isolated native display graph prepared`; (iii) conector DSI + `msm-kmsdrmfb`; (iv) **imagen en el panel** (dueño); (v) underrun 0 con un plano mantenido; (vi) ADSP running y battmgr `Charging` |
| 5 | Si (iv): capturas de §4.3 y comparación con L77b. Si no: dmesg y snapshot, y comparar con su README | Informe de diferencia con cada cambio clasificado |
| 6 | Decidir: adoptar su base (rebase de lo nuestro) o portar a nuestro árbol (ICC/MMCX/handoff/ACTLR/PHY) guiados por la diferencia | — |
| Rollback | `dtbo_a`=s288 (`02d403c5…`) + `boot_a`=L77b/L74. Slot B Android intacto | — |

En paralelo (opcional, en nuestro árbol): **L78-PHY+ACTLR** = 0013 + 0014 + 0018 adaptados (con readback `UKE-L78-PHY`
de 0x0ec/0x10c/0x014/FLL) + `qcom,palawan-mdss` en `qcom_smmu_actlr_client_of_match` con `PREFETCH_DEFAULT|CMTLB`
(readback del ACTLR del CB). Antes hay que comprobar que nuestro apps-SMMU (`qcom,qsmmu-v500`) pasa por
`qcom_smmu_init_context`. PASA si la PHY y el ACTLR igualan al vendor. Sirve como dato aunque siga negro.

---

## 5. Resumen (≤400 palabras)

**Build.** Linux 7.2.9 de kernel.org (sha `b4c5dfbe…`, firma `647F2865…`). Encima: 44 parches de plataforma
derivada del vendor, el hook ABL (`uke-abl.c` + libfdt), los providers de display y los parches 0002-0034 sin 0017, con
el overlay O82-42 de 7 modos embebido en el Image. `native.config` completa, clang 23.1.2 `LLVM=1`. Sale un Image crudo
y módulos; **ni initramfs ni boot.img en el repo** (su bundle `.4054` es privado).

**Arranque.** ABL de stock, EL1, slot B, DTB de `vendor_boot` + dtbo de stock. El kernel transforma el FDT en
`setup_machine_fdt`: valida unos 25 grupos OEM exactos (si no encajan, cuelgue sin consola) y aplica overlays
UFS/USB/simplefb y el grafo nativo. `CMDLINE_FORCE`, `root=PARTLABEL=linux`, Fedora. **No usan DT propio.** Nuestro DT
vivo pasa lo comprobado (12 de ~25 grupos, panel 42, splash `0xe3940000`).

**Display.** Su DPU ya es el nuestro: mismo catálogo y LUT, y llevan C2/C4/C7/L73/C5. **No usan** prog-fetch, bit23,
`DSC_CLK_CTRL` ni split 0/0 (L77b). Se diferencian en dos frentes:
- plataforma: ICC real (BCM + QoS `urg_fwd`), MMCX/MXA, handoff VBIF→BCR→SMR y CB nuevo con **ACTLR=1** (nosotros no
  escribimos ACTLR);
- PHY y protocolo DSI.

**Nuevo en nuestra cosecha**: el vendor tiene HSTX 0xff, SWI_CAL 0x01, `CLK_CFG1` 0x20/0x24 y FLL
`02 11 00 00 80 00 00`. Nuestro código pone 0x88/0x00, deja `CLK_EN_SEL`=1 y no toca el FLL. Su arreglo final (0032) ya
equivale a nuestro código.

**Candidatos al underrun**: ICC+QoS > ACTLR/CB > MMCX > handoff > CTL único. **Al negro sin underrun**: PHY
0013/14/18, protocolo DSI y los dos KTZ.

**Recomendación: C.**
1. Compilar **su** kernel desde fuente, con deltas mínimos: cmdline nuestra, UFS/USB/MSM built-in y `panic` en vez de
   cuelgue.
2. Empaquetarlo con nuestro boot v4 e initramfs, **dtbo stock** en el slot A (s288 es incompatible) y rootfs de 8 GiB
   con sus módulos. La carga va con sus módulos: nuestros `.ko` no valen por vermagic.
3. Si enciende, comparar su estado con L77b y decidir entre adoptar su base o portar.

Portar todo a nuestra rc2 (A) cuesta 2-4 semanas, con conflictos altos (`dsi_host.c`, SMMU, dispcc/vdd-class) y
fidelidad dudosa. En paralelo, barato: L78 con PHY 0013/0014/0018 + ACTLR, y lecturas sin flash de PHY/PLL, MMCX e ICC
sobre L77b.

**Riesgos**: código externo (revisión dirigida), cuelgue por el DT (checker propio antes de flashear), dtbo, firmware
OS3 frente a OS2, y la carga.
