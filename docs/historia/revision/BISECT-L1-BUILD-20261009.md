# BISECT-L1-BUILD — L1 = L0 + K64-solo (2026-10-09)

> Solo PC. Tablet VIVA en L0 por SSH — PROHIBIDO flashear/tocarla.
> Este turno es solo build. Sin repack ejecutado, sin flash.
> Fichero NUEVO, escritura incremental. Base: §4 de `docs/historia/revision/BISECT-L0-20261009.md`.

## 1. K64-solo: código exacto y extracción

Origen: `build/kernel-pokes/k52-tree` (estado k70), función
`uke_k64_vendor_config` (`drivers/gpu/drm/msm/adreno/a6xx_gmu.c`, ~l.856–890)
+ llamada tras `P3-pwrOK` en `a6xx_gmu_fw_start` (~l.2015–2016).
Referencias: `docs/historia/revision/BARRIDO-FASE2-VENDOR-20261009.md` §0 (testigos en binario k64:
`register_config COMPLETADO`, `register_config vendor (0x1f8f0=1 0x1f8f1=1
0x1f984=1 base=0x3c45)`, `RSC wake rc=%d status=%#x`).

Contenido del hunk (lógica byte-idéntica al K64 original):
`0x1f8f0=1, 0x1f8f1=1, 0x1f984=1, base GMU+0=0x3c45, 0x1f9cd–d0=0xf`
+ wake RSC (`0x3b07=2`, poll `0x3b08&2`, luego 0) + unlock `0x3b11=0x80c808a0`.
Testigos renombrados a `UKE-L1/K64:` (×3) — el prefijo trae `K64` dentro
para el gate `K64×1` de la receta y `UKE-L1` para identidad propia.
Dependencias: `gmu_write`, `gmu_write_rscc` + `gmu_poll_timeout_rscc`
(`a6xx_gmu.h:189/194`, presentes en L0), `wmb`, `pr_flush` (ya usado en L0).
Cero referencias a infraestructura K61 (params, whitelist, rescue, env_probe):
**K64 es extraíble limpio** (veredicto §5).

Deliberadamente AUSENTE del hunk (verificado por grep en el diff: CLEAN):
D1/D2/D3 (rates 220M/200M, voto OPP), poll-vendor con máscara cambiada,
G10/G8 (chipid/log programados, K66), C1 (voto RDPM, k69). Sin alternativa:
no hizo falta L1-alternativo.

Parche versionado: `build/gates/patches/k52L1-k64solo.diff`
(2 hunks `a/drivers/...`, `-p1`; hunk1 con fuzz 1 verificado a mano:
el sitio resume idéntico al K64 original salvo nombre+prefijo — diff en §2).

## 2. Aplicación (copia de trabajo, L0 intacto)

- `cp -a k52-L0-tree k52-L1-tree` (1,8 GB; `k52-tree` sigue en k70,
  `k52-L0-tree` sin tocar — `grep UKE-L1` en L0 = 0).
- `patch -p1 --dry-run` OK → aplicado: hunk1 en 1376 (fuzz 1),
  hunk2 (llamada tras `P3-pwrOK`) en 1537. `grep UKE-L1` en L1 = 5
  (3 `pr_err` + comentario + llamada).
- Diff función L1 vs `uke_k64_vendor_config` del k52-tree: SOLO nombre de
  función + prefijo `UKE-K64:` → `UKE-L1/K64:` en los 3 testigos (4 líneas).
- Config: `build/kernel-config/k52L1-bateria.config` (= k52L0, cpio 6-oct).
- Script: `docs/historia/gates-palawan/build-k52L1.sh` (clon de build-k52L0.sh):
  perfil L0 (V1) + `UKE-L1/K64` ×3 (incluido `COMPLETADO` ×1 = K64×1)
  + negativos V2-L1 (familia K55–K63/K65–K68/K70/C1/C3, `uke_s3_stage`,
  `uke_rescue`, `D1 gmu`, `D2 hub`, `D3 cx`, `poll vendor`, `GENERAL_10/8`;
  `register_config` permitido). Bloque python verificado con `py_compile`.
- Incidencia menor: el editor duplicó un backslash en el gate `poke-warn`
  (l.170); restaurado a byte-idéntico con L0 (l.156) y `bash -n` OK.

## 3. Build L1 (desprendido, en marcha → resultado abajo)

Lanzado 22:20 (pid 38197), log `build/logs/build-k52L1.log`.
Gates de config en verde (QCOM, INITRAMFS_SOURCE→cpio K34-fw con fw dentro,
GZIP). `make Image.gz` en `k52L1-build` (~15 min, como L0 18:5x→19:01).

### 3.1 Verificación en binario (ejecutada DE VERDAD 22:49)

Build terminado 22:49:35 con `DONE L1-BUILD-OK` (30 `GATE OK`, 0 fallos en
`build/logs/build-k52L1.log`; config-gates + `Image mas nuevo que .config` OK).
Verificación independiente posterior sobre el `Image` crudo (41.490.944 B):
V1: perfil L0 intacto (`UKE-K19`×21, `UKE-K17: dtcmR`×1, `WALK`×8,
`MAPPING`×15, `UKE-POKE`×113; diff de familias `UKE-*` L1-vs-L0: solo
aparece `UKE-L1`, nada desaparece).
V2-L1: `UKE-L1`×3, `register_config`×2, `RSC wake`×1,
`UKE-L1/K64: register_config COMPLETADO`×1 (= K64×1 de la receta);
negativos 25/25 ausentes (K55–K63, `UKE-K64` original, K65–K68, K70, C1, C3,
`uke_s3_stage`, `uke_rescue`, `D1 gmu`, `D2 hub`, `D3 cx`, `poll vendor`,
`GENERAL_10/8`).
V3: tamaño idéntico a L0 y al kernel del k52b2 (41.490.944 B), banner
`7.2.0-rc2-palawan` idéntico; sha256 `c4b1961c…` (difiere de L0 `a07464c4…`
solo en el hunk).
L1 == L0 + K64-solo declarado en fuente Y en binario.

## 4. Repack + ledger (EJECUTADO por el coordinador 9-oct ~23:00)

- `docs/historia/gates-palawan/repack-k52L1.py`: clon de `repack-k52L0.py` con G3-L1
  (perfil k52b2 + `UKE-L1/K64` ×3; negativos L0 menos `register_config`;
  `KERNEL=k52L1-build`, `OUT=boot-uke-k52L1.img`). Creado, NO ejecutado.
- Ledger hermano `~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md`:
  fila `#562 — L1-BISECT PRE-REGISTRO + FLASH` con sha `6d980152…` (repack
  G0–G8 verdes ejecutados por el coordinador; perfil L0 + UKE-L1/K64 ×3
  re-verificado en binario). Flash pendiente de autorización (nº10).

## 5. Veredicto (cerrado 22:49)

K64 extraíble limpio: SÍ (hunk autocontenido, sin K61/D1/D2/D3/poll/G10/G8/C1).
L1 alternativo: NO necesario.
L1 == L0 + K64-solo verificado en binario (V1+V2-L1+V3).
Siguiente: repack (fila #562) + flash cuando el dueño autorice (escritura
nº10). Pregunta abierta: ¿K64-solo vive? (L2 = +D1-solo después).
