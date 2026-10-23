# Dudas y tareas del dueño — sesión «resto de apps + dictado» (noche del 22-oct-2026)

La sesión trabajó sola mientras el dueño dormía. Aquí va lo que necesita una respuesta o una acción suya.
Nada de esto bloquea lo demás: se siguió con valores por defecto razonables.

## Inicios de sesión y cuentas (los hace el dueño)
| App | Qué hacer | Notas |
|---|---|---|
| Fractal (Matrix) | Abrir Fractal → «Iniciar sesión» → servidor → navegador (OIDC/MAS) o usuario+contraseña. Después **verificar la sesión** desde otro dispositivo (emojis/QR) o con la **clave de recuperación** para descifrar el historial. | El llavero es gnome-keyring (ya instalado): la primera vez puede pedir crear la contraseña del llavero. |

## Preguntas
1. **Otras webapps de Omarchy en la tablet**: además de Element y Tuta (borradas), en `~omarchy/.local/share/applications/` quedan
   las webapps que trae Omarchy de serie (Basecamp, Discord, Google Contacts/Maps/Messages/Photos, HEY, WhatsApp, X, YouTube,
   Zoom) y `SuperProductivity.desktop` (PWA en Firefox, aunque elegiste `sp-nativo`). Como dijiste «no quiero webapps»,
   ¿las borro todas? → **RESUELTO 22-oct ~16:05: el dueño dijo «desinstala»; borradas las 12** (copia en
   `/root/backup-webapps-20261022`).
2. **Navidrome en la barra (plugin `backmeupplz.navidrome`) y Strawberry**: ninguno sabe usar proxies, y la tablet solo llega a
   la tailnet por el proxy de tailscaled (`127.0.0.1:1055`). Propuesta lista, **no instalada** (el clasificador de permisos de la
   sesión no deja instalar servicios persistentes sin tu visto bueno): servicio `uke-navidrome-fwd` (socat, `127.0.0.1:14533` →
   `PC-PORTATIL:4533` por el proxy) + `navidrome.json` apuntando a `http://127.0.0.1:14533`. Para aplicarlo:
   `build/rootfs/deploy/resto-apps/deploy.sh navidrome` (revertir: `deploy.sh revert`). ¿Lo instalo? → **RESUELTO 22-oct ~19:26**:
   instalado, plugin activo y parche de Omarchy aplicado (informe §11). Reaplicar el parche tras actualizar Omarchy.
3. **Kavita está detrás de Authelia** (`https://SERVIDORhost.tailnet-ejemplo.ts.net:9455` → 302 a `:9443`). Komikku y Foliate hablan
   OPDS/API con usuario y clave o API key, no pueden pasar el login web de Authelia. Opciones: (a) regla `bypass` en Authelia
   para `^/api/opds/.*` y `^/api/.*` de Kavita (la autenticación la hace Kavita con su API key); (b) exponer Kavita sin
   Authelia solo en la tailnet. → **RESUELTO 22-oct ~19:20: opción (b)**, ver informe §10 (Caddy sin Authelia en :9455 +
   `tailscale serve` de Kavita en PC-PORTATIL:5001). Falta tu login en Komikku y la API key para Foliate.
4. **Servidor Matrix**: ¿usas matrix.org u otro? Si es uno de la tailnet, Fractal ya sale por el proxy (`uke-tailnet`).

5. **Llavero (gnome-keyring)** → 22-oct: el dueño lo deja como está por ahora.: Fractal (y cualquier app que guarde sesiones) pide crear la contraseña del llavero «Default» la
   primera vez. Si la tablet entra sin contraseña (autologin), una contraseña de llavero obliga a teclearla en cada arranque;
   dejarla vacía guarda los secretos sin cifrar en disco. Decisión tuya; no la he creado.
6. **Prueba del dictado con tu voz**: abre cualquier campo de texto, toca «🎙 Voz», habla y toca «■ Parar». Con audio
   reproducido por el altavoz de la propia tablet sale regular (nivel bajo); con voz real debería ir mucho mejor (WER 2,4 % en
   el banco). Si notas que corta el final o cambia de idioma, dímelo.
7. **Strawberry**: probado, es interfaz de escritorio (iconos de ~3 mm). Recomiendo el plugin Navidrome de la barra (pregunta
   2). ¿Desinstalo Strawberry (`pacman -Rns strawberry`) o lo dejas? → **RESUELTO 22-oct ~16:05: desinstalado** con sus 17
   dependencias; su config está en `/root/backup-resto-apps-20261022/strawberry*`.

## Logins pendientes (además de Fractal)
| App | Servidor | Notas |
|---|---|---|
| Delfin (Jellyfin) | `https://SERVIDORhost.tailnet-ejemplo.ts.net:9444` (**ya añadido** en Delfin, servidor `d728b050740f`) | usuario + contraseña de Jellyfin |
| Komikku / Foliate (Kavita) | `https://SERVIDORhost.tailnet-ejemplo.ts.net:9455` | **ya accesible** (sin Authelia); Komikku: Kavita → dirección + usuario + contraseña; Foliate OPDS: `…/api/opds/<API key>` |
| Plugin Navidrome de la barra | `http://127.0.0.1:14533` | **funcionando** (token ya en `navidrome.json`) |
| scrcpy | Nothing Phone 2a por Tailscale (`nothing-phone-2`, 100.64.0.14) o LAN | activar Depuración inalámbrica y emparejar (`adb pair`) la primera vez desde el móvil |
