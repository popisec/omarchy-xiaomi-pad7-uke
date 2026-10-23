# WD19 + Xiaomi Pad 7 «uke»: por qué no carga (14-oct-2026)

Estado: **todo HIPÓTESIS + bibliografía**. Tablet en fastboot al redactar;
**nada medido en vivo**. Plan de medición en §4.

## 1. Qué da el Dell WD19 (dato, manual Dell)

Fuente: WD19 User Guide «Docking specifications» (Dell, consultado 14-oct-2026):
`dell.com/support/manuals/.../wd19_userguide/docking-specifications`.
Puertos **downstream** (todos **5 V fijos, sin PD**):

- Frontal USB-A: BC1.2 PowerShare, **2 A @ 5 V (máx 10 W)**.
- Frontal USB-C: **1,5 A @ 5 V (máx 7,5 W)**.
- Traseros USB-A x2: **0,9 A @ 5 V (máx 4,5 W)**.
- Trasero USB-C (+DP1.4): **3 A @ 5 V (máx 15 W)**.
- El **PD de 90/130 W es SOLO el cable cautivo hacia el portátil**, no los
  puertos downstream. Sin la fuente AC del dock (130/180 W) el WD19 **no
  funciona en pasivo** (dato: hilo Dell «WD19 without power supply»).

## 2. Qué pide la Xiaomi Pad 7 (dato, Xiaomi)

Fuente: `mi.com/global/product/xiaomi-pad-7/specs` + FAQ Xiaomi (consult. 14-oct-2026):
batería **8850 mAh**, carga **45 W turbo**; protocolos
**PD3.0/PD2.0 + QC3+/QC3.0/QC2.0 + MI FC2.0**; cargador oficial **5–11 V/4,1 A**.
Conclusión: la carga «buena» exige **>5 V (clase 9/11 V)**. Con 5 V pela­dos
carga lenta; con **5 V/0,9 A (4,5 W)** y pantalla encendida el balance puede ser
**nulo o descarga neta** («no carga» percibido). Hipótesis razonada, no medido.

## 3. Hipótesis rankeadas (setup: tablet→dock→mismo dock→laptop)

1. **Techo 5 V del dock (probable, DATO parcial).** El puerto downstream no
   negocia PD con un *device*; da 5 V con tope 4,5–15 W según puerto. La tablet
   queda en carga lenta/nula. Discriminante: probar puerto trasero USB-C (15 W)
   vs trasero USB-A (4,5 W) — si «carga» solo en el C, es esto.
2. **Límite por enumeración USB (hipótesis).** En modo gadget/RNDIS el D+/D-
   enumera como datos y la detección BC1.2 puede no aplicar → la tablet se
   autolimita a 500 mA (USB2) / 900 mA (USB3). Peor que el techo del puerto.
   Discriminante: `CHARGE_TYPE`/`USB_TYPE` + `CURRENT_NOW` con RNDIS activo vs
   cable de solo-carga.
3. **Driver de carga en mainline (hipótesis).** `qpnp-smb5/smblib`, `extcon`,
   `typec` pueden no clasificar el cargador o no subir el ICL en periférico.
   Discriminante: `dmesg | grep -iE 'smb5|charger|extcon|typec|qpnp'`.
4. **Dock sin AC o en ahorro (verificable en 30 s).** LED del dock, fuente
   conectada; hay reportes de WD19 que corta periféricos con el laptop en
   batería (`reddit r/UsbCHardware`). Discriminante: ¿cargan otros aparatos?
5. **Cable (hipótesis menor).** C-C vs A-C cambia quién anuncia corriente
   (Rp vs BC1.2). Probar ambos, mismo puerto.

## 4. Plan de medición (cuando arranque; todo lectura)

Tablet (SSH `root@192.168.42.129`):
`for f in /sys/class/power_supply/*/uevent; do echo "== $f"; cat $f; done`
(mirar `STATUS`/`CAPACITY`/`VOLTAGE_NOW`/`CURRENT_NOW`/`ONLINE`/`USB_TYPE`/
`CHARGE_TYPE`/`INPUT_CURRENT_LIMIT`); `dmesg | grep -iE 'usb|smb5|charger|
extcon|typec|qpnp'`; repetir en: (a) USB-A trasero, (b) USB-C trasero,
(c) USB-A frontal PowerShare, (d) cargador pared, (e) con/sin RNDIS activo.
PC: `lsusb -t`, `dmesg -w` durante la caída, comparar `lsusb` antes/después,
`cat /sys/module/usbcore/parameters/autosuspend`, `tlp-stat -u`/tunables
powertop del puerto.

## 5. Recomendación práctica

- **Cargar: directo a pared con PD/QC ≥45 W (5–11 V), NO por el dock.** El dock
  como mucho mantiene (trasero USB-C, 15 W); el USB-A trasero (4,5 W) no sirve.
- **RNDIS: preferible a puerto directo del PC**, no vía hub del dock.
- **Caídas RNDIS (20:37, ~21:2x, ~21:4x):** el dock **puede** explicarlas
  (re-enumeración del hub, autosuspend del PC, ahorro con laptop en batería),
  pero es **hipótesis**: verificar con `dmesg` del PC en el momento de la
  caída + `lsusb -t` antes/después; si el dispositivo desaparece y reaparece
  con otra numeración, es re-enumeración del dock/hub. Mitigación: fijar
  `usbcore.autosuspend=-1` o denylist del dispositivo, y no dejar el laptop
  suspender.
