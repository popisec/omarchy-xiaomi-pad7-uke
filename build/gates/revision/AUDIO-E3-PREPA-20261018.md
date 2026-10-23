# AUDIO — E3 preparado en el PC: pinctrl LPI + votos de reloj PRM (sin tocar la tablet) — 18-oct-2026

Orden del dueño: preparar E3 (pinctrl LPI y votos de reloj PRM) retargeteando los overlays a service 3, con informe de qué hará en la tablet y cómo se revierte. **No se tocó la tablet.**

## Cambios (VERIFICADO-PC)
- **Cadena de overlays nueva**: `e2d → e3 → e4 → e5-codec → e5-card` (antes `e2 → …`). `e2-gpr` pasa a «solo referencia» (EXTRA). `build.sh` aplica la cadena en cascada y de una vez (idénticas), rechaza `e4` sin `e2d`, y `check-overlays.py` valida phandles/compatibles/celdas de toda la cadena: **RESULTADO OK**.
- `e2d` lleva ahora las **etiquetas** `uke_q6apm` (service@3), `uke_q6prm` (service@7) y `uke_q6prmcc` (el clock-controller): las usan e3 (relojes), e5-codec y e5-card. Coste: 3 avisos benignos «memory leak … /__symbols__/uke_*» al aplicarlo. **El `uke_audio_e2d.ko` instalado hoy en la tablet no las tiene: hay que reinstalarlo** (`deploy.sh --module`).
- `e4-dais` cuelga ahora de `…/qcom,gpr/service@3`.
- Módulo cargador nuevo `out/uke_audio_e3.ko` (sha `ad55b39c…`, vermagic ouke4); `uke_audio_e2d.ko` regenerado (sha `1b59f327…`). `boot/deploy.sh --module` instala los dos (e3 sin usar al arrancar; `uke-audio-up.sh` no lo carga).

## Qué hace E3 (lectura del driver `pinctrl-lpass-lpi.c`)
`lpi_pinctrl_probe()` solo mapea la MMIO (`devm_platform_ioremap_resource`), registra los relojes con `of_pm_clk_add_clks` (los de `uke_q6prmcc`: `LPASS_HW_MACRO_VOTE`, `LPASS_HW_DCODEC_VOTE`) y habilita runtime PM: **no lee ni escribe registros ni vota relojes al sondear**. Los votos PRM al ADSP (PRM_CMD_REQUEST_HW_RSC) y el primer acceso a MMIO ocurren solo con la primera operación de pines (mux/config/gpio) vía `pm_runtime_resume_and_get`. Por eso E3 se parte en tres pasos de riesgo creciente:
| Paso | Qué hace en la tablet | Riesgo | Éxito | Reversa |
|---|---|---|---|---|
| **E3a** | `uke-audio-up.sh --down`; `boot/deploy.sh --go --module` (e2d con etiquetas + e3); `uke-audio-up.sh` (VERDE); `insmod uke_audio_e3.ko` (crea el nodo `pinctrl@6e80000`); `modprobe pinctrl-sm8650-lpass-lpi` | **bajo**: solo registra gpiochip/pinctrl; sin MMIO ni votos. Nuevo: `fw_devlink`/probe diferido del nodo, platform device creado al vuelo (no medido) | dispositivo `6e80000.pinctrl` ligado a su driver, sin errores; ADSP running | `modprobe -r pinctrl-sm8650-lpass-lpi pinctrl-lpass-lpi`, `rmmod uke_audio_e3` |
| **E3b** | `echo on > /sys/devices/platform/soc/6e80000.pinctrl/power/control`: fuerza runtime-resume ⇒ **solo el voto PRM** (relojes `LPASS_HW_MACRO/DCODEC_VOTE`) sin acceso a MMIO; luego `auto` | **medio**: primer `PRM_CMD_REQUEST_HW_RSC` al ADSP (el ADSP ya contesta al APM; PRM no probado). Posible: respuesta con error o timeout (5 s) | `clk_summary` con los votos habilitados, sin `CMD timeout` de PRM, ADSP running | `echo auto > …/power/control`; si no, `stop/start` del ADSP |
| **E3c** | **una** lectura de un pin inofensivo (no gpio12=reset del WCD, no gpio6-9=TDM de los amplis, no gpio0-5=SWR) con votos activos | **medio-alto**: primer acceso MMIO al LPASS (cuelgue duro si el voto no basta; regla 3: nada de volcados, ni `debugfs/gpio`, ni `gpioinfo`) | lectura sin cuelgue | reset físico si cuelga |
Mi recomendación: E3a y E3b ahora; **E3c solo si el dueño lo pide** (lo útil para E4/E5 es que el voto PRM funcione; el acceso a pines llega solo con el WCD).

## Qué NO cubre / no verificado
Que el platform device del nodo creado en `/soc` por el overlay se cree y ligue (INFERIDO: `of_platform_notify`); que la tabla de pines de `sm8650` sirva para cliffs (la comprobación de E0: 23 pines, mismos IDs de reloj y bases que `sm8650.dtsi`; el vendor declara 23); que PRM conteste. Nada de E3 cambia el arranque: `uke-audio.service` sigue levantando solo E2d.
