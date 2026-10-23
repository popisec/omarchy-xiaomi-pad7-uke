# resto-apps — **fuera del objetivo del port**

> Este directorio **no es parte del objetivo del proyecto**. El objetivo es que
> **Omarchy arranque y funcione en la tablet** (kernel mainline + arranque desde
> `boot.img` en slots A/B + sesión Hyprland/Quickshell). Lo que hay aquí es
> **integración con servicios y apps de terceros**: reenvío de puertos a un
> servidor de música, proxy de Tailscale para que las apps alcancen la red del
> autor, y un lanzador de `scrcpy` para el móvil.
>
> **No hace falta nada de esto para arrancar Omarchy en la tablet.** Se conserva
> porque es trabajo real y porque los scripts de `build/gates/revision/` lo
> citan; pero no lo leas como parte del port, y no lo tomes como un requisito.

| Fichero | Qué es | ¿Hace falta para el port? |
|---|---|---|
| `uke.navidrome/` | Fork del plugin de Omarchy para un servidor de música (Subsonic) | No. Es una app concreta |
| `uke-navidrome-fwd.service` | Reenvío local de un puerto hacia ese servidor | No |
| `uke-tailnet` | Envuelve una app con el proxy de `tailscaled` para que salga a la tailnet | No (es red de servicios, no del port) |
| `uke-movil`, `uke-movil.desktop` | Lanza `scrcpy` contra el móvil por Tailscale | No |
| `omarchy-parche-servicefor.sh` | Parche de Omarchy para el anclaje de apps de servicios | No |
| `pruebas/` | Pruebas de foco y de atajos de teclado de Hyprland | No (sirven si se toca el gestor de ventanas) |

Lo que **sí** es parte del port y está en otros directorios: `touch-mode/`,
`escritorio-tactil/`, `tablet-t1..t5/`, `lapiz/`, `tactil/`, `audio/`, `bt/`,
`wifi*/`, `camaras/`, `bateria/`, `carga/`, `arranque/`, `omarchy/`.
