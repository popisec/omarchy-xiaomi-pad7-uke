# Autorrotación (y auto-brillo) de la uke — diseño del camino, 18-oct-2026

Alcance: investigación + lectura + material preparado en el PC. **Nada ejecutado con riesgo**: no se cargó ningún módulo, no se tocó el ADSP ni
fastrpc, no hay commit. Material: `build/rootfs/deploy/autorotacion/` (script `uke-autorotate`, unidad, `deploy.sh`, `propuesto/`, README).
Todas las mediciones son del 18-oct-2026 (caducan el 1-nov). Convención: HECHO = visto hoy con comando/URL; INFERIDO = deducción mía.

## 0. Resumen

1. **Camino viable y ya recorrido por primos Xiaomi/Qualcomm**: kernel `fastrpc` + demonio de FastRPC que **crea/atiende el PD de sensores del ADSP**
   (`adsprpcd sensorspd`, o `hexagonrpcd -s`) + ficheros de Android (`odm/sensors/config`, registro de `persist`, `sns_reg_config`) + `libssc` (QMI sobre QRTR)
   + `iio-sensor-proxy` ≥ 3.9 (backend SSC) + `monitor-sensor`. Nadie lo documenta en SM8650/SM7675 todavía (**NO hay reporte directo**; ver §1.3).
2. **El PD de sensores de la uke es el del ADSP** (no hay SLPI aparte): Android arrancó `sscrpcd` con `createstaticpd:sensorspd on domain 0` (= ADSP) y el
   firmware cargado en la tablet lleva dentro el SSC completo (drivers lsm6dso, qmc630x, stk3bcx, sip1328, sx937x, `qmi8658`; HECHO, §3).
3. **Casi todo lo del lado Linux ya está en la tablet**: `libssc.so.2`, `ssccli`, `iio-sensor-proxy` 3.9 con SSC y `monitor-sensor` (sin paquete pacman; procedencia
   por documentar) y el `adsprpcd` que audio ya compiló. **Falta solo**: (a) los ficheros de Android, que **están en las particiones de la tablet** (persist ext4 y `odm_b`/`vendor_b` EROFS
   dentro de `super`; legibles en solo lectura), (b) el servicio `sensorspd`, (c) udev + matriz de montaje, (d) un fastrpc **persistente** (hoy solo hay overlay en caliente de audio).
4. **Lo único con riesgo es R3** (crear el PD de sensores en el ADSP compartido con audio y con la carga, `recovery_disabled=true`). Todo lo demás es PC o lectura.
5. Gyro no hace falta para girar la pantalla y `libssc` 0.4.4 no lo lee (los primos lo parchean). ALS (stk3bcx) sí está soportado por libssc → auto-brillo posible, pero la
   calidad del ALS tras una pantalla de 2 paneles/dos KTZ es incierta (R7).

## 1. Camino de postmarketOS y primos (fuentes, medidas 18-oct-2026)

### 1.1 Piezas y versiones

| Pieza | Función | Versión / estado (medido hoy) | Fuente |
|---|---|---|---|
| `fastrpc` (kernel) | `/dev/fastrpc-adsp[-secure]`; ioctl `INIT_ATTACH_SNS` (PD de sensores del DSP raíz) e `INIT_CREATE_STATIC` (nombre libre) | **En nuestro kernel 7.2.9 están los dos** (`fastrpc.c:2182,2185`, HECHO); `CONFIG_QCOM_FASTRPC=m` | `build/kernel-pokes/senemos-7.2.9/linux-7.2.9/drivers/misc/fastrpc.c` |
| `hexagonrpcd` | Sirve al DSP el «hexagonfs»: `sensors/config`, `sensors/registry`, `sns_reg.conf`, `acdb`, `dsp`, `socinfo`; `-s` = engancha a *sensorspd*; `-R dir` raíz de ficheros | Debian testing 0.4.0-2, exp. 0.5.0-1; GitHub tags hasta v0.5.0; el repo de sheng cita upstream 0.6.0 (Rust, `db659bd`). **AUR `hexagonrpcd` = 0.3.2 (abandonado, dic-2023)**; no hay en Arch/ALARM | <https://manpages.debian.org/testing/hexagonrpcd/hexagonrpcd.1.en.html>, <https://api.github.com/repos/linux-msm/hexagonrpc/tags>, <https://aur.archlinux.org/rpc/v5/search/hexagonrpc?by=name> |
| `adsprpcd` (quic/fastrpc) | Alternativa de Qualcomm: `adsprpcd <pd_name>` crea ese PD estático y atiende `adsp_default_listener`; abre rutas **absolutas** de Android (`/vendor/etc/sensors/...`) | **Ya compilado por audio** (`fastrpc-uke-a56e9d4d.tar`, commit `a56e9d4d`) y en la tablet (`/usr/bin/adsprpcd`) | `build/rootfs/deploy/audio/fastrpc/build-fastrpc.sh`; usado para sensores en <https://github.com/blu-sharky/piano-sensors> |
| `libssc` | Habla QMI/protobuf con el servicio SSC por QRTR; sensores: acelerómetro, luz, proximidad, magnetómetro, brújula (**sin giroscopio**) | **v0.4.4 (tag 27-jun-2026)**; en la tablet `libssc.so.2` + `ssccli` (28-jun-2026, sin paquete). AUR `libssc-git` = 0.1.3 (oct-2023, obsoleto, soname distinto) | <https://codeberg.org/api/v1/repos/DylanVanAssche/libssc/tags>, <https://aur.archlinux.org/rpc/v5/search/libssc?by=name>, `ssh … find / -name 'libssc*'` |
| `iio-sensor-proxy` | Backend SSC mergeado el **8-feb-2026** (MR 381); tag **3.9 (2-mar-2026)**; Arch `extra` 3.9-1 | En la tablet 3.9 con `libssc.so.2` enlazado y `monitor-sensor` (3-mar-2026) | <https://gitlab.freedesktop.org/hadess/iio-sensor-proxy/-/merge_requests/381>, <https://archlinux.org/packages/extra/x86_64/iio-sensor-proxy/> |
| udev | `IIO_SENSOR_PROXY_TYPE+="ssc-accel ssc-proximity"` y `ACCEL_MOUNT_MATRIX` sobre el nodo `fastrpc-adsp*`; el `80-iio-sensor-proxy.rules` de serie solo declara luz y brújula | Regla de serie de la tablet: solo `ssc-light ssc-compass` (HECHO) | <https://github.com/blu-sharky/piano-sensors> (`piano-sensors.udev`), Fairphone 4: <https://ayakael.net/forge/pmaports/commit/f1767d7dbd149997434468088219acd855f9294c> |

### 1.2 Qué PD sirve los sensores (la pregunta «¿sensorspd en ADSP o SLPI?»)

- Depende del SoC. SDM845/SM8150/SM8450: **SLPI/SDSP aparte** (`/dev/fastrpc-sdsp`, `hexagonrpcd-sdsp`) — nabu <https://github.com/CFM880/nabu-accelerometer>, Tab S8+ <https://github.com/aaronsb/sm-x800-linux/pull/37>.
  SDM670 (sin SLPI) y **SM8550/SM8750: el PD `sensorspd` vive en el ADSP** — pmaports MR 5329 <https://gitlab.com/postmarketOS/pmaports/-/merge_requests/5329>,
  sheng (SM8550) `hexagonrpcd-adsp-sensorspd.service` <https://github.com/lzxcr/arch-xiaomi-sheng>, Pad 8 Pro (SM8750) `adsprpcd sensorspd` <https://github.com/blu-sharky/piano-sensors>.
- **uke (HECHO)**: logcat de Android (`build/android/coldboot-20261017/logcat-30s.txt:2054`): `sscrpcd … createstaticpd:sensorspd on domain 0`, `Diag … msm/adsp/sensor_pd`;
  `DT /reserved-memory/adspslpi_region@9d400000` solo es memoria. El firmware ADSP (`/lib/firmware/adsp.b*`) contiene el SSC: `sns_registry*`, `/mnt/vendor/persist/sensors/*`,
  `/vendor/etc/sensors/sns_reg_config`, `/odm/etc/sensors/config`, 111 hits de `lsm6dso`, `sns_stk3bcx_hal_island.c`, `qmi8658` (IMU alternativa en otras variantes), `sx937x`.
- El pd-mapper del kernel conoce `msm/adsp/sensor_pd` en varias tablas SoC (`qcom_pd_mapper.c:289`); falta **comprobar qué tabla usa la uke** (INFERIDO: la de sm8550/sm8650).
  `adsps.jsn` (PD de sensores) existe en `~/gpu-work/ramaa/s24/adsp-fw/extra/`; la tablet solo tiene `audio_pd` en su `adspua.jsn`, pero los primos no lo necesitan para libssc.

### 1.3 SoCs que funcionan (evidencia)

| SoC / dispositivo | Qué | Fuente |
|---|---|---|
| SM8450 Galaxy Tab S8+ (SLPI) | acel + luz + mag por libssc; **hacen falta raíles pm8350c L2C/L13C fijos** (sin ellos el PD cae a los 13 s por timeout I2C); gyro sin leer; necesitó 7 parches a hexagonrpcd (ruta `socinfo`, `sns_registry`, escritura de `sns_reg_version`) | sm-x800-linux PR #37 |
| SM8750 Xiaomi Pad 8 Pro (ADSP, `adsprpcd sensorspd`) | acel/luz/prox/brújula; rota la pantalla; **parche de iio-sensor-proxy** (carrera: un cliente reclama el sensor mientras el SSC aún abre ⇒ nunca rota tras el arranque) + **esperar a que el PD publique todos los sensores** antes de lanzar iio-sensor-proxy (los busca una sola vez) | piano-sensors |
| SM8550 Xiaomi Pad 6S Pro «sheng» | paquete `xiaomi-sheng-sensors` + `hexagonrpcd-adsp-sensorspd.service` manual; **sin tabla de «funciona»** | arch-xiaomi-sheng |
| SM8150 Xiaomi Pad 5 «nabu» | acel/giro/luz/mag con parches de kernel (alias IOVA alto para el SDSP, esperar PDR de root-PD antes de `INIT_ATTACH_SNS`) y de iio-sensor-proxy (gyro/mag, carrera de arranque) | nabu-accelerometer |
| SDM845/SDM670/SM6350 | pmaports MR 4050, 5329, 5290: acel + luz; matriz de montaje por udev | <https://gitlab.com/postmarketOS/pmaports/-/merge_requests/4050> |
| **SM8650 / SM7675 / SM7475** | **NO encontrado** (búsquedas 18-oct-2026; extendidas: sin resultados). SM7675 «cliffs» es primo de SM8550/SM8650; los prefijos de registro de Android son `sm7675_*` | — |

Lecciones que se aplican a la uke: (1) el ADSP lee `json.lst` primero y se rinde sin él aunque `persist` esté bien (piano); (2) el registro debe ser **una copia escribible** (el ADSP escribe `fstempfile`,
`sns_reg_version`); (3) lanzar iio-sensor-proxy **después** de que el PD publique el acelerómetro; (4) comprobar los raíles del I2C del sensor (en Android el PD ya los tiene vía
la plataforma — en mainline, ver R3); (5) 1 Hz de `Handover signaled, but it already happened` es ruido de fastrpc ya visto en audio.

## 2. Ficheros de Android: qué hace falta y dónde están

**No están en `build/android/`** (HECHO: `grep -rIl 'sns_reg\|json.lst\|sensors/config' build/android` solo da el logcat; no hay `*.json` de sensores). **Pero sí están en la tablet, en solo lectura**:

| Necesario (ruta Android) | Dónde está hoy | Cómo |
|---|---|---|
| `/mnt/vendor/persist/sensors/**` (`registry/`, `sensors_list.txt`, `*_caldata.txt`, `Lux_F_channel_data.txt`…) | partición `persist` = `/dev/sdf7`, **ext4** (HECHO: `blkid`; `debugfs -R "ls /sensors"` lista 8 ficheros + `registry/` con ~218 entradas, últimas escrituras 17-oct) | `debugfs -R "rdump /sensors DIR" /dev/disk/by-partlabel/persist` (no monta; sin replay de journal) |
| `/odm/etc/sensors/config/*.json` + `json.lst` (21 ficheros que el PD abrió: `lsm6dso_0`, `qmc6308_0`, `stk3bcx_0`, `sip1328`, `sx937x_*`, `sm7675_*`, `chre_dynamic_sensors`, `sns_*.json`…) | `odm_b` dentro de `super` (EROFS; HECHO: magic `e2e1f5e0`; `lpdump` sobre las 4 primeras MiB: **solo hay set `_b`**, `odm_b` sector 2048 + 2 336 448 sectores) | loop `-r -o 1048576 --sizelimit …` + `mount -t erofs -o ro` (el kernel de la tablet lista `erofs`), o en el PC con `erofs-utils` (`pacman -S erofs-utils`, hoy ausente) |
| `/vendor/etc/sensors/sns_reg_config` | `vendor_b` (EROFS; HECHO magic; sector 12 400 640 + 2 397 256) | idem |
| `/vendor/dsp/adsp/sns_tppe.so` (el PD lo abrió) | `vendor_b` | idem |
| `/sys/class/mi_display/disp-DSI-0/{panel_build_id,panel_info}` (el PD los abrió en Android) | sysfs de Xiaomi; **no existe en mainline** | servir un fichero estático (cosechado de Android en `build/android/*snapshot*`) vía enlace; INFERIDO: es calibración de luz por panel, no bloqueante para el acelerómetro |
| Firmware ADSP con el PD de sensores | **ya cargado** (`/lib/firmware/adsp.b*`, 53 sensores en Android; sha del paquete `adsp-fw.sha256`) | nada que extraer |

Lista exacta de rutas que abrió el PD en el arranque de Android: `build/rootfs/deploy/autorotacion/android-paths-opened-by-sensorspd.txt` (70 entradas).
Script de extracción preparado (**solo lectura, NO ejecutado**): `propuesto/uke-sensors-extract.sh` → `/root/uke-sensors-android.tar.gz`.
Alternativa literal pedida (si Android arrancase, hoy no): `adb pull /odm/etc/sensors/config`, `adb pull /vendor/etc/sensors/sns_reg_config`,
`adb root; adb pull /mnt/vendor/persist/sensors` (el slot a de super ya no tiene Android; la ruta buena es la de las particiones).

## 3. Lectura en la tablet (solo lectura, 18-oct-2026)

| Comprobación | Resultado |
|---|---|
| Kernel | `7.2.9-senemos.1.4054.3-ouke4`; `adsp` y `wpss` `running` |
| `lsmod` | `fastrpc` (refcount 2, **sin `/dev/fastrpc*`**: overlay de audio retirado), `qrtr`, `qrtr_smd`, `rpmsg_char/ctrl` |
| `/sys/bus/iio/devices` | no existe (esperado) |
| Firmware ADSP (concatenado `adsp.b00..b52`, 80 039 cadenas) | SSC completo dentro (no hay `sensorspd`/`slpi` ficheros aparte: el PD lo crea el DSP por nombre); lee `/odm/etc/sensors/config`, `/vendor/etc/sensors/sns_reg_config`, `/mnt/vendor/persist/sensors/*` |
| Userspace | `/usr/bin/ssccli`, `/usr/lib/libssc.so.2`, `/usr/lib/iio-sensor-proxy` (enlaza `libssc.so.2` y `libqmi-glib`), `iio-sensor-proxy.service` (`static`, `RestrictAddressFamilies … AF_QIPCRTR`), `/usr/bin/monitor-sensor`, `/usr/bin/adsprpcd`; **ninguno es paquete pacman** (`pacman -Qo` vacío) |
| `qrtr-lookup` / `hexagonrpcd` | **no instalados**; el servidor de nombres QRTR es el del kernel (no hace falta `qrtr-ns`) |
| Servicios QRTR visibles | **No medible sin cargar nada**: `qrtr-lookup` no está y no hay `/dev/qrtr*`. Paso propuesto en R4 (compilar `qrtr-lookup` en el PC o usar `ssccli -v`) |

## 4. Coordinación con audio (informes `AUDIO-E2*-20261018.md`, `audio-E0-handover`)

Ya resuelto y reutilizable (HECHO en los informes):
- Parche SMMU 0004 (SIDs de FastRPC del ADSP) **está en el kernel v4/ouke4**; los 5 compute-cb enlazan sin error; `/dev/fastrpc-adsp` aparece (E2b: `AUDIO-E2b-RESULTADO`).
- `adsprpcd audiopd` → `createstaticpd:audiopd` handle 0x101 + listener (mismo patrón que Android) — **sensorspd es el mismo mecanismo con otro nombre** (`adsprpcd <pd_name>`).
- Overlays en caliente (`uke_audio_e2b/e2c.ko`; `e2c` añade `memory-region=<&adsp_mem_heap>` y `qcom,vmids=<22 37>`), vigía del ADSP, regla de doble captura.
- **Salvedades que nos afectan**: (1) `fastrpc` queda con refcount colgado al retirar el overlay (solo se resuelve reiniciando) — no descargar nunca; (2) el overlay **no es persistente**; (3) el kernel comparte un único `remote_heap` por canal
  (`fastrpc.c:1341`): crear `sensorspd` tras `audiopd` reutiliza el mismo heap (en Android también); (4) **el APM de audio sigue sin responder del todo en el ciclo del PD** (hipótesis «falta el PD» refutada en 3 ciclos), así que audio todavía puede reiniciar el ADSP varias veces; (5) el ADSP lleva la carga y `recovery_disabled=true` — si cae, no se recupera.

**Orden propuesto para no pisar a audio**
1. R0–R2 y R1 (PC/lectura) en paralelo a audio: no tocan el ADSP.
2. **R3 solo cuando la sesión de audio lo autorice y el overlay `fastrpc` esté aplicado por ella** (o cuando un fastrpc persistente esté horneado): `sensorspd` se engancha al mismo `/dev/fastrpc-adsp` ya abierto; una instancia de `adsprpcd` por PD.
3. Si audio necesita reiniciar el ADSP (`stop/start`), el PD de sensores se pierde y se relanza por el servicio (`Restart=on-failure`); acordar una ventana: audio avisa, sensores paran `uke-autorotate`/`adsprpcd_sensorspd` antes y los vuelven a levantar después.
4. La persistencia (R8, fastrpc nodo+overlay horneado en el dtbo/abl) debe diseñarse **una sola vez** con audio (un único overlay `uke_fastrpc` con heap), no dos.

## 5. Etapas

| Etapa | Qué | Criterio de «hecho» | Riesgo | Autorización |
|---|---|---|---|---|
| **R0** (hecho 18-oct) | Este informe + `uke-autorotate` + unidad + `deploy.sh` + piezas `propuesto/` | `deploy.sh check` OK; prueba en el PC con `monitor-sensor`/`uke-rotate` simulados (0/270/180, lock, unlock) | nulo | ninguna |
| **R1** | Extraer Android a `/root/uke-sensors-android.tar.gz` (persist por debugfs, odm/vendor por loop `ro`) y copiarlo al PC (`build/android/sensores-YYYYMMDD/`, con `sha256`) | `json.lst` + 21 jsons + `sns_reg_config` + `persist/sensors/registry` presentes; el `json.lst` enumera ficheros que todos existen | bajo (solo lectura; un loop device `ro` en la tablet) | «solo lectura en la tablet» (regla del proyecto): OK del dueño para el loop; sin necesidad de audio |
| **R2** | Userspace: documentar procedencia de `libssc 0.4.x`/`iio-sensor-proxy`/`monitor-sensor` (PKGBUILD o nota), instalar `uke-sensors-import`, regla udev, copiar a `/var/lib/uke-sensors` | `ldd` sin faltantes; `/odm/etc/sensors/config` etc. resuelven; nada arranca solo | bajo (no toca ADSP) | dueño (cambios de rootfs); coordinar solo el nombre del paquete |
| **R3** | `systemctl start adsprpcd_sensorspd` con fastrpc ya presente (overlay de audio e2c aplicado por audio) y el vigía del ADSP armado | `createstaticpd:sensorspd` abierto, listener `adsp_default_listener`, ficheros del PD abiertos desde `/var/lib/uke-sensors` (ver `strace`/log), **ADSP `running`, carga `Charging`, WiFi/BT arriba, sin faults SMMU, sin cuelgue 5 min**; `ssccli` no obligatorio todavía | **medio-alto** (ADSP compartido con carga y audio; sin recuperación automática; cuidado con raíles I2C del sensor: el PR de SM8450 cayó a los 13 s sin L2C/L13C) | **Orden expresa del dueño + OK de la sesión de audio.** Presupuesto de operación del AGENTS (batería ≥3700 mV, vigía, doble captura). Techo de 3 ciclos |
| **R4** | `ssccli --sensor accelerometer` (y `light`) — y `qrtr-lookup` para listar servicios | 3 lecturas de acelerómetro con `|a|≈9,8 m/s²`, cambia al inclinar; luz > 0 lux. Servicios QRTR del SSC anotados | bajo si R3 verde | dueño |
| **R5** | `iio-sensor-proxy` + udev: matriz de montaje y mapa de orientación | `monitor-sensor` da `normal/left-up/bottom-up/right-up` coherentes con 4 posturas; `ACCEL_MOUNT_MATRIX` medida; `MAP_*` validado con `uke-rotate` a mano | bajo | dueño (la tablet en la mano) |
| **R6** | `deploy.sh apply` + `systemctl --user enable --now uke-autorotate` + bind de `toggle` | gira sola en 4 posturas, el táctil acierta, `lock` la fija, `unlock` aplica; 30 min sin carrera ni parpadeos | bajo | dueño |
| **R7** (auto-brillo) | `uke-autobrillo`: suscribirse a `LightLevel` de `net.hadess.SensorProxy` (D-Bus) y fijar brillo con la curva del dueño; usa el dual KTZ ×2 de la sesión `ktz-brillo` | brillo sigue a la luz sin oscilar (suavizado + histéresis, ver parche de luz de nabu) y respeta el brillo manual | bajo; depende de que stk3bcx publique (HAL `sns_stk3bcx_hal_island` en el firmware) | dueño; **coordinar con `ktz-brillo`** (misma interfaz de backlight) |
| **R8** | Persistencia en frío: fastrpc nodo+overlay horneado (UNO con audio), `adsprpcd_sensorspd.service` y `iio-sensor-proxy` habilitados con espera al acelerómetro; interruptor `/etc/uke/no-sensors` y `uke-bootguard sensors`; interacción con s2idle | reinicio en frío: rota solo sin intervención; `verify` 19/19+; el reboot no gasta reintentos de slot | **alto** (arranque; ciclo de flash o dtbo) | dueño + ledger/gates del proyecto (par bueno, sha, ≤2 escrituras/día) |

**Techo**: 3 ciclos por hipótesis en R3 (regla 11). Si tras 3 intentos el PD no publica el acelerómetro, la hipótesis se anota refutada y queda la rotación manual de T2 (ya entregada).

## 6. Riesgos y huecos conocidos

- **Sin evidencia directa en SM7675/SM8650.** El camino es el de SM8550/SM8750 (mismo SSC del ADSP, mismo `adsprpcd sensorspd`); INFERIDO por analogía.
- **Raíles del I2C de los sensores**: en mainline nadie los mantiene (el SSC los pide al RPMh por el firmware, pero el PR de SM8450 necesitó fijarlos). Si el PD cae a los ~13 s, buscar en `/sys/kernel/debug/regulator` y en `dt-full-uke-android` el nodo SLPI/ADSP de sensores.
- **Carrera de arranque de iio-sensor-proxy** (parche de piano/nabu): comprobar si nuestra 3.9 la tiene; si no, el servicio debe esperar a `ssccli`. `ExecStartPost` de la unidad propuesta lo hace de forma provisional (formato de salida de `ssccli` por verificar).
- **Orientación de los ejes**: panel landscape-nativo y táctil ya rotado por Hyprland (T2); `MAP_*` y la matriz se miden en R5, no se suponen.
- **Giróscopo, magnetómetro, hall (tapa)**: fuera de alcance; el hall va por `gpio-keys` (otra línea, `RE-FOLIO-SENSORES.md §2`).
- **`/sys/class/mi_display/...`**: ficheros Xiaomi abiertos por el PD; efecto de su ausencia desconocido (INFERIDO: calibración de luz).
- Nada de esto se ha escrito en NOTAS-OMARCHY.md ni docs/historia/ESTADO-VIVO.md (instrucción de la sesión que lo encargó).
