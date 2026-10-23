# L56 — PWM_ENABLE off en el probe del KTZ8866 (luz desde el arranque) — 14-oct-2026

> Solo-PC (prep). Causa raíz CONFIRMADA EN VIVO hoy (ledger #631, KTZ-PWM-ENABLE.md §6):
> BL_CFG1 0x02 bit0=1 (modo "I2C × PWM") + pin PWM a duty=0 ⇒ Standby, boost OFF.
> Receta probada sin flash: 0x02 0x53→0x52 + 0x08 0x3F→50 ms→0x7F ⇒ luz ON.
> Diff: `/tmp/ukefix/l56-ktz-pwmoff.diff` (patch -p1 --dry-run OK contra k52-L16-tree).

## 1. Cambio (solo drivers/video/backlight/ktz8866.c, +27 líneas)

- En `ktz8866_probe`, tras `ktz8866_init` + dump `post-init`, antes del primer
  `update_status`: RMW de BL_CFG1 (limpia SOLO bit0, conserva resto) + BL_EN 0x3F,
  msleep(50), 0x7F. Más `linux/delay.h` y un `unsigned int cfg1`.
- Punto elegido: lo más temprano sin que el 0x3F de `ktz8866_init` deshaga el re-armo
  (colocarlo tras el regmap parpadearía: init lo apagaría); el update posterior
  (0x7F + brillo, PWM_EN ya 0) mantiene la luz sin parpadeo. Los brillos aún guardan
  el resto del ABL ⇒ réplica exacta del flip en vivo.
- Fallo de I2C ⇒ `dev_warn` y seguir (NO falla el probe): peor caso = L54 (vivo sin
  luz); fallar rompería el enlace panel-backlight (L45). Marcador único `UKE-L56`
  (`dev_info` incondicional: sale incluso si el RMW falla).
- Nada de DT/panel/SMMU/cmdline. Desvío justificado de L53 §5 ("nada de msleep"): el
  msleep(50) ES la receta probada; el probe duerme (I2C) y 50 ms a ~4,2 s despreciables.

## 2. Gates

- Fuente (tras aplicar): `UKE-L56` ×1 (solo el dev_info), `UKE-K53` ×2 (intacto).
- Binario (repack clona `repack-k52L54.py`, Image crudo): `UKE-L56` ×1 (nuevo);
  `UKE-K53` ×1, `UKE-L45` ×1, strings KTZ ×1 c/u, resto de testigos L43–L55 intactos;
  cmdline 632 B idéntica a L54 (display-ON + reclaim + regulator_ignore_unused).
- L56 exige BUILD (cambia fuente; G0 pedirá Image.gz posterior a ktz8866.c), no repack-only.

## 3. Runbook (1 escritura, boot_a; sddm sigue OFF)

1. Build k52L56 (incremental) → repack clon L54 → sha PRE-REGISTRADO en ledger antes de flashear.
2. Cold-boot (restaura UFS del rescate); lector ACM único + netconsole armados.
3. A ~5 s la pantalla queda ENCENDIDA (blanca hasta el commit; sddm off, sin modeset).
4. `modetest -M msm-kms -s 36@85:#0` → patrón iluminado.
5. `live-ktz-pwmoff.py --read-only` → 0x02=0x52 en ambos chips; `dmesg | grep UKE-L56` → 1 por chip.

## 4. Criterio

- PASA = luz desde el probe (blanco pre-commit) + control sysfs 0/apagado/4095 visible.
- FALLA = igual que L54 (display OK sin luz) ⇒ reabre causa física (ENP/ENN/pin PWM).
- Rollback: L54 `1d641e63…` / L53 `c6b64752…`. sddm se reactiva DESPUÉS (escritorio Omarchy).
