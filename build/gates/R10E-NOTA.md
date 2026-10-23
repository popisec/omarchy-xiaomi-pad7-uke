# r10e — la 4ª medida del Delta YA EXISTE (recuperada 28-sep-2026, coste 0)

## Qué es r10e (ledger del hermano, #442, 27-sep ~00:1x)

Pre-registro del hermano para la 4ª medida limpia del Δ con `s248` (MSI sin
armar): guardián de blacklist (reescribe `blacklist-ath11k.conf` cada 0,2 s para
que un reset no deje autocarga fantasma como en #441 §1) + `rmmod` + carga
tardía vía `uke-wifi-trace.sh` (máscara por defecto). Criterios pre-registrados:

- **ÉXITO de la hipótesis** (temporizador): muerte a Δ = 7,2–7,45 s (4/4).
- **HIPÓTESIS MUERTA**: Δ fuera de banda ⇒ volver al acceso concreto.
- **SORPRESA (la mejor)**: sin muerte en 300 s ⇒ `s248` sobrevive con carga
  tardía ⇒ WiFi sin tocar el firmware.

## Lo que encontré (28-sep, solo lectura, sin tablet)

**r10e SE EJECUTÓ** (logs `out/wifi-dmesg-r10e.log` + `out/wifi-trace-pipe-r10e.log`,
26-sep 22:58) **pero nunca se escribió su acta**: el ledger salta de #442
(pre-registro) a #443 (otro tema). Medida recuperada de los logs:

| dato | r10e | patrón r10/r10b/r10c |
|---|---|---|
| inicio probe (t0, `deferred probe timeout`) | 1511,112883 (≈25 min uptime, carga tardía OK) | — |
| `qmi firmware start` | 1518,122829 | — |
| último MMIO trazado (write `0xa380f4←0x42`, **CON retorno** `uke_pcic_w_ret`) | 1518,509807 | puntos distintos cada vez |
| último dmesg (`hal type 4 ring_num 0`) | 1518,510323 (fichero termina ahí, en mitad del burst) | — |
| **Δ = 7,397 s** | **DENTRO de 7,2–7,45** | 7,319 / 7,333 / 7,350 |
| muerte tras `firmware start` | **0,387 s** | 0,388 / 0,382 |
| calibración coldboot | 6,138 s | 6,14 s |
| `failed to load CAL data file: cal-ahb-17110040.qcom,wcn6750.bin (sigo sin cal)` | presente, **no fatal** (sigue a `firmware init done`) | — |

**Veredicto con los criterios de #442: ÉXITO de la hipótesis del temporizador
(4/4 en banda).** La SORPRESA no ocurrió: con carga tardía (pwrseq listo, sin
DEFER) `s248` muere igual ⇒ **no hay camino al WiFi sin tocar el firmware por
esta vía**. El resultado más esperanzador queda cerrado con dato, no con olvido.
Caveat honesto: la muerte se infiere del corte en mitad del burst en AMBAS
capturas (firma idéntica a r10/r10b/r10c); el criterio «sobrevive 300 s» falla
objetivamente (no hay ni una línea posterior a t=1518,5 en ningún fichero).

Efecto sobre las tres hipótesis F3:

1. **Watchdog firmware-TZ (INFERIDA→CORROBORADA 4/4)**: la más fuerte. Δ fijo
   con puntos de muerte distintos + muerte ~0,39 s tras `firmware start` +
   APSS limpio (último acceso con retorno).
2. **Orden MSI-antes-de-base (REFUTADA)**: s247 la probó (#437: 211/211
   retornos, reset inmóvil) y s248 la remató (#441: 0 escrituras MSI, reset
   a 7,33 s). El parche `patches/wlan-msi-orden.diff` es su registro, no un fix.
3. **Falta de `cal-ahb-*.bin` (ABIERTA pero debilitada)**: r10e muestra que sin
   cal se llega a `firmware ready` + rings igualmente; para probarla hay que
   APORTAR el fichero y ver si el reset desaparece (experimento nuevo, no repetición).

## De quién es r10e y si puedo ejecutarlo

**Es SUYO y no puedo ejecutarlo sin su OK.** Pre-registrado por el hermano en
SU ledger (#442), en SU ventana de hardware, con SUS scripts
(`~/gpu-work/ramaa/s21/uke-wifi-trace.sh`), SUS shas (`s248` `825e53d5…`,
fallback stock `19202463…`) y SU presupuesto de slot. Semáforo inter-proyecto
(docs/historia/AGENTS.md) + series separadas (s2xx suyas). Y además **el procedimiento, tal
como está escrito, está caducado**: su paso 3 y su vuelta atrás asumen el
rootfs Ubuntu (`extra/`, `/root/ko-backup-r9`, blacklist en `/etc`), pero
`userdata` ahora es Arch (ledger #444). Re-ejecutarlo exige su OK + revalidar
rutas en Arch + justificación nueva (la pregunta de #442 ya está respondida:
4/4 en banda). Repetirlo sin nada nuevo violaría el techo de 3 ciclos por
hipótesis.

## Acta propuesta (para pegar en SU ledger, no aquí)

> **#445 (propuesta) — RESULTADO r10e (logs 26-sep 22:58, acta diferida)**:
> 4ª medida limpia Δ=7,397 s (banda 7,2–7,45: 4/4), muerte 0,387 s tras
> `firmware start`, cal 6,138 s, último write CON retorno, `cal-ahb-…bin`
> ausente no fatal. Criterio #442: ÉXITO del temporizador; SORPRESA descartada
> (`s248` no sobrevive con carga tardía). Siguiente: watchdog firmware/TZ o
> aportar cal; nada más de MSI.
