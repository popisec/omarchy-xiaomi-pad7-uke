# STAGING-FW #529 — firmwares radio+ADSP al staging, batería cerrada, vadc NTCs (2026-10-05)

Staging agent #529. Ejecuta los 3 PREPARABLE-OFFLINE de REV-PENDIENTES (§12 fw radio,
§13 batería, §4 vadc) sobre el árbol del port. 100% offline en el PC: cero adb/fastboot,
tablet intacta. NON-HLOS.bin extraído del tgz con 7z SIN montar (resultó ser FAT16, no
ext4/sparse como decía RADIO §8 — nota de corrección abajo).

## 1. Firmwares radio → staging del rootfs (pend. 12, W1–W4/B1–B2 + A1/A2 + cdsp)

**Origen Android**: `ROM-OS3.0.303.0.WOZEUXM.tgz` (7,7 GB) → miembro
`uke_eea_global_images_OS3.0.303.0.WOZEUXM_16.0/images/NON-HLOS.bin` (174.469.120 B).
`file`: **imagen FAT16** (sectors 51712×4096 = 211.812.352 B declarados; el tgz trae el
fichero truncado a 174 MB — la cola que falta es FREE SPACE del FAT, los 614 ficheros
del listado están íntegros). Extracción con `7z x` (sin loop ni sudo): 90 ficheros
pedidos, **90/90 con tamaño exacto** contra el directorio del FAT. sha256 del
NON-HLOS.bin (re-extraíble del tgz cuando haga falta): en SHA-BUENOS.txt. /var/tmp
limpio tras copiar (disco al 98%).

**Origen host**: linux-firmware de Arch trae estos blobs `.zst`; el kernel del port NO
tiene `CONFIG_FW_LOADER_COMPRESS` → descomprimidos con `zstd -d` al empaquetar.

### Copiado a `build/rootfs/staging/usr/lib/firmware/` (95 ficheros, ~36 MB nuevos)

| Bloque | Ficheros | Tamaño | Origen |
|---|---|---|---|
| `qca6750/` W1–W3 | `wpss.mdt` (4.844 B, casa con el dmesg vivo "size 4844") + `wpss.b00..b10,b12` (**12 seg, SIN b11** — así está en la ROM) + `wpss.qdb` | 7,9 MB | NON-HLOS image/qca6750 |
| raíz A1/A2 | `adsp.mdt` (8.044 B) + `adsp.b??` (**51 seg: sin b24/b51**) + `adsp_dtb.mdt` (4.044 B) + `adsp_dtb.b00..b02` | 25 MB | NON-HLOS image/adsp* |
| raíz A3 | `cdsp.mdt` (5.084 B) + `cdsp.b??` (**15 seg: sin b14**) + `cdsp_dtb.mdt` + `.b00..b02` | 3,3 MB | NON-HLOS image/cdsp* (opcional, peso ridículo: entra) |
| `qca/` B1/B2 | `msbtfw11.mbn` (202.508), `msnv11.bin`, `msnv11.b09`, `msnv11.b0a` | ~221 KB | host `.zst` descomprimido |
| `ath11k/WCN6750/hw1.0/` W4 | `board-2.bin` (927.980) | 0,9 MB | host `board-2.bin.zst` descomprimido |

Notas:
- El staging YA traía `qca/msbtfw11*` + `msnv11*` + `board-2.bin` (de una ronda
  anterior): **shas verificados idénticos** a los .zst del host descomprimidos hoy
  (linux-firmware misma fuente) — no se duplicó nada.
- `wpss.mdt` de linux-firmware (symlink a `sc7280/wpss.mbn`, SIN .bXX) NO sirve para
  `qcom_q6v5_pas` → NO se instala; el wpss va por `qca6750/` (firmware-name del DT).
- Descartados a conciencia: `adsp2*` (segunda instancia ADSP, 24,5 MB, sin nodo en el
  port), `*.jsn` (registry JSON vendor), `regdb_xiaomi.bin`/`bd_o82gl.elf`/`wlan_mac.bin`
  (formato vendor, ath11k no los consume), mss (modem disabled).
- **Peso**: staging 1,2 GB → 1,3 GB (+36 MB). Impacto en userdata v7 (4 GB): ~1%.
  Disco del PC: 24 GB libres (98% usado — limpiar antes de hornear, no por esto).

### Package `uke-fw-radio` (build/pkg/uke-fw-radio/)

- `PKGBUILD` (makepkg verificado) + 95 fuentes planas + **uke-fw-radio-1-1-any.pkg.tar.zst**
  (19.300.434 B, sha en SHA-BUENOS.txt). Gate offline de rutas OK: tar contiene
  `usr/lib/firmware/qca6750/wpss.mdt`, `usr/lib/firmware/adsp.mdt`,
  `usr/lib/firmware/qca/msbtfw11.mbn`, `usr/lib/firmware/ath11k/WCN6750/hw1.0/board-2.bin`.
- **staging == package verificado 1:1** (diff de listados: 95 == 95).
- shas de los 95 ficheros + package: sección nueva al final de `build/gates/SHA-BUENOS.txt`.

## 2. Batería (pend. 13)

- `build/gates/prepara/uke-adsp-load.sh` (ya estaba en el repo, corregido hoy):
  - ORDEN alineado a **REV-ENERGIA F4**: `qcom_sysmon → qcom_common → qcom_pil_info →
    qcom_q6v5 → qcom_glink_smem → qcom_q6v5_pas → qrtr_smd → qcom_pd_mapper →
    pmic_glink → qcom_battmgr`, y `echo start` al remoteproc del ADSP **AL FINAL**
    (antes arrancaba el ADSP antes del pd_mapper: primera petición de PDR perdida).
  - `qcom_sysmon` AÑADIDO (faltaba): `strings qcom_q6v5_pas.ko | grep ^depends=` = 
    `qcom_q6v5,qcom_common,qcom_sysmon,qcom_pil_info` — sin él el insmod del pas falla.
  - `pmic_glink` y `qcom_battmgr` son **built-in (=y) desde fix528**: el script los
    detecta (`/sys/module/` o sin .ko) y no los marca como fallo.
  - Instalado en el staging: `usr/local/bin/uke-adsp-load.sh` (0755) +
    `etc/systemd/system/uke-adsp.service` + enable
    (`multi-user.target.wants/uke-adsp.service` → `../uke-adsp.service`).
  - NO ejecutado (regla).
- **.ko obsoletos del staging corregidos**: `usr/lib/modules/7.2.0-rc2-palawan+/extra/`
  tenía solo 5 .ko sueltos de una ronda vieja y `qcom_pd_mapper.ko` SIN el fix
  `qcom,lamma` (0 ocurrencias) — habría roto el PDR charger_pd. Refrescados con los del
  build fix528 (5-oct 22:23): `qcom_pd_mapper.ko` (ahora con `qcom,lamma`), `ath11k.ko`,
  `ath11k_ahb.ko`, `ath11k_pci.ko`; **eliminado `qcom_battmgr.ko`** (el módulo ya no
  existe: es =y). Índices de módulos del staging corregidos (ver §4.5).

## 3. vadc NTCs (pend. 4) — DT + módulo nuevo

- `xiaomi-uke.dts` (rama `uke-fixes-20261005`): `&pmk8550 { vadc@9000 }` compatible
  **`qcom,spmi-adc5-gen3`** (driver del fork `qcom-spmi-adc5-gen3.c`; el patrón
  ADC_TM5 clásico NO aplica: en gen3 no hay periférico `adc_tm@3400`, el TM va
  embebido por canal — confirmado en el DT vivo, que no tiene nodo adc_tm).
- **24 canales** copiados 1:1 del vivo (reg virtual = sid<<8|ch, label, hw-settle 200,
  pre-scaling, ratiometric; `qcom,adc-tm` donde el vivo trae `adc-tm-type=<1>`, 10 NTCs:
  xo/quiet/ap/conn2/display/flash/charger/conn/wifi/backlight_therm; `batt_therm` sin
  tm, como el vivo — la temp de celda la trae el ADSP).
- **3 canales del vivo OMITIDOS a conciencia**: `pm7550ba chg_temp (0x10)`,
  `iin_fb (0x17)`, `ichg_fb (0xa1)` — sin entrada en `adc5_gen3_chans_pmic[]` del fork
  (el probe abortaría con "Channel ... not supported"); telemetría del cargador que
  gestiona el ADSP.
- `.config`: `CONFIG_QCOM_SPMI_ADC5_GEN3=m` añadido (los `ADC5`/`ADC_TM5` =m viejos
  quedan, no molestan). Snapshot: `build/kernel-config/fix529-build-uke.config`.
- **DTB nuevo**: `build/bootimg/xiaomi-uke-fix529.dtb` (94.708 B; fix528 era 91.884).
  Verificado con fdtget: compatible/reg 0x9000+0x9100/#thermal-sensor-cells=1/24
  channel@*/label de quiet_therm/adc-tm en @147 y ausente en @744. sha en SHA-BUENOS.txt.
- **TM gen3 = gap conocido**: el aux `adc5_tm_gen3` que crea el driver no tiene driver
  en este árbol → las thermal zones de los NTC NO existen aún (los canales IIO sí serán
  legibles en /sys/bus/iio). Portar ese driver es cambio C, fuera de este paso.
- Módulo nuevo `qcom-spmi-adc5-gen3.ko` compilado (make modules) y copiado al staging
  (`extra/`) + depmod regenerado.

## 4. Incidencias del paso (para el historial)

1. NON-HLOS.bin es **FAT16 truncado a la parte ocupada** (no ext4 como decía RADIO §8):
   extraer SIEMPRE con 7z y verificar tamaños contra el listado, no montar.
2. `make olddefconfig` sin `ARCH=arm64` aplicó la vista x86 y **podó el .config**
   (2507 vs 3039 líneas). Recuperado desde `build/kernel-config/fix528-build-uke.config`
   + re-aplicado el cambio con ARCH correcto. Verificado: ARCH_QCOM/Q6V5_PAS/BATTMGR/
   panel/novatek intactos. Lección: SIEMPRE `ARCH=arm64` (como hace build-k23b.sh).
3. El build de módulos recompiló los 846 .ko (efecto del restore del .config). El
   `Image`/`Image.gz` NO se ha recompilado (los de fix528 siguen válidos); el DTB sí
   es nuevo (era el objetivo). Los 4 .ko refrescados en staging resultaron
   **byte-idénticos** tras recompilar (cmp verificado).
4. modpost falló la primera vez por un `uvc.o` residual de un build viejo
   (`drivers/media/common/`): resuelto borrando ese dir de build-uke y recompilando
   (EXIT=0, 847 .ko).
5. `depmod` del host ROTO en esta sesión (kmod sale 1 sin diagnóstico incluso en un
   árbol mínimo): `modules.dep`/`modules.alias` del staging corregidos A MANO (fuera el
   fantasma `qcom_battmgr.ko`; dentro `qcom-vadc-common.ko` + `qcom-spmi-adc5-gen3.ko`
   con su alias of). El `modules_install`+depmod reales al hornear reescriben todo.
6. **Correcciones al informe RADIO §8**: NON-HLOS.bin es FAT16 (no ext4); adsp trae
   51 segmentos (sin b24/b51), no "b00…b52" contiguo; cdsp sin b14; wpss.qdb existe
   (W3 sí disponible).

## 5. Lo que queda para el boot de validación (en orden de lectura, REV-PENDIENTES)

1. **Sudo del dueño (ventana PC)**: instalar `uke-gpu-firmware` + `uke-fw-radio` en el
   rootfs k521 (pacman -U o cp del staging) y **make modules_install** al rootfs (el
   staging solo lleva 6 .ko en extra/; hacen falta los 847 + modules.builtin/order para
   que depmod regenere índices de verdad).
2. Hornear userdata con ese rootfs; boot con `UKE-CM3DBG hub=200000000`.
3. **Batería**: `systemctl status uke-adsp` (enable ya en el staging) → dmesg SIN
   "PDM: no support" y CON "PDR: Indication received from msm/adsp/charger_pd,
   state: 0x1fffffff" → `/sys/class/power_supply/battery` (con cable: status=Charging,
   current_now negativo).
4. **WiFi/BT**: `Booting fw image qca6750/wpss.mdt, size 4844` → wlan0;
   `bluetoothctl list` (fw qca/msbtfw11.mbn+msnv11.bin ya planos en el rootfs).
5. **vadc**: `cat /sys/bus/iio/devices/iio:device*/label` → 24 labels del vivo.
   (Las thermal zones NTC siguen pendientes del driver TM gen3.)
6. Táctil/GPU según el plan de REV-PENDIENTES (sin cambios de este paso).

## 6. Evidence / trazabilidad

- Los `.ko` vendor de CAPTURA-GAPS siguen dentro de evidencia
  (`build/evidencia/android-full-gaps/h9-modules/topull/` + copia en `extracted-gaps/`):
  no había nada que mover.
- `NON-HLOS.bin` borrado de /var/tmp tras copiar (re-extraíble del tgz; sha anotado).
- Commits: palawan-linux "DT vadc NTCs (#529)"; omarchy-uke "staging fw radio+adsp (#529)".
