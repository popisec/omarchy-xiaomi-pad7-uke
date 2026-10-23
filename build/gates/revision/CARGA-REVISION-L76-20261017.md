# REVISION CARGA para L76 / L76R — 17-oct-2026 (solo lectura, sin tablet)

Alcance: ¿el stack de carga (charge/) sigue valiendo con los kernels L76 y L76R y con el rootfs de
userdata perdido (#653)? Todo medido en el PC; no se uso adb/fastboot/ssh, no se compilo, no se commiteo.

## 1. ¿Siguen valiendo los .ko con L76/L76R?  SI

| Prueba | Resultado (comando/fichero) |
|---|---|
| Config versionada | `cmp k52L74.config k52L76r.config` OK; `diff k52L74 k52L76` vacio; `diff k52L76 k52L76r` vacio (build/kernel-config/) |
| `.config` de los build dirs | `diff k52L74-build/.config k52L76-build/.config` vacio; `diff k52L76-build/.config k52L76r-build/.config` vacio (LOCALVERSION="-palawan", PREEMPT=y, MODULE_UNLOAD=y) |
| Release | `include/generated/utsrelease.h` = `7.2.0-rc2-palawan` en k52L74, k52L76 y k52L76r (sin `+`) |
| vermagic en el Image | `strings -a k52L76-build/arch/arm64/boot/Image` -> `7.2.0-rc2-palawan SMP preempt mod_unload aarch64` (identico a L74) |
| vermagic de los .ko | `strings` de `charge/mods-7.2.0-rc2-palawan/qcom_battmgr.ko` -> `vermagic=7.2.0-rc2-palawan SMP preempt mod_unload aarch64` (la variante sin `+` es la correcta; la `+` no sirve). `charge/VERMAGIC-PIN` lista ambas variantes. |
| Built-in vs =m | Identico en L74/L76/L76R: `QCOM_PIL_INFO`, `RPROC_COMMON`, `Q6V5_COMMON`, `Q6V5_PAS`, `RPMSG_QCOM_GLINK(_SMEM)`, `QRTR_SMD`, `QCOM_PD_MAPPER`, `QCOM_APR` = **y**; `QCOM_PMIC_GLINK`, `UCSI_PMIC_GLINK`, `BATTERY_QCOM_BATTMGR` = **m**. Nada cambia. En el Image: `pmic-glink`, `ucsi_glink`, `qcom_battmgr` x0 (carga fuera del boot.img, como L71/L74). |
| Fuentes | Los .ko se compilaron desde k52L33-tree; el kernel L76 sale de `k52-L16-tree`. `cmp` fichero a fichero: `pmic_glink.c`, `qcom_battmgr.c`, `qcom_pd_mapper.c`, `pmic_glink.h`, `ucsi_glink.c`, `qcom_glink_smem.c`, `qcom_q6v5_pas.c`, `rpmsg.h`, `remoteproc.h`, `auxiliary_bus.h` = **identicos**. `qcom_pd_mapper.c` lleva el parche `cliffs` (3 ocurrencias). MODVERSIONS esta unset, asi que esta igualdad de fuente es la unica defensa de ABI y se cumple. |

Nota: L76R (`k52L76r-build`) **aun se esta compilando** (proceso make vivo, no existe `arch/arm64/boot/`); la conclusion para L76R se apoya en que `.config` es byte a byte igual al de L76 (no en un Image ya construido). Hay que repetir el `strings` de vermagic sobre el Image L76R cuando salga.

## 2. cmdline / dtbo / gate de carga

- cmdline: `repack-k52L76.py` y `repack-k52L76r.py` exigen 622 B == L74 byte a byte (cadena L57..L74) y token `regulator_ignore_unused` (gate G2, repack-k52L76r.py:237-238; cabecera :19). Tambien `clk_ignore_unused pd_ignore_unused` (visto en `strings boot-uke-k52L76.img`). Sin `root=`: rdinit=/ukeinit, el init busca `userdata` por label/tamano (`build/init/ukeinit-arch:33-75`).
- dtbo: los repack solo escriben boot.img. `flash-l76r-gated.sh:23,25,28` exige `s288...adsp.img` sha `02d403c5...` y aborta si no coincide; unica escritura `boot_a` (:52). s288 = s287 + ADSP icc a mc_virt + gpr disabled (`charge/repack-s288-report.txt` G4/G5). `build/backup-par-bueno/android-20261017/dtbo_a.img` empieza con exactamente los 608832 B de s288 (cmp OK): dtbo_a conservaba s288 al hacer el backup (12:18) tras restaurar Android. **s289** (solo label `ktz_bl_1`) no es necesario para carga y no esta referenciado por los flash L76*.
- nodos adsp/pmic_glink/battmgr: vienen del DT base + s288 (no tocados por L76*). Los gates L76 no los miran.
- **flash-l76r-gated.sh: `EB=SHA_PENDIENTE` (:24) y aborta en :26** hasta rellenarlo tras el repack. Archivos L76R sin commitear (git status ?? x3).
- Verificacion de CARGA del flash L76R (:129-132): identica a L73; solo IMPRIME `remoteproc name: state`, `PDR: <n>`, `status`/`current_now` de `qcom-battmgr-bat`. **No es gate**: nada sale con error si el ADSP no esta `running`, si PDR=0 o si status != Charging, y los `g()` no lo cuentan (18 g + orden = 19). Ademas el bloque entero va dentro de ssh: sin rootfs no hay carga ni gates. No comprueba sha de adsp.b40 ni `systemctl is-active uke-adsp`.
- Inconsistencia menor: el criterio impreso habla de 19/19 y luego "gates 18/18" (:139-148).

## 3. Rootfs perdido: que reinstalar

Realidad (medida con `debugfs -R stat/ls` sobre las imagenes base): ni `build/rootfs/arch-rootfs.img` (27-sep) ni `rootfs-uke-k521.img` (5-oct, 4 GiB) contienen NADA del stack de carga (no hay `/lib/firmware/adsp*`, `uke-adsp.service`, `uke-adsp-load.sh`, `/usr/local/share/uke`). `rootfs-uke-k521.img.sha256` (bd2b3029...) NO coincide con el sha real de la imagen (5f9f00fe...): verificar/regenerar antes de usarla. `build/rootfs/staging/` tiene un unit VIEJO (`ExecStart=/usr/local/bin/uke-adsp-load.sh`, 5-oct) y `.ko` viejos de 6-oct (vermagic sin `+`, binarios distintos): no usarlo como fuente.

Importante: el loader NO usa `/lib/modules/<rel>/extra` ni depmod. Carga con `insmod` desde `/usr/local/share/uke/mods` (uke-adsp-load.sh:20,44-54). La premisa depmod/extra no aplica.

Lista exacta (todo existe en el PC):

| # | Pieza | Origen -> destino |
|---|---|---|
| 1 | 10 .ko variante SIN `+` | `charge/mods-7.2.0-rc2-palawan/*.ko` -> `/usr/local/share/uke/mods/` (carga `pmic_glink`, `ucsi_glink`, `qcom_battmgr`; el resto se salta/avisa por built-in) |
| 2 | Firmware 56 ficheros | `charge/firmware/adsp.mdt adsp_dtb.mdt adsp.b?? adsp_dtb.b??` -> `/lib/firmware/` **sin `qcom/`** (en Arch `/lib` = `/usr/lib`; mas de 49 segmentos) |
| 3 | Manifest | `charge/adsp-fw.sha256` -> `/lib/firmware/adsp-fw.sha256` (si falta, el loader solo avisa y no verifica, :70-80) |
| 4 | Loader | `charge/uke-adsp-load.sh` -> `/usr/local/sbin/uke-adsp-load.sh`, chmod +x |
| 5 | Unit | `charge/uke-adsp.service` -> `/etc/systemd/system/uke-adsp.service` + `systemctl enable` (symlink en `multi-user.target.wants`) |
| 6 | Comprobar | `sha256sum /lib/firmware/adsp.b40` == `42c86837570fabc9...5882b352` (en el PC: `charge/firmware/adsp.b40` = ese sha, manifiesto OK) |

GAP-1: **CERRADO en el script**. `charge/uke-charge-run.sh:62-64` ya hace `scp adsp-fw.sha256 -> /lib/firmware/adsp-fw.sha256` (commit 742a24a). Pero el script **solo corre con la tablet viva por SSH** (RNDIS 192.168.42.129, clave `build/rootfs/uke-arch-root`, :17-24) y su unit se sobrescribe y habilita en :70-72. No hay ningun paso en el repo que meta el stack DENTRO de una imagen/rootfs (busque en build/rootfs, charge, build/gates: nada; `build/gates/prepara/uke-adsp-load.sh` es una version antigua). Por tanto: tras reinstalar la base, la carga NO funciona al primer arranque a menos que (a) se hornee el stack en la imagen (debugfs/e2cp con las 6 piezas de arriba) o (b) se llegue por SSH y se corra `uke-charge-run.sh`. Con (b) hay un dia de tablet sin cargar en Linux: para eso esta el off-mode-charge del ABL con cargador de pared.

Huecos detectados en el nuevo rootfs (ademas del stack):
1. No hay script de "reinstalacion de rootfs + stack" (hueco principal).
2. Raiz de 4 GiB: el 15-oct el flood DSI la lleno al 100% y tumbo `uke-adsp` (CARGA-AUDITORIA §3). Conviene la imagen 8 GiB o resize2fs.
3. `modinfo` del gate vermagic (`uke-charge-run.sh:42-46`) ya fue refutado como falso OK (NOTAS 17-oct): se mantiene.
4. Config de red RNDIS (`10-uke-usb.network`, 192.168.42.129/24) y sshd/authorized_keys van en la base (existen en ambas imagenes; `authorized_keys` presente). OK.
5. `sddm` disabled por defecto (ESTADO-VIVO 16-oct); irrelevante para carga.
6. Loader: ruta `GPRNODE=/proc/device-tree/soc/remoteproc-adsp@03000000/...` (:96); si no existe ese path, cae en "no toco el bus" (inocuo con gpr disabled).

## 4. Riesgos

- **adsp.b40 corrupto (3 veces)**: el loader endurecido lo detecta (exit 1, :70-77) pero no repara; hace falta SSH + `scp charge/firmware/adsp.b40 root@...:/lib/firmware/` (ruta SIN `qcom/`). Con rootfs recien escrito no hay motivo de corrupcion, pero si hay que correr el ritual de sha en el primer contacto. Ritual: `cd charge/firmware && sha256sum -c ../adsp-fw.sha256 --quiet` en PC (ejecutado hoy: adsp.b40 == manifiesto).
- **Fastboot no carga** (USB-PC ~100 mA, descarga ~7 mV/min, CARGA-AUDITORIA §4): minimizar tiempo en fastboot; el flash L76R debe hacerse con cargador de pared o bateria >=3700 mV (gate: aborta <3300, avisa <3700, :34-35).
- **Bateria**: Android la llevo a 4082 mV (ESTADO-VIVO 17-oct 05:0x); margen amplio ahora.
- **Orden de arranque**: L76R arranca con rootfs vacio -> sin SSH no hay gates ni carga gestionada; con userdata de Android el init no encuentra raiz ext4 valida (ukeinit-arch hace e2fsck/switch_root).
- **L76R sin construir**: Image aun no existe y `EB=SHA_PENDIENTE`.
- Carga en off-mode del ABL (no depende de Linux) es la red de seguridad.

## VEREDICTO / RESUMEN (<=300 palabras)

**Kernel: la carga "se monta" con L76 y L76R.** `.config` byte a byte igual a L74 (y L76R igual a L76), release/vermagic `7.2.0-rc2-palawan`, mismos built-in (PAS/glink/pd_mapper/QRTR =y) y mismos =m (pmic_glink, ucsi_glink, battmgr). Las fuentes de los .ko son identicas a las del arbol de L76. Variante de modulos correcta: la SIN `+`. El dtbo s288 (gpr disabled, ADSP icc) esta intacto en dtbo_a (backup del 17-oct == s288) y los flash L76* lo exigen por sha; cmdline == L74 con `regulator_ignore_unused`. Pendiente solo verificar el vermagic del Image L76R cuando termine el build.

**Rootfs: NO esta montado.** Ninguna imagen base del repo lleva el stack (comprobado con debugfs), y no existe script que lo hornee. Hay que instalar 6 piezas: 10 .ko en `/usr/local/share/uke/mods/`, 56 ficheros de firmware en `/lib/firmware/` (sin `qcom/`), `adsp-fw.sha256`, loader en `/usr/local/sbin/`, unit en `/etc/systemd/system/` y `enable`. No hace falta depmod ni `/lib/modules/.../extra`. GAP-1 esta cerrado en `uke-charge-run.sh:62-64`, pero ese script solo funciona con SSH vivo.

**Huecos:** (1) falta paso de reinstalacion rootfs+stack; (2) `flash-l76r-gated.sh` tiene `EB=SHA_PENDIENTE`, y su bloque CARGA solo imprime (no falla si ADSP no esta running/PDR=0/status!=Charging) ni comprueba sha de adsp.b40; (3) staging y su unit/.ko estan obsoletos; (4) `rootfs-uke-k521.img.sha256` no coincide con la imagen; (5) raiz de 4 GiB se llena con flood.

**Para que si:** hornear el stack en el rootfs (o correr `uke-charge-run.sh` en el primer contacto), verificar sha de adsp.b40, endurecer el bloque CARGA del flash L76R con exit != 0, y flashear con cargador de pared.
