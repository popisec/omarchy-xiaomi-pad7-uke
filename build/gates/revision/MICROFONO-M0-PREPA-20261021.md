# MICRÓFONO — etapa M0 (solo PC): preparación y propuesta de M1 (21-oct-2026)

Base: `MICROFONO-20261020.md` (micros ANALÓGICOS AMIC en el WCD9395 por SoundWire TX; sin DMIC). La tablet NO se ha tocado (lectura de ficheros del PC únicamente).

## Hecho (todo en `build/rootfs/deploy/audio/`)
| Pieza | Fichero | Estado |
|---|---|---|
| Overlay de tarjeta combinada | `dts/uke-audio-e9a-card-fs19xx-wcd-capture.dtso` | compila (dtc sin avisos); se aplica con `fdtoverlay` sobre el DT vivo en cadena **e2d → e3 → e5-codec → e9a**; `model = "UKE"` con `tdm-playback-dai-link` (como e8b) y `wcd-capture-dai-link` (cpu `TX_CODEC_DMA_TX_3` = DAI 120; codec = `uke_wcd939x 1` + `uke_swr2 0` + `uke_txmacro 0`); sin «WCD Playback» (no se toca la ruta RX/USB-C); `audio-routing` solo de captura: 17 extremos, **0 sin widget** en `wcd939x.c`/`lpass-tx-macro.c` |
| Gate de build | `build.sh` (+ casos e9a) | `RESULTADO: OK`: e9a aplica; e5-codec sin e2d/e3 sigue rechazado |
| Cargadores | `module/uke_audio_e5.c` (e5-codec), `module/uke_audio_e9a.c`; `Kbuild`; `build-module.sh` | `.ko` compilados contra `senemos-ouke5/build`, vermagic `7.2.9-senemos.1.4054.3-ouke5` (el árbol `senemos-ouke6/build` no tiene `Module.symvers`; la config del kernel no usa MODVERSIONS, así que basta el vermagic: ouke5 = release de la tablet con el kernel v6) en `out-ouke5/` (sha `9112d9fc…` e5, `f4e354a0…` e9a) |
| Ruta de mezclador | `mic/uke-mic-route.sh` (`--list`, `--dry`, `--apply amic1\|amic4\|amic3-vendor\|estereo-vendor`, `--off`) | valores de la QRD (alsa-ucm-conf, mainline) y de Android (`main-mic`, `handset-dmic-endfire`); salta con aviso los controles inexistentes |
| UCM «UKE» | `mic/ucm2/conf.d/sm8650/UKE.conf`, `mic/ucm2/Qualcomm/uke/HiFi.conf` | solo captura (Mic1 AMIC1, Mic2 AMIC4) y habilita `MultiMedia3 Mixer TX_CODEC_DMA_TX_3`; **no define Speaker** a propósito (los altavoces son `uke-speakers` de PipeWire) |
| PipeWire | `pipewire/51-uke-mic.conf` | fuente ALSA `hw:UKE,2` mono S16/48 k sin mmap, **`nofail`** |
| Harness | `mic/harness/test-mic.sh` | **9 ok, 0 fallos**: PipeWire sobrevive sin tarjeta (y el control sin `nofail` muere), ruta de mezclador con `amixer` falso, UCM con ficheros reales |
| Despliegue | `mic/deploy-mic.sh` | solo ficheros (`.ko` a `extra/`, ruta, UCM, conf pendiente en `/root/uke-mic/`), `--check`/`--revert`; `HOSTIP=uke` por defecto |

## Supuestos sin verificar (se miden en M1-M3)
- `hw:UKE,2` como PCM de captura (en la QRD es el 2): `arecord -l` en M2.
- Numeración `SWR_MIC` del vendor ((puerto−1)·4+(canal−1)) frente a mainline (`qcom,tx-port-mapping = <2 2 3 4>`): M3 barre opciones midiendo RMS.
- Que el SPF/ADSP de Xiaomi acepte el grafo CODEC_DMA del HDK (solo TDM probado): sin respuesta hasta M3.

## Propuesta de M1 (en la tablet; necesita TU orden expresa)
Objetivo: que el WCD9395 **enumere por SoundWire**, sin grabar. Con la tarjeta de altavoces `e8b` ya arriba (no se descarga).
1. Prerrequisitos: cargador de pared, vigía, doble captura (`dmesg -w` a fichero + consola ACM con un solo lector), `dmesg -n 7`, acceso por **Tailscale** (`root@uke`): el WCD comparte rail `pmxr2230_l7` con el usbss del USB-C, o sea el camino de SSH por RNDIS puede caer; NO usar `rmmod` tras un oops, reiniciar (con `sync`).
2. Instalar ficheros: `HOSTIP=uke mic/deploy-mic.sh --go` (solo ficheros).
3. Con `uke-audio` y amps VERDES: `insmod uke_audio_e5.ko` (aplica e5-codec sobre e2d+e3: probe de macros y WCD, ya con relojes votados por e2d/e3) y mirar `dmesg` + `/sys/bus/soundwire/devices` (`sdw:…0217:010e…` ×2) + que el ADSP siga `running` y no haya faults de SMMU. Revertir: reinicio (el overlay e5 no se retira limpio si hay otro encima).
4. Criterio PASA M1: dos esclavos SoundWire, WCD939x sondeado, sin oops/SMMU, SSH vivo. M2 (cambiar a e9a, `arecord -l`) y M3 (captura) son órdenes aparte.
Riesgos: sondeo MMIO del LPASS (cuelgue duro si falta un reloj), reset del WCD (LPI gpio12), rail compartido con USB-C; mitigados por vigía/ACM/Tailscale y por no tocar nada más. Reinicio necesario si se quiere volver al estado previo.
