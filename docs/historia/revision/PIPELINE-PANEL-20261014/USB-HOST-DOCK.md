# USB host/OTG + dock Dell WD19 — auditoría (14-oct-2026, ~21:45)

Estado: **DT + config + drivers VERIFICADOS en fichero; NADA medido en vivo**
(tablet inaccesible durante la auditoría, ver §3). Todo lo vivo = plan.

## 1. Hardware/DT (medido en `build/kernel-pokes/k52-L16-tree`)

- Controlador: `usb_1: usb@a600000`, `compatible = "qcom,palawan-dwc3"` (`palawan.dtsi:3149`).
  PHYs: `usb_1_hsphy` (HS, vía `pm7550ba_eusb2_repeater`) + `usb_dp_qmpphy`
  (`qcom,palawan-qmp-usb3-dp-phy`, `palawan.dtsi:3092`) para SS/DP.
- `xiaomi-uke.dts:485-494`: `&usb_1 { dr_mode = "otg"; usb-role-switch; status = "okay"; }`,
  endpoint HS → `pmic_glink_hs_in`. pmic-glink (`xiaomi-uke.dts:89-129`, compatible
  `qcom,lamma-pmic-glink`): conector `power-role/data-role = "dual"`.
- Driver `drivers/usb/dwc3/dwc3-qcom.c:618-642`: role-switch con notifier + vbus-override. OK.
- **Huecos DT**: endpoints SS y SBU con `remote-endpoint = <0>` (sin cablear, líneas 119-129)
  → hoy solo HS (USB2). `orientation-gpios = tlmm 122` copiado del QRD, **sin confirmar en
  uke** (TODO en `xiaomi-uke.dts:79-82`). **Sin regulador VBUS/boost OTG declarado** (grep
  `vbus` vacío en ambos DTS) — el boost lo llevaría el PMIC vía glink, sin describir.

## 2. Config `build/kernel-config/k52L58.config` (líneas medidas)

SÍ está: `USB_DWC3=y` (6128) + `DUAL_ROLE=y` (6132) + `DWC3_QCOM=y` (6140);
`XHCI_HCD=y` + `XHCI_PLATFORM=y` (6052/6056); `USB_STORAGE=y` (6090); `HID=y` (5872),
`USB_HID=m` (6016); `USB_RTL8152=m` (2800, Ethernet del WD19); `TYPEC=y` (6335),
`TYPEC_UCSI=y` (6343), `UCSI_PMIC_GLINK=m` (6347), `TYPEC_QCOM_PMIC=m` (6342);
`USB_ROLE_SWITCH=y` (6379); `EXTCON=y` (7380); `QCOM_PMIC_GLINK=m` (7294);
PHYs `QMP_USB/QUSB2/EUSB2_REPEATER=y` (8131-8134); gadget configfs ACM+NCM+RNDIS (6279-6299).
**Nada obligatorio que añadir** (no existe `CONFIG_USB_HUB`: el hub es core de usbcore).
Opcionales: `CONFIG_USB_MON=y` (debug); `CONFIG_EXTCON_QCOM_SPMI_MISC=y` (hoy `is not set`,
línea 7392 — solo si la detección VBUS/cargador falla en vivo). Pendiente: confirmar que los
`=m` (ucsi_glink, r8152, xhci-plat) están en el rootfs y cargan (`lsmod`, en vivo).

## 3. Vivo: NO MEDIDO (tablet caída durante la auditoría)

`ssh root@192.168.42.129` timeout ×3; ping 100% loss; `lsusb` del PC sin la tablet.
`journalctl -k`: gadget `UKE-S120` (ACM+NCM, **NCM no RNDIS**) conectado hasta **21:37:32**,
luego `USB disconnect` + `error -71` sin regreso (medido 21:40:58). Hipótesis: el dueño la
desenchufó/reinició. **Reintentar la parte viva cuando vuelva.**
Mecanismo de conmutación (documentado, NO probado): desbindear gadget
(`echo "" > /sys/kernel/config/usb_gadget/g1/UDC`), luego
`echo host > /sys/class/usb_role/<rol>/role`; retorno con `echo device` o **reboot físico**
(ukeinit re-arme el gadget → device por defecto). **El SSH muere al pasar a host por diseño**
(va por NCM en el mismo cable): usar script con temporizador que revierta solo, o consola
ACM como testigo. Plan vivo: `ls /sys/class/{usb_role,typec,extcon}/`, `lsusb -t`,
`dmesg | grep -iE 'dwc3|typec|role|ucsi|phy'`, `lsmod | grep -E 'ucsi|r8152|xhci'`.

## 4. Plan de prueba (cuando el dueño decida; tablet al cable upstream del dock)

1. Consola ACM abierta en el PC como testigo + `dmesg -w`.
2. Enchufar al upstream; en vivo: `dmesg` (esperar `new high/super-speed USB device` + hub
   `1-1.x`), `lsusb -t`, `ls /sys/bus/usb/devices/`.
3. RJ45 al dock: esperar `r8152 … ethX`; DHCP a su red; `ip addr`.
4. Carga: `cat /sys/class/power_supply/*/uevent` (`STATUS/VOLTAGE_NOW/CURRENT_NOW/USB_TYPE`).
   Ver también `docs/historia/revision/PIPELINE-PANEL-20261014/WD19-CARGA.md` (downstream = 5 V sin PD; upstream podría dar PD 90 W).
5. Recuperación: si no hay SSH, reboot físico → vuelve a device+NCM.
**PASA = hub enumerado + HID/Ethernet con IP + PD >5 V (o carga neta positiva).**

## 5. Riesgos/incógnitas (hipótesis hasta medir)

- **VBUS**: sin boost OTG en DT, ¿la tablet entrega 5 V? El WD19 autoalimentado quizá enumere
  sin VBUS de la tablet, o quizá no (USB lo exige). Primer discriminante del test.
- **SS sin cablear** → USB2 como techo (suficiente para hub+HID+R8153); USB3/DP-alt no.
  Datos no necesitan alt-mode DP. El WD19 acepta hosts USB-C no-TB en modo USB2/3+DP-alt
  (reportes públicos; hipótesis para esta unidad concreta).
- Gadget NCM bindeado + roleswitch: el `echo host` exige UDC libre; ukeinit NO lo suelta solo.
- Hub del WD19: sin firmware extra en Linux (usa `hub` genérico + `r8152`); FLIR no aplica.
- `orientation-gpios 122` sin confirmar: si el CC está mal, el rol puede no cambiar por cable.
