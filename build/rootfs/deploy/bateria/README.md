# bateria — % exacto, perfiles de energía, log (19-oct-2026)

**Estado: DESPLEGADO el 19-oct-2026** (servicios `uke-perfil` y `uke-bateria-log` activos y habilitados, widget `uke.bateria` en la barra). Pendiente: medir consumo real en descarga.

- `uke-bateria-lectura` — % exacto = `charge_counter/charge_full` (flag `ok` si difiere de `capacity` >1,5 pt), V, I, W (media de 4 muestras), tiempo estimado desde `charge_counter`/I. Signo: + = descarga.
- `uke-perfil get|list|status|set|cycle|apply|apply-user|medir` — Ahorro/Equilibrado/Rendimiento (= power-saver/balanced/performance de Omarchy). Valores en `/etc/uke/perfiles.conf`. Persistencia: `/var/lib/uke-bateria/perfil` + `uke-perfil.service` (root: governor, freq máx por clúster, GPU devfreq) + autostart Hyprland (`apply-user`: refresco 60/90/120 Hz y tope de brillo).
- `powerprofilesctl` (shim en /usr/local/bin): no hay power-profiles-daemon; así `omarchy-powerprofiles-*` y el panel Power de Omarchy funcionan.
- `uke-bateria-log` (servicio, cada 60 s) → `/var/log/uke-bateria/AAAA-MM-DD.csv`; filas `start`/`resume` (tiempo suspendido); rotación propia (gzip >2 d, borra >60 d; no hay logrotate).
- `uke-bateria-informe [días]` — W por perfil y por hora, procesos con más CPU-segundos, IRQ más activas, drenaje en suspensión.
- Widget de barra `plugin/uke.bateria` (icono de perfil + %.1f + W; clic = siguiente perfil; tooltip con estado y tiempo).

`./deploy.sh check|apply|revert|status|informe`. `revert` restaura governor performance y freq máx originales.
Medir consumo por perfil: `uke-perfil medir 90` en la tablet **desconectada del cargador** (por USB/SSH no se puede medir descarga).
