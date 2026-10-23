# Seguridad

## Qué se considera una vulnerabilidad aquí

Este repo publica volcados del aparato de un port experimental. Un informe que
incluya datos que **no** deberían ser públicos es un problema de seguridad:

- Tokens, claves de API, contraseñas o claves privadas de sesión.
- Contraseñas o PSKs de WiFi.
- Claves de nodo de Tailscale, claves SSH del host o `/etc/shadow`.
- Números de serie, IMEI o identificadores únicos del aparato.
- IPs privadas de una red doméstica o de una tailnet que no sea de ejemplo.

La CI ejecuta `gitleaks` sobre cada push y falla si aparece un secreto; el
comprobador de binarios también bloquea los blobs del fabricante.

## Cómo reportarlo

Abre un issue privado (**Security advisory**) en este repo, o escribe a
`popisec@tutamail.com` desde la página del repo. **No abras un issue público**
con el dato dentro: en cuanto hay issue, hay notificación.

Incluye:

- Qué fichero y qué línea (o el commit).
- Qué clase de dato es.
- Si el dato está en el historial o solo en la última instantánea.

## Qué pasa después

- Se revisa en cuanto llega.
- Se retira el dato y se reescribe el historial si hace falta (este repo se
  publica **sin historial**, así que normalmente basta con un commit nuevo).
- Si el dato es una credencial viva, se revoca en origen y se avisa a quien
  corresponda.

## Alcance

Este repo es documentación y scripts, no software que se ejecute en un servidor
con datos de terceros. Las incidencias que importan son las **fugas de datos**,
no los fallos de los scripts de despliegue.

## Lo que ya está anonimizado

La instantánea pública ya viene con datos de red y del aparato sustituidos:
IPs → `192.0.2.x` / `100.64.0.x`, MAC → `02:00:5e:00:00:xx`, serie →
`SERIE0001`, SSID → `RED-EJEMPLO-n`, contraseñas → `<CONTRASEÑA…>`, nombres
de host → `PC-PORTATIL` / `SERVIDOR-01`, rutas del entorno original →
`/home/USUARIO` y `~/proyectos/<proyecto>`. El enlace USB `192.168.42.x` sí es
el real, pero es el rango estándar de RNDIS en Android.

La CI lo vigila: `gitleaks` para los secretos, `tools/check-privacidad.py` para
las rutas, IPs, correos y MACs, `tools/check-manifests.py` para que los
manifiestos de despliegue cuadren, y `tools/check-assets.sh` para los ficheros
publicados como release (un asset comprimido es invisible para el resto de
comprobaciones).
