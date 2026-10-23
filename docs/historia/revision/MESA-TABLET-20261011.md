# MESA-TABLET-20261011 — Instalación de mesa/libdrm/eglinfo en la tablet (Xiaomi Pad 7, rootfs k521)

Fecha: 2026-10-11. Vía: SSH root@192.168.42.129 (`build/gates/uke-ssh.sh`), paquetes bajados en el PC
desde http://nj.us.mirror.archlinuxarm.org/aarch64/{core,extra}/ y subidos por scp a /tmp/.

## Qué se instaló (pacman -U --noconfirm --disable-sandbox --needed --overwrite "*")

Estado inicial: 9+ paquetes en /tmp de la tablet, 15 ROTOS (misma página HTML 404 con sha256
idéntico `c375e42b…`): bzip2, dbus, expat, gcc-libs, glibc, krb5, libedit, libelf, libnl, libxml2,
ncurses, systemd-libs, util-linux-libs, xz + zlib. Los 15 se re-bajaron del mirror en el PC,
verificados con `file | grep XZ` y sha256 bit a bit contra la tablet antes de instalar.

Pacman exigió además actualizar paquetes del sistema para casar versiones exactas
("breaks dependency systemd-libs=261.2 required by systemd", etc.):
- core: systemd-262-1, systemd-libs-262-1, systemd-resolvconf-262-1, systemd-sysvcompat-262-1, util-linux-2.42.4-1, util-linux-libs-2.42.4-1, lzo-2.10-5
- extra (35 paquetes nuevos): cairo, default-cursors, fontconfig, freetype2, fribidi, graphite, harfbuzz, libdatrie, libdecor, libdisplay-info, libpng, libthai, libx11, libxau, libxcb, libxdmcp, libxext, libxfixes, libxft, libxkbcommon, libxkbcommon-x11, libxrender, libxshmfence, libxxf86vm, lm_sensors, pango, pixman, spirv-tools, vulkan-icd-loader, vulkan-mesa-implicit-layers, xcb-proto, xcb-util-keysyms, xkeyboard-config, xorgproto
- Los 40+34 .pkg.tar.xz se verificaron con `file`+sha256; ADEMÁS con `xz -t` (descubrió que
  xz-5.8.4-1 estaba TRUNCADO pese a pasar el check `file`; re-bajado y re-subido).

Dos obstáculos resueltos:
1. Conflictos de ficheros huérfanos (249 ficheros "exists in filesystem" de libelf/libxml2/systemd/
   systemd-libs/util-linux/xz — drift de la imagen k521): resuelto con `--overwrite "*"`.
2. xz-5.8.4 truncado: "Truncated tar archive detected" al extraer → re-descarga.

## Resultado

- `pacman -Q mesa mesa-utils libdrm` → **mesa 1:26.2.4-1, mesa-utils 9.0.0-7, libdrm 2.4.134-1**
  (además vulkan-freedreno 1:26.2.4-1). Total paquetes: 165 → 211.
- Espacio libre en / : 2.6 GB → **2.3 GB** (41% usado, /dev/sda32 4.0G).
- `timeout 30 eglinfo -B` → **exit 0, corre**. Resultado:
  - GBM platform y Surfaceless platform: **funcionan**, EGL 1.5, vendor "Mesa Project",
    renderer **llvmpipe (LLVM 23.1.1, 128 bits)** — software, OpenGL 4.6 / GLES 3.2.
  - **Vendor NO es freedreno**: el driver hw rechaza la GPU:
    `MESA: error: fd_pipe_new2:49: unsupported GPU id 0x0 / chip id 0xffff43030b00`
    (Adreno 735 chipid 0x43030b00 llega con prefijo 0xffff que la mesa 26.2.4 de Arch ARM
    no acepta en su tabla de dispositivos; cae a llvmpipe).
  - Wayland platform: `eglInitialize failed` (no hay compositor wayland corriendo — esperado en rootfs mínimo).
  - X11 platform: `eglInitialize failed` (no hay servidor X corriendo — esperado).

Conclusión: objetivo mínimo cumplido (mesa+libdrm+mesa-utils instalados y eglinfo -B operativa con
renderizado por software). El path acelerado freedreno queda bloqueado por el chip id no soportado
en la tabla de mesa (posible pata: parchear la tabla fd_dev_id de mesa o revisar qué reporta el
kernel en MSM_IOCTL/param GPU_ID — el 0xffff superior sugiere lectura parcial del chip id).
