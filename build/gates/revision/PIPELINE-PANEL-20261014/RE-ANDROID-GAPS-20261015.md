# RE-ANDROID: cierre de 3 huecos (§5 ENABLE-COMPARISON, CRITICA-RONDA2 §1c) — 15-oct-2026

Solo lectura local sobre `~/proyectos/ubuntu-uke/stock/modules/msm_drm.ko` + `build/vendor-re/decomp/`
+ DT `build/evidencia/android-snap/dt-r15/`. Nada en la tablet. MEDIDO = disasm/DT; HIPÓTESIS donde se dice.

## 0. Método (reproducible)

`llvm-objdump --arch-name=aarch64 -d -r --disassemble-symbols=<f>` (los `bl` son `R_AARCH64_CALL26`;
los `adrp/add` se resuelven contra `readelf -rW` → `.rodata+off` → string). Mapa RO: `.rodata`
vive en fileoff `0x17128` (`readelf -SW`). Suplementos nuevos: `build/vendor-re/disasm-coldpath/*.s`
(12 funciones del cold-path con reubicaciones, comando en §4).

## 1. VEREDICTO SPLIT_LINK (hueco §5.1): Android NO lo programa para el o82 — H2 DECAE

Cadena completa, cada eslabón medido:

1. `dsi_ctrl_hw_cmn_host_setup` (`decomp/…host_setup.c:20-33`): el write a `SPLIT_LINK (0x330)`
   con `0x503000|EN` corre **solo si `host_cfg+0x38 != 0`**.
2. `host_cfg+0x38 ← mode_priv+0x1c90` (`decomp/dsi_panel_get_host_cfg_for_mode.c:54`).
3. `qcom,split-link-enabled` se lee en `dsi_panel_get` (nodo del **panel**): `adrp` en fileoff
   `0x14fd5c` → `.rodata+0x106f2` = esa prop (`relocs.txt`); si `read_bool` = falso, `tbz → skip`
   (`14fd8c`, verificado en disasm). `qcom,split-link-sublink-swap` igual en `0x14fe50`.
4. El nodo o82 **no trae ninguna prop split**: `ls` del dir del panel, de `qcom,dsi-display-primary/`
   y de `qcom,mdss_dsi_ctrl{0,1}@ae9{4,6}000/` → 0 ficheros `*split*` (solo existe
   `qcom,sde-has-src-split`, que es del MDP, no del link DSI). ⇒ `read_bool` = falso ⇒ skip.
5. `dsi_panel_get_mode` no lee **ninguna** prop split: mapa exhaustivo de sus ~130 refs
   `adrp→.rodata→string` (script en sesión): 0 contienen `split`; el flag `+0x1c90` se valida
   después contra topología (`1542f8: ldrb; cbz → skip`), que con `display-topology = 2 2 2`
   (DT, sin sublinks) lo deja a 0.
6. `dsi_ctrl_hw_22_configure_splitlink` solo existe como entrada de ops (`catalog_cmn_init.c:66`,
   única ref `ADRP` en `0x1380dc`); `qcom,split-link-supported` (leída en `dsi_ctrl_dev_probe`,
   `0x137108`) tampoco está en los nodos ctrl.

**Veredicto: paridad por omisión mutua.** No gastar ningún ciclo en `SPLITLINK←0x503001`.
Residual honesto: la identidad exacta del gate-a-1 per-mode (copia del flag de panel vs topología)
no se trazó instrucción a instrucción; ambas fuentes son 0/ausentes para o82, así que no afecta.
Layout del `timing[]` vendor verificado de paso (stores post-`read_u32` en `get_mode`):
`{hact@0, hbp@4, hsync@8, hfp@0xc, hskew@0x10, vact@0x18, vbp@0x1c, vsync@0x20, vfp@0x24}`.

## 2. VEREDICTO DSC-enable (sospecha CRITICA-RONDA2 §1c): el DDIC recibe PPS en cold-path, SÍ — por UNA sola vía, y no existe comando de compresión aparte

1. `dsi_panel_update_pps` (`decomp:16-65`): solo dos ramas, `sde_dsc_create_pps_buf_cmd` (128 B PPS
   VESA puro) o `sde_vdc_…`; construye **1 paquete** (`create_cmd_packets(…,1,…)`) y lo envía por
   `dsi_panel_tx_cmd_set(panel, 0x13)`. Índice `0x13 = 19` = slot PPS:
   `cmd_set_prop_map[19]` = `"PPS not parsed from DTSI, generated dynamically"`
   (resuelto vía relocs `R_AARCH64_ABS64` → `.rodata`; mapa completo 0–261 verificado).
2. El paquete es **DCS long-write tipo `0x0A`** (`MIPI_DSI_PICTURE_PARAMETER_SET = 0x0a`,
   `k52-L16-tree/include/video/mipi_display.h:49`): el buffer generado lleva `0x0A` en el byte
   de tipo y 128 B de PPS; `dsi_panel_update_pps` tiene **un único llamador**:
   `dsi_display_enable` (búsqueda `CALL26` en `relocs.txt`).
3. timing@120 trae `qcom,compression-mode = "dsc"` (`64 73 63 00`), DSC 1.1, 10 bpc, 8 bpp,
   slice 800×24 (`od` del DT) ⇒ corre la rama DSC, no VDC.
4. No hay nada más: el blob de 108 no contiene payloads `0x07`/`0x0A` (transcripción §2
   de ANDROID-DSI-PROFUNDO verificada); `strings` del `.ko`: 0 comandos `compression_mode*`;
   `dsi_display_update_pps` (programación PPS del host, no del panel) **no tiene llamadores DSI**.

**Veredicto: la sospecha §1c queda refutada como causa diferencial** — el vendor no envía ningún
`compression_mode_ext/0x07`; la activación de DSC en este DDIC es PPS-`0x0A` + bloque vendor
`0x90/0x91/0x92/0x9D` del blob. Nuestra PPS `_multi` (L59/L63, `err=0`) va por la misma vía.
Lo que SÍ sigue en pie de §1a/1b/1d/1e: PPS-en-stream vs en-idle, tablas RC, asimetría dual-link.

## 3. VEREDICTO valores de vídeo (hueco §5.2): mainline computa lo mismo — SÍ, salvo 1 bit abierto

Fórmulas (vendor `set_video_timing.c:58-74` vs mainline `dsi_host.c:1081-1097` + `927-988`):

| Reg | Vendor (con layout §1) | Mainline (bonded /2, DSC) | ¿Igual? |
|---|---|---|---|
| ACTIVE_H 0x24 | `(hbp+hsync)‖(…+H)` | `ha_start=32 ‖ ha_end=32+H'` | SÍ si H=H' |
| ACTIVE_V 0x28 | `148‖2284` = `0x08EC0094` | idem (`va_start=148`) | SÍ |
| TOTAL 0x2c | `(H+144)‖2309` | idem (`h_total-1600+H'-1`, `vtotal-1`) | SÍ si H=H' |
| HSYNC 0x30 | `16<<16` = `0x00100000` | `hs_end=16` | SÍ |
| VPOS 0x34 | 0 | 0 | SÍ |
| VSYNC 0x38 | `2<<16` = `0x00020000` | `vs_end=2` | SÍ |
| VID_CFG1 0x20 | 0 (sin props swap/rgb en DT) | siempre 0 (`dsi_host.c:831-837`) | SÍ |
| VID_CFG0 0x10 | misma receta (SYNC_EVENT/RGB888/BLLP, `video_engine_setup.c:10-15`) | idem (filas 1-2 ENABLE-COMPARISON) | SÍ (estructural) |
| + vendor extra | `HS_TIMER=0x4BB80, MISR=0x10100, FLUSH=1, DB_MODE=0` | no existen en mainline | H1/H4, sin cambio |

Con H=534 (ver abajo): `ACTIVE_H=0x02360020, TOTAL=0x090502A6`.
**Bit abierto (HIPÓTESIS, único): H.** Vendor: sin `qcom,widebus-enable` en ningún nodo DSI
(solo existe en `qcom,dp_display@ae154000/`) y sin rama widebus en su `set_video_timing` ⇒
H = ⌈1600·8/24⌉ = **534**. Mainline: `bits_per_pclk = 24`, pero `30` si widebus, que depende de
la versión HW leída en vivo (`dsi_host.c:797-803`, gate `≥6G v2.5`; uke SM7675 probablemente ≥,
`dsi_cfg.c:334-344`) ⇒ H' = 534 ó **427** (`ACTIVE_H=0x01CB0020, TOTAL=0x0905023B`).
Discriminante exacto sin flash extra: leer `ACTIVE_H` tras L59 o la versión DSI en el dmesg L64.

## 4. Decomp crítico: CERO funciones ausentes + 12 suplementos nuevos

Barrido sistemático `nm (T+t)` vs `decomp/*.c` para `dsi_*|sde_*|msm_dss*|mi_dsi*|mi_disp*|ktz*|dp_*`:
**1318 globales + 659 estáticas, 0 faltantes** (`_INDEX.txt: total=3404 written=3404 failed=0`;
archivos <10 líneas son funciones realmente triviales). Añadido: `build/vendor-re/disasm-coldpath/`
con 12 `.s` (`-d -r`, con reubicaciones): prepare/enable/panel_enable/pre_prepare/prepare,
`get_host_cfg_for_mode`, `get_mode`, `update_pps`, `host_setup`, `set_video_timing`,
`video_engine_setup`, `ctrl_reset`. Ghidra no hizo falta.

## 5. Qué cambia para el test L65 (BTA readback, construido en L67)

1. **H2 muere**: no programar `SPLITLINK`; el ciclo ahorrado va al BTA.
2. **El BTA es ahora el discriminante maestro**: si `0x0A` responde, el DDIC vive y la PPS aplica
   (cierra §1a/1e de RONDA2 de un golpe); si no responde, parar DSC e ir a link/PHY/vci + H-widebus.
3. **Añadir al BTA, gratis**: leer `ACTIVE_H` por BTA/debugfs tras el `enable` — `0x02360020`
   confirma H=534 (paridad vendor); `0x01CB0020` delata widebus-mainline (nº1-bis real).
   Y leer la versión DSI del dmesg L64 resuelve H' sin hardware extra.
