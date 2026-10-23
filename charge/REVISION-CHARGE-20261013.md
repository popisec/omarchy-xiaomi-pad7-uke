# REVISIÓN ESCÉPTICA — Pila de carga ADSP/battmgr (13-oct-2026, sin tablet)

Revisor: pila power/PMIC/remoteproc. Alcance exclusivo: `charge/uke-adsp-load.sh`,
`charge/uke-charge-run.sh`, `charge/uke-adsp.service`, los 20 `.ko`, el firmware y la
trampa `qcom,gpr`. NO se revisan panel/PHY/overlays de display. Nada flasheado, nada
arrancado, nada reiniciado; todo verificado en PC (lectura de árbol + `modinfo` +
`depmod` + fuentes del ledger hermano).

## 1. VEREDICTO

**Arrancar la pila con el guion tal cual es SEGURO (no bricks, no wedge, no drenaje),
pero casi con certeza NO CARGARÁ.** El fallo es silencioso y con `exit 0`.

- Seguro porque: todo va por `insmod` tardío (nada built-in nuevo, el wedge documentado
  era solo de símbolos built-in en el arranque — ledger #404.1/#405); cada `insmod`
  fallido se traga como AVISO y sigue; el `echo start` fallido lleva a `exit 1`
  (`uke-adsp-load.sh:88,93-96`); el `release` sin variante aborta en el deploy
  (`uke-charge-run.sh:41`). No hay camino al crash-loop `k52c` desde este guion.
- Ineficaz por el hallazgo H1 (bloqueo del bind por `drivers_autoprobe=0`, §3).
- ¿Cargaría yo? **No con este guion sin el arreglo H1. Con el arreglo H1 + dtbo con
  `gpr disabled` verificado en vivo: sí.**

Efectos laterales del guion aunque falle: `drivers_autoprobe=0` y `dmesg -n 1`
persisten hasta el reboot (sysfs + runtime, no persistentes). Reversibles, pero el
primero es precisamente lo que impide la carga en reintentos sin reboot.

## 2. LA TRAMPA DEL `gpr`: TRAZADO COMPLETO, SIN VENTANA PARA EL DRENAJE

Mecanismo (ledger #406.4): `apr.c` exige `qcom,domain` para `qcom,gpr`; sin ella
`apr_probe` → `-22` → `rpmsg_destroy_ept()` manda CLOSE → el ADSP reabre a ~2,5 ms →
bucle (6420 fallos/38 min, udevd 99 %).

**El bucle exige el ADSP en `running`** (el CLOSE/re-open lo protagoniza el canal
glink, que solo existe con el ADSP vivo). Antes del primer `echo start` no hay bucle
posible en ningún camino. Verificación del orden en `uke-adsp-load.sh`:

| Paso | Línea | Qué hace |
|---|---|---|
| 1. insmods | 43-55 | cargan drivers; con el ADSP parado no crean canales |
| 2. firmware | 57-67 | solo lectura de ficheros |
| 3. `echo 0 > …/rpmsg/drivers_autoprobe` + `dmesg -n 1` | 69-74 | **antes** del start ✓ |
| 4. `echo start` | 86-92 | primer instante en que el bucle podría nacer, ya mitigado |

Tres caminos:

- **(a) s282 flasheado (`gpr disabled`).** El nodo no existe para
  `qcom_glink_match_channel()` (`for_each_available_child`, cf. #406.4) → el device
  rpmsg nace sin `of_node` → ningún driver lo bindea → **no hay bucle ni siquiera con
  `autoprobe=1`**. El paso 3 del guion es innecesario pero inofensivo para el drenaje.
  Imagen en disco verificada: `build/bootimg/s282-boot-dtbo-gpu-display-opp148-nogpr.img`,
  sha `00c34106…eee168d0` == informe §4 == pin del generador. **Pero OJO (§5.3): no hay
  evidencia en el ledger hermano (cero ocurrencias de `s282`) de que esté flasheado en
  la tablet; sus slots llevan kernels/display (K43/K47, s260/s262) o L39.**
- **(b) s281/base con `gpr` vivo.** El driver `apr` va **built-in**
  (`k52L33-build/.config:7299 CONFIG_QCOM_APR=y`): al boot da UN `-22` suelto (sin
  bucle, ADSP parado). El paso 3 precede al start → el re-open post-start crea devices
  sin probe → **bucle contenido, udevd quieto**. Sin ventana de drenaje. Verificado por
  construcción; la mitigación es la misma que el hermano probó en caliente (#406.4).
- **(c) Reboots/reintentos.** `autoprobe` y `dmesg -n` son runtime (se pierden al
  reboot); el servicio los repone antes de cada start. Sin ventana acumulada.

**Conclusión trampa: el drenaje está bien mitigado en tiempo y forma. El problema es
el contrario: la mitigación, aplicada ANTES del bind, mata la carga (H1).**

## 3. HALLAZGOS POR GRAVEDAD

### H1 — ALTA (eficacia): `drivers_autoprobe=0` antes del start impide el bind de `pmic_glink` → no hay battmgr → no hay carga

- `pmic_glink` es un **`struct rpmsg_driver`** (`k52L33-tree/drivers/soc/qcom/pmic_glink.c:289`,
  registrado en `:445`). Sus canales aparecen DESPUÉS del `echo start`.
- Con `autoprobe=0`, el core salta el attach en las DOS direcciones:
  driver-nuevo (`drivers/base/bus.c:762-766`: `if (sp->drivers_autoprobe) driver_attach`)
  y device-nuevo (`drivers/base/dd.c:1167-1168`: `if (sp->drivers_autoprobe)
  __device_attach`; los canales rpmsg entran por `device_add` en
  `drivers/rpmsg/rpmsg_core.c:546`). El canal `pmic_glink` post-start queda huérfano.
- Sin bind de `pmic_glink` no hay devices auxiliares (`qcom_battmgr` es
  `auxiliary_driver`, `qcom_battmgr.c:1816-1822`, creado por pmic_glink) → el paso 5
  (`uke-adsp-load.sh:101-106`) no imprime nada → **`service_up=false` / `-EAGAIN`,
  el síntoma exacto de #404.4, con `exit 0`**.
- Por qué al hermano sí le funcionó: su `echo 0 > drivers_autoprobe` (#406.4) se aplicó
  **en caliente con los binds ya hechos** (los devices bindeados siguen funcionando);
  y su carga "en frío" verificada corrió tras reboot (= `autoprobe` vuelto a 1) con el
  s207. El guion nuevo invierte el orden: **0 antes del bind**. La mitigación es
  orden-sensible y está copiada al momento equivocado.
- **Arreglo propuesto (sin tocar CONFIG_*):** consultar el DT vivo y actuar en
  consecuencia — si `/proc/device-tree/soc/remoteproc-adsp@*/glink-edge/qcom,gpr/status`
  == `disabled`, NO tocar `autoprobe`; si está vivo, `autoprobe=0` → `echo start` →
  bind explícito SOLO de `pmic_glink`
  (`echo <dev> > /sys/bus/rpmsg/drivers/qcom_pmic_glink/bind`, o re-`echo 1 >
  drivers_autoprobe` solo tras el settle si el dtbo es s282) → verificar que aparecen
  `qcom-battmgr-*` y **fallar (`exit 1`) si no aparecen**. Nunca `exit 0` sin battmgr.

### H2 — MEDIA (eficacia en kernel todo-módulos): orden de `insmod` incompatible con las dependencias reales

- El guion usa `insmod` (sin resolución de deps) en el orden
  `qcom_common → qcom_q6v5 → qcom_pil_info → qcom_q6v5_pas → … → qcom_glink_smem`
  (`uke-adsp-load.sh:44-49`). Pero `depmod -b` sobre el stage real dice
  (`charge/stage-7.2.0-rc2-palawan/.../modules.dep`):
  `qcom_common.ko: qcom_glink_smem.ko` y
  `qcom_q6v5_pas.ko: qcom_pil_info.ko qcom_common.ko qcom_glink_smem.ko qcom_q6v5.ko`.
  (`modinfo -F depends` dice vacío porque los lotes `M=` se compilaron por separado;
  el `depmod` es la verdad de suelo: símbolos indefinidos reales.)
- En un kernel estilo K5 (todo `=m`), `insmod qcom_common.ko` falla (símbolo desconocido),
  el fallo se traga como AVISO (`load_one`, `:32-36`, siempre `return 0`), `pas` falla en
  cascada y no hay remoteproc → `exit 1` "no hay remoteproc adsp". Falla cerrado (seguro),
  pero **el guion no funciona en la configuración para la que se compilaron los `.ko`**.
- Enmascarado hoy porque el L33 lleva `PIL_INFO/RPROC_COMMON/Q6V5_COMMON/Q6V5_PAS/
  GLINK_SMEM/QRTR_SMD/PD_MAPPER=y` built-in (`k52L33-build/.config` verificado): los
  `/sys/module` existen y todo se salta; solo entran `pmic_glink → ucsi/battmgr`, cuyo
  orden sí es correcto. Frágil ante cualquier kernel que cambie un `=y` por `=m`.
- **Arreglo:** reordenar a `qcom_glink_smem → qcom_common → qcom_q6v5 → qcom_pil_info →
  qcom_q6v5_pas → qrtr-smd → qcom_pd_mapper → pmic_glink → ucsi_glink → qcom_battmgr`
  (orden topológico del `modules.dep` medido), o mejor: `modprobe -d` contra un
  `modules.dep` desplegado en vez de `insmod` a mano.

### H3 — MEDIA (diagnóstico): el veredicto nunca suspende; `exit 0` sin carga

- El paso 5 imprime pero no comprueba nada: sin `qcom-battmgr-*`, sin `charger_pd` en
  dmesg, o con `status=Discharging`, el servicio queda `active (exited)` y el deploy
  (`uke-charge-run.sh:70`) reporta `is-active` en verde. El operador debe leer el texto.
- Falta el chequeo que el hermano SÍ hacía desde el PC: locator anunciado (servicio
  QRTR `0x40`, `uke-adsp-load.sh` del hermano paso 5) y `dmesg | grep PDM`. El guion
  nuevo no mira `PDM: no support for the platform` en ningún punto.
- **Arreglo:** gatear `exit 1` si (i) no hay `qcom-battmgr-bat`, (ii) no hay
  `charger_pd` en dmesg, (iii) `pd_mapper` dijo `no support`. Es lo que convierte el
  "veredicto" en veredicto.

### H4 — BAJA (higiene, prueba de que el guion nunca corrió en caliente)

- `:101`: `"$FWDIR/../class/power_supply"/qcom-battmgr-*` = `/lib/class/power_supply/*`
  (no existe; el segundo glob lo rescata). Cosmético pero delata cero ejecuciones.
- `load_one qcom_glink qcom_glink.ko` (`:48`): ese `.ko` **no existe** (el core glink es
  `CONFIG_RPMSG_QCOM_GLINK=y` built-in; el stage trae 10 `.ko`, sin `qcom_glink.ko`) →
  AVISO espurio siempre. Renombrar a `qcom_glink_smem` o eliminar la línea.
- Sin `timeout` en el `echo start` (el hermano usaba `timeout 30 …`, paso 4); un
  remoteproc colgado deja al oneshot en `D` hasta el `TimeoutStartSec` de systemd.
- `dmesg -n 1` oculta la consola justo cuando más se necesita (el wedge es mudo por
  definición); aceptable como anti-spam, pero restaurar `dmesg -n 7` (regla 2 del
  proyecto hermano) tras el settle ayudaría al diagnóstico.
- `uke-adsp.service:3`: `Documentation=file:///root/charge/…` apunta a un path que no
  existe en la tablet. Cosmético.
- `uke-charge-run.sh:58`: `cp -f` sin verificar conteo/vermagic en destino; un stage
  rancio en `/tmp/uke-mods-stage` podría mezclar variantes (mismo nombre de fichero,
  distinto vermagic → `insmod` falla → AVISO silencioso). Limpiar el stage antes de
  copiar.

## 4. QUÉ FALTA PARA QUE LA BATERÍA FUNCIONE DE VERDAD

1. **Arreglos H1+H2+H3** (cero cambios de `CONFIG_*`, solo el loader y el veredicto).
2. **Confirmar en vivo qué dtbo/kernel arranca** (hoy incierto: el ledger hermano no
   contiene `s282`; sus slots van por display/K43-K47/s260-s262 o L39 — §5.3). Si no es
   s282, flashear el dtbo con `gpr disabled` (ciclo con flash, fuera de alcance aquí).
3. **Cadena completa en orden** (ya contemplada si H1/H2 se arreglan): firmware en
   `/lib/firmware` (coincide con #404: es el path que lee el PAS; `firmware_class.path`
   custom no consta en el árbol ni en el ledger → **incertidumbre explícita** si el
   rootfs de la tablet lo overridea) + `qcom_q6v5_pas` → `glink_smem` → `qrtr_smd` →
   **`qcom_pd_mapper` ANTES de `pmic_glink`** (parche `qcom,cliffs`/`cliffs-mtp`
   verificado en el árbol, `qcom_pd_mapper.c:602-606`; el `.ko` de ambas variantes lo
   hereda por ser misma fuente — confirmado EN LOS BINARIOS:
   `strings qcom_pd_mapper.ko | grep -E 'cliffs|palawan'` da
   `qcom,cliffs` + `qcom,cliffs-mtp` + `qcom,palawan` en AMBAS variantes) → `echo start` → PDR `charger_pd` UP (`0x1fffffff`) → `pmic_glink`
   bindea → `battmgr` expone `status=Charging, current_now>0, charge_type=Fast`.
4. **Cargador de pared** en el primer ciclo (batería ~3439-3555 mV < gate 3700; en
   fastboot no carga).

## 5. LO QUE ESTÁ BIEN (una línea por acierto)

- Dos variantes de vermagic exactas (`modinfo` 10/10 por variante, verificado) porque el
  `uname -r` es incierto con la tablet caída.
- El deploy **para de verdad** si no hay variante (`uke-charge-run.sh:41`) con mensaje
  accionable; el gate de vermagic por `.ko` (`:42-46`) también aborta (re-simulado en
  local: OK/OK).
- `insmod` tardío fuera de udev/kmod (`/usr/local/share/uke/mods`) evita exactamente el
  wedge de built-ins (#404/#405/k52c).
- `qcom_pd_mapper` antes de `pmic_glink` respeta la lección del locator (#406.1).
- Parche `cliffs` presente en la fuente de compilación (`qcom_pd_mapper.c:605-606`).
- Parche de dialecto battmgr `0x50`+`complete(&ack)` presente (`qcom_battmgr.c:43,124,
  1410,1439,1471,1652`).
- Firmware: 56/56 ficheros con `SHA256SUMS`, 51 segmentos `bNN` ≥ gate 49 (b24/b51
  ausentes = normal); deploy los copia todos incl. `adsp_dtb.*`.
- `fdtoverlay` + `uke-dtbo-check.py` + paridad s281 + `gpr disabled` verificados para
  s282 (report G0-G7 todo OK; sha en disco == pre-registro).
- `CONFIG_MODULE_SIG`/`MODVERSIONS` unset: sin firmas que bloqueen el `insmod`, sin
  CRCs falsos que lo enmascaren (riesgo declarado correctamente en informe §5.6).
- `ConditionPathExists` en el service evita arranques a medias (falla cerrado).
- `gpio_shared_proxy` (panel) correctamente excluido del camino de carga.
- `pmic_glink_altmode.ko` correctamente excluido (símbolos DRM-DP ausentes, irrelevante).
- Informe honesto sobre `insmod --dry-run` inexistente y el WARNING de `modules.order`.
