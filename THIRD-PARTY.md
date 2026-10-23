# Trabajos de terceros

Este repo es mayoritariamente trabajo propio, pero incluye ficheros que vienen de
otros proyectos. Esos **conservan su licencia original** y no se re-licencian con la
del proyecto. Esta tabla es la referencia; si un fichero no aparece aquí y lleva
cabecera `SPDX-License-Identifier`, esa cabecera manda.

| Qué | De dónde | Licencia | Dónde está |
|---|---|---|---|
| **Kernel en uso: árbol «senemos»** | [MCC45TR/senemos-uke-kernel-mainline](https://github.com/MCC45TR/senemos-uke-kernel-mainline) @ `43e4036e` (Linux 7.2.9 + 78 parches, display DPU/DSI nativo para el panel o82) | **MIT** (empaquetado y scripts) / **GPL-2.0-only** (los ficheros C derivados del kernel, que llevan su propio SPDX) | Base del kernel desde el 17-oct. Sus fuentes **no** se versionan aquí; los parches propios del proyecto, sí (`build/gates/senemos/patches/`, `build/rootfs/deploy/camaras/patches/`, `build/rootfs/deploy/audio/kernel/`) |
| Linux kernel del linaje **histórico** «palawan» (fuentes y parches) | [palawan-mainline/linux](https://codeberg.org/palawan-mainline/linux), rama `palawan/v7.2-rc2` | **GPL-2.0-only** | `build/gates/patches/`, `build/gates/patches/k47-fuentes/`, `build/gates/patches/k52L33-fuentes/`, `build/gates/patches/k52L39-fuentes/`, `build/rootfs/deploy/audio/kernel/`, `build/rootfs/deploy/bt/`, `build/rootfs/deploy/camaras/patches/`, `build/rootfs/deploy/tapa/` |
| Configuraciones de kernel (`.config`) | cada build del proyecto | GPL-2.0-only (siguen al kernel) | `build/kernel-config/` |
| Topologías de audio AudioReach | [linux-msm/audioreach-topology](https://github.com/linux-msm/audioreach-topology), commit `35e482d` | **BSD-3-Clause** (© 2021-2024 Linaro Ltd) | `build/rootfs/deploy/audio/topology/src/` (texto de `UPSTREAM.txt`, sha256 en `UPSTREAM.sha256`, licencia en `LICENSE.BSD-3-Clause`) |
| Módulos de topología derivados de AudioReach | ídem, modificados | **BSD-3-Clause** (conservan el aviso de Linaro) | `build/rootfs/deploy/audio/topology/uke/` |
| Megapixels 1.8.3 (parches) | [megapixels-org/Megapixels](https://gitlab.com/megapixels-org/Megapixels), tag `1.8.3` | **GPL-3.0-or-later** | `build/rootfs/deploy/camaras/megapixels/000{1..7}-*.patch` (cabecera SPDX en cada parche) |
| Plugin de teclado en pantalla | [alertxsto/omarchy-touch-mode](https://github.com/alertxsto/omarchy-touch-mode) (id `omarkyy.tablet` 1.0.0) | **MIT** | `build/rootfs/deploy/touch-mode/fork/`, `build/rootfs/deploy/touch-mode/upstream/`, `build/rootfs/deploy/touch-mode/backup-previo/osk-fork-20261018/` |
| Lista de frecuencias del español | [hermitdave/FrequencyWords](https://github.com/hermitdave/FrequencyWords), OpenSubtitles 2018 | **CC-BY-SA-4.0** (© Hermit Dave) | `build/rootfs/deploy/touch-mode/fork/dict/es.txt` (atribución en `dict/README`, texto legal en `dict/LICENSE-CC-BY-SA-4.0.txt`) |
| Parches propios sobre el árbol «senemos» (`0045`, `0046`, `0001` del ABL) | de este proyecto, sobre ficheros GPL-2.0-only del upstream | **GPL-2.0-only** | `build/gates/senemos/patches/`, `build/rootfs/deploy/camaras/patches/` |
| Derivados de Omarchy (ficheros de shell, QML de la barra y el lanzador) | [omarchy](https://omarchy.org) (`edge/aarch64`) | **MIT** | `build/rootfs/deploy/omarchy/files/`, `build/rootfs/deploy/escritorio-tactil/uke.launcher/`, `build/rootfs/deploy/tablet-t5/` |
| Paquetes de Arch Linux ARM del rootfs | Arch Linux ARM | **variada** (GPL-2.0/3.0, LGPL, MIT…) | no se publican; sus textos de licencia van en `/usr/share/licenses` de la imagen |
| Plugin Navidrome para la barra | [backmeupplz/omarchy-navidrome](https://github.com/backmeupplz/omarchy-navidrome) 0.2.1 | **MIT** | `build/rootfs/deploy/resto-apps/uke.navidrome/` |
| XML de protocolos Wayland | upstream de Wayland / wlroots | **MIT** | `build/rootfs/deploy/touch-mode/*/virtual-keyboard-unstable-v1.xml`, `input-method-unstable-v2.xml` |
| Driver del táctil Novatek NT36xxx | reimplementación propia sobre el driver *in-tree* del kernel | **GPL-2.0-or-later** | `build/gates/prepara/novatek/`, `build/rootfs/deploy/lapiz/` |

## Licencia de este repo

El trabajo propio del proyecto está bajo **GPL-2.0-or-later** (`LICENSE`), por
compatibilidad con el kernel, del que derivan buena parte de los parches. Los
ficheros de la tabla de arriba conservan su licencia y **no** se re-licencian.

Una consecuencia práctica, y un matiz que conviene no saltarse: hay ficheros
**GPL-2.0-only** (los derivados del kernel: `uke-abl.c`, `arm-smmu-qcom.c`,
`qcom-rpmh-regulator-uke.c`…) y otros **GPL-3.0-or-later** (los parches de
Megapixels). La GPL-2.0-only **no** puede relicenciarse a la v3, así que quien
redistribuya **el conjunto** debe hacerlo bajo la GPL-2.0 (la v3 no cubre lo
GPL-2.0-only) y tratar los ficheros GPL-3.0-or-later como una agregación
separada, cada uno con su licencia. La forma correcta de cumplirlo es publicar
**el conjunto** bajo GPL-2.0-or-later y **declarar fichero por fichero** las
excepciones, que es lo que hace esta tabla.

## Qué NO está aquí

Ni firmware, ni ACDB, ni `.fsm`, ni módulos `.ko`, ni imágenes de partición, ni
volcados de `vendor`/`odm` de Android. Son material del fabricante y no se
redistribuyen: los scripts los citan por **sha256** y su origen. Ver la sección
«Qué NO hay» del [README](README.md).

## Procedencia de lo que es dato y no código

Algunos valores del aparato (secuencias de registro, timings, calibraciones) se
transcribieron del driver del fabricante o de volcados de Android. Son **datos
funcionales**, no código del fabricante, y el código que los usa es propio: está
documentado en las cabeceras de cada fichero. Los ficheros de origen no se
versionan.
