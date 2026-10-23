# Batería, consumo y carga de uke en ANDROID: mapa de referencia (20-oct-2026, 22:06–22:21 CEST)

Medido en la tablet con Android (HyperOS, root Magisk), uptime 7–18 min, por adb inalámbrico `192.0.2.14:5555`,
**solo lectura**. Conectada al PC por USB (SDP). Datos crudos en `build/android/bateria-20261019/mapa/`.
Contexto que condiciona los números: **YouTube reproduciendo vídeo** (wakelock `AudioMix`, `video 8m42s` en
batterystats, `ExoPlayer` en cpuinfo), carga 6–7, CPU 73–90 °C, y **otra sesión (lápiz, `lapiz-cap8`) usando la
tablet a la vez** (el dueño la estaba usando físicamente). No es reposo.

## 1. Mapa de fuentes de datos (signo verificado)

Convención de signo en ANDROID: **corriente > 0 = DESCARGA, < 0 = CARGA** (al revés que `qcom_battmgr` en Linux,
donde `current_now` > 0 = carga). Evidencia: con SDP 500 mA y vídeo, `current_now` medio +0,48 A mientras `fg1_rm`
baja 5610→5602 mAh y `fg1_rsoc` 6340→6331 en 297 s; el 19-oct con PD_PPS `current_now` −2,86 A y qbg
`ibat` −2882 mA con `brm` subiendo 620→635 (`carga-rapida/dmesg-carga.txt`). Al arrancar (9 s) qbg `ibat` +2846 mA
(descarga fuerte del arranque).

### /sys/class/power_supply/battery (driver Xiaomi `qti_battery_charger`)
| atributo | valor 22:06 | unidad / significado | signo / nota |
|---|---|---|---|
| capacity | 63 | % UI (entero) = `dumpsys battery level` | idéntico en 105/105 muestras |
| charge_counter | 5614 | **mAh** (¡no µAh como en Linux!) = `fg1_rm` | igual a fg1_rm en 105/105 muestras |
| charge_full / _design | 8 850 000 | µAh | `fg1_fcc`=8850 hoy (8810 el 19-oct) |
| current_now | +942 650 | µA instantánea | **+ = descarga**; **sesgada al alza** por el propio muestreo (ver §3) |
| current_avg | 0 | — | sin uso en Android |
| voltage_now / voltage_ocv / voltage_max | 4,065 / 4,068 / 4,480 V | µV | Vmax 4,48 V (FV) |
| power_now / power_avg | 91 482 072 / 65 119 467 | ¿? valor no físico, casi constante | **no usar** |
| constant_charge_current | 5 780 000 | µA = FCC máx. (`fg1_current_max`, «PdAuth-5780») | — |
| charge_control_limit (_max 16) | 0 / 4 | **nivel térmico `tl`** del driver | verificado: `tl:=0` en dmesg a 965,02 s ↔ ccl 4→0 a 965,4 s |
| charge_control_start/end_threshold | 70 / 80 | % límite de carga (no actúa: carga hasta 100 por defecto) | — |
| charge_type / status | Fast / Charging | etiqueta | «Charging» aunque la batería **descargue** (SDP < consumo) |
| temp | 270 | décimas de °C | — |
| time_to_empty_avg / time_to_full_* | 77023 / −1 | s | — |
| cycle_count | 93 | ciclos (= fg1_cycle, fake_cycle) | — |
| model_name | O82_8850mah_45w | — | celda SAMSUNG, pack NVT |

### /sys/class/power_supply/usb, ucsi-source-psy-…ucsi1, wireless
| atributo | valor | significado |
|---|---|---|
| usb/voltage_now | 5,05–5,06 V | VBUS medido (varía en el 3.er dígito → medido) |
| usb/current_now | 453–456 mA | IBUS (= `ibus_ua` del log Xiaomi); casi constante: saturado contra ICL. **No verificado con medidor externo** |
| usb/input_current_limit, current_max | 500 000 µA | ICL efectivo (SDP) |
| usb/usb_type | [SDP] | tipo detectado (BC1.2) |
| ucsi…/usb_type, voltage_* , current_max | [C] PD PD_PPS, 5 V, 3 A | rol UCSI (Rp «high current» del PC, sin contrato PD) |
| wireless/* | online=0; current_now/voltage_now **copian el USB** | no usar |

### /sys/class/qcom-battery (nodo Xiaomi, datos del ADSP por pmic_glink)
| atributo | valor | significado / unidad | evidencia |
|---|---|---|---|
| fg1_rm | 5614 | mAh restantes (coulomb counter del gauge), resolución 1 mAh | = charge_counter; baja 8 mAh en 297 s |
| fg1_rsoc | 6344 | SOC en centésimas de % = rm/fcc | |rsoc/100 − 100·rm/fcc| ≤ 0,011 pt en 105 muestras |
| fg1_fcc / fg1_soh / soh | 8850 / 100 / 100 | mAh / % | — |
| fg1_ai | 107 628…1 174 704 | µA, **corriente media** del gauge (+ = descarga), refresco ~20 s | media fase A 0,355 A, fase C 0,116 A |
| fg1_current_max | 5 780 000 | µA FCC máx. del perfil | = constant_charge_current |
| fg1_tremq / fg1_tfullq / qbg_curr | 0 | sin uso con este gauge | — |
| soc_decimal / soc_decimal_rate | 53→39 / 33 | decimales de la animación de carga de la UI (rate = velocidad) | **hipótesis**: baja 10 por −0,16 pt de rsoc; no es la fracción de rsoc |
| real_type = usb_real_type | SDP | tipo de adaptador (SDP/DCP/PD/PD_PPS…) | PD_PPS el 19-oct |
| quick_charge_type | 0 | 0 normal, 1 rápida | 1 con PD_PPS (19-oct) |
| cp_mode | 0 | modo bomba bq2597x (0 off; 4 = 2:1 activa con PPS) | 19-oct |
| bq2597x_bus_voltage / _bus_current | 165 / 5 | mV / mA del bus de la bomba (ruido en reposo) | 9,25 V / 1,4 A el 19-oct |
| bq2597x_battery_voltage | 4365 | mV (último valor latched, no sigue a Vbat sin bomba) | — |
| apdo_max / power_max / pdo2 | 0 / 0 / 0 | W máx. PPS / W del adaptador / PDO | 33 / 33 con el cargador de pared |
| pd_verifed / authentic / bap_match | 0 / 1 / 1 | auth. del adaptador Xiaomi / de la batería | carga rápida PPS sin pd_verifed (19-oct) |
| typec_mode | Source attached (high current) | Rp del puerto | — |
| thermal_board_temp | 293–322 | décimas °C (placa) | — |
| thermal_scene | 0/11/15 | escena térmica MIUI (11 = vídeo?, 15 = otra) | dmesg `set thermal_scene` |
| smart_chg / night_charging / restrict_chg / restrict_cur | 0/0/0/1 000 000 | carga inteligente / nocturna / restricción (µA) | inactivos |
| ut_test | `cycle_volt…cycle_step_curr,0,800,8000,6000,5400,3476…temp_term_curr…thermal,8200,7200,6800,6400…` | **tabla del perfil de carga** (FV por ciclos, corrientes por paso, terminación) | `ut_test_parse: chg_cfg = 3 pack_vendor = NVT` |
| fake_soc / fake_temp / fake_cycle | −22 / 0 / 93 | depuración (sin uso) | — |

Trazas `BATTERY_CHG` en dmesg (`dmesg-qbg-221650.txt`): `[ADSP] qbg_update_status:: ssoc, rsoc, raw_soc, vbat (mV),
ibat (mA, + = descarga), btemp (d°C), brm (×10 mAh), bfcc (×10 mAh), bcc (ciclos), fcc: <regla>-<mA>, icl: <regla>-<mA>`
cada **10 s**, independiente de nuestro muestreo → es la mejor fuente de corriente no sesgada en Android.

## 2. Exactitud del % (105 muestras cada ~4 s, 22:07:59–22:16:42)
- capacity (UI) = `dumpsys battery level` = 63 en todas; rsoc 63,40 → 63,23 %; rm/fcc coincide con rsoc/100 a ±0,011 pt.
- **% exacto = `fg1_rsoc`/100 = `charge_counter`/`fg1_fcc`** (en Android charge_counter va en mAh). En Linux,
  `charge_counter(µAh)/charge_full` es la misma magnitud (ya validado el 19-oct).
- La UI redondea/suaviza: el 19-oct mostraba 66 con rsoc 65,83 y 67 con 68,75 (retraso ~1 pt en carga rápida). Hoy,
  en 9 min de descarga lenta no hubo cruce de entero → **retraso no medible hoy**; requiere la fase de descarga.
- Resolución útil: rm 1 mAh = 0,011 pt; rsoc 0,01 pt.

## 3. Consumo del sistema con el PC (SDP 500 mA)
Sistema = entrada USB + descarga de la batería. Entrada USB: 5,055 V × 0,456 A = **2,305 W** (constante, ICL
saturado; valor del PMIC, sin medidor externo).

**Hallazgo de método**: `current_now` leído por adb sale **sesgado al alza** porque el muestreo (adb + su + dumpsys)
despierta la CPU justo al leerlo. Tres estimadores de la misma descarga:

| fase (pantalla encendida, vídeo YouTube, 60 Hz, brillo auto 32–74 de settings ≈ 591/4095 backlight, 45–72 % de barra) | current_now | fg1_ai | qbg ibat (ADSP, 10 s) | Δrm (coulomb) |
|---|---|---|---|---|
| A 22:07:59–22:12:56 (297 s, n=75/29) | 0,476 ± 0,054 A | 0,355 A | 0,198 ± 0,054 A | 8 mAh → 0,097 ± 0,017 A |
| C 22:14:46–22:16:42 (116 s, n=30/12) | 0,192 ± 0,030 A | 0,116 A | 0,074 ± 0,027 A | 5 mAh → 0,155 ± 0,043 A |

Con Vbat 4,06 V: batería 0,39–0,80 W (A) y 0,30–0,63 W (C). **Sistema ≈ 2,9 ± 0,3 W (A) y 2,75 ± 0,2 W (C)**
(pantalla encendida + vídeo + lápiz en uso). Comparación Linux (CONSUMO-DESGLOSE-20261020): pantalla 5 %/60 Hz 2,43 W
sin vídeo → del mismo orden. **Regla para Linux y Android: medir por Δrm/Δcharge_counter (o qbg) en ventanas
≥ 5 min, no por la media de current_now muestreada.**

**Pantalla apagada: NO medida.** `input keyevent 223` funcionó (dmesg/logcat: `Going to sleep due to sleep_button`
22:14:03) pero a los 4 s llegó `Waking up from Asleep … WAKE_REASON_POWER_BUTTON` que yo no envié (botón físico / la
sesión de lápiz en curso); antes, 22:13:42, sueño por timeout y despertar por POWER. Para no interferir con el
dueño se abandonó la fase y la pantalla quedó **encendida**. Línea base histórica: suelo con pantalla apagada ~1,4 W
(Android, informe de consumo previo).

## 4. Procesos y estado (`procesos-pant_on-221702.txt`)
- CPU: `com.google.android.youtube` 110 % (41 % medio en cpuinfo 22:09–22:14), surfaceflinger 41 %, system_server 25 %,
  composer 21 %, systemui 13 %, audioserver 10 %, crtc_commit 8 %, media.hwcodec 7 %, touchfeature 5 %, kswapd 5 %
  (swap 2,7 GB usada: RAM llena), com.android.bluetooth 4 % (escaneo BLE continuo de `com.xiaomi.bluetooth`
  `MiuiBleOobHelperService`, que además adquiere `SCREEN_DIM_WAKE_LOCK ACQUIRE_CAUSES_WAKEUP`).
- Wakelocks: `AudioMix` (audioserver, PARTIAL), `WindowManager` (SCREEN_BRIGHT). Kernel: `qcom_rx_wakelock` (WiFi RX,
  2054 activaciones), `qup_uart` (BT), `a600000.ssusb` (USB, permanente con cable).
- deviceidle: ACTIVE/ACTIVE (cargando, pantalla encendida) → Doze no entra con cable.
- CPU: governor **walt** en las 3 políticas (policy0 595–1901 MHz, policy3 634–2611, policy7 634–2669); GPU
  **msm-adreno-tz** 255–835 MHz, 255 MHz y 8 % ocupación durante el vídeo.
- Pantalla: modo activo **60 Hz** (`peak-refresh-rate 60`, modos 30/48/50/60/90/120/144), brillo automático.
- WiFi 11ax asociada (RSSI −41), BT ON con GATT LE abierto (el lápiz).
- batterystats --charged (21 min desde arranque): cpu 187 mAh, video 11, cámara 12,2 (¿sesión de cámara previa?), audio
  4,1, BT 1,4, wifi 0,7 mAh.

## 5. Modelo de carga (evidencia: `dmesg-qbg-221650.txt`, `carga-rapida/pared-20261019-113806.txt`)
Quien decide FCC/ICL es el **firmware del ADSP** (cargador/qbg), no Android; la regla ganadora aparece en cada
`qbg_update_status` como `<votante>-<mA>`:
- **Arranque**: `fcc: BattAuth-2000, icl: i_sdp-100` (9,4 s): hasta autenticar batería, FCC 2 A; hasta enumerar
  USB, ICL 100 mA (el mismo «100 mA de firmware» que ve Linux sin ICL explícito).
- **PC (SDP)**: desde 19,4 s `fcc: PdAuth-5780, icl: chg_det-500` → FCC tope 5,78 A (batería autenticada), ICL
  500 mA por detección BC1.2 SDP. Con 2,3 W de entrada y ~2,7–3 W de consumo la batería **descarga** con
  `status=Charging`.
- **Pared PD/PPS 33 W (19-oct)**: `fcc: StepChgJeit-5350, icl: chg_det-3000`, cp_mode 4, bus 9,25 V/1,4 A, batería
  −2,6…−2,9 A a 4,45 V; FCC limitado por el **escalonado JEITA** (tabla `cycle_step_curr` 8000/6000/5400/3476 mA de
  `ut_test`, FV 4,48 V por ciclos 0–100).
- **Android** (driver `qti_battery_charger`) solo añade el **nivel térmico `tl`** con `battery_psy_set_charge_current:
  chg_type=… tl:=N ffc=… pd_verifed=…` (=`charge_control_limit`; hoy 0/2/4/6, cambia con pantalla y
  `thermal_scene`), además de autenticación de adaptador (aquí no necesaria). Temperaturas: batería 27–28 °C, placa
  29–32 °C, sin limitación térmica efectiva a 500 mA.
- Carga «rápida» real con el PC: **no existe** (SDP 500 mA, 2,3 W < consumo).

## 6. Pendiente (requiere cable) — scripts listos y probados en seco el 20-oct 22:17–22:18
| fase | requiere | script (adb WiFi, solo lectura) |
|---|---|---|
| Descarga real: pantalla encendida / apagada (60 s asentamiento) / encendida | **cable desenchufado**, y que nadie use la tablet | `build/android/bateria-20261019/medir-android-descarga.sh 192.0.2.14:5555 120` (espera `Discharging`; restaura pantalla con WAKEUP al salir; guarda CSV + qbg + resumen) |
| Retraso UI vs rsoc (cruce de enteros) | descarga ≥ 15 min | mismo script con `T` grande, o `mapa/muestreo-android.sh SERIE 900 larga` |
| Carga rápida PD/PPS: I, V, cp_mode, bus V/I de la bomba, tl, temperaturas, PDO/APDO | **cargador de pared PD/PPS 33 W** | `build/android/bateria-20261019/medir-android-carga-rapida.sh 192.0.2.14:5555 300` (espera `real_type≠SDP`; snapshot PD antes/después y trazas BATTERY_CHG) |
| Consumo con pantalla apagada (con cable) | que el dueño no use la tablet | `mapa/muestreo-android.sh` tras `input keyevent 223` |
Ojo: al quitar el cable USB se pierde la serie `SERIE0001`; los scripts usan la serie WiFi.

## Ficheros (`build/android/bateria-20261019/mapa/`)
`snapshot-attrs-220629.txt` (todos los atributos), `estado-inicial-220705.txt`, `fases.csv` (A/C), `fases-eventos.log`,
`dmesg-qbg-221650.txt`, `procesos-pant_on-221702.txt`, `muestreo-android.sh`, `procesos-android.sh`, pruebas en seco
`descarga-20261020-221728*` y `carga-rapida-20261020-221759*`.
