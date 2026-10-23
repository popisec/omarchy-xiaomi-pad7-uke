# build/ — el motor del proyecto

> ⚠️ **Este fichero estaba obsoleto** (describía la estructura y el entorno del 27-sep-2026, con
> carpetas que ya no existen). La descripción actual está en
> [`../INDICE-DOCUMENTACION.md`](../INDICE-DOCUMENTACION.md) §4 y en
> [`../BUILD.md`](../BUILD.md).

## Qué hay aquí

| Carpeta | Contenido |
|---|---|
| `gates/` | El motor: scripts de build, empaquetado de `boot.img`/`dtbo`, verificación, pre-registros e informes de cada ciclo. Los subdirectorios `prepara/`, `patches/`, `revision/` y `tools/` cuelgan de aquí |
| `rootfs/` | Construcción del rootfs y **todos los despliegues** sobre la tablet (`rootfs/deploy/<tema>/`) |
| `kernel-config/` | Un `.config` por cada kernel probado (`k23b`…`k52L76r`) |
| `pkg/` | PKGBUILD que empaquetan firmware que hay que extraer del fabricante |
| `slot/` | Procedimiento y scripts del swap de slots A/B |
| `cm3-ladder/` | Medida del CM3 (la pieza que cuelga la tablet) |
| `tools/` | Utilidades (export de Ghidra) |
| `linux-l76r-20261017/`, `linux-senemos-20261017/` | Capturas de estado (`dmesg`, DRM, clocks) de dos builds concretos |

## Reglas

- **Nada se flashea sin pasar los gates**: ver [`../REGLAS.md`](../REGLAS.md).
- **Un cambio por ciclo**, con su fila pre-registrada en
  `build/gates/PRE-REGISTRO-PANTALLA.md`.
- **Nunca se versionan binarios del fabricante** (`.ko`, firmware, imágenes): van por sha256.
  Lo que el `.gitignore` excluye no se publica; el verificador `tools/check-links.py` lo sabe.
