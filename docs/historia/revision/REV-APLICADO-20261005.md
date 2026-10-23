# REV-APLICADO (2026-10-05) — fixes P0/P1 de #528 aplicados, compilados y verificados

Aplicador: subagente fixes #528. Entrada: los 5 informes de revisión
(`REV-{GPU-DISPLAY,TACTIL,ENERGIA,RADIO-FW,KCONFIG}-20261005.md`). La tablet **NO se ha
tocado** (cero adb/fastboot, cero flash, cero reboot); todo offline en el PC.

## 0. Decisiones de entorno (leer antes de nada)

- **Rama**: la orden decía commitear en `uke-ports-20260915`, pero esa rama es una foto del
  15-sep SIN el driver táctil (20f0df992), el panel O82, los compatibles `cliffs-*-pas`
  (d1c7ef2e0) ni pwrseq-wcn (d9c42df0c) — sin eso, los fixes B1/B2/B3/D son imposibles.
  **Decisión (confirmada por el usuario)**: rama nueva **`uke-fixes-20261005`** desde
  `s150-postclk` (el checkout que los 5 informes usaron como fuente). `s150-postclk` queda
  intacta. Los 5 ficheros WIP que ya estaban modificados en el árbol (runtime.c,
  arm-smmu{,impl}.c, qcom_battmgr.c, uke-panic-fb.c) **siguen sin commitear** — no son de
  esta ronda y no se han tocado.
- **`make` del sandbox**: el argv[0] de make se reescribe a ZCode.AppImage y los sub-makes
  salen no-ops silenciosos (la trampa documentada en build-pokes.sh). Solución del propio
  proyecto: `export MAKE=/usr/bin/make` (usado en todos los builds de esta ronda).
- **`CONFIG_VIDEO_QCOM_IRIS` apagado**: el build completo moría en
  `drivers/media/platform/qcom/iris/iris_platform_palawan.h:19` (`num_comv` no existe en
  `struct platform_inst_caps`) — **rotura preexistente del árbol**, no de estos fixes.
  Las configs canónicas del proyecto (`kernel-config/k51-pantalla.config`) ya lo llevaban
  `not set`. Se alineó con ellas; VENUS sigue `=m`.

## 1. FIX → COMMIT → VERIFICACIÓN

Build: `cd ~/gpu-work/palawan-linux && make O=~/gpu-work/build-uke -j16 Image modules`
con `ARCH=arm64 LLVM=1 KBUILD_BUILD_USER=uke KBUILD_BUILD_HOST=palawan MAKE=/usr/bin/make`.
Log: `build/logs/build-fix528-20261005.log` (EXIT=0; gate "Image más nuevo que .config" OK).

| Fix | Informe | Estado | Commit (uke-fixes-20261005) | Verificación |
|---|---|---|---|---|
| A1 hub 200 MHz (pre_div 3→6) | GPU F2 | **APLICADO** | `603b37730` "uke: hub 200MHz (F2)" | grep: `F(200000000, P_GPLL0_OUT_MAIN, 6, 0, 0)` en gpucc-palawan.c:158 + comentario del informe. Gate runtime (G3-1, próximo boot): `UKE-CM3DBG hub=200000000` esperado |
| A2 zap en `qcom/uke/` | GPU F1 | **YA ESTABA** | — | PKGBUILD:44 ya instala `usr/lib/firmware/qcom/uke/gen71100_zap.mbn`; el staging `pkg/uke-gpu-firmware/pkg/.../qcom/uke/` y el `uke-gpu-firmware-1-1-any.pkg.tar.zst` (tar -tf) ya lo llevan (estado de 27-sep). El informe partía de un estado anterior. **Gap real anotado en §3**: el rootfs v7 (k521) no tiene el paquete instalado |
| B1 táctil SPI | TACTIL F1 | **APLICADO** | `5702c18ac` | fdtget: `/soc/geniqup@ac0000/spi@a90000 status=okay`; `touchscreen@0 compatible="novatek,NVT-ts-spi", spi-max-frequency=19200000, size 0x858=2136 x 0xc80=3200`; IRQ `<&tlmm 54 EDGE_FALLING>` (0x02) en el decompile |
| B2 ADSP + memoria | ENERGIA F3 / RADIO §5 | **APLICADO** | `5702c18ac` | fdtget: `remoteproc@6800000 status=okay compatible=qcom,cliffs-adsp-pas`; `adspslpi@9d400000 reg=…0x4500000`; `q6-adsp-dtb@a1900000 reg=…0x80000`; el nodo viejo `@a0600000` ya no existe (grep 0). Nota: se aplicó también la alineación recomendada del informe (compatible cliffs + reg 0x03000000). El nombre del nodo sigue siendo `remoteproc@6800000` (el compatible manda para el driver; el estado esperado del propio informe cita `6800000.remoteproc`). El override de reserved-memory es el del diff de RADIO-FW (`/delete-node/ q6-adsp-dtb@a0600000` + nodo nuevo `@a1900000` con el label redeclarado); probé dtc antes y acepta el re-label tras el delete (la referencia `<&q6_adsp_dtb_mem>` de remoteproc_adsp resuelve al nodo nuevo) |
| B3 WPSS + PMU + regulators-3 | RADIO §1-§3 | **APLICADO** | `5702c18ac` | fdtget: `remoteproc@9bb00000 status=okay, firmware-name="qca6750/wpss.mdt"` + cx-supply s3b; `wifi@17110040 status=okay vddaon-supply→vreg_pmu_aon_0p59`; nodo `wcn6750-pmu` con 7 rails (aon/pmu/rfa0p8→s3b, 1p2→s2b, 1p7→s1b, 2p2/asd→s3e) y `bt-enable-gpios` tlmm **156** / `wlan-enable-gpios` tlmm **35**; `regulators-3` (pmr735a, pmic-id e) `smps3=vreg_s3e_2p4` 0x186a00–0x249f00 (1.6–2.4 V) |
| B4 BT UART | RADIO §2.3 | **APLICADO** | `5702c18ac` | fdtget: `/soc/geniqup@8c0000/serial@888000 status=okay` con hijo `bluetooth compatible="qcom,wcn6750-bt", max-speed=3200000` y 6 vregs al PMU virtual (vddio/vddrfa2p2/vddasd → dummy regulator, tal como dice el informe) |
| B5 OPP GPU recortadas | GPU F4 | **APLICADO** | `5702c18ac` | decompile: 9 niveles 255…950 MHz; `opp-1000000000`/`opp-1100000000` ausentes (grep 0). ACD (F3) **NO tocado** a propósito — pendiente |
| B6 USB SS | ENERGIA F5 | **APLICADO** | `5702c18ac` | decompile: connector `port@1/endpoint remote-endpoint=<0xf6>` ↔ phy@88e8000 `port@0/endpoint remote-endpoint=<0xa4>` (cruzados los dos sentidos) |
| C pd_mapper `qcom,lamma` | ENERGIA F2 | **APLICADO** | `760160d41` | `{ .compatible = "qcom,lamma", .data = sm8550_domains, }` junto a palawan (array `sm8550_domains` confirmado). Gate: `grep -a -c "qcom,lamma"` en `qcom_pd_mapper.ko` = 1; en Image = 2 |
| D1 `DRM_PANEL_XIAOMI_O82_DUALDSI=y` | KCONFIG #1 | **APLICADO** | .config (snapshot versionado) | olddefconfig la mantiene; string `xiaomi,uke-o82` presente en Image (driver built-in) |
| D2 `TOUCHSCREEN_NOVATEK_NT36XXX_SPI=y` | KCONFIG #2 / TACTIL F2 | **APLICADO** | idem | string `novatek,NVT-ts-spi` en Image (built-in) |
| D3 `THERMAL_GOV_USER_SPACE=y` | KCONFIG #3 | **APLICADO** | idem | línea `=y` tras olddefconfig |
| D4 `QCOM_IOMMU=n` | KCONFIG #4 | **APLICADO (mejor de lo pedido)** | — | el driver `qcom_iommu.c` **ya no existe en el árbol 7.2**; olddefconfig/syncconfig soltaron el símbolo (NEW→n). Ni línea queda |
| D5 `BATTERY_QCOM_BATTMGR=y` | ENERGIA F1 | **APLICADO** | — | símbolo existe (`drivers/power/supply/Kconfig:211`); `=y` tras olddefconfig. pmic_glink crea el aux "power-supply" incondicionalmente (pmic_glink.c:353), así que no falta nodo DT hijo |
| F3.2 defaults táctil 2136x3200 | TACTIL F3 | **APLICADO** | `5702c18ac` | `NVT_SPI_DEF_X_SIZE 2136 / DEF_Y_SIZE 3200` (antes 1600x2136 del QRD) |
| F3.3 comentario desfasado dts | TACTIL F3 | **APLICADO** | `5702c18ac` | TODO del display actualizado: el driver ya está en el árbol y el nodo enchufado |

Artefactos generados (copiados a `build/bootimg/`, fuera de git, referenciados arriba en
SHA-BUENOS.txt):

```
e3756f6185dec2a1198abdb795478bf9e447ed24af66bb54441032d5440aa932  bootimg/Image-fix528-palawan      (39889408 B)
021641839028ac39d432c200cc3e6b5647775486eb8a2a144a44ad84c292c3a4  bootimg/Image-fix528-palawan.gz  (15389639 B)
2bdc506633a0877339be591cffbf8ae7bc20f5a36fdef486a23808ca1643d642  bootimg/xiaomi-uke-fix528.dtb    (91884 B)
```

DTB: compila sin warnings nuevos (log dtbs limpio); verificado con fdtget/dtc sobre el
decompile (§1). **Sin DTBO nuevo**: esta ronda no toca overlays (mkdtbo-s26X no re-ejecutado,
según la orden); el dtbo vigente (s262 en dtbo_a/b) no cambia.

Config versionada: `build/kernel-config/fix528-build-uke.config` (snapshot del .config final
de build-uke; incluye los 5 toggles + IRIS off).

## 2. Pendientes P2/P3 (FUERA de esta ronda, según los informes)

- **ACD de la GPU** (GPU F3): mantener `qmp acd val:0` durante el bring-up; receta completa
  con la tabla `qcom,opp-acd-level` del DT vivo ya documentada en REV-GPU-DISPLAY §F3.
  Gate: solo tras caída del muro CM3 + soak verde.
- **DFPS / modos de panel** (GPU F5): exponer 60/90/50/48/30/144 Hz del o82 (3 timings +
  switch de timing HS); hoy `num_modes = 1` (120 Hz).
- **Lápiz NT36532 fase 2** (TACTIL F5): handlers de pen del frame de 5176 B (targets
  M80p/P81c) tras cerrar el triaje del layout de dedo.
- **Vibrador** (ENERGIA F7/RADIO): `qcom,qpnp-vibrator-ldo` (pm7550ba @0xdf00, 3.0 V) —
  driver propio o port downstream (~100-150 líneas).
- **Sensores SSC** (RADIO §6): LSM6DSO/QMC630x/STK3BCX/SX937x cuelgan del I2C del ADSP;
  requeriría stack SSC completo (fastrpc + sensor_pd + HAL). Postergado.
- **Audio** (RADIO §7, P1): nodo `sound` + soundwire rx/tx/va + wcd939x-sdw + lpasscc
  cliffs + UCM derivado de mixer_paths. El esqueleto mainline ya está en palawan.dtsi.
- **Cámaras** (RADIO §7, P2): tablas cliffs para camss (csid-gen3/csiphy/vfe) — proyecto
  en sí mismo.
- **vadc skin-therm** (ENERGIA F6, P2): portar `vadc@9000` de pmk8550 + canales NTC +
  adc-tm5; sin eso no hay mitigación de carga por temperatura de chasis.
- **Driver `qti_battery_charger`** (KCONFIG gap 1): `drivers/power/supply/qcom/` NO existe
  en el árbol; la carga mainline va por `qcom_battmgr` (activado en D5), así que este port
  solo sería necesario si se quiere la clase Xiaomi `xiaomi_charge`.
- **Chipid Adreno732 en catálogo** (KCONFIG gap 2): confirmar 0x43030b00 al arrancar DRM_MSM
  (bring-up ya instrumentado, ecbf7efd7).
- **Retimer USBSS WCD939x** (KCONFIG #5 opcional): `TYPEC_MUX_WCD939X_USBSS=m` + nodo DT
  cuando se quiera SS/DP fiable por el redriver.
- **FW radio a empaquetar** (RADIO §8): W1-W4 (`qca6750/wpss.mdt+bXX`, board-2.bin de
  linux-firmware) y B1-B2 (`qca/msbtfw11.mbn`, `msnv11.bin` — ya en el host); A1-A2
  (adsp/adsp_dtb — verificar en rootfs). NO extraídos en esta ronda (el NON-HLOS.bin no se
  abrió, según la prohibición de tocar nada del dispositivo).

## 3. Avisos y riesgos para el próximo boot de Arch

1. **El rootfs v7 (rootfs-uke-k521.img) NO lleva el fw de la GPU** (no existe
   `/usr/lib/firmware/qcom` en la imagen ni `uke-gpu-firmware` en el pacman local db,
   verificado con debugfs RO). Este kernel de build-uke tiene `INITRAMFS_SOURCE=""`
   (los K-series lo llevaban embebido con los 3 blobs). **Antes de flashear este Image**:
   instalar `uke-gpu-firmware` en el rootfs (el pkg ya instala `qcom/uke/gen71100_zap.mbn`)
   o hornear el cpio K22/K34 con INITRAMFS_SOURCE. Si no, el primer boot se queda sin GPU
   por fw ausente (no es un muro, es falta de blobs).
2. **Gate G3-1 (F2)**: leer `gcc_gpll0` real en el próximo boot (debugfs clk_summary);
   esperado 1200 MHz → `UKE-CM3DBG hub=200000000`. Si el ABL diera otro rate, el pre_div
   correcto es gpll0/200 (el print lo delata).
3. **ADSP es arranque manual** (`auto_boot=false` en cliffs-adsp): no rompe el boot si
   falla; para carga, mantener el orden `pd_mapper → PAS → glink → qrtr → pmic_glink →
   battmgr` y luego `echo start > state` (ENERGIA F4: la unidad systemd aún hay que
   habilitarla en el rootfs).
4. **Táctil**: espera panel alimentado (TDDI). Si EDGE_FALLING no reporta eventos, probar
   `IRQ_TYPE_EDGE_RISING` (1 línea en el DT). Triaje de `point_layout` con evtest
   (parámetro de módulo ya expuesto).
5. **BT/WiFi**: faltan los blobs `qca6750/wpss.*` en el rootfs (RADIO §8 W1/W2); el BT
   usará los `msbtfw11/msnv11` del host si se copian. Primera prueba con hub alimentado
   si se prueba host mode (VBUS depende del ADSP).
6. **IRIS off**: no hay decodificador de vídeo HW en este kernel hasta que se arregle
   `iris_platform_palawan.h` (rotura preexistente); VENUS sigue =m si se necesita.
7. **El par vigente en la tablet NO cambia**: nada flasheado; boot_a=K49-esd-plyoff,
   dtbo_a=s266, userdata v7 siguen siendo la dorada (SHA-BUENOS §PAR).

## 4. Traza rápida

- Commits kernel (`uke-fixes-20261005`, base s150-postclk): `603b37730` (F2), `5702c18ac`
  (DT + defaults táctil), `760160d41` (pd_mapper). `git status` tras los commits: solo los
  5 WIP previos, intactos.
- Omarchy-uke: SHA-BUENOS.txt (append), `kernel-config/fix528-build-uke.config` (nuevo),
  este informe. Commit: "aplicar fixes #528 (sin flashear)".
- Logs: `build/logs/build-fix528-20261005.log` (build completo, EXIT=0).
