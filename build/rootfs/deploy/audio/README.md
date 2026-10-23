# Audio de la uke — material de la etapa E0 (preparación en el PC)

Fecha: 18-oct-2026. Plan: [`build/gates/revision/AUDIO-SENEMOS-20261018.md`](../../../gates/revision/AUDIO-SENEMOS-20261018.md).
Informe de esta etapa (qué está verificado y qué no): [`build/gates/revision/AUDIO-E0-20261018.md`](../../../gates/revision/AUDIO-E0-20261018.md).

> **Nada de esto se ha aplicado a la tablet ni se ha probado en ella.** Todo se generó y se comprobó en el PC
> (sin ssh/adb/fastboot). Las etapas que tocan el ADSP (E2 en adelante) necesitan orden expresa del dueño: el ADSP lleva
> también la carga y `recovery_disabled=true` (parche 0033) significa que, si cae, no se recupera solo.
> Los overlays **no son para la partición `dtbo`** (ni se pasan por `uke-dtbo-check.py`): se aplican en caliente
> con `of_overlay_fdt_apply()` desde un módulo cargador (por escribir, E0-f del plan) o se hornean vía `uke-abl.c`.

## Reproducir y verificar

```bash
build/rootfs/deploy/audio/build.sh          # ~3 s: compila, aplica con fdtoverlay, comprueba, genera la topología, corre los tests
build/rootfs/deploy/audio/build.sh --quick  # solo overlays y topología
```
`build.sh` falla si `dtc` da algún aviso no previsto, si `fdtoverlay` rechaza algo, si una etiqueta pisa a una del vendor,
si un phandle no resuelve, si algún `compatible` no tiene módulo en el kernel `ouke3`, si los includes de topología cambian o
si un test de los parches falla. Genera `out/*.dtbo`, `topology/out/UKE.conf`, `firmware/qcom/sm8650/UKE-tplg.bin`,
`out/*.txt` (salidas de los chequeos) y `MANIFEST.sha256`.

## Contenido

| Ruta | Qué es | Etapa |
|---|---|---|
| `dts/uke-audio-e2-gpr.dtso` | `q6apm` + `q6prm` + `q6prmcc` bajo `qcom,gpr`, con `qcom,protection-domain`. Sin DMA ni pines ni relojes | **E2** |
| `dts/uke-audio-e3-lpi.dtso` | Pinctrl LPI de mainline (23 pines) + estados SWR RX/TX, reset del WCD (LPI gpio12) y TDM1 (sin consumidor) | E3 |
| `dts/uke-audio-e4-dais.dtso` | `bedais` + `dais` (con `iommus` del LPASS). **No funciona sin el parche 0002 del kernel (flash)** | E4 |
| `dts/uke-audio-e5-codec.dtso` | Macros VA/TX/RX, SoundWire RX/TX, WCD9395 | E5 |
| `dts/uke-audio-e5-card.dtso` | Tarjeta `qcom,sm8650-sndcard`, `model = "UKE"`: enlaces WCD Playback y WCD Capture | E5/E6 |
| `dts/uke-audio-e7-amps-i2c.dtso` | Enciende `i2c@88c000` (4 FS19xx) **en caliente**; alternativa al parche 0001 | E7 (no antes) |
| `fs19xx/uke_fs19xx.c` (+`build.sh`, `deploy.sh`, `dryrun.py`) | Driver mínimo, «falla cerrado», de los 4 FS19xx (I²C 0x34-0x37, reset GPIO, preset `fs19xx.fsm` cargado con `request_firmware`, DAI `fs16xx-aif`). Por defecto NO escribe en los amps (`uke_fs_play=0`) | **E8** |
| `dts/uke-audio-e8a-card-fs19xx.dtso`, `…e8b-card-fs19xx-pins.dtso` | Tarjeta TDM con el códec real (sin / con pines LPI gpio6-9); nodo `uke,fs19xx-codec` | E8 |
| `topology/UKE.m4` (+ `src/`) | Topología AudioReach derivada de `SM8550-HDK.m4` (sin WSA ni DP) | E4–E6 |
| `firmware/qcom/sm8650/UKE-tplg.bin` | Compilada con `alsatplg 1.2.16`; destino `/lib/firmware/qcom/sm8650/UKE-tplg.bin` | E4–E6 |
| `kernel/0001-…amps.patch` | `uke-abl.c`: admite `i2c@88c000` + 4 FS19xx, validado «fail closed» | E7 (flash) |
| `kernel/0002-…sids.patch` | `arm-smmu-qcom.c`: admite los SIDs de audio del LPASS. **Hallazgo fuera de encargo** | E4 (flash) |
| `kernel/0003-…client.patch` | `uke-abl.c`: opcional, solo si el overlay de audio se hornea en el DT de arranque | opcional |
| `kernel/harness/` | Arnés que ejecuta `uke_abl_transform()` en el PC sobre el DT capturado + tests de los parches | — |
| `pipewire/50-uke-null-sink.conf` | Sumidero nulo de PipeWire | **E1** |
| `pipewire/test-private.sh` | Prueba la config en una instancia privada de PipeWire+WirePlumber | — |
| `check-overlays.py` | Chequeos del DT resultante (nodos, símbolos, phandles, cobertura de módulos) | — |

## Orden de aplicación de los overlays

`e2` → `e3` → `e4` → `e5-codec` → `e5-card` (cada uno usa etiquetas del anterior; `e4` sin `e2` se rechaza, comprobado).
Quitarlos: orden inverso, descargando antes los módulos (`snd*`, `q6*`, `apr`) como dice el plan §5.
Etiquetas con prefijo `uke_` a propósito: el vendor ya tiene `swr1`, `rx_macro`, `lpi_tlmm`… en `/__symbols__`.
Convenciones del DT vivo que el overlay respeta: `/soc` es 1/1 celdas (no 2/2), el GIC es de 3 celdas, los hijos vendor del gpr
(`spf_core`, `q6prm` `qcom,audio_prm`, `audio-pkt`) se dejan intactos.

Al aplicarlos, `of_overlay_fdt_apply()` imprimirá (previsto por lectura de `drivers/of/overlay.c:372-374`, sin comprobar en la tablet) líneas `WARNING: memory leak will occur if overlay removed, property:
/__symbols__/uke_…` (una por etiqueta, 19 en total): son benignas (propiedades nuevas en un nodo del DT original). El
vigía de E2 no debe tratarlas como fallo.

## E1 — sumidero nulo (riesgo nulo para ADSP/HW; instalación manual, no hay `deploy.sh` a propósito)

Probado en el PC (instancia privada, ver `out/pipewire-test.txt`): nodo `uke-null-sink` `Audio/Sink` 48 kHz FL FR,
`wpctl status` lo muestra como sumidero predeterminado y un flujo `pw-cat` se enlaza solo y queda `active`.
En la tablet (cuando el dueño lo ordene; es solo software y no toca remoteproc):

```bash
ssh -i build/rootfs/uke-arch-root -o BatchMode=yes root@192.168.42.129 'mkdir -p /etc/pipewire/pipewire.conf.d'
scp -i build/rootfs/uke-arch-root build/rootfs/deploy/audio/pipewire/50-uke-null-sink.conf root@192.168.42.129:/etc/pipewire/pipewire.conf.d/
# como el usuario de la sesión Omarchy:
systemctl --user restart pipewire pipewire-pulse wireplumber && wpctl status
```
Alternativa sin PipeWire: `modprobe snd-aloop` (módulo presente en `ouke3`); da una tarjeta ALSA, pero no es lo que pide E1.
Desinstalar: borrar el fichero y reiniciar PipeWire.

## Decisiones que son del dueño (no tomadas aquí)

1. **E1**: ¿instalar el sumidero nulo? (sin riesgo; solo software).
2. **E2'/E2**: ¿ensayo `stop/start` del ADSP y primer overlay `e2`? Requiere el módulo cargador y el vigía (E0-f, no hechos).
3. **E4**: el kernel necesita el parche 0002 ⇒ un ciclo de flash (ledger, gates, ≤2 escrituras/día). El plan decía que quizá bastaba
   un overlay en caliente; el código del kernel lo desmiente (ver informe §3).
4. **Nombre de la tarjeta**: `UKE` (propio, recomendado: topología sin WSA y UCM a medida) o `SM8650-QRD` (reutiliza
   `SM8650-QRD-tplg.bin` de `linux-firmware` si se instalase; esa topología y su UCM asumen WSA).
5. **I2C de los amplificadores**: overlay en caliente (`e7-amps-i2c`, para probar sin flash) o parche 0001 (permanente).

## E2 — cargador y vigía (añadido 18-oct, tras E2')
`build-module.sh` compila `out/uke_audio_e2.ko` (carga `uke-audio-e2-gpr.dtbo` con `of_overlay_fdt_apply`; reutiliza el cargador genérico `uke-ovl.h` de la sesión BT, copiado en `module/`).
vermagic = `7.2.9-senemos.1.4054.3-ouke3` = `uname -r` de la tablet; sin dependencias. `vigia-adsp.sh` = vigía de solo lectura para la tablet (ver cabecera).
**Nada cargado en la tablet.** Procedimiento de E2 (cada paso con riesgo pide autorización): ver `build/gates/revision/AUDIO-E2-PREPA-20261018.md`.
