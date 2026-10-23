# BLUETOOTH WCN6750 — estado al 14-oct-2026 (solo lectura, sin tablet)

Fuente base: `build/gates/prepara/P4-bluetooth.md` (29-sep, 0 accesos tablet). Esto es
re-verificación contra el árbol/config/rootfs **vigentes**. Leyenda: **[M]**=medido hoy,
**[C]**=citado de P4/informes (no re-medido), **[H]**=hipótesis.

## (a) Kernel: casi listo, un bloqueante sigue abierto

- **[M]** `build/kernel-config/k52L58.config`: `BT=m`, `BREDR/LE=y`, `HCIUART=m`,
  `HCIUART_SERDEV=y`, `H4=y`, **`QCA=y`**, `BT_QCA=m`, `SERIAL_DEV_BUS=y`,
  `QCOM_GENI_SE=y`, `RFKILL=m`, `PWRSEQ_QCOM_WCN=m`. Suficiente para hci_qca+btqca+serdev.
- **[M]** **Bloqueante: `CONFIG_SERIAL_QCOM_GENI` sigue `# … is not set`** (`k52L58.config:3317`).
  Sin este driver no existe `serial@888000` ⇒ no hay serdev ⇒ BT imposible. Igual que en P4 §2.2.
- **[M]** `k52L39-tree/.../xiaomi-uke.dts` (556 lín.): solo habilita `qupv3_id_0/1` + `uart5`
  (consola). `uart10`/BT **no** están en el DTS del kernel (grep vacío).
- **[M]** El nodo BT vive en el **DTBO overlay**: s268 `fragment@1703`
  (`uart@888000` → `qcom,geni-uart` + hijo `bluetooth qcom,wcn6750-bt`, supplies→dummy)
  (`mkdtbo-s268.py:20,36,94,284-285`, `repack-s268-report.txt:58`). s281 hereda el stack
  común s250 con uart (comentario `mkdtbo-s281.py:16`). **[H]**: confirmar que el DTBO vigente
  (línea L56) sigue llevando el fragmento 1703 antes de probar BT.
- **[C]** Pines exclusivos: BT_EN gpio156, SW_CTRL gpio80, UART gpio40-43 (`base-uke.dts`,
  P4 §1). Driver exige 9 reguladores por nombre; `vddasd` sin contraparte vendor (P4 R2):
  REV-RADIO-FW dice que supplies ausentes caen a **dummy** (`regulator_dummy_init`,
  `core.c:2435`) y es aceptado; P4 propone mapeo provisorio o parche 3 líneas. **[H]** abierta.

## (b) Firmware: v11 sí, v12 no

- **[M]** Ambas rootfs (`arch-rootfs.img`, `rootfs-uke-k521.img`, debugfs):
  `qca/msbtfw11.mbn`+`.tlv`, `msnv11.bin`+`.b09`+`.b0a` **presentes**; `msbtfw12/msnv12` **ausentes**.
- **[M]** v12 existen en `~/gpu-work/fw-qrd8635/` (shas = P4 §3: `24c90664…`, `66eb3eb2…`).
  Staging offline `build/rootfs/staging` + paquete `uke-fw-radio` llevan la pareja v11 (ledger #529).
- **[H]** `rom_ver`: REV-RADIO-FW afirma 0x11 (basta v11); P4/E dicen la familia cliffs usa
  v12. Sin `dmesg` vivo ni `adb ls /vendor/bt_firmware` no se dirime. Mitigación: instalar ambas.

## (c) Qué falta para `hci0`

1. `CONFIG_SERIAL_QCOM_GENI=y` + rebuild (un cambio por ciclo, con fila ledger + consola).
2. Verificar fragmento BT en el DTBO vigente; si falta, re-añadir (Anexo A de P4).
3. Decidir `vddasd` (dummy vs mapeo vs parche) — solo se valida en vivo (`-ENODEV` en probe si muerde).
4. **[M]** Módulos BT ausentes en `extra/` (solo ath11k*, battmgr, pd_mapper):
   instalar `bluetooth, hci_uart, btqca, rfkill` (+hidp/rfcomm) + `depmod`.
5. **[M]** Copiar `msbtfw12.mbn`+`msnv12.bin` a `/usr/lib/firmware/qca/` (dejar los v11).
6. **[M]** Userspace ausente (sin `bluetoothctl`/`main.conf`/`bluetooth.service` en ambas imgs;
   `PACKAGES-OVERLAY.txt` sin bluez/pipewire): instalar `bluez bluez-utils pipewire
   pipewire-pulse wireplumber` (+sbc; aptX/LDAC opcional).
7. **[C/H]** WiFi no requerido (cores/FW independientes, P4 §5, no medido en esta tablet).
  SMMU sí indirecto: qup1 es cliente de `apps_smmu`; el proyecto hoy lleva `QCOM_IOMMU=n`
  (ledger #528) — el bring-up de display en curso despeja el mismo camino QUP/SMMU.
8. Hermano: DT BT+PMU aplicado (#528), fw v11 en staging (#529), captura "BT apagado,
  recaptura con radio ON pendiente". **Ningún proyecto ha hecho bring-up BT en Arch.**

## (d) Plan de prueba (próxima sesión con enlace; consola ACM + ≥3700 mV)

```bash
dmesg -n 7
dmesg | grep -iE '888000|geni|serdev|hci|bluetooth|qca|btqca|msbtfw|msnv'
ls /sys/bus/platform/devices/ | grep -E 'geniqup|888000'
ls /usr/lib/firmware/qca/ | grep -E 'msbtfw|msnv'
modprobe -v hci_uart btqca rfkill; ls /sys/class/bluetooth/   # esperado: hci0
rfkill list; rfkill unblock bluetooth
bluetoothctl show                                              # UP RUNNING + BD address
systemctl start bluetooth
bluetoothctl  # power on, agent on, default-agent, scan on -> MACs; pair/trust/connect
wpctl status; pactl list cards short                           # bluez_card.<MAC> (A2DP)
```
- Solo-lectura Android previo (barato, dirime rom_ver): `adb shell ls -l /vendor/bt_firmware/`,
  `dmesg | grep -iE 'btqca|QCA controller|msbtfw|msnv'`, `regulator_summary | grep -iE 'asd|wcn|bt'`.
- Fallos guía: sin `888000` ⇒ DTBO/SMMU/GENI; `QCA controller version` + fallo descarga ⇒
  pareja v11/v12 equivocada (ver nombre pedido en el log); `-ENODEV` en probe ⇒ R2 vddasd;
  `Soft blocked` ⇒ rfkill. HFP por SCO-HCI es riesgo alto conocido (vendor usa ADSP/BTFM);
  A2DP no afectado.
