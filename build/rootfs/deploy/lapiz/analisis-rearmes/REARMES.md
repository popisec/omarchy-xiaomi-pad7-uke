# Rearmes del modo lápiz (NT36532): correlación con BLE/frames y parche mínimo

Fecha de análisis: 21-oct-2026, solo con logs del 20-oct (sin tablet). Reloj monotónico común a `touchd-pen.log`, `ble.log` y `evmon.log`.
Fuente: `build/android/lapiz-20261019/linux/sesion-20261020{b,c,d}/*`, `sesion-20261020-d/ultima`, `sesion-20261020/*`.
Scripts reproducibles en esta carpeta: `correlar.py`, `rafagas.py`, `tablas.py`, `latencia.py` (salidas `out-*.txt`).

## 1. Hechos medidos

**Los «desactivar/activar» NO son azar ni los provoca el demonio: siguen al hall.** En las 7 sesiones con log, 47 de 47 «activar» y 45 de 47 «desactivar»
llegan <0,6 s después de un cambio de `attached` por BLE (`out-tablas.txt`). Las sesiones 144206 y 145932 son pegar/despegar repetido (30 y 52 cambios de hall,
mediana 3-5 s por estado, 3 y 5 estados <1 s): ahí salen la mayoría de ciclos. Ninguna ráfaga de presión (>=5 muestras) empezó con el hall en «pegado» (0 de 41).

**Rearmes reales** (líneas `rearme N (presion BLE …)`; las 26/30 que cuenta `grep rearme` incluyen `rearmes=` de las líneas de estadísticas): **8 en 4 sesiones**.

| Sesión | t (s) | presión | hasta cuándo no había BLE | enable previo | contexto |
|---|---|---|---|---|---|
| 144206 | 8162.470 | 4441 | hueco BLE 8145.1→8162.37 (17 s) | 8136.0 | volcado de 1024 muestras en 0,27 s + tormenta de botones; `attached true` a +2,1 s |
| 145504 | 8416.195 | 543 | hueco 8376.3→8416.12 (40 s) | 8360.0 | volcado 354 muestras en 0,1 s; `attached true` a +0,11 s |
| 145932 | 8807.817 | 1084 | hueco 8787.2→8807.75 (21 s) | 8772.1 | volcado 401 muestras en 0,15 s; `attached true` a +0,14 s |
| ultima | 9512.290 | 1231 | hueco 9462.0→9512.18 (50 s) | 9439.9 | volcado 684 muestras en 0,29 s; `attached true` a +0,26 s (se ignoró por ACTIVITY_S → desactivar a +1,96 s) |
| 145932 | 8772.608 | 1477 | — | **8772.061 (+0,55 s)** | 1.ª muestra de presión a 8772.476; 1.er frame del chip a 8773.166 (+0,69 s desde la presión) |
| 145932 | 8891.959 | 847 | — | 8885.588 | ráfaga de 11 muestras (0,10 s), máx 5129; el rearme cae a +0,1 s del inicio |
| 145932 | 8964.309 | 108 | — | 8959.245 | ráfaga 0,88 s, máx 327; rearme a +0,1 s |
| 145932 | 8965.909 | 119 | — | (rearme 4) | ráfaga 0,77 s, máx 235 |

- 4/8 son **artefactos de un parón del cliente BLE**: `uke_lapiz_ble` deja de entregar 17-80 s (mismo fenómeno en 8 huecos >2,6 s de `ble.log`), y al volver
  vuelca toda la presión/botones atrasados de golpe. El demonio los lee con su `now` actual, ve `pressure>0` y `last_pen` viejo (>0,3 s) y rearma, con el lápiz ya pegado
  (el aviso de hall llega 0,1-2 s después y se desactiva).
- 1/8 llega 0,55 s después del `enable` (se rearma el chip antes de darle tiempo; la condición mide `REARM_AFTER` desde el último frame, no desde el último enable).
- 3/8 son el 1.er informe de una ráfaga corta/débil (0,8-1 s, <=330 salvo una de 11 muestras) cuyo propio inicio dispara el rearme.
- 0/8 ocurren «al levantar», «al pasar a hover» ni «tras un parón de presión» dentro de un trazo continuo: en las ventanas de dibujo continuo (144206 8091-8145; 145932 8772-8787)
  no hay rearmes. Latencia presión→frames medida en `evmon` (`out-latencia.txt`): 0,00-0,09 s en 5 de 6 arranques en frío; la excepción (+0,69 s) es justo tras un enable.
- Tras ningún rearme se ve que reaparezcan frames: el contador `frames0x509` queda congelado (2807, 2557, 3620, 1697) porque el lápiz se pega enseguida o no hay más trazos.
  **No hay ningún caso documentado de «el chip salió del modo lápiz» confirmado por frames**.

## 2. ¿Lo provoca el demonio?

Sí, en parte (7/8): `PenRuntime.tick` rearma con `sess.pressure>0 and now-last_pen>REARM_AFTER(0.3)`, sin exigir que la presión sea sostenida ni que el enable sea antiguo.
`REARM_AFTER=0.3` es menor que la latencia observada tras un enable (0,69 s). El rearme reenvía `[BF 04 00 01 00]`+`[7B 01]`, que Android solo manda en flancos
(`update_pen_status`: `enable != enable_last_time` o `enforce`).
`ACTIVITY_S` no genera rearmes, solo retrasa 1,5 s el desactivar cuando el hall llega pegado justo tras un volcado (1 caso, `ultima`). No se vio «disable por hall espurio y enable inmediato»:
los pares disable→enable <1 s (8885.276→8885.588, 9439.824→9439.914, 8026.098→8026.188) siguen a flaps reales de hall de 0,2-0,3 s.

## 3. Driver Android (decompilado)

- `update_pen_status` (0x15a788) se dispara **solo por eventos**: resume/recovery (enforce), `pen_charge_connect` (`nvt_pen_charge_state_change_work`→`update_pen_status(0)`),
  conexión del lápiz (modo 20), gamemode/whitelist. `enable = bluetooth && !charge && (whitelist || !gamemode)`; si `enable==last` y no enforce no escribe `stylus_enable`;
  con enable siempre reescribe `pen_switch(id)`. **No hay temporizador ni rearme por presión/ausencia de frames** (RE-CHIP-MODO-LAPIZ §1-2, §5).
- `report_release_pen_event` solo pone a 0 los ejes del input (no toca el chip); `nvt_ic_switch_mode` solo gestos.
- Lo que Android sí hace periódicamente y Linux no (por defecto): `op_mode=2` + `idle_baseline` cada 0,25-6 s (`LAPIZ_OPMODE=1` lo activa; no probado en sesión real).
  Es el único candidato a «temporizador que atiende Android» (HAL: doze mode también, no disponible) — **hipótesis, sin evidencia en estos logs**.

## 4. Parche (cambio mínimo): `rearmes-sostenidos.patch`

`PenSession.press_since` (instante en que la presión BLE pasa de 0 a >0; None con 0 o BLE caído) y `REARM_PRESS_S=1.0`: el rearme exige además
`now - max(press_since, last_try, last_rearm) >= 1,0 s`. Efecto sobre los 8 casos: los 4 volcados acaban en presión 0 (no rearman), el de +0,55 s del enable y los 3 de ráfagas <1 s
tampoco. Un lápiz que de verdad presiona >1 s sin frames sí se rearma (el test existente `test_rearm_when_pressure_without_frames` sigue pasando sin cambios).
Test nuevo `test_no_rearm_for_stale_backlog_or_fresh_enable` (falla sin el cambio). Verificado en copia de `deploy/lapiz`+`tactil`: `patch -p1 --dry-run` limpio
(desde `build/rootfs/deploy/lapiz`) y `PYTHONPATH=. python3 -W error -m unittest test_touchd_pen_smoke test_uke_lapiz_ble test_uke_pen test_lapiz` → OK (skipped=4); el test nuevo falla con el `uke_pen.py` actual.
Nada instalado ni editado en `uke_pen.py`.

## 5. Qué NO se pudo concluir

- Si alguna vez el chip sale **realmente** del modo lápiz: `evmon.log` solo cubre 7-125 s por sesión (empieza con el primer evento) y no hay log de frames por IRQ; la correlación
  con frames se hace por los contadores cada 30 s. El «unas 3 veces por sesión» del informe del usuario no se pudo asociar a un fallo del chip: los rearmes vistos tienen explicación en BLE/demonio.
- Que el rearme sirva: sin frames posteriores medibles. El parche lo conserva para presión sostenida.
- Causa del parón de 17-80 s del cliente BLE (no investigada; fuera del alcance, es lo que genera los volcados). Un fix de raíz sería marcar con tiempo de origen cada mensaje de `uke_lapiz_ble` y que el demonio descarte los viejos.
- Si `LAPIZ_OPMODE=1` (op_mode/idle_baseline periódicos como Android) reduce fallos reales: requiere sesión en tablet.
