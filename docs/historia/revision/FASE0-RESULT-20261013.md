# FASE 0 — Resultados (13-oct-2026, tablet viva L25-diag, kernel 7.2.0-rc2-palawan #2)

Sesión SSH como root a 192.168.42.129. Cero flashes, cero reinicios, cero escrituras fuera de /tmp y /root/diag2. dmesg completo del boot vivo guardado en la máquina local para trazabilidad (5649 líneas).

## 0.1 — La GPU real: VEREDICTO = HARDWARE (freedreno FD735), no llvmpipe

- `eglinfo -B`: en plataformas GBM, surfaceless y device, renderer **`FD735` (freedreno)**, OpenGL ES 3.2 / GL 4.6, Mesa 26.2.4. La palabra `llvmpipe` **no aparece en ninguna plataforma**. Wayland/X11 fallan en `eglInitialize` (esperable: sin outputs, ver 0.2).
- `/dev/dri`: `card0` (adreno/KGSL_3d0), `card1` (msm DPU, `msm-kms 1.13.0`), **`renderD128` presente**.
- GMU viva: `Loaded GMU firmware v4.5.1` (gen71100_sqe/gmu/zap a t=9.14 s), OPP table OK, HFI/resume periódicos en dmesg. `vulkan-freedreno` instalado + ICD `/usr/share/vulkan/icd.d/freedreno_icd.json` (turnip presente; sin `vulkan-tools`, sin probar).
- **Número**: contexto EGL ES3 real sobre la GPU (GBM/renderD128 y surfaceless), 100 frames de clear fullscreen a **3200×2136 + readback con verificación de píxel** (píxel leído `634cccff` = color exacto pedido): **0.09 s → 1066 FPS → 29.1 GB/s de fill**. Cero faults/hangs de `a6xx`/adreno en dmesg tras la prueba. `LIBGL_ALWAYS_SOFTWARE`/`GALLIUM_DRIVER` vacías.
- Nota metodológica: un loop de `glClear`+`swap` sin readback da ~150k "FPS" (mide overhead de API, la GPU ni se entera). Los demos `es2gears_wayland`/`eglgears_wayland`/`vkgears` hacen SIGSEGV al arrancar — causa identificada: conectan al compositor pero **no hay ningún `wl_output`** (ver 0.2), no un cuelgue de GPU (cero trazas de fault tras los crashes).

## 0.2 — Hyprland: YA ESTÁ CORRIENDO (el problema no es el backend headless)

- Hallazgo principal: **Hyprland 0.56.2 corre desde el arranque** (PID 795, usuario sddm, vía sddm-greeter, `Hyprland --config /usr/share/sddm/hyprland.lua`). `hyprctl version` responde; socket en `/run/user/962/hypr/…`, `wayland-1` existe.
- Su propio log dice: backend **DRM sobre `/dev/dri/card1` (msm-kms)**, atomic modesetting, 2 CRTCs, GBM allocator, y renderer **`freedreno FD735 / OpenGL ES 3.2` sobre `renderD128`**. Aquamarine trae backends **DRM + Wayland** (símbolos `CDRMBackend`/`CWaylandBackend`; el fallback Wayland falla como es esperado sin compositor padre).
- Pero: conector `DSI-1` en estado 2 (disconnected, por `:d`) → **cero monitores** → `grim` falla con `no wl_output`, `hyprctl clients` = `no open windows`. El criterio de éxito de la FASE 0 ("hyprctl responde y hay imagen") queda en **1 de 2**: el compositor vive y renderiza en GPU, pero **mientras `:d` fuerce el conector no puede haber imagen por DRM**. Weston no hace falta para nada de esto (coste reportado de todos modos: 1.37 MB descarga / 8.8 MB instalado; `pacman -Si` responde, no se instaló nada).
- Conclusión: 0.2 no está bloqueado por falta de backend headless sino **por el propio `:d`**. Quitar `:d` = monitores de vuelta = Hyprland con salida real (y vuelta al riesgo de muerte del bind, que es la FASE 1).

## 0.3 — Disco: estrecho pero ampliable sin flash

- `/` (sda32): **4.0 GB, 3.5 GB usados, 258 MB libres (94%)**. 510 paquetes. Caché pacman 12 KB (limpia). Journal **113 MB** (recuperable con `SystemMaxUse=`).
- `/usr`: lib 1.4 GB + share 1.1 GB + bin 392 MB.
- La partición sda32 mide **~106 GB** (`/proc/partitions`: 110993388 bloques de 1K) con el fs en 4 GB. `resize2fs` y `e2fsck` **existen** (`/usr/bin`). Crecer el fs montado es operación online segura (previo e2fsck, ver 0.5). Margen >1 GB conseguible hoy: journal (~100 MB) + resize a 8–10 GB (minutos, sin flash).

## 0.4 — Memoria: sin riesgo de OOM para un compositor

- `MemTotal 1.6 GB` (cmdline `mem=2048M`, resto reservado), `MemAvailable ~1.0 GB`, **sin swap**, sin OOM en dmesg. Hyprland+sddm-greeter ya consumen ~230 MB y el sistema va sobrado (`load 0.05`).
- Sin ficheros de límite de memoria (cmdline lleva `cgroup.memory=nokmem,nosocket`: el controlador de memoria está desactivado a propósito). Un compositor + apps ligeras cabe; un escritorio pesado con navegador, no.

## 0.5 — FS: errores EXT4 reales, e2fsck pendiente (en frío)

- `dmesg` del boot: `EXT4-fs error … ext4_mb_generate_buddy: group 26/19/18/15/14, block bitmap and bg descriptor inconsistent` (descuadres de clusters libres, el grupo 14 el peor: 28028 vs 29040). No son "doubly allocated" sino **inconsistencias bitmap↔descriptor**, típicas de apagones bruscos (muertes del SoC sin sync).
- `/root/diag/` contiene solo una captura vieja de initramfs (dmesg.0.txt de 400 líneas, hasta t≈6 s, también con `:d`). `/root/diag2/` no existía; creado con la prueba de `grim` (vacío: sin outputs no hay captura posible).
- No se puede e2fsck la raíz montada en un sistema vivo: queda como **prerrequisito antes de cualquier resize2fs** (arranque en frío o desde initramfs).

## 0.6 — La contradicción de `:d`: RESUELTA (el agente concluded se equivocó de sitio)

**Hipótesis concreta**: `video=DSI-1:d` no es causalmente inerte. Se consume en `drm_connector_init()` (`drm_connector.c:295` → `drm_connector_get_cmdline_mode`), es decir, **en el momento de creación del conector**, y el conector DSI-1 de msm se crea **dentro del bind**, en la cadena `dpu_kms_hw_init → _dpu_kms_initialize_dsi → msm_dsi_modeset_init → msm_dsi_manager_connector_init → drm_bridge_connector_init`. Traza del boot vivo:

| t (s) | evento |
|---|---|
| 0.48 | panel `o82-dualdsi` probe OK + attach OK (hay modos desde este instante) |
| 0.48–3.95 | display-controller retenido por el gate X9WAVE/probe-hold (tries en 0.48, 3.597, 3.958) |
| 3.958704 | `couldn't set disp_cc_mdss_vsync_clk … (-22)` (set_rate rechazado, pre-bind) |
| 3.959154/66 | `bound ae94000.dsi` + `bound ae96000.dsi` |
| 3.960245 | `dpu_kms_hw_init` (hw rev 0xa0010000) |
| **3.960546** | **`[drm] forcing DSI-1 connector off`** ← `:d` aplicado AQUÍ, mid-bind |
| 3.963565 | `Initialized msm-kms 1.13.0` |
| 3.963656/724 | `Cannot find any crtc or sizes` ×2 → sin commit → **vive** |

- El "0,4 ms después del punto de muerte" es aritmética sobre un punto de muerte mal situado: la muerte sin `:d` no está en el bind (3.96) sino en el **commit del modeset inicial (~4.0 s)**, que ocurre DESPUÉS. `:d` llega ~40 ms antes y lo vacía.
- Mecanismo verificado en código (`drm_client_modeset.c:686`): con `force == DRM_FORCE_OFF` el commit salta el conector (`disabled by user, skipping`); y en el probe previo, el conector forzado queda `disconnected` sin modoset → `__drm_fb_helper_find_sizes` devuelve `-EAGAIN` (los dos `Cannot find any crtc`) → **no hay atomic commit → el DPU nunca se enciende → no hay escritura asesina de clocks → sobrevive**.
- Sin `:d`, el commit SÍ tendría con qué trabajar: el panel hace probe OK a 0.48 s y su `o82_get_modes()` (`panel-xiaomi-o82-dualdsi.c:482`) **devuelve 1–2 modos (3200×2136 @120/144) incondicionalmente, sin comprobar `prepare()`**. Conector conectado + modos → `find_sizes` OK → commit → enable del DPU/DSI → el `set_rate`/glitch del SRC con `parked_cfg=0` → muerte a ~4 s. El 7/7 empírico es determinista, no suerte.
- Corolario para FASE 1: el `vsync_clk … (-22)` de 3.958704 y el `disp_cc_mdss_mdp_clk_src: rcg didn't update` de 0.31 son las huellas visibles de la hipótesis del SRC en el boot vivo; el plan de sembrar el SRC desde código (ciclo 1a) ataca exactamente el commit que `:d` hoy evita.

**Limitación honesta**: no existe dmesg guardado de un boot muerto sin `:d` con el que comparar línea a línea (el `/root/diag/dmesg.0.txt` es initramfs con `:d`). La hipótesis se sostiene en traza+ código del camino vivo, no en diferencial vivo/muerto.
