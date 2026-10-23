# INFORME-PHY-PANEL — SG-PHY-PANEL (28-sep-2026)

Subagente SG-PHY-PANEL (fase F1 de docs/historia/PLAN-PANTALLA.md, piezas (a) PHY y (b) panel).
Cero escrituras en la tablet, cero flashes, `~/gpu-work/palawan-linux` solo lectura
(se compilo sobre copia `/tmp`, patron `aplicar-parche-msi.sh`).

---

## 0. Titulares (lo que hay que leer aunque no se lea nada mas)

1. **DATO — El hueco 2 (compatible del DSI PHY) YA ESTA CERRADO en el dtbo flasheado.**
   El payload de `s238` (`dtbo_b` vivo, sha `bdb361df…0022`) contiene `fragment@1105` con el
   arbol display mainline COMPLETO: `/soc/display-subsystem@ae00000/phy@ae95000` y `phy@ae97000`
   con `compatible = "qcom,palawan-dsi-phy-4nm", "qcom,sm8650-dsi-phy-4nm"`, los 3 `reg` con
   `reg-names` correctos, `clocks` con `iface`/`ref` y `vdds-supply`. El hermano lo midio
   ligado: `ae95000.phy -> msm_dsi_phy` y `ae97000.phy -> msm_dsi_phy`
   (`build/gates/PRE-REGISTRO-F5-B1.md:266`; raw en `proyectos/ubuntu-permanente/docs/
   ESTADO-ACTUAL.md:207-208`, ledger #410).
   **Verificado aqui ademas por construccion**: el fragmento de la T1 aplicado sobre el payload
   de `s238` da **delta CERO** (`+0/-0` lineas en los 4271 nodos fusionados) -> es idempotente,
   no falta nada.
2. **DATO — El driver del panel compila como MODULO, limpio.** `panel-xiaomi-o82-dualdsi.ko`,
   sha256 `9890258752426704508bcd0dd51784898816faf6c242d42cb18c7a4125e88a14`, 387 432 B,
   vermagic `7.2.0-rc2-palawan SMP preempt mod_unload aarch64`, `alias=of:N*T*Cxiaomi,uke-o82-4202-0b`.
   **NO hizo falta ningun buildfix** (0 errores, 0 warnings): `build/gates/patches/panel-o72-buildfix.diff`
   es un diff vacio a proposito.
3. **DATO — El driver del panel NO esta en el kernel de ESTE proyecto.**
   `build/kernel-pokes/.config:4952` = `# CONFIG_DRM_PANEL_XIAOMI_O82_DUALDSI is not set`
   (idem en `config-bueno-actual.config`: el simbolo ni aparece). El `.ko` de T2 **es necesario**;
   sin el, `panel@0` del DT no tiene driver en nuestro arranque.
4. **Correccion al enunciado**: `~/gpu-work/w4-panel/` **NO contiene ningun `.c`** (verificado con
   `find`: solo README/PORT-TODO/Kconfig.fragment/Makefile.fragment/uke-display-o82.dtsi/yaml).
   El driver de verdad es `~/gpu-work/palawan-linux/drivers/gpu/drm/panel/panel-xiaomi-o82-dualdsi.c`
   (681 lineas, 24-sep, ya en el arbol) — y su `compatible` **coincide exacto** con el del DT vivo.
   w4-panel es un plan viejo (11-sep) que apunta a otro driver (`proyectos/ubuntu-uke/kernel/
   panel-o82/panel-xiaomi-o82.c`, 1425 lineas, `compatible = "xiaomi,uke-panel-o82-42020b"`),
   que **no** casa con el DT vivo.
5. **El muro que queda no es mio**: apps-smmu -> `msm_dpu` con `no IOMMU, bailing out`
   (`msm_kms.c:198`) => sin `card0` aunque PHY y panel esten perfectos. Es el hueco 1.

---

## T1 — Mapear el compatible del DSI PHY

### T1.1 Tabla COMPLETA de `dsi_phy_dt_match` (DATO)

`drivers/gpu/drm/msm/dsi/phy/dsi_phy.c:516-586`. Todo el bloque de 7nm y posteriores esta
dentro de **un solo** `#ifdef CONFIG_DRM_MSM_DSI_7NM_PHY` (`:557` abre, `:584` cierra) — o sea que
ese simbolo gatea tambien los PHY de 5nm/4nm/3nm.

| compatible | cfg | linea |
|---|---|---|
| qcom,dsi-phy-28nm-hpm | dsi_phy_28nm_hpm_cfgs | :518 |
| qcom,dsi-phy-28nm-hpm-fam-b | dsi_phy_28nm_hpm_famb_cfgs | :520 |
| qcom,dsi-phy-28nm-lp | dsi_phy_28nm_lp_cfgs | :522 |
| qcom,dsi-phy-28nm-8226 | dsi_phy_28nm_8226_cfgs | :524 |
| qcom,dsi-phy-28nm-8937 | dsi_phy_28nm_8937_cfgs | :526 |
| qcom,dsi-phy-20nm | dsi_phy_20nm_cfgs | :530 |
| qcom,dsi-phy-28nm-8960 | dsi_phy_28nm_8960_cfgs | :534 |
| qcom,dsi-phy-14nm | dsi_phy_14nm_cfgs | :538 |
| qcom,dsi-phy-14nm-2290 | dsi_phy_14nm_2290_cfgs | :540 |
| qcom,dsi-phy-14nm-660 | dsi_phy_14nm_660_cfgs | :542 |
| qcom,dsi-phy-14nm-8953 | dsi_phy_14nm_8953_cfgs | :544 |
| qcom,sm6125-dsi-phy-14nm | dsi_phy_14nm_2290_cfgs | :546 |
| qcom,sm6150-dsi-phy-14nm | dsi_phy_14nm_6150_cfgs | :548 |
| qcom,dsi-phy-10nm | dsi_phy_10nm_cfgs | :552 |
| qcom,dsi-phy-10nm-8998 | dsi_phy_10nm_8998_cfgs | :554 |
| qcom,dsi-phy-7nm | dsi_phy_7nm_cfgs | :558 |
| qcom,dsi-phy-7nm-8150 | dsi_phy_7nm_8150_cfgs | :560 |
| qcom,sa8775p-dsi-phy-5nm | dsi_phy_5nm_8775p_cfgs | :562 |
| **qcom,sar2130p-dsi-phy-5nm** | dsi_phy_5nm_sar2130p_cfgs | **:564** |
| qcom,sc7280-dsi-phy-7nm | dsi_phy_7nm_7280_cfgs | :566 |
| qcom,sm6375-dsi-phy-7nm | dsi_phy_7nm_6375_cfgs | :568 |
| qcom,sm8350-dsi-phy-5nm | dsi_phy_5nm_8350_cfgs | :570 |
| qcom,sm8450-dsi-phy-5nm | dsi_phy_5nm_8450_cfgs | :572 |
| qcom,milos-dsi-phy-4nm | dsi_phy_4nm_milos_cfgs | :574 |
| **qcom,sm8550-dsi-phy-4nm** | dsi_phy_4nm_8550_cfgs | **:576-577** |
| **qcom,sm8650-dsi-phy-4nm** | dsi_phy_4nm_8650_cfgs | **:578-579** |
| qcom,sm8750-dsi-phy-3nm | dsi_phy_3nm_8750_cfgs | :580-581 |
| qcom,kaanapali-dsi-phy-3nm | dsi_phy_3nm_kaanapali_cfgs | :582-583 |

`"qcom,dsi-phy-v5.2"` **no aparece** en la tabla (DATO). Los cuatro cfgs con el quirk
`DSI_PHY_7NM_QUIRK_V5_2` estan en `dsi_phy_7nm.c` (fichero compartido por 7nm/5nm/4nm/3nm).

### T1.2 Nodos PHY del vendor, completos (DATO)

Descompilados de `stock-fdt2.dtb` (`qcom,msm-id = <0x283 0x10000>` — verificado con `dtc`; es el
fdt de este aparato) y presentes identicos en `base-dtb.img:15853/15886`, el DT base real que
fusionan `mkdtbo-s2xx.py` (`fdtoverlay -i base-dtb.img -o merged <dtbo>`):

```
qcom,mdss_dsi_phy0@ae95500 {            qcom,mdss_dsi_phy1@ae97500 {
    compatible = "qcom,dsi-phy-v5.2";       compatible = "qcom,dsi-phy-v5.2";
    reg = <0xae95000 0xa00                  reg = <0xae97000 0xa00
           0xae95500 0x400                  0xae97500 0x400
           0xae94200 0xa0>;                 0xae96200 0xa0>;
    reg-names = "dsi_phy", "pll_base",      (igual)
                "dyn_refresh_base";
    vdda-0p9-supply = <0x14d>;              (igual)
    pll-label = "dsi_pll_4nm";              pll-label = "dsi_pll_4nm";
    pll_codes_region = <0x487>;             (igual)
    qcom,dsi-pll-ssc-en;  (down-spread)     (igual)
    qcom,panel-allow-phy-poweroff;          (igual)
    qcom,platform-lane-config = <0xa0a 0xa0a 0xa0a 0xa0a 0x8a8a>;
    qcom,platform-strength-ctrl = [55 03 55 03 55 03 55 03 55 00];
    qcom,platform-regulator-settings = [1d 1d 1d 1d 1d];
    cell-index = <0x00>;  label = "dsi-phy-0";
    #clock-cells = <0x01>;   phandle = <0x48c>;
    (SIN clocks, SIN clock-names, SIN status, SIN #phy-cells)
    qcom,phy-supply-entry@0 { supply-name = "vdda-0p9"; min 0xd6d80; max 0xe7ef0; enable-load 0x17ed0; }
}
```

`pll-label = "dsi_pll_4nm"` es la pista fuerte: el vendor **se identifica como 4nm**.

### T1.3 Candidato elegido: `qcom,sm8650-dsi-phy-4nm`

**DATO — `dsi_phy_4nm_8650_cfgs` (`dsi_phy_7nm.c:1485-1506`):**
```
1487  .regulator_data = dsi_phy_7nm_98000uA_regulators,   /* "vdds", 98000 uA */
1492  .ops.pll_init  = dsi_pll_7nm_init
1503  .io_start = { 0xae95000, 0xae97000 },
1504  .num_dsi_phy = 2,
1505  .quirks = DSI_PHY_7NM_QUIRK_V5_2,
```
`dsi_phy_get_id()` (`dsi_phy.c:594-611`) exige `res->start == cfg->io_start[i]` para el recurso
llamado **`dsi_phy`**: los nodos mainline de `fragment@1105` declaran
`reg = <0xae95000 0x200 0xae95200 0x280 0xae95500 0x400>` => `0xae95000` == `io_start[0]` (id 0) y
`0xae97000` == `io_start[1]` (id 1) — **encaje exacto**. Ademas la region `dsi_pll`
(`0xae95500 0x400` / `0xae97500 0x400`) es **la misma direccion y tamaño** que el `pll_base` del
vendor: el hardware del PLL coincide region a region.

**Ranking completo (por que este y no otro):**

| # | compatible | io_start | quirk | µA | veredicto |
|---|---|---|---|---|---|
| 1 | **qcom,sm8650-dsi-phy-4nm** | {0xae95000,0xae97000} (:1503) | V5_2 (:1505) | 98000 (:1487) | **ELEGIDO** |
| 2 | qcom,sm8550-dsi-phy-4nm | {0xae95000,0xae97000} (:1480) | V5_2 (:1482) | 98400 (:1464) | plan B; solo cambia la carga |
| 3 | qcom,sar2130p-dsi-phy-5nm | {0xae95000,0xae97000} (:1434) | V5_2 (:1436) | 97800 (:1418) | descartado: es 5nm, el vendor dice 4nm |
| 4 | qcom,sm8750-dsi-phy-3nm | {0xae95000,0xae97000} (:1526) | V7_2 (:1528) | 98000 (:1510) | descartado: quirk V7_2 (secuencia distinta) |
| - | qcom,dsi-phy-7nm (8250/…): {0xae94400,0xae96400} (:1281) | no encaja | V4_1 | 36000 | descartado por io_start |
| - | qcom,dsi-phy-v5.2 (vendor) | - | - | - | **no esta en la tabla** |

Y el dato que cierra el caso: **el propio DT del fork ya lo eligio**:
`palawan.dtsi:3549` y `:3627` = `compatible = "qcom,palawan-dsi-phy-4nm", "qcom,sm8650-dsi-phy-4nm"`.
Mismo par que el payload flasheado.

**Lo que mediria en vivo para desambiguar 8650 vs 8550** (NO VERIFICADO aun): no hace falta
medir nada mientras el bind de `ae95000.phy` funcione; el unico sintoma que distinguiria un rail
demasiado bajo es `regulator enable failed` o inestabilidad del PLL en el bring-up — y el hermano
ya midio el bind de los dos PHY (#410), luego el 8650 (98000 µA) es correcto para este hardware.
Si algun dia fallara por el rail: subir `regulator-min/max` de `pmxr2230_l2` no aplica (el rail es
`0xd6d80..0xe7ef0` en el DT); el cambio de prueba seria al plan B (8550, 98400 µA).

### T1.4 Fragmento y su validacion

Entregado: **`build/gates/FRAGMENTO-PHY.dts`**. Contiene dos variantes documentadas:

* **VARIANTE A (recomendada)**: asercion idempotente sobre los nodos **mainline**
  (`/soc/display-subsystem@ae00000/phy@ae95000` y `phy@ae97000`) con `compatible` mainline,
  los 3 `reg` + `reg-names` (`dsi_phy`/`dsi_phy_lane`/`dsi_pll`), `clocks`+`clock-names`
  (`iface`/`ref`), `#clock-cells`, `#phy-cells`, `vdds-supply = <0x14d>` y `status = "okay"`.
* **VARIANTE B (comentada)**: traduccion in-place del nodo **vendor**
  (`/soc/qcom,mdss_dsi_phy0@ae95500`, `…phy1@ae97500`) — lo que literalmente pedia el enunciado.
  **NO usar junto con A**: crearia un segundo `platform_device` para el mismo MMIO con el mismo
  driver; la segunda instancia falla en `devm_of_clk_add_hw_provider()` (`dsi_phy.c:705`,
  proveedor de clocks duplicado).

**DATO — por que renombrar SOLO el compatible (lo "facil") NO funciona** (esto refuta la via
ingenua, y ya lo habia visto otro subagente en `VERIFICACION-ORQUESTADOR.md:1088-1096`):
`dsi_phy_driver_probe()` (`dsi_phy.c:613-736`) exige, en este orden, cosas que el nodo vendor no
tiene bajo esos nombres:
* `:648` `msm_ioremap_size(pdev, "dsi_phy", …)` -> el vendor si lo tiene, OK.
* `:653` `msm_ioremap_size(pdev, "dsi_pll", …)` -> el vendor lo llama **`pll_base`** => falla
  ("Failed to map pll base") y el probe aborta.
* `:658-660` `msm_ioremap_size(pdev, "dsi_phy_lane", …)` porque `has_phy_lane = true`
  (`dsi_phy_7nm.c:1486` para el 8650) -> el vendor **no tiene** esa region.
* `:694` `pm_clk_add(dev, "iface")` -> el vendor **no tiene** `clocks`/`clock-names`.
* `:678-680` `devm_regulator_bulk_get_const(…, "vdds", …)` (`dsi_phy_7nm.c:1259-1261`) ->
  el vendor lo llama **`vdda-0p9`**.
* `:594-611` `dsi_phy_get_id()` -> el vendor SI encaja aqui (`dsi_phy` empieza en 0xae95000),
  pero muere en las tres lineas anteriores.
Ademas `pll_codes_region` y `qcom,dsi-pll-ssc*` **no se leen en ningun sitio** del arbol
(`grep -rn pll_codes_region drivers/gpu/drm/msm/ drivers/clk/qcom/` = vacio): son props de vendor
que mainline ignora — inofensivas, no hay que borrarlas.

**Validacion ejecutada** (mismo procedimiento que `mkdtbo-s252.py`, evidencia reproducible):
```
payload s238      : 607470 B   (imagen 607534 B, margen 2770 B sobre 610304)
payload s254(PHY) : 608206 B   (+736 B; imagen 608270 B, margen 2034 B)
fdtoverlay -i base-dtb.img -o merged  <payload+fragmento A>   -> rc=0
diff merged-s238.dts vs merged-s254.dts : +0 / -0 lineas
grep 'qcom,sm8650-dsi-phy-4nm' merged-s254.dts -> 2 nodos (lineas 878 y 935)
```
=> **delta cero**: el mapeo ya estaba. El fragmento sirve como (a) prueba ejecutable de que el
hueco esta cerrado, (b) red de seguridad si algun dia se parte de un payload sin `fragment@1105`.

**RECOMENDACION AL ORQUESTADOR (presupuesto)**: el dtbo_b tiene **2770 B** de margen y el
fragmento PHY gasta 736 B. Como es un **no-op**, **no lo metas en s254**: deja los 2770 B para el
fragmento A' del SMMU (s253). Si s254 se empaqueta igualmente, el gate correcto es "delta 0", no
"el PHY liga" (ya liga).

---

## T2 — Compilar el driver del panel como MODULO

### T2.1 Clasificacion del driver (DATO)

* **Es un `drm_panel` estandar de mainline**: `struct drm_panel` + `drm_panel_funcs`
  (`.prepare/.unprepare/.get_modes`), registrado con `devm_drm_panel_alloc()`
  (`panel-xiaomi-o82-dualdsi.c:581`), `drm_panel_add()` (`:637`) y
  `module_mipi_dsi_driver()` (`:677`) con su `of_device_id` (`:663-666`). **No hay ninguna API
  privada de msm/vendor** (no `msm_drm_*`, no `sde_*`): grep limpio.
* **Dual-DSI: si, con la API mainline del fork.** Registra un segundo `mipi_dsi_device`
  (`dsi_info = { "dsi-secondary", 0, NULL }`, `:572`; `devm_mipi_dsi_device_register_full`
  `:617`) sobre el host que saca de `of_graph_get_remote_node(node, 1, -1)` (`:605`), y manda
  cada comando a los dos links con `mipi_dsi_dual_dcs_write_buffer_multi()` (`:226-228`,
  `:327-338`) via `struct mipi_dsi_multi_context`. Mismo patron que
  `panel-novatek-nt36523.c`.
* **DSC: si, por el camino mainline.** `struct drm_dsc_config` propio (`:535-545`:
  1.1, 10 bpc -> 8 bpp, slice 800x24, pred on) colgado en `dsi->dsc = &ctx->dsc` (`:643`); el
  host msm lo consume para el PPS. **No** manda PPS al panel (el vendor no lo manda).
* **Backlight**: crea su propio `backlight_device` con DCS 0x51 12 bits
  (`o82_bl_update_status`, `:432-451`), nombre = `dev_name(dsi)` = `ae94000.dsi.0`. **No usa**
  `drm_panel_of_backlight()` ni el nodo `backlight` del DT (por eso el `backlight = <&ktz8866_0>`
  del plan w4-panel es irrelevante para ESTE driver).
* **Supplies**: pide `vddil8b`, `vsp`, `vsn` (`:78-82`, `devm_regulator_bulk_get_const` `:586`)
  y `reset` gpio (`:591`, activo-bajo). Los tres nombres existen EXACTO en el `panel@0` del DT
  vivo, mas `reset-gpios = <&tlmm 2 GPIO_ACTIVE_LOW>`.
* **Kernel/includes que asume**: 7.x (`devm_drm_panel_alloc`, `mipi_dsi_*_multi`,
  `prepare_prev_first`, `BACKLIGHT_SCALE_NON_LINEAR`, `mipi_dsi_dcs_set_display_brightness_large`).
  Todo existe en palawan 7.2-rc2: lo **prueba** que compile sin un solo warning.
* **NO es estilo vendor** (el supuesto que invalidaba el plan): no hay que parar nada.

### T2.2 Build (DATO)

Script reproducible nuevo: **`build/gates/compilar-panel-o82.sh`** (patron `aplicar-parche-msi.sh`,
incluidos sus tres tropiezos: copia rsync sin `.git`/objetos, `archprepare modules_prepare` antes
del `M=`, `.ko` buscado en la copia; mas un cuarto: `Module.symvers` de
`~/gpu-work/ramaa/s10/build-s122` — solo lectura — porque sin el, modpost no resuelve
`drm_panel_*`/`mipi_dsi_*` del vmlinux).

```
DST   = /tmp/opencode/sg-panel            (rsync de palawan-linux, 1,8 GB)
O     = /tmp/opencode/sg-panel-build-out  (.config = config-bueno-actual.config)
delta de config: SOLO DRM_PANEL_XIAOMI_O82_DUALDSI: not-set -> =m
comando: make O=$O -C $DST -j16 M=drivers/gpu/drm/panel modules
log    : /tmp/opencode/sg-panel-build.log  (17:52:23 -> 17:52:43)
  :184  CC [M]  panel-xiaomi-o82-dualdsi.o
  :205  CC [M]  panel-xiaomi-o82-dualdsi.mod.o
  :224  LD [M]  panel-xiaomi-o82-dualdsi.ko
  0 errores, 0 warnings (grep 'error:|warning:' = vacio)
```
Artefacto: **`build/pkg/panel-o82/panel_xiaomi_o82_dualdsi.ko`**
(sha256 en `build/pkg/panel-o82/sha256.txt`):
```
sha256 : 9890258752426704508bcd0dd51784898816faf6c242d42cb18c7a4125e88a14
tamano : 387432 B        BuildID: e8e000cace0955eeb3d7e06b0d7b91615b0063c1
vermagic: 7.2.0-rc2-palawan SMP preempt mod_unload aarch64
depends : (vacio — todo builtin)
```
`nm -u` = **36 simbolos indefinidos, todos razonables** y exportados por el kernel objetivo
(por eso modpost no se quejo): `backlight_*`, `drm_mode_*`, `drm_panel_add/remove`,
`mipi_dsi_dcs_*`, `mipi_dsi_dual_dcs_write_buffer_multi`, `devm_mipi_dsi_*`,
`devm_regulator_bulk_get_const`, `regulator_*`, `of_graph_get_remote_node`,
`of_find_mipi_dsi_host_by_node`, `gpiod_*`, `__devm_drm_panel_alloc`, `__stack_chk_fail`.
`modinfo`: `alias=of:N*T*Cxiaomi,uke-o82-4202-0b` (+ variante `C*`) — o sea que el
`MODULE_DEVICE_TABLE(of, …)` si genera el modalias de autoload.

**Buildfix**: NINGUNO. `build/gates/patches/panel-o72-buildfix.diff` = diff vacio documentado
(el `.c` de w4-panel/arbol no se toco; la copia /tmp es byte-identica al original en ese fichero).

**Nota .gitignore**: `build/pkg` **no** esta ignorado en bloque; se ignoran
`build/pkg/*/pkg/`, `build/pkg/*/src/` y `build/pkg/*/*.pkg.tar.zst` (`.gitignore:24-29`). El
`.ko` de 387 KB **si** lo veria git. Queda sin commitear (regla de la sesion); el sha manda y el
binario se reconstruye con `compilar-panel-o82.sh`.

### T2.3 Instalacion en la tablet (para el orquestador)

```bash
# 0) COMPROBAR ANTES: uname -r debe ser exactamente 7.2.0-rc2-palawan y el kernel
#    con SMP+preempt+mod_unload (si no: "invalid module format"). Sin MODVERSIONS
#    (# CONFIG_MODVERSIONS is not set) NO hay CRC de simbolos que casar.
K=$(uname -r); ls /lib/modules/$K
scp build/pkg/panel-o82/panel_xiaomi_o82_dualdsi.ko root@TABLET:/tmp/
ssh root@TABLET 'K=$(uname -r); install -D -m 0644 /tmp/panel_xiaomi_o82_dualdsi.ko \
   /lib/modules/$K/extra/panel_xiaomi_o82_dualdsi.ko && depmod -a && echo depmod-ok'
# 1) insmod MANUAL primero (un solo cambio, reversible):
ssh root@TABLET 'insmod /lib/modules/$(uname -r)/extra/panel_xiaomi_o82_dualdsi.ko; \
   dmesg | tail -30; ls -l /sys/class/backlight/; \
   ls /sys/bus/mipi-dsi/drivers/ | grep -i xiaomi'
#    esperado: driver "panel-xiaomi-o82-dualdsi" en /sys/bus/mipi-dsi/drivers,
#    backlight "ae94000.dsi.0", y en dmesg el probe del panel. rmmod para revertir.
# 2) Auto-carga: tras depmod, /lib/modules/$K/modules.alias debe contener
#       alias of:N*T*Cxiaomi,uke-o82-4202-0b panel_xiaomi_o82_dualdsi
#    grep -i "xiaomi,uke-o82" /lib/modules/$(uname -r)/modules.alias
#    Con eso, el panel se autocarga al crear el host DSI el device panel@0.
#    (Alternativa permanente: /etc/modules-load.d/panel-o82.conf con el nombre del modulo.)
```

**Match EXACTO del compatible: SI** (DATO). DT vivo (`merged-s238.dts`, `panel@0` dentro de
`dsi@ae94000`): `compatible = "xiaomi,uke-o82-4202-0b";` — y el `.ko` declara
`alias=of:N*T*Cxiaomi,uke-o82-4202-0b`. Coinciden caracter a caracter, asi que **no hay fix de
compatible que proponer**. Los supplies del nodo (`vddil8b-supply`, `vsp-supply`, `vsn-supply`) y
`reset-gpios` tambien coinciden con lo que pide el driver.

---

## T3 — Auditoria de config y cadena

### T3.1 Estado exacto (DATO) — `configs-uke/config-bueno-actual.config` y `build/kernel-pokes/.config`

| simbolo | config-bueno-actual | kernel-pokes (kernel nuestro) | s122 (hermano) | veredicto |
|---|---|---|---|---|
| CONFIG_DRM | =y | =y | =y | OK |
| CONFIG_DRM_MSM | =y | =y | =y | OK (**builtin**, no modulo) |
| CONFIG_DRM_MSM_KMS | =y | =y | =y | OK |
| CONFIG_DRM_MSM_MDSS | =y | =y | =y | OK |
| CONFIG_DRM_MSM_DPU | =y | =y | =y | OK |
| CONFIG_DRM_MSM_DP | =y | =y | =y | OK |
| CONFIG_DRM_MSM_DSI | =y | =y | =y | OK (**builtin**) |
| CONFIG_DRM_MSM_DSI_7NM_PHY | =y | =y | =y | OK — **gatea** sm8650-dsi-phy-4nm |
| CONFIG_DRM_MIPI_DSI | =y | =y | =y | OK |
| CONFIG_DRM_DISPLAY_DSC_HELPER | =y | =y | =y | OK (DSC de la cadena) |
| CONFIG_DRM_PANEL | =y | =y | =y | OK |
| **CONFIG_DRM_PANEL_XIAOMI_O82_DUALDSI** | **no aparece** | **is not set** | **=y** | **HUECO REAL** |
| CONFIG_BACKLIGHT_CLASS_DEVICE | =y | =y | =y | OK |
| CONFIG_BACKLIGHT_KTZ8866 | not set | not set | not set | no bloquea a ESTE driver |
| CONFIG_DRM_FBDEV_EMULATION / DRM_MSM_KMS_FBDEV | =y / =y | =y | =y | OK (fbcon sobre card0) |
| CONFIG_PHY_QCOM_QMP / _COMBO | =y / =y | =y | =y | OK (ruta DP/USB, no DSI) |
| CONFIG_CLK_PALAWAN_GCC / _CAMCC / _GPUCC | =y | =y | =y | OK |
| CONFIG_SM_DISPCC_8550 | =y | =y | =y | OK — **es** el driver de `qcom,palawan-dispcc` |
| CONFIG_INTERCONNECT_QCOM_PALAWAN | =y | =y | =y | OK |
| CONFIG_QCOM_GDSC / RPMHPD / RPMPD | =y | =y | =y | OK |
| CONFIG_PWM / BACKLIGHT_PWM | =y / =m | =y | =y | irrelevante (brillo por DCS) |
| CONFIG_MODVERSIONS | not set | not set | not set | sin CRC de simbolos |
| CONFIG_LOCALVERSION | "-palawan" | "-palawan" | "-palawan" | vermagic identico |

**Unico hueco de config que rompe la cadena**: el driver del panel. El `.ko` de T2 lo cubre
(`insmod` sin recompilar kernel). Alternativa permanente: poner el simbolo `=y` (o `=m`) en
`config-bueno-actual.config` y recompilar — decision del orquestador.

`CONFIG_BACKLIGHT_KTZ8866` no esta en ninguno de los tres: si alguien añade un nodo
`compatible = "kinetic,ktz8866"` (como propone el plan w4-panel) **no probea**. No hace falta para
nada: el driver del panel controla el brillo por DCS 0x51.

### T3.2 Component model: ¿reintenta el bind del master al cargar el panel tarde? (DATO de codigo)

* El DSI host msm es **builtin** (`CONFIG_DRM_MSM=y`, `CONFIG_DRM_MSM_DSI=y`) -> su driver ya esta
  registrado y el host `ae94000.dsi` probea en el arranque; es el quién instancia el device hijo
  `panel@0`.
* El panel NO es componente del master: solo hace `drm_panel_add()` + `devm_mipi_dsi_attach()`.
  El `component_add()` del **DSI** ocurre en el *attach* del panel:
  `dsi_host.c:1708` `dsi_host_attach()` -> `:1744` `dsi_dev_attach(msm_host->pdev)` ->
  `dsi.c:159-162` `component_add(&pdev->dev, &dsi_ops)`.
* El core de componentes reintenta **cualquier agregado no ligado** cada vez que entra un
  componente nuevo: `component.c:748` `try_to_bring_up_masters(component)` ->
  `component.c:262-276` `list_for_each_entry(adev, &aggregate_devices, node) if (!adev->bound)
  try_to_bring_up_aggregate_device(adev, component)`.
* El master msm se registra en `msm_drv.c:1089` `component_master_add_with_match(master_dev,
  &msm_drm_ops, match)`; su lista de match incluye las interfaces de display
  (`msm_drv.c:948` `drm_of_component_match_add(..., intf)`) y, si `separate_gpu_kms=0`, la GPU
  (`:1027`/`:1076`).

**Conclusion (DATO de codigo, NO VERIFICADO en la tablet)**: cargar `panel_xiaomi_o82_dualdsi.ko`
en caliente **si** dispara un reintento del bind del master (por el `component_add` del attach),
asi que no hace falta reiniciar para que `msm_drm` vuelva a intentarlo. Pero **`card0` no
aparecera mientras falle el IOMMU del DPU**: `msm_kms.c:192-200` (`no IOMMU, bailing out`,
`-ENODEV`) aborta el `msm_drm_bind` -> es el hueco 1 (apps-smmu). Lo que si ocurre con el insmod
es el probe del panel, su backlight y el attach de los dos links.

---

## Riesgos, ordenados por impacto

1. **R1 (falso hueco abierto / ciclo de flash tirado)**: dar por abierto el hueco del PHY y gastar
   un ciclo de `dtbo_b` + flash en un no-op. Evidencia: delta 0 (T1.4). Gate propuesto: si s254 se
   construye, el criterio es "delta 0", no "el PHY liga".
2. **R2 (la via ingenua que NO funciona)**: renombrar solo el `compatible` del nodo vendor.
   Muere en `dsi_phy.c:653` (`dsi_pll` vs `pll_base`) antes que cualquier otra cosa; y aunque se
   arreglara, **el host mainline no apunta a ese nodo** (`phys = <&mdss_dsi0_phy_ml>`) => el
   mensaje `phy driver is not ready` seguiria igual y pareceria que el fragmento no sirve.
3. **R3 (mi pieza mas fragil: los timings del modo)**: el modo 3200x2136 esta construido con los
   porches del vendor **dobla2dos** (`o82_modes`, `:485-522`, hfp 113->226, hsync/hbp 16->32)
   porque el autor INFIERE que el msm divide el modo por link. NO VERIFICADO en hardware. Si la
   inferencia es falsa, habra bind completo y **imagen corrupta/desplazada** (no negro), y el
   sintoma apuntaria erroneamente a DSC. Segundo candidato dentro de esta pieza: la variante
   `42_02_0b` vs `36_02_0a` (secuencias on distintas, 108 vs 171 paquetes) y los registros de
   frecuencia (solo se programan los de 120 Hz; `num_modes = 1` a proposito).
4. **R4 (presupuesto)**: `dtbo_b` tiene 2770 B de margen; el fragmento PHY gasta 736 B y el A' del
   SMMU gastara mas. Si se empaquetan juntos, riesgo de no caber -> toca descartar el PHY (que es
   lo correcto por R1).
5. **R5 (vermagic/autoload en la tablet)**: el `.ko` solo vale para un kernel
   `7.2.0-rc2-palawan` SMP+preempt; si el orquestador recompila el kernel y cambia
   `LOCALVERSION`/`PREEMPT`, el `.ko` hay que regenerarlo (barato: `compilar-panel-o82.sh`), o
   poner el simbolo `=y` en el config del kernel.
6. **R6 (lo de siempre, fuera de mi alcance)**: sin apps-smmu no hay `card0`; con `card0` aparece
   el cuelgue conocido del CM3 al abrir la GPU (R-57 de PLAN-PANTALLA). El panel no cambia eso.

## Anexo — reproduccion

```bash
# T1: fusion del DT vivo y validacion del fragmento
python3 /tmp/opencode/sg-phy/valida-fragmento.py     # -> "lineas +0 / -0"
# T2: compilar el modulo (idempotente, detached, log en /tmp/opencode/sg-panel-build.log)
build/gates/compilar-panel-o82.sh
sha256sum build/pkg/panel-o82/panel_xiaomi_o82_dualdsi.ko
# T3: estado de config
grep -nE 'DRM_MSM|DSC|XIAOMI_O82|BACKLIGHT_K' build/kernel-pokes/.config
```
Artefactos de esta sesion (ninguno commiteado): `build/gates/FRAGMENTO-PHY.dts`,
`build/gates/INFORME-PHY-PANEL.md`, `build/gates/compilar-panel-o82.sh`,
`build/gates/patches/panel-o72-buildfix.diff`, `build/pkg/panel-o82/{panel_xiaomi_o82_dualdsi.ko,sha256.txt}`.
