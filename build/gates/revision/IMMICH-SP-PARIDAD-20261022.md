# Immich y Super Productivity nativos: paridad con las apps oficiales (22-oct-2026, 03:30–04:50, sesión immich-sp-re)

## Resumen
| | sp-nativo (`~/proyectos/super-productivity-nativo`) | immich-nativo (`~/proyectos/immich-nativo`) |
|---|---|---|
| Referencia | SP oficial: Flatpak 19.1.0 (ejecutada aislada) + código 19.2.0 | app móvil (navegación, táctil) + web (lo que falta), código upstream oct-2026 + servidor real v3.3.5 |
| Checklist | `PARIDAD.md` (sync, navegación, lista, detalle, añadir, pantallas, atajos, aspecto, peso) | `PARIDAD.md` (navegación, rejilla, selección, visor, detalles, biblioteca, búsqueda, álbumes, papelera…) |
| Qué cambió | UI rehecha a imagen de la oficial + **sync como un dispositivo más** (ops oficiales) | NavigationRail como la app en horizontal, rejilla, pinch, selección, hoja de acciones, visor con gestos, panel de detalles, Biblioteca/Archivo/Papelera/Recuerdos/Lugares/Explorar |
| Tests | `bin/test` **27/27** (incluye sync real de dos clientes por WebDAV) | `bin/test` **25/25** (mock con estado) |
| Contra lo real | Nextcloud: lectura (54 tareas); escritura probada contra la **SP oficial** en un WebDAV local con copia de los datos | Immich real: **14/14 escrituras** con una foto de prueba (subida…borrado); nada quedó en el servidor |
| RSS (PC, Wayland real, mismos datos) | **256 MB RSS / 128 MB PSS** frente a **~990 MB / 545 MB** de la oficial (11 procesos Electron) | 249 MB RSS / 128 MB PSS (la oficial no se pudo medir: ver «Límites») |
| Tablet | `sp-nativo 0.2.0` instalado; RSS 102 MB offscreen | `immich-nativo 0.2.0` instalado; RSS 115–119 MB offscreen contra el mock (20 000 assets) |
| Commits | `217fce7`…`7949d8c` (19 esta noche) | `c446e5f`…`aec37a5` (10 esta noche) |

## Método
1. **Ingeniería inversa** con subagentes Sonnet sobre clones de upstream (`~/.cache/upstream/{immich,super-productivity}`):
   `docs/re/re-sp.md`, `docs/re/re-immich-mobile.md`, `docs/re/re-immich-web.md` (ficheros y líneas citados).
2. **SP oficial aislada**: Flatpak 19.1.0 lanzado con `XDG_CONFIG_HOME/DATA/CACHE` propios *dentro* del sandbox
   (`~/.var/app/…/prueba-spn`, ya borrado) y `--remote-debugging-port` para manejarla por CDP; sincronizando como «Nextcloud» contra
   `tests/webdav_mock.py` (WebDAV local, usuario de prueba) con una **copia** del `sync-data.json` real. Así las dos apps ven los mismos
   datos y se comparan capturas y estados. **El perfil real de SP no se tocó** (backups sin cambios, último 14-oct).
3. **Comparación**: capturas lado a lado (oficial izquierda) en la carpeta de notas de la sesión
   (`…/side-session-notes/local_97c1eb5c-…/capturas-paridad-20261022/`; fuera de git porque llevan títulos de tareas y fotos reales).
4. **Implementación**: SP la hice yo (diseño + sync); Immich un subagente Sonnet con el RE como especificación, revisado después.

## Hallazgos de sync (SP)
- Cada edición de sp-nativo es una op del registro oficial con su **código congelado** y la carga de la acción NgRx
  (HA, TA, HU, HD, HMP, HPT, KT, WM, PA, GA, ST, NA, NU, ND). La SP oficial aplicó una batería de 21 ops sin diálogos ni errores y
  su estado coincidió con el nuestro entidad a entidad tras corregir 3 diferencias (null en campos, etiquetas nuevas delante, árbol
  de etiquetas). Conflicto real (la oficial marca hecha y sp-nativo renombra la misma tarea a la vez): la oficial lo resuelve sola
  con una op LWW, sin diálogo, y sp-nativo recoge ambos cambios.
- **El SP del dueño no sincroniza desde el 26-sep** (hipótesis fuerte): el `sync-data.json` de Nextcloud es de esa fecha y el
  Flatpak tiene `syncProvider` vacío. Ver `super-productivity-nativo/DUDAS.md`.
- Escritura real **apagada** (`allowWrite` ausente) en PC y tablet: decisión del dueño. Copia de hoy en `~/backups/sp-real-20261022/`.

## Hallazgos de la tablet
- **Copiar un fichero recién escrito deja su cola a ceros** (kernel 7.2.9-senemos, ext4): el binario instalado por makepkg daba
  SIGSEGV; `cmp` mostraba 52 835 bytes a 0 al final; con `sync -f` antes de copiar, idéntico y funciona. Los dos PKGBUILD hacen ya
  `sync` + `cmp`. Afecta a todo lo que se compile e instale allí: nota `NOTA-COPIA-CEROS-20261022.md` en la carpeta compartida y
  aviso a las sesiones de notas, resto de apps y cámaras.
- `tailscale status` marca a uke *offline* y el proxy `localhost:1055` no responde (04:25–04:40): sin sync real desde la tablet.
  Causa (según la sesión de notas): la tablet **no tiene WiFi desde las 04:06:49**; NetworkManager perdió el bus en la caída de D-Bus
  de las 03:50 y wlan0 está DOWN. Al volver la WiFi el proxy debería funcionar sin tocar nada.
- Pantalla congelada desde las 03:50 (D-Bus, documentado por la sesión de notas): sin prueba de ventana real, dedo ni teclado en
  pantalla. Los gestos se probaron con eventos sintéticos (deslizar = hecha, deslizar/mantener = menú, arrastrar asa = reordenar en
  SP; swipe/long-press/arrastre/scroll en Immich).
- La sesión gráfica va con `LANG=C.UTF-8`: las dos apps salen en inglés allí (en el PC, español). Decisión del dueño.
- En la tablet `sans-serif` resuelve a Noto Naskh Arabic: las apps fijan Inter si está.
- Instalación con `setpriv` (sin sesiones PAM) y turno `immich-sp-re` (04:22–04:45), soltado.

## Límites y qué no se midió
- **Immich oficial sin capturas ni RSS**: la web en neo pide inicio de sesión (no tecleo contraseñas) y el móvil del dueño no tiene la
  app instalada; la referencia de Immich es el código (RE con medidas exactas).
- Electron oficial de SP no existe para ARM; en la tablet la referencia es `sp-web` (WebKitGTK con la web oficial): 806 MB RSS
  (21-oct), frente a 102 MB offscreen de sp-nativo.
- No se probaron contra el Immich real «vaciar papelera» ni «restaurar todo» (afectarían a datos reales): solo contra el mock.

## Limpieza
Foto y álbum de prueba de Immich borrados (GET → 400). Carpeta de prueba de Nextcloud borrada (no hizo falta). SP oficial aislada
cerrada y su perfil borrado. WebDAV local parado. En la tablet: binarios de prueba, mock y capturas borrados; quedan los paquetes y
las configs (600) en `~omarchy/.config/{sp-nativo,immich-nativo}/`.

## Próximos pasos (dueño)
1. Elegir idioma de la tablet y recuperar la sesión gráfica; después probar con dedo las dos apps (son `sp-nativo` e `immich-nativo`
   en el lanzador).
2. SP: reactivar la sync Nextcloud del Flatpak y decidir si sp-nativo escribe (`"allowWrite": true`).
3. Immich: crear una key de permisos acotados para la tablet (la actual es de admin con `all`).

## Anexo 12:10–12:25: prueba en la tablet recuperada (WiFi, Tailscale y sesión gráfica bien tras el reinicio de las 11:37)
Turno `immich-sp-re` 12:10–12:25. Toques multitáctiles reales del compositor con un dispositivo uinput (el mismo método que `/root/utap.py`).
| | sp-nativo | immich-nativo |
|---|---|---|
| Sync real desde la tablet (proxy `localhost:1055`) | 54 tareas de Nextcloud (solo lectura) | 9571 assets, servidor v3.3.5 |
| Ventana Wayland real | 182 MB RSS / 112 MB PSS | 0,58 s hasta la ventana; 203/134 MB al arrancar, 246/177 MB tras ver fotos |
| Dedo | menú, Bandeja, deslizar = hecha, deslizar = menú, + con barra de añadir | desplazar, pellizcar columnas, selección por pulsación larga, abrir foto, pasar, info arriba, cerrar abajo |
| Teclado en pantalla | aparece solo al enfocar la barra; escribir + Intro añade | aparece solo en la búsqueda; «perro» → resultados |
| Arreglado en el momento | tooltip pegado tras un toque; texto de ayuda flotante recortado | **tocar una foto no la abría** (el TapHandler del clic derecho se quedaba los toques); ayuda flotante; consulta perdida al pasar a resultados |

Incidencia mía: en un toque el foco estaba en otra ventana (un borrador sin guardar de GNOME Text Editor que dejó otra sesión) y le
añadí «ya» y un salto de línea; lo devolví a «Ü» con tres retrocesos, comprobado en el título de la ventana. Los cambios de prueba de
sp-nativo se deshicieron en su copia local; con `allowWrite` apagado nada se subió. Capturas (con datos reales, fuera de git):
`…/capturas-paridad-20261022/tablet-dedo/`.
Sigue pendiente: idioma de la sesión (`LANG=C.UTF-8`, las apps salen en inglés) y las decisiones de `docs/historia/DUDAS.md`.

## Anexo tarde: Immich comparado con capturas públicas (sin login)
Referencia: capturas del repo upstream (`mobile/assets/feature_message/*.webp` = interfaz actual; `docs/static/img/screenshot-dark.webp`
= app v1.112; capturas de la tienda = mar-2022, interfaz antigua). Detalle pantalla por pantalla en `immich-nativo/PARIDAD.md` §10;
imágenes lado a lado (con tus fotos, fuera de git) en `…/capturas-paridad-20261022/immich-vs-publicas/`.
- **Comparado con capturas públicas:** barra de 4 pestañas (igual; icono de Biblioteca corregido), accesos rápidos de Buscar (añadido
  «Tomadas recientemente»), hoja de selección (orden corregido al de la app), menú ⋮ del visor (reordenado; falta pase de diapositivas),
  panel de información (igual salvo el mapa), textos en español (mismas claves de upstream).
- **Distinto con motivo:** rejilla agrupada solo por mes (la app agrupa por día), sin mapa, sin compartir/enlaces/Cast.
- **Pendiente de comparar con tus datos reales en la oficial** (requiere tu sesión en la web o la app en el móvil): aspecto de la rejilla
  con tus fotos, visor, Recuerdos, Personas, Lugares, Álbumes, Biblioteca y el RSS de la web oficial.
- `bin/test` 25/25; cambios en el PC, **no instalados en la tablet** (pendiente de su reinicio tras el oops del kernel de las 12:31).
- **15:49–15:53 (tablet reiniciada a las 15:46, turno immich-sp-re):** correcciones de Immich instaladas y comprobadas con toques reales
  (Tomadas recientemente, icono de Biblioteca, orden de selección, menú ⋮). Arreglado en el momento: la pulsación larga usaba el umbral de
  Qt (800 ms) y una de 0,9 s abría la foto; ahora 500 ms como Flutter. sp-nativo tras el reinicio: arranca a ancho completo con el esquema
  de la oficial, sync real de 54 tareas, barra de añadir sin la etiqueta flotante y teclado en pantalla; RSS 186 MB / 119 MB PSS.
- **16:00–16:31:** Immich con la **rejilla agrupada por día** dentro del mes (como la app; el mes se reparte al cargarse) y **pase de
  diapositivas** (5 s, en bucle, como `slideshow_config.dart`); instalados y probados en la tablet con toques reales. Con eso, de las
  capturas públicas solo quedan distintos el mapa (por peso) y el texto reconocido (OCR, pendiente).
- **16:35–16:45:** Immich con **texto reconocido (OCR)** como la app (botón «Texto», velo con recuadros, tocar = texto seleccionable y
  Copiar; `GET /assets/{id}/ocr`), 26/26 tests. **Incidencia mía:** lo reinstalé en la tablet sin tener el turno (lo tenía
  escritorio-tactil; mi orden encadenaba la instalación aunque `uke-turno pedir` fallase). Cerré la app y avisé a esa sesión; la prueba
  con dedo del OCR queda pendiente de turno.
- **SP oficial:** se cerró hacia las 16:28 sin guardar URL/usuario/contraseña de Nextcloud (sigue `syncProvider: Nextcloud` sin datos) y,
  además, Nextcloud responde **502** desde las ~16:40 (`status.php`). Sin sync todavía; copia previa en `~/backups/sp-real-20261022-sync/`.
- **17:08–17:10 (turno immich-sp-re):** OCR de Immich probado en la tablet con una foto real con texto: recuadros alineados, tocar uno
  muestra su texto y «Copiar» lo pasa al portapapeles (`wl-paste` → «ZONA GRATIS»).
- **Noche (21:00–22:12):** sync real de SP activada en los tres sitios: el dueño tecleó la contraseña en el SP oficial; conflicto resuelto
  con «Mantener local» (94 tareas a Nextcloud, copia previa en `~/backups/sp-real-20261022-sync/`); sp-nativo con escritura en PC y
  tablet, alta y baja de prueba subidas desde la tablet (sv 3, ops HA/HD). sp-nativo 0.2.0 en la tablet como «Super Productivity» (sp-web
  no estaba instalado), con Tableros, Cronograma, notas en markdown, etiquetas como la oficial y fecha límite, probados con el dedo.
  Incidencia ajena resuelta: `/home/omarchy` quedó de root a las 21:35 por un `cp -a` de plugins-tablet (ya corregido por ellos).
