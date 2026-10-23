# OMARCHY-SENEMOS — escritorio Omarchy + GPU sobre el kernel MCC45TR y nuestro rootfs (preparación, sin tablet)

> 17-oct-2026, noche. **Solo PC**: sin adb/fastboot/ssh, sin flash, sin ledger, sin commit; el kernel no se tocó (otro agente
> hace la v2). `/tmp/claude-1000/ext-senemos` solo leído; no se ejecutó nada suyo. Todo lo escrito está en
> `build/rootfs/deploy/omarchy/` y en este fichero. Complementa `PIPELINE-PANEL-20261014/DESKTOP-OMARCHY-REVISION.md`
> (cadena de sesión), `docs/guias/RE-NOCTURNO-HALLAZGOS-20261017.md §3.8` (Omarchy offline) y `docs/historia/revision/ADOPCION-SENEMOS-20261017.md`.

## 0. Veredicto

- **Cierre de dependencias: completo.** Para `omarchy + hyprland + quickshell + sddm + mesa(freedreno) + fuentes` el stage
  (`build/stage-escritorio`, 473 pkgs) + la base del rootfs lo cierran **sin un solo paquete sin proveedor**, 0 deps rotas,
  0 conflictos, 0 downgrades, orden topológico sin violaciones y **9 169 enlaces ELF `NEEDED` resueltos** (solo 17 sonames de
  plugins opcionales —Qt5 de `sddm-greeter` Qt5, SDL2, mariadb…— sin proveedor, ninguno en la ruta de Hyprland/quickshell/greeter Qt6).
- **Se instalan 342 paquetes** (222 de cierre estricto + 120 «extras de Omarchy» que lanza la sesión: foot, kitty, hyprlock, hypridle,
  waybar, grim, slurp, upower…): 503 MiB comprimidos, 1 923 MiB instalados, **≈1 787 MiB netos**. De 5,67 GiB libres quedan ≈3,7 GiB.
- **Hallazgo que cambia el método (§1): la DB de pacman del rootfs v8 no describe el disco.** 32 de esos paquetes ya están volcados
  en el disco sin registrar; `pacman -U` los rechazaría por «exists in filesystem». Las tandas afectadas llevan `--overwrite '*'`
  (acotado y medido); el resto, no.
- **GPU:** el firmware `gen71100_{gmu.bin,sqe.fw,zap.mbn}` **ya está en el rootfs** (sha verificado, ruta que el kernel pide);
  Mesa 26.2.4 del stage trae la tabla freedreno con el chip-id `0x43030b00`. El riesgo no es userspace: es el primer `open` de la GPU
  (§3, escalera swrast → hardware).
- **Nada se ha ejecutado contra la tablet.** Probado en el PC: manifiestos, sha256 de los 342 `.pkg`, `bash -n`, y los scripts remotos
  contra stubs/sandbox (`uke-setup.sh pre|post|undo`, `batch.sh` con sha corrupto/conflicto/overlay, `deploy.sh install` con un `ssh` falso).

## 1. Hallazgo: pacman no sabe lo que hay en disco (rootfs v8)

`build/rootfs/INFORME-A2.md §a.4` (27-sep): sobre la base ALARM (166 pkgs registrados) se superpusieron con `bsdtar -xpf` 44 pkgs nuevos
+ 47 actualizados **sin registrarlos** (scriptlets emulados a mano). La imagen `rootfs-uke-l76-8g.img` conserva ese estado:

| Medido (debugfs, solo lectura) | |
|---|---|
| Paquetes registrados | 165 (systemd **261.2**, openssh 10.4p1, sin `perl`/`git`/`polkit`/`networkmanager`) |
| Ficheros de nuestra selección ya en disco **sin dueño** | **7 131 en 32 paquetes** (perl 2 863, abseil-cpp 886, libwacom 851, git 650, networkmanager 173/182, libelf 49/148…); 5 fuera de `/usr` (NM.conf, pcscd, perlbin, slsh.rc: contenido = el del paquete) |
| `/usr/bin/sudo` y `su` | existen (setuid) pero sin paquete `sudo` registrado |
| `/home/alarm` | `root:root 0700` (el mismo fallo del 14-oct) → `setup-pre` lo corrige |

Consecuencias: (a) las dependencias se resuelven contra la DB (lo que pacman verá), no contra el disco; (b) esas 32 se instalan con
`--overwrite '*'` **solo en las tandas que las contienen** (`manifest/overlay-sin-dueno.tsv`); la medición exhaustiva de los 59 388 ficheros
garantiza que solo puede pisar los 7 131 ya medidos (0 solapes con ficheros de paquetes registrados, 0 duplicados entre paquetes); una
tanda sin overlay que choque **no** se fuerza (rc 20); (c) **los otros despliegues con `pacman -U` (carga, wifi) pueden toparse con lo mismo.**

## 2. Cierre de dependencias (reproducible: `tools/gen-manifest.py`, `tools/elf-check.py`)

Método (el de modetest, ahora script): `.PKGINFO` de cada `.pkg.tar.*` (bsdtar) + `desc` de la DB local de la imagen (debugfs); raíces =
omarchy, omarchy-settings, omarchy-keyring, hyprland, quickshell, sddm, mesa, uwsm, xdg-desktop-portal-hyprland, fuentes (noto, noto-emoji,
jetbrains-mono-nerd, nerd-symbols, inter), networkmanager, pipewire, wireplumber, gnome-keyring; `satisfies` con versiones, `provides` y sonames.

| | |
|---|---|
| tier1 (cierre estricto) | 222 pkgs, 1 487 MiB. Lo que la base ya satisface **no se reinstala**. Única subida de algo instalado: `libelf 0.195→0.196` (`elfutils` pide `libelf=0.196`; cadena `quickshell→cpptrace→libdwarf/elfutils`) |
| tier2 (extras de Omarchy) | 120 pkgs, 437 MiB (paridad con el escritorio de L57): **ninguno es dependencia de `omarchy`**, pero la sesión los lanza |
| tier3 (EXCLUIDO) | 48 subidas de base (systemd 261.2→262, openssh 10.4→10.6, openssl, curl, bash, coreutils, util-linux, pam…; `manifest/no-incluidos.tsv`). No hacen falta (la base satisface todas las deps) y subir systemd/openssh por SSH (`70-openssh-restart-sshd.hook`, `daemon-reexec`) es riesgo gratuito |
| 83 más | misma versión que la instalada: `--needed` las salta |
| Tandas | T1–T7 por lotes topológicos del stage (los ciclos `libglvnd↔mesa`, `gdk-pixbuf2↔glycin↔librsvg` quedan dentro de una tanda); `omarchy` va en T7 |

**Lo que falta de verdad (no está en el stage; NO descargado aquí — `manifest/opcionales.tsv` trae URL + sha256 de la DB de sync):**
`xdg-terminal-exec` (omarchy edge, 24 KB: **SUPER+Return lo llama** vía `omarchy-launch-terminal`; sin él no hay terminal por atajo),
`udiskie` (0,16 MB; línea de autostart que hoy falla en silencio), `mesa-utils` (`eglinfo`, 0,2 MB), `vulkan-freedreno` (Turnip, 1,8 MB) y
`vulkan-tools`, `wtype`, `pamixer`, `power-profiles-daemon` (`omarchy-powerprofiles-init`), `hyprsunset`, `fcitx5`. Sus deps ya están cubiertas.
La lista completa de Omarchy (`omarchy-base.packages`, 147 nombres: chromium, nautilus, mpv, btop…) **no** se cubre ni se pretende: 28 están.

## 3. GPU (Adreno 732 = gen7_11_0, chip-id `0x43030b00`)

**Firmware.** Su parche 0036 (`a6xx_catalog.c`): `gen71100_sqe.fw`, `gen71100_gmu.bin`, `.zapfw = "gen71100_zap.mbn"`. `adreno_request_fw()`
(en nuestro árbol `senemos-7.2.9`, `adreno_gpu.c:527`) prueba `qcom/<nombre>` y luego `<nombre>`; el nodo `zap-shader` del DT stock solo trae `memory-region`
(sin `firmware-name`), así que el zap sigue la misma ruta. **Todo está ya en `rootfs-uke-l76-8g.img`** (debugfs + sha256):

| Fichero | Rutas presentes en el rootfs | sha256 |
|---|---|---|
| `gen71100_gmu.bin` (80 680 B) | `/lib/firmware/` y `/lib/firmware/qcom/` | `435c7bac…bb864` |
| `gen71100_sqe.fw` (66 036 B) | ídem | `b6df660d…8c401` |
| `gen71100_zap.mbn` (12 088 B) | ídem + `qcom/uke/` + `qcom/palawan/` | `0c86e4ae…a8e6` |

Origen: `vendor_a:/firmware` de ESTA tablet (`build/pkg/uke-gpu-firmware`, `build/gates/lib/firmware/qcom`, `~/proyectos/ubuntu-uke/stock/firmware`); sqe y zap **no** son los
de `firmware-qualcomm-qrd8635` (el zap va firmado por dispositivo); el GMU es idéntico. `verify.sh` los comprueba por sha. Se piden en el primer `open` de la GPU, con el rootfs ya montado.

**Mesa.** `mesa-1:26.2.4-1` (stage) incluye `msm_dri.so`, `kms_swrast_dri.so`, `libgbm`, `libEGL_mesa` y en `libgallium-26.2.4` la tabla freedreno con
`FD730`, `FD735`, `FD740`… y el id `0x43030b00` (en la tabla entre los de A730 y A740). Es evidencia estática (strings + tabla), no de ejecución.
No trae Turnip (`vulkan-freedreno`, opcional): Hyprland (GLES2/EGL) y Qt Quick no lo necesitan.

**Requisitos para el kernel (escritos aquí; no se tocó nada).** Estado medido en `config-senemos-ouke1` y en el `.config` v2:

| # | Requisito | Estado |
|---|---|---|
| K1 | `gpucc-cliffs` tiene que cargarse (clock + GDSC CX/GX de la GPU, su parche 0036): módulos `7.2.9-senemos.1.4054.3-ouke2` instalados **+ `depmod`** (+ `kmod`/udev). `CONFIG_SM_GPUCC_CLIFFS=m`; en la v2 el `.ko` existe y su alias `of:N*T*Cqcom,cliffs-gpucc` casa con el DT | **depende de instalar los módulos**; alternativa `=y` |
| K2 | Mantener `msm.separate_gpu_kms=1` en la primera prueba: con `=0` el maestro DRM no enlaza hasta que **todos** los componentes (incl. adreno) hayan sondeado ⇒ la pantalla dependería de la GPU | cmdline actual ya lo trae |
| K3 | `DRM_MSM=y`, `QCOM_SCM=y`, `QCOM_MDT_LOADER=y`, `QCOM_AOSS_QMP=y`, `ARM_SMMU_QCOM=y`, ICC GFX3D (0037), `PM_DEVFREQ`+`DEVFREQ_GOV_SIMPLE_ONDEMAND`=y, `DRM_MSM_GPU_STATE=y`, `DRM_GPUVM=y`, `SYNC_FILE=y` | ya cumplidos |
| K4 | `CONFIG_ZRAM` (+`ZSMALLOC`) **no está**: sin swap; L57 (7,2 GiB) aguantó sin él y L58 añadió zram | recomendado, no bloqueante |
| K5 | cmdline: `systemd.unit=multi-user.target` ⇒ sddm no arranca solo. Se resuelve sin kernel con `BOOT_DESKTOP=1` (symlink en `multi-user.target.wants`) o cambiando el cmdline | informativo |
| K6 | Sin `mem=2048M` (D16) | ya cumplido; `setup-pre` aborta si lo ve |

**Riesgo principal: dos nodos DRM.** Con `separate_gpu_kms=1` hay KMS-only (card del panel) + GPU (renderD128). Cómo reparte Aquamarine render/KMS en ese caso **no está verificado**.
Por eso `uke-session gpu-mode` (`default` = sin variables, `swrast` = `LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe MESA_LOADER_DRIVER_OVERRIDE=kms_swrast`,
`split` = `AQ_DRM_DEVICES=<gpu>:<kms>` detectado por sysfs) y la **escalera**: 1) `swrast` + `start`: prueba panel + sddm + uwsm + Hyprland + quickshell **sin abrir la GPU**;
2) `default`: sobre freedreno. El primer `open` de la GPU es donde históricamente se colgó (eglinfo y modetest morían en el `load_gpu` del open, GMU/`kgsl-smmu`: `NOTAS-OMARCHY.md:1625` y `:1873-1883`); su kernel dice que renderiza (KWin), el nuestro aún no se ha medido.

## 4. El despliegue (`build/rootfs/deploy/omarchy/`)

```
deploy.sh            orquestador (PC). Todo lo que escribe en la tablet es DRY-RUN salvo --go
remote/batch.sh      tablet: sha256 → df-gate → pacman -U --needed [--overwrite *] → pacman -Qk → borra los .pkg   (setsid+nohup, estado en disco)
remote/uke-setup.sh  tablet: pre | post | undo | boot-desktop
remote/verify.sh     tablet, solo lectura: pre | post (exit = nº de fallos)
remote/session.sh    tablet: start stop status shot evidence gpu-mode perf   (instalado como /usr/local/sbin/uke-session)
files/               wrappers de RE-NOCTURNO §3.8 (verbatim, mismos sha256) + seal-migrations-uke.sh
manifest/            instalar.tsv (342 filas + sha256) · opcionales.tsv · overlay-sin-dueno.tsv · no-incluidos.tsv · resumen.txt · nombres.txt
tools/               gen-manifest.py (regenera el cierre) · elf-check.py (segunda opinión por ELF)
```

Pasos: `check` (PC) → `preflight` (lectura) → `all --go` = `setup-pre` → `install 1..7` → `setup-post` → `verify`. Clave y host como `build/gates/uke-ssh.sh`;
transporte `tar | ssh 'tar -x'` por tanda (≈70–120 MiB; solo se envía lo que la tablet no tiene ya a esa versión, así que los 16 de modetest de L76R se saltan).

**`setup-pre`**: gates (aarch64, MemTotal ≥6 GB, libres ≥2,8 GiB, sin `mem=2048M`), copia de `/etc` a `/var/backups/uke-omarchy/`, `pkg-antes.txt`,
hooks `90-mkinitcpio-install` y `60-mkinitcpio-remove` anulados con symlink a `/dev/null` en `/etc/pacman.d/hooks` (el kernel viaja en boot.img; `plymouth` instala
`usr/lib/initcpio/*` y dispararía `mkinitcpio -P` sobre un `/boot` vacío en cada tanda), `chown -R alarm` a su home, y comprobación de que `networkd` está activo y **NetworkManager no**.

**`setup-post`**: usuario `omarchy` (`useradd -m`, grupos wheel/video/render/input/audio) que **hereda `/etc/skel` de `omarchy-settings`** (hypr/*.lua, shell.json y las 106 semillas de migraciones);
`/etc/sddm.conf.d/20-uke-autologin.conf` = `[Autologin] User=omarchy Session=omarchy Relogin=false` (la receta de L57; sddm acepta el nombre sin `.desktop` y busca en
`/usr/local/share/wayland-sessions`, donde `omarchy-settings` **ya** trae `omarchy.desktop`: no hay que hacerlo a mano); el `sed` de upstream sobre `/etc/pam.d/sddm`;
wrappers en `/usr/local/bin` (precede a `/usr/bin`; en producción Omarchy no antepone `/usr/share/omarchy/bin`); `systemctl enable sddm`.
Nota: **L57 usó `alarm`** (home de alarm + `Session=omarchy`); `--user alarm` lo reproduce (copia `/etc/skel` sin pisar y sella migraciones).

**Migraciones offline (§3.8 aplicado a este caso).** `omarchy-migrate` solo corre al pulsar el aviso o en `omarchy update`; el primer fallo aborta la tanda y no deja marcador.
Sin red, ~25 de las 106 hacen `omarchy-pkg-add` (aborta) y `1781984677` (snapper) falla seguro: **se sellan las 106** (marcador = semántica upstream; un usuario nuevo ya nace así) y no se ejecuta ninguna.
Para cuando haya red (borrar el marcador y correr `omarchy-migrate`): `1781793381` udiskie, `1784568652` mask NM-wait-online, `1784914435` wifi powersave off;
**no** `1782002156` (habilita NM y retira networkd ⇒ cortaría el SSH por usb0) hasta que NM tenga perfil/`unmanaged` para usb0; `1788124236` (sshd hardening) solo verificando `authorized_keys`.
`omarchy-pkg-add` tolerante y `omarchy-update-restart` (kernel externo = boot.img) se instalan tal cual; `omarchy update` por NCM sigue el checklist de §3.8.

**Lo que NO hace, a propósito:** habilitar NetworkManager (compite con networkd por usb0 = el SSH; sin WiFi aún), tocar `pacman.conf`/DBs de sync/`omarchy refresh pacman`, subir la base,
`BOOT_DESKTOP` (por defecto sddm **no** arranca solo), dar sudo sin password (`--sudo-nopasswd` lo abre; el usuario no tiene password).

## 5. Riesgos

| Riesgo | Mitigación / estado |
|---|---|
| Espacio: 5,67 GiB libres (6,07 con la reserva de root); el fs es ext2-like sin journal | netos ≈1,79 GiB + tanda en tránsito ≤119 MiB; `df-gate` por tanda (rc 42, nada tocado); los `.pkg` se borran al terminar. Cortes de luz: sin journal ⇒ `e2fsck` |
| Corte NCM/USB a mitad de tanda | `setsid nohup`: pacman sigue; `deploy.sh status-batch N`; `--needed` reanuda |
| Conflictos de ficheros fuera del overlay medido | rc 20, no se pisa nada |
| Hooks de pacman | `quickshell-check.hook` (PostTransaction, solo avisa), `systemd-hwdb`/`fc-cache`/schemas (CPU, minutos); mkinitcpio anulado; el guard de Omarchy solo bloquea `-Syu` (se exporta `OMARCHY_ALLOW_DIRECT_PACMAN=1`) |
| `omarchy-settings` post_install sobrescribe `/etc/os-release` (ID=omarchy), `nsswitch.conf`, `faillock.conf`, `plymouthd.conf`, `/etc/skel/.bashrc` | revisado: ninguno afecta a sshd/networkd; `/etc` respaldado antes |
| GPU: colgado al primer open / dos nodos DRM | escalera swrast→hardware (§3); batería ≥3700 mV y `slot-retry-count` como en cualquier prueba |
| OOM | MemTotal ≥6 GB exigido; sin zram (K4); `uke-session perf on` apaga animaciones/blur/sombras |
| Deriva edge: `omarchy.db` (11-oct) trae `hyprland-0.56.2-5` y el stage `-4`; `omarchy-chromium` solo en edge | no se usa red; revalidar el día de un `omarchy update` |
| `scp` falla (medido el 17-oct) aunque la imagen trae `/usr/lib/ssh/sftp-server` y `Subsystem sftp` | no se investigó; `tar\|ssh` no depende de ello |

## 6. Prueba de aceptación (Hyprland visible en el panel)

1. PC: `deploy.sh check` verde; tablet: kernel v2 con módulos + `depmod`, SSH vivo, MemTotal ≈7,2 GiB, `deploy.sh preflight` sin fallos (firmware con sha OK).
2. `deploy.sh all --go` → `verify` sin FALLOS (binarios, `ldd` sin «not found», 342 pkgs registrados, `pacman -Qk` limpio, usuario, autologin, 106/106 migraciones, hooks anulados).
3. Escalón 1 (sin GPU): `gpu-mode swrast --go` + `start --go`. **PASA** = Hyprland y quickshell vivos en ≤90 s, `hyprctl monitors` con el panel (3200×2136 / 2136×3200), sin OOM, `status` limpio,
   `shot` no negro **y el dueño ve fondo + barra de Omarchy en el panel (foto)**. (`grim` no prueba el panel: el 14-oct hubo captura buena con panel negro.)
4. Escalón 2 (GPU): `stop`, `gpu-mode default`, `start`, `evidence`. **PASA** = `drm-driver: msm` con `drm-engine-gpu` creciendo en el fdinfo de Hyprland, `msm_dri`/`libgallium` mapeados y sin `kms_swrast`/`llvmpipe`
   en `hyprland.log`, `dmesg` con adreno/gmu y sin fault. Si falla: `gpu-mode split`, o volver a `swrast` y registrar el hallazgo.
5. Persistencia: `boot-desktop on --go` (o cmdline) + reinicio ⇒ lo mismo sin intervención. Rollback: `undo --go` (config) o reflash de la imagen (sha `7e4309f0…`).

## 7. Qué se verificó y qué no

Verificado en el PC: cierre y conflictos (342 pkgs; 59 388 ficheros contra DB y disco de la imagen), sha256 de los 342 `.pkg`, ELF `NEEDED`, `bash -n`, scripts remotos en sandbox con stubs (no hay `shellcheck`),
flujo `install` extremo a extremo con `ssh` falso, firmware por sha dentro de la imagen, tabla freedreno por strings, alias `of:…qcom,cliffs-gpucc` en el `modules.alias` v2.
**No verificado** (necesita la tablet): que el rootfs real coincida con la imagen (los 16 de modetest, ficheros nuevos sin dueño), tiempos y hooks reales, el primer `open` de la GPU, el reparto de Aquamarine con dos nodos,
el comportamiento de `pacman -Qk` y `--overwrite '*'` en pacman 7.1 de la tablet, y todo lo visual.
