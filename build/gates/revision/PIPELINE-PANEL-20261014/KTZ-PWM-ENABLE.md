# KTZ8866: PWM_ENABLE escondido — por qué los registros «idénticos» y sin luz (14-oct-2026)

> Destilado de: docs/historia/revision/PIPELINE-PANEL-20261014/ANDROID-CAMINO-COMPLETO.md + docs/historia/revision/PIPELINE-PANEL-20261014/NUESTRO-CAMINO-COMPLETO.md (14-oct) + datasheet
> KTZ8866 rev 04b + volcados UKE-K53 (L53/L54). Hipótesis central marcada.

## 1. El dato que faltaba: el volcado L53 decodificado con el mapa del datasheet

Regs 0x00–0x10 capturados (netconsole L53, t=231 s; «probe-entry» = estado del ABL, idéntico):

```
0x00=00 0x01=21 0x02=53 0x03=cd 0x04=00 0x05=a6 0x06=00 0x07=00
0x08=7f 0x09=9f 0x0a=11 0x0b=00 0x0c=32 0x0d=24 0x0e=28 0x0f=00 0x10=80
```

Mapa (datasheet KTZ8866, tabla 5; kinet-ic.com/uploads/KTZ8866-04b.pdf):

| Reg | Nombre | Valor | Lectura |
|---|---|---|---|
| 0x01 | DEVICE_ID | 0x21 | OK (00100xxx) |
| 0x02 | BL_CFG1 | **0x53** | **bit0 = PWM_ENABLE = 1 ⇒ modo «I2C × PWM»** |
| 0x03 | BL_CFG2 | 0xcd | config vendor |
| 0x04/0x05 | BL_BRT | 00/a6 | código 11-bit 0x530 |
| 0x08 | BL_EN | 0x7f | bit6=1 enable + sinks 0x3f ✅ |
| 0x09 | BIAS_CFG1 | 0x9f | bias ON ✅ |
| 0x0d/0x0e | OUTP/OUTN | 24/28 | ±5.8 V aprox ✅ |
| 0x0f | FLAG | 0x00 | sin fallos ✅ |
| 0x10 | BL_OPTION1 | 0x80 | bits[6:1]=0 (sin DISABLEs) ✅ |

## 2. La tabla de enable del datasheet (citada textual)

Filas relevantes (columnas: HWEN | BL_EN 0x08[6] | PWM INPUT | BRILLO | SINKS 0x08[5:0] |
PWM_EN 0x02[0] | DISABLEs 0x10[6:1] | MAPPING):

- `1 1 Duty=0 X ≥000001 1 <111111 X` → **Standby 7**
- `1 1 X ≥0x001 ≥000001 0 <111111` (0=Exp/1=Lin) → **«Backlight boost enabled - Selected
  current sink(s) enabled - I2C control only»**

Y: «**The KTZ8866 PWM timeout feature turns off the boost output when the PWM is enabled and
there is no PWM pulse detected.**» + pin D2 PWM: «300 kΩ pull-down resistor at this pin to GND».

⇒ **HIPÓTESIS CENTRAL (alta confianza):** nuestro estado = HWEN=1 (regs nunca reseteados ⇒ HWEN
jamás togado, nota vieja: «HWEN lo deja asertado el bootloader»), BL_EN=1, brilla 0x530,
sinks ON, **PWM_EN=1** y el pin PWM a duty 0 (nadie lo maneja en Linux) ⇒ **Standby: boost OFF**.
El ABL SÍ enciende porque genera los pulsos PWM (o su init deja el pin activo) — al handoff,
cesan ⇒ timeout ⇒ **luz muerta con registros «idénticos»**. Es exactamente el eslabón que el
regmap no podía ver.

## 3. Por qué no lo vimos antes

- El instrumento L53 solo volcaba 0x00–0x10 y los registros son idénticos ABL↔nosotros: la
  diferencia NO está en valores de registro sino en un **estado dependiente de un pin externo**
  (duty PWM). FLAG=0 (sin fault) imposible de distinguir de un standby limpio.
- La vieja nota #618 («sysfs→I2C→KTZ→LEDs verificado») verificaba los **registros**, no la luz:
  con duty=0 el standby mantenía los LEDs apagados.

## 4. Fix

- **En vivo (ahora, sin flash):** `live-ktz-pwmoff.py` → 0x02 bit0=0 (I2C Only Mode) + re-armar
  0x08. Esperado: luz al código I2C actual (0x530).
- **Kernel (L56):** en `ktz8866.c`, tras probe/enable, limpiar BL_CFG1 bit0 (read-modify-write)
  + marcador `UKE-L56`. La vuelta a PWM (CABC) queda como mejora futura opcional (requiere el
  driver PWM del pin, no existe en el árbol).

## 5. Cautelas

- La prueba en vivo solo escribe 0x02[0], 0x08 y (opcional) 0x04/0x05; un reboot restaura.
- Si el modo I2C-only NO enciende: la hipótesis cae y toca mirar ENP/ENN/AVDD/pin real del PWM
  (pero las tres filas del datasheet apuntan al Standby-por-duty-0).

## 6. CONFIRMADO EN VIVO (14-oct-2026 ~12:10, sin flash)

- Volcado previo íntegro 0x00–0x15: `00 21 53 cd 00 a6 00 00 7f 9f 11 00 32 24 28 00 80 77 00 00 44 d9`
  con **0x12/0x13 = 00 00 → duty PWM = 0** (el chip confirma que nadie le da pulsos).
- Flip en vivo `0x02: 0x53 → 0x52` (PWM_EN=0) + re-armo `0x08 3f→7f` → **dueño: «SE ENCENDIO»**.
- Control sysfs verificado: `2-0011` 307→0 (apagado)→4095→2048; dueño: «ahora está con más brillo».
- Commit de vídeo con el bit intacto: `update-in 00 21 52 cd 00 f4 ...` (código 0x7a0 = remap(2048)),
  `K47-atom-tail`×3 (pipeline K47 completo). El bit 0x52 persiste (nuestro driver nunca escribe 0x02).
- Herramienta: `build/gates/live-ktz-pwmoff.py` (flip/re-armo/--read-only). Evidencia en el hilo de
  sesión; commit `95f8e30` + `6e33530`.
