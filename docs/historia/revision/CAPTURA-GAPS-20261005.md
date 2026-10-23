# CAPTURA-GAPS #529 — Xiaomi Pad 7 (uke), Android 16, root — 2026-10-05

Segunda pasada: detección y cierre de huecos de la captura integral (3531 ficheros del 2026-10-05).
Dispositivo: `adb -s SERIE0001` (uke, Android 16, BP2A.250605.031.A3, kernel 6.1.68-android14-11).
Solo lecturas; escrituras limitadas a `/data/local/tmp/uke-gaps/`; SELinux ya Permissive; sin toggles de radio, sin reboot.

Evidencia: `build/evidencia/android-full-gaps/` (gitignoreada).
- PC: `uke-gaps-20261005.tar.gz` (4.928.205 B) + `extracted-gaps/` (191 ficheros) + `scripts/s1..s7` + pulls incrementales por bloque.
- sha256 tar (dispositivo == PC): `178778e14759e386d2cad0d39661a359448e5c8b7d74233e89c503b6afa4552b`
- Manifest en dispositivo/PC: `manifest-shas.txt` (190 ficheros con sha256). Tar borrado del dispositivo tras verificar.

## 1. Tabla por hueco

| Hueco | Estado | Ficheros clave | Notas |
|---|---|---|---|
| H1 GMU log (G5) | **FAIL/n.a.** (el nodo NO existe en este kernel) | `h1-gmu/listing-kgsl-3d0.txt` | `/sys/kernel/debug/kgsl/kgsl-3d0/` solo contiene: `acd_calibrate, active_cnt, bcl/, ctx/, events, globals, ifpc_hyst, preemption/`. Sin `gmu-log` ni `gmu-log-gmu`. `find /sys/kernel/debug -iname '*gmu*'` → solo clks (`gpu_cc_cx_gmu_clk`), tracing kgsl_gmu_* y regulators GDSC. Conclusión: en el kernel gen7 (6.1.68) el GMU log no está expuesto por debugfs; para logs GMU hay que ir por tracing `gmu_event`/`kgsl_gmu_*`. |
| H2 GPU runtime | **OK** | `h2-gpu-runtime/sample-{1,2,3}.txt` | Adreno 732. 3 muestras a 10s (idle: 7%/6%/6% busy, cur 255 MHz, pwrlevel 8). Escalado 255–950 MHz (9 OPs). |
| H3 clk gpu | **OK** | `h3-clk/clk-gpu-{1,2,3}.txt` | clk_summary filtrado gpu|gmu|hub, 3 muestras. En idle los clks de dominio GPU aparecen a 0 (gated); `gpu_cc_cx_gmu_clk`/`gpu_cc_hub_clk_src` solo activos con GPU despierta. |
| H4 Cargador/PD | **OK** | `h4-power/` (69 fich: battery/, usb/, wireless/, ucsi…/, dumpsys-*, debugfs-votables-full.txt, dmesg-power-*) | 4 supplies: `battery`, `usb`, `wireless`, `ucsi-source-psy-soc:qcom,pmic_glink:qcom,ucsi1`. En el momento de la captura la tablet estaba enchufada al PC (SDP): **PD inactivo** — para ver negociación PD hay que enchufar cargador USB-C PD y recapturar `usb/` + `typec/port0/`. |
| H5 Bluetooth | **OK (limitado por estado)** | `h5-bluetooth/` | **BT estaba APAGADO**: `/sys/class/bluetooth/` vacío (sin hci0), debugfs BT solo l2cap/rfcomm/sco. Prohibido toglear radios → capturado lo existente: driver `btpower` vivo en dmesg (ciclos Power OFF→ON→Retention en t=6418s del arranque), HAL `vendor.bluetooth-1-1-qti` running, `btconfig` existe en `/vendor/bin/btconfig` (btmgmt/hciconfig no). Chip BT = combo **WCN6750_V2** (mismo paquete que WiFi; driver `btpower.ko` capturado). FW BT: no hay líneas de carga en el ring actual ni ficheros btfw/btnv en `/vendor/firmware` → probablemente dentro de `firmware_mnt/image` (partición modem). Pendiente: recapturar con BT ON activado por el dueño. |
| H6 WiFi runtime | **OK** | `h6-wifi/` (17 fich) | `/sys/kernel/debug/cnss2/` NO existe; sí `cnss_utils/` (fw_version, soc_id, serial_number), `icnss/stats`, y `qca_cld3_qca6750/` (ini_config, mem, cnss_runtime_pm…). Versión FW vía dumpsys wifi. |
| H7 ueventd/firmware | **OK** | `h7-init/ueventd-{vendor,system,odm}.rc`, `firmware-grep-*.txt`, `fw-layout-pc-notes.txt` | Ver sección 3. |
| H8 init rc drivers | **OK** | `h7-init/rc/` (20 .rc), `key-rc-list.txt`, `insmod-key-lines.txt` | Ver sección 4. |
| H9 módulos vendor | **OK** | `h9-modules/topull/`: `nt36532_touch.ko` (1.063.304 B), `icnss2.ko` (411.608 B), `btpower.ko` (141.920 B), `qca_cld3_qca6750.ko` (17.276.600 B) + `modules.{dep,alias,softdep,load}` de `/vendor_dlkm` y `/vendor` | modinfo strings en `key-modinfo-strings.txt` y `qca-cld3-modinfo-strings.txt`. |
| H10 DT | skip (ya capturado en pasada 1) | — | Sin carencias detectadas: gmu node `qcom,gmu@3d69000` visible en clk_summary/regulators; modelo gpu coherente. |
| H11 thermal | **OK** | `h11-h14-misc/thermal-now.txt` (63 zonas), `cooling-now.txt` (45) | Snapshot con pantalla encendida y cargando por USB: SoC 32–40 °C, aoss 32 °C. |
| H12 typec/PD partner | **OK** | `h11-h14-misc/port0/` + `port0/port0-partner/` | port0: sink, data_role device, op mode 3.0A, PD rev 3.0, TypeC 1.3, vconn no. Partner actual (PC): **sin PD** (`supports_usb_power_delivery=no`, rev 0.0). |
| H13 pstore | **OK (vacío)** | `h11-h14-misc/pstore-ls.txt` | `/sys/fs/pstore/` EMPTY: no hay ramoops de boots previos ni del actual (no ha habido crash/panic registrado). |
| H14 sensors head | **OK** | `h11-h14-misc/sensorservice-head.txt` | 53 sensores HW; visibles lsm6dso (STMicro, IMU), qmc630x (QST, magnetómetro), virtual xiaomi orientation. |

## 2. VALORES CLAVE leídos de verdad

### Carga / PD (H4)
Contexto: conectada al PC por USB (SDP), **no hay negociación PD activa ahora**.
- `usb/type` = USB, `real_type` = (vacío), `usb_type` = `Unknown [SDP] DCP CDP ACA C PD PD_DRP PD_PPS BrickID`
- `usb/current_max` = 500000 µA, `voltage_max` = 5000000 µV, `voltage_now` = 5052000 µV, `input_current_limit` = 500000
- `usb/online` = 1, `pd_active` = (vacío), `scope` = (vacío)
- `wireless/online` = 0 (Qi presente pero inactivo), `ucsi-source-psy` presente (rol UCSI del pmic_glink)
- dumpsys battery: AC false, USB true, Max charging current 500000, Max charging voltage 5000000, level 44, Li-poly
- debugfs de carga encontrado y volcado: `/sys/kernel/debug/battery_charger/` (block_tx=N), `/sys/kernel/debug/charger_ulog/` (log deshabilitado: enable=0), `/sys/kernel/debug/battery_debug/votables/` (7 votables, volcados en `debugfs-votables-full.txt`), ipc_logging `charger_ulog{,_init}` (vacíos con ulog off)

### Batería (H4, completa)
- **Modelo: `O82_8850mah_45w`** (8850 mAh, 45 W máx)
- `charge_full` = 8850000 µAh == `charge_full_design` = 8850000 → **SoH 100%**
- capacity 44%, `charge_counter` = 3908, `voltage_now` = 3913425 µV, `voltage_ocv` = 3871204 µV
- `current_now` = -498791 µA (cargando), `temp` = 270 (27,0 °C), `cycle_count` = 91, health Good, status Charging
- **Limitador de carga Xiaomi activo**: `charge_control_start_threshold` = 70, `charge_control_end_threshold` = 80 (además `charge_control_limit` = 0, `charge_control_limit_max` presente)
- `constant_charge_current` = 5780000 µA (techo CC solicitado), `charge_type` = Fast
- `resistance`, `sw_jeita_status`, `charge_limit`: atributos NO presentes en este supply (no es que fallaran: no existen)

### Bluetooth (H5)
- Radio OFF durante la captura → sin hci0, sin features/commands de debugfs, sin líneas de carga de fw BT en dmesg (el ring actual no las conserva)
- Chip: **QCA WCN6750_V2** (combo), driver `btpower` (Power OFF→ON→Retention @ 6418 s), HAL `vendor.bluetooth-1-1-qti` running, `persist.vendor.bluetooth.haltest=true`
- Tools: `btconfig` en `/vendor/bin/btconfig`; btmgmt/hciconfig no existen

### WiFi (H6)
- **FW: `3.0.0.0.642.1` HW: `WCN6750_V2`** `QC_IMAGE_VERSION_STRING=WLAN.MSL.3.0-00642-QCABMSLSWPLZ-1.81982.7.102970.2`
- Driver: `5.2.1.91G`, módulo `qca_cld3_qca6750` ("WLAN HOST DEVICE DRIVER", Dual BSD/GPL), prop `ro.hardware.wlan.chip=qca_cld3_qca6750`
- Config fw: `/vendor/firmware/wlan/qca_cld/qca6750/{WCNSS_qcom_cfg.ini, wlan_mac.bin}` (también dir `kiwi_v2`)

### GPU / GMU (H1-H3)
- **Adreno 732**, devfreq governor `msm-adreno-tz`, rango 255–950 MHz (950/900/835/736/684/633/500/353/255)
- Idle en las 3 muestras: busy 7%/6%/6%, 255 MHz, pwrlevel 8 (min), max_pwrlevel 0
- **GMU log: el fichero NO existe en este kernel** (gen7): sin `gmu-log`/`gmu-log-gmu` en debugfs; único camino = tracing (`/sys/kernel/tracing/events/kgsl/gmu_event`, `kgsl_gmu_pwrlevel`, `kgsl_gmu_oob_{set,clear}`, `gmu_ao_sync`)
- FW GMU en disco: `/vendor/firmware/gmu_gen70900.bin`, `gen70900_{aqe,sqe}.fw`, **`gen71100_gmu.bin`**, `gen71100_sqe.fw` (conviven fw 70900 y 71100)

### Rutas de firmware — CÓMO resuelve Android los paths (H7)
- Los .rc NO definen rutas de firmware: **ueventd busca por orden fijo** `{/odm/firmware, /vendor/firmware, /system/etc/firmware, /etc/firmware}` (firmware_handler de init) y, si falla, sysfs fallback — que QTI fuerza: `init.qti.kernel.rc` hace `write /proc/sys/kernel/firmware_config/force_sysfs_fallback 1`
- Symlinks de montaje: `/vendor/firmware_mnt → /firmware` y `/vendor/bt_firmware → /bt_firmware` (init.qcom.rc); `firmware_mounts_complete` en init.qcom.factory.rc
- Firmware que se auto-actualiza vive en data: `/vendor/firmware/wlanmdsp.otaupdate → /data/vendor/firmware/wlanmdsp.mbn`
- Layout real para rootfs: GPU en `/vendor/firmware/gmu_gen70900.bin|gen71100_gmu.bin`, WLAN en `/vendor/firmware/wlan/qca_cld/qca6750/`, DSPs (`CAMERA_ICP*.elf`, `st54l_fw.bin` NFC, `qps615_fw.bin` PCIe switch), modem en `/firmware/image` (firmware_mnt)
- `ueventd-vendor.rc` (33 KB) capturado con todas las reglas de nodos /dev de los drivers

### Parámetros de módulos / carga de módulos (H8-H9)
- Los módulos NO se cargan con insmod del .rc: `init.qti.kernel.rc` → `exec_start gki.modprobe` + `start vendor.modprobe` (o `load_dlkm` si `ro.vendor.qti.load_dlkm.service=native`), esperando `vendor.all.modules.ready=1`. Orden: `modules.load` de `/vendor_dlkm/lib/modules` (capturado)
- Único insmod del .rc clave: `insmod /system/lib/modules/pronto/pronto_wlan.ko con_mode=5` (solo factory)
- WLAN se arranca por sysfs, no por módulo con args: `init.vendor.wlan.rc` → `write /sys/kernel/icnss/wlan_en_delay 1000` + `write /sys/kernel/icnss/wpss_boot 1`
- modinfo de los capturados (vermagic `6.1.68-android14-11`):
  - `btpower.ko` — "MSM Bluetooth power control driver", depends: smcinvoke_dlkm, pinctrl-msm, rfkill
  - `icnss2.ko` — "iWCN CORE platform driver", depends: qcom_ipc_logging, socinfo, pdr_interface, cnss_prealloc, qcom_ramdump, rproc_qcom_common, qcom_aoss, qmi_helpers, hwid, wlan_firmware_service
  - `nt36532_touch.ko` — "Novatek Touchscreen Driver", depends: xiaomi_touch, qti_battery_charger, msm_drm, metis
  - `qca_cld3_qca6750.ko` — parms: prealloc_disabled, qdf_log_dump_at_kernel_enable, qdf_log_flush_timer_period, enable_dfs_chan_scan, enable_11d, country_code (lista completa de parmtype en `qca-cld3-modinfo-strings.txt`)

### Sensors (H14)
- 53 sensores HW: `lsm6dso` IMU (STMicro), `qmc630x` magnetómetro (QST), virtual `orientation` (xiaomi), Dynamic Sensor Manager (Google/HID)

## 3. Manifest / shas

- Tar dispositivo: `sha256 178778e14759e386d2cad0d39661a359448e5c8b7d74233e89c503b6afa4552b` (verificado idéntico en PC)
- `manifest-shas.txt`: 190 ficheros con sha256 individual (dentro del tar y en extracted-gaps/)
- Extras fuera del tar: `h9-modules/topull/qca_cld3_qca6750.ko` (pulled a PC; 17.276.600 B), `h7-init/fw-layout-pc-notes.txt`
- Vacíos conocidos (anotados, no son fallo de captura): gmu-log*.bin (nodo inexistente), debugfs charger_ulog logs (ulog enable=0), pstore (sin crashlogs), dmesg-boot cnss (ring wrapped), hci0 (BT off), PD (sin partner PD: carga SDP desde PC)

## 4. Pendiente para próxima ventana (requiere intervención del dueño)
1. Recapturar `usb/` + `typec/port0(-partner)/identity` con **cargador PD de 45 W** enchufado → valores reales de negociación (pd_active, voltage/current_max PD, PPS)
2. Recapturar H5 con **BT activado** (hci0 + debugfs hci0 + dmesg de carga fw BT)
3. GMU log: activar tracing `gmu_event`/`kgsl_gmu_pwrlevel` y capturar trace_pipe durante uso GPU (requiere escritura en /sys/kernel/tracing — solo con permiso)
