# PREP-MINUCIAS — 3 minucias "panel sordo" preparadas (verificación + hunk exacto, SIN aplicar)

**Fecha:** 13-oct-2026. **Alcance:** solo lectura + redacción. NO se modificó ningún árbol,
NO se compiló, NO se flasheó, NO hay commit. Los hunks de abajo van al próximo build/dtbo.

**Árbol vivo determinado:** `build/kernel-pokes/k52L39-tree` (no L33).
Evidencia: `stat` del panel — L33 `2026-10-12 20:32`, L39 `2026-10-13 16:55`
(phy `19:27`); `diff -u` L33→L39 muestra backlight-externo + G5 (`lane_ctrl0 0x1f→0x15`)
+ G7 (SSC). Coherente con `L39-PLAN-20261013.md §6` (L39 = L33 + L38 + G5 + G6, más L39b/G7
posteriores). Todas las citas de líneas del driver/host son del **k52L39-tree** salvo aviso.

**Fuentes DT:** overlay vivo `build/gates/patches/k52L39-fuentes/fase4-display.dts`
(idéntico el panel al del árbol: `diff -q` fuentes↔árbol = IDENTICOS);
base vendor `build/evidencia/stock-dt/stock2-Cliffs7P-uke.dts`.

---

## (a) `vci-supply` (rail L19, 2,6 V) — AUSENTE en driver vivo Y en DT

### Verificación (cita fichero:línea)

1. **Driver vivo NO tiene consumidor vci.** `k52L39-tree/.../panel/panel-xiaomi-o82-dualdsi.c`:
   struct solo `supplies` (:54), tabla `o82_supplies[]` con 3 entradas
   `vddil8b/vsp/vsn` (:85-88), `o82_power_on()` solo vota esas 3 (:297-340),
   probe solo `devm_regulator_bulk_get_const` (:681-684). `grep -n vci` = **0 hits**.
   Igual en `k52L33-tree` (0 hits; tabla :87-90, probe :712-715).
2. **El `get_optional("vci")` existió y se perdió entre L29→L33.**
   `k52L27-tree` (y L29) sí lo tienen: campo `struct regulator *vci` (:56-59),
   voto en `o82_power_on()` con `set_voltage(2600000,3544000)` + enable + 2 ms (:309-326),
   `ctx->vci = devm_regulator_get_optional(dev, "vci")` con `L27-vci-absent` (:721-732).
   En L33/L39 ese bloque no existe: **el driver "listo" que cita
   `ANDROID-DSI-PROFUNDO §4.3` corresponde a L27, no al árbol vivo.**
3. **DT overlay vivo NO declara `vci-supply`.** `fase4-display.dts:358-364` (`panel@0`):
   solo `vddil8b-supply = <&L8B>; vsp-supply; vsn-supply`. `grep -c vci-supply` = 0
   en todo el overlay; en el resto del repo solo aparece en bindings genéricos (yaml),
   ningún DT propio lo declara.
4. **El rail existe en la base vendor con phandle usable por el overlay.**
   `stock2-Cliffs7P-uke.dts:6956`: `pmxr2230_l19: L19B: regulator-pmxr2230-l19`,
   `min 0x27ac40 (=2600000, 2,6 V)`, `max 0x3613c0 (=3544000)`, `init 0x27ac40`,
   `phandle 0x150` (= el `vci-supply=0x150` de Android citado en §4.1). Símbolo
   `L19B` en `:20727` — mismo mecanismo que el `&L8B` que el overlay ya usa (`:110`,`:362`),
   luego el fragmento debe referenciar **`&L19B`**.

### Hunk exacto (para el próximo dtbo + driver)

**Hunk 1 — DT (el que pide el encargo), listo para pegar** como `fragment@10`
(o extendiendo `panel@0` en `fragment@6`; se propone fragmento separado = 1 variable):

```dts
	/* vci/L19 2,6 V del panel o82 (Android vci-supply=0x150, init 2,6 V,
	 * rango 2,6-3,544 V; stock2-Cliffs7P-uke.dts:6956). Sin esto el voto
	 * opcional del driver es NULL (L27-vci-absent). */
	fragment@10 {
		target-path = "/soc/display-subsystem@ae00000/dsi@ae94000/panel@0";

		__overlay__ {
			vci-supply = <&L19B>;
		};
	};
```

**Hunk 2 — driver (OBLIGATORIO junto al Hunk 1; hoy el vivo no consume `vci`,**
con solo el DT el rail quedaría sin reclamar = no-op). Restaurar el bloque L27
en el vivo (`k52L39-tree/.../panel-xiaomi-o82-dualdsi.c`), 3 sitios (texto literal de L27):

```diff
 --- a/drivers/gpu/drm/panel/panel-xiaomi-o82-dualdsi.c
 +++ b/drivers/gpu/drm/panel/panel-xiaomi-o82-dualdsi.c
 @@ struct o82_panel {
  	struct regulator_bulk_data *supplies;
  	struct gpio_desc *reset_gpio;
 +	/* L27 (§E.2 informe 12-oct): rail vci = pmxr2230 L19 (Android
 +	 * vci-supply=0x150, init 2.6 V). Opcional: el dtbo vivo aun no
 +	 * declara vci-supply; NULL = seguir con los 3 rails. */
 +	struct regulator *vci;
  	/* K49 (#509): vendor declara mi,esd-err-irq-gpio ... */
```

```diff
 @@ static int o82_power_on(struct o82_panel *ctx)
  {
  	uke_poke("K47-pan-pwron");
  	uke_poke("K47-pan-pwr");
  	unsigned int i;
  	int ret;
 +
 +	/* L27 (§E.2 informe 12-oct): rail vci = pmxr2230 L19 (Android
 +	 * vci-supply=0x150, init 2.6 V, rango 2.6-3.544 V; vddio=L8 ya lo
 +	 * cubre supplies[0]). Sin voto de load: el path vendor
 +	 * (dsi_pwr_enable_regulator) no lo pone. Fallo de set_voltage no
 +	 * fatal: se habilita con la del DT. */
 +	if (ctx->vci) {
 +		ret = regulator_set_voltage(ctx->vci, 2600000, 3544000);
 +		if (ret < 0)
 +			pr_warn("UKE-P82: vci: set_voltage 2.6V fallo %d (sigo con la del DT)\n", ret);
 +		ret = regulator_enable(ctx->vci);
 +		if (ret < 0) {
 +			pr_err("UKE-P82: vci: enable FALLO %d\n", ret);
 +			return ret;
 +		}
 +		usleep_range(2000, 2500);
 +		uke_poke("L27-vci-ok");
 +		pr_info("UKE-P82: power_on: vci(L19,2.6V) ENABLED\n");
 +	}
 
  	pr_info("UKE-P82: power_on: inicio (%zu supplies)\n", ARRAY_SIZE(o82_supplies));
```

```diff
 @@ static int o82_probe(struct mipi_dsi_device *dsi)
  	ret = devm_regulator_bulk_get_const(dev, ARRAY_SIZE(o82_supplies),
  					    o82_supplies, &ctx->supplies);
  	if (ret < 0)
  		return dev_err_probe(dev, ret, "failed to get regulators\n");
 +
 +	/* L27 (§E.2 informe 12-oct): vci/L19 opcional (el dtbo vivo aun no
 +	 * lo declara; bulk_get con 4 fallaria el probe). */
 +	ctx->vci = devm_regulator_get_optional(dev, "vci");
 +	if (IS_ERR(ctx->vci)) {
 +		if (PTR_ERR(ctx->vci) == -ENODEV) {
 +			ctx->vci = NULL;
 +			uke_poke("L27-vci-absent");
 +		} else {
 +			return dev_err_probe(dev, PTR_ERR(ctx->vci),
 +					     "failed to get vci regulator\n");
 +		}
 +	}
 
  	/* L27 (§E.3 informe 12-oct): Android NO toca el reset hasta power_on; ... */
```

### Riesgo / nota

- **Corrección al encargo:** la premisa "driver declara, DT ausente" es de L27; en el vivo
  **faltan las dos mitades**. Solo-DT = no-op silencioso; aplicar ambos juntos o nada.
- Riesgo bajo: `get_optional` + `NULL` = comportamiento actual si el DT no llega;
  con DT, un voto enable más en el orden vendor (vci junto a vddio, antes de vsp/vsn).
  Una variable por ciclo; gate `fdtoverlay -i base -o merged overlay` en verde antes de
  flashear (regla AGENTS nº1). No invalida G5/G6.

---

## (b) `MIPI_DSI_CLOCK_NON_CONTINUOUS` — SIGUE puesto en el vivo

### Verificación

`k52L39-tree/.../panel/panel-xiaomi-o82-dualdsi.c:636-641`:

```c
	/* K48-A (#507): lp11-init del vendor — sin CLOCK_NON_CONTINUOUS,
	 * dsi_ctrl_enable (dsi_host.c:909-916) fuerza bitclk HS CONTINUO ... */
	.mode_flags = MIPI_DSI_MODE_VIDEO | MIPI_DSI_MODE_LPM |
		      MIPI_DSI_CLOCK_NON_CONTINUOUS,
```

El comentario dice "sin" pero el flag **está**. Igual en L27 (:671-676), L29 y
L33 (:667-672): la regresión de comentario señalada en `ANDROID-DSI-PROFUNDO §6`
y `ENABLE-COMPARISON H3 (:143-158)` **sigue vigente en el árbol vivo**.
Efecto: con el flag, `dsi_host.c:909-917` salta `LANE_CTRL |= CLKLN_HS_FORCE_REQUEST`
+ `msm_dsi_phy_set_continuous_clock` (verificado en el fuente del vivo).

### Hunk exacto (1 línea + ajuste de comentario; alinear código con su propio comentario)

```diff
 --- a/drivers/gpu/drm/panel/panel-xiaomi-o82-dualdsi.c
 +++ b/drivers/gpu/drm/panel/panel-xiaomi-o82-dualdsi.c
 @@ -636,9 +636,8 @@
  	/* K48-A (#507): lp11-init del vendor — sin CLOCK_NON_CONTINUOUS,
  	 * dsi_ctrl_enable (dsi_host.c:909-916) fuerza bitclk HS CONTINUO en el
  	 * carril de clock desde power_on, ANTES de rieles y reset; el vendor
  	 * tiene LP11 durante toda la secuencia de reset. */
 -	.mode_flags = MIPI_DSI_MODE_VIDEO | MIPI_DSI_MODE_LPM |
 -		      MIPI_DSI_CLOCK_NON_CONTINUOUS,
 +	.mode_flags = MIPI_DSI_MODE_VIDEO | MIPI_DSI_MODE_LPM,
  	.format = MIPI_DSI_FMT_RGB888,
  	.is_dual_dsi = true,
```

### Riesgo / nota

- Riesgo bajo-medio, P0 ya aceptado: una sola variable; es el ciclo H3/H4 del
  `ENABLE-COMPARISON §4` (ciclos 1a→4 antes que este si se sigue ese orden).
  No juntar con (a) ni con H1 en el mismo flash (atribución).
- Nota: con `prepare_prev_first=false` ya aplicado, este flag es el siguiente
  sospechoso de contradecir el contrato `lp11-init` del vendor. `dsi1` hereda
  `mode_flags` por `desc` (`:799`), luego el cambio cubre ambos links.

---

## (c) `byte_clk` pedida vs efectiva — punto de instrumentación localizado

### Verificación

Vivo `k52L39-tree/.../msm/dsi/dsi_host.c:2460-2483`
(`msm_dsi_host_get_phy_clk_req`): `:2468` `calc_clk_rate()` → `:2478-2481`
`clk_req->bitclk_rate = byte_clk_rate ×7/×8`. La `byte_clk_rate` viene de
`dsi_calc_pclk()` (`:662-670`) ← `dsi_byte_clk_get_rate()` (`:639-660`), derivada
del **modo** (pedida), no del OPP redondeado — es el input pendiente de
`L39-PLAN §2-bis (:152-190)`. La efectiva es legible con
`clk_get_rate(msm_host->byte_clk)` (precedentes en el mismo fichero:
`clk_set_rate(msm_host->byte_clk, …)` en `:484`; `clk_get_rate(esc_clk)` en `:680`).

### Hunk exacto (solo traza, cero cambio funcional; registra pedida vs efectiva)

```diff
 --- a/drivers/gpu/drm/msm/dsi/dsi_host.c
 +++ b/drivers/gpu/drm/msm/dsi/dsi_host.c
 @@ -2474,8 +2474,13 @@ void msm_dsi_host_get_phy_clk_req(struct mipi_dsi_host *host,
  	/* CPHY transmits 16 bits over 7 clock cycles
  	 * "byte_clk" is in units of 16-bits (see dsi_calc_pclk),
  	 * so multiply by 7 to get the "bitclk rate"
  	 */
  	if (msm_host->cphy_mode)
  		clk_req->bitclk_rate = msm_host->byte_clk_rate * 7;
  	else
  		clk_req->bitclk_rate = msm_host->byte_clk_rate * 8;
 +	pr_info("UKE-L39B: byte_clk pedida=%lu efectiva=%lu bitclk=%lu (cphy=%d)\n",
 +		msm_host->byte_clk_rate,
 +		msm_host->byte_clk ? clk_get_rate(msm_host->byte_clk) : 0,
 +		clk_req->bitclk_rate, msm_host->cphy_mode);
  	clk_req->escclk_rate = msm_host->esc_clk_rate;
  }
```

### Riesgo / nota

- Riesgo cero funcional (un `pr_info` en el path de modeset; `clk_get_rate` es
  solo lectura y tolera `NULL` con el ternario).
- Convierte `L39-PLAN §2-bis` en dato: con pedida y efectiva en el log se cierra si
  el "6 de 14 difieren / hs_rqst 47,05 ns" vale (tasa medida) o si son "10 difieren /
  42,0 ns" (tasa pedida). NO cambiar el cálculo en este mismo ciclo.
- `pr_info` es coherente con el fichero (usa `pr_err`/`DBG`; `pr_info` ya aparece en
  el driver del panel). Sin `dev_info` a propósito: aquí no hay `dev` a mano, solo
  `msm_host`.

---

## Resumen de estado

| # | Verificado | Hunk listo | Dónde va |
|---|---|---|---|
| (a) vci | driver vivo SIN vci (pérdida L29→L33); DT sin `vci-supply`; rail = `&L19B` verificado | DT 1 línea + restore driver L27 (3 sitios) | próximo dtbo + build |
| (b) NON_CONTINUOUS | sigue en vivo `:640-641` pese a comentario K48-A | diff 1 línea | próximo build (ciclo propio, H3) |
| (c) byte_clk | pedida en `:2468-2481`, efectiva vía `clk_get_rate` | `pr_info` 5 líneas | próximo build (ciclo cero-riesgo) |

*Nada aplicado, nada compilado, nada flasheado. Orden sugerido si se sigue
`ENABLE-COMPARISON §4`: (c) ya (traza) → H1a/H4 → (b) → (a).*
