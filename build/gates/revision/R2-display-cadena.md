# R2 — La cadena display COMPLETA: de «apps-smmu bindeado» a «card0 con modetest»

Fecha: 2026-09-29 (madrugada). Autor: agente revisor R2. **Sin tablet**: cero adb/fastboot/ssh,
cero apertura de `/dev/ttyACM0`. Todo lo de aquí sale de leer código + reproducir el DT en el PC
(`fdtoverlay`) + los logs vivos ya capturados (`~/proyectos/out/k6-migas.log`, `k6b-migas.log`) +
el DT **vivo** del aparato (`build/evidencia/2026-09-28/device-tree.tar.gz`, captura de las 18:32).

Árbol auditado: `/var/tmp/uke-k1` (K6, `arm-smmu.c 0f6f3006…`) con `O=/var/tmp/uke-k1-build`
(`.config` del #82 con parches de la serie). Base DT: `~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img`.
Overlay vigente: `build/bootimg/s258-panel-gpio2.img` (`f4663ff8…`).

---

## 0. Resumen ejecutivo (lo que cambia el plan)

1. **La cadena display está COMPLETA en driver y DT, con UNA excepción: el apps-smmu.** Panel
   (integrado, `=y`), DSI ctrl, DSI PHY, MDSS, DPU (catálogo `palawan`), dispcc, gcc, icc y GPU
   tienen driver y compatible que casa con NUESTRO DT (tabla §1). El único eslabón que hoy no
   existe es `device_iommu_mapped(mdss)` → `-19` en `dpu_kms_mmu_init`.
2. **`msm_drm.dsi_display0=…dualdsi_dsc_vid` de la cmdline es INERTE** en este kernel: 0 lectores
   (`grep -rn dsi_display0 drivers/` → vacío). No hay que tocar la cmdline; el panel se encuentra
   por DT (`xiaomi,uke-o82-4202-0b`). Lo que sí hace el driver con DSC es exactamente lo que el
   panel pide (video mode + DSC 1.1 + dual-DSI bond; §4).
3. **HALLAZGO CRÍTICO (nuevo, cambia el orden de la misión):** el solo hecho de **registrar
   card0** dispara el arranque del **CM3/GPU**. `msm_drm_kms_post_init()` llama
   `drm_client_setup()` (fbdev) → `drm_fbdev_client_setup()` → `drm_client_init()` →
   `drm_client_open()` → `drm_file_alloc()` → `dev->driver->open` = `msm_open()` →
   `load_gpu()` → `adreno_load_gpu()` → `pm_runtime_get_sync` + `msm_gpu_hw_init()` (CM3).
   Evidencia: `msm_kms.c:380-387`, `clients/drm_client_setup.c:45-53`, `clients/drm_fbdev_client.c:162`,
   `drm_client.c:36-41` + `drm_file.c:175-176`, `msm_drv.c:198-207` y `:265-272`,
   `adreno_device.c:69-127`. **No hay «card0 sin CM3»** salvo parche o `separate_gpu_kms=1`.
   El plan «card0 → modetest → foto» es, en la práctica, «card0 → CM3 → foto o cuelgue duro».
4. **Segundo hallazgo (bug latente del árbol):** el camino de error de `dpu_kms_hw_init` hace
   **doble `drm_atomic_private_obj_fini`** → OOPS con `dead000000000108` (medido: `k6-migas.log`
   13.974252). Cualquier fallo nuevo dentro de `dpu_kms_hw_init` (no solo el `-19`) se verá como
   **el mismo OOPS**; la línea `[dpu error]…` que lo precede dice el paso que falló.
5. **Re-disparo de probes diferidos:** el timeout de deferred probe es 10 s
   (`CONFIG_DRIVER_DEFERRED_PROBE_TIMEOUT=10`, `dd.c:273-283`) y a los ~13,8 s el kernel imprime
   `deferred probe timeout, ignoring dependency` (medido: `msm-mdss … 13.926997`). Después de ese
   punto **nada se re-proba solo**: hay que usar `/sys/bus/platform/drivers_probe` (§3.4).
6. **El riesgo «el SMMU mata el disco» ya está mitigado por el fork**: `qcom_smmu_def_domain_type()`
   (`arm-smmu-qcom.c:704-708`) devuelve `IOMMU_DOMAIN_IDENTITY` para **todos** los maestros menos
   el WLAN ⇒ UFS/ADSP quedan en bypass cuando el apps-smmu bindea (parche nacido de una muerte
   medida y bisecada con el s222). El display y la GPU no se ven afectados: piden su dominio
   traducido explícito (`msm_iommu.c:735-756`). Riesgo residual: el SID `0x1c00` del mdss está en
   el `qcom,handoff-smrs` del vendor (traducción **viva** del BL) ⇒ el `attach` del display
   escribe sobre ella (§5.5).
7. **Reguladores del panel: resueltos** (auditoría 27-sep): `vddil8b` = pmxr2230 L8B (rail
   `rpmh-regulator-ldob8`, en la rejilla de 8 mV), `vsp`/`vsn` = reguladores fijos GPIO TLMM 74/75
   (`uke_panel_vsp`/`uke_panel_vsn`, `regulator-boot-on`). El probe del panel ya no depende de
   nada más (§2).
8. **Riesgo nº1 detectado (resumen)**: abrir card0 (o que el kernel lo abra por ti con el cliente
   fbdev) puede colgar la tablet en el CM3 **sin watchdog** ⇒ reset físico. Antes de ese momento:
   escalera CM3 (`build/cm3-ladder/`) y doble captura.

---

## 1. INVENTARIO DRIVER — nodo DT vs driver real (uke-k1)

Método: (a) `fdtoverlay -i base-dtb.img -o merged.dtb s258-payload.dtb` (rc=0) y `dtc -I dtb -O dts`;
(b) contraste con el **DT vivo** (`/proc/device-tree` del aparato, captura 28-sep 18:32);
(c) `grep` de los `of_device_id` en `/var/tmp/uke-k1`. Los paths son los del DT fusionado.

| Nodo (path en el DT) | compatible en NUESTRO DT (primero → fallback) | driver que matchea (file:line) | driver/símbolo | bind esperado |
|---|---|---|---|---|
| `/soc/apps-smmu@15000000` | `qcom,qsmmu-v500` (único) | `arm-smmu.c:2734` `{ "qcom,qsmmu-v500", &arm_mmu500 }` + `arm-smmu-qcom.c:912` impl0 | `arm_smmu` (`CONFIG_ARM_SMMU=y`) | **HOY NO** (probe muere; K1-K7). Es el único eslabón que falta |
| `/soc/display-subsystem@ae00000` (mdss) | `qcom,palawan-mdss` | `msm_mdss.c:534` `data_57k` | `msm-mdss` (`msm_mdss.c:568`) | SÍ (medido 13.9269, tras `deferred probe timeout`) |
| `…/display-controller@ae01000` (DPU) | `qcom,palawan-dpu` | `dpu_kms.c:1514` `dpu_palawan_cfg` | `msm_dpu` (`dpu_kms.c:1527`) | SÍ (probe + `msm_drv_probe` = **master**) |
| `…/dsi@ae94000` (master) | `qcom,palawan-dsi-ctrl`, `qcom,mdss-dsi-ctrl` | `dsi.c:195` `{"qcom,mdss-dsi-ctrl"}` (fallback) | `msm_dsi` (`dsi.c:213`) | SÍ (bindea al master, 13.9521) |
| `…/dsi@ae96000` (slave) | ídem | ídem | ídem | SÍ |
| `…/phy@ae95000`, `…/phy@ae97000` | `qcom,palawan-dsi-phy-4nm`, `qcom,sm8650-dsi-phy-4nm` | `dsi_phy.c:578` `{"qcom,sm8650-dsi-phy-4nm", &dsi_phy_4nm_8650_cfgs}` (fallback) | `msm_dsi_phy` (`dsi_phy.c:721`) | SÍ (el 1º difirió una vez: `dsi_get_phy: phy driver is not ready` 13.9500) |
| `…/dsi@ae94000/panel@0` | `xiaomi,uke-o82-4202-0b` | `panel-xiaomi-o82-dualdsi.c:664` | `panel-xiaomi-o82-dualdsi` (**=y**, integrado) | SÍ (s258; ESTADO-VIVO) |
| `/soc/clock-controller@af00000` (dispcc) | `qcom,palawan-dispcc` | `dispcc-sm8550.c:1772` (+ rama palawan `:1799`: `ftbl_disp_cc_mdss_mdp_clk_src_palawan`) | `disp_cc-sm8550` | SÍ (vivo ya a 0.31 s: WARN de su RCG) |
| `/soc/clock-controller@100000` (gcc) | `qcom,cliffs-gcc`, `syscon` | `gcc-palawan.c:2855` | `gcc-palawan` | SÍ (relojes `bus`/`nrt_bus` del DSI/DPU resuelven) |
| `/soc/clock-controller@3d90000` (gpucc) | `qcom,palawan-gpucc` | `gpucc-palawan.c:607` | `palawan-gpucc` | SÍ |
| `/soc/interconnect@1` (mc_virt) | `qcom,cliffs-mc_virt` | `palawan.c:1900` (`cliffs_mc_virt`: nodos 3 y 512) | `qnoc-palawan` | SÍ — es el proveedor del `interconnects = <&mc_virt 3 &mc_virt 512>` del mdss (`mdp0-mem`) |
| `/soc/qcom,gdsc@af09000` | `qcom,gdsc` | **no es un driver aparte**: lo registra el CC de dispcc (`common.c:384` → `gdsc_register`; `[MDSS_GDSC] = mdss_gdsc`, `dispcc-sm8550.c:1748-1751`) | genpd `disp_cc_mdss_core_gdsc` | SÍ (proveedor = nodo dispcc, `#power-domain-cells=1`; el mdss usa `<&dispcc 0>`) |
| `/soc/kgsl-3d0@3d00000` (GPU) | `qcom,adreno-43030b00`, `qcom,adreno` | `a6xx_catalog.c:1618` chipid `0x43030b00`, familia `ADRENO_7XX_GEN2`, fw `gen71100_*` | `adreno` | SÍ, **como componente de card0** (`bound 3d00000.qcom,kgsl-3d0 (ops a3xx_ops)`) |
| `/soc/qcom,kgsl-3d0@3da0000`… (kgsl-smmu) | `…,qcom,smmu-500`,`arm,mmu-500` | `arm-smmu.c:2721` | `arm_smmu` | SÍ (referencia sana del mismo kernel, 0.321 s) |
| Subárbol VENDOR `qcom,mdss_mdp@ae00000` | `qcom,sde-kms` | **sin driver** | — | NO (inerto) |
| `…/qcom,mdss_dsi_ctrl0@ae94000` | `qcom,dsi-ctrl-hw-v2.8` | sin driver | — | NO (inerto; **no colisiona** con nuestro `msm_dsi`) |
| `…/qcom,mdss_dsi_phy0@ae95500` | `qcom,dsi-phy-v5.2` | sin driver | — | NO (inerto) |
| `…/qcom,dsi-display-primary` | `qcom,dsi-display` | sin driver | — | NO (inerto) |

Notas de la tabla:

* El **compatible de primer lugar** `qcom,palawan-*` es del fork y **sí existe** en todos los
  drivers del display (palawan-dpu/mdss/dispcc/gpucc); el DSI ctrl y el PHY casan por el
  **segundo** compatible (mainline genérico). Es decir: el DT del aparato ya está alineado con el
  fork; no hay que renombrar nada.
* **58 nodos** del DT llevan `iommus = <&apps_smmu …>` (`grep -c` sobre el DT fusionado). Cuando el
  apps-smmu bindee, el `bus_iommu_probe()` del core (`iommu.c:306-307`, llamado al final del probe
  de cada IOMMU) barrerá el bus de plataforma y añadirá **todos** esos dispositivos a grupos —
  incluido `1d84000.ufshc` (sid 0x60) y `ae00000.display-subsystem` (sid 0x1c00). Eso es lo que
  hace verdadero `device_iommu_mapped(mdss)`.
* El subárbol vendor (`qcom,sde-kms`, `qcom,dsi-display`, `qcom,mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid`)
  sigue **presente** en el DT pero sin driver ⇒ inerto. No hay que borrarlo (y el ABL no lo borra).

### 1.1 Mapa de relojes del display (para leer el dmesg)

DT fusionado, nodo → clocks (índices del header `include/dt-bindings/clock/qcom,palawan-dispcc.h`):

| Nodo | clocks (idx) | nombres |
|---|---|---|
| mdss | `<&dispcc 2>`, `<&gcc 0x15>`, `<&dispcc 0x3d>` | `disp_cc_mdss_ahb_clk`(iface), gcc bus, `disp_cc_mdss_mdp_clk` |
| DPU | `<&gcc 0x15> <&dispcc 2> <&dispcc 0x40> <&dispcc 0x3d> <&dispcc 0x49>` | `nrt_bus`, `iface`, `lut`(mdp_lut), `core`(mdp), `vsync` |
| DSI0 | `<&dispcc 4> <&dispcc 7> <&dispcc 0x42> <&dispcc 0x38> <&dispcc 2> <&gcc 0x15>` | byte0, byte0_intf, pclk0, esc0, ahb, bus |
| DSI1 | `<&dispcc 8> <&dispcc 0xb> <&dispcc 0x44> <&dispcc 0x3a> <&dispcc 2> <&gcc 0x15>` | byte1, byte1_intf, pclk1, esc1, ahb, bus |
| PHY0/1 | `<&dispcc 2> <&dispcc 0x16c 0>` | iface, ref (XO) |
| DPU assigned | `<&dispcc 0x49>` rate `0x124f800` = 19 200 000 | **falla hoy** (ver §5.2) |
| DSI0/1 assigned | `<&dispcc 5> <&dispcc 0x43>` / `<&dispcc 9> <&dispcc 0x45>` con `assigned-clock-parents = <&phy0 0> <&phy0 1>` | byte_clk_src/pclk_clk_src ← PLL del PHY |

El proveedor `bi_tcxo`/`sleep_clk` del dispcc y los 4 pares «basura» (`0x00 0x00`) al final de su
`clocks` son **inertes**: `qcom_cc_really_probe()` no lee la propiedad `clocks`
(`drivers/clk/qcom/common.c:324-430`); los padres se resuelven por **nombre** dentro del clk core.

---

## 2. EL PANEL o82: quién es y qué le falta

* **Driver: INTEGRADO en el árbol** — `/var/tmp/uke-k1/drivers/gpu/drm/panel/panel-xiaomi-o82-dualdsi.c`
  (681 líneas, sha `848f8ef78598474eb33fb45f324a8d03307ed89bd4033503427c140c186414f5`, idéntico al de
  `~/gpu-work/palawan-linux`), `CONFIG_DRM_PANEL_XIAOMI_O82_DUALDSI=y`
  (`/var/tmp/uke-k1-build/.config:5120`) ⇒ **dentro del `Image` de K6**: `strings` de
  `/var/tmp/uke-k6/k6-Image` encuentra `xiaomi,uke-o82-4202-0b` ×1. **No hace falta ningún módulo.**
* `build/pkg/panel-o82/panel_xiaomi_o82_dualdsi.ko` es un artefacto **paralelo** (compilado como
  `=m` con `build/gates/compilar-panel-o82.sh` sobre la copia del árbol compartido). Es para los
  kernels-pokes con el panel apagado; **no está en la imagen K6 ni hace falta cargarlo** (no hay
  ningún `insmod` en la ruta de arranque: `build/bootimg/mkarch-boot.sh` empaqueta Image+initramfs,
  y el rootfs no lleva el `.ko`).
* **compatible exacto que matchea**: `xiaomi,uke-o82-4202-0b` (`panel-xiaomi-o82-dualdsi.c:664`),
  que es el compatible del nodo del DT **vivo** (`…/dsi@ae94000/panel@0`, verificado en la captura
  de `/proc/device-tree`). La cmdline sigue nombrando el nodo vendor
  `qcom,mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid` — **irrelevante**: ese compatible no tiene driver y
  `dsi_display0` no se lee.
* **Qué le falta hoy al panel: NADA más que el SMMU.** El probe completo (s258) ya hace: 3
  reguladores (`vddil8b`, `vsp`, `vsn`; `o82_supplies`, con `regulator_set_load` 300 mA), GPIO de
  reset (`reset-gpios = <&tlmm 2 GPIO_ACTIVE_LOW>`, `GPIOD_OUT_HIGH`), DSI secundario
  (`of_graph_get_remote_node(node,1,-1)` → `dsi@ae96000`), backlight
  (`/sys/class/backlight/ae94000.dsi.0`, `bl_max 0xfff`, init `0x133` = 307 — el brillo medido),
  `drm_panel_add` y **attach de los dos DSI** (`devm_mipi_dsi_attach` ×2).
* La secuencia de encendido real (la que hace la PRIMERA LUZ) vive en `o82_prepare()`
  (`:296-353`): power-on de los 3 rails → reset (10 ms/3/3/15 ms) → **964 B de comandos DCS**
  (`o82_init_cmds`, comandos 1..104 del vendor) → `0xb3/0xb2` de timing (120 Hz: 0x40/0x91) →
  `0x11` sleep-out + 120 ms → `0x29` display-on → `backlight_enable`. Los comandos se envían a
  **los dos** DSI (`mipi_dsi_dual_dcs_write_buffer_multi`).
* Resumen de la auditoría de reguladores (27-sep, `AUDITORIA-REGULADORES-Y-GPIO.md` + `DT-RAILS-L.md`):
  la regla de la rejilla de 8 mV predice los `-131` de RPMh; L8B quedó en `min=max=1900000`
  (49,5 pasos ⇒ falla el `-131` de `apply_uV` y el core reintenta con un selector válido: **el
  rail se registra**); `vsp/vsn` no son RPMh (son fijos por GPIO) y `l22` no toca al panel.

---

## 3. CHECKLIST `card0` ORDENADA

### 3.1 Estado de partida (medido en K6 + s258; `k6-migas.log` / `k6b-migas.log`)

| t | línea (literal, medida) | significado |
|---|---|---|
| 13.9269 | `msm-mdss ae00000.display-subsystem: deferred probe timeout, ignoring dependency` | mdss difirió (cadena dispcc→GDSC→mdss) y solo probó al expirar el timeout de 10 s |
| 13.9477 | `clk: couldn't set disp_cc_mdss_vsync_clk clk rate to 19200000 (-22), current rate: 38400000` | `assigned-clock-rates` del DPU; **no es fatal** (`clk-conf.c:147-152` solo imprime) |
| 13.9500 | `msm_dsi ae96000.dsi: [drm:dsi_dev_probe] *ERROR* dsi_get_phy: phy driver is not ready` | defer del PHY del slave; reintenta y liga |
| 13.9521 | `msm_dpu ae01000.display-controller: bound ae94000.dsi (ops dsi_ops)` / `bound ae96000.dsi` | `component_bind_all` (el panel ya adjuntó los 2 DSI) |
| 13.9696 | `msm_dpu … bound 3d00000.qcom,kgsl-3d0 (ops a3xx_ops)` | la GPU es componente de card0 |
| 13.9738 | `[drm:dpu_kms_hw_init:1168] dpu hardware revision:0xa0010000` | el bloque MDP lee OK (GDSC lo dejó el ABL) |
| 13.9738 | `msm_dpu …: [drm] no IOMMU, bailing out` + `[dpu error]dpu_kms_mmu_init failed: -19` + `*ERROR* kms hw init failed: -19` | **EL MURO** (`msm_kms.c:189-200`; el iommu-dev puede ser el DPU **o el mdss**) |
| 13.9742 | OOPS `dead000000000108` en `drm_atomic_private_obj_fini+0x2c/0x78` ← `dpu_kms_destroy+0x58` | bug de doble `fini` (§5.4) |

### 3.2 Qué pasa SOLO cuando el apps-smmu bindee (esperado, literal)

Referencia del mismo kernel para un SMMU-500 qcom **sano** (kgsl-smmu, `k6-migas.log:1055-1077`):

```
arm-smmu 3da0000.kgsl-smmu: probing hardware configuration...
arm-smmu 3da0000.kgsl-smmu: SMMUv2 with:
arm-smmu 3da0000.kgsl-smmu: 	stream matching with 24 register groups
arm-smmu 3da0000.kgsl-smmu: 	22 context banks (0 stage-2 only)
arm-smmu 3da0000.kgsl-smmu: 	preserved 0 boot mappings
platform 3d00000.qcom,kgsl-3d0: Adding to iommu group 0
```

Para **apps-smmu** (ya medido con el probe armado en K6b, `k6b-migas.log:2266-2298`), lo que
aparecerá es:

```
arm-smmu 15000000.apps-smmu: probing hardware configuration...
arm-smmu 15000000.apps-smmu: SMMUv2 with:
arm-smmu 15000000.apps-smmu: 	stream matching with 110 register groups
arm-smmu 15000000.apps-smmu: SMMU address space size (0x100000) differs from mapped region size (0x200000)!
arm-smmu 15000000.apps-smmu: 	71 context banks (0 stage-2 only)
arm-smmu 15000000.apps-smmu: 	preserved 0 boot mappings
platform ae00000.display-subsystem: Adding to iommu group <N>
platform 1d84000.ufshc: Adding to iommu group <M>          <-- el UFS entra en un grupo (bypass IDENTITY: §5.5)
```

La línea `Adding to iommu group` **del mdss** es la que convierte `device_iommu_mapped(mdss)` en
verdadero. Sin ella, el DPU seguirá dando `-19` aunque el SMMU haya bindeado.

Después del bind, la cadena de card0 (si el master bind se re-dispara o nunca falló) es:

```
[drm:dpu_kms_hw_init:1168] dpu hardware revision:0xa0010000          <-- ya medido
(desaparece "no IOMMU, bailing out")
msm_dpu ae01000.display-controller: [drm] Initialized msm 1.13.0 for ae01000.display-controller on minor 0
msm_dpu ae01000.display-controller: [drm] fb0: msmdrmfb frame buffer device
```
(`MSM_VERSION_MAJOR/MINOR/PATCHLEVEL = 1/13/0`, `msm_drv.c:45-47`; formato del mensaje en
`drm_drv.c:1109-1113` y `drm_fb_helper.c:1660`.)

### 3.3 Escenario A — SMMU bindea TEMPRANO (K7, ventana Android ~1 s)

Es el escenario bueno: el display se probea **después** del SMMU ⇒ no hay nada que re-disparar.

| # | paso | comando (literal) | dmesg esperado | fallo típico |
|---|---|---|---|---|
| A1 | SMMU bindea | (automático, cmdline `arm_smmu.uke_*=…`) | bloque de §3.2 + `Adding to iommu group` del mdss | muerte muda ⇒ mirar la última miga UKE-POKE |
| A2 | mdss/dpu/dsi/phy/panel se probean | (automático) | `dpu hardware revision:0xa0010000` sin `-19` | si algo más falla en `dpu_kms_hw_init` ⇒ OOPS `dead000000000108` (§5.4) |
| A3 | card0 | `ls -l /dev/dri/` → `card0`, `renderD128` | `[drm] Initialized msm 1.13.0 … on minor 0` | si no aparece: `kms hw init failed: -N` |
| A4 | **CM3 arranca solo** | (automático, cliente fbdev) | — | **cuelgue duro sin watchdog** (§4.4) |
| A5 | fbcon hace el 1er modeset | (automático, `console=tty0`) | `fb0: msmdrmfb frame buffer device` | si fbcon no engancha: usar modetest (A6) |
| A6 | primer modeset explícito | `modetest -M msm -c` / `-s …` (§4.1) | (silencioso) | `cmd dma tx failed`, `PLL lock failed`, `wait for video done timed out` |

### 3.4 Escenario B — SMMU bindea TARDE (sysfs, después del timeout)

Entonces el mdss/dpu/dsi/panel ya probaron (13,9 s) y **el master bind ya falló con OOPS**
(13,97 s). El timeout de deferred ya pasó ⇒ **nada se reintenta solo**. Orden correcto (no
invertirlo; el `bind` del SMMU siempre desprendido, regla #P12):

```sh
# B1) bind del SMMU (desprendido EN LA TABLET)
nohup sh -c 'echo -n 15000000.apps-smmu > /sys/bus/platform/drivers_probe' >/tmp/b1.log 2>&1 &

# B2) comprobar que el mdss entró en grupo (si no, forzar el probe del mdss)
ls /sys/kernel/iommu_groups/*/devices/ 2>/dev/null | grep -E "ae00000|ufshc"
echo -n ae00000.display-subsystem > /sys/bus/platform/drivers_probe    # idempotente

# B3) re-disparar el MASTER bind. PRIMERA opción (martillo pequeño y seguro):
#     rebind del PANEL -> dsi_host_detach/attach -> component_del/add(dsi_ops) -> bring-up
echo -n ae94000.dsi.0 > /sys/bus/mipi-dsi/drivers/panel-xiaomi-o82-dualdsi/unbind
sleep 1
echo -n ae94000.dsi.0 > /sys/bus/mipi-dsi/drivers/panel-xiaomi-o82-dualdsi/bind
#     (B3-alt, si el panel no reengancha: rebind del DPU = el master.
#      OJO: el unbind del DPU pasa por dpu_kms_destroy -> dpu_kms_global_obj_fini y
#      dispara OTRA VEZ el OOPS del bug §5.4 (medido: sobrevivible, pero ensucia):
#        echo -n ae01000.display-controller > /sys/bus/platform/drivers/msm_dpu/unbind
#        sleep 1
#        echo -n ae01000.display-controller > /sys/bus/platform/drivers/msm_dpu/bind )

# B4) vigilar
dmesg -n 7; dmesg -w | grep -Ei "drm|msm_dpu|msm_dsi|msm-mdss|iommu|panel|o82|fb0|adreno|gmu"
ls -l /sys/class/drm/ /dev/dri/
```

Por qué funciona B3: el master (`msm_drm_bind`) está registrado con `master_dev` = **el device del
DPU** (`dpu_kms.c:1426` → `msm_drv_probe(&pdev->dev, …)`), y sus componentes son los 2 DSI + la
GPU (`add_mdp_components` recorre los `ports` del DPU → `dsi@ae94000/ae96000`; `add_gpu_components`
→ `kgsl-3d0`). El fallo anterior dejó los componentes «añadidos pero no bindeados»
(`msm_drm_uninit` → `component_unbind_all`, `msm_drv.c:99-102`), que es exactamente el estado que
permite el reintento: **cualquier `component_add` nuevo vuelve a llamar
`try_to_bring_up_aggregate_device()`** (y el rebind del panel es el más barato porque su
`unbind`/`bind` es un leaf: `devm_mipi_dsi_attach` → `dsi_host_detach` → `dsi_dev_detach` →
`component_del`).

**Re-disparadores disponibles (los tres):**

| herramienta | path | uso |
|---|---|---|
| bus probe | `/sys/bus/platform/drivers_probe` (`bus.c:309,694`) | `echo -n <device> > …` (re-proba un device por nombre) |
| bind explícito | `/sys/bus/platform/drivers/<drv>/bind` | `msm_dpu`, `msm_dsi`, `msm_dsi_phy`, `msm-mdss`, `arm-smmu`, `adreno` |
| lista de diferidos | `/sys/kernel/debug/devices_deferred` (`dd.c:355`) | `cat` antes/después; los que salen de la lista bindearon |
| ampliar ventana | cmdline `deferred_probe_timeout=30` | solo en el **próximo** arranque (`dd.c:283`); no hay knob runtime |

---

## 4. PRIMERA LUZ SIN FOTO (el dueño duerme)

### 4.1 `modetest`: nomenclatura y comando

`modetest` viene de `libdrm` y **no está en la imagen del rootfs** (`grep -c modetest
build/rootfs/arch-rootfs.img` → 0; `libdrm` tampoco). Antes de nada:

```sh
command -v modetest || echo "FALTA: pacman -S libdrm   (o usar la vía fbcon de §4.3)"
```

Con `modetest` presente, los IDs se calculan (no se inventan):

```sh
modetest -M msm -c                     # tabla de conectores: id, encoder, status, name, size, modes
CONN=$(modetest -M msm -c | awk '$4=="connected" && $5 ~ /^DSI/ {print $1}')
MODE=$(modetest -M msm -c | awk -v c="$CONN" '$1==c {for(i=7;i<=NF;i++) if ($i ~ /^[0-9]+x[0-9]+$/) {print $i; exit}}')
CRTC=$(modetest -M msm -p | awk '/^CRTCs:/{f=1;next} f && /^[0-9]+/ {print $1; exit}')
echo "CONN=$CONN MODE=$MODE CRTC=$CRTC"
# el conector del panel es "DSI-1" (drm_bridge_connector + panel bridge) y el modo se llama "3200x2136"

modetest -M msm -s "$CONN"@"$CRTC":3200x2136@XR24        # forma completa
modetest -M msm -s "$CONN":3200x2136@XR24                # el @crtc es opcional: modetest elige
```

Notas de nomenclatura:
* `<conn>@<crtc>` = id de conector `@` id de CRTC; `:` y luego `<modo>[-<vrefresh>][@<fourcc>]`.
* El **modo correcto es 3200×2136** (el panel es 1600×2136 por enlace, dual-DSI = 3200). El
  «1920x1200» del encargo **no existe** en el panel: úsalo solo como prueba de humo si el modo
  nativo fallara (`-s "$CONN":1920x1200@XR24` no está en la lista del conector ⇒ modetest lo
  añadiría como modo nuevo, y el panel no lo soporta sin cambiar timing; **no recomendado**).
* Formatos: `XR24` (24bpp) es el que usa el fbdev; `AR24`/`RG24` también valen.

### 4.2 ¿Soporta el msm DSC video-mode dual-DSI para este panel? — SÍ

* **DSI**: `dsi_adjust_pclk_for_compression()` (`dsi_host.c:588-612`) divide `hdisplay` **por 2**
  cuando `is_bonded_dsi` y aplica el ratio `bpp/(bpc*3)`; `dsi_get_pclk_rate()` (`:614-634`) divide
  el pclk entre 2 para bonded. `dsi_update_dsc_timing(host,false)` = rama **video mode**
  (`dsi_host.c:1077-1078`). El `dsc` llega al host por `dsi->dsc = &ctx->dsc` en `o82_probe`
  (`panel:643`) → `dsi_host_attach` (`dsi_host.c:1721-1722`).
* **DPU**: `dpu_encoder` tiene DSC completo (`dpu_encoder.c:29,187,299,644-692`), con
  `topology->num_dsc = 2` cuando hay ≥2 INTF (`:689-692`), y `dpu_encoder_phys_vid.c:98-140`
  aplica `compression_en` + `dce_bytes_per_line`. El catálogo palawan tiene 3 bloques DSC
  (`dpu_10_1_palawan.h:222-240`, `DSC_0/1/2`).
* **Comprobaciones del host** (`dsi_host.c:2595-2619`): `pic_width % slice_width == 0`
  (3200 % 800 = 0 ✔) y `pic_height % slice_height == 0` (2136 % 24 = 0 ✔).
* **Números que debe producir el driver** para el modo 3200×2136@120 (calculados con las mismas
  fórmulas del código; `pclk_total=317 116 800 Hz`, `new_htotal=1144`, `new_hdisplay/enlace=427`):

| magnitud | valor | dónde mirarlo |
|---|---|---|
| pclk por enlace | **158 558 400 Hz** | `dsi_calc_pclk` (`dsi_host.c:660`) |
| byte clk por enlace (bpp 24, 4 lanes) | **118 918 800 Hz** | ídem |
| bit rate por lane | **≈951 Mbps** (VCO ≈ 951 MHz, rango cfg 600 M–5 G) | `dsi_phy_7nm.c:614` clamp |
| BLLP máximo por comando | 9600 B (`hdisplay*bpp/8`) | `dsi_host.c:1525` |

* **`msm_drm.dsi_display0=…dualdsi_dsc_vid` no hace NADA** (0 lectores en el árbol). **No hay que
  quitarlo** para que el panel funcione; y **no se puede «deshabilitar DSC»** desde ahí: el DSC lo
  impone el driver del panel (`o82_dsc_config`, `bits_per_pixel = 8<<4`, `slice_count=2`), porque
  el IC del panel está preconfigurado para recibir DSC (el vendor no envía PPS). Quitar DSC sería
  inventar otro modo (y el enlace iría a 2,66 Gbps/lane sin comprimir, fuera de lo que el panel
  espera). **Mantener DSC.**

### 4.3 Vía fbcon (sin modetest, sin abrir la card con una herramienta de usuario)

`console=tty0` está en la cmdline (bootconfig) + `CONFIG_FRAMEBUFFER_CONSOLE=y` +
`CONFIG_DRM_CLIENT_DEFAULT_FBDEV=y` ⇒ al registrarse `fb0` (cliente fbdev) **fbcon engancha y
hace `set_par`**, que programa el modo preferido del panel (3200×2136) — es decir, **la primera luz
puede ocurrir sola**, sin escribir un comando. Señales:

```sh
cat /sys/class/graphics/fb0/name          # "msmdrmfb"
cat /sys/class/graphics/fb0/virtual_size  # 3200,2136
cat /sys/class/vtconsole/vtcon*/name      # "frame buffer device" activo?
# si fbcon no enganchó, forzarlo (re-bind del vtconsole dispara set_par → modeset):
echo 0 > /sys/class/vtconsole/vtcon1/bind ; echo 1 > /sys/class/vtconsole/vtcon1/bind
dd if=/dev/urandom of=/dev/fb0 bs=1M count=4   # si el CRTC está activo, se ve ruido
```

Cuidado: **escribir en `/dev/fb0` no es «abrir card0»** (no llama a `msm_open`), pero **el simple
registro de card0 ya dispara el CM3** (§4.4).

### 4.4 EL RIESGO QUE CAMBIA EL ORDEN: card0 ⇒ CM3

Cadena literal (todo en el árbol):

```
msm_drm_kms_post_init()            msm_kms.c:380-387  drm_client_setup(ddev, NULL)
 └ drm_client_setup()              clients/drm_client_setup.c:45-53  (CONFIG_DRM_CLIENT_DEFAULT="fbdev")
   └ drm_fbdev_client_setup()      clients/drm_fbdev_client.c:162   drm_client_init(…)
     └ drm_client_init()           drm_client.c:96                  drm_client_open(client)
       └ drm_client_open()         drm_client.c:36-41              drm_file_alloc(dev->primary)
         └ drm_file_alloc()        drm_file.c:175-176              dev->driver->open(dev, file)
           └ msm_open()            msm_drv.c:265-272               load_gpu(dev)
             └ load_gpu()          msm_drv.c:198-207               adreno_load_gpu(dev)
               └ adreno_load_gpu() adreno_device.c:69-127          pm_runtime_get_sync + msm_gpu_hw_init
                                                                   (a6xx → a6xx_gmu_resume → CM3)
```

Consecuencias operativas:

1. **No hay que ejecutar modetest para que el CM3 arranque**: basta con que el master bind
   termine bien (card0 se registra y el cliente fbdev abre la card en el mismo initcall).
2. Si el CM3 se cuelga (cuelgue duro ya medido por el hermano; watchdog muerto,
   `docs/historia/PLAN-PANTALLA.md:47`, `REVISTA-ARCH-AARCH64.md:258-262`), la consola serie y el ssh mueren con
   él ⇒ **reset físico**. `uke-panic-fb` **no** pinta nada en un cuelgue (solo en pánico/oops).
3. Antes de provocarlo: doble captura viva (ACM + `dmesg -w`) y, si se quiere diagnóstico, el
   kernel con la escalera CM3 (`build/cm3-ladder/uke-cm3-ladder.diff` + `measure-cm3.sh`) para que
   la última línea pintada diga el acceso exacto.
4. Palancas de desacople (todas con coste):
   * `drm.active=` (vacío) por cmdline (`module_param_string(active, …, 0444)`,
     `drm_client_setup.c:14`) ⇒ **ningún cliente interno** ⇒ sin fb0/fbcon **y** sin `msm_open`
     automático. La luz habría que provocarla con modetest ⇒ que sí abre ⇒ CM3. Sirve para
     *separar* el momento del modeset del momento del CM3, no para evitarlo.
   * `separate_gpu_kms=1` ⇒ el master del display no incluye la GPU
     (`msm_gpu_no_components()`, `msm_drv.c:64-67`), `priv->gpu_pdev` queda NULL
     (`adreno_device.c:226` solo se ejecuta en `adreno_bind` del master del display) y
     `adreno_load_gpu()` sale con `no GPU device was found` ⇒ **sin CM3 en card0**. Pero
     (a) el F5/B1 tiene anotado que `separate_gpu_kms=1` **por cmdline no arrancaba** en este
     kernel (`PRE-REGISTRO-F5-B1.md:210`, ledger #409, causa desconocida) y (b) la GPU crearía su
     propio card en el probe. **No es la vía para esta noche**; sí es la hipótesis F5/B1 a
     reabrir con calma.
   * Parche de 3 líneas: saltar `load_gpu()` si el DT/param lo pide. No existe hoy.

### 4.5 Verificación «sin foto» (lo que SÍ se puede afirmar sin ojos)

```sh
# 1) card0 y conector
ls -l /dev/dri/ ; ls /sys/class/drm/
cat /sys/class/drm/card0-DSI-1/status        # esperado: connected
cat /sys/class/drm/card0-DSI-1/modes         # esperado: 3200x2136
cat /sys/class/drm/card0-DSI-1/enabled       # enabled tras el modeset

# 2) estado real del CRTC/planes (debugfs DRM; CONFIG_DEBUG_FS=y)
cat /sys/kernel/debug/dri/0/state | sed -n '1,40p'    # crtc[…] enable=1, mode=3200x2136
cat /sys/kernel/debug/dri/0/kms                        # snapshot del estado DPU/DSI
cat /sys/kernel/debug/dri/0/fb
cat /sys/kernel/debug/dri/0/summary 2>/dev/null        # si existe: "crtc: enable=1"

# 3) backlight y reguladores del panel (¡prueba de que prepare() corrió!)
cat /sys/class/backlight/ae94000.dsi.0/brightness      # 307 (0x133) tras el primer modeset
cat /sys/class/backlight/ae94000.dsi.0/bl_power        # 0
cat /sys/kernel/debug/regulator/uke_panel_vsp/state    # enabled
cat /sys/kernel/debug/regulator/uke_panel_vsn/state    # enabled
cat /sys/kernel/debug/regulator/regulator_summary | grep -E "vsp|vsn|L8B"

# 4) dmesg del panel-on (debe estar AUSENTE todo esto)
dmesg | grep -Ei "cmd dma tx failed|PLL\([01]\) lock failed|wait for video done timed out|DSI: pic_|underrun|timeout pending|no IOMMU"

# 5) relojes efectivos (los números de §4.2)
grep -E "byte|pixel|mdp" /sys/kernel/debug/clk/clk_summary | head -20
```

Si `state` muestra el CRTC `enable=1` con `mode=3200x2136`, el backlight en 307 y **cero** líneas
de error DSI, entonces **el panel está encendido** aunque nadie lo haya visto: el driver solo
enciende el backlight al final de `o82_prepare()`, y `prepare()` solo corre en un modeset real.

---

## 5. RIESGOS Y GAPS

### 5.1 Nodos/props del vendor que NO ponemos (y que NO hacen falta)

De `mkdtbo-s253.py` (cabecera, gates G1/G3/G4) + `INFORME-A-PRIMA.md`, esto es lo que el vendor
tiene y nosotros dejamos como está o no leemos:

| del vendor | ¿lo usamos? | veredicto |
|---|---|---|
| `reg = <0x15000000 0x100000 0x151fe000 0x40>`, `reg-names="base","tcu-base"` | sustituido por 1 región de 2 MiB (s256/s258) | el driver mapea **solo** `resource 0` (`arm-smmu.c:2192`) |
| 8 hijos `qcom,qsmmuv500-tbu` / `qcom,qtb500` | intactos | **sin driver** (`qcom_smmu_tbu_of_match` solo tiene `sc7280-tbu`/`sdm845-tbu`, `arm-smmu-qcom.c:943-947`) ⇒ inertes |
| `qcom,actlr`, `qcom,handoff-smrs`, `qcom,use-3-lvl-tables` | intactos | **0 lectores** directos en este árbol. El ACTLR por cliente lo decide `qcom_smmu_actlr_client_of_match` (`arm-smmu-qcom.c:36-64`) y **no tiene `qcom,palawan-mdss`** (sí `sm8550-mdss`/`sm8650-mdss` con `PREFETCH_DEFAULT\|CMTLB`) ⇒ **gap real pero inocuo hoy**: el CB del display no recibe prefetch/CPRE (posible coste de rendimiento/estabilidad en cargas altas, no la primera luz). Parche de 2 líneas: añadir `{ "qcom,palawan-mdss", PREFETCH_DEFAULT\|CMTLB }` |
| `interrupts` (97 = 1 global + 96), `#global-interrupts=1` | intactos | el contrato coincide con mainline; el driver pide 1 IRQ global + las de contexto al hacer attach |
| `phandle` del apps-smmu | intacto | el `iommus` del mdss apunta a él |
| subárbol `qcom,mdss_mdp@ae00000` (sde-kms) y sus `qcom,mdss_dsi_*` | intacto | inertes (§1) |
| panel vendor `qcom,mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid` (props `qcom,mdss-dsi-on-command`, timings, DSC) | **replicado a mano** en el driver integrado (`o82_init_cmds`, `o82_modes`, `o82_dsc_config`) | es la fuente de la que se portó; no hace falta el nodo |
| `mi,esd-err-irq-gpio` del panel | **no** | el driver no hace ESD check (riesgo de imagen congelada sin recuperación; no bloquea la primera luz) |
| `qcom,mdss-dsi-bl-*` / `bl_ctrl_external` | **sí, portado** a constantes (`O82_BL_*`) | ok |

Props que los drivers mainline **sí leen** y están todos presentes en nuestro DT:
`phys`, `data-lanes`, `qcom,dual-dsi-mode`, `qcom,master-dsi`, `qcom,sync-dual-dsi`
(`dsi_manager.c:55-63`), `qcom,te-source` (solo cmd-mode, no aplica), `reg-names="mdss"`,
`mdp0-mem`, `mdss-dsi-ctrl`, `vdds`/`vdda`, `vddil8b/vsp/vsn`, `reset-gpios`. **No hay ningún prop
faltante** para el display (verificado con `grep of_property_read|of_parse_phandle` sobre
`disp/dpu1`, `dsi`, `msm_mdss.c`, `msm_drv.c`).

### 5.2 Clocks/resets: lo que puede morder

1. `disp_cc_mdss_mdp_clk_src: rcg didn't update its configuration.` — **WARN medido a 0.311 s en
   TODOS los arranques sanos** (`k6-migas.log:1002`, `clk-rcg2.c:136`). La tabla palawan
   (`dispcc-sm8550.c:595-606`) tiene 200/342/402/514/600 MHz pero el OPP del DT ofrece
   **325 y 375 MHz** que NO están ⇒ cualquier `clk_set_rate` a esos valores cae al vecino y deja el
   RCG en un estado que el driver considera «no actualizado». **Qué mirar tras el SMMU**: si el
   WARN reaparece durante el modeset, sospechar del MDP core clock (imagen corrupta/congelada).
   Mitigación barata: añadir 325 M y 375 M a la tabla (o quitar esos OPP del DT).
2. `clk: couldn't set disp_cc_mdss_vsync_clk … 19200000 (-22)` — **no fatal**
   (`clk-conf.c:147-152` imprime y sigue). Ruido esperado; no perseguirlo.
3. **Resets del mdss/DPU**: el DT del mdss lleva `resets = <&dispcc 0>` (BCR MDSS_CORE) y el DPU
   no lleva resets. El `msm_mdss_reset()` (reset_control) corre en `msm_mdss_init` y ya pasa hoy.
4. **Power domains**: mdss `<&dispcc 0>` = `mdss_gdsc` (MDSS_GDSC). Si el GDSC no se registra
   (padres `bi_tcxo`/`sleep_clk` tarde), el mdss difiere y — como el timeout de deferred expira —
   **puede probar con la genpd sin adjuntar**. Hoy el ABL deja el MDSS encendido (por eso
   `dpu hardware revision` lee), pero **en el primer modeset el driver apaga/enciende de verdad**:
   si el GDSC no está adjunto, ahí es donde dolería. Chequeo tras el SMMU:
   `ls /sys/kernel/debug/pm_genpd/` y `cat /sys/kernel/debug/pm_genpd/pm_genpd_summary`
   (buscar `disp_cc_mdss_core_gdsc` y su contador `on`).
5. **ICC del display sin votos reales**: `cliffs_mc_virt` se registró **sin `bcms`**
   (`palawan.c:1850-1860` y comentario `:1830-1838`: «SIN bcms: cero commits RPMh en probe»). Es
   decir: el voto de ancho de banda `mdp0-mem` del DPU **no llega a RPMh** ⇒ no hay garantía de
   DDR para el display. Síntoma si molesta: *underruns* del DPU (no hay mensaje de underrun en
   video mode en este árbol; se vería como imagen congelada/parpadeo). Riesgo real, no bloqueante.

### 5.3 Los 5 fallos más probables DESPUÉS del SMMU (con su síntoma exacto)

| # | fallo | síntoma literal en dmesg | qué hacer |
|---|---|---|---|
| 1 | **CM3/GPU al registrar card0** (§4.4) | silencio total (sin panic); la consola muere; **no** hay OOPS ni pstore | reset físico; repetir con escalera CM3 + doble captura. **Es el más probable de todos** |
| 2 | Algún otro paso de `dpu_kms_hw_init` falla | `[dpu error] rm init failed: -N` / `failed to get hw_mdp` / `failed to init vbif` / `failed to init perf` / `hw_intr init failed` / `modeset init failed: -N` **seguido del OOPS `dead000000000108`** (bug §5.4) | leer la línea `[dpu error]` inmediatamente anterior; el OOPS es cosmético |
| 3 | El attach del dominio del mdss sobre su SID vivo (`0x1c00`, `handoff-smrs`) | muerte muda en la tormenta de attach (sin miga) | §5.5; palancas `uke_attach_log=2`, `uke_protect_smr0=1` |
| 4 | Primer modeset: comandos DCS del panel | `dsi_cmds2buf_tx: cmd dma tx failed, type=0x39, data0=0x…, len=…, ret=…` o `cmd cannot fit into BLLP period, len=…` o `wait for video done timed out` | los comandos son ≤11 B y el BLLP son 9600 B ⇒ un fallo aquí apunta a **relojes del DSI/PHY**, no al tamaño |
| 5 | PLL del PHY o relojes DSI | `DSI PLL(0) lock failed, status=0x…` / `PLL(1) lock failed` / `Failed to set rate byte clk, -N` / `Failed to enable dsi esc clk` | revisar §5.2.1 (RCG del MDP/vsync) y que los `assigned-clock-parents` (PLL del PHY) estén aplicados |

### 5.4 Bug latente: doble `fini` en el camino de error del DPU (nuevo)

* `dpu_kms_hw_init()` inicializa el private obj **al principio** (`dpu_kms.c:1157-1158`) y en
  cualquier error salta a `err_pm_put` → `_dpu_kms_hw_destroy()` → `dpu_kms_global_obj_fini()` →
  `drm_atomic_private_obj_fini(&dpu_kms->global_state)` (`dpu_kms.c:405`).
* El error se propaga a `msm_drm_kms_init` → `msm_drm_uninit` → `msm_drm_kms_uninit` →
  `kms->funcs->destroy` = `dpu_kms_destroy` → **otra vez** `_dpu_kms_hw_destroy` →
  `drm_atomic_private_obj_fini` sobre una lista ya envenenada (`list_del` escribe en
  `0xdead000000000108`) ⇒ OOPS.
* Medido: `k6-migas.log:13.974252-13.974517` (x8=`dead…100`, x9=`dead…122`, `WnR=1`, `FSC=level 0
  translation fault`), stack `drm_atomic_private_obj_fini ← dpu_kms_destroy ← msm_drm_kms_uninit`.
* Efecto práctico: **el kernel queda tainted y el kworker de deferred probe muere**; el arranque
  sigue (medido). No es el muro, pero **enmascara** el fallo real y puede dejar la deferred-probe
  queue tocada (una razón más para no encadenar experimentos en el mismo boot).
* **Consecuencia operativa grave (nueva):** en el mismo camino de error, `msm_drm_uninit()` hace
  `drm_dev_put(ddev)` (`msm_drv.c:103-104`) ⇒ `priv->dev` queda **colgando**. Cualquier `unbind`
  posterior del DPU (`msm_drv_remove` → `msm_drm_uninit`) leería `ddev->registered` de memoria
  liberada (**UAF**) además de repetir el OOPS. Por eso el re-disparo recomendado es el **rebind
  del panel** (o del host DSI), no el del DPU.
* Arreglo de 2 líneas (para después): llamar `dpu_kms_global_obj_fini()` solo si el obj se
  inicializó, o no llamarlo en `dpu_kms_destroy` cuando `hw_init` falló.

### 5.5 El UFS y el dominio por defecto: **ya mitigado por el fork** (con historia medida)

Al bindear el apps-smmu, `bus_iommu_probe()` mete **todos** los clientes con `iommus` en grupos
(incluido `1d84000.ufshc`, sid `0x60`; en total 58 referencias en el DT) y
`iommu_setup_default_domain()` decidiría el dominio por defecto de cada grupo
(`IOMMU_DEFAULT_DMA_STRICT=y`, medido `iommu: Default domain type: Translated` a 0.280 s). Ese es
el escenario que **ya mató la tablet** en sesiones anteriores: el fork lleva un parche explícito
para ello, `qcom_smmu_def_domain_type()` (`arm-smmu-qcom.c:704-708`):

```c
	/* UKE (palawan/cliffs): dominio por defecto IDENTITY para TODOS los maestros. */
	if (dev_of_node(dev) &&
	    of_device_is_compatible(dev_of_node(dev), "qcom,wcn6750-wifi"))
		return 0;	/* sin preferencia -> dominio por defecto (traducido) */
	return IOMMU_DOMAIN_IDENTITY;
```

El comentario del propio parche documenta la medición: «con el repunte del apps-smmu la tablet no
arranca (contador de slot 7→0, fastboot, sin consola y sin pstore) y la bisección con el s222
demuestra que el fallo es el bind del SMMU» — entre los SIDs afectados están los del ADSP
(`qcom,msm_fastrpc_compute_cb*`), que es firmware que el port necesita para arrancar. Con IDENTITY,
UFS/ADSP/resto quedan en **bypass** (como funcionan hoy sin driver de SMMU) y **el display y la GPU
no se ven afectados** porque piden su propio dominio traducido explícitamente:
`iommu_paging_domain_alloc()` + `iommu_attach_device()` (`msm_iommu.c:735-756`).

Riesgo residual (no eliminado):
1. El SID del mdss, `0x1c00 0x02`, está en el **`qcom,handoff-smrs` del vendor** — es decir, el BL
   tiene una traducción **viva** para el display (probablemente el framebuffer del splash). El
   attach del dominio del display **escribirá SMR/S2CR sobre esa entrada viva**, que es
   exactamente la clase de escritura que mata (mapa de minas #P13-#P16). El momento crítico, por
   tanto, no es solo el reset del SMMU: también el `attach` del mdss.
2. Con IDENTITY el quirk de bypass de este SMMU (`arm-smmu-qcom.c:675-687`, medido: BYPASS se
   relee como FAULT y el driver lo convierte en TRANS al CB reservado más alto) tiene que estar
   bien resuelto para los clientes en bypass; ya lo está hoy para el kgsl-smmu, pero el apps-smmu
   nunca ha llegado a ese punto.
3. Si el disco empieza a dar errores UFS/EXT4 justo tras el bind, **rollback antes de seguir**
   (boot_b bueno `ffff8c51…` + `set_active`); la palanca de diagnóstico es
   `uke_attach_log=2` (+ `uke_protect_smr0=1` si el attach del mdss es el que mata).

---

## 6. GPU (breve, para después de card0)

* **No hay «card1»**: la GPU es un **componente del mismo DRM device** que el display
  (`a3xx_ops` bindeado por el master del DPU, `adreno_device.c:211-259`). Lo que aparece es
  `/dev/dri/card0` + `/dev/dri/renderD128`. «card1» solo existiría con
  `separate_gpu_kms=1` (`msm_drv.c:57-59`), que es la línea F5/B1.
* **Firmware: ya está en la tablet.** Paquete propio `uke-gpu-firmware 1-1`
  (`build/pkg/uke-gpu-firmware/`, PKGBUILD + 3 blobs; `build/gates/firmware-gpu.sha256`:
  `gen71100_gmu.bin 435c7bac…`, `gen71100_sqe.fw b6df660d…`, `gen71100_zap.mbn 0c86e4ae…`),
  instalado y verificado en el aparato (`pacman -Qk` = 14 ficheros, 0 missing;
  `VERIFICACION-ORQUESTADOR.md:793-802`). Ojo: **no está en `build/rootfs/arch-rootfs.img`**
  (grep = 0) porque se instaló después, sobre el sistema vivo — si algún día se re-flashea el
  rootfs desde esa imagen, **hay que reinstalar el paquete**.
  Rutas que pide el driver: `qcom/gen71100_sqe.fw`, `qcom/gen71100_gmu.bin`,
  `qcom/uke/gen71100_zap.mbn` (+ legado en `/lib/firmware/`).
* **Qué falta para render**: nada de firmware; falta **que el CM3 arranque**. Y ahí está el cuelgue
  duro conocido: `hw_init` → `a6xx_gmu_resume` → CM3. La H1 («el CM3 depende del apps-smmu») está
  **archivada/refutada** por R-57 (tres premisas falsadas con código) — **no re-proponerla**.
* **Qué NO tocar hasta tener `measure-cm3.sh` corrido**: (a) **no abrir `/dev/dri/card0`** con
  ninguna herramienta (`modetest`, `drm_info`, `eglinfo`, compositor) — cada apertura reintenta el
  CM3; (b) **no** hacer `unbind/bind` del `adreno` ni tocar sus params en runtime (R-26, ronda 33:
  nada de MMIO en caliente); (c) **no** flashear `separate_gpu_kms=1` sin reabrir F5/B1 con
  pre-registro (por cmdline no arrancó, causa desconocida). El procedimiento ya escrito y probado
  en frío es `build/cm3-ladder/measure-cm3.sh` (+ `uke-cm3-ladder.diff`, aplicado y compilado OK);
  su regla de oro: `dmesg -n 7`, doble captura **antes** del trigger, `sync` antes de cualquier
  reboot, y **no reiniciar** (reset físico).

---

## 7. RUNBOOK POST-SMMU (copiar y pegar)

> Ejecutar en la tablet por ssh (o consola serie). Regla #P12: **el bind del SMMU SIEMPRE
> desprendido en la tablet**. Antes de empezar: doble captura viva y `e2fsck` pendiente asumido.
> Si en cualquier momento la tablet deja de responder: **no** insistir; el CM3 y los wedges no
> tienen watchdog ⇒ reset físico.

```sh
# ---------- 0) PREPARACIÓN (antes de tocar el SMMU) ----------
dmesg -n 7
mkdir -p /tmp/r2
cat /sys/kernel/debug/devices_deferred > /tmp/r2/deferred.antes
ls -l /sys/class/drm/ /dev/dri/ 2>&1 | tee /tmp/r2/drm.antes
cat /proc/device-tree/soc/apps-smmu@15000000/reg | xxd | head -2      # esperado: 15000000 00200000
tr -d '\0' < /proc/device-tree/soc/display-subsystem@ae00000/dsi@ae94000/panel@0/compatible
                                                                     # esperado: xiaomi,uke-o82-4202-0b
command -v modetest || echo "OJO: modetest ausente -> via fbcon (§4.3)"
# doble captura (dos canales, uno por lector):
#   en el PC:  ssh … "dmesg -w" > ~/proyectos/out/r2-migas.log      (stream)
#   en la tablet: /path/captura-robusta.sh (consola ACM)             (resiste mejor la muerte)

# ---------- 1) BIND DEL SMMU (desprendido) ----------
nohup sh -c 'echo -n 15000000.apps-smmu > /sys/bus/platform/drivers_probe' >/tmp/r2/bind.log 2>&1 &
sleep 20
dmesg | grep -E "apps-smmu|iommu group|no IOMMU" | tail -30
cat /sys/kernel/debug/devices_deferred > /tmp/r2/deferred.despues
# ÉXITO: "probing hardware configuration…" + "71 context banks" + "Adding to iommu group" del mdss
#        y el apps-smmu FUERA de deferred.
# SI NO hay "Adding to iommu group" del mdss -> forzar el probe del mdss:
echo -n ae00000.display-subsystem > /sys/bus/platform/drivers_probe ; sleep 5

# ---------- 2) ¿EL DPU VE EL IOMMU? ----------
# El master bind ya falló con OOPS si el SMMU bindeó tarde -> hay que re-dispararlo.
# PRIMERO el martillo pequeño: rebind del PANEL (leaf; su detach dispara component_del/add).
echo -n ae94000.dsi.0 > /sys/bus/mipi-dsi/drivers/panel-xiaomi-o82-dualdsi/unbind ; sleep 1
echo -n ae94000.dsi.0 > /sys/bus/mipi-dsi/drivers/panel-xiaomi-o82-dualdsi/bind
# ALTERNATIVA: rebind del host DSI (también seguro): msm_dsi
#   echo -n ae94000.dsi > /sys/bus/platform/drivers/msm_dsi/unbind ; sleep 1 ; … /bind
# ÚLTIMO RECURSO (avisado): rebind del DPU (el master). Su unbind pasa por msm_drm_uninit con
# priv->dev ya liberado por el camino de error -> UAF + el OOPS del bug §5.4:
#   echo -n ae01000.display-controller > /sys/bus/platform/drivers/msm_dpu/unbind ; sleep 1 ; … /bind
sleep 10
dmesg | tail -60
# ÉXITO: "dpu hardware revision:0xa0010000" y NO debe salir "[drm] no IOMMU, bailing out"
# ÉXITO 2: "[drm] Initialized msm 1.13.0 for ae01000.display-controller on minor 0"
# OJO: a partir de aquí el CM3 arranca (cliente fbdev) -> cuelgue posible. Ten la captura lista.

# ---------- 3) card0 ----------
ls -l /dev/dri/
for f in status enabled modes; do echo -n "$f: "; cat /sys/class/drm/card0-DSI-1/$f; done
cat /sys/kernel/debug/dri/0/state | sed -n '1,30p'
cat /sys/class/graphics/fb0/name /sys/class/graphics/fb0/virtual_size 2>/dev/null

# ---------- 4) PRIMERA LUZ ----------
# (a) vía fbcon: normalmente ya habrá ocurrido sola; si no:
echo 0 > /sys/class/vtconsole/vtcon1/bind ; echo 1 > /sys/class/vtconsole/vtcon1/bind
# (b) vía modetest (si existe):
CONN=$(modetest -M msm -c | awk '$4=="connected" && $5 ~ /^DSI/ {print $1}')
CRTC=$(modetest -M msm -p | awk '/^CRTCs:/{f=1;next} f && /^[0-9]+/ {print $1; exit}')
modetest -M msm -s "$CONN"@"$CRTC":3200x2136@XR24

# ---------- 5) VERIFICACIÓN SIN OJOS ----------
cat /sys/class/backlight/ae94000.dsi.0/brightness          # 307
cat /sys/kernel/debug/regulator/uke_panel_vsp/state        # enabled
cat /sys/kernel/debug/regulator/uke_panel_vsn/state        # enabled
dmesg | grep -Ei "cmd dma tx failed|lock failed|video done timed out|pic_width|underrun|no IOMMU"
grep -E "byte|pixel|mdp" /sys/kernel/debug/clk/clk_summary | head

# ---------- 6) ROLLBACK si algo va mal ----------
# boot_b bueno: build/backup-par-bueno/boot_b-lee.img (ffff8c51…)  [fastboot, con pre-registro]
# dtbo_b: NO tocar (s258 sigue siendo el bueno)
```

**Árbol de decisión de una línea por desenlace** (para anotar en el ledger):

| desenlace | siguiente jugada |
|---|---|
| bind OK + `Adding to iommu group` mdss + card0 + fb0 | primera luz (fbcon o modetest) → foto; **antes**, escalera CM3 lista |
| bind OK pero el DPU sigue `-19` | falta el grupo del mdss: `echo -n ae00000.display-subsystem > /sys/bus/platform/drivers_probe` y repetir §7.2 |
| bind OK, card0, pero `kms hw init failed: -N` + OOPS `dead…` | leer la línea `[dpu error]` previa; es §5.3-fila 2 (el OOPS es el bug §5.4) |
| bind OK y el disco empieza a fallar | §5.5: rollback de boot_b/dtbo_b y no repetir sin `attach_log=2` |
| muerte muda durante el bind | última miga UKE-POKE = registro exacto (mapa de minas #P13-#P16) |
| cuelgue tras card0 (sin dmesg) | CM3 (§4.4): reset físico; siguiente ciclo con escalera CM3 |

---

## Anexo A — Cómo se reprodujo el DT (para repetirlo)

```sh
# 1) payload del dtbo vigente (contenedor dt_table -> DTB)
python3 build/bootimg/dtbo-extract.py build/bootimg/s258-panel-gpio2.img /tmp/s258-payload.dtb
#    payload_bytes 608405 · payload_sha256 ea6ac36ed395a6f117aa18e82eb382aa53f32fff96bfa6de5501a921c3c3253a
# 2) base: base-dtb.img = 4 DTBs cliffs concatenados (Cliffs, Cliffs 7, Cliffs7P, CliffsP);
#    fdtoverlay usa el PRIMERO (475426 B)
fdtoverlay -i ~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img -o /tmp/merged.dtb /tmp/s258-payload.dtb
dtc -I dtb -O dts /tmp/merged.dtb -o /tmp/merged.dts
fdtget /tmp/merged.dtb /soc/display-subsystem@ae00000 compatible        # qcom,palawan-mdss
fdtget /tmp/merged.dtb /soc/display-subsystem@ae00000/dsi@ae94000/panel@0 compatible
                                                                        # xiaomi,uke-o82-4202-0b
```

**Aviso de fidelidad (importante):** `fdtoverlay` **no copia las props de raíz del overlay**
(`model`, `qcom,msm-id`, `qcom,board-id` quedan los del base) mientras que el ABL **sí** lo hace
(el DT vivo dice `model = "Qualcomm Technologies, Inc. Uke based on SM8635"` y `compatible` con
`qcom,lamma`, que vienen del payload). Para los **nodos** (fragmentos) la fusión es fiel: el DT
vivo coincide con lo reconstruido en todos los nodos del display. El DT vivo de la captura del
28-sep 18:32 es de la era s238 (p. ej. `panel@0/pinctrl-names = "default sleep"`, antes del fix
s258), así que para lo específico de s258 manda `fdtoverlay` + los gates del generador.

## Anexo B — Números del modo (calculados con las fórmulas del driver)

| magnitud | valor |
|---|---|
| modo | 3200×2136, `clock` = 967 428 kHz, htotal 3490, vtotal 2310 ⇒ **120,000 Hz exactos** |
| DSC | 1.1, 8 bpp, 10 bpc, slices 800×24, `slice_count=2`, block pred, `convert_rgb` |
| pclk (bonded+DSC) | 317 116 800 Hz total → **158 558 400 Hz por enlace** |
| byte clk por enlace | **118 918 800 Hz** (bpp 24, 4 lanes) |
| bit rate por lane | ≈ **951,4 Mbps** |
| VCO del PLL | ≈ 951 MHz (rango cfg 8650: 600 M – 5 G) |
| BLLP por comando (video) | 9600 B |
| init del panel | 964 B / 104 comandos + `b3,b2` + `0x11` (+120 ms) + `0x29` |
| brillo | min 4, max 0xfff, init 0x133 = 307 |

## Anexo C — Fuentes citadas (todas leídas en esta revisión)

`/var/tmp/uke-k1`: `drivers/gpu/drm/msm/{msm_drv.c,msm_kms.c,msm_mdss.c,msm_iommu.c,msm_fbdev.c,
msm_debugfs.c}`, `disp/dpu1/{dpu_kms.c,dpu_encoder.c,dpu_encoder_phys_vid.c,catalog/dpu_10_1_palawan.h}`,
`dsi/{dsi.c,dsi_cfg.c,dsi_host.c,dsi_manager.c,phy/dsi_phy.c,phy/dsi_phy_7nm.c}`,
`panel/panel-xiaomi-o82-dualdsi.c`, `drivers/clk/qcom/{dispcc-sm8550.c,gpucc-palawan.c,gcc-palawan.c,
clk-rcg2.c,common.c,gdsc.c}`, `drivers/interconnect/qcom/palawan.c`, `drivers/soc/qcom/{ubwc_config.c,
uke-panic-fb.c}`, `drivers/iommu/{iommu.c,arm/arm-smmu/arm-smmu.c,arm/arm-smmu/arm-smmu-qcom.c}`,
`drivers/base/{dd.c,bus.c,platform.c}`, `drivers/gpu/drm/{drm_drv.c,drm_file.c,drm_client.c,
clients/drm_client_setup.c,clients/drm_fbdev_client.c,drm_fb_helper.c,drm_mipi_dsi.c}`,
`include/dt-bindings/clock/qcom,palawan-dispcc.h`, `/var/tmp/uke-k1-build/.config`.

Proyecto: `docs/historia/ESTADO-VIVO.md`, `docs/historia/PLAN-PANTALLA.md`, `OBJETIVOS.md`, `build/gates/{PRE-REGISTRO-PANTALLA.md,
INFORME-K6-BUILD.md,INFORME-A-PRIMA.md,AUDITORIA-REGULADORES-Y-GPIO.md,DT-RAILS-L.md,
INFORME-PHY-PANEL.md,EVIDENCIA-PANTALLA-28sep.md,VERIFICACION-ORQUESTADOR.md,REVISTA-ARCH-AARCH64.md,
PRE-REGISTRO-F5-B1.md}`, `build/cm3-ladder/INFORME-CM3.md`, `build/evidencia/2026-09-28/`
(`device-tree.tar.gz`, `dt-nodos-clave.txt`), `build/bootimg/{dtbo-extract.py,mkdtbo-s253.py}`,
`build/rootfs/` (grep de `modetest`/`libdrm`), `build/pkg/uke-gpu-firmware/`,
`~/proyectos/out/k6-migas.log`, `~/proyectos/out/k6b-migas.log`.
