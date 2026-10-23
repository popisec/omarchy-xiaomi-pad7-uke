# PLAN-KERNEL-PANTALLA — L76 "paridad vendor" (17-oct-2026)

> Analista, solo lectura. Sin adb/fastboot/ssh, sin flasheos, sin commits, sin compilar.
> Fuentes: `docs/historia/ESTADO-VIVO.md`, `NOTAS-OMARCHY.md`, ledger hermano `FLASH-LEDGER.md` (#646–#653,
> líneas 13659–13871), `PANEL-REVISION-{A1,B2,B3}-*`, `PANEL-REVISION-{DPU-VENDOR,DCS-COTEJO,
> PARIDAD-CLK-ICC,INV75-PHY}-20261017.md`, `docs/historia/revision/CRITICA-L75-20261017.md`, `KTZ-DUAL-S289-20261017.md`,
> `build/android/vendor-harvest-20261017b/` (README, panel-on-timeline, dsi*-ctrl-reg, dpu/),
> árbol `build/kernel-pokes/k52-L16-tree`, `build/gates/{build-fast.sh,repack-k52L75.py,flash-l7*-gated.sh}`.
> Abreviaturas: HOST = `drivers/gpu/drm/msm/dsi/dsi_host.c`, PVID = `.../dpu1/dpu_encoder_phys_vid.c`,
> HINTF = `.../dpu1/dpu_hw_intf.c`, PANEL = `drivers/gpu/drm/panel/panel-xiaomi-o82-dualdsi.c`,
> KTZ = `drivers/video/backlight/ktz8866.c` (todas bajo `k52-L16-tree`).

---

## 0. Hallazgo nuevo de este informe (además del widebus)

Cruzando el volcado vendor del controlador DSI (`dsi0-ctrl-reg.txt`, offset físico = offset
mainline + 4 en DSI 6G; versión HW `0x20080000` = v2.8) contra lo que programa mainline:

| Registro (mainline) | Vendor medido | Nuestro (L70 / L73-L74) | Nota |
|---|---|---|---|
| `REG_DSI_CTRL` 0x00 | `0x000001f3` | igual (pero VID_MODE_EN desde pre_enable) | CLK_EN+4 lanes+VID+ENABLE |
| **`REG_DSI_VID_CFG0` 0x0c** | **`0x02009140`** = DST_FORMAT **4 (RGB101010)** + DATABUS_WIDEN + non-burst-sync + BLLP/EOF stop | L70: `0x02009130` (RGB888=3); L71-L74: `0x00009130` | **el panel declara `MIPI_DSI_FMT_RGB888` (PANEL:814)**; mainline solo pone RGB101010 si el panel lo pide (HOST:801-811, 877) |
| `REG_DSI_ACTIVE_H/TOTAL` | `0x01cb0020` / `0x0905023b` | L70 igual; L71-L74 `0x02360020`/`0x090502a6` | widebus ON |
| `REG_DSI_VIDEO_COMPRESSION_MODE_CTRL` 0x29c | `0x03200b51` | probablemente igual (WC 800, DT 0x0b, pkt/line 1, eol 1) — **no medido** | readback en L76 |
| `REG_DSI_HS_TIMER_CTRL` / MISR | `0x0004bb80` / `0x00010100` | = desde L74 | L74 ya en paridad |
| `REG_DSI_TRIG_CTRL` 0x80 | `0x80000004` | `0x80001004` (BLOCK_DMA_WITHIN_FRAME) | inocuo si los DCS van con vídeo OFF |
| `REG_DSI_CMD_DMA_CTRL` 0x38 | `0xd4000000`/`0x94000000` (broadcast en/master) | `0x14000000` | broadcast lo emula dsi_manager (`need_sync`) |
| `REG_DSI_EOT_PACKET_CTRL` | `0x11` (RX_EOT_IGNORE) | `0x01` | menor |
| `REG_DSI_ERR_INT_MASK0` | `0x13e0391f` | `0x13ff3fe0` | el vendor desenmascara más errores (y frena) |

INTF_1 vendor (DPU-VENDOR §2): HSYNC_CTL `0x023c0010` (572/16), VSYNC_PERIOD `0x142968`
(572×2310), DISPLAY_HCTL `0x01ca0020` (427 px), INTF_CONFIG2 `0x1011`, DATA_HCTL `0x012a0020`
(267 = ceil(1600/6)). Mainline con widebus ON genera **exactamente** CONFIG2 `0x1011` y DATA_HCTL 267
(HINTF:166-170, 196-200, 266-267), **pero el ancho del INTF lo trunca a 426** (vanilla
`width*8/(bpc*3)`, B3 §1: periodo 571 ≠ DSI 572). Con ceil sale 427/572 = vendor bit a bit.

**Conclusión**: el "mundo 30" coherente del vendor = widebus ON **+ formato RGB101010 en el DSI**
(DST_FORMAT 4: el DSI consume 30 bit/pclk, que es justo lo que asume el cálculo
`bits_per_pclk = bpc*3` de HOST:1108-1110) **+ ceil 427 en el INTF**. L70 tenía las piezas del DSI de
timing pero con DST_FORMAT RGB888 (24 bit/pclk) e INTF 426: dos desajustes de alimentación, uno de
ellos de 6 bit/pclk. El comentario upstream HOST:1899-1906 ("Downstream overrides RGB101010 back to
RGB888 when DSC is enabled but widebus is not") confirma que **downstream usa RGB101010 con
DSC+widebus**: es la configuración vendor.

---

## 1. Historia L68→L75 con evidencia

### 1.1 Qué tenía exactamente L70 (`f2e820d2…`, ledger #649) y por qué se abandonó

L70 = k52L68 + hunk `L70-byteclk` (HOST:684-688, `bpp = bpc*3` en `dsi_byte_clk_get_rate`) con el /24
de L69 revertido (ledger:13705-13713). Por tanto:

- **Widebus ON** (lógica upstream `dsc && DSI ≥ 2.5`, k52L39-tree HOST:797-804): DSI `ACTIVE_H=0x01cb0020`
  (427), `TOTAL=0x0905023b` (572×2310) — **medido** por el readback `UKE-L68` (ledger:13717-13718). = vendor.
- Byte clock **148,648 MHz medido** (= vendor 148.648.750).
- INTF: vanilla `/(bpc*3)` **truncado → 426, periodo 571** (B3 §1, tabla :83-88) ≠ DSI 572 ≠ vendor 427/572.
- Formato DSI `RGB888` → VID_CFG0 DST_FORMAT 3 (vendor 4).
- PPS mainline (flb 12, max_qp0 4: 5 bytes distintos del OEM; B1), **enviada 2 veces**: en `o82_prepare`
  antes de 0x11 (PANEL:413-463) y en `o82_enable` post-0x29 (L63).
- VID_MODE_EN activo desde `dsi_mgr_bridge_pre_enable` (HOST:2630, `prepare_prev_first` PANEL:959) durante
  reset+108 DCS; **más el toggle L68** (VID OFF → 10 lecturas BTA → VID ON en `o82_enable`) y las 12 lecturas L65.
- PHY timings calculados por mainline (sin L75), sin HS_TIMER/MISR/FLUSH (sin L74), sin freno anti-flood,
  reset final 100 ms.

Resultado: flood continuo `FIFO_STATUS=dddd1011` (VIDEO_MDP over+underflow + HS FIFOs) que llenó el root al
100 %, tumbó la carga y recorrompió `adsp.b40` (ledger:13716-13723). Pantalla sin contenido (no hay
veredicto visual específico de L70 en el ledger; el estado común L57-L74 es "negro con luz", A1 §1).

**Por qué se abandonó (dos razones, ambas hoy refutadas):**
1. Se atribuyó el flood al "mundo 30". En L71 se demostró que la causa era el **toggle L68** (L67 sin
   toggle = limpio; L68-L71 con toggle = flood en cualquier mundo; ledger:13745-13749, A1 §3).
2. Se creyó que el vendor era "mundo 24" (`ACTIVE_H 534`, `TOTAL 0x090502a6`): era una **derivación** de
   `RE-ANDROID-GAPS-20261015.md:78-84`, nunca una medida (DPU-VENDOR §3). El vendor medido es 427/572.

### 1.2 Resultado de cada boot

| Boot (ledger) | Cambio | Log/medida | Visual |
|---|---|---|---|
| L67 (#646, flasheado mañana 15-oct) | BTA readback (L65) | 20 reads `ret=0` ambos links; byte 118,919 M (×24); INTF 571/DSI 572; **0 underruns, sin flood** | negro con luz |
| L68 (#647) | toggle VID OFF/ON + readback ACTIVE_H | reads `ret=0` en ambos contextos; `ACTIVE_H=0x01cb0020`; 19 underruns; nace el flood | negro con luz (sin fila de resultado propia: A1 §1 / B3 §3) |
| L69 (#648) | INTF /24 solo DPU | flood S4-DIAG (evicción de marcadores), **underrun 1929/1929** | negro |
| L70 (#649) | all-30: revert /24 + byte ×30 | ver §1.1; flood `dddd1011`, root 100 % | sin contenido |
| L71 (#650) | "mundo 24": INTF /24 + widebus OFF + byte ×30 | `0x02360020`/`0x090502a6`/148,648 M; underruns 1/1; flood 143k líneas/20 s | negro con luz |
| L72 | L71 sin toggle + ratelimit | **nunca flasheado** (plegado en L73) | — |
| L73 (#651) | PPS OEM (flb 13/max_qp0 8) + freno + ceil /24 (534) | `UKE-L73: PPS[19]=B2 [23]=9F [27]=0D [29]=86 [58]=02`; burst FIFO al commit 17 ev/250 ms frenado (12-26 líneas); escritorio arriba | **veredicto no anotado** en el ledger; L74 se construyó porque seguía negro |
| L74 (#652) | HS_TIMER 0x4bb80 + MISR 0x10100 + FLUSH | eco OK; 0 timeouts video-done en boot; con modetest forzado `MISR=ffffffff TO=0` (vídeo fluye) | **dueño: NEGRO con patrón de modetest** (ledger:13833-13838) |
| L75 | tabla PHY vendor (14 TIMING_CTRL) | parche **aplicado en el árbol** (PHY:987-1041) y bug B1 del repack ya corregido (repack-k52L75.py:716); **sin compilar** (no existe `k52L75-build` ni `boot-uke-k52L75.img`), `flash-l75-gated.sh` con `EB=SHA_PENDIENTE` | — |

Ningún boot ha mostrado contenido; la luz funciona desde L56/L57. Tras L74 la tablet pasó a Android
(#653, slot b): **el rootfs Arch de `userdata` se perdió**; `boot_a` = L74 + `dtbo_a` = s288 intactos.

### 1.3 ¿Se probó alguna vez widebus ON + PPS OEM + PPS única post-0x29 + vídeo tras PPS?

**No. Ninguna de las cuatro piezas a la vez, y dos de ellas nunca.**
- Widebus ON solo en ≤L68 y L70: siempre con PPS mainline (flb 12), PPS ×2, VID desde pre_enable, RGB888 e INTF 426.
- PPS OEM solo en L73/L74: siempre con widebus OFF (mundo 24 derivado) y PPS ×2.
- PPS única: nunca (desde L63 siempre van dos).
- Vídeo encendido después de la PPS: nunca (L68 apagaba/encendía tras la PPS #2 con el motor ya activo
  durante los DCS; no es el orden vendor).
- DST_FORMAT RGB101010 e INTF 427: nunca.

---

## 2. Árbol vigente, build y reempaquetado

- **Fuente**: `build/kernel-pokes/k52-L16-tree` (fuera de git, ver `POR-QUE-FUERA-DE-GIT.md`). Contiene
  L73 + L74 + **L75 aplicado**. Último build: `build/kernel-pokes/k52L74-build` (log `build/logs/build-k52L74.log`,
  `DONE k52L74-BUILD-OK` 14:32:53 del 16-oct).
- **Parches**: diffs en `build/gates/patches/` solo desde L73 (`l73-panel-composite.diff`,
  `l74-hstimer-misr-flush.diff`, `l75-phy-timings-vendor.diff`); L67-L72 viven solo en el árbol.
  Ficheros: HOST, `msm/dsi/dsi_manager.c`, `msm/dsi/phy/dsi_phy_7nm.c`, PVID, HINTF, PANEL, KTZ.
- **Config**: `build/kernel-config/k52L74.config` (= k52L73.config byte a byte; `k52L75.config` citado por
  el repack **no existe** en disco: crear como copia).
- **Toolchain**: `build/gates/build-fast.sh` (no `build-pokes.sh`, que es la receta vieja de pokes SMMU):
  `ARCH=arm64 LLVM=1`, `CC="ccache clang"` (clang 22.1.8), `HOSTCC="ccache gcc"`, `-j12`,
  `KBUILD_BUILD_USER=uke KBUILD_BUILD_HOST=palawan`, `KBUILD_BUILD_TIMESTAMP` fijo, objetivo `Image.gz`
  con initramfs embebido `build/init/uke-k34-fw-k52b2-initramfs.cpio.gz`; se relanza desprendido.
- **Comandos L76** (cuando se autorice compilar):
  ```bash
  R=~/proyectos/omarchy-uke
  cp $R/build/kernel-config/k52L74.config $R/build/kernel-config/k52L76.config
  bash $R/build/gates/build-fast.sh --src $R/build/kernel-pokes/k52-L16-tree \
       --cfg $R/build/kernel-config/k52L76.config \
       --out $R/build/kernel-pokes/k52L76-build --tag k52L76
  # esperar "DONE k52L76-BUILD-OK" en build/logs/build-k52L76.log
  cp $R/docs/historia/gates-palawan/repack-k52L75.py $R/docs/historia/gates-palawan/repack-k52L76.py   # y adaptar gates (§3.4)
  python3 $R/docs/historia/gates-palawan/repack-k52L76.py \
       --cmdline-append=-video=DSI-1:d,iomem=relaxed,arm_smmu.uke_disp_reclaim=1,regulator_ignore_unused
  ```
  (append de 4 tokens: así lo valida G2, `repack-k52L74-report.txt:8-11`; cmdline final 622 B == L74.)
  Flash: clon de `flash-l75-gated.sh` → `flash-l76-gated.sh` (solo `boot_a`; s288 solo lectura).
- **Prerrequisito no-kernel**: restaurar el rootfs Arch en `userdata` (ANDROID-HIST2 §A.1/D.2) antes de
  cualquier boot L76; sin él no hay SSH ni gates.

---

## 3. Plan L76 "paridad vendor"

Base: árbol actual (L73 PPS OEM + freno + L74 HS_TIMER/MISR/FLUSH + L75 PHY). Se conservan: FIX-1
flb 13/max_qp0 8 (HOST:2083-2100; el vendor mide `first_line_bpg_offset=0x0d`), freno B2-A, L74, L75 (tabla
PHY = registros vendor `00 27 0a 0a 1b 19 0a 0b 0a 02 04 00 20 0f`), hunk L70 (redundante con RGB101010, inocuo).

### 3.1 Cambios, ordenados por probabilidad de arreglar el negro (y riesgo)

**C1 — Mundo de píxel vendor en DSI+INTF (P alta · riesgo bajo).** Las tres piezas juntas (lección L69).
- HOST `msm_dsi_host_is_wide_bus_enabled()` (:841-852): quitar el `return false` de L71; volver a
  `msm_host->dsc && msm_dsi_host_version_geq(..., 6G, V2_5_0)`; `pr_info_once("UKE-L76: widebus ON")`.
- PANEL `o82_desc.format` (:814): `MIPI_DSI_FMT_RGB101010` → VID_CFG0 `0x02009140` (DST_FORMAT 4 +
  WIDEN). Efecto colateral verificado: `dsi_byte_clk_get_rate` ya da bpp 30 (igual que L70); el warning de
  HOST:1903 no salta (widebus ON).
- PVID `drm_mode_to_intf_timing_params()` (:126-150): sustituir el ceil /24 de L72/L73 por
  `DIV_ROUND_UP(width * drm_dsc_get_bpp_int(dsc), dsc->bits_per_component * 3)` → 427, periodo 572;
  renombrar el `uke_poke("L72-intf24ceil")` a `uke_poke("L76-intf30ceil")` (mantiene UKE-POKE en cuenta).
- Gates: `UKE-L76-DSI: id=%d CTRL VIDCFG0=0x02009140 AH=0x01cb0020 TOT=0x0905023b COMP=0x03200b51`
  (ampliar el readback `UKE-L68` de HOST:1176-1181 con `REG_DSI_VID_CFG0` y
  `REG_DSI_VIDEO_COMPRESSION_MODE_CTRL`); en HINTF `dpu_hw_intf_setup_timing_engine()` al final:
  `UKE-L76-INTF: INTF%d HSYNC=0x023c0010 VPER=0x00142968 DHCTL=0x01ca0020 CFG2=0x00001011 DHCTL_DATA=0x012a0020`
  (readback con `DPU_REG_READ`). Criterio: todos == vendor, si no → abortar lectura visual.

**C2 — Secuencia vendor: PPS única post-0x29 y motor de vídeo después (P media-alta · riesgo medio).**
- HOST `msm_dsi_host_enable()` (:2625): si `msm_host->dsc && MODE_VIDEO` (parámetro `uke_l76_defer_vid`,
  default 1) poner solo `DSI_CTRL_ENABLE` (no `VID_MODE_EN`); `msm_host->enabled = true` igual.
  Precedente: el flujo msm clásico enviaba el init antes de `host_enable` (CTRL con ENABLE sin VID).
  `pr_info("UKE-L76: VID diferido id=%d CTRL=0x%08x")` (esperado `0x1f1`).
- HOST: reutilizar `msm_dsi_host_video_engine_set()` (:1271, exportado) y añadir readback de CTRL + `ktime`.
- PANEL `o82_prepare()`: **eliminar el bloque PPS #1** (L37/L62, :413-463).
- PANEL `o82_enable()` (:610-713): mantener la PPS (L63, ambos links), **eliminar las 12 lecturas L65**
  (:672-693; el vendor no lee), y tras la PPS: `msm_dsi_host_video_engine_set(ctx->dsi[0]->host, true)` y
  luego `dsi[1]`; `pr_info("UKE-L76: VID ON tras PPS link%d CTRL=0x%08x dt_0x29=%lld ms")` (esperado `0x1f3`,
  ~+2 ms como el vendor +168.3→+168.8). En el camino inherit y en error de PPS, encender también el vídeo
  (no regresar a "sin vídeo").
- PVID `dpu_encoder_phys_vid_handle_post_kickoff()` (:659): `pr_info("UKE-L76: INTF%d TE ON t=%lld")`.
  Gate de orden: `VID ON` < `INTF TE ON` (el kickoff va tras `modeset_enables`).
- Riesgo: es un flanco VID 0→1 (el L68 fue 1→0→1 y latcheó el FIFO). Aquí no hay toggle y el freno B2-A
  acota cualquier flood; guarda DPMS del flash se mantiene.

**C3 — DCS como 0x39 (P baja-media · riesgo bajo).** PANEL `o82_send_panel_cmds()` (:225-262) + cola
b3/b2/0x11/0x29 (:466-491): helper local `o82_dual_dcs_long()` que construye `struct mipi_dsi_msg`
`{.type = MIPI_DSI_DCS_LONG_WRITE, .flags = MIPI_DSI_MSG_USE_LPM}` y llama
`dsi->host->ops->transfer()` para dsi[0] y dsi[1] (mismo orden que el helper dual: respeta `need_sync` de
dsi_manager). Gate `UKE-L76: DCS dt=0x39 n=112 err=0`.

**C4 — Reset final 15 ms (P baja · riesgo muy bajo).** PANEL `o82_reset()` :291 `usleep_range(15000,15500)`
(vendor TL:16→17); corregir el texto del pr_info.

**C5 — INTF_2 timing engine (P desconocida · riesgo medio).** El vendor lo deja a 0 (solo INTF_1 maestro).
En L76 **solo medir** con el log de C2 (`INTF2 TE ON`); cambiar en L77 si sale ON.

**C6 — KTZ dual (P muy baja para el negro · riesgo bajo).** KTZ: lista global `ktz8866_dev_list` + mutex en
`ktz8866_probe()` (:511) y `ktz8866_backlight_update_status()` (:406) escribe todos los chips. s288 ya
declara los dos nodos (s289 no es necesario). Marcador `UKE-L76: KTZ dual n=%d`. Recomendado en L77
(no toca el negro; cambia la ruta de luz que hoy funciona).

**C7 — Votos MMCX/MXA (P desconocida · riesgo alto).** Requiere DT: `power-domains`/supply hacia
`pm_v8_s6_level` (384) y `pm_v8_s8_level` (384-416) en `mdss_mdp_ml`/dsi (dtbo s290) + consumidor en
`msm_mdss.c` (`devm_regulator_get_optional` + `regulator_set_voltage` antes de relojes). Antes: 0-flash
`regulator_summary` en el port (PARIDAD §7.1). L78, nunca junto a C1-C2.

**C8 — ICC display (P baja · riesgo medio).** dtbo: rutas `qnm_mdp→qns_llcc` (mmss_noc) y `cpu-cfg`
(`chm_apps→qhs_display_cfg`) en `mdss_ml`; `msm_mdss.c` ya consume `mdp0-mem/mdp1-mem/cpu-cfg`. La ruta
rscc no tiene análogo. L78/L79.

### 3.2 Recomendación de empaquetado
**L76 = C1+C2+C3+C4** sobre L75 (un solo flash; todo es paridad medida y cada pieza lleva su readback). Si
el dueño prefiere bisección: L76a = C1 (lo más probable, menor riesgo) → L76b = +C2+C3+C4. L77 = C5/C6;
L78 = C7/C8 (dtbo).

### 3.3 Matriz de lectura post-boot
- Gates C1 verdes + C2 orden OK + contenido → cerrado.
- Gates verdes + negro + flood 0 → residuo DDIC/PHY-RX o potencia (C7/C8).
- Gates verdes + FIFO burst → mirar `INTF2 TE`, ERR_INT_MASK0/broadcast (§0) antes de tocar timing.

### 3.4 Gates de repack a adaptar (repack-k52L76.py desde L75)
`UKE-L71`→0, `L72-intf24ceil`→0, `L76-intf30ceil`=1, `L37-pps`→0, `UKE-L37`/`UKE-L62`→0, `UKE-L65`/`L65-bta`→0,
`UKE-L76` ≥5 formatos, UKE-POKE 121 → 117 (−3 L37, −1 L65-bta; nuevos marcadores por `pr_info`),
`UKE-P82` recontar; resto (L73/L74/L75, cmdline 622 B, s288) intacto.

---

## 4. Resumen (≤400 palabras)

L70 (#649) tenía widebus ON con DSI ACTIVE_H 427/TOTAL 0x0905023b y byte 148,648 MHz (= vendor medido
hoy), pero INTF truncado a 426 (periodo 571), formato DSI RGB888, PPS mainline (flb 12) enviada dos veces,
vídeo activo desde pre_enable y el toggle L68. Dio flood `dddd1011` que llenó el root, y se abandonó por
dos premisas hoy refutadas: el flood era del toggle (demostrado en L71) y el "vendor 534/0x090502a6" era
una derivación, no una medida. L67 limpio-negro; L68 ret=0 + flood; L69 underrun 1929/1929; L71 registros
"mundo 24" + flood 143k/20 s; L72 nunca flasheado; L73 PPS OEM + freno, sin veredicto anotado; L74 con
modetest: MISR≠0, TO=0, el dueño ve negro; L75 en el árbol, sin compilar. Ningún boot mostró contenido. La
combinación widebus ON + PPS OEM + PPS única post-0x29 + vídeo tras la PPS **no se probó nunca**.

Hallazgo nuevo: el vendor tiene VID_CFG0 `0x02009140` = **DST_FORMAT RGB101010** + WIDEN; nosotros
declaramos RGB888. Con widebus, el DSI espera 30 bit/pclk (HOST:1108) y le decíamos 24. INTF vendor
427/572 con CONFIG2 0x1011 y DATA_HCTL 267, que mainline reproduce con ceil.

Árbol: `build/kernel-pokes/k52-L16-tree` (L73+L74+L75). Build: `build-fast.sh --src … --cfg
build/kernel-config/k52L76.config (copia de k52L74) --out k52L76-build --tag k52L76` (clang LLVM=1, ccache,
Image.gz con initramfs k34-fw); repack clonando `repack-k52L75.py` con el append de 4 tokens; flash
clonando `flash-l75-gated.sh`. Antes hay que restaurar el rootfs Arch, que se perdió con #653.

L76, por orden: **C1** widebus ON (HOST:841) + `.format=RGB101010` (PANEL:814) + ceil /(bpc·3) en el INTF
(PVID:139); **C2** VID_MODE_EN diferido en `msm_dsi_host_enable`, quitar PPS #1 (PANEL:413-463) y las
lecturas L65, encender el vídeo en `o82_enable` tras la PPS única; **C3** DCS forzados a 0x39; **C4** reset
de 15 ms. Se mantienen L73/L74/L75. Cada pieza lleva marcadores `UKE-L76-DSI`/`UKE-L76-INTF` con los
valores vendor esperados, y un gate de orden (VID ON antes de INTF TE ON). En L76 solo se mide el timing
engine de INTF_2. Después vienen KTZ dual (driver; s288 ya declara los dos chips) y, como dtbo aparte, los
votos MMCX/MXA e ICC, que van tras medir `regulator_summary`.
