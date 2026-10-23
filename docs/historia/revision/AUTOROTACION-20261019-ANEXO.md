# Anexo a AUTOROTACION-20261018.md — captura en Android (19-oct-2026)

Capturado por la sesión gestora con adb + root (Magisk), Android stock en slot b, userdata recién borrado:
`build/android/sensores-20261019/` (**fuera de git**: ficheros del fabricante y calibración del aparato), `sens.tar`
(ddeeaba0653e7bce…, 237 entradas: `/vendor/etc/sensors` + `/mnt/vendor/persist/sensors`, incluido `registry/`)
y `sensorservice.txt` (`sensors_list.txt` + `dumpsys sensorservice`).

- Sensores listados: device_orient, accel, gyro, gyro_cal, ambient_light (+ back, streams, cal).
- **Acelerómetro y giroscopio = ST LSM6DSO** (`lsm6dso_0.json.lsm6dso_0.accel/gyro` en el registro). Mainline tiene
  `st_lsm6dsx` (I2C/I3C/SPI): **hipótesis sin verificar** — solo serviría si el bus del sensor es accesible desde el AP;
  en Qualcomm suele colgar de un QUP de la isla SSC que controla el ADSP. Comprobar en el DT de Android qué bus/QUP usa
  antes de elegir entre la vía libssc (R-etapas) y un driver directo.
- Registro de sensores y calibraciones (`acc_caldata.txt`, `gyro_caldata.txt`) disponibles para hexagonrpcd (etapas R).
