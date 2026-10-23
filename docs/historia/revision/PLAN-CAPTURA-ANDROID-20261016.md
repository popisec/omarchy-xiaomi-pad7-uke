# PLAN — Captar cómo Android crea la imagen de la pantalla (16-oct-2026)

Objetivo: obtener la verdad del panel FUNCIONANDO (Android/HyperOS) para cerrar la brecha de
paridad que deja L74 (luz ON, vídeo fluyendo según MISR, DDIC en negro — sospecha: DDIC sordo
al LP / esc_clk, u otro hueco de configuración).

## Capa 0 — Lo que Android ya nos dio (sin root, adb shell shell@production)

- **Modo activo**: 2136×3200 @ 120 Hz (modeId 1), hasta 144 Hz (id 2); 7 modos
  [30..144 Hz]. `state ON`. Fabricante DDIC según dumpsys: `manufacturerPnpId=QCM, productId=1`.
  ⇒ Confirma que nuestro modo (grupo 0, 967 MHz, 120 Hz) es EL modo nativo del panel.
- **Confirmación de que el stack vendor funciona** con el mismo hardware que a nosotros nos da negro.

## Capa 1 — Intentada y denegada por SELinux/producción (documentado, no reintentar)

- `/dev/kmsg`, `/sys/fs/pstore/` → EACCES (shell NO lee kernel log).
- `/proc/device-tree/soc/*` (nodos display), `/sys/class/drm/card0-DSI-1/*` → EACCES.
- `logcat -b kernel` → buffer vacío (logd no espeja el kernel); HAL de display no loguea clocks.
- `su`/`adb root` → build de producción, sin root.

## Capa 2 — La verdad de CONFIGURACIÓN vive en el PC (sin tocar la tablet)

El kernel/DT que Android ejecuta YA lo tenemos localmente:

1. **DTB/DTBO stock** (`~/proyectos/ubuntu-uke/stock/`, dtbo ya decodificado por B1 para la
   variante 42_02_0b): falta minar →
   a. **Cadena del reloj escape** (candidato nº1 de L75): clocks del nodo dsi/phy y
      `assigned-clock-rates` — ¿de dónde sale la esc del vendor (¿byte/8?) y a qué rate.
   b. **Los 14 bytes de `qcom,mdss-dsi-panel-timings`** (+ variante `-8550` si existe) para
      1189,19 Mbps — byte-exactos contra los 6 deltas residuales del cálculo v4 (B4).
   c. **Bools ECC/CRC/deskew** del nodo del controlador (hueco de paridad señalado por INV §3).
2. **msm_drm.ko decompilado** (3.328 ficheros en `build/vendor-re/decomp/`): comportamiento del
   driver (ya minado en A3/INV), ahora para las rutas de esc_clk y de los bools del punto 1c.
3. **EL LOG DE ARRANQUE DEL KERNEL VENDOR**: en Android el dmesg está bloqueado PERO el mismo
   kernel+DT corren en `~/proyectos/ubuntu-uke/stock/` — su boot.img puede analizarse offline, y
   el proyecto tiene capturas históricas del kernel vendor (`ubuntu-uke/`, forklogs de rescate
   con `android-kmsg.txt` de 2 MB!). Re-minar esas capturas por líneas de display.

## Capa 3 — Root real (NO recomendado ahora)

Desbloquear el bootloader borra datos y rompe el esquema de slots A/B del proyecto. Solo si
todas las capas anteriores agotan la hipótesis.

## Consumo del plan

La Capa 2 alimenta el diseño de **L75** (kernel-side: esc_clk = byte/8 + tabla PHY vendor
verbatim; dtbo solo si las bools fueran necesarias). Dif de verdad vs nuestro L74 medido:
nuestro HS_TIMER/MISR/FLUSH ya en paridad; esc 19,2 vs 18,58 MHz (pendiente confirmar en DT);
6 deltas PHY (pendiente tabla vendor byte-exacta).
