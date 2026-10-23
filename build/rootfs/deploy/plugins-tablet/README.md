# plugins-tablet — plugins de la shell (Omarchy/Quickshell)

Plugins que se despliegan en la **shell de Omarchy** (Quickshell) de la tablet.
Esto **sí es parte del port**: sin ellos la sesión funciona pero pierde widgets
y comportamientos que el proyecto usa a diario.

| Fichero | Qué es | ¿Necesario para arrancar? |
|---|---|---|
| `UkeKeyboardPanel.qml` | Panel del teclado en pantalla en la barra | No, pero es el acceso al teclado táctil |
| `deploy.sh` | Instala los plugins en la shell de la tablet | — |
| `port-elsewhen.py` | Adaptador del plugin «elsewhen» (reloj mundial, tus ciudades) | **No. Es opcional**: un widget de una app de terceros, no parte del port |

## El plugin `elsewhen`

`port-elsewhen.py` es un parche/adaptador del plugin de reloj mundial
«elsewhen» para el tema y la barra de la tablet. **No hace falta para que
arranque Omarchy**: si no se instala, la barra funciona igual y sin ese widget.

Los demás informes del proyecto que hablan de apps concretas (Navidrome,
Jellyfin, Kavita, Nextcloud, Bitwarden, Element, Fractal, Strawberry…) están en
`build/gates/revision/` y son **historia de sesiones**, no parte del port: el
código de integración de apps de verdad está en
[`../resto-apps/`](../resto-apps/README.md), que también es opcional.
