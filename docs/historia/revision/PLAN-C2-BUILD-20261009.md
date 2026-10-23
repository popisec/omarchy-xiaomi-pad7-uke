# PLAN-C2 — BUILD k70 (C1 + D1, réplica del orden vendor) — 2026-10-09, solo PC, sin flashear

> PROHIBIDO flashear/tocar la tablet (colgada en k69; 7 escrituras hoy, presupuesto agotado).
> Solo PC: parche + build + gates ejecutados DE VERDAD sobre el binario. Nada de self-report sin re-ejecución.

## 1. Linaje del árbol (verificado, no supuesto)

- Estado encontrado: `build/kernel-pokes/k52-tree/.../a6xx_gmu.c` = **base + K64 + C1**, limpio:
  - `grep UKE-K65/K66/K67/K68` = 0; `mask = 0xffffffff` + `reset_val = 0xbabeface` (mainline, poll vendor revertido);
  - rates mainline (`core 200M`, hub condicional 200M/150M, sin `ret =`); C1 presente (`#include <linux/io.h>`, bloque voto + `H2-cxvoto`).
  - `git status --short` (repo): solo `M docs/historia/ESTADO-VIVO.md` + `??` restos de k69 (el tree fuente no tiene diffs pendientes: C1 ya está aplicado en disco).
- Conclusión: el árbol SÍ está en el estado supuesto → NO hizo falta reconstrucción. C2 = C1 (ya aplicado) + diff incremental D1.
- Lección K43 re-verificada DE VERDAD: el Image k69 (build 14:12, gateado con el script viejo roto) SÍ contiene `01 33 UKE-POKE` x1 y cero `01 34` (comprobado con `python3` sobre el binario en este turno). El binario estaba bien; el que mentía era el gate de doble-backslash. El 28/28 del k68 sigue siendo ficción.

## 2. Parche k70 (SOLO hunk D1 del k67-d1solo.diff)

- Origen: `build/gates/patches/k67-d1solo.diff`, hunk `@@ -2306,21 +2346,17 @@` (el único que toca `a6xx_gmu_resume`).
- DESCARTADO del k67: hunk G10/G8 (chipid+log, `0x1f9cf/0x1f9cd`) y hunk poll-vendor (`mask 0x1ff/reset 0x100`).
- Adaptación: testigos `UKE-K67:` → `UKE-K70:`; contexto rebasado sobre el árbol C1 actual (tras `H2-cxvoto`, contra rates mainline 200M/150M, no contra el K65).
- Fichero: `build/gates/patches/k70-planC-C2.diff` (D1-only incremental; C1 y K64 intactos).
- Contenido (core 220M + SIN-D2 + SIN-D3, orden voto → set_rate → enable = réplica vendor):

```
tras uke_poke("H2-cxvoto"):
  RETIRADO: clk_set_rate(core, 200M) + clk_set_rate(hub, 200M/150M) [mainline, hub a XBL de facto]
  PUESTO:   ret = clk_set_rate(core, 220000000) + pr_err UKE-K70:D1 rc + SIN-D2 + SIN-D3 + pr_flush
  SIGUE:    ret = clk_bulk_prepare_enable(...) (enable-path intacto)
```

- Dry-run: `patch -p1 --dry-run < k70-planC-C2.diff` en k52-tree → rc=0 (ver §4).
- Aplicado sobre el árbol en este turno (ver §4).

## 3. Build k70 — RESULTADO: OK (14:32, incremental ~35 s)

- `cp -a k69-build k70-build` (3.2 G, COPY-OK) + `./docs/historia/gates-palawan/build-k70.sh`.
  OJO: `UKE_BUILD_DETACHED=1` venía heredado en el entorno → el build corrió
  **adosado** (foreground), no desprendido; el log `build-k70.log` no se generó
  por la rama detached — la salida completa está en la transcripción del turno.
- Compilación: solo `a6xx_gmu.o` + relink (`CC ... a6xx_gmu.o`, 1 warning
  preexistente `uke_k61_rescue_write` frame-larger-than, igual que k69).
- Gates del propio `build-k70.sh` sobre el Image: **todos OK + `DONE K70-BUILD-OK`**:
  28 must heredados + 3 nuevos `UKE-K70:` (D1, SIN-D2, SIN-D3, x1 cada uno) +
  K43 single-backslash (`\x013UKE-POKE` x1, `\x014` x0) + mustnt K65/K66/K67/K68 x0.
- Re-ejecución INDEPENDIENTE en este turno (python3 directo sobre el binario,
  no el report del script): **31 must OK + 7 mustnt OK**, `mtime Image > fuente`,
  shas coincidentes con los del build:
  - `Image` (41490944 B) `de94ea2b2d2d696a8406f45136277541c360c2d02a1b65e91d3152d04f8cef9e`
  - `Image.gz` `1cf0e9e70d3421a7c0da45a9beeb79edcbb373dec4462d78db88f360a4715d00`
  - cpio embebido = K22 `08780e35…` (verificado por el script).

## 4. Trazabilidad de comandos (dry-run antes de cada paso)

1. Linaje: greps en fuente (K65–K68 = 0, C1 presente, rates mainline) + `git status` (tree fuente gitignored; versionado vía diffs). Estado = el supuesto → sin reconstrucción.
2. `patch -p1 --dry-run < k70-planC-C2.diff` en k52-tree → `rc=0` (antes de tocar nada).
3. `patch -p1 < k70-planC-C2.diff` → `rc=0`, `grep UKE-K70` = 4 hits (comentario + 3 testigos), C1/K64 intactos.
4. `cp build-k69.sh build-k70.sh` + 4 ediciones (O/LOG, gates K70 x3, comentario mustnt, DONE) → `bash -n` OK + `diff` solo-deltas + K43 single-backslash intacto (línea 115).
5. `cp -a k69-build k70-build` (background, COPY-OK) → build adosado OK → gates del script + re-ejecución independiente (§3).
6. `cp repack-k69.py repack-k70.py` + 7 ediciones (cabecera, KERNEL, OUT/LOG, G3 K70 x8 testigos, `dec65→dec70`, fila k70, unpack-dir) → `ast.parse` OK + diff normalizado solo-deltas. **NO ejecutado** (sin Image.gz→img hasta pre-registro).
7. Tablet: ni un comando contra ella en todo el turno (cero `adb`/`fastboot`).

## 5. Fila ledger #560 REDACTADA (pendiente: repack NO ejecutado, sin sha de img)

> Para `~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md`. NO pegar hasta tener
> el `boot-uke-k70-plancC2.img` + su sha (repack-k70.py pendiente de ejecutar por
> el coordinador) y la tablet revivida a fastboot (dueño, sería escritura nº8).

```
### #560 — k70-PLAN-C-C2 PRE-REGISTRO (9-oct): voto C1 + D1 (réplica vendor).

**Artefacto.** `omarchy-uke/build/bootimg/boot-uke-k70-plancC2.img`
sha256 `___` (___ B; repack-k70.py G0–G8 verdes; cmdline 580 B = k64; cpio = k64).
**Variable vs k69:** D1 restaurado tras el voto (core 220M exacto; hub en XBL,
SIN-D2/SIN-D3); C1 + K64 intactos; familia K65–K68 ausente del binario.
Build: incremental de k69-build (~35 s), gates 28 must + 3 K70 + K43
single-backslash + mustnt, re-ejecutados de forma independiente sobre el Image
(31+7 verdes); `Image de94ea2b…` (41490944 B), `Image.gz 1cf0e9e7…`.
**Presupuesto: escritura nº8 (6º override, PENDIENTE: tablet colgada en k69,
falta revival a fastboot por botones — dueño).** Gates: batería por medir,
rollback k52b2 en disco, dueño presente.
**Comando.** `fastboot flash boot_a` + reboot; buscar `UKE-C1: voto CX pre-rate:`,
`H2-cxvoto`, `UKE-K70: D1 gmu clk_set 220M rc=`, desenlace.
**Criterios.** Habla ⇒ faltaba rate con voto previo (C1 calló sin D1); C2 vive
con `rdpm PRESENTE` ⇒ el voto era la llave y el rate el complemento. Calla
igual ⇒ el voto no llegó (rdpm ausente) o el asesino está en el enable-path
(puerta de C3: enables diferidos tras USB). Aviso W6 vigente: 6/6 mudos
apuntarían a muerte antes de nuestro código o gadget roto.
**Resultado #560.** ___.
```
