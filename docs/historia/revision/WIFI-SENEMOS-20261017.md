# WIFI-SENEMOS-20261017 — WiFi (WCN6750 / ath11k AHB vía WPSS) sobre el kernel senemos 7.2.9

Fecha: 17-oct-2026 · Alcance: **solo análisis estático + preparación de ficheros en el PC**. No se ha usado
adb/fastboot/ssh, no se ha flasheado, no se ha ejecutado `deploy.sh` ni nada en la tablet.
Fuentes leídas: `docs/guias/RE-NOCTURNO-HALLAZGOS-20261017.md §3.6`, `docs/historia/revision/PERIF-WIFI-20261017.md`, árbol
`build/kernel-pokes/senemos-7.2.9/linux-7.2.9` + `senemos-build/.config` (solo lectura), parches 0014-0016 y tests del
repo de referencia `/tmp/claude-1000/ext-senemos` (solo lectura, nada ejecutado), capturas Android
(`build/android/{cosecha,sistema,coldboot}-20261017`), imagen `build/rootfs/rootfs-uke-l76-8g.img` (debugfs de solo lectura).

Entregable: `build/rootfs/deploy/wifi/` (ver §7).

## 1. Hallazgos que cambian el plan anterior (todos medidos)

1. **`board.bin` debe ser `bd_o82gl.elf` ENTERO (ELF), no el payload crudo `da424c03` del payload v2.**
   En el árbol senemos `ath11k_qmi_load_bdf_qmi` (`qmi.c:2440-2472`): BDF que empieza por `\x7fELF` → `BDF_TYPE_ELF` (=1) y
   **salta el caldata**; BDF crudo (`BDF_TYPE_BIN`) → exige `cal-ahb-<dev>.bin` o `caldata.bin` y aborta con `-ENOENT`.
   El poke local que perdonaba la falta de caldata (k52-L16) **no está en el kernel senemos** (stock 7.2.9 + 44 parches).
   Apoyos: (a) `board-2.bin` de linux-firmware para WCN6750 (parseado: 11 entradas `bus=ahb,qmi-chip-id=1,qmi-board-id=…`)
   lleva las 11 placas como **ELF** (≈59900 B) y los 11 regdb como BIN; (b) el icnss2 de Android carga
   `qca6750/bd_o82gl.elf` y `regdb_xiaomi.bin` (kmsg 6,31-6,35 s). Hay 59928 B < `board_size` 256 KiB.
   → El payload v2 (`2b0dd75a…`) queda superado en esto: su `board.bin` (BIN) fallaría en caldata.
2. **La imagen `rootfs-uke-l76-8g.img` lleva un `wpss.b08` CORRUPTO**: 266 668 B, sha `ba3c1b48…`; el `.mdt` declara
   `p_filesz=275 644` y el Android vivo tiene `0de7c47d…` (275 644 B). Verificado con la tabla de hashes de `b12`
   (SHA-384 por segmento): la imagen da `YYYYYYYYnYY` (falla el seg. 8); el set del PC da todo OK. El mismo b08 malo está en
   `build/pkg/uke-fw-radio/uke-fw-radio-1-1-any.pkg.tar.zst` (el paquete del 5-oct es anterior a los fuentes del PC).
   El TZ habría rechazado la autenticación del WPSS. Los otros 13 ficheros de la imagen sí coinciden.
3. **La imagen tiene `ath11k/WCN6750/hw1.0/board-2.bin` (927 980 B, linux-firmware)**: ath11k prueba api-2 ANTES que
   `board.bin`. Si el `qmi-board-id` de la tablet coincide con alguna de las 11 entradas (ids 1-7, 9, 10, 255) cargaría
   calibración ajena. `deploy.sh` lo aparta a `board-2.bin.stock-linux-firmware` (y `uke-wifi-up.sh` aborta si sigue ahí).
4. **El rootfs NO tiene módulos para este kernel**: `/usr/lib/modules` solo contiene `7.2.0-rc2-palawan+`; el kernel es
   `7.2.9-senemos.1.4054.3-ouke1` y `build-senemos.sh` dice «Módulos NO». Los `.ko` del payload v2 (7.2.0-rc2-palawan) no
   cargan. **Bloqueante**: hace falta el `modroot` del build v2 + `depmod -a`.
5. **"Startup manual" del WPSS**: `cliffs_wpss_resource.auto_boot=false` solo significa que el remoteproc no arranca al
   registrarse. El arranque real lo hace **`ath11k_ahb_power_up()`** (`ahb.c:443`, llamado desde `ath11k_core_soc_create`
   `core.c:2006` durante el probe): `regulator_enable` de `vdd-cx-mx` (smpb3) → `vdd-1.8-xo` (smpb1) → `vdd-1.3-rfa`
   (smpb2) y **después** `rproc_boot(wpss)`. **No hay que hacer `echo start > …/state`**: un start manual previo levantaría
   el WPSS con las rails RF apagadas y `rproc_boot` posterior solo subiría el contador. En Android lo hace
   `init.vendor.wlan.rc` (kmsg: 5,731 s «powering up wpss», 6,07 QMI connected, 6,33 BDF, 6,36 «WLAN FW Initialization
   done») porque su icnss2 no llama a `rproc_boot`. El rproc se llama `wpss` (`sysmon_name`).
6. **Set WPSS a usar = el del vendor VIVO** (`mdt b3451c51…`, `b12 a1f14ed3…`; 13 ficheros, sin b11: `filesz=0`),
   idéntico sha a sha al `firmware-sha.txt` del Android vivo y a `build/pkg/uke-fw-radio/wpss.*`. El set v1 del payload
   (`mdt e2d14e4f…`, `b12 54c223d5…`) también es coherente (SHA-384) pero difiere en 100 B de la cadena de certificados; no se
   mezcla (siempre set completo). `wpss.qdb` no lo pide el flujo mainline (ya está en la imagen, no se toca).

## 2. Firmware: nombres exactos que pedirá el kernel y de dónde sale

Rutas (relativas a `/usr/lib/firmware`; `/lib` → `usr/lib`):

| Quién pide | Fichero | Fuente (PC) | sha256 | Notas |
|---|---|---|---|---|
| ath11k (api-2) | `ath11k/WCN6750/hw1.0/board-2.bin` | — | — | **No debe existir** (ENOENT ×3 esperado) |
| ath11k (api-1) | `…/hw1.0/board.bin` | `build/android/bd_o82gl.elf` | `dc4a4640 0832e730 f3aa6adf 0137931f 1d450e54 3279fffa e977bd86 046ad300` | == `/vendor/firmware_mnt/image/qca6750/bd_o82gl.elf` vivo; ELF 59 928 B |
| ath11k (regdb) | `…/hw1.0/regdb.bin` | `build/android/regdb_xiaomi.bin` | `fca5bbfa f5a9d490 d9214ac6 397fe7c4 2412af33 f8f600dd e518639376255c3f` | == `qca6750/regdb_xiaomi.bin` vivo (el que pide icnss2); fallo no fatal |
| remoteproc PAS 6 | `qca6750/wpss.mdt` + `wpss.b00…b10`, `wpss.b12` | `build/pkg/uke-fw-radio/wpss.*` | ver `uke-wifi-fw.sha256` | == Android vivo (13/13); `firmware-name` del DT |
| (no se piden) | `amss.bin`, `m3.bin` | — | — | AHB: `amss.bin` solo MHI/PCI; `m3_fw_support=false` (core.c:642) |

Procedencia independiente: la partición `modem` (NON-HLOS) **no está** en `backup-par-bueno/android-20261017` (solo
`modemst1/2`, `fsg`, `fsc`, `persist`); el origen es la ROM OS3.0.303.0 extraída (`uke-fw-radio`) y la verificación es contra el
`sha256sum` del Android vivo (`sistema-20261017/firmware-sha.txt`). BT (`msbtfw12.mbn`/`msnv12.bin`) queda fuera de este frente.
Dato opcional: `persist.img:/wlan/wlan_mac.bin` (19 B, formato `wlan0=<MAC12>`) es la MAC de fábrica; no se aplica ni se copia al repo.

## 3. Kernel: módulos y config (`senemos-build/.config`, 17-oct)

| Pieza | Config | Estado en `.config` |
|---|---|---|
| ath11k / AHB | `ATH11K=m`, `ATH11K_AHB=m` (`ATH11K_PCI=m` sobra) | OK |
| WPSS PAS | `QCOM_Q6V5_PAS=m` (+ `Q6V5_COMMON=m`, `PIL_INFO=m`, `RPROC_COMMON=m`, `SYSMON=m`) | OK |
| Transporte QMI | `QRTR=m`, `QRTR_SMD=m`, `QCOM_QMI_HELPERS=m`, `RPMSG_QCOM_GLINK_SMEM=m`, `RPMSG_QCOM_GLINK=y` | OK (`qrtr_smd` para el canal `IPCRTR` del WPSS; parche 0018) |
| Dependencias PAS | `QCOM_AOSS_QMP=y` (QMP obligatorio del 0014), `QCOM_MDT_LOADER=y`, `QCOM_SCM=y`, `QCOM_SMEM/SMP2P=y`, `REMOTEPROC=y` | OK |
| Rails/SMMU | `REGULATOR_QCOM_RPMH_UKE=y`, `QCOM_RPMH_UKE=y`, `ARM_SMMU_QCOM=y` (SMR 0x1400/mask 1, parche 0015) | OK |
| 802.11 | `CFG80211=m`, `MAC80211=m`, `CRYPTO_CCM/GCM=m`, `CRYPTO_CMAC=y`, `CRYPTO_LIB_ARC4=m` | OK |
| Firmware | `FW_LOADER=y`, `FW_LOADER_COMPRESS` **no** (el firmware va sin comprimir), `USER_HELPER_FALLBACK` no | OK (sin retardos de 60 s) |
| Pwrseq | `POWER_SEQUENCING_QCOM_WCN=m` | No interviene en esta vía (0015 usa las 3 rails directas) |

**Obligatorios que faltan: ninguno de config.** Sí falta el **conjunto de `.ko`** (v2). Cierre mínimo a instalar (lo calcula
`deploy.sh --modules` con el `modules.dep` del v2): `ath11k_ahb ath11k ath(ath_common) qcom_qmi_helpers qrtr qrtr_smd
qcom_q6v5_pas qcom_q6v5 qcom_pil_info qcom_common qcom_sysmon qcom_glink_smem cfg80211 mac80211 rfkill libarc4` (+ lo que
añada el `modules.dep`).

**Requisitos recomendados para el kernel v2 (los escribe el otro agente, no se tocan aquí):**
- `CONFIG_ATH11K_DEBUG=y` (bool, depende solo de `ATH11K`): sin él `ath11k_dbg()` es un stub y **no salen** los marcadores
  `using board api`, `bdf_type`, `fetched regdb` (el parámetro `debug_mask` existe pero no imprime). Opcional:
  `ATH11K_TRACING=y` (EVENT_TRACING ya está) y `MAC80211_DEBUGFS`+`ATH11K_DEBUGFS`.
- Mantener `QCOM_Q6V5_PAS`, `QRTR_SMD`, `ATH11K_AHB` como **módulos** (o built-in, el guion detecta ambos), pero no quitarlos.

## 4. Secuencia de arranque implementada (`/usr/local/sbin/uke-wifi-up.sh`)

1. **Preflight sin efectos** (código 4 si falla): DT vivo (`/soc/qcom,wcn6750` con compatible `xiaomi,uke-wcn6750-wifi` y
   `status=okay`; `/soc/remoteproc-wpss@9bb00000` = `qcom,cliffs-wpss-pas`), `modules.dep` de `uname -r`, módulos
   encontrables, **`sha256sum -c` de los 15 ficheros** (detecta el b08 malo) y ausencia de `board-2.bin`.
2. `modprobe cfg80211 mac80211 qrtr qrtr_smd qcom_q6v5_pas` → aparece `remoteproc` `wpss` en `offline`.
   (Ojo: cargar PAS hace que el ADSP arranque solo — parche uke en `qcom_q6v5_pas.c:890-893`; si PAS ya cargó en el boot, no pasa nada nuevo.)
3. **`sync`** y `modprobe ath11k debug_mask=0x261` + `modprobe ath11k_ahb` (con `timeout`): probe → rails RF → `rproc_boot`.
   La blacklist de `ath11k*` **se queda** (solo bloquea alias; el modprobe por nombre funciona; REGLAS §1.9).
4. Espera hasta 90 s a `phy` + netdev cuyo `device` sea `17110040.qcom,wcn6750`. Veredictos: **VERDE** (0), **AMARILLO**
   (2: WPSS running, sin phy → QMI/BDF), **ROJO** (3: WPSS no running → PAS/TZ/rails). Vuelca dmesg filtrado,
   `devices_deferred` y regulator_summary a `/var/log/uke-wifi*.{log,txt}` + kmsg.
5. Red (solo si VERDE): `wpa_supplicant-nl80211@wlan0` (arrancado por el guion cuando la interfaz ya existe) + `systemd-networkd`
   (`20-uke-wlan.network`, DHCP). Sin red configurada → solo `wpa_cli scan_results` (equivale al `iw scan` del gate; **`iw` no está en el rootfs**).
- Opciones: `--status` (sin tocar módulos ni hardware; solo escribe el log), `--down` (para wpa, `modprobe -r` ⇒ `rproc_shutdown` + rails off), `--no-net`.
- **Servicio `uke-wifi.service`**: armado de **un solo uso** (`ConditionPathExists=/var/lib/uke-wifi/armed`, borrado + sync antes de tocar
  nada); NO enabled por defecto → un wedge no se repite en cada arranque ni gasta reintentos de slot.

**Red del rootfs (medido con debugfs):** `systemd-networkd` + `resolved` habilitados, `10-uke-usb.network` (gadget estático
192.168.42.129, sin gateway); `wpa_supplicant` 2.12, `wpa_cli`, `nmcli`/`NetworkManager` instalados pero **NM no habilitado**
(habilitarlo se llevaría el gadget USB). Se eligió **networkd + wpa_supplicant-nl80211@wlan0** (consistente con lo que ya corre);
`10-uke-wlan.link` fija el nombre `wlan0`. No hay `iw`, `iwd` ni `wireless-regdb` (`regulatory.db` ausente: cfg80211 lo registrará
como fallo inocuo; ath11k usa regdom propio del firmware/`regdb.bin`; `CFG80211_REQUIRE_SIGNED_REGDB=y`).
Credenciales: nunca en el repo; `WIFI_SSID`/`WIFI_PSK` por entorno al ejecutar `deploy.sh --go` (PSK hasheada con `wpa_passphrase`).

## 5. Riesgos

| # | Riesgo | Mitigación |
|---|---|---|
| R1 | **Wedge/reset al arrancar el WPSS** (palawan: reset silencioso a ~7,33 s, 3/3, y `-EIO` de DMA). El kernel senemos cambia las 3 causas candidatas: votos proxy CX/MX (0014), SMR 0x1400/1 + rails en orden OEM (0015/0016). Según su README el rev 1.39 (mismos 44 parches, incluye 0014-0016) llegó a «Wi-Fi SSH» en Fedora; el README añade que el paquete 1.7 (previo a 0016) «no se probó físicamente» | primer test **manual** con sesión SSH persistente abierta, `sync` antes del disparo, marcador `UKE-WIFI-PROBE-BEGIN` en kmsg, servicio no enabled, armado de un solo uso. Si el WPSS cuelga, no reintentar un 4º ciclo (REGLAS §1.11) |
| R2 | Sin módulos senemos en el rootfs → no hay nada que cargar | `deploy.sh --modules` con el modroot v2 (comprueba vermagic) |
| R3 | SSH depende del gadget USB (el otro agente lo está recuperando) | deploy y test exigen SSH; tras VERDE habrá un 2º canal por WiFi |
| R4 | `board-2.bin` / pacman lo reinstala en una actualización | el guion lo detecta y aborta; hay que reaplicar `deploy.sh` |
| R5 | Sin `CONFIG_ATH11K_DEBUG` la evidencia se reduce a `chip_id/board_id`, `fw_version`, `wcn6750 hw1.0` y errores | pedirlo en el v2 (§3) |
| R6 | Regdom/6 GHz: sin `regulatory.db`; `country=ES` por defecto en wpa_supplicant (`WIFI_COUNTRY`) | verificar canales con `wpa_cli`; instalar `wireless-regdb`/`iw` cuando haya red |
| R7 | La regla §1.8 dice que el arranque «regenera `/etc`» | el rootfs v8 es ext4 persistente (uke-adsp.service ya vive en `/etc`), pero **comprobar tras el primer reboot** que `/etc/systemd/{system,network}` y la conf siguen |
| R8 | Calibración: BDF ELF `o82gl` es el que usa el Android vivo; board-id real aún desconocido | se lee en el 1er boot (`board_id 0x…` en dmesg); no se instala ningún board de terceros |
| R9 | `uke-adsp.service` (insmod de `.ko` palawan) fallará en el kernel senemos | ajeno a este frente; no se toca |

## 6. Pasos de prueba (a ejecutar cuando haya SSH + modroot v2; nada se ha ejecutado)

0. En el PC: `build/rootfs/deploy/wifi/deploy.sh` (sin `--go`: solo verifica shas y sintaxis, no abre conexión).
1. `deploy.sh --check` (solo lectura remota): kernel, `/usr/lib/modules`, sha del b08 (debe salir `0de7c47d…` tras desplegar), blacklist, `board-2.bin`.
2. `WIFI_SSID=… WIFI_PSK=… deploy.sh --go --modules` (sin `--arm`). Tras el primer reboot comprobar persistencia (R7).
3. Dos sesiones SSH abiertas (una con `dmesg -w > /root/wifi-dmesg.txt`). `uke-wifi-up.sh --status`.
4. **Etapa A**: `uke-wifi-up.sh --no-net`. Esperado (~3-8 s tras `modprobe ath11k_ahb`): `rproc wpss running`; dmesg:
   `remoteproc… powering up wpss`, `qcom_q6v5_pas… wpss`, `ath11k_ahb 17110040.qcom,wcn6750: chip_id 0x… board_id 0x…`,
   `fw_version 0x…`, `wcn6750 hw1.0`; con DEBUG: `using board api 1`, `bdf_type 1`, `fetched regdb`; `wlan0` + `phy0`.
5. **Etapa B**: `uke-wifi-up.sh` → `wpa_cli scan_results` > 0 redes → (con credenciales) `wpa_state=COMPLETED`, IPv4 por DHCP.
6. Criterio de éxito (como F3): uptime > 300 s sin reset, `ping` a la puerta de enlace, `ssh` por `wlan0`, `uke-wifi-up.sh --down` baja limpio y vuelve a subir.
7. Solo entonces `--arm` para probar el arranque automático (un intento).

Veredictos de fallo → siguiente acción: ROJO ⇒ `devices_deferred` + líneas `qcom_q6v5_pas` (¿AUTH_AND_RESET? ¿b08?); AMARILLO ⇒ líneas
`ath11k` de QMI (`failed to fetch board data`, `qmi failed to load CAL data file` = BDF no ELF, `failed to load regdb` es no fatal).

## 7. Inventario de `build/rootfs/deploy/wifi/`

```
deploy.sh                 tar|ssh (sin scp); SIN --go solo verifica; --check, --modules, --arm, --regen-manifest
modclosure.sh             cierre de dependencias de módulos desde modules.dep (probado con el modules.dep palawan)
MANIFEST.sha256           shas de todo root/
root/usr/lib/firmware/ath11k/WCN6750/hw1.0/{board.bin,regdb.bin}
root/usr/lib/firmware/qca6750/wpss.{mdt,b00..b10,b12}
root/usr/lib/firmware/uke-wifi-fw.sha256   (15 ficheros; `cd / && sha256sum -c`)
root/usr/local/sbin/uke-wifi-up.sh
root/etc/systemd/system/uke-wifi.service   (armado de un solo uso, no enabled)
root/etc/systemd/network/{10-uke-wlan.link,20-uke-wlan.network}
```
Comprobaciones hechas en el PC: los 15 shas == Android vivo; set WPSS coherente (SHA-384 de cada segmento ∈ tabla de `b12`);
`bash -n` de los tres scripts; el flujo `find|tar --null -T -` genera el archivo con propietario 0/0; `gen_wpa_conf` probado con valores
ficticios. **No** se ejecutó `deploy.sh` ni `uke-wifi-up.sh` (solo `--help`).
Pendiente tras el v2: instalar modroot, config `ATH11K_DEBUG=y`, primer test físico, `wireless-regdb`/`iw` por pacman cuando haya red.
