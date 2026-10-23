# Dudas de la sesión plugins-tablet (22-oct-2026)

Informes: `build/gates/revision/BARRA-PORTATIL-TABLET-20261022.md` (la barra del portátil, orden de las 21:2x) y
`build/gates/revision/PLUGINS-TABLET-20261022.md` (arreglos de la tarde, antes de la orden).

## Orden: «la barra entera del portátil, tal cual»

Hecho. En la tablet está tu barra **serpbar** con sus ajustes, su tema (Tokyo sobre Catppuccin), sus fuentes y tu fondo,
además de todos tus plugins. Comparativa: `build/gates/revision/capturas-barra-portatil-20261022/barras-lado-a-lado.png`.

### Lo que no funciona igual, y por qué

| Pieza | Estado en la tablet | Motivo |
|---|---|---|
| `omarchy.dock` (dock) | **No portado** | Es *first-party* del Omarchy `dev` del portátil. Solo aparece en escritorios en modo «flotante» (layouts de `dev`, con el comando `omarchy-dock`), y nada de eso existe en el 4.0.6 de la tablet. Además, el escritorio táctil abre cada app a pantalla completa, así que nunca se vería. Tus apps fijadas sí están copiadas en `shell.json` (`dock.pinned`), por si se actualiza Omarchy. |
| `omarchy.remote-session` | **No portado** | Solo detecta sesiones de escritorio remoto «gliff» para un indicador que el 4.0.6 no tiene. En la tablet no haría nada visible. |
| `crmne.hyprmoncfg` | Píldora y panel, pero **sin daemon** | El binario oficial para arm64 (1.24.0, la misma versión del portátil) está instalado como paquete. El daemon `hyprmoncfgd` lo he dejado **sin activar**: aplica perfiles de pantalla, y en la tablet la pantalla es delicada. Sin él, el panel sale vacío. ¿Lo activo? |
| `radimsem.omafind` | Píldora y asistente de instalación; **motor pendiente** | Necesita compilar `llama-server` en la tablet, unos 15–30 min de CPU. Sin driver Vulkan (va atado a `mesa`, que está retenido) irá solo con CPU. El modelo se copia del portátil. Lo hago en un turno aparte (ver informe). |
| Grabación con `gpu-screen-recorder` | No instalado | En los espejos de ALARM da 404. Sí están `wf-recorder`, `cava`, `matugen` y `ddcutil`. |
| Iconos de la bandeja | Distintos | Son los de las apps que corren en cada equipo. |

### Adaptaciones que he hecho para que quepa y se toque (todo en `deploy/serpbar-tablet/adapt-serpbar.py`)

La tablet tiene **1600 px lógicos** de ancho y el portátil 1920. Con tu barra tal cual más los widgets de la tablet, el grupo
de la derecha tapaba el reloj. Lo que he cambiado, de menos a más visible:
- **Altura 42 px** en la pantalla de la tablet (en el portátil, 40). Probé 48 y 44 y no cabían. Las píldoras miden unos 32 px de alto: es tocable, pero por debajo de los 48 recomendados.
- **5 escritorios** en lugar de 8: la tablet usaba 5.
- **Música**: texto al mínimo de su propio deslizador (80 en lugar de 120). Sin nada sonando pone «Nothing is».
- **Wi-Fi y Bluetooth**: nombre recortado a 96 px. En la tablet salen el SSID y el lápiz conectado («Xiaomi Focus Pen»), mientras que en el portátil pone «Connected» y «On».
- **Bluetooth visible**: serpbar decidía «sobremesa» porque la batería de la tablet no se llama `BAT*`, y escondía la píldora. Lo he corregido.
- **Grupo nuevo de la tablet**, con la misma píldora que los demás: lanzador, teclado en pantalla, Bitwarden, Wi-Fi con QR y batería exacta (perfil y vatios).

### Preguntas

1. **Peligro con el dedo: «Logout» bajo la píldora de batería.** El panel lateral de batería se abre encima de la esquina
   de arriba a la derecha y su botón «Logout» cae justo donde estaba la píldora. Un segundo toque para cerrarlo **cierra la
   sesión**: me pasó a las 21:44 en las pruebas, y lo recuperé reiniciando sddm. ¿Le pongo una confirmación al «Logout» o
   bajo el panel por debajo de la barra? (cambia un poco el comportamiento, no el aspecto).
2. ¿Activo `hyprmoncfgd` (ver tabla)?
3. ¿La altura de 42 te vale, o prefieres quitar algo del grupo de la tablet para subir a 48? El teclado ya aparece solo al tocar un campo, y el lanzador se abre también con el gesto de 3 dedos hacia arriba.
4. **El perfil de energía cambia con un toque** en la batería exacta (Ahorro > Equilibrado > Rendimiento). Igual que
   antes; en las pruebas lo dejé en «ahorro».

## Anteriores (antes de la orden de la barra entera)

- Powerbar ya no es la barra (la copia de seguridad la conserva). Sus widgets «On demand» eran inalcanzables con el dedo: esto ya no aplica.
- `omaplug` saca el teclado en pantalla al abrirse, porque enfoca su buscador.
- «Primer toque perdido» tras reiniciar la shell (visto con el puntero simulado): **sin verificar con el dedo real**.
- `udiskie`: **resuelto** (instalado a las 19:27). Comprobado a las 21:46: el autostart lo arrancó sin la notificación de error.
