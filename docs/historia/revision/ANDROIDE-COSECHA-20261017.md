# COSECHA ANDROID — la verdad del panel funcionando (17-oct-2026)

Método: adb con root Magisk (v30.7, su en `/debug_ramdisk/su`; exige Ajustes→Superusuario→
"Apps y ADB"). Tablet en Android/HyperOS (OS3.0.303.0.WOZEUXM), WiFi conectada por
`cmd wifi connect-network` (192.0.2.13). Artefactos en `build/android/cosecha-20261017/`
(dmesg vendor completo 1,4 MB, kmsg vivo 1,7 MB, clk_summary 867 líneas, dump_info, states,
listas de debugfs y DT).

## Tabla de paridad: Android vivo vs nuestro L74

| Qué | Android (trabajando) | Nuestro L74 | ¿Paridad? |
|---|---|---|---|
| bitclk | **1.189.190.000 Hz** (dump_info) | 1.189.190.000 (OPP→VCO) | ✓ |
| BYTE_CLK | 148.648.750 | 148.648.498 | ✓ |
| PIXEL_CLK | 158.558.666 | 158.558.400 | ✓ |
| **ESC_CLK** | **19.200.000** (state_info) | 19.200.000 | ✓ **hipótesis esc MUERTA** |
| byte_intf | 74.322.766 (byte/2) | — (revisar) | por verificar |
| topología | lm2/comp_enc2/intf2, **Clock master = dsi-ctrl-0** | single-PLL bonded master dsi0 | ✓ |
| panel | `qcom,mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid`, "panel is tddi" | mismo | ✓ |
| PPS | OEM (nuestro L73 = OEM byte-exact) | ✓ |
| **read cell ID** | **falla TAMBIÉN en el vendor (rc=-22)** | BTA mudo (ret=0) | ✓ propiedad del panel |
| **TDDI táctil↔display** | **NVT-ts por SPI activo en CADA transición** (`xiaomi_drm_panel_notifier_callback: TDDI_FB_BLANK_UNBLANK`, touch modes 1071/1000, custom cmd 0x19; irq-gpio 387, lcd_id-gpio 359) | **AUSENTE** | ✗ **ÚNICA diferencia estructural** |

## Hechos nuevos del sistema funcionando

1. **El kernel vendor re-inició el panel completo por su propio camino** en el arranque:
   `power mode 1->2, fps 0->120` (t=9,70 s) — no heredó el splash del ABL. Su enable va directo
   a 120 Hz y el táctil sincroniza en ese ciclo.
2. Modos del panel (dfps): 120/144/90/60/50/48/30 — con multi-timing Xiaomi (mi_dpfs); el modo
   "120 Hz" del grupo 0 que usamos es EL modo nativo.
3. debugfs del vendor: `qcom,mdss_dsi_o82_.../{misr_data, dsi-ctrl-{0,1}/{reg_dump,state_info,cmd_dma_stats}, dsi-phy-*_*, esd_*, ulps_*}`.
   `misr_data` lee DSI_0/DSI_1 MISR: 0x0 en idle (su MISR se arma por frame).
4. `/dev/mem` no existe en el kernel vendor (CONFIG_DEVMEM=n); debugfs montable con root
   (`mount -t debugfs none /sys/kernel/debug`).
5. El reloj `dsi1_phy_pll_out_*` queda a 500/312,5 MHz con enable 0 — la PLL activa es la de
   dsi0 para ambos (confirma el single-PLL bonded que ya replicamos).
6. SSC deshabilitado en el vendor (`qcom,dsi-pll-ssc-disable`).

## Consecuencia para L75

Todo el bloque de control/relojes/config está en paridad **medida contra el aparato trabajando**
— ya no es inferencia. Quedan vivas, por orden:

1. **TDDI: el port del táctil (NVT-ts, SPI)** — la única diferencia estructural. El port
   `0001-touch` (commits 346255d/a0e3a7f) existe con dry-run verde pero SIN DT en el slot.
   El handshake del táctil en cada power transition es lo único que nuestro camino no hace.
   Ruta kernel-only: hardcoded board-info SPI (bus/CS/irq-gpio 387/lcd_id 359 — datos del
   dmesg vendor capturados) o su fragmento DT vía dtbo (2ª escritura).
2. **Los 6 deltas residuales de la tabla PHY** (hs_exit/hs_zero/clk_post/clk_pre/clk_trail/
   hs_rqst vs vendor) — kernel-only vía DT de la PHY o tabla verbatim.
3. **Bools ECC/CRC/deskew** — verificar primero si el DTB stock las declara (dtb local).

## Deuda operativa de esta cosecha

- `04-regs-*` vacíos: toybox devmem exige ancho en BYTES (`devmem ADDR 4`) y el kernel vendor
  no tiene /dev/mem → los registros completos del working DSI solo via `dsi-ctrl-*/reg_dump`
  (dump al dmesg; el trigger echo 1 no volcó hex en esta sesión — reintentar leyendo dmesg tras
  un dpms cycle).
- Registros OURS vs vendor sin comparar aún: capturar el equivalente en nuestro L74
  (nuestro kernel tiene debugfs propio; usar el mismo canal si existe, o añadir un dump de
  registros a la próxima imagen).
- El Magisk de la tablet quedó con "Apps y ADB" habilitado y WiFi `RED-EJEMPLO-3_5G` guardada —
  reutilizable en futuras sesiones Android.
