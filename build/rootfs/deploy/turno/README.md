# Turno de la tablet entre sesiones (22-oct-2026; dos recursos desde las 22:05)

Hay varias sesiones trabajando a la vez y sin gestora (de noche). Antes de **escribir o cargar** algo en la tablet (pacman, insmod/rmmod, instalar ficheros, reiniciar servicios), cada sesión pide turno, y lo suelta al terminar:

```bash
build/rootfs/deploy/turno/uke-turno pedir <sesion> "<qué>" [espera_s]   # espera hasta conseguirlo (30 min por defecto)
build/rootfs/deploy/turno/uke-turno soltar <sesion>
build/rootfs/deploy/turno/uke-turno estado
```

- El cerrojo es `/run/uke-turno.d` en la tablet: `mkdir` es atómico y el cerrojo desaparece al reiniciar.
- Las lecturas (journalctl, ps, cat, capturas de pantalla) no necesitan turno.
- Un turno de más de 45 min se da por abandonado: `pedir --forzar` lo rompe.
- Si Tailscale falla, se usa `UKE_HOST=root@192.168.42.129` (USB).
- Nunca se reinicia la tablet de noche: nadie puede hacer el reset físico.

Probado el 22-oct a las 03:31: pedir, pedir ocupado, soltar ajeno y soltar.

## Dos recursos (22-oct, 22:05): trabajar en paralelo
Hay dos cerrojos independientes. Pide solo el que necesites:
- `--recurso pantalla`: toques sintéticos, capturas, abrir y cerrar apps en la sesión gráfica, reiniciar la shell o sddm.
- `--recurso sistema`: pacman, insmod/rmmod, servicios del sistema, suspender y medidas de batería.

Sin `--recurso` se piden los dos (turno exclusivo, como antes). Ejemplos:
- Una sesión instala con pacman (sistema) mientras otra prueba su app con el dedo (pantalla).
- Cámaras carga módulos (sistema) mientras plugins prueba la barra (pantalla).

Transición: el cerrojo antiguo `/run/uke-turno.d` bloquea ambos recursos hasta que su dueño lo suelta (`soltar` lo borra).
