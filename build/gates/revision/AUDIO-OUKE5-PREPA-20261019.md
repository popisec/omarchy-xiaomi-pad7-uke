# AUDIO — preparación para el kernel ouke5 (19-oct-2026, solo PC)

Pedido por la sesión de cámaras (ciclo C3, parche rpmh `0045`), con aprobación del dueño de PREPARAR; el flash lo decide él. No se ha tocado la tablet ni el árbol ouke4.

## Hecho
- **.ko recompilados contra `build/kernel-pokes/senemos-ouke5/build`** (release `7.2.9-senemos.1.4054.3-ouke5`) en `build/rootfs/deploy/audio/out-ouke5/` (8 ficheros, todos vermagic ouke5): `uke_audio_e2d`, `uke_audio_e3`, `uke_audio_e7i2c`, `uke_audio_e8a`, `uke_audio_e8b`, `uke_fs19xx`, `snd-q6apm-uke` (parches 0005-0008), `q6apm-lpass-dais-uke`. Los símbolos y modversions de q6apm coinciden con los del árbol ouke5.
- Scripts de build con variable `OUT` (defecto `out/` = ouke4 intacto): `build-module.sh`, `q6apm-port/build.sh`, `fs19xx/build.sh`.
- Gates de `uke-audio-up.sh` y `uke-audio-amps-up.sh`: aceptan `*senemos*ouke[45]*` (ouke4 sigue valiendo, rollback). Harness: 21/21 y 19/19, con prueba nueva de ouke5.
- `boot/deploy-amps.sh`: `KREL=…ouke5` usa `out-ouke5/`. Nuevo `boot/deploy-ouke5-pre.sh` (solo ficheros): tras `flash-senemos-v5-gated.sh --pre`, instala `snd-q6apm.ko` y `q6apm-lpass-dais.ko` parcheados en `/lib/modules/<ouke5>/updates/` y hace depmod (el gate de `uke-audio-up.sh` exige que `snd-q6apm` salga de `updates/`; el `--pre` de flash solo copia a `extra/`).

## Desviación respecto al pedido
Se pidió dejar los .ko en `audio/out/`. Allí están los .ko ouke4 que usan los scripts de despliegue y el rollback, y el `--pre` aborta si queda algún .ko con otro release. Por eso los ouke5 van en `out-ouke5/` (como cámaras). **Hay que cambiar `OWN_KO_DIRS` de `flash-senemos-v5-gated.sh` a `…/audio/out-ouke5`** (fichero de la sesión de cámaras; no lo he tocado).

## Verificado / no verificado
Verificado en el PC: vermagic, harness, dry-run de los scripts. NO verificado: carga en ouke5 (cold boot), ni que `pinctrl-sm8650-lpass-lpi`, `apr`, `q6prm*`, `snd-soc-core` del tarball ouke5 se comporten igual que en ouke4 (están en el tarball). Antes del flash: `--pre` de flash, `deploy-ouke5-pre.sh --go`, y `--check` de ambos.

## Orden en el ciclo ouke5
1. `flash-senemos-v5-gated.sh --pre` (instala árbol de módulos ouke5 y los .ko de `out-ouke5/` en `extra/`). 2. `boot/deploy-ouke5-pre.sh --go` (updates/ + depmod). 3. Flash (decide el dueño). 4. Arranque: `uke-audio.service` y `uke-audio-amps.service` (habilitados, comparten guarda 'audio'); si fallan, `touch /etc/uke/no-audio` y volver a ouke4 con el set_active.

## Resultado en la tablet ya en ouke5 (19-oct, 23:0x)
La tablet arrancó en ouke5 sin el paso de `updates/`: `uke-audio` no cargó nada (gate viejo ouke4-only) y `uke-audio-amps` falló por dependencia; sin tarjeta. Con autorización: `deploy-ouke5-pre.sh --go` (ahora válido con la tablet en ouke5; copia también los gates) + etapa 1 y etapa 2 a mano:
etapa 1 VERDE (APM estado 1, `q6prm_clocks`; un `CMD timeout` previo = reintento normal en frío), etapa 2 VERDE (4 amps DEVID 0x2900, tarjeta `UKE`, `snd-q6apm` desde `updates/`). Vigía sin oops. Captura `build/logs/audio/e15-20261019-dmesg-ouke5.log`. Tono NO lanzado aún.
Lección: el `updates/` y los gates deben instalarse ANTES del flash (`--pre`); sin ello el primer arranque en ouke5 queda mudo.

## Tono en ouke5 (19-oct, 23:21)
Tras instalar `updates/`, gates y la conf con `nofail` (y recuperar PipeWire), `pw-play --target uke-speakers` (−18 dBFS efectivos, 2 s, vol 0xE0): **el dueño lo oye en ouke5**. Vigía sin oops. Pendiente: arranque en frío en ouke5 con `uke-audio` y `uke-audio-amps` por sí solos (autorización de reinicio aparte).

## Arranque en frío en ouke5 (verificado 20-oct, boot de las 12:32 hora tablet)
La tablet reinició sola dos veces (12:22 y 12:32; no por mí: mi `systemctl reboot` por USB no llegó, el enlace USB ya no existía y la tablet seguía arriba). El arranque de las 12:32, ya con `updates/`, gates ouke[45] y la conf con `nofail`, deja SIN intervención: `uke-audio` active (VERDE en 7 s), `uke-audio-amps` active (VERDE, tarjeta UKE, 4 amps), `snd-q6apm` desde `updates/`, PipeWire/WirePlumber activos, `uke-speakers` como sumidero predeterminado, 0 oops/faults. Tono tras este arranque: pendiente de confirmar con el dueño.
