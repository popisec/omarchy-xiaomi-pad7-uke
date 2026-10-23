# PRE-RENDER — inventario userspace + estado drm (L10, HFI caído)

Fecha: 2026-10-10 ~05:45 CEST. Tablet VIVA por SSH (192.168.42.129, L10+s250).
**card0 NO abierto en este turno**: solo `ls/stat`, sysfs, dmesg, `command -v`, `pacman -Q`.
Nada de lo aquí listado ejecutó `vulkaninfo/kmscube/modetest` (todos ABREN card0 → cuelgue hasta L11).

## 1. Mesa/freedreno en el rootfs: NO HAY

- `pacman -Q | grep -i mesa/vulkan/libgl/egl/freedreno/kms/drm` → **sin coincidencias** (165 pkgs, solo base ALARM).
- `/usr/lib/dri/` → no existe. `/usr/share/vulkan/`, `/etc/vulkan/icd.d/` → no existen.
- `/usr/lib/libEGL* libGL* libGLES* libvulkan* libdrm*` → no existen.
- `ldconfig -p | grep EGL|GL|vulkan|drm` → solo glib/qrtr/qmi (falsos positivos del grep).
- `PACKAGES-OVERLAY.txt` local tampoco contiene mesa/vulkan/libdrm (base + utilidades, sin GL).
- Firmwares GPU SÍ presentes: `/lib/firmware/qcom/gen71100_{gmu.bin,sqe.fw,zap.mbn}` + `palawan/` + `uke/gen71100_zap.mbn`.

## 2. Herramientas de render: NINGUNA instalada

`kmscube, vulkaninfo, vkcube, glmark2, glmark2-es2, modetest, kmsprint, drm_info, es2_info, glxinfo, eglinfo, clinfo` → **todas MISSING** (`command -v`, sin ejecutar).

Agravante: la tablet **no tiene red** (`ping 8.8.8.8` → Network is unreachable), así que
`pacman -S` en el dispositivo es imposible. Hay que descargar en el host e instalar por scp:
`pacman -U` de ArchLinuxARM-aarch64: **mesa, vulkan-freedreno, libdrm, vulkan-tools, mesa-utils**
(modetest viene en libdrm; es2_info/eglinfo en mesa-utils; vulkaninfo en vulkan-tools).
`kmscube`/`glmark2` opcionales (ver §4: sin conector KMS no sirven de primer render).

## 3. Estado /dev/dri + sysfs drm (solo lectura)

- `/dev/dri/`: `card0` (226,0, `root:video` 660) + `renderD128` (226,128, `root:render` 666) + `by-path/`.
- `card0` → `../../devices/platform/soc/3d00000.qcom,kgsl-3d0`: **nodo GPU, no display**.
- `/sys/class/drm/`: solo `card0`, `renderD128`, `version` (drm 1.1.0). **Cero `card0-*`: sin conectores KMS**
  (DPU/DSI no bindeados en drm — coherente con GPU OFF por diseño, `s3_stage=3 rescue=1 probe_hold=5000`).
- `debugfs dri/0/name`: `msm dev=3d00000.qcom,kgsl-3d0`. Tabla `clients` vacía. Sin `msm_drm_bind` en `/sys/bus/platform/drivers/`.
- dmesg boot: `adreno_bind` OK (K42), LLC slices `-ENODEV`, reguladores dummy, `GMU OPP table OK: 2 opps`,
  pokes G6→G7-gmuinit→G8-preRSCC. **Ninguna línea de HFI arriba / FW_INIT_RESULT**: HFI sigue caído (L10 confirmado).

## 4. Comando exacto de primer render (para cuando L11 dé HFI)

Restricción clave: **no hay conectores KMS** → `kmscube` y `modetest` NO pueden ser el primer render
(necesitan un CRTC+conector; aquí no existen). El primer render debe ir por **renderD128** (off-screen,
sin drm-master sobre card0). Tras instalar los pkgs del §2:

```sh
# Paso 1 — enumeración por el render-node (prueba HFI/GMU/fw sin modeset ni master sobre card0):
vulkaninfo --summary
# OK esperado: GPU freedreno (Turnip) listada con sus queues/firmwares cargados.

# Paso 2 — píxeles reales off-screen (cuando el paso 1 liste el device):
glmark2-es2 --off-screen -b build:duration=5
# (confirmar flags con `glmark2-es2 --help` en el dispositivo; alternativa: eglinfo/es2_info
#  surfaceless solo como chequeo de contexto EGL, no como prueba de render)
```

Orden de operaciones L11: (1) flashear L11 (poll VENDOR bit8); (2) dmesg → HFI arriba;
(3) scp + `pacman -U` de los 5 pkgs; (4) `vulkaninfo --summary`; (5) `glmark2-es2 --off-screen`.
Si el paso 1 falla con HFI arriba → el problema es ICD/kernel (revisar `/usr/share/vulkan/icd.d/` + `dmesg | grep tu/freedreno`), no el display.
