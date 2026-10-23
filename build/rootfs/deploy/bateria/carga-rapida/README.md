# Carga rápida en Linux — plan de captura y análisis (19-oct-2026)

## Qué sabemos (evidencia)
- **Linux hoy carga por el firmware**: `qcom-battmgr-bat` da `charge_type=Fast`, pero con el PC (SDP) solo 0,15–0,5 A y con cargador de pared «~1 A» (ESTADO-VIVO) / +1,19 A (ledger #406) / 2,49 A puntual hoy a las 10:15. No hay medida de Linux con un adaptador PD de 45 W.
- **Android en este mismo puerto del PC también va a SDP 500 mA** (`usb_real_type=SDP`, `quick_charge_type=0`, `fastchg_mode=0`, `cp_mode=0`, `pdo2=0`, `apdo_max=0`; dmesg `BATTERY_CHG: … chg_type=SDP tl:=4 ffc=0, pd_verifed=0`). Rectifico mi afirmación anterior de «Android carga a ~3 A por este puerto»: no está verificada; la subida de rm tras arrancar fue la recalibración del gauge/carga previa.
- **La bomba de carga bq2597x no es de Linux**: no hay dispositivo I2C bq2597x en el AP (solo `i2c-9 glink-i2c`, es decir, I2C proxied por el ADSP). Sus datos (`bq2597x_*`, `cp_mode`) llegan por pmic_glink desde el ADSP. Linux solo necesita ADSP + pmic_glink + battmgr (+ ucsi_glink), que ya están.
- **Lo que Android añade y Linux no**: el driver Xiaomi `qti_battery_charger` (trazas `BATTERY_CHG:`) llama `battery_psy_set_charge_current` con nivel térmico (`tl`), `ffc` y `pd_verifed` (autenticación del adaptador Xiaomi: `authentic`, `verify_digest`, `request_vdm_cmd`, servicios `micharge-hal`/`batterysecret`). El `qcom_battmgr` de mainline no fija corriente de carga. Un parche de jun-2026 en LKML añade mitigación térmica con límite FCC ([patch](https://lkml.rescloud.iu.edu/hypermail/linux/kernel/2606.1/03398.html)); sirve de modelo para escribir el límite (`charge_control_limit`-like) pero no es PD ni autenticación.
- Especificación del aparato: 45 W (PD3.0/PPS, QC3+), batería `O82_8850mah_45w` ([ficha Xiaomi](https://www.mi.com/global/product/xiaomi-pad-7/specs/)). Sin cargador de pared no se ha comprobado nada de 45 W en ningún SO.

## Resultado Android con cargador de pared (19-oct 11:38, `build/android/bateria-20261019/carga-rapida/pared-20261019-113806.txt`)
- `usb_real_type=PD_PPS`, `quick_charge_type=1`, `cp_mode=4` (bomba de carga activa), `apdo_max=power_max=33` (adaptador PPS de **33 W**, no 45), bus de la bomba 9,25 V / 1,4 A (~13 W), batería **+2,6–2,9 A a 4,45 V (~12 W)**, `usb_ilim=3000000`.
- **`pd_verifed=0`, `authentic=0`**: la carga rápida PPS funciona **sin** autenticación Xiaomi con este adaptador. Traza del ADSP: `qbg_update_status: … fcc: StepChgJeit-5350, icl: chg_det-3000` → el propio firmware ADSP decide FCC/ICL (perfil escalonado JEITA, 5,35 A máx.); el driver Android `qti_battery_charger` solo informa y aplica límites térmicos (`tl`).
- Conclusión: **H2 refutada** (no hace falta autenticación) y **H1 muy probable**: la negociación PD/PPS y la bomba son del ADSP, que en Linux ya corre. Falta confirmarlo midiendo Linux con este mismo cable.

## Hipótesis (estado)
H1 (probable): el ADSP negocia PPS solo; en Linux debería cargar ~12 W con este cable. H2 (autenticación Xiaomi necesaria): refutada para este adaptador (<=33 W).
Si Linux NO llega: mirar `ucsi_glink`/typec (¿se carga?), el límite térmico (`tl`) y que el ADSP arranque con el PD completo; techo de 3 ciclos.

## Experimento A/B (lo único que falta; lo hace el dueño con el cargador de pared de 45 W)
1. **Android: HECHO** (ver arriba). adb inalámbrico: `192.0.2.17:5555`.
2. **Linux** (cuando vuelva): cargador de pared puesto, en la tablet `uke-carga-captura 120` (copiado antes con deploy.sh o scp por la sesión gestora) y copiar el fichero al PC.
3. Comparar bat_I/usb_V: si Linux ≈ Android → H1 (hecho). Si Linux ≪ Android y Android tiene `pd_verifed=1`/`cp_mode>0` → H2.
Solo-lectura en ambos; no se escribe en settings ni sysfs.

## RESULTADO Linux con el cargador rápido (19-oct 10:53–10:57, log `uke-bateria-log`)
**La carga rápida YA funciona en Linux, sin cambios** (ADSP + pmic_glink + qcom_battmgr; no hay `ucsi_glink` ni `/sys/class/typec`):
| hora | V bat | I carga | W a la batería | % |
|---|---|---|---|---|
| 10:53:09 | 4,425 V | +4,45 A | 19,7 W | 93,5 |
| 10:54:10 | 4,452 V | +4,39 A | 19,5 W | 94,4 |
| 10:55:10 | 4,453 V | +3,99 A | 17,8 W | 95,0 |
| 10:56:11 | 4,452 V | +3,60 A | 16,0 W | 95,6 |
| 10:57:12 | 4,454 V | +3,39 A | 15,1 W | 95,9 |
Mejor que los ~12 W de Android a 72 % (Android estaba en otra fase de carga; no es comparación estricta). La corriente baja por el final de carga (CV a 4,45 V). Con el PC (SDP 500 mA) la batería **no carga**: baja ~0,35 A (1,5 W) aunque `status=Charging`.
Limitación: no se capturó `usb_type`/VBUS del cargador (la unidad `uke-carga-espera` falló por un bug mío, ya corregido); la carga se ve en `/var/log/uke-bateria/2026-10-19.csv`. Para ver la tensión de VBUS (9 V) habría que repetir con `uke-carga-captura 120` y el cable puesto.

## Corrección de signo (importante)
battmgr: `current_now` **>0 = carga**, <0 = descarga (comprobado: +4,4 A con % y charge_counter subiendo; -0,35 A con charge_counter bajando). `uke-bateria-lectura` vuelve a `i = -current_now` (+ = descarga); en el CSV de hoy anterior a las 10:58 `i_a`/`w` tienen el signo contrario (negativo = descarga, positivo = carga) y las «medidas por perfil» previas eran **descarga neta con el cable del PC**: consumo real del sistema ≈ descarga neta + entrada USB (5,19 V × 0,36 A = 1,87 W): ahorro ≈ 3,06 W, rendimiento ≈ 3,63 W, equilibrado ≈ 3,99 W (60 s cada uno, pantalla encendida; el primero pudo estar aún calentándose; indicativo).
