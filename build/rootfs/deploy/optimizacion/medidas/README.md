# Scripts de medida del plan integrado (22-oct-2026) — PREPARADOS Y PROBADOS EN SECO, NO EJECUTADOS en la tablet

Todos se lanzan desde el PC. Los que escriben o necesitan que la tablet esté quieta exigen `UKE_TURNO=1` (turno concedido con «pido tablet»). Prueba en seco (ssh y sysfs falsos, sin tablet): `bash selftest.sh` → **29 PASA / 0 FALLA**.

| Pendiente | Script | Gates | Escribe en la tablet | Revert |
|---|---|---|---|---|
| B3 s2idle sin cable | `medir-s2idle.sh arm [s]`, `status`, `report` | turno, Discharging ≥30 %, `mem_sleep=s2idle`, gancho `uke-bt-sleep`, 300–7200 s; **desenchufar a mano antes** | `/root/uke-s2idle-run.sh`, unidad `uke-s2idle-run`, `/var/log/uke-bateria/s2idle-medidas.csv`, alarma RTC | `revert` |
| B2 drenaje uso real | `medir-drenaje-uso.sh start|stop|report` | turno, Discharging ≥30 % | `/var/lib/uke-bateria/marcas-uso.csv` (2 líneas) | `revert` |
| B4 carga rápida | `medir-carga-rapida.sh run [s]` | turno, <80 %, cargador conectado, por Tailscale (no por el USB del PC) | nada (solo lectura) | — |
| B1 refresco en batería | `probar-refresco-bateria.sh run [s]` | turno; el dueño enchufa/desenchufa en la ventana | nada (solo lectura) | `revert` = `uke-refresco auto` |
| M1 coste del «micro siempre abierto» (audio, `51-uke-mic.conf`) | `medir-mic-ab.sh run [s]` (A B A B, DPMS off) | turno, Discharging ≥40 % (aborta <25 %), `mic-abierta.sh` presente; restaura SIEMPRE el estado inicial | `51-uke-mic.conf` vía `mic-abierta.sh --go/--revert` + reinicio de pipewire/wireplumber del usuario (corta el audio unos segundos) | `revert` |
| B7 WiFi caído | `leer-journal-wifi.sh run [-1]` | ninguno (solo lectura) | nada | — |

`report` del drenaje reproduce con los datos reales del 21-oct el tramo de 1,08 h: **100 → 95,81 % = 3,88 %/h** (coincide con `PENDIENTES-BATERIA`). El runner de s2idle usa `systemctl suspend` (pasa por los ganchos `system-sleep`, como en uso real) y `rtcwake -m no` para la alarma; en la prueba en seco se sustituyen por stubs.
Medir s2idle y drenaje **antes y después de v7** (cpuidle `teo`) para no atribuir mal el efecto.

Coste del micro: si ΔW > 0,05 W (~0,14 %/h con ~34,5 Wh) el script propone dejar la base; con pantalla encendida el delta es el mismo (ADC/bias), y en suspensión se mide con `medir-s2idle.sh` en cada estado (`MIC_S2IDLE`).
