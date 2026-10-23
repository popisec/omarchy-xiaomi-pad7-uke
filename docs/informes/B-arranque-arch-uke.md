# B — Arranque de Arch Linux ARM (aarch64) + kernel propio en la Xiaomi Pad 7 «uke» (SM7675/cliffs)

> ## ⚠️ Nota de vigencia (1-oct-2026)
> Este informe es **referencia de método** (arranque por `boot.img` de Android, BCB, slots sin
> UEFI). Sus **shas y su par «vigente» son históricos**: el `s240-mem2g` y el shell `s244-bounce`
> que se citan (L307, 867-868, 966, 972) se	superaron el 26-sep y el 30-sep. El par que hay hoy
> en la tablet se lee en `build/gates/SHA-BUENOS.txt` y en `docs/historia/ESTADO-VIVO.md`.

> **Pregunta que responde:** cómo se instala y se hace arrancar **Arch Linux ARM aarch64 con kernel propio**
> en esta tablet, **sin UEFI y sin Limine**, usando **`boot.img` de Android** con **AVB** y **slots A/B**.
>
> **Método:** investigación web con fuentes citadas (URL en cada afirmación) + lectura **solo lectura** de
> los artefactos reales del proyecto en `pc-build` (`~/gpu-work/ramaa/s21/`, `~/gpu-work/initramfs-uke/`,
> `~/proyectos/ubuntu-permanente/{docs,bin}/`) + lectura en vivo del dispositivo por el doble salto SSH.
> Todo lo que no está verificado lleva **«(no verificado)»**.
>
> **Fecha:** 26-sep-2026. **Estado del dispositivo ese día:** arranca Ubuntu 24.04 arm64 con kernel propio
> `7.2.0-rc2-palawan+ #82` vía `rdinit=/ukeinit`; slot **b** activo; `misc` con BCB sucio; ext4 con
> ~908 errores; en fastboot **no carga**.

---

## 1. Resumen ejecutivo

### 1.1 La respuesta corta

**Sí es viable, y el camino es «cambiar el rootfs y conservar entre el 80 % y el 90 % del arranque que ya
funciona».** No hay que inventar un bootloader: el **ABL** de Qualcomm, en `abl_a`/`abl_b`, hace hoy
exactamente el trabajo que en un PC hace UEFI + el bootloader. La tabla de particiones ya está hecha y los
slots A/B ya existen. Lo que hay que sustituir es **el contenido del rootfs** (Ubuntu → Arch ARM) y **la
pieza que lo monta** (el `ukeinit` actual → un initramfs de Arch).

Lo que **no** cambia y es la columna vertebral del arranque:

| Pieza | Estado | Por qué se conserva |
|---|---|---|
| **ABL** (`abl_a`=`sde8`, `abl_b`=`sde36`) | **intocable** | Es el bootloader. No hay U-Boot público para SM7675 (el repo `palawan-mainline/u-boot` está **vacío**; el teléfono más nuevo en mainline es SM7635) — `docs/MIGRACION-PORT-MODERNO.md` Fase 2, leído en `pc-build` |
| **`boot_b`** (`sde39`, 96 MB) | **se reescribe** | Aquí va el `boot.img` con **nuestro** kernel + **nuestro** initramfs |
| **`dtbo_b`** (`sde43`, 24 MB) | se conserva al principio | Los fragmentos vendor (rieles del panel, `gpucc`, watchdog) siguen haciendo falta hasta que el **DT propio** los absorba |
| **`vendor_boot_b`** (`sde49`, 96 MB) | **stock, NO TOCAR** | El ABL concatena su ramdisk al nuestro; su `/init` **sobrescribe** el nuestro. De ahí viene `rdinit=/ukeinit` (ver §4.1) |
| **`userdata`** (`sda32`, 105,9 GB ext4) | **se reemplaza** | El rootfs Arch vive aquí. Es el modelo estándar de pmOS y es **DIRECTO**: la partición es de 105,9 GB y el sistema sólo ocupa 7,8 GB |
| **`misc`** (`sda12`, 4 MB) | **hay que limpiarla** | Tiene grabado el BCB `reboot-bootloader` ⇒ el próximo reinicio puede caer a fastboot |
| **GPT (atributos de slot)** | **sólo vía `fastboot set_active`** | R11 de `docs/REGLAS-PARTICIONES.md`: editar attrs por `dd` **causó el brick del 11-sep-2026** |

### 1.2 El flujo de arranque propuesto, de fastboot a sesión gráfica

```
  [1] PC: se prepara el rootfs Arch ARM aarch64 (en el PC, por chroot emulado aarch64)
  [2] PC: se compila el kernel palawan (Image.gz) con el config de referencia
  [3] PC: se construye el initramfs propio (busybox + /init que monta userdata y hace switch_root)
  [4] PC: se empaqueta el boot.img con el PATRÓN DEL PROYECTO (header v4, kernel@4096, cmdline byte a byte, AVB intacto)
  [5] PC: e2fsck en frío sobre userdata + backup del par bueno + limpieza de misc
  [6] Tablet → fastboot (adb reboot bootloader o Power+Vol-)
  [7] fastboot flash boot_b  arch-uke-boot.img        ← sha256 pre-registrado
  [8] Verificación: fastboot getvar current-slot / retry-count / unbootable
  [9] set_active b AL FINAL (R2/RX) + reboot
[10] ABL: lee misc(BCB) → GPT(flags de slot) → carga boot_b + concatena vendor_boot_b
[11] Kernel palawan arranca con la cmdline de la cabecera → rdinit=/ukeinit  (alias de nuestro initramfs)
[12] Initramfs propio: pseudofs → gadget ACM+RNDIS → IP 192.168.42.129 → shell en ttyGS0 → mount userdata → switch_root
[13] Arch ARM: /sbin/init (systemd) desde userdata
[14] systemd: multi-user → servicios uke-* (ADSP/charger_pd, watchdog, batería)
[15] (se está trabajando en paralelo) Hyprland 0.56 + Quickshell + capa tablet
```

**Latencias medidas hoy (línea base a batir):** `systemd-analyze` en el sistema Ubuntu actual →
**15,710 s de kernel + 9,646 s de userspace = 25,356 s**; `multi-user.target` a los **896 ms**.

### 1.3 Qué me da Arch ARM y qué no

| Necesidad | Quién lo cubre en Arch ARM | Veredicto |
|---|---|---|
| Rootfs aarch64 genérico | **`ArchLinuxARM-aarch64-latest.tar.gz`** — tarball «aarch64 Multi-platform», y su página de descargas lo dice explícitamente: *«our package repositories work with any ARM device compatible with … ARMv8-a AArch64 instructions. Simply download the tarball that best fits and **supply your own kernel**»* — https://archlinuxarm.org/about/downloads | **DIRECTO** |
| Soporte del dispositivo | **No existe**. `archlinuxarm.org/platforms` **no lista ningún Qualcomm SM7675/SM8635/cliffs/Xiaomi** — la lista son OlinuXino, Chromebooks, BeagleBone, ODROID, RPi, DragonBoard 410c, Pine64… https://archlinuxarm.org/platforms | **lo pone el proyecto** |
| Kernel | **`linux-aarch64`** (PKGBUILD con `arch=('aarch64')`, multi-platform, mantenido por Kevin Mihelich / graysky) — https://github.com/archlinuxarm/PKGBUILDs/blob/master/core/linux-aarch64/PKGBUILD | **no sirve tal cual** (§5): es multi-platform mainline y le falta **todo** el bring-up de palawan/cliffs |
| Port oficial aarch64 | **No hay port oficial.** `ports.archlinux.page/aarch64` dice literalmente **«Status: Unofficial / RFC: None»** y avisa: los paquetes *«are not built with Arch Linux infrastructure, are not signed by Arch Linux Staff, and are not hosted on Arch Linux domains/mirrors»*. El RFC está **propuesto**, no aceptado — https://ports.archlinux.page/aarch64 y https://rfc.archlinux.page/0032-arch-linux-ports | **terceros, con matiz** (§2) |
| ¿Hay «postmarketOS para Arch»? | **No.** pmOS es Alpine/musl con `apk`. Lo que sí existe es una **implementación independiente** del flujo pmOS hecha por **Linux-for-Fydetab-Duo** (§3). **danctnix** es un port Arch ARM de terceros orientado a dispositivos Pine64/Qualcomm-aarch64 (no verificado en detalle aquí) | referencia, no dependencia |

---

## 2. Arch Linux ARM en dispositivos sin UEFI

### 2.1 El modelo de instalación real (y por qué encaja como un guante)

Arch Linux ARM **no tiene un instalador**. Tiene **tarballs de rootfs** + una **wiki de instrucciones por
dispositivo**. La página de descargas lo formula sin ambigüedad:

> *«Since Arch Linux ARM is a rolling distribution, you never need to download new releases or run special
> upgrade scripts. The entire system is kept up-to-date by running one command: `pacman -Syu`. The only time
> you have to download a full Arch Linux ARM root filesystem is when you're installing for the very first time.»*
> — https://archlinuxarm.org/about/downloads

Los tarballs se firman con la clave `68B3537F39A313B3E574D06777193F152BDBE6A6` (misma clave que firma los
paquetes), y hay `.md5` + `.sig` para cada uno — https://archlinuxarm.org/about/downloads.

**El patrón de dispositivos ARM (por ejemplo ODROID-C2) es exactamente el que necesitamos:**

```
1. Particionar el medio (boot + rootfs)
2. mkfs en cada partición
3. Descomprimir el tarball sobre el rootfs
4. Copiar el kernel/dtb a /boot (que en algunos es la partición FAT de arranque)
5. Instalar/generar el bootloader (U-Boot) en los offsets que pide la placa
```

En **nuestro** caso los pasos 1, 2 y 5 **no aplican**: la tabla de particiones ya existe (la fijó el
fabricante y no se toca), y el paso 5 lo cumple el ABL leyendo `boot_b`. Sólo quedan los pasos 3 y 4 —
y el 4 cambia de sitio: el «kernel en `/boot`» de un ODROID aquí es **el `boot.img` de `boot_b`**.

**Referencia de la mecánica general de instalación desde un host Linux** (útil porque el rootfs se prepara
en `pc-build`, no en la tablet): ArchWiki documenta el bootstrap con `arch-install-scripts`
(`pacstrap`, `arch-chroot`) cuando el host ya es Arch, y el chroot de Arch desde otra distro cuando no lo
es — https://wiki.archlinux.org/title/Install_Arch_Linux_from_existing_Linux. `pc-build` corre
**`Linux 7.2.6-arch2-1` (Arch)** — verificado por SSH — así que la vía es la primera: `arch-install-scripts`
está disponible y **`pacstrap` se puede ejecutar nativo**, sin emular.

### 2.2 `ports.archlinux.page` aarch64: quién lo mantiene y qué ofrece

`https://ports.archlinux.page/aarch64` es **infraestructura oficial del proyecto Arch Linux (la página y
el marco de RFC)**, y describe un **port no oficial todavía**:

- **Estado:** *«Unofficial»*, **RFC: None**.
- **Aviso literal:** paquetes *«not built with Arch Linux infrastructure, not signed by Arch Linux Staff,
  and not hosted on Arch Linux domains/mirrors. Packages may also be outdated, broken, or missing
  entirely. Support is primarily provided by other Arch Linux users (i.e. not Staff).»*
- **Mantenimiento:** el trabajo se coordina en `gitlab.archlinux.org/archlinux/ports/aarch64/project-management`
  y los forks de paquetes viven en los *namespaces* personales de **`solskogen`** y **`bschnei`**
  (p. ej. el kernel del port: `gitlab.archlinux.org/bschnei/linux` rama `aarch64`, con su `config.arm64`).
- **Requisito de CPU del kernel del port:** está pensado para dispositivos **con soporte mainline** y su
  `config.arm64` **no lleva parches específicos de dispositivo**. La lista de dispositivos confirmados son
  portátiles/servidores/placas: ASUS Vivobook S15 S5507Q, Dell XPS13 9345, Lenovo ThinkPad X13s, ODROID-M1/M2,
  Radxa Rock 5B, Radxa Orion O6… **ningún móvil ni tablet Qualcomm «cliffs»**.
- **Repositorios de paquetes:** los de **terceros** son **drzee.net** (core/extra/forge + tarballs de
  bootstrap, construidos **nativamente en ARMv8.2** en AWS), mantenidos por *solskogen* con el build system
  `archlinux-aarch64-builder`. ⚠️ Aviso textual: *«Packages are built for devices supporting the ARMv8.2 (and
  later) instruction sets only»*. Nuestro SoC es **ARMv9.2-A** (4× Cortex-X4 `0xd80`, 3× Cortex-A720 `0xd81`,
  1× Cortex-A520 `0xd82` — medido en `/proc/cpuinfo`) ⇒ **la restricción no nos afecta**: estamos por encima.
- **ArchISO aarch64** para instalación/recovery: `codeberg.org/ironrobin/archiso-aarch64/releases/latest`.

**Implicación práctica:** el **rootfs de partida** puede ser `ArchLinuxARM-aarch64-latest.tar.gz`
(el de `os.archlinuxarm.org`, que es lo que recomienda la propia ALARM), y **opcionalmente** apuntar
`pacman.conf` a `drzee.net` si aparece un paquete que ALARM lleva atrasado. Las dos vías son válidas y
**ambas son de terceros/no-oficiales en el fondo** — ALARM tampoco es «Arch oficial» (es un proyecto
independiente con su propio keyring). Esto no es un problema para el proyecto, pero es un hecho que hay
que tener escrito: **no hay soporte de staff detrás de nada de esto**.

**Ojo con el cebo del «RFC 0032»:** ese RFC define *cómo* se incorpora un port, y exige **dos package
maintainers de Arch** para liderarlo. Es decir, el port aarch64 está en fase de *pre-RFC work items*, y
ninguno de los dos repos es todavía una fuente de garantía — https://rfc.archlinux.page/0032-arch-linux-ports.

### 2.3 ¿Algo tipo postmarketOS para móviles/tablets?

No desde Arch. El ecosistema de móviles Linux (pmOS, Mobian, Droidian) es Debian/Alpine. Lo que sí existe
y **es la plantilla correcta** es el trabajo de Fydetab Duo (§3) y, como **implementación del flujo pmOS
sobre Arch ARM**, el proyecto **`Linux-for-Fydetab-Duo/imagebuild`**. `danctnix` es un port aarch64 de
terceros usado sobre todo en Pine64 (no verificado aquí). **U-Boot**: no hay port para SM7675
(`palawan-mainline/u-boot` **vacío**, `docs/MIGRACION-PORT-MODERNO.md` Fase 2, leído en `pc-build`)
⇒ **descartado con motivo**, igual que lo descartó pmOS.

---

## 3. El caso Fydetab Duo: qué copiar y qué no

**Qué es:** tablet **RK3588S** (Rockchip, GPU Mali G610) con **imágenes Arch Linux ARM aarch64**,
incluido un perfil **Omarchy 4.0** (Hyprland + Quickshell). Es **la plantilla del trabajo** que el README
del proyecto ya identificó.

### 3.1 Cómo arranca (y en qué se diferencia de nosotros)

Fuente: https://github.com/Linux-for-Fydetab-Duo/imagebuild/blob/main/docs/build-internals.md

> *«**No UEFI, no grub.** The board boots **u-boot → `boot.scr` → kernel**.»*

- Layout de particiones **fijo por la ROM de Rockchip y por `boot.cmd`**:
  `LBA 64 idblock.bin` · `LBA 16384 uboot.img` · `LBA 24580 resource.img` (los tres **dentro de la partición 1**),
  luego `p1 FW` (sin FS), `p2 ESP` (FAT32, 512 MiB, `legacy_boot`, type `ef00`), `p3 ROOTFS` (btrfs en omarchy,
  ext4 en arch-gnome).
- El **ESP se monta en `/boot`**: kernel, initramfs, dtb y `boot.scr` en la raíz del FS. Y la raíz lleva `/boot`
  como punto de montaje vacío. **FAT32 con type `ef00`** es lo que permitiría a un UEFI posterior arrancar el
  mismo layout **sin reparticionar**.
- `boot.cmd` **hardcodea** `setenv bootpart 2` y `setenv rootpart 3`.
- Rootfs omarchy = **btrfs con subvolúmenes de upstream** (`@`, `@home`, `@log`, `@/.snapshots`), `rootflags=subvol=/@`.
- Stage 3 del build **no usa loop device ni mount**: `sgdisk` sobre un fichero plano, `dd` para los blobs,
  `mkfs.vfat` + `mcopy` (mtools) para el ESP, `mke2fs -E offset= -d` para ext4, `mkfs.btrfs --rootdir --subvol`
  para btrfs. **Todo dentro de un contenedor / runner de CI.**
- Detalle fino que merece copiarse: stage 3 hace **`chown` de la raíz del staging a `0:0`** porque *«a non-root `/`
  makes systemd-tmpfiles refuse every path on the booted system ("unsafe path transition")»*, con `/run/lock`
  sin crear y `alsactl store/restore` roto para siempre.
- La instalación del dispositivo (wiki oficial) es **flashear imagen a SD con Etcher/Rufus**, o para UEFI:
  `rkdeveloptool db <spl_loader>` + `rkdeveloptool wl 0 <img>` + `rkdeveloptool rd` —
  https://wiki.fydetabduo.com/Available-OS/ArchLinux/arch-install. **Imágenes UEFI ⇒ se pierde el MASKROM
  (Vol+ + Power)**; para recuperarlo hay que `dd if=/dev/urandom of=/dev/mmcblk0 bs=10M count=2`.

### 3.2 Cómo lo hace el build (muy copiable aunque el transporte cambie)

Fuente: https://github.com/Linux-for-Fydetab-Duo/imagebuild/blob/main/README.md

- **Cross-build real desde un host x86_64** dentro de **docker**, con `qemu-aarch64` binfmt **con flag F
  (fix-binary)**. El `build.sh` **se niega a arrancar** sin las dos cosas. Sólo cuatro cosas ejecutan código
  aarch64: *install scriptlets, `mkinitcpio`, `locale-gen` y `pacman-key`*. El resto (resolver/extraer
  paquetes, particionar, `mke2fs`, escribir el bootloader, comprimir) es **neutro de arquitectura y corre a
  velocidad nativa**. `pacman` es el binario del host con `Architecture = aarch64`.
- **El kernel se cross-compila, no se emula**: el build system honra `ARCH`/`CROSS_COMPILE`, así que **el
  PKGBUILD no necesita cambios**.
- Entradas: `./build.sh containers | sync | pkg | image [profile] | all`. Salida en `out/`: imagen comprimida +
  `.manifest` (paquetes instalados) + `.sha256`.
- **Repo pacman propio** (`repo/fyde/aarch64/`) que es *«a complete replacement»*: se publica como un
  **GitHub Release rolling** (`repo`) que los dispositivos usan directamente como servidor pacman. En
  `profiles/*/pacman.conf` la sección `[fyde]` va **primero a propósito**, porque *«pacman resolves a package
  name to the first repo in file order **regardless of version**»* — así su `linux-fydetab` local le gana al
  publicado. **Truco importante y contraintuitivo.**
- **First boot (omarchy):** la imagen **no trae cuenta**; en el primer arranque `omarchy-provision-owner`
  toma tty1 antes de SDDM y pide layout de teclado, nombre, usuario, contraseña, hostname y zona horaria;
  crea el owner en `wheel` + los grupos de `/var/lib/omarchy/provisioning/groups`, da a root la misma
  contraseña y pasa al escritorio. ⚠️ **El formulario necesita teclado físico** (dock o USB): tty1 no tiene
  OSK, y el greeter de SDDM tampoco. Autologin **sólo en ese primer arranque**, con una unidad autoeliminable
  que lo quita al siguiente.

### 3.3 Tabla: qué se copia y qué no

| Elemento de Fydetab | ¿Sirve en la uke? | Motivo |
|---|---|---|
| **Cross-build Arch ARM desde x86 con docker + binfmt-F** | **SÍ, tal cual** | Es exactamente lo que hace falta en `pc-build` (`Linux 7.2.6-arch2-1`). Nota: el proyecto **ya tiene** su propia receta de chroot/emulación; la de Fydetab la **formaliza** |
| **Repo pacman propio + publicación rolling** | **SÍ** | Resuelve «kernel propio + paquetes Omarchy recompilados» y la regla de `[fyde]` primero. Es el patrón para el subproyecto A |
| **Subvolúmenes btrfs de Omarchy (`@`/`@home`/`@log`/`@.snapshots`)** | **SÍ, con un pero** | Se puede reproducir en `userdata`; **pero sin Limine no hay rollback** — el propio port lo declara fuera de alcance (*«needs the Limine stack the tablet can't run yet»*, README del proyecto). **Snapshots sí, arranque de snapshot no** |
| **`chown 0:0` de la raíz del staging** | **SÍ** | Evita el fallo «unsafe path transition» de `systemd-tmpfiles`, que deja `/run/lock` sin crear |
| **FAT32 con type `ef00` en el ESP montado en `/boot`** | **NO** | La uke **no tiene UEFI** (`ls /sys/firmware/efi` → no existe, medido) y **no podemos reparticionar** (`REGLAS-PARTICIONES.md`: R1/R11/R12) |
| **u-boot + `boot.scr` + `boot.cmd`** | **NO** | No hay port de U-Boot para SM7675; el equivalente es el **ABL**, que no se sustituye |
| **`rkdeveloptool` / MASKROM / SD** | **NO** | Transporte Rockchip. Aquí el transporte es **fastboot** |
| **Estructura del repo (`stages/`, `profiles/`, `image.conf` como única fuente de verdad)** | **SÍ, como modelo** | Es el patrón de ingeniería a imitar para el build de la uke |

**Lo más importante que se aprende de Fydetab:** el **transporte** (U-Boot vs ABL) es lo único
irreductiblemente distinto; el **proceso** (rootfs Arch ARM + kernel propio cross-compilado + initramfs
`mkinitcpio` + empaquetado del bootloader) es **el mismo** y está resuelto y en producción.

---

## 4. Arranque de Linux en tablets Qualcomm modernas sin UEFI

### 4.1 La cadena de arranque real

Fuente: https://wiki.postmarketos.org/wiki/Qualcomm

> *«Qualcomm ARM SoCs make use of several bootloaders, each of which initializes and/or checks some things
> and then passes on execution to the next stage… the main change introduced in **msm8996** is support for the
> **ABL UEFI bootloader**»*

Es decir: **el ABL es un UEFI**, pero un UEFI *de Qualcomm*, que **no expone** runtime services al SO ni
arranca binarios EFI arbitrarios del disco — sólo sabe cargar **boot images de Android** desde particiones
concretas. De ahí que no haya `/sys/firmware/efi` y que Limine/systemd-boot sean **imposibles** en esta
tablet. (Nota aparte: la uke **sí tiene** una partición `uefi_a`/`uefi_b` — `sde1`/`sde29`, 5 MB — pero es
la imagen EFI **interna del propio ABL**, no una ESP de usuario; `REGLAS-PARTICIONES.md` la lista entre las
particiones del bootloader que **no se tocan**.)

**Anatomía del arranque de la uke (línea base real, verificada en el dispositivo):**

```
Power → XBL (xbl_a/xbl_b, sdb1/sdc1) + xbl_config
      → ABL (abl_a=sde8 / abl_b=sde36)   ← "UEFI" de Qualcomm
      → lee misc (sda12) → BCB: "reboot-bootloader"  ⇒ si lo consume, cae a FASTBOOT
      → lee la GPT → flags de slot del atributo de partición (bits 48-63)
      → carga boot_b (sde39, 96 MB) = boot.img con header "ANDROID!" v4
      → concatena el ramdisk de vendor_boot_b (sde49, STOCK) al initramfs nuestro
      → pasa la cmdline de la CABECERA del boot.img al kernel
[✓] kernel palawan 7.2.0-rc2  →  rdinit=/ukeinit
      → ukeinit: pseudofs, block2mtd+mtdoops sobre `oops`, gadget ACM+RNDIS,
                 IP 192.168.42.129, shell en ttyGS0, y switch_root a la raíz
      → /sbin/init de la distro (systemd)
```

**Evidencia dura del porqué de `rdinit=/ukeinit`** — el hallazgo más caro de la campaña y **la primera
trampa** para el port:

> `docs/FLASH-LEDGER.md:2964-2965` (leído en `pc-build`): *«el `/init` que corre y exita 127 es el
> INIT DE ANDROID del ramdisk del vendor_boot (stock): ABL concatena el ramdisk del vendor_boot … y su
> `/init` **SOBRESCRIBE** el del initramfs integrado. FIX: renombrar nuestro init a `/ukeinit` +
> `rdinit=/ukeinit`»*

⚠️ **Corolario operativo:** si el initramfs de Arch se llama `/init`, **el init de Android ganará** y veremos
un `127` opaco. **El propio initramfs de Arch para esta tablet tiene que llamarse `/ukeinit`** (o cualquier
nombre que no sea `/init`). Es el patrón que ya funciona y **no hay que «arreglarlo»**: es una necesidad
impuesta por el ABL, no un apaño.

### 4.2 La cabecera del `boot.img` (header v4), medida sobre el artefacto real

Fuente de la especificación: https://source.android.com/docs/core/architecture/bootloader/boot-image-header

`struct boot_img_hdr` **versión 4** (Android 12+; los dispositivos GKI usan v4 como imagen primaria):

| Offset | Campo | Comentario |
|---|---|---|
| 0 | `magic[8]` | `ANDROID!` |
| 8 | `kernel_size` | **aquí escribe `s244-boot-repack.py`: `KS_OFF=8`** |
| 12 | `ramdisk_size` | |
| 16 | `os_version` | **debe ser 0 en v4 con GKI**; la versión se saca de las props AVB |
| 20 | `header_size` | |
| 24 | `reserved[4]` | |
| 40 | `header_version` | **el script lo verifica: `struct.unpack("<I", img[40:44]) == 4`** |
| 44 | `cmdline[512+1024]` | **`CMD_OFF=44`, `CMD_LEN=1536`** |
| 1580 | `signature_size` | `boot_signature` de v4 (**sólo lo usa VTS**, no el verified boot del dispositivo) |

**Los números reales del proyecto** (de `s244-boot-repack.py`, leído en `pc-build`):

```python
PAGE, CMD_OFF, CMD_LEN, KS_OFF, SIG_OFF, STOCK_SIZE = 4096, 44, 1536, 8, 35438592, 100663296
#  PAGE     = 4096      página (y offset del kernel)
#  CMD_OFF  = 44        offset de la cmdline en la cabecera
#  CMD_LEN  = 1536      longitud de la cmdline (512+1024)
#  KS_OFF   = 8         offset de kernel_size
#  SIG_OFF  = 35438592  offset del BLOQUE DE FIRMA AVB (v1/v2/v3 concatenados)
#  STOCK_SIZE = 100663296 = 96 MiB = tamaño EXACTO de la partición boot_b
```

**Cmdline verificada (255 B, byte a byte) — la del par bueno `s240-mem2g`:**

```
mem=2048M rdinit=/ukeinit panic=10 memmap=0x1A12800$0xE3940000 console=tty0 fbcon=map:0 ...
```

Y el script **exige** que estén presentes: `mem=2048M`, `memmap=0x1A12800$0xE3940000`, `rdinit=/ukeinit`,
`console=ttyGS0,115200`, `arm-smmu.disable_bypass=0`. **Esos cinco tokens son el mínimo no negociable.**

### 4.3 AVB: qué se firma, qué no, y por qué no podemos re-firmar

La partición de arranque está **protegida por Android Verified Boot**. El `boot.img` lleva un **footer AVB**
(`AVBf` en los últimos 64 bytes) y un **bloque de firma** en `SIG_OFF=35438592` (`AVB0` en `SIG_OFF:SIG_OFF+4`).

- **El proyecto conserva el footer intacto.** El script lo verifica en dos direcciones:
  `assert img[SIG_OFF:SIG_OFF+4] == b"AVB0" and img[-64:-60] == b"AVBf"` antes, y
  `assert blob[SIG_OFF:] == src_bytes[SIG_OFF:]` después ⇒ **«AVB footer: OK»** y **«no se tocó la cabecera»**.
- La estrategia es **reutilizar la firma de un `boot.img` que ya arrancó en este aparato** y sólo reescribir
  `kernel_size@8` y el kernel a partir de 4096. El resto de la cabecera y todo el bloque AVB **se copian**.
- El footer declara **rollback index `1769904000`** (verificado en `s244-boot-repack-report.txt`).
- `boot_signature` (v4) **no interviene** en el verified boot del dispositivo: *«isn't involved in the
  device-specific verified boot process and is only used in VTS»* —
  https://source.android.com/docs/core/architecture/bootloader/boot-image-header.

**El aparato está `unlocked`** (`fastboot getvar unlocked → yes`, ledger #231), y el ledger lo cierra:
el digest de la cadena AVB que la tablet cargó el 3-sep coincide **exactamente** con el de la ROM en disco
⇒ *«esos bytes ya arrancaron aquí: reflashearlos no puede fallar por incoherencia AVB»*.
El riesgo real que el ledger cuantifica es **otro**: *«(b) LECTURA de UFS a Gear 1 por VBAT<3600 (~40 %)»*.

**Implicación para Arch:** **no hace falta tocar AVB ni `vbmeta`**. Se copia el patrón del proyecto:
`boot.img` del par bueno como **shell**, se reemplaza el kernel, se conserva cabecera y bloque de firma.
Si en algún momento hiciera falta desactivar verificación, el comando es
`fastboot --disable-verity --disable-verification flash vbmeta[_b] <vbmeta.img>`, **pero el proyecto
demostró por medición que no es necesario y que jugar con `vbmeta_b` mató el arranque visible**
(ledger #235 → revert en #240: *«con boot_b=s110 TAMPOCO pinta nada… la config idéntica SALVO vbmeta_b»*).
**Regla: `vbmeta` no se toca.**

### 4.4 Slots A/B, contador de reintentos y `qbootctl`

Fuente: https://wiki.postmarketos.org/wiki/Android_AB_Slots

**Cómo funcionan:**
- Implementados en **dos partes**: los **campos de atributo de la GPT** y el atributo **UFS `bBootLunEn`**.
  *«Every partition header in GPT contains 8 bytes (64 bits) of attribute flags, of those, the last 16 bits
  (bits 48-63) are left for vendor specific use. Qualcomm's A/B implementation uses these to store flags
  representing if a slot is active, if it has booted successfully, and if it is unbootable, as well as the
  retry count.»*
- `userdata` **no está duplicada** por slots — y **eso es lo que hace posible este port**: el rootfs vive
  en una única `userdata`.
- *«it's quite likely that the other slot is broken (ie because you installed postmarketOS to the userdata
  partition), so this leads to an unbootable system, requiring the use of fastboot to clear the flags»*.
- Desde 2019 la mayoría de dispositivos usan **partición `super`** (dynamic partitions): la uke la tiene
  (`sda31`, 10,5 GB) y **es irrelevante para Linux** — el rootfs no va ahí.

**El contador:**
> *«Upgrade roll-back is implemented using a counter, it is initialised at 7 and decremented every time you
> boot the system unless you set the "boot successful" flag from userspace. When the counter reaches 0 the
> bootloader will automatically mark the slot as "unbootable" and switch to the other slot.»*

**Esto ya nos ha pasado, y está medido:** `docs/ESTADO-ACTUAL.md:323` (leído en `pc-build`):
*«contador del slot b (el 25-sep cayó 3 veces: mañana con `slot-retry-count:b=3`, tarde dos veces con slot b
unbootable y contador a 0; ambos slots con par bueno)»*. Y en el ledger #231: `slot-unbootable:b=yes`
(retry 0), `unbootable:a=no` (retry 7).

**El remedio, textual de la wiki:**
```
$ fastboot getvar current-slot
# si el slot actual es a:   (invertir el orden si es b)
$ fastboot set_active b
$ fastboot set_active a
```

**Y el arreglo de fondo: `qbootctl`.**

| Aspecto | Dato |
|---|---|
| **Qué es** | *«A CLI tool for manipulating A/B slots on Android devices. It is a port of the original Android bootctrl HAL developed by Qualcomm, modified to build on Linux and provide a friendly CLI interface. It also includes a port of the gpt-utils code required by the HAL, and an implementation of the UFS BSG API.»* |
| **Repos** | `https://github.com/linux-msm/qbootctl` (y `gitlab.com/sdm845-mainline/qbootctl`) |
| **¿Binario independiente?** | **SÍ.** El `README` dice literalmente: *«This HAL was pulled from AOSP source code and **bastardised to build and run on a musl/glibc system**»* ⇒ **no depende de Alpine ni de pmOS**. Dependencias: `zlib-dev`, `meson`, `cmake`, `linux-headers` |
| **¿Se puede usar en otra distro?** | **Sí.** La wiki dice: *«It is currently packaged in **Alpine testing and Debian**»*. En Arch ARM **habría que empaquetarlo** (PKGBUILD propio, trivial: meson + zlib) |
| **Qué necesita del kernel** | **`CONFIG_SCSI_UFS_BSG=y`** — *«Downstream uses an old ioctl interface called "sg" for setting this attribute, whilst it was submitted to mainline it was never accepted, instead we have a different interface called **UFS BSG**»*. ✅ **Nuestro config ya lo tiene** (`config-bueno-actual.config`, `docs/03-servicios-kernel-arranque.md` §1.3) |
| **CLI** | `<no args>` dump · `-c` current slot · `-b SLOT` is bootable · `-n SLOT` is successful · `-x [SLOT]` slot suffix · `-s SLOT` set active · **`-m [SLOT]` mark a boot as successful** · `-u [SLOT]` mark unbootable · `-i` write GPT headers even if UFS bLun can't be changed |
| **Dispositivos validados** | Pixel 3a, OnePlus 6/6T/8 Pro, SHIFT6mq, **Xiaomi 12 (xiaomi-cupid)** — ⚠️ **«cliffs» NO está en la lista** ⇒ **validación pendiente** |
| **Empaquetado en pmOS** | `soc-qcom-sdm845-qbootctl`, servicio que hay que habilitar **explícitamente** (`sudo rc-update add qbootctl default`) |
| **Efecto** | *«This will automatically set the "boot successful" flag on every postmarketOS boot»* |

**⚠️ Aviso del propio README de qbootctl, que hay que tomar en serio:**
> *«This may or may not render any hardware you run it on unusable, you have been warned.»*

⇒ **`qbootctl` es la herramienta correcta, pero es la operación de mayor riesgo de esta lista.** Se integra
**después** de que Arch arranque y con el par bueno en el otro slot. Y **siempre** con las reglas R1–R12
(`REGLAS-PARTICIONES.md`), en particular **R1** (*sólo `fastboot set_active` cambia el slot activo;
prohibido editar attrs por `dd`*) y **R2** (*sin re-dump no hay reboot*).

### 4.5 BCB y `misc`

`misc` (`sda12`, 4 MB) contiene el **Bootloader Control Block**. Estado **medido hoy** leyendo 4 KiB con
Python (sólo lectura): `command[0:32] = "reboot-bootloader"`.

**Hallazgos del proyecto sobre este ABL concreto** (`docs/FLASH-LEDGER.md` #230, #241):
- *«este firmware **NO** implementa `bootonce-*` (0 ocurrencias en todos los binarios). Sólo reconoce
  `boot-fastboot`, `boot-recovery`, `reboot-bootloader`, `reboot-recovery`, `reboot-fastboot`. **El cambio
  de slot se hace por GPT (`fastboot set_active`)»***
- *«misc contiene BCB "bootonce-bootloader" (escrito por Android en cada `adb reboot bootloader`; el ABL no
  soporta bootonce y **NUNCA lo limpia**). Presente también a las 00:15 ⇒ no discrimina, pero: queda para
  siempre hasta que se escriba misc»*
- *«Un `adb reboot` normal **NO** limpia el BCB: escribir recovery en misc SOLO si se limpia después.»*
- Limpieza: **`misc.img` son 8192 B de ceros**; `fastboot flash misc misc.img` limpia cualquier BCB.
  (En `~/gpu-work/` hay `bcb-clean.bin`.)
- Ojo: **`fastboot erase` y `fastboot flash` NO están igual de permitidos** — *«el ABL puede rechazar el
  borrado de una partición entera y aceptar la escritura de una imagen sparse. Si hay que resetear datos,
  ESCRIBIR sparse en vez de borrar.»*
- Los **22 comandos `oem`** que acepta este ABL (leídos del `abl.elf` descomprimido): `off-mode-charge`,
  `enable/disable-charger-screen`, `poweroff`, `edl`, `allow-wipe-userdata`, `device-info`, `fbreason`,
  `getguid`, `hwid`, `ramdump`, `lkmsg`, `lpmsg`, `uefilog`, `dm-verity-enforcing`, `uart-enable`,
  `set-hw-fence-value`, `set-gpu-preemption`… **No hay `oem charge`/`powerdown`/`soc`/`current`.**
  `oem poweroff` es **diferido por diseño**: *«Will power off after USB is plugged out»* (`0xab85c`).

### 4.6 `vendor_boot`: por qué no se toca

Fuente: https://source.android.com/docs/core/architecture/bootloader/partitions/vendor-boot-partitions

- Android 11 introdujo **GKI**: la cabecera v3 **saca toda la información vendor** de `boot` a `vendor_boot`.
- v4 soporta **múltiples fragmentos de vendor ramdisk**, concatenados, con una **tabla** que describe cada
  fragmento (`VENDOR_RAMDISK_TYPE_PLATFORM | RECOVERY | DLKM`) + **bootconfig**.
- *«the bootloader must access both the boot and vendor boot partitions to have enough data to complete booting.»*
- En la uke, **`vendor_boot_b` (`sde49`, 96 MB) es el STOCK de la ROM y NO se toca**. El ABL concatena su
  ramdisk ⇒ **de ahí el `rdinit=/ukeinit`** (§4.1). Además el proyecto midió que sustituirlo **rompe el
  arranque**: ledger #238 — *«con vendor_boot_b=s38-pstore, el fork moría ANTES del pintor: solo las 2 líneas
  del ABL… Con vendor_boot stock, el fork pintaba log completo y ciclaba ~105 s»* ⇒ **REVERT a stock**.
- Del mismo modo, `init_boot_a/b` (`sde26`/`sde53`, 8 MB) son **irrelevantes** para Linux (son Magisk/root de
  Android en los experimentos del proyecto).
- Y el **bootconfig** del vendor trae `swiotlb=noforce`, que es la **causa raíz del muro del WCN6750** (§5.3).

---

## 5. Kernel: empaquetado del fork palawan en Arch ARM

### 5.1 Los números del fork (medidos)

En `pc-build`, árbol `~/gpu-work/palawan-linux`, remoto `origin = https://codeberg.org/palawan-mainline/linux`,
rama de trabajo `s150-postclk`, base `palawan/v7.2-rc2`:
- `git diff --stat origin/palawan/v7.2-rc2..HEAD` → **46 ficheros, 25 097 inserciones, 323 borrados**, **29 commits** propios.
- **Además 27 ficheros con cambios de working tree SIN commitear** (entre ellos `qcom_pd_mapper.c`,
  `pmic_glink.c`, `qcom_battmgr.c`, `ath11k/ahb.c`, `ath11k/qmi.c`, `qcom_q6v5_pas.c`, `arm-smmu-qcom.c`,
  `ufs-qcom.{c,h}`, `pinctrl-cliffs`, `pinctrl-msm.c`, `phy-snps-eusb2.c`, `phy-qcom-eusb2-repeater.c`,
  `kernel/dma/swiotlb.c`, `gpio-regulator.c`, `rpmh-rsc.c`, `rpmh-regulator.c`,
  `interconnect/qcom/palawan.c`, `drivers/base/dd.c`, `qcom-spmi-temp-alarm.c`) y **2 drivers nuevos sin
  trackear** (`panel-xiaomi-o82-dualdsi.c`, `novatek-nt36xxx-spi.c`).

⚠️ **RIESGO #1 DEL PROYECTO, y es de método, no de tecnología:** si se empaqueta el kernel **desde el `.git`**
se pierde **casi todo el estado de working tree** — incluidos `qcom_battmgr.c` (**sin él no hay carga de
batería**), `ath11k`, `ufs-qcom.c` (**sin él no hay UFS**) y `swiotlb`. *«Hay que consolidar antes»*
(`docs/OBJETIVOS.md` §12: «recoger el fork»).

**Las 3 opciones de empaquetado, y cuál elegir:**

| Opción | Comando | Veredicto |
|---|---|---|
| **A. PKGBUILD propio tipo `linux-*`** | ver §5.2 | ✅ **Recomendado.** Estándar Arch, `pacman` lo gestiona, `depmod` y presets de `mkinitcpio` automáticos |
| B. `linux-aarch64` de ALARM parcheado | PKGBUILD de https://github.com/archlinuxarm/PKGBUILDs/blob/master/core/linux-aarch64/PKGBUILD | ❌ Base equivocada: es **multi-platform mainline** (parches de Rockchip/RPi), sin palawan. Lo que hace falta es A con **`source=` apuntando al fork** |
| C. Compilar a mano + `make modules_install` | `make ARCH=arm64 CROSS_COMPILE=... Image.gz modules` | ❌ Sólo para iterar rápido; `pacman` pierde la pista de los ficheros |

### 5.2 PKGBUILD de la uke (patrón real de ALARM, adaptado)

El PKGBUILD de `linux-aarch64` (leído completo) hace, en esencia:

```bash
buildarch=8
pkgbase=linux-aarch64 ; arch=('aarch64')
makedepends=('xmlto' 'docbook-xsl' 'kmod' 'inetutils' 'bc' 'git' 'uboot-tools' 'vboot-utils' 'dtc' 'python')
options=('!strip')                       # ← el kernel NO se strippea
# ...
prepare() { cd $_srcname ; cat "${srcdir}/config" > ./.config }
build()   { cd ${_srcname}
            make prepare
            make -s kernelrelease > version
            unset LDFLAGS
            make ${MAKEFLAGS} Image Image.gz modules
            make ${MAKEFLAGS} DTC_FLAGS="-@" dtbs }
_package(){ # instala Image{,.gz} en /boot, dtbs_install, modules_install con DEPMOD=/doesnt/exist
            # instala el preset /etc/mkinitcpio.d/${pkgbase}.preset
            # toca /usr/lib/initcpio/$(<version) para disparar el hook 90-mkinitcpio-install
}
```

**Traducido a `linux-uke` (adaptación directa, con los 4 cambios que importan):**

```bash
# PKGBUILD — linux-uke (kernel palawan para Xiaomi Pad 7 / cliffs)
pkgbase=linux-uke
_srcname=linux-palawan
pkgver=7.2.0rc2
pkgrel=1
arch=('aarch64')
options=('!strip')                       # imprescindible: como en linux-aarch64
# fuente = TARBALL CONSOLIDADO del fork (NUNCA el .git: se pierde el working tree)
source=("linux-palawan-${pkgver}.tar.xz"
        'config'                          # = configs-uke/config-bueno-actual.config
        'linux-uke.preset')
sha256sums=('SKIP' 'SKIP' 'SKIP')

prepare() {
  cd "$_srcname"
  cat "${srcdir}/config" > ./.config       # ← el config de referencia, NO un defconfig
}
build() {
  cd "$_srcname"
  make prepare
  make -s kernelrelease > version
  unset LDFLAGS
  make ${MAKEFLAGS} Image Image.gz modules
  make ${MAKEFLAGS} DTC_FLAGS="-@" dtbs     # -@ = símbolos DT para overlays
}
package() {
  cd "$_srcname"
  local kernver="$(<version)"
  install -Dm644 arch/arm64/boot/Image{,.gz} -t "${pkgdir}/boot"
  make INSTALL_DTBS_PATH="${pkgdir}/boot/dtbs" dtbs_install
  make INSTALL_MOD_PATH="$pkgdir/usr" INSTALL_MOD_STRIP=1 DEPMOD=/doesnt/exist modules_install
  rm "$pkgdir/usr/lib/modules/$kernver/build"
  install -Dm644 "${srcdir}/linux-uke.preset" "${pkgdir}/etc/mkinitcpio.d/${pkgbase}.preset"
  install -d "${pkgdir}/usr/lib/initcpio/"; echo dummy > "${pkgdir}/usr/lib/initcpio/$(<version)"
}
```

**Los 4 cambios que importan respecto a `linux-aarch64`:**
1. **`source=` al fork consolidado**, no a kernel.org.
2. **Compilador**: hoy es **clang 22.1.8 + LLD 22.1.8** (`/proc/version` de la tablet: *«clang version 22.1.8,
   LLD 22.1.8»*). El PKGBUILD por defecto usa GCC ⇒ hay que fijar `CC`/`HOSTCC`/`LLVM=1` a clang en `build()`
   **o** validar GCC (**no verificado** que este árbol compile con GCC). *Nota metodológica de pmOS que
   aplica aquí:* Alpine tuvo que mantener **GCC 6** porque ciertos vendor kernels no arrancaban compilados
   con GCC 8 — https://wiki.postmarketos.org/wiki/Downstream_kernel_specific_package ⇒ **si el kernel no
   arranca, la primera sospecha razonable es el compilador**.
3. **`KERNEL_IMAGE_NAME="Image.gz"`**: el equivalente pmOS de esta regla (porque su helper busca
   `Image.gz-dtb`/`*zImage`) se traduce aquí en que el **empaquetador del `boot.img` debe buscar
   `arch/arm64/boot/Image.gz`** — que es lo que produce el `build()`.
4. **El config**: `configs-uke/config-bueno-actual.config` (256 350 B) como base. Y **antes de flashear**,
   el gate de `docs/CONFIG-BUENO.md`.

### 5.3 El gate de config (obligatorio) — `docs/CONFIG-BUENO.md`

Nace del peor fallo de la campaña: *«entre s88 (13:22) y s89 (13:45) el config del build perdió **498
opciones**, entre ellas `COMMON_CLK_QCOM` y `PHY_SNPS_EUSB2`. Durante tres sesiones se depuró el gadget USB
de un kernel sin PHY USB2 y sin árbol de relojes… el gate daba GO porque no comprobaba ni un reloj ni una
PHY ni el tamaño.»*

| # | Comprobación | Dónde | Umbral |
|---|---|---|---|
| 1 | **config** — 12 opciones críticas en `=y` | `.config` del build **y** config embebido en la imagen (`extract-ikconfig`) | las 12 |
| 2 | **símbolos** — 13 críticos en `System.map` | build | los 13 |
| 3 | **tamaño** — `Image.gz` | del build **y** del kernel **dentro** del `.img` | **≥ 16 000 000 B** |

**Regla de oro derivada:** *«verificar por **símbolos y por config embebido**, nunca por cadenas»*.
Señales baratas de alarma: las imágenes buenas pesan **~16,5 MB**; s89–s93 pesaban 14,87 MB.
Símbolos centinela: `clk_rpmh_probe`, `qcom_cc_probe`, `snps_eusb2_hsphy_probe`, `eusb2_repeater_probe`.

**Los centinelas que ya usa el proyecto en el empaquetado del `boot.img`** (`s244-boot-repack.py`) — este es
el patrón exacto a replicar:

```python
kern_raw = gzip.decompress(io.BytesIO(kern).read())
assert kern_raw.find(b"UKE: se ignora") > 0        # marca del parche del swiotlb DENTRO del kernel
assert 12_000_000 < len(kern) < 18_000_000          # tamaño sano
src = open(SRC,"rb").read()
assert hashlib.sha256(src).hexdigest() == SHA_SRC   # el shell es el par bueno conocido
assert len(img) == STOCK_SIZE and img[:8] == b"ANDROID!"
assert struct.unpack("<I", img[40:44])[0] == 4      # header_version == 4
assert img[SIG_OFF:SIG_OFF+4] == b"AVB0" and img[-64:-60] == b"AVBf"
```

### 5.4 La deuda del `swiotlb` (contexto, para que Arch no la descubra de nuevo)

Es la causa raíz del muro de RAM del WCN6750 y explica `mem=2048M`:

- El **bootconfig del vendor** mete `swiotlb=noforce` (visto en `/proc/cmdline` de la tablet) ⇒ el pool de
  bounce queda desactivado ⇒ el `-EIO` del CE del ath11k.
- `s243` (`swiotlb=force` en la cmdline) fue **inerte**: el kernel compilado tenía `setup_io_tlb_npages()`
  sin `swiotlb_force_disable = false;` en la rama `force` (`kernel/dma/swiotlb.c:197-198`).
- El árbol **sí** tiene el parche que **ignora** `noforce` (`kernel/dma/swiotlb.c:199-212`, con `pr_info
  "UKE: se ignora 'swiotlb=noforce' …"`), pero **ningún kernel compilado lo llevaba** hasta `s244`.
- Con el parche, arm64 crea el pool por `CONFIG_DMA_BOUNCE_UNALIGNED_KMALLOC` **aunque `mem=2048M` deje todo
  < 4 GB**, y `dma_direct_map_phys()` rebota en el fallback los mapeos que no caben en la **máscara de 32 bits**
  del WCN6750.
- **NO usar `force`**: con `force_bounce`, `dma_map_resource()` con `DMA_ATTR_MMIO` devuelve
  `DMA_MAPPING_ERROR` ⇒ **moriría el mapeo MSI de ath11k**.

⇒ **`mem=2048M` no elimina el banco >4 GB** (medido: sigue apareciendo `880000000-88b9cefff : System RAM`)
y hay que llevarlo en la cmdline hasta que el `swiotlb` se resuelva. En el sistema actual eso cuesta
~1,6 GB de los 8 GB nominales (`MemTotal: 1645140 kB`).

---

## 6. Initramfs e init propio con `rdinit`

### 6.1 Comparativa de opciones

| Opción | Cómo | Veredicto para la uke |
|---|---|---|
**(a) `mkinitcpio` con hooks `base udev block filesystems`** | Estándar Arch. El hook `base` + `udev` montan `/dev`, `/sys`, `/proc`; **`filesystems`** provee `mount`/`fsck`; la raíz se resuelve por **`root=UUID=…`** de la cmdline | ✅ **Recomendado**, con un añadido: hace falta una **hook/script propio** para el gadget ACM antes del `switch_root` |
**(b) `mkinitcpio` con `systemd` en el initramfs** | systemd ya en el initramfs; más features, **más tamaño** | ❌ El initramfs **no puede engordar**: hay que vigilar el tamaño del `boot.img` (los buenos pesan 96 MB = la partición; el techo de `fastboot boot` es ~64 MB según `pack-bootimg.sh`) |
**(c) initramfs a mano tipo `ukeinit`** | busybox estático + `/init` en shell | ✅ **Ya existe y funciona.** Es lo que corre hoy. Sirve de **canal de emergencia** y de fuente del gadget ACM |
| **(d) `isorec`** | Un initramfs *stub* mínimo compilado **dentro** del kernel que carga el initramfs real desde `/boot` — https://wiki.postmarketos.org/wiki/Boot_process | 🔶 **Alternativa válida** si el `boot.img` se pasa de tamaño. Añade un rebuild de kernel para cambiar el initramfs |

**Dato de tamaño real:** el `initramfs-uke.cpio.gz` actual pesa **1 010 980 B (~1 MiB)**, y el `s244` tiene
`debug_ext.initrd_size=35510` en la cmdline (restos del integrado en el kernel). Hay **mucho margen**.

### 6.2 Cómo lo hace pmOS (y qué se ahorra quien lo copia) — §6 de la segunda tabla

Fuente: https://wiki.postmarketos.org/wiki/Boot_process · https://wiki.postmarketos.org/wiki/Initramfs

- *«pmOS would put its initramfs and kernel into a **Android boot image** and flash it to the `boot` partition»*
  ⇒ **el mismo mecanismo exacto que usamos**, ya validado en centenares de dispositivos.
- `postmarketos-mkinitfs` genera el initramfs; luego **`boot-deploy`** empaqueta kernel + initramfs en el
  formato adecuado y **genera la config del bootloader**.
- **Orden de tareas del initramfs** (esto es lo que damos «gratis» si copiamos el diseño):
  1. Cargar device config del `deviceinfo`
  2. Inicializar busybox
  3. Montar `/dev`, `/proc`, `/sys`
  4. Configurar logging
  5. **Habilitar USB networking desde el initramfs** (para depurar)
  6. Correr hooks · shell de depuración por combo de teclas · **buscar/desbloquear/montar la raíz (con `fsck`)** · correr hooks de limpieza · **`switch_root`**
- **Búsqueda de particiones:** `pmos_boot` (cmdline) o label **`pmOS_boot`**; `pmos_root` (cmdline) o label
  **`pmOS_root`**; o **cualquier partición cifrada**. Al final la raíz queda en `/sysroot` y la boot en
  `/sysroot/boot`, y se llama a `switch_root`.
- **Argumentos de cmdline que da gratis:** `pmos.debug-shell` (**halt tras cargar `-extra` + shell en TODAS
  las consolas y por telnet**), `pmos.nosplash`, `pmos.root_uuid=`, `pmos.rootfsopts=`,
  `pmos.force-partition-resize`, `pmos.usb-storage=`, `rd.info`, `pmos.stowaway`, `pmos.bootchart2`.
- **Depuración:** `pmOS_init.log` (en la raíz del dispositivo), `/proc/last_kmsg`,
  `/sys/fs/pstore/console-ramoops`, `pmbootstrap initfs hook_add maximum-attention` (LED/vibrador),
  `pmbootstrap bootimg_analyze <boot.img>`, `pmbootstrap kconfig check` —
  https://wiki.postmarketos.org/wiki/Troubleshooting:boot

### 6.3 Comparativa: qué me da pmOS gratis que aquí hago a mano

| Capacidad | pmOS | En la uke hoy | Coste de hacerlo a mano |
|---|---|---|---|
| Montaje de la raíz con `fsck` | ✅ `find_root_partition` + `mount_root_partition` + `switch_root` | ❌ `mount -t ext4 -o ro,noload` ⇒ **de ahí el `norecovery`** | **ya pagado**: 908 errores ext4 acumulados |
| Resolución de raíz por label/UUID | ✅ `pmos_root_uuid` desde `boot-deploy` | 🔶 propio (`uke_root=`, no usado en producción) | bajo |
| USB networking temprano + telnet | ✅ `unudhcpd`, **IP `172.16.42.1/24`**, cliente `172.16.42.2`, **función NCM** | 🔶 RNDIS propio en `192.168.42.129/24` con DHCP | medio (convivencia NCM/RNDIS) |
| **Consola serie por gadget ACM** | ❌ **no viene de serie** | ✅ **es nuestro** (`ttyGS0` → `/dev/ttyACM0` en el PC) | **es lo único que hay que portar** |
| Shell de depuración | ✅ `pmos.debug-shell` + telnet + combo de teclas | 🔶 `getty -L -n -l /bin/sh ttyGS0` | bajo |
| `pstore`/`console-ramoops` | ✅ de serie | 🔶 `block2mtd`+`mtdoops` sobre la partición `oops` | medio (el `oops` es nuestro) |
| **`qbootctl` empaquetado y con servicio** | ✅ paquete + `rc-update add qbootctl default` | ❌ **nada marca el slot como successful** | **ALTO — es la deuda P0.5** |
| Redimensionar la raíz en el primer arranque | ✅ `pmos.force-partition-resize` | ❌ no aplica (ya está dimensionada) | nulo |
| Cifrado de la raíz + UI (`Unl0kr`) | ✅ `initramfs-extra` | ❌ no aplica (no ciframos) | nulo (decisión) |
| Empaquetado del `boot.img` | ✅ `boot-deploy` | 🔶 `pack-bootimg.sh` + `mkbootimg` + repack | bajo (ya resuelto) |
| **Sustituir el `dtbo` por DT propio** | ✅ `deviceinfo_dtb` + `deviceinfo_append_dtb` | 🔶 artefacto probado: `avb/boot-m1-modern-dt.img` (**header v2 + DTB único appended**, sha `99781d55…`) | **ALTO** — es el grueso del trabajo de arranque (3–8 días) |
| Config de kernel declarativo | ✅ `deviceinfo` + `kernel-cmdline.d/` (pmaports!7708; `deviceinfo_kernel_cmdline` es **obsoleto**) | 🔶 cabecera del `boot.img` byte a byte | bajo |

**Veredicto:** pmOS no aporta nada que no podamos replicar, **excepto dos cosas que merece la pena copiar
deliberadamente**: **(1)** el **`fsck` en el montaje de la raíz** (que es exactamente lo que arregla nuestra
deuda de ext4) y **(2)** que **`qbootctl` no es opcional** — sin él el dispositivo no es usable en remoto
(lo dice el propio `docs/OBJETIVOS.md` P0.5).

### 6.4 El `init` propio: código de ejemplo

**Diseño, en una frase:** casi todo lo del `ukeinit` actual **se tira** (pseudofs, panic-capture, red,
PID1-never-exits) porque el initramfs de Arch + systemd lo hacen mejor; **se conservan** las §1 (espera de
UDC) y §2 (gadget configfs **ACM**) del original, y el §5 (`switch_root`) se **reescribe con `fsck`**.

**`initramfs-uke/init` original, sección por sección (leído completo en `pc-build`):**

| Sección del `ukeinit` actual | Qué hace | En el initramfs de Arch |
|---|---|---|
| `0` pseudo-FS | `mount proc/sysfs/devtmpfs/devpts/tmpfs/configfs`, `printk=7` | **se tira** — lo hace `mkinitcpio` |
| `0b` panic-capture | resuelve `PARTNAME=oops` en `/sys/class/block/*/uevent`, adjunta **`block2mtd`** (`echo "$OOPS_PATH,2097152" > /sys/module/block2mtd/parameters/block2mtd`), deja **`mtdoops`** volcar oops; breadcrumbs en `/tmp/uke-bc.log` volcados con `dd … conv=notrunc` | **se conserva** (hook, opcional) — es **el único canal de panics sin consola** |
| **`1` espera de UDC** (30 s) | `for u in /sys/class/udc/*` con `sleep 1` | **SE CONSERVA** (es lo que hace posible la consola) |
| **`2` gadget configfs** | `mkdir /sys/kernel/config/usb_gadget/uke`; `idVendor=0x18d1 idProduct=0xD002 bcdDevice=0x0100`; strings (`mainline-uke`/`UKE mainline debug`/serial `SERIE0001`); `functions/acm.GS0` + `functions/rndis.rndis0`; `configs/c.1` `MaxPower=500`; symlinks; **y `echo $UDC > $G/UDC` LO ÚLTIMO** | **SE CONSERVA**, pero en Arch conviene **sólo `acm.GS0`** (la red la hace systemd-networkd con `usb0`) |
| `3` red USB | `ip link set up` + `ip addr add 192.168.42.129/24` | **se tira/shiftifica** — mejor en el rootfs |
| `4` shell en `ttyGS0` | `setsid getty -L -n -l /bin/sh ttyGS0 115200`, **una sola vez, sin respawn** | **se conserva** (es el `debug-shell`) |
| `5` `switch_root` con `uke_root=` | resuelve PARTLABEL/LABEL/UUID/PARTUUID, `mount -t ext4 -o rw` (fallback `ro`), `mount -o move` de proc/sys/dev/run, `exec switch_root /newroot /sbin/init` | **SE REESCRIBE** — el `-o ro,noload` es **el origen del `norecovery`** (`docs/TRABAJO-PENDIENTE.md:316-318`, ledger #3059) |
| `6` PID1 nunca sale | shell en `/dev/console` + `while true; do sleep 600; done` | **se tira** — si el `switch_root` falla, se queda en el shell de depuración |

> ⚠️ **ERRATA 2-oct-2026** (ledger #487/#489, `NOTAS-OMARCHY.md`): la fila `0b` de arriba **nunca ha
> funcionado**. El ABL pasa `block2mtd.block2mtd=/dev/block/by-name/oops,…`, pero
> **`/dev/block/by-name/` no existe** en esta rootfs (sin symlinks udev) ⇒ `block2mtd` no se adjunta,
> y el kernel lo confirma en consola (`block2mtd: error: cannot open device /dev/block/by-name/oops`
> @3.495 s). La partición existe (`PARTNAME=oops` = `/dev/sda26`, 16 MiB) pero leída cruda solo tiene
> oops de fábrica de junio-2026. Requisito para que el hook sirva: crear los symlinks `by-name` (o
> pasar `/dev/sda26` por cmdline). Este informe queda por lo demás intacto (documento congelado).

**`/ukeinit` para Arch (shell POSIX, busybox ash) — ejemplo funcional:**

```sh
#!/bin/sh
# /ukeinit — PID1 del initramfs de Arch para la Xiaomi Pad 7 «uke».
# NO se llama /init A PROPOSITO: el ramdisk del vendor_boot (stock) que el ABL
# concatena trae su propio /init y SOBRESCRIBE el nuestro (ledger :2964-2965).
# Invocacion: rdinit=/ukeinit  en la cmdline de la cabecera del boot.img.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
KMSG=/dev/kmsg
kmsg() { echo "<6>ukeinit: $*" > "$KMSG" 2>/dev/null || true; }

# ---------- 1) ESPERA DE UDC (hasta 30 s) — pieza portada del ukeinit original ----------
UDC=""
i=0
while [ $i -lt 30 ]; do
    for u in /sys/class/udc/*; do
        [ -d "$u" ] && { UDC="${u##*/}"; break; }
    done
    [ -n "$UDC" ] && break
    i=$((i+1)); sleep 1
done
[ -n "$UDC" ] && kmsg "UDC presente: $UDC (espera $i s)" || kmsg "AVISO: sin UDC tras 30 s"

# ---------- 2) GADGET: SOLO ACM (consola serie; el PC lo ve como /dev/ttyACM0) ----------
# Orden CRITICO: crear funciones -> enlazar a la config -> escribir UDC LO ULTIMO.
G=/sys/kernel/config/usb_gadget/uke
if [ -n "$UDC" ] && [ -d /sys/kernel/config/usb_gadget ]; then
    if [ ! -d "$G" ]; then
        mkdir -p "$G"
        echo 0x18d1 > "$G/idVendor"
        echo 0xD002 > "$G/idProduct"
        echo 0x0100 > "$G/bcdDevice"
        mkdir -p "$G/strings/0x409"
        echo "mainline-uke"       > "$G/strings/0x409/manufacturer"
        echo "UKE Arch debug"     > "$G/strings/0x409/product"
        echo "SERIE0001"           > "$G/strings/0x409/serialnumber"
        mkdir -p "$G/functions/acm.GS0"
        mkdir -p "$G/configs/c.1/strings/0x409"
        echo "ACM"                > "$G/configs/c.1/strings/0x409/configuration"
        echo 500                  > "$G/configs/c.1/MaxPower"
        ln -sf "$G/functions/acm.GS0" "$G/configs/c.1/"
    fi
    if [ -z "$(cat "$G/UDC" 2>/dev/null)" ]; then
        echo "$UDC" > "$G/UDC" 2>/dev/null
        [ "$(cat "$G/UDC" 2>/dev/null)" = "$UDC" ] \
            && kmsg "gadget BOUND a $UDC (ACM)" || kmsg "FALLO bind UDC $UDC"
    fi
fi
bc() { kmsg "BC: $*"; }
bc "udc=${UDC:-none} gadget=$(cat /sys/kernel/config/usb_gadget/uke/UDC 2>/dev/null || echo none)"

# ---------- 3) SHELL DE DEPURACION EN ttyGS0, UNA SOLA VEZ (sin respawn) ----------
if [ -c /dev/ttyGS0 ]; then
    ( setsid getty -L -n -l /bin/sh ttyGS0 115200 </dev/null >/dev/null 2>&1 & )
    sleep 1
    [ -c /dev/ttyGS0 ] && bc "shell=ttyGS0 (PC: /dev/ttyACM0)" || bc "shell=ttyGS0-lost"
else
    bc "shell=none (sin /dev/ttyGS0)"
fi
bc "PASO 3 hecho: apaga y lee la consola si algo falla"

# ---------- 4) RAIZ: por label, con fsck, SIN noload ----------
# IMPORTANTE: nada de -o ro,noload. Ese fue el origen del `norecovery` que hoy
# arrastra el / de la tablet (TRABAJO-PENDIENTE.md:316-318). Aqui SI se repara.
LABEL="${uke_root:-userdata}"          # override con uke_root=<label|UUID=..|/dev/..>
ROOT=""
case "$LABEL" in
    /dev/*)  ROOT="$LABEL" ;;
    UUID=*)  for l in /dev/disk/by-uuid/*; do [ -e "$l" ] || continue
                 [ "${l##*/}" = "${LABEL#UUID=}" ] && { ROOT="$l"; break; }; done ;;
    *)       [ -e "/dev/disk/by-partlabel/$LABEL" ] && ROOT="/dev/disk/by-partlabel/$LABEL" ;;
esac
[ -n "$ROOT" ] || { bc "root=$LABEL NO resuelto: shell"; exec /bin/sh; }
bc "root=$ROOT"

# fsck OBLIGATORIO antes de montar (la deuda de los ~908 errores ext4 se paga AQUI).
# -p = repara sin preguntar (-y tambien vale). `-f` fuerza la revision.
e2fsck -p -f "$ROOT" >/dev/console 2>&1 || kmsg "e2fsck rc=$? (revisar)"

mkdir -p /newroot
# `norecovery` NO: queremos el journal reproducido. `rw` para que el arranque no
# fuerce un remontaje; `errors=remount-ro` es el default sano del ext4.
mount -t ext4 -o rw "$ROOT" /newroot \
  || { bc "FALLO mount $ROOT (ext4?): shell"; exec /bin/sh; }

if [ -x /newroot/sbin/init ] || [ -x /newroot/init ]; then
    # mover los pseudo-FS al nuevo root y saltar (patron obligatorio de switch_root)
    mount -o move /proc /newroot/proc
    mount -o move /sys  /newroot/sys
    mount -o move /dev  /newroot/dev
    mount -o move /run  /newroot/run 2>/dev/null || true
    bc "switch_root -> $ROOT"
    if [ -x /newroot/sbin/init ]; then exec switch_root /newroot /sbin/init
    else                             exec switch_root /newroot /init; fi
    bc "switch_root FALLO: shell"
else
    bc "$ROOT sin /sbin/init ni /init: shell"
fi

# ---------- 5) Si llegamos aqui, el switch_root fallo: shell de emergencia, NUNCA panic ----------
# (kept: sin respawn-loops, sin `pkill -f busybox`)
[ -c /dev/console ] && exec sh </dev/console >/dev/console 2>&1
while true; do sleep 600; done
```

**Empaquetado del initramfs (mismo `build.sh` que ya funciona, adaptado):**

```bash
#!/bin/bash
set -e
STAGE=_stage-uke ; OUT=initramfs-uke.cpio.gz
BUSYBOX=/usr/bin/busybox               # ESTATICO aarch64
# El original usa halium/stage1/stage/bin/busybox (v1.36.1, sha c162688974b9c56e…)
command -v cpio gzip file >/dev/null || { echo "faltan cpio/gzip/file"; exit 1; }
sh -n ./ukeinit                        # sintaxis: ash -n del host (o qemu-aarch64 busybox ash -n)
rm -rf $STAGE ; mkdir -p $STAGE/{bin,sbin,etc,proc,sys,dev,run,tmp,newroot}
cp $BUSYBOX $STAGE/bin/busybox ; chmod +x $STAGE/bin/busybox
for a in sh mount umount sleep ls cat echo mkdir mknod dd setsid getty switch_root \
         blkid e2fsck dmesg ip ln ; do ln -sf busybox "$STAGE/bin/$a" ; done
ln -sf /bin/busybox $STAGE/sbin/init
cp ./ukeinit $STAGE/ukeinit ; chmod +x $STAGE/ukeinit   # <- NO se llama init
( cd $STAGE && find . -print0 | cpio --format=newc --create --null 2>/dev/null | gzip -9 -n > ../$OUT )
ls -la $OUT
```

⚠️ **Tres trampas del empaquetado:**
1. **`/ukeinit`, no `/init`** — ver §4.1.
2. **`udev`/`e2fsck` reales**: el busybox estático debe **enlazar `e2fsck`** (o llevar el binario real de
   `e2fsprogs`), o el fsck será un no-op silencioso y seguiremos con el ext4 roto. **Verificar con
   `ls -l` que el symlink existe y que `e2fsck` no es el applet recortado.**
3. **`find . -print0 | cpio`** desde dentro del staging ⇒ los paths del archivo quedan como `./ukeinit`
   (**relativos**). Es lo que hace el `build.sh` original y funciona; añadir `--owner 0:0`
   (`cpio --reproducible --owner 0:0`) para que el initramfs no dependa del uid del host.

**Cómo se conecta el rootfs:** la raíz se monta **por label** (`PARTLABEL=userdata`, `sda32`) — exactamente
el patrón que la tablet ya usa: *«`/dev/sda32` = `PARTLABEL=userdata`, ext4, UUID
`2311404a-42a2-446e-b018-c918075b4f56`, montado `/` con `norecovery`»*. Con `mkinitcpio` se usaría
`root=PARTLABEL=userdata` en la cmdline + hooks `base udev block filesystems`; con el `/ukeinit` propio,
`uke_root=userdata`.

**Consola temprana por USB gadget (ACM):** es exactamente lo que hace el §1/§2 del `ukeinit` actual y lo que
el sistema de Arch **no** da. En el PC aparece como **`/dev/ttyACM0`** (driver `cdc_acm`, grupo `uucp`).
Dos motivos documentados por los que **no se puede prescindir de ella**:
1. *«el CM3 del GMU **cuelga sin panic** y la única copia de los `UKE-CM3DBG` es la consola»*
2. *«si nadie lee el `ttyACM0`, los `write()` del kernel se bloquean con el buffer lleno»* (bug
   **X9DUMP-block**, ledger #268/#269)
⇒ **El nivel de consola debe ser 7** (`dmesg -n 7`) y hay que mantener el capturador `bin/uke-console-cap.sh`
del PC (*«bucle `cat /dev/ttyACM0 >> $LOG` reabriendo en cada vuelta»*, porque *«tras un reinicio de la tablet
el gadget se re-enumera y el descriptor viejo deja de valer»*). Y **sólo un lector de consola a la vez**.

---

## 7. Guía de instalación por fases

> **Reglas de trabajo (obligatorias, de `docs/REGLAS-PARTICIONES.md` y el README del proyecto):**
> **R1** sólo `fastboot set_active` cambia el slot · **R2** sin re-dump GPT no hay reboot · **R3** prohibido
> mezclar mecanismos de slot en una sesión · **R5** backup antes de la primera escritura · **R7** una
> operación con slot = una fila de ledger · **R11** prohibido editar attrs GPT con herramientas propias
> (**causó el brick del 11-sep-2026**) · **R12** la reparación de GPT es byte-exacta o no es.
> Y: *«Les reglas son obligatorias… Si una regla impide algo, se para y se lanza crítica; no se "adapta"
> la regla en caliente.»*

### Fase 0 — Reconocimiento y copia de seguridad (sólo lectura)

```bash
# 0.1 Entrar en fastboot (o por adb, o con Power+Vol- que es el camino que SÍ carga)
adb reboot bootloader
fastboot devices                      # ⚠ SIN -s SERIAL: no funciona en este aparato
fastboot getvar current-slot          # anotar: el par bueno esta en el OTRO slot
fastboot getvar slot-retry-count
fastboot getvar slot-unbootable
fastboot getvar unlocked              # esperado: yes
fastboot getvar battery-voltage       # RIESGO: en fastboot NO carga; umbral GO >= 3700 mV
fastboot getvar partition-size:boot_b # esperado: 0x6000000 (96 MiB)
fastboot getvar partition-size:userdata
```
**Criterio de hecho:** los 4 getvars de slot anotados en el ledger + `unlocked=yes` + batería **≥ 3700 mV**.
Si no: **parar** (la tabla del ledger cuantifica el fallo de lectura de UFS por VBAT<3600 en ~40 %).

```bash
# 0.2 Backup del par bueno (el que HOY arranca). Poner el par bueno en AMBOS slots antes de nada.
fastboot fetch boot_b   boot_b-good.img   # (si el fastboot del ABL soporta fetch; si no, vía adb+su)
fastboot fetch dtbo_b   dtbo_b-good.img
sha256sum boot_b-good.img dtbo_b-good.img | tee SHA-BUENOS.txt
```
> **Patrón del proyecto:** el par vigente es `boot s240-mem2g` + `dtbo s229` en **slot b**; y el artefacto
> actual más reciente es `avb/boot-s244-bounce.img` (sha256 `ffff8c51265ff03c84cff15ffdb275f396a666a491eb5d67580be705321db99e`,
> kernel `adad4bb4dc1567d1`, 16 559 711 B). **Y la mitigación documentada** es *«mismo par bueno en **ambos**
> slots + `bin/uke-fastboot-watch.sh`»*.
>
> ⚠️ **ERRATA 2-oct-2026** (ledger #487–#491): el bloque de arriba es histórico (era 26-sep). El par
> operativo hoy es **`boot-ukek13-dsid.img` (`e0ee47dc…`) + `s260` (`6fbb5173…`) en slot a**
> (`SHA-BUENOS.txt`, `docs/historia/ESTADO-VIVO.md`); slot b está `unbootable` (no hay rollback arrancable).
> Además `fastboot fetch` **no existe** en este bootloader (la verificación es por relectura desde
> Linux), y limpiar `misc` a ceros **no** rehabilita slots (los contadores viven en atributos GPT;
> lo que rehabilita es reescribir la partición — medido 3 veces el 2-oct). Este informe queda por lo
> demás intacto (documento congelado).

```bash
# 0.3 Limpiar el BCB de misc (hoy dice "reboot-bootloader")
adb shell su -c 'dd if=/dev/zero of=/dev/block/by-name/misc bs=4096 count=1'   # o
fastboot flash misc misc-zeros.img    # 8192 B de ceros (misc.img de la ROM = ceros)
```
**Criterio de hecho:** releer `misc` y ver `command[0:32]` en ceros.

### Fase 1 — Rootfs Arch ARM en el PC (nativo, sin emular)

`pc-build` corre **Arch** (`Linux 7.2.6-arch2-1`) ⇒ **`pacstrap` corre nativo**.

```bash
# 1.1 Tarball oficial ALARM aarch64 (descarga + firma)
curl -O http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz
curl -O http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz.sig
gpg --keyserver keyserver.ubuntu.com --recv-keys 68B3537F39A313B3E574D06777193F152BDBE6A6
gpg --verify ArchLinuxARM-aarch64-latest.tar.gz.sig ArchLinuxARM-aarch64-latest.tar.gz

# 1.2 Preparar la imagen/tree del rootfs (ext4; ~8-12 GB de margen sobre 105,9 GB)
truncate -s 12G rootfs-arch.img
mkfs.ext4 -L uke-arch -E offset=0 rootfs-arch.img 1048576   # (o con un loop/mount real)
mkdir -p mnt && sudo mount -o loop rootfs-arch.img mnt
sudo bsdtar -xpf ArchLinuxARM-aarch64-latest.tar.gz -C mnt   # ← el paso 3 del patron ALARM
```
> **Alternativa (más limpia y con `pacman` nativo):** `pacstrap` desde el host Arch, con
> `pacman.conf` de ALARM (`Architecture = aarch64`, server `os.archlinuxarm.org`), tal como describe
> https://wiki.archlinux.org/title/Install_Arch_Linux_from_existing_Linux. Requiere `qemu-user-static` con
> binfmt **flag F** sólo para los scriptlets (el mismo requisito que documenta Fydetab:
> https://github.com/Linux-for-Fydetab-Duo/imagebuild/blob/main/docs/build-internals.md).

```bash
# 1.3 Lo minimo imprescindible sobre el rootfs base
sudo pacman -r mnt -S --needed base linux-firmware mkinitcpio e2fsprogs \
     systemd sudo openssh networkmanager libwacom iio-sensor-proxy
# + firmware del vendor (hoy copiado a mano en /lib/firmware, sin dueno dpkg):
#   ath11k/WCN6750/hw1.0/{amss,board,regdb}.bin · qca6750/wpss.* ·
#   qcom/uke/gen71100_{gmu.bin,sqe.fw,zap.mbn} · adsp.b00..b52 + adsp.mdt + adsp_dtb.*
# 1.4 fstab: solo lo no-raiz (la raiz la monta el initramfs)
#   tmpfs /tmp tmpfs defaults,nosuid 0 0        <- igual que el sistema actual
# 1.5 Preservar lo de valor del /etc de Ubuntu (ver docs/01-inventario-tablet.md §7.4)
```

**Criterio de hecho:** `chroot mnt /usr/bin/bash -c 'uname -m'` → **`aarch64`** (con binfmt) y
`ls mnt/usr/lib/modules/` vacío (el kernel va aparte).

### Fase 2 — Kernel PKGBUILD (§5.2)

```bash
# 2.1 CONSOLIDAR EL FORK PRIMERO (esto es el riesgo #1, no un paso de tramite)
cd ~/gpu-work/palawan-linux
git status --porcelain | wc -l          # hoy: 27 modificados + 2 sin trackear
# commitear por temas: pd_mapper+pmic_glink+battmgr | ath11k+pwrseq+swiotlb | ufs-qcom |
#                      pinctrl-cliffs+icc-palawan | panel-o82+nt36xxx | gpu/a6xx
# dejar los pokes detras de un CONFIG (uke-panic-fb, uke-prevlog, uke-poke.h)
tar -cJf ~/linux-palawan-7.2.0rc2.tar.xz --exclude=.git .

# 2.2 Build con el PKGBUILD propio (linux-uke) y el config de referencia
cd ~/pkgbuilds/linux-uke && makepkg -f -s
```

**Criterio de hecho (gate `CONFIG-BUENO.md` §1), TODO verde:**
- 12 opciones críticas en `=y` en `.config` **y** en el config embebido (`scripts/extract-ikconfig`)
- 13 símbolos críticos en `System.map`
- `Image.gz` **del build y del `.img`** ≥ **16 000 000 B**
- **el centinela del parche**: `gzip -dc Image.gz | grep -c 'UKE: se ignora'` > 0
- `pmbootstrap kconfig check` equivalente: `CONFIG_SCSI_UFS_BSG=y` (**qbootctl**),
  `CONFIG_USB_CONFIGFS_NCM/F_FS/RNDIS`, `CONFIG_DMA_BOUNCE_UNALIGNED_KMALLOC`, `CONFIG_MTD_BLOCK2MTD`,
  `CONFIG_BLK_DEV_LOOP`

### Fase 3 — initramfs (§6.4)

```bash
cd ~/gpu-work/initramfs-uke
BUSYBOX=/usr/bin/busybox ./build.sh          # enlaza e2fsck y llama al fichero /ukeinit
ls -la initramfs-uke.cpio.gz
# Sintaxis con el propio busybox bajo qemu (lo que ya hace build.sh):
qemu-aarch64 $BUSYBOX ash -n ./ukeinit && echo "init: sintaxis OK"
```
**Criterio de hecho:** `cpio.gz` < 8 MiB (holgura real: el actual son ~1 MiB), y
`qemu-aarch64 $BUSYBOX ash -n ./ukeinit` en verde.

⚠️ **Este es el punto donde se puede ser víctima del init de Android:** confirmar que el fichero se llama
**`ukeinit`** (no `init`) y que la cmdline del boot.img dice **`rdinit=/ukeinit`**.

### Fase 4 — Empaquetar el `boot.img` con el PATRÓN DEL PROYECTO

**Este es el paso crítico, y es una reescritura de `s244-boot-repack.py` con el kernel de Arch.** El script
original (leído completo) hace exactamente esto, y sus aserciones son las que hay que mantener:

```python
#!/usr/bin/env python3
"""arch-uke-boot: shell del par BUENO + KERNEL de Arch + initramfs de Arch. NO inventa cabecera."""
import struct, hashlib, subprocess, os, sys, gzip, io

SHELL   = "avb/boot-s244-bounce.img"     # <- que YA arrancó en esta tablet (firma AVB valida)
KERNEL  = "build-uke/arch/arm64/boot/Image.gz"
RAMDISK = "initramfs-uke/initramfs-uke.cpio.gz"
OUT     = "avb/boot-arch-uke.img"

PAGE, CMD_OFF, CMD_LEN, KS_OFF, SIG_OFF, STOCK_SIZE = 4096, 44, 1536, 8, 35438592, 100663296
SHA_SHELL = "ffff8c51265ff03c84cff15ffdb275f396a666a491eb5d67580be705321db99e"

# --- gates sobre el KERNEL (nunca por cadenas sueltas: por config embebido y simbolos) ---
kern = open(KERNEL, "rb").read()
assert kern[:2] == b"\x1f\x8b", "el kernel no es gzip"
assert 12_000_000 < len(kern) < 18_000_000, "Image.gz fuera de rango sano (~16.5 MB)"
raw = gzip.decompress(io.BytesIO(kern).read())
assert raw.find(b"UKE: se ignora") > 0, "falta el parche que ignora swiotlb=noforce"

# --- gates sobre el SHELL ---
src = open(SHELL, "rb").read()
assert hashlib.sha256(src).hexdigest() == SHA_SHELL, "el shell no es el par bueno"
img = bytearray(src)
assert len(img) == STOCK_SIZE and img[:8] == b"ANDROID!"
assert struct.unpack("<I", img[40:44])[0] == 4, "header_version != 4"
assert img[SIG_OFF:SIG_OFF+4] == b"AVB0" and img[-64:-60] == b"AVBf"

# --- cmdline: la del par bueno, BYTE A BYTE. Nada de reescribirla "por si acaso". ---
cmd = bytes(img[CMD_OFF:CMD_OFF+CMD_LEN]).split(b"\x00")[0].decode()
for need in ("mem=2048M", "memmap=0x1A12800$0xE3940000", "rdinit=/ukeinit",
             "console=ttyGS0,115200", "arm-smmu.disable_bypass=0"):
    assert need in cmd, "cmdline sin: " + need
assert "swiotlb" not in cmd, "la cmdline NO debe llevar token swiotlb"

# --- escribir: SOLO kernel_size@8 y el kernel desde 4096; el resto SE COPIA ---
img[KS_OFF:KS_OFF+4] = struct.pack("<I", len(kern))
img[PAGE:PAGE+len(kern)] = kern
GAP = PAGE + len(kern)
assert GAP < SIG_OFF, "el kernel no cabe antes del bloque de firma AVB"
img[GAP:SIG_OFF] = b"\x00" * (SIG_OFF - GAP)
blob = bytes(img)

# --- RA (realidad aumentada): verificar lo que se va a flashear ---
assert len(blob) == STOCK_SIZE and blob[:8] == b"ANDROID!"
assert blob[PAGE:PAGE+len(kern)] == kern
assert bytes(blob[CMD_OFF:CMD_OFF+CMD_LEN]).split(b"\x00")[0].decode() == cmd
assert bytes(blob[CMD_OFF+CMD_LEN:PAGE]) == src[CMD_OFF+CMD_LEN:PAGE], "se toco la cabecera"
assert blob[SIG_OFF:] == src[SIG_OFF:], "AVB footer alterado"
open(OUT, "wb").write(blob)
print("sha256", hashlib.sha256(blob).hexdigest())
subprocess.run(f"avbtool info_image --image {OUT}", shell=True)   # debe seguir diciendo 1769904000
```

**El `boot.img` de Arch tiene que salir de aquí, y con `fastboot boot` primero (RAM-boot, cero flashes).**

**Criterio de hecho:** `unpack_bootimg` del resultado muestra la cmdline esperada, el footer AVB sigue
diciendo rollback `1769904000`, y `cmp` del kernel del `.img` contra el del build da **IDENTICO**.

### Fase 5 — Prueba sin escribir (RAM-boot)

```bash
timeout 90 fastboot boot avb/boot-arch-uke.img      # el kernel se carga en RAM, la particion no se toca
# A la vez, en el PC:  bin/uke-console-cap.sh   ->  /dev/ttyACM0
```
**Criterio de hecho:** aparece la consola ACM y se lee `ukeinit: BC: ...` y el intento de `switch_root`.
⚠️ **Sólo un lector de consola** (no abrir dos `cat /dev/ttyACM0`).

### Fase 6 — `e2fsck` en frío + escritura del rootfs

```bash
# 6.1 e2fsck OBLIGATORIO antes de escribir el rootfs nuevo (la deuda de ~908 errores)
sudo e2fsck -f -y -v /dev/sda32        # ⚠ EN FRIO: sin el FS montado por nadie
# Si sale con reparaciones: repetir hasta "clean", porque la primera pasada crea huerfanos
sudo e2fsck -f -y -D /dev/sda32        # -D: optimizar directorios (el dmesg pedia justo esto:
                                       #  "ext4_dirblock_csum_verify: No space for directory leaf checksum")
```
**Criterio de hecho:** `e2fsck` termina en verde **dos pasadas seguidas**, y `dumpe2fs -h` sin
`Filesystem state: not clean`.

```bash
# 6.2 Escribir el rootfs Arch por la red del gadget (patron de uke-fase2-install.py, que ya funciona)
#   El PC sirve el rootfs por HTTP; la tablet lo baja y lo dd-ea a userdata.
#   bin/uke-http-rootfs.sh  ->  http://192.168.42.1:8000/rootfs.img.gz
busybox wget -O - http://192.168.42.1:8000/rootfs.img.gz | busybox zcat | \
    busybox dd of=/dev/disk/by-partlabel/userdata bs=4M conv=fsync
# 6.3 VERIFICACION (esto es lo que hace uke-fase2-install.py al final)
mount -t ext4 -o ro,noload /dev/disk/by-partlabel/userdata /mnt/x \
  && ls /mnt/x/sbin/init /mnt/x/etc/hostname && umount /mnt/x
```
> **Alternativa y por qué NO se usa `fastboot flash userdata`:** `userdata` son 105,9 GB y el `rootfs.img`
> comprimido son ~36 MB — **la red es más rápida y no gasta escritura de UFS**. Además el ledger avisa:
> *«`fastboot erase` y `fastboot flash` NO están igual de permitidos»*.

### Fase 7 — Flashear el `boot.img` y verificar la lectura de vuelta

```bash
# 7.1 sha256 PRE-REGISTRADO en el ledger ANTES de flashear (R7)
sha256sum avb/boot-arch-uke.img | tee -a LEDGER.txt

# 7.2 Flashear SOLO boot_b. NO set_active todavia (R2/RX: set_active va AL FINAL).
fastboot flash boot_b avb/boot-arch-uke.img

# 7.3 set_active b y reboot, en ese orden y como ultimo paso
fastboot set_active b
fastboot reboot
```
**Criterio de hecho (lectura de vuelta):** volver a entrar en fastboot y comprobar
- `fastboot getvar current-slot` → **`b`**
- el sha256 del `boot_b` leído del aparato == el del fichero (**patrón de ledger #241**: `su` sobre
  `/dev/block/by-name/*` hasheando **al tamaño exacto de la imagen** para anular el pad de ceros de la
  partición de 96 MB)
- `dtbo_b` sigue siendo el par bueno.

### Fase 8 — `qbootctl` (el contador de slot, **P0.5**)

```bash
# 8.1 PKGBUILD propio (deps del README: zlib, meson, cmake, linux-headers)
#     https://github.com/linux-msm/qbootctl
qbootctl                                # dump: ver los 4 slots y sus flags
qbootctl -c                             # current slot
qbootctl -n b                           # ¿marcado successful?
qbootctl -m                             # MARCAR el slot actual como successful
```
```ini
# 8.2 Unidad systemd (equivalente al `rc-update add qbootctl default` de pmOS)
# /etc/systemd/system/qbootctl.service
[Unit]
Description=Mark the current A/B slot as boot successful (qbootctl)
After=local-fs.target
ConditionKernelCommandLine=!androidboot.force_normal_boot
[Service]
Type=oneshot
ExecStart=/usr/bin/qbootctl -m
[Install]
WantedBy=multi-user.target
```
**Criterio de hecho (el de `docs/OBJETIVOS.md` P0.5):**
*«un reinicio deja `slot-retry-count:b` en 7 sin intervención»* — y sigue en 7 tras varios reinicios.
⚠️ **`cliffs` NO está en la lista de dispositivos validados** ⇒ la **primera ejecución de `qbootctl -m` es
la operación de mayor riesgo** de toda la guía. Hacerla **con el par bueno en el otro slot**, con
**qbootctl ya probado en modo lectura** (`-c`/`-n`/`-x`) y **sin tocar nada más** ese ciclo.

### Fase 9 — Sesión gráfica (desbloquea los subproyectos A y C)

- **Orden de desbloqueo:** `userdata`+`boot_b` arrancando Arch ⇒ **A (port de Omarchy)** y **C (Hyprland
  0.56 + Lua + Quickshell)** ya tienen dónde trabajar. El **DT propio** (`deviceinfo_dtb` de pmOS;
  `boot-m1-modern-dt.img` aquí) es lo que permite prescindir del `dtbo`.
- **Lo que aún bloquea la sesión gráfica** (medido hoy en la tablet): `/dev/dri` **no existe** (sin KMS/GPU:
  *«`msm_dpu … no IOMMU, bailing out`»*), `/dev/input` **no existe** (*«`novatek-nt36xxx-spi spi0.0: no IRQ
  specified`», `probe … failed with error -22`*), y hoy hay un **framebuffer virtual**
  (`video=vfb:640x400,bpp=32,memsize=3072000`) porque no hay GPU.
- ⚠️ **Trampa de instalación heredada, corregida en Arch:** las reglas udev del proyecto están en
  **`/etc/udev/99-uke-*.rules`**, *no* en `/etc/udev/rules.d/` ⇒ **hoy no se aplican**. En Arch, ponerlas
  donde udev las lee.

---

## 8. Tabla de particiones: qué va en cada una

**Mapa real medido en la tablet** (`lsblk -o NAME,SIZE,FSTYPE,PARTLABEL`, 121 partlabels, discos
`sd{a..f}`; UFS `HN8T05DEHKX073` de 117,1 GB). Se listan **sólo las que importan a Linux**:

| Partición | Disco:num | Tamaño | FS | Qué va | ¿Se toca? |
|---|---|---|---|---|---|
| **`boot_b`** | `sde39` | **96 MiB** | — | **`boot.img` de Arch** (header v4, kernel `Image.gz`@4096, cmdline 255 B, footer AVB `AVBf`) | ✍️ **SÍ — es LA partición de trabajo** |
| `boot_a` | `sde11` | 96 MiB | — | **pared de seguridad**: el par bueno (Ubuntu/`s240`) | 🔒 **NO** |
| **`dtbo_b`** | `sde43` | 24 MiB | — | Overlays vendor (`s229`) mientras no haya DT propio | 🔒 **NO** al principio |
| `dtbo_a` | `sde15` | 24 MiB | — | Par bueno del otro slot | 🔒 NO |
| **`vendor_boot_b`** | `sde49` | 96 MiB | — | **STOCK de la ROM.** Su ramdisk se concatena al nuestro ⇒ **de ahí `rdinit=/ukeinit`** | 🔒 **NO — sustituirlo rompió el arranque (ledger #238)** |
| `vendor_boot_a` | `sde21` | 96 MiB | — | Stock | 🔒 NO |
| **`userdata`** | `sda32` | **105,9 GiB** | **ext4** | **ROOTFS Arch** (`PARTLABEL=userdata`, UUID `2311404a-42a2-446e-b018-c918075b4f56`). El rootfs actual ocupa 7,8 GB ⇒ **margen sobrado** | ✍️ **SÍ — se reescribe** |
| **`misc`** | `sda12` | 4 MiB | — | **BCB**. Hoy: `command = "reboot-bootloader"` ⇒ el próximo reinicio puede caer a fastboot | ✍️ **limpiar** |
| `metadata` | `sda21` | 64 MiB | f2fs | metadatos de Android | 🔒 NO |
| `super` | `sda31` | 10,5 GiB | — | dynamic partitions de Android (system/vendor/product). **Irrelevante para Linux** | 🔒 NO |
| `oops` | `sda26` | 16 MiB | — | **nuestra** caja negra: `block2mtd`+`mtdoops` para volcar oops/panics y breadcrumbs | ✍️ (lo usa el initramfs) |
| `rescue` | `sda30` | 128 MiB | ext4 | rescate | 🔒 NO |
| `persist` | `sdf7` | — | — | **calibración de panel y táctil** | 🔒 NO (R: `REGLAS-PARTICIONES.md`) |
| `logfs` | `sda14` | 8 MiB | vfat | log del bootloader | 🔒 NO |
| `blackbox` | `sda25` | 154 MiB | — | blackbox del fabricante | 🔒 NO |
| `modem_a/b` | `sde6`/`sde34` | 202 MiB | vfat | firmware del módem | 🔒 NO |
| `dsp_a/b` | `sde9`/`sde37` | 64 MiB | ext4 | DSP | 🔒 NO |
| `abl_a/b` | `sde8`/`sde36` | 8 MiB | — | **EL BOOTLOADER** | 🔒 **JAMÁS** |
| `xbl_a/b` | `sdb1`/`sdc1` | — | — | XBL (etapa previa al ABL) | 🔒 **JAMÁS** |
| `xbl_config_a/b` | `sdb2`/`sdc2` | — | — | config de XBL | 🔒 **JAMÁS** |
| `uefi_a/b` | `sde1`/`sde29` | 5 MiB | — | imagen EFI **interna del ABL** (no es una ESP de usuario) | 🔒 NO |
| `tz_a/b`, `hyp_a/b`, `aop_a/b`, `devcfg_a/b`, `keymaster_a/b`, `qupfw_a/b`, `featenabler_a/b`, `shrm_a/b`, `cpucp_a/b`, `imagefv_a/b`, `uefisecapp_a/b`, `pvmfw_a/b`, `multiimg*`, `storsec`, `toolsfv`, `spunvm`, `dpm`, `xbl_ramdump_a/b` | — | — | — | la cadena de confianza del SoC | 🔒 **JAMÁS** (el ledger: *«es lo único que puede dejar el aparato irrecuperable si se corta la corriente»*) |
| `vbmeta_a/b` | `sde14`/`sde42` | 128 KiB | — | AVB | 🔒 **NO** (ledger #235→#240: tocarlo mató el arranque visible) |
| `vbmeta_system_a/b` | `sda17`/`sda18` | 128 KiB | — | AVB del sistema | 🔒 NO |
| `init_boot_a/b` | `sde26`/`sde53` | 8 MiB | — | Magisk/root de Android | 🔒 NO (irrelevante para Linux) |
| `recovery_a/b` | `sde24`/`sde51` | 100 MiB | — | recovery Android | 🔒 NO |
| `ffu`, `frp`, `keystore`, `secdata`, `countrycode_a/b`, `fsg`, `fsc`, `modemst1/2`, `opconfig`, `rawdump`, `mbnconfig`, `devinfo`, `charger`, `bk01..bk07`, `bk51`, `cdt`, `ddr`, `dbg`, `mem`, `mtdblk`, `switch`, `ssd`, `apdp`, `apdpb`, `ALIGN_TO_128K_1/2` | — | — | — | miscelánea del fabricante | 🔒 NO |

> **Nota de nombres (discrepancia a resolver, no resuelta aquí):** el DT que arranca dice
> `Qualcomm Technologies, Inc. Uke based on **SM8635**` con `compatible` raíz **`qcom,cliffs-mtp` / `qcom,cliffs`**,
> mientras el README del proyecto llama al SoC **SM7675 «cliffs»**. La plataforma interna es `cliffs` en
> todas las trazas (`disp_cc_sm8550`, `palawan-gpucc`). Antes de escribir cualquier `deviceinfo`/nombre de
> paquete hay que fijar el nombre correcto — **no verificado** cuál de los dos es el de marketing.

### 8.1 Notas de GPT/atributos

- **R1 (obligatoria):** *«Solo `fastboot set_active` cambia el slot activo. Prohibido editar attrs de slot
  por `dd`/script*… *Prohibido `--scope boot` (edición parcial): cualquier cambio GPT de slot toca las **54
  entradas `_a/_b`** o no se hace.»*
- **R12:** *«Toda recuperación de GPT se hace con los ficheros de fábrica **parcheados a la geometría real
  del disco** (`gpu-work/w2-out/gpt_*4-fixed`, validados con SHA + parser GPT) o por EDL
  `rawprogram+patch`; nunca reflasheando particiones "a ver si".»* ⚠️ *«Los ficheros crudos de la ROM no
  sirven: su backup apunta a LBA falsa.»*
- **R2:** tras cualquier escritura GPT o `set_active`: **re-dump → `verificar-gpt.py` (TABLA SANA +
  backup==primaria) → getvars → comparar → sólo entonces `reboot`.**
- **R4:** verificar **backup Y primaria**, nunca una.
- **Los 4 KB del ramoops se reparten por device tree** (`record-size`, `console-size`, `pmsg-size`); el
  overlay del proyecto puso `pmsg-size = 0x00` ⇒ **`/dev/pmsg0` no existe**. El canal que funciona sin
  panic es **`console-ramoops-0`** (ledger #230).

---

## 9. Riesgos y mitigaciones

| # | Riesgo | Evidencia / medida | Mitigación |
|---|---|---|---|
| **1** | **El fork sin consolidar** ⇒ se pierde `qcom_battmgr.c` (carga de batería), `ath11k`, `ufs-qcom.c` (UFS), `swiotlb`, panel o82, táctil NT36532 | **27 ficheros modificados + 2 sin trackear** en el working tree de `~/gpu-work/palawan-linux` | **Commitear TODO antes de empaquetar.** *«si se empaqueta desde el `.git`, se pierde ~todo el estado de working tree»*. Criterio: `git status --porcelain \| wc -l` → 0 salvo lo intencional, y el árbol compila desde un tarball limpio |
| **2** | **En fastboot la tablet NO carga** (sólo baja la batería) | ledger: `battery-voltage` **3780 mV** durante un flasheo; el ADSP está apagado en fastboot | **Umbral GO ≥ 3700 mV** medido 3×. Cargador de **pared** (el puerto del PC es SDP, 100–500 mA: *«con cargador de pared los ciclos pasan de horas a minutos»*). `bin/uke-fastboot-watch.sh` vigilando |
| **3** | **El contador de slots cae a 0 ⇒ la tablet cae a fastboot** | Medido: el 25-sep cayó **3 veces** (`slot-retry-count:b=3` por la mañana; dos veces con slot b **unbootable** y contador a 0 por la tarde) | **`qbootctl` (Fase 8)** + **mismo par bueno en AMBOS slots** + recuperación con `set_active b; set_active a`. *«sin esto, cada ~7 arranques hay que ir a fastboot a mano — es exactamente la deuda que hace inservible el dispositivo en remoto»* |
| **4** | **El BCB de `misc` sucio** | Medido hoy: `command[0:32] = "reboot-bootloader"`. Y *«Un `adb reboot` normal NO limpia el BCB»*; *«misc contiene BCB "bootonce-bootloader"… el ABL no lo soporta y NUNCA lo limpia»* | **Limpiar `misc` a ceros (8192 B) ANTES de empezar** y **volver a comprobar** tras cada sesión. Guardar el `.img` de ceros |
| **5** | **El rootfs ext4 con `norecovery`** | `mount` → `/dev/sda32 ext4 (rw,relatime,norecovery)`; `dmesg`: **error count since last fsck: 908** (`ext4_free_inode:356`, `ext4_lookup:1789: deleted inode referenced`, `ext4_dirblock_csum_verify:375: No space for directory leaf checksum`) | **`e2fsck -f -y` (y `-D`) EN FRÍO**, dos pasadas en verde, antes de escribir. **Y el initramfs nuevo monta SIN `noload`** ⇒ el journal se reproduce en cada arranque. El `-o ro,noload` del `ukeinit` actual es **la causa raíz** (ledger #3059) |
| **6** | **El `/init` de Android sobrescribe el nuestro** | Ledger :2964-2965: el `/init` que corría y exita 127 **era el de Android**, del ramdisk de `vendor_boot` stock | **Llamar al init `/ukeinit`** + `rdinit=/ukeinit` en la cmdline. **No** renombrar a `/init` "para que sea estándar" |
| **7** | **Tocar `vbmeta` rompe el arranque visible** | Ledger #235 → #240: con `vbmeta_b` flags-off, *«s110 TAMPOCO pinta nada»*; la config era idéntica salvo eso | **`vbmeta` NO se toca.** No hace falta `--disable-verity --disable-verification` (el aparato está `unlocked` y el digest AVB ya arrancó aquí) |
| **8** | **Regresión de config del kernel** (perder 498 opciones) | `docs/CONFIG-BUENO.md`: se depuró 3 sesiones un USB sin PHY ni relojes | **Gate de 3 comprobaciones** (opciones/símbolos/tamaño) en verde + centinela del parche + **`Image.gz` ≥ 16 MB** |
| **9** | **El kernel no cabe antes del bloque AVB** | `SIG_OFF=35438592`; el `Image.gz` actual son 16 559 711 B desde 4096 | `assert GAP < SIG_OFF` (el script ya lo hace). Un kernel >35 MB **no cabe** ⇒ si pasa, toca `isorec` |
| **10** | **Sabotear el GPT** | **Brick del 11-sep-2026** causado por `gpt-switch.sh` | **R11: prohibido editar attrs GPT con herramientas propias.** Sólo `fastboot set_active`. **R1/R2/R4/R12** completas |
| **11** | **Sustituir `vendor_boot`** mata el arranque | Ledger #238: con `vendor_boot_b=s38-pstore` *«el fork moría ANTES del pintor»*; revertido a stock | **No tocar `vendor_boot_b`** |
| **12** | **`qbootctl` en un SoC no validado** | El propio README: *«This may or may not render any hardware you run it on unusable, you have been warned.»* `cliffs` **no** está en la lista validada | Hacerlo **en modo lectura primero** (`-c`/`-n`/`-x`), **con el par bueno en el otro slot**, **un cambio por ciclo**, fila de ledger, y `CONFIG_SCSI_UFS_BSG=y` confirmado |
| **13** | **Reloj sin RTC** | `date` en la tablet: **Thu Sep 24 15:08** vs realidad 26-sep ~19:00 ⇒ **~2 días de atraso**. `fake-hwclock.data = "2026-09-24 15:00:02"` | El atraso se acumula porque sólo se guarda **al apagar limpiamente**. Mitigación: `fake-hwclock` (paquete de ALARM/AUR: existe en Arch) + `fake-hwclock.service` **con save periódico, no sólo al apagar**, + NTP en cuanto haya red. ⚠️ Rompe SSH/TLS si el atraso es grande |
| **14** | **Ruido del UFS que inunda la consola** | `devfreq … dvfs failed (-22)` cada ~2 s ⇒ *«inunda la consola y tapa el log»* | Silenciar/arreglar en el driver (`ufs-qcom.c`) — viaja con el fork. Y máscaras de log en sesiones largas (la instrumentación de genpd genera **cientos de líneas/s**) |
| **15** | **Un fallo temprano no deja ningún log** | P0.3: *«la consola va por `ttyGS0`, que lo levanta userspace: un fallo temprano no deja ningún log (ni pstore, porque el wedge para todos los kthreads y no hay panic)»* | **El gadget ACM en el initramfs** (Fase 3). Es **justo** la pieza que hay que portar. Y el `console-ramoops-0` (el `pmsg0` no existe) |
| **16** | **`mem=2048M` deja 1,6 GB** | `MemTotal: 1645140 kB` con `mem=2048M`; y **el banco >4 GB sigue apareciendo** (`880000000-88b9cefff`) ⇒ el trabajo del `swiotlb` **no está terminado** | Llevar `mem=2048M` en la cmdline hasta que el `swiotlb` se cierre. **No** usar `swiotlb=force` (mata el MSI de ath11k) |
| **17** | **La tablet NO carga sólo con el PC** | Entrada USB capada a **SDP** (100–500 mA, de sólo lectura) | Cargador de **pared** para ciclos de flasheo. Gobernador: hoy vuelve a `performance` en cada arranque ⇒ decidirlo en la cmdline de Arch |
| **18** | **`fastboot erase` ≠ `fastboot flash`** | Ledger #230: *«el ABL puede rechazar el borrado de una partición entera y aceptar la escritura de una imagen sparse»* | **Escribir sparse en vez de borrar** |
| **19** | **Dos sesiones de agente en paralelo** | El ledger registra solapes (#232/#233/#234): *«de aquí en adelante, ESA sesión NO flashea sin coordinar; solo lee»* | **Un cambio por ciclo**, fila pre-registrada, y coordinación explícita |
| **20** | **No verificar la lectura de vuelta** | El proyecto lo hizo bien en #241: hashear el `boot_b` leído **al tamaño exacto de la imagen** (anula el pad de ceros de los 96 MB) y comparar con lo esperado | **Hacerlo siempre.** *«Boot_b=0f8bef19 ✓, dtbo_b=b763f2d9 ✓ … las particiones de B son EXACTAMENTE las de las 00:15 que PINTÓ.»* |

### 9.1 Lo que NO puede salir mal (dominio de la promesa)

`REGLAS-PARTICIONES.md` **R8**: *«"Peor caso = latch→fastboot" vale SOLO para flashes `boot_b` vía fastboot
con A intacto; nunca para ediciones GPT/`set_active`/XBL/ABL. **Sin dominio escrito, no se promete.**»*

| Operación | Peor caso | ¿Vuelta atrás? |
|---|---|---|
`fastboot flash boot_b` con `boot_a` intacto y par bueno | **latch → fastboot** (recuperable) | ✅ 
`fastboot flash userdata` (rootfs) | se pierde el rootfs antiguo (hoy: Ubuntu sin datos de usuario: `/home` **vacío**, sin UID ≥ 1000) | ✅ (se reinstala) 
`fastboot set_active` mal usado | slot a medio flashear ⇒ unbootable | ⚠️ recuperable con `set_active` inverso si el contador no llegó a 0 
**Flujo del bootloader** (`abl`/`xbl`/`tz`/…) | **irrecuperable sin EDL** | ❌ **NUNCA** 
Edición de attrs GPT por `dd` | **brick (ocurrió el 11-sep-2026)** | ❌ **PROHIBIDO** 
Flujo de GPT (R12) | GPT corrupta ⇒ sin disco | ❌ sólo con ficheros de fábrica **parcheados a la geometría real** |

---

## 10. No verificado

Todo lo de esta sección **no lo he podido comprobar**; se marca explícitamente para no arrastrarlo como si
fuera hecho.

1. **Slot activo ahora mismo.** El `cmdline` **no** lleva sufijo de slot (no hay `androidboot.slot_suffix`),
   y `misc` sólo dice `reboot-bootloader`. Los docs del proyecto afirman «slot **b** activo». **Es dato de
   segunda mano**: confirmarlo con `fastboot getvar current-slot` es la **Fase 0.1**.
2. **Si el ABL llegó a consumir el BCB `reboot-bootloader`.** No he reiniciado nada. Puede ser un **resto**
   de una sesión de depuración (el proyecto usa el BCB para su «fastboot autónomo»).
3. **Que `qbootctl` funcione en `cliffs`.** No está en la lista de dispositivos validados
   (Pixel 3a, OnePlus 6/6T/8 Pro, SHIFT6mq, Xiaomi 12). **Es la incógnita más grande de la guía.** El
   requisito de kernel (`CONFIG_SCSI_UFS_BSG=y`) **sí** está — verificado en el config de referencia.
4. **Que `boot.img` de Arch quepa.** Depende del tamaño del `Image.gz` de Arch (~16,5 MB hoy ⇒ cabe de
   sobra antes de `SIG_OFF=35438592`). Con un kernel más gordo podría hacer falta `isorec`.
5. **Que el rootfs Arch ARM aarch64 arranque tal cual** en `cliffs`. ALARM **no lista** este dispositivo;
   los paquetes son genéricos y el kernel lo ponemos nosotros ⇒ **es plausible pero no probado**.
6. **Compactibilidad de la `userdata` de 105,9 GB con el `mkinitcpio` de Arch.** El `e2fsck` sobre
   `/dev/sda32` **puede tardar mucho** (105,9 GB con 908 errores); no lo he medido.
7. **El `deviceinfo`/nombre de SoC definitivo** (SM7675 vs SM8635). Afecta a `arch`/`soc` de pmOS y al
   nombre del paquete de firmware.
8. **WiFi/BT reales.** `ath11k` está blacklisteado (`/etc/modprobe.d/blacklist-ath11k.conf`) y hay un muro
   de DMA (banco >4 GB). No he probado `iw`/`nmcli` (**no están instalados**). El estado de `lsmod`
   (ath11k cargado) y el de `/etc/modprobe.d` (blacklisteado) **son incoherentes** — observación del
   inventario, no resuelta.
9. **GPU/panel/táctil.** En el arranque actual `/dev/dri` y `/dev/input` **no existen**; sólo hay
   `drm_panel`, `backlight` y `video=vfb`. La sesión gráfica (Fase 9) está **medida como imposible hoy**:
   es trabajo del subproyecto C. Concretamente, los fallos: `msm_dpu … no IOMMU, bailing out`,
   `novatek-nt36xxx-spi spi0.0: no IRQ specified`, `probe … failed with error -22`.
10. **`danctnix`**: mencionado como port de terceros aarch64 (Pine64/Qualcomm), **no verificado** en detalle.
11. **El «techo de 64 MiB» de `fastboot boot`**: lo dice el comentario de `pack-bootimg.sh` (*«el ABL la
    puede rechazar (Bad Buffer Size, R3 §1.2)»*). No he encontrado la fuente primaria del valor exacto.
12. **El estado exacto de `e2fsck` en frío**: `-D` (optimizar directorios) lo **pide el propio dmesg**, pero
    **no he ejecutado nada** (sería escritura y en caliente no se puede). Puede que haga falta **más de una
    pasada**.
13. **Los números de ledger que cito** (`:2964-2965`, `#238`, `#241`, `#3059`) están leídos de
    `docs/FLASH-LEDGER.md` y `docs/TRABAJO-PENDIENTE.md` **tal cual**, sin cotejar contra el aparato.
14. **Los `dtbo` del proyecto** (`s229`, `s241`, `s246`, `gpu-off.dtbo`, `smmu-on.dtbo`, `uke-ovl/*`) están
    **listados y nombrados pero no desensamblados** (`dtc` no está en la tablet). Su contenido exacto, no.
15. **`/dev/ttyACM0` no se ha leído a propósito** (la consola tiene lector y **sólo puede haber uno**).
    Toda la consola serie queda **fuera** de esta investigación.

---

## Anexo A — Ficheros y comandos citados

**En `pc-build`** (lectura sólo, por `sshpass -p <CONTRASEÑA> ssh -J PC-PORTATIL usuario@100.64.0.11`):

| Ruta | Qué aporta |
|---|---|
`~/gpu-work/ramaa/s21/s244-boot-repack.py` | **El patrón del `boot.img`**: `PAGE/CMD_OFF/CMD_LEN/KS_OFF/SIG_OFF/STOCK_SIZE` y todas las aserciones (§6.4/Fase 4) |
`~/gpu-work/ramaa/s21/s244-boot-repack-report.txt` | Salida del gate: kernel `adad4bb4dc1567d1`, 16 559 711 B, base 16 560 041, sha256 `ffff8c51…`, AVB OK |
`~/gpu-work/ramaa/s21/avb/boot-s240-mem2g.img` | **El «shell»** (sha `e3c60969269c0b36…`) con la cmdline de 255 B |
`~/gpu-work/initramfs-uke/{init,build.sh,pack-bootimg.sh,README.md}` | El initramfs actual completo; el `pack-bootimg.sh` con `mkbootimg --header_version 4 --pagesize 4096` |
`~/proyectos/ubuntu-permanente/bin/uke-fase2-install.py` | El patrón de escritura del rootfs por red + verificación posterior |
`~/proyectos/ubuntu-permanente/bin/uke-flash.sh` | El patrón de flasheo: `fastboot flash` → `set_active b` → `reboot` |
`~/proyectos/ubuntu-permanente/bin/uke-console-cap.sh` | Capturador de `/dev/ttyACM0` reabriendo en cada vuelta |
`~/proyectos/ubuntu-permanente/docs/{REGLAS-PARTICIONES,CONFIG-BUENO,MIGRACION-PORT-MODERNO,OBJETIVOS,ESTADO-ACTUAL,FLASH-LEDGER}.md` | Las reglas duras R1–R12, el gate de config, y todos los hallazgos de slots/BCB/AVB |
`~/gpu-work/palawan-linux/configs-uke/{config-bueno-actual.config,opciones-criticas.txt,simbolos-criticos.txt,nuevo-build-bueno.sh}` | El config de referencia y los centinelas |

**En la tablet** (`root@192.168.42.129`, doble salto, sólo lectura): `/proc/cmdline`, `/proc/version`,
`/proc/cpuinfo`, `/proc/iomem`, `/dev/disk/by-partlabel/` (121 entradas), `misc` (lectura de 4 KiB con
Python), `lsblk -o NAME,SIZE,FSTYPE,PARTLABEL`.

**URLs verificadas**

| Tema | URL |
|---|---|
Descargas ALARM aarch64 + clave de firma | https://archlinuxarm.org/about/downloads |
Dispositivos soportados por ALARM (la uke **no** está) | https://archlinuxarm.org/platforms |
PKGBUILD `linux-aarch64` | https://github.com/archlinuxarm/PKGBUILDs/blob/master/core/linux-aarch64/PKGBUILD |
Port aarch64 (estado **Unofficial**, quién: `solskogen`/`bschnei`, repos de terceros drzee.net) | https://ports.archlinux.page/aarch64 |
RFC 0032 Arch Linux Ports | https://rfc.archlinux.page/0032-arch-linux-ports |
Instalar Arch desde un Linux existente (`pacstrap`) | https://wiki.archlinux.org/title/Install_Arch_Linux_from_existing_Linux |
`mkinitcpio` (hooks, systemd vs busybox, presets) | https://wiki.archlinux.org/title/Mkinitcpio |
Proceso de arranque de Arch | https://wiki.archlinux.org/title/Arch_boot_process |
Kernel: opciones y compilación | https://wiki.archlinux.org/title/Kernel |
Fydetab Duo: build (repo, particiones, GPU, **no UEFI no grub**) | https://github.com/Linux-for-Fydetab-Duo/imagebuild/blob/main/docs/build-internals.md |
Fydetab Duo: README (perfiles, cross-build, `[fyde]` primero, first boot) | https://github.com/Linux-for-Fydetab-Duo/imagebuild/blob/main/README.md |
Fydetab Duo: instalación (`rkdeveloptool`, MASKROM) | https://wiki.fydetabduo.com/Available-OS/ArchLinux/arch-install |
pmOS: slots A/B, contador, GPT, UFS bBootLunEn, **qbootctl** | https://wiki.postmarketos.org/wiki/Android_AB_Slots |
pmOS: `qbootctl` (README, CLI, musl/glibc, aviso) | https://github.com/linux-msm/qbootctl |
pmOS: proceso de arranque (boot.img, isorec) | https://wiki.postmarketos.org/wiki/Boot_process |
pmOS: initramfs (tareas, cmdline `pmos.*`, `initramfs-extra`, switch_root) | https://wiki.postmarketos.org/wiki/Initramfs |
pmOS: red USB (`172.16.42.1`, `unudhcpd`, NCM) | https://wiki.postmarketos.org/wiki/USB_Network |
pmOS: depurar el arranque (`pmOS_init.log`, ramoops, `bootimg_analyze`) | https://wiki.postmarketos.org/wiki/Troubleshooting:boot |
pmOS: Qualcomm (cadena de arranque, ABL desde msm8996) | https://wiki.postmarketos.org/wiki/Qualcomm |
pmOS: paquete de kernel downstream (GCC, `KERNEL_IMAGE_NAME`) | https://wiki.postmarketos.org/wiki/Downstream_kernel_specific_package |
Android: cabecera del boot image (v4, `struct`, `boot_signature`) | https://source.android.com/docs/core/architecture/bootloader/boot-image-header |
Android: `vendor_boot` (GKI, fragmentos de ramdisk, bootconfig) | https://source.android.com/docs/core/architecture/partitions/vendor-boot-partitions |

*(Las URLs de `wiki.postmarketos.org` están detrás de **Anubis** para clientes automatizados; el contenido
citado se obtuvo de los **snapshots de Wayback Machine** — la ruta canónica es
`https://web.archive.org/web/2026/https://wiki.postmarketos.org/wiki/<Página>`.)*

## Anexo B — Resumen en una tabla

| Bloque | Veredicto | Trabajo |
|---|---|---|
Rootfs Arch ARM aarch64 | **DIRECTO** (tarball ALARM multi-platform) | 1-2 días |
Kernel propio (fork consolidado, PKGBUILD) | **RE-PORTAR** — y **consolidar antes** es el riesgo #1 | 3-5 días |
initramfs + `/ukeinit` (label, `switch_root`, consola ACM) | **RE-PORTAR** (el `ukeinit` actual sirve de base) | 2-3 días |
`boot.img` con el patrón del proyecto | **DIRECTO** (reescritura de `s244-boot-repack.py`) | 0,5 día |
Flasheo + verificación (sha256, lectura de vuelta) | **DIRECTO** (patrón existente) | 0,5 día |
`misc`/BCB | **ADAPTAR** (limpiar a ceros) | 0,5 día |
**`qbootctl`** | **ADAPTAR** (empaquetar en Arch + validar en `cliffs`) | **1-2 días — prioridad alta** |
`e2fsck` + la deuda del `norecovery` | **ADAPTAR** (el initramfs nuevo monta sin `noload`) | 0,5 día |
DT propio / prescindir del `dtbo` | **RE-PORTAR** (artefacto ya probado: `boot-m1-modern-dt.img`) | **3-8 días** |
Reloj sin RTC | **ADAPTAR** (`fake-hwclock` con save periódico) | 0,5 día |
Sesión gráfica (Hyprland/Quickshell) | **bloqueada hoy** por GPU/panel/táctil (subproyecto C) | — |
