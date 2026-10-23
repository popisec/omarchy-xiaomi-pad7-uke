# Carga lenta en Linux con fuentes no-PD: drivers, firmware y causas (20-oct-2026)

Investigación solo lectura, hecha el 20-oct-2026 entre las 13:04 y las 13:20 CEST. Kernel `7.2.9-senemos.1.4054.3-ouke5 #5`.
No se ha escrito en `/sys`, no se han cargado ni descargado módulos y no se ha reiniciado nada.
Fuentes del kernel: `build/kernel-pokes/senemos-ouke5/linux-7.2.9/`. Mainline: `raw.githubusercontent.com/torvalds/linux/master/drivers/power/supply/qcom_battmgr.c`, descargado el 20-oct (git.kernel.org devolvió 403).

## 1. Estado medido (tablet, 13:04)
```
qcom-battmgr-usb: online=1 usb_type=[SDP] voltage_now=5051000 current_now=928000..931000
                  current_max=1000000 input_current_limit=1000000
qcom-battmgr-bat: status=Charging capacity=2 voltage_now=3598514 ocv=3587584 current_now=+177982 temp=260 health=Good
/sys/class/udc/a600000.ssusb/state = configured (high-speed)   → la fuente es un HOST USB que enumeró el gadget
/sys/class/typec, /sys/class/usb_power_delivery: no existen
/sys/bus/auxiliary/devices: solo pmic_glink.power-supply.0 (no hay .ucsi ni .altmode)
/sys/kernel/config/usb_gadget/g1/configs/c.1/MaxPower = 120
```
- La corriente de entrada, `ibus` = 0,93 A, está pegada al límite de entrada (ICL) de 1,0 A.
- VBUS se mantiene en 5,05 V, sin caída, así que la fuente no se satura y el AICL no está recortando.
- **La tablet está limitada por el ICL que fija el ADSP, no por la batería.**

## 2. Causas, ordenadas por evidencia

**C1. La fuente se detecta como SDP (BC1.2, puerto de datos), y en SDP el ADSP no pasa de 0,5–1 A.** Evidencia fuerte.
- `usb_type=[SDP]` y el UDC está `configured`: es un host que enumera, no un cargador.
- El ICL lo decide el firmware del ADSP. En Android, por el puerto del PC: `typec_mode=Source attached (high current)` (Rp 3 A), `power_operation_mode=3.0A` y `usb_type=SDP`. Aun así, `usb/current_max=500000` e `input_current_limit=500000` (`build/android/bateria-20261019/carga-rapida/estado.txt`).
- Es decir, **Android tampoco pasa de 500 mA en SDP, aunque el puerto anuncie Rp 3 A.** El firmware ignora el Rp cuando la fuente es SDP.
- Con PPS, la traza del ADSP da `icl: chg_det-3000`: el ICL sale de la detección de cargador (chg_det).
- Hoy el ADSP puso `current_max`=ICL=1 A por su cuenta. No fue Linux: `uke-icl` y el driver no pasan de 500000.
- **Hipótesis sin verificar:** sería el puerto USB-C del host con Rp 1,5 A o un USB3/CDP mal clasificado. No se puede ver sin typec.

**C2. En Linux nadie fija el presupuesto de enumeración USB.** Evidencia fuerte. Explica los 100 mA de esta mañana; el arreglo actual con `uke-icl` es solo un parche.
- El firmware arranca el SDP con 100 mA (el «unconfigured» del USB). En Android, el driver USB pide 500 mA al enumerar.
- En Linux, `dwc3` sí tiene ese camino: `dwc3_gadget_vbus_draw` → `dwc3_vbus_draw_work` → `power_supply_set_property(INPUT_CURRENT_LIMIT)` (`drivers/usb/dwc3/core.c:2184-2212`, gadget.c:3152).
- Pero solo se activa si el nodo dwc3 tiene `usb-psy-name`, y el DT vivo **no lo tiene**. Comprobado: no aparece en `of_node` de `/sys/devices/platform/soc/a600000.ssusb`. Solo existe en `native-generated/usb.dts`, que no es el DT que corre.
- Además, el gadget pide `MaxPower=120`, que en el mejor caso daría 120 mA.

**C3. El driver solo deja escribir el ICL hasta 500 mA y solo en SDP.** Evidencia: código. Es un tope del parche Uke, no del hardware.
- `qcom_battmgr.c:1077-1121` (parche Uke): `if (val->intval < 0 || val->intval > 500000) return -EINVAL;` y rechaza cualquier tipo distinto de SDP o por encima de `current_max`.
- De ahí salen los EINVAL con 900000 o más.
- Mainline no permite escribir **nada** en la psy USB: `qcom_battmgr_usb_*` es de solo lectura y solo la batería tiene `set_property`, para los umbrales.

**C4. El consumo del sistema se come casi toda la entrada.** Evidencia: medido.
- 5,05 V × 0,93 A ≈ 4,7 W de entrada, menos ~3,6–4 W del escritorio: quedan ~0,65 W para la batería (+0,18 A a 3,6 V).
- `uke-touchd.py` consume ~36 % de un núcleo (sondeo a 120 Hz).
- Con 500 mA de entrada (2,3 W), la batería apenas carga con la pantalla encendida.

**Descartadas, o sin efecto en este caso:**
- **Tensión baja o precarga:** 3,59 V está por encima del umbral típico de precarga (~3,0 V). La batería admite 4,45 A con PPS (medido el 19-oct), y el FCC del ADSP es `StepChgJeit-5350` (Android). El FCC no es el cuello: lo es el ICL.
- **Térmica o JEITA:** `temp=26,0 °C` y `health=Good`. En Linux nadie fija un nivel térmico: el parche Uke devuelve `-EOPNOTSUPP` a todo `BATTMGR_BAT_PROPERTY_SET` (`qcom_battmgr.c:393-396`), así que el ADSP queda en el nivel 0, que es el máximo. Android mete `tl=4` con la pantalla encendida, pero en SDP da igual.
- **Falta de `ucsi_glink`/typec:** no limita la carga.
  - La PPS de 19,7 W funcionó el 19-oct sin ellos: la política PD/PPS y la bomba de carga están en el ADSP.
  - `ucsi_glink` solo expone puertos, PDOs y `ucsi-source-psy` (informativo). No fija ICL ni FCC (`drivers/usb/typec/ucsi/ucsi_glink.c`: probe, conectores por `reg` y GPIO de orientación).
  - Cargarlo hoy tampoco haría nada: el parche 0032 deja `xiaomi,uke-pmic-glink` con `client_mask = BIT(PMIC_GLINK_CLIENT_BATT)` (`pmic_glink.c:393-397`) y no se crea ningún dispositivo `pmic_glink.ucsi`. También está en la lista negra de `/etc/modprobe.d/uke-carga.conf`.
  - Además, ya dio un Oops (`docs/historia/ESTADO-VIVO.md:431`).
- **Parche LKML de jun-2026** ([2606.1/03398](https://lkml.rescloud.iu.edu/hypermail/linux/kernel/2606.1/03398.html), leído el 20-oct): añade `CHARGE_CONTROL_LIMIT` y un cooling device que **baja** el FCC con `BATT_CHG_CTRL_LIM` (`BATTMGR_BAT_PROPERTY_SET`), solo en la ruta sm8350. Sirve para mitigación térmica y **no sube** la carga. Para Uke habría que mapear el ID 10→10 (no cambia, va antes de `BATT_TEMP`) y levantar el `EOPNOTSUPP`. No aplica a este problema.

## 3. Cambios propuestos

| # | Cambio | Efecto esperado | Riesgo | Probar / revertir |
|---|---|---|---|---|
| P1 | Probar con un **cargador de pared BC1.2 (DCP), USB-A 5 V/2 A** o con el de 33 W. No hay que cambiar nada. | El ADSP debería dar DCP con 1,5–2 A, o PPS. Confirma C1. | Nulo | `uke-carga-captura 120` con el cable puesto: usb_type, ICL, ibus |
| P2 | `MaxPower` del gadget a 500 en el script que crea `g1` (rootfs). | Prepara P3. Solo, no cambia nada. | Bajo | Ver `configs/c.1/MaxPower`; revertir al valor anterior |
| P3 | Añadir `usb-psy-name = "qcom-battmgr-usb"` al nodo dwc3 del DT vivo. **Requiere autorización (flash dtbo/boot).** | El ICL de 500 mA se fija en el kernel al enumerar, y `uke-icl` sobra. | Medio: hay un `device_link` con battmgr, y si battmgr no ha cargado, dwc3 hace `EPROBE_DEFER`, lo que **retrasa el gadget USB (SSH de rescate)** hasta que cargue battmgr (~3,3 s). Hay un precedente en `native-generated/usb.dts` | Gate fdtoverlay + ledger; dmesg `USB budget: request=500 mA result=0`; revertir con el par bueno |
| P4 | Quitar el tope de 500000 del parche Uke y permitir ICL ≤ `current_max` del ADSP (p. ej. 1 A hoy). **Requiere autorización (kernel nuevo).** | Casi nulo: el ADSP ya está a 1 A. | Bajo | — Solo tiene sentido si el ADSP ofrece un `current_max` mayor que el ICL |
| P5 | Fijar el ICL al Rp del puerto (1,5/3 A) en SDP. Exige UCSI para leer el Rp. **Requiere autorización. No recomendado.** | Hasta 7–15 W desde puertos USB-C. | Alto: Android no lo hace; activar UCSI rompe la decisión 0032 (rol fijo en periférico, Oops previo); sobrecargar un puerto que no es USB-C dañaría el host | No proponer sin evidencia de que el firmware lo acepta |
| P6 | Bajar el consumo mientras carga: modo carga (pantalla apagada, ~1,9 W) y arreglar el sondeo de `uke-touchd`. | A 1 A pasa de ~0,65 W a ~2,8 W netos hacia la batería. | Nulo (ya desplegado; el táctil es de otra sesión) | CSV `/var/log/uke-bateria` |

**Recomendación:** para cargar de verdad, usar el cargador de pared (PD/PPS = 19,7 W medidos, o un DCP). Con un PC no hay arreglo de driver que dé más de 0,5–1 A sin ir en contra de la política del firmware (igual que en Android). P2+P3 solo sirven para que el ICL de SDP lo fije el kernel en vez del script.

## 4. Qué medir para confirmar
1. **El mismo cable con un cargador USB-A DCP** (sin PD): si `usb_type=DCP` e ICL ≥ 1,5 A, C1 queda confirmada.
2. **Tipo de puerto de la fuente de 1 A de hoy:** USB-C o USB-A, y si es USB3. Desconectar y volver a conectar con `uke-carga-captura`, y mirar si `current_max` vuelve a 500000 o se queda en 1000000.
3. **Android, mismo puerto que hoy:** `usb/current_max`, `typec_mode`, `power_operation_mode`. Si Android da 1 A ahí, el ADSP se comporta igual en los dos sistemas.
4. **Carga neta con 1 A y pantalla apagada** (modo carga): se esperan unos +0,7 A a 3,6 V.
