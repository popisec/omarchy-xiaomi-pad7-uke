# P3-WIFI — todo el WiFi posible SIN tablet (preparación para la ventana)

**Fecha:** 2026-09-29 (madrugada). **Autor:** agente preparador P3-WIFI.
**Restricción cumplida:** cero fastboot/adb/ssh/ttyACM0. Todo lo de este documento está medido en el PC
(ledger del hermano, logs de las rondas, árbol del kernel, DT, imagen del rootfs) o construido offline
bajo `/var/tmp` y `build/gates/prepara/`. Nada flasheado, nada escrito en la tablet.

**Pregunta que responde:** ¿qué falta EXACTAMENTE para que el WiFi se pueda probar en minutos cuando la
tablet vuelva, y cuál es la hipótesis viva del reset de ~7,33 s?

**Respuesta corta:** falta (1) el firmware WCN6750 del vendor (16 ficheros; el rootfs Arch trae solo el
de linux-firmware, que no vale para esta variante) y (2) la cadena de MÓDULOS del kernel (el rootfs
solo trae 5 `.ko` y **bajo el directorio equivocado**: `7.2.0-rc2-palawan+` con `+`, mientras el kernel
K-series es `7.2.0-rc2-palawan` sin `+` ⇒ ni esos 5 cargarían). **Las dos cosas ya están empaquetadas
offline**: `uke-wifi-payload.tar.gz` (§e Rank 1, sha `dfca8884…`). El reset de
~7,33 s es un **reinicio externo del SoC** con el APSS limpio: la hipótesis viva sigue siendo un
temporizador/watchdog del firmware WPSS o de TZ, ~0,38 s después de `qmi firmware start`. El MSI de los
anillos está descartado (s247 y s248). El WiFi **hoy** corre en bypass (la apps-smmu no bindea) pero el
nodo lleva `iommus` (SID 0x1400) y el fork quiere dominio traducido: **dependencia cruzada anotada**
(§b.3).

---

## (a) Línea temporal del problema, con citas

### a.1 Los cuatro intentos limpios (r10/r10b/r10c/r10e) y el Δ de ~7,33 s

Anclas medidas en los logs crudos (`~/proyectos/out/wifi-dmesg-r{10,10b,10c,10e}.log` y
`wifi-trace-pipe-r{10c,10e}.log`). Todos los tiempos en segundos del reloj monótono del kernel:

| ancla (línea de dmesg) | r10 | r10b | r10c | r10e |
|---|---|---|---|---|
| `deferred probe timeout, ignoring dependency` (t0 = inicio probe) | 9412.381835 | 422.416131 | 120.421534 | 1511.112883 |
| `remoteproc0: powering up wpss` | 9412.437763 | 422.472683 | 120.477361 | 1511.177788 |
| `qmi firmware init done` | 9412.833181 | 422.881964 | 120.890367 | 1511.642676 |
| `qmi Coldboot calibration wait started` | 9413.060689 | 423.108356 | — | 1511.869345 |
| `qmi cold boot calibration done` | 9419.196656 | 429.251948 | — | 1518.007537 |
| `qmi firmware ready` | 9419.312820 | 429.366652 | (corte de captura) | 1518.122767 |
| `qmi firmware start` | 9419.312946 | 429.367154 | — | 1518.122829 |
| última línea de dmesg | 9419.700985¹ | 429.749473¹ | — | 1518.510323 |
| última escritura trazada (kprobe) | — | — | 127.771279 | 1518.509807 |
| **Δ(t0 → muerte)** | **7.319** | **7.333** | **7.350** | **7.397** |
| Δ(`powering up wpss` → muerte) | 7.263 | 7.277 | 7.294 | 7.333 |
| Δ(`qmi firmware start` → muerte) | 0.388 | 0.382 | — | 0.387 |
| calibración coldboot (`wait started` → `cal done`) | 6.136 | 6.144 | — | 6.138 |

¹ r10/r10b: última línea del ledger #441; r10c: última traza del `trace_pipe` (el fichero de dmesg se
cortó antes); r10e: dmesg y traza coinciden a 0,5 ms (fichero entero, `wifi-dmesg-r10e.log:3455`).
La 4ª medida (r10e) es la que faltaba: estaba ejecutada (26-sep 22:58) pero **sin acta**; recuperada en
`build/gates/R10E-NOTA.md` (Δ=7,397 s, dentro de la banda pre-registrada 7,2–7,45 s de #442).

### a.2 Qué pasa exactamente en el instante de la muerte

Secuencia medida (r10e, `wifi-dmesg-r10e.log` líneas 3250-3455 y `wifi-trace-pipe-r10e.log`):

1. `ath11k 17110040.qcom,wcn6750: wcn6750 hw1.0` → `boot using fw api 1` (no hay `firmware-2.bin`) →
   `remoteproc remoteproc0: powering up wpss` → `Booting fw image qca6750/wpss.mdt, size 4844`
   (`wifi-dmesg-r10e.log:3251-3265`).
2. `remote processor wpss is now up` (t=1511.384) y el QMI arranca: `qmi wifi fw qmi service
   connected`, `chip_id 0x1 chip_family 0xb board_id 0xff soc_id 0x40140120`,
   `fw_build_id WLAN.MSL.3.0-00642-QCABMSLSWPLZ-1.81982.7.102970.2` (`:3288-3294`).
3. BDF: pide `ath11k/WCN6750/hw1.0/regdb.bin` (`:3308`) y `ath11k/WCN6750/hw1.0/board.bin` (`:3323`);
   el cal **no está** y el fork lo tolera: `qmi failed to load CAL data file:
   cal-ahb-17110040.qcom,wcn6750.bin (sigo sin cal)` (`:3346`, parche UKE en `qmi.c:2483-2493`).
4. **Calibración coldboot explícita en el log: 6,138 s** de
   `qmi Coldboot calibration wait started` (`:3352`, t=1511.869345) a
   `qmi cold boot calibration done` (`:3362`, t=1518.007537); `qmi firmware ready` llega 0,305 s
   después (`:3364`). Es la misma calibración que en Android tarda ~7,0 s (contraste abajo).
5. `qmi firmware start` (`:3395`, = `ath11k_qmi_firmware_start`, `qmi.c:2854`; envía `wlan cfg` +
   `wlan mode`) y **0,375 s después** empieza el burst de programación de anillos
   (`hal type 8 … 0x1b80400` CE, `:3399`) y DP (`hal type 11 … 0xa370b0`, `:3419`).
6. **La muerte cae a mitad del burst DP**, en `ath11k_hal_srng_setup` → `ath11k_pcic_write32`
   (`ath11k_hal_srng_setup+0x60c`, última traza `wifi-trace-pipe-r10e.log` cola: `offset=0xa380f4
   value=0x42`, **con su retorno** a 1518.509807). La última línea de dmesg es
   `hal type 4 ring_num 0 target_reg 0xa3b074 shadow 0x520` (`wifi-dmesg-r10e.log:3455`).

**Módulo/evento concreto:** no muere un acceso al bus (en r10e **238/238** accesos con retorno; en r10c
**123/122** — la última, `0xa3701c`, se quedó sin retorno porque el stream se cortó a media escritura,
no consta wedge). No hay oops, ni pstore, ni PDR, ni `remoteproc … stop/crash`, ni `watchdog received:`
(el handler del wdog del WPSS está registrado por `qcom_q6v5.c:91-105` y no imprimió nada). La consola
muestra **el banner del arranque siguiente** justo después (`out/uke-ubuntu_console.log:8899` seguido
del banner, ledger #441 §3). ⇒ **El APSS está limpio y el que reinicia es el SoC entero**, no el driver.

**Contraste Android (clave):** el Android dorado hace exactamente la misma calibración en frío —
`remoteproc2: powering up wpss` a 5.770783 (`dmesg-android.txt:6647`) y `icnss2: WLAN FW is ready` a
12.788312 (`:10019`) = **7,017 s** — y **allí no hay reset**; después icnss2 sigue (DMS, cfg.ini,
`wlan_mac.bin`) durante segundos. O sea: los ~7 s son la calibración coldboot del firmware, no un
temporizador que mate por sí solo; lo que cambia es lo que hace el host justo después.

### a.3 Lo que ya está descartado (para no repetirlo)

- **`-EIO`/overflow del CE**: resuelto con el parche que ignora `swiotlb=noforce` + pool de rebote
  (ledger #433; `software IO TLB: mapped [mem 0xe7000000-0xeb000000] (64MB)`).
- **Orden MSI→base** (`s247`): el orden cambió exactamente como se pre-registró y el reset no se movió
  (ledger #437: 211/211 escrituras con retorno, mismo tramo).
- **MSI de los anillos como gatillo** (`s248`): 0 escrituras a `+0x48/+0x4c/+0x50` en las 3 trazas y el
  reset persistió a Δ=7,33 s (ledger #441; patch archivado en `patches/wlan-msi-orden.diff` como
  registro, no como fix).
- **`pureason` del ABL**: no discrimina (5 reinicios con el mismo mecanismo → 3 valores; informe
  `criticas/ronda-36/wifi-ronda6-pureason.md`).
- **Fragmento DT de clocks/interconnect del nodo WLAN**: inerte (nadie los consume; `ahb.c` no pide
  clk/icc) — no construirlo (mismo informe).

---

## (b) Dónde está hoy el ath11k en NUESTRO kernel

### b.1 Árbol y configuración

- Árbol: `/var/tmp/uke-k1` = fork `palawan-linux` (base 7.2.0-rc2, `LOCALVERSION="-palawan"`).
  Vermagic (medido con `modinfo`/`strings` sobre el `ath11k_ahb.ko` del rootfs):
  **`7.2.0-rc2-palawan+ SMP preempt mod_unload aarch64`**.
- `drivers/net/wireless/ath/ath11k/` está **en-tree** (mainline) con parches del fork:
  - `ahb.c`: `devm_pwrseq_get(&pdev->dev, "wlan")` (`ahb.c:1178`) — encendido del chip por el PMU;
    `qcom,rproc` (`ahb.c:804`), `memory-region`/MSA (`ahb.c:931-975`); `hybrid_bus_type` para WCN6750.
  - `hal.c`: **s248 sigue aplicado** (`if (0 && (srng->flags & HAL_SRNG_FLAGS_MSI_INTR))` en
    `hal.c:283` y `hal.c:367`) ⇒ los módulos que construya este árbol **no arman el MSI de los anillos**.
    Ver §5 para cómo hacer la variante stock.
  - `qmi.c`: tolera la ausencia del fichero de cal (`qmi.c:2483-2493`).
- Config efectiva = `/var/tmp/uke-k1-build/.config` (= `~/gpu-work/ramaa/s10/build-s122/.config`,
  sha `02354ace…`; INFORME-K1-BUILD §Config):
  `CONFIG_ATH11K=m`, `CONFIG_ATH11K_AHB=m`, `CONFIG_ATH11K_PCI=m`, `CONFIG_CFG80211=m`,
  `CONFIG_MAC80211=m`, `CONFIG_RFKILL=m`, `CONFIG_QRTR=y`, `CONFIG_QRTR_SMD=m`,
  `CONFIG_QCOM_Q6V5_PAS=m`, `CONFIG_QCOM_PIL_INFO=m`, `CONFIG_QCOM_PD_MAPPER=m`, `CONFIG_QCOM_SMP2P=y`,
  `CONFIG_POWER_SEQUENCING_QCOM_WCN=m`, `CONFIG_MHI_BUS=m`, `CONFIG_ARM_SMMU=y`,
  `CONFIG_ARM_SMMU_QCOM=y`, `# CONFIG_MODVERSIONS is not set` (⇒ un módulo de esta misma versión
  carga sin CRCs).
- Matches de driver (compatibles):
  - `ath11k_ahb` solo matchea **`qcom,wcn6750-wifi`** (`ahb.c:35`) — y el nodo vivo **sí** lleva ese
    compatible: el `s229` lo impone por overlay (`fragment@1701`, ver b.2).
  - `qcom_q6v5_pas` matchea **`qcom,cliffs-wpss-pas`** (añadido por el fork, `qcom_q6v5_pas.c:1628`,
    `cliffs_wpss_resource` en `:1433`) ⇒ el WPSS bindea con el nodo vendor tal cual.
  - `pwrseq-qcom-wcn` matchea **`qcom,wcn6750-pmu`** (`pwrseq-qcom-wcn.c:580`) ⇒ el nodo `wifi-pmu`
    del overlay tiene driver.

### b.2 Nodo WLAN en el DT vivo: `iommus` SÍ, y a quién apunta

Verificado en el PC fusionando el DT base del vendor con el payload del `s229`
(`fdtoverlay base-dtb.img + s229-payload-0.dtb`; artefacto
`~/gpu-work/ramaa/s21/dtbo-gpu/s229-boot-dtbo-wifi-wpss.img`, sha `d2a29ea5…`) y contrastado con las
medidas en vivo del ledger #438 (`/proc/device-tree/soc/qcom,wcn6750`):

```
/soc/qcom,wcn6750  (nombre del nodo vendor; el s229 lo modifica in-place)
  compatible      = "qcom,wcn6750-wifi"        ← el vendor trae "qcom,wcn6750"; s229 lo SUSTITUYE
  reg             = <0x17110040 0x0  0xc0000000 0x10000>   (reg-names = msi_addr, smmu_iova_ipa)
  iommus          = <&apps_smmu 0x1400 0x1>    ← SID 0x1400, mask 0x1  (apps_smmu@15000000, phandle 0x129)
  qcom,iommu-dma-addr-pool = <0xb0000000 0x10000000>
  qcom,iommu-dma  = "fastmap";  qcom,iommu-geometry = <0xb0000000 0x10010000>
  dma-coherent
  qcom,rproc      = <&wpss_pas>                ← añadido por s229 (el vendor trae qcom,rproc-handle)
  memory-region   = <&wlan_msa_mem>            ← añadido por s229
  vddaon-supply   = <&ldo_aon>                 ← de wifi-pmu (fragment@1702)
  interrupts      = 32 (0x300..0x31f, GIC SPI)
```

El `s229` crea además `/soc/wifi-pmu` (`compatible = "qcom,wcn6750-pmu"`, con `wlan-enable-gpios` y
los 7 rieles `vdd*`; `fragment@1702`) — es el proveedor del `pwrseq` que `ath11k_ahb` pide.
Los dtbo de pantalla vigentes (`s238`, `s253`, `s257`, `s258`) **conservan la cadena WiFi** (verificado:
todos contienen `fragment@1701` + `wifi-pmu`), porque derivan del `s229`. ⇒ El dtbo actual ya sirve
para el test de WiFi.

Ojo con la confusión "wlan pcie": el nodo **no** es PCI. Es un device "híbrido" cuyo **BAR de 2 MB lo
publica el firmware por QMI** (`ath11k_qmi_request_device_info`, `qmi.c:2169-2186`;
`ATH11K_QMI_DEVICE_BAR_SIZE = 0x200000` en `qmi.h:41`); el driver lo ioremapa y las ventanas de
registros (`0x1b8xxxx` CE, `0xa3xxxx`/`0xa46xxx` DP) caen dentro de él (el remapeo de ventana está en
`ath11k_ahb_get_window_start_wcn6750()`, `ahb.c:152`; explicado en
`criticas/ronda-36/wifi-ronda8-ce-init.md`). El `reg[0]` del DT (0x17110040, **tamaño 0**) es solo la
dirección del MSI (`ahb.c:848-861`), y el `reg[1]` (0xc0000000) es el rango IOVA del vendor, que
mainline no usa.

### b.3 `iommus` ⇒ dependencia cruzada con el apps-smmu (la respuesta al "¿depende del SMMU?")

- **Estructuralmente SÍ**: el nodo vivo declara `iommus = <&apps_smmu 0x1400 0x1>`; si el apps-smmu
  bindea, el WLAN pasa a DMA traducido con pool IOVA `0xb0000000+`. Android lo tiene igual
  (`icnss2 17110040.qcom,wcn6750: Adding to iommu group 8`, `dmesg-android.txt:3697`).
- **Hoy NO lo usa**: el apps-smmu no bindea en nuestro arranque (el wedge de la noche), así que el
  device queda en **bypass/direct** y por eso el bring-up avanza: el pool swiotlb de 64 MB (parche de
  `swiotlb=noforce`) cubre la máscara de 32 bits del WCN6750. El quirk del fork
  (`drivers/iommu/arm/arm-smmu/arm-smmu-qcom.c`, `qcom_smmu_def_domain_type`) devuelve "sin
  preferencia → dominio por defecto **traducido**" para `qcom,wcn6750-wifi`, y **IDENTITY para todo lo
  demás**; el compatible del quirk coincide con el nodo vivo (b.2) ⇒ cuando el SMMU bindee, el WLAN
  será el único maestro que pase a traducción (intencionado; imita a Android).
- **Consecuencia práctica:** el WiFi no necesita al SMMU para llegar al punto actual, pero **cambia de
  modo DMA** cuando el SMMU bindee. Si tras el bind del SMMU reaparece un `overflow`/`-EIO` del CE,
  es esta transición, no una regresión nueva (el pool de rebote debería seguir como fallback, pero el
  camino de `dma_map_resource` del MSI con dominio traducido hay que vigilarlo).
- Riesgo residual a anotar (no bloquea): el `qcom,actlr` del apps-smmu del vendor **no incluye** el SID
  0x1400 (sí 0x800, 0x1800-0x18e0, 0xc01-0xc0e, 0x1c00-0x1c01, 0x1920-0x1947); en mainline ese
  `qcom,actlr` no tiene lector (ledger #443), así que no debería importar.

---

## (c) Firmware: ficheros exactos, paths y qué falta copiar

### c.1 Lo que el driver PIDE de verdad (medido, no supuesto)

Medido en r10e (mismo árbol y misma config que usaremos):

| petición del kernel (log r10e) | quién la hace | ¿necesario? |
|---|---|---|
| `qca6750/wpss.mdt` (+ `wpss.b00..b10,b12`) | `qcom_q6v5_pas` (remoteproc), `firmware-name` del DT | **SÍ** (sin él no hay WPSS) |
| `ath11k/WCN6750/hw1.0/regdb.bin` | ath11k (QMI BDF_TYPE_REGDB) | **SÍ** (o board-2.bin con regdb) |
| `ath11k/WCN6750/hw1.0/board.bin` | ath11k (`ath11k_core_fetch_bdf` → API1) | **SÍ** (es la board file de la variante o82) |
| `ath11k/WCN6750/hw1.0/cal-ahb-17110040.qcom,wcn6750.bin` | ath11k (`cal-<bus>-<dev>.bin`) | **opcional** (el fork arranca sin cal; coldboot cal 6,14 s) |
| `ath11k/WCN6750/hw1.0/amss.bin` | **solo la ruta PCI/MHI** (`mhi.c:357`; `ATH11K_AMSS_FILE` no se usa en AHB) | NO para nosotros |
| `m3.bin` | solo si `m3_fw_support` (WCN6750 = false, hermano #420 §2) | NO |
| `board-2.bin` | alternativa API2 al `board.bin` | NO (usamos API1 a propósito) |

### c.2 Los 16 ficheros del paquete (sha256 del manifiesto `build/gates/firmware-wlan.sha256`)

Procedencia (hermano #420/#422): volcado FAT16 de `modem_a`
(`~/uke-backups/efs-20260905/efs-20260905-modem_a.bin`) → `ramaa/s21/firmware-wcn6750/` (172 ficheros);
`board.bin` se **extrae del segmento LOAD** de `bd_o82.elf` (ELF32 LE, `p_offset=0x400`,
`p_filesz=0xe344`=58180 B). Stage listo y verificado en `~/gpu-work/ramaa/s21/wifi-fw-stage/` (16,0 MB):

| ruta en /lib/firmware | tamaño | sha256 (16 primeros) |
|---|---|---|
| `ath11k/WCN6750/hw1.0/amss.bin` | 7 458 880 | `c42e06f534c07ffd` (no usado por AHB) |
| `ath11k/WCN6750/hw1.0/board.bin` | 58 180 | `2a63af3fec4a2405` |
| `ath11k/WCN6750/hw1.0/regdb.bin` | 24 278 | `dfd788a430239111` |
| `qca6750/wpss.mdt` | 4 844 | `e2d14e4fbcf2acbf` |
| `qca6750/wpss.b00..b10, b12` (12 trozos) | 8 564 907 en total | ver manifiesto (`b11` no existe: normal) |

Manifiesto completo con los 16 shas: `build/gates/firmware-wlan.sha256` (4 shas coinciden con el ledger
del hermano #422/#434; los otros 12 son generados y verificables con `sha256sum -c`). El paquete se
instala con `build/gates/paquete-firmware-wlan.sh --instalar` (destino
`build/rootfs/staging/lib/firmware/`; 24 gates verdes el 28-sep).

### c.3 Android dorado vs linux-firmware vs rootfs Arch

- **Android** (`dmesg-android.txt`): usa **icnss2 + qca_cld**, no ath11k. Rutas del vendor:
  `/vendor/firmware_mnt/image/qca6750/wpss.mdt` (`:6676`, y `wpss.b01..b12` `:6704+`),
  `bd_o82gl.elf` (`:7682`), `regdb_xiaomi.bin` (`:7618`), `WCNSS_qcom_cfg.ini` (`:10021`),
  `wlan_mac.bin` (`:10126`). **No hay `amss.bin` ni `m3.bin` en todo el dmesg** ⇒ el firmware del WLAN
  en esta plataforma es el propio WPSS (`qca6750/wpss.*`), lo que confirma el set del hermano.
  Reservas de memoria del DT dorado: `wpss_region@9bb00000` (25,6 MB) y `wlan_msa_region@a6400000`
  (12 MB) (`:74`, `:77`) — las mismas que el nodo vendor nuestro.
- **linux-firmware (lo que trae el rootfs)**: `ath11k/WCN6750/hw1.0/{Notice.txt, board-2.bin,
  wpss.mdt→sc7280/wpss.mbn, sc7280/wpss.mbn, qcm6490/wpss.mbn}`. Es el set de **otras** placas
  (sc7280/qcm6490); **no** trae `qca6750/`, ni `board.bin`/`regdb.bin` del vendor, ni el cal.
- **Rootfs Arch actual** (`build/rootfs/arch-rootfs.img`, **V4** sha
  `6d7b3fb8254c3229f2e131d3597c7d791965640fc4673b2e147933760b86624d`; en la tablet va **V3**
  `c26a5fcd…`, mismo contenido de firmware/módulos):
  - firmware presente: lo de linux-firmware (arriba). `debugfs`: existe
    `/usr/lib/firmware/ath11k/WCN6750/hw1.0/{Notice.txt,board-2.bin,wpss.mdt→sc7280/wpss.mbn,
    sc7280/wpss.mbn,qcm6490/wpss.mbn}`.
  - **falta**: `/usr/lib/firmware/qca6750/` entero (13 ficheros), `…/hw1.0/board.bin`,
    `…/hw1.0/regdb.bin`, el cal, y `/usr/lib/firmware/qcom/` (GPU/adsp: ámbito F1/F2, no F3).
  - **falta la cadena de módulos**: en `/usr/lib/modules/7.2.0-rc2-palawan+/` solo hay `extra/` con 5
    `.ko` (`ath11k.ko`, `ath11k_ahb.ko`, `ath11k_pci.ko`, `qcom_battmgr.ko`, `qcom_pd_mapper.ko`) y su
    `modules.dep` (`extra/ath11k_ahb.ko: extra/ath11k.ko`). Con eso, `modprobe ath11k_ahb` **falla**
    (faltan `cfg80211`, `mac80211`, `rfkill`, `qcom_q6v5_pas`, `qcom_pil_info`, `qcom_common`,
    `qcom_glink_smem`, `qcom_q6v5`, `pwrseq-qcom-wcn`, `qrtr-smd`; todos son `=m` en el .config).
    El INFORME-A2 §b asumió "la mayoría de drivers van in-tree/builtin" — **no es cierto para el WiFi**.
  - 🔴 **Además, el directorio de módulos NO coincide con el kernel**: los `.ko` del rootfs llevan
    vermagic **`7.2.0-rc2-palawan+`** (build viejo desde el árbol git `~/gpu-work/palawan-linux`),
    pero el kernel K-series que corre la tablet es **`7.2.0-rc2-palawan`** SIN `+`
    (`include/config/kernel.release` del build, y `Linux version 7.2.0-rc2-palawan` en
    `out/k5b-migas.log`, `out/k6-migas.log`). ⇒ ni siquiera los 5 `.ko` presentes cargarían, y
    `modprobe` busca en `/usr/lib/modules/$(uname -r)/` (que no existe). **El payload de §e Rank 1
    instala en el directorio correcto (`7.2.0-rc2-palawan/`), por eso es imprescindible.**
  - **falta la blacklist** (`/etc/modprobe.d/` está vacío en la imagen; el gate 6 de
    `instala-blacklist-ath11k.sh` ya lo decía). Es obligatoria: el compatible vivo
    `qcom,wcn6750-wifi` coincide con el alias OF del módulo, así que udev autocarga `ath11k_ahb` al
    arrancar (el "probe fantasma" del ledger #441 §1, con `-EPROBE_DEFER` por pwrseq y gasto de slot).

---

## (d) Hipótesis firmware-TZ: qué la soporta, qué la debilita y CÓMO se discrimina

### d.1 Soporte

1. **Δ fijo con puntos de muerte distintos (4/4)**: 7.319/7.333/7.350/7.397 s desde t0; el último
   acceso cambia en cada ronda (`dscp_tid_map`, `srng_setup+0x5b4`, `srng_setup+0x60c`, `0xa380f4`) y
   el tiempo no (ledger #441 §3, R10E-NOTA).
2. **APSS limpio**: todas las MMIO con retorno en r10e (238/238); sin oops/pstore/PDR/remoteproc
   stop; sin `watchdog received:` (wdog del WPSS registrado en `qcom_q6v5.c:91-105`).
3. **El reset no lo ve el APSS**: la consola salta al banner del arranque siguiente; no hay mensaje de
   parada. Un reinicio "desde fuera" (TZ/firmware) explica eso; un oops lo habría dejado escrito.
4. **El ancla más estable es `qmi firmware start` (0,382-0,388 s, dispersión 6 ms)** — la muerte llega
   siempre ~0,385 s después de que el host envía cfg+mode. Si el host no envía nada (D1), se sabrá si
   el temporizador cuenta desde ahí o desde el lado firmware.
5. **En Android el WPSS tarda lo mismo (7,017 s) en estar listo y no se resetea** ⇒ el firmware es
   capaz de convivir con un host lento; lo que no tolera es algo del handshake posterior.

### d.2 Lo que la debilita (honestidad)

- La muerte se **infiere** del corte de las capturas (no hay mensaje de reset); en r10c el corte pilló
  una escritura **sin retorno** (123/122) — compatible con un wedge de bus atrapado a media escritura.
  No se puede descartar al 100% un cuelgue del bus con reset por watchdog de hardware.
- El ancla no es única: desde t0 el Δ varía 78 ms (7.319→7.397); el "temporizador" podría estar contado
  desde `powering up wpss` (dispersión 70 ms) o desde `firmware start` (6 ms). Las tres lecturas son
  compatibles con "cal 6,14 s (+0,34 s hasta ready) + 0,38 s" pero no demuestran de dónde cuenta el reloj.
- Nunca se midió la línea base **stock (MSI armado)** con la misma instrumentación de kprobes y en un
  arranque limpio (r4/r5 son de la era pre-pool y con otra instrumentación). Es una medida barata que
  falta.
- TZ no tiene interfaz Linux: no se puede "ver" el temporizador, solo su efecto (reset total).

### d.3 Discriminadores (el experimento que la separa)

**D1 — inyección de espera en el host (el bueno: 1 parche de módulo, 1 arranque, 0 flashes).**
En `ath11k_core_qmi_firmware_ready()` (`core.c:2261`), insertar `msleep(10000)` **antes** de
`ath11k_core_start_firmware()` (es decir: tras `qmi firmware ready`, sin enviar aún cfg+mode y sin tocar
un solo registro). Lectura pre-registrable:
- **muere durante el sueño** (a ~7,3 s de t0, sin ninguna MMIO ni QMI del host) ⇒ el reloj corre del
  lado firmware/TZ y es independiente de lo que haga el host ⇒ hipótesis CONFIRMADA; el camino pasa a
  "averiguar qué espera el firmware" (cal, PD, servicio QMI) y no a más registros.
- **sobrevive el sueño y muere ~0,38 s después del `firmware start`** ⇒ el disparador es del host
  (handshake/registros) ⇒ hipótesis REFUTADA y se vuelve al acceso/ventana concreta.
- **sobrevive >300 s** ⇒ sorpresa (el driver sobrevive con el firmware ya asentado) ⇒ repetir antes de
  cantar nada.

**D2 — aportar el fichero de cal** (`cal-ahb-17110040.qcom,wcn6750.bin`). Si el coldboot cal (6,48 s)
se acorta y el Δ se desplaza con él ⇒ el temporizador está atado al estado del firmware; si el Δ no se
mueve ⇒ la cal es irrelevante. **No se puede preparar offline**: no está en el dump del vendor
(hermano #420; tampoco en `firmware-wcn6750/`), y lo genera un ath11k que ya haya calibrado (huevo y
gallina). Solo tiene sentido si D1 apunta al firmware; como el coldboot cal ya termina
(`qmi firmware ready`), **no es el bloqueo**.

**D3 — escuchar la línea smp2p de crash del WLAN.** El DT tiene
`qcom,smp2p-force-fatal-error` / `qcom,smp2p-early-crash-ind` (mapa en el nodo vendor) y **mainline no
tiene cliente** (eso lo maneja icnss2 en Android). Un módulo mínimo (o un kprobe sobre el handler de
smp2p) que registre esas entradas diría si el firmware **avisa** antes del reset: si avisa ⇒ crash del
firmware (watchdog); si no avisa ⇒ reset externo tipo bus/TZ. Coste: 1 módulo nuevo (no existe hoy).

**D4 — leer el crash reason del WPSS.** `q6v5_wdog_interrupt` imprime
`watchdog received: %s` con el `crash_reason` de SMEM (`qcom_q6v5.c:91-105`); su ausencia en r4/r5/r10*
es evidencia (débil) de que el wdog del WPSS no disparó. No hay debugfs de smp2p en este árbol para
leerlo en frío.

**Lo que NO discrimina (y no hay que gastar en ello):**
- **pd-mapper**: nuestro `qcom_pd_mapper.c` sirve dominios **adsp/cdsp/slpi/mpss/msm8996**
  (`qcom_pd_mapper.c:253-330`); **no hay dominio wpss/wlan** y `qcom_q6v5_pas` no lo usa ⇒ no puede
  ser la palanca del WPSS (y el WPSS ya arranca sin él). El `pd-mapper` de AUR sigue en plan B
  (degradado en F3).
- **pronto**: es el cargador legado de WCNSS (`wcn36xx`/`qcom_wcnss_pil`); el WCN6750 va por
  remoteproc+QMI ⇒ no aplica.
- **TZ**: no hay interfaz; solo su efecto (reset). El `pureason` ya se demostró inútil.

---

## (e) El camino más corto a WiFi hoy (rankeado, con comandos literales)

### Rank 1 — firmware + cadena de módulos en el Arch vivo (SIN reflashear; el camino de minutos)

Es lo único que falta: no hay que tocar kernel, ni dtbo, ni particiones. El dtbo vivo ya trae la cadena
WiFi (§b.2) y el kernel es el K6/K7 (mismo árbol/config que los módulos construidos offline, §5).

**En el PC** (el payload **YA está construido**; el script lo regenera si cambia el árbol):
```bash
sh ~/proyectos/omarchy-uke/build/gates/prepara/preparar-wifi-payload.sh --construir
# deja: /var/tmp/wifi-prep/uke-wifi-payload.tar.gz + .sha256 + INVENTARIO.txt
#   sha256 actual: dfca8884d4d40ef8262188623daa16cbeafa4880f077f831d7a393478b01c697
#   28 .ko (cadena cerrada) + 16 firmware + etc/modprobe.d/blacklist-ath11k.conf  (28 MB)
```
**En la tablet** (Arch; por SSH `root@192.168.42.129` o consola ttyGS0):
```bash
mkdir -p /root/wifi-prep && cd /root/wifi-prep
# desde el PC:  scp /var/tmp/wifi-prep/uke-wifi-payload.tar.gz* root@192.168.42.129:/root/wifi-prep/
sha256sum -c uke-wifi-payload.tar.gz.sha256
tar xzf uke-wifi-payload.tar.gz -C /          # usr/lib/firmware/… · usr/lib/modules/7.2.0-rc2-palawan/… · etc/…
depmod -a "$(uname -r)"                       # release REAL: 7.2.0-rc2-palawan (sin '+', ver §c.3)
sync
./wifi-test.sh                                # ciclo completo: check + modprobe + 30 s + informe
```
Criterios de "hecho" (F3): `lsmod | grep -E 'qcom_pd_mapper|ath11k'`, `ip link` con `wlan*`,
`nmcli dev status` = connected, `nmcli dev wifi list` > 0 redes, y **sobrevivir 300 s** (el fallo
actual es un reset a ~7,33 s; que la interfaz aparezca no basta).
Gate previo en la tablet (1 línea): `cat /proc/device-tree/soc/qcom,wcn6750/compatible` debe contener
`qcom,wcn6750-wifi` (si no, el dtbo no es de la cadena WiFi: volver a `s229`/`s238`).

### Rank 2 — los discriminadores D1/D2 (solo después de reproducir la línea base)

D1: parche de `core.c` + `make M=drivers/net/wireless/ath/ath11k modules` (ver §5.3) → 1 arranque.
D2: solo si D1 dice "lado firmware" y hace falta una pieza que esperar (cal) — requiere una fuente
válida (no existe offline).

### Rank 3 — SMMU traducido / clocks-interconnect (NO son camino, son contexto)

- El SMMU traducido para el WLAN llegará gratis cuando bindee el apps-smmu (el quirk ya lo quiere así,
  §b.3). No es un paso de F3; es una variable a vigilar.
- El fragmento DT de clocks/interconnect es **inerte** (informe ronda 6) ⇒ no construirlo.

### Lo que NO hay que hacer (lecciones ya pagadas)

- No usar `swiotlb=force` (rompe el `dma_map_resource` del MSI: ledger #433/#430).
- No borrar la blacklist sin restaurarla (probe fantasma y gasto de slot: #441 §1).
- No fiarse de la consola 115200 sola (pierde la cola al reset: doble captura obligatoria, #429).

---

## (f) Plan de prueba de 15 minutos (para cuando haya tablet) + captura lista

Presupuesto: **1 ciclo** (1 modprobe = como mucho 1 reintento de slot). Reglas: doble captura
(dmesg + trace_pipe) **a fichero en la tablet y en el PC si hay SSH**; consola serie capturando;
vigía de fastboot del hermano como red de seguridad; nada de reflashear para esto.

| min | paso | comando / criterio |
|---|---|---|
| 0-2 | Pre-flight | `cat /proc/uptime`; `cat /proc/device-tree/soc/qcom,wcn6750/compatible` (→ `qcom,wcn6750-wifi`); `lsmod | grep -c ath11k` (→ 0); `cat /etc/modprobe.d/blacklist-ath11k.conf` (3 líneas); batería ≥ 3,7 V si se puede leer |
| 2-3 | Firmware | `wifi-test.sh --solo-check` → los 16 shas OK (si falta alguno, instalar el payload de Rank 1 y parar) |
| 3-4 | Módulos | `wifi-test.sh --solo-modulos` → los 10 `.ko` de la cadena presentes (`depmod -a` ya hecho) |
| 4-5 | Arnés | el script arma kprobes (`uke_pcic_w/_ret`, `uke_pcic_r/_ret`), `buffer_size_kb=32768`, `dmesg -n 7`, marca `UKE-WIFI-TEST` en `trace_marker` |
| 5-6 | Trigger | `modprobe ath11k debug_mask=0x1FFFF` + `modprobe ath11k_ahb` (UN solo ciclo) |
| 6-7 | 30 s | el script captura 30 s (`dmesg -w` + `trace_pipe` a `/root/wifi-test/*.log`, con `sync` periódico) |
| 7-8 | ¿Vivo? | si responde: `lsmod`, `ip link`, `nmcli dev status`, `dmesg | grep ath11k | tail` |
| 8-13 | Supervivencia | si vivo a 30 s: esperar a **300 s** y `nmcli dev wifi list`; si cae: no insistir, anotar y leer las capturas |
| 13-15 | Informe | el script escribe `reporte-<ts>.txt` (Δ vs t0, Δ vs `firmware start`, entradas/retornos, veredicto) + `sha256sum` de las capturas + fila de ledger (coste: reintentos de slot antes/después) |

Veredictos que imprime el script (pre-registrados aquí):
- `SIN-RESET-300s` → el bring-up sobrevive ⇒ siguiente: `nmcli`, iperf3, y repetir.
- `RESET` con Δ(t0) ∈ 7,2-7,45 s y **todas** las MMIO con retorno → APSS limpio ⇒ rama firmware-TZ.
- `RESET` con la última entrada **sin** retorno → BUS WEDGE ⇒ volver al acceso concreto.
- `DEFER` (probe no llega a `powering up wpss`) → pwrseq no listo: repetir con `modprobe` tardío
  (el script lo detecta y lo dice).

Script listo para copiar: **`build/gates/prepara/wifi-test.sh`** (bash+awk, sin python: el rootfs no
lo trae). Modos: `--solo-check`, `--solo-modulos`, `--captura N` (por defecto 30), `--sin-probe`.
Todo lo que escribe va a `/root/wifi-test/` (persiste al reset; `sync` cada 2 s).

---

## 5. Construcción offline hecha en esta preparación

### 5.1 Módulos (lo que faltaba en el rootfs)

Los builds K1-K6 solo compilaron `Image.gz` (0 `.ko`). Aquí se ha lanzado, sin tocar el hardware:

```bash
env MAKE=/usr/bin/make /usr/bin/make -C /var/tmp/uke-k1 O=/var/tmp/uke-k1-build \
    ARCH=arm64 LLVM=1 MAKE=/usr/bin/make modules -j8     # log: /var/tmp/wifi-prep/modules-build.log
```
Salida: **857 `.ko` en `/var/tmp/uke-k1-build`** (mismo árbol y `.config` que el kernel K6/K7 de la
tablet; `CONFIG_MODVERSIONS` off ⇒ cargan por vermagic **`7.2.0-rc2-palawan`** — el release real, SIN
`+`: ver §c.3). El payload de Rank 1 se arma con `preparar-wifi-payload.sh --construir`, que copia
**la cadena cerrada** (verificada con `modprobe --show-depends` sobre el árbol staged:
`ath11k_ahb → ath11k → mac80211 → cfg80211` + `rfkill` +
`qcom_q6v5_pas → qcom_q6v5/qcom_pil_info/qcom_common/qcom_glink_smem` + `qrtr-smd` +
`pwrseq-qcom-wcn` + `qcom_pd_mapper`) = **28 `.ko`**, no los ~850 del kernel. Resultado verificado
(32 gates OK, 0 fallos): `/var/tmp/wifi-prep/uke-wifi-payload.tar.gz`, 27 999 373 B, sha256
`dfca8884d4d40ef8262188623daa16cbeafa4880f077f831d7a393478b01c697`, 81 entradas.

**Aviso de estado del árbol:** `hal.c` lleva **s248** (MSI de anillos desarmado, `hal.c:283,367`) ⇒ el
`ath11k.ko` del payload **no arma el MSI de los anillos** (es la variante que el hermano ya midió en
r10*: el reset no se movió). Para la variante stock (MSI armado) hay receta literal en §5.3; el primer
test puede hacerse con cualquiera de las dos (el reset es idéntico en ambas según #441) pero **debe
quedar escrito cuál se usó**. Inventario del payload con shas: `/var/tmp/wifi-prep/INVENTARIO.txt`.

### 5.2 Firmware

El paquete de 16 ficheros se instala con `build/gates/paquete-firmware-wlan.sh --instalar` (fuente
`~/gpu-work/ramaa/s21/wifi-fw-stage/`, destino `build/rootfs/staging/lib/firmware/`, shas contra
`firmware-wlan.sha256`). Para el test en caliente no hace falta reconstruir la imagen: el payload de
Rank 1 los copia a `/usr/lib/firmware/` de la tablet.

### 5.3 Recetas literales pendientes (por si se quieren dejar hechas)

Variante stock-MSI del `ath11k.ko` (deshacer s248, compilar solo el módulo, y volver a dejarlo):
```bash
cd /var/tmp/uke-k1
sed -i 's/if (0 && (srng->flags & HAL_SRNG_FLAGS_MSI_INTR))/if (srng->flags \& HAL_SRNG_FLAGS_MSI_INTR)/' \
    drivers/net/wireless/ath/ath11k/hal.c
env MAKE=/usr/bin/make /usr/bin/make -C /var/tmp/uke-k1 O=/var/tmp/uke-k1-build ARCH=arm64 LLVM=1 \
    MAKE=/usr/bin/make M=drivers/net/wireless/ath/ath11k modules
cp drivers/net/wireless/ath/ath11k/ath11k.ko /var/tmp/wifi-prep/ath11k-stock-msi.ko
git -C /var/tmp/uke-k1 status 2>/dev/null || true   # no es repo: deshacer = re-aplicar el '0 && '
```
(Para volver a s248: el mismo `sed` en sentido contrario sobre las dos ocurrencias.)

D1 (espera de 10 s en el host), parche a mano en `core.c:2261`:
```c
 static int ath11k_core_qmi_firmware_ready(struct ath11k_base *ab)
 {
 	int ret;
+	msleep(10000);   /* UKE D1: 10 s de silencio del host tras "firmware ready" */
```
y `make M=drivers/net/wireless/ath/ath11k modules` igual que arriba.

---

## 6. Fuentes citadas

- Ledger del hermano: `~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md` #420 (firmware y
  los 4 compatibles), #422 (16 ficheros), #433 (swiotlb), #434 (instalación verificada), #437 (s247),
  #438 (msi_addr = vendor), #441 (ronda 10: 3 medidas y oops ajenos), #442 (pre-registro r10e).
- Recuperación de r10e: `build/gates/R10E-NOTA.md`.
- Logs: `~/proyectos/out/wifi-dmesg-r{10,10b,10c,10e}.log`,
  `wifi-trace-pipe-r{10c,10e}.log`, `uke-ubuntu_console.log` (línea 8899).
- Android dorado: `~/proyectos/ubuntu-permanente/criticas/ufs-referencia-android/dmesg-android.txt`
  (líneas 55/74/77 reservas; 3697 iommu group 8; 6647 powering up; 6676 wpss.mdt; 7350 QMI server;
  7712 FW init done; 10019 FW ready).
- Kernel: `/var/tmp/uke-k1/drivers/net/wireless/ath/ath11k/{ahb.c,hal.c,qmi.c,core.c,hw.h}`,
  `/var/tmp/uke-k1/drivers/remoteproc/qcom_q6v5_pas.c` (1628), `qcom_q6v5.c` (91),
  `/var/tmp/uke-k1/drivers/power/sequencing/pwrseq-qcom-wcn.c` (580),
  `/var/tmp/uke-k1/drivers/iommu/arm/arm-smmu/arm-smmu-qcom.c` (quirk UKE),
  `/var/tmp/uke-k1-build/.config`.
- DT: `~/gpu-work/ramaa/s21/dtbo-gpu/{base-dtb.img,s229-boot-dtbo-wifi-wpss.img}` (fusión local con
  `fdtoverlay`); `~/proyectos/out/dtb` (volcado vivo del 22-sep, nodo `wifi@17110040`).
- Rootfs: `build/rootfs/arch-rootfs.img` (V4 `6d7b3fb8…`; en la tablet V3 `c26a5fcd…`),
  `build/rootfs/INFORME-A2.md`, `build/gates/PRE-REGISTRO-F5-B1.md` (V1-V4),
  `build/gates/instala-blacklist-ath11k.sh`.
- Gates: `build/gates/firmware-wlan.sha256`, `paquete-firmware-wlan.sh`, `medir-wlan-reset.sh`,
  `patches/wlan-msi-orden.diff`.
- Informes del hermano: `criticas/ronda-36/wifi-ronda8-ce-init.md` (ventana CE, conteo),
  `wifi-ronda6-pureason.md` (pureason y dtbo de clocks inertes).
- Este encargo: misión P3-WIFI (2026-09-29).
