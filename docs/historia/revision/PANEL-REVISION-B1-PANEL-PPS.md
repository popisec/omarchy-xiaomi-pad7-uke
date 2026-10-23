# PANEL-REVISION B1 — Driver de panel + carga de configuración al DDIC — 15-oct-2026

> Agente B1 de la revisión por fases. Solo lectura de código/evidencia; cero toques al
> dispositivo, cero builds. No repite A1 (boots L67–L71), A2 (fedora/senemos) ni A3
> (verdad vendor); los cita. **NUEVO** = hallazgo no escrito antes en ningún informe.

---

## 0. Veredicto ejecutivo (1 párrafo)

**El init DCS está CERRADO (byte-idéntico al OEM 42_02_0b, incluido el bloque DSC
0x90/0x91/0x92/0x9D y 0x51=0x0FFF/0x53=0x24). La PPS NO es byte-idéntica al OEM:
5 bytes difieren**, y el propio init del panel lo certifica: el registro DDIC **0x91**
lleva `02 B2 / 02 9F / 00 0B / 04 86 / 02 DC` (dec_delay 690, scale_inc 671, nfl 1158 —
valores derivados de `first_line_bpg_offset = 13`), que es exactamente lo que el vendor
computa y envía por 0x0A; nosotros enviamos `02 91 / 02 C0 / 04 2D` (flb = 12) y
`range_max_qp[0] = 4` en vez de 8. PPS-COMPARA.md («diff 0 bytes») queda **REFUTADO**.
L64 cerró la rama «PPS enviada err=0» pero nadie había cotejado los BYTES contra el PPS
que el vendor genera para ESTE panel-id. Fix nº1: quirk RC OEM (flb=13 + max_qp0=8 +
recompute) en `dsi_populate_dsc_params`, que corrige PPS **y** encoder DPU a la vez
(mismo `struct` compartido). Rama PPS: **RE-ABIERTA como causa nº1 del negro.**

---

## 1. Tabla de discrepancias

| # | Dónde (nuestro) | Vendor/OEM | Qué | Estado |
|---|---|---|---|---|
| D1 | `panel-xiaomi-o82-dualdsi.c:106-188` + tail `:464-492` | DTBO dt-r15 `…/o82_42_02_0b_dualdsi_dsc_vid/…timing@120/qcom,mdss-dsi-on-command` (998 B, 108 cmds) | **Init DCS**: decode comando a comando (script /tmp/b1_decode.py): 108/108 payloads idénticos byte a byte. Único delta: dt de los 4 comandos del tail (vendor 0x39 long-write; nosotros 0x15/0x05 short) — semánticamente equivalentes en DCS | YA CONOCIDO (A1 §2 «byte-idéntico», ANGULO-DDIC C3) — ahora verificado con decodificador |
| D2 | `panel-xiaomi-o82-dualdsi.c:183-187` | A3 §1; DTBO vendor | **Bloque DSC 0x90=03 / 0x91(17 B) / 0x92=10 f0 / 0x9D=01** presente e idéntico; `0x51=0x0FFF` (`:180`), `0x53=0x24` (`:181`) presentes | YA CONOCIDO, confirmado |
| D3 | PPS empaquetada con `drm_dsc_pps_payload_pack` desde `ctx->dsc` (`panel…c:413-461` prepare-L37/L62 y `:610-632` enable-L63) | `sde_dsc_populate_dsc_config` (decomp `sde_dsc_populate_dsc_config.c:26-46`) para panel-id `0x4f38325042020b`: **first_line_bpg_offset = 13** (override o82; genérico: 15/12) y **max_qp de la tabla `sde_dsc_rc_range_max_qp_nvt_36532`** (`range_max_qp[0] = 8`; tabla genérica y mainline: 4). Extraído del `msm_drm.ko` stock (`sde_dsc_rc_range_max_qp_nvt_36532` @ .rodata+0x742b8, combo idx 1 = 8bpp/10bpc) | **PPS: 5 bytes de diferencia** (ver §2). Todo lo demás (thresh, min_qp, bpg, LUT xmit 512/flat 7-16/qincr 15, chunk 800, scale_dec 11, slice_bpg 732, final 0x10F0) idéntico | **NUEVO — hallazgo principal.** Refuta PPS-COMPARA.md §2 («diff 0 bytes») y A2 §6.3 / A3 §3 («ya byte-equivalente») |
| D4 | — | `o82_…0b…/timing@120/qcom,mdss-dsi-on-command` cmd 0x91 payload: `…02 b2 02 9f 00 0b 04 86 02 dc…` = dec_delay 0x02B2, scale_inc 0x029F, scale_dec 0x000B, nfl 0x0486, slice_bpg 0x02DC | **El init del propio DDIC pre-fija el mundo flb=13.** Nuestro PPS (flb=12 → 0291/02C0/042D) sobrescribe esos registros vía 0x0A justo antes del vídeo | **NUEVO** — prueba independiente del D3, sin depender de mi lectura del decomp |
| D5 | `panel…c:464-483` (tail): PPS en prepare (pre-0x11) **y** post-0x29 en enable `:622-629` | A3 §1/§3: PPS una sola vez, post-0x29, pre-engine (`dsi_display_enable.c:75→103-110→154`) | Orden: nuestro post-0x29 replica al vendor; el pre en prepare no existe en vendor (inofensivo: LP antes de 0x11) | YA CONOCIDO (L63, PPS-COMPARA §3) |
| D6 | `panel…c:271-294` (o82_reset): 0/10 ms, 1/3 ms, 0/3 ms, 1/**100 ms** (r7) | DTBO vendor `qcom,mdss-dsi-reset-sequence` (0a y 0b idénticos): 0/10, 1/3, 0/3, **1/15 ms** | Última liberación 100 ms vs 15 ms — deliberado («discriminador temporal» r7) | YA CONOCIDO |
| D7 | `panel…c:853-855` + `msm_drv.c:69-77`: herencia UKE-L63 por `msm.uke_panel_inherit` | A3 §6: vendor con splash no toca nada (rama B) | Coherente; en los flashes L64+ el parámetro va a 0 (se ve `UKE-L63: PPS…` en kmsg) ⇒ cold path completo. Con U-Boot no hay splash que heredar | YA CONOCIDO |
| D8 | dtbo s288 / `fase4-display.dts:358-388`: panel `xiaomi,uke-o82-4202-0b`, L8B/vsp/vsn, reset TLMM 2, ports 0/1; backlight→ktz_bl_0 | DTBO vendor: `mi,panel-id=004f38325042020b` (unidad CSOT 0b, docs/historia/revision/PIPELINE-PANEL-20261014/ANDROID-PANTALLA-COMPLETA.md:4), broadcast, lp11-init | Nodo correcto y variante correcta (D1 depende de esto) | YA CONOCIDO |
| D9 | `uke-display-o82.dtsi:113-121` (ktz8866_1 comentado) + FRAGMENTO-KTZ8866.dts (declara los DOS como el stock) | A3 §7: vendor escribe a las DOS chips (se0+se12), remap `mi_bl_level_remap` | Luz, no vídeo (KTZ = LED strings por I2C; el vídeo no pasa por KTZ). No explica el negro | YA CONOCIDO (A3) |
| D10 | Init 0a vs 0b (A2/A3 no lo distinguían): `…o82_36_02_0a…/on-command` = **1632 B / 171 comandos** ≠ 0b (998 B / 108) | — | Las variantes difieren desde el cmd 78 (gamma/blocks extra en 0a). Nuestra unidad es 0b ⇒ irrelevante, pero invalida cualquier mezcla de streams entre variantes (A3 §1 citaba 1632 B/108 cmds: cóctel) | **SEMI-NUEVO** (aclaración) |
| D11 | `panel…c:180-181` 0x51/0x53 en init; driver no usa 0x51 en runtime | A3 §7: brillo 100 % por I2C KTZ, 0x51 solo init | Correcto en nuestro port | YA CONOCIDO |

---

## 2. El PPS, byte a byte (D3/D4)

PPS esperada (128 B) — **la que enviamos hoy** (computada fiel a
`drm_dsc_pps_payload_pack` + `dsi_populate_dsc_params` de k52-L16-tree) vs **la del
vendor para panel-id 0x4f38325042020b** (decomp + tablas del msm_drm.ko stock):

```
ours  : 11 00 00 ab 30 80 08 58 06 40 00 18 03 20 03 20 02 00 02 91 00 20 02 c0
        00 0b 00 0c 04 2d 02 dc 18 00 10 f0 07 10 20 00 06 0f 0f 33
        0e 1c 2a 38 46 54 62 69 70 77 79 7b 7d 7e | 01 02 22 00 2a 40 2a be 3a fc
        3a fa 3a f8 3b 38 3b 78 3b b6 4b f6 4c 34 4c 74 5c 74 8c f4 | 00…00

vendor: 11 00 00 ab 30 80 08 58 06 40 00 18 03 20 03 20 02 00 02 b2 00 20 02 9f
        00 0b 00 0d 04 86 02 dc 18 00 10 f0 07 10 20 00 06 0f 0f 33
        0e 1c 2a 38 46 54 62 69 70 77 79 7b 7d 7e | 02 02 22 00 2a 40 2a be 3a fc
        3a fa 3a f8 3b 38 3b 78 3b b6 4b f6 4c 34 4c 74 5c 74 8c f4 | 00…00

diffs (5):
  PPS[ 19] ours=91 vendor=B2   (initial_dec_delay: 657 vs 690)     ← deriva de flb
  PPS[ 23] ours=C0 vendor=9F   (scale_increment_interval: 704 vs 671) ← deriva de flb
  PPS[ 27] ours=0C vendor=0D   (first_line_bpg_offset: 12 vs 13)   ← RAÍZ A
  PPS[ 29] ours=2D vendor=86   (nfl_bpg_offset: 1069 vs 1158)      ← deriva de flb
  PPS[ 58] ours=01 vendor=02   (range0: max_qp 4 vs 8)             ← RAÍZ B
```

- **Raíz A**: mainline coge flb=12 de la tabla VESA E-5 (`drm_dsc_helper.c`,
  `rc_parameters_pre_scr` 8bpp/10bpc); el vendor fuerza **13** para los DOS o82
  (branch `param_3 ∈ {0x4f38325036020a, 0x4f38325042020b}` en
  `sde_dsc_populate_dsc_config.c:26-46`).
- **Raíz B**: mainline elige max_qp[0]=4 («VESA E-5» con comentario explícito); el
  vendor usa para el o82 la tabla **`sde_dsc_rc_range_max_qp_nvt_36532`** (el o82 es un
  TDDI Novatek NT36532) cuyo `range_max_qp[0] = 8` (el valor del C-model que mainline
  rechaza). Extraído del msm_drm.ko stock por símbolos ELF (`readelf -s`), combo idx 1
  (8bpp/10bpc): min/bpg idénticos a VESA; solo max_qp[0] difiere (8 vs 4).
- **Corroboración sin decomp**: los bytes 0x91/0x92 del init del panel (que nosotros YA
  enviamos) contienen `02 B2 / 02 9F / 04 86 / 02 DC / 10 F0` = dec_delay 690, scale_inc
  671, nfl 1158, slice_bpg 732, final 4336 — mi emulación del mundo flb=13 reproduce los
  tres primeros EXACTOS (1158 = ceil(13·2048/23); 690 = ceil((2048+4096+267·13)·16/128)−512;
  671 = (4336<<11)/((1158+732)·7)). El mundo flb=12 daría 0291/02C0/042D (lo que enviamos).
- Consecuencia mecánica: nuestro PPS reprograma el RC del decodificador del DDIC a un
  presupuesto distinto del que su init (y el vendor) usan. DSC RC mal emparejado
  ⇒ decodificador sin salida válida ⇒ negro con enlaces «sanos» (writes err=0, sin
  underrun de comando). Nota: el error de PPS-COMPARA en pps[4] (`0C` vs real `30`,
  convert_rgb+block_pred) era solo un error de transcripción de su repro Python; el
  packer real (`drm_dsc_helper.c:99-160`) memset y fija 0x30.

---

## 3. Fixes candidatos para el ÚNICO flash (L73)

### FIX-1 (nº1) — Quirk RC OEM del o82 en el DSI host (corrige PPS + encoder DPU)

**Qué arregla**: los 5 bytes del PPS (D3) Y el encoder DSC del DPU, que comparte el
mismo `struct drm_dsc_config` (`dsi.c:17` → `msm_dsi_host_get_dsc_config` →
`&ctx->dsc`; el DPU lo lee en `dpu_encoder.c:218` vía dpu_encoder_get_dsc_config).
Decodificador y encoder quedan en el mundo OEM validado en Android (flb=13/max8).
Recomputar reproduce exactamente los valores que el init del panel declara en 0x91/0x92.

```diff
--- a/drivers/gpu/drm/msm/dsi/dsi_host.c
+++ b/drivers/gpu/drm/msm/dsi/dsi_host.c
@@ -1985,12 +1985,35 @@ static int dsi_populate_dsc_params(struct msm_dsi_host *msm_host, struct drm_dsc
 	dsc->initial_scale_value = drm_dsc_initial_scale_value(dsc);
 	dsc->line_buf_depth = dsc->bits_per_component + 1;
 
-	return drm_dsc_compute_rc_parameters(dsc);
+	ret = drm_dsc_compute_rc_parameters(dsc);
+	if (ret < 0)
+		return ret;
+
+	/*
+	 * L73 (uke, 15-oct-2026): parametros RC OEM del panel o82 42_02_0b.
+	 * El vendor (msm_drm.ko, sde_dsc_populate_dsc_config, branch panel-id
+	 * 0x4f38325042020b/36020a) usa first_line_bpg_offset = 13 (override
+	 * o82) y range_max_qp[0] = 8 (tabla sde_dsc_rc_range_max_qp_nvt_36532);
+	 * mainline usa 12 y 4 (VESA E-5). El init del propio panel (cmd 0x91:
+	 * 02 b2 / 02 9f / 04 86) certifica los valores derivados del 13:
+	 * dec_delay 690, scale_inc 671, nfl 1158. Nuestro PPS diferia en 5
+	 * bytes y reprogramaba el RC del decodificador del DDIC. Override +
+	 * recompute = PPS byte-identica al OEM; el DPU (mismo struct via
+	 * msm_dsi_host_get_dsc_config) queda en el mismo mundo.
+	 */
+	if (dsc->bits_per_component == 10 && dsc->bits_per_pixel == (8 << 4) &&
+	    dsc->slice_width == 800 && dsc->slice_height == 24) {
+		dsc->first_line_bpg_offset = 13;
+		dsc->rc_range_params[0].range_max_qp = 8;
+		ret = drm_dsc_compute_rc_parameters(dsc);
+	}
+
+	return ret;
 }
```

- **Riesgo: medio.** Cambia el bitstream del encoder y el RC del decoder a la vez;
  es el único mundo probado en hardware (Android), pero toca la ruta DPU→INTF: si algo
  del feed L71 dependía de los RC params (chunk 800 no cambia; dce_bytes_per_line no
  cambia), el impacto es solo RC. Idempotente (se ejecuta 2× sobre el mismo struct,
  dsi0+dsi1).
- **Verificación post-boot**: (a) marcador nuevo — añadir en el log de L63
  `UKE-L73: PPS[19]=%02X [23]=%02X [27]=%02X [29]=%02X [58]=%02X` (esperado B2 9F 0D
  86 02); (b) `grep -c S4-DIAG` ≈ 0 y `FIFO_STATUS` crudo sin VIDEO_MDP over/underflow;
  (c) underruns encoder ≈ 0; (d) **PASA = contenido en pantalla**. Fallback: si sigue
  negro con flood 0, el residuo vuelve a PHY-RX/sordo (A1 §6.3), no al RC.
- **Independencia**: independiente de FIX-2/FIX-3; puede componerse. Debe volar SOBRE
  L72 (toggle L68 retirado + ratelimit), no sobre L71.

### FIX-2 (opcional, independiente) — Reset final 100 ms → 15 ms (vendor)

**Qué arregla**: D6, fidelidad al `qcom,mdss-dsi-reset-sequence` del OEM.

```diff
--- a/drivers/gpu/drm/panel/panel-xiaomi-o82-dualdsi.c
+++ b/drivers/gpu/drm/panel/panel-xiaomi-o82-dualdsi.c
@@ -289,7 +289,7 @@ static void o82_reset(struct o82_panel *ctx)
 	uke_poke("K48-w3-done");
 	usleep_range(3000, 3500);
 	uke_poke("K48-rst-A2-ok");	/* re-ASSERT 3ms */
 	pr_info("UKE-P82: rst: assert2(3ms) OK\n");
 	gpiod_set_value_cansleep(ctx->reset_gpio, 0);
 	uke_poke("K48-w4-done");
-	usleep_range(100000, 101000);	/* r7: 15->100ms, discriminador temporal */
+	usleep_range(15000, 15500);	/* L73: vendor reset-sequence (1, 15 ms) */
 	uke_poke("K48-rst-R2-ok");	/* RELEASE final */
```

- **Riesgo: bajo** (solo un delay post-release; el reset ya corre en cold path).
- **Verificación**: marcadores K48 intactos; init err=0 como hoy.
- **Independencia**: sí (subsys y fase distintos). Recomendación: NO componerla este
  flash — mantener 1 variable y conservar el discriminador r7; el 100 ms no puede
  causar negro (es más conservador que el vendor).

### FIX-3 (NO para este flash) — PPS-only payload patch

Parchear solo los 5 bytes del PPS en el panel (post-pack) dejando el encoder mainline
en flb=12/max4: **descartado** — decodificador (13/8) y encoder (12/4) con RC
desemparejado ⇒ bitstream indescifrable garantizado. FIX-1 es la forma correcta de
hacerlo (mismo struct en ambos lados).

### KTZ dual (D9) — fuera del flash de vídeo

Sin impacto en vídeo (luz por I2C). El FRAGMENTO-KTZ8866.dts ya declara ambos nodos
como el stock; si el dtbo s288 vivo solo lleva ktz_bl_0, el efecto sería brillo, no
negro. No mezclar.

---

## 4. Veredicto

**¿El PPS es la causa más probable del negro? Sí — rama re-abierta con prueba dura.**
L64 cerró «PPS enviada err=0», pero err=0 solo prueba el DMA del host (A1 §4). Ahora se
sabe que el PPS difiere en 5 bytes del que el vendor genera para ESTE panel-id, y que el
init del propio panel (0x91: 02B2/029F/0486/02DC) declara el mundo flb=13 que nuestro
PPS sobrescribe por 0x0A antes del vídeo. Con init DCS byte-idéntico, timing/ ACTIVE_H/
byte-clock clavados al vendor (L71) y el toggle L68 retirado (L72), los 5 bytes del PPS
son el ÚNICO delta de contenido restante entre el cold-path vendor y el nuestro. **El
cambio que mejor lo ataca en un solo flash es FIX-1** (quirk flb=13 + max_qp0=8 +
recompute en `dsi_populate_dsc_params`): corrige decoder (PPS) y encoder (DPU) juntos,
reproduce exactamente los valores que el init del panel ya fija, y es verificable
marcador en mano (`UKE-L73: PPS[19]=B2 [23]=9F [27]=0D [29]=86 [58]=02` + flood 0 +
contenido). Escenario post-flash: negro con flood 0 ⇒ el residuo es PHY-RX/BTA-sordo
(A1 §6.3), y la rama PPS queda cerrada de verdad; negro con contenido parcial/garbage ⇒
RC mal emparejado en otro campo (revisar second_line/native-422, ambos 0 ✓).

---

## 5. Ficheros y pruebas usados

- Nuestro árbol: `build/kernel-pokes/k52-L16-tree/drivers/gpu/drm/panel/panel-xiaomi-o82-dualdsi.c`,
  `.../drivers/gpu/drm/msm/dsi/dsi_host.c` (`dsi_populate_dsc_params` :1948-1991,
  `msm_dsi_host_get_dsc_config` :2790),
  `.../drivers/gpu/drm/msm/dsi/dsi.c:17`, `.../disp/dpu1/dpu_encoder.c:218`,
  `drivers/gpu/drm/display/drm_dsc_helper.c` (packer + pre-SCR table).
- Vendor: `build/evidencia/android-snap/dt-r15/soc/qcom,mdss_mdp@ae00000/
  qcom,mdss_dsi_o82_{36_02_0a,42_02_0b}_dualdsi_dsc_vid/**` (reset-seq, DSC props,
  on-commands 1632 B/0a y 998 B/0b), `build/vendor-re/decomp/sde_dsc_populate_dsc_config.c`,
  `sde_dsc_create_pps_buf_cmd.c`, `dsi_panel_update_pps.c`,
  `build/vendor-re/decomp/…/l68-videooff-read.diff` (no: `build/gates/revision/PIPELINE-PANEL-20261014/l68-videooff-read.diff`).
- OEM RC extraído de **`~/proyectos/ubuntu-uke/stock/modules/msm_drm.ko`** (símbolos
  `sde_dsc_rc_range_{min,max}_qp*`, `sde_dsc_rc_range_bpg*`, `sde_dsc_rc_init_param_lut`,
  `sde_dsc_rc_buf_thresh`; tablas en .rodata, LUT 15×0x20 en .data).
- Scripts efímeros: `/tmp/b1_decode.py` (diff init), `/tmp/b1_pps_full.py` + inline
  (extracción tablas + PPS diff). Fedora/senemos: `/tmp/uke-mainline-linux/src/display/`
  (sin PPS en ningún sitio — gap reconocido A2 §3.2; su DSC 8bpp/10bpc/800×24 coincide
  con el nuestro).
