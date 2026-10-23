# Lo que te toca a ti (22-oct-2026)

Resumen de todas las dudas y pruebas de las sesiones de esta noche. El detalle de cada punto está en el fichero que se cita.

## Urgente
1. **Reiniciar la tablet.** A las 12:31 hubo un oops del kernel al aplicar el overlay de la cámara frontal, y quedaron dos tareas en D. Con ellas `systemctl reboot` puede colgarse: hace falta que estés para el reset físico. (docs/historia/DUDAS-CAMARAS.md §1)

## Cámaras (docs/historia/DUDAS-CAMARAS.md)
2. ¿Autorizas `pacman -S --needed libcamera libcamera-ipa libcamera-tools gst-plugin-libcamera pipewire-libcamera`? Contesta en la sesión de cámaras.
3. ¿Instalar una unidad que cargue los módulos de cámara una sola vez al arrancar? Sirve para no volver a aplicar overlays en caliente, que es lo que provocó el oops.
4. ¿Compilar Megapixels 1.8.3 desde su código fuente e instalarlo en `/usr/local`?

## Resto de apps y dictado (build/gates/revision/DUDAS-RESTO-APPS.md)
5. Prueba el dictado con tu voz: toca «🎙 Voz», habla y toca «■ Parar».
6. El servidor Matrix que usas y el inicio de sesión en Fractal. La primera vez te pedirá crear la contraseña del llavero.
7. Música: el plugin Navidrome de la barra (recomendado; Strawberry no se puede usar con el dedo). Ni uno ni otro saben usar el proxy.
8. Kavita está detrás de Authelia: cómo quieres que entren Komikku y Foliate.
9. Las demás webapps de Omarchy que quedan en la tablet: ¿se borran también?

## Super Productivity (~/proyectos/super-productivity-nativo/DUDAS.md)
10. ¿Tu SP del PC sincroniza hoy con Nextcloud? El `sync-data.json` del servidor parece antiguo.
11. La credencial: para leer se reutilizó la contraseña de aplicación de la sync de notas. ¿Te vale, o creas otra?
12. La escritura real en la sync está desactivada: ¿la activamos?
13. El idioma de la sesión gráfica de la tablet (ahora `C.UTF-8`): ¿la ponemos en español?

## Apuntes (docs/historia/DUDAS.md)
14. La IA de apuntes (Token Spy): falta la URL, el modelo con visión y el token.
15. Probar el lápiz de verdad y los gestos de dos dedos en la app de apuntes.

## Lápiz
16. El atasco de D-Bus de las 03:50 ya está arreglado (commit 211cac0) y `uke-lapiz` vuelve a estar activo. Pega el lápiz a la tablet y comprueba que se conecta solo.

## Informes finales
- `build/gates/revision/IMMICH-SP-PARIDAD-20261022.md`. La checklist de cada app está en su `PARIDAD.md`.
- `build/gates/revision/NOTAS-NEXTCLOUD-20261022.md`
- `build/gates/revision/RESTO-APPS-DICTADO-20261022.md`
- `build/gates/revision/CAMARAS-MEGAPIXELS-20261022.md`

## Immich: comparación con la oficial sin cerrar
17. Faltan las capturas lado a lado de Immich oficial, porque la web pide iniciar sesión y las sesiones no teclean contraseñas. Inicia sesión una vez en tu Immich web desde el navegador BrowserOS neo, o instala la app de Immich en el móvil. Con eso la sesión immich-sp-re hace la comparación de Immich y cierra la paridad. La de SP sí está hecha.
