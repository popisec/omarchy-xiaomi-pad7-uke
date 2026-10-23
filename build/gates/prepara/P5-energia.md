# P5-ENERGIA — Gestión de energía en uke (batería, gestor Omarchy, suspend, protección)

**Fecha:** 2026-09-29 (madrugada) · **Fase:** preparación (sin tablet: solo lectura de logs/árbol/rootfs)
**Ámbito:** SM7675/cliffs "uke" · kernel `7.2.0-rc2-palawan+` · árbol `/var/tmp/uke-k1` (solo lectura)
**Entrega:** este informe + `bateria.sh`, `suspend-prueba.sh`, `bateria-baja-guard.sh`,
`uke-adsp-load.sh`, `uke-adsp.service`, `uke-bateria-baja.service`, `uke-bateria-baja.timer`.

> Regla de esta fase: **nada de fastboot/adb/ssh/ttyACM0**. Todo lo de abajo sale de logs ya
> capturados, del DT/kernel en disco y del rootfs. Lo que no se puede verificar sin tablet va
> marcado como **[VERIFICAR EN VIVO]** con el comando exacto.

---

## 0. Resumen para decidir en 30 segundos

| Pregunta | Respuesta |
|---|---|
| ¿La cadena de energía está viva? | **Sí, pero solo si alguien la carga a mano.** Medida viva el 28-sep: `qcom-battmgr-bat` = 3 954 881 µV. En los boots de esta noche (k4..k6b) hay **0** líneas de remoteproc/battmgr. |
| ¿Qué falta instalar? | (1) `make modules` del k1 (**hoy hay 0 `.ko`**), (2) firmware ADSP en `/lib/firmware` (56 ficheros), (3) `uke-adsp.service`, (4) `upower` (+deps) en el rootfs para el widget de Omarchy. |
| Riesgo 1 (suspend) | **Hoy no hay ningún wake source**: el PON/power-key lo descarta el parche `X9PMIC-skip` y el táctil/USB no arman wakeup → `s2idle` sería **irrecuperable** (solo long-press PON = reset duro). |
| Riesgo 2 (ABL) | El ABL lee ~3,4 V (su propio driver) y `battery-soc-ok:no` → cae a fastboot, **que es justo donde no carga**. Desde kernel/userspace **no se puede corregir esa lectura**; solo se puede (a) no quedarse en fastboot, (b) mantener la cadena ADSP arriba, (c) medir desde Arch. |

---

## (a) Estado de la cadena de energía HOY

### a.1 La cadena, eslabón a eslabón

```
celda Li-ion
  └─ PMIC PM7550/PMXR2230 (SID1) + cargador + SMB1393 charge-pump (i2c-pmic)
       └─ ADSP firmware "charger_pd"  (servicio PDR msm/adsp/charger_pd, subsys lpass)
            └─ glink (PMIC_RTR_ADSP_APPS) ⇄ pmic_glink (AP)
                 └─ aux "power-supply"  →  qcom_battmgr  →  /sys/class/power_supply/qcom-battmgr-{bat,usb,wls}
                      └─ upower → Quickshell (widget Omarchy) / scripts
```
Quien **gestiona la carga es el ADSP**, no el kernel: el kernel solo reenvía peticiones
(`battery_psy_set_charge_current` no existe; el vendor lo llama desde su `qti_battery_charger`).
Citado del proyecto hermano (`REFUTADO.md` R-50): *"La carga la configura el servicio `charger_pd`
del ADSP (por qrtr/glink + `qcom_pd_mapper` → `pmic_glink` → `qcom_battmgr`) y el bootloader no
ejecuta nada de esa cadena."*

### a.2 Evidencia de que HOY funciona (citas)

**E1 — Tablet viva, 28-sep 12:10 (kernel #82), `build/evidencia/2026-09-28/ssh-comandos-lote1.txt`:**
```
### CMD 6 (lsmod)
qcom_pd_mapper  28672 0     qrtr_smd 16384 0        qcom_battmgr 28672 0
pmic_glink      16384 1 qcom_battmgr                qcom_q6v5_pas 49152 0
qcom_pil_info   12288 1 qcom_q6v5_pas               qcom_common 16384 1 qcom_q6v5_pas
qcom_glink_smem 12288 1 qcom_common                 qcom_q6v5 16384 1 qcom_q6v5_pas
gpio_shared_proxy 20480 1
### CMD 12
3954881                                  ← /sys/class/power_supply/qcom-battmgr-bat/voltage_now (µV) = 3,955 V
qcom-battmgr-bat
qcom-battmgr-usb
qcom-battmgr-wls
```
⇒ **La cadena completa está probada en este aparato y en este rootfs.** Los módulos y el firmware
**están en disco** (el `extra/` del rootfs trae `qcom_battmgr.ko` y `qcom_pd_mapper.ko`; los otros
se copiaron por SSH desde `~/gpu-work/ramaa/s10/build-s122/`).

**E2 — Consola del 28-sep 18:32 (`consola-ultimo-boot-28sep.txt`), cargada a mano en t≈366 s:**
```
[  366.249220] remoteproc remoteproc1: powering up adsp
[  366.25xxxx] remoteproc remoteproc1: Booting fw image adsp.mdt, size 8044
[  366.xxx]    remoteproc remoteproc1: remote processor adsp is now up
[  366.218470] PDR: Indication received from msm/adsp/charger_pd, state: 0x1fffffff, trans-id: 1
[  368.150095] qcom_battmgr.pmic_glink_power_supply pmic_glink.power-supply.0:
              payload extendido del vendor (prop 0x13, 132 B): 00000030 00000013 5f32384f 30353838
```
El **t=366 s** es la prueba de que **no sube sola**: alguien hizo `insmod` a los 6 minutos.

**E3 — Android dorado (`criticas/ufs-referencia-android/dmesg-android.txt`) — el patrón bueno:**
```
[    2.739968] remoteproc remoteproc0: 3000000.remoteproc-adsp is available
[    5.756129] remoteproc remoteproc0: powering up 3000000.remoteproc-adsp   (lo dispara init: /sys/kernel/boot_adsp/boot 1)
[    8.658808] qti_battery_charger ...:qcom,battery_charger: battery_chg probe start
[    8.668347] init: wait for '/sys/class/power_supply/usb/type' took 2143ms
[    8.742611] healthd: battery l=57 v=3936 t=30.0 h=2 st=2 c=2184136 chg=
[    7.013515] PDR: Indication received from msm/adsp/charger_pd, state: 0x1fffffff
```
(En Android el ADSP también se arranca **por userspace**, a los 5,7 s, con
`echo 1 > /sys/kernel/boot_adsp/boot`; el driver es el out-of-tree `qti_battery_charger`.)

**E4 — Los boots de esta noche NO la tienen:** `k4, k4b, k4c, k5, k5b, k6, k6b-migas.log` →
**0** apariciones de `remoteproc|adsp.mdt|battmgr|power_supply`. En `k6b` sí arrancó Arch
(`systemd 262-1-arch`, hostname `uke-arch`) pero nadie cargó los módulos.

### a.3 Qué falta exactamente (lista cerrada)

| # | Falta | Evidencia / comando |
|---|---|---|
| 1 | **Módulos del k1**: el build tiene **0 `.ko`** (`find /var/tmp/uke-k1-build -name '*.ko' \| wc -l` → 0). El `.config` los tiene todos `=m`: `QRTR_SMD`, `QCOM_PMIC_GLINK`, `BATTERY_QCOM_BATTMGR`, `QCOM_Q6V5_PAS`, `QCOM_Q6V5_COMMON`, `RPMSG_QCOM_GLINK_SMEM`, `QCOM_PD_MAPPER`, `QCOM_PIL_INFO`, `UCSI_PMIC_GLINK`, `QCOM_Q6V5_ADSP`, `QCOM_Q6V5_MSS`. | `make modules && make modules_install INSTALL_MOD_PATH=<rootfs>` |
| 2 | **Firmware ADSP** en `/lib/firmware` **plano**: `adsp.mdt` (8044 B, sha256 `fd874a8d7520e8363b6345b0…`) + `adsp.b00..b52` (51) + `adsp_dtb.mdt` (4044 B, sha256 `909cf11723a898172b654bbe…`) + `adsp_dtb.b00..b02` (3). Fuente: `~/gpu-work/ramaa/s24/adsp-fw/` (58 entradas, con `MANIFEST.txt`). | `cp adsp*.b?? adsp*.mdt /lib/firmware/` |
| 3 | **Servicio de arranque** (hoy la cadena se carga a mano). Entregado: `uke-adsp-load.sh` + `uke-adsp.service`. | `systemctl enable --now uke-adsp.service` |
| 4 | **`upower` en el rootfs** (el widget de Omarchy lo exige; ver (c)). El rootfs tiene 168 paquetes y **no** tiene upower, quickshell, hyprland ni omarchy. | ver (c).4 |
| 5 | **depmod roto en la imagen**: faltan `modules.order`/`modules.builtin` en `/lib/modules/7.2.0-rc2-palawan+/`, así que `modprobe` no resuelve `qcom_battmgr → pmic_glink`. Por eso `uke-adsp-load.sh` usa `insmod` con rutas explícitas y orden topológico. (Detalle: `qrtr_smd` vive en `net/qrtr/**qrtr-smd.ko**`, con guion; el buscador del script prueba las dos formas.) | — |

### a.4 Dos avisos de fiabilidad (medidos, no teóricos)

1. **Lecturas inestables al despertar el fuel gauge.** Medido el 28-sep
   (`NOTAS-OMARCHY.md`): `voltage_now` bajando 2,869 → 2,588 V con `status=Charging` y
   `capacity=0`. Un Li-ion a 2,59 V es imposible: **el fuel gauge recién despierto miente**.
   Regla del proyecto hermano (correcta): *no mires el signo de `current_now`; lo que decide es
   `voltage_now` subiendo de forma sostenida*. Los scripts de esta entrega aplican además un
   filtro de plausibilidad (≥ 3,0 V) para no actuar sobre basura.
2. **Dialecto Xiaomi del firmware** (ya parcheado en el fork, `qcom_battmgr.c`):
   - `BATT_TTF_AVG` (0x13) contesta con payload **extendido de 132 B** en vez de 12 →
     `dev_info_once "payload extendido del vendor (prop 0x13, 132 B)"` (línea 1459).
   - `BATT_MODEL_NAME` contesta 12 B en vez de 128 → `-ENODATA` limpio (línea 1436).
   ⇒ **`time_to_full/empty` y `model_name` no estarán disponibles**; no es un fallo del port.
   Sin este parche, el lector esperaba `HZ` entero por cada consulta (`-ETIMEDOUT`) y salían
   dos líneas por segundo en consola para siempre.

### a.5 DT: **no hay que tocar nada** (verificado)

- `xiaomi-uke.dts:88-95` ya trae el nodo `pmic-glink` con
  `compatible = "qcom,lamma-pmic-glink", "qcom,sm8550-pmic-glink", "qcom,pmic-glink"`.
  El driver (`drivers/soc/qcom/pmic_glink.c:420-425`) solo tiene tres compatibles
  (`glymur`, `kaanapali`, `pmic-glink`): matchea el genérico y usa `pmic_glink_adsp_data`
  (líneas 407-410) con `client_mask = BATT|ALTMODE|UCSI` **y**
  `charger_pdr_service_name="tms/servreg"`, `charger_pdr_service_path="msm/adsp/charger_pd"`
  (líneas 411-413) — exactamente lo que declara el DT vendor.
- El aux que espera `qcom_battmgr` es `"pmic_glink.power-supply"` (`qcom_battmgr.c:1810-1811`) y lo
  crea `pmic_glink.c:352-354`. El canal glink está hardcodeado (`pmic_glink.c:284`,
  `PMIC_RTR_ADSP_APPS`).
- Variante de protocolo: el DT lista `qcom,sm8550-pmic-glink` → `QCOM_BATTMGR_SM8550`
  (`qcom_battmgr.c:1697-1706`). Correcto.
- **`qcom,gpr` debe seguir `disabled`**: el DTBO vendor ya lo trae así
  (`dt-fusionado-s238.dts:15226-15227`). El hermano midió que con `qcom,apr` activo hay un bucle
  `-22` que **drena la batería**. No habilitarlo.
- `remoteproc@6800000` (`compatible = "qcom,palawan-adsp-pas"`, `palawan.dtsi:2675-2727`) y el
  recurso `cliffs_adsp_resource` del fork (`qcom_q6v5_pas.c:1396-1423`) cubren el ADSP. Sin proxy
  PDs (correcto para este DT vendor).
- Único matiz: el nodo `pmic-glink` de `uke.dts` **no tiene hijos** (ni `qcom,battery_charger`).
  En mainline **no hacen falta**: los clientes son aux-devices creados por el driver. (El vendor sí
  los declara en su base: `stock/dtbase/base-uke.dts:13095` `qcom,battery_charger` +
  `ucsi-glink` + `altmode-glink`, con `qcom,protection-domain = "tms/servreg","msm/adsp/charger_pd"`.)

---

## (b) Suspend / resume

### b.1 Qué soporta el kernel (medido en el árbol y en dmesg)

| Pieza | Estado | Cita |
|---|---|---|
| PSCI | v1.1, **OSI mode supported**, SMC v1.3 | `k6b-migas.log:101-106` |
| cpuidle | `CPUidle PSCI: Initialized CPU PM domain topology using OSI mode` | `k6b-migas.log:896` |
| idle-states DT | silver/gold `power-collapse` (`arm,psci-suspend-param 0x40000003`) y `rail-power-collapse` (`0x40000004`), con `local-timer-stop` | `palawan.dtsi:383-420` |
| nodos PSCI | `compatible="arm,psci-1.0"`, `method="smc"`, dominios `cpu_pdN`/`cluster_pd` | `palawan.dtsi:701-716` |
| CONFIG | `CONFIG_SUSPEND=y`, `PM_SLEEP=y`, `CPU_IDLE=y`, `ARM_PSCI_CPUIDLE(_DOMAIN)=y`, `SUSPEND_FREEZER=y` | `.config` k1 |
| PDC | `qcom,palawan-pdc` presente (routing de wakeup) | `palawan.dtsi:3766-3777` |

**"freeze" (s2idle) está SIEMPRE disponible** — no depende de ningún driver:
`kernel/power/suspend.c:188-196` (`pm_states_init`: *"'mem' and 'freeze' are always present in
/sys/power/state"*). **"mem" (deep) solo si el firmware soporta `PSCI SYSTEM_SUSPEND`**
(`drivers/firmware/psci/psci.c:582-593`, sin mensaje en dmesg si va bien).

⚠️ **Detalle que muerde:** si el firmware soporta `SYSTEM_SUSPEND`, `suspend_set_ops()` deja
`mem_sleep_current = deep` por defecto (`kernel/power/suspend.c:240-247`, porque
`mem_sleep_default = PM_SUSPEND_MAX`). Entonces `systemctl suspend` (que escribe `mem`) haría
**deep**, no s2idle. Para forzar s2idle: `echo s2idle > /sys/power/mem_sleep` o cmdline
`mem_sleep_default=s2idle`.

**[VERIFICAR EN VIVO]** (una vez, sin suspender):
```
cat /sys/power/state        # esperado: "freeze mem" o al menos "freeze"
cat /sys/power/mem_sleep    # "s2idle" o "[s2idle] deep" o "s2idle [deep]"
cat /sys/devices/system/cpu/cpuidle/current_driver
```

### b.2 Wake sources: el problema serio de hoy

**No hay ninguno utilizable.** Recuento, con cita:

| Candidato | ¿Sirve hoy? | Por qué |
|---|---|---|
| **PON / power key** | ❌ | `xiaomi-uke.dts:456-458` pone `&pon_pwrkey { status="okay" }` y `:460-462` `&pon_resin` = `KEY_VOLUMEDOWN`, pero el padre PMK8550 **se descarta**: `pmic-spmi 0-00: X9PMIC-skip: qcom,pmk8550@0` (`k6b-migas.log:1083`) por el parche quirúrgico de `drivers/mfd/qcom-spmi-pmic.c:279` (toda lectura SPMI de periférico congelaba la máquina). Sin nodo padre, `pmk8550-pon` no bindea → **no hay IRQ de pwrkey**. |
| Volumen (gpio-keys) | ❌ | Existe en el **DT vendor** (`devicetree/uke.dts:1726,1837` `gpio-keys` con `volume_up`), **no** en el DT mainline. |
| Cober / hall | ❌ | Vendor: `xiaomi_hall` con `lid_hall` (GPIO 0x63=99) y `table_hall` (0x64=100) (`uke.dts:2398-2432`). Mainline: no existe. |
| Táctil novatek | ❌ | `novatek-nvt-ts.c` tiene PM ops pero **no** llama a `device_init_wakeup`/`enable_irq_wake`. |
| USB (dwc3) | ❌ | `dwc3-qcom.c:862` solo arma wakeup si el DT trae `wakeup-source`; `grep wakeup-source` en `uke.dts`/`lamma.dtsi`/`palawan.dtsi` → **0**. Sin eso no hay ni atributo sysfs `power/wakeup`. |
| RTC (rtcwake) | ❌ | El RTC es `pmk8550_rtc`, hijo del mismo nodo descartado. Sin RTC no hay `rtcwake` ni auto-despertar por reloj. |
| WiFi (WoWLAN) | ❌ | `ath11k` no carga (símbolos de `cfg80211` ausentes) y no hay WoWLAN configurado. |
| Modem | ❌/n/a | MPSS no arranca en mainline (sin firmware de módem). **El riesgo clásico "wake del modem" hoy no aplica**; el riesgo real es el contrario (no hay wake). |

**Consecuencia:** en s2idle la única condición de salida es `pm_wakeup_pending()`
(`kernel/power/suspend.c:146-158`; sin `s2idle_ops` en ARM64 sin ACPI). Con 0 wake sources
armados, la tablet **no despierta**: se queda hasta agotar la batería o hasta el **reset duro del
PON (long-press ~8-10 s)**, que ya está documentado en el proyecto como salida de emergencia.

### b.3 Plan de prueba de suspend/resume (cuando haya wake source)

Requisito de entrada: **al menos un wakeup armado y verificado** (que sea el PON o el USB del PC,
no un IRQ ruidoso). Vías para conseguirlo, en orden de coste:

1. **Barato (DT, 0 flashes de kernel):** añadir al DT mainline un `gpio-keys` con `wakeup-source`
   para volumen (los GPIOs ya están en el DT vendor) y/o un `gpio-keys` para los dos hall
   (99/100). Es el mismo camino que ya se usó para el táctil (`gpio-shared-proxy`).
2. **Medio:** añadir `wakeup-source` al nodo `usb_1_dwc3`/`ssusb` (una línea; `dwc3-qcom` ya
   respeta la propiedad). Sirve para "despertar al conectar el cable", que es un banco de pruebas
   cómodo (y el PC lo ve).
3. **Caro:** deshacer el `X9PMIC-skip` del PMK8550 para tener PON real. **No es de esta fase**:
   ese parche existe porque la primera transacción SPMI congelaba la máquina; requiere resolver
   antes el freeze del bus.

Secuencia de medida (la implementa `suspend-prueba.sh`):
```
# 0. Gate: que la cadena de energía esté arriba (si no, no hay manómetro)
sudo uke-adsp-load.sh && sudo bateria.sh
# 1. Chequeo: ¿hay wake source? (si dice NO SEGURO, PARAR)
sudo suspend-prueba.sh                 # exit 1 = no suspender
# 2. Prueba real (mata el SSH): anotar antes V0/cap0 y hora
sudo suspend-prueba.sh --run --si-seguro
# 3. Al volver (o tras recuperar con long-press): leer el resultado
sudo suspend-prueba.sh --post
```
**Verificación de consumo** (sin RTC no hay marca de tiempo fiable en suspensión):
- *Tiempo dormido*: `date` antes/después y `dmesg | grep -i 'PM: suspend'` (`suspend entry/exit`).
  `/proc/uptime` **no avanza** durante s2idle: la diferencia `wall - uptime` es el tiempo dormido.
- *Energía consumida*: `capacity` y `voltage_now` antes y después (con la advertencia de a.4:
  exigir ≥ 3,0 V y varias muestras). Cálculo honesto: `Δcapacity % / Δh` → %/h; con
  `charge_full_design` se pasa a mA medios. **No** usar `current_now` durante la suspensión (no se
  refresca) ni `power_now` (el vendor no lo sirve de forma fiable en este dialecto).
- Criterio de éxito: vuelve **solo** (sin long-press), `dmesg` con `PM: suspend exit`, y consumo
  < ~1 %/h en reposo (referencia: en Android un tablet en doze ronda 0,2-0,5 %/h; aquí, sin
  modem ni WiFi, debería ser bajo).

**Riesgos residuales de suspend:** (i) no volver (b.2); (ii) si algún día se levanta `mpss`,
el modem puede impedir el reposo profundo o despertar solo — habría que comprobar
`/sys/class/remoteproc/*/name` y no dejar MPSS `running` durante la prueba; (iii) `ath11k`
tampoco está: no habrá wake por WiFi.

---

## (c) Gestor de batería en Omarchy: mecanismo y dependencias

### c.1 Cómo muestra la batería (código real, rama `quattro`)

1. **Widget de barra `omarchy.power`** — `shell/plugins/panels/power/Panel.qml` (536 líneas):
   `import Quickshell.Services.UPower` y lee `UPower.displayDevice` (`percentage`, `state`,
   `isPresent`), `UPower.onBattery` y `UPowerDeviceState.{Charging,Discharging,FullyCharged,
   PendingCharge}`; pinta icono, % opcional (`showPercentage`) y el flujo de carga. Está en el
   layout por defecto: `config/omarchy/shell.json` → `bar.layout.right` termina en
   `{"id":"omarchy.power"}`.
2. **Servicio de aviso `omarchy.battery`** — `shell/plugins/services/battery/Service.qml`:
   `readonly property int batteryThreshold: 10`; si está descargando y `% ≤ 10` llama a
   `omarchy-battery-low <nivel>` → `bin/omarchy-battery-low` = `omarchy-notification-send`
   (crítico, 30 s) + `omarchy-hook battery-low <nivel>` → hooks en
   `config/omarchy/hooks/battery-low.d/` (ejemplo: `play-warning-sound.sample`). Además aplica
   perfiles: `omarchy-powerprofiles-set battery|ac`.
3. **CLI**: `bin/omarchy-battery-status` usa **`upower -e` / `upower -i`** (¡el binario!) y para el
   `power_now` instantáneo lee `/sys/class/power_supply/<native-path>/power_now`, con la variable
   `OMARCHY_POWER_SUPPLY_PATH` para redirigir la base (útil en tests).
   `bin/omarchy-notification-battery` = notificación con ese texto.

**Mecanismo en una línea:** Quickshell → **D-Bus `org.freedesktop.UPower`** → `upowerd` →
`/sys/class/power_supply`. **No** lee sysfs directamente el widget, y **no** hace falta python.

### c.2 Gotchas específicos de uke (importantes)

- `bin/omarchy-battery-present` recorre `/sys/class/power_supply/BAT*`:
  **nuestro nodo se llama `qcom-battmgr-bat` → no matchea** y el helper devuelve "no hay batería".
  El widget **no** usa ese helper (usa UPower), así que el efecto es limitado, pero conviene
  saberlo si algún script de Omarchy lo llama.
- `omarchy-power-present` (AC) sí funciona: busca `type == Mains|USB` con `online == 1`, y
  `qcom-battmgr-usb` cumple.
- **Sin cadena ADSP no hay batería para nadie**: ni UPower, ni el widget, ni el aviso del 10 %.
  Por eso `uke-adsp.service` es prerrequisito del gestor.
- `upower` clasifica por `type=Battery` + `present=1`: `qcom-battmgr-bat` cumple (el driver lo
  registra con `POWER_SUPPLY_TYPE_BATTERY`).
- Perfiles de energía: `omarchy-powerprofiles-set` habla con **power-profiles-daemon** por
  `busctl`; sin ppd instalado, el menú de perfiles queda vacío (no rompe nada).

### c.3 Comprobación (en vivo, cuando esté instalado)

```
upower -e                       # debe listar .../devices/battery_... (qcom-battmgr-bat)
upower -i $(upower -e | grep BAT | head -1)   # percentage / state / energy-rate
busctl get-property org.freedesktop.UPower /org/freedesktop/UPower org.freedesktop.UPower OnBattery
```
Si `upower -e` no lista nada: la cadena ADSP está caída (mirar `bateria.sh`).

### c.4 Dependencias exactas e instalación (el rootfs NO tiene red)

Paquetes a añadir al rootfs (aarch64, Arch Linux ARM; versiones consultadas 28-sep-2026):

| Paquete | Versión ALARM | Para qué | Deps que además hay que traer |
|---|---|---|---|
| `upower` | `1.91.4-1` | `upowerd` + CLI `upower` (widget y OSD) | `libgudev`, `libimobiledevice`, `libplist`, `polkit` (glib2/glibc/libgcc ya están) |
| `power-profiles-daemon` | existe (200 OK) | menú de perfiles de `omarchy.power` | `upower`, `libgudev`, `polkit`; `python-gobject` opcional para `powerprofilesctl` |
| `quickshell` | `0.3.1-1` | el shell (el widget vive aquí) | ya planificado en el port de Omarchy (doc C) |
| `omarchy` (repo `[omarchy]` edge) | `4.0.4-1` | scripts `omarchy-battery-*`, hooks, layout | idem |

Como la tablet **no tiene red**, la instalación es **offline**: descargar los `.pkg.tar.xz` a
`build/rootfs/pkgs/` y extraerlos con `bsdtar` igual que el resto (`PACKAGES-OVERLAY.txt`), o bien
`pacman -U` dentro de un chroot al montar la imagen. `upower` trae un servicio D-Bus
(`/usr/share/dbus-1/system-services/org.freedesktop.UPower.service` + `/usr/lib/systemd/system/upower.service`);
con dbus-broker (ya presente) arranca solo al primer uso, pero conviene `systemctl enable upower`.

**Orden de instalación en la imagen (recomendado):**
```
1) make modules (k1) + modules_install al rootfs
2) cp ~/gpu-work/ramaa/s24/adsp-fw/{adsp.mdt,adsp.b00..b52,adsp_dtb.mdt,adsp_dtb.b00..b02} /lib/firmware/
3) cp prepara/uke-adsp-load.sh -> /usr/local/bin/ ; prepara/{bateria.sh,suspend-prueba.sh,bateria-baja-guard.sh} -> /usr/local/bin/
4) cp prepara/uke-adsp.service uke-bateria-baja.service uke-bateria-baja.timer -> /etc/systemd/system/
5) pacman/bsdtar: upower (+deps) [y ppd]
6) systemctl enable uke-adsp.service uke-bateria-baja.timer upower
7) (omarchy/quickshell: los añade P6, no esta fase)
```
En el primer arranque: `bateria.sh` (debe dar V y %), `suspend-prueba.sh` (debe decir NO SEGURO
mientras no haya wake source), `systemctl status uke-adsp uke-bateria-baja.timer`.

---

## (d) Protección de batería baja

### d.1 Diseño de `bateria-baja-guard.sh`

- Umbrales: **aviso 15 %**, **acción 8 %** (configurables `--umbral/--apagado`).
- **Histéresis**: exige `UKE_MUESTRAS=3` lecturas consecutivas bajo el umbral (el timer corre
  cada 2 min ⇒ ~6 min de confirmación). Con `status=Charging|Full|Not charging` reinicia
  contadores.
- **Filtros de plausibilidad** (contra el fuel gauge recién despierto): `present=1`,
  `voltage_now ≥ 3,0 V`, `capacity ≤ 100`. Si fallan → exit 5 y **no actúa**.
- **Sin nodo → exit 4 y se grita en el log.** Nunca se asume un 100 % (trampa del hermano:
  `|| echo 100` dejaba su `uke-battery.service` siempre en 100 y **nunca apagaba**).
- **Acción por defecto `poweroff`**, *no* `suspend`: hoy suspender es irrecuperable (b.2).
  `--accion suspend` existe pero avisa; `--accion log` para probar sin apagar.
- `flock` para que el timer no solape instancias; log en `/var/log/uke-bateria.log`.
- Notifica por `omarchy-notification-send` si existe y por `wall` si no.

### d.2 Unidades entregadas

- `uke-bateria-baja.service` (`Type=oneshot`, `After=uke-adsp.service`,
  `SuccessExitStatus=0 2 3 4 5` para que los avisos no marquen la unidad como fallida).
- `uke-bateria-baja.timer`: `OnBootSec=3min`, `OnUnitActiveSec=2min`, `AccuracySec=15s`.

### d.3 Cómo probarlo (sin tablet, y luego en el próximo boot)

**Ya probado en el PC con un nodo falso** (misma lógica, `UKE_BAT_NODO` apunta a un árbol falso):
```
mkdir -p /tmp/fakebat && printf 'Battery\n' >/tmp/fakebat/type && printf '1\n' >/tmp/fakebat/present
printf 'Discharging\n' >/tmp/fakebat/status && printf '12\n' >/tmp/fakebat/capacity && printf '3650000\n' >/tmp/fakebat/voltage_now
for i in 1 2 3; do UKE_BAT_NODO=/tmp/fakebat UKE_LOG=/tmp/g.log UKE_ESTADO=/tmp/g.state \
  ./bateria-baja-guard.sh --dry-run --accion poweroff --umbral 15 --apagado 8; done
# -> muestras 1/3, 2/3, 3/3 + "AVISO emitido al 12%"
printf '6\n' >/tmp/fakebat/capacity   # ahora por debajo del umbral de apagado
UKE_BAT_NODO=/tmp/fakebat ... ./bateria-baja-guard.sh --dry-run --accion poweroff --umbral 15 --apagado 8
# -> "DRY-RUN: systemctl poweroff (cap=6%)"  exit 3
```
**En la tablet (próximo boot), secuencia exacta:**
1. `bateria.sh` → comprobar que hay V/% reales.
2. `bateria-baja-guard.sh --dry-run --umbral 99 --apagado 1` → debe emitir AVISO sin apagar
   (el aviso es una notificación/`wall`, inofensivo).
3. `systemctl start uke-bateria-baja.service; journalctl -u uke-bateria-baja -n 30`.
4. Prueba real del apagado **solo** cuando haya batería de sobra y acceso físico:
   `bateria-baja-guard.sh --dry-run --accion poweroff --apagado 100` (no apaga por el `--dry-run`),
   y después `systemctl poweroff` a mano para validar el camino real.
5. Dejar el timer activo (`enable --now`) y verificar que no se solapa:
   `journalctl -u uke-bateria-baja -f` durante 10 min.

---

## (e) El bug del ABL (lee ~3,4 V cuando el kernel ve 4,4 V)

### e.1 Qué es, con evidencia

- El ABL (bootloader) tiene **su propio driver de PMIC**, independiente del kernel. Lee ~3,4 V y
  pone `battery-soc-ok: no`; el kernel, con la cadena ADSP arriba, reporta 4,42 V y `capacity=99`
  (hermano, `REFUTADO.md` R-51). Medidas nuestras: `fastboot getvar battery-voltage` 3412→3406 mV
  mientras `voltage_now` desde Arch era 3 954 881 µV (`docs/historia/ESTADO-VIVO.md:80`, `NOTAS-OMARCHY.md:843`).
- Consecuencia: la tablet **cae aleatoriamente a fastboot** por `battery-soc-ok`, y **en fastboot
  no carga** (el bootloader no ejecuta la cadena `charger_pd`): medido 3451→3411 mV en 3 min
  (hermano) y 3662→3655 mV (R-44). Es una trampa circular: cae a fastboot justo donde la batería
  no se recupera.

### e.2 Qué se puede hacer desde kernel/userspace: **poco, y hay que decirlo claro**

| Acción | ¿Sirve? | Por qué |
|---|---|---|
| Corregir la lectura del ABL desde Linux | **NO** | El ABL corre **antes** que el kernel, con su propio driver; no lee nada de nuestra rootfs. No hay interfaz (fuera de EDL/firmware del bootloader, que está vetado). |
| Tocar `vbmeta`/AVB para saltar el check | **NO** (vetado) | AVB ya está "decorativo" (unlocked) y el check es del ABL, no de AVB. Regla C.5 del proyecto: no tocar `vbmeta`. |
| Esperar en fastboot a que suba | **NO** | Medido: en fastboot la tensión **baja**. |
| **Mantener la cadena ADSP arriba en Linux** | **SÍ** | Es lo único que **gestiona** el cargador (detecta DCP/PD, `STATUS=Charging`, `CHARGE_TYPE=Fast`, hermana `FLASH-LEDGER.md` §4833). Con la tablet apagada, el PMIC carga con sus valores por defecto y nadie lo vigila. |
| **Si cae a fastboot: apagar y usar cargador de pared** | **SÍ** | `off-mode-charge=1` ya está puesto; apagada **sí** carga. |
| **Medir desde Arch en vez de ir a fastboot** | **SÍ** | `bateria.sh --umbral 3700` da el gate sin gastar un intento de slot. Es la comodidad que faltaba. |
| Dejar que el fuel gauge recalibre (la lectura del ABL depende del modelo OCV/SOC del PMIC, que el ADSP mantiene/actualiza) | **HIPÓTESIS, no medida** | Es plausible que correr Linux con la cadena arriba un rato mejore la lectura del ABL, pero **no está medido**. No planificar con eso. |

**Recomendación operativa (doble gate antes de cualquier flash):**
```
1) Desde Arch:  bateria.sh --umbral 3700      # exit 0 = pasa
2) En fastboot: battery-voltage >= 3700 mV y battery-soc-ok: yes
3) Si cae a fastboot por debajo: NO flashear; apagar y cargador de pared 15-20 min.
```

---

## (f) Termal y governors

### f.1 Termal hoy

- **tsens**: `CONFIG_QCOM_TSENS=y` (built-in). El DT trae 3 controladores
  (`tsens0/1/2` en `palawan.dtsi:3779,3794,3809`, `compatible="qcom,palawan-tsens",
  "qcom,tsens-v2"` → el driver matchea el genérico `qcom,tsens-v2`, `tsens.c:1213-1214`) y las
  `thermal-zones` completas (aoss0/1, cpuss0/1, cpu0..cpu7, gpu0/1/2…).
- **No hay ninguna línea de tsens en los dmesg** — pero eso **no** prueba fallo: el driver solo
  imprime en `dev_dbg` (`tsens.c:94,148,219,…`), y el log corre a `loglevel=6`. **[VERIFICAR EN
  VIVO]**: `for z in /sys/class/thermal/thermal_zone*; do echo "$z $(cat $z/type) $(cat $z/temp)"; done`
- **Trips**: CPU `critical = 110 °C` (p.ej. `cpu0-thermal`, `palawan.dtsi:5283-5293`); GPU con
  `hot 110 / critical 115`. **No hay cooling-maps para CPU** (solo `cooling-device = <&gpu>` en las
  zonas GPU). Es decir: **la CPU no tiene throttling térmico configurado**; si se calienta, el
  único mecanismo es el `critical` (apagado de emergencia).
- `CONFIG_QCOM_LMH=m` **y no está en la imagen** ⇒ el Limit Management Hardware (el throttling
  del vendor) no está activo. `CONFIG_CPU_THERMAL=y` está, pero sin mapas que lo usen.
- Governor térmico por defecto: `step_wise` (`CONFIG_THERMAL_DEFAULT_GOV_STEP_WISE=y`;
  en `k6b-migas.log:303-304` se registran `step_wise` y `power_allocator`).

**Riesgo real:** tablet + governor `performance` + sin cooling de CPU ⇒ se puede llegar al trip
crítico (110 °C) y apagar de golpe. Para una tablet en la mano es inaceptable.

### f.2 cpufreq: qué hay puesto y qué recomiendo

- **Hoy el cmdline fuerza `performance`**: `/proc/cmdline` de la tablet incluye
  `cpufreq.default_governor=performance` (heredado de la cmdline del vendor/ABL; lo imprime
  también el kernel: `dmesg-arch.txt:162`). Además `sysctl.kernel.sched_pelt_multiplier=4`
  (tuning de rendimiento del vendor).
- Disponibles en el k1: `schedutil` (además de `performance/powersave/ondemand/conservative/
  userspace`); el **default del kernel es `schedutil`** (`CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL=y`).
- **EAS está disponible**: los 8 CPUs traen `dynamic-power-coefficient` (`palawan.dtsi:85,125,…`)
  y `CONFIG_ENERGY_MODEL=y`, `CONFIG_SCHED_MC=y`, `CONFIG_UCLAMP_TASK=y`. Con `schedutil` + EAS
  el consumo en cargas ligeras (lo normal en una tablet) es sensiblemente mejor que con
  `performance`, que clava la frecuencia máxima.
- Sobre "schedutil + rtv": **en este kernel no existe ningún governor `rtv`** (la lista está
  arriba). Si te referías a **RT (real-time)** como clase de scheduling: no hay que usarla para
  nada de usuario; el shell y Hyprland deben ir en `SCHED_OTHER`/`SCHED_BATCH`. Mi recomendación:
  **`schedutil` + quitar `sched_pelt_multiplier=4`** (dejarlo en el default 1, o 2 como mucho:
  el 4 es un tuning de rendimiento del vendor que empeora la eficiencia).

**Recomendación concreta para la tablet:**
```
# quitar de la cmdline:  cpufreq.default_governor=performance  y  sysctl.kernel.sched_pelt_multiplier=4
# (o, en caliente, sin reflashear:)
echo schedutil | tee /sys/devices/system/cpu/cpufreq/policy*/scaling_governor
# y para el termal, cuando se toque DT: cooling-maps cpuX-thermal -> cooling-device = <&cpuN THERMAL_NO_LIMIT THERMAL_NO_LIMIT>
# o portar qcom_lmh (CONFIG_QCOM_LMH=m) si el DT tiene los nodos lmh.
```
Mientras no haya cooling de CPU, `bateria.sh`/`suspend-prueba.sh` imprimen el máximo de
`thermal_zone*` para que el operador vea la temperatura antes de cargar la tablet (en la práctica,
para esta fase: **no hace falta tocar nada para arrancar; sí para dejarlo como producto**).

---

## 2. Riesgos (los dos que mandan)

| # | Riesgo | Detalle | Mitigación de esta fase |
|---|---|---|---|
| **R1** | **Suspend sin wake source = tablet muerta hasta reset duro** | 0 wake sources armados (PON descartado por `X9PMIC-skip`, táctil/USB sin `wakeup-source`, sin RTC). s2idle solo sale por `pm_wakeup_pending()`. | `suspend-prueba.sh` dictamina **NO SEGURO** y **aborta** `--run`; el guard de batería **no suspende** por defecto (apaga). Antes de suspender: gpio-keys/hall en DT o `wakeup-source` en el USB. |
| **R2** | **Caída a fastboot por `battery-soc-ok` (ABL lee 3,4 V) y en fastboot no carga** | El ABL no ejecuta la cadena `charger_pd`; su lectura es suya y no se puede corregir desde Linux. | Doble gate (Arch + fastboot) antes de flashear; `bateria.sh --umbral 3700`; si cae a fastboot, apagar + cargador de pared; mantener `uke-adsp.service` para que **sí** cargue mientras corre Linux. |

Riesgos secundarios anotados: (R3) lecturas del fuel gauge no fiables al principio (filtros en los
scripts); (R4) CPU sin throttling térmico (f.1) — no bloquea, pero es deuda para "producto".

---

## 3. Anexo A — ficheros entregados en `build/gates/prepara/`

| Fichero | Qué es |
|---|---|
| `P5-energia.md` | este informe |
| `bateria.sh` | estado legible de la energía (humano/`--json`/`--watch`/`--umbral` gate) |
| `suspend-prueba.sh` | chequeo de seguridad + prueba de suspend + lectura post-resume |
| `bateria-baja-guard.sh` | guardia de batería baja (aviso 15 %, apagado 8 %, histéresis, filtros) |
| `uke-adsp-load.sh` | carga ordenada e idempotente de la cadena ADSP (firmware + módulos + start) |
| `uke-adsp.service` | unidad oneshot que la levanta en cada arranque |
| `uke-bateria-baja.service` / `.timer` | timer de 2 min que llama al guardia |

## 4. Anexo B — citas crudas (para no repetir la búsqueda)

```
# cadena viva
build/evidencia/2026-09-28/ssh-comandos-lote1.txt   (CMD 6 lsmod, CMD 12 = 3954881)
build/evidencia/2026-09-28/consola-ultimo-boot-28sep.txt:2982,2984,3022,3032,3049
build/evidencia/2026-09-28/dmesg-arch.txt:2071-2072,2091-2092,2102,2112,2151-2152
criticas/ufs-referencia-android/dmesg-android.txt:3467,6567,8247,8550,8592,8623
# cadena ausente en los boots de esta noche
~/proyectos/out/k{4,4b,4c,5,5b,6,6b}-migas.log -> 0 lineas power_supply/battmgr
# PON descartado
~/proyectos/out/k6b-migas.log:1083  "pmic-spmi 0-00: X9PMIC-skip: qcom,pmk8550@0"
/var/tmp/uke-k1/drivers/mfd/qcom-spmi-pmic.c:279
/var/tmp/uke-k1/arch/arm64/boot/dts/qcom/xiaomi-uke.dts:456-462
# pmic_glink / battmgr
/var/tmp/uke-k1/drivers/soc/qcom/pmic_glink.c:284,342-354,407-425
/var/tmp/uke-k1/drivers/power/supply/qcom_battmgr.c:1436,1459,1697-1706,1810-1811
/var/tmp/uke-k1/drivers/remoteproc/qcom_q6v5_pas.c:1396-1433,1627-1628,1640-1643
# suspend
/var/tmp/uke-k1/kernel/power/suspend.c:37-51,146-158,176-196,240-247
/var/tmp/uke-k1/drivers/firmware/psci/psci.c:530-560,582-593
/var/tmp/uke-k1/drivers/usb/dwc3/dwc3-qcom.c:862
/var/tmp/uke-k1/arch/arm64/boot/dts/qcom/palawan.dtsi:383-420,701-716,3766-3777
# termal
/var/tmp/uke-k1/drivers/thermal/qcom/tsens.c:1213-1214 (fallback qcom,tsens-v2)
/var/tmp/uke-k1/arch/arm64/boot/dts/qcom/palawan.dtsi:3779-3821,5078-5402,5283-5293
# Omarchy (rama quattro, omacom/omarchy)
shell/plugins/panels/power/Panel.qml  · shell/plugins/services/battery/Service.qml (threshold 10)
bin/omarchy-battery-status (upower -e/-i) · bin/omarchy-battery-low · bin/omarchy-battery-present (BAT*)
config/omarchy/shell.json (bar right: omarchy.power) · config/omarchy/hooks/battery-low.d/
# rootfs
build/rootfs/arch-rootfs.img: /usr/bin sin upower/quickshell; 168 paquetes; /lib/modules/.../extra con 5 .ko
```
