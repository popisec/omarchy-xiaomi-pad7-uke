# Procedimiento slot A/B — hemorragia de reintentos (riesgo nº1)

**Estado 27-sep-2026:** el slot **b** está activo pero **NO marcado como bueno**
(`qbootctl` en la tablet: `Successful: 0`). Cada arranque resta 1 al
`slot-retry-count`; a 0 el ABL marca `unbootable` y la tablet no arranca hasta el
reset manual. **El riesgo SIGUE ABIERTO**: hay herramienta y vigilancia, falta la
decisión de marcar el arranque como bueno.

## 1. Vigilar (solo lectura, sin riesgo)

```bash
build/gates/uke-slot-check.sh linux      # por SSH; exit 1 + aviso si Successful=0
build/gates/uke-slot-check.sh fastboot   # con la tablet en fastboot (coordinar
                                         # con el proyecto hermano); avisa si
                                         # algún retry-count < 3
```

El log acumulado vive en `build/slot/slot-log.tsv`. Estado de referencia:

```
Current slot: _b
SLOT _a: Active 0, Successful 0, Bootable 1
SLOT _b: Active 1, Successful 0, Bootable 1   ← la hemorragia
```

## 2. Reset cuando el contador llega a 0 (fastboot, proyecto hermano)

```bash
fastboot getvar all | grep -iE 'slot-retry-count|unbootable|current-slot'
fastboot set_active a && fastboot set_active b   # devuelve retry a 7
fastboot getvar all | grep -iE 'slot-retry-count|unbootable|current-slot'
```

Registrar mV + los 4 contadores antes/después en la fila del ledger de origen.

## 3. La solución de fondo: `qbootctl -m` — **DECIDIDO Y EN USO (22-oct-2026)**

> ⚠️ **Este apartado estaba desactualizado.** Cuando se escribió (26-sep) la decisión estaba
> pendiente y la instrucción era «no ejecutar». **Desde el 22-oct-2026 sí se ejecuta**: la
> unidad `uke-boot-ok.service` llama a `qbootctl -m` a los ~130 s de cada arranque sano, y el
> 22-oct marcó el slot `_a` (`Successful 1`). Ver `NOTAS-OMARCHY.md` 22-oct 01:58.
>
> **Por qué seepta el riesgo:** sin marcar el slot, el ABL **descuenta un reintento en cada
> arranque** (`slot-retry-count`) y a los 7 marca el slot como *unbootable* y salta al otro
> slot (Android → recovery). En una tablet cuyo arranque se prueba muchas veces, eso es un
> bloqueante peor que el riesgo de la escritura GPT.
>
> **Lo que sigue en pie:** `qbootctl -m` escribe los atributos GPT de 12 particiones de DOS
> discos, incluida **`vbmeta_system` en `/dev/sda`, el disco del rootfs vivo** (no toca
> `misc`/BCB). El riesgo está asumido y documentado, no eliminado.
>
> ⚠️ **`arranque-slot/` no tiene `deploy.sh`**: la unidad **no es instalable desde este repo**
> de forma reproducible, aunque esté desplegada en la tablet. Publicar su receta es una
> decisión pendiente.

- Binario: `/usr/local/bin/qbootctl` en la tablet
  (sha `629434acd40f3e6b03c3ba619ff94a4e46b49daf000f814a24cff5f9a85b64ab`,
  construido con `build/slot/build-qbootctl-aarch64.sh`, copia en `build/slot/`).
- Comandos seguros (solo lectura, verificados en la tablet + por lectura de código):
  `qbootctl` (dump), `-c`, `-a`, `-b SLOT`, `-n SLOT`, `-x`.
- **Peligroso: `qbootctl -m b`.** Escribe los atributos GPT (cabeceras + arrays,
  primaria y backup, con CRC recalculados) en **12 particiones de DOS discos**:
  11 pares en `/dev/sde` y **`vbmeta_system` en `/dev/sda`, el disco del rootfs
  vivo**. No toca `misc`/BCB nunca (verificado por grep en el fuente 0.2.2).
- Por qué no se ha ejecutado: (a) es una escritura GPT desde Linux, la misma
  familia que la R1 del hermano prohíbe fuera de `fastboot set_active`
  (el brick del 11-sep-2026 fue editando attrs de GPT); (b) cliffs/uke **no está
  en la lista de dispositivos validados** de la wiki de pmOS; (c) el aviso
  upstream sigue vigente: *"may or may not render any hardware you run it on
  unusable"*; (d) requiere fila pre-registrada en el ledger de origen y
  coordinación (un cambio por ciclo).
- Para decidir: el `dump`/`-n`/`-b` ya están; lo que falta es validar `-m` en un
  ciclo con consola armada, vigía de fastboot y par bueno en el otro slot.

## 4. Qué NO sirve (descartado con evidencia)

- `bootctl` (systemd): exige EFI; la tablet no tiene `/sys/firmware/efi`
  (`bootctl status` → "Not booted with EFI"). Inútil aquí.
- Limpiar/escribir el BCB de `misc`: los contadores de slot viven en los
  **atributos GPT (bits 48-63)**, no en `misc`. `misc` solo lleva el BCB
  (medido: `command="bootloader"`, resto ceros). Que el ABL ignore el BCB
  (medición del hermano) es ortogonal: el ABL sí lee la GPT para los slots.
- `qbootctl` no existe en ALARM (verificado en `core/extra/alarm/aur` .db del
  27-sep-2026) ni compilado en ningún repo; el AUR lo tiene (`qbootctl 0.2.2-1`,
  `arch=($CARCH)` ⇒ apto para aarch64) pero el AUR es x86_64-first y no había
  binario: por eso se cross-compiló.
