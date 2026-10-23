# MAÑANA (14-oct por la mañana) — qué hacer con la tablet

> Escrito la noche del 13/14-oct. El pipeline de subagentes trabaja toda la noche.

## Estado de la tablet (dejada por el dueño)

- **Arrancada con L45** (`83647c45…`) + **dtbo s286** (`33d153f2…`), **cargando** por USB
  (la ventana de fastboot de las 00:35 se usó solo para leer: batería 3682 mV, retries a=6/b=6 —
  **cero escrituras**; se reinició a L45 para que cargue durante la noche).
- Lector ACM armado (`out/acm-overnight.log`, hasta ~11:36).
- Rollbacks: L44 `13c9454d…`, L43 `5a6d1dee…`, L19 `71d89ca6…`.

## Lo que hay que hacer por la mañana (dueño)

1. Mirar el informe de la noche: `docs/historia/revision/PIPELINE-PANEL-20261014/MANANA.md`
   (se actualiza al acabar el pipeline) y `docs/historia/revision/PIPELINE-PANEL-20261014/FINAL-INTEGRACION.md`.
2. **Poner la tablet en fastboot** (Power+Vol-; el dueño, no el agente) cuando el informe diga
   «build listo»: el agente flashea la imagen integrada (pre-registrada en el ledger) y verifica
   por SSH/ACM.
3. Si el informe dice «sin build» (pipeline sin consenso), la tablet se queda en L45 y se decide
   el siguiente ciclo con la escalera de `AUDITORIA-METODO-20261013.md` §3.

## Regla de batería

- No dejar la tablet en fastboot más de lo imprescindible (no carga; ~12–16 mV/min). El flash de
  la mañana debe ser: fastboot → flash → `set_active a` → reboot → verificar.
