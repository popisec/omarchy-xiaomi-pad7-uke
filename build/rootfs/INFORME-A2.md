# INFORME A2 — imagen rootfs Arch ARM para uke (grupo F5-A2)

Fecha: 27-sep-2026 (00:3x CEST). Todo offline, sin sudo, sin tablet, sin mount/loop.
Salidas en `~/proyectos/omarchy-uke/build/rootfs/`:
`arch-rootfs.img` (8 GiB) · `arch-rootfs.img.gz` · `SHA-ARCH.txt` ·
`INFORME-A2.md` (este) · `PACKAGES-OVERLAY.txt` (171 pkgs) · `uke-arch-root(.pub)` (clave operador) ·
`pkgs/` (DBs + 171 `.pkg.tar.xz` + `fetch.sh` + `index.json`) · `dl/` (base + sig + md5) · `staging/`.

## (a) Construcción paso a paso (reproducible)

1. Base: `http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz` (829 367 415 B).
   md5 `23eec86365b24f7913c403e8f4e8719b` OK contra `.md5`. Firma GPG **OK**:
   `gpg --verify` → «Firma correcta de Arch Linux ARM Build System»,
   huella `68B3 537F 39A3 13B3 E574 D067 7719 3F15 2BDB E6A6` (clave traída de keyserver.ubuntu.com).
   Ojo: el primer intento sin `-L` descargó 0 B (el 302 a `fl.us.mirror` no se seguía).
2. Extracción a `staging/` con `tar -xzf`. Incidencia: `etc/ca-certificates/extracted/cadir/`
   viene con modo 555 y tar como no-root no puede poblarlo (ni con `--no-same-permissions`,
   tar reaplica el modo al final). Fix: extraer ese subárbol a temp y `cp -r` (363 ficheros OK).
3. Espejos de paquetes: **SÍ responden** (refuta la nota previa de «000/404» para estos):
   `fl/nj/ca/de.us.mirror.archlinuxarm.org/aarch64/{core,extra,alarm,aur}/…db` → 200.
   Se resolvió el cierre de dependencias parseando `desc`+`depends` de los DBs
   (235 nodos, 171 ficheros, 156 MB) y se descargó todo de `fl.us.mirror`.
   Magia `xz` verificada en los 171 (0 corruptos).
4. La base ya traía systemd/openssh/mkinitcpio/e2fsprogs/dbus/pacman (166 pkgs).
   Se superpusieron con `bsdtar -xpf` 44 pkgs NUEVOS + 47 UPG (detalle en §b).
   Incidencia: mi glob `n-*` emparejó prefijos (`systemd`→`systemd-libs`) y 7 pkgs
   (systemd, util-linux, pacman, mkinitcpio, ca-certificates, libcap, perl) quedaron
   sin extraer; detectado por `systemctl --version` (261 vs 262) y corregido con
   `extract-missing.txt`. Incidencia: el overlay pisó `/etc/{passwd,group,shadow,fstab}`
   (el pkg `filesystem` trae skeletons) y `mirrorlist` → **reconstruidos al final**.
   Lección: toda edición de `/etc`, DESPUÉS del último overlay.
5. Scriptlets emulados a mano: usuarios `polkitd(102:102,fijo)`, `chrony(968,!bloq)`,
   `git(967,git-shell)`, `pcscd(966,!bloq)` en passwd/group/shadow/gshadow.
   `depmod` del overlay de módulos corrido con `qemu-aarch64 -L staging …/depmod -b staging`
   (rc=0; `ath11k_{pci,ahb}.ko: ath11k.ko` resuelto). Se eliminó el symlink colgado
   `build -> ~/gpu-work/w1-out/build`.
6. Recorte (la imagen cabe de sobra y el transporte adelgaza): fuera kernel stock
   (`/boot/Image*`, `initramfs`, `dtbs/`, `/usr/lib/modules/7.1.6-1`: 381 MB),
   fuera firmware x86/irrelevante (`intel nvidia amdgpu mediatek ath12k i915 rtw89
   ath10k radeon xe dpaa2…`: 960→151 MB; **se conserva `ath11k/` con `WCN6750/`+`wpss.mdt`**)
   y 206 symlinks colgados a `intel/` borrados. Staging: 2,1 GB → 1,2 GB.
7. Setuid: tar como no-root los deja en 755. Repuestos por lista (sudo/su/passwd/mount/…,
   `unix_chkpwd` 6755 y `wall/write`+`var/log/journal` 2755 según .MTREE).
8. Imagen: `truncate -s 8G` + **`fakeroot chown -R 0:0` + `mkfs.ext4 -F -L arch-arm -d staging`**
   (sin root, sin loop — el truco verificado). Incidencia: `dbus-daemon-launch-helper`
   es modo 0111 (ilegible) y mkfs aborta; fix: `chmod u+r` temporal y restaurar a
   0111 dentro de la imagen con `debugfs -w set_inode_field … mode 0100111` (verificado).
   Limpieza: 4 dotfiles `.BUILDINFO/.INSTALL/.MTREE/.PKGINFO` en `/` (uno por pkg,
   el último era util-linux) borrados con `debugfs rm`. `e2fsck -fn`: limpio.
9. `gzip -9` → `.gz`; `sha256sum` de ambos en `SHA-ARCH.txt`.

## (b) Paquetes: qué hay y qué falta

- Base (166): systemd 262, openssh 10.5p1, mkinitcpio 42, e2fsprogs, dbus(+broker),
  iproute2, pacman 7.1, sudo 1.9.17, bash, shadow, pacman-mirrorlist, tzdata,
  archlinux-keyring+archlinuxarm-keyring, dhcpcd, netctl, linux-firmware (recortado).
- Añadidos (44): **networkmanager 1.58.1** (+libnm/libndp/libmm-glib/libmbim/libqmi/
  libqrtr-glib/modemmanager? NO — ver faltas), **openssh**, **iio-sensor-proxy 3.9**,
  **libwacom 2.20**, **fake-hwclock 0.3-2** (de `alarm`), **sudo**, **git 2.55**,
  busybox 1.36.1, chrony 4.9, wpa_supplicant, polkit 127, perl, nss, protobuf…
  (lista exacta: `PACKAGES-OVERLAY.txt`).
- **FALTAN (lista explícita)**: `modemmanager` (NM sin WWAN; irrelevante aquí),
  `libfido2` (solo optdepend de openssh), `xorg-xauth/x11-ssh-askpass` (X-forwarding),
  `dnsmasq` (NM lo usa opcional), `bluez/bluez-libs` (BT; NM funciona sin ellos),
  `linux-uke` (no existe como pkg: el kernel lo pone el `boot.img`, §d),
  `qbootctl` (herramienta pmOS, no existe en ALARM), firmwares Adreno `gen71100`
  (no hay dir `qcom/` en este snapshot de linux-firmware — GPU es F1/F2, no F5),
  `hyprland/quickshell/omarchy*` (eso es F6, con red en la tablet).
- Escaneo NEEDED sobre **987 ELFs** de `/usr/bin`: solo 5 binarios con libs ausentes,
  todos no-críticos: `arpd` (libdb), `memusagestat` (libgd), `pinentry-gnome3/gtk/qt`
  (gtk/qt6/gcr; `pinentry-curses/tty` OK). **sshd, NetworkManager, sudo, bash,
  systemd, git, chronyd: OK.**
- Smoke bajo `qemu-aarch64 -L staging`: `bash --version` (5.3.20 aarch64),
  `systemctl --version` (262), `sshd -T` (rc=0, `PermitRootLogin prohibit-password`,
  `PubkeyAuthentication yes`, puerto 22). systemd completo NO arrancado (imposible sin máquina).

## (c) Cómo se entra

- USB gadget (lo levanta el ukeinit-arch de A1, no esta imagen): `rndis/ecm.usb0`,
  IP tablet `192.168.42.129`, puerto 22.
- `ssh -i uke-arch-root root@192.168.42.129` (pub ya en `/root/.ssh/authorized_keys`;
  **la privada `uke-arch-root` queda en `build/rootfs/`, FUERA de la imagen**).
- Fallback: `root` / contraseña (fuera del repo, en `~/.config/omarchy-uke/root-tablet.pass`) (hash SHA512 `$6$<SALT-ELIMINADO>$…` en `/etc/shadow`).
- Consola serie por ACM como siempre (`console=ttyGS0,115200` la pone la cmdline del boot.img).
- Servicios: `sshd` + `fake-hwclock(+timer)` + `systemd-timesyncd/resolved` habilitados.
  **NetworkManager instalado pero DESHABILITADO** a propósito (sin él, nada toca `usb0`
  con la IP estática del init; se habilita por SSH cuando haya WiFi en F3).

## (d) Lo que NO se pudo hacer sin root/emulación y su impacto

1. **Scriptlets de pacman** (ldconfig, sysusers/tmpfiles hooks, update-ca, mkinitcpio
   -p, ssh-keygen -A): emulados a mano (usuarios, depmod, host keys, setuid, modes).
   Riesgo bajo; en la tablet con red, `pacman -Syu` reconcilia la DB (que queda
   **rancia**: dice systemd 261 etc. — documentado, no es fallo).
2. **`linux-uke`**: no se compila/empaqueta aquí; el kernel 7.2-rc2-palawan+ viaja en
   el `boot.img` (A3) y sus 5 `.ko` (vermagic `7.2.0-rc2-palawan+`, medido con modinfo)
   van en `/lib/modules/…/extra` + depfiles del overlay `u1-prep`.
   La mayoría de drivers van **in-tree/builtin** (el overlay no trae `.ko`: normal).
3. **fstab por UUID: [NO VERIFICADO]** — sin acceso a la tablet no conozco el UUID de
   `userdata`; uso `/dev/disk/by-partlabel/userdata` (lo que usa el proyecto hermano).
   Si el ukeinit monta por otro nombre, systemd hace remount por esta línea igualmente.
4. Primer `pacman -Syu`/reloj: sin RTC hasta NTP; `fake-hwclock` + `timesyncd` lo cubren.

## (e) Plan B si no arranca en la tablet

1. La consola ACM manda: si no hay `uke-init:` es el boot.img (A3/B2), no esta imagen.
2. Si `switch_root` falla: desde el initramfs montar userdata y mirar
   `/sbin/init`, `/etc/os-release` (este .gz se re-escribe por el mismo canal
   `wget|zcat|dd`, §B3 de F).
3. Si systemd no levanta: `rdinit=/bin/sh` temporal en un `boot.img` de prueba
   (RAM-boot, sin escribir) para inspeccionar.
4. Si SSH falla: primero sospechar del reloj (1970) antes que de la red;
   `fake-hwclock` debería evitarlo; la contraseña documentada evita depender de la key.
5. Vuelta atrás: `fastboot set_active a` + re-`dd` del `rootfs.img.gz` de Ubuntu
   (`~/gpu-work/ramaa/s22/`, 370 MB, NO tocar hasta cerrar F5).

## Verificación (salidas reales, 27-sep-2026)

- `debugfs stat /sbin/init`: symlink → `../lib/systemd/systemd`, User 0.
- `debugfs cat /usr/lib/os-release`: `Arch Linux ARM` (os-release es symlink; `cat` directo falla en debugfs, [NO VERIFICADO] por esa vía pero sí por el target).
- `debugfs ls /lib/modules/7.2.0-rc2-palawan+/extra`: 5 `.ko` (ath11k×3, qcom_battmgr, qcom_pd_mapper).
- `e2fsck -fn`: `47668/524288 ficheros, 349816/2097152 bloques`, limpio.
- (tras gzip) sha256 en `SHA-ARCH.txt` + `ls -la` + comparativa con 370 MB de Ubuntu.

## Cierre (números finales medidos)

- `arch-rootfs.img`: 8 589 934 592 B (8 GiB), sha256
  `c36557503f4b6fa0ee30facc5a6c3908d82156613447c4ba73915f6830ac2653`.
- `arch-rootfs.img.gz`: 403 133 197 B (**384 MiB**, `gzip -t` OK), sha256
  `bca709a275c1c23c0b7bed3789e63be1ab04f19b0401b5ec3cc5f53edca5e112`.
- Referencia Ubuntu (`~/gpu-work/ramaa/s22/rootfs.img.gz`): 369 822 577 B (353 MiB).
  El nuestro es un **9 % mayor** con 1,2 GB de contenido útil (vs Ubuntu ~similar):
  transporte equivalente por el mismo canal `wget|zcat|dd`.
- Clave operador: `uke-arch-root` (privada, fuera de la imagen) + `uke-arch-root.pub`
  (= `/root/.ssh/authorized_keys` dentro).
