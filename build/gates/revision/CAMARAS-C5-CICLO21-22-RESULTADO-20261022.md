# C5b ciclos 21–22 — el foco como V4L2 y camss listo para libcamera (22-oct-2026 03:33–03:36; orden del dueño «V4L2 del foco y libcamera/softISP, solo insmod/rmmod»)
Solo insmod/rmmod; 0 faults SMMU/oops; 0 módulos y ningún proceso al final de cada ciclo; batería 100 %.

## Piezas nuevas
- **`uke_dw9714.ko`** (`vcm/gen-dw9714.py`): el `dw9714.c` de mainline (no compilado en ouke5) + compatible `uke,cn3927v` + riel opcional `vio` (l20, pull-ups del CCI) encendido con `vcc` (l14). Protocolo idéntico al que validó `uke_vcm` en los ciclos 18–20 (`[D9..D4] [D3..D0|S]`).
- **`uke_cam_lens.ko`** (`vcm/uke-cam-lens.dtso`): `lens@c` (`uke,cn3927v`, `vcc-supply = &pmxr2230_l14`, `vio-supply = &pmxr2230_l20`) y `lens-focus = <&uke_rear_vcm>` en `camera@10`. Se aplica **antes** de cargar `uke_ov13b10`. Sustituye a `uke_cam_vcm`/`uke_vcm` (no cargar ambos).
- **camss como `qcom-camss`** (`gen-modules.py`, `UKE_CAMSS_NAME=qcom-camss`; `out-ciclo22/`): el pipeline `simple` de libcamera reconoce el media device por el nombre del driver. El `qcom-camss.ko` del árbol no casa con `qcom,cliffs-camss` y no se carga.
- **`mtopo.py`**: `MEDIA_IOC_G_TOPOLOGY` sin dependencias; lista los enlaces AUXILIARES (sensor→lente), que `media-ctl -p` no muestra porque no tienen pads.

## Medido
- Ciclo 21 (`out/c5-ciclo21-20261022-0333.txt`): `dw9714 7-000c` ligado; entidad **`dw9714 7-000c`, tipo V4L2 subdev, subtipo Lens, `/dev/v4l-subdev28`**, control **`focus_absolute` 0..1023**; ráfaga ×4 en foco 416. La escena estaba a oscuras (media8 16,8 con ganancia máxima): el AF de este ciclo no es significativo (el AF ya se validó en los ciclos 19–20 con luz).
- Ciclo 22 (`out/c5-ciclo22-20261022-0335.txt`): `media0: driver qcom-camss model Qualcomm Camera Subsystem`; `mtopo.py`: **`AUXILIAR: ov13b10 7-0010 -> dw9714 7-000c`**, 46 entidades, 175 enlaces, 1 auxiliar, lentes `['dw9714 7-000c']`. La AE/AF de este ciclo no corrió (fallo de mi script: la sustitución que añadía `mtopo.py` a la lista de subida también cambió la variable `AF`; corregido en `c5-ciclo22.sh`).

## libcamera (sin hacer: necesita `pacman`, orden del dueño)
En la tablet **no hay libcamera** (ni `cam`, ni la librería, ni plugins). En la base de `extra` (aarch64, leída con `bsdtar` sin ejecutar pacman) están `libcamera 0.7.2-4`, `libcamera-ipa`, `libcamera-tools`, `gst-plugin-libcamera` y `pipewire-libcamera 1:1.6.9-1`; las dependencias principales (`libyaml`, `gnutls`, `libevent`, `libtiff`, `libunwind`, `elfutils`, `gstreamer`, `pipewire`) ya están instaladas. Ninguno figura en `uke-hold.conf`. Propuesta: `pacman -S --needed libcamera libcamera-ipa libcamera-tools gst-plugin-libcamera pipewire-libcamera` y un ciclo 23 de insmod con `cam -l` / `cam -c1 --capture` (softISP) y prueba en una app (PipeWire/GStreamer).
