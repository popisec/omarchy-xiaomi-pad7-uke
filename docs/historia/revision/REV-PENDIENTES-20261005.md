# REV-PENDIENTES (2026-10-05) — auditoría de los P2/P3 de la ronda #528 y plan de ejecución

Auditor: subagente revisor de pendientes (#529). Entrada: los 6 informes
`REV-{APLICADO,GPU-DISPLAY,TACTIL,ENERGIA,RADIO-FW,KCONFIG}-20261005.md` + FLASH-LEDGER
#526–#528 + re-verificación **offline en el PC** (tabla NO tocada: cero adb/fastboot) de
DT vivo (`extracted-full/14-dt/dt-live.tar.gz`, extraído a /tmp), árboles del port
(`~/gpu-work/palawan-linux` rama `uke-fixes-20261005`, `build-uke/.config`), host
(`/usr/lib/firmware/`, ROM tgz) y repo (`build/gates/prepara/`). **Este informe NO aplica
ningún fix: solo plan.**

Leyenda: PREPARABLE-OFFLINE (se puede avanzar ya en el PC) · NECESITA-DATOS-ANDROID
(requiere nueva sesión Android) · NECESITA-BOOT-ARCH (requiere el boot de validación) ·
DESCARTAR-POSTERGAR (no invertir ahora).

Resumen de veredictos:

| # | Pendiente | Veredicto | Esf. | Riesgo |
|---|---|---|---|---|
| 1 | ACD on | NECESITA-BOOT-ARCH (tras soak) | S | medio (hangs silenciosos) |
| 2 | Lápiz fase 2 | NECESITA-DATOS-ANDROID | M-L | bajo |
| 3 | Vibrador qpnp-vibrator-ldo | DESCARTAR-POSTERGAR (P3) | S-M | nulo |
| 4 | vadc skin NTCs | PREPARABLE-OFFLINE | M | bajo |
| 5 | DFPS 7 modos | DESCARTAR-POSTERGAR (P3; necesita datos para 144/90) | M-L | medio |
| 6 | Retimer USBSS WCD939x | DESCARTAR-POSTERGAR (P3) | S-M | medio (bus i2c compartido) |
| 7 | Sensores SSC | DESCARTAR-POSTERGAR (P2, confirmado) | L | nulo |
| 8 | Audio | DESCARTAR-POSTERGAR condicionado (P1) | M-L | nulo |
| 9 | Cámaras camss | DESCARTAR-POSTERGAR (P2, confirmado) | L | nulo |
| 10 | Chipid Adreno732 | NECESITA-BOOT-ARCH (entrada ya en catálogo) | S | nulo |
| 11 | gmu-log (G5) | NECESITA-DATOS-ANDROID (causa raíz hallada) | S | nulo |
| 12 | Fw radio W1-W4/B1-B2 | **PREPARABLE-OFFLINE YA** | M | bajo |
| 13 | Validación batería | **PREPARABLE-OFFLINE YA** | S | bajo |

---

## 1. ACD on (`qcom,opp-acd-level`)

**Veredicto: NECESITA-BOOT-ARCH, pero SOLO después del soak verde. No en el boot de
validación.**

- Valores re-verificados hoy contra el DT vivo (decode directo de
  `qcom,kgsl-3d0@3d00000/qcom,gpu-pwrlevels/qcom,gpu-pwrlevel@0..8`): 950/900/835 →
  `0xa8285ffd`; 736/684/633 → `0x88295ffd`; 500 → `0xa8295ffd`; 353 → `0x882c5ffd`;
  255 → `0x882f5ffd`. **Coinciden 1:1 con la receta F3 de REV-GPU-DISPLAY** — la tabla está
  cerrada, no queda nada que extraer.
- Qué tener verificado ANTES de activar: (a) muro CM3 caído con GPU viva
  (`Loaded GMU firmware v…` en dmesg, `a6xx_gmu.c:937`); (b) gate G3-1 `hub=200000000`;
  (c) sin ESR/erange en 5 min a 950 MHz (soak). El riesgo real es único y conocido
  (R1 del informe GPU): el ACD negocia por QMP con AOSS y mete la tabla por HFI; con un
  fw GMU cuyo comportamiento difiera del vendor, el fallo son **hangs silenciosos**, no
  un panic legible. Por eso `qmp acd val:0` (harmless, comentado upstream en
  `a6xx_gmu.c:2108-2110`) se mantiene durante todo el bring-up.
- Pasos (cuando toque): añadir las 9 props de F3 al override de `&gpu_opp_table` en
  `xiaomi-uke.dts` (255 MHz sin prop: el bucle del driver empieza en i=1), recompilar
  DTB, boot, y verificar ausencia de `Unable to enable ACD`/`Unable to ACD table`
  (`a6xx_hfi.c:877,884`) + estabilidad a 950 sostenido. Si algo falla: revert = borrar
  las props (una línea por OPP, sin tocar código).
- Esfuerzo S (8 líneas DTS + rebuild DTB). Riesgo medio, mitigable con revert trivial.

## 2. Lápiz NT36532 fase 2 (handlers pen)

**Veredicto: NECESITA-DATOS-ANDROID para la decodificación; lo userspace ya está
preparado offline.**

- Lo capturado SÍ basta para la especificación funcional: los caps de los 2 input
  virtuales completos (`06-pen/getevent-lp.txt`: `NVTCapacitivePenM80p` X/Y
  21360x32000, pressure 8191, distance 0-1, tilt ±60, BTN_DIGI; `P81c` pressure 16383 +
  ABS_BRAKE 0-360; sin BTN_STYLUS), frame completo de 5176 B y hall por pmic_glink
  (`POWER_SUPPLY_PEN_HALL3/4`). Lo que NO hay: **el `.ko` vendor `nt36532_touch.ko` no
  está en `extracted-full/`** (0 ficheros .ko en toda la captura; el desensamble citado
  en REV-TACTIL proviene de una ronda anterior, no de esta captura) → la zona de pen del
  frame de 5176 B no se puede decodificar offline hoy.
- Factible sin tablet en Arch: NO para el parseo (a ciegas sería prueba-y-error sobre
  SPI con el IC en vivo); SÍ para el andamiaje: segundo `input_dev` con esos caps en
  `novatek-nt36xxx-spi.c` + userspace ya existente
  (`build/gates/prepara/novatek/userspace/`: hwdb 60-uke-evdev, rules, libwacom
  `xiaomi-uke.tablet`, conf Hyprland tablet-v2 — el P2-lapiz.md ya documentó que la
  presión va por tablet-v2/GTK4, no por libwacom).
- Pasos en la próxima sesión Android (barato, 5 min): `adb pull` de
  `/vendor_dlkm/lib/modules/nt36532_touch.ko` y `xiaomi_touch.ko` (localizar con
  `find /vendor_dlkm /odm_dlkm /vendor -name 'nt36532*' -o -name 'xiaomi_touch*'`), y de
  regalo `/odm/firmware/novatek_nt36532_o82_fw_csot.bin` (0x3c000, por si algún día hay
  que portar el updater). Opcional: `getevent -lt` durante trazos reales de lápiz como
  cross-check del parseo.
- Esfuerzo total M-L (decodificar + 2º input_dev + triaje). Riesgo bajo (es fase 2, no
  bloquea nada).

## 3. Vibrador `qcom,qpnp-vibrator-ldo`

**Veredicto: DESCARTAR-POSTERGAR (P3).**

- Verificado hoy: en `drivers/input/misc/` del fork NO hay driver que encaje —
  `pm8xxx-vibrator.c` es SSBI del troquel pm8xxx viejo (HW distinto), `pwm-vibra`/
  `gpio-vibra` no aplican; no existe `qpnp-vibrator-ldo` upstream ni downstream en el
  árbol. Driver propio o port downstream (~100-150 líneas regmap SPMI): único camino.
- Nodo DT vivo existe (`pm7550ba@7/qcom,vibrator@df00`, 3.0 V, `disable-overdrive`,
  status ok) — verificado hoy en dt-live — pero **NI el Android vendor lo binda**
  (unbound en la captura; lsmod sin driver de vibrador). No hay ni referencia de
  comportamiento vendor que imitar.
- Nodo en el port: NO existe (`pm7550ba.dtsi:63` solo trae el eusb2 repeater). Coste S-M,
  beneficio haptics-only. Mantener como proyecto menor de relleno; no ocupa ventana.

## 4. vadc skin NTCs (`vadc@9000` + adc-tm)

**Veredicto: PREPARABLE-OFFLINE (M). El dato completo está capturado y los drivers ya
están en el kernel.**

- DT vivo verificado hoy: `pmk8550@0/vadc@9000` con **27 canales** — los térmicos que
  importan: `pmxr2230_quiet_therm` (con `qcom,adc-tm-type`), `pmk8550_xo_therm`,
  `pm7550ba_{batt,charger,conn,wifi,backlight}_therm`, `pmxr2230_{display,flash,conn2,ap}_therm`,
  más die-temps, `vph_pwr`, `ichg/iin_fb` y refs. Cada canal con reg / hw-settle-time /
  pre-scaling / ratiometric / label → el mapeo se copia literal, sin ingeniería inversa.
- Drivers in-tree: `CONFIG_QCOM_SPMI_ADC5=m` y `CONFIG_QCOM_SPMI_ADC_TM5=m` ya activos
  (verificado en build-uke/.config) — solo faltan los nodos; el fork's `pmk8550.dtsi` no
  trae `vadc@9000`. No existe nodo `adc_tm` dedicado en el DT vivo (el vendor lleva el
  tm de algunos canales en `qcom,adc-tm-type` y el resto por glink/ADSP): portar el
  patrón upstream (pmk8550.dtsi mainline: vadc + adc_tm5) usando los valores del vivo.
- Qué aporta: temperatura de chasis en el port (hoy 0 zonas ADC) → mitigación de carga
  por piel y monitorización; sin ello el ADSP limita solo por temp de celda (riesgo
  asumido en v1, REV-ENERGIA §8 notas).
- Pasos: (1) añadir `vadc@9000` (+ `adc_tm@…` del patrón upstream) al
  `pmk8550.dtsi`/override en `xiaomi-uke.dts` con los canales del vivo; (2) crear las
  thermal zones de los NTC con trips razonables (el vendor usa thermal*.conf, no
  capturado — elegir trips conservadores propios); (3) compilar DTB (validable sin
  boot); (4) gate en boot: `/sys/class/thermal/` con zonas `quiet_therm`/`xo-therm`
  legibles.
- Esfuerzo M. Riesgo bajo (solo lectura; un canal mal mapeado da una lectura absurda,
  no cuelga nada).

## 5. DFPS 7 modos (144/120/90/60/50/48/30)

**Veredicto: DESCARTAR-POSTERGAR (P3). Preparación parcial offline posible; 144/90
necesitan datos del vendor.**

- Cómo se hace en mainline msm: el panel driver expone los modos
  (`drm_panel` → `get_modes`) y DSI elige timing por modo. Nuestro driver
  `panel-xiaomi-o82-dualdsi.c` YA tiene la maquinaria de enumeración: `o82_modes[]` con
  3 timings (120/144/90, hfp 226/36/608 en coordenadas de panel completo = 2× vendor) y
  `get_modes` itera `desc->num_modes` (línea 396). El gap es que `num_modes = 1`
  (línea 555) y **no existe el switch de timing**: el enable solo escribe la secuencia
  de 120 Hz (b3=0x40 b2=0x91). Exponer modos sin switch = imagen corrupta.
- El vendor lo resuelve con `qcom,dsi-supported-dfps-list` (120 144 90 60 50 48 30)
  sobre **3 timings** (timing@144 hfp 18; timing@120 → 120+60; timing@90 → 90+50+48+30)
  — el switch son comandos DSI por panel (no capturados; viven en el `msm_drm` DLKM
  vendor).
- Camino si se quiere: (a) 60 Hz es el más barato (mismo timing@120 que 120 Hz: cambia
  pclk/refresco, mismo hfp) — ensayable en boot Arch con riesgo controlado; (b) 144 y
  90 exigen las secuencias del vendor → NECESITA-DATOS-ANDROID (tirar
  `msm_drm.ko`/techpack display de `/vendor_dlkm`) o experimentación.
- Coste M (60 Hz) a L (resto). Beneficio: batería (60 Hz) y fluidez (144). No toca la
  ventana de validación.

## 6. Retimer USBSS WCD939x (`wcd_usbss_i2c`)

**Veredicto: DESCARTAR-POSTERGAR (P3) mientras HS funcione.**

- DT vivo verificado hoy: el nodo es `i2c@a80000/wcd939x_i2c@e` (compatible
  **`qcom,wcd939x-i2c`**, reg 0x0e, `reset-gpios`, `vdd-usb-cp-supply`, status ok,
  pinctrl propio `wcd_usbss_reset_active/sleep`, en `__symbols__` como `wcd_usbss`) —
  comparte bus I2C con `ktz8866@11` (backlight) y el codec.
- Driver in-tree: `drivers/usb/typec/mux/wcd939x-usbss.c` existe y
  `CONFIG_TYPEC_MUX_WCD939X_USBSS=m` **ya está activo** en build-uke (verificado hoy),
  PERO su compatible es **`qcom,wcd9390-usbss`** — binding upstream distinto del
  `qcom,wcd939x-i2c` vendor (upstream separa usbss del codec). Activarlo exige nodo
  propio con el compatible upstream en esa dirección I2C y probar (sin garantía de que
  el chip responda al mapa de registros upstream).
- Prioridad real: NULA hasta que se quiera SuperSpeed/DP fiable (el port funciona en HS;
  el SS ya queda enrutado por el fix B6 pendiente de validar en boot). El nodo va solo
  cuando se pise el tema DP-altmode v2. Riesgo de adelantarlo: pinchar el bus i2c
  compartido con backlight/codec.

## 7. Sensores SSC — confirmación de postergación

**Veredicto: DESCARTAR-POSTERGAR (P2), confirmado.**

- Reconfirmado: los 4 chips (LSM6DSO/QMC630x/STK3BCX/SX937x) cuelgan del I2C del SSC
  del ADSP (0 nodos AP en el DT vivo; PDR `msm/adsp/sensor_pd` up en dmesg). Dato a
  favor de la viabilidad futura: el fw ADSP que ya se extrajo
  (`~/gpu-work/ramaa/s24/adsp-fw/adsp.b22`) **ya trae el driver SSC del LSM6DSO**
  (60 ocurrencias `lsm6dso`, 2804 cadenas `sns_`, `PX-rotacion.md:36`) → el lado DSP
  existe; lo que falta es el lado AP: `QCOM_FASTRPC=m` ya está, pero no hay
  sensor-PD-boot ni el stack userspace SSC/HAL empacado para Arch (trabajo L,
  semanas). QMC630x/STK3BCX/SX937x: sin driver mainline ni por SSC-visible (los gestiona
  el fw DSP).
- Cuándo valdría la pena: cuando el ADSP sea rutina en el port (cadena batería
  estable) y se quiera rotación de pantalla (el autorotate de `prepara/` espera un iio
  que hoy no existirá). Hasta entonces, nada.

## 8. Audio — postergación condicionada: qué falta exactamente

**Veredicto: DESCARTAR-POSTERGAR (P1) hasta que ADSP+WiFi/BT estén verificados en boot
Arch. La lista de lo que falta, cerrada:**

1. FW QDSP6 en el rootfs (`adsp.mdt/bXX` + `adsp_dtb.*`, filas A1/A2 de RADIO §8) —
   prerrequisito compartido con la cadena de batería (mismo ADSP).
2. Nodo `sound` estilo sm8550.dtsi (card + dai-links a q6apm) — el esqueleto de macros
   rx/tx/wsa/va ya está en `palawan.dtsi` con las direcciones del vivo.
3. Nodos soundwire rx/tx/va + `wcd939x-sdw` (configs `SND_SOC_WCD939X=m` +
   `_SDW=m` ya activas, verificado hoy).
4. UCM/mixer derivado de `11-audio/vendor-etc/mixer_paths*.xml` (capturados).
5. **Corrección al informe RADIO §7**: "adaptar lpasscc de cliffs" es trabajo
   innecesario — no existe lpasscc sm8550+ en mainline (verificado: los únicos
   `lpasscc-*` in-tree son sc7280/sc8280xp/sdm845/sm6115) porque en esa generación los
   relojes LPASS los pone el ADSP vía **Q6PRM**, y el árbol ya trae
   `sound/soc/qcom/qdsp6/q6prm{,-clocks}.c` con `SND_SOC_QDSP6_PRM{,_LPASS_CLOCKS}=m`
   activos. El audio va por GPR/q6apm sobre el glink del ADSP: nada de clk driver nuevo.
6. **Gap no mencionado como tal en los informes**: los 4 altavoces van por smartPA
   `fs16xx` en `i2c@88c000` (fw `fs19xx.fsm`) **sin driver mainline** → audio por
   altavoz exige portar foursemi; altavoces no, auriculares/USB sí (wcd939x mbhc +
   jack). Citarlo en el plan para no descubrirlo tarde.
- Coste M-L. Gatillo para empezarlo: ADSP `running` rutinario + PDR charger_pd estable.

## 9. Cámaras camss — confirmación de gap

**Veredicto: DESCARTAR-POSTERGAR (P2), confirmado, con un matiz.**

- Matiz al RADIO §7: "la tabla más moderna es sm8550" es inexacto — el `of_match` del
  camss del fork llega hasta **`qcom,sm8650-camss` y `qcom,x1e80100-camss`**
  (`camss.c:5758-5760`, verificado hoy; tablas csiphy/csid/vfe de sm8650 existentes).
  La conclusión NO cambia: **no hay tablas cliffs/sm8635** y portarlas (csid-gen3/
  csiphy/vfe de cliffs + ICP `CAMERA_ICP.mbn` + stack userspace) es un proyecto L en sí.
- Hasta dónde se llega hoy: a nada funcional (el nodo no probea sin compatible cliffs).
  Confirmado postergar sin fecha.

## 10. Chipid Adreno732 (0x43030b00)

**Veredicto: NECESITA-BOOT-ARCH; offline no queda nada que preparar salvo el guion de
lectura.**

- Verificado hoy: la entrada **ya existe** en el catálogo del fork
  (`a6xx_catalog.c:1618`: `chip_ids 0x43030b00`, ADRENO_7XX_GEN2, fw
  `gen71100_{sqe,gmu}`, zapfw `gen71100_zap.mbn`, `gmu_chipid 0x70b0000`, funcs
  a7xx). Si el silicio reporta ese chipid, el probe funciona sin tocar nada.
- Guion para el boot (qué mirar): dmesg `Loaded GMU firmware v%u.%u.%u`
  (`a6xx_gmu.c:937`), `revision: %u (chipid)` de adreno (`adreno_gpu.c:1040`, visible
  con `cat /sys/kernel/debug/dri/*/gpu` o drm.debug), y si el chipid difiriera,
  `Unable to identify the GPU`-style dev_err del catálogo → entonces sí habría que añadir
  entrada (plan B: clonar la entrada 0x43030b00 con el chipid real y re-probar).
- Esfuerzo S (lectura en boot). Riesgo nulo (no cambia nada del árbol).

## 11. gmu-log capture (G5) — por qué falló y comando correcto

**Veredicto: NECESITA-DATOS-ANDROID, con causa raíz cerrada hoy.**

- Causa raíz: el debugfs kgsl del vendor (6.1.138) **no tiene `gmu_log` ni `gmucore`**.
  Verificado en la evidencia: `01-gpu/kgsl-debugfs/kgsl-3d0/` contiene solo
  `acd_calibrate, active_cnt, bcl, ctx, events, globals, ifpc_hyst, preemption` (8
  ficheros; 60 en todo el árbol debugfs capturado con dirs `snapshot/mempools/proc/debug`).
  La captura tiró por lista de nombres tipo upstream → 0 ficheros gmu. No es fallo de
  permisos ni de ruta: **el fichero no existe en ese build** (y dmesg no loguea versión
  GMU — cero líneas acd/ifpc/gmu).
- Comando correcto para la próxima sesión Android (receta G5-v2):
  ```sh
  su -c 'find /sys/kernel/debug/kgsl \( -type f -o -type l \) | sort'   # inventario PRIMERO
  su -c 'for f in $(find /sys/kernel/debug/kgsl -type f); do echo "== $f"; cat $f; done' > gmu-all.txt
  ```
  (tirar TODO el debugfs kgsl sin lista previa; si aparece `gmu_log`/`gmucore`, cat
  directo). Complemento: `cat /d/kgsl/gmucore` si existiera.
- Nota práctica: **G5 se cierra igualmente desde el boot Arch** — nuestro kernel sí
  imprime la versión (`Loaded GMU firmware v…`), que era el dato buscado. La recaptura
  Android queda como nice-to-have para comparar el fw del vendor.

## 12. Fw radio W1–W4 / B1–B2 — empaquetado YA

**Veredicto: PREPARABLE-OFFLINE (M), con dos matices verificados hoy en el host.**

- **Matiz 1 (corrección a RADIO §2.2)**: el host NO tiene
  `/usr/lib/firmware/qca/msbtfw11.mbn` plano — linux-firmware de Arch lo trae
  **comprimido**: `msbtfw11.mbn.zst`, `msnv11.bin.zst`, `msnv11.b09.zst`,
  `msnv11.b0a.zst` (todos presentes, verificado). Y **`CONFIG_FW_LOADER_COMPRESS is not
  set`** en build-uke → el kernel NO leerá `.zst`: hay que descomprimir con `zstd -d`
  al empaquetar (zstd disponible en el host).
- **Matiz 2**: `ath11k/WCN6750/hw1.0/` tiene `board-2.bin.zst` (38 KB) y el symlink
  `wpss.mdt.zst -> sc7280/wpss.mbn.zst` — el wpss de linux-firmware NO sirve para
  `qcom_q6v5_pas` (sin segmentos .bXX, como ya dijo RADIO §8): W1/W2 salen del
  **NON-HLOS.bin** del ROM (tgz presente en host, 7.7 GB; herramientas `tar`, `simg2img`,
  `debugfs`, `7z` disponibles → extracción 100% offline, sin tablet).
- Plan de staging concreto (ventana PC):
  1. `mkdir -p build/rootfs/staging-firmware/{qca6750,qca,ath11k/WCN6750/hw1.0}`
  2. Extraer del tgz `…/images/NON-HLOS.bin` (tar -xzf con el miembro concreto); si es
     sparse → `simg2img`; montar RO (o `debugfs -R "dump …"`) y sacar
     `image/qca6750/wpss.mdt + wpss.b00…b12 (sin b11)` y `image/adsp*`/`adsp_dtb*`
     (A1/A2, para batería). W3 `wpss.qdb` opcional.
  3. `zstd -d` → `qca/msbtfw11.mbn`, `qca/msnv11.bin`, `qca/msnv11.b09/.b0a` (B1/B2) y
     `ath11k/WCN6750/hw1.0/board-2.bin` (W4).
  4. Crear package `uke-radio-firmware` al estilo `pkg/uke-gpu-firmware` (o copiar
     directo al rootfs k521 — paso que ya exige sudo, no este subagente).
  5. Gate offline: `tar -tf` del package y verificación de rutas exactas que piden los
     drivers: `qca6750/wpss.mdt` (firmware-name del DT), `qca/msbtfw11.mbn` +
     `qca/msnv11.bin` (btqca.c:828/929), `ath11k/WCN6750/hw1.0/board-2.bin` (ath11k).
- Dependencias: NINGUNA externa. Lo único que no es offline es el paso final de copia al
  rootfs/montaje (sudo en ventana PC del dueño).

## 13. Validación cadena batería (pmic_glink + battmgr + ADSP)

**Veredicto: PREPARABLE-OFFLINE (S) — queda un gap concreto de repo.**

- Ya preparado: `build/gates/prepara/uke-adsp.service` (oneshot,
  `ExecStart=/usr/local/bin/uke-adsp-load.sh`, `Before=uke-bateria-baja.service`,
  TimeoutStartSec=120, no bloquea boot), `bateria.sh` y `bateria-baja-guard.sh`.
- **Gap hallado hoy: `uke-adsp-load.sh` NO está en el repo omarchy-uke** — el original
  vive en el rootfs Ubuntu (`~/proyectos/ubuntu-permanente/bin/
  uke-adsp-load.sh`). Pasos: (1) copiarlo a `build/gates/prepara/` y adaptar al Arch
  (orden de módulos `qcom_pd_mapper → qcom_q6v5_pas → qcom_glink_smem → qrtr_smd →
  pmic_glink → qcom_battmgr`, luego `echo start > /sys/class/remoteproc/remoteprocN/
  state`; ruta `/usr/bin/` o `/usr/local/bin/` según convención del rootfs); (2) dejar
  documentado el enable (`systemctl enable uke-adsp.service`) para cuando se hornee el
  rootfs; (3) verificar que el rootfs lleva los `adsp*` fw (A1/A2) — cubierto por el
  staging del pendiente 12.
- Gates de lectura ya definibles offline (para el plan de boot): dmesg SIN
  «PDM: no support for the platform» y CON «PDR: Indication received from
  msm/adsp/charger_pd, state: 0x1fffffff»; `/sys/class/power_supply/battery` presente;
  `uevent` con `status=Charging` y `current_now` negativo = cargando (convención
  confirmada: vivo −103274 µA); WIP de `qcom_battmgr.c` en el árbol (90 líneas, XM
  properties) **sigue sin commitear** — decidir antes del boot si vuela o se commitea
  como experimento (no es bloqueante de la cadena básica).

## 14. Inconsistencias detectadas entre informes

1. **Fw BT "ya en el host" (RADIO §2.2)** — cierto en contenido, pero está `.zst` y el
   kernel port no tiene `FW_LOADER_COMPRESS`: hay que descomprimir al empaquetar
   (detallado en §12). Riesgo real si se copia tal cual: BT sin fw con todo "correcto".
2. **Audio "adaptar lpasscc de cliffs" (RADIO §7)** — trabajo innecesario/inexistente:
   no hay lpasscc sm8550+ en mainline; los relojes van por Q6PRM y ya están =m. Ahorra
   un trabajo L fantasma (§8.5).
3. **Camss "tabla más moderna sm8550" (RADIO §7)** — inexacto: of_match llega a
   sm8650/x1e80100. Conclusión (sin tablas cliffs) intacta (§9).
4. **KCONFIG gap 4 "el nodo pmic-glink necesitará child battery"** — falso para este
   camino: `pmic_glink.c:352` crea el aux `power-supply` según `client_mask` del match
   `qcom,pmic-glink` (nuestro `xiaomi-uke.dts:92`), sin hijo DT. La nota de REV-APLICADO
   D5 era la correcta.
5. **Zap F1 "mismatch confirmado" (GPU Q2) vs "YA ESTABA" (APLICADO)** — resuelto: el
   informe GPU partía de un estado viejo del package. Gap real restante: el rootfs v7 no
   tiene el package instalado (aviso §3.1 de REV-APLICADO, sigue vigente).
6. **ACD #526 (acd=0) vs #527 (acd=1)** — resuelto en GPU Q1 (knob de disparo vs
   estado); tabla ACD re-verificada hoy contra dt-live: coincide 1:1.
7. **Nombre de nodo vs reg en ADSP** — el override aplicado dejó
   `remoteproc@6800000` con `reg = <0x03000000>` (unit-address no coincide con reg).
   El build lo silencia con `-Wno-unit_address_vs_reg` (visto en el .dtb.cmd) → no
   perseguir "warnings fantasma" ni renombrar el nodo a la ligera (el vendor lo llama
   `remoteproc-adsp@03000000`; renombrar es opcional y cosmético).
8. **`.ko` táctil vendor** — REV-TACTIL describe su desensamble, pero la captura del
   5-oct no contiene ningún `.ko` (fuente: ronda anterior). Para lápiz/fase 2 hay que
   re-tirarlo (§2).
9. **Conteo W2** — RADIO §8 dice "b00…b10, b12 (13 fich; sin b11)": b00–b10 son 11 +
   b12 = **12** ficheros. Al extraer del NON-HLOS, fiarse del listado real, no del
   conteo.
10. **Unbound del vibrador** — coherente entre informes (ni Android vendor lo binda):
    refuerza el DESCARTAR-POSTERGAR (§3).

---

## PLAN DE EJECUCIÓN PRIORIZADO

### Ventana PC (offline, próxima — puede empezar ya)

1. **Firmwares radio + GPU al staging/rootfs** (pend. 12 + aviso §3.1 APLICADO):
   staging con `qca6750/wpss.*`, `board-2.bin`, `qca/msbtfw11.mbn+msnv11*`,
   `adsp*/adsp_dtb*` (todo descomprimido) + package `uke-radio-firmware`; instalar
   `uke-gpu-firmware` y el radio pkg en el rootfs k521 (paso sudo del dueño). [M]
2. **Cerrar el paquete batería** (pend. 13): traer/adaptar `uke-adsp-load.sh` al repo,
   unit lista para enable, gates de validación escritos (PDR charger_pd, battery uevent,
   corriente negativa=cargando). [S]
3. **vadc NTCs** (pend. 4): nodos vadc/adc_tm + canales del DT vivo + trips; compilar
   DTB y dejar gate de lectura para el boot. [M]
4. Opcional de relleno: guion de triaje táctil (`point_layout`, evtest, swap/flip) ya
   existe en prepara — solo dejarlo referenciado en el plan de boot. [S]

### Ventana boot de validación Arch (en este orden de lectura)

1. **GPU**: `UKE-CM3DBG hub=200000000` (G3-1) → `Loaded GMU firmware v…` +
   `revision`/chipid (pend. 10, cierra también G5 por nuestra parte) → ausencia de
   `Unable to load qcom/uke/gen71100_zap.mbn` (G1) → burn 5 min a 950 (G4).
2. **Batería/ADSP**: `uke-adsp.service` → ADSP `running` → PDR charger_pd UP →
   `/sys/class/power_supply/battery` + prueba con cable (pend. 13).
3. **WiFi/BT**: con el fw del staging: `Booting fw image qca6750/wpss.mdt`, wlan0 up,
   `bluetoothctl list` (pend. 12). Primera prueba host-mode con hub alimentado.
4. **Táctil**: triaje `point_layout` + evtest (esquinas opuestas); si EDGE_FALLING no
   reporta, probar EDGE_RISING (1 línea DT).
5. **ACD (pend. 1)**: NO en este boot. Solo si 1–4 verdes → activar en el boot
   siguiente con la receta F3 y sus gates.

### Ventana Android (solo si se repite captura)

1. **G5-v2** (pend. 11): inventario + tirado completo del debugfs kgsl (`find … | cat`),
   no por lista de nombres.
2. **Lápiz** (pend. 2): pull `nt36532_touch.ko` + `xiaomi_touch.ko` (+ fw táctil por si
   acaso).
3. Opcional DFPS (pend. 5): tirar el techpack display vendor para decodificar los
   comandos de timing de 144/90.

### Explícitamente NO programado (DESCARTAR-POSTERGAR)

Vibrador (3), retimer USBSS (6), sensores SSC (7), audio (8 — hasta ADSP rutinario),
cámaras (9), DFPS completo (5), NFC/FM (P3 radio).
