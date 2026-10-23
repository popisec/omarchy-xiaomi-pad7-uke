# Plan integrado de optimización (fusión con la sesión batería) — 22-oct-2026

Base: `docs/historia/revision/OPTIMIZACION-20261020.md` (hecho + medido), `docs/historia/revision/OPTIMIZACION-KERNEL-PROPUESTA-20261021.md` (kernel), `docs/historia/revision/PENDIENTES-BATERIA-20261022.md` (traspaso de batería, commit `e559e2d`). Este fichero solo ordena lo pendiente; **no se ha tocado la tablet** al escribirlo (es de cámaras, ciclo 11).

## Estado
| Área | Estado |
|---|---|
| Userspace seguro (journald 150M, coredump, THP madvise, homed off, rtkit, plugins de barra, uke-fix) | HECHO y medido (journal 746→149 MB, `/` 89→81 %) |
| Disco: fsck + ampliar `/` | HECHO: 7,9 G → 105 G, fs `clean` |
| Perfiles de batería/refresco/ICL/modo carga (desplegados por la sesión batería) | activos; ver `deploy/bateria/` |
| Kernel v7 (v6 + zram + teo + audit=0 + nftables) | construido, `--check` OK, ledger **#675 pendiente de orden del dueño** (con gate de slot `qbootctl`) |

## Pendientes heredados de batería, integrados (por dependencia)
| # | Pendiente | Necesita | Cuándo / con qué |
|---|---|---|---|
| B1 | Probar `uke-refresco` en batería real (60 Hz sin cargador, 120 Hz con) | desenchufar (dueño) + turno de tablet | junto a B2; lectura + 1 cambio visible |
| B2 | Drenaje con uso real y larga duración (`carga-rapida/medir-linux-descarga.sh`, filtrar `estado=Discharging`) | dueño desenchufa; tablet libre 1–2 h | tras v7 y la prueba de cámaras, para no mezclar causas |
| B3 | s2idle sin cable (`event=resume`, Δ`charge_uah`), `modprobe qcom_stats` | dueño: desenchufar y autorizar `qcom_stats`; coordinar con BT (gancho `uke-bt-sleep`, IRQ 229) | medir **antes y después de v7** (teo cambia cpuidle) |
| B4 | Carga rápida completa (`medir-linux-carga-rapida.sh 180`) | batería <80 %, cargador de pared | independiente |
| B5 | Modo carga: `pureason` de un encendido normal | un reinicio por botón (dueño) | oportunista |
| B6 | Referencias Android sin medir (descarga limpia, carga rápida) | tablet en Android (otra ida a Android = decisión del dueño) | baja prioridad: el «1,4 W de Android» sigue sin fuente |
| B7 | WiFi/NM caído 21-oct 23:52 (`NetworkManager is not running`, Tailscale offline por USB) | solo lectura del journal de ese boot (`journalctl -b -1`) | **primer paso barato** al tener turno; posible relación con reinicios/pruebas de audio de esa hora |

## Decisiones de DT/kernel que se solapan con v7
- **Ya en v7**: `cpuidle.governor=teo`, `audit=0`, zram, nftables/TUN. `rcu_expedited`: sin efecto medible, no se toca.
- **Siguiente ciclo (v8), solo con orden**: `fw_devlink.sync_state=timeout deferred_probe_timeout=30` (0,1–0,4 W; riesgo medio de pantalla/GPU) y, aparte, `usb-psy-name` + `MaxPower` del gadget (carga por USB; puede retrasar el SSH por USB) — uno por flash, techo de 3 ciclos por hipótesis.
- **No viable/alto riesgo**: quitar `*_ignore_unused` (de uno en uno, solo con orden expresa); apagado real sin que el cargador encienda (`PON-CARGADOR-VIABILIDAD`); `mem_sleep=deep` (sin watchdog, R-42).
- Efecto esperado de v7 en consumo: pequeño (≤0,05 W por teo); la ganancia grande sigue siendo el sondeo del táctil (0,2–0,5 W, sesión táctil) y los tiempos de hypridle (decisión del dueño). Medir B3/B2 antes y después para no atribuir mal.

## Secuencia propuesta (todo con turno de tablet y orden del dueño)
1. Con turno corto y solo lectura: B7 (`journalctl -b -1`) y `--pre` de v7 (deja tarball y copia de módulos; no toca `/lib/modules`).
2. Dueño pone fastboot → flash v7 (#675) → `--post` → `--post-modules` → comprobar `Successful 1` (qbootctl). Cámaras prueba su pila sobre v7.
3. Dueño desenchufa: B1+B3 (s2idle) y B2 (drenaje) sobre v7; comparar con la referencia 21-oct (3,88 %/h; pantalla 1,97 W, DPMS off 0,93 W).
4. Si v7 PASA y hay margen: v8 con `sync_state=timeout`.
