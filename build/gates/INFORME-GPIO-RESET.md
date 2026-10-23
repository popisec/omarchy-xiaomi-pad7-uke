# INFORME-GPIO-RESET — `panel: failed to get reset gpio` (GPIO2 del TLMM)

**SG-GPIO · 28-sep-2026 · proyecto omarchy-uke · TODO OFFLINE (0 escrituras en la tablet)**

> Causa raíz (una frase): el `reset-gpios` del panel apunta al **pin 2 del TLMM**, y el DT
> fusionado (base vendor + `s238`) deja ese pin con **4 consumidores activos** ⇒ el mecanismo
> propio del kernel `CONFIG_GPIO_SHARED` lo marca **compartido**, esconde el descriptor real y
> obliga a pasar por un chip **proxy** `gpiolib_shared.proxy.<id>` que solo existe si está
> cargado y enlazado el módulo `gpio-shared-proxy.ko` (`=m`, vive en el rootfs). Si ese chip no
> está registrado en el momento de la petición, `gpiod_get()` devuelve `-EPROBE_DEFER` **para
> siempre** y el panel se queda en defer con el motivo `failed to get reset gpio`.
>
> Arreglo (una frase): neutralizar en el DT las **3 referencias vendor** al pin 2 con
> `status = "disabled"` (mismo patrón que `s238` usó con gpio74/75) ⇒ el pin queda con **1 solo
> consumidor real** ⇒ el mecanismo compartido lo **descarta** y el panel pide el pin **directo**,
> sin depender de ningún módulo.
>
> Validado offline con `fdtoverlay` sobre el **DT base real** (`base-dtb.img`, sha `3f973c78…`):
> el fusionado `s254 = s253 + FRAGMENTO-GPIO` difiere de `s253` en **exactamente 3 líneas**
> (`status = "disabled"` ×3) y el pin 2 pasa de **4 refs activas a 1**. Entregables:
> `build/gates/FRAGMENTO-GPIO.dts` + este informe.

---

## 0. Qué es DATO, qué es INFERENCIA y qué NO está verificado

| etiqueta | significado |
|---|---|
| **DATO-fichero** | leído en un fichero del disco (cita `fichero:línea`) |
| **DATO-medido** | salida de un comando ya registrada en disco (cita la fuente) |
| **DATO-offline** | reproducido por mí en este PC (comando + salida en §6) |
| **INFERENCIA** | deducción a partir de código/DT, no medida en la tablet |
| **NO VERIFICADO** | no se puede cerrar sin la tablet (USB caído) |

---

## 1. El fallo y las dos asimetrías

**Mensaje (el del encargo):** `mipi-dsi ae94000.dsi.0: deferred probe pending:
panel-xiaomi-o82-dualdsi: failed to get reset gpio`
(`build/gates/EVIDENCIA-PANTALLA-28sep.md:202`; el `dev_err_probe` que lo produce es
`panel-xiaomi-o82-dualdsi.c:591-594`).

Ese mensaje es la **razón de diferido** que registra `dev_err_probe()`: solo se imprime una línea
"deferred probe pending: …" si el probe devolvió **`-EPROBE_DEFER`**
(`drivers/base/dd.c:326` lo imprime para los devices de la lista de diferidos;
`drivers/base/core.c:5091-5092` `__dev_probe_failed()` con `-EPROBE_DEFER` →
`device_set_deferred_probe_reason()` y **no** imprime error; con otro errno imprimiría
`error -2/…`). **DATO-fichero.** Por tanto el `devm_gpiod_get(dev, "reset", GPIOD_OUT_HIGH)`
**no falló con un error terminal: devolvió defer**.

Asimetría medida:

| pin | consumidores activos en el DT (fusionado s238) | resultado |
|---|---|---|
| 74 / 75 (`vsp`/`vsn`) | **1** cada uno (`uke-regulator-display-vsp/vsn`; su duplicado vendor quedó `disabled` por `s238`) | petición **directa** al tlmm; funciona con o sin módulo |
| **2 (reset panel)** | **4** (`panel@0` + 3 nodos vendor) | pin **shared** ⇒ petición **redirigida al proxy** ⇒ defer si el proxy no está |

**DATO-fichero:** fusionado `build/evidencia/2026-09-28/dt-reconstruido/dt-fusionado-s238.dts`
líneas 980 (`reset-gpios` del `panel@0`), 22240, 22471 y 22681 (los 3 nodos vendor con
`qcom,platform-reset-gpio = <0x16b 0x02 0x00>`). Reproducido por mí con `fdtget` sobre el DT base
real + payload `s238` (§6.1).

---

## 2. El mecanismo `CONFIG_GPIO_SHARED`, línea a línea

Kernel `7.2.0-rc2-palawan+` (en marcha). Config viva:
`CONFIG_GPIO_SHARED=y` (config-kernel.txt:3709), `CONFIG_GPIO_SHARED_PROXY=m` (config-kernel.txt:3812).
Ficheros: `drivers/gpio/gpiolib-shared.c`, `drivers/gpio/gpio-shared-proxy.c`,
`drivers/gpio/gpiolib.c`. Todo lo de esta sección es **DATO-fichero** (código leído en
`~/gpu-work/palawan-linux`, solo lectura).

### 2.1 El escaneo (postcore_initcall, sobre el DT fusionado ya aplicado)

`gpio_shared_of_scan()` (gpiolib-shared.c:292-298) recorre **todo** el DT en
`postcore_initcall` (`gpio_shared_init`, :780-797), antes de que ningún driver de gpiochip probe.

- **Ignora nodos `status != okay`** (`gpio_shared_of_node_ignore`, :136-157:
  `if (!of_device_is_available(node)) return true;`) y **no desciende** a sus hijos (:171).
- Cuenta como referencia toda propiedad `*-gpios`, `*-gpio`, `gpios` o `gpio` (:185-189) que
  apunte a un nodo con `gpio-controller` (:208) y tenga **2 celdas** (:222).
- **No mira si el nodo consumidor tiene driver**: la referencia existe aunque nadie llame nunca a
  `gpiod_get()`. (Esto es exactamente lo que el comentario del constructor `s238` da por supuesto
  al revés — ver §4.1.)
- Si la propiedad es **`reset-gpios` exactamente**, añade una referencia **sintética** con
  `is_reset_gpio = true` (con_id `"reset"`, fwnode NULL) para el caso del subsistema `reset-gpio`
  (:110-133, invocada en :275-279).

### 2.2 El umbral: "realmente compartido"

`gpio_shared_free_exclusive()` (:765-778) descarta, **antes de que ningún chip registre**, las
entradas que `gpio_shared_entry_is_really_shared()` (:739-763) considera no compartidas:

```c
	size_t num_nodes = list_count_nodes(&entry->refs);
	if (num_nodes <= 1)
		return false;
	if (num_nodes > 2)
		return true;
	/* Exactamente dos referencias: */
	list_for_each_entry(ref, &entry->refs, list) {
		if (ref->is_reset_gpio)
			return false;       /* <- el caso "1 consumidor con reset-gpios" */
	}
	return true;
```

Es decir: **1 referencia real (+ la sintética) = NO compartido; 3 o más = compartido.**

### 2.3 La marca y el secuestro del descriptor

Cuando el gpiochip del TLMM se registra (`gpiochip_add_data` → `gpiochip_setup_shared`,
gpiolib.c:1340 y gpiolib-shared.c:509-593), para cada entrada superviviente:

```c
	if (list_count_nodes(&entry->refs) <= 1)          /* :539 */
		continue;
	...
	__set_bit(GPIOD_FLAG_SHARED, &desc->flags);        /* :565 */
	ret = gpiod_request_commit(desc, "shared");        /* :571  <- nadie más lo puede pedir */
	...
	ret = gpio_shared_make_adev(gdev, entry, ref);     /* :584  -> 1 device auxiliar por ref */
```

Cada device auxiliar `gpiolib_shared.proxy.<id>` se convierte, vía
`gpio-shared-proxy.c:256-303`, en un **gpiochip de 1 línea** (`gc->label = dev_name(adev)`,
`ngpio = 1`, `can_sleep = true`). El módulo `gpio-shared-proxy` es `=m`: **si no está cargado, los
devices auxiliares existen pero nadie los bindea** y no hay gpiochip proxy.

### 2.4 La petición del consumidor

`gpiod_find_and_request()` (gpiolib.c:4776-…): tras resolver el `reset-gpios` por DT,

```c
		if (!IS_ERR_OR_NULL(desc) &&
		    test_bit(GPIOD_FLAG_SHARED, &desc->flags)) {           /* :4796-4797 */
			ret = gpio_shared_add_proxy_lookup(consumer, fwnode,
							   con_id, lookupflags);   /* :4804 */
			...
			desc = ERR_PTR(-ENOENT);                               /* :4810 */
			platform_lookup_allowed = true;                        /* :4812 */
		}
```

`gpio_shared_add_proxy_lookup()` (gpiolib-shared.c:446-501) registra una `gpiod_lookup_table`
para **ese consumidor** cuya clave es `KBUILD_MODNAME ".proxy.%u"` = **la etiqueta del chip
proxy de ESA referencia** (:473-476, `dev_id = dev_name(consumer)`). El lookup se resuelve por
etiqueta (gpiolib.c:4652-4653: `gpio_device_find_by_label(p->key)`) y, si el chip no está:

```c
			dev_dbg(dev, "cannot find GPIO chip %s, deferring\n",
				p->key);                                    /* :4662-4663 */
			return ERR_PTR(-EPROBE_DEFER);                      /* :4664 */
```

⇒ **`-EPROBE_DEFER` permanente** (no hay estado que lo convierta en `-ETIMEDOUT`: es un defer
duro del path de gpiod, que se reintenta en cada `driver_deferred_probe_trigger`). **Así se
produce exactamente el `failed to get reset gpio` del encargo.**

### 2.5 Aplicado a nuestro DT: por qué el 2 sí y el 74/75 no

Con el fusionado `s238` (contado con el emulador del escaneo, §6.3):

| pin | refs reales | + sintética | `really_shared` | efecto |
|---|---|---|---|---|
| 2 | 4 (`panel@0`, o82_36, o82_42, visionox) | 1 (`reset-gpios`) | **sí (5 > 2)** | descriptor secuestrado; panel ⇒ proxy obligatorio |
| 74 | 1 (`uke-regulator-display-vsp`) | 0 | no | entrada descartada; petición directa |
| 75 | 1 (`uke-regulator-display-vsn`) | 0 | no | idem |

**Predicción falsable del diagnóstico:** neutralizar **las 3** referencias vendor deja pin 2 con
1 real + 1 sintética ⇒ `really_shared = false` ⇒ sin marca, sin secuestro, sin proxy ⇒ el
`devm_gpiod_get("reset")` del panel resuelve el descriptor **real** y el probe no depende de
`gpio-shared-proxy.ko`.

---

## 3. Evidencia medida (y lo que no se pudo cerrar)

### 3.1 DATO — con el módulo cargado y `s238`, el panel PROBÓ (boot de las 12:10 del 28-sep)

Fuente: `/tmp/uke-autorecolecta.log` (recogida en vivo por SSH en ese boot):

- `:98` `gpio_shared_proxy      20480  1` → módulo cargado **ya en el arranque** (`up 0 min`:
  `:10`) y **1 solo device auxiliar bindeado** (los demás proxies no tienen consumidor que los
  pida). Con `s238` (74/75 dedup), el único consumidor real de un pin compartido que *pide* su
  GPIO es el panel ⇒ ese refcount 1 es consistente con que el proxy **del reset del panel** esté
  vivo.
- `CMD 4` (`cat /sys/kernel/debug/devices_deferred`): **vacío** ⇒ no había ni un device diferido.
- `CMD 7` (`:99-107`): existe `/sys/class/backlight/ae94000.dsi.0/` con
  `device -> ../../../ae94000.dsi.0`; ese backlight lo registra **el driver del panel**
  (`o82_create_backlight`, `panel-xiaomi-o82-dualdsi.c:459-471`,
  `devm_backlight_device_register(dev=dsi dev, name=dev_name(dev))`). ⇒ el probe del panel
  terminó bien en ese boot.
- `:373-374`, `:1059-1060` y `:424`/`:1085`: `display_gpio_regulator_vsp/vsn` con
  `status: disabled` ⇒ el dtbo vivo era `s238` (o un hijo suyo) y el dedup de 74/75 estaba
  aplicado.

### 3.2 DATO — sin el módulo, el mismo mecanismo da el fallo exacto

Medición previa en la tablet, en caliente (citada literal en `mkdtbo-s238.py:13-17` y en
`build/gates/PRE-REGISTRO-F5-B1.md:522`):

```
reg-fixed-voltage soc:uke-regulator-display-vsp: using lookup tables for GPIO lookup
reg-fixed-voltage soc:uke-regulator-display-vsp: cannot find GPIO chip gpiolib_shared.proxy.45, deferring
bash: echo: write error: Resource temporarily unavailable          <- -EPROBE_DEFER
```

y en el mismo estado: **30** devices `gpiolib_shared.proxy.*`, **0 de 30 con driver**
(`try-shared-proxy.sh:6-12`, `PRE-REGISTRO-F5-B1.md:545`).

### 3.3 INFERENCIA — el fallo del encargo es este mismo, con el proxy ausente en ese boot

El encargo dice que el panel difiere **ahora** con el módulo cargado; el boot de 12:10 demuestra
que con módulo + `s238` el panel prohíbe ese diferido (backlight presente, `devices_deferred`
vacío). Las dos cosas caben si el boot del fallo fue **anterior a la instalación persistente del
módulo** (o un boot con el módulo no enlazado). El `-EPROBE_DEFER` duro del §2.4 es la única
forma de que `devm_gpiod_get("reset")` devuelva defer con el descriptor real ya presente en el
DT: **INFERENCIA** sólida, pero **NO VERIFICADO** que ese boot fuera el último (la captura de
consola del último boot tiene huecos: `consola-ultimo-boot-28sep.txt` no contiene ni una línea
`deferred probe pending` ni `mipi-dsi`, y sí contiene 6 intentos de `systemd-backlight` sobre
`backlight:ae94000.dsi.0`, que **también** apuntan a panel proebado — `:28-168`).

**Consecuencia para el diseño:** el arreglo elegido (§4) elimina la dependencia del módulo en
**ambos** mundos (con y sin proxy), así que no hace falta desambiguar ese punto antes de flashear.

---

## 4. Decisión: el arreglo de DT

### 4.1 Los 3 nodos vendor que hay que neutralizar (y una corrección a la evidencia previa)

Los 4 consumidores activos del pin 2 en el fusionado `s238` (**DATO-offline**, §6.1/6.3):

| # | nodo (target-path) | propiedad | quién es |
|---|---|---|---|
| 1 | `/soc/display-subsystem@ae00000/dsi@ae94000/panel@0` | `reset-gpios = <0x16b 0x02 0x01>` | **nuestro** panel mainline (`xiaomi,uke-o82-4202-0b`) |
| 2 | `/soc/qcom,mdss_mdp@ae00000/qcom,mdss_dsi_o82_36_02_0a_dualdsi_dsc_vid` | `qcom,platform-reset-gpio = <0x16b 0x02 0x00>` | panel vendor O82-36 |
| 3 | `/soc/qcom,mdss_mdp@ae00000/qcom,mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid` | idem | panel vendor O82-42 |
| 4 | `/soc/qcom,mdss_mdp@ae00000/qcom,mdss_dsi_visionox_r66451_fhd_plus_video` | idem | panel vendor **visionox r66451** (otra variante) |

> **Corrección a `EVIDENCIA-PANTALLA-28sep.md` §10.4:3**: decía "3 instancias en DOS nodos
> vendor o82"; son **3 nodos distintos** (dos o82 + uno visionox). Importa: deshabilitar solo los
> dos o82 dejaría pin 2 con **2 reales + 1 sintética = 3 > 2 ⇒ seguiría compartido**. Hacen falta
> los **tres**; el contador de §6.3 lo verifica (4 → 1).

¿Los consume alguien? **DATO-offline:** los tres nodos **no tienen `compatible`** (fdtget:
`FDT_ERR_NOTFOUND`) ⇒ nunca crean device; solo los referencia como **datos** el árbol vendor
(`panel = <0x6bd 0x6be 0x6ad>`, `qcom,dsi-default-panel = <0x6ad>`; fusionado líneas 1162-1172,
1301 y 17440), que **no tiene driver** en este kernel (`qcom,mdss_mdp@ae00000` =
`qcom,sde-kms`; `qcom,platform-reset-gpio` tiene **0 lectores mainline**:
`grep -rn "qcom,platform-reset-gpio" drivers/` = vacío). Nada mainline los usa.

### 4.2 Por qué `status = "disabled"` y no las alternativas

- **Elegida: `status = "disabled"` en los 3 nodos.** Es el **mismo patrón ya probado en esta
  tablet**: `s238` deshabilitó así los dos `display_gpio_regulator_*` (medido: `status: disabled`
  en el DT vivo, §3.1) y `s207` el nodo `qcom,gpr`. El escaneo ignora el nodo entero
  (gpiolib-shared.c:136-157) y **no añade ninguna referencia nueva**. No toca el panel, ni los
  reguladores, ni el SMMU, ni el PHY.
- **Descartada: repuntar `qcom,platform-reset-gpio` a un pin huérfano.** Exigiría inventar un pin
  y dejaría una referencia **falsa** que un driver vendor (fuera de árbol) conduciría de verdad;
  además podría crear un pin compartido nuevo si el elegido ya tuviera refs. Deshabilitar no
  inventa datos.
- **Descartada: `/delete-node/` o `/delete-property/`.** El ABL ignora las directivas de borrado
  en overlays (lección del hermano; el proyecto ya lo sufrió): un `delete` no aplica y el pin
  seguiría con 4 refs.
- **Descartada: cambiar la forma en que pide el gpio el driver** (`devm_gpiod_get` con
  `GPIOD_FLAG_NONEXCLUSIVE` o similar). No es un cambio de DT, y con el descriptor marcado
  `GPIOD_FLAG_SHARED` el camino sigue siendo el proxy (el flag se marca antes de cualquier
  petición, gpiolib-shared.c:565). Además el fork ya redirige *antes* de pedir.
- **Nota de orden (importante):** los 3 nodos **los crea el propio payload** (fragment@94/95/96,
  con `target = <&mdss_mdp>`), y el fragmento nuevo los alcanza por `target-path`. Eso **ya
  funciona medido** en esta tablet: `s238` hace lo mismo (fragment@156/157 con `target-path`
  sobre `/soc/display_gpio_regulator_vsp/vsn`, que **también** los crea el payload — no están en
  `base-dtb.img`) y el resultado está vivo (`status: disabled`, §3.1). Para no depender de cómo
  ordene el aplicador, el fragmento va **numerado por encima de todo lo existente (2100+)**:
  queda el último tanto en orden de fichero como numérico (los creadores son 94/95/96).

### 4.3 El fragmento (entregable)

`build/gates/FRAGMENTO-GPIO.dts` — tres bloques `fragment@2100/2101/2102`, cada uno con
`target-path` al nodo y `__overlay__ { status = "disabled"; }`. **No añade ningún phandle** (ni
literal ni por etiqueta): no toca `__fixups__`/`__symbols__` (R-24: un phandle colgando cuelga el
arranque). Es el mismo formato que `FRAGMENTO-PHY.dts` (bloques para insertar en el payload
descompilado).

---

## 5. Integración futura (para el constructor de `s254`)

NO construyo `s254`: lo integra el orquestador. Instrucciones exactas, calcadas del patrón
`mkdtbo-s238.py` / `mkdtbo-s253.py`:

1. **Base:** `s253` (`build/bootimg/s253-boot-dtbo-aprima.img`, sha
   `eeb57d95a5454afdfc4312264a84a612ab2fa67d29eb1c98fa3754a82765a4e1`, 607 714 B). Si se prefiere
   el par ya probado, vale `s238` (`bdb361df…`); §6 valida **los dos**.
2. **DTB base real:** `~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img`, sha
   `3f973c78f7dc6a66f1acea363be27774c51ff174fbf71117ebe74c385547562e` (el que usan todos los
   constructores; pinearlo en G0).
3. **Payload:** `dtbo-extract.py <img> payload.dtbo` → `dtc -I dtb -O dts -o payload.dts
   payload.dtbo`.
4. **Inserción:** copiar **verbatim** los tres bloques `fragment@2100/2101/2102` de
   `build/gates/FRAGMENTO-GPIO.dts` **antes del último `};`** del `payload.dts` (igual que
   `mkdtbo-s238.py:213-219`). No hay que tocar nada más del payload.
5. **Recompilar y fusionar:** `dtc -I dts -O dtb -o payload-s254.dtb payload.dts` (los warnings de
   `reg_format`/`interrupts_property` son del vendor y son normales) y
   `fdtoverlay -i base-dtb.img -o fusionado.dtb payload-s254.dtb`.
6. **Target-paths exactos** (los tres, tal cual):
   - `/soc/qcom,mdss_mdp@ae00000/qcom,mdss_dsi_o82_36_02_0a_dualdsi_dsc_vid`
   - `/soc/qcom,mdss_mdp@ae00000/qcom,mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid`
   - `/soc/qcom,mdss_mdp@ae00000/qcom,mdss_dsi_visionox_r66451_fhd_plus_video`
7. **Phandles:** ninguno (por diseño). Si algún día se quisiera repuntar la propiedad en vez de
   deshabilitar, el phandle del tlmm es `0x16b` (literal, estable en este flujo), pero **no se
   recomienda** (§4.2).
8. **Empaquetado:** cabecera `dt_table` como en `mkdtbo-s253.py:821-836`; tamaño del payload
   medido con este fragmento = **608 106 B** ⇒ imagen **608 170 B** ≤ 610 304 (`dtbo_b`), margen
   2 134 B.
9. **Gates a añadir al constructor** (con `die()`; §6 trae los comandos exactos):
   - **G-GPIO-1**: los 3 nodos existen en el fusionado y **no** tenían `status` antes; después los
     3 tienen `status = "disabled"`.
   - **G-GPIO-2**: refs **activas** a `<0x16b 0x02` en el fusionado **== 1** (solo `panel@0`),
     partiendo de 4.
   - **G-GPIO-3**: pin 74 y 75 siguen con **1** ref activa; el diff del recuento vs `s253` es
     **solo** pin 2 (3 refs) y pin 168 (2 refs menos: los dos o82 deshabilitados también eran sus
     `mi,esd-err-irq-gpio`; inerte, sin driver).
   - **G-GPIO-4**: `panel@0` conserva `reset-gpios = <0x16b 0x02 0x01>`, sus 3 supplies y sus
     `pinctrl-0/1`; los nodos vendor conservan todas sus props (solo se les añade `status`).
   - **G-GPIO-5**: diff semántico vs `s253` = **exactamente 3 líneas**; el fragmento no añade
     `phandle`, ni `&`, ni entradas en `__fixups__`/`__local_fixups__`.
   - **G-GPIO-6 (autoprobado)**: los mismos gates aplicados a `s238`/`s253` deben contar **4** refs
     activas a pin 2 y **abortar**.

---

## 6. Validación offline (comandos y salidas)

Todo en `/tmp/sg-gpio` (temporal; no se escribió nada en `~/gpu-work` ni en la tablet). Herramientas:
`dtc`, `fdtoverlay`, `fdtget` (presentes: `/usr/sbin/…`).

### 6.0 Inputs pineados

```
$ sha256sum ~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img
3f973c78f7dc6a66f1acea363be27774c51ff174fbf71117ebe74c385547562e  base-dtb.img
$ sha256sum build/bootimg/s238-boot-dtbo-dedup-gpio.img
bdb361dff87de52dd7d4581c7f4007abdaf98ac145d47658ef2a29bc458f0022
$ sha256sum build/bootimg/s253-boot-dtbo-aprima.img
eeb57d95a5454afdfc4312264a84a612ab2fa67d29eb1c98fa3754a82765a4e1
```

### 6.1 Los nodos destino existen y el pin 2 tiene 4 refs (antes)

```
$ grep -n "0x16b 0x02" dt-fusionado-s238.dts
980:					reset-gpios = <0x16b 0x02 0x01>;
22240:				qcom,platform-reset-gpio = <0x16b 0x02 0x00>;
22471:				qcom,platform-reset-gpio = <0x16b 0x02 0x00>;
22681:				qcom,platform-reset-gpio = <0x16b 0x02 0x00>;

$ fdtget -t x fused-s238.dtb /soc/qcom,mdss_mdp@ae00000/qcom,mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid qcom,platform-reset-gpio
16b 2 0
$ fdtget fused-s238.dtb …/qcom,mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid status
Error at 'status': FDT_ERR_NOTFOUND      ← "available": el escaneo lo cuenta
```
(los 3 nodos responden igual; ninguno tiene `compatible`.)

### 6.2 Los dos caminos de aplicación dan el mismo árbol

```
# Camino constructor (el que usará s254): payload s238 + 3 fragmentos, recompilado
$ python3 - <<'EOF'   # inserta los fragmentos de FRAGMENTO-GPIO.dts antes del último "};"
  … (extrae los bloques desde la 1ª línea que empieza por "\tfragment@") …
$ dtc -I dts -O dtb -o payload-s254.dtb payload-s254.dts     # rc=0 (solo warnings del vendor)
$ fdtoverlay -i base-dtb.img -o fused-s254-constructor.dtb payload-s254.dtb   # OK
$ dtc -I dtb -O dts -o fused-s254-constructor.dts fused-s254-constructor.dtb

# Camino overlay independiente: los MISMOS bloques como .dts suelto aplicado sobre el s238 ya fusionado
$ dtc -I dts -O dtb -o frag-gpio-standalone.dtbo frag-gpio-standalone.dts    # OK
$ fdtoverlay -i fused-s238.dtb -o fused-s254-standalone.dtb frag-gpio-standalone.dtbo   # OK
$ cmp fused-s254-standalone.dts fused-s254-constructor.dts
IDENTICOS
```

**Diff del fusionado (s238 → s254): exactamente 3 líneas**

```
$ diff fused-s238.dts fused-s254-constructor.dts
22179a22180
> 				status = "disabled";
22410a22412
> 				status = "disabled";
22641a22644
> 				status = "disabled";
$ diff fused-s238.dts fused-s254-constructor.dts | grep -c '^[<>]'
3
```

**Sobre `s253` (la base que toca en el plan: `s254 = s253 + GPIO2`): también 3 líneas**

```
$ fdtoverlay -i base-dtb.img -o fused-s253.dtb s253.dtbo && dtc -I dtb -O dts -o fused-s253.dts fused-s253.dtb
$ (protocolo de 6.2 con el payload de s253)
$ diff fused-s253.dts fused-s254-base253.dts | grep -c '^[<>]'
3
```

### 6.3 El pin 2 queda con UNA sola referencia activa

Emulador del filtro de `gpiolib-shared.c:159-298` + regla de nodos ignorados (:136-157) sobre el
`.dts` fusionado (`/tmp/sg-gpio/count-gpio-refs.py <fused.dts> 0x16b`):

```
############ ANTES (s238) ############
pin 2   activas=4
    reset-gpios  … /display-subsystem@ae00000/dsi@ae94000/panel@0 flags=0x1
    qcom,platform-reset-gpio  … qcom,mdss_dsi_o82_36_02_0a_dualdsi_dsc_vid flags=0x0
    qcom,platform-reset-gpio  … qcom,mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid flags=0x0
    qcom,platform-reset-gpio  … qcom,mdss_dsi_visionox_r66451_fhd_plus_video flags=0x0
pin 74  activas=1        pin 75  activas=1
TOTAL refs activas a 0x16b: 38

############ DESPUES (s238 + FRAGMENTO-GPIO) ############
pin 2   activas=1
    reset-gpios  … /display-subsystem@ae00000/dsi@ae94000/panel@0 flags=0x1
pin 74  activas=1        pin 75  activas=1
TOTAL refs activas a 0x16b: 33
```

(38−33 = 5: las 3 del pin 2 + las 2 del pin 168, que eran `mi,esd-err-irq-gpio` de los dos o82
ahora deshabilitados; entrada inerte sin driver.) El mismo recuento sobre
`fused-s254-base253.dts` da identicamente `pin 2 activas=1`.

Con eso, la decisión del kernel queda: pin 2 = **1 real + 1 sintética (`is_reset_gpio`) = 2** ⇒
`gpio_shared_entry_is_really_shared()` = **false** (gpiolib-shared.c:747-759) ⇒
`gpio_shared_free_exclusive()` descarta la entrada ⇒ **nunca se marca `GPIOD_FLAG_SHARED`** ⇒ el
`devm_gpiod_get("reset")` del panel va **directo** al tlmm. La polaridad se conserva: el `flags`
`0x01` (ACTIVE_LOW) sigue aplicándose por el camino directo
(`of_find_gpio` → `of_convert_gpio_flags`, gpiolib-of.c, `*flags |= GPIO_ACTIVE_LOW`; antes se
aplicaba igual vía la lookup del proxy).

### 6.4 Gates de forma sobre el resultado

```
$ for n in qcom,mdss_dsi_o82_36_02_0a_dualdsi_dsc_vid qcom,mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid \
           qcom,mdss_dsi_visionox_r66451_fhd_plus_video; do \
      fdtget fused-s254-constructor.dtb /soc/qcom,mdss_mdp@ae00000/$n status; done
disabled
disabled
disabled

$ fdtget -t x fused-s254-constructor.dtb /soc/display-subsystem@ae00000/dsi@ae94000/panel@0 reset-gpios
16b 2 1                                   ← intacto
$ fdtget fused-s254-constructor.dtb …/panel@0 pinctrl-names
default sleep                             ← intacto
$ fdtget fused-s254-constructor.dtb /soc/uke-regulator-display-vsp regulator-name
uke_panel_vsp                             ← intacto
$ fdtget -t x fused-s254-base253.dtb /soc/apps-smmu@15000000 reg
15000000 200000                           ← A′ (s253) intacto
$ fdtget fused-s254-base253.dtb /soc/apps-smmu@15000000 compatible
qcom,sm8550-smmu-500 qcom,smmu-500 arm,mmu-500   ← A′ (s253) intacto

# diff de props del nodo o82_42 antes/después: solo se añade "status"
$ diff <(fdtget -p fused-s238.dtb …/qcom,mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid | tr ' ' '\n' | sort) \
       <(fdtget -p fused-s254-constructor.dtb …/qcom,mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid | tr ' ' '\n' | sort)
66a67
> status
```

Tamaño y autoprobado (control negativo):

```
$ python3 -c "print(608106+64, 610304-(608106+64))"
608170 2134                                ← cabe en dtbo_b con 2 134 B de margen
# G-GPIO-6: el contador sobre s238/s253 (sin fragmento) da pin 2 = 4 refs ⇒ los gates abortan.
```

---

## 7. Riesgos

1. **Resolución de `target-path` sobre nodos creados por el propio payload.** El fragmento
   apunta a nodos que crean los fragment@94/95/96 del mismo dtbo. **Medido que funciona** con el
   patrón idéntico de `s238` (fragment@156/157 → nodos de fragment@98; `status: disabled` vivo en
   la tablet, §3.1) y ordenado para que el aplicador (ABL o `fdtoverlay`) no tenga ambigüedad
   (2100+ va último en orden de fichero y numérico). El hermano documentó un caso en que esto
   falló (`LECCIONES.md` Ronda 36 #3: "hay que editarlo en origen"); su caso era un fragmento
   nuevo con target-path a un nodo del overlay — la diferencia operativa aquí es el **orden**
   (creador 94-96 ≪ 2100-2102) y el respaldo medido. Si aun así el orquestador quiere cinturón y
   tirantes: variante B = insertar `status = "disabled";` **en los cuerpos de los 3 nodos dentro
   de fragment@94/95/96** del payload (mismo efecto, edición en origen). El gate G-GPIO-1/2 lo
   detecta igual antes de flashear.
2. **El fix no se ha probado en hardware** (tablet inaccesible). La verificación es
   `fdtoverlay` + contador + diff de 3 líneas; el ABL podría sorprender (patrón §1, no hay
   precedente de fallo con este orden).
3. **Queda un mundo con proxies que no se toca:** los pines 35/156 (wifi-pmu / bt_wcn6750) y
   157/177 (paneles n16t/vtdr6130, sin driver) siguen compartidos. Hoy **ninguno** tiene driver
   que pida su GPIO salvo, quizá, wifi-pmu/bt. Si el bring-up posterior necesita que wifi-pmu
   pida su gpio, seguirá dependiendo de `gpio-shared-proxy.ko`. **No** es parte de este ciclo (un
   cambio por ciclo), pero conviene anotarlo.
4. **Efecto colateral inerte**: pin 168 pierde sus 2 refs (`mi,esd-err-irq-gpio` de los o82
   deshabilitados). No hay driver que lo use.
5. **El panel pasa a pedir el pin real en exclusiva.** Nadie más lo pide (contador: 1 ref activa;
   los otros 3 consumidores no tienen device). Si un día se quisiera reactivar un panel vendor,
   habría que volver a habilitar su nodo (y entonces el pin volvería a ser compartido).
6. **Medida post-flash (criterios):** éxito = el panel prohíbe (sigue el backlight) **y**
   `dmesg | grep -c "gpiolib_shared.proxy"` sin nuevas entradas para pin 2; con el módulo
   descargado (`rmmod gpio_shared_proxy` si se puede) el panel debe seguir proebando — eso
   demostraría la independencia del módulo. Si el panel difiere igual, `dmesg | grep -i "cannot
   find GPIO chip"` dirá qué etiqueta falta (diagnóstico de §2.4).

---

## 8. Entregables y ficheros

| fichero | qué es |
|---|---|
| `build/gates/INFORME-GPIO-RESET.md` | este informe |
| `build/gates/FRAGMENTO-GPIO.dts` | los 3 bloques `fragment@2100/2101/2102` para insertar en el payload de `s254` (formato `s238`/`s253`) |
| DT base real | `~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img` sha `3f973c78…` (**solo lectura**, no se modificó) |
| payloads de prueba | `/tmp/sg-gpio/{payload-s254*.dtb, fused-s254*.dts, count-gpio-refs.py}` (temporales) |

Sin commits, sin escrituras en `~/gpu-work/palawan-linux` (solo lecturas), sin tocar la tablet,
sin editar ficheros existentes del repo.
