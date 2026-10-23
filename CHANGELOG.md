# Changelog

El repo se publica **sin historial** (es una instantánea de un repo privado de
más de 1000 commits), así que este fichero es la cronología del port. Las
fechas son las de los informes citados, no las de los commits.

Formato: fechas en `AAAA-MM-DD`. «Cierre» = la fase queda verificada en la
tablet, no solo planeada.

## 2026-09

- **26-sep** — Primera auditoría del cuaderno de trabajo. Se escriben los
  informes de partida `A`–`G` (port a aarch64, arranque, Hyprland/Quickshell,
  capa tablet, paquetes del SoC) y el plan por fases `F` (F0–F8, 32 riesgos; las
  decisiones del dueño son D1–D20, 20 en total).
- **27-sep** — Se inicializa el repo privado. Empieza el trabajo con reglas
  estrictas: backup del par `boot`+`dtbo` y sha256 pre-registrado **antes** de
  cada flasheo, un cambio por ciclo, y lectura del `/dev/ttyACM0` con un único
  lector. Varias reglassale de pagar puntos de una sesión de la hermana
  `ubuntu-permanente` (ver `REGLAS.md`).
- **28-sep** — Se detecta el bloqueo nº1: el slot A no arranca imágenes nuevas.
- **29-sep** — Trabajo con el táctil y el lápiz (Novatek NT36532). Se prepara
  el camino del lápiz (`build/gates/prepara/novatek/`).
- **30-sep** — Primeras medidas del panel `o82`.

## 2026-10

- **05-oct** — **K49**: la build «dorada» del kernel (linaje palawan) (`boot-ukek49-esd-plyoff.img`,
  sha256 `6988dc7b…`, clang 23.1.1 / LLD 23.1.1) es la que arranca. Se documenta
  el análisis forense en `build/gates/BUILD-RECIPE-DORADA.md`.
- **06-oct** — Auditoría forense del build (banner, `setlocalversion`, por qué el
  `+` del release string).
- **08-oct** — Vías de GPU; se atacan el DPU, el DSI y el GMU.
- **12-oct** — Revisión del panel: DSI con DSC, doble enlace y comandos de IOPHY.
- **14-oct** — **Hito de luz**: backlight del panel (KTZ8866) y el escritorio de
  Omarchy en pie, pero **la imagen seguía en negro**. Informe en
  `build/gates/revision/PIPELINE-PANEL-20261014/`.
- **17-oct** — **Cambio de linaje de kernel y primera imagen del panel**: el
  port pasa del árbol «palawan» (propio) al de terceros
  [MCC45TR/senemos-uke-kernel-mainline](https://github.com/MCC45TR/senemos-uke-kernel-mainline)
  (Linux 7.2.9 + 78 parches, display DPU/DSI nativo), con los parches propios
  encima. Con ese árbol el panel **da imagen** (#658) y el USB/SSH funciona
  (#659). También **Bluetooth**: `hci0` + A2DP/AAC con el `hci_uart` parcheado,
  y la captura de referencia de Android para comparar.
- **17-oct ~23:2x** — **Primer arranque de Arch** con escritorio (Hyprland
  0.56 con Lua + Quickshell) y sesión de Omarchy, ya con imagen.
- **18-oct** — **Cierre de WiFi**: `wlan0` con ath11k (WCN6750 + WPSS), y el
  escritorio persistente tras el arranque.
- **19-oct** — Teclado en pantalla con predicción; captura por WiFi (SSID QR).
- **20-oct** — **Cierre del audio**: altavoces internos (FS19xx) y micrófono
  funcionando y persistentes desde el arranque; revisión crítica del audio.
  Carga rápida y perfil de batería; sensor de tapa.
- **21-oct** — **Cierre de las cámaras**: trasera **OV13B10** (13 MP) con
  autofocus por software (VCM `dw9714`) y frontal OV08D10, en Megapixels 1.8.3
  parcheado.
  La tablet queda con un oops de slab en el kernel (pendiente de reiniciar con
  alguien delante).
- **22-oct** — **Escritorio táctil**: teclado en pantalla con sugerencias y
  autocorrección en español (11/11 pruebas con toques reales), rotación
  automática, gestos, y `uke.launcher` en lugar de `nwg-drawer`.
  **Plugins de la shell** arreglados (recarga en caliente, widgets de Powerbar
  accesibles con el dedo, reloj mundial). Dictado offline con Parakeet v3 (WER
  2,4 %). Sesión de Qt 6.12 + `omarchy 4.0.6-1` (la 4.0.4 daba la pantalla en
  blanco por un bug de quickshell). Última sesión antes de publicar.

## 2026-10-23 — El kernel ya se reconstruye y se compila

- `build/gates/senemos/reproducir-arbol.sh` reconstruye el árbol del kernel desde el
  tarball oficial de kernel.org y el upstream público, con la firma verificada.
- `build/gates/senemos/deltas-senemos.sh` aplica los parches propios.
- `build/gates/senemos/build-ouke5.sh` compila: `olddefconfig` sin cambios y un `Image.gz`
  con el vermagic `7.2.9-senemos.1.4054.3-ouke5`, con el veredicto del ABL dentro.
- Se publica el trabajo nuevo del cuaderno: kernel v8, optimización de RAM, fsck+journal,
  los generadores del initramfs, el manifiesto de los 56 blobs de firmware y el descargador de
  los 342 paquetes de la capa de Omarchy.
- `ESTADO.md` nuevo (una página) y el material de trabajo a `docs/historia/`.
- `tools/publicar.sh`: el repo público se genera del cuaderno privado, anonimizado y verificado.

## 2026-10-22 — Publicación

- El cuaderno se publica como repo público (`popisec/omarchy-xiaomi-pad7-uke`):
  instantánea única, sin historial, con los datos de red y del aparato
  anonimizados, sin binarios del fabricante, y con CI que vigila que no entren
  secretos, blobs ni referencias rotas.

## Lo que sigue abierto

- Autofoco por software sin validar con una escena con detalle (medido: 946 y
  805 de diferencia en una pared lisa).
- El oops de slab de las cámaras (21-oct) y la estabilidad del kernel.
- La reproducibilidad del kernel: **pendiente**. (Al publicar esto, el árbol
  todavía no se podía reconstruir; se resolvió en la instantánea del 23-oct, con la receta de
  `build/gates/senemos/`.)
  (ver [`BUILD.md`](BUILD.md) §2).
- `nwg-drawer` desactivado a favor de `uke.launcher`: falta decidir si vuelve.
