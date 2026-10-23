# Índice de pendientes — cierre de sesiones del 22-oct-2026

El dueño cerró todas las subsesiones. Cada una dejó sus pendientes por escrito y commiteados. Este índice es solo el mapa; el detalle está en cada fichero.

## Estado de la tablet al cierre (22-oct, ~02:20)

- Kernel `7.2.9-senemos.1.4054.3-ouke7` en slot `_a`, `Successful 1` (el v7 se flasheo el 22-oct 23:55, ledger #675; antes corria el v6 = `...-ouke5`). `uke-boot-ok.service` lo vuelve a marcar 90 s después de cada arranque sano (commit 5e79ffd).
- Userland actualizado: systemd 262.1, Qt 6.12, quickshell 0.3.2.r7-1, omarchy 4.0.6. Reinicio de verificación en verde.
- `/etc/pacman.d/uke-hold.conf`: IgnorePkg de `linux-aarch64 linux-firmware* mesa quickshell`. **No ejecutar** `omarchy-upgrade-to-quattro`, `omarchy refresh pacman`, `omarchy-reinstall-pkgs` ni `pacman -S` explícito de mesa o del kernel.
- Las 14 migraciones de Omarchy están marcadas como hechas sin ejecutarse.
- El micro está en la variante «siempre abierto» (`/etc/pipewire/pipewire.conf.d/51-uke-mic.conf`), con su coste de batería sin medir.
- Tailscale ya va en **modo TUN** desde el v7: la tablet alcanza los equipos 100.x. Antes (con el v6) seguia en userspace-networking y no llegaba a la tailnet.

## Ficheros de pendientes

| Área | Fichero | Commit |
|---|---|---|
| Audio | `docs/historia/revision/PENDIENTES-AUDIO-20261022.md` | 4367298 |
| Optimización (incluye batería y kernel v7 #675) | `docs/historia/revision/PENDIENTES-OPTIMIZACION-20261022.md` | 71abff2 |
| Batería (absorbido por optimización) | `docs/historia/revision/PENDIENTES-BATERIA-20261022.md` | e559e2d |
| Apps de la tablet, -Syu y reglas de pacman | `docs/historia/revision/PENDIENTES-APPS-20261022.md` | ef00863 |
| Super Productivity nativo | `docs/historia/revision/PENDIENTES-SP-NATIVO-20261022.md` | bbf3368 |
| Immich nativo | `~/proyectos/immich-nativo/PENDIENTES.md` | (repo propio) |
| App de apuntes | `~/proyectos/notas-nativas/PENDIENTES.md` | f6db5e4 (repo propio) |
| Cámaras y vibración | `build/gates/revision/PENDIENTES-CAMARAS-20261022.md` | c949198 (lo continúa una sesión nueva de cámaras) |

## Lo que bloquea a varias áreas

1. ~~**Kernel v7**~~ **HECHO** (ledger #675, flasheado el 22-oct 23:55). Desbloquea Tailscale TUN, con lo que la tablet llega a Nextcloud, Immich, Navidrome, Jellyfin, Kavita y Token Spy, y la sync de apuntes. Pasos en PENDIENTES-OPTIMIZACION §1.
2. **Medidas sin cable** (el dueño tiene que desenchufar la tablet): el coste del micro siempre abierto, s2idle, drenaje con uso real y refresco en batería.
3. **Instalar las apps nativas en la tablet** (Immich, sp-nativo, notas): cada una con turno de tablet y orden del dueño. Los scripts de instalación están sin probar.

## Decisiones abiertas del dueño

- La orden de flashear v7 (fastboot a mano y cargador de pared).
- sp-nativo o sp-web.
- Credenciales y modelo de Token Spy (la IA de apuntes) y pruebas reales de Immich/SP contra los servidores.
- Activar el plugin Navidrome (necesita `qt6-multimedia`) o usar Strawberry.
- Si el micro sigue siempre abierto, tras medir su coste.
- Regenerar las claves SSH de host de la tablet (las antiguas están en el historial de git).

## Reglas de coordinación que siguen vigentes

- Una sola sesión usa la tablet a la vez.
- Ledger antes de cualquier flash.
- Nada de binarios del fabricante en git.
- Las credenciales van solo en `~/.config` con modo 600.
