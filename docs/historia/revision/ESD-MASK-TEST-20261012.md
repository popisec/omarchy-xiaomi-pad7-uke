# ESD-MASK-TEST-20261012 — enmascarado de IRQ ESD 86/87 antes del enable del panel o82

Objetivo (#608): falsar la hipótesis "el boot del TDDI (sus IRQ ESD 86/87 = gpios 168/169) mata el SoC"
enmascarando las IRQs antes del enable. Captura idéntica a #608 + timing de alta resolución.

## 1. Vía de enmascarado: NO EXISTE en userspace (documentado)

- `/proc/irq/86/` y `/proc/irq/87/` (acciones `uke-o82-esd`, chip msmgpio, Edge): solo ofrecen
  `smp_affinity(_list)`, `spurious`, `affinity_hint` — **no hay mask/disable**. El subdirectorio
  irqaction `uke-o82-esd/` está vacío (handler no threaded, sin ficheros).
- `CONFIG_GPIO_SYSFS` no está en L19 → no existe `/sys/class/gpio`, imposible `edge=none` en
  gpio168/169 (y exportar habría reconfigurado el pin: descartado de entrada).
- Sin knob ESD en sysfs del driver (solo propiedades DT de solo-lectura: `esd-err-gpios` en
  `panel@0`). debugfs gpio es solo lectura.
- Conclusión: el mask REAL (free_irq/disable_irq) exige cambio en el driver del kernel. Se ejecutó
  el **EXPERIMENTO DE TIMING** (plan B del protocolo).

## 2. Captura armada (idéntica a #608 + timing)

scp de `uke-ufs-witness.sh` + `uke-wedge-sampler.sh` a `/root/` (chmod +x); witness arm (3 procs),
sampler arm (4 loops, regmap: uke_panel_vsp/vsn + pmxr2230_l8), `dmesg -n 7`, `nohup acm-loop.sh
/tmp/acm-esd-mask.log` en el PC. Loop de timing propio: dump completo de `/proc/interrupts` con
timestamp `date +%s%3N` a `/root/esd-timing.log` (persistente, symlink `/tmp/esd-timing.log`),
cadencia real ~53 ms (~19 Hz), arrancado ~22 s antes del disparo.

Incidente: caída del cable USB a las 00:24:18Z (dueño lo confirmó como desconexión accidental);
la tablet NO reinició (mismo boot, uptime intacto) y los 7 procesos testigo sobrevivieron; el
acm-loop del PC agotó sus 400 iteraciones y se relanzó.

## 3. Disparo y muerte (6/6 — el wedge reproduce SIEMPRE)

`TRIGGER 1790298217066` (wall ms) = kernel `[1823.5158]`; conexión SSH reseteada al instante.
Línea temporal exacta (dmesg.log del witness, timestamps de kernel µs):

| kernel s | evento |
|---|---|
| 1823.5730 | UKE-P82 prepare/power_on INICIO |
| 1823.5758–5821 | vddil8b / vsp / vsn ENABLED (rieles OK) |
| 1823.5823 | K48-rst-A (assert reset #1) |
| **1823.5933** | **UKE-K49: ESD irq 86! val=0 — UNA sola vez** |
| **1823.5937** | **UKE-K49: ESD irq 87! val=0 — UNA sola vez** |
| 1823.5965/5998 | release → assert2 → **K48-w4-done** |
| 1823.6357 | último mensaje kernel (ufshcd/devfreq, rutinario) → **muerte** |

- **Muerte a +35,9 ms tras w4-done** (+120 ms tras el trigger) — coincide con #608 (≤100 ms).
- El timing loop a 53 ms se congeló en `1790298217140` (+74 ms del trigger): cero SMMU faults, y
  los contadores 86/87 en TODOS sus dumps = 0/1 (los dos edges caben entre muestras).
- El sampler 25 Hz SÍ los pescó: `irq.now` final (renombrado atómico, mtime = instante de muerte)
  muestra **86:1, 87:2** (baseline 0/1) → **ni tormenta ni repetición: exactamente un par de edges**.
- Último tick tlmm (…217150): g168/g169 **LOW** (el TDDI soltó sus líneas al perder estado en el
  reset), g74/g75 HIGH, g2 low, rieles enabled. ACM log (7,8 MB) capturó muerte+reboot en vivo.
- Reboot WDT ~12–25 s; post-boot: panel disconnected/disabled, irq 87 con su fire de armada habitual.

## 4. Conclusión sobre el mecanismo TDDI

1. **Las IRQ ESD NO se comportan como causa**: disparan UNA vez cada una (no hay storm), ANTES de
   w4-done, y el SoC sigue ejecutando código y logueando **36 ms después** de ellas en estado
   aparentemente normal. Un IRQ asesino mata en el handler o de inmediato; esto es el patrón de
   **síntoma**: el TDDI pierde estado/suelta sus líneas ESD (val=0, pull-down) durante el assert
   del reset y nosotros lo observamos.
2. La muerte llega **después de w4-done**, en la fase que viene sin llegar a loguear nada:
   DSI host on / init del panel tras el segundo assert. Ahí está el asesino probable, no en las IRQ.
3. La hipótesis queda **debilitada pero no falsada formalmente** (el mask real exige kernel: un
   `disable_irq_nosync(86/87)` o no armarse hasta post-init en el driver UKE-K49 seguiría siendo
   el experimento definitivo — pendiente, requiere build L19).

## 5. Evidencia

`~/proyectos/omarchy-uke/build/evidencia/pantalla-esd-mask-20261012/`:
`witness/` (dmesg.log con la línea de muerte µs-a-µs, trace.log ftrace a6xx, wedge/: irq.now final,
rails.log, tlmm.log, ~365 irq-full-N.txt), `esd-timing.log` (19 Hz, 464 dumps), `acm-esd-mask.log`
(consola serie completa). Regla del proyecto: rootfs rw sin journal → e2fsck en frío pendiente si
aplica tras muertes.
