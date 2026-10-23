# AUDIO — E3b ejecutado: los votos PRM de reloj funcionan — 18-oct-2026 16:18

Autorizado por el dueño. Gate: 3847 mV, Charging, ADSP/WPSS running; vigía + `ssh dmesg -w` + ACM. Logs `build/logs/audio/e3b-20261018-tablet.log`.

## Resultado (MEDIDO) — **PASA**
Con E2d cargado: `insmod uke_audio_e3.ko` (el driver sm8650-lpass-lpi se autocarga y liga; `LPASS_HW_MACRO`/`LPASS_HW_DCODEC` en 0, runtime `suspended`) y luego:
- `echo on > /sys/devices/platform/soc/6e80000.pinctrl/power/control` → runtime **active**; `clk_summary`: `LPASS_HW_MACRO` y `LPASS_HW_DCODEC` con **enable_count 1** (consumidor `pin`) ⇒ **los dos `PRM_CMD_REQUEST_HW_RSC` al ADSP se completaron sin error ni `CMD timeout`**.
- `echo auto` → autosuspend → **enable_count 0** (los `RELEASE_HW_RSC` también OK). Ciclo on/auto repetido una segunda vez: igual.
- ADSP running todo el tiempo, Charging, WiFi up, sin faults/SMMU/watchdog. **No hubo ningún acceso MMIO al LPASS** (ninguna lectura/escritura de pines).
Reversa: descarga de `pinctrl_sm8650_lpass_lpi`/`pinctrl_lpass_lpi` y `uke_audio_e3` (overlay retirado); E2d queda cargado como antes (`uke-audio.service` habilitado). Relojes en 0.

## Qué prueba
El camino completo **apps ↔ ADSP por PRM** (votos de los relojes `LPASS_HW_MACRO_VOTE` y `LPASS_HW_DCODEC_VOTE`) funciona sobre el q6prm de mainline en los puertos GPR reg 7: es la base que necesitan el WCD/macros (E5) y el pinctrl para tocar el LPASS sin colgar el bus. Con los votos activos el LPASS tiene sus relojes de bus.

## Siguiente
- **E3c** (una lectura de un único pin con los votos activos; primer acceso MMIO al LPASS): solo si el dueño lo pide; no es necesaria para continuar.
- **E4**: DAIs/DMA (`q6apm-dai`/`bedais`) con el SMMU 0x801001/0x1061 (admitidos en v4). Riesgo medio-alto (primera DMA del LPASS a memoria de Linux); además los grafos usan puertos dinámicos (≥0x10000000) y no se sabe si el firmware enruta sus respuestas — es lo que probará E4. Antes: preparar en el PC, con informe, el overlay `e4` retargeteado (ya apunta a `service@3`) y el procedimiento.
- Los altavoces (E7) siguen necesitando TDM + driver FS19xx (trabajo grande); sin ellos E4–E6 solo validan la tubería (WCD sin jack).
