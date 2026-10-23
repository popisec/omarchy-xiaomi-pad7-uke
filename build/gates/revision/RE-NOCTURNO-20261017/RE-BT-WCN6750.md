# RE-BT-WCN6750 — Bluetooth WCN6750: btpower vendor + FW + plan mainline (17-oct-2026, nocturno)

> **ERRATA (VERIFICACION-W2 + FIXES-W3):** §2 describe mal la anatomía del `.mbn` (es **ELF32**,
> no secciones QCA planas) y §3 exagera swctrl/lamma (lamma 3,0–3,96 V, no 1,6–2,4 V); el
> «walker no encadena» quedó **resuelto a favor** (stride real 12 B; 63 tags; NVM encadena).
> Fragmento DT: usar `artifacts/parches/20-bt-wcn6750-fragment-v2.dtsi` (compila con `dtc`).

Fuentes: `build/android/vendor-modules-20261017/btpower.ko` (141.920 B, `fdbc8e3a…`),
Ghidra `artifacts/bt/decomp/` (47 fns), `llvm-objdump -t` + disasm `artifacts/bt/btpower-disasm.txt`,
DT dump `build/android/dt-full-uke-android/base/`, FW `build/android/msbtfw12.{mbn,ver}` + `msnv12.bin`,
`build/kernel-pokes/k52-L16-tree` (hci_qca.c 2841 lín, btqca.c, binding `qcom,wcn6750-bt.yaml`,
`palawan.dtsi`, `xiaomi-uke.dts`, `lamma-qrd.dts`), `build/kernel-config/k37.config`,
tablet viva `192.0.2.13:5555` (solo lectura). Leyenda: **[H]** HECHO / **[I]** INFERIDO / **[N]** NO VERIFICADO.

## 1. btpower.ko: probe y power-on

**[H]** Platform driver `bt_power`, compatible `qcom,wcn6750-bt` (también `qcom,qca6174/wcn3990/qca6390/qca6490/kiwi/peach-bt/bt-qca-converged`
en la tabla; el .ko trae símbolos). `modinfo`: `MSM Bluetooth power control driver`, vermagic
`6.1.68-android14-11`, depends `smcinvoke_dlkm,pinctrl-msm,rfkill`. Exporta
`btpower_register_slimdev` + `btpower_get_chipset_version`. **NO toca UART/baud**: gestiona solo
reguladores+GPIOs+reloj; el transporte lo abre el HAL QTI sobre `/dev/ttyHS0` (grupo `bluetooth`) con
protocolo QCA en `hci_uart.ko`. Sin refs a tty/serial/baud en decompilado ni strings.

**[H]** Probe (`bt_power_probe`, decomp:155 lín): kmalloc `pwr_data` → flag `qcom,peach-bt` (ausente en uke) →
workqueue/waitqueues/mutexes → `bt_power_populate_dt_pinfo` (DT presente) → `rfkill_alloc("bt_power",
RFKILL_TYPE_BLUETOOTH)` + sysfs `extldo`, `rfkill_init_sw_state(blocked)` → `rfkill_register` →
lee `qcom,pdc_init_table` (ausente en uke) → `btpower_aop_mbox_init` → `probe_finished=1`.
El probe **NO enciende**: el ON llega por rfkill-unblock → `btpower_toggle_radio` → `power_regulators`.

**[H]** Parse DT (`bt_power_populate_dt_pinfo` + `dt_parse_vreg_info`): por cada nombre de la tabla match-data
lee `<nombre>-supply` (phandle) + `<nombre>-config` (16 B BE: min_uV, max_uV, load_uA, enable_flag).
GPIOs leídos (decomp:117-150): `qcom,bt-reset-gpio` → `of_get_named_gpio_flags` (gestiona reset),
`qcom,wl-reset-gpio` (compartido WLAN), `mpm_wake_set_gpios` (u32 array), `qcom,bt-sw-ctrl-gpio`,
`qcom,bt-debug-gpio` (opcional), `qcom,xo-clk-gpio` (opcional), más `clocks`/`clock-names` (ausentes en uke →
reloj omitido). Hijos `bt_ganges`/`uwb_ganges` solo si flag match-data (uke no tiene hijos: va al nodo propio).

**[H]** Valores dump uke (`soc/bt_wcn6750`, phandle TLMM=`pinctrl@f000000` 0x16b):
reset=`<0x16b 156 0>`, sw-ctrl=`<0x16b 80 0>`, wl-reset=`<0x16b 35 0>`, `mpm_wake_set_gpios=<80>`,
`pinctrl-names="default"`. Supplies → regulador (resuelto por phandle vía script):
aon/dig/rfa0p8/rfacmn→`pmxr2230-s3` (0x348, 968000–1040000), rfa1→`pmxr2230-s1` (0x346, 1856000–2040000),
rfa2→`pmxr2230-s2` (0x347, **1256000–1408000**, corrección a PERIF-BT que decía 1.25–1.35M),
ipa-2p2→`pmr735a-s3` (0x345, 1600000–2400000), io→`pmxr2230-l7` (0x1e0, 1800000 fijo).
Ventanas coinciden con los `regulator-min/max-microvolt` de los nodos destino **[H]**.

**[H]** Secuencia ON (camino BT: `btpower_on` → `power_enable(1)` → `platform_regulators_pwr(1)` y
`power_regulators(BT,ON)`; OFF inverso): **1º reguladores** (por cada vreg en orden de tabla:
`regulator_set_voltage(min,max)` —omitido si min/max 0— → `regulator_set_load(load)` →
`regulator_enable`), **2º GPIOs** (`bt_configure_gpios(1)`): request reset (`"bt_sys_rst_n"`) →
reset=0 → **msleep(50)** → `msm_gpio_mpm_wake_set(80,1)` → chequeo wl-reset (si WLAN apagado:
reset=0 → **msleep(100)** `"BTON: WLAN OFF waiting for 100ms delay"`) → xo_clk on → reset=1 →
xo_clk off → **msleep(50)** → sw-ctrl a entrada. **OFF**: reset=0 → **msleep(100)** →
`vreg_disable` todos → `gpio_free` → clk disable. Nombres de vregs en tabla (strings, orden **[I]**):
`qcom,bt-vdd-{io,aon,dig,rfa1,rfa2,rfacmn,rfa-0p8,ipa-2p2}` (+core/pa/smps/asd/xtal/ant-ldo para otros
compatibles; `rfaOp8` es alias con typo de `rfa-0p8`).

## 2. Firmware (`artifacts/bt/parse_msbtfw.py` → `fw-tables.txt`)

**[H]** `msbtfw12.ver` (45 B): `BTFW.MOSELLE.1.2.0-00268.2-PATCHZ-1.76686.25` → ROM **1.2**, SoC Moselle.
**[H]** `msbtfw12.mbn` (109248 B, `3efbd7fa…`): ELF32-ARM EXEC, entry `0x23dc4`, 3 phdrs:
PH0 NULL (148 B cabecera), PH1 `off 0x1000 filesz 4616 memsz 8192 → paddr 0x3d000` (blob config;
cabecera `[0,6,0,0,0x1160,0x60,0xffffffff,0x100]`), PH2 `PT_LOAD off 0x3000 filesz 96960 memsz 100724
(+3764 BSS) → paddr 0x23dc4 = entry`, flags RWX; el segmento termina **exacto a EOF** (slack 0).
btqca lo pide como `qca/msbtfw12.mbn` (`ELF_TYPE_PATCH`, btqca.c:832-834) y lo emite por segmentos.
**[H]** `msnv12.bin` (6206 B, `52553c8a…`): NVM TLV tipo 2, `len 6202` (6202+4 = tamaño exacto):
tag 1 len 64 @0x4 (8 ceros + string versión idéntica al .ver), tags (0,0)@0x48/0x4c,
tag 2 (`EDL_TAG_ID_BD_ADDR`, btqca.h:32) len 6 @0x50 = ceros (placeholder; el kernel lo rellena),
y desde 0x5a blob opaco de 6116 B (tablas RF-cal densas; bytes `08 00 08 00…`, tag HCI=17 no
separable en plano). **[H]** Calibrador: `msnv11/apnv11/cmnv12/hmtnv20` de linux-firmware local
presentan el **mismo esqueleto** → layout estándar QCA, no corrupción del vendor.
**[N]** (riesgo): el walker ingenuo `{u16,u16}` —la misma aritmética que `qca_tlv_check_data`
(btqca.c:418-431)— no encadena el blob; si el kernel lo exige tal cual, el download fallaría con
`-EINVAL`. La validación en target (`dmesg: "QCA Downloading qca/msnv12.bin"`) dirá la última palabra.
Target baud: init 115200 → oper `max-speed` (3.2M propuesto) o 3M proto; el NVM tag 17 (HCI) lo
parchea el kernel en runtime (baud + bit IBS) **[H]** (btqca.c:437-453).

## 3. Plan mainline (borrador en `artifacts/bt/wcn6750-bt-fragment.dtsi`)

**[H]** hci_qca.c: `qcom,wcn6750-bt` (2781) como **serdev**; `qca_soc_data_wcn6750` (2171-2186): 9 vregs
`vddio 5mA, vddaon 26mA, vddbtcxmx 126mA, vddrfacmn 12.5mA, vddrfa0p8 102mA, vddrfa1p7 302mA,
vddrfa1p2 257mA, vddrfa2p2 1700mA, vddasd 200µA`, caps wideband+LE. Con `enable-gpios`: `bt_en`="enable"
OUT_LOW + pulso 0→50ms→1→50ms en setup (1807-1817) y lectura `swctrl`; `swctrl` **obligatorio**
(probe falla sin él, 2492-2500); `susclk` opcional. Sin `enable-gpios` intentaría `pwrseq "bluetooth"`.
OFF: bt_en=0 → 100 ms → reguladores off (2271-2280). Binding (`qcom,wcn6750-bt.yaml`): required
`vddaon/rfa0p8/rfa1p2/rfa1p7/rfacmn` (+resto documentados, gpios deprecated pero el código los exige).
**[H]** UART: vendor `qup_uart@888000` (`qcom,msm-geni-serial-hs`, status ok, reg 888000/4000,
wakeup-byte 0xFD, wakeup IRQ = TLMM **43**, 4 pinctrl) == nuestro `uart10: serial@888000`
(`qcom,geni-uart`, disabled, palawan.dtsi:1344; pinctrl gpio42/43 TX-RX + 40/41 CTS-RTS, qup1_se2).
`uart5` a94000 = consola (serial0): no tocar.
**[H]** Reguladores nuestros (`xiaomi-uke.dts` &apps_rsc): `vreg_s3b_1p04` 968–1040 ✓ (4 rails),
`vreg_s1b_2p04` 1856–2040 ✓, `vreg_s2b_1p4` 1256–1408 ✓ (calca vendor), `vreg_l7b_1p8` 1800 ✓.
**Falta**: grupo pmr735a (plantilla `lamma-qrd.dts:397`, `vreg_s3e_2p4` 1.6–2.4V ✓) para `vddrfa2p2`.
**Hallazgo**: `vddasd` sin equivalente vendor pero `qca_init_regulators` hace `bulk_get` de los 9
(hci_qca.c:2358-2374) → sin `vddasd-supply` el probe falla; el borrador propone fixed always-on
0.95V **[N]** eléctricamente (revisar esquema/ABL; alternativa: colgarlo de rail existente).
**[H]** Kconfig apta ya (`build/kernel-config/k37.config`): `BT=m, BT_QCA=m, BT_HCIUART=m,
HCIUART_SERDEV/H4/QCA=y, SERIAL_DEV_BUS=y` (líneas 1630-1673, 3343).
**[H]** `xiaomi_wifi_gpio.ko` = driver de test GPIO WiFi/SAR Xiaomi (`xiaomi,xiaomi-wifi`), sin relación
con BT; `wlan_firmware_service.ko` sin refs BT/BT-GPIO. **`bt_fm_slim.ko` no existe** en
`vendor-modules-20261017/` (el material lo citaba; solo están btpower + wifi_gpio +
wlan_firmware_service) **[H]**. Sin evidencia de gestor de GPIO compartido: el 156 lo maneja
btpower en exclusiva (mainline: `enable-gpios`; coordinar con `pwrseq-qcom-wcn` del frag wifi,
parche l21 lo tolera — PERIF-BT §4).
FW a rootfs: `msbtfw12.mbn + msnv12.bin → /lib/firmware/qca/` (linux-firmware trae solo rev 11).
Marcador: `hci0` + `QCA controller version` en dmesg; `sw_ctrl`(80)=1 con BT on.

## 4. Verificación viva (solo lectura)

**[H]** `getprop`: `vendor.bt_firmware` en `sde35`, perfiles BT Android estándar, `net.bt.name Android`.
`dmesg` (anillo rotado, uptime ~3170 s): sin líneas de boot `bt_power` (solo WLAN qca6750 + denegaciones
avc de `com.xiaomi.bluetooth` irrelevantes). `soc:bt_wcn6750` presente; `rfkill0=bt_power state 0
(SOFT BLOCKED, coherente con `rfkill_init_sw_state(blocked)` del probe)`, `rfkill1=phy0/wlan state 1`;
`/dev/ttyHS0` 488:0 grupo bluetooth; `/sys/class/bluetooth` vacío (BT apagado, no se tocó);
`/proc/device-tree/soc/bt_wcn6750/` legible con las mismas props del dump.

## Riesgos / pendientes

1. Aceptación de `msnv12.bin` por `qca_tlv_check_data` **[N]** (ver §2; comando: tras insmod hci_uart,
`dmesg | grep -E "QCA Downloading|QCA\,|tlv"`). 2. `vddasd` sin rail vendor **[N]**. 3. GPIO 156 egpio +
colisión pwrseq wifi (mitigado l21). 4. Baud operativo 3.2M vs 3M (quitar `max-speed` si inestable).
5. `qcom,bt-debug-gpio`/`xo-clk-gpio` ausentes en uke: el vendor los tolera (opcionales), mainline no
los pide. 6. `bt_fm_slim.ko` ilocalizable: si existe en otra partición, re-chequear FM/BT coexistencia.
