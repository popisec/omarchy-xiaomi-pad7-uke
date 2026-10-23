# PX-rotacion — rotación de pantalla (auto + manual) en la Xiaomi Pad 7 "uke" (SM7675/cliffs)

Preparado por P1-ROTACION · 29-sep-2026, madrugada · **sin tablet** (nada de fastboot/adb/ssh/ttyACM0)
Todo lo de este documento es preparación en frío: evidencia de los dumps, código del kernel
`/var/tmp/uke-k1` (no tocado) y prueba de paquetes/exe del rootfs Arch ya construido.

## 0. Resumen ejecutivo

| Pregunta | Respuesta corta |
|---|---|
| ¿Qué IMU tiene la uke? | **STMicro LSM6DSO** (acelerómetro + giroscopio de 6 ejes). Evidencia: `fullSensorList.txt` del persist ("lsm6dso Accelerometer/Gyroscope"), registro `sm7675_lsm6dso_0`, y el firmware del ADSP (`sns_lsm6dso`, build `palawan.adsp.prod`). |
| ¿A qué bus va? | Al **Sensor Core (SSC) del ADSP (LPASS)**. **No está en el device-tree del AP** (ni en el DTB base vendor ni en el DT vivo de Android): el AP no lo ve. Dirección/pines no constan en ningún dump (el dtsi vendor es propietario y no se publica). |
| Driver kernel | Mainline `drivers/iio/imu/st_lsm6dsx/` soporta `st,lsm6dso` (i2c y spi). En nuestro `.config` está **`=m` pero NO compilado** (no existe ni un `.ko`). Comando para activarlo en §2.3. |
| Camino recomendado | **No usar IIO**: el IMU está detrás del ADSP. Usar **iio-sensor-proxy 3.9 + libssc** (habla con el SSC por QRTR una vez que el ADSP está arriba). **El userspace ya está instalado en el rootfs Arch** que tenemos. |
| Integración Hyprland 0.56 | `hyprctl eval "hl.monitor({output=..., transform=N, scale=..." )"` (**preservando escala**) + `hl.config({input={touchdevice={transform=N}}})` con **el mismo N**. Hyprland **no** remapea el táctil al rotar (fuente citada en §4/§5). |
| Omarchy/Quickshell | No trae applet de rotación. El OSD `omarchy osd -i rotate-cw` (o `notify-send`) es opcional; los scripts lo soportan vía `ROTATE_OSD`. |
| Entregables | `rotar.sh` (rotación manual) · `autorotate.sh` (daemon con debounce, backend proxy/SSC o sysfs) · lista `pacman` exacta (§3.4). |

**Lo único que falta el día que la pantalla arranque**: (1) que el kernel arranque con Hyprland;
(2) que la cadena ADSP suba (ya preparada por P5: `uke-adsp-load.sh` + firmware con `sns_lsm6dso`);
(3) calibrar etiquetas/signos de postura (5 minutos, §6 Fase D); (4) que el táctil mainline
ponga `INPUT_PROP_DIRECT` (TODO del port Novatek, §5.2).

---

## 1. Qué sensor tiene la uke (con evidencia)

### 1.1 Chip: LSM6DSO

| Evidencia | Fichero / comando | Resultado |
|---|---|---|
| Lista de sensores vivos en Android | `debugfs -R 'cat /sensors/fullSensorList.txt' ~/proyectos/ubuntu-uke/dump/20260903-073613/partitions/persist.img` | `4 lsm6dso Gyroscope Non-wakeup` · `1 lsm6dso Accelerometer Non-wakeup` (más `qmc630x` mag, `stk_stk3bcx` ALS/PS, `sip1328`, `semtech_sx937x`) |
| Registro de calibración | `strings` del fichero `/sensors/registry/registry` del mismo `persist.img` | claves `sm7675_lsm6dso_0.json.lsm6dso_0_platform.{config,orient,placement,accel.fac_cal.*,gyro.fac_cal.*}` → instancia `lsm6dso_0` en SoC `sm7675` |
| Log Android (sscrpcd) | `~/proyectos/ubuntu-uke/dump/fastboot-boot-gki61/logcat.txt:9747-9786` | `sscrpcd … Successfully opened file /mnt/vendor/persist/sensors/registry/registry/sm7675_lsm6dso_0.json.lsm6dso_0_platform.config` (sensor pd = `sensorspd` vía fastrpc) |
| Firmware ADSP del ROM | `strings dspso.bin \| grep -i lsm6dso` (imagen `…WOZEUXM_16.0/images/dspso.bin`) | rutas de build `…/adsp_proc/ssc_drivers/lsm6dso/build/ssc_shared_libs/qdsp6/palawan.adsp.prod/lsm6dso_{,island,normal}.so` y `sns_lsm6dso_{accel,gyro}_sensor.os` + `IMAGE_VARIANT_STRING=palawan.adsp.prod` |
| Firmware ya preparado por P5 | `~/gpu-work/ramaa/s24/adsp-fw/adsp.b22` | 60 ocurrencias de `lsm6dso`, 2804 cadenas `sns_`, `IMAGE_VARIANT_STRING=palawan.adsp.prod` → el firmware que `uke-adsp-load.sh` va a cargar **ya trae el driver SSC del LSM6DSO** |

El LSM6DSO es de ST (familia LSM6DSx): I2C (0x6A/0x6B) o SPI, 3.3 V, INT1/INT2 para datos.
En el Pad 7 el chip **no cuelga del AP**: lo gestiona el Sensor Core que corre en el ADSP.

### 1.2 Por qué sabemos que NO está en un bus del AP

* **DT base vendor** (`fdtdump ~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img`): no hay nodo
  `accelerometer/gyro/imu/lsm`. Solo hay `qcom,cam-i3c-id-table`, cámaras y `thermal-sensors`.
* **DT vivo de Android** (volcado `/proc/device-tree` en
  `dump/20260903-073613/devicetree/devicetree.tar.gz`, convertido con
  `dtc -I fs -O dts`): **cero** nodos accel/gyro (se comprobó `lsm6|bmi|icm|qmi8658|mpu|st,lsm`).
* **dmesg Android** (`dump/p1-vivo-20260903/dmesg.txt`): no hay probe de IMU en el AP; solo
  servicios de sensores (`vendor.sensors*`, `sscrpcd`) y `PDR … msm/adsp/sensor_pd`.
* El dtsi vendor que sí lo describe es propietario: la rama pública `MiCode/Xiaomi_Kernel_OpenSource`
  `uke-v-oss` enlaza `arch/arm64/boot/dts/vendor -> ../../../../../qcom/proprietary/devicetree`,
  y ese directorio **no está publicado** (404). Por eso el SE QUP/pines/IRQ exactos no constan
  en ningún artefacto que tengamos; se descubrirán (si hiciera falta) sobre la tablet viva.

### 1.3 Consecuencia práctica

Hoy, en mainline, **no habrá `/sys/bus/iio/devices/*in_accel_x_raw`** para el LSM6DSO.
La vía que respeta el hardware es leer el Sensor Core a través del ADSP (**§2.4 + §3**).
La vía IIO (`st_lsm6dsx`) queda documentada por si en el futuro se recupera un bus del AP
(haría falta: SE QUP + pinctrl + IRQ + rail + añadir nodo al `xiaomi-uke.dts`; no hay datos
para prepararlo en frío).

---

## 2. Kernel

### 2.1 Driver mainline del chip (presente en el árbol)

| Fichero | Qué tiene |
|---|---|
| `/var/tmp/uke-k1/drivers/iio/imu/st_lsm6dsx/st_lsm6dsx_i2c.c:66` | `.compatible = "st,lsm6dso"` (+ `lsm6dsox`, `lsm6dsop`, `lsm6dso16is`, asm330lhhx…) |
| `/var/tmp/uke-k1/drivers/iio/imu/st_lsm6dsx/st_lsm6dsx_spi.c:61` | mismo `"st,lsm6dso"` para SPI |
| `st_lsm6dsx_core.c`, `st_lsm6dsx_buffer.c` | core FIFO/DRI; `st_lsm6dsx.h` define `ST_LSM6DSO_DEV_NAME "lsm6dso"` |

Requisitos ya cumplidos en config: `CONFIG_IIO=y`, `CONFIG_IIO_BUFFER=y`,
`CONFIG_IIO_TRIGGERED_BUFFER=y`.

### 2.2 Estado real en nuestro kernel (build k1, 29-sep 01:02)

`/var/tmp/uke-k1-build/.config`:

```
CONFIG_IIO=y
CONFIG_IIO_ST_LSM6DSX=m
CONFIG_IIO_ST_LSM6DSX_I2C=m
CONFIG_IIO_ST_LSM6DSX_SPI=m
```

Pero **no está compilado**:

* `drivers/iio/imu/st_lsm6dsx/built-in.a` mide **8 bytes** (archivo vacío) y no hay `.o`/`.ko`.
* `System.map` (01:02) tiene **0** símbolos `lsm6dso`.
* El rootfs `build/rootfs/arch-rootfs.img` solo trae `…/modules/7.2.0-rc2-palawan+/extra/{ath11k*,qcom_battmgr,qcom_pd_mapper}.ko`.

Conclusión: el día del arranque, `modprobe st_lsm6dsx_i2c` **no existe**. Hay que compilar
módulos (o hacer el driver built-in).

### 2.3 Comandos para activarlo (cuando toque; sin tocar el árbol fuente)

Opción módulos (recomendada; no toca `/var/tmp/uke-k1`):

```bash
# build aparte para no pisar el árbol compartido de F0-F5
mkdir -p /var/tmp/px-rot-build
cp /var/tmp/uke-k1-build/.config /var/tmp/px-rot-build/.config
make -C /var/tmp/uke-k1 O=/var/tmp/px-rot-build ARCH=arm64 LLVM=1 olddefconfig
make -C /var/tmp/uke-k1 O=/var/tmp/px-rot-build ARCH=arm64 LLVM=1 -j"$(nproc)" modules
# instalar en el rootfs/tablet (mismo kernel version):
#   /lib/modules/$(uname -r)/extra/{st_lsm6dsx.ko,st_lsm6dsx_i2c.ko,st_lsm6dsx_spi.ko}
# y depmod -a  (ojo: en esta imagen depmod no resuelve bien; usar insmod con ruta, como hace P5)
```

Si en su lugar se quiere built-in (sin módulos):
`/var/tmp/uke-k1/scripts/config --file .config --enable IIO_ST_LSM6DSX`
(y `--enable IIO_ST_LSM6DSX_I2C` o `--enable IIO_ST_LSM6DSX_SPI` según el bus; luego `olddefconfig`)
y reconstruir `Image`. Los flags válidos de `scripts/config` son `-e/--enable` y `-m/--module`
(**no existe `-y`**).

⚠️ **NO cambiar a `=y` `QRTR_SMD` ni `BATTERY_QCOM_BATTMGR`**: en esta imagen wedgean el arranque
(sin panic, consola muda) — ledger #404, aviso literal en `prepara/uke-adsp-load.sh`.
`CONFIG_MODVERSIONS` no está activo (los `.ko` no llevan CRC), lo que simplifica el insmod.

### 2.4 Vía SSC (la que va con el hardware): piezas de kernel ya listas

`/var/tmp/uke-k1-build/.config` tiene:

```
CONFIG_QRTR=y            CONFIG_QRTR_SMD=m        CONFIG_QCOM_Q6V5_ADSP=m
CONFIG_QCOM_FASTRPC=m    CONFIG_QCOM_Q6V5_PAS=m   CONFIG_QCOM_PDR_HELPERS=y
CONFIG_RPMSG_QCOM_GLINK_SMEM=m / _SMD=y / _RPM=y  CONFIG_QCOM_SYSMON=y
```

El DT mainline (`palawan.dtsi:2675`) trae `remoteproc@6800000 compatible "qcom,palawan-adsp-pas"`
(con `fastrpc` hijo, `glink-channels`), y nuestro fork ya añadió los compatibles
`qcom,cliffs-adsp-pas` en `drivers/remoteproc/qcom_q6v5_pas.c:1627`. En `xiaomi-uke.dts`
el ADSP **no está habilitado todavía** (no se referencia `remoteproc_adsp`).

El firmware del ADSP con los sensores está **ya staged** para P5:
`~/gpu-work/ramaa/s24/adsp-fw/adsp.mdt` (+`adsp.b00..b52`) y `adsp_dtb.*`
(copia de trabajo del ROM/EDL; `adsp.b22` contiene `sns_lsm6dso`, ver §1.1).
`prepara/uke-adsp-load.sh` + `uke-adsp.service` cargan la cadena ordenada
(`qcom_glink_smem → qcom_common → qcom_q6v5 → qcom_pil_info → qcom_q6v5_pas → qrtr_smd →
qcom_pd_mapper → pmic_glink → qcom_battmgr`) y arrancan el remoteproc.
**Si el ADSP sube, el Sensor Core (y con él el LSM6DSO) queda accesible por QRTR.**

---

## 3. Userspace

### 3.1 `iio-sensor-proxy` 3.9-1 (ALARM extra, aarch64) — **ya instalado en la imagen**

* Disponible en el repo `extra` de ALARM aarch64 (snapshot local del proyecto:
  `build/rootfs/pkgs/extra.db` + `pkgs/index.json`; también confirmado en
  `https://archlinuxarm.org/packages/aarch64/iio-sensor-proxy`).
  Paquete: `iio-sensor-proxy-3.9-1-aarch64.pkg.tar.xz`.
  Deps: `glib2 glibc libgcc libgudev **libssc** polkit`.
* **Clave**: 3.9 depende de `libssc` y el binario contiene
  `"Creating SSC accelerometer sensor failed: %s"` → soporta el **Sensor Core Qualcomm**
  (`libssc` 0.4.4-1, "Library for exposing Qualcomm Sensor Core sensors to Linux",
  deps `libqmi libqrtr-glib protobuf-c`).
* `arch-rootfs.img` (26-sep) ya tiene:
  `/usr/bin/monitor-sensor`, `/usr/lib/iio-sensor-proxy` (daemon, ELF aarch64),
  `/usr/lib/systemd/system/iio-sensor-proxy.service`,
  `/usr/lib/udev/rules.d/80-iio-sensor-proxy.rules`,
  `/usr/share/dbus-1/system.d/net.hadess.SensorProxy.conf`,
  `/usr/share/polkit-1/actions/net.hadess.SensorProxy.policy`, más
  `libssc.so.2`, `libqmi-glib.so.5`, `libqrtr-glib.so.0`, `qmi-proxy`.
  → **No hay que instalar nada para la rotación en esta imagen**, solo asegurarse de que el
  servicio arranca.

### 3.2 Qué expone (para los scripts)

* D-Bus de sistema: `net.hadess.SensorProxy`, objeto `/net/hadess/SensorProxy`.
  Propiedad `AccelerometerOrientation` (`normal`, `left-up`, `right-up`, `bottom-up`, `undefined`),
  `HasAccelerometer`; hay que llamar `ClaimAccelerometer()` para recibir cambios.
* CLI: `monitor-sensor --accel` imprime `Accelerometer orientation changed: <postura>`
  (y `=== Has accelerometer (orientation: X, tilt: Y)` al empezar; `--- No accelerometer` si no ve).
* Arranque por udev (`80-iio-sensor-proxy.rules`): el servicio se pide cuando aparece
  - un device IIO con `in_accel_x_raw` (vía kernel IIO), **o**
  - `/dev/fastrpc-adsp*` (vía `misc`) → **este es el trigger del camino SSC**.
  Si no saltara solo: `systemctl enable --now iio-sensor-proxy.service`.
* Nota: la unidad restringe `RestrictAddressFamilies=… AF_QIPCRTR` → confirma que usa QRTR.

### 3.3 Activación en la tablet (resumen)

```bash
# (con la cadena ADSP ya cargada por uke-adsp-load.sh)
ls -l /dev/fastrpc-* 2>/dev/null && lsmod | grep -E 'fastrpc|qrtr'
systemctl status iio-sensor-proxy.service        # si no está: systemctl start …  (+enable)
monitor-sensor --accel                            # prueba manual
gdbus introspect --system --dest net.hadess.SensorProxy --object-path /net/hadess/SensorProxy
```

### 3.4 Lista exacta `pacman` (deliverable #3)

```bash
# --- imprescindible para rotación (ya viene en arch-rootfs.img; por si se rehace) ---
sudo pacman -S --needed iio-sensor-proxy          # arrastra: libssc, libqmi, libqrtr-glib, libgudev, polkit

# --- sesión gráfica (AÚN NO instalada en la imagen; la mete P6/F6) ---
sudo pacman -S --needed hyprland                  # 0.56.2-3 en ALARM extra (aarch64)
sudo pacman -S --needed quickshell                # 0.3.1-1 (Omarchy la usa; opcional para rotación)

# --- diagnóstico/verificación ---
sudo pacman -S --needed libinput libinput-tools   # libinput list-devices (ver Touchscreen)
sudo pacman -S --needed python                    # lo usan rotar.sh/autorotate.sh (json)
sudo pacman -S --needed python-evdev              # solo si se usa texp-touch (gestos)
sudo pacman -S --needed python-pywayland          # OPCIONAL: solo si se escribe un cliente Wayland propio
sudo pacman -S --needed swayosd                   # OPCIONAL: OSD alternativo (ROTATE_OSD)
# AUR (opcional, diagnóstico QRTR/SSC):
#   qrtr-git   (provee qrtr-lookup; r126.ae88108-1 en el snapshot AUR del proyecto)
```

**No hacen falta**: `python-dbus`/`python-dbus-next`/`dbus-python` (se usa `monitor-sensor`),
`python-gobject`, `ydotool`, `wvkbd`/`squeekboard` (son para OSK/gestos, no rotación).
Nada de esto viene en x86_64: son paquetes **aarch64 de ALARM** (comprobado en `index.json`
del proyecto: los `.pkg.tar.xz` son `-aarch64`).

---

## 4. Integración Hyprland 0.56 (+ Omarchy 4.0.4)

### 4.1 Rotar el monitor

Hyprland 0.56 usa parser nuevo; `hyprctl keyword` da
*"keyword can't work with non-legacy parsers. Use eval."* → **usar `hyprctl eval`** (Lua):

```bash
# leer estado
hyprctl monitors -j | python3 -c 'import json,sys;m=json.load(sys.stdin);print(m[0]["name"],m[0]["transform"],m[0]["scale"])'

# aplicar (N=0 normal, 1=90°, 2=180°, 3=270°; 4-7 giros reflejados)
hyprctl eval 'hl.monitor({ output = "eDP-1", transform = 1, scale = 1.25 })'
hyprctl eval 'hl.config({ input = { touchdevice = { transform = 1 } } })'
```

**Preservar la escala**: llamar a `hl.monitor()` sin `scale` la re-deriva (bug observado 1.25→1.6
en el plugin de referencia). `rotar.sh` lee la escala actual y la pasa explícita.
Respaldo legacy (solo si el parser fuese el clásico, nunca mezclar):
`hyprctl keyword monitor "eDP-1,preferred,auto,1.25,1"` y `hyprctl keyword input:touchdevice:transform 1`.

### 4.2 Táctil: mismo índice que el monitor (obligatorio)

* Fuente Hyprland (rama actual): `src/managers/input/InputManager.cpp` →
  `setTouchDeviceConfigs()` lee `input:touchdevice:transform` (default **-1 = sin matriz**) y,
  si ≥0, llama `libinput_device_config_calibration_set_matrix(dev, MATRICES[ROTATION])`.
  La tabla vive en `src/managers/input/InputManager.hpp` como `static const float MATRICES[8][6]`.
* **No hay acoplamiento monitor→táctil**: al rotar el output no se toca la matriz del panel.
  Es el mismo hallazgo que documentó el análisis previo del proyecto (`docs/informes/D-capa-tablet-fallback.md`
  §2.1, verificado contra Hyprland 0.56.2): *"Hyprland does NOT re-map touch coords when the
  output rotates"*.
* Comprobación en marcha:
  `hyprctl getoption input:touchdevice:transform -j` debe valer lo mismo que el `transform` del monitor.

### 4.3 Omarchy 4.0.4 / Quickshell

* No existe applet de rotación ni de sensores en Omarchy/Quickshell (el plugin de referencia
  `javon27/omarchy-surface-touch` lo añade *por encima*; el proyecto decidió portar los helpers
  sueltos, no el plugin). Para rotación **no se necesita Quickshell**: basta el daemon + `hyprctl`.
* Feedback opcional: `omarchy osd -i rotate-cw -m "Rotate: N"` si existe el CLI de Omarchy;
  si no, `notify-send -i video-display`; o `swayosd-client`. `rotar.sh` lo controla con `ROTATE_OSD`.

### 4.4 Arranque

* `rotar.sh`: `install -m755 rotar.sh /usr/local/bin/rotar.sh` (o `~/.local/bin`).
* `autorotate.sh`: unidad de usuario `PartOf=graphical-session.target` (plantilla en la cabecera
  del script; `systemctl --user enable --now uke-autorotate.service`).
  Puede correr antes de que Hyprland exista: reintentará; cuando no haya Hyprland, `rotar.sh`
  falla y el daemon lo registra sin morir.

---

## 5. Mapeo del táctil al rotar

### 5.1 ¿Remapea libinput solo? No.

* libinput **sí** tiene matrices de calibración y **las aplica a cada coordenada de entrada**
  de dispositivos absolutos (touchscreens, tabletas) — doc oficial `absolute-axes`:
  *"the calibration matrix is applied to each input coordinate"* —, pero **nadie la mueve
  cuando rota el output**: Hyprland no toca `input:touchdevice:transform` al cambiar el
  `transform` del monitor (fuente en §4.2). Por eso hay que fijarla a mano **con el mismo índice**.
* Convención de las 4 matrices que usa Hyprland (`MATRICES[8][6]`, `InputManager.hpp`):
  `t0: 1,0,0, 0,1,0` · `t1: 0,-1,1, 1,0,0` · `t2: -1,0,1, 0,-1,1` · `t3: 0,1,0, -1,0,1`
  (equivale a las fórmulas de `texp-touch`: `t1:(1-y,x)`, `t2:(1-x,1-y)`, `t3:(y,1-x)`).
  Es decir: primero libinput mapea las ABS crudas, después Hyprland escala al tamaño lógico
  del monitor (dims intercambiadas en t1/t3). Documentado para poder reimplementar el
  raw→lógico en un eventual `texp-touch` port.

### 5.2 Requisito del driver táctil: `INPUT_PROP_DIRECT`

* En Android, el panel Novatek aparece como `NVTCapacitiveTouchScreen` con **`B: PROP=2`
  = `INPUT_PROP_DIRECT`** (`dump/20260903-073613/pen/proc-bus-input-devices.txt`); los lápices
  `NVTCapacitivePenM80p/P81c` también (`PROP=2`).
* El driver mainline del proyecto (`~/gpu-work/w5-touch/novatek-nt36532-spi.c:168-169`)
  tiene **pendiente** justo eso: *"TODO(W5-input): ABS_MT_SLOT 0..9, X/Y ranges, MT_DIRECT,
  INPUT_PROP_DIRECT, KEY_POWER/KEY_WAKEUP"*. El driver mainline `novatek-nvt-ts.c` de nuestro
  árbol tampoco lo pone y no soporta `nt36532`.
  Riesgo ya identificado en F-plan §F7 (R5). Si falta, el panel puede clasificarse como
  touchpad (udev marca `ID_INPUT_TOUCHSCREEN` si hay `BTN_TOUCH` **o** `DIRECT`, y como
  touchpad si hay dedo y **no** DIRECT) y la matriz de calibración podría no aplicarse.
* Verificación en device: `libinput list-devices` debe listarlo como **Touchscreen**
  (no Touchpad) y `udevadm info /dev/input/eventX | grep -E 'ID_INPUT_(TOUCHSCREEN|TOUCHPAD)'`.
* Nota lápiz: `input:touchdevice:transform` es para el táctil; los dispositivos de lápiz
  (M80p/P81c) son **tablet tools** aparte y no los cubre: pendiente decidir si necesitan su
  propio ajuste (el plugin de dibujo del proyecto lo trata por separado).

### 5.5 Consola (fbcon/DRM): fuera del alcance de la rotación de Hyprland

* `fbcon=rotate:N` (cmdline) gira **el texto de consola**, pero (a) no toca la matriz táctil,
  (b) se queda en la consola y no afecta a Hyprland. No sirve para el objetivo; solo se
  menciona por completitud (si algún día se quiere consola girada, `fbcon=rotate:1`).
* La rotación de la sesión gráfica es siempre `transform` del output + `touchdevice:transform`.
* El panel de la uke es nativo **3200×2136 en apaisado** (DTBO: `touchscreen-size-x/y`), así
  que `transform=0` = apaisado natural.

---

## 6. Plan de prueba paso a paso (cuando la pantalla arranque)

### Fase A — sin compositor (solo consola/SSH)

Prerrequisitos: `e2fsck` en frío si el ext4 sigue podrido (P7) y que la cadena ADSP suba.

1. `uke-adsp-load.sh --verbose` → esperado: `qcom-battmgr-*` en `/sys/class/power_supply` y
   `/sys/class/remoteproc/remoteprocN/state = running`.
2. `ls -l /dev/fastrpc-*` → debe existir `/dev/fastrpc-adsp` (dispara el udev de iio-sensor-proxy).
3. `systemctl status iio-sensor-proxy` (si `inactive`: `systemctl start iio-sensor-proxy`).
4. `monitor-sensor --accel` girando la tablet a mano: esperado
   `=== Has accelerometer (orientation: normal, tilt: …)` y cambios `Accelerometer orientation changed: <postura>`.
   *Si no*: `journalctl -u iio-sensor-proxy -b --no-pager | tail -50`.
5. (Opcional AUR) `qrtr-lookup` → debe listar el servicio de sensores del SSC (bus 1/2…).
   Si no aparece ninguno: el ADSP está arriba pero el PD de sensores no se anunció (riesgo §7).
6. (Solo si se elige la vía IIO) `find /sys/bus/iio/devices -name 'in_accel_x_raw'` → si aparece,
   `cat …/in_accel_x_raw` cambia al mover la tablet; `cat …/name` = `lsm6dso`.

### Fase B — con Hyprland: rotación manual

1. `hyprctl monitors -j` → anotar `name`, `transform`, `scale`.
2. `rotar.sh 90` → pantalla girada 90°, `monitor.transform=1`, touch transform=1, **misma escala**.
3. Tocar las 4 esquinas: el puntero táctil debe caer donde se toca (si cae espejado,
   el mapeo postura→transform está invertido: probar `rotar.sh 270`).
4. `rotar.sh next` ×4 → vuelve a 0 sin degradar la escala.
5. Si hay lápiz: comprobar si sus coordenadas siguen al panel (si no, ver §5.2/§7).

### Fase C — auto-rotación

1. `autorotate.sh --once` → imprime la postura actual. Comparar con la postura física.
2. `autorotate.sh --verbose` y girar la tablet: debe rotar solo tras ~0.8 s de estabilidad.
3. `autorotate.sh --lock` congela (manual manda); `--unlock` reanuda; `--status`.
4. Instalar la unidad de usuario y `systemctl --user enable --now uke-autorotate`.

### Fase D — calibración (5–10 min, una sola vez)

1. `monitor-sensor --accel` en una terminal; girar la tablet a las 4 posturas y anotar qué
   postura imprime cada una (p.ej. "de pie en horizontal" debería decir `normal`).
2. Si los nombres no cuadran con `AUTOROTATE_LABELS` (orden = transforms 0..3), ajustar
   la variable en el entorno de la unidad (o el orden por defecto).
3. Si se usa el backend `sysfs`: `autorotate.sh --backend sysfs --verbose` y ajustar los
   signos de `classify` en el script (mismos ejes que `texp-orient`, tabla del docstring).
4. Verificar el táctil tras cada rotación en las 4 esquinas. Repetir `rotar.sh N` + `hyprctl
   getoption input:touchdevice:transform -j` hasta que coincidan siempre.

### Problemas típicos → causa

| Síntoma | Causa probable | Acción |
|---|---|---|
| `monitor-sensor` dice "No accelerometer" | ADSP no arriba / PD de sensores no anunciado / fastrpc sin cargar | §2.4, `lsmod`, `dmesg | grep -iE 'adsp|fastrpc|qrtr'`, `journalctl -u iio-sensor-proxy` |
| No existe `/dev/fastrpc-adsp*` | módulo `qcom_fastrpc`/`qcom_q6v5_pas` no cargado o ADSP no `running` | `uke-adsp-load.sh --force --verbose` |
| Rota pero el táctil va espejado | touch transform no aplicado (o índice distinto) | `hyprctl getoption input:touchdevice:transform -j`; repetir con `ROTATE_OSD` off |
| `hyprctl keyword` da error de parser | config Lua (0.56) | usar `hyprctl eval` (lo hacen los scripts) |
| La escala cambia al rotar | se llamó a `hl.monitor` sin `scale` | usar `rotar.sh` (ya la preserva) |
| `libinput list-devices` lo ve como Touchpad | falta `INPUT_PROP_DIRECT` en el driver Novatek | completar TODO W5 (w5-touch) |

---

## 7. Incógnitas y riesgos (honestos)

1. **Registro del servicio SSC**: que el ADSP arranque no garantiza que el *sensorspd*/servicio
   de sensores se anuncie en QRTR. En Android lo lanza `sscrpcd` (fastrpc). Si `libssc` no lo
   encuentra tras Fase A, hay que investigar en la tablet (no preparable en frío). El firmware
   ya trae el código (`sns_lsm6dso`, `sns_*`), y la unidad `iio-sensor-proxy` está restringida
   a AF_QIPCRTR, que es la señal de que el diseño espera ese camino.
2. **Mapeo postura→transform**: los nombres/`transform` iniciales son una hipótesis
   (`normal→0, left-up→1, bottom-up→2, right-up→3`); la calibración de Fase D es obligatoria
   (el montaje del sensor varía por placa; ya pasó en el plugin de referencia).
3. **`INPUT_PROP_DIRECT`** en el táctil mainline (port Novatek W5 sin acabar).
4. **Lápiz** (M80p/P81c) tras rotar: sin cubrir por `touchdevice`.
5. **Ext4 podrido** → `e2fsck` en frío antes de fiarse de ningún arranque (P7).
6. **No mezclar** `hyprctl eval` (Lua) y `hyprctl keyword` en la misma sesión de configuración.
7. Este documento **no modifica** `/var/tmp/uke-k1` ni su build: los comandos de §2.3 usan
   un directorio `O=/var/tmp/px-rot-build` aparte, para no interferir con la serie K de kernels.

---

## 8. Anexo — comandos de evidencia usados (repetibles)

```bash
# sensor y calibración (Android persist)
debugfs -R 'cat /sensors/fullSensorList.txt' …/dump/20260903-073613/partitions/persist.img
debugfs -R 'dump /sensors/registry/registry /tmp/reg.bin' … ; strings /tmp/reg.bin | grep lsm6dso
grep -n lsm6dso …/dump/fastboot-boot-gki61/logcat.txt | head

# firmware ADSP (ROM y staging de P5)
strings -n 6 …/images/dspso.bin | grep -iE 'lsm6dso|palawan.adsp.prod' | head
strings -n 6 ~/gpu-work/ramaa/s24/adsp-fw/adsp.b22 | grep -c -i sns_
strings -n 6 ~/gpu-work/ramaa/s24/adsp-fw/adsp.b22 | grep -i IMAGE_VARIANT_STRING

# DT: que el AP no lo ve
fdtdump ~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img | grep -iE 'accel|gyro|lsm|sensor' | head
dtc -I fs -O dts /var/tmp/uke-dt > /var/tmp/uke-live.dts   # extraído de dump/…/devicetree.tar.gz
grep -icE 'lsm6|bmi|icm|qmi8658|accel' /var/tmp/uke-live.dts

# kernel
grep -n 'st,lsm6dso' /var/tmp/uke-k1/drivers/iio/imu/st_lsm6dsx/st_lsm6dsx_{i2c,spi}.c
grep -E '^CONFIG_(IIO|QRTR|QCOM_Q6V5|QCOM_FASTRPC)' /var/tmp/uke-k1-build/.config
ls -la /var/tmp/uke-k1-build/drivers/iio/imu/st_lsm6dsx/built-in.a   # 8 B = sin compilar

# userspace
debugfs -R 'stat /usr/bin/monitor-sensor' build/rootfs/arch-rootfs.img
tar xJf build/rootfs/pkgs/files/iio-sensor-proxy-3.9-1-aarch64.pkg.tar.xz -C /tmp/iio-x
strings /tmp/iio-x/usr/lib/iio-sensor-proxy | grep -i 'SSC accelerometer'
cat /tmp/iio-x/usr/lib/udev/rules.d/80-iio-sensor-proxy.rules | grep -A2 fastrpc
```
