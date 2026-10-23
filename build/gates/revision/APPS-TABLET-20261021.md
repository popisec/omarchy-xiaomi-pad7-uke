# Apps para la tablet «uke» — lista acordada con el dueño (21-oct-2026)

Estado: **BORRADOR EN CONVERSACIÓN**. Nada instalado. Disponibilidad medida el 21-oct-2026 con
`pacman -Sii` en la tablet (bases sincronizadas el 11–16-oct-2026; revalidar tras el `-Syu`).
Inventario: 380 paquetes explícitos, 110 actualizaciones pendientes (`pacman -Qu`), `/` con 94 GB libres.
Sin Flatpak. En el lanzador hoy: Firefox, Rnote, Papers, Loupe, Celluloid/mpv, Nautilus,
gnome-text-editor, foot, kitty, pavucontrol.

## Decisiones del dueño

| Tema | Decisión |
|---|---|
| Jellyfin | **Delfin** nativo (extra 0.4.8-1, 4 MB, usa mpv que ya está). No usa Netflix. |
| Matrix | **Fractal nativo** (22-oct: el dueño no quiere webapps; elegido frente a NeoChat, ver `RESTO-APPS-DICTADO-20261022.md`) |
| Tutamail | ~~Webapp~~ **Descartado el 22-oct** (el dueño no quiere webapps; el correo no se sustituye) |
| Ofimática | **Sin LibreOffice.** Alternativa **pospuesta** (AbiWord+Gnumeric / webapps / Typst-LaTeX) |
| Música | Servidor **Navidrome** (Subsonic, `http://100.64.0.12:4533` por tailnet). Plugin Omarchy `backmeupplz.navidrome` 0.2.1 (QML, ya en el portátil: `~/.config/omarchy/plugins/`) **+ Strawberry** (extra 1.2.31-1) como reproductor de interfaz grande. Requiere `mpv` (instalado) y `mpv-mpris` (extra 1.3-1, NO instalado). En la tablet el usuario es `omarchy`; no tiene aún carpeta de plugins ni `navidrome.json` (contiene credenciales: copiar sin versionar). |
| Fotos | **Immich**: no hay cliente nativo Linux/aarch64. El dueño quiere **construir una app nativa propia, no Electron, de bajo consumo** (Qt Quick/C++ según skill `omarchy-app`) → sesión aparte. Mientras: webapp. `immich-go` (extra) opcional. |

Sesión de la app Immich: `local_4ff1013c-3149-4c39-ae70-0a7ebe412d5b` (proyecto `~/proyectos/immich-nativo`).
| Mapas | Ninguno |
| Control del móvil | **scrcpy** 5.0.1-1 (extra) por ADB inalámbrico/Tailscale; comprobar `android-tools`. |
| Lectura | Servidor **Kavita** en `PC-PORTATIL` (manga + libros). Clientes: **Komikku** (extra 50.11.0-1, fuente Kavita/OPDS) y **Foliate** (extra 3.3.0-3, OPDS); alternativa: web de Kavita. Kavita/Komga/Calibre-Web no tienen paquete aarch64 (no hace falta, son servidor). |
| Apuntes/lápiz | El dueño quiere **app nativa propia tipo GoodNotes**, carpeta por asignatura sincronizada con **Nextcloud** al editar. Sesión `local_1badc9a8-ee36-41cd-87f3-2b1607cda9b3` (`~/proyectos/notas-nativas`), con módulo de **corrección con IA** (visión → LaTeX → evaluación). Mientras: Rnote (instalado) y, opcional, Xournal++ 1.3.8 (extra, NO instalado) + `nextcloud-client` (extra, 26 MiB). |
| Tareas | Quiere **Super Productivity**. v19.2.0 (GitHub, 21-oct-2026) publica Linux solo **x86_64** (deb/snap/AppImage/rpm): **sin ARM Linux**; no hay `electron` en los repos. Opciones: PWA `app.super-productivity.com` con sync WebDAV/Nextcloud, o compilar con Electron arm64 de npm (pesado). Alternativas nativas: Errands (extra 46.2.10), Planify (extra 4.20.0-2). |
| Categorías pedidas | navegar/vídeo, lectura, lápiz, estudio, ofimática, comunicación, multimedia/ocio, utilidades/PC |

## Tabla categoría → app

Estado: I = instalada, P = por instalar, W = webapp, ? = sin decidir. Prioridad: A/M/B.

| Categoría | App | Origen (verificado 21-oct) | Estado | Ajustes táctiles | Prio |
|---|---|---|---|---|---|
| Navegador | Firefox | instalado | I | políticas de privacidad ya puestas | A |
| Vídeo local | Celluloid, mpv | instalados | I | — | A |
| Jellyfin | **Delfin** | extra `delfin` 0.4.8-1 | P | GTK4/libadwaita, táctil de serie | A |
| PDF | Papers | instalado | I | — | A |
| Imágenes | Loupe | instalado | I | — | M |
| Notas con lápiz | Rnote | instalado | I | ya validado con el lápiz | A |
| Archivos | Nautilus | instalado | I | — | M |
| Editor de texto | gnome-text-editor | instalado | I | — | B |
| Matrix | **Fractal** 14.1 | extra (ALARM) | I (22-oct) | GTK4/libadwaita adaptable | M |
| Correo | — (Tuta descartado el 22-oct, sin sustituto) | — | — | — | — |
| Mensajería (resto) | ? | Telegram `extra` 7.3.1-1, Signal `extra` 8.30.0-1, WhatsApp web | ? | el dueño aún no eligió | ? |
| Lectura EPUB | ? Foliate | extra 3.3.0-3 | ? | GTK4 adaptativo | ? |
| Cómics | ? Komikku | extra 50.11.0-1 | ? | GTK4 adaptativo | ? |
| Anotar PDF/lápiz | ? Xournal++ | extra 1.3.8-1 | ? | tamaño de botones; presión OK en GTK3 | ? |
| Dibujo serio | ? Krita | extra 6.0.4.1-1 | ? | pesado | ? |
| Calculadora | ? gnome-calculator / qalculate-gtk | extra | ? | — | ? |
| Ofimática | ? AbiWord 3.0.8-2 + Gnumeric 1.12.62-1 / webapps / Typst 0.x / Tectonic 0.17.0-1 | extra | ? | — | ? |
| Música | ? Amberol 2026.1-1 / Lollypop | extra | ? | — | ? |
| Podcasts/radio | ? Gnome Podcasts 25.3-2 / Shortwave 5.1.0-2 | extra | ? | — | ? |
| Fotos | ? gThumb 3.12.12-1 | extra | ? | — | ? |
| Mapas | ? GNOME Maps 51.2-1 | extra (Organic Maps: NO en aarch64) | ? | necesita red | ? |
| Control del PC | ? KDE Connect 26.08.2-1, Remmina, TigerVNC 1.16.2-5 | extra | ? | — | ? |
| Red | Tailscale | instalado | I | ya en uso | A |
| Juegos | ? | por definir | ? | — | ? |

No disponibles en aarch64 (21-oct): `jellyfin-media-player`, `koreader`, `obsidian`, `onlyoffice-desktopeditors`,
`organicmaps`, `element-desktop`, `tutanota-desktop`.

## Decisiones finales de este bloque (21-oct-2026)
- Ofimática: **no la necesita**. Mensajería: **solo Matrix** (22-oct: Fractal nativo; Tuta y las webapps descartadas). Mapas: ninguno. Juegos: no pedidos.
- Apps nativas propias en marcha (sesiones aparte, nada que instalar todavía): Immich (`~/proyectos/immich-nativo`),
  apuntes+Nextcloud+IA (`~/proyectos/notas-nativas`; la revisión recomienda empezar con Xournal++ + capa IA + carpeta Nextcloud),
  Super Productivity nativo (`~/proyectos/super-productivity-nativo`, diseño en `docs/DISENO.md`).
- Super Productivity mientras tanto: PWA `app.super-productivity.com` con sync WebDAV a Nextcloud.

## Plan de instalación (LISTO PARA AUTORIZAR — no ejecutado)

Medido hoy en la tablet (DB sincronizada 11–16-oct): `pacman -Qu` = 110 actualizaciones; instalar paquetes sueltos **falla**
(`gstreamer`/`gst-plugins-base-libs` 1.28.8 rompen `gst-plugins-bad-libs` 1.28.7) ⇒ hace falta `-Syu` completo.
`/etc/pacman.conf` solo tiene `HoldPkg = pacman glibc` (sin `IgnorePkg`).

⚠️ **Riesgo crítico para el arranque:** el `-Syu` trae `linux-aarch64 7.1.6 → 7.2.10` y `linux-firmware 20260622 → 20260916`.
La tablet arranca un kernel propio (`7.2.0-rc2-palawan+`, boot.img de Android) y firmware WCN6750/gen71100 ajustado. **Añadir
`IgnorePkg = linux-aarch64 linux-firmware` antes** (`pacman -Syu --ignore linux-aarch64,linux-firmware` basta la primera vez) y
revisar que ningún hook escriba en `/boot`. También sube `qt6-base 6.11.2 → 6.12.0` (los paquetes Qt de Omarchy/quickshell deben
subir juntos: no cortar a mitad).

Pasos (cuando el dueño autorice y la sesión gestora confirme la tablet libre; nada de reinicios cruzados con cámaras/BT/audio):
1. Backup: `pacman -Qqe > /root/pkgs-pre-syu.txt`, copia de `/etc/pacman.conf`, `/var/log/pacman.log` de referencia.
2. `IgnorePkg = linux-aarch64 linux-firmware` en `/etc/pacman.conf`.
3. `pacman -Syu` (no `-Sy` suelto) y revisar la salida; luego **un reinicio con sync** y comprobar sesión gráfica, WiFi, BT, audio.
4. `pacman -S --needed delfin mpv-mpris strawberry scrcpy android-tools komikku foliate` (todas en `extra` hoy; revalidar con `pacman -Si`).
   Opcionales según decida el dueño: `xournalpp nextcloud-client` (apuntes), `syncthing`/`rclone`.
5. Webapps: `.desktop` (Element `app.element.io`, Tuta `app.tuta.com`, Super Productivity PWA, Jellyfin si hace falta) en modo aplicación de Firefox.
6. Plugin Navidrome: copiar `~/.config/omarchy/plugins/backmeupplz.navidrome` del portátil al usuario `omarchy` de la tablet
   (`~/.config/omarchy/plugins/`) y `navidrome.json` **sin versionar** (lleva token); servidor por tailnet.
7. Delfin: configurar servidor Jellyfin (usuario/contraseña a mano por el dueño). Komikku/Foliate: Kavita en `PC-PORTATIL` (OPDS).
8. scrcpy: `adb connect` por avahi/Tailscale (ver docs/historia/AGENTS.md del home: el puerto es efímero).
9. Añadir/comprobar iconos en `nwg-drawer`, escala, teclado en pantalla y rotación en cada app.

Revertir: `pacman -U` desde caché `/var/cache/pacman/pkg` (conserva las versiones previas) o `pacman -Rns` de los paquetes nuevos.

## Pendiente
Aprobación del dueño del plan; confirmar tablet libre; decisiones de las tres apps nativas (en sus sesiones).

## Hallazgos de la comprobación previa (21-oct-2026 21:45, solo lectura; instalación DETENIDA)
La sesión gestora confirmó la tablet libre (30 min arrancada, batería 99 %, sin pruebas). Antes de ejecutar aparecieron cuatro cosas **que el plan no recogía**:
1. **Guardia de Omarchy**: `00-omarchy-update-guard.hook` (PreTransaction, AbortOnFail) corre `/usr/bin/omarchy-update-pacman-guard`, que **aborta cualquier `pacman -Syu` directo** salvo con `OMARCHY_UPDATE_PACMAN=1` o `OMARCHY_ALLOW_DIRECT_PACMAN=1` (la vía prevista es `omarchy-update`).
2. **systemd 261.2 → 262** (mayor) en el mismo `-Syu`, junto con `mkinitcpio 41-4 → 42.2`, `qt6-base 6.11 → 6.12` y 108 paquetes en total (simulado con `pacman -Su --ignore linux-aarch64,linux-firmware --print`, DB del 16-oct).
3. **Hook mkinitcpio** (`90-mkinitcpio-install`) se dispara con systemd y mkinitcpio; el preset `/etc/mkinitcpio.d/linux-aarch64.preset` apunta a `7.1.6-1-aarch64-ARCH` que **no es el kernel en uso** (`7.2.9-senemos…-ouke5`; `/boot` está vacío, arranca de boot.img). Puede fallar o generar un initramfs inútil en `/boot` sin consecuencias de arranque, pero no está probado.
4. La tablet no tiene recuperación automática (watchdog sin arreglar, R-42): si systemd 262 falla al reiniciar, hace falta reset físico y reparar desde USB/ACM.
Opciones: (A) `-Syu` completo con `OMARCHY_ALLOW_DIRECT_PACMAN=1`, `--ignore linux-aarch64,linux-firmware` y `NoExtract`/hook mkinitcpio desactivado; (B) `omarchy-update` (lo prevé Omarchy; revisar qué hace); (C) sin `-Syu`: bajar `.pkg.tar.xz` + `.sig` de las 7 apps y de sus dependencias y `pacman -U` (el simulado falla por gstreamer 1.28.8 vs `gst-plugins-bad-libs` 1.28.7 ⇒ habría que fijar versiones antiguas del mirror).

## Preparación del método C (paquetes sueltos) — 21-oct-2026 ~22:00 — SIN INSTALAR
Método: DB temporal `/root/pacdb-tmp` en la tablet (`pacman --dbpath … -Sy`; la DB real `/var/lib/pacman/sync` no se tocó), simulación por app y descarga con firmas a `/root/pkgs-apps` (58 paquetes + 58 `.sig`, 86 MB; `-Sw` verificó integridad).
| App | Resultado de la simulación | Decisión |
|---|---|---|
| delfin 0.4.8-1 | solo él, sin dependencias nuevas | instalar |
| mpv-mpris 1.3-1 | solo él | instalar |
| scrcpy 5.0.1-1 | + android-tools 37.0.0.p1-1 + protobuf 36.1-1 (nuevos, sin tocar nada instalado) | instalar |
| komikku 50.11.0-1 | ~45 paquetes `python-*` nuevos + webkitgtk-6.0; `python` 3.14.7 instalado vs 3.14.8 del repo = misma rama 3.14 | instalar; probar arranque (libsoup3 instalado 3.6.6 vs 3.8.0 del repo: posible fallo de ABI en webkit) |
| foliate 3.3.0-3 | gjs, js140, webkitgtk-6.0 (41 MB), etc., sin tocar nada instalado | instalar; probar arranque |
| strawberry 1.2.31-1 | **requiere `-Syu`**: gstreamer/gst-plugins-base-libs 1.28.8 rompen `gst-plugins-bad-libs` 1.28.7 y además depende de qt6-base | **diferido a `-Syu`** |
Base verificada igual que el repo: gtk4 4.24.1, libadwaita 1.10.0, glib2 2.90.1.
Estado: el `pacman -U --needed` fue **denegado por el clasificador de permisos** (escritura remota); no se instaló nada. Backup de listas: no creado (se haría justo antes).

## RESULTADO DE LA INSTALACIÓN (método C) — 21-oct-2026 ~21:50 — HECHA, verificada
Autorizada por el dueño en esta sesión. Backups de listas en la tablet: `/root/pkgs-pre-apps-20261021.txt`, `/root/pkgs-all-pre-apps-20261021.txt`. Paquetes con firma en `/root/pkgs-apps` (`pacman -U` verificó cada `.sig`).
- Instalado (`pacman -U --needed`, DB real de pacman sin sincronizar, sin `-Syu`, kernel/firmware/systemd sin tocar): **delfin 0.4.8-1, mpv-mpris 1.3-1, scrcpy 5.0.1-1 + android-tools 37.0.0.p1-1, komikku 50.11.0-1, foliate 3.3.0-3** y 55 dependencias nuevas (python-*, webkitgtk-6.0 2.54.1-1, gjs…).
- Incidencias: (1) el primer intento falló por incluir los `.sig` en el glob y no instaló nada; (2) el segundo abortó sin cambios porque **protobuf 36.1 está instalado a mano fuera de pacman** (libs de 7-sep, misma versión que el repo): se instaló con `--assume-installed protobuf=36.1-1` y **sin** el paquete `protobuf`, para no pisar esos ficheros. `pacman -Q protobuf` seguirá sin existir.
- Verificación: `ldd` sin librerías faltantes en delfin/komikku/foliate/scrcpy/adb; arranque como usuario `omarchy` en `wayland-1`: las tres apps GTK siguieron vivas 10 s sin error (exit 124); `scrcpy --version` 5.0.1; `adb version` 1.0.41. Komikku avisa solo de `/etc/timezone` y del logo de anilist (red). No probado: Delfin contra el Jellyfin real, Komikku contra Kavita, scrcpy contra el móvil, plugin Navidrome con `mpv-mpris`.
- **Sigue pendiente de `-Syu`**: strawberry (gstreamer 1.28.8 rompe gst-plugins-bad-libs 1.28.7 + qt6-base) y cualquier otra cosa que lo exija.
- Pendiente aparte: copiar el plugin `backmeupplz.navidrome` + `navidrome.json` (token) al usuario `omarchy`, webapps (Element, Tuta, Super Productivity PWA), configurar servidores, `nwg-drawer`.

## Navidrome + webapps en la tablet — 21-oct-2026 ~21:56
- **Plugin Navidrome**: `backmeupplz.navidrome` 0.2.1 ya estaba en `/home/omarchy/.config/omarchy/plugins/` con ficheros idénticos (sha256) a los del portátil. Se copió `navidrome.json` (token; modo 600, dueño omarchy; no versionado). **NO activado en la barra** (`shell.json` solo carga `radimsem.omafind`; no tocado).
- ⚠️ **Bloqueo de red**: desde la tablet `curl http://100.64.0.12:4533/ping` y TCP 22/4533 a PC-PORTATIL **fallan** (el portátil responde 200). Causa: `tailscaled` en la tablet va con `--tun=userspace-networking` (`/etc/default/tailscaled`, no existe `tailscale0`), así que las apps normales no alcanzan IPs 100.x; solo `tailscale ping` (vía DERP) y `ssh` por el proxy funcionan. Lo mismo afecta a Delfin (Jellyfin), Komikku (Kavita) y al servidor Nextcloud de SERVIDOR-01 (`https://SERVIDORhost.tailnet-ejemplo.ts.net:9454`: http 000). **Arreglo propuesto (necesita decisión del dueño, toca la conexión SSH de respaldo):** pasar `tailscaled` a modo TUN (`FLAGS=""`, requiere `/dev/net/tun` y módulo `tun`; comprobar antes) con ciclo de prueba y USB como respaldo; alternativa: `tailscale serve`/proxy SOCKS5 por app (`ALL_PROXY=socks5://localhost:1055`).
- **Webapps** (Firefox, ventana propia, sin modo app: Firefox no lo tiene; el lanzador de Omarchy exige chromium, no instalado): `Element.desktop` (app.element.io), `Tuta.desktop` (app.tuta.com), `SuperProductivity.desktop` (app.super-productivity.com) en `/home/omarchy/.local/share/applications/` (validados con `desktop-file-validate`). Sin probar visualmente en nwg-drawer; sin sync WebDAV de Super Productivity configurada.

## Prueba de tailscaled en modo TUN — 21-oct-2026 21:58 — FALLÓ y se revirtió sola (sin pérdida de acceso)
Hecha por la vía USB (`root@192.168.42.129`) con script de reversión automática (`/root/ts-tun-test.sh`, log `/root/ts-tun-test.log`, backup `/root/tailscaled.default.bak-20261021`). `/dev/net/tun` existe y `CONFIG_TUN=y`, pero con `FLAGS=""` y `--netfilter-mode=off` **tailscaled entra en bucle de reinicios** (`linuxfw: could not get iptables version`, `router: failed to look up link "tailscale0"`; no se crea `tailscale0`): el kernel no tiene netfilter, como ya anotaba `deploy/tailscale/README.md`. Reversión a `--tun=userspace-networking` y `netfilter-mode=on` comprobada (`active`, nodos visibles, SSH por Tailscale y USB OK). **El modo TUN queda descartado** hasta que el kernel tenga netfilter.
Alternativa viable (sin probar): `--socks5-server=localhost:1055` en `FLAGS` (sigue en userspace) + reenvíos locales con `socat`/`tailscale` hacia PC-PORTATIL (Navidrome 4533, Jellyfin, Kavita) y SERVIDOR-01:9454 (Nextcloud), y apuntar las apps a `localhost:<puerto>`; o proxy `ALL_PROXY=socks5h://localhost:1055` por app (libsoup/GLib lo respeta; Delfin/mpv a verificar).

## Resultado del lanzador web de Super Productivity (21-oct-2026 ~22:50, informe de su sesión)
`sp-web` (WebKitGTK 6.0 cargando app.super-productivity.com, en `~/proyectos/super-productivity-nativo`) funciona en la tablet y se ve igual que la web oficial, pero **consume 806 MB de RSS / 602 MB de PSS tras 60 s**, unas 4–5 veces más que `sp-nativo` (143 MB en la tablet; 248 MB en el portátil). No medido con datos reales, en reposo largo ni offline; el Electron oficial no se pudo medir. Decisión sobre cuál seguir: pendiente del dueño (ver abajo).

## PENDIENTES (para retomar) — sesión de apps EN PAUSA desde el 21-oct-2026
Decisión del dueño: solo 4 sesiones a la vez (audio, cámaras, apuntes, optimización); el resto queda aquí como pendiente.
| # | Pendiente | Estado | Primer paso al retomar |
|---|---|---|---|
| 1 | `-Syu` completo con backup | NO hecho. 110 actualizaciones; la guardia de Omarchy (`omarchy-update-pacman-guard`) bloquea el `-Syu` directo; sube systemd 261→262, mkinitcpio 41→42, qt6-base 6.11→6.12; hook mkinitcpio con preset desfasado (`7.1.6`, kernel en uso `7.2.9-senemos…-ouke5`) | Decidir vía (`omarchy-update` revisado, o `-Syu` con `OMARCHY_ALLOW_DIRECT_PACMAN=1`); `IgnorePkg = linux-aarch64 linux-firmware`; backup de `pacman -Qqe`/`-Q`; tablet libre y orden del dueño |
| 2 | Strawberry (música local/Navidrome con interfaz grande) | NO instalado: gstreamer 1.28.8 rompe `gst-plugins-bad-libs` 1.28.7 y pide qt6-base | Instalar tras el `-Syu` (`pacman -S strawberry`) |
| 3 | Apps que dependen de Tailscale TUN: plugin Navidrome (activar en `shell.json` de la tablet; `navidrome.json` ya copiado), Delfin→Jellyfin, Komikku→Kavita (PC-PORTATIL), Nextcloud (SERVIDOR-01:9454), Super Productivity WebDAV | Bloqueado: tailscaled en userspace; TUN falló (sin `CONFIG_NF_TABLES`); **el kernel con NF_TABLES lo prepara la sesión de optimización** | Cuando el kernel nuevo esté flasheado: `FLAGS=""` + `tailscale set --netfilter-mode=on` con reversión automática (ver `NOTAS-OMARCHY.md` 21-oct 22:15 y `deploy/tailscale/README.md`); luego probar `curl http://100.64.0.12:4533/ping` desde la tablet y configurar cada app |
| 4 | Categorías pospuestas: ofimática alternativa (el dueño dijo «no necesito nada de esto»), calculadora/estudio (gnome-calculator, Typst/Tectonic), mensajería extra (descartada: solo Element y Tuta), música local fuera de Navidrome, fotos, mapas (ninguno), juegos | Sin decidir/descartado según el caso | Preguntar al dueño solo si cambia de idea |
| 5 | Webapps (Element, Tuta, Super Productivity) | Lanzadores creados, sin probar en `nwg-drawer` ni con el dedo | Abrirlas en la tablet y revisar escala y teclado en pantalla |
| 6 | Super Productivity en la tablet | Tres vías: `sp-nativo` (143 MB, interfaz «muy mal» según el dueño), `sp-web` (806 MB, idéntico a la oficial), PWA en Firefox; sync completa con el oficial aceptada en pruebas aisladas, escritura contra su Nextcloud real NO autorizada | Elegir vía; si `sp-nativo`, mejorar la interfaz y empaquetar `PKGBUILD` aarch64 |
| 7 | Apuntes + Nextcloud + IA (sesión `notas-nativas`, activa) | `nextcloud.toml` y WebDAV probados en el portátil; falta `nextcloud-client`/`xournalpp` (portátil y tablet) | La gestiona esa sesión |
| 8 | Immich nativo (sesión `immich-nativo`) | F1 y F2 hechas contra mock; falta URL y API key reales del servidor (en `~/.config/immich-nativo/config.json`, escrita por el dueño) | Retomar cuando haya URL/API key; sesión pausada por la gestora |
| 9 | Instalado y verificado el 21-oct | delfin, mpv-mpris, scrcpy+android-tools, komikku, foliate (+55 deps) con `pacman -U`; protobuf manual preservado con `--assume-installed` | Nada; listas previas en `/root/pkgs-*-pre-apps-20261021.txt`, paquetes en `/root/pkgs-apps` |

### Actualización 21-oct-2026 (aviso de la sesión `notas-nativas`, no verificado por esta sesión)
`xournalpp 1.3.8` fue **instalado en la tablet** por la sesión de Apuntes (`pacman -U`, sin reiniciar; comprobó que dibuja la capa «ia» y exporta a PNG sin ventana). Corrige las menciones anteriores de «Xournal++ NO instalado». Pendiente en la tablet: sincronización Nextcloud (`nextcloud-client` requiere `-Syu`; la sesión propone un script WebDAV propio, sin decidir) y probar la corrección IA con un proveedor real.

## Retomado 22-oct-2026 (decisiones del dueño: sp-nativo; Immich con config puesta)
- **Immich nativo verificado contra el servidor real** (`http://100.64.0.13:2283`, Immich v3.3.5, `check --json` → 9545 assets): línea de tiempo con miniaturas OK en captura offscreen, RSS 130 MB (presupuesto < 150 MB). Pendiente: medir en Wayland con scroll, favoritos/álbumes reales, F3/F4, despliegue en la tablet (sin autorizar; la tablet no llega a 100.x sin TUN).
- **Super Productivity: el dueño elige `sp-nativo`** (143 MB). Commit `cd1f3ab` en su repo: lateral plano sin ripple (arregla el círculo gris), barra de acento, carpetas como rótulo, ganchos `SPN_SHOT`/`SPN_VIEW` para capturas; 21/21 tests. Siguientes pasos: pulir la lista de tareas (espaciado, chips, iconos como la web), traducción al español, fetch real contra Nextcloud (credenciales las teclea el dueño), medir Electron, PKGBUILD aarch64.

### sp-nativo: lista pulida y en español — 22-oct-2026 (subagente, verificado por esta sesión)
Commits `bfef950` (i18n: locale del sistema, es con plurales) y `e85d5b2` (lista: casilla 20 px con zona táctil de 52, chips con color, tarea activa resaltada, cabecera con contador, barra de añadir, estado vacío; ganchos `SPN_ACTIVE`/`SPN_SELECT`). `bin/test` 21/21 (rehecho aquí), RSS 109–116 MB offscreen (tope 150), capturas revisadas. Dudas: no visto en la tablet ni en vertical; emojis de títulos reales desentonan; colores de etiqueta solo probados con datos de ejemplo.

### Immich nativo probado a fondo contra el servidor real — 22-oct-2026 (subagente, verificado por esta sesión)
Solo lecturas (Immich v3.3.5, 9545 assets). OK: timeline columnar (35 meses), álbumes, búsqueda smart, visor foto/vídeo, vídeo vía mpv (30 fotogramas con `--vo=null --ao=null`). Favoritos: el servidor no tiene ninguno. Arreglado (commits `9dc8ee5`…`7e68ede` en `~/proyectos/immich-nativo`): botones del visor invisibles, `/server/about` 401/403 ya no impide conectar, favoritos con `PUT /assets/{id}` (solo probado con el mock), `es.json` completo; `bin/test` 11/11 (rehecho aquí); la API key NO aparece en git ni en ficheros (comprobado). RSS 130–137 MB offscreen (pico con 40 s de scroll), tope 150. **Pendiente:** key mínima dedicada (la del dueño es `all`/admin; recomendado asset.read, asset.view, asset.update, album.read, user.read) y repetir; probar `PUT` real solo con permiso del dueño; RSS en Wayland real y en la tablet; F3/F4; círculo gris en la esquina de la barra (☰) en offscreen, revisar en pantalla real.

### Immich nativo F3 (subida manual + Personas) — 22-oct-2026 (subagente, verificado por esta sesión)
`bin/test` 17/17 (rehecho aquí), clave no aparece en git ni ficheros. Subida (botón ⬆, SHA-1 por streaming, `bulk-upload-check`, `POST /assets`, reintentos, cancelación, CLI `upload`) probada SOLO contra el mock (CLI con vídeo de 600 MB: 82 MB de RSS); NO se escribió nada en el servidor real. Personas (282 en el real, solo GET): rejilla paginada y línea de tiempo por persona vía `timeline/bucket?personId=` (`personIds` de `/search/metadata` está deprecado desde v3.2.0). Diferencias doc↔v3.3.5: `POST /assets` ya no pide `deviceAssetId`/`deviceId`. Pendiente: probar la subida real con permiso del dueño (la key necesita `asset.upload`), diálogo de ficheros real en Wayland, subir carpetas, F4 (mapa, enlaces, papelera). RSS GUI 135–141 MB.

### Impacto del -Syu (Qt 6.12, systemd 262) — 22-oct-2026 (dos informes de subagentes de solo lectura; certezas en cada informe)
Informes: `QUICKSHELL-QT612-FUENTE-20261022.md` (commit 2017fb1) y `QT612-IMPACTO-20261022.md` (commit 5da7f4f). Resumen para el pendiente #1 (`-Syu`):
- **No hace falta compilar Qt ni quickshell**: Omarchy publica quickshell reconstruido contra Qt 6.12 (edge `quickshell-0.3.2.r7.g2b4501a-2`, 21-oct; stable `-1`), pero la shell instalada `omarchy 4.0.4-2` no lleva el pragma que evita el bug de upstream #1295 (aparece en omarchy 4.0.5/4.0.6) → actualizar quickshell + `omarchy`/`omarchy-settings` 4.0.6 juntos y probar la barra en sesión aparte (no verificado que la 4.0.4 se rompa).
- **IgnorePkg**: `linux-aarch64`, `linux-firmware-atheros`, `linux-firmware-other`, `linux-firmware-whence` (el firmware ath11k/WCN6750 propio quedaría pisado); mkinitcpio 42 inerte (hooks vacíos en `/etc/pacman.d/hooks`).
- **Guardia**: `OMARCHY_ALLOW_DIRECT_PACMAN=1`; fases: `-Syuw`, base (systemd+util-linux+openssh juntos), Qt 6.12 + quickshell con `-U`; rollback de Qt con `build/stage-escritorio/` del PC; **sin copia de systemd 261.2** (único punto sin vuelta fácil: dejar `systemd*` en IgnorePkg un ciclo).
- **Hallazgo nuevo**: el plugin Navidrome importa `QtMultimedia`, que **no está instalado** en la tablet → ya estaba roto antes del `-Syu` (hay que instalar `qt6-multimedia` o cambiar el plugin; no hecho).
- Sin verificar: que el `-Syu` completo deje la tablet arrancando; compatibilidad de quickshell `r7` con los plugins uke/powerbar y de omarchy 4.0.6 con hyprland 0.56.2-4 local.

## Actualización 22-oct-2026 ~16:05 (sesión resto-apps, orden del dueño «desinstala»)
- **Sin webapps**: borrados de `~omarchy/.local/share/applications` los 14 lanzadores web (Element y Tuta de madrugada; Basecamp,
  Discord, Google Contacts/Maps/Messages/Photos, HEY, SuperProductivity (PWA), WhatsApp, X, YouTube y Zoom ahora). Copias en
  `/root/backup-webapps-20261022`. Ojo: una actualización de Omarchy que reinstale sus webapps de serie podría volver a crearlos.
- **Strawberry desinstalado** (`pacman -Rns`, 17 paquetes, 53 MB): no es apto para el dedo (ver `RESTO-APPS-DICTADO-20261022.md`
  §7). Música: plugin Navidrome de la barra (pendiente del reenvío) o Delfin si hay música en Jellyfin.
