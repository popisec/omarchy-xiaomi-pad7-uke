# CRÍTICA L56 — PWM_ENABLE off en probe KTZ8866 (14-oct-2026)

Veredicto: **PASA flashear L56** (sin bloqueantes; 2 correcciones menores opcionales abajo).

## 1. Diff (51 líneas, `patch -p1 --dry-run` = 0, verificado en copia `/tmp`)

- Hunks anclan en código real: `ktz8866.c:510` probe, `568` init, `571-572`
  set_clientdata+update — el punto elegido existe y el orden es el declarado.
- `ktz8866_init` (`474-487`) escribe 0x08=0x3F (sinks, bit6=0) ⇒ el re-armo
  DESPUÉS es obligatorio; antes sería deshecho. Correcto.
- RMW `cfg1 & ~BIT(0)`: conserva bits 7:1 (0x53→0x52). `BIT()` ya se usaba
  (`88,484,487`) ⇒ sin riesgo de include nuevo; `delay.h` añadido para `msleep`.
- `msleep(50)` legal: probe es contexto sleepable (ya hace I2C). 2 chips ≈100 ms.
- Sin parpadeo visible: a ~4,2 s aún no hay luz; el `update_status` posterior
  (`432-436`, `led_on=false`→ escribe 0x7F + brillo) mantiene lo re-armado.
- Helper correcto: no existe `ktz8866_read`; `regmap_read` directo = lo que usa
  `uke_ktz_dump` (`389`). `BL_CFG1` solo se escribe aquí (grep: solo define `68`).

## 2. Fail/warn — aceptable

- Warn-y-seguir es lo correcto: fallar el probe rompería el enlace
  panel→backlight (L45) y el peor caso es L54 (vivo sin luz). `dev_info`
  incondicional ⇒ marcador forense incluso si el RMW falla.

## 3. Gates — robustos

- Fuente: `UKE-L56` ×1 real (solo el `dev_info`; comentario y warns usan `L56:`
  sin prefijo ⇒ sin falsos conteos). `UKE-K53` ×2 intacto (verificado: 2 hoy).
- Repack clon L54 + `UKE-L56`×1 en Image crudo + cmdline 632 B (L54 §4) + BUILD
  obligatorio (cambia fuente): suficiente y declarado.

## 4. Riesgos — no rompe lo que funciona

- Solo toca probe del KTZ (I2C backlight); DSI/panel/SMMU/cmdline intactos.
- CABC: no existe driver del pin PWM (KTZ-PWM-ENABLE §4) ⇒ I2C-only es la única
  vía; sysfs 0..4095 probado en vivo (307→0→4095→2048). 2.º KTZ: cada probe
  aplica el fix a su chip ⇒ superconjunto del flip vivo. Bit0=1 nunca deseable
  sin pulsos PWM (datasheet: timeout→boost OFF).

## 5. Criterio/runbook/rollback — completos

- PASA (luz ~5 s + sysfs) / FALLA (=L54, reabre ENP/ENN) bien definidos.
- Rollback L54 `1d641e63…`/L53 `c6b64752…` + cold boot. Gates vivos presentes:
  `live-ktz-pwmoff.py --read-only` (existe, 3829 B) + `dmesg | grep UKE-L56`.

## 6. Correcciones (menores, no bloquean)

1. (log) `rc=%d` refleja solo el RMW: si el RMW va bien pero un `BL_EN`
   falla, imprime rc=0. Opcional: guardar `int bl_en_rc` y loguearlo.
2. (runbook §5) precisar: `grep -c UKE-L56` → **2** (1 por chip, dos probes).
