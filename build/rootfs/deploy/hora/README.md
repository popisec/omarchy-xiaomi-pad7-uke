# Hora correcta sin red (19-oct-2026)

**Problema** (medido): la tablet iba 6 h 13 min atrasada (16:14 frente a 22:27). El RTC de la PMIC (`rtc-pm8xxx`, pmk8550) marca 1970
porque Qualcomm no deja escribirlo desde Linux; `fake-hwclock` no tenía fichero; chrony no tenía red (la WiFi del dueño fuera de alcance),
así que cada arranque partía de una hora antigua. El RTC SÍ corre siempre (avanzó lo mismo que el uptime, suspensiones incluidas).

**Arreglo** (como Android): guardar el desfase `hora_real − RTC` en `/var/lib/uke/rtc-offset` y aplicarlo al arrancar.
- `uke-rtc-offset.service`: lo arranca **udev al aparecer rtc0** (`90-uke-rtc-offset.rules`): `restore`; `save` al apagar.
  `rtc-pm8xxx` se carga por `modules-load.d/uke-rtc.conf` (en ouke5 no se autocargaba). Ojo: al registrarse, HCTOSYS pone el
  reloj a 1970 y justo después udev restaura la hora.
- **Corrección 19-oct 23:16** (arranque ouke5): la primera versión colgaba de `dev-rtc0.device`, que no existe sin TAG systemd:
  el servicio corría antes del RTC (no restauraba) y systemd esperó 90 s a `/dev/rtc0` en el arranque.
- `uke-rtc-offset-save.timer`: guarda cada 30 min (recoge las correcciones de chrony cuando hay red). Solo guarda si la hora es
  fiable: NTP sincronizado, ya derivada del desfase, o `save --force` tras ponerla a mano.
- chrony: `makestep 1.0 -1` (antes `1.0 3`) para corregir saltos tras suspensiones largas en cualquier momento.

Puesta en hora inicial: desde el PC, `date -s @<epoch del PC>` + `uke-rtc-offset save --force` (19-oct 22:30:05, PC 22:30:06).
Desplegar: `tar cf - -C root --exclude=. ...` (¡no extraer la entrada `.` sobre `/`!) o copiar ficheros; `systemctl enable --now
uke-rtc-offset.service uke-rtc-offset-save.timer`. Revertir: `systemctl disable uke-rtc-offset.service uke-rtc-offset-save.timer`,
borrar los ficheros y `/var/lib/uke/rtc-offset`, restaurar `/root/chrony.conf.bak-hora`.
Verificado a mano (udev trigger + modprobe): hora restaurada 23:16:47 (PC 23:16:48). **Pendiente**: el próximo arranque en frío.
