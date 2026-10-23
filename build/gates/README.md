# `build/gates/` — el motor del port

Scripts de build, empaquetado, verificación y flasheo; y los informes del ciclo
vivo. **Nada aquí se flashea sin pasar los gates** (ver
[`../../REGLAS.md`](../../REGLAS.md)).

## Que hay

| | |
|---|---|
| `senemos/` | **La receta reproducible del kernel**: tarball oficial de kernel.org + upstream público + parches propios. Empieza por su [`README.md`](senemos/README.md) |
| `revision/` | Los **226 informes vivos** del ciclo: lo que se lee para saber que funciona hoy |
| `patches/` | Los parches del kernel del linaje **historico** «palawan». El vigente esta en `build/rootfs/deploy/*/kernel/` y en `senemos/patches/` |
| `prepara/` | Preparaciones por tema (A1-G1): el guion de arranque, el instalador de Omarchy, la GPU, el lapiz, el WiFi, la energia, el audio. Son los `P2-lapiz.md`, `P3-wifi.md`… con su script |

## Los scripts sueltos

Los ficheros sueltos de este directorio, y las cuatro carpetas que cuelgan de él:

### La linea vigente (senemos)

| Script | Que hace |
|---|---|
| `flash-senemos-v7-gated.sh` | **El siguiente flasheo preparado, nunca ejecutado** (su cabecera lo dice: «NO EJECUTADO NUNCA, solo `--check`»). El vigente en la tablet es el **v6** (kernel `ouke5`); los `v2`…`v6` son las versiones anteriores, cada una con su rollback |
| `flash-senemos-gated.sh` | El primer flasheo de la serie |
| `repack-senemos-v7.py` | Empaqueta el `boot.img` de la versión vigente |
| `build-pokes.sh`, `build-fast.sh` | Builds del linaje palawan (historico) |

### Utilidad general (valen para cualquier linea)

| Script | Que hace |
|---|---|
| `backup-par-bueno.sh` | Backup del par `boot`+`dtbo` con su sha256 (regla 1 de `REGLAS.md`) |
| `backup-userdata.sh` | Copia del `userdata` (el rootfs) |
| `check-session-b.sh` | Comprueba la sesión en la tablet |
| `ciclo-restaurar-slot-a.sh` | Devuelve el slot A al estado bueno |
| `drain-to-fastboot.sh` | Vuelve a fastboot sin perder la sesión |
| `bcb-clean-8192.py` | Limpia el BCB de `misc` (los 8 KiB de ceros) |
| `cmdline-variant.py` | Variantes de la linea de comandos del kernel |
| `compilar-panel-o82.sh` | Compila el panel o82 y sus fuentes |
| `dump-log.sh`, `dump-rails-l.py` | Captura de logs y de los rails de alimentación |
| `gen-diff-acumulado.py` | Acumula los parches en un diff reproducible |
| `firmware-gpu.sha256`, `firmware-wlan.sha256` | Los sha del firmware que hay que traer |

## El linaje historico

Los **163 scripts** de la escalera «palawan» (K23 -> k77b: `build-k*.sh`,
`repack-k*.py`, `flash-k*.sh`, `auto-flash-*.sh`…) están en
[`../../docs/historia/gates-palawan/`](../../docs/historia/gates-palawan/README.md).

**No son codigo duplicado**: cada uno es una receta con sus propios gates
(testigos, perfiles G3, cmdlines, kerneis distintos). Colapsarlos en un script
parametrico perderia esos gates, que es justo lo que hace valioso cada uno. Se
archivan enteros, con sus referencias reescritas.

## Reglas

- Nada se flashea sin pasar los gates de `REGLAS.md`.
- Un cambio por ciclo, con su fila pre-registrada en
  `build/gates/PRE-REGISTRO-PANTALLA.md`.
- Nunca se versionan binarios del fabricante: van por sha256.
