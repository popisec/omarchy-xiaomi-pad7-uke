# AUDIO — E3c preparado en el PC: una lectura de un pin LPI con los votos PRM activos — 18-oct-2026

**No se tocó la tablet.** Requisito de E7b (primeras escrituras al TLMM del LPASS para los pines TDM gpio6-9).

## Qué hay
| Fichero | Qué es |
|---|---|
| `e3c/uke_lpi_rd.c` → `out/uke_lpi_rd.ko` (sha `62fee0a2…`, vermagic ouke4) | Módulo de **solo lectura** de un único registro |
| `e3c/build.sh`, `e3c/deploy.sh` | Compilar; copiar el `.ko` a `extra/` (sin cargarlo; `--revert` lo borra) |

## Qué hace el módulo
1. Busca `6e80000.pinctrl` (ya ligado al driver `pinctrl-sm8650-lpass-lpi`, estado E3a) y aborta si no existe, no tiene driver o su recurso MMIO es menor de 23×0x1000.
2. `pm_runtime_resume_and_get()`: **lo mismo que hace el driver antes de cualquier acceso** (votos PRM `LPASS_HW_MACRO`/`LPASS_HW_DCODEC`, ya medidos OK en E3b). Si falla o el dispositivo no queda `active`, **no lee**.
3. Solo con `uke_lpi_go=1`: **un** `ioread32` en `res->start + 0x1000·pin + 0x00` (`LPI_TLMM_REG_OFFSET`·pin + `LPI_GPIO_CFG_REG`; sm8650 no usa offsets predefinidos, medido en el árbol). Imprime `CFG(gpioN) = 0x…`.
4. Libera siempre la referencia (`put_autosuspend`). **Ninguna escritura**, ningún barrido, ni debugfs/gpio (regla 3).
Pin por defecto **13** (dmic3_data/i2s3_ws; sin consumidor; no es gpio12 = reset del WCD, ni gpio6-9 = TDM de los amps, ni gpio0-5 = SWR). `uke_lpi_pin` admite 0-22.

## Procedimiento propuesto (autorización del dueño; ACM un lector, vigía, doble captura, `dmesg -n 7`)
- **E3c-0** `e3c/deploy.sh --go` (solo fichero).
- **E3c-1** (estado E3a si no está): `insmod uke_audio_e3.ko` y `modprobe pinctrl-sm8650-lpass-lpi` (el driver solo mapea; sin MMIO). Comprobar `6e80000.pinctrl` ligado.
- **E3c-2 «seco»**: `insmod uke_lpi_rd.ko` (go=0): solo resume/votos y comprobaciones; esperar `votos PRM activos`; `rmmod uke_lpi_read`.
- **E3c-3 lectura**: `insmod uke_lpi_rd.ko uke_lpi_go=1` ⇒ una línea `CFG(gpio13) = 0x…`; `rmmod uke_lpi_read`.
- **Reversa**: `rmmod uke_lpi_read` (el autosuspend suelta los votos a los 100 ms); `modprobe -r pinctrl_sm8650_lpass_lpi pinctrl_lpass_lpi`, `rmmod uke_audio_e3`; borrar el `.ko` con `deploy.sh --revert`.

## Riesgos
| # | Riesgo | Prob./impacto | Mitigación |
|---|---|---|---|
| 1 | La lectura MMIO cuelga el bus (error de NoC/SError) aunque los votos estén activos | baja-media / **alto**: reset físico, sin watchdog (R-42) | paso 2 «seco» antes; votos ya verificados en E3b; un solo acceso, 4 bytes, de un registro de configuración sin efecto; batería ≥ 3700 mV y cargador; el dueño tiene el reset a mano |
| 2 | Los votos PRM no bastan para el bus del TLMM LPI (falta otro reloj/dominio, p. ej. el `lpass_core` o la isla) | media / alto (el mismo cuelgue) | es justamente lo que mide E3c; si cuelga, E7b queda descartada por esa vía y la causa queda medida |
| 3 | La dirección es errónea (`0x6e80000` + 0x1000·13) | baja / alto | deriva del recurso del propio nodo y del `LPI_TLMM_REG_OFFSET` del árbol; el DT de Android declara el mismo `reg = <0x6e80000>` |
| 4 | Modificar estado del pin | nula | solo `ioread32` |
| 5 | Interferir con otra sesión (BT/PipeWire) | baja | no toca BT, shell ni PipeWire; avisar a la sesión BT si hay reinicio |

## No cubre
Que la lectura sea representativa de una *escritura* (E7b escribirá mux/config); que el estado reportado por el CFG sea el esperado (se interpretará con `LPI_GPIO_CFG_REG`: pull/drive/dir/función); el reloj del TDM real (E7b).

## E3c-0..2 EJECUTADO (MEDIDO, 21:07) — PASA, sin MMIO
Autorizado por el dueño. Gate: 3818 mV, Charging, ADSP running; vigía + `dmesg -w` a `build/logs/audio/e3c-20261018-dmesg.log` + ACM (`e3c-20261018-acm.log`, reader propio; la captura anterior de E8 se había parado). Aviso: los dos lectores previos de `dmesg`/ACM no estaban vivos al empezar; se rearmaron antes de tocar nada.
- E3c-1: `insmod uke_audio_e3` + `modprobe pinctrl-sm8650-lpass-lpi` ⇒ `6e80000.pinctrl` ligado a `qcom-sm8650-lpass-lpi-pinctrl`, runtime `suspended`, `LPASS_HW_MACRO/DCODEC` en 0.
- E3c-2 (go=0): `uke_lpi_read: votos PRM activos (runtime active); pin 13, CFG en 0x6e8d000; go=0` con `clk_summary` **LPASS_HW_DCODEC y LPASS_HW_MACRO enable_count 1** mientras el módulo corría y **0** a los ~100 ms (autosuspend). Sin `CMD timeout` nuevos, ADSP running, 0 oops. **Ningún acceso MMIO.** La dirección derivada del recurso (`0x6e80000 + 0x1000·13 = 0x6e8d000`) es la esperada.
- Defecto de mi módulo: sin `module_exit` no se puede descargar (`rmmod: Device or resource busy`). La 1.ª versión (`uke_lpi_read`) queda cargada en RAM, inofensiva, hasta el próximo arranque. Corregido: el módulo se llama ahora `uke_lpi_rd` (exit vacío, sha `62fee0a2…`), copiado a la tablet (`extra/`); el viejo se borró de `extra/` y del repo.
- Estado actual de la tablet: e2d + e3 + driver LPI cargados, `uke_lpi_read` (v1) cargado, e8a/uke_fs19xx/e7i2c cargados.
- **Pendiente (pedir aparte): E3c-3** `insmod uke_lpi_rd.ko uke_lpi_go=1` ⇒ una lectura de `CFG(gpio13)`; `rmmod uke_lpi_rd` funcionará.

## E3c-3 EJECUTADO (MEDIDO, 21:08) — PASA: primer acceso MMIO al LPASS TLMM sin cuelgue
`insmod uke_lpi_rd.ko uke_lpi_go=1` ⇒ `uke_lpi_rd: CFG(gpio13) = 0x00000401`; `rmmod uke_lpi_rd` rc 0; votos `LPASS_HW_MACRO/DCODEC` de vuelta a 0; ADSP running, Charging, 0 oops/faults; vigía y capturas vivos todo el tiempo.
Decodificación (máscaras del driver): PULL=1 (pull-down), FUNC=0 (gpio), DRIVE=0, OE=0 (entrada); el bit 10 (0x400) no está definido en el driver (reservado/por defecto). Es un estado de reposo coherente ⇒ la dirección y los votos son correctos y **el bus del TLMM LPI responde con solo los votos PRM** (riesgos 1-3 de E3c descartados para lecturas). Las escrituras (E7b) siguen sin probar.
Estado de la tablet: e2d + e3 + driver LPI + `uke_lpi_read` (v1, no descargable) + e8a/uke_fs19xx/e7i2c cargados.
