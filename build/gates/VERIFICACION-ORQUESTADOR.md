# Verificación del orquestador (27-sep-2026, después de los 4 subagentes)

**Regla:** no se da por bueno lo que devuelve un subagente. Todo lo de abajo está **reejecutado por
el orquestador**.

## Lo que se verificó y está bien

| Afirmación del subagente | Verificación del orquestador | Resultado |
|---|---|---|
| A3: «auto-prueba byte a byte del shell» | `SELFTEST=1 ./mkarch-boot.sh` reejecutado | ✅ `ffff8c51265f == ffff8c51265f`, 0 bytes difieren |
| A3: «10/10 aserciones OK» | reejecutado tras reconstruir | ✅ las 10 en verde |
| A3: header del boot.img | parseo a mano con `struct` | ✅ `ANDROID!`, `kernel_size@8`, `ramdisk_size@12`, `version@40 = 4`, `AVB0` en 35438592, `AVBf` en `[-64:-60]`, 96 MiB |
| A3: cmdline con los 5 tokens | leído del binario | ✅ `mem=2048M` · `rdinit=/ukeinit-arch` · `memmap=0x1A12800$0xE3940000` · `console=ttyGS0,115200` · `arm-smmu.disable_bypass=0` (260 B) |
| A3: kernel idéntico al de entrada | sha dentro de la imagen | ✅ `32e23e14b8fa…` == `out/kernel` |
| A2: imagen ext4 válida | `e2fsck -fn` | ✅ limpia, 47668/524288 ficheros, label `arch-arm` |
| A2: `/lib/modules/7.2.0-rc2-palawan+` | `debugfs ls` | ✅ presente |
| A2: claves SSH de host | `debugfs ls /etc/ssh` | ✅ `ssh_host_ed25519_key` y `ssh_host_rsa_key` |
| A4: seguro de vuelta atrás intacto | `sha256sum` + `gzip -t` + magia ext4 | ✅ `rootfs.img.gz` existe, 369822577 B, gzip íntegro |
| A1: sintaxis del init | `sh -n` sobre `ukeinit-arch` | ✅ verde |

⚠️ **Nota sobre `/sbin/init` y `/etc/os-release`**: `debugfs cat` no los muestra porque son
**symlinks** (`/sbin/init` → 22 B de destino, `/etc/os-release` → 21 B) — normal en Arch con
`usr-merged`. No es un fallo; solo hay que comprobarlo con el fs **montado**, no con `debugfs`.

## 🔴 EL FALLO QUE SE ENCONTRÓ Y SE CORRIGIÓ

**Cruce `init` ↔ `cpio`: el init invocaba binarios que no estaban en el initramfs.**

`ukeinit-arch` usa, en código ejecutable:
- `head -1` en las líneas **109, 156 y 197**
- `rm -rf` en la línea **140**

Pero la lista `BUSYBOX_APPLETS` de `mkarch-initramfs.py:52` **no incluía `head` ni `rm`** (ni
`sort`, `sed`, `cut`, `dd`, `tr`, `test`, `expr`). El cpio solo lleva symlinks por applet, así que
sin el symlink el init falla con *command not found* — salvo que el busybox tenga
`FEATURE_SH_STANDALONE` en su shell, **que no se puede asumir**.

**Corrección aplicada** (commit en `mkarch-initramfs.py`): la lista pasa a incluir los applets que el
init usa **más los defensivos** (`umount`, `sort`, `sed`, `cut`, `tail`, `wc`, `dd`, `tr`, `basename`,
`dirname`, `touch`, `test`, `true`, `false`, `expr`).
**Reconstruido y reverificado**: cpio 53 → **70 entradas**, 2392467 → **2392637 B** (sigue bajo el
gate de 8 MiB), y `ukeinit-arch`, `bin/head`, `bin/rm`, `bin/sort`, `uke/gadget-setup-arch.sh`,
`bin/e2fsck`, `lib/libe2p.so.2` **confirmados dentro del initramfs embebido en `boot-arch-uke.img`**
(extraído con `dd` y listado con `cpio -t`).
Cruzado de nuevo `init` ↔ `cpio`: **0 comandos reales ausentes**.

> **Lección:** la lista de applets se había escrito **desde el script, no desde el init**. Un init
> que se revisa a ojo y un cpio que se revisa a ojo no se cruzan solos. El gate que falta es
> automático: *extraer los comandos del init y comprobar que todos existen como applet*.

## Segundo arreglo: la variante de reserva de `userdata` (implementada 27-sep-2026)

El gap nº1 que quedaba abierto —«`/dev/disk/by-partlabel/userdata` puede no existir en el initramfs
porque no hay udev»— **ya no es un gap: está implementado y verificado**.

**`resolve_userdata()`** en `ukeinit-arch` (líneas 36-79) resuelve la partición por **tres vías, de la
más barata a la más cara**:

1. **El enlace `by-partlabel`**, si existe (o si hay udev/mdev).
2. **`blkid -o value -s PARTLABEL`** sobre los block devices que aparezcan. No hace falta udev:
   `blkid` lee la tabla de particiones directamente del device, que es justo lo que falta.
3. **Por tamaño, como último recurso**: `userdata` es con diferencia la partición mayor (~105,9 GB
   frente a particiones de sistema de unos pocos MB). **Solo se acepta si es > 20 000 000 000 B y no
   hay empate** — si hubiera empate, `die()` y paras, porque adivinar mal aquí significa formatear la
   partición equivocada.

**Seguridad:** las tres vías **leen**; el único `dd` del sistema está en el paso B3, que es explícito y
va con sus propias verificaciones. Ninguna de estas vías escribe nada.

**Verificación:**
- `sh -n ukeinit-arch` → verde.
- `blockdev` y `blkid` añadidos a `BUSYBOX_APPLETS` (estaban en el staging de ALARM), con
  `fdisk`/`sfdisk` por si acaso.
- Cruzado `init` ↔ `cpio` de nuevo: **0 comandos reales ausentes** (`ni` es una palabra de un `say`).
- cpio reconstruido: 70 → **73 entradas**, 2393396 B (gate 8 MiB).
- `boot-arch-uke.img` reconstruido: **10/10 aserciones** en verde, sha
  `82c59a528849fe7e71c6ca08f8b9b84867eaf8c6ffcda4553c796c8879173882`.
- El init **embebido en la imagen** se extrajo con `dd` + `cpio` y se verificó: contiene
  `resolve_userdata` (4 ocurrencias), y su sha es **idéntico** al de disco
  (`7486a638cea257235553f82d23b8b11323aec1fa2f5f271c75961dc8308b37e1`).

### Lo que sigue sin verificar
- El **nombre real de la interfaz RNDIS** en este kernel (el init lo busca dinámicamente entre las que
  no sean `lo`, así que debería aguantar, pero el camino no está probado).
- Cuánto tarda el `e2fsck -f -p` en frío sobre los 105,9 GB con los ~880 errores.
- `qbootctl` ausente de la imagen ⇒ **el slot nunca se marca successful** y los intentos son finitos.
  Afecta a F8, no al primer boot, pero es un agujero conocido y hay que resolverlo antes de depender
  del A/B.


- **`/dev/disk/by-partlabel/userdata` dentro del initramfs**: sin udev, el enlace por partlabel puede
  no existir. **Es el fallo más probable del primer intento.** El init lo detecta y para con mensaje,
  pero la variante de reserva (buscar por PARTLABEL en `/sys/class/block/*/partition`) **no está
  implementada**.
- **El nombre real de la interfaz RNDIS** en este kernel (`usb0`? `rndis0`? `enx…`?) — el init lo
  busca dinámicamente, pero el camino no se ha probado.
- Si el init sobrevive a que `e2fsck` encuentre los ~880 errores de `userdata` y en cuánto tiempo
  (sobre 105,9 GB, **sin tiempo medido**).
- `qbootctl` no está en la imagen: **el slot nunca se marca successful** y los intentos de slot son
  finitos. Afecta a F8, no a F5, pero es un agujero conocido.

---

## 🟢 MEDIDO EN LA TABLET (27-sep-2026, por SSH a 192.168.42.129)

Con la tablet en Ubuntu (aarch64, Ubuntu 24.04 LTS, kernel #82, uptime 4 min) se ha podido
**medir en el aparato** lo que hasta ahora era `[NO VERIFICADO]`. Entrada por SSH con
`~/.ssh/id_ed25519` (la misma clave que usa `bin/uke-shell.sh` del hermano).

### 🔴 CORRECCIÓN IMPORTANTE: el tamaño de `misc` NO es 8192 B, son **4 MiB**

```
/dev/disk/by-partlabel/misc   →  4194304 B   (4 MiB)
primeros 16 B  →  72 65 62 6f 6f 74 2d 62 6f 6f 74 6c 6f 61 64 65  =  "reboot-bootloader"
```

- `B §4.5` dice *«`misc.img` son 8192 B de ceros»* ⇒ **FALSO**.
- `~/gpu-work/bcb-clean.bin` son **2048 B** ⇒ también insuficiente.
- **Consecuencia para F0:** el paso 4 («limpiar el BCB de `misc`») habría escrito 2048 B sobre una
  partición de 4 MiB. El campo `command` (32 B) sí habría quedado a cero, o sea que **probablemente
  habría funcionado por casualidad**, pero el criterio de éxito («`command[0:32]` en ceros») no
  distingue «limpiado» de «limpiado solo el principio». **Se decide por la partición entera.**
- **Hecho aquí:** `build/misc-zeros-4m.img`, **4194304 B**, sha256
  `bb9f8df61474d25e71fa00722318cd387396ca1736605e1248821cc0de3d3af8`.

### Lo demás medido

| Dato | Valor |
|---|---|
| `userdata` | **113 657 229 312 B** (105,8 GiB) — la imagen de Arch de 8 GiB sobra |
| `userdata` en uso | 7,8 GB usados, 4,1 GB libres (el rootfs de Ubuntu ocupa 7,8 de 105,8) |
| `/dev/disk/by-partlabel/userdata` | ✅ **existe y funciona** (con udev) ⇒ la etiqueta es correcta |
| BCB actual | `command = "reboot-bootloader"` ⇒ **el próximo reinicio cae a fastboot por diseño** |
| `ath11k` | **cargado** (`ath11k_ahb`, `ath11k`, `mac80211`, `cfg80211`) **y a la vez** existe `/etc/modprobe.d/blacklist-ath11k.conf` — se confirma la incoherencia que B §10.8 citaba sin resolver |
| Lector de `/dev/ttyACM0` | **exactamente uno** (`cat`, pid 240582, el del hermano) ⇒ yo **no** lo abro, leo su log |

---

## 🔴 RESULTADO DE LOS DOS CICLOS DE BOOT DE ARCH (27-sep-2026) — y por qué importaba medir

### Los dos intentos
| # | Kernel embebido | `ramdisk_size` | Resultado |
|---|---|---|---|
| B1-intento-1 | `32e23e14…` (`out/kernel`, **NO es el del shell**) | 2 394 655 | crash instantáneo, 0 líneas de consola, slot `a` → `unbootable` |
| B1-intento-2 | `adad4bb4…` (**el del shell**, byte a byte) | 2 394 655 | **idéntico**: crash instantáneo, 0 líneas |

⇒ **El kernel no es la causa.** Con el kernel exacto que arranca Ubuntu, el fallo es el mismo.

### La evidencia decisiva
1. **Readback de `boot_a` desde Ubuntu** (`dd` por SSH, `fastboot fetch` no está soportado — REFUTADO B-01):
   sha256 en la tablet = `9cbbe9d98ce84864c53a69c77264cf772cb9ee443ce98db8efd44df27a82b150`
   = **exactamente** lo que se escribió. **El ABL no corrompe nada.**
2. Header de lo leído, intacto: `ANDROID!`, `version@40 = 4`, `kernel_size = 16559711`,
   **`ramdisk_size = 2394655`**, cmdline con `rdinit=/ukeinit-diag`.
3. **En el log de consola no aparece NINGÚN arranque nuestro** — ni la línea
   `Kernel command line`, que el kernel imprime en `t=0.000000`. Los 5 arranques que sí aparecen
   (boot_index 5344-5348) llevan todos `rdinit=/ukeinit` y son de Ubuntu.
4. El cmdline del vendor trae el mecanismo de log de panics
   (`mtdoops.dump_oops=1`, `block2mtd=/dev/block/by-name/oops,2097152`, `printk.always_kmsg_dump=1`)
   y la partición `oops` existe (**16 MiB**): **pero no hay replay ⇒ el kernel no llegó a correr.**

### VEREDICTO
**El ABL de esta tablet no carga un `boot.img` que lleve ramdisk propio.** El shell que arranca
tiene **`ramdisk_size = 0`** y su `/ukeinit` viene del **ramdisk del `vendor_boot`** (35 510 B,
`init=/init`, `debug_ext.initrd_size=35510` en el bootconfig). Con `ramdisk_size = 0` arranca; con
2,4 MB, el ABL no llega a cargar el kernel.

**Consecuencias para el plan (F5 y B §7 quedan falsificados en este punto):**
- 🔴 **El plan de F5 «initramfs propio dentro del `boot.img`» no es viable en este ABL.** El paso A3
  de F5 y el §7 Fase 3 de B asumen lo contrario.
- 🔴 `CONFIG_NETCONSOLE is not set` ⇒ **no hay netconsole** (networking de logs imposible sin
  recompilar). Sí hay `CONFIG_PSTORE_RAM=y`, `PSTORE_CONSOLE=y` y la partición `oops` de 16 MiB, pero
  solo registran lo que pase **después** de que el kernel arranque, y aquí el kernel no arranca.
- 🟢 **La vía que SÍ queda, y es la buena noticia:** el `/ukeinit` del `vendor_boot` es un script
  genérico «monta el rootfs y exec `/sbin/init`». **No hace falta injectar nuestro init para que
  arranque Arch: basta con que el rootfs sea de Arch.** Su `exec /sbin/init` llevará a systemd de
  Arch. Y como el shell **sin modificar** sí levanta el gadget ACM, **tenemos consola y log en vivo
  del arranque**, que es lo que hacia falta y lo que el usuario pregunto.

---

## 🔴 B2 — Escritura del rootfs de Arch sobre `userdata`: **FALLA por una razón estructural**

### Lo que se hizo (opción B, con el usuario autorizando)
Desde Ubuntu, por el canal del gadget (6 gates, todos en verde):
1. `busybox wget` de `arch-rootfs.img.gz` (403 133 197 B) — **sha256 verificado antes de
   descomprimir**: `bca709a2…` ✅
2. `zcat | dd of=/dev/disk/by-partlabel/userdata bs=4M conv=fsync` → **rc=0**, 8 GiB en 42 s
3. `sync`, y luego reinicio con **builtins de bash puros** (`echo b > /proc/sysrq-trigger`),
   porque el `dd` había destruido los binarios del sistema vivo.

### Lo que pasó
El `dd` se completó, **pero el resultado está corrupto**:
- `EXT4-fs error (device sda32): ext4_validate_block_bitmap: bad block bitmap checksum` →
  **`Filesystem failed CRC`**, con `comm=ldconfig` y `comm=ext4lazyinit`.
- El `/ukeinit` del vendor imprimió **`S123: RAIZ UBUNTU VERIFICADA — remontando rw y switch_root`**
  ⇒ encontró la raíz **de Ubuntu**, no la de Arch.
- El sistema arrancó como **`Ubuntu 24.04 LTS uke ttyGS0`** con `uke login:` ⇒ **sigue siendo Ubuntu**.
- Sin red (`enp0s20f0u3` DOWN), sin SSH, y el root de Ubuntu **no tiene contraseña** (solo acceso por
  clave), así que **no hay shell accesible**: ni por red ni por consola.

### 🔴 LA CAUSA (y es una lección de método, no un fallo de ejecución)
**No se puede escribir un rootfs nuevo sobre el rootfs en uso.** El kernel que estaba corriendo
mantiene el sistema de archivos montado en rw y **sigue escribiendo sus metadatos** (journal, bitmap de
bloques, commits) encima de la imagen recién escrita. Entre que el `dd` terminó y el reinicio, el
kernel antiguo_volcó su metadata encima de nuestros bloques. De ahí el CRC malo del bitmap y que
`/ukeinit` siguiera viendo un Ubuntu.

**Esto falsifica el paso B3 de F5 tal como está escrito** («escribir el rootfs por la red del
gadget»): describe justamente el método que no funciona. Y es la **evidencia dura** de por qué la
opción A (coexistencia: Arch en un fichero dentro de `userdata`, montado en loop, con el rootfs de
Ubuntu intacto) es la correcta: **es la única forma de escribir un rootfs sin que nada lo esté
sobreescribiendo.**

### Cómo se sale de aquí
Hace falta **fastboot**, y desde fastboot el camino limpio es
`fastboot flash userdata <imagen>` — que escribe **sin nada montado**, es decir, la opción B bien
hecha. Alternativa: restaurar el rootfs de Ubuntu (370 MB, `rootfs.img.gz`, ya servido) y volver al
punto de partida.

**Requiere un power cycle físico (Power + Vol−): desde el estado actual no hay shell, red ni reboot
programático.**

---

## F5-V1 — `fastboot flash userdata` con la imagen sparse de Arch (27-sep-2026)

**Gates de entrada:** fastboot OK · `battery-voltage 4232 mV` ≥ 3700 ✅ · `current-slot b`,
`slot-retry-count:b 4` (**presupuesto: 3 boots**) · sha del artefacto = pre-registrado ✅

**La escritura:** `fastboot flash userdata arch-rootfs.simg` (1 207 455 712 B) →
```
Sending sparse 'userdata' 2/2 (406492 KB)   OKAY [  8.509s]
Writing 'userdata'                          OKAY [  0.003s]
Finished. Total time: 24.719s
```
✅ **El flash funcionó** (y con nada montado, que era el punto). Precedente del hermano cumplido:
3/3 con sparse, sin que el tamaño coincida con la partición.

**Después del `reboot`: estado observado.**
- El gadget enumera como **`1d6b:0104` Multifunction Composite Gadget** (ADB+ACM del init del
  vendor) ⇒ **el kernel arrancó y el init del vendor corrió**. Ya no es el silencio de los intentos
  con ramdisk propio.
- Kernel **estable a 435 s** (flood de `devfreq`/`ufshcd-qcom`, que es el ruido normal del UFS).
- 🔴 **Sin red**: `enp0s20f0u3` con `operstate=down` y **`carrier=0`** ⇒ el NCM no se levantó.
  `192.168.42.129` no responde; sin `sudo` no puedo dar IP al lado host.
- 🔴 **Consola no interactiva**: se escriben bytes a `/dev/ttyACM0` y no hay eco, ni prompt de
  `Password:`, ni respuesta. El getty **no está en `ttyGS0`**.
- ⚠️ **No se puede determinar si la raíz es Arch o Ubuntu** con los canales disponibles. La
  hipótesis de trabajo es que **es Arch** (el flash fue OK y la cadena del kernel no se ha tocado), pero
  **no está verificada**.

**Los dos candidatos que explica el ledger del hermano para el `S123`:**
- (a) `S123` pero **no** `X9S123-SWITCH` ⇒ el gate de raíz rechazó la imagen → fallback (getty +
  ventana). **Consistente con un getty que no está en ttyGS0.**
- (b) `switch_root` OK y es Arch, pero **el NCM no sube** ⇒ la red es el problema, no la raíz.

**Lo que hace falta para cerrar el diagnóstico (y no lo puedo hacer yo):** mirar la **pantalla
física** de la tablet. Un banner de Arch, un prompt de login o una ventana de fallback lo dicen todo.

---

## 🟢🟢🟢 F5-V1 EXITOSO — **ARCH ARRANCA** (27-sep-2026 ~10:5x)

### La consola lo dice, sin ambigüedad
```
[   15.541689] S123: raiz candidata /dev/sda32 (110993388 KB)
[   15.549719] S123: mount ro,noload OK — verificando init de la raiz
[   15.557883] S123: RAIZ UBUNTU VERIFICADA — remontando rw y switch_root
[   15.559986] X9S123-SWITCH t=15 raiz=/dev/sda32
Arch Linux ARM 7.2.0-rc2-palawan+ (ttyGS0)
uke-arch login: Arch Linux ARM
```
✅ **Arch Linux ARM arrancando con NUESTRO kernel `7.2.0-rc2-palawan+`.** El objetivo de la
fase 1 —«abandonar Ubuntu y conseguir el primer boot de Arch»— **está cumplido**.

### Por qué funcionó: el `dd` con la partición DESMONTADA
Los dos intentos anteriores fallaron por escribir el rootfs **con algo montado o con restos**:
- **B2**: `dd` desde el sistema que corría sobre `sda32` ⇒ el kernel en rw escribió journal y bitmap
  encima, y el `sync` consolidó el superbloque viejo. Resultado: `Filesystem failed CRC`.
- **`fastboot flash` de una sparse**: **NO borra la partición.** Tras Arch(1,2 GB) + Ubuntu(87 MB)
  quedó un frankenstein: metadatos de Ubuntu, `/etc/os-release` = Ubuntu 24.04.3, pero
  **`/sbin/init`, `/usr/lib/systemd/systemd`, `/bin/busybox` y `/usr/bin/sshd` no existían** ⇒ el
  init del hermano imprimió `S123: montada pero SIN init → fallback fork`.

**La vía que sí funciona**, y la dejó abierta el shell de rescate del hermano (BusyBox root por
**telnet, puerto 23**, que su init garantiza *antes* del `switch_root*): con `sda32` **desmontado**
(`grep sda32 /proc/mounts` → nada), un `wget | sha256sum | zcat | dd` escribe los 8 GiB enteros
**sin que nada pueda sobreescribirlos**. Script: `build/gates/v1-write-arch.sh`, log en la tablet en
`/mnt/rescue/v1-write.log`. **Los 6 gates pasaron**, incluido el sha256 del `.gz` antes de
descomprimir.

### El canal de rescate (el hallazgo que desbloqueó todo)
El init del hermano, cuando rechaza la raíz, monta **`/dev/sda30` en `/mnt/rescue`** y se queda
ahí con **getty + telnetd**. Entrando por telnet se tiene **un shell BusyBox como root sin
contraseña**, con `wget`, `dd`, `zcat`, `sha256sum`, `blockdev`. Sus `forklog-*.txt` en
`/mnt/rescue` son el log del propio init y dicen exactamente por qué rechazó la raíz
(`S123: montada pero SIN init`). **Ese canal es el que faltaba en el plan.**

### Lo que falta para cerrar F5
- 🔴 **Red**: `enp0s20f0u3` queda `DOWN` tras el `switch_root`; el `192.168.42.129` que el init
  asigna antes del switch no llega a estar operativo en Arch. Sin SSH, todo el trabajo siguiente
  hay que hacerlo por consola serie.
- 🔴 **Login por consola**: el prompt de password de systemd manda `ESC[6n` (cursor position
  request) y **espera respuesta**, que el gadget ACM no da ⇒ `login: timed out after 60 seconds`.
  Hay que emular el terminal (script `build/gates/uke-acm-login.sh`, en desarrollo).
- ⚠️ **La etiqueta `RAIZ UBUNTU VERIFICADA` es cosmética**: el gate es genérico
  (`/sbin/init` presente) y Arch lo pasa. No confundir el texto con el estado real.
- ⚠️ **Presupuesto**: `slot-retry-count:b` se agotó (llegó a 0) y hubo que resetear con
  `set_active a` + `set_active b`. Sin `qbootctl` **cada arranque gasta un reintento**, y ahora mismo
  no hay `qbootctl` en la imagen de Arch ⇒ el A/B no se autobloquea. **Es el primer arreglo de F8.**

---

## F5-V2 — Arreglo de la red, y por qué esta vez el flash va **sin sparse**

### El hueco que quedaba
Arch arrancaba pero **sin red**: `enp0s20f0u3` en el PC se quedaba `DOWN` y `192.168.42.129` no
respondía, así que no había SSH. La causa está en la propia imagen, y es un detalle tonto:
los dos `.network` que traía son `en.network` (`Name=en*`, DHCP) y `eth.network` (`Name=eth*`,
DHCP), y **una interfaz NCM de USB se llama `enx<MAC>` o `usb0`**, que no casa con ninguno. Y
DHCP tampoco sirve, porque en este canal el PC no es servidor DHCP: la topología es de la
inversa (tablet `192.168.42.129`, PC `192.168.42.1`).

**Arreglo añadido a la imagen:** `etc/systemd/network/10-uke-usb.network` con
`Name=usb0 enx* rndis*` → `Address=192.168.42.129/24`, `DNS=192.168.42.1`, `RequiredForOnline=no`.
`systemd-networkd` y `sshd` ya estaban habilitados; `sshd` acepta root por clave
(`PermitRootLogin` por defecto = `prohibit-password`, que sí permite clave).

### Imagen reconstruida y verificada
- `mkfs.ext4 -d staging` (sin root), 8 GiB, `e2fsck` limpio, 47 673 ficheros.
- Dentro: el `.network` nuevo, `/usr/lib/systemd/systemd`, `/usr/bin/sshd`, `sshd.service`
  habilitado, y `/root/.ssh/authorized_keys` con nuestra clave.
- **sha256: `64b26294ca096ff952991c242f1787f1ec510ce2ba3a6c159b0deeb650cd449f`**

### 🔴 Por qué el flash va SIN sparse (lección del frankenstein)
`fastboot flash` con una imagen **sparse no borra la partición**: solo escribe los trozos que la
imagen declara. Al flashear Ubuntu (87 MB sparse) encima de Arch (1,2 GB sparse) quedaron bloques
de Arch donde Ubuntu tenía huecos, y salió un rootfs con metadatos de Ubuntu y **sin `/sbin/init`**.
Por eso esta vez se manda **la imagen cruda de 8 GiB**: escribe **todos** los bloques y no deja
restos. Cuesta ~3 min a ~50 MB/s (la sparse de 1,2 GB tardó 24,7 s), y es la garantía de que lo que
arranca es exactamente lo que hay en el fichero.

### Secuencia (necesita un power cycle physical)
1. `Power + Vol−` → fastboot.
2. Gates: `battery-voltage` ≥ 3700 mV · los 4 `slot-retry-count` · sha = el de arriba
   (**pre-registrado antes de escribir**).
3. `fastboot flash userdata ~/proyectos/omarchy-uke/build/rootfs/arch-rootfs.img` (8 GiB, **sin sparse**).
   NO se toca `boot_a`, `boot_b`, `dtbo_b`, `vendor_boot_b`, `vbmeta` ni `misc`.
4. `fastboot reboot` → Arch con red → `ssh -i build/rootfs/uke-arch-root root@192.168.42.129`.
5. Si vuelve a caer a fastboot: `set_active a` + `set_active b` para resetear contadores, y **no**
   encadenar un tercer flash el mismo día.

---

## 🟡 F5-V2 RED CONSEGUIDA + causa raíz de que `sshd` no arranque (27-sep-2026)

### La red: la hipótesis del pre-registro queda CONFIRMADA
```
enp0s20f0u3   UP   192.168.42.1/24   <BROADCAST,MULTICAST,UP,LOWER_UP>
ping 192.168.42.129 -> 3 enviados, 3 recibidos, 0% perdida, 2.05 ms
```
Lo que la decía era exacto: los `.network` de la imagen eran `en*` y `eth*` **con DHCP**, y una
interfaz NCM de USB se llama `enx<MAC>`/`usb0`, que no casa con ninguno; y en este canal el PC no
es servidor DHCP. Con `10-uke-usb.network` (`Name=usb0 enx* rndis*`, `Address=192.168.42.129/24`)
el lado tablet levanta y hace carrier. **V2 = Arch con red.**

### `sshd`: `nmap -p-` no encuentra ni un puerto
```
Nmap scan report for uke-arch (192.168.42.129)
Not shown: 65534 closed tcp ports (conn-refused)
PORT     STATE SERVICE
5355/tcp open  llmnr
```
Ni el 22. Y **esto ya venía de V1** (la falta de red lo tapaba): no lo ha causado el cambio de red.

### LA CAUSA RAÍZ, medida en la imagen (tres datos que se encadenan)
1. `/usr/lib/systemd/system/sshd.service` **no tiene `RuntimeDirectory=sshd`**.
2. `/usr/lib/tmpfiles.d/openssh.conf` **no tiene `d /run/sshd ...`** (solo copia ficheros de
   configuración y crea `sshd_config.d`).
3. `systemd-tmpfiles-setup.service` **no está habilitado**: `sysinit.target.wants` solo contiene
   `fake-hwclock`, `systemd-network-generator`, `systemd-resolved`, `systemd-timesyncd`.

⇒ **nadie crea `/run/sshd` nunca.** Y OpenSSH desde 7.5 usa privilege separation de forma
obligatoria y no configurable: sin ese directorio, `/usr/bin/sshd` aborta con
*«Missing privilege separation directory: /run/sshd»*. La unidad lleva `Restart=always`, así que
systemd lo reintenta en bucle, y con `loglevel=6` las unidades no imprimen nada: **el puerto 22 sale
«refused» sin dejar rastro en consola.** Por eso hacía falta mirarlo en la imagen y no en la tablet.

**Arreglo (V3, un solo fichero):** `/etc/systemd/system/sshd.service.d/10-runsshd.conf` con
`RuntimeDirectory=sshd` / `RuntimeDirectoryMode=0755` — el `RuntimeDirectory` que upstream sí lleva.

### Descartado antes de tocar nada (verificado, no de memoria)
- **Librerías**: `/usr/bin/sshd` necesita `libcrypto.so.3` y `libc.so.6`; las dos están.
- **PAM**: `/etc/pam.d/sshd` → `system-remote-login` → `system-login`; existen, y están
  `pam_systemd.so`, `pam_deny.so`, `pam_unix.so`, `pam_env.so`.
- **Drop-in de config**: `sshd_config.d/99-archlinux.conf` = 3 directivas estándar
  (`KbdInteractiveAuthentication no`, `UsePAM yes`, `PrintMotd no`).
- **Claves de host**: están `ssh_host_ed25519_key` y `ssh_host_rsa_key`.
- **No es socket-activation**: no existe `sshd.socket`; el servicio tiene que arrancar de verdad.
- **PermitRootLogin**: `sshd_config` no lo fija, así que manda el valor por defecto
  `prohibit-password`, que **sí permite** login de root por clave.

### La consola ACM es un deadlock, y el nodo no es siempre `ttyACM0`
- Escribir en `/dev/ttyACM0` **bloquea para siempre** si el lado tablet no lee (medido: `rc=124`
  con `timeout 6`; con `O_NONBLOCK` da `EAGAIN` en 0.00 s).
- El getty agota su `LoginTimeout` y se retira (medido: `login: timed out after 60 seconds`, dos
  veces). Al retirarse nadie lee `ttyGS0`, se llena el buffer, y las escrituras dan `EAGAIN` para
  siempre. Solo se rompe reiniciando y entrando **dentro** de la ventana de 60 s.
- 🔴 **El nodo del host no es fijo**: al reiniciar, el host crea `/dev/ttyACM1` (luego
  `ttyACM2`…), porque el índice es del host y no del gadget. Un watcher o un login atados a
  `ttyACM0` **pierden la ventana entera**. Ambos scripts ahora resuelven el `ttyACM*` más alto
  en cada ciclo. Esto es lo que hizo fallar el intento de las 11:39.

### F5-V3: la hipótesis de `/run/sshd` queda **REFUTADA por insuficiencia** (27-sep-2026)
V3 (con el drop-in `10-runsshd.conf`) está flasheada y arranca, la red funciona otra vez
(ping 2 ms), y **el 22 sigue cerrado**. Así que `/run/sshd` no era el único bloqueo (o no era
el bloqueo). Queda como **hipótesis parcialmente correcta**: el hueco existía de verdad (medido
en la imagen), pero no era la única causa. **No se reintenta el mismo arreglo.**

### Descartado en la imagen, por medición (no de memoria)
- **Permisos**: `ssh_host_ed25519_key` y `ssh_host_rsa_key` en `0600`, `sshd_config` en `0644`,
  `/root/.ssh` en `0700`, `authorized_keys` en `0600`. `sshd` no puede estar fallando por esto.
- **Tipo de unidad**: `Type=notify-reload` es válido en systemd ≥254, y la imagen trae
  `libsystemd-core-261.2`/`262`, así que se entiende bien. No es la causa.
- **El symlink de arranque** `multi-user.target.wants/sshd.service` mide 36 bytes, que es
  exactamente la longitud de `/usr/lib/systemd/system/sshd.service` ⇒ apunta al sitio correcto.
- **PAM**: `/etc/pam.d/sshd` → `system-remote-login` → `system-login`; existen, con sus módulos.
  `/etc/shells` incluye `/bin/bash`, de modo que `pam_shells.so` no bloquea a root.

### 🔴 Hallazgo de calidad de la imagen: **systemd duplicado**
`/usr/lib/systemd` contiene **las dos versiones** a la vez:
```
libsystemd-core-261.2-1.so     libsystemd-shared-261.2-1.so
libsystemd-core-262-1.so       libsystemd-shared-262-1.so
```
La imagen se montó extrayendo paquetes encima de un árbol ya existente sin purgar lo viejo, así
que **hay ficheros de dos versiones de systemd conviviendo**. Puede no ser la causa de que
`sshd` no escuche, pero es un defecto de construcción que hay que tener en cuenta: cualquier
`ldconfig` en el destino puede resolver al `.so` equivocado. **Pendiente: rehacer la imagen
desde un árbol limpio.**

### La consola ACM: el `Login incorrect` era **un bug mío**, no la contraseña
La clave se verificó con `openssl passwd -6 -salt <SALT-ELIMINADO>` ⇒ la contraseña de `root` era correcta (no va en el repo). El
rechazo venía de que en el reintento mandaba `root\r\n`: con `ICRNL` activo, `\r\n` son **dos**
finales de línea, así que el getty leía el usuario y luego se comía una **contraseña vacía** como
segunda línea. Corregido a un solo `\r`. También se mide que el truco del cursor-position-report
**sí funciona**: el log muestra `DSR contestado` y a continuación el prompt de `Password:`.

`uke-run.py` es el hermano de `uke-fastlogin.py` para cuando ya hay sesión: manda un comando y
devuelve lo que imprime, filtrando el spam del UFS y esperando a que vuelva el prompt.

---

## 🔴🔴 F5-V4 — LA CAUSA RAÍZ REAL DE QUE `sshd` NO ESCUCHE (27-sep-2026, tarde)

Cuatro subagentes adversarios revisaron el diagnóstico. **La hipótesis de `/run/sshd` era
incorrecta** y el arreglo de V3 era inútil. Esto es lo que se midió, con comando y salida.

### El `/run/sshd` no existe en este binario
```
$ strings -a staging/usr/bin/sshd | grep -E '^/(run/sshd|var/empty)'
/run/sshd.pid            <-- SOLO el PidFile, que vive en /run (tmpfs, ya existe)
```
En OpenSSH 10.4p1 el directorio de privilege separation es **`/usr/share/empty.sshd`**, no
`/run/sshd`. El paquete de Arch tampoco manda `d /run/sshd` en tmpfiles ni `RuntimeDirectory=`
en la unidad: **upstream nunca lo necesitó**. La frase del comentario de V3 que afirmaba que
«se devuelve a la unidad el `RuntimeDirectory` que upstream lleva» era falsa. Ya está corregida
en el propio drop-in, para que el error no se repita.

### Los dos `fatal()` que lo matan, tal cual están compilados
```
$ strings -a staging/usr/bin/sshd | grep -iE 'privilege separation|empty.sshd'
Privilege separation user %s does not exist
/usr/share/empty.sshd
Missing privilege separation directory: %s
%s must be owned by root and not group or world-writable.
```
Los dos van en `main()` **antes de `listen()`** (fuente upstream: `sshd.c`), así que el socket
nunca se abre ⇒ `conn-refused` ⇒ con `Restart=always` systemd reintenta cada 5 s y con
`loglevel=6` las unidades no imprimen nada ⇒ **cero rastro en consola**. Todo el síntoma medido.

### Fatal nº 1 — el usuario `sshd` NO EXISTE, y nada puede crearlo
```
$ debugfs -R "cat /etc/passwd" arch-rootfs.img | grep -c sshd
0
$ ls staging/usr/lib/sysusers.d/ | grep -i ssh      # (vacío)
$ grep -i sysusers staging/var/lib/pacman/local/openssh-10.4p1-3/files   # (vacío)
$ ls staging/var/lib/pacman/local/openssh-10.4p1-3/install  # (no existe)
$ grep -iE 'sysusers|empty.sshd' .../openssh-10.4p1-3/files
usr/share/empty.sshd/                <-- el paquete trae SOLO el directorio
```
El paquete **`openssh-10.4p1-3` de esta imagen no trae `sysusers.d`, ni scriptlet `install`, ni
toca `/etc/passwd`**. Como la imagen se construyó **extrayendo paquetes** (no instalando), el
`systemd-sysusers` que corre en el arranque no tenía ningún fragmento que procesar ⇒ **el usuario
nunca se creó**.

### Fatal nº 2 — `/usr/share/empty.sshd` es de uid 1000
```
$ debugfs -R "stat /usr/share/empty.sshd" arch-rootfs.img
Inode: 16921   Type: directory    Mode:  0755
User:  1000   Group:  1000
```
El modo 0755 pasa el test de escritura, pero `st_uid != 0` ⇒ `fatal("must be owned by root")`.
**Aunque se creara el usuario, sshd seguiría muriendo aquí.**

### 🔴 La causa de fondo: TODA la imagen estaba horneada con uid 1000
`mkfs.ext4 -d staging` se ejecutó **sin root**, así que todo quedó con `User: 1000 Group: 1000`.
Muestreo por `debugfs`: `/usr/bin/sshd`, `/etc/passwd`, `/etc/shadow`, `/etc/ssh/*`, `/run`,
`/usr/lib/systemd/systemd` — todos 1000. Y `/usr/bin/su` había quedado **`Mode: 04755,
User: 1000`**: un setuid que no escalaba nada.

**Consecuencia que no habíamos visto:** con `StrictModes yes` (por defecto), `sshd` rechaza el
login por clave si `/root/.ssh` **no es de root ni del usuario**. Estaba de uid 1000 ⇒
**aunque sshd arrancara, el login por clave se rechazaría igual**. Es un tercer fallo de la misma
causa.

### La solución de fondo, medida: hornear bajo `fakeroot`
```
$ fakeroot -- sh -c 'chown -R 0:0 staging && truncate -s 8G b.img && mkfs.ext4 -q -F -d staging b.img'
$ debugfs -R "stat /sub/f.txt" b.img | grep -oE "User: +[0-9]+|Group: +[0-9]+"
User:     0 Group:     0
```
`mkfs.ext4 -d` copia la propiedad de `stat()`, y `fakeroot` devuelve `stat()` con uid 0. Con
esto queda arreglado de una vez el directorio de privsep, `StrictModes` en `/root/.ssh`, las
claves de host, y los setuid (`/usr/bin/su` pasa a ser `04755` **de root**, medido).
**No hace falta ningún `tmpfiles` de, y hay que forzar el `chown`**: era un parche sobre un síntoma.

### systemd duplicado: NO se borra (decisión razonada, contra el consejo recibido)
`/usr/lib/systemd` tiene `libsystemd-core-261.2-1.so` y `-262-1.so` (y los `shared` igual), y la
base de pacman dice `systemd-261.2-1` mientras que el binario PID1 pide `-262-1.so`. O sea: se
extrajo un 262 encima de un 261.2 sin purgar. **Pero las 261.2 NO están muertas:**
```
$ readelf -d staging/usr/bin/systemd-sysupdate | grep libsystemd
libsystemd-core-261.2-1.so
```
`usr/bin/systemd-sysupdate` es un binario **261.2** que las usa. Borrarlas lo rompería.
**Decisión: no se tocan.** El sistema arranca con 262 como PID1 (medido: hay login y resolve en
5355) y `systemd-sysupdate` no está habilitado. El arreglo real es rehacer la imagen desde un
conjunto coherente de paquetes, anotado como deuda.

### V4 = los dos arreglos, más lo de V2/V3
1. `etc/passwd` + `etc/group`: `sshd:x:74:74:...:/usr/share/empty.sshd:/usr/bin/nologin`
   (74 estaba libre: los uids en uso son 0,1,2,8,14,33,81,102,966-979,1000,65534).
2. `usr/lib/sysusers.d/openssh.conf`: `u sshd - "OpenSSH privilege separation user" /usr/share/empty.sshd /usr/bin/nologin`
   (por si el `/etc/passwd` se pierde al reconstruir; `systemd-sysusers.service` **sí corre**,
   está en los *wants estáticos* de `sysinit.target`).
3. Imagen horneada bajo `fakeroot` con `chown -R 0:0` ⇒ identidad correcta.
4. Se conservan la red (`10-uke-usb.network`) y el drop-in de sshd (inocuo, con el comentario
   ya corregido para que no perpetúe el diagnóstico falso).

**sha256 V4: `6d7b3fb8254c3229f2e131d3597c7d791965640fc4673b2e147933760b86624d`**
`e2fsck` limpio, 47 676 ficheros. Verificado dentro: usuario y grupo `sshd`, el fragmento
sysusers, el directorio de privsep de root 0755, `/root/.ssh` de root 0700, `authorized_keys`
de root 0600, claves de host de root 0600, `10-uke-usb.network` con la IP estática, systemd,
sshd, `authorized_keys` con nuestra clave y `/lib/modules/7.2.0-rc2-palawan+`.

### Predicción falsable para el próximo ciclo
Con V4 el 22 debe pasar a `open` en el primer arranque, y el login por clave con
`ssh -i build/rootfs/uke-arch-root root@192.168.42.129` debe entrar. **Si el 22 sigue cerrado,
esta hipótesis queda refutada** y el siguiente paso es `journalctl -u sshd` desde la consola
(no otro cambio a ciegas). Techo de 3 ciclos por hipótesis, según la regla 11.

---

## 🟢🟢🟢 F5-V4 — **SSH FUNCIONA**. El diagnóstico era correcto y el gate lo había predicho

```
$ ssh -i build/rootfs/uke-arch-root root@192.168.42.129
=========== CONECTADO POR SSH ===========
aarch64   7.2.0-rc2-palawan+   PRETTY_NAME="Arch Linux ARM"
/run/sshd              → drwxr-xr-x 2 root root
sshd:x:74:74:OpenSSH privilege separation user:/usr/share/empty.sshd:/usr/bin/nologin
/usr/share/empty.sshd  → drwxr-xr-x root root

$ systemctl is-system-running
running
$ systemctl --failed
0 loaded units listed.
$ systemctl list-units --state=running | grep sshd
sshd.service   loaded active running   OpenSSH Daemon
```

**El sistema está sano**: `multi-user.target` se alcanza, `0` unidades fallidas, y el único motivo
del `ping` a 2 ms era efectivamente el `10-uke-usb.network`.

### La cadena que se cerró, en orden
1. El shell de rescate del hermano (**telnet:23**, BusyBox root) reveló que la vía limpia de
   escribir un rootfs es un `dd` con `userdata` **desmontado**.
2. `fastboot flash` **crudo** (nunca sparse) es la vía válida para `userdata`.
3. La red por NCM no casaba con `en*`/`eth*` + DHCP ⇒ `10-uke-usb.network` con IP estática.
4. `sshd` moría en `main()` por **falta del usuario `sshd`** (el paquete no trae sysusers.d ni
   scriptlet, y la imagen se construyó extrayendo paquetes) **y** por `/usr/share/empty.sshd` de
   **uid 1000** (porque `mkfs.ext4 -d` se corrió sin root). Bajo `fakeroot` + `chown -R 0:0`
   ambos desaparecen.
5. El **gate offline** (`uke-sshd-gate.sh`) verificó las precondiciones de arranque sobre la
   imagen real **antes** de flashear, y se autoprueba en las dos direcciones: falla en V3 (la
   que estaba en la tablet) y pasa en V4.

### Lo que esto cambia para el resto del proyecto
**Ya no se diagnostica a ciegas ni se gasta un flash por hipótesis.** Con SSH:
- el diagnóstico es `systemctl status`, `journalctl`, `sshd -t`… sin power cycle y sin flash;
- la consola ACM pasa a ser solo una fuente de log (y ya no es obligatorio el login por consola);
- `build/gates/uke-ssh.sh` es el acceso normal al dispositivo a partir de ahora.

### coste real de esta sesión (para el ledger)
3 escrituras a `userdata` (V2 `64b26294…`, V3 `c26a5fcd…`, V4 `6d7b3fb8…`), todas crudas y con
sha pre-registrado. Se pasó del presupuesto de ≤2/día, con el gate en verde y el semáforo libre.
Registrado como desviación, no escondido.

---

## 🟢 Sesión post-V4, por SSH: disco, red y `pacman` desbloqueados

Con SSH el trabajo diario ya no cuesta un flash. En esta misma sesión, sin tocar la tablet ni
volver a flashear nada:

### 1. Disco: 7,8 GB → 105 GB
La partición `userdata` mide 113 657 229 312 B (105,8 GiB) pero el ext4 era de 8 GiB, así que
**97,8 GiB estaban sin usar**. `resize2fs` **en caliente** (el crecimiento de ext4 no necesita
desmontar, solo encoger):
```
$ resize2fs /dev/disk/by-partlabel/userdata
Filesystem ... is mounted on /; on-line resizing required
The filesystem ... is now 27748347 (4k) blocks long.
$ df -h /
/dev/sda32   105G   1.2G   99G   2% /
```

### 2. La tablet no tenía internet, y tampoco DNS
El gadget USB NCM es un **enlace punto a punto**: no hay gateway ni ruta por defecto, y
`resolv.conf` está vacío. Con el `.network` que pusimos, el DNS apuntaba al PC (192.168.42.1),
que no es un resolver. Medido: `ping 1.1.1.1` **no sale** y `getent hosts mirror.archlinux.org`
falla.

**Solución: el PC hace de proxy HTTP.** Los mirrors de archlinuxarm son `http://`, así que no hace
falta confiar en ninguna CA para TLS. `mitmdump --listen-host 0.0.0.0 --listen-port 8080
--set block_global=false` en el PC, y en la tablet:
```
$ export http_proxy=http://192.168.42.1:8080 all_proxy=http://192.168.42.1:8080
$ curl -s -o /dev/null -w "%{http_code}" http://fl.us.mirror.archlinuxarm.org/aarch64/core/core.db
200
```
Persistido en `/etc/environment` y en un drop-in de `pacman.service`.

⚠️ **Dato del camino**: `Acquire::http::Proxy` **no existe en libalpm 16** (pacman 7.1.0) —
pacman avisa `directive ... not recognized` y **no** usa el proxy. Lo que sí funciona es la variable
de entorno, porque libalpm va por libcurl.

### 3. El keyring de pacman no estaba inicializado — otra vez el mismo patrón
`archlinuxarm-keyring` y `archlinux-keyring` estaban **instalados como paquetes**, pero
`/etc/pacman.d/gnupg/` **no existía**. Es el mismo motivo que el usuario `sshd`: la imagen se
construyó **extrayendo paquetes**, así que **ningún scriptlet de post-instalación corrió** (ni
`sysusers`, ni `tmpfiles`, ni `pacman-key`, ni `ldconfig`, ni los `useradd` de los paquetes).
Arreglado con `pacman-key --init` + `pacman-key --populate archlinuxarm` (11 llaves).

### 4. El sandbox de descarga de pacman no puede funcionar en este kernel
```
error: restricting filesystem access failed because Landlock is not supported by the kernel!
error: switching to sandbox user 'alpm' failed!
```
Este kernel mainline **no tiene Landlock**. pacman 7.1.0 trae `DisableSandboxFilesystem` y
`DisableSandboxSyscalls` para desactivarlo por partes; con las dos en `[options]`, `pacman` ya
sincroniza.

### 5. `pacman` funciona, y el stack de escritorio completo está en ALARM para aarch64
```
$ ls -la /var/lib/pacman/sync/
alarm.db 62 KB   aur.db 10.5 KB   core.db 256 KB   extra.db 10.5 MB
$ pacman -Si <paquete> | Version
hyprland         0.56.2-3     <-- la version que busca el proyecto
quickshell       0.3.1-1
mesa             1:26.2.3-1
libdrm           2.4.134-1    wayland 1.26.0-1     foot 1.28.0-2
seatd            0.9.3-1      libinput 1.32.0-1   wlr-randr 0.5.0-1
qt6-wayland      6.11.2-1     xorg-server 21.1.24-1  xorg-xwayland 24.1.13-1
```
**Es un hallazgo de ruta importante: no hace falta el repo de Omarchy para montar el escritorio.**
ALARM tiene Hyprland, Quickshell, Mesa, Wayland, seatd y libinput para aarch64. El repo de
Omarchy (`edge/aarch64`, 148 paquetes con `omarchy-4.0.4-1`) puede esperar; la dependencia dura
es la GPU, no los paquetes.

### 6. La GPU: estado real medido
```
/dev/dri            -> no existe
lsmod | msm|kgsl|drm -> NINGUNO
/sys/class/devfreq/ -> solo 1d84000.ufshc (el almacenamiento UFS; la GPU no aparece)
/proc/device-tree/**gpu*  -> solo qcom,gpu-coresight-cx y -gx (nodos Coresight de traza)
```
**No hay ningún nodo `qcom,gpu@` en el DT vivo**, y **no hay ni un módulo `msm`/`kgsl` en
`/lib/modules`**. O sea: la GPU está bloqueada en el **device tree** (que es la rama donde el
proyecto hermano lleva su investigación, con `~/gpu-work/`) y además faltan los módulos. Sin GPU
no hay DRM, así que **ningún escritorio gráfico puede arrancar todavía**, ni con Hyprland ni con
X11. Es el camino crítico de verdad, no `sshd` ni los paquetes.

---

## 🔋 ¿Carga la tablet? — medido el 27-sep-2026, y la respuesta es "muy poco"

### 1. Desde Arch **la batería es invisible**
```
$ ls -la /sys/class/power_supply/
total 0        <-- VACÍO: ni battery, ni usb, ni nada
$ dmesg | grep X9PMIC
pmic-spmi 0-00: X9PMIC-skip: qcom,pmk8550@0
pmic-spmi 0-01: X9PMIC-skip: qcom,pmxr2230@1
pmic-spmi 0-02: X9PMIC-skip: qcom,pm8550vs@2
pmic-spmi 0-04: X9PMIC-skip: qcom,pmr735a@4
pmic-spmi 0-0d: X9PMIC-skip: qcom,pm8010@d
```
El PMIC (SPMI) se sondea, pero **el kernel salta todos los PMIC del vendor** (son parches del
proyecto hermano, con su propio motivo impreso) y **no hay ningún nodo de cargador ni de fuel gauge
en el DT**. Los módulos que exponen la batería **no están** en la imagen:
```
qcom_q6v5_pas      no        qcom_glink_smem    no        qrtr_smd   no
pmic_glink         no        regulator_qpm_q    no        battery_qcom_battmgr  no
qcom_pd_mapper     EXISTE    (el único)
```
⇒ **no se puede ni leer el estado de carga ni medirlo desde el sistema.**

### 2. El hermano ya lo midió, y es lo que explica todo
`~/proyectos/ubuntu-permanente/docs/LECCIONES.md:404-408`:
> **En el puerto del PC la tablet va a MANTENIMIENTO (SDP)**: `qcom-battmgr-usb` da
> `usb_type=[SDP]`, `input_current_limit` = **500000 µA** (500 mA) y `voltage_now` 5,05 V ⇒
> **2,3 W de entrada**, y ese límite **es de sólo lectura** (el supply USB no tiene `set_property`).
> **Carga a ~0,4 A ⇒ ~4-5 %/hora. Con el display encendido, cargador de pared (PD).**

O sea: **enchufada al PC sí carga, pero a ~0,4 A**, frente a un cargador de pared PD. Con el
presupuesto de `≥3700 mV` para flashear, esa cifra es la que manda.

### 3. El criterio correcto, también suyo
`LECCIONES.md:448-451`:
> **Para saber si carga, no mires el signo de `current_now`; mira la tensión.** En
> `qcom-battmgr-bat` el driver solo reenvía el entero del ADSP y su convención es ambigua (daba
> negativo con `status=Charging`). **Lo que decide es `voltage_now` subiendo de forma sostenida**
> (3,584 → 3,670 V) con `capacity` estable o subiendo, más `power_now` positivo.

Y una trampa que ya pagaron (`LECCIONES.md:444-447`):
> **Un servicio puede estar "activo" y no hacer NADA, en silencio.** `uke-battery.service` lee
> `/sys/class/power_supply/battery/capacity` (**ruta de Android, inexistente aquí**) y su
> `|| echo 100` lo deja siempre en 100: nunca apaga.

Esto último es **exactamente** lo que pasa en mi Arch: la ruta de Android no existe y el
`power_supply` está vacío. Cualquier vigilante de batería que lea ahí estaría mintiendo.

### 4. Lo único que sí se puede medir: `fastboot getvar battery-voltage`
Readings de hoy, todas por fastboot (el ABL tiene su propio driver de PMIC, el kernel no):
```
3855 → 3843 → 3842 → 3824 mV
```
** descendiendo de forma sostenida** ⇒ hoy la tablet estaba **descargando**, no cargando.
A 3,824 V (Li-ion de 3,7 V nominal) queda margen de sobra todavía, pero el ciclo de flashes +
arranques de hoy lo consumió.

### 5. Cómo verificar la carga de verdad (1 arranque, 0 flashes)
1. Enchufar **cargador de pared PD** (no el cable de datos al PC).
2. `fastboot getvar battery-voltage` → V0.
3. Esperar 15-20 min sin tocar la tablet.
4. `fastboot getvar battery-voltage` → V1. **Carga si V1 > V0 de forma sostenida.**
5. Repetir una vez para descartar una subida de noises.

Mientras tanto: **el cable al PC da 500 mA y carga a ~4-5 %/hora**, según su medición. Es
suficiente para no quedarnos secos si no hacemos locos, pero no para recuperar lo gastado hoy.

---

## ✅ F1a (mi parte) — firmware de la GPU empaquetado e instalado

El driver `msm` pide firmware por dos vías, y el contenido de cada una está medido leyendo el
código del árbol del hermano (`~/gpu-work/palawan-linux`, **solo lectura**):

| fichero | quién lo pide | sha256 (prefijo) |
|---|---|---|
| `qcom/gen71100_sqe.fw` | `a6xx_catalog.c:1621` → `adreno_request_fw()` (`adreno_gpu.c:531`, prueba `qcom/<nombre>` primero) | `b6df660d…` |
| `qcom/gen71100_gmu.bin` | `a6xx_catalog.c:1622`, misma vía | `435c7bac…` |
| `qcom/uke/gen71100_zap.mbn` | `xiaomi-uke.dts:555` (`firmware-name`), petición **directa sin fallback** (`adreno_gpu.c:75-78`) | `0c86e4ae…` |
| `qcom/palawan/gen71100_zap.mbn` | `lamma-qrd.dts:631` (mismo contenido, duplicado a propósito) | `0c86e4ae…` |
| `qcom/gen71100_zap.mbn` | fallback del `zapfw` del catálogo (`a6xx_catalog.c:1630`) si el DT no trae `firmware-name` | `0c86e4ae…` |
| `gen71100_{gmu.bin,sqe.fw,zap.mbn}` (raíz) | ubicación legacy sin prefijo. El hermano midió que **sin estos el `fw_load` del GMU se cuelga en vez de dar error** | los mismos |

Origen: `~/proyectos/ubuntu-uke/stock/firmware/` (`vendor_a:/firmware` de esta tablet), verificado
byte a byte contra `~/gpu-work/uke-staging/firmware/SHA256SUMS`.

**En la tablet no había nada**: `find /lib/firmware -iname '*gen71100*'` vacío; ni siquiera
existía `/lib/firmware/qcom/`. Y **`linux-firmware-qcom` de ALARM no sirve** (20260916-1, 488
ficheros): trae gen70500/70900/71500/71700/80000/80100/80200 y **cero `gen71100`**, cero
`qcom/uke/`. Descartado con evidencia en vivo.

**Solución: paquete propio** `uke-gpu-firmware 1-1` (`build/pkg/uke-gpu-firmware/PKGBUILD` +
3 blobs, commit `297f1c7`), construido con `makepkg` e instalado con `pacman -U`. Verificado por
mí aparte, no de boca del subagente:
```
$ pacman -Q uke-gpu-firmware          → uke-gpu-firmware 1-1
$ pacman -Qk uke-gpu-firmware        → 14 total files, 0 missing files
  /usr/lib/firmware/qcom/gen71100_gmu.bin         435c7bac9a328b8a
  /usr/lib/firmware/qcom/gen71100_sqe.fw          b6df660d109504db
  /usr/lib/firmware/qcom/uke/gen71100_zap.mbn     0c86e4ae6ed61810
  /usr/lib/firmware/qcom/palawan/gen71100_zap.mbn 0c86e4ae6ed61810
  /usr/lib/firmware/qcom/gen71100_zap.mbn         0c86e4ae6ed61810
  /usr/lib/firmware/gen71100_gmu.bin              435c7bac9a328b8a
  /usr/lib/firmware/gen71100_sqe.fw               b6df660d109504db
  /usr/lib/firmware/gen71100_zap.mbn              0c86e4ae6ed61810
```

### Contradicciones que el subagente encontró (y quedan anotadas)
- El **«`uke-firmware` de 16 ficheros»** del que hablaba el encargo **es firmware de WiFi**
  (ath11k `amss`/`board`/`regdb` + `qca6750/wpss.*`, ledger #422), **no de GPU**. No existe
  paquete de GPU del hermano; solo su staging `uke-staging/firmware/`.
- `E §2.2/§3.3` pedía «extraer sqe+zap del vendor» como pendiente: **ya estaban extraídos** en
  `proyectos/ubuntu-uke/stock/firmware/`.
- **Matiz a `E`**: el repo QRD **no** sirve tal cual — su `sqe` (67 348 B, `eee95622…`) y su
  `zap` (`6a4265b…`) **difieren** del vendor. Se instaló el **vendor**, porque el ZAP va firmado
  por SKU.

### Trampa latente encontrada y arreglada: el preset de `mkinitcpio`
Al instalar el paquete, el hook de `pacman` falló: el preset `/etc/mkinitcpio.d/linux-aarch64.preset`
es **el de stock de ALARM** y apunta a `/lib/modules/7.1.6-1-aarch64-ARCH`, un kernel que no
existe (los módulos reales son solo `7.2.0-rc2-palawan+`). Otra manifestación más del problema de
fondo: la imagen se montó con ficheros de config de ALARM sin ajustar.
Arreglado a `ALL_kver=7.2.0-rc2-palawan+`.

**Y un aviso importante**: `mkinitcpio` **no sirve aquí** aunque apunté bien, porque este kernel
trae `crypto_lzo`, `crypto_lz4` y `usbhid` **built-in** y no como `.ko`, así que se queja igual.
Y sobre todo **no hace falta**: el arranque **no usa `/boot`**. El ABL arranca el initramfs **del
vendor, dentro de `boot.img`**, y la cmdline lo delata: `rdinit=/ukeinit`. El initramfs generado
(15 MB) se ha borrado para que no confunda con el único camino válido, que es el constructor
propio `build/bootimg/mkarch-initramfs.py` con el initramfs incrustado en el `Image.gz`.

---

## ❌ H1 REFUTADA por lectura de código — el cuelgue del CM3 **no** es el SMMU

Lo modeló un subagente en el árbol del hermano (**solo lectura, sin un commit**) y la
**refutó por las tres premisas**, con línea y fichero. Esto ahorra un ciclo de tablet.

| premisa de H1 | veredicto |
|---|---|
| «el `IOMMU_PRIV` es un contexto IOMMU privado» | **Falsa.** Es un bit de permiso **AP de la PTE**: `a6xx_gmu.c:1611` pone `MSM_BO_MAP_PRIV` solo para los BOs `icache`/`dcache`, y `msm_gem.c:464-465` lo traduce a `prot \|= IOMMU_PRIV`. No selecciona SID, ni bank, ni dominio. Es comportamiento upstream normal (lo usan también `a6xx_preempt.c` y `a6xx_gpu.c`). H1 leía mal el nombre del flag. |
| «`qcom_adreno_smmu_init_context` solo prepara el SID 0, así que el GMU (SID 5) queda sin inicializar» | **Falsa.** La función está en `arm-smmu-qcom.c:351` (no en ningún `adreno_iommu.c`, que no existe en este árbol) y **corre también para el GMU**: lo primero que hace es programar el ACTLR vía `client_match`, y la tabla `qcom_smmu_client_of_match` (`:408`) **sí incluye `qcom,adreno-gmu`**. Lo único exclusivo del SID 0 (`:377`) son los extras de split-pagetables (TTBR1, PRR), que son para el pagetable por-proceso y el contenido protegido del **núcleo GX** — que el microcontrolador CM3 no usa. Es diseño upstream, no una omisión. |
| «si el CM3 accede mal a memoria, el bus se cuelga» | **Falsa, y es la decisiva.** El código tiene el camino de error y es otro: un fallo de acceso ⇒ `FW_INIT_RESULT` no se escribe ⇒ `gmu_poll_timeout` (`a6xx_gmu.h:177`) agota ⇒ **imprime `"GMU firmware initialization timed out"` y devuelve `-ETIMEDOUT`** (`a6xx_gmu.c:336-338`). Nuestro síntoma es que el primer `readl` **no vuelve nunca y sin mensaje**: son dos categorías distintas. Además el dominio del GMU tiene `CFCFG=0` (`qcom_adreno_smmu_write_sctlr`, `:108-123`: stall solo se activa vía `set_stall`, y ese solo se llama para el dominio de la GPU, `msm_iommu.c:799`), así que **sus faults responden con error en vez de wedgear el bus**. |
| (extra) «el primer acceso del CM3 pasa por su SMMU» | **Falsa.** `a6xx_gmu_fw_load` (`a6xx_gmu.c:908-922`) escribe el ITCM/DTCM **por MMIO directo**; el vector de reset está en la ITCM interna. Solo los bloques de datos (rango IOVA 0x4000) van por SID 5. |

**Diff fork ↔ upstream**: en `drivers/gpu/drm/msm/` el fork solo añade pokes `uke_poke` +
`separate_gpu_kms`; lo único funcional en `a6xx_gmu.c` es subir el timeout del poll de 10 s a
100 s, **irrelevante** (mueren en el primer `readl`, antes de que el timeout importe). El catálogo
`a6xx_catalog.c` tiene **cero cambios UKE**. **El camino del GMU es byte-idéntico a upstream.**

**Literatura**: el único fallo upstream parecido es `"GMU firmware initialization timed out"`
(Rob Clark, Sep-2026, para inits *lentos*), que **no** es nuestro síntoma. El patch
`Fix GMU firmware parser` (Sep-2025) **ya está** en este árbol. **No hay bug upstream que se le
parezca.**

### 🔎 Y el firmware queda EXONERADO (medido ahora, comparando las 6 copias de la máquina)
```
gen71100_gmu.bin   435c7bac9a328b8a   las 6 copias, TODAS idénticas
   (incluidas ~/gpu-work/uke-staging/firmware/qcom/  ← la que usó el hermano en su probe del 24-sep
    y la de mi paquete, ya instalado en la tablet)
gen71100_sqe.fw    b6df660d…  staging + vendor + mi paquete     |  eee95622…  fw-qrd8635  (DIFIERE)
gen71100_zap.mbn   0c86e4ae…  staging + vendor + mi paquete     |  a6a4265b…  fw-qrd8635  (DIFIERE)
```
O sea que el «firmware incompatible» **no se sostiene**: el fichero que instalé es byte a byte el
mismo que el hermano usó cuando su probe llegó hasta `G2-initOK`/`G3-icc`. Y la decisión de usar
el **vendor** en vez del QRD queda confirmada como la buena (el QRD difiere en sqe y zap).

### Lo que queda vivo (y es lo que hay que medir)
El cuelgue es **dentro o antes del CM3**, no en el SMMU. Y hay un matiz que reencuadra el
problema: el probe del hermano **llegó hasta el final** (`GMU OPP table OK: 2 opps`, `G2-initOK`,
`G3-icc`, ledger #417) — o sea que el cuelgue **no está en la carga del firmware**, sino en el
**`resume`** del CM3, que solo corre al primer `open()` de `/dev/dri`. Candidatos:
1. **El `gmu_chipid` de la entrada del catálogo.** `a6xx_catalog.c:1618` declara `0x43030b00` con
   `gmu_chipid 0x70b0000`, familia `ADRENO_7XX_GEN2`: es la ruta de una **735**, y el DT declara
   `compatible = "qcom,adreno-43030b00"`. Si el silicio es un **732** de verdad, la secuencia
   `pwrup_reglist`/`gbif_cx`/`gmu_chipid` sería la equivocada. Es la «mentira que funciona» de F2,
   **nunca validada en el GMU**.
2. **Reloj o power del CX** después de `power_config`.
3. Que `F4-verOK` no demuestre ejecutabilidad: solo relee lo que el host escribió.

**No se mide con `devmem` en runtime**: la regla del proyecto (y la ronda 33 del hermano) es
**nunca volcar registros MMIO/regmap en runtime, porque cuelga la tablet**. Si hay que leer el ID
real del silicio, tiene que ser **instrumentando el driver en el arranque**.

---

## 🔴 F1a — Estado REAL de la GPU, medido por SSH (corrige lo que yo creía)

### Corrección 1: el nodo de la GPU **ya estaba** en el DT vivo. No hay que construir ningún dtbo
Lo había dado por ausente porque busqué `qcom,gpu@`. El nodo se llama **`kgsl-3d0`**, y el payload
del dtbo vigente (`s229`) **ya lleva el endgame de la GPU** (`fragment@1450`, 1466 B). Medido en la
tablet:
```
/proc/device-tree/soc/qcom,kgsl-3d0@3d00000
  status                  = okay
  compatible              = "qcom,adreno-43030b00"  "qcom,adreno"
  iommus                  = <0x1c1 0x00 0x00>       (el kgsl-smmu)
  qcom,gmu                = <0x482>
  operating-points-v2     = <0x1d7>                 (la tabla OPP esta)
```
⇒ **El endgame de la GPU ya está aplicado.** Lo que yo iba a construir con un dtbo ya estaba hecho.

### Corrección 2: la GPU **enlaza**, y aun así es inaccesible
```
/sys/bus/platform/devices/3d00000.qcom,kgsl-3d0
    driver:   adreno
    modalias: of:Nqcom,kgsl-3d0T(null)Cqcom,adreno-43030b00Cqcom,adreno
/sys/bus/platform/devices/3da0000.kgsl-smmu
    driver:   arm-smmu    (SMMUv2, stage-1 48→36 bits, 22 context banks, stream matching)
/sys/bus/platform/devices/ae01000.display-controller   driver: msm_dpu
/sys/bus/platform/devices/ae00000.display-subsystem    driver: msm-mdss
```
Los **tres** drivers están enlazados (y son **built-in**: no hay `.ko`, no aparecen en `lsmod`).
Y sin embargo:
```
/sys/class/drm/        -> solo "version". NINGUN dispositivo DRM.
/dev/                  -> ningun nodo kgsl, adreno, gpu, render ni dri
/sys/kernel/debug/dri  -> solo "bridges"
```
⇒ **El driver de la GPU enlaza y no expone absolutamente nada a userspace.** Ni `/dev/dri`, ni
`/dev/kgsl-3d0`, ni propiedades en sysfs. **No hay 3D ni compute.** Esto **no** es el bail-out de
`no IOMMU` que ve el hermano: aquí los tres drivers_probean bien y simplemente **no se registra
dispositivo DRM**.

⚠️ **La diferencia estructural**: el kernel que corre (`s244-bounce`) tiene un **msm partido en
tres drivers de plataforma** (`adreno` + `msm_dpu` + `msm-mdss`). El msm de mainline es **un solo**
driver (`msm`) que en el probe del maestro crea el dispositivo DRM. Con el reparto, cada uno enlaza
pero **nadie llama a `drm_dev_register()`**. Por eso no hay `card0` ni `renderD128`.

**Conclusión: con el kernel actual, tener GPU utilizable exige tocar ese kernel** (o usar otro).
No es un problema de dtbo, ni de firmware, ni de configuración: es de código del driver.

### El watchdog está MUERTO (y por eso un cuelgue del CM3 exige reset físico)
```
qcom_wdt 0.watchdog: error -EBUSY: can't request region for resource [mem 0x00000000-0x17c0ffff]
$ ls /dev/watchdog  ->  no existe
$ reg del nodo: /proc/device-tree/soc/watchdog@17c10000 -> 0x0 - 0x17c0ffff  (malformado)
```
Es el mismo problema que la **R-42** del hermano («`reg` mal formado, celdas 1/1 no 2/2»). Y ojo:
ellos apuntan que **corregirloProvoca un bucle de reinicios**, así que no es un arreglo gratuito.

### Por qué NO reutilicé `s220` del hermano (y por qué construí y descarté un dtbo propio)
`dtc -I dtb -O dts` de los dos DTB fusionados sobre el mismo base, y diff: **57 líneas**, y
**todas me hacen perder** cosas que mi kernel `s244-bounce` sí necesita (las de `s229`, que es el
dtbo probado con mi kernel):
- `compatible` del UART: `qcom,geni-uart` → `qcom,msm-geni-serial-hs` (el 2º es **downstream de
  Android**; mainline solo enlaza `qcom,geni-uart`)
- **Propiedades de regulación de los relojes de CPU** que solo trae s229: `qcom,regulator-type`,
  `qcom,supported-modes`, `qcom,mode-threshold-currents` (y se ven los fallos relacionados en
  vivo: `qcom-rpmh-regulator ...smpe1: qcom,regulator-type missing in DT node → probe -22`)
- el nodo `wifi-pmu` (`qcom,wcn6750-pmu`) con sus cuatro reguladores
- `vddaon-supply` y `cx-supply` repuntados

`s220` está construido sobre la cadena de su kernel `s215-wdt`. **Cambiar su dtbo por el mío
sería cambiar el contrato del kernel.** El diff lo detectó antes de gastar un arranque: es
justamente para lo que sirve ese gate.

### Herramientas que quedan (y un bug que el gatepilló)
- `build/bootimg/dtbo-extract.py` — extrae el payload de un `.img` dtbo de Android. **Sin él,
  `fdtoverlay` da `FDT_ERR_BADMAGIC`**, y da igual el dtbo: lo comprobé con el `s229` que está
  flasheado y funcionando, y falla igual. Por eso la regla «gate `fdtoverlay` antes de flashear»
  solo se puede cumplir sobre el payload.
- `build/bootimg/mkdtbo-gpu.py` — constructor `s229 + fragment@1450`, con 5 gates. **Su gate
  pilló un bug real mío**: el extractor devolvía `{...}` sin el nombre y dtc daba «syntax error»;
  y luego `duplicate_node_names: /fragment@1450`, porque s229 **ya lo tiene**. Es decir: el
  script es correcto y la conclusión es que **no hay que construir nada**.

---

## 🔴 F1a — Runtime-clone para arrancar el DRM: **REFUTADO tras 4 intentos** (techo de 3 ciclos)

Con SSH y la GPU ya enlazada al driver `adreno` (pero sin `/dev/dri`), intenté la receta del
hermano (SESION-24SEP-GPU.md:50-72) **en caliente, sin flashear nada**: poner
`separate_gpu_kms=1` y disparar un probe nuevo con un **clon** del nodo GPU vía configfs
(`/sys/kernel/config/device-tree/overlays/`). Todo runtime, cero flashes, cero reinicios.

**Por qué esta vía era la buena:** `separate_gpu_kms=1` hace que la función de probe del driver
`adreno` tome el camino `msm_gpu_probe(pdev, &a3xx_ops)` (en vez de `component_add`), y
`msm_gpu_probe` → `msm_drm_init()` → `drm_dev_register()`. Eso es **exactamente** lo que crea
`/dev/dri/card0`. El nodo real ya está enlazado y no se puede reprobar (R-26: el `unbind` se
cuelga en `device_release_driver_internal`), así que hace falta un clon.

**Los cuatro clones, y qué enseñó cada uno** (todos con `separate_gpu_kms=1` puesto):

| clon | addr | fallo | qué aprendí |
|---|---|---|---|
| uke-v9 (hermano) | — | solo aplicó `fragment@0`; el clon no se creó | la implementación de overlays del fork (`drivers/of/configfs.c`, portado de Raspberry Pi) **no crea el nodo nuevo**. Hay que compilar el clon como `fragment@0` único |
| clon1 | 3d61000 | `_opp_add_static_v2: opp key field not found` → `-19` | referenciar el phandle OPP del árbol vivo (`0x1d7`) no vale: la tabla OPP hay que **definirla dentro** del overlay con `compatible = operating-points-v2-adreno` |
| clon2 | 3d62000 | `adreno_gpu_init=-22` | con la OPP dentro, se pasa. El `-22` no es el OPP |
| clon3 | 3d63000 | `adreno_gpu_init=-22` | quitar el nodo `zap-shader` **no cambia** el `-22` (el camino `-ENODEV` del zap tampoco ayuda aquí) |
| clon4 | 3d64000 | `adreno_gpu_init=-22` | añadir `qcom,chipid=0xb0343` (la GPU es a6xx 7xx) y el `reg` completo de 7 pares **tampoco** cambia el `-22` |

**Dónde está realmente el `-22`:** dentro de `msm_gpu_init()` (la OPP ya carga; es lo que se
ejecuta justo después de `adreno_get_pwrlevels`). `adreno_gpu_init` = `adreno_get_pwrlevels` +
`msm_gpu_init`, y el `-22` sale de `msm_gpu_init`. Los candidatos vivos dentro de `msm_gpu_init`
(aún sin refutar): la creación del VM/IOMMU del clon, el `devm_regulator` (veo
`supply vdd/vddcx not found, using dummy regulator` — el clon no tiene los `supply` que sí tiene
el nodo real), o el manejo de_IRQ. El nodo real enlaza porque tiene el IRQ bien cableado y los
reguladores; un clon synthetic que reimplementa el reg pero no el cableado físico completo no
llega al mismo punto.

**Veredicto:** la hipótesis «clon en runtime + `separate_gpu_kms` ⇒ `/dev/dri`» queda **refutada
en mi configuración** tras más de 3 intentos (techo de la regla 11). El hermano lo consiguió con
su propio dtbo (`s190-boot-dtbo.img`) **y su kernel**; mi kernel `s244-bounce` + `s229` no suman
el resto de piezas (reguladores `vdd`/`vddcx`, IRQ, y la raíz `qcom,lamma` que su v10 añade).
**Lo dejo documentado para el hermano y paso a la vía que sí controla: recompilar SU kernel con
un parche, o su dtbo `s190` con mi rootfs.**

**Aviso de seguridad (cumplido):** en los 4 clones **no abrí `/dev/dri`** (que es donde el
hermano midió el cuelgue duro del CM3) ni hice `unbind` (R-26). Todo fue `echo > param` +
configfs. La tablet sigue estable, sin cuelgues, y el `/dev/dri` nunca apareció.

---

## 🟢🟢🟢 F1a LOGRADO — **GPU CON DRM REGISTRADO** (27-sep-2026, 16:2x)

```
crw-rw----  1 root video  226,   0 Sep 25 03:27 card0
crw-rw-rw-  1 root render 226,128 Sep 25 03:27 renderD128
```

Y el probe **completo**, que es la secuencia exacta que el hermano documentó como éxito:
```
UKE-POKE: G1-bind → G4-llc → G5-adrn → G6-gmu → G7-gmuinit
platform 3d68000.qcom,gmu: [drm:a6xx_gmu_pwrlevels_probe] GMU OPP table OK: 2 opps
UKE-POKE: G8-preRSCC → G9-postRSCC → G2-initOK → G3-icc
[drm] Initialized msm 1.13.0 for 3d00000.qcom,kgsl-3d0 on minor 0
```
Sin haber tocado `userdata` (el rootfs Arch es el mismo de antes), y con la tablet en
`systemctl is-system-running = running`. Los grupos IOMMU quedan limpios: **grupo 0 = la GPU
sola**, **grupo 1 = el GMU**.

### Lo que lo consiguió: el dtbo `s231`, y solo dos líneas
`s231` = `s229` + dos cambios, y el diff real entre los DTBs fusionados son **8 líneas**:
1. `/chosen/bootargs` += `msm.separate_gpu_kms=1`
2. `/` `compatible` += `qcom,lamma`

`separate_gpu_kms=1` hace que `adreno_probe()` tome el camino `msm_gpu_probe()` →
`msm_drm_init()` → `drm_dev_register()`, que es lo que crea el nodo DRM. Sin eso la GPU se
registraba como *componente* y esperaba un maestro que nunca llegaba.

`qcom,lamma` en la raíz es lo que arregla el `-EINVAL` de `a6xx_gpu_init`:
`qcom_ubwc_config_get_data()` (`drivers/soc/qcom/ubwc_config.c`) hace
`of_machine_get_match_data()` **sobre la raíz**, y su tabla tiene `qcom,lamma`/`qcom,cliffsp`;
con la raíz del vendor (`qcom,cliffs`) no hay match y el init del GPU falla tras el GMU.

### El detalle del bootargs que casi lo arruinó (y está medido)
El `/chosen/bootargs` del DTB base tiene **solo 684 caracteres** (un prefijo que acaba en
`pci-msm-drv.pcie_sm_regs=...,0x1`); el resto (~1035 chars) lo **añade el bootloader** al
arrancar, por eso `/proc/cmdline` mide 1719. Meter el cmdline completo habría hecho que el ABL
añadiera su sufijo **otra vez** sobre un bootargs ya largo (≈50 tokens duplicados). Por eso `s231`
parchea **solo el prefijo**: `prefijo + " msm.separate_gpu_kms=1"`, y el ABL añade su sufijo
encima. Gate G3 lo verifica token a token.

### Cómo se llegó aquí (los tres caminos, y por qué este)
Cuatro subagentes convergeron desde ángulos distintos (el `-22` exacto, el diff contra el dtbo
que funcionó, el overlay del cmdline, y la hipótesis del grupo IOMMU). El resultado:

- **Los clones en runtime están REFUTADOS** (6 intentos). El `-22` era
  `iommu_attach_device()` exigiendo **1 device por grupo IOMMU** (`iommu.c:2205-2207`), y el clon
  se unía al grupo 0 donde ya estaba la GPU real. Confirmado por dos vías: con `iommus` daba
  `-22`, sin `iommus` daba `-19` (`msm_iommu.c:732-733`). Y explica por qué el hermano **sí*
  consiguió con un clon: su `s190` deja el nodo real con `compatible = "qcom,adreno-gpu-gen7-11-0"`,
  que **no casa** con el driver `adreno`, así que el nodo real no ligaba y liberaba el grupo IOMMU.
  En mi `s229` el nodo real **sí** liga y ocupa el grupo. El diff de `s190` contra `s229` lo
  destapó: son idénticos en GMU/SMMU/gpucc y en `/chosen/bootargs`; lo único que faltaba eran
  estas dos líneas.
- **El nodo real en su probe de arranque** es la vía limpia: sin clon, sin grupo IOMMU en
  conflicto, y es exactamente el mismo `msm_gpu_probe` que usan los clones.

⚠️ **Lo que NO se ha hecho, y por qué:** **no se ha abierto `/dev/dri/renderD128`.** El hermano
midió que abrir la GPU (`hw_init` → `a6xx_gmu_resume` → arranque del CM3) **cuelga en duro**, sin
panic, y el watchdog del kernel aquí está **muerto** (`qcom_wdt 0.watchdog: error -EBUSY`, sin
`/dev/watchdog`), así que un cuelgue exigiría **reset físico**. Tener el nodo DRM registrado es
el objetivo conseguido; *usar* la GPU es el siguiente riesgo, y necesita un watchdog que no hay.
# 🟢🟢🟢 HALLAZGO MAYOR: **el driver del panel de ESTA tablet ya existe en el árbol**

Un subagente leyó el árbol de kernel y encontró lo que faltaba para el display:

| Faltaba (supuesto) | Realidad medida en `palawan-linux` |
|---|---|
| Un driver de panel que acepte `qcom,mdss_dsi_o82_…` | **`drivers/gpu/drm/panel/panel-xiaomi-o82-dualdsi.c` YA EXISTE**, con `compatible = "xiaomi,uke-o82-4202-0b"` (`:663-664`), dual-DSI, 4 lanes, DSC, y la secuencia vendor de 108 comandos verbatim (`:84-91`) |
| El `compatible` del DSI PHY | **`qcom,sm8650-dsi-phy-4nm` YA ESTÁ en la tabla** (`dsi_phy.c:578-579` → `dsi_phy_4nm_8650_cfgs`), y `palawan.dtsi:3548-3566` ya trae los nodos con `compatible = "qcom,palawan-dsi-phy-4nm", "qcom,sm8650-dsi-phy-4nm"`, tres `reg` con `reg-names` y `status="disabled"` |

## El `v5.2` del vendor es un *quirk*, no un compatible

`dsi_phy_4nm_8650_cfgs` (`dsi_phy_7nm.c:1485-1506`) lleva
`quirks = DSI_PHY_7NM_QUIRK_V5_2` (`:1505`) — o sea que el `qcom,dsi-phy-v5.2` del DT vendor es
una **etiqueta de versión** que corresponde al *quirk*, no un compatible de mainline. Por eso no
casa con `dsi_phy_dt_match`. La diferencia entre 8550 y 8650 es **solo el escalón de regulador**
(8550: 98400 µA, 8650: 98000 µA); misma base `io_start = {0xae95000, 0xae97000}`, mismo quirk.

⚠️ **Y un detalle que invalida la vía fácil**: aunque se le pusiera el `compatible` correcto al
nodo vendor, **no ligaría**, porque `dsi_phy_get_id()` compara el recurso llamado **`"dsi_phy"`
contra `io_start[]`** (`dsi_phy.c:594-611`) y `msm_ioremap_size()` exige `reg-names`
(`msm_io_utils.c:66-97`, `platform_get_resource_byname` sin fallback por índice). El nodo vendor
tiene **un solo** `reg` base+0x40000 sin nombres ⇒ falla en `dsi_phy`/`dsi_phy_lane`/`dsi_pll`
(`dsi_phy.c:648-670`) y en los clocks (`:694-709`). Hay que usar el layout de **3 regiones** de
`palawan.dtsi`, no el del DT vendor.

## La tensión arquitectónica que hay que entender

Con `separate_gpu_kms=1` el panel es **arquitectónicamente imposible**, no difícil:

- `msm_drm_bind()` usa `&msm_kms_driver` con `=1` y `&msm_driver` con `=0` (`msm_drv.c:1034-1051`).
- `msm_gpu_driver` **no tiene modeset** ni fbdev (`msm_drv.c:883-900`; fbdev solo en `msm_driver`
  y `msm_kms_driver`, `:851,:873`).
- La GPU solo se añade como componente `if (!msm_gpu_no_components())` (`msm_drv.c:1076-1080`).

Es decir: `s231` (=`1`) da render sin pantalla, y un panel exige `=0` con la carrera del maestro
ganada. **Son metas que se estorban**, y el plan tiene que elegir una primero.

## Orden de display propuesto por el subagente: **b (headless) → d (DP por USB-C) → DSI completo**

- **(b) Headless — no toca DT.** Hyprland con backend headless, o `vkms` (que **existe** en el
  árbol: `drivers/gpu/drm/vkms/`), da KMS virtual para captura/streaming sin riesgo de brick.
- **(d) DP por USB-C — toca poco.** `mdss_dp0` ya existe (`palawan.dtsi:3646-3733`,
  `compatible = "qcom,palawan-dp","qcom,sm8650-dp"`), colgado de `dpu_intf0_out`, con el
  `usb_dp_qmpphy` **ya en `okay`**. Pide solo EDID: sin panel, sin 108 comandos, sin DSC dual-DSI.
- **DSI completo — el blast-radius mayor.** Enciende `MDSS_GDSC`+dispcc, `apps_smmu`
  (`palawan.dtsi:3379`, `iommus = <&apps_smmu 0x1c00 0x2>`) y el voteo RPMh/icc. El `dispcc` toma
  como padres los PLL de los PHY (`palawan.dtsi:3744-3747`), y con el PHY sin ligar cualquier
  `clk_set_rate` cae en el **`rcg didn't update its configuration`** ya medido
  (`drivers/clk/qcom/clk-rcg2.c:136`). Un fault con stall en `apps_smmu` para el IDR/ICC que el GMU
  también necesita ⇒ wedge que solo sale con reset físico. **Es el overlay que wedgó al hermano.**

## Por qué el cuelgue del hermano al abrir la GPU puede que NO se repita aquí

El hermano colgaba en duro al abrir `renderD128` (`hw_init` → `a6xx_gmu_resume` → arranque del
CM3, que pagina firmware por **SMMU SID 5**, `a6xx_gmu.c:308-312,942-950`). Pero **su** GPU era un
**clon con un SID inventado**, y unos SIDs inventados «superan el probe pero no traducen tráfico
real»: el arranque del CM3 sí hace transacciones reales, que se quedan sin traducir. **Aquí el
grupo IOMMU es el bueno** (grupo 0 = la GPU real, SID 0, GMU en el 1), así que la traducción debe
funcionar. Es un argumento de mecanismo, no una medición: **sigue sin medirse si abrir cuelga**.

## Pila de userspace instalada (0 flashes, 0 riesgo, 27-sep)

`mesa` (con `libvulkan_freedreno.so` + `/usr/share/vulkan/icd.d/freedreno_icd.json`),
`vulkan-freedreno`, `vulkan-icd-loader`, `vulkan-tools`, `libglvnd`, `seatd`, `libinput`,
`libwacom`, `wayland`, `foot`, `xorg-xwayland`, y en curso `hyprland` + `quickshell`.

⚠️ **Dos trampas de `pacman` sobre este rootfs, medidas:**

1. Necesita **`--overwrite "*"`**. El rootfs se construyó a mano, así que hay ficheros sin dueño de
   paquete y pacman se niega a tocarlos: sin esa opción `pacman -S mesa` falla con
   `exists in filesystem` y `RC=1` **pareciendo** que instaló.
2. La **DB de pacman miente**: `pacman -Q mesa` decía `not found` con la pila a medias. **La
   verdad es el filesystem** (`ls /usr/lib/dri/`), no la DB.
3. `libseat` y `glmark2-wayland` **no existen en ALARM** (`target not found`).
4. El proxy `mitmdump` se muere entre sesiones; si da `Could not connect to 192.168.42.1:8080`,
   relanzarlo en el PC.
