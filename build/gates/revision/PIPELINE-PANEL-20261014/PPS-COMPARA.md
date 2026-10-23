# PPS-COMPARA — mainline (L62) vs vendor o82 · 14-oct-2026

## Veredicto (1 línea)
**Contenido: IGUALES campo a campo** (L62 = lo que el vendor calcularía);
en el cable del boot con splash el vendor **no envía ninguna PPS**
(rama cont-splash la salta) ⇒ el negro no son los bytes de la PPS.

## 1. PPS mainline L62 — campo a campo (128 B)
Packer `drm_dsc_pps_payload_pack()` (`k52-L16-tree/.../display/drm_dsc_helper.c:99`);
fill `dsi_populate_dsc_params()` (`k47-fuentes/dsi_host.c:1872-1916`: const+thresh+
`setup_rc_params(PRE_SCR)` + `initial_scale` + `compute_rc`);
template `o82_dsc_config` (`k47-fuentes/panel-xiaomi-o82-dualdsi.c:566-576`,
copiado en probe `:631`, dims L62 `:25-26`); dims host FULL vía
`dsi_timing_setup()` (`k47-fuentes/dsi_host.c:1034-1035`, `pic=FULL` sin `/2`).
`line_buf_depth=bpc+1=11` (`dsi_host.c:1913`); `simple_422=vbr=native=0`,
`convert_rgb=1` (`:1898-1900`); `second_line/nsl/offset_adj=0` (template no los
pone, populate no los toca); `mux=48` (`drm_dsc.h:15`), `rc_model=8192`,
`edge=6`, `tgt=0x33` (`:22-25`); `chunk=ceil(800·128/128)=800`;
`groups=267`, `init_scale=32`, `dec_int=11`, `final=4336/0x10F0`,
`nfl=1069/0x42D`, `slice_bpg=732/0x2DC`, `inc=704/0x2C0`, `dec_delay=657/0x291`
(calculados del fuente, §comando abajo); thresh `>>6` = `0E…7E` (`:316-339`).
Bytes: `11 00 00 AB 0C 80 | 08 58 | 06 40(L62; L59=0C 80) | 00 18 | 03 20 |
03 20 | 02 00 | 02 91 | 00 | 20 | 02 C0 | 00 0B | 00 | 0C | 04 2D | 02 DC |
18 00 | 10 F0 | 07 | 10 | 20 00 | 06 | 0F | 0F | 33 |
0E 1C 2A 38 46 54 62 69 70 77 79 7B 7D 7E |
`0082 2100 2920 297E 397C 397A 3978 39B8 39B8 39F6 49F6 4A34 4A34 5A34 8A74`
(range pre-SCR 8bpp/10bpc, `drm_dsc_helper.c:380-390`) | `00…00` (88-127).
Repro: `python3` con las fórmulas de `:1340-1430` (verificado hoy: coincide).

## 2. PPS del vendor — RE
`dsi_panel_update_pps()` (`build/vendor-re/decomp/dsi_panel_update_pps.c:30-45`):
`sde_dsc_create_pps_buf_cmd` + `tx_cmd_set(0x13)` — **existe y envía (DCS 0x0A)**,
pero `dsi_display_enable()` solo lo llama fuera de splash
(`decomp/dsi_display_enable.c:103-110`, con flags DSC `0x1c90/1c91`);
con splash vivo toma `config_ctrl_for_cont_splash` (`:164`) y **no hay ni PPS
ni 108 cmds** — el ABL gobierna el panel. Coherente con
`SECUENCIA-…-O82-20261012.md:52` ("calculado, no va al panel") y
`docs/historia/revision/ANDROID-DSI-PROFUNDO-20261013.md:484-485` ("IC preconfigurado").
Inputs idénticos en DT-r15 (medido hoy): ver `0x11`=1.1, scr `0`,
slice `0x320×0x18`=800×24, bpc 10, bpp 8, slice/pkt 1, 1600×2136 por link,
topo `2 2 2` (`dt-r15/…/o82_42_02_0b…/timing@120/*`, `docs/historia/revision/PIPELINE-PANEL-20261014/S6-MINUCIAS-DT.md:120-121`).
CAF `sde_dsc_create_pps_buf_cmd` empaqueta el mismo PPS VESA 1.1 → **diff de
contenido L62 vs vendor: 0 bytes** (salvedad: tablas RC sde vs DRM sin cotejo
entrada a entrada, `docs/historia/revision/INFORME-MODO-OPP-DSC-20261013.md:235-236`; ambas VESA
pre-SCR/C-model — residual bajo). El único byte que difirió fue
`pic_width` L59 (`0C 80`=3200, 4 slices fantasma); L62 (`06 40`) lo cierra.

## 3. El verdadero delta: ORDEN, no bytes
Nosotros: PPS en `prepare` **antes** de `0x11/0x29`
(`k47-fuentes/…o82…c:333-360`, hunk L59/L62 entre init y `freq_sel`).
Vendor: PPS en `enable` **después** de los 108 cmds (`0x11`+120 ms, `0x29`)
(`SECUENCIA:49-52`, `enable.c:75+103-110`). PPS a panel dormido puede ignorarse.
El driver no tiene hook `enable` (solo prepare/unprepare, `:452-454`).

## 4. Re-ranking (un cambio por ciclo)
(i) **Re-envío post-0x29** (nuevo `o82_enable` con la misma PPS, o mover el hunk
tras el `0x29` del prepare): coste 1 hunk+1 flash; PASA=contenido, FALLA=cierra
la rama PPS entera (las dos posiciones probadas). **Candidato nº1.**
(ii) Coherencia encoder: `dsi_update_dsc_timing` (`dsi_host.c:927-988`: WC=800,
eol=1, pkt/linea=2) sale del mismo struct — solo auditoría de código, 0 flashes.
(iii) `CLOCK_NON_CONTINUOUS`: `docs/historia/revision/PIPELINE-PANEL-20261014/s6-noncontinuous.diff` listo (dry-run OK,
`docs/historia/revision/PIPELINE-PANEL-20261014/S6-MINUCIAS-DT.md:139-142`); vendor LP11-init ⇐ HS continuo desde power_on;
nº2 si (i) falla. (iv) PHY vendor (`strength=0xff`, `voltage=0x51`, medidos hoy;
`phy-timings` pendiente de volcar): nº3, timings a velocidad equivocada ya es
territorio R1/G5-G6-inertes — solo con artefactos.

## 5. Extra pedido
Sin captura vendor de la PPS: `dmesg-FULL.txt` r15 da 0 líneas PPS/DSC
(solo `LinuxPPS` del kernel); snapshot r15 sin traza DSI. Versión correcta:
DT `0x11`/scr `0` ⇒ pre-SCR = nuestro `PRE_SCR` + `ver=11` en el log. ✅
