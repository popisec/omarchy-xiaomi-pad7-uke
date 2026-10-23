# CARGA-SENEMOS — carga de batería con el kernel MCC45TR (ouke2) y nuestro rootfs

> 17-oct-2026, noche. **Solo PC**: sin adb/fastboot/ssh, sin flash, sin commit. Nada de lo suyo se ejecutó
> (`/tmp/claude-1000/ext-senemos` solo lectura). Árbol leído: `build/kernel-pokes/senemos-7.2.9/linux-7.2.9`
> (parches 0001–0044 aplicados). No se tocó el kernel. Entregable: `build/rootfs/deploy/carga/`
> (`deploy.sh` **NO ejecutado**). Sustituye a `charge/uke-adsp-load.sh` + `uke-adsp.service` para este kernel.

## 0. Resumen

- **La carga funciona con `.ko` de SU build (`modroot` ouke2, ya generado), no con los palawan** (vermagic distinto).
- **Hallazgo que corrige el encargo: el ADSP NO queda "manual".** `0020`/`0026` dicen *startup stays manual*, pero **`0033`**
  pone `auto_boot = true` + `recovery_disabled = true` para `xiaomi,uke` + `qcom,cliffs-adsp-pas`
  (`drivers/remoteproc/qcom_q6v5_pas.c:890-894`). **Cargar `qcom_q6v5_pas` arranca el ADSP solo** (asíncrono). Consecuencias:
  firmware verificado **antes** del modprobe, `qcom_q6v5_pas` el **último**, autoload por udev bloqueado
  (`modules.alias` de ouke2 trae `of:…Cqcom,cliffs-adsp-pas → qcom_q6v5_pas`), y se **espera** en vez de `echo start`
  (solo queda un `echo start` de respaldo). El WiFi (WPSS) usa el mismo módulo: su servicio debe ir `After=uke-carga.service`.
- Servicio nuevo `uke-carga.service` (condicionado a `*senemos*`) + drop-in que apaga el `uke-adsp.service` viejo en ese kernel
  (sigue activo en los palawan). 36/36 casos offline pasan; `systemd-analyze verify` OK; pre-vuelo OK contra el modroot ouke2 real.
- Cableado de verdad **sin verificar en tablet**: todo es lectura de código/DT + simulación en el PC.

## 1. Cómo carga su kernel (medido en `senemos-build/.config` ouke2 y en el árbol)

| Pieza | Config | Qué hace / evidencia |
|---|---|---|
| ADSP PAS | `QCOM_Q6V5_PAS=m` (+`QCOM_PIL_INFO`,`RPROC_COMMON`,`Q6V5_COMMON`,`SYSMON`=m) | `cliffs_adsp_resource` (0020): `adsp.mdt` + `adsp_dtb.mdt`, `pas_id 1`, `dtb_pas_id 0x24`, CX/MX TURBO, AOP `load_state "adsp"`. El DT final **no** trae `firmware-name` ⇒ defaults. `qcom_q6v5_pas.c:866-874` |
| GLINK/QRTR | `RPMSG_QCOM_GLINK=y`, `RPMSG_QCOM_GLINK_SMEM=m`, `QRTR=m`, `QRTR_SMD=m` | `qrtr_smd` se autocarga por `rpmsg:IPCRTR`; `qrtr` NO es dep de pas ⇒ precarga explícita (0035: *"initramfs must preload QRTR transport"*) |
| pd-mapper | `QCOM_PD_MAPPER=m` (+`PDR_HELPERS`,`PDR_MSG`,`QMI_HELPERS`=m) | Es driver **auxiliary** (`qcom_common.pd-mapper`); el aux-device lo crea `qcom_common` al *preparar* el ADSP ⇒ el módulo debe estar **antes**. 0028: `uke_domains` por `xiaomi,uke` (adspr/adsps/adspua/charger_pd/cdspr). 0035: `MODULE_SOFTDEP("pre: qcom_pd_mapper")` en `qcom_common.c:632` (confirmado en `modules.softdep`) |
| pmic_glink | `QCOM_PMIC_GLINK=m` | 0032: `xiaomi,uke-pmic-glink` = **battery-only** (`client_mask` solo BATT; PDR `tms/servreg` `msm/adsp/charger_pd`). El nodo raíz `/pmic-glink` lo crea el overlay USB; el OEM `qcom,pmic_glink` queda `disabled`. **Sin UCSI/altmode ⇒ NO se carga `ucsi_glink`** (el insmod viejo daba Oops) |
| battmgr | `BATTERY_QCOM_BATTMGR=m` | 0031/0033/0035: variante `QCOM_BATTMGR_UKE` por `of_machine_is_compatible("xiaomi,uke")` (IDs de propiedad +1 desde `BATT_TEMP`, mAh→µAh, **corriente con signo invertido**), USB SDP ≤500 mA con reintentos (0044). Psy: `qcom-battmgr-bat/-usb/-wls` |
| Auto-arranque | `qcom_q6v5_pas.c:890-894` (0033) | `auto_boot=true`, `recovery_disabled=true` ⇒ un crash del ADSP **no** se recupera solo (`echo stop; echo start`) |
| GPR/APR/FastRPC | `QCOM_APR=m` (módulo **`apr`**), `QCOM_FASTRPC=m`, `SND_SOC_QDSP6*=m` | El DT trae `qcom,gpr` **vivo** (`reg=<2>`; 0027 lo acepta). No hacen falta para cargar ⇒ `blacklist apr`, `fastrpc` (alias `of:…Cqcom,gpr → apr` los autocargaría). `slim@6C40000` va `disabled` en su overlay |

**Firmware** (idéntico a lo que ya tenemos): pide `adsp.mdt` + `adsp_dtb.mdt`, y de ahí `adsp.bNN`/`adsp_dtb.bNN` por el
cargador MDT, en `/lib/firmware` sin `qcom/`. `charge/firmware` = 56 ficheros (51 `adsp.bNN`, b24/b51 no existen; 3 `adsp_dtb.bNN`; 2 `.mdt`),
`charge/adsp-fw.sha256` 56/56 OK en el PC; la imagen `rootfs-uke-l76-8g.img` ya trae `adsp.b40 = 42c86837…` (debugfs). Las rutas de
búsqueda del kernel incluyen siempre `/lib/firmware` (el `firmware_class.path=` del bootargs vendor solo antepone una ruta inexistente).
Si faltara un fichero con el auto-boot, `request_firmware_nowait` espera el fallback de usuario (60 s): por eso se verifica antes.

**0033 "charger budget and startup"**: unidades mAh/charge-negativo, ruta SDP 500 mA (`INPUT_CURRENT_LIMIT` ≤ techo reportado), reutiliza el
worker `vbus_draw` de DWC3 y **arranca el ADSP del cargador por remoteproc**. **0035 "readiness and ABI"**: pd-mapper antes del remoteproc,
conversión de ABI con rechazo de overflow, reintento SDP ≤5 s mientras el cargador remoto da `EAGAIN`, `device_link` USB→battmgr.
Ninguno sube tensión/corriente ni PD: **la carga la decide el firmware del ADSP**; Linux solo lee y limita el SDP.

## 2. Qué cambia respecto al stack viejo

| | Viejo (`charge/`) | Nuevo (`deploy/carga/`) |
|---|---|---|
| Módulos | `insmod` de `/usr/local/share/uke/mods` (vermagic palawan) | `modprobe` por nombre desde `/lib/modules/<rel>` (depmod) |
| ADSP | `echo start` | `modprobe qcom_q6v5_pas` el último (auto-boot) + espera `running` ≤45 s; `echo start` único de respaldo (también si PAS fuera built-in); `crashed` ⇒ stop+start |
| Firmware | verificado antes, pero tras cargar módulos | verificado **antes de todo** (b40/mdt fijados en el script + manifiesto 56/56), exit 4 sin cargar nada |
| gpr | `drivers_autoprobe=0` según estado del nodo | no hace falta: `apr` bloqueado por modprobe.d |
| `ucsi_glink` | cargado | no se carga (battery-only) |
| Veredicto | `current_now>0` | **no** exige signo ni >0 (lección 13-oct: en CV es ~0); exige `voltage_now>0` + `Charging/Full`; la carga sostenida se mide con `--watch` (¿sube `voltage_now`?) |

## 3. Diseño y ficheros (`build/rootfs/deploy/carga/`)

Orden de `uke-carga-start.sh` (POSIX sh): **0** kernel `*senemos*` (si no, sale 0 sin tocar nada) y `modules.dep` · **1** gate firmware ·
**2** `modprobe qrtr qrtr_smd qcom_pd_mapper pmic_glink qcom_battmgr` (cualquier fallo ⇒ exit 4, **no** se arranca el ADSP) ·
**3** `modprobe qcom_q6v5_pas` + espera · **4** espera `qcom-battmgr-bat` con `voltage_now` ≤45 s y veredicto.
Salida: **0** verde · **2** amarillo (batería visible, sin Charging: ¿sin cargador?) · **3** rojo (sin psy) · **4** prerrequisito ·
**5** ADSP no running. La unidad lleva `SuccessExitStatus=2`, sin `Restart=`, `TimeoutStartSec=240`. Estado en `/run/uke-carga.status`.

| Fichero (sha256 16 car.) | Destino en la tablet |
|---|---|
| `rootfs/usr/local/sbin/uke-carga-start.sh` `d3075fe7…` | `/usr/local/sbin/` (0755) |
| `rootfs/usr/local/sbin/uke-carga-verify.sh` `5c7c6c68…` | idem: `--pre` / `--post` / `--watch N SEG` |
| `rootfs/etc/systemd/system/uke-carga.service` `17a2a52b…` | `ConditionKernelVersion=*senemos*`, WantedBy multi-user |
| `rootfs/etc/systemd/system/uke-adsp.service.d/10-senemos-off.conf` `f8df1281…` | `ConditionKernelVersion=!*senemos*` (verificado con `systemd-analyze condition`) |
| `rootfs/etc/modprobe.d/uke-carga.conf` `d48973c5…` | `blacklist qcom_q6v5_pas apr fastrpc ucsi_glink pmic_glink_altmode` (solo alias; el modprobe por nombre funciona; en palawan son built-in ⇒ sin efecto) |
| `rootfs/usr/local/sbin/uke-usb-gadget-late.sh` + `.service` `2c8eb467…`/`83fc1d5a…` | **OPCIONAL** (`--with-gadget-late`): solo útil con un DT que lleve `usb-psy-name` (ouke1) |
| `deploy.sh` `611c9f6a…` | PC |
| `tests/offline-test.sh` `aac7fd8c…` | PC: 36 casos con `/sys` y `modprobe` falsos |

`deploy.sh` (tar | ssh, sin scp; `UKE_HOST`, `UKE_KEY` como `uke-charge-run.sh`): `pc` (gates sin tablet) · `check` (pre-vuelo solo lectura) ·
`install [--with-gadget-late]` (pre-vuelo informativo, copia, repara firmware corrupto fichero a fichero desde `charge/firmware` y re-verifica,
`daemon-reload` + `enable`; **no arranca**) · `start` (pre-vuelo **duro**: si falla no arranca; `systemctl start`; journal; verify) ·
`verify [--watch N SEG]` · `mods [MODROOT] [--dry-run]` (opcional: sube solo los 14 `.ko` de la cadena (+3 `modules.*`) + `depmod`; probado en seco contra el modroot
ouke2: vermagic OK) · `rollback` · `stage DIR` (extrae en una raíz montada/imagen y crea el symlink de enable). El firmware va por `/usr/lib/firmware`
(en Arch `/lib` es symlink) y los módulos por `-C /usr`.

## 4. Checklist de verificación (en la tablet; automatizado por `deploy.sh verify`)

1. **Pre-vuelo** (`deploy.sh check`): `uname -r` = `7.2.9-senemos.1.4054.3-ouke2`; `/lib/modules/<rel>/modules.dep`; vermagic de la cadena == `uname -r`;
   DT vivo: `remoteproc-adsp@03000000` = `qcom,cliffs-adsp-pas`, `/pmic-glink` = `xiaomi,uke-pmic-glink`, canal `PMIC_RTR_ADSP_APPS`; firmware 56/56; `/` ≥200 MiB.
2. **Servicio**: `systemctl is-active uke-carga` = active; `uke-adsp` (viejo) = inactive/condición no cumplida; `journalctl -u uke-carga -b` termina en `RESULTADO: VERDE|AMARILLO`.
3. **Módulos** (`lsmod`): `qrtr qrtr_smd qcom_pd_mapper pmic_glink qcom_battmgr qcom_q6v5_pas qcom_sysmon qcom_glink_smem`; **no** `ucsi_glink`, `pmic_glink_altmode`, `apr`, `fastrpc`.
4. **ADSP**: `for r in /sys/class/remoteproc/*; do echo $r $(cat $r/name $r/state $r/firmware); done` ⇒ `adsp running adsp.mdt`.
5. **dmesg**: `remote processor … is now up`; `PDR: Indication received from msm/adsp/charger_pd, state: 0x1fffffff`; **0** de: `Domain ID not specified`, `AUTH_AND_RESET`/`auth … fail`,
   `crash detected in adsp`, `Direct firmware load for adsp… failed`, `unknown message`, `Oops`, `Call trace`.
6. **power_supply**: `ls /sys/class/power_supply` ⇒ `qcom-battmgr-bat`, `-usb`, `-wls`. `qcom-battmgr-bat`: `status`=`Charging` (con cargador de pared) o `Discharging` (sin él),
   `voltage_now`>0, `current_now` (µA; **ni el signo ni el 0 deciden**), `capacity`. `qcom-battmgr-usb`: `online`, `usb_type`, `input_current_limit`.
7. **Carga sostenida** (`deploy.sh verify --watch 6 30`): `voltage_now` **sube** (OK), plano (AVISO: CV o llena), **baja ⇒ FALLA** (no carga). Control: sin cable ⇒ `Discharging` y tensión a la baja.
8. **Idempotencia**: `systemctl restart uke-carga` con el ADSP ya `running` no lo toca (veredicto otra vez verde).
9. **Si el ADSP queda `crashed`/`offline`**: `echo stop > …/state; echo start > …/state`; mirar `dmesg | grep -E 'q6v5|adsp|remoteproc'`. **No** hacer `rmmod` de `pmic_glink`/`qcom_battmgr`.

## 5. Requisitos de config/DT para el kernel (v2/ouke2), por escrito

Ninguno **bloqueante**: ouke2 ya los cumple (comprobado en `config-senemos-ouke2` y en `modroot`). Hay que **mantenerlos**:

1. **`QCOM_Q6V5_PAS=m` obligatorio** (con `=y` probaría en el initramfs, sin firmware, y perderíamos el control del orden). El resto de la cadena puede ser `=m` o `=y` (el script cubre ambos):
   `QCOM_PIL_INFO QCOM_RPROC_COMMON QCOM_Q6V5_COMMON QCOM_SYSMON RPMSG_QCOM_GLINK_SMEM QRTR QRTR_SMD QCOM_PD_MAPPER QCOM_PDR_HELPERS QCOM_PDR_MSG QCOM_QMI_HELPERS QCOM_PMIC_GLINK BATTERY_QCOM_BATTMGR`.
2. `uname -r` debe **contener `senemos`** (`-senemos.1.4054.3-ouke2`) y coincidir **exactamente** con el directorio de `/lib/modules/` (sin MODVERSIONS no hay CRC: solo el vermagic protege). Modules sin compresión (`MODULE_COMPRESS` off) y con `depmod` ejecutado (`modules.dep/alias/softdep`).
3. Mantener `FW_LOADER=y` con `FW_LOADER_USER_HELPER_FALLBACK` **sin** definir y `FW_LOADER_COMPRESS` off (el firmware son ficheros planos).
4. **DT/USB (ya resuelto en ouke2)**: ouke1 llevaba `usb-psy-name = "qcom-battmgr-usb"` ⇒ `dwc3_core_probe` diferido hasta que `qcom_battmgr` registrara el psy (`core.c:2224-2226,2286-2288`), es decir, sin UDC/SSH hasta tener la pila de carga (y `ukeinit` espera 600 s). ouke2 lo quita (`usb.dtbo` verificado sin esa propiedad). **No reintroducirla** hasta que el USB-PC no dependa de la carga; entonces `uke-usb-gadget-late` (opcional) cubre el UDC tardío. Efecto de quitarla: `dwc->usb_psy=NULL` ⇒ `dwc3_gadget_vbus_draw` devuelve `-EOPNOTSUPP`, no hay negociación SDP desde Linux; la corriente la fija el firmware del ADSP.
5. Opcional (no necesario): `# CONFIG_QCOM_FASTRPC is not set`, `QCOM_APR`/`SND_SOC_QDSP6` fuera, para quitar superficie; el `modprobe.d` ya los frena.

## 6. Riesgos

| # | Riesgo | Mitigación |
|---|---|---|
| 1 | Auto-boot al cargar PAS con firmware malo ⇒ `AUTH_AND_RESET -22` (b40 corrupto 3 veces) | gate antes de cualquier módulo; `deploy.sh install` repara y re-verifica; exit 4 |
| 2 | udev autocarga PAS (alias) antes de nuestro orden | `blacklist qcom_q6v5_pas`; instalar **antes** o junto al modroot (`install` no exige módulos) |
| 3 | `apr`/`fastrpc` autocargados tras el ADSP: audio q6/SLIM/DMA "no cualificado" (0033); trampa histórica del gpr | blacklist; no se cargan |
| 4 | Crash del ADSP no se recupera (0033) | `verify` lo detecta; recuperación manual (checklist 9) |
| 5 | `rmmod`/reinicio de battmgr/pmic_glink rompe USB: `device_link` USB→battmgr (0035) — solo si el DT tuviera `usb-psy-name` | no hay `ExecStop`; no descargar módulos |
| 6 | Sin cargador al probar: veredicto 2 (amarillo) es normal | usar cargador de pared (≥3700 mV; en fastboot no carga) |
| 7 | Sin MODVERSIONS: `.ko` de otra build entran y corrompen | vermagic exacto en `--pre` y `mods`; solo modroot de **este** Image |
| 8 | WiFi/PAS: el mismo módulo; su `modprobe qcom_q6v5_pas` también arranca el ADSP | `uke-wifi` `After=uke-carga.service` (pendiente de coordinar con `deploy/wifi`) |
| 9 | El pre-vuelo y el loader nunca corrieron en la tablet real (solo simulación y modroot real en el PC) | primer ciclo con SSH y lector ACM, un cambio por ciclo |

## 7. Pasos (con orden del dueño; cada paso es un único cambio)

0. Cargador de pared y batería ≥3700 mV. Kernel ouke2 flasheado (su propio ciclo, `SENEMOS-V2-USB-20261017.md`) y SSH vivo.
1. Módulos: `tar --zstd -xf build/kernel-pokes/senemos-build/modules-7.2.9-senemos.1.4054.3-ouke2.tar.zst -C /` + `depmod -a`
   (o `deploy/wifi/deploy.sh --modules`, o `deploy.sh mods`). `deploy.sh check` ⇒ todo OK.
2. `bash build/rootfs/deploy/carga/deploy.sh pc` y `bash build/rootfs/deploy/carga/tests/offline-test.sh` (sin tablet).
3. `deploy.sh install` ⇒ instala y habilita, no arranca.
4. `deploy.sh start` ⇒ pre-vuelo duro + arranque + verify. Esperado: `RESULTADO: VERDE`.
5. `deploy.sh verify --watch 6 30` ⇒ `voltage_now` sube. Reboot de comprobación: `uke-carga` arranca solo.
6. Rollback: `deploy.sh rollback` (no para el ADSP). En un kernel palawan el unit viejo vuelve a mandar solo (drop-in condicional).

## 8. Qué se probó y qué no

- **Sí (PC)**: `tests/offline-test.sh` 36/36 (orden de carga con pas último; b40 corrupto/ausente y otro segmento corrupto ⇒ 0 modprobe y exit 4; sin `modules.dep`; kernel palawan ⇒ no-op; auto-boot, `echo start` de respaldo, `crashed`;
  ADSP que nunca arranca ⇒ 5; Discharging ⇒ 2; sin psy ⇒ 3; fallo de `qrtr_smd` ⇒ aborta antes del ADSP; idempotencia; gadget tardío; `verify --post/--watch`); `sh -n`/`bash -n`;
  `systemd-analyze verify --root` de los units y del drop-in sobre el unit viejo; `deploy.sh pc`, `stage`, `mods --dry-run` contra el modroot ouke2 real (14 `.ko`, vermagic OK) y `uke-carga-verify.sh --pre` contra él con DT simulado.
- **No**: nada en la tablet; el comportamiento real del ADSP/battmgr con este DT (p. ej. si `charger_pd` sube o si hay `unknown message`) solo se sabrá con SSH; el rollback; `deploy.sh install/start/check/verify/rollback` (necesitan SSH).
