# INFORME-GPIO-EINVAL — el `-EINVAL` del reset del panel (s257)

**SG-GPIO2 · 28-sep-2026 (noche) · proyecto omarchy-uke · TODO OFFLINE (0 escrituras en la tablet, 0 compilaciones)**

> **Causa exacta (una frase):** el pin 2 del TLMM ya NO pasa por el mecanismo GPIO compartido (s257 lo
> descompartió), así que `devm_gpiod_get("reset")` va directo al gpiochip real y muere en
> `pin_request()` (drivers/pinctrl/pinmux.c:120) con el check *strict*
> (`!gpio_ok && mux_usecount && strcmp(mux_owner, owner)`, pinmux.c:152-157) porque el propio
> `pinctrl-0` del panel ya había reclamado el pin para la función `"gpio"` y esa función **no lleva
> `PINFUNCTION_FLAG_GPIO` en el driver vivo** (`cliffs-pinctrl`, port fork
> `drivers/pinctrl/qcom/pinctrl-cliffs.c:44+1571`) ⇒ `gpio_ok=false` ⇒ `status=-EINVAL` (pinmux.c:127).
>
> **Por qué cambió de defer a -EINVAL:** con el pin *shared* (s238..s256) `gpiod_get` se redirigía al
> chip proxy por lookup-table (gpiolib.c:4796-4812) y **nunca** se ejecutaba el request del descriptor
> real (el core shared ya lo había pedido con label `"shared"`, gpiolib-shared.c:571); el único fallo
> visible era el proxy ausente ⇒ `-EPROBE_DEFER`. s257 descompartió el pin (1 ref real + 1 sintética ⇒
> entrada descartada, gpiolib-shared.c:739-778) y **desenmascaró** un segundo bug, independiente, que el
> proxy tapaba.
>
> **Fix elegido para el ciclo inmediato (DT, 1 propiedad, 0 phandles):** quitar el estado `"default"`
> del panel (`pinctrl-names = "sleep"`) ⇒ `pinctrl_bind_pins` no reclama gpio2 ⇒ `mux_setting == NULL`
> ⇒ `gpio_ok = true` ⇒ el check strict no aplica y `gpiod_get("reset")` pasa
> (`build/gates/FRAGMENTO-GPIO2.dts`, fragment@2103). **Causa raíz (para el próximo kernel, 2 líneas):**
> `FUNCTION(gpio)` → `MSM_GPIO_PIN_FUNCTION(gpio)` en `pinctrl-cliffs.c` (§4.2).
>
> **Validado offline** con `fdtoverlay` sobre el `base-dtb.img` real (`3f973c78…`) + el payload de s257
> (`44a2a6b7…`, el mismo que va dentro de `s257-gpio.img`): el fusionado s258 difiere del s257 en
> **exactamente 1 propiedad** (4271 nodos = 4271, 0 nodos nuevos, 475 phandles idénticos,
> `__fixups__`/`__symbols__`/`__local_fixups__` idénticos).

---

## 0. Etiquetas de evidencia

| etiqueta | significado |
|---|---|
| **DATO-log** | línea literal de una captura ya guardada en el PC (cito ruta:línea) |
| **DATO-offline** | reproducido por mí en este PC (comando + salida, §5) |
| **DATO-fichero** | código/DT leído en `~/gpu-work/palawan-linux` (SOLO LECTURA) o en el disco |
| **INFERENCIA** | deducción a partir de lo anterior, no medida |
| **NO VERIFICADO** | requiere tablet (no la he tocado) |

## 1. La cadena exacta del `-EINVAL` (todo con fichero:línea)

`panel-xiaomi-o82-dualdsi.c:591` → `devm_gpiod_get(dev, "reset", GPIOD_OUT_HIGH)`

| # | fichero:línea | qué hace | ¿devuelve -EINVAL aquí? |
|---|---|---|---|
| 1 | `drivers/gpio/gpiolib-devres.c:47-51,94-124` | `devm_gpiod_get` → `devm_gpiod_get_index` → `gpiod_get_index` | no |
| 2 | `drivers/gpio/gpiolib.c:5060-5068` | `gpiod_get_index` → `gpiod_find_and_request` | no |
| 3 | `drivers/gpio/gpiolib-of.c:1048-1075` + `120-150` | `of_find_gpio` → `of_get_named_gpiod_flags` → `of_xlate_and_get_gpiod_flags`: `args[0]=2 < ngpio=179` ⇒ resuelve el descriptor REAL del tlmm | no |
| 4 | `drivers/gpio/gpiolib.c:4796-4812` | `test_bit(GPIOD_FLAG_SHARED)`: **NO está puesto** en s257 (§3) ⇒ sigue al request directo | no (en s238..s256 sí entraba aquí y de ahí el defer) |
| 5 | `drivers/gpio/gpiolib.c:2629-2638` → `2585-2626` | `gpiod_request` → `gpiod_request_commit`: línea válida (`gpiochip_line_is_valid` línea 2598; `qcom,gpios-reserved` del tlmm = {8,9,10,11,56..60}, no incluye 2) ⇒ llama a `gc->request` (línea 2608) | **aquí no**, pero propaga el error de 6 |
| 6 | `drivers/gpio/gpiolib.c:2392-2400` → `drivers/pinctrl/core.c:814-833` → `drivers/pinctrl/pinmux.c:290-307` → **`pin_request`, pinmux.c:120** | `gpiochip_generic_request` → `pinctrl_gpio_request` → `pinmux_request_gpio` (owner = `"%s:%d"` = `f000000.pinctrl:514`, pinmux.c:298) → `pin_request(pctldev, pin=2, owner, range)` | **SÍ: -EINVAL** (pinmux.c:127 `status = -EINVAL` por el `goto out` de la línea 157) |
| 7 | panel driver :592-594 | `dev_err_probe(dev, -EINVAL, "failed to get reset gpio")` | imprime la línea del log |

### 1.1 Por qué dispara ese `-EINVAL` y no otro

En `pin_request` (pinmux.c:120-200), con `ops = msm_pinmux_ops` (compartido por el driver vivo):

- `desc->mux_owner = "ae94000.dsi.0"`, `mux_usecount = 1`: lo reclamó **el propio device del panel**
  al aplicar su `pinctrl-0` antes de probe (`pinctrl_bind_pins`, `drivers/base/pinctrl.c:23-47` →
  `pinmux_enable_setting` → `pin_request(..., setting->dev_name, NULL)`, pinmux.c:462). **DATO-fichero**
- `gpio_ok = ops->function_is_gpio(pctldev, mux_setting->func)` (pinmux.c:145-147) = **false**.
- `ops->strict = true` (pinctrl-msm.c:287) ⇒ primer check (pinmux.c:152-157):
  `(!gpio_range || strict) && !gpio_ok && mux_usecount && strcmp(mux_owner, owner)`
  → `owner = "f000000.pinctrl:514"` ≠ `"ae94000.dsi.0"` ⇒ `dev_err("pin %s already requested by %s;
  cannot claim for %s")` + `goto out` con `status = -EINVAL`.
  (`gc->base` del tlmm = 512 en este boot ⇒ `512 + 2 = 514`.)

Otros `-EINVAL` alcanzables en la cadena, descartados con esta evidencia:

- `gpiod_request_commit` por línea inválida (gpiolib.c:2598-2600): no — el propio `/sys/kernel/debug/gpio`
  imprime `gpio2` (msm_gpio_dbg_show_one hace *early-return* si la línea no es válida, pinctrl-msm.c:684).
- `gpiod_configure_flags` por pulls contradictorios (gpiolib.c:5012-5016): no — `lookupflags` solo lleva
  `GPIO_ACTIVE_LOW` (`of_convert_gpio_flags`, gpiolib-of.c:458-480).
- `of_xlate` / `gpiochip_get_desc` (gpiolib-of.c:137-150): no — 2 < 179.
- `gpiod_set_transitory`/`gpio_set_bias` (gpiolib.c:2847-2874, 3363): devuelven `-ENOTSUPP` (el tlmm no
  tiene `.set_config`, plantilla en pinctrl-msm.c:806-814) y el wrapper `_optional` lo absorbe.
- `msm_config_group_set` default → -EINVAL (pinctrl-msm.c:527-531): no se llega (no hay `.set_config`).
- `msm_pinmux_set_mux` → -EINVAL si la función no está en el grupo (pinctrl-msm.c:193-194): no se llega
  (el check previo ya abortó).

### 1.2 El bug de base: la función `"gpio"` sin `PINFUNCTION_FLAG_GPIO`

- `pinmux_generic_function_is_gpio()` = `radix_tree_lookup(pin_function_tree, selector)->func->flags & PINFUNCTION_FLAG_GPIO`
  (`drivers/pinctrl/pinmux.c:896-906`; flag en `include/linux/pinctrl/pinctrl.h:207`).
- El driver **vivo** es `cliffs-pinctrl` (pinctrl-cliffs.c:2259; el DT vivo usa
  `compatible = "qcom,cliffs-pinctrl"` — DATO-offline §5.0), un **port del fork** desde el vendor
  (cabecera del fichero, líneas 1-33). Su macro de tabla es
  `#define FUNCTION(fname) [msm_mux_##fname] = PINCTRL_PINFUNCTION(...)` (**sin flag**,
  pinctrl-cliffs.c:43-46) y la tabla usa `FUNCTION(gpio)` (línea 1571) y `FUNCTION(egpio)` (línea 1623).
- El hermano mainline del mismo fork **sí** lo hace bien: `MSM_GPIO_PIN_FUNCTION(gpio)`
  (`pinctrl-msm.h:33` → `PINCTRL_GPIO_PINFUNCTION`, `pinctrl.h:236-243`) en `pinctrl-palawan.c:1112`.
  ⇒ es un bug del **port**, no del core.
- Consecuencia: para el TLMM vivo, `function_is_gpio("gpio") == false`. No sólo afecta a este caso:
  también rompe `pinmux_can_be_used_for_gpio()` (usado por el cdev en `gpiolib-cdev.c:2220,2467`) y la
  contabilidad de `gpio_owner` en `pin_free`.

### 1.3 Evidencia viva (DATO-log) — captura de consola del boot s257

`~/proyectos/out/uke-ubuntu_console.log:443390-443393` (líneas literales; el log es la
captura de consola del orquestador, no está en el repo):

```
[   13.949778] cliffs-pinctrl f000000.pinctrl: pin GPIO_2 already requested by ae94000.dsi.0; cannot claim for f000000.pinctrl:514
[   13.949783] cliffs-pinctrl f000000.pinctrl: error -EINVAL: pin-2 (f000000.pinctrl:514)
[   13.949786] panel-xiaomi-o82-dualdsi ae94000.dsi.0: error -EINVAL: failed to get reset gpio
[   13.949789] panel-xiaomi-o82-dualdsi ae94000.dsi.0: probe with driver panel-xiaomi-o82-dualdsi failed with error -22
```

Lectura de campos: `cliffs-pinctrl f000000.pinctrl` = `dev_driver_string(dev) + dev_name(dev)` del
pinctrl device ⇒ **el driver vivo es el port cliffs**; `already requested by ae94000.dsi.0` = impreso
como `desc->mux_owner` ⇒ primer check ⇒ `gpio_ok=false` (§1.1); `cannot claim for f000000.pinctrl:514`
= el owner del request GPIO. Nota: sólo hay **una** ocurrencia de "already requested by" en todo el
log ⇒ es un caso aislado del panel, no un problema masivo.

## 2. Respuestas directas a las preguntas del encargo

1. **¿Quién devuelve -EINVAL?** `pin_request()` — `drivers/pinctrl/pinmux.c:152-157` (mensaje
   "pin %s already requested by %s; cannot claim for %s") con `status = -EINVAL` de la línea 127.
   No es el mecanismo `CONFIG_GPIO_SHARED` (ese ya no participa: sin `GPIOD_FLAG_SHARED`), no es el
   proxy (no hay proxy de este pin), no son flags (`-EINVAL` de pulls no aplica), no es la máscara de
   líneas válidas (línea 2 válida). La causa próxima es `gpio_ok=false` por el flag ausente (§1.2).
2. **¿Por qué antes defer y ahora -EINVAL?** §3.
3. **¿El fix?** §4 (DT ahora + kernel 2 líneas como causa raíz).
4. **Validación offline** §5 (fragmento DT sobre `base-dtb.img` con `fdtoverlay`+`fdtget`).

## 3. Por qué ANTES era `-EPROBE_DEFER` y AHORA `-EINVAL` (la diferencia de estado)

| estado | refs a pin 2 en el DT fusionado | `really_shared` (gpiolib-shared.c:739-763) | efecto en `gpiod_get("reset")` | fallo observado |
|---|---|---|---|---|
| s238..s256 | 4 reales (panel@0 + 3 vendor) + 1 sintética = **5** | true (>2) | `GPIOD_FLAG_SHARED` + `gpiod_request_commit(desc,"shared")` (gpiolib-shared.c:565-571) + **redirección por lookup al proxy** (gpiolib.c:4796-4812) | proxy ausente ⇒ `cannot find GPIO chip … deferring` ⇒ **-EPROBE_DEFER** (gpiolib.c:4662-4664). El request del descriptor real **nunca** se ejecuta ⇒ el bug de §1 nunca se ve |
| s257 | 1 real (panel@0) + 1 sintética = **2**, una `is_reset_gpio` | **false** ⇒ `gpio_shared_free_exclusive()` descarta la entrada (gpiolib-shared.c:765-778) | sin flag ⇒ `of_find_gpio` da el descriptor real y se llama a `gc->request` | `pin_request` strict ⇒ **-EINVAL** (§1) |

**Conclusión (DATO-fichero + DATO-log):** s257 no rompió nada; hizo exactamente lo que debía
(descompartir el pin). Lo que ocurre es que **el camino del proxy estaba tapando un segundo bug
independiente**: mientras el pin era shared, el descriptor real ya estaba pedido por el core
(`"shared"`) y `pin_request` con owner de consumidor ni se invocaba. Al quedar exclusivo, el panel
ejerce el camino normal `gpiod_request → gc->request` y ahí aparece el flag ausente del driver cliffs.

## 4. El fix

### 4.1 Elegido para el ciclo inmediato — DT (`build/gates/FRAGMENTO-GPIO2.dts`, fragment@2103)

```
pinctrl-names = "default", "sleep"  ->  pinctrl-names = "sleep"
```

sobre `/soc/display-subsystem@ae00000/dsi@ae94000/panel@0` (override de propiedad; **no** se borra
nada, que el ABL ignora los `delete-*`, y no se añade ningún phandle).

Mecanismo (todo verificado en código): sin estado `"default"` (nombre reservado,
`pinctrl-state.h:33`), `pinctrl_bind_pins` hace `dev_dbg("no default pinctrl state")` + `ret=0`
(`drivers/base/pinctrl.c:38-43`) ⇒ **no** reclama gpio2 ⇒ en el request del panel
`desc->mux_setting == NULL` ⇒ `gpio_ok = true` (pinmux.c:148-149) ⇒ los dos checks strict no aplican
⇒ `desc->gpio_owner = owner` y `msm_pinmux_request_gpio` muxea el pin a gpio
(pinctrl-msm.c:276) ⇒ `gpiod_get` OK ⇒ el panel sigue su probe.

Coste/efectos: (a) el grupo `uke-dsi-reset-active` ya no se aplica ⇒ no se re-aplica el pinconf
(8mA/bias-disable); el pad conserva lo que dejó el BL (medido en vivo:
`gpio2: out high func0 8mA no pull`) y gpiolib sólo toca IO/OE (`msm_gpio_direction_output`,
pinctrl-msm.c:577-601) ⇒ sin pérdida práctica **INFERENCIA**; (b) los estados quedan nombrados
`"sleep"` y `"1"` — nadie los selecciona (el driver del panel no usa pinctrl: `grep pinctrl
panel-xiaomi-o82-dualdsi.c` = 0 coincidencias, DATO-fichero); (c) `pinctrl-0`/`pinctrl-1` siguen
apuntando a los mismos grupos (0x700/0x701) para no invalidar phandles.

Descartados (con motivo):
- **(i) neutralizar la referencia sintética**: con 1 real + 1 sintética la entrada ya se descarta
  (umbral: `num_nodes<=2` y `is_reset_gpio`, gpiolib-shared.c:753-761). No hay nada más que
  neutralizar; el problema no está en el mecanismo shared.
- **(ii) prop de exención del mecanismo shared**: no existe (grep `gpio-shared,`/`shared-mask`/`exempt`
  en `gpiolib-shared.c` = 0 resultados; la única condición de exención es el propio recuento de refs).
- **(iii) cargar el módulo proxy antes**: irrelevante en s257 — el pin ya no es shared y el proxy no
  participa (además `lsmod` da `gpio_shared_proxy 20480 0` porque el refcount lo da
  `gpiod_request`/`try_module_get` sobre el chip proxy, gpiolib.c:2634, no el bind).
- **Pinconf sin mux (grupo nuevo solo-config + phandle nuevo + repuntar `pinctrl-0`)**: válido en
  teoría (`pins="GPIO_2"` sin `function` ⇒ MAP_TYPE_CONFIGS_PIN) pero exige inventar un phandle;
  descartado por la regla del proyecto (R-24).

### 4.2 Causa raíz — parche kernel de 2 líneas (para el próximo build, SIN compilar aquí)

`drivers/pinctrl/qcom/pinctrl-cliffs.c` (el port debe marcar su función GPIO como tal; mismo macro que
el hermano mainline `pinctrl-palawan.c:1112`):

```diff
--- a/drivers/pinctrl/qcom/pinctrl-cliffs.c
+++ b/drivers/pinctrl/qcom/pinctrl-cliffs.c
@@ -1568,7 +1568,7 @@ static const char *const vsense_trigger_mirnat_groups[] = {
 static const struct pinfunction cliffs_functions[] = {
-	FUNCTION(gpio),
+	MSM_GPIO_PIN_FUNCTION(gpio),
 	FUNCTION(HOST2WLAN_SOL),
@@ -1620,7 +1620,7 @@ static const struct pinfunction cliffs_functions[] = {
-	FUNCTION(egpio),
+	MSM_GPIO_PIN_FUNCTION(egpio),
```

`MSM_GPIO_PIN_FUNCTION(fname)` (pinctrl-msm.h:33) expande a `[msm_mux_##fname] = PINCTRL_GPIO_PINFUNCTION(...)`
— **mismo designador** que `FUNCTION()`, así que es un reemplazo directo de una línea (los grupos
`gpio_groups`/`egpio_groups` existen: pinctrl-cliffs.c:741/933). Efecto: `function_is_gpio("gpio")=true`
⇒ `gpio_ok=true` ⇒ el check strict no aplica aunque el pin esté reclamado por pinctrl; el request
funciona con el pinconf aplicado (8mA) y con los nombres de estado originales. Con este parche el
fragmento DT de §4.1 se puede revertir.

## 5. Validación offline del fix DT (DATO-offline)

### 5.0 Material

| pieza | sha256 / dato | fuente |
|---|---|---|
| DT base real | `3f973c78f7dc6a66f1acea363be27774c51ff174fbf71117ebe74c385547562e` | `~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img` |
| payload s257 | `44a2a6b7729ed3f937917e16df0d24cab85aa5c8c4c7e24dcd9bc3e5a1ee0527` | extraído de `build/bootimg/s257-gpio.img` (tabla DTBO: payload en offset 64, tamaño 608277; `dd skip=64 count=608277` ⇒ sha idéntico al `/tmp/s257.dtb` del constructor) |
| fusionado s257 (referencia) | `f5afd883a4a34fae999c083c653aba3c5dd934da680ba66fa1fb9f2ff28a6f1b` | reproducido por mí (`fdtoverlay`) = el del orquestador |
| payload s258 (mi test) | `ea6ac36ed395a6f117aa18e82eb382aa53f32fff96bfa6de5501a921c3c3253a` | s257 + `fragment@2103` (`FRAGMENTO-GPIO2.dts`), 608405 B |
| fusionado s258 (mi test) | `9efe07d57a98637d07ab02e3bc5f39d0b9aafa0b2fab1a5f045c2789c73ee1e7` | `fdtoverlay -i base-dtb.img -o s258-fused.dtb s258-payload.dtb` |
| driver vivo del tlmm | `compatible = "qcom,cliffs-pinctrl"` | `fdtget s257-merged.dtb /soc/pinctrl@f000000 compatible` |

Comandos: `dtc -I dtb -O dts -o pay.dts s257.dtb` → insertar `fragment@2103` antes del último `};` →
`dtc -I dts -O dtb -o s258-payload.dtb pay.dts` → `fdtoverlay -i base-dtb.img -o s258-fused.dtb s258-payload.dtb`.

### 5.1 Gates (todos VERDES)

| gate | qué comprueba | resultado |
|---|---|---|
| G-GPIO2-1 | `pinctrl-names` del panel | `sleep` exacto; la lista **no** contiene `default` (`fdtget -t x` ⇒ `73 6c 65 65 70 0`) |
| G-GPIO2-2 | resto del panel intacto | `pinctrl-0 = 700`, `pinctrl-1 = 701`, `reset-gpios = 16b 2 1`, `vsp/vsn/vddil8b-supply` y `compatible = xiaomi,uke-o82-4202-0b` sin cambios; grupos `uke-dsi-reset-active/suspend` siguen `function=gpio`, `pins=gpio2` |
| G-GPIO2-3 | diff semántico s257→s258 | 4271 nodos = 4271; 0 nodos añadidos/quitados; **1** propiedad distinta: `panel@0/pinctrl-names` `"default", "sleep"` → `"sleep"` |
| G-GPIO2-4 | referencias al pin 2 | activas = **1** (solo `panel@0/reset-gpios`); los 3 nodos vendor siguen `disabled`; resto de pines sin cambios |
| G-GPIO2-5 | sin phandles/fixups nuevos | `__symbols__`, `__fixups__`, `__local_fixups__` idénticos (md5 del payload s257 vs s258); conjunto de 475 phandles idéntico, 0 nuevos; el fragmento usa `target-path` (sin `&`) |
| G-GPIO2-6 | control negativo | sobre el fusionado s238 el pin 2 sigue con **4 refs activas** ⇒ compartido ⇒ este fragmento **no** bastaría (el `gpiod_get` muere antes, en el lookup del proxy). El fragmento sólo es suficiente combinado con s257 |

## 6. Riesgos y lo NO VERIFICADO

| item | estado |
|---|---|
| Que el ABL aplique `fragment@2103` (target-path sobre el panel) | **INFERENCIA fuerte**: es el mismo patrón que los fragment@2100-2102 que s257 aplicó medidamente sobre nodos hermanos bajo `/soc/...` |
| Que el pad conserve 8mA/no-pull sin el pinconf | **DATO-medido en el boot s257** (`gpio2: out high func0 8mA no pull` en debugfs tras soltarse el estado) + INFERENCIA de que el BL lo dejó así; gpiolib no lo revierte |
| Que `pinctrl_bind_pins` tolere no tener "default" | **DATO-fichero**: `drivers/base/pinctrl.c:38-43` (`ret = 0; goto cleanup_get`) |
| Que el panel probe con esto | **NO VERIFICADO** (requiere flash; sin tablet) |
| El bug del driver sigue vivo tras el puente DT | **DATO-fichero** (§1.2): cualquier otro pin reclamado por pinctrl como `"gpio"` y pedido por gpiod dará el mismo `-EINVAL`; por eso el parche kernel es el fix definitivo |

## 7. Ciclo propuesto (s258) y evidencia esperada

1. **s258 = s257 + `FRAGMENTO-GPIO2.dts`** (fragment@2103), construido con el constructor de dtbo
   habitual (insertar antes del último `};` del payload descompilado; verificación con los gates
   G-GPIO2-1..6 ya definidos en el fichero del fragmento).
2. Flash de `dtbo_b` (canal fiable: fastboot o `dd` con `sync`+`drop_caches`, lección de P1e).
3. Evidencia de ÉXITO: **desaparecen** las 3 líneas `cliffs-pinctrl … pin GPIO_2 already requested…`
   / `error -EINVAL: pin-2 …` / `panel … failed to get reset gpio`, y el panel registra (p. ej.
   `ls /sys/class/backlight/` con `ae94000.dsi.0`, `dmesg | grep -i panel` sin error).
4. Evidencia de CONTROL: `pinmux-pins` mostrará `pin 2 (GPIO_2): GPIO f000000.pinctrl:514`
   (gpio_owner en vez de UNCLAIMED) ⇒ el pin quedó pedido por el panel vía gpiod.
5. Si aparece un fallo **distinto** (p.ej. del DSI/DPU/SMMU), ya no es de este hilo: es la cadena
   siguiente (fuera de esta misión).
6. Para el próximo build de kernel (#83): aplicar el diff de §4.2 y, una vez verificado que el panel
   probea con el pinconf aplicado, revertir el fragmento 2103.
