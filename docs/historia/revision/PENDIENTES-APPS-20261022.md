# PENDIENTES — sesión «apps tablet» (cierre del 22-oct-2026)

Documento de traspaso. Estado vivo: `docs/historia/ESTADO-VIVO.md` + `NOTAS-OMARCHY.md`. Historia completa de la sesión en `build/gates/revision/APPS-TABLET-20261021.md`. Nada de lo de abajo toca la tablet sin «pido tablet» a la sesión gestora.

## 1. Hecho y verificado (con evidencia en los documentos citados)
- **Lista de apps acordada** con el dueño (`APPS-TABLET-20261021.md`): Jellyfin → Delfin nativo; Matrix → webapp Element; correo → webapp Tuta; lectura → Kavita en `PC-PORTATIL` con Komikku/Foliate; música → Navidrome (plugin Omarchy + Strawberry); fotos → app nativa Immich; apuntes → app nativa propia con Nextcloud e IA; tareas → sp-nativo; control del móvil → scrcpy; sin LibreOffice, sin mapas, sin mensajería extra.
- **Instalado en la tablet** (`pacman -U`, verificado el arranque): delfin, mpv-mpris, scrcpy + android-tools, komikku, foliate (+55 dependencias; protobuf manual preservado con `--assume-installed`). Lanzadores `.desktop` de Element, Tuta y Super Productivity (Firefox) en `~omarchy/.local/share/applications/`. `xournalpp` y otros 10 paquetes los instaló la sesión Apuntes (sin verificar por esta sesión).
- **`-Syu` a Qt 6.12 completo** (`build/rootfs/deploy/syu-qt612/README.md`): fase 0 (copias + `-Syuw`), fase 1 (135 paquetes: systemd 262.1, util-linux 2.42.4, openssh 10.6p1-2…, con `--overwrite` acotado a 261 ficheros sin dueño: el rootfs era un híbrido), fase 2 (Qt 6.12, quickshell `0.3.2.r7-1`, omarchy 4.0.6 + omarchy-themes-intros). Reinicio de verificación VERDE (`uke-boot-ok` marcó el slot, sistema `running`, WiFi, Tailscale y barra bien). Regresión de systemd 262 corregida (comentarios al final de línea en `uke-audio.service` y `uke-optim.conf`).
- **Migraciones de Omarchy**: las 14 marcadas como hechas sin ejecutar (enlaces aplicada a mano; Firefox sin nada que cambiar; KEF descartada); `omarchy-migrate --pending` vacío.
- **Regla permanente `uke-hold.conf`** (IgnorePkg `linux-aarch64 linux-firmware* mesa quickshell` + NoUpgrade de firmware propio): `pacman -Su --print` y `-Suu --print` vacíos. Backup `/root/pacman.conf.pre-hold-20261022`.
- Rollbacks: tablet `/root/syu-qt612-20261022/` (+ `rollback/*.pkg.tar.zst` de systemd, pacman, openssh, openssl, util-linux), PC `~/backups/uke-qt612-20261022/` y `build/stage-escritorio/` (Qt 6.11.2, quickshell 0.3.2-3, omarchy 4.0.4).

## 2. Apps nativas (en el PC; ninguna instalada en la tablet)
| App | Repo / último commit | Estado | Falta |
|---|---|---|---|
| **immich-nativo** (Qt Quick, sin Electron) | `~/proyectos/immich-nativo` · `1661b0f` | F1–F3 hechas (línea de tiempo, álbumes, favoritos, búsqueda, visor, vídeo con mpv, subida manual con cola, Personas); `bin/test` 17/17 (rehecho); verificada solo con LECTURAS contra el servidor real (v3.3.5); la clave NO está en git (comprobado). PKGBUILD x86_64/aarch64, `.desktop`, icono, `deploy/instalar-tablet.sh` (solo `bash -n`) | Subida real (necesita permiso `asset.upload` y orden del dueño); key mínima dedicada (la actual es `all`/admin); RSS en Wayland real: ~240 MB RSS / 139 MB PSS en el PC con GPU (el tope de 150 MB solo vale offscreen o en la tablet: medir allí); arrastre con ratón/pinch/diálogo del portal sin probar; F4 (mapa, enlaces, papelera); círculo gris de la barra en offscreen |
| **sp-nativo** (cliente nativo de Super Productivity) | `~/proyectos/super-productivity-nativo` · `83298b1` | Elegido por el dueño frente a sp-web (806 MB). Lista pulida y en español, 21/21 tests, escritor verificado contra SP 19.1.0 aislado; PKGBUILD x86_64/aarch64, `.desktop`, icono, `deploy/instalar-tablet.sh` (solo `bash -n`) | Fetch REAL de solo lectura contra Nextcloud (lo teclea el dueño: `sp-nativo setup`); escritura real (casos sin verificar); gancho `SPN_DRIVE` se colgó una vez (¿hook o app?), uso táctil sin probar; RSS ~232 MB en el PC con GPU (108–124 MB offscreen; 143 MB medido en la tablet antes de la UI nueva: re-medir); medir el Electron oficial |
| **notas** (apuntes + Nextcloud + IA) | `~/proyectos/notas-nativas` · `c140830` y posteriores (informe de la sesión Apuntes, no verificado por esta sesión) | Decisión B+: Xournal++ + capa «ia» + `notas-ia correct` + `notas-sync` (WebDAV, 9 tests; subida/bajada/borrado reales probados con un fichero de prueba, remoto limpio); paquete `notas` construido en el PC | IA real: `ods-token-spy` (127.0.0.1:10009 en `SERVIDOR-01`) con `ods-litellm`/`ods-model-router`: falta URL de acceso desde fuera, modelo con visión y el token en `~/.config/notas/ia.toml` (lo pone el dueño); instalar en la tablet |

## 3. Bloqueos y dependencias
- **Red de la tablet hacia `PC-PORTATIL`/`SERVIDOR-01`**: `tailscaled` va en `--tun=userspace-networking` (TUN falló: el kernel no tiene `CONFIG_NF_TABLES`). Bloquea Navidrome, Delfin→Jellyfin, Komikku→Kavita, Nextcloud, Immich y Token Spy desde la tablet. Decisión del dueño: **esperar al kernel con NF_TABLES** (sin puente SOCKS); la prepara la sesión de optimización. Después: `FLAGS=""` + `tailscale set --netfilter-mode=on` con reversión automática (`NOTAS-OMARCHY.md` 22-oct 02:00, `deploy/tailscale/README.md`).
- **Plugin Navidrome** (`backmeupplz.navidrome`, `navidrome.json` ya copiado a la tablet, sin activar): importa `QtMultimedia`, que no está instalado (`qt6-multimedia`); además depende de la red anterior y de activarlo en `shell.json`.
- **Strawberry**: ya instalable (DB alineada), comprobando antes con `pacman -S --needed --print` que no arrastra mesa/firmware (la regla `uke-hold.conf` los ignora).

## 4. Decisiones abiertas del dueño
1. Cuándo instalar immich-nativo, sp-nativo y notas en la tablet (cada uno con «pido tablet»; los scripts `deploy/instalar-tablet.sh` están sin probar).
2. Credenciales/pruebas reales: URL y modelo de Token Spy + token; `sp-nativo setup` (fetch real); key mínima de Immich y permiso de subida real.
3. Si activa el plugin Navidrome (instalar `qt6-multimedia`) o usa Strawberry/Delfin cuando haya red.
4. Mesa 26.2.5, kernel 7.2.11 y `linux-firmware` nuevos: congelados a propósito; subirlos solo por fases con backup, quitando la entrada de `IgnorePkg` a conciencia.

## 5. Avisos
- NO ejecutar en la tablet: `omarchy-upgrade-to-quattro` (`--overwrite='*'`), `omarchy refresh pacman`, `omarchy-reinstall-pkgs`, `pacman -S mesa`/`-S linux-aarch64`, ni `omarchy update` sin revisar. El hook de usuario del informe `ESTABILIDAD-REGLAS-20261022.md` no está instalado.
- Una versión futura de `omarchy` que añada migraciones volverá a mostrar el aviso: revisarlas antes (`migraciones.sh plan`).
- Webapps (Element, Tuta, Super Productivity) sin probar en `nwg-drawer` ni con el dedo; la de enlaces (`hyprland-mimeapps.list`) sin probar con un enlace real.
- Los scripts de instalación de las apps nativas exigen revisar rutas de batería, usuario `omarchy` y `sudo` antes de ejecutarlos.
- Fotos personales: las capturas de Immich contienen contenido del dueño; no van al repo.
