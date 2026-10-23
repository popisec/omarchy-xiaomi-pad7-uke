# AUDIO — copia de seguridad verificada de `userdata` y pre-registro del ledger para la ida a Android — 19-oct-2026

**No se tocó la tablet** salvo `--check`: lectura ligera por SSH (tune2fs, blockdev, df, batería). Nada se ha copiado ni escrito.

## Hechos medidos (solo lectura, 10:54)
- El rootfs Linux **es `userdata`**: `/dev/sda32`, ext4 montado rw (`norecovery`, **sin diario**, estado «not clean» permanente), 2 097 152 bloques × 4096 B = **8 589 934 592 B (8 GiB)**, usado 6,58 GB (83 %), partición de 113 657 229 312 B (106 GiB). Batería 4,33 V, `Charging`.
- Espacio libre en el PC: 121 GB (necesario ≈ 19 GB para la imagen cruda + la `.zst`).
- Copias antiguas en el PC (`/var/tmp/rootfs-v7/v8-backup-*.img`, 4 GiB, 6-7 oct) **no sirven**: son de otra generación del rootfs.

## Qué se ha preparado
| Pieza | Qué hace |
|---|---|
| `build/gates/backup-userdata.sh --check` | Solo lectura por SSH: dispositivo, tamaño exacto, estado, batería, espacio en el PC (probado: OK) |
| `--go` | `dd` del fs por SSH (bloques de 4 MiB, tamaño exacto del fs) con `sha256` en la tablet **y** en el PC (integridad del flujo), `zstd` a `/var/tmp/uke-userdata-backup/userdata-<fecha>.img.zst`, descomprime a imagen cruda y comprueba su sha; aborta con batería < 3700 mV, sin espacio o ante cualquier discrepancia. Tiempo estimado 10-15 min por USB/RNDIS |
| `--verify IMG` | En el PC, sin root: `e2fsck -fn`, `dumpe2fs`, ficheros centinela con `debugfs -R cat` (`os-release`, `hostname`, `fstab`, `authorized_keys`, `uke-audio-up.sh`, `uke-audio.service`, `fs19xx.fsm`) e **ida y vuelta sparse** (`img2simg` → `simg2img` = mismo sha). Probado en el PC con una imagen sintética: OK |
| `--restore-plan IMG` | Imprime (no ejecuta) los comandos de la vuelta a Linux: `sha256sum`, `img2simg`, `fastboot flash userdata`, `set_active a` (doble si hace falta), `reboot`, y las tareas posteriores |
| Ledger hermano `docs/FLASH-LEDGER.md` **#662-#666** (PRE-REGISTRO, todas PENDIENTE) | #662 copia verificada (lectura), #663 `erase userdata`+`metadata`, #664 slot b (`boot_b`/`init_boot_b`/`dtbo_b` si no coinciden con `flash-b/`, `set_active b`), #665 `flash userdata` desde la copia, #666 `set_active a` + `reboot` + limpieza de `misc`. Cada una con prerrequisitos, criterio PASA y «Orden del dueño: PENDIENTE». *(El ledger vive en el repo hermano; la edición queda sin commit allí, como las anteriores)* |

## Consistencia y límites (honestos)
- La copia es de un fs **montado en lectura-escritura**: «consistente ante caída», no congelada (no se congela: `fsfreeze` bloquearía escrituras del propio sistema/SSH). Con el sistema en reposo (sin pruebas de audio, sin `pacman`) el riesgo es bajo; `--verify` lo comprueba con `e2fsck -fn`. Si saliera con errores, se repara **solo la copia** (`e2fsck -fy`) y la imagen reparada es la que se restaura; se registra su sha.
- «Prueba de restauración» **no destructiva**: integridad de la transferencia + descompresión + fsck + centinelas + ida y vuelta sparse. La restauración real por `fastboot flash userdata` no se puede ensayar sin borrar (solo se haría en #665); la receta ya se ejecutó dos veces con éxito (`docs/guias/LINUX-A-ANDROID-IDA-VUELTA.md`).
- El fs de 8 GiB cabe de sobra en la partición de 106 GiB; tras la vuelta el fs sigue siendo de 8 GiB (no se redimensiona).
- Android arranca sobre `userdata` vacía y el asistente exige **manos del dueño** (activar ADB y root) durante ~15-30 min.

## Autorización que se pide (por pasos; cada una aparte)
1. **Ahora, sin riesgo para el estado actual:** ejecutar `backup-userdata.sh --go` y `--verify` (lectura del `userdata` por SSH durante ~15 min; carga la tablet y el USB; **no escribe nada**). Resultado: una imagen verificada en el PC.
2. **Después y solo si la copia PASA:** decidir la ventana de la ida a Android (#663-#664), con las sesiones avisadas y el dueño en fastboot.

## EJECUTADA (MEDIDO, 10:55-11:02 del 19-oct) — copia verificada: **PASA**
Autorizada por el dueño (solo lectura de `userdata`; sin pruebas de audio ni pacman durante la copia). Logs: `build/logs/backup-userdata-*.log`.
- **`--go`:** 8 589 934 592 B de `/dev/sda32` en **4 min 19 s**; sha256 del flujo crudo **igual en la tablet y en el PC**: `e72914ed27711fa47ac70f935d9fe34d25295eccf8ca875dbd8bd7b59a1d2de8`; `.zst` 2,34 GB; la imagen descomprimida tiene ese mismo sha. Ruta (PC, fuera del repo): `/var/tmp/uke-userdata-backup/userdata-20261019-105504.img` (+ `.img.zst`, `.sha256`).
- **`--verify` sobre la cruda:** `e2fsck -fn` rc 4 con exactamente lo esperable de copiar un fs montado en vivo: mapas de bits y cuentas de bloques/inodos libres desajustados, 2 inodos con dtime 0, 4 entradas a inodos borrados y 4 inodos desacoplados, **todos en cachés/estado transitorio** (`/home/omarchy/.local/state/omarchy/agents/usage`, `.cache/omarchy/agent-usage`); sin daños en el árbol del sistema.
- **`--repair`:** copia `userdata-…-fsck.img` con `e2fsck -fy` **solo sobre la copia** (rc 1 = corregido); segunda pasada **limpia**; **sha256 de la imagen reparada (la que se restauraría): `6bd9c632b262e43c1034da642d07886e0a0a048866a3acdc4e49f426d146f59e`**. La imagen cruda original queda intacta.
- **`--verify` sobre la reparada:** fs `clean`, mismo UUID (`4bf2908c-6561-4b6e-81d5-5c0c534a39d9`), 2 097 152 bloques; los 7 ficheros centinela presentes (`os-release`, `hostname`, `fstab`, `authorized_keys`, `uke-audio-up.sh` 5672 B, `uke-audio.service`, `fs19xx.fsm` 4828 B); **ida y vuelta sparse con sha igual**; cabe en la partición (106 GiB).
- Corrección del script: la prueba sparse usaba `/tmp` (tmpfs de 5,5 GB libres) y fallaba con la imagen de 8 GiB; ahora usa un temporal en `/var/tmp/uke-userdata-backup/`.
**Estado: la tablet no se ha tocado más que con lecturas. Hay copia verificada; NO se ha hecho nada de la ida a Android (#663-#666 siguen PENDIENTE).**
