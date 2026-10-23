# PERIF-TÁCTIL+LÁPIZ — frente listo para port (17-oct-2026)

Fuentes: DT Android completo (`/tmp/dtfull/base/`, = `build/android/dt-full-uke-android.tar`),
dmesg vendor (`/tmp/cosecha/01-dmesg.txt`), bins `build/android/novatek_nt36532_o82_{fw,mp}_csot.bin`,
árbol `build/kernel-pokes/k52-L16-tree`, port previo `build/gates/revision/PIPELINE-PANEL-20261014/ports/`
(docs/historia/revision/PIPELINE-PANEL-20261014/ports/TOUCH-PORT.md + 0001-touch-nt36532.patch) y `build/gates/prepara/novatek/`.

## 1. DT Android: nodo novatek@0 COMPLETO

Ruta: `/soc/qcom,qupv3_0_geni_se@ac0000/spi@a90000/novatek@0` (compatible `novatek,NVT-ts-spi`,
name `novatek`, status `ok`).

| Propiedad | Valor decodificado |
|---|---|
| `reg` | `<0>` (chip-select 0 → dmesg `spi1.0`) |
| `spi-max-frequency` | `0x0124F800` = **19.200.000 Hz (19,2 MHz)** |
| `interrupts` | **NO TIENE** — usa `novatek,irq-gpio` + gpio_to_irq |
| `novatek,irq-gpio` | `<&tlmm 54 0x2001>` (TLMM pinctrl@f000000, **GPIO 54**; flag 0x2001) |
| `novatek,lcd_id-gpio` | `<&tlmm 26 0>` (**GPIO 26**) — dmesg: `lcd_id_value=1` → **panel CSOT** |
| `novatek,pen-support` | bool (lápi­z M80p/P81c) |
| `novatek,stylus-resol-double` | bool (resolución lápiz x10: fw reporta abs 32000×21360) |
| `novatek,mp-support-dt` | bool (selftest MP con criterios del DT) |
| `novatek,touch-game-param-config1/2/3` | `[2,2,1,2,1]` / `[2,2,2,2,1]` / `[2,2,3,2,1]` (game-mode) |
| `mi_tp,*` (10 arrays) | framework Xiaomi: todos `[n,0...]` (active/game/panel-orien/report-rate=0; aim-sensitivity/edge-filter/tap-stability/tolerance=[4|3,0,2,2,2]; up-threshold=[4,0,3,3,3]; expert-mode=[3,1,1,1,1]) |
| `panel` | `<phandle 0x6b4 0x6b5>` → `qcom,mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid` y `qcom,mdss_dsi_o82_36_02_0a_dualdsi_dsc_vid` (mapeo panel↔touch; el lcd_id-gpio elige) |
| `pinctrl-0/1` + names | `mi_ts_spi_cs_active` / `mi_ts_spi_cs_suspend` ("pmx_ts_active"/"pmx_ts_suspend"): CS=**gpio19**, activo `qup0_se4_l3` ds6; suspend gpio output-low pull-down ds2 |
| supplies / firmware-name / reset-gpio | **NINGUNA** (TDDI: rieles con el panel) |

Hijas: **`novatek-mp-criteria-5993@0` y `novatek-mp-criteria-5994@0`** (compatible
`novatek-mp-criteria-59xx`): criterios MP del selftest — `AIN_X/Y/KEY` (ids 0-59/0-39),
`IC_X_CFG_SIZE=0x3c` (**60 TX**), `IC_Y_CFG_SIZE=0x28` (**40 RX**), `PS_Config_Diff_Test_Frame=0x32`,
decimales de límites, etc. Se emparejan con el PID del fw (dmesg: PID 0x5993 tras update).
NO hay `firmware-name` ni nodo de panel mapping adicional. Hermano `goodix-berlin@0`: stub
INERTE (solo `name` + `panel=<4 phandles>`, sin compatible/reg/status → no bindea).

## 2. Controlador SPI a90000 = QUP0 SE4

- `compatible="qcom,spi-geni"`, `reg=0xa90000 +0x4000` (`se_phys`), `status=ok`, `qcom,rt` (flag Xiaomi).
- `interrupts = <GIC_SPI 357 IRQ_TYPE_LEVEL_HIGH>`.
- `clocks = <gcc 0x49>` "se-clk" → gcc clock-controller@100000 índice **73** = `GCC_QUPV3_WRAP0_S4_CLK`
  (idéntico a `qcom,palawan-gcc.h:84`). Wrapper `qupv3_0_geni_se@ac0000` (`qcom,geni-se-qup`,
  m/s-ahb = gcc 102/103, iommus apps_smmu, dma-coherent, `qcom,iommu-dma=fastmap`).
- Pinctrl del bus: `qupv3_se4_spi_pins` — MISO **gpio16**, MOSI **gpio17**, CLK **gpio18**
  (`qup0_se4_l2/l3`), CS **gpio19**. dmas: gpi_dma0 idx4 tx/rx.
- Total: **SE4 de QUP0** — exactamente `spi4` de `palawan.dtsi:1978` (que está `status="disabled"`).

## 3. dmesg vendor: sonda + runtime NVT-ts (driver `nvt_version_2024.01.13-001`)

- **t=3,69 s** `nvt_driver_init` → `nvt_ts_probe`: `spi controller thread PID 874 prio 99`.
  `nvt_parse_dt`: `irq-gpio=387` (numeración global vendor = TLMM+333; el pin HW es **54**),
  `pen-support=1`, `stylus-resol-double=1`, `lcd_id-gpio=359` (pin 26), `lcd_id_value=1 → CSOT`,
  sin `spi-rd-fast-addr`, game configs 1-3. `nvt_pinctrl_init`.
- **Identificación IC**: `nvt_ts_check_chip_ver_trim` (`chip_ver_trim_addr=0x1fb104`,
  `swrst_sif_addr=0x1fb43e`, `crc_err_flag_addr=0x1fb535`): "This is NVT touch IC" + **"Cascade Chip"**
  (ILM/DLM separadas). abs 2136×3200, rx40/tx60, super_resolution_factor=10.
- Inputs: `NVTCapacitiveTouchScreen` (input11) + `NVTCapacitivePenM80p` (input12) +
  `NVTCapacitivePenP81c` (input13). `int_trigger_type=1`; `request irq 359 succeed` (IRQ Linux del
  gpio 54; en el driver vendor: ONESHOT+RISING, consistente con flag 0x2001).
- proc: `/proc/NVTSPI`, `nvt_fw_version/baseline/raw/diff`, `nvt_pen_diff/pen_switch`,
  `xm_htc_*` (stylus_enable, gesture, game_mode, charger, scan_freq...), `/proc/nvt_selftest` (MP).
- **fw leída de la flash del IC al sondear**: `fw_ver:0x0E fw_type:0x01 nvt_pid:0x5981`.
- **t=3,71 s** `xiaomi_register_panel_notifier_work` → el touch se suscribe al notifier del panel.
- **t=8,83 s** `nvt_pen_charge_state_notifier_callback` (hall del lápiz XM_PROP_PEN_HALL3/4).
- **t=9,72 s** handoff TDDI: `xiaomi_drm_panel_notifier_callback: Notification type:2 …
  **TDDI_FB_BLANK_UNBLAN[K]**` → `xiaomi_touch_resume_work` (panel on → touch resume).
- **t=10,3 s** `FW info is broken!` (×4, IC sin FW válida en RAM antes del update).
- **t=17,89 s — carga de FW**: `update_firmware_request: filename is novatek_nt36532_o82_fw_csot.bin`
  → `request_firmware` con nombre corto (no ruta): falla `/vendor/firmware_mnt/image/`,
  `.../kiwi/`, `/vendor/firmware/`, `/vendor/firmware/wlan/qca_cld/kiwi_v2/` (**-13 EACCES**) y
  `/lib/firmware` (-2) → **sysfs fallback**: `ueventd` la sirve desde **`/odm/firmware/`**.
- **t=17,95 s**: `fw_need_write_size=245760 (0x3c000)` + "NVT end flag";
  `nvt_bin_header_parser`: `cascade_2nd_header_info=1`, `ilm_dlm_num=2, ovly_sec_num=0,
  info_sec_num=14, partition=16`; `nvt_bootloader_reset`; `nvt_tx_auto_copy_mode 2 enable`;
  **t=18,08 s `Update firmware success! <128 ms>`**; `nvt_get_xm_htc_poll_info` frame_len 5176
  (host touch polling Xiaomi); **fw nueva: `fw_ver=0x11, PID=0x5993`, abs 32000×21360**.
- **Lápiz**: `update_pen_status` (bt/charge/gamemode) + `nvt_set_extend_custom_cmd sub_cmd 0x04
  val 0` (stylus enable, falla 3 intentos antes del update, OK después).
- **Modos MI_TP (framework xiaomi_touch, HAL touchfeature)** — todas via `cmd: 0`:
  `mode:1071 val:1` → `nvt_set_cur_value` 1071 → **custom cmd 0x19 val 1**; `mode:1000 val:1` →
  **cmd 0x01 val 2**; `mode:33` → pen (update_pen_status). Son features de userspace (screen
  awake/refresh-rate/pen) mapeadas por el driver a extended custom cmds al IC; **no son parte del
  DT ni del bus** — irrelevante para mainline (el panel-handoff sí importa, punto 6).

## 4. Bins extraídos (como datos)

Ambos **245.760 B (0x3C000)** = exactamente `fw_need_write_size`; los **últimos 3 bytes = "NVT"**
(end flag estándar). Cabecera NVT estándar de 128 B: primera palabra `0x0002` (formato bin v2),
**16 particiones de 8 B (u32 size + u32 dst)**: ILM `0x000174d7` → SRAM **0x22000**, DLM
`0x0001409f` → **0x100000**, 0 overlays, 14 secciones info (coincide 1:1 con `partition=16` del
parser y con el chip "Cascade"). **Sin ninguna cadena ASCII "NT36532"** (imagen packed; la
identidad es solo por nombre de fichero + PID del fw). fw vs mp: cabeceras idénticas salvo el
primer size (`0x174d7` vs `0x17983`) y los CRC.
**fw = imagen runtime que el driver flashea** (dmesg pide `..._fw_csot.bin`);
**mp = límites/calibración del selftest** (`/proc/nvt_selftest` + nodos mp-criteria del DT,
cargada on-demand por el flow MP, no en probe). Para el port solo hace falta el fw bin, y solo
en la fase de updater.

## 5. Nuestro port (estado real del árbol k52-L16-tree)

- **Driver: SPI** (no I2C). `drivers/input/touchscreen/novatek-nt36xxx-spi.c` ya en el árbol y ya
  es la variante ext integrada: `compatible = "novatek,NVT-ts-spi"` (+ alias `"novatek,nt36xxx-spi"`),
  `reset_gpio` OPCIONAL, handshake de rescate si EVENT_BUF no responde (reset + msleep 240 "boot
  de FW TDDI"), **cero `request_firmware`** (trabaja con la FW de flash del IC — no flashea).
  El `novatek-nvt-ts.c` es el I2C de mainline: **no aplica** (`CONFIG_TOUCHSCREEN_NOVATEK_NVT_TS`
  no está en k52L74-build/.config:3166; **`NT36XXX_SPI=y`** en k52L74:3167, l39:3162, k52L64:3167).
- **DT**: `xiaomi-uke.dts` **NO tiene aún** el nodo touch (`spi@a90000` ausente). El parche
  **`PIPELINE-PANEL-20261014/ports/0001-touch-nt36532.patch`** (67 líneas, 3 hunks, dry-run RC=0,
  compila con dtc, **sin aplicar al árbol**): H1 `pinctrl-cliffs.c` `FUNCTION(gpio)` →
  `MSM_GPIO_PIN_FUNCTION(gpio)` (porte literal de senemos 0017); H2 retira el TODO desfasado del
  comentario; H3 añade `&spi4 { status okay; touchscreen@0 { compatible novatek,NVT-ts-spi; reg<0>;
  spi-max-frequency 19200000; interrupts-extended <&tlmm 54 IRQ_TYPE_EDGE_RISING>;
  touchscreen-size 2136×3200; } }`. `flash-l75-gated.sh` ya existe para aplicarlo con gates.
- **Cuadre de constantes (todo cuadra 1:1)**: bus a90000 = `spi4` de palawan.dtsi (QUP0 SE4);
  `GCC_QUPV3_WRAP0_S4_CLK`=73 = índice vendor 0x49; IRQ controlador GIC_SPI 357 igual; pines
  `qup_spi4_data_clk/cs` = gpio16/17/18/19 = vendor; freq 19,2 MHz = vendor; INT tlmm **54**
  (el "387" del prompt es numeración global vendor, pin HW 54); lcd_id no portable (el driver
  in-tree no lo lee; nuestro unidad = CSOT, bins ya extraídos con ese nombre); sin reset ni
  supplies en ambos lados. I2C: descartado.
- Fw path fase 2 (si se porta el updater vendor): `/lib/firmware/novatek_nt36532_o82_fw_csot.bin`
  (el nombre que `request_firmware` pide). El mp bin no hace falta para operar.

## 6. PLAN DE PORT (concreto)

1. **Ficheros a tocar** (una sola pieza): aplicar
   `build/gates/revision/PIPELINE-PANEL-20261014/ports/0001-touch-nt36532.patch` con `patch -p1`
   sobre k52-L16-tree → toca `drivers/pinctrl/qcom/pinctrl-cliffs.c` (1 línea) y
   `arch/arm64/boot/dts/qcom/xiaomi-uke.dts` (comentario + bloque `&spi4`). Nada más en kernel:
   driver y config ya correctos. Rootfs: **nada** en fase 1 (sin fw, sin udev extra; los de
   `prepara/novatek/userspace/` siguen inertes/ok).
2. **Marcadores de verificación** (post-flash L75): `dmesg | grep -i nt36` →
   `NT36xxx SPI probe ok: irq … 2136x3200`; `cat /proc/bus/input/devices` → `Novatek NT36xxx`;
   `evtest`: 1 dedo esquinas + `point_layout 0/1/2` (kernel param del driver) para el unknown
   del layout; `dmesg | grep -c 'deferred_probe'` + timestamps para H1.
3. **Si no hay eventos** (IRQ muda): re-flash cambiando `IRQ_TYPE_EDGE_RISING` → `EDGE_FALLING`
   en xiaomi-uke.dts (1 línea; vendor flag 0x2001 es ONESHOT+RISING según el .ko, pero quedó
   alternativa documentada).
4. **Riesgos**:
   - **H1/TDDI (el gordo)**: táctil y display comparten DDIC. En nuestro port, el probe del
     táctil es quien limpia el deferral del host DSI secundario (t≈47 s, PANEL-REVISION-B4 §6.3
     y :287): no rompe el bonding, solo la latencia de card1/modeset/DCS/vci. El hunk H1
     (pinctrl-cliffs) puede mover el orden de probes → **registrar en cada boot de verificación
     el timestamp del táctil vs el del panel**; si la latencia display empeora, el fix es
     acortar el deferral (no tocar la PHY).
   - Probe sin panel alimentado puede no responder (en vendor el IC ya venía de flash y el fw
     update ocurre a 17,9 s con panel ON); el driver in-tree tiene el rescate reset+240 ms, y
     NO flashea fw → **nunca portar el updater en fase 1** (flashear el IC en pruebas = riesgo
     de muda TDDI).
   - `palawan.dtsi` declara TLMM en `f100000`/`qcom,palawan-tlmm` pero el HW es `f000000`+
     `qcom,cliffs-pinctrl` (TOUCH-PORT §5.4): con DT nativo el gpiochip no bindea y gpio54 no
     existe. En la ruta actual (DTBO derivado del vendor) el nodo vivo lo aporta el DTBO → el
     fix equivalente es el overlay `fase4-touch.dts` del staging hermano (`~/gpu-work/ramaa/s21/
     dtbo-gpu/`, anade `interrupts` al `novatek@0` existente; sin probar en HW).
   - Rollback: `patch -R`; el driver queda compiled-in pero sin nodo no hace nada; slot bueno intacto.

## 7. Conclusión

Frente táctil+lápiz **LISTO PARA PORT**: datos exactos cuadrados (SPI QUP0 SE4 a90000/19,2 MHz,
INT TLMM 54, pines 16-19, GCC S4 idx73, fw csot 245760 B, PID 0x5993, 2136×3200, 60TX/40RX,
pen-support+stylus-double), driver in-tree correcto ya configurado, y un único parche pendiente
(0001-touch) con dry-run verde. Único trabajo DT restante: decidir ruta DTBO-overlay vs DT nativo
y vigilar H1 en la verificación.
