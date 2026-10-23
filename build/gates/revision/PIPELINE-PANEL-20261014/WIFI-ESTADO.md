# WIFI WCN6750 / ath11k — estado al 14-oct-2026 (solo lectura, sin tablet)

> Base: informes E, B §16, G; NOTAS; `k52L58.config`; `k52-L16-tree` DT;
> `staging/` + `firmware-wlan.sha256`; P4-GO-NOGO (11-oct); ledger #599–#607.

## (a) Kernel: listo para probe, con 2 pokes propios — MEDIDO

- `k52L58.config`: `ATH11K=m`, `ATH11K_AHB=m`, `ATH11K_PCI=m`, `DEBUG=y`;
  `QCOM_PD_MAPPER=y` (in-kernel, E quedó degradado a plan B);
  `QCOM_Q6V5_PAS=y` + `COMMON=y`, `QRTR=y`, `GLINK=y` (+SMEM), `PMIC_GLINK=m`,
  `QCOM_RMTFS_MEM=y`, `ARM_SMMU_QCOM=y`, `SWIOTLB=y`,
  `DMA_BOUNCE_UNALIGNED_KMALLOC=y`. `QCOM_Q6V5_WCSS` ausente = OK
  (es para IPQ; el WPSS de uke va por PAS con `qcom,cliffs-wpss-pas`).
- Pokes wifi en built-in: L18 (`qcom_q6v5_pas.c`, `-EPROBE_DEFER`→sigue),
  L19 (`qcom_q6v5.c`, ICC vendor sin proveedor→NULL), L21
  (`l21-wifi-btgpio.diff`, bt-enable GPIO156 sigue con warning UKE-WIFI).
- Cadena módulos verificada 11-oct (P4 GO 3/3): 234/234 símbolos UND
  resueltos contra `System.map` L19; `ath11k_ahb→ath11k→mac80211→cfg80211`.
- DT: `palawan.dtsi` trae `wifi@17110040` (`qcom,wcn6750-wifi`) y
  `remoteproc_wpss@9bb00000`, AMBOS `status="disabled"`;
  `xiaomi-uke.dts` no habilita NADA wifi (0 nodos). El enable vive en los
  frags dtbo **1701–1707** (wifi-pmu/pwrseq, wifi, wpss `cliffs-wpss-pas`,
  rails smpb1/smpb3/smpe3, GPIOs 35/156) — ver (c).

## (b) Firmware: el vendor está manifestado, NO en nuestro staging — MEDIDO

- Manifiesto `build/gates/firmware-wlan.sha256` (28-sep): 16 ficheros
  `ath11k/WCN6750/hw1.0/{amss,board,regdb}.bin` + `qca6750/wpss.{mdt,b00-b12}`
  (4/4 shas ledger #422/#434 coinciden; los 12 restantes son shas nuevos aquí).
- Nuestro `staging/` solo trae upstream: `WCN6750/hw1.0/board-2.bin` +
  `sc7280/qcm6490/wpss.mbn`. Faltan `amss.bin`, `board.bin`, `regdb.bin` y
  todo `qca6750/`. El driver pide **`board.bin` + `regdb.bin`** (`core.c:1912,
  :1927`), no `board-2.bin` → con solo staging, el probe no encuentra board.
- Board-id: `board.bin` vendor (58180 B, sha `2a63af3f…`) es el que instaló el
  hermano en la tablet (#422); si su tabla no trae el id de uke, el driver lo
  dirá por `ath11k_dbg` — HIPÓTESIS hasta medir en vivo. Payload instalable:
  `build/pkg/uke-wifi-payload.tar.gz` (29-sep, 16/16 contra manifiesto).
- Blacklist horneada (`blacklist ath11k{,_ahb,_pci}` en `etc-base/` + staging):
  bloquea autocarga udev (~26 s, causa del reset de slot #441 por
  `uke-wifi-trace.sh:46` que la borraba); `modprobe` manual sigue válido (#442).

## (c) Qué bloquea hoy: el DT wifi wedgea el arranque — MEDIDO (ledger #601)

- Bisect 11-oct: frags wifi → **wedge a 4,1–4,2 s pre-userspace** (H1, único
  superviviente limpio); watchdog muerde a ~40 s; s276 solo-rail inestable.
  Decisión del dueño: **frags wifi aparcados, pantalla primero**.
- Base oficial #607: **L19 + s275-r2 (SIN wifi)** + rootfs k521; `wpss+adsp`
  en remoteproc, GPU FD735 viva. Ningún `wlan0` ha existido jamás; lo más
  lejos: WPSS arriba + `qmi firmware ready` y reset a 7,33 s (3/3, #441).
- **L58 (D16 aprobado 14-oct)**: L56 PWM + L57 **sin `mem=2048M`** + zram.
  B §16: `mem=2048M` enmascara el muro DMA pero **NO elimina el banco >4 GB**
  (`880000000-88b9cefff` sigue visible); el parche `swiotlb.c` (ignora
  `noforce`) + `BOUNCE_UNALIGNED=y` es la mitigación; `swiotlb=force` mata el
  MSI de ath11k. Quitar `mem=` es **riesgo y test a la vez**: si el bounce
  funciona, CE/MSI mapean y se acaba el OOM del escritorio; si no, vuelve el
  `-EIO` del CE. Aislar por gates (MemTotal⇒mem, luz⇒PWM), no por flashes.

## (d) Plan de prueba cuando vuelva el enlace (ordenado, 1 variable/ciclo)

```bash
uname -r; ls /lib/firmware/ath11k/WCN6750/hw1.0/ /lib/firmware/qca6750/ | head -20
lsmod | grep -E 'ath11k|pwrseq|q6v5'; cat /etc/modprobe.d/blacklist-ath11k.conf
cat /sys/firmware/devicetree/base/soc/wifi-pmu/compatible          # ausente hoy: frags aparcados
grep -l wpss /sys/kernel/debug/remoteproc/remoteproc*/name
dmesg -n 7; dmesg -C; T0=$(date +%s)
modprobe pwrseq-qcom-wcn; time modprobe ath11k_ahb
dmesg | grep -iE 'wpss|ath11k|wcn6750|pwrseq|board|CE.*EIO|DMA_MAPPING' | tail -60
ip link show wlan0; rfkill list; nmcli device wifi rescan && nmcli device wifi list
nmcli device wifi connect SSID password PASS   # criterio: connected + uptime>300 s
sync  # siempre antes de sysrq/reboot; reponer blacklist tras el probe
```

- Precondición: reinstalar payload + `depmod` si k521 no lo trae; re-verificar
  símbolos si el kernel vivo ya no es L19 (serie L5x = mismo vermagic, confirmar).
- NO reflashear dtbo con frags wifi hasta que la pantalla esté cerrada (orden
  del dueño); el probe manual con el dtbo actual debe fallar en
  `-EPROBE_DEFER`/ausencia de nodos — ese negativo también es dato.
