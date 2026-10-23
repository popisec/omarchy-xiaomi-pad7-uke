# PRE-REGISTRO L43 — kernel ICC-tolerante (geni_icc_get) para desbloquear el bus I2C del KTZ (13-oct-2026, noche)

> Fila lista para pegar en `~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md` ANTES de flashear.
> **NO flasheado aún**: build en curso + repack pendiente de gates (y de la batería ≥3700 mV).
> Crítica adversarial previa: APROBADO compilar; sus 2 avisos de flash-time están aplicados aquí
> (invocación `--dsid` y nombres/shas exactos del rollback).

## Qué es (el "peldaño ICC" del ciclo del bus I2C)

`L43 = L19 + un hunk`: en `geni_icc_get()` (`drivers/soc/qcom/qcom-geni-se.c`) tolerar que
`devm_of_icc_get()` falle para `qup-core` / `qup-config` / `qup-memory` (helper
`uke_icc_get_tolerante`: log `UKE-L43-ICC` una vez + `path=NULL` + seguir). **Motivo medido en vivo
(#616)**: la ruta `qup-core` la provee `interconnect@0` (clk_virt), que no tiene driver atado
(`qnoc-palawan` ata los otros) → `-EPROBE_DEFER` eterno
(`a80000.i2c: deferred probe pending: geni_i2c: Failed to get 'qup-core' ICC path`). Los votos ICC
ya están neutralizados (`X9ICC-skip`) ⇒ seguir sin path es funcionalmente equivalente y desbloquea
el bus. Diff: `build/gates/patches/l43-icc-get-tolerante.diff`. Los 4 consumidores ICC toleran
NULL (`drivers/interconnect/core.c:665,714,766,807`).

## Artefactos

- Kernel: `build/kernel-pokes/k52L43-build/arch/arm64/boot/Image.gz` (sha en el log del build).
- Boot: `build/bootimg/boot-uke-k52L43.img` — **repack OBLIGATORIO con `--dsid`**:
  `python3 docs/historia/gates-palawan/repack-k52L43.py --dsid`
  (cmdline byte-idéntica a L19: 580 B con `video=DSI-1:d` + `msm.uke_gmu_shared=0`).
- **dtbo: NO se toca** — sigue el `s286` `33d153f2cec617e2a7c8512559d57a06e1a9c15844b57106ee0891374aa2f419`
  flasheado en #616 (es el bus I2C que queremos ver registrar).
- Gates del repack: heredados de L19 + nuevos `UKE-L43-ICC x1` y `X9I2C-icc-get-ok x1`.

## Criterio pasa/falla (prefijado, comandos exactos)

PASA (tras el boot, por SSH):
1. `dmesg | grep -c 'UKE-L43-ICC'` ≥ 1 **y** `dmesg | grep -c 'X9I2C-icc-get-ok'` ≥ 1
   (son nivel 6/pr_info: **no salen en consola con `loglevel=4`** — hace falta `dmesg` por SSH,
   doble captura ACM + SSH).
2. `/sys/class/i2c-adapter/` NO vacío (`ls`); en `/sys/bus/i2c/devices/` aparece el cliente del KTZ
   (`<bus>-0011`, addr 0x11) — el nº de bus se lee de ese nombre.
3. `i2cdetect -y <bus>` con respuesta en **0x11** (KTZ8866) y anotar cualquier otra dirección
   (TDDI/`wcd939x@0e`).
FALLA: wedge / 0 B de consola / regreso a fastboot / adapter sigue vacío **sin** marcador L43.

## Rollback (nombres y shas exactos)

- `boot_a` ← `build/bootimg/boot-uke-k52L19.img` sha
  `71d89ca6e875941b75af012ac24d20fb7690de407fa341923f2d896557ee51a9` (par estable; copia en
  `build/backup-par-bueno/`).
- `dtbo_a` ← (solo si hiciera falta) `build/bootimg/s275-boot-dtbo-gpu-display.img` sha
  `67a65bc161b645d8664c4ba3fd1bfeaa9a92637bc52a1669feab9784fa7e01df` (el llamado "s275-r2").
- dtbo actual (se queda): `s286` `33d153f2…` (arriba).

## Gates del flash

Batería ≥3700 mV (medida en fastboot), `slot-retry-count` leído antes/después, lector ACM único
armado antes del reboot, `fastboot set_active a` SIEMPRE, sha pre-registrado en el ledger antes de
escribir, y `fastboot reboot` (sin `-f`).

## Nota de alcance (honesta)

Este ciclo **no** enciende el panel: desbloquea **ver el KTZ/TDDI desde el otro lado** (I2C), que es
prerrequisito del backlight externo (el driver o82 lo exige) y el discriminador "panel sordo vs
panel no alimentado". El siguiente candidato tras este: restaurar `vci` (driver+DT) y G8.
