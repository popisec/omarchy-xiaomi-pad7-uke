# AUDIO — E3a ejecutado: pinctrl LPI sondea sin votos ni MMIO — 18-oct-2026 16:14

Autorizado por el dueño. Gate: 3867 mV, Charging, ADSP/WPSS running; vigía + `ssh dmesg -w` + ACM. Logs `build/logs/audio/e3a-20261018-tablet.log`.

## Secuencia y resultado (MEDIDO) — **PASA**
1. `uke-audio-up.sh --down` (E2d descargado), `boot/deploy.sh --go --module` (e2d con etiquetas `f…1b59f327`, `uke_audio_e3.ko` `ad55b39c`, depmod), `uke-audio-up.sh` → VERDE (APM estado 1).
2. `insmod uke_audio_e3.ko` → `overlay aplicado (id 3, 2431 B)`; 5 avisos benignos «memory leak … /__symbols__/uke_*»; el nodo `pinctrl@6e80000` aparece en el DT y se crea el platform device `6e80000.pinctrl` (**confirma que un overlay añadido bajo `/soc` crea su dispositivo al vuelo**). Aviso inocuo: `arch-timer-mmio 17420000.timer: Failed to create device link (0x180)`.
3. El módulo `pinctrl_sm8650_lpass_lpi` (+ `pinctrl_lpass_lpi`) se **autocargó** por modalias y el dispositivo quedó ligado: `/sys/bus/platform/devices/6e80000.pinctrl/driver → qcom-sm8650-lpass-lpi-pinctrl`, sin errores.
4. Estado de relojes/energía: `LPASS_HW_MACRO` y `LPASS_HW_DCODEC` figuran con consumidor `pin` pero **enable_count 0** (sin votos PRM), `runtime_status = suspended`, `power/control = auto`. Es lo previsto (el probe no vota ni toca MMIO).
5. Estabilidad: ADSP running, Charging, WiFi up, sin faults/watchdog/SMMU; sin `CMD timeout`.
Reversa: `rmmod pinctrl_sm8650_lpass_lpi pinctrl_lpass_lpi`, `rmmod uke_audio_e3` («overlay retirado», nodo desaparece del DT). Se deja E2d cargado como antes (`uke-audio.service` habilitado).

## Siguiente: E3b (autorización aparte; riesgo medio)
Con e3 y el driver cargados: `echo on > /sys/devices/platform/soc/6e80000.pinctrl/power/control` fuerza runtime-resume ⇒ **solo los votos PRM** (`PRM_CMD_REQUEST_HW_RSC` de `LPASS_HW_MACRO/DCODEC_VOTE`) sin acceso a MMIO; luego `auto`. Éxito: `enable_count` 1 en `clk_summary`, sin `CMD timeout`, ADSP running. Reversa `echo auto`; si el ADSP se degrada, stop/start. E3c (una lectura de pin) solo a petición expresa.
