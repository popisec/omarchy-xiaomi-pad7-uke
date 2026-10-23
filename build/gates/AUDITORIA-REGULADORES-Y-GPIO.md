# Auditoría de los dos `-131` de L8/L22 y del bloqueo real del panel (27-sep-2026, noche)

Todo lo de aquí sale de **leer código + reproducir el DT fusionado en el PC**. La tablet se
apagó/desconectó a mitad de la sesión, así que las dos últimas mediciones marcadas
**PENDIENTE** no se pudieron hacer. Ningún flash en esta sesión: **0 escrituras**.

Source tree auditado: `~/gpu-work/palawan-linux`, HEAD `07ca40a0b` (rama `s150-postclk`) **con
mods sin commitear**. Verificado que es el árbol del kernel que corre: el banner del kernel
extraído de `boot-s244-bounce.img` es `#82 SMP PREEMPT Sat Sep 26 17:01:40 CEST 2026`, idéntico
al `uname -a` de la tablet, y contiene `UKE-POKE`, `X9WAVE`, `G1-ini`, `P5-gpio`.

---

## 1. Veredicto sobre tu hipótesis: **REFUTADA** (colisión de nombre)

Tu intuición apuntaba a `qcom-rpmh-regulator.c:490` (`vreg->rdesc.name = rpmh_data->name`) y a una
colisión de nombres. Es falso, por cuatro motivos independientes:

**1.1 — El core del regulator no comprueba nombres duplicados.** En
`drivers/regulator/core.c:5984` (`regulator_register()`) no existe ninguna comprobación de
nombre duplicado. Lo único que lleva nombre es el *device*, y con un contador atómico:

```c
	/* core.c:6111 */
	dev_set_name(&rdev->dev, "regulator.%lu",
		    (unsigned long) atomic_inc_return(&regulator_no));
```

Los únicos comentarios con "duplicate" en todo `core.c` (líneas 5299 y 5755) son de **directorios
debugfs** y no devuelven error. `regulator_desc->name` no se usa para nada que pueda colisionar.

**1.2 — Los dos nombres ni siquiera coinciden.** El log imprime `uke-l8b-stub:` y
`pmxr2230_l22:`. Son distintos, y **uno de los dos es mío**.

**1.3 — `uke-l8b-stub` no existe en el kernel: es DT mío.** `rdev_err()` no imprime
`dev_name()`, imprime `rdev_get_name()`:

```c
/* internal.h:20 */  #define rdev_err(rdev, fmt, ...) pr_err("%s: " fmt, rdev_get_name(rdev), ...)
/* core.c:119 */
const char *rdev_get_name(struct regulator_dev *rdev)
{
	if (rdev->constraints && rdev->constraints->name)
		return rdev->constraints->name;      /* <-- gana constraints->name */
	else if (rdev->desc->name)
		return rdev->desc->name;
	...
```

y `constraints->name` sale de la propiedad **`regulator-name`** del nodo
(`of_regulator.c:98`: `constraints->name = of_get_property(np, "regulator-name", NULL);`).

Medido de dos formas, y las dos coinciden:
- `strings` del kernel **extraído y descomprimido** de `boot-s244-bounce.img`: **0** apariciones
  de `l8b-stub`.
- El fragmento 154 del **overlay `s236`**, escrito por `mkdtbo-s236.py`:
  ```
  fragment@154 {
      target-path = "/soc/rsc@17a00000/drv@2/rpmh-regulator-ldob8/regulator-pmxr2230-l8";
      __overlay__ {
          compatible = "regulator-fixed";
          regulator-name = "uke-l8b-stub";      <-- lo puse YO en s234
          regulator-min-microvolt = <0x1cfde0>;
          regulator-max-microvolt = <0x1cfde0>;
          regulator-always-on;
      };
  };
  ```

**1.4 — El `-131` es un valor propagado, no un veredicto de nombre.** La cadena real es:

```
gpiolib/core.c  machine_constraints_voltage()      -> llama regulator_get_voltage_rdev()
core.c:1230-1246                                 -> si da -ENOTRECOVERABLE, reintenta un
                                                    _regulator_do_set_voltage() y vuelve a leer;
                                                    si sigue <0, IMPRIME y DEVUELVE
core.c:6144       set_machine_constraints()       -> return ret
core.c            regulator_register()            -> return ERR_PTR(ret)
qcom-rpmh-regulator.c:492-496                      -> "devm_regulator_register() failed, ret=-131"
```

Y el log lo dice literalmente, una línea por encima de cada fallo:

```
[    0.370529] uke-l8b-stub: failed to get the current voltage: -ENOTRECOVERABLE
[    0.370559] qcom-rpmh-regulator ...:rpmh-regulator-ldob8: regulator-pmxr2230-l8: devm_regulator_register() failed, ret=-131
[    0.377795] pmxr2230_l22: failed to get the current voltage: -ENOTRECOVERABLE
[    0.377812] qcom-rpmh-regulator ...:rpmh-regulator-ldob22: regulator-pmxr2230-l22: devm_regulator_register() failed, ret=-131
```

**El `-131` es el `-ENOTRECOVERABLE` de `get_voltage` propagado.** Cero contenido semántico sobre
nombres.

---

## 2. De dónde sale el `-ENOTRECOVERABLE` — y por qué fallan **exactamente dos** rails

> ⚠️ **CORREGIDO EL 27-sep-2026 (2ª revisión).** La primera versión de esta sección decía que el
> selector «solo se rellena DESPUÉS de registrarse, es un deadlock lógico, y solo se salva si
> `set_machine_constraints()` no llama a `get_voltage`». **La segunda mitad es FALSA**, y arrastraba
> una regla equivocada («`min != 0` ⇒ `-131`») con 17 contraejemplos. Un subagente adversarial lo
> cazó; lo he vuelto a verificar yo contra el código antes de aceptarlo. La versión buena,
> **ajustada a la medida 2/2**, es la de abajo.

El `get_voltage` del RPMh no habla con el PMIC: devuelve un **selector** que el driver mantiene en
memoria.

```c
/* qcom-rpmh-regulator.c:250 */
static int rpmh_regulator_vrm_get_voltage_sel(struct regulator_dev *rdev)
{
	struct rpmh_vreg *vreg = rdev_get_drvdata(rdev);
	return vreg->voltage_selector;
}
```

Y el path *vendor* lo inicializa a `-ENOTRECOVERABLE` y lo rellena **después** de registrarse:

```c
/* qcom-rpmh-regulator.c:2128-2130, dentro de rpmh_vrm_vendor_init_vreg() */
	vv->vreg.voltage_selector = -ENOTRECOVERABLE;
	vv->vreg.enabled = -EINVAL;                 /* <-- tambien -EINVAL */
	...
	rdev = devm_regulator_register(...);          /* aqui set_machine_constraints() llama a
	                                                 get_voltage y lee -131 */
	if (IS_ERR(rdev)) { ...; return PTR_ERR(rdev); }
	return rpmh_vrm_vendor_apply_init(vv, node);  /* y AQUI se rellena, con qcom,init-voltage */
```

**Pero no hay deadlock**, porque el core contempla exactamente ese caso:

```c
/* core.c:1230-1240, machine_constraints_voltage() */
		if (current_uV == -ENOTRECOVERABLE) {
			/* This regulator can't be read and must be initialized */
			rdev_info(rdev, "Setting %d-%duV\n", min, max);
			_regulator_do_set_voltage(rdev, min, max);   /* <-- EL REINTENTO */
			current_uV = regulator_get_voltage_rdev(rdev);
		}
		if (current_uV < 0) { rdev_err(rdev, "failed to get the current voltage: %pe\n", ...);
				      return current_uV; }
```

Y ese reintento **no toca hardware**: con `enabled == -EINVAL` (el estado de todo rail vendor
durante el registro) el set **cachea el selector y devuelve 0**:

```c
/* qcom-rpmh-regulator.c:232-244 */
static int rpmh_regulator_vrm_set_voltage_sel(struct regulator_dev *rdev, unsigned int selector)
{
	struct rpmh_vreg *vreg = rdev_get_drvdata(rdev);
	if (vreg->enabled == -EINVAL) {
		/* Cache the voltage and send it later when the regulator is enabled or disabled. */
		vreg->voltage_selector = selector;
		return 0;
	}
	...
}
```

### 🔴 LA REGLA, ajustada a la medida

El reintento se resuelve con `regulator_map_voltage_linear_range()` (`helpers.c:427-464`), que
devuelve `-EINVAL` si **no hay ningún punto de la rejilla** dentro de `[min, max]`. Por tanto:

> **Un rail vendor falla con `-131` ⟺ su rango `[min_uV, max_uV]` no contiene ningún punto de la
> rejilla lineal de 8 mV de su `hw_data`.**

Rejillas (tablas `pmic5_vendor_*`): `pldo` = `1504000 + n·8000` (n ≤ 255), elegido si
`regulator-max-microvolt >= 1504000`; `nldo` = `320000 + n·8000` (n ≤ 123).

Y eso explica los dos fallos **exactamente**, sin resto:

| rail | `[min, max]` | hw | `(max − base)/8000` | veredicto |
|---|---|---|---|---|
| `l22` | `[3300000, 3300000]` | pldo | **224,5** → medio paso | **NINGÚN punto ⇒ `-131`** ✔ medido |
| `l8` en `s236` | `[1900000, 1900000]` *(lo puso mi overlay)* | pldo | **49,5** → medio paso | **NINGÚN punto ⇒ `-131`** ✔ medido |
| `l4`,`l5`,`l7`,`l11`,`l14`,`l16`,`l23` | `min == max` | pldo/nldo | **enteros** | punto exacto ⇒ PASA |
| `l9`,`l10`,`l13`,`l17`,`l20`,`l21`… | `min != max` | — | extremos a media rejilla, pero el **intervalo contiene** un punto | PASA |

**Predicción falsable para el próximo arranque** (una sola línea): debe aparecer
`Setting 3300000-3300000uV` inmediatamente antes de cada `-131`, y **no** debe aparecer para ningún
otro rail. Si aparece `Setting` y aun así hay `-131`, la regla es falsa.

Tabla completa y reproducible: `build/gates/DT-RAILS-L.md` + `dump-rails-l.py`.

### Tres candidatos refutados por medición (no los des por buenos)

Reproduje el DT vivo en el PC: `base-dtb.img` + overlay `s229` con `fdtoverlay`, y volqué los 22
hijos `regulator-pmxr2230-l*` con sus `min`/`max`/`init-voltage`. Tabla en
`build/gates/DT-RAILS-L.md`.

- **«`min == max` es lo que falla» → REFUTADO.** Hay **8** rails con `min == max` y solo 2 fallan.
  `l23` tiene `min==max=1800000` con `init-voltage=1650000` y **funciona**.
- **«`qcom,regulator-type` es lo que falla» → REFUTADO.** Los 22 tienen
  `qcom,regulator-type = "pmic5-ldo"` y el mismo `hw_data`.
- **«`min != 0` (o sea `apply_uV`) es lo que falla» → REFUTADO.** 19 rails lo tienen y **17 se
  registran**. La regla buena es la de la rejilla, arriba. *Esta la sostenía yo: la primera versión
  de esta auditoría la daba por buena y estuvo a punto de convertirse en la premisa del arreglo.*

### Lo que SÍ distingue a L8, y por qué es culpa mía

`s229` (el par bueno) pone L8B con **`min = max = 0`** ⇒ `apply_uV` falso ⇒ ni se llama a
`get_voltage` ⇒ el rail se registra. **`s234`/`s236` le ponen `min = max = 1900000`**, y 1900000
está a **49,5 pasos** de la rejilla: no hay punto ⇒ **`-131`, por mi overlay**.

⚠️ **Corrección**: el apunte de `PRE-REGISTRO-F5-B1.md` de `s233` («L8B tampoco registraba antes»)
es una **lectura errónea de `regulator_summary`**. Con `s229`, L8 se registra.

> **PREDICCIÓN FALSABLE (sin flash)**: bajo `s229` puro, `rpmh-regulator-ldob8` **se registra**.
> Si al volver a `s229` sigue sin aparecer en `regulator_summary`, esta explicación es falsa.

### Y L22 da igual para la pantalla

El panel pide `vddil8b`, `vsp`, `vsn` (`panel-xiaomi-o82-dualdsi.c:79-81`). **L22 no se usa.** Aunque
se arreglara, no cambia el display. **El `-131` no es el bloqueo** (salvo para L8, donde sí me
interesa que funcione como `vddil8b`).
## 3. 🔴 EL BLOQUEO REAL: el gpiochip no se encuentra por phandle, y `s236` fue un no-op

### 3.1 — `s236` sí aterrizó, y el error sigue igual

Medido en `/proc/device-tree` con el `s236` ya en la tablet:

```
uke-regulator-display-vsp:   gpio=0000016b0000004a00000000   enable-gpios=0000016b0000004a00000000
uke-regulator-display-vsn:   gpio=0000016b0000004b00000000   enable-gpios=0000016b0000004b00000000
display_gpio_regulator_vsp:  gpio=0000016b0000004a00000000   enable-gpios=AUSENTE
display_gpio_regulator_vsn:  gpio=0000016b0000004b00000000   enable-gpios=AUSENTE
```

`enable-gpios` está, con el phandle y los 2 args correctos. Y aun así:

```
platform soc:uke-regulator-display-vsp:   deferred probe pending: reg-fixed-voltage: can't get GPIO
platform soc:uke-regulator-display-vsn:   deferred probe pending: reg-fixed-voltage: can't get GPIO
platform soc:display_gpio_regulator_vsp:  deferred probe pending: reg-fixed-voltage: can't get GPIO
platform soc:display_gpio_regulator_vsn:  deferred probe pending: reg-fixed-voltage: can't get GPIO
mipi-dsi ae94000.dsi.0: deferred probe pending: panel-xiaomi-o82-dualdsi: failed to get regulators
```

**Son 4 nodos, no 2**, y los 2 sin `enable-gpios` fallan igual ⇒ el nombre de la propiedad **no es
la causa**. `s236` fue un cambio en el sitio equivocado: no cambió nada.
### 3.1-bis 🔴 Y la premisa de `s236` era doblemente falsa: `enable-gpios` NO se llega a leer

`s236` sostenía que «con `con_id = NULL`, gpiod busca la propiedad literalmente `enable-gpios`».
**Es falso en este kernel.** `fixed.c:320` llama a `gpiod_get_optional(dev, NULL, …)`, y
`of_find_gpio()` itera los sufijos con:

```c
/* gpiolib.h:105-116 */
#define for_each_gpio_property_name(propname, con_id)                    \
        for (const char * const *__suffixes = gpio_suffixes;             \
             *__suffixes && ({  ... else strscpy(propname, __gs); 1; }); \
             __suffixes++)

/* gpiolib.c:106 */
const char *const gpio_suffixes[] = { "gpios", "gpio", NULL };
```

Con `con_id == NULL` se prueban **`gpios`** y **`gpio`** — y **`enable-gpios` no esta en la
lista**: solo se buscaria con `con_id = "enable"`. O sea que la propiedad que anadio `s236` **no la
lee nadie**, ni antes ni despues. Y los 4 nodos tienen `gpio` (legacy), que **si** se busca: por eso
los 4 llegan al lookup del chip y los 4 reciben `-EPROBE_DEFER`. Refuerza §3.2 y cierra el «por que
mecanico».

### 3.1-ter — Correcciones de citas (las tenia mal; no cambian el sentido)

| yo cite | real | que es |
|---|---|---|
| `qcom-rpmh-regulator.c:492-496` -> «devm_regulator_register() failed» | **531-533** (path estandar) y **2161-2163** (path **vendor**, que es el que corre `ldob8`/`ldob22`) | la linea citada no contiene ninguna de las dos del log |
| `qcom-rpmh-regulator.c:252` | **250** | `get_voltage_sel` |
| `of_regulator.c:98` | **97** | `constraints->name` |
| `fixed.c:317-321` | **320-322** | el `gpiod_get_optional` |
| `gpiolib-of.c:432-437` | **433-437** | el `ERR_PTR(-EPROBE_DEFER)` |
| `panel-xiaomi-o82-dualdsi.c:79` | **79-81** | las 3 supplies |

Exacto o ±1 el resto: `core.c:119`, `core.c:5984`, `core.c:6111`, `core.c:1230-1246`,
`of_regulator.c:110-111`, `gpiolib-of.c:121-129`, `gpiolib.c:929`, `pinctrl-msm.c:1488`.

### 3.2 — `can't get GPIO` es `-EPROBE_DEFER`, no «no está la propiedad»

`regulator-fixed` hace, con `con_id = NULL`:

```c
/* fixed.c:317-321 */
	cfg.ena_gpiod = gpiod_get_optional(&pdev->dev, NULL, gflags);
	if (IS_ERR(cfg.ena_gpiod))
		return dev_err_probe(&pdev->dev, PTR_ERR(cfg.ena_gpiod), "can't get GPIO\n");
```

Y el lookup de GPIO, cuando el chip proveedor no se encuentra, **devuelve `-EPROBE_DEFER`**:

```c
/* gpiolib-of.c:432-437  (of_get_named_gpiod_flags) */
	struct gpio_device *gdev = of_find_gpio_device_by_xlate(&gpiospec);
	if (!gdev) {
		desc = ERR_PTR(-EPROBE_DEFER);     /* <-- ERROR, no NULL */
		goto out;
	}
```

`dev_err_probe` con `-EPROBE_DEFER` imprime el texto **solo como motivo** del diferido, y el
driver core lo envuelve como `deferred probe pending: <motivo>`. Es exactamente la línea que
vemos. **O sea: el texto «can't get GPIO» no dice que falte la propiedad; dice que el chip GPIO
del phandle `0x16b` no se localiza.**

### 3.3 — Lo que el código dice que debería pasar (y luego no pasa)

`of_find_gpio_device_by_xlate` → `gpio_device_find(data, of_gpiochip_match_node_and_xlate)`, y:

```c
/* gpiolib-of.c:123-128 */
static int of_gpiochip_match_node_and_xlate(struct gpio_chip *chip, const void *data)
{
	const struct of_phandle_args *gpiospec = data;
	return device_match_of_node(&chip->gpiodev->dev, gpiospec->np) &&
			chip->of_xlate &&
			chip->of_xlate(chip, gpiospec, NULL) >= 0;
}
```

Revisé toda la cadena y **todo debería casar**:

| eslabón | estado |
|---|---|
| `gpiochip0` registrado | **sí** — existe en `/sys/bus/gpio/devices/`, y `msm_gpio_init` no imprimió «Failed register gpiochip» |
| en la lista `gpio_devices` | **sí** — `gpiodev_add_to_list_unlocked()` va antes de `of_gpiochip_add()` |
| `chip->of_xlate` instalado | **sí** — `of_gpiochip_add()` (gpiolib-of.c:1057-1065) pone `of_gpio_twocell_xlate` porque `of_gpio_n_cells != 3` |
| `chip->fwnode` correcto | **sí** — `msm_gpio_init` **no** pone `chip->fwnode` (solo `girq->fwnode`, línea 1488), así que `gpiochip_choose_fwnode()` cae a `dev_fwnode(gc->parent)` = el nodo del pinctrl |
| gpio 74/75 válido | **sí** — `msm_gpio_init_valid_mask` solo limpia lo de `qcom,gpios-reserved` = `8 9 10 11 56 57 58 59 60` |
| `of_node` del gpiodev = phandle `0x16b` | 🔴 **NUNCA COMPROBADO** |

**El único eslabón sin verificar es el último**: que el `of_node` de `gpiochip0` sea realmente
`/soc/pinctrl@f000000`. Ese es el punto a medir.

### 3.4 — 🚩 `gpiochip0` sin `base`/`ngpio`/`label` es una PISTA FALSA, no evidencia

`NOTAS-OMARCHY.md` (27-sep, noche) da como dato que «el gpiochip está registrado pero no
expone `base` ni `ngpio`». **Eso no significa nada en este kernel.** En `drivers/gpio/gpiolib.c`
**no existe ni un `DEVICE_ATTR` de `ngpio`, `base` o `label`**: el modelo nuevo de `gpio_device`
(7.x) los quitó de sysfs. Lo único que crea el último paso, `gpiochip_setup_dev()`
(gpiolib.c:929), es el chardev `dev`, que **sí** vi:

```
/sys/bus/gpio/devices/gpiochip0/  ->  dev  of_node  power  subsystem  uevent
```

Es decir: **el chip se registró del todo.** La ausencia de `base`/`ngpio` no es una avería; es la
norma en este kernel. Chivarlo como «el gpiochip está a medias» costó tiempo y hay que borrarlo de
la bitácora.

---

## 4. 🟢 El segundo no-op: el «dummy» de L8B nunca puede ligar

`rpmh_regulator_vendor_probe()` **se come el nodo hijo en proceso**:

```c
/* qcom-rpmh-regulator.c */
	for_each_available_child_of_node_scoped(dev->of_node, child) {
		struct rpmh_vreg_vendor *vv = devm_kzalloc(dev, sizeof(*vv), GFP_KERNEL);
		...
		ret = rpmh_vrm_vendor_init_vreg(vv, dev, child, addr, hw_data);
		if (ret) { dev_err(dev, "%pOFn: failed to register regulator: %d\n", child, ret); return ret; }
	}
```

El hijo `regulator-pmxr2230-l8` **nunca se convierte en un platform device propio**, así que
**ningún segundo driver puede hacer bind sobre él**. Por tanto el
`compatible = "regulator-fixed"` que puse en `s234` y `s236` es **código muerto**.

**Consecuencia que explica el panel:** el `vddil8b-supply = <0x14f>` del panel sigue apuntando al
rail RPMh de L8, y ese rail falla con `-131` en el `s236`. **El panel no tiene regulador de
`vddil8b`.** Aunque arreglemos los GPIO, el panel seguirá diferido por esto.

⇒ El arreglo correcto para `vddil8b` es **revertir mi fragmento 154** y dejar L8B como lo deja
`s229` (`min = max = 0`, `init-voltage = 1900000`): así `apply_uV` es falso, el registro NO llama a
`get_voltage`, el rail vendor **se registra** y el panel recibe un `vddil8b` de verdad. Sin SPMI,
sin el PMIC, sin tocar hardware. Un cambio de una línea, sobre un overlay ya probado.

---

## 5. Qué hacer cuando vuelva la tablet — **0 flashes, todo por SSH**

Esto decide entre «el gpiochip está mal」 y «el nodo es otro», y no gasta ciclo:

```sh
# 1) ¿A qué nodo DT apunta realmente el gpiochip?  <-- EL ESLABÓN QUE FALTA
readlink -f /sys/bus/gpio/devices/gpiochip0/of_node
readlink -f /proc/device-tree/soc/pinctrl@f000000
#    tienen que coincidir. Si no: ese es el bug.

# 2) ¿ existen y son válidos las líneas 74 y 75?
cat /sys/kernel/debug/gpio | head -1        # nº de líneas del chip
cat /sys/kernel/debug/gpio | sed -n '70,80p'

# 3) el veredicto del lookup, en texto.  dmesg -n 7 ANTES (los pr_debug son KERN_DEBUG)
dmesg -n 7; dmesg | grep -iE "of_get_named_gpiod_flags|of_find_gpio|gpiochip"
#    "parsed '<prop>' property ... status (0)"  => el lookup FUNCIONA
#    "can't parse '<prop>' property"            => propiedad mal formada
#    (sin línea)                                 => el chip no se encuentra

# 4) ¿qué regularizadores hay y cuáles faltan?  (el dummy de L8B NO estará: es código muerto)
grep -E "pmxr2230_l(8|22)|display_(gpio_)?regulator" /sys/kernel/debug/regulator/regulator_summary

# 5) qué dtbo hay puesto de verdad
tr '\0' '|' < /proc/device-tree/soc/uke-regulator-display-vsp/../..//compatible
ls /proc/device-tree/soc/rsc@17a00000/drv@2/rpmh-regulator-ldob8/regulator-pmxr2230-l8/
```

Criterio de decisión:

- **Si (1) no coincide** → causa raíz encontrada: el gpiochip está registrado bajo otro nodo DT.
  Se arregla por código (`msm_gpio_init` / `chip->fwnode`) o por DT, no por overlay de `regulator-fixed`.
- **Si (1) coincide y (3) dice «parsed … status (0)»** → el GPIO **sí** se obtiene, y entonces el
  diferido viene de otra cosa: hay que releer `fixed.c` con el valor exacto que devuelve
  `gpiod_get_optional` (p. ej. `-EPROBE_DEFER` reintentado y agotado, con
  `deferred_probe_timeout` a los 13.8 s).
- **Si (3) no dice nada** → el chip no aparece en la lista y el arreglo es de registro del gpiochip.

⚠️ **Doble captura**: esto es SSH, pero si además se toca DT, `dmesg -n 7` **antes** de pedir
evidencia, y nunca leer `/dev/ttyACM0` si hay otro lector.

## 6. Lo que NO se debe hacer

- **No tocar más `regulator-fixed` por overlay.** Ya sabemos que el nodo de L8B lo consume el RPMh
  y que un `enable-gpios` no arregla el diferido. Tres overlays seguidos (s233/s234/s236) han sido
  no-ops o retrocesos; el próximo tiene que ser un cambio **medido** con (5) por delante.
- **No tocar SPMI ni el PMIC.** Sigue vigente (`X9PMIC-skip`).
- **No abrir `/dev/dri` ni hacer unbind** sin watchdog. El watchdog sigue muerto.
- **No contar con L22.** No lo usa el panel.
- **No reconstruir el kernel** por esto: la causa es orden de llamadas en un path que solo se
  activa con `apply_uV`, y hay un rodeo por DT de una línea.

## 7. PENDIENTE de medir (la tablet se fue) — y el hueco que queda, ya CERRADO

- (5) completo, sobre todo `readlink` del `of_node` del gpiochip.
- Si bajo `s229` puro L8 se registra o no (la predicción falsable de §2).
- ~~Por que fallan solo 2 de los 19 rails con `apply_uV`~~ → **HUECO CERRADO EL 27-sep (2ª
  revision).** No era un orden de sondeo ni un misterio: la regla buena es la **rejilla de 8 mV**
  (§2). Un rail falla con `-131` si y solo si su `[min, max]` no contiene **ningun punto** de la
  rejilla de su `hw_data`; el reintento del core lo salva cacheando un selector valido sin tocar
  hardware. Reproduce **2 de 2** (`l22` a 224,5 pasos; `l8`-con-`s236` a 49,5 pasos). Tabla
  reproducible en `DT-RAILS-L.md`. **La regla falsa que yo sostenia («`min != 0` => `-131`») tiene
  17 contraejemplos** y casi se convierte en la premisa del arreglo.
- Lo unico que queda abierto de esta auditoria es el **eslabon del `of_node` del gpiochip** (§5).
