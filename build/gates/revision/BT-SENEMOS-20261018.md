# BT sobre senemos v3 (ouke3) — inventario, bloqueos y plan por etapas (FASE 1, solo lectura)

Fecha de medición: 18-oct-2026, 01:1x–01:3x CEST (reloj de la tablet; uptime 5–19 min). Tablet: `7.2.9-senemos.1.4054.3-ouke3`, slot a,
WiFi asociado a 5 GHz (5180 MHz). Rutas relativas a `~/proyectos/omarchy-uke` (en adelante `R/`).
Convención: **MEDIDO** = comando+salida o fichero:línea de este repo/árbol del kernel; **INFERIDO** = deducción mía, a refutar
(la columna "cómo refutarlo" está en §8). Nada de lo que aquí figura como MEDIDO viene de memoria.

## 0. Qué se hizo (y qué no)

- **En la tablet, solo lectura**: `cat`/`ls`/`xxd`/`find` bajo `/proc/device-tree`, `/sys/firmware/devicetree`, `/sys/class`, `/sys/bus`,
  `/sys/kernel/debug/pinctrl/*/pinmux-pins`; `lsmod`, `dmesg`, `pacman -Q/-Si/-Ql/-Qo`, `modprobe --show-depends`/`-R` (simulacro, no carga),
  `modinfo`, `ip`/`wpa_cli`/`iw` (estado), `df`. Nada de módulos cargados, blacklists, escrituras en sysfs/debugfs, reinicios ni fastboot.
- **Una desviación de método que declaro**: leí `/sys/kernel/debug/gpio` **tres veces** (dos por descuido de una tubería, una a propósito para
  capturar la sección del TLMM). Sin incidente (la tablet sigue arriba, uptime 19 min al cerrar). Ese fichero lee el registro de control de cada pin
  por gpiolib, no un rango MMIO crudo, y `gpio-reserved-ranges = <8 4>, <56 5>` deja fuera los pines protegidos (MEDIDO, §2.1 D11). Aun así:
  no repetirlo sin necesidad (regla 3 de `docs/historia/AGENTS.md`).
- **En el PC**: este informe y ficheros en el scratchpad de la sesión (overlay borrador compilado y aplicado con `fdtoverlay`, §App. A).
  No toqué `build/rootfs/deploy/audio/` (solo lectura de su README, un `.dtso` de ejemplo y `build.sh` para reutilizar su base de DT). Sin commit.

## 1. Resumen ejecutivo

1. **Quitar la blacklist de `hci_uart` no activa el BT, ni hace falta para probarlo.** Hoy el BT no tiene dónde engancharse: la UART del chip
   (`qcom,qup_uart@888000`, SE2 de QUP1) está `disabled` por el transform del ABL (`uke_scope_qup_buses`) y además lleva el compatible vendor
   `qcom,msm-geni-serial-hs`, que el driver mainline no atiende; y bajo ella no hay nodo serdev `qcom,wcn6750-bt` (el `bt_wcn6750` que existe es
   un nodo de plataforma para el `btpower.ko` de Android, sin driver aquí). Hace falta un **overlay de DT** (§App. A, ya compila y se aplica en el PC).
2. **No hay forma de aplicar un overlay en caliente sin un módulo propio** (`OF_OVERLAY=y`, pero sin `OF_CONFIGFS`; el audio llegó a la misma
   conclusión). Camino: módulo cargador con `of_overlay_fdt_apply()` (exportado GPL) — **sin reflashear**. La alternativa (hornearlo en `uke-abl.c`) es un flash.
3. **Hay un bloqueo de verdad fuera del DT: el rail del amplificador de potencia.** `vddrfa2p2` ← `pmr735a_s3` (1,6–2,4 V) **no está registrado**
   en el kernel ouke3: `qcom-rpmh-regulator-uke.c:1995-2013` solo admite una lista cerrada de recursos y `smpe3` no está. Para la etapa en vivo se
   propone **omitir** ese supply (el core pone un regulador dummy); activarlo de verdad exige kernel v4 (flash).
4. **El firmware que pide el kernel no está en el rootfs**: el chip es ROM 1.2 (`BTFW.MOSELLE.1.2.0…`), mainline pide `qca/msbtfw12.mbn` + `qca/msnv12.bin`; el
   rootfs solo trae la rev 11. Los dos ficheros están extraídos del vendor en `build/android/` (shas en §2.3) y la fuente primaria son las particiones `bluetooth_a/_b`.
5. **Convivencia con WiFi: favorable y sin recursos "exclusivos" en conflicto.** Los rails `s1`, `s2`, `s3` (ya encendidos por `ath11k_ahb`) y `l7` los toma el BT por
   refcount (no cambia tensiones). **Un único efecto sí toca al WiFi**: `hci_qca` declara 257 mA de carga sobre `s2` (`vddrfa1p2`) y ese rail cambia de modo con
   umbral de 200 mA (hoy `standby`; en Android estaba en `fast`), §3. Lo demás es independiente: BT_EN (156) y SW_CTRL (80) no los usa nadie; la UART, el firmware (por UART, no
   por WPSS) y la IRQ son otros. El otro acoplamiento real no es con el WiFi: el wrapper QUP1 comparte ICC/reloj con el backlight secundario (KTZ).
6. **Primer paso propuesto = B0 (en el PC) + B1 (ficheros inertes en la tablet)**: riesgo nulo para el WiFi (B0 no abre ssh; B1 no carga nada). El primer paso que enciende
   el chip es B4 y va precedido de B2 (módulos sin hardware) y B3 (UART sola).
7. Decisiones del dueño en §7 (cargar módulos en vivo, mantener o quitar la blacklist, BD address, rail PA, instalar bluez).

## 2. Inventario

### 2.1 Hardware y DT (estado vivo)

| # | Dato | Valor | Tipo | Fuente |
|---|---|---|---|---|
| D1 | Nodo del BT | `/soc/bt_wcn6750`, `compatible="qcom,wcn6750-bt"`, hijo de `/soc` (no de la UART). Platform device `soc:bt_wcn6750` **sin driver** (suppliers: `ldob7`, `smpb1`, `smpb2`, `smpb3`, `f000000.pinctrl`) | MEDIDO | `/proc/device-tree/soc/bt_wcn6750/*`; `ls /sys/bus/platform/devices/soc:bt_wcn6750/` |
| D2 | GPIOs del nodo | `qcom,bt-reset-gpio=<tlmm 156>`, `qcom,bt-sw-ctrl-gpio=<tlmm 80>`, `qcom,wl-reset-gpio=<tlmm 35>`, `mpm_wake_set_gpios=<80>`; `pinctrl-0=<bt_en_sleep>` = gpio156 función `gpio`, `output-low`, `bias-pull-down`, 2 mA | MEDIDO | idem + `build/android/dt-full-uke-android/base/soc/pinctrl@f000000/bt_en_sleep/*` (idéntico al vivo) |
| D3 | Lo que el nodo NO tiene | sin `clocks`, sin `qcom,bt-debug-gpio`, sin `qcom,xo-clk-gpio`, sin `qcom,bt-vdd-asd` | MEDIDO | `coldboot-20261017/dmesg-30s.txt:3560-3566` (el `btpower` de Android lo dice al parsear) |
| D4 | UART del BT | `/soc/qcom,qupv3_1_geni_se@8c0000/qcom,qup_uart@888000` (SE2 de QUP1, alias `hsuart0`): `compatible="qcom,msm-geni-serial-hs"`, **`status="disabled"`** (en Android `ok`), `reg=<0x888000 0x4000>`, `clocks=<gcc 0x5a>` con `clock-names="se-clk"`, 3 `interconnects` (`qup-core/config/memory`), `interrupts-extended=<gic SPI 0x248 lvl-high>,<tlmm 43 lvl-high>`, `qcom,wakeup-byte=0xfd`, `pinctrl-names=default,active,sleep,shutdown` (default=GPIO en reposo, **active=función UART**) | MEDIDO | `/proc/device-tree/soc/qcom,qupv3_1_geni_se@8c0000/qcom,qup_uart@888000/*`; Android: `dt-full-uke-android/base/...` (status `ok`) |
| D5 | Por qué está `disabled` | `uke_scope_qup_buses()` apaga todo hijo de QUP1/QUP0 salvo `i2c@890000`, `ktz8866@11`, `i2c@a80000`, `spi@a90000`; comentario: "other OEM serial engines retain five-cell vendor DMA routes" | MEDIDO | `R/build/kernel-pokes/senemos-build/source/arch/arm64/kernel/uke-abl.c:314-345` |
| D6 | Wrapper QUP1 | `8c0000.qcom,qupv3_1_geni_se` ligado a `geni_se_qup`; su hijo `890000.i2c` (backlight secundario) ligado. Un `status` disabled→okay en caliente crea el platform device del hijo si el wrapper es bus poblado | MEDIDO (sysfs) / INFERIDO (creación al vuelo) | `readlink .../8c0000.../driver`; `drivers/of/platform.c:727-760` |
| D7 | Pines UART | gpio40 `in high func0 2mA pull down`, 41 `in low … pull down`, 42 `out high … pull up`, 43 `in low … pull down`; los cuatro `UNCLAIMED` | MEDIDO | `/sys/kernel/debug/gpio` (sección gpiochip6); `pinctrl/f000000.pinctrl/pinmux-pins` |
| D8 | GPIO 156 (BT_EN) | `egpio` (estado POR sin reclamar; 38 pines están así); `UNCLAIMED`. Al pedir el GPIO el driver msm marca la propiedad APPS del pin | MEDIDO (estado) / INFERIDO (reclamo) | debugfs gpio; `drivers/pinctrl/qcom/pinctrl-msm.c:232-240,695-704` |
| D9 | GPIO 80 (SW_CTRL) | `in low func0 2mA pull down`, `UNCLAIMED` | MEDIDO | debugfs gpio / pinmux-pins |
| D10 | GPIO 35 (WLAN_EN, "wl-reset") | `out high func0 10mA no pull`, **`UNCLAIMED` en Linux**: nadie en el kernel lo gestiona; lo mantiene alto otro agente (ABL/firmware) con el WiFi asociado | MEDIDO (estado) / INFERIDO (quién) | idem |
| D11 | Pines protegidos | `gpio-reserved-ranges = <8 4>, <56 5>`; 35, 40–43, 80 y 156 **no** están reservados | MEDIDO | `/proc/device-tree/soc/pinctrl@f000000/gpio-reserved-ranges` |

Reguladores (vendor → regulador vivo → supply de `hci_qca`). WiFi consume 3 de los 5 rails:

| Supply vendor | Regulador (phandle) | Estado vivo | Usuarios hoy | Ventana DT | Supply mainline | Tipo |
|---|---|---|---|---|---|---|
| `bt-vdd-io` | `pmxr2230_l7` (0x1e0) | enabled 1,800 V | 2 | 1,8 V fijo | `vddio` | MEDIDO |
| `bt-vdd-aon/dig/rfacmn/rfa-0p8` | `pmxr2230_s3` (0x348) | enabled 0,984 V | 1 (ath11k `vdd-cx-mx`) | 0,968–1,040 V | `vddaon`, `vddbtcxmx`, `vddrfacmn`, `vddrfa0p8` | MEDIDO |
| `bt-vdd-rfa1` | `pmxr2230_s1` (0x346) | enabled 1,856 V | 1 (ath11k `vdd-1.8-xo`) | 1,856–2,040 V | `vddrfa1p7` | MEDIDO |
| `bt-vdd-rfa2` | `pmxr2230_s2` (0x347) | enabled 1,256 V (modo standby) | 1 (ath11k `vdd-1.3-rfa`) | 1,256 V fijo (min=max); `supported-modes=<1 4>`, `mode-threshold-currents=<0 200000>`, `init-mode=1` | `vddrfa1p2` | MEDIDO |
| `bt-vdd-ipa-2p2` | `pmr735a_s3` (0x345) | **NO registrado** (`rpmh-regulator-smpe3` sin driver) | — | 1,6–2,4 V (`init` 1,6 V) | `vddrfa2p2` | MEDIDO |
| (no hay) | — | — | — | — | `vddasd` → dummy | MEDIDO |

Fuentes: `/sys/class/regulator/regulator.{15,16,17,21}/{name,state,microvolts,num_users}`; DT vivo del `qcom,wcn6750` (`vdd-cx-mx-supply=0x348`, `vdd-1.8-xo=0x346`, `vdd-1.3-rfa=0x347`);
`ls /sys/bus/platform/devices/17a00000.rsc:drv@2:rpmh-regulator-smpe3` → sin `driver`; lista de enlazados: solo `cxlvl lcxlvl ldob2/4/5/7/8/12/17 ldod1/3 lmxlvl mmcxlvl mxclvl mxlvl smpb1/2/3`.
En Android (BT apagado) `pmr735a_s3` figura con 0 usuarios: `sistema-20261017/regulators.txt:156`.

### 2.2 Kernel senemos ouke3

| Dato | Valor | Tipo | Fuente |
|---|---|---|---|
| Config BT | `BT=m`, `BT_BREDR=y`, `BT_HIDP=m`, `BT_QCA=m`, `BT_HCIUART=m`, `HCIUART_SERDEV=y`, `HCIUART_QCA=y` (+`H4/LL/BCM/MRVL`), `SERIAL_QCOM_GENI=y` (8 puertos), `SERIAL_DEV_BUS=y`, `SERIAL_DEV_CTRL_TTYPORT=y`, `POWER_SEQUENCING_QCOM_WCN=m`, `RFKILL=m`, `OF_OVERLAY=y`, `OF_DYNAMIC=y`, `OF_RESOLVE=y`, `CONFIGFS_FS=y`; **sin `OF_CONFIGFS`** (`/sys/kernel/config` solo tiene `cs-syscfg pci_ep stp-policy usb_gadget`) | MEDIDO | `build/kernel-pokes/senemos-build/config-senemos-ouke3` (ouke2 == ouke3 en BT); `ls /sys/kernel/config` |
| Huecos para un BlueZ completo | `# BT_LE`, `# BT_RFCOMM`, `# BT_BNEP`, `# UHID`, `# CRYPTO_USER_API_HASH/SKCIPHER/AEAD` (solo `USER_API` y `RNG`) | MEDIDO | config ouke3 líneas 1623-1626, 6239, 9269-9274. Efecto práctico: A2DP/BR-EDR no los necesita (INFERIDO); sin LE no hay teclados/ratones BLE, sin RFCOMM no hay HFP/HSP (mic de auriculares), sin AF_ALG-hash `bluetoothd` pierde el hash de GATT (INFERIDO) |
| Módulos instalados | `bluetooth.ko`, `btbcm`, `btqca`, `hci_uart`, `hidp`, `rfkill`, `ecc`, `ecdh_generic`, `kpp`, `pwrseq-qcom-wcn` en `/lib/modules/…ouke3/`; `modprobe --show-depends hci_uart` cierra con `rfkill kpp ecc ecdh_generic bluetooth btbcm btqca hci_uart`; vermagic = `7.2.9-senemos.1.4054.3-ouke3 SMP preempt mod_unload aarch64` | MEDIDO | `modprobe --show-depends`, `modinfo -F vermagic` |
| Estado de carga | ningún módulo BT cargado (solo `rfkill`, con 3 usuarios por cfg80211); no existe `/sys/class/bluetooth`; `rfkill0`=`phy0 wlan` | MEDIDO | `lsmod`, `ls`, `/sys/class/rfkill/rfkill0/*` |
| Guarda | `uke-senemos-guard.conf` de la tablet == repo (sha `d28fa89d…`), con `blacklist hci_uart` | MEDIDO | `sha256sum` a ambos lados |
| **Por qué existe esa línea** | el modalias del nodo vendor `soc:bt_wcn6750` es `of:Nbt_wcn6750T(null)Cqcom,wcn6750-bt` y `modprobe -R` lo resuelve a **`hci_uart`**: sin la guarda, udev lo autocargaría en cada arranque | MEDIDO | `cat /sys/bus/platform/devices/soc:bt_wcn6750/modalias`; `modprobe -R` |
| `hci_uart` sin DT | solo registra ldisc/protocolos y el driver serdev; **no tiene platform driver** (no puede ligarse al nodo vendor) | MEDIDO | `grep platform_driver hci_qca.c hci_ldisc.c hci_serdev.c` (vacío); `hci_ldisc.c:890` |
| `pwrseq-qcom-wcn` | presente (`=m`) pero **sin uso**: no hay nodo `qcom,wcn6750-pmu`; `ath11k_ahb` no usa pwrseq: sus parches 0014-0016 encienden `vdd-cx-mx → vdd-1.8-xo → vdd-1.3-rfa` y luego `rproc_boot(wpss)` | MEDIDO | `senemos-adaptation/patches/0016-uke-wlan-ordered-rails.patch`; `uke-wifi-up.sh:1-30` |
| Allowlist de rails | `rpmh_regulator_probe` devuelve `-ENODEV` para todo recurso fuera de la lista (cx/mx/lcx/lmx/mxc/mmcx.lvl, ldob2/4/5/7/8/12/17, smpb1/2/3, ldod1/3). `smpe*`/`ldoe*` no están | MEDIDO | `drivers/regulator/qcom-rpmh-regulator-uke.c:1995-2013` |
| Cmdline | `fw_devlink.strict=1`, `clk_ignore_unused`, `console=tty0`, `console=ttyGS0,115200` | MEDIDO | `/proc/cmdline` |

`hci_qca.c` (7.2.9, MEDIDO en `R/build/kernel-pokes/senemos-build/source/drivers/bluetooth/`):
- `qca_soc_data_wcn6750` (`:2175-2190`): 9 supplies `vddio vddaon vddbtcxmx vddrfacmn vddrfa0p8 vddrfa1p7 vddrfa1p2 vddrfa2p2 vddasd`, caps wideband speech + LE states.
- Con `enable-gpios` en el DT → camino "legacy": bulk_get de los 9, `enable` (OUT_LOW **ya en el probe**) y `swctrl` (IN) (`:2457-2517`). **Sin** `enable-gpios` → busca pwrseq (no hay) y deja `power_ctrl_enabled=false`: el driver no enciende nada.
- Encendido (`:1769-1841`): `regulator_bulk_enable` → BT_EN 0 → 50 ms → 1 → 50 ms → init 115200 → descarga de firmware → velocidad operativa 3 Mbaud (por defecto del proto, `:2096-2097`; `max-speed` es opcional). Apagado (`:2281-2290`): BT_EN=0 → 100 ms → bulk_disable.
- No consulta `wl-reset` (35) ni el wake MPM (80) como hacía `btpower.ko` (RE-BT §1).
- `vddasd` ausente **no bloquea**: sin la propiedad el core entrega un regulador dummy con aviso (`drivers/regulator/core.c:131-134,2440-2458`; `have_full_constraints()` es cierto con DT). Corrige a RE-BT-WCN6750 §3, que lo daba como bloqueo y proponía un fixed de 0,95 V inventado.
- Patrón upstream equivalente en el propio árbol: `arch/arm64/boot/dts/qcom/sm7325-nothing-spacewar.dts:1384-1406` (WCN6750 con `enable-gpios`, `swctrl-gpios`, `pinctrl-0` de BT_EN, 9 supplies, `max-speed`, `qcom,local-bd-address-broken`).

### 2.3 Firmware

| Dato | Valor | Tipo | Fuente |
|---|---|---|---|
| Lo que pide mainline | `qca/msbtfw%02x.mbn` (ELF; si falla, `.tlv`) y `qca/msnv%02x.bin`, con `rom_ver` leído del chip | MEDIDO | `drivers/bluetooth/btqca.c:828-834, 858-863, 929-931` |
| Rootfs de la tablet | `/lib/firmware/qca/` trae `msbtfw11.mbn` (202 508 B), `msbtfw11.tlv`, `msnv11.{bin,b09,b0a}` y otros chips; **no hay `msbtfw12`/`msnv12`**. Los shas `msbtfw11.mbn 2c450354…`, `msnv11.bin e213c462…` están en `build/gates/SHA-BUENOS.txt:183-186` | MEDIDO | `ls /lib/firmware/qca` |
| Copia de trabajo (repo) | `build/android/msbtfw12.mbn` 109 248 B sha256 `3efbd7fa985702982ba3f2fb4e4e37dab2de51b26fa5574d6165f1cd4ec5506d`; `build/android/msnv12.bin` 6 206 B `52553c8a4041d4c564e55046c010609198fb3636a21d5a87a8e2df55023c0476`; `build/android/msbtfw12.ver` = `BTFW.MOSELLE.1.2.0-00268.2-PATCHZ-1.76686.25`. Shas recalculados hoy: coinciden | MEDIDO | `sha256sum` |
| Fuente primaria | particiones `bluetooth_a` → `/dev/sde7` y `bluetooth_b` → `/dev/sde35`, 4 MiB `vfat` cada una; Android montó `bluetooth_b` en `/vendor/bt_firmware` (los ficheros se extrajeron de `/vendor/bt_firmware/image`) | MEDIDO | `ls /dev/disk/by-partlabel`, `lsblk`; `coldboot-20261017/dmesg-30s.txt:4095`; `docs/historia/revision/PERIF-BT-20261017.md §3` |
| **No están en el backup de particiones** | `build/backup-par-bueno/android-20261017/` (19 particiones) no incluye `bluetooth_*`; la única copia local son los 3 ficheros de arriba | MEDIDO | `ls`, `particiones.txt` |
| ROM del chip | 1.2, **deducido del nombre del fichero del vendor**; la versión real no se ha medido (el BT nunca se encendió en las capturas) | INFERIDO | — |
| NVM | `msnv12.bin`: TLV, tag `BD_ADDR` = ceros (placeholder); el resto, calibración RF opaca. Aceptación por `qca_tlv_check_data`: RE-BT lo dejó "resuelto a favor" en VERIFICACION-W2; la última palabra la dará `dmesg` | INFERIDO | `RE-BT-WCN6750.md` errata |
| Dirección BD | partición `persist` (`sdf7`): `/bluetooth/.bt_nv.bin` = 6 bytes, no nulos, últimos dos `e5 37` = coincide con el `address: XX:XX:XX:XX:E5:37` de `bt.txt:4` | MEDIDO (existe y casa en el sufijo) / INFERIDO (que sea la BD addr) | `debugfs -R "cat /bluetooth/.bt_nv.bin" persist.img` (sin imprimir el valor) |
| Necesidad de `local-bd-address` | con la dirección a ceros del NVM el core de BT dejaría el controlador sin configurar o con dirección aleatoria; hay que darla por DT (`local-bd-address`, 6 bytes little-endian) o con `btmgmt public-addr` | INFERIDO | semántica de `HCI_QUIRK_USE_BDADDR_PROPERTY`; el spacewar de arriba usa `qcom,local-bd-address-broken` porque su ABL la pasa |

No se redistribuye nada: solo se localiza y se cita el sha. Decidir la dirección BD (reutilizar la de Android o generar una nueva) es del dueño (§7).

### 2.4 Userspace

| Dato | Valor | Tipo | Fuente |
|---|---|---|---|
| BlueZ | solo `bluez-libs 5.87-2`; **faltan `bluez`, `bluez-utils` y `bluetui`**; `bluetooth.service` = not-found. Disponibles en `extra`: `bluez 5.87-2` (600 KiB), `bluez-utils 5.87-2` (948 KiB), `bluetui 0.8.1-2` (1006 KiB) | MEDIDO | `pacman -Q`, `pacman -Si` (BD local) |
| Audio | `pipewire 1.6.9`, `wireplumber 0.5.18`, `pipewire-audio` con `/usr/lib/spa-0.2/bluez5/` (`libspa-bluez5.so` + códecs sbc/aac/aptx/lc3/msbc…); `rfkill` instalado | MEDIDO | `ls /usr/lib/spa-0.2/bluez5`; `pacman -Qo` |
| Espacio | `/` 7,9 GiB, 3,5 GiB libres | MEDIDO | `df -h /` |
| Rootfs sin journal | corrupciones silenciosas ya vistas en ficheros de firmware (`adsp.b40`, `wpss.b08`); ritual del proyecto: `sha256sum /lib/firmware/adsp.b40` = `42c86837…` al abrir y cerrar | MEDIDO (histórico) | `docs/historia/ESTADO-VIVO.md:141-152`; `deploy/wifi/deploy.sh` |

### 2.5 Lo que dicen las capturas de Android

- **`build/android/perif-20261017/bt.txt`**: `enabled: false`, `state: OFF`, **"Bluetooth never enabled!"**, "crashed 0 times", `address: XX:XX:XX:XX:E5:37` (enmascarada); luego un volcado de flags de la pila (sin interés) y, al final, el `rfkill` (`bt_power`, `phy0`, `0`, `1`; RE-BT §4 lo lee como `bt_power` soft-blocked y `phy0` libre: INFERIDO). **No hay ninguna traza de encendido del BT**: solo estructura. (MEDIDO)
- **`coldboot-20261017/dmesg-30s.txt`** (arranque en frío del vendor, 17-oct 12:38): 
  - 2,064–2,113 s: carga `bluetooth.ko`, `btbcm`, `btqca`, `btsdio`, `hci_uart` (protocolos H4, LL, Broadcom, **QCA**), `rfcomm`, `hidp`: todo software (`:2768-2932`).
  - 2,3227–2,328 s: `msm_geni_serial 888000.qcom,qup_uart: Wakeup byte 0xfd`, `gsi_mode:0`, `Serial port0 added. FifoSize 64`, **`ttyHS0 at MMIO 0x888000 (irq = 205)`**: la SE2 de QUP1 ya viene como UART con su firmware cargado y en modo FIFO (sin DMA) (`:3105-3127`). (MEDIDO; "el firmware lo carga el arranque, no el SO" es INFERIDO)
  - 2,7727 s `bt_power_probe`: 9 vregs (`io 1,8 V`, `aon/rfacmn/dig/rfa-0p8 968–1040 mV`, `rfa1 1856–2040 mV`, `rfa2 1256–1408 mV`, `asd` ausente, `ipa-2p2 1600–2400 mV`), sin clk, sin debug/xo-gpio; `btpower_aop_mbox_init: failed to get mbox channel` y `Secure HW feature not supported` (smcinvoke): ruido vendor, no aplica (`:3544-3573`).
  - 3,379 s `btfm_slim_probe`/`btpower_register_slimdev`: SLIMbus del offload de audio, no HCI (`:4236-4240`).
  - 5,73 s arranca el HAL `vendor.bluetooth-1-1-qti` (`:6713`); `logcat-30s.txt` (104 682 líneas) no tiene bring-up de BT: 0 coincidencias de `ttyHS0`, `btpower`, `msbtfw`, `msnv`, `libbt`, `bt_vendor`, `hci_hal`; solo `BluetoothAdapter: isLeEnabled(): OFF` y mensajes de VINTF/PAL.
- **Lo que las capturas NO aportan**: baudios reales, duración del pulso de BT_EN, versión de ROM, tensión real del rail de 2,2 V, ni un `regulator_summary` con el BT encendido. El flujo del `btpower.ko` (reguladores → BT_EN=0 50 ms → wake MPM(80) → si WLAN off espera 100 ms → BT_EN=1 50 ms; apagado inverso con 100 ms) viene del reverso en `RE-NOCTURNO-20261017/RE-BT-WCN6750.md §1`, no de una captura.
- `vendor-harvest-20261017b/lsmod.txt:350,369`: en Android `hci_uart btqca btbcm bluetooth rfcomm hidp btsdio` y `btpower` (rfkill: 4 usuarios) estaban cargados con el BT apagado. (MEDIDO)

## 3. Convivencia con el WiFi (uke-wifi.service, WPSS + ath11k_ahb)

Línea base del WiFi para no culpar al BT de nada: `wlan0` 192.0.2.12/24, `wpa_state=COMPLETED`, 5180 MHz; `ath11k` ya trae 3 líneas de error en `dmesg` (`Failed to set the requested Country regulatory setting`, `failed to process regulatory info -22`, a los 20,9 s) — anteriores a cualquier BT (MEDIDO).

| Recurso | Estado con WiFi | Qué haría el BT | Efecto | Veredicto |
|---|---|---|---|---|
| Rails `s1`/`s2`/`s3` | enabled por ath11k (1 usuario cada uno) | `regulator_bulk_enable` suma 1 usuario; hci_qca no hace `set_voltage`, solo `set_load` (`hci_qca.c:2368-2396`) | `s1`/`s3`: refcount puro (sin `supported-modes` → `set_load=NULL`, `qcom-rpmh-regulator-uke.c:1841-1851`). **`s2`: cambia de modo**: BT declara 257 mA (`vddrfa1p2`) y su umbral es 200 mA (`mode-threshold-currents=<0 200000>`), así que pasa de `standby` a `fast` mientras el BT esté encendido | `s1`/`s3` sin riesgo. `s2`: transición de modo de un rail RF compartido **con el WiFi activo**; Android lo tenía en `fast` (`sistema-20261017/regulators.txt:162`) con el WiFi funcionando, así que el estado destino es conocido-bueno; la transición en caliente no está medida (INFERIDO). Vigilarla en B4 (WiFi `COMPLETED`, ping, `dmesg` de ath11k) |
| `l7` (1,8 V) | 2 usuarios (WCD939x, USB-C) | +1 | idem | sin riesgo |
| `pmr735a_s3` (2,2 V PA) | no existe | rail nuevo, **solo BT** | si se registra (kernel v4) es un voto RPMh nuevo a un SMPS no usado hoy | variante B lo omite; A exige flash |
| Orden de rails | `0016` fija el orden OEM `cx/mx → xo → rfa` para WLAN | con WiFi arriba: nada que ordenar. Con WiFi apagado: el BT enciende `s1/s2/s3` con `bulk` paralelo (sin el orden OEM de WLAN) | escenario no medido; sin riesgo conocido | arrancar el BT **después** de `uke-wifi.service` |
| BT_EN (156) y SW_CTRL (80) | libres (`UNCLAIMED`) | los reclama `hci_qca` | WiFi no los usa en senemos. **En el stack viejo (L16) sí**: el `pwrseq` del WiFi pedía el 156 y su modo `egpio` difería ath11k (`NOTAS-OMARCHY.md:1872`); aquí `ath11k_ahb` no usa pwrseq | el BT no puede romper el WiFi por esa vía |
| WLAN_EN (35) | `out high`, fuera de Linux | `hci_qca` no lo mira (el `btpower` sí esperaba 100 ms si estaba bajo) | si algún día se apaga WiFi bajando el 35, el BT no se enteraría; hoy nadie lo baja | vigilar en B6b |
| UART | no usada | SE2 de QUP1 | QUP1 comparte wrapper (ICC `qup-core`, AHB) con el KTZ secundario `i2c@890000` | único acoplamiento real: **backlight**, no WiFi |
| Firmware y transporte | WPSS (`qca6750/wpss.*`, `ath11k/WCN6750/hw1.0/board.bin`) por QMI/ath11k | `qca/msbtfw12.mbn` + `msnv12.bin` por UART HCI | independientes; el BT no pasa por icnss/QMI/WPSS (en Android `bt_power` solo toca regs+GPIO y el HAL abre `ttyHS0`) | sin riesgo |
| DMA / SMMU | WPSS `iommus 0x1400 mask 1` | UART en FIFO (`gsi_mode:0`, sin `dmas` en el nodo) | independientes | sin riesgo |
| rfkill | `phy0` | `hci0` | independientes | — |
| Coexistencia RF | WiFi en 5 GHz (no pisa los 2,4 GHz del BT) | — | la coex WLAN-FW↔BT-FW del chip no se ha auditado | INFERIDO que va dentro del chip; probar en B6 con streaming A2DP mientras se mide el WiFi |

Apagado cruzado (escenarios para B6b, no medidos): BT off con WiFi on → los rails no caen (refcount). WiFi off (`uke-wifi-up.sh --down`: `rproc_shutdown` + liberar rails de ath11k) con BT on → `s1/s2/s3` los sostiene el BT y el WPSS queda parado; el `btpower` de Android tenía una rama "WLAN OFF" para esto, mainline no.

## 4. Qué bloquea hoy (y cuál es el remedio mínimo)

| # | Bloqueo | Evidencia | Remedio | ¿Flash? |
|---|---|---|---|---|
| 1 | UART disabled + compat vendor + sin serdev | D4, D5 | overlay (App. A) | no (módulo cargador) |
| 2 | Sin mecanismo para aplicar overlays en caliente | config sin `OF_CONFIGFS` | módulo con `of_overlay_fdt_apply()/of_overlay_remove()` (ambas `EXPORT_SYMBOL_GPL`, `drivers/of/overlay.c:1090,1275`). La sesión de audio planea el mismo cargador (E0-f): **reutilizarlo con otro dtbo, no escribir dos** | no |
| 3 | Rail `pmr735a_s3` sin registrar | allowlist | omitir `vddrfa2p2-supply` (dummy) en la etapa en vivo; añadir `smpe3` en v4 | solo para el rail real |
| 4 | Firmware rev 12 ausente del rootfs | §2.3 | B1 | no |
| 5 | Sin dirección BD | §2.3 | decisión del dueño; `local-bd-address` generado al desplegar (no se versiona) | no |
| 6 | Sin `bluez`/`bluez-utils` | §2.4 | B1 (pacman) | no |
| 7 | Kernel sin LE/RFCOMM/BNEP/UHID/AF_ALG | §2.2 | v4 (junto con el rail y con cualquier otro flash que haya) | sí, no urgente |

**Nota sobre `fw_devlink.strict=1`**: con `vddrfa2p2-supply=<&pmr735a_s3>` y un proveedor que nunca liga, el probe del serdev se quedaría diferido (INFERIDO; el nodo vendor `soc:bt_wcn6750` tampoco tiene enlace a `smpe3`). Otra razón para la variante B hasta tener el kernel v4.

## 5. Plan por etapas

Principios: una etapa = un cambio; cada paso en vivo con (a) lector ACM único armado, (b) `dmesg -n 7`, (c) `sync` antes de lo que pueda colgar, (d) doble captura (ACM + `ssh … 'dmesg -w' > fichero`), (e) línea base de WiFi antes y después (`wpa_cli status`, ping a la puerta de enlace, `dmesg | grep -c ath11k`), (f) techo de 3 ciclos por hipótesis. **Toda etapa que cargue módulos o toque hardware necesita orden del dueño (B2 en adelante).** No solapar con etapas de la sesión de audio que toquen la SoC (E2 en adelante) ni con E7 (mismo wrapper QUP1).

| Etapa | Qué | Toca la tablet | Riesgo | Puede colgar el WiFi |
|---|---|---|---|---|
| **B0** | PC: overlay definitivo (variantes `UART_ONLY`, B, A), cargador, deploy y tests | no | nulo | no |
| **B1** | Ficheros inertes: firmware rev 12 + `bluez` | sí (ficheros, sin cargar nada) | muy bajo | no |
| B2 | `modprobe bluetooth btqca btbcm hci_uart` sin DT | sí (módulos, sin hardware) | muy bajo | no |
| B3 | Overlay solo de la UART (SE2 de QUP1) | sí (QUP1) | bajo–medio | no; sí podría tocar el backlight secundario |
| B4 | Overlay completo, variante B (sin rail PA) + `hci_uart` → primer encendido del chip | sí (rails ya on, BT_EN, UART) | medio | improbable: rails aditivos; el único efecto sobre un rail del WiFi es el cambio de modo de `s2` (§3) |
| B5 | Kernel v4: rail `smpe3`, `BT_LE`, RFCOMM, BNEP, UHID, AF_ALG | **flash** | medio–alto | indirecto (cualquier flash) |
| B6 | `bluetoothd` + A2DP + soak + escenarios cruzados (B6b) | sí | bajo | a medir |
| B7 | Persistencia: `uke-bt.service` con guarda | sí | bajo (con guarda) | no (After=WiFi) |

### B0 — preparación en el PC (primer paso; riesgo nulo, ni abre ssh)
- Hecho en esta fase: overlay borrador (App. A) que compila con `dtc -@` sin avisos y se aplica con `fdtoverlay` sobre `build/kernel-pokes/senemos-7.2.9/dt/res-live-final.dtb` (sha `61e48829…`, la base que usa el audio); las tres variantes comprobadas; phandles (`0x348 0x346 0x347 0x1e0 0x345`) = los del DT vivo.
- Falta: (1) cargador (~40 líneas) con el dtbo embebido, `of_overlay_fdt_apply` en `init` y `of_overlay_remove` en `exit`; se compila contra `senemos-build` (tiene `Module.symvers`), y se comprueba `vermagic == …ouke3` y `modinfo`; (2) `deploy.sh` estilo `deploy/wifi` (`--check` de solo lectura, `--go`, shas, manifiesto), en `build/rootfs/deploy/bt/` (carpeta nueva; no la del audio); (3) añadir `bt` a `KNOWN` en `uke-bootguard`; (4) tests locales de la guarda y del script.
- Hecho cuando: `deploy.sh` sin `--go` verifica todo y `fdtoverlay` acepta las 3 variantes. Rollback: no hay nada que deshacer.

### B1 — staging inerte en la tablet (orden del dueño: escribir ficheros)
- `tar | ssh` (el rootfs no tiene sftp) de `msbtfw12.mbn` y `msnv12.bin` a `/lib/firmware/qca/`; `sha256sum` a ambos lados contra §2.3; `sync`. `pacman -S --needed bluez bluez-utils bluetui`. **No** habilitar `bluetooth.service`. Ritual: `sha256sum /lib/firmware/adsp.b40` (= `42c86837…`) antes y después, y el manifiesto del WiFi (`uke-wifi-fw.sha256`) intacto.
- Riesgo: los ficheros no los carga nadie; lo único real es una escritura en ext4 sin journal (mitigado con sha + `sync`). WiFi: nulo.
- Hecho cuando: shas verdes, `bluetoothctl --version` ejecuta, WiFi sin cambios. Rollback: `rm` de los 2 ficheros y `pacman -R`.

### B2 — módulos sin hardware (orden del dueño: cargar módulos)
- `modprobe bluetooth btqca btbcm hci_uart` **por nombre** (la blacklist se queda; solo frena el autoload). Sin DT no hay serdev: no se toca ningún pin ni rail.
- Éxito: `lsmod` los muestra; `/sys/class/bluetooth` sigue ausente; `rfkill` solo `phy0`; `dmesg` solo trae las líneas de registro de protocolos (como en Android 2,07–2,11 s); ping/`wpa_state` iguales 5 min. Abortar: cualquier línea nueva de `ath11k`/WPSS.
- Rollback: `modprobe -r hci_uart btqca btbcm bluetooth`. Riesgo: muy bajo.

### B3 — la UART sola (overlay `UART_ONLY`)
- Cargar el cargador con el dtbo de solo-UART (sin nodo `bluetooth`, sin GPIO ni rails): `compatible=qcom,geni-uart`, `clock-names=se`, pinctrl `default`=función UART / `sleep`=GPIO (intercambiado respecto al vendor), `status=okay`, wake en flanco de bajada.
- Qué demuestra: que `qcom_geni_serial` liga la SE2 (protocolo UART, reloj `gcc 0x5a`, ICC, pines 40–43) sin que haya chip al otro lado. Éxito: probe sin errores; el backlight (incl. el KTZ secundario) sin cambios; WiFi igual; BT_EN no se toca (`gpio156` sigue `egpio`).
- Riesgos concretos (INFERIDOS): (a) la SE no está cargada como UART → `-ENXIO`, inofensivo (el vendor la usaba como UART en FIFO, así que debería estarlo); (b) acceso con reloj apagado → abort síncrono (improbable: el driver enciende el reloj antes de leer); (c) votos ICC del `qup-core` compartido con el KTZ.
- Rollback: `rmmod` del cargador (`of_overlay_remove`) → el nodo vuelve a `disabled`. Riesgo: bajo–medio. Abortar a la primera aparición de `Unhandled fault`/cuelgue (reset físico; cuesta un reintento de slot).

### B4 — primer encendido del chip (variante B, sin rail PA)
- Cargar el cargador con el dtbo completo (variante B) y luego `modprobe hci_uart`. **Ojo**: el probe del serdev pide `enable-gpios` con `OUT_LOW` y el registro del `hdev` dispara el setup (INFERIDO), así que el encendido ocurre ya al cargar `hci_uart`; sin `bluetoothd` el core lo apaga solo a los ~2 s (auto-off, INFERIDO). Para observarlo con calma: `btmgmt -i hci0 power on` (de `bluez-utils`; no necesita `bluetoothd`).
- Qué sube y baja: 5 supplies ya encendidos (+1 usuario cada uno; `s2` pasa de `standby` a `fast` por el `set_load`, §3), BT_EN 0→50 ms→1→50 ms, UART a 115 200 (init) → firmware → 3 Mbaud; `vddasd`/`vddrfa2p2` dummy (avisos esperados `supply … not found, using dummy regulator`).
- Éxito en `dmesg`: `hci0: setting up wcn6750`, `QCA controller version 0x…` (**anotar `rom_ver`**: debe ser 12 → `msbtfw12`/`msnv12`), `QCA Downloading qca/msbtfw12.mbn`, `QCA Downloading qca/msnv12.bin`, `QCA setup on UART is completed`; `btmgmt info` con dirección; `opmode` de `regulator.16` (`s2`) antes/después; WiFi `COMPLETED` y ping iguales; soak 10 min con `hci0` arriba.
- Fallos esperables → diagnóstico: `-ENOENT` de firmware (el `rom_ver` real es otro: copiar la rev correcta desde la partición `bluetooth_*`); timeout de setup (UART/BT_EN: medir con `/sys/kernel/debug/gpio` solo una vez, ver §0); `-EPROBE_DEFER` (hay un `&pmr735a_s3` en el overlay: usar B); dirección BD a ceros (añadir `local-bd-address`).
- Rollback: `modprobe -r hci_uart` (BT_EN=0 → 100 ms → rails; los de WiFi se quedan por refcount) y `rmmod` del cargador. Riesgo: medio (primer toque al chip; cuelgue → reset físico).

### B5 — kernel v4 (solo con orden del dueño; mejor combinado con otro flash)
- Añadir `smpe3` a la allowlist de `qcom-rpmh-regulator-uke.c:1995-2013` (comprobar antes que `cmd_db_read_addr("smpe3")` existe) y `vddrfa2p2-supply` al overlay (variante A); config: `BT_LE=y`, `BT_RFCOMM=m`, `BT_BNEP=m`, `UHID=m`, `CRYPTO_USER_API_HASH/SKCIPHER/AEAD=m`.
- Procedimiento: el del proyecto (ledger pre-registrado; el gate `fdtoverlay` es para la partición `dtbo` y aquí solo se flashea `boot_a`; sha de lectura al tamaño exacto; batería ≥3700 mV; ≤2 escrituras/día; par bueno a mano). Riesgo: medio–alto (flash). **Solo si B4 muestra problemas de alcance/TX o el firmware lo exige**; en Android el rail de 2,2 V se votaba al encender el BT.

### B6 — BlueZ + A2DP + convivencia
- `bluetoothd`, emparejar unos auriculares, perfil A2DP por PipeWire/WirePlumber (SBC/AAC), soak 30 min con el WiFi cargado (ping continuo y `iperf` a 5 GHz), mirar `dmesg` de ath11k. Sin RFCOMM no habrá HFP/mic hasta B5 (esperado).
- B6b (escenarios cruzados, uno por vez, con orden): WiFi apagado con BT encendido y al revés. Riesgo: bajo; son los únicos puntos donde el refcount de rails se ejercita al revés.
- Es además la salida de audio realista mientras el ADSP se trabaja aparte (la tarjeta de audio no depende del BT).

### B7 — persistencia
- Un `uke-bt.service` (oneshot, `After=uke-wifi.service`, `ConditionPathExists=!/etc/uke/no-bt` y `!/etc/uke/safe-mode`, `ExecCondition=uke-bootguard begin bt`, `ExecStartPost=uke-bootguard ok bt`) que: carga el cargador (en `/lib/modules/…ouke3/extra/` + `depmod`), hace `modprobe hci_uart` por nombre y deja `bluetooth.service` normal. **La blacklist de `hci_uart` se queda** (patrón del ath11k): es la que impide que udev cargue `hci_uart` (y con él encienda el chip) fuera del orden y de la guarda del servicio.
- `local-bd-address` se genera al desplegar (no se versiona). Riesgo: bucle de arranque, cubierto por la guarda (2 fallos seguidos → se omite solo).

## 6. Gates operativos comunes
Batería ≥3700 mV solo cuenta para flash (B5); en B1–B4/B6/B7 basta con carga activa (`Charging`). Vigilar `slot-retry-count` (antes del flash de v3 eran a=7/b=6, `docs/historia/ESTADO-VIVO.md`; no se ha vuelto a medir): un cuelgue = reset físico = un reintento. `blacklist` y `uke-wifi.service` no se tocan en B0–B6. Un solo lector de `/dev/ttyACM0`.

## 7. Decisiones del dueño
1. ¿Autoriza cargar módulos en vivo (B2 en adelante)? B1 solo necesita permiso para escribir ficheros e instalar paquetes.
2. Blacklist de `hci_uart`: **recomiendo mantenerla** y arrancar el BT con servicio propio (B7). Quitarla solo adelanta un `modprobe` que ya hace el servicio, y reabre el autoload sobre el nodo vendor `soc:bt_wcn6750` (D1 y §2.2).
3. Dirección BD: reutilizar la de Android (sale de `persist`) o generar una nueva localmente administrada.
4. Rail PA: empezar sin él (variante B) y decidir B5 según B4, o esperar al próximo flash.
5. Instalar `bluez`, `bluez-utils` y `bluetui` en la tablet (B1) y coordinar el orden con la sesión de audio.
6. Cuándo agrupar el kernel v4 (BT_LE etc.) con otro flash.

## 8. Hipótesis sin verificar y cómo refutarlas

| Hipótesis | Cómo refutarla | Etapa |
|---|---|---|
| El overlay en caliente crea el platform device de la UART y el serdev hijo (todas las entradas del changeset se aplican antes de notificar; el hijo `bluetooth` ya está cuando liga la UART) | `ls /sys/bus/serial/devices` tras B3/B4 (el bus serdev se llama `serial`: `drivers/tty/serdev/core.c:428`); si no aparece, cargar en dos overlays (UART, luego `bluetooth`) | B3/B4 |
| La SE2 de QUP1 viene cargada como UART | `dmesg` del probe de `qcom_geni_serial` (`Invalid FW loaded, proto`) | B3 |
| El registro del `hdev` enciende el chip en el probe y el auto-off lo apaga a los ~2 s | `dmesg` con marcas de tiempo; `btmgmt` | B4 |
| ROM 1.2 (nombre del fichero del vendor) | línea `QCA controller version 0x…` | B4 |
| Sin `vddrfa2p2` el chip arranca y funciona (en Android el rail se votaba al encender) | alcance y TX a 1–3 m con auriculares; si falla, B5 | B4/B6 |
| `msnv12.bin` pasa `qca_tlv_check_data` | `dmesg` (`QCA Downloading qca/msnv12.bin`) | B4 |
| La coexistencia WLAN/BT va dentro del chip | A2DP con tráfico WiFi sostenido; pérdidas de ping | B6 |
| El paso de `s2` de `standby` a `fast` (por el `set_load` de 257 mA del BT) no perturba al WiFi activo | B4 con ping/iperf continuos y `dmesg` de ath11k; si hubiera síntoma, probar el BT con `vddrfa1p2-supply` omitido (dummy) para aislarlo, y comparar con `/sys/class/regulator/regulator.16/opmode` antes/después | B4 |
| Sin LE/RFCOMM/AF_ALG el A2DP BR/EDR funciona | `bluetoothd` arranca y empareja | B6 |

## 9. Correcciones a informes previos
- `RE-NOCTURNO-20261017/RE-BT-WCN6750.md` §3 y `docs/historia/revision/PERIF-BT-20261017.md` §2/§4 suponían el árbol L16 (`uart10`, `&tlmm`, `vreg_*`): en senemos el kernel ve **el DT vendor**, con la UART `disabled` por `uke_scope_qup_buses` y nombres vendor (`qcom,qup_uart@888000`, `pmxr2230_*`, `pmr735a_s3`). Su fragmento no aplica tal cual; el del App. A sí.
- `vddasd` **no** bloquea el probe (dummy, §2.2); el fixed de 0,95 V no debe usarse.
- "BT bloqueado sin `SERIAL_QCOM_GENI=y`" (`NOTAS-OMARCHY.md`): ya es `=y` en ouke3.
- El rail `pmr735a_s3` sí falta, pero por la allowlist del driver de rails, no por el DT (el nodo existe en el DT vivo).

## App. A — overlay borrador (compila y se aplica en el PC; NO probado en la tablet)

Verificado el 18-oct con `cpp` + `dtc -@` (0 avisos) y `fdtoverlay -i res-live-final.dtb`: `uke-bt-uart-only` 1 154 B (`c01aab0c…`), `uke-bt-B` 2 180 B (`007443a3…`), `uke-bt-A` 2 292 B (`2805474a…`). Valores comprobados con `fdtget`: `status=okay`, `compatible=qcom,geni-uart`, `clock-names=se`, `pinctrl-0={0x23f..0x242}` (función UART), `pinctrl-1={0x23b..0x23e}` (GPIO), wake `<tlmm 43>` en flanco de bajada, `enable-gpios=<0x16b 156 0>`, `swctrl-gpios=<0x16b 80 0>`, supplies `0x1e0 0x348 0x346 0x347` (+`0x345` en A). Copia del fuente (`uke-bt.dtso`) y de los tres `.dtbo`, con `SHA256SUMS`, en la carpeta de notas de la sesión (`~/.omarchy-home/.config/Claude/side-session-notes/local_97c1eb5c-d152-4777-892b-bbfda56a0dca/bt-overlay/`, fuera del repo); se versionará en `build/rootfs/deploy/bt/` en B0.

```dts
#include <dt-bindings/gpio/gpio.h>
#include <dt-bindings/interrupt-controller/arm-gic.h>
#include <dt-bindings/interrupt-controller/irq.h>
/dts-v1/;
/plugin/;

/ {
	fragment@0 {
		target-path = "/soc/qcom,qupv3_1_geni_se@8c0000/qcom,qup_uart@888000";

		__overlay__ {
			compatible = "qcom,geni-uart";
			clock-names = "se";
			status = "okay";
			pinctrl-names = "default", "sleep";
			pinctrl-0 = <&qupv3_se10_cts &qupv3_se10_rts &qupv3_se10_tx &qupv3_se10_rx>;
			pinctrl-1 = <&qupv3_se10_default_cts &qupv3_se10_default_rts
				     &qupv3_se10_default_tx &qupv3_se10_default_rx>;
			interrupts-extended = <&intc GIC_SPI 584 IRQ_TYPE_LEVEL_HIGH>,
					      <&tlmm 43 IRQ_TYPE_EDGE_FALLING>;

#ifndef UART_ONLY
			bluetooth {
				compatible = "qcom,wcn6750-bt";
				pinctrl-names = "default";
				pinctrl-0 = <&bt_en_sleep>;
				enable-gpios = <&tlmm 156 GPIO_ACTIVE_HIGH>;
				swctrl-gpios = <&tlmm 80 GPIO_ACTIVE_HIGH>;
				vddio-supply = <&pmxr2230_l7>;
				vddaon-supply = <&pmxr2230_s3>;
				vddbtcxmx-supply = <&pmxr2230_s3>;
				vddrfacmn-supply = <&pmxr2230_s3>;
				vddrfa0p8-supply = <&pmxr2230_s3>;
				vddrfa1p7-supply = <&pmxr2230_s1>;
				vddrfa1p2-supply = <&pmxr2230_s2>;
#ifdef WITH_PA_RAIL	/* variante A: exige kernel v4 (allowlist de rails) */
				vddrfa2p2-supply = <&pmr735a_s3>;
#endif
				/* local-bd-address = [..];  se genera al desplegar, no se versiona */
			};
#endif
		};
	};
};
```

Notas del diseño: las dos propiedades que el overlay *reescribe* (`compatible`, `clock-names`) y la inversión `default`↔`sleep` de pinctrl son lo que hace que el driver mainline acepte un nodo vendor; `pinctrl-2/3`, `qcom,wakeup-byte` y `reg-names` quedan como residuo inocuo (un overlay no puede borrar propiedades). Los labels (`tlmm`, `intc`, `pmxr2230_*`, `pmr735a_s3`, `qupv3_se10_*`, `bt_en_sleep`) existen en el `__symbols__` vivo (1430 entradas; `tlmm`, `pmxr2230_*`, `pmr735a_s3`, `qupv3_se10_*`, `bt_en_sleep` medidos en la tablet; `intc` en la base DTB). SPI 584 y la polaridad de la IRQ principal son los del DT vendor.

## Resultado de B1 (aplicado el 18-oct-2026, ~10:32–10:41 CEST del PC; con orden expresa del dueño)

- **Firmware rev 12 instalado** con `deploy.sh --go --fw`: `/usr/lib/firmware/qca/msbtfw12.mbn` (`3efbd7fa…`) y `msnv12.bin` (`52553c8a…`) + `/usr/lib/firmware/uke-bt-fw.sha256`; sha256 verificado a ambos lados y `uke-bt-fw.sha256: OK` en `--check`. MEDIDO.
- **`bluez 5.87-2`, `bluez-utils 5.87-2` y `bluetui 0.8.1-2` instalados** con `deploy.sh --go --pkgs` (la transacción solo añadía esos 3 paquetes, sin actualizar ninguno ya instalado). `bluetoothctl` y `btmgmt` ejecutan (5.87). `bluetooth.service`: `disabled` / `inactive`. MEDIDO.
- **Antes/después idénticos** en la lectura del script: kernel, `adsp.b40` (`42c86837`), WiFi `COMPLETED` y ping a la puerta de enlace ok, `ath11k_dmesg=42`, manifiesto del WiFi ok, **ningún módulo BT cargado**, sin `/sys/class/bluetooth`. MEDIDO.
- **Incidencias, ninguna del BT**:
  1. A las 01:45 (reloj de la tablet) la tablet **entró en suspensión** (`wiphy_suspend`, `DEAUTH_LEAVING`); al volver, wlan0 quedó sin enlace y con 0 redes en el escaneo (`wpa_state=SCANNING`) hasta que el dueño lo arregló. El WiFi no se recupera solo tras suspender: relevante para la sesión de suspensión y para B6 (BT + suspensión). MEDIDO (journal); causa del fallo tras reanudar: INFERIDO.
  2. `pacman` en la tablet no podía instalar: el kernel no tiene Landlock (`/sys/kernel/security/lsm` = `capability,selinux`) y el keyring de pacman no estaba inicializado. Lo arregló la sesión "Revisión proyecto Omarchy" a petición del dueño: `pacman-key --init`, `--populate archlinuxarm omarchy` y `DisableSandbox` en `/etc/pacman.conf` (copia previa `/etc/pacman.conf.bak.1792312812`). Yo solo ejecuté, antes de eso, dos intentos fallidos sin efecto (`deploy.sh --go --pkgs` y `pacman -S --disable-sandbox`; "no packages were upgraded").
- **Siguiente**: B2 (módulos sin hardware) en adelante, con orden expresa. `deploy.sh --go --module` instala los `.ko` en `extra/` + `depmod` sin cargar nada.

## Resultado de B2 (aplicado el 18-oct-2026, 10:46–10:52 CEST del PC; con orden expresa del dueño)

- **`.ko` instalados** con `deploy.sh --go --module`: `uke_bt_uart`, `uke_bt_b`, `uke_bt_a` en `/usr/lib/modules/7.2.9-senemos.1.4054.3-ouke3/extra/` + `depmod`; **no se cargó ningún `uke_bt_*`**. MEDIDO.
- **Carga**: `dmesg -n 7` y `sync` antes. Mi primera orden, `modprobe bluetooth btqca btbcm hci_uart`, cargó solo `bluetooth` (modprobe toma el resto de argumentos como parámetros del primer módulo; el kernel los ignoró con `bluetooth: unknown parameter 'btqca' ignored`, inocuo). Después `modprobe -a btqca btbcm hci_uart` cargó el resto. MEDIDO.
- **Resultado**: `lsmod` = `hci_uart btbcm btqca bluetooth` (+ `ecdh_generic ecc kpp`); en `dmesg` los mismos mensajes de registro que en el arranque en frío de Android: `Bluetooth: Core ver 2.22`, `HCI UART driver ver 2.3`, protocolos **H4, LL, Broadcom, QCA, Marvell** registrados. Sin `hci0`, sin `/sys/class/bluetooth`, `rfkill` solo `phy0`. MEDIDO.
- **Hallazgo útil para B3/B4**: el bus serdev del kernel se llama **`serial`** (`drivers/tty/serdev/core.c:428`): los dispositivos aparecen en `/sys/bus/serial/devices` y el driver `hci_uart_qca` ya está registrado en `/sys/bus/serial/drivers/` (junto a `hci_uart_bcm`, `hci_uart_mrvl`, `hci-ti`). `/sys/bus/serdev` no existe: `uke-bt-up.sh` y su arnés usaban esa ruta (avisado a la sesión B0; corregida también en §8 de este informe). MEDIDO.
- **Sin efecto sobre WiFi ni hardware**: ping de la tablet a la puerta de enlace durante toda la prueba, **330/330, 0 % de pérdida**, rtt medio 16,9 ms; `wpa_state=COMPLETED` (5180 MHz) antes/durante/después; `adsp.b40` `42c86837`; `ath11k` sin líneas nuevas; `s2` sigue en `standby` con usuarios `s1/s2/s3/l7 = 1/1/1/2` (el BT no ha encendido nada, como se esperaba); pines 35/40–43/80/156 siguen `UNCLAIMED`; la consola ACM no recibió ni un byte (`/var/tmp/uke-sesion-console.log` sin crecer; un único lector armado, el lazo `timeout 5 cat`). MEDIDO.
- **Estado final**: los 4 módulos siguen cargados (inocuos; no sobreviven a un reinicio por la blacklist). Para descargarlos: `modprobe -r hci_uart btqca btbcm bluetooth`.
- **Para B3, corrección del plan**: la sesión B0 comprobó en el código que la UART mainline **no** trabaja en FIFO sino en DMA (`qcom_geni_uart_data.mode = GENI_SE_DMA`; mapeo por `dma_map_single` con el wrapper QUP1, SID `0x423`, el mismo stream del KTZ secundario). Mi §2.5/§5 B3 decían "FIFO sin DMA: sin riesgo"; no es así: B3 ejercita por primera vez ese camino DMA/SMMU en esta tablet. Detalle y mitigaciones en `BT-B0-20261018.md` §6 (leer antes de B3). INFERIDO hasta que se pruebe.

## Resultado de B3 (aplicado el 18-oct-2026, 10:54 CEST del PC; con orden expresa del dueño, tras leer BT-B0 §6)

- **Preparación**: instalé **solo** `uke-bt-up.sh` en la tablet (sha `9facfb49…` == repo, ruta corregida a `/sys/bus/serial`); sin servicio, sin guarda nueva, sin `uke-bt.conf`. Antes: `uke-bt-up.sh --status` (wrapper QUP1 con `iommu_group` 5: pre-check de BT-B0 §6.3 cumplido), `dmesg -n 7`, `sync`, lector ACM único (el lazo `timeout 5 cat`), segundo canal `ssh … dmesg -W` y ping continuo de la tablet a la puerta de enlace.
- **Orden**: `UKE_BT_VARIANT=u uke-bt-up.sh` → `uke_bt_uart cargado (overlay aplicado)`, `VERDE: solo la UART (sin chip)`, rc=0, en menos de 1 s. MEDIDO.
- **Qué pasó en el kernel** (`dmesg`, MEDIDO): `uke_bt_uart: overlay aplicado (id 1, 1154 B)` y **`888000.qcom,qup_uart: ttyHS0 at MMIO 0x888000 (irq = 232, base_baud = 0) is a MSM`**. El nodo vivo pasó a `status=okay`, `compatible=qcom,geni-uart`; el dispositivo `888000.qcom,qup_uart` está ligado a `qcom_geni_serial`; existe `/dev/ttyHS0` (el alias vendor `hsuart0` da el nombre, como predijo BT-B0 §6.1). Sin `Invalid FW loaded`: la SE2 de QUP1 viene como UART. Los pines 40–43 figuran reclamados por la UART en función `gpio` (estado `sleep`, puerto cerrado). Sin ningún `fault`/`Unhandled`/aviso de SMMU. MEDIDO.
- **Avisos esperables, sin consecuencia**: `loading out-of-tree module taints kernel` y siete `OF: overlay: WARNING: memory leak will occur if overlay removed, property: …` (el overlay *reescribe* propiedades de un nodo del DT de arranque; la fuga solo ocurre al retirar el overlay). Coincidiendo con la carga, `arm-scmi arm-scmi.1.auto: failed to setup channel for protocol:0x10`: es el reintento de un probe que ya figuraba en `devices_deferred` antes (6 entradas antes y después), no del BT. MEDIDO.
- **Sin efecto en el resto**: ping de la tablet a la puerta de enlace **150/150, 0 % de pérdida**, rtt medio 16,2 ms; `wpa_state=COMPLETED`; backlight `uke-backlight` 372/372 antes y después; `adsp.b40` `42c86837`; la consola ACM no recibió ni un byte (`/var/tmp/uke-sesion-console.log` sin crecer). MEDIDO.
- **Lo que B3 NO ha ejercitado (corrección a "B3 = primera vez por DMA")**: el probe no abre el puerto. El mapeo DMA por el SID `0x423` ocurre en el primer `open` (startup del puerto), que hará `hci_uart` en B4 (serdev). Con B3 solo se ha demostrado: probe, protocolo UART, reloj, interconnect y pinctrl. El camino DMA/SMMU sigue sin probar en esta tablet. INFERIDO.
- **Estado final**: `uke_bt_uart` sigue cargado y `/dev/ttyHS0` existe; `hci_uart`, `btqca`, `btbcm`, `bluetooth` también. Sin chip encendido (BT_EN, rails y el nodo `bluetooth` no se han tocado). Descargar: `ssh … '/usr/local/sbin/uke-bt-up.sh --down'` (descarga `hci_uart` y retira el overlay; el camino de retirada no está probado y avisa de fuga de memoria). Antes de B4 hay que descargarlo (el script no mezcla variantes).

## Resultado de B3b (aplicado el 18-oct-2026, 10:58 CEST del PC; con orden expresa del dueño)

Objetivo: abrir `/dev/ttyHS0` con el chip apagado para ejercitar por primera vez el DMA de la UART por el SID `0x423` del wrapper QUP1 (BT-B0 §6.3).
- **Montaje**: `sync`, `dmesg -n 7`, lector ACM único, `ssh … dmesg -W` y ping continuo (90 s) de la tablet a la puerta de enlace. Línea base: `uke_bt_uart` y `hci_uart` cargados, `ttyHS0` cerrado (`runtime_status=suspended`), WiFi `COMPLETED`, `adsp.b40` `42c86837`. Nota: el `stty -F /dev/ttyHS0 -a` de mi lectura de línea base ya abrió y cerró el puerto una vez antes de armar las capturas; no dejó rastro en `dmesg`.
- **Paso 1 (el pedido)**: `stty 115200 raw -echo crtscts clocal` (rc 0); lectura de 3 s con `cat` (0 bytes, expirado por `timeout` como se esperaba); escritura de 1 byte con `dd` → **rc 124: bloqueado 5 s**. Causa (INFERIDA, coherente con la medida): con `crtscts` el transmisor espera CTS (gpio40), que con el chip apagado lee `high` (= inactivo, línea activa en bajo): `/proc/tty/driver/qcom_geni_uart` marcó `tx:0 rx:0 brk:2` (RX en bajo permanente = *break*, normal sin chip). Sin fallos en `dmesg`.
- **Paso 2 (variación mía, mismo byte)**: para completar la transmisión repetí la escritura con `-crtscts`: `dd` rc 0, **`tx:1`**, `brk:3`; el puerto volvió a `runtime_status=suspended`. Es una desviación menor de la orden (quitar el control de flujo) con el mismo riesgo; la decisión de repetirla fue mía y la anoto aquí.
- **Resultado**: **el DMA RX (3 s con el puerto abierto) y el DMA TX (1 byte completado) por el SID `0x423` funcionan sin ningún fault**: cero líneas nuevas de kernel en `dmesg` ni en la captura `dmesg -W` (41 líneas, todas `audit:`), sin avisos de SMMU/IOMMU. Hipótesis "nadie ha ejercitado nunca el DMA por ese stream" → ahora ejercitada con éxito en reposo (carga pequeña: 1 byte, RX vacío). MEDIDO.
- **Sin efecto en el resto**: ping **90/90, 0 % de pérdida**, rtt medio 17,2 ms; `wpa_state=COMPLETED`; `adsp.b40` intacto; consola ACM sin un byte nuevo; rails y pines sin cambios (40–43 vuelven al estado `gpio`/`sleep` al cerrar).
- **Observación ajena al BT**: al terminar, `uke-backlight` marca `brightness=102 actual_brightness=0`, `bl_power=4`, `card1-DSI-1/dpms: Off` y no hay ningún mensaje de KTZ/I2C/panel en `dmesg`: es el apagado de pantalla por inactividad (el brillo ya había pasado de 372 a 102 antes de B3b, por otra sesión o por el usuario). INFERIDO que no es del BT. Cuidado: la tablet se **suspendió sola a las 01:45** y el WiFi no volvió; si vuelve a suspenderse durante B4, la prueba y la conexión USB se pierden.
- **Estado final**: `uke_bt_uart` y `hci_uart` (+`btqca`, `btbcm`, `bluetooth`) siguen cargados; `ttyHS0` cerrado; chip sin encender (BT_EN, rails y nodo `bluetooth` sin tocar).
- **Siguiente (B4)**: `uke-bt-up.sh --down`, instalar el servicio sin habilitar (`deploy.sh --go --service`: sustituye `uke-bootguard` por la versión con `bt`, ruta de arranque de WiFi/escritorio, ya probada en el PC con 59 comprobaciones), generar la dirección BD (`--bdaddr random`, con confirmación interactiva en terminal) y `uke-bt-up.sh` (variante B). Con el control de flujo del driver (el chip alimentado conducirá RTS).

## Resultado de B4 (aplicado el 18-oct-2026, 11:02–11:08 CEST del PC; con orden expresa del dueño) — PRIMER ENCENDIDO DEL CHIP: VERDE

**Pasos previos (todos sin incidencias)**: `uke-bt-up.sh --down` (retira el overlay UART: nodo vuelve a `disabled`/compat vendor, `ttyHS0` desaparece, pines 40–43 `UNCLAIMED`; primer `of_overlay_remove` de la tablet, sin fallos); `deploy.sh --go --service` (instala `uke-bt.service` **sin habilitar**, `uke-bt-up.sh` y `uke-bootguard` con `bt`; antes/después idénticos); dirección BD aleatoria local escrita en `/etc/modprobe.d/uke-bt.conf` (modo 600, solo en la tablet, no versionada; `--bdaddr XX:XX:XX:XX:be:12`). El script exige que el dueño reescriba la dirección en un terminal; el dueño dijo en el chat "hazlo tú" tras ver esa misma dirección, y yo le pasé la confirmación por un pseudo-terminal (`script`), tras cerrar la pestaña que esperaba. Anotado porque es una forma de saltarse la comprobación `[ -t 0 ]` del script, con orden expresa.

**Orden**: `uke-bt-up.sh` (variante B, sin rail PA) con `dmesg -n 7`, `sync`, lector ACM único, `dmesg -W` por ssh, ping continuo (200 s) y un muestreador cada 0,5 s de `s2/opmode`, usuarios de los rails y `wpa_state`.

**Resultado (MEDIDO)**: `VERDE` en ~2 s: `uke_bt_b cargado (overlay aplicado)` → `serdev: serial0-0` (**hipótesis 1 del plan confirmada**: el overlay crea el dispositivo serdev hijo en el orden bueno) → `hci_uart cargado` → `hci0: QCA setup on UART is completed`.
- `dmesg`: `uke_bt_b: local-bd-address fijada por el parametro bdaddr`; `serial serial0: tty port ttyHS0 registered`; `hci_uart_qca serial0-0: supply vddrfa2p2 not found, using dummy regulator` y `supply vddasd … dummy` (los dos avisos previstos); `hci0: setting up wcn6750`; **`QCA Product ID 0x00000015`, `SOC Version 0x40140120`, `ROM Version 0x00000102`, `Patch Version 0x00005639`, `controller version 0x01200102`** (ROM 1.2 **confirmada**: coincide con `msbtfw12`/`msnv12`); `QCA Downloading qca/msbtfw12.mbn` (0,58 s) y `qca/msnv12.bin` (0,10 s); **`QCA FW build version: BTFW.MOSELLE.1.2.0-00268.2-PATCHZ-1.76686.25`** (== `msbtfw12.ver`); `setup completed`. Dos avisos benignos del arranque del chip a 115 200: `Frame reassembly failed (-84)` y `unexpected event for opcode 0xfc48`.
- **NVM aceptado** (`qca_tlv_check_data` no se queja): hipótesis del RE-BT cerrada. **La velocidad operativa de 3 Mbaud y el firmware funcionan** (setup en ~0,9 s tras el reset).
- Sin ningún `fault`/`Unhandled`/aviso de SMMU en `dmesg` ni en la captura `dmesg -W`; la consola ACM no recibió un byte; `uke-bootguard status bt` = `fallos=0`.
- **Auto-apagado confirmado** (hipótesis del plan): sin `bluetoothd`, el core apaga `hci0` a los ~3 s: el muestreador ve los rails subir de `1,1,1,2` a `2,2,5,3` (s1 +1, s2 +1, **s3 +4**, l7 +1; los 4 consumidores de s3 del driver) entre 11:04:26 y 11:04:29, y volver a `1,1,1,2`.
- **`s2` cambió de modo, como se predijo**: `standby` → `fast` mientras el BT estuvo encendido (por el `set_load` de 257 mA, umbral 200 mA) y de vuelta a `standby` al apagarlo. **El WiFi no lo notó**: `wpa_state=COMPLETED` en las 360 muestras (0,5 s) y ping de la tablet a la puerta de enlace **200/200, 0 % de pérdida**, rtt medio 17,5 ms (un máximo de 99 ms, aislado). Hipótesis §8 "el paso de s2 a fast no perturba al WiFi": **cumplida** en este escenario (WiFi activo, 5 GHz).
- **Encendido sostenido**: `btmgmt -i hci0 power on` (sin `bluetoothd`) mantiene el chip arriba (`current settings: powered br/edr`; rails `2,2,5,3`, `s2=fast`); segunda descarga idéntica del firmware en el re-setup. `btmgmt info`: controlador primario, versión HCI 13, fabricante 29 (Qualcomm), `supported settings` incluye `le`, `ssp`, `secure-conn`, `wide-band-speech`, `cis-*`, `iso-broadcaster`; `current settings: br/edr` (LE no activo: el kernel no tiene `BT_LE`); `Configuration options: missing options:` vacío → la dirección BD del DT está aplicada. `rfkill`: `hci0: Bluetooth`, soft y hard desbloqueado.
- **Pines**: tras el encendido, gpio156 (BT_EN) y gpio80 (SW_CTRL) figuran reclamados (`serial0-0` / `f000000.pinctrl:636`); gpio35 (WLAN_EN) sigue `UNCLAIMED`.
- **Prueba funcional (inconclusa)**: `btmgmt find -b` (inquiry BR/EDR de ~10 s): empezó y terminó bien, **0 dispositivos** (nadie visible cerca o chip con menos alcance por faltar el rail PA; indistinguibles). El alcance real no está medido; se mide en B6 con auriculares en modo emparejamiento (§8: "sin vddrfa2p2 el chip arranca y funciona" → **arranca y completa el setup; funcionamiento RF por verificar**).
- **Estado final**: chip apagado (`btmgmt power off`; rails `1,1,1,2`, `s2=standby`, WiFi `COMPLETED`, `adsp.b40` `42c86837`), `hci0` registrado y `uke_bt_b` + `hci_uart` + `btqca` + `btbcm` + `bluetooth` cargados. `bluetooth.service` sin habilitar; nada que arranque solo (sin `--arm`).

**Pendiente tras B4**: B6 (bluetoothd, emparejar auriculares, A2DP, alcance/TX, soak 30 min con tráfico WiFi) y, si el alcance es malo, B5 (rail `pmr735a_s3` en kernel v4; `BT_LE`, RFCOMM, BNEP, UHID, AF_ALG). B7 (`--arm`) solo cuando el dueño lo decida. Riesgo conocido: la tablet se suspende sola tras un rato de inactividad (01:45) y el WiFi no vuelve; con el BT en uso conviene vigilar suspensión/reanudación.

## Resultado de B6 (aplicado el 18-oct-2026, 11:09–11:52 CEST del PC; con orden expresa del dueño): A2DP FUNCIONA, 31 min sin cortes

- **Montaje**: bloqueo de suspensión transitorio (`systemd-run … systemd-inhibit --what=sleep --mode=block`, 55 min como máximo; liberado al terminar), `bluetooth.service` arrancado **a mano** (sigue `disabled`; no sobrevive a un reinicio), ping continuo de la tablet a la puerta de enlace (35 min + 31 min), muestreadores de `s2`/rails/WiFi cada 2 s y de enlace BR/EDR/sink/xruns cada ~10 s, `dmesg -W` y lector ACM único. Aviso: otra sesión ejercitó el ADSP durante el soak (`qcom-apm gprsvc:service:2:1: CMD timeout for [1001021] opcode`, 11:34; `uke-null-sink` de PipeWire también es suyo): ajeno al BT; el ADSP siguió `running` y la carga `Charging`.
- **Arranque de `bluetoothd`**: PipeWire/WirePlumber (usuario `omarchy`) registró los endpoints A2DP en `bluetoothd` sin tocar nada; adaptador `Powered: yes` (AutoEnable). MEDIDO.
- **Emparejamiento, en dos tiempos (lección práctica)**:
  1. Descubrimiento normal (`scan on`) → el auricular `Nothing Headphone (a)` se vio por **anuncios LE**; `bluetoothctl pair` emparejó **por LE** (`type LE Public connected`, GATT leído, `Bonded: yes`) y `connect` abrió un enlace BR/EDR que `bluetoothd` cerró a los segundos ("terminated by local host"): sin llave clásica no hay A2DP; `btmgmt con` solo mostraba `LE Public`. **LE funciona** en este kernel (el controlador anuncia `le`, `ll-privacy`, `cis-*`…; GATT y emparejamiento LE operativos).
  2. `remove` del dispositivo y `scan bredr` (filtro de transporte) con el auricular otra vez en modo emparejamiento → **visto por BR/EDR en <1 s**, `pair` por clásico **correcto** (`type BR/EDR connected`, `Pairing successful`), `trust`, `connect`: aparece el transporte `…/sep2/fd0` (retardo 1500, volumen 64) y `btmgmt con` = `BR/EDR`. Regla: para dispositivos de doble modo, descubrir con `scan bredr` antes de emparejar. MEDIDO.
- **PipeWire**: sumidero `bluez_output.<mac>.1`, `api.bluez5.profile = a2dp-sink`, **códec AAC**, ya por defecto de WirePlumber; `pw-play` de un tono de 3 s (440 Hz, −22 dBFS): sumidero `RUNNING` durante la reproducción, `IDLE` después, `pw-top` ERR=0, `pw-play` rc 0. **Que se oyó: NO confirmado** (ver la corrección al final de este apartado). MEDIDO (flujo) / pendiente (audición).
- **Perfiles que no hay, como se predijo**: HFP/HSP fallan con `socket(STREAM, RFCOMM): Protocol not supported (93)` (sin `BT_RFCOMM`): sin micrófono de auriculares hasta B5; `hidp` se autocarga y el auricular crea su `input` (botones multimedia). MEDIDO.
- **Soak de 31 min (11:20:48–11:50:48)**: seis segmentos de 5 min, casi silenciosos, con un pitido de 0,4 s (−26 dBFS) al inicio de cada uno, a 24 kHz por el mismo sumidero AAC:
  - **Enlace**: 190 muestras (~10 s) con `bredr_con=1`, sumidero `RUNNING`, `pw-top` ERR=0 en **todas**; los seis `pw-play` terminaron con rc 0; ningún mensaje de `hci0`/`Bluetooth` en el `dmesg` del soak (solo el `CMD timeout` de audio, ajeno).
  - **WiFi**: ping de la tablet a la puerta de enlace **1860/1860 y 2100/2100, 0 % de pérdida**, rtt medio 15,3 y 15,5 ms (máx. 41 y 44 ms); `wpa_state=COMPLETED` en las 190 + 1050 muestras.
  - **Rails**: constantes `users=2,2,5,3` y `s2=fast` durante todo el soak (BT encendido); el WiFi no lo notó.
  - **Suspensión**: ninguna durante el soak (el bloqueo estaba activo; las últimas suspensiones —`suspend-to-idle` a ~3826 s, pantalla apagada por inactividad— fueron antes de B4). El bloqueo se liberó al terminar, de modo que la tablet vuelve a poder suspenderse (y tras suspender el WiFi no volvía, ver B1).
- **Alcance (RF sin el rail PA)**: a muy corta distancia la RX/TX funciona (descubrimiento BR/EDR <1 s, emparejamiento, 31 min de AAC sin errores). **El alcance en metros no está medido** (BlueZ no expone RSSI de un enlace BR/EDR conectado sin `Experimental`); la medida es que el dueño se aleje con los auriculares y anote a qué distancia se corta. Si es insuficiente → B5 (rail `pmr735a_s3`). Hipótesis §8 "sin `vddrfa2p2` funciona": **funciona a corta distancia durante 31 min**; alcance pendiente.
- **Estado final**: auricular emparejado, de confianza y **conectado**; `bluetooth.service` activo (no habilitado), chip encendido (`s2=fast`), `hci0` arriba; `/tmp/bt-b6` borrado; `adsp.b40` `42c86837`; `uke-bootguard status bt` `fallos=0`; consola ACM sin un byte. Para apagarlo: `bluetoothctl disconnect`, `systemctl stop bluetooth`, `uke-bt-up.sh --down`.
- **Correcciones a este informe**: §2.2/§4#7 decían "sin `BT_LE` no hay teclados/ratones BLE": el `.config` tiene `# CONFIG_BT_LE is not set` pero **LE funciona** en 7.2.9 (medido); lo que sí falta de verdad es `BT_RFCOMM` (HFP/HSP), y siguen sin AF_ALG-hash ni `UHID` (impacto en HOGP/GATT hash por medir con un teclado BLE).

- **CORRECCIÓN (18-oct, ~11:55) — el dueño NO oyó nada**: la respuesta "oí los pitidos y el alcance es suficiente" salió de un botón con texto predefinido por mí y el dueño la corrigió después ("no oí nada, el alcance bien"). Por tanto **B6 queda en `PASA en enlace/transporte, FALLA/PENDIENTE en audición`** y B7 (`--arm`) se pospone hasta que haya sonido audible. Datos del diagnóstico (solo lectura + un tono de prueba): sumidero `bluez_output.*` al **81 %** (−5,46 dB, sin mute; sube desde el 50 % porque el auricular sincroniza el volumen absoluto por AVRCP), transporte `MediaTransport1` `State=idle` sin stream y **`active`** durante/tras la reproducción, y `btmon` durante un **tono de 880 Hz creciente de 12 s (−34 → −6 dBFS)** muestra tramas L2CAP continuas de 54–71 B (≈300 en el intervalo; longitudes variables: no es silencio) en el canal dinámico del A2DP, **sin ningún error ni desconexión** (el contador `ACL Data TX` dio 0 porque el formato de `btmon` no lleva ese texto). Es decir, los datos AAC salen hacia el auricular; si no suenan, el fallo está en el lado del auricular (volumen propio, otra fuente/multipunto, tono demasiado bajo: los pitidos del soak eran de −26 dBFS y 0,4 s) o en que el dueño no los tenía puestos. Pendiente: que el dueño diga si oye el tono creciente.

## Resultado de B7 (aplicado el 18-oct-2026, 11:55–11:57 CEST del PC; con orden expresa del dueño tras confirmar que SÍ oyó el tono creciente)

- **Apagado previo**: `bluetoothctl disconnect`, `systemctl stop bluetooth.service`, `uke-bt-up.sh --down` (descarga `hci_uart` y retira `uke_bt_b`): rails `1,1,1,2`, `s2=standby`, pines 40–43/80/156 `UNCLAIMED`, nodo UART `disabled`, WiFi `COMPLETED`. MEDIDO.
- **`deploy.sh --go --arm`**: comprueba firmware, módulo, servicio, `uke-bootguard` con `bt` y la blacklist de `hci_uart`; `uke-bootguard reset bt`; `systemctl enable uke-bt.service` (enlace en `multi-user.target.wants`). Antes/después idénticos (WiFi, ath11k, `adsp.b40`). MEDIDO.
- **Prueba de la unidad sin reiniciar** (`systemctl start uke-bt.service`, 11:56:13): `uke-bootguard bt: intento marcado (pending)` → `uke_bt_b cargado` → `serdev: serial0-0` → `hci_uart cargado` → `VERDE: hci0: QCA setup on UART is completed` (1 s) → `uke-bootguard: bt: ok` → `Finished`; `Result=success`, `ExecMainStatus=0`; guarda `fallos=0` y sin `pending`. Muestreo de 0,5 s: `s2` `standby`→`fast`→`standby` (3 s) con `wpa_state=COMPLETED` en todas. `hci0` presente, chip apagado tras el auto-off, `bluetooth.service` inactivo. MEDIDO.
- **Qué NO está probado**: el arranque en frío con la unidad habilitada (orden real: carga → WiFi → BT → escritorio), ni BT + suspensión s2idle. **`bluetooth.service` sigue deshabilitado**: tras un reinicio habrá `hci0` pero ningún `bluetoothd` hasta que se arranque a mano (o se habilite: decisión del dueño). Desactivar el BT al arranque sin reflashear: `touch /etc/uke/no-bt`; deshacer todo: `deploy.sh --go --revert`.

## Resultado del REINICIO EN FRÍO con `uke-bt.service` habilitado (18-oct-2026, 12:02 CEST del PC; con orden expresa del dueño)

- **Procedimiento**: aviso previo a la sesión de audio (sin módulos de audio cargados, ADSP `running`), un solo lector ACM, `sync; sync; systemctl reboot` (nunca `reboot -f`). Ping caído a +4 s, vuelve a +17 s, SSH a +18 s. MEDIDO.
- **`deploy/arranque/deploy.sh verify`: 19 pasan, 0 fallan** (unidades, sddm/Hyprland/quickshell, WiFi con IP/ruta/ping, hora, GMU cargado, dmesg sin errores ath11k/GMU/SMMU/Oops, guarda sin omitir nada). Orden medido: carga 7,6 s → WiFi 22,6 s → escritorio 22,8 s (GMU 25,0 s) → BT 22,7 s (en paralelo con el escritorio, `After=uke-wifi` solamente). Táctil: `uke-touchd` carga firmware en 0,29 s y valida ~3600 frames/30 s. Pendiente del ojo y el dedo del dueño: escritorio y táctil. MEDIDO.
- **BT en el arranque: el chip queda arriba, pero la unidad figura `failed` (exit 3)**:
  - `dmesg`: `22.817 hci0: setting up wcn6750` → `24.959 command 0xfc00 tx timeout` / `Reading QCA version information failed (-110)` → `Retry BT power ON:0` → `27.199 otro tx timeout` → `Retry BT power ON:1` → `27.419` versión leída (`ROM 0x102`, `controller 0x01200102`) → firmware y NVM → **`28.136 QCA setup on UART is completed`**. Es decir, **en frío los dos primeros intentos de encendido expiraron (2,1 s cada uno) y el tercero funcionó** (hci_qca reintenta hasta 3 veces); en los ensayos en caliente, con el WiFi arriba desde hacía horas, el primer intento había funcionado siempre.
  - **Bug de `uke-bt-up.sh`** (falso positivo): a los ~3 s vio `hci0:.*timeout` del primer intento y devolvió **ROJO** sin esperar al reintento del driver; `/var/log/uke-bt.log`: `ROJO: el setup del chip fallo`. Efecto: `uke-bt.service` `failed` (`Result=exit-code`) con `hci0` presente, `hci_uart`+`btqca`+`btbcm`+`bluetooth` cargados y el chip ya apagado por auto-off. La guarda dio `ok` (la tablet siguió viva), `fallos=0`. Los otros dos `failed` del sistema (`fake-hwclock`, `shadow`) son anteriores y ajenos al BT. MEDIDO.
  - **Hipótesis de causa del fallo en frío (INFERIDA)**: el BT se encendió 0,1–0,3 s después de que `uke-wifi` terminara (WiFi `VERDE` a 22,56 s, `uke_bt_b` a 22,74 s), con el WPSS recién arrancado y coincidiendo con el escritorio; refutar con un colchón de espera en la unidad y repetir el reinicio en frío.
  - **Corrección en curso** (sesión B0, solo PC): tratar `tx timeout`, `Reading QCA version information failed` y `Retry BT power ON:N` como transitorios, ROJO solo si el driver se rinde o a los 90 s, VERDE con `setup completed` aunque haya reintentos; caso de prueba nuevo en el arnés; valorar un `ExecStartPre` con espera tras `uke-wifi`. Nada desplegado: la unidad de la tablet sigue siendo la anterior.
- **Estado tras el reinicio**: `hci0` registrado y chip apagado, `bluetooth.service` `disabled`/`inactive` (sin `bluetoothd` no hay A2DP hasta arrancarlo a mano o habilitarlo), `uke-bt.service` `enabled` pero `failed`, WiFi `COMPLETED`, `adsp.b40` íntegro, rails `1,1,1,2` y `s2=standby`.

## Resultado del SEGUNDO reinicio en frío, con la corrección de la sesión B0 desplegada (18-oct-2026, 12:13–12:16 CEST del PC; con orden expresa del dueño): `uke-bt.service` VERDE

- **Verificado antes de desplegar** (no me fié del aviso de la sesión B0): `build.sh` → `RESULTADO: OK` (58 pruebas de `uke-bt-up.sh`, 59 de la guarda, 26 del despliegue simulado; `MAX_INIT_RETRIES=3` coincide con `hci_qca.c`; los mensajes que reconoce existen en el fuente); revisé la lógica nueva: `setup completed` ⇒ VERDE (anotando los reintentos), ROJO solo si el driver se rinde (último reintento fallido y registro quieto) o no reabre el puerto, AMARILLO si hay `hci0` pero no se vio el final en 90 s; y `Environment=UKE_BT_SETTLE=8` en la unidad (el script espera hasta que `uke-wifi` lleve 8 s activo).
- **Despliegue**: `deploy.sh --go --service` (unidad + `uke-bt-up.sh` + `uke-bootguard`; sha del script en la tablet == repo `2a1f97a2…`; WiFi, ath11k y `adsp.b40` idénticos antes/después) y `systemctl reset-failed`. Aviso previo a la sesión de audio (sin módulos de audio, ADSP `running`), un lector ACM, `sync; sync; systemctl reboot`: SSH a +16 s.
- **Resultado (MEDIDO)**: `uke-bt.service` **`active`, `Result=success`, `ExecMainStatus=0`**. Línea de tiempos (s desde el arranque): WiFi terminado a 23,34 → unidad BT arrancada a 23,34 → `colchón: uke-wifi quedó activo hace 0,2 s; espero 7,83 s` → `uke_bt_b` cargado a 31,41 → `hci0: setting up wcn6750` 31,47 → versión del controlador 31,59 → **`QCA setup on UART is completed` a 32,30 s, a la PRIMERA, sin `tx timeout` ni `Retry BT power ON`** (solo el aviso benigno `Frame reassembly failed (-84)`) → `VERDE` → guarda `ok` → `Finished`. En el reinicio anterior (sin colchón, BT a 0,1–0,3 s de `uke-wifi`) hicieron falta dos reintentos.
- **`deploy/arranque/deploy.sh verify`: 19 pasan, 0 fallan**. Fallidas del sistema: solo `fake-hwclock` y `shadow` (anteriores y ajenas). Rails al final `1,1,1,2`, `s2=standby`, `adsp.b40` íntegro, `Charging`.
- **Qué prueba y qué no**: con el colchón de 8 s el encendido del chip en frío funciona al primer intento, coherente con la hipótesis de que el BT necesita que el WPSS/WiFi lleve unos segundos estable; **es una sola observación por brazo** (sin colchón: fallo en frío, 1 arranque; con colchón: éxito, 1 arranque), así que la causa sigue INFERIDA. Para refutarla: repetir varios arranques con `UKE_BT_SETTLE=0` (drop-in `Environment=UKE_BT_SETTLE=0`) y con 8. Sigue pendiente decidir si se habilita `bluetooth.service` (sin él no hay `bluetoothd` ni A2DP tras el arranque) y si se mide el alcance en metros.

## Resultado sobre el kernel v4 (`7.2.9-senemos.1.4054.3-ouke4`, flasheado por el dueño; 18-oct-2026, ~15:30 CEST del PC; con orden expresa del dueño)

- **Contexto**: la sesión de audio construyó el v4 (ouke3 + parches SMMU 0002 y 0004) y el dueño lo flasheó; la tablet arrancó en v4 con `fw_devlink.strict=0`, `regulator_ignore_unused`, `pd_ignore_unused` en el cmdline. En ese primer arranque `uke-carga` y `uke-wifi` fallaron (faltaban los módulos ouke4; la sesión de audio los arrancó a mano tras instalar el árbol) y `uke-bt.service` falló con salida limpia (`no encuentro el modulo uke_bt_b`, exit 1; la guarda dio `ok`, `fallos=0`). MEDIDO.
- **Recompilación (PC)**: `build.sh` contra `build/kernel-pokes/senemos-build` (release ouke4): los tres `.ko` con vermagic `7.2.9-senemos.1.4054.3-ouke4` (referencia: `hci_uart.ko` del modroot ouke4), `RESULTADO: OK`. Defecto propio corregido de paso: `harness/test-deploy-sim.sh` tenía `ouke3` cableado en dos comprobaciones (fallaban al cambiar el árbol); ahora lee `include/config/kernel.release` como `deploy.sh`. Commit `82aa1fa`; los `.ko` ouke3 siguen en `31fbf3f`. MEDIDO.
- **Instalación**: `deploy.sh --go --module` → `/usr/lib/modules/…ouke4/extra/uke_bt_{uart,b,a}.ko` + `depmod` de ouke4 (junto a `uke_audio_e2/e2b.ko`); el árbol ouke3 no se tocó; WiFi, ath11k y `adsp.b40` idénticos antes/después. (Avisos de `tar` por marcas de tiempo "en el futuro": el reloj de la tablet va por detrás del PC; inocuos.) MEDIDO.
- **Arranque del BT sobre v4**: `dmesg -n 7`, `sync`, lector ACM único, `dmesg -W`, ping y muestreador de 0,5 s; `systemctl restart uke-bt.service` → **VERDE al primer intento** (sin reintentos del driver): `uke_bt_b` cargado, `serial serial0: tty port ttyHS0 registered`, `serdev: serial0-0`, `ROM Version 0x102`, `controller 0x01200102`, firmware y NVM, **`QCA setup on UART is completed`** ~0,9 s después de `setting up wcn6750`; guarda `ok`. MEDIDO.
- **DMA de la UART con los parches SMMU del v4 (lo que se pidió vigilar)**: `/proc/tty/driver/qcom_geni_uart` = **`tx:118912 rx:2251`** (≈ firmware 109 KB + NVM 6 KB por TX, respuestas por RX), **cero** `Unhandled context fault`/errores `arm-smmu`/Oops/aborts en `dmesg` ni en la captura `dmesg -W` (un falso positivo de mi primera regex: la cadena "iommu: Default domain type" contiene "fault"). MEDIDO.
- **Resto**: WiFi `COMPLETED` en las 240 muestras (0,5 s) y ping de la tablet **150/150, 0 % de pérdida** (rtt medio 17,0 ms); rails `1,1,1,2`→`2,2,5,3`→`1,1,1,2` y `s2` `standby`→`fast`→`standby` (3 s, auto-off) como en v3; ADSP/WPSS `running`, `Charging`; consola ACM sin crecer. El único mensaje ajeno en `dmesg -W` es `qcom-apm gprsvc:service:2:1: CMD timeout` (457 s), de las pruebas de audio de la otra sesión. MEDIDO.
- **Pendiente en v4**: reinicio en frío para ver el BT arrancar solo con la unidad (colchón de 8 s) sobre el kernel nuevo; A2DP sobre v4 no se ha repetido (solo el encendido del chip).

## PENDIENTES (para retomar) — 21-oct-2026 ~21:30 (cierre de la sesión BT; la tablet NO se toca sin orden del dueño)

**Estado general.** El BT del día a día está cubierto y probado en la tablet: arranque VERDE con `uke-bt.service` (opción A, ciclos), panel y A2DP, suspensión de 25 s con auriculares (VERDE el 21-oct 21:07 con el gancho y el ayudante nuevos) y 1.er arranque en frío con el `hci_uart` parcheado (21:12, VERDE tras 1 reintento). En la tablet (ouke5/v6) están instalados: `uke-bt-up.sh` `3e493c5f`, `uke-bt-sleep` `90930b33`, `uke-bt-resume` `e9d026e0`, `uke-bt-wait` `dec89b83`, `uke-bt.service` `a934f78f`, `hci_uart.ko` parcheado en `updates/` (`493ef41c951f…`), `bt-medir.sh` y `bt-consumo.sh` en `/usr/local/sbin/`. Visión de conjunto y plan: `BT-ESTADO-PARA-EL-DUENO-20261021.md` §0. Vuelta atrás de todo: `build/rootfs/deploy/bt/deploy.sh --go --revert`.

| # | Pendiente | Estado | Commit | Primer paso para retomar |
|---|---|---|---|---|
| 1 | **Chip «mudo» en frío** (el 1.er comando `0xfc00` sin respuesta) y el `hci_uart` parcheado | Causa sin determinar (H1 carrera de 50 ms, H2 contención con el WiFi, H3 reapertura del puerto). Opción A (reintento por ciclos) **desplegada y verificada** en hardware (12/12 en bucle). El parcheado **ya está desplegado** (defaults = serie) y cargó bien 4 veces (3 en las fases `bt_down` del consumo y el arranque en frío de 21:12). **Las medidas H1/H2 NO se han ejecutado.** Urgencia baja: 0 ROJOS en los arranques de ouke5 registrados (9 a 21-oct 01:40 + el de 21:12), frente a 4 de 10 en ouke4 (p = 0,087) | `62c82a8`, `286f264` (análisis); `acaa674` (despliegue; **`extra/`→`updates/`**); `6e88b3d` (arranque en frío) | Con orden del dueño, por **USB**, un solo lector ACM y **sin otras sesiones ni SSH abiertos** (avisarlas): `build/rootfs/deploy/bt/ciclo-prueba.sh --check` y luego `--go --etapas "medir carga"` (~20 min, ~140 encendidos); analizar con `python3 -I hciqca/analiza-medicion.py <log>`; criterio y decisión en `BT-MUDO-FIX-20261021.md` §4–5 (MEJORA = p < 0,05 y 1.er intento ≥ 90 % en ≥ 20 ciclos). Si «MEJORA»: `deploy.sh --go --hciqca-conf "uke_bt_boot_ms=N"` (**solo probado con mocks**). Si se descarta el parche: `ssh … 'rm /usr/lib/modules/$(uname -r)/updates/hci_uart.ko; depmod -a'` y `uke-bt-up.sh --down` + `--service` |
| 2 | **Consumo en suspensión** (D3) | Despierto **medido**: `bt_off` −0,016 ± 0,035 W, `bt_down` −0,034 ± 0,018 W (no significativos, < 0,1 W; descartadas las 2 primeras fases por un escalón de 1,3 W de la sesión de audio). **En suspensión SIN medir**: exige USB desenchufado | `acaa674` (despierto + herramientas), `c730a4b` | Con la tablet cargada y libre: lanzar **detached** `ssh … 'systemd-run --unit=uke-bt-consumo-s --collect bt-consumo.sh --solo-suspension -R 1 -s 180 -o /root/consumo-s-<fecha>.log'` (~25 min; por defecto ~1 h), **cerrar el SSH y desenchufar el USB** (con SSH abierto `uke-idle-guard` impide dormir), volver a enchufar, recoger el log y `python3 -I consumo/analiza-consumo.py`. Repetir lo despierto sin solapar sesiones si se quiere más precisión |
| 3 | **Reconexión de auriculares tras suspender** | Implementada (ayudante solo-audio con recuperación del mudo) y **verificada en hardware**: 25 s dormida, `pm_wakeup_irq=183`, auriculares reconectados a los 5 s, 0 faults. **Sin verificar**: que el audio SUENE tras reanudar con el gancho nuevo (con el anterior lo confirmó el dueño el 19-oct), la recuperación del mudo *al reanudar* (nunca visto; solo mocks) y `/etc/uke/bt-keep-on` (solo mocks) | `c730a4b`, `f58d804` | El dueño suspende con el botón con audio sonando y confirma que suena al volver; si falla, `grep -E 'uke-bt-(sleep|resume)' /var/log/uke-bt.log` |
| 4 | **Lo que yo veo (menor)** | (a) `uke-idle-guard` (sesión «bateria») bloquea `systemctl suspend` mientras haya CUALQUIER SSH en el puerto 22: una captura `ssh … dmesg -w` impide probar la suspensión (usar ACM + `dmesg` tras reanudar; `ciclo-prueba.sh` ya lo detecta). (b) Si se flashea otro kernel con release distinto de `…-ouke5`, reconstruir los `.ko` (`build.sh`, `KB=`) **y** el parcheado (`hciqca/build-hciqca.sh`): `deploy.sh` se niega si el vermagic no coincide. (c) El «mudo en v6» que citó la sesión padre no consta en `/var/log/uke-bt.log`. (d) `build/android/bt-20261019/` (README modificado y `bt-apagado-20261020/` sin versionar, por instrucción «sin commit»): decidir si versionar (sin binarios del fabricante ni la dirección BD). (e) Los registros de `ciclo-prueba.sh` (`build/logs/bt-ciclo-20261021-*`) están git-ignorados: las cifras están en `NOTAS-OMARCHY.md` (21:0x y 21:07). (f) Ningún interruptor activado: no hay `/etc/uke/no-bt`, `/etc/uke/bt-keep-on` ni `/run/uke-idle-guard.off` | `f58d804` | Nada urgente; (b) solo al cambiar de kernel |
