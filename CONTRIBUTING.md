# Como contribuir

Este repo es el cuaderno de trabajo de un port: **Arch Linux ARM + Omarchy a la
Xiaomi Pad 7 (`uke`)**. La mayor parte del contenido son informes de sesiones
con la evidencia que se midio en el aparato. Las correcciones valen mas que los
informes nuevos.

## Que es util

- **Correcciones de los informes.** Si un dato esta mal (un sha256, una linea de
  `uname -a`, una ruta, el estado de un par `boot`/`dtbo`), corrigelo y explica
  de donde sale el dato correcto. Los hashes de commit que citan los documentos
  son del repo privado de origen y **no existen aqui**: no se pueden verificar
  contra este historial.
- **Fallos reproducibles.** Abre un issue con la plantilla de
  `.github/ISSUE_TEMPLATE/bug_report.yml` y, si sabes de donde sale el fallo,
  el parche o el script que lo arregla.
- **Portabilidad.** Scripts que asumen un camino, una distro o una herramienta
  concreta; o que no comprueban el error antes de seguir.

## Que no es util

- **Volcados del fabricante.** Ni firmware (`.mdt`/`.bNN`/`.mbn`/`.bin`), ni
  ACDB, ni `.fsm`, ni modulos `.ko`, ni imagenes, ni `vendor`/`odm` de Android.
  Van por sha256 y su origen, nunca en el repo (ver `.gitignore` y la seccion
  "Que NO hay" del README).
- **Reportes de pruebas sobre el aparato.** Esta instantanea se publica sin
  historial y el aparato no es reproducible por quien lee.

## Reglas de los informes

1. **Cita la evidencia.** Cada afirmacion tecnica apunta al fichero, al log o
   al comando que la sostiene. Sin eso, es una opinion.
2. **Distingue lo medido de lo supuesto.** `medido:` / `supuesto:` / `plan:`.
   El proyecto separa informe (dato) de plan (intencion); no los mezcles.
3. **No pegues secretos.** Sin contrasenas, PSKs, tokens, IPs reales de casa ni
   series del aparato. El CI corre `gitleaks` y falla si aparece uno.
4. **No toques el aparato.** Nadie deberia flashear nada siguiendo este repo
   sin leer antes `REGLAS.md` y el aviso del `README.md`. El port puede dejar la
   tablet sin arrancar.

## Estilo

- Markdown en español, como el resto del repo.
- Scripts en `bash`/`sh` con `set -euo pipefail` cuando puedan.
- Nombres de fichero con fecha: `INFORME-<TEMA>-AAAAMMDD.md`.
- Licencia: **GPL-2.0-or-later** (los ficheros GPL-2.0-only, como los del kernel, conservan la suya;
  ver `THIRD-PARTY.md`). Los ficheros que vienen de otros
  proyectos conservan su licencia original y su cabecera.
