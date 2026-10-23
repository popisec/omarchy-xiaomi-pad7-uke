# PANEL-REVISION-A1 — Evidencia consolidada de los boots 14-15 oct (2026-10-15)

> Informe de auditoría de evidencia, SOLO lectura local (tablet en fastboot; cero comandos al
> dispositivo). Fuentes: ledger del hermano `~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md`
> (entradas #640–#650, líneas 13542–13750), docs de `build/gates/revision/PIPELINE-PANEL-20261014/`,
> `docs/historia/ESTADO-VIVO.md`, `NOTAS-OMARCHY.md`, los scripts `build/gates/flash-l6*.sh`/`flash-l7*.sh` y el
> árbol vivo `build/kernel-pokes/k52-L16-tree`.
> **Nota sobre capturas crudas**: los vuelcos de los boots L68–L71 se hicieron en la TABLET
> (`/root/kmsg-l71.txt` vía `cat /dev/kmsg` dentro del SSH del script; `flash-l71-gated.sh:33-50`).
> **No existe ninguna captura kmsg/ACM de L68–L71 en el disco del PC** (`out/` llega hasta el 14-oct);
> los valores medidos que se listan abajo provienen del ledger (transcripción del operador en
> caliente) y del PHY-LANE-RATE para L67. Todo sha citado ha sido re-verificado con `sha256sum`
> contra `build/bootimg/` (coinciden, ver §1).

---

## 1. Cronología de los boots 14-15 oct (una fila por boot)

| # | Boot | Cambio (1 variable) | sha256 boot (100663296 B) | Resultado medido | Valor clave |
|---|------|--------------------|---------------------------|------------------|-------------|
| #634 | L57 (14-oct ~21:1x) | PWM KTZ (UKE-L56) + sin `mem=2048M` | `ebe94093…d068c2b82` | **PASA — escritorio Omarchy EN PIE + ILUMINADO**; `MemTotal 7,2 GiB`; `UKE-L56` a 4,27 s | luz automática; pero pantalla **sin contenido** (dato dueño: siempre fue negra) — ledger:13450 |
| #636-637 | L58 (14-oct ~21:5x) | L57 + zram (CONFIG_ZRAM=y) | `763d7869…08208550` | OK: 7,2 GiB, luz, zram 4 GiB lz4 | auditoría userspace/DRM EXIMIDA (FB XR24 con contenido real, media R117/G49/B114) — ledger:13503 |
| #640 | L62 (14-oct ~23:0x) | PPS con dims por link (1600×2136) | `d52f5967…19f90f260` | **PARCIAL**: `UKE-L62: PPS dims=1600x2136 por link` + commit K47×4; pantalla SIGUE NEGRA | dims eran bug real (3200 vs 1600) pero no causa única — ledger:13542/13552 |
| #641 | L63 (14-oct ~23:1x) | PPS post-0x29 (`.enable`) + carga glink/ucsi `=y` | `1d7b440f…244ee109` | **FALLA — wedge de arranque** («rebooteando, volvió a fallar»); el test de pantalla NO se ejecutó | el wedge NO es solo battmgr: denominador = `pmic_glink/ucsi =y` — ledger:13562/13576 |
| #642 | L64 (14-oct ~23:4x) | display-only (kernel L63 + config L62, carga `=m`) | `84bc0e44…4db8cfa231` | Arranca ✓; modetest commit OK (3200×2136@120, K47×4) + `UKE-L63: PPS post-0x29 enviada (dims=1600x2136, err=0)`; **pantalla sin contenido** | **rama PPS (pre+post-0x29) CERRADA** — ledger:13586/13596 |
| #643 | L66 (15-oct ~01:3x) | ADSP icc: revert L19 + dtbo s288 `02d403c5…702dfb` | `1aa5a1f1…2472f5b432` | **FALLA (refuta icc)**: `failed to authenticate image and release reset` → -22; battmgr `-EAGAIN` | ADSP sigue sin arrancar — ledger:13618/13629 |
| #644 | (0-flash, 15-oct ~01:5x) | fix `/lib/firmware/adsp.b40` corrupto (`a2057b8c…`→bueno `42c86837…`) | — (copia de fichero, 0 slots) | **LA TABLET CARGA**: `adsp is now up` + PDR `charger_pd` + **`Charging` 1,04 A / 3.244 V** | drivers/DT exonerados — ledger:13636 |
| #645 | (operativo, 15-oct ~02:0x) | apagado limpio (2,856 V cap 0) | — | paso-0: `pmxr2230_l19` ENABLED use=1 2600 mV (vci vivo); `uke_panel_vsp/vsn` enabled 5800 mV; sin sesión ⇒ `dsi*_pll_out_dsiclk`=0 Hz (byte-clock NO medible) — ledger:13647 |
| #646 | L67 (15-oct ~02:1x, PRE) | BTA readback (10 lecturas DCS LP post-PPS en `o82_enable`) | `56e7b1e5…15580f4d79` | **NO flasheado esa noche** (sin fastboot); crítica: GO CONDICIONAL, dirección devmem corregida a `0xae94024` — ledger:13659; CRITICA-L67-20261015.md:24-34 |
| — | **L67 FLASHEADO (mañana 15-oct)** | el mismo L67 | `56e7b1e5…` (re-verify ✓) | **DDIC MUDO A READS**: 20 DCS-reads (0x0A/0B/0C/0D + 0x04 ×2 links) post-PPS, vídeo ON → **todas `ret=0`, 0 bytes, ambos links**. PLLs lock: vco 951,35 M, byte0 118,919 M, pclk 158,558 M (= vendor), 0 underruns, rails on, KTZ luz OK, writes `err=0` | PHY-LANE-RATE-20261015.md:3-5 |
| #647 | L68 (15-oct ~10:3x) | lecturas BTA con **VIDEO OFF** (toggle `msm_dsi_host_video_engine_set`) + readback ACTIVE_H | `0df71b56…02fdaa46` | lecturas **ret=0 se mantienen en ambos contextos** (vídeo ON y OFF) — «DDIC mudo a reads» (conclusión #650) | + primer dato ACTIVE_H vía dmesg — ledger:13676; sha verify ✓ |
| #648 | **L69** (15-oct ~10:5x) | FIX INTF DSC **/24** (Koskovich) SOLO en el lado DPU | `a986950f…ad398c6ab` | **EMPEORA**: flood `S4-DIAG` (dmesg saturado, marcadores evitados por evicción), **underrun 1929/1929 (1:1 con vsync) en ambos intf**; DSI seguía 30-based (ACTIVE_H 427 + byte 118,9) | conclusión: feed INTF, ACTIVE_H y byte clock deben ir en el MISMO mundo — ledger:13686/13696 |
| #649 | **L70** (15-oct ~11:0x) | ALL-30: revert /24 + **byte-clock ×30** (`bpp = bpc*3`) | `f2e820d2…169963662` | byte **148,648 MHz medido en vivo** + `ACTIVE_H=0x01cb0020` (427, widebus=1); **flood continuo** `FIFO_STATUS=dddd1011`; root 4G al 100%, tumbó uke-adsp; `adsp.b40` corrupto OTRA vez (repuesto + `sync`) | vendor = «mundo 24» (INTF /24 + H 534) + byte ×30 — ledger:13705/13716; sha verify ✓ |
| #650 | **L71** (15-oct ~11:3x) | MUNDO 24 COMPLETO: INTF /24 + **widebus OFF** (ACTIVE_H→534) + byte ×30 | `5e13addf…5109ff0d89` | Los 3 registros del vendor CLAVADOS (ver §2); **flood persiste (143k líneas/20 s); causa identificada: el toggle L68**; pantalla sigue sin contenido | ledger:13730/13741; sha verify ✓ |
| — | **L72** (PENDIENTE de flash) | L71 **sin toggle L68** + `pr_err_ratelimited` en S4-DIAG | aún sin generar | Estado en disco (11:3x): árbol vivo ya lleva los cambios (toggle retirado, ratelimit puesto); `k52L72-build/` creado 11:33-11:35 **en compilación (sin Image.gz aún)**; `flash-l72-gated.sh:8` con `EB=SHA_PENDIENTE` (bloqueo de seguridad) | este informe |

Slots: `a=3` con hemorragia documentada (#640; cada arranque resta 1; `qbootctl` pendiente). Carga preservada desde L66: ADSP running + PDR + Charging (L71 midió 1,098 A).

---

## 2. «Verdad medida en vivo» de L71 (todos los valores)

Fuente primaria: ledger `FLASH-LEDGER.md:13741-13750` (Resultado #650, captura `/dev/kmsg` de 20 s
según `flash-l71-gated.sh:33-40`), contrastado con los valores de referencia del vendor
(RE-ANDROID-GAPS-20261015.md §3).

| Magnitud | Valor medido en L71 | Valor vendor | Fuente/cita |
|---|---|---|---|
| Marcador widebus OFF | `UKE-L71: widebus desactivado (mundo 24 del vendor)` | — | ledger:13742; código §5f |
| ACTIVE_H | **`0x02360020`** (H=534) | `0x02360020` (H=534) — EXACTO | ledger:13742 |
| ACTIVE_V | **`0x08ec0094`** (148‖2284) | `0x08EC0094` — idéntico en ambas hipótesis (ancla de mapa) | ledger:13742; CRITICA-L67 §B1 |
| TOTAL | **`0x090502a6`** | **EL DEL VENDOR EXACTO** (antes con H=427 daba `0x0905023b`) | ledger:13743 |
| Byte clock | **148,648 MHz** (clk_summary) | 148,645 MHz (vendor ×30) | ledger:13743/13745 |
| INTF divisor DSC | `/24` (`L71-intf24` activo) | /24 (Koskovich) | ledger:13733-13736 |
| Underruns INTF | **1/1** (en intf0/intf1) | — (L69 dio 1929/1929; L67/L68 con /30 dieron 19) | ledger:13743; #648 |
| pclk (referencia L67) | 158,558 MHz = vendor 158.558.666 Hz (Δ266 Hz) | igual | PHY-LANE-RATE:34-38 |
| Carga | `Charging` 1,098 A | — | ledger:13743 |
| Flood S4-DIAG | **persiste: 143k líneas en 20 s** | — | ledger:13745 |
| Pantalla | **sin contenido** (negro con luz) | vendor enciende contenido | ledger:13741 |
| Init DCS | byte-idéntico al vendor (cerrado antes, ANGULO-DDIC C3) | — | ANGULO-DDIC-20261015.md:13 |
| PLL/PHY lock | vco 951,35 M / byte 118,919 M (en L67); en L70/L71 byte 148,648 | 1,189 Gbps/lane (C/8) | PHY-LANE-RATE:5-6,36-38; ledger:13743 |

Lectura conjunta: con L71 el host programa exactamente los tres registros que mide el vendor
(ACTIVE_H/TOTAL/byte-clock), el feed del INTF es coherente (underruns 1/1) y aun así **no hay
contenido**: el residuo del problema ya no está en esos registros.

---

## 3. El flood: síntomas exactos, causa identificada y evidencia

**Síntomas medidos.**
- L69: flood de `S4-DIAG` que saturó el dmesg — «los marcadores daban 0 por evicción, no por
  ausencia»; `underrun: 1929/1929` (1:1 con vsync) en ambos intf (ledger:13696-13703).
- L70/L71: «flood DSI continuo (`FIFO_STATUS=dddd1011`: VIDEO_MDP over+underflow + HS FIFOs)
  saturó el dmesg/journal y **llenó el root de 4G al 100%**, tumbando uke-adsp (sin carga)»
  (ledger:13717-13719). En L71: **143k líneas en 20 s** (ledger:13745).

**Causa identificada: el «toggle L68».** El bloque añadido en L68 dentro de `o82_enable`
(apagar VID_MODE_EN → 20 lecturas → re-encender, ver §5a) **deja el FIFO del DSI en error
perpetuo**:
- Evidencia de contraste (ledger:13745-13749): **L67 (sin toggle) = limpio; L68/L69/L70/L71
  (con toggle) = flood en CUALQUIER mundo** (mundo 30 en L68/L70, mundo 24 en L71: el flood es
  independiente de la configuración de timing). Las lecturas `ret=0` se mantienen en ambos
  contextos (DDIC mudo a reads).
- Mecanismo anotado en #649 (ledger:13720-13721): «Flood = handler DSI re-armando IRQ (niveles)
  + print S4-DIAG sin ratelimit; el `sw_reset` del worker no se dispara (mira CMD_MDP, no VIDEO)».
- El código actual confirma ambos extremos: `dsi_fifo_status()` imprime con `pr_err` (sin
  ratelimit) y re-arma la IRQ al final de `dsi_err_worker()` (`dsi_intr_ctrl(…DSI_IRQ_MASK_ERROR, 1)`)
  — `dsi_host.c:1700-1721` y `1641-1652`. El `dsi_sw_reset` solo salta con
  `DSI_ERR_STATE_MDP_FIFO_UNDERFLOW` (`dsi_host.c:1643-1645`).
- L72 (ya retirado el toggle en el árbol vivo, `panel-xiaomi-o82-dualdsi.c:686-691`) añade
  `pr_err_ratelimited` en el print FIFO (`dsi_host.c:1708-1711`) como mitigación secundaria.

**Incidente operativo derivado** (#649): el flood llenó el root al 100% y volvió a corromper
`adsp.b40` «misma talla, contenido distinto, mtime viejo = corrupción silenciosa en disco»
(ledger:13718-13720); repuesto y verificado `42c86837…` + `sync` incorporado al procedimiento.
Los flashes L70/L71 llevan **guarda anti-flood**: DPMS off si `dmesg | grep -c S4-DIAG` > 1500
(`flash-l71-gated.sh:50-52`).

---

## 4. Estado de las lecturas BTA/DCS (qué se probó, qué devolvió el DDIC)

| Test | Contexto | Comandos | Resultado |
|---|---|---|---|
| L67 (mañana 15-oct) | vídeo ON, post-PPS, en `o82_enable` | 0x0A GET_POWER_MODE, 0x0B, 0x0C, 0x0D (1 B) + 0x04 GET_DISPLAY_ID (3 B) × 2 links = 20 lecturas LP | **todas `ret=0`, 0 bytes, ambos links** (PHY-LANE-RATE:3-5). `ret=0` = el host no recibe nada; «err=0» de los writes solo prueba el DMA del host, no ACK (CRITICA-RONDA2 §2, citado en docs/historia/revision/PIPELINE-PANEL-20261014/L67-PREP.md:13-14) |
| L68 | MISMO bloque con **motor de vídeo parado** (toggle VID_MODE_EN off→lecturas→on, `usleep 100-200`) | las mismas 20 | **`ret=0` se mantiene en ambos contextos** — el «sordo» no era contención de vídeo (ledger:13747-13749); criterio de L68 («si OFF responde y ON no ⇒ contención», ledger:13681) resultó NEGATIVO en ambas ramas |
| Vendor (referencia) | splash | lockdown | «Panel not initialized», `cell_id rc=-22` — el vendor TAMBIÉN falló sus lecturas en vivo (ANGULO-DDIC:11 vía PHY-LANE-RATE:6) |

Conclusiones soportadas:
1. El DDIC está **mudo a reads** con el enlace tal como lo programa mainline, con vídeo ON y OFF,
   en ambos links — o el enlace/PHY-RX no está como él espera, o el DDIC está dormido/en un estado
   que no respuesta BTA (ANGULO-DDIC §2.4: en AMOLED negro-con-luz ⇒ probablemente despierto y
   escaneando negro [H]).
2. Candidata nº1 para el sordo: los **14 TIMING_CTRL RX de la PHY** calculados @951 M vs los fijos
   del DT vendor (P≈0,4) — PHY-LANE-RATE:23-27. Widebus/ACTIVE_H explica «sin contenido», NO el
   sordo (PHY-LANE-RATE:24).
3. DSC/PPS: la rama PPS está CERRADA como causa única (L62/L64: PPS pre+post con dims correctas,
   `err=0`, negro); el RE Android demostró que el vendor envía la PPS por vía única `0x0A`
   (128 B) sin `compression_mode_ext` (RE-ANDROID-GAPS §2).

---

## 5. Código exacto en el árbol vivo (con fichero:línea)

Árbol: `~/proyectos/omarchy-uke/build/kernel-pokes/k52-L16-tree` (estado L72:
toggle retirado, ratelimit puesto; los hunks L68-L71 siguen exactos salvo el bloque retirado,
cuya forma flasheada está en `PIPELINE-PANEL-20261014/l68-videooff-read.diff` y `l69-intf24.diff`).

### (a) El «toggle L68» — `drivers/gpu/drm/panel/panel-xiaomi-o82-dualdsi.c`

Estado ACTUAL (L72): el bloque fue RETIRADO con comentario en las líneas 686-691:

```c
	/*
	 * L72 (15-oct): el bloque L68 (apagar/encender VID_MODE_EN + lecturas
	 * OFF) queda RETIRADO: el toggle dejaba el FIFO del DSI en error
	 * perpetuo (flood S4-DIAG en L68/L69/L70/L71 con CUALQUIER config).
	 * Las lecturas del bloque L65 (video ON) se mantienen: dan ret=0 sin
	 * side effects. El readback ACTIVE_H (dsi_host.c) se mantiene.
	 */
```
(ubicación: tras el bloque L65, `panel-xiaomi-o82-dualdsi.c:686-691`, justo antes del
`return dsi_ctx.accum_err` de la `o82_enable` que empieza en `:610`).

Lo que se FLASHEÓ en L68→L71 (forma exacta, `l68-videooff-read.diff:62-100`):

```c
	uke_poke("L68-ve");
	msm_dsi_host_video_engine_set(ctx->dsi[0]->host, false);
	msm_dsi_host_video_engine_set(ctx->dsi[1]->host, false);
	usleep_range(100, 200);
	pr_info("UKE-L68: video engine OFF; leyendo DDIC (contexto vendor)\n");
	{
		static const u8 l68_cmds[] = { 0x0A, 0x0B, 0x0C, 0x0D };
		int li, ci;

		for (li = 0; li < 2; li++) {
			for (ci = 0; ci < ARRAY_SIZE(l68_cmds); ci++) {
				u8 val = 0;
				ssize_t r = mipi_dsi_dcs_read(ctx->dsi[li],
							      l68_cmds[ci], &val, 1);
				pr_info("UKE-L68: DCS read 0x%02X link%d = 0x%02X (ret=%zd)\n",
					l68_cmds[ci], li, val, r);
			}
		}
		for (li = 0; li < 2; li++) {
			u8 id[3] = { 0, 0, 0 };
			ssize_t r = mipi_dsi_dcs_read(ctx->dsi[li],
						      MIPI_DCS_GET_DISPLAY_ID, id, 3);
			pr_info("UKE-L68: DCS read 0x04 link%d = 0x%02X 0x%02X 0x%02X (ret=%zd)\n",
				li, id[0], id[1], id[2], r);
		}
	}
	msm_dsi_host_video_engine_set(ctx->dsi[0]->host, true);
	msm_dsi_host_video_engine_set(ctx->dsi[1]->host, true);
	pr_info("UKE-L68: video engine ON de vuelta\n");
```

El helper que usa (VIVE en el árbol, `drivers/gpu/drm/msm/dsi/dsi_host.c:1214-1230`):

```c
/* L68 (uke): parar/arrancar SOLO el motor de video del controlador DSI.
 * Necesario para leer al DDIC en el contexto del cold-path vendor (108 DCS
 * con vid_engine OFF); con video ON las lecturas BTA devolvieron ret=0 en
 * ambos links (L67). No toca IRQs ni ENABLE: solo VID_MODE_EN. */
void msm_dsi_host_video_engine_set(struct mipi_dsi_host *host, bool on)
{
	struct msm_dsi_host *msm_host = to_msm_dsi_host(host);
	u32 ctrl = dsi_read(msm_host, REG_DSI_CTRL);

	if (on)
		ctrl |= DSI_CTRL_VID_MODE_EN;
	else
		ctrl &= ~DSI_CTRL_VID_MODE_EN;
	dsi_write(msm_host, REG_DSI_CTRL, ctrl);
	wmb();
}
EXPORT_SYMBOL_GPL(msm_dsi_host_video_engine_set);
```
Declaración `extern` en el panel: `panel-xiaomi-o82-dualdsi.c:41`.

### (b) Los prints S4-DIAG — `drivers/gpu/drm/msm/dsi/dsi_host.c`

- `dsi_wait4video_done()` — `dsi_host.c:1259-1265`:
```c
		/* S4-DIAG (arranque): distingue "motor parado" de "motor colgado". */
		u32 st0 = dsi_read(msm_host, REG_DSI_STATUS0);
		u32 fifo = dsi_read(msm_host, REG_DSI_FIFO_STATUS);
		DRM_DEV_ERROR(dev,
			"S4-DIAG: wait for video done timed out, id=%d STATUS0=%08x FIFO=%08x (BUSY=%d)\n",
			msm_host->id, st0, fifo,
			!!(st0 & DSI_STATUS0_VIDEO_MODE_ENGINE_BUSY));
```
- Timeout de CMD-DMA — `dsi_host.c:1525-1531`:
```c
			/* S4-DIAG (arranque): foto del stall en el instante del fallo. */
			u32 st0 = dsi_read(msm_host, REG_DSI_STATUS0);
			u32 fifo = dsi_read(msm_host, REG_DSI_FIFO_STATUS);
			u32 tout = dsi_read(msm_host, REG_DSI_TIMEOUT_STATUS);
			pr_err("S4-DIAG: %s: CMD_DMA_DONE timeout, id=%d len=%d STATUS0=%08x FIFO=%08x TIMEOUT=%08x\n",
				__func__, msm_host->id, len, st0, fifo, tout);
```
- `dsi_err_worker()` — `dsi_host.c:1640-1652` (aquí vive el sw_reset condicionado):
```c
	/* S4-DIAG (arranque): atribuir el rafaga a su link en dual-DSI. */
	pr_err_ratelimited("%s: id=%d status=%x\n", __func__, msm_host->id, status);
	if (status & DSI_ERR_STATE_MDP_FIFO_UNDERFLOW)
		dsi_sw_reset(msm_host);
	...
	/* enable dsi error interrupt */
	dsi_intr_ctrl(msm_host, DSI_IRQ_MASK_ERROR, 1);
```
- `dsi_timeout_status()` — `dsi_host.c:1676-1679`:
```c
		/* S4-DIAG (arranque): el agregado status=5 no dice QUE timeout. */
		pr_err("S4-DIAG: %s: id=%d TIMEOUT_STATUS=%08x\n",
			__func__, msm_host->id, status);
```
- `dsi_fifo_status()` — `dsi_host.c:1706-1715` — **el print del flood; L72 le pone ratelimit**:
```c
		/* S4-DIAG (arranque): el agregado status=4 no dice QUE fifo.
		 * L72: ratelimit (el flood de L68-L71 lleno el root de 4G). */
		pr_err_ratelimited("S4-DIAG: %s: id=%d FIFO_STATUS=%08x\n",
			__func__, msm_host->id, status);
		if (status & DSI_FIFO_STATUS_CMD_MDP_FIFO_UNDERFLOW)
			msm_host->err_work_state |=
					DSI_ERR_STATE_MDP_FIFO_UNDERFLOW;
```

### (c) Marcadores UKE-L68 / L70 / L71

- **`UKE-L68: ACTIVE_H`** (readback de timing en `dsi_timing_setup`) — `dsi_host.c:1119-1126`:
```c
		/* L68 (uke): readback de los registros de timing escritos; el
		 * discriminante widebus (CRITICA-L67/RE-GAPS §3) espera
		 * ACTIVE_H=0x01CB0020 (widebus, H=427) o 0x02360020 (H=534). */
		if (msm_host->dsc)
			pr_info("UKE-L68: ACTIVE_H=0x%08x ACTIVE_V=0x%08x TOTAL=0x%08x widebus=%d\n",
				dsi_read(msm_host, REG_DSI_ACTIVE_H),
				dsi_read(msm_host, REG_DSI_ACTIVE_V),
				dsi_read(msm_host, REG_DSI_TOTAL),
				msm_dsi_host_is_wide_bus_enabled(&msm_host->base));
```
- **`L70-byteclk`** — `dsi_host.c:660-661` (dentro de `dsi_byte_clk_get_rate`, ver (d)).
- **`UKE-L71`** (widebus OFF) — `dsi_host.c:814-825` (ver (f)).
- **`L71-intf24`** — `dpu_encoder_phys_vid.c:140` (ver (e)).
- (Los `UKE-L68: DCS read…` del bloque OFF viven hoy solo en el diff `l68-videooff-read.diff`;
  en el árbol vivo fueron retirados con el bloque, §5a.)

### (d) `dsi_byte_clk_get_rate` — hunk byte-clock ×30 — `drivers/gpu/drm/msm/dsi/dsi_host.c:639-673`

```c
unsigned long dsi_byte_clk_get_rate(struct mipi_dsi_host *host, bool is_bonded_dsi,
				    const struct drm_display_mode *mode)
{
	struct msm_dsi_host *msm_host = to_msm_dsi_host(host);
	u8 lanes = msm_host->lanes;
	u32 bpp = mipi_dsi_pixel_format_to_bpp(msm_host->format);
	unsigned long pclk_rate = dsi_get_pclk_rate(mode, msm_host->dsc, is_bonded_dsi);
	unsigned long pclk_bpp;

	/*
	 * L70 (uke, 15-oct-2026): con DSC, el byte clock usa la profundidad DSC
	 * (bpc*3 = 30 con 10bpc), no el contenedor RGB888 (24). El vendor r15
	 * mide byte=148,645 MHz = pclk*30/32 (= panel-clockrate/8 del DT,
	 * 1,189 Gbps/lane); mainline daba 118,92 = *24/32 y el enlace no drenaba
	 * lo que el INTF alimenta (underrun medido). Fuente: linuxgamer
	 * 0011-dsi-dsc-input-depth-byte-clock.patch via MCC45TR senemos
	 * patches/display/7.2.10/0001-...patch (rotulo "not hardware validated"
	 * en su origen; aqui se coteja contra el vendor medido). L69 (/24 en el
	 * INTF) queda REVERTIDO: solo cambiaba un lado (medido: FIFO errors
	 * constantes, underrun 1:1).
	 */
	if (msm_host->dsc) {
		uke_poke("L70-byteclk");
		bpp = msm_host->dsc->bits_per_component * 3;
	}

	if (lanes == 0) {
		pr_err("%s: forcing mdss_dsi lanes to 1\n", __func__);
		lanes = 1;
	}

	/* CPHY "byte_clk" is in units of 16 bits */
	if (msm_host->cphy_mode)
		pclk_bpp = mult_frac(pclk_rate, bpp, 16 * lanes);
	else
		pclk_bpp = mult_frac(pclk_rate, bpp, 8 * lanes);
```
(Nótese que `dsi_adjust_pclk_for_compression` en `:589-615` — el pclk del INTF — sigue con el
`/(bpc*3)=30` original; el /24 del INTF se aplicó en el lado DPU, ver (e).)

### (e) Fix INTF /24 de Koskovich — `drivers/gpu/drm/msm/disp/dpu1/dpu_encoder_phys_vid.c:125-142`

```c
	/*
	 * L71 (uke, 15-oct-2026): divisor de INTF DSC /24 = el mundo 24 del
	 * vendor (Koskovich: "24 bits per pclk always"). Con bpc=10 el /30 daba
	 * FIFO errors; el vendor escribe H=534 = /24. Va ACOMPANADO de widebus
	 * OFF en DSI (ACTIVE_H 534) + byte x30 (148,6) = los 3 registros del
	 * vendor alineados.
	 */
	if (phys_enc->hw_intf->cap->type != INTF_DP && timing->compression_en) {
		struct drm_dsc_config *dsc =
		       dpu_encoder_get_dsc_config(phys_enc->parent);
		/*
		 * TODO: replace drm_dsc_get_bpp_int with logic to handle
		 * fractional part if there is fraction
		 */
		uke_poke("L71-intf24");
		timing->width = timing->width * drm_dsc_get_bpp_int(dsc) / 24;
		timing->xres = timing->width;
		timing->dce_bytes_per_line = msm_dsc_get_bytes_per_line(dsc);
	}
```
(La versión L69 flasheada ese mediodía era idéntica salvo el marcador `L69-intf24` y el
comentario — `l69-intf24.diff:25-31`.)

### (f) Widebus OFF UKE-L71 — `drivers/gpu/drm/msm/dsi/dsi_host.c:814-826`

```c
bool msm_dsi_host_is_wide_bus_enabled(struct mipi_dsi_host *host)
{
	/*
	 * L71 (uke, 15-oct-2026): widebus DESACTIVADO = mundo 24 del vendor.
	 * Medido: nuestro ACTIVE_H=0x01CB0020 (427, widebus/30) vs vendor 534
	 * (0x02360020, /24); byte 148,6 (x30) + INTF /24 (Koskovich) cierran el
	 * mundo: DPU alimenta 3 B/pclk, DSI recibe 3 B/pclk (sin widen) y el
	 * enlace drena 3,75 B/pclk (holgura). El mundo 30 (L70) tambien floodeo
	 * FIFO: el vendor evita widebus en DSI.
	 */
	pr_info_once("UKE-L71: widebus desactivado (mundo 24 del vendor)\n");
	return false;
}
```

---

## 6. Preguntas abiertas que la evidencia NO responde (para la fase de revisión de código)

1. **Mecanismo del toggle→flood.** ¿Por qué un clear/set de `DSI_CTRL_VID_MODE_EN` en caliente
   deja el FIFO en error perpetuo en CUALQUIER mundo? El handler re-arma la IRQ de nivel
   (`dsi_host.c:1650-1651`) y `dsi_sw_reset` solo cubre `CMD_MDP` FIFO underflow
   (`dsi_host.c:1643-1645`) — no hay clear/recovery específico para VIDEO. Revisar si la
   re-activación necesita resincronizar el MDP (FLUSH) o si el estado FIFO debe limpiarse
   antes de re-unmask.
2. **L72 sin toggle: ¿desaparece el flood de raíz o solo se enmascara con el ratelimit?**
   El ratelimit (`dsi_host.c:1710`) evita llenar el disco, pero si el FIFO queda en error con
   el motor funcionando, los underruns reales seguirán. El gate del flash debe medir
   `FIFO_STATUS` crudo, no solo contar líneas.
3. **DDIC mudo a BTA (ret=0 en 40 lecturas, ON y OFF).** Candidata nº1: los 14 `TIMING_CTRL`
   RX de la PHY calculados (`dsi_phy.c`) vs los fijos del DT vendor (`timing@120`) —
   PHY-LANE-RATE:23-27. La revisión debe decidir si se programan los bytes del DT
   (quirk `USE_DT_TIMINGS`) antes de cualquier otro cambio.
4. **Coherencia del «mundo 24» con upstream.** Con `msm_dsi_host_is_wide_bus_enabled()=false`,
   ¿queda programado `DSI_VID_CFG0_DATABUS_WIDEN` en algún sitio? Baryshkov: "48-bit bus width
   should be used when DSC is enabled" (EXTERNO-DSC-NEGRO:11) — el vendor NO usa widebus en DSI;
   verificar que el MDP (3 B/pclk, INTF /24) y el DSI (3 B/pclk, sin widen) y el enlace
   (3,75 B/pclk, byte ×30) son consistentes como declara el comentario de (f), y qué pasa con
   `WC` (`VIDEO_COMPRESSION_MODE_CTRL`, fix 1/3 de la serie Nie/Marek v6 — EXTERNO-DSC-NEGRO:10,20).
5. **Los 3 fixes de la serie Nie/Marek v6 en 7.2-rc2**: `WC=slice_chunk_size`, `DATABUS_WIDEN`,
   INTF `compression_en` — EXTERNO-DSC-NEGRO:20 pide verificar con `git log` que están; no se
   ha hecho aún (la serie explica exactamente «PPS OK + negro»).
6. **`dsi_adjust_pclk_for_compression` sigue en /(bpc*3)=30** para el PCLK (`dsi_host.c:589-615`)
   mientras el INTF ahora divide /24: ¿es intencional (el vendor mide pclk 158,558 M = C/7,5)
   o falta el segundo lado del «mundo 24»? Los underruns 1/1 de L71 no lo discriminan.
7. **La asimetría dual-link** en los reads (CRITICA-L67 I3: link0 manda) nunca se juzgó por
   separado en la evidencia conservada; el dmesg crudo quedó en la tablet.
8. **Corrupción silenciosa de disco** (`adsp.b40` dos veces: #644 y #649): ¿causa el flood el
   llenado y la corrupción, o hay un problema de UFS subyacente (precedente glitch #629)? El
   sweep completo de `/lib/firmware` contra staging sigue pendiente (ledger #644).
9. **`docs/historia/revision/PIPELINE-PANEL-20261014/PANTALLA-COMPLETA-2.md` corrupto** (todo NULs, también en git): reconstruir o borrar
   (docs/historia/revision/PIPELINE-PANEL-20261014/L67-PREP.md:59-60). Y el estado real del artefacto L72: build en curso a las 11:3x, sin
   `Image.gz` ni boot.img; `flash-l72-gated.sh` aborta con `EB=SHA_PENDIENTE` (correcto).
10. **Slots**: `slot-retry-count:a=3` y hemorragia por boot (#640); `qbootctl` sigue pendiente
    — riesgo operativo para el ÚNICO flash permitido (L72).

---

## 7. Ficheros de referencia usados

- Ledger: `~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md` (#640:13542, #641:13562,
  #642:13586, #643:13618, #644:13636, #645:13647, #646:13659, #647:13676, #648:13686, #649:13705,
  #650:13730)
- `~/proyectos/omarchy-uke/build/gates/revision/PIPELINE-PANEL-20261014/`:
  `docs/historia/revision/PIPELINE-PANEL-20261014/L67-PREP.md`, `CRITICA-L67-20261015.md`, `RE-ANDROID-GAPS-20261015.md`, `ANGULO-DDIC-20261015.md`,
  `PHY-LANE-RATE-20261015.md`, `EXTERNO-DSC-NEGRO-20261015.md`, `docs/historia/revision/PIPELINE-PANEL-20261014/EXTERNO-PAD7-CLIFFS-20261015.md`,
  `H2-CRASH-CAPTURADO-20261014.md`, `docs/historia/revision/PIPELINE-PANEL-20261014/BRIEF.md`, `l68-videooff-read.diff`, `l69-intf24.diff`
- `~/proyectos/omarchy-uke/docs/historia/ESTADO-VIVO.md:15-31` y `NOTAS-OMARCHY.md:4802-4831` (última
  entrada 15-oct noche)
- Scripts: `docs/historia/gates-palawan/flash-l67-gated.sh` … `flash-l72-gated.sh` (checklist de captura en vivo)
- Árbol: `build/kernel-pokes/k52-L16-tree` (citas §5)
