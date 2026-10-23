# CRÍTICA-HW: write SYSRESET=0 cuelga el bus AXI en duro (10-oct-2026, SOLO-PC)

Veredicto de partida: **L8 (ledger #572,ot escritura nº20)**. Traza ACM:
`…k44e-ok → K19-dumpOK → k25-ok → L7-pre-rst` y MUERTE — ni `L8-write-done`
ni `L7-post-rst` ni `S3` salen. El `gmu_write(REG_A6XX_GMU_CM3_SYSRESET, 0)`
de `a6xx_gmu_start()` (`build/kernel-pokes/k52-L8-tree/.../adreno/a6xx_gmu.c:760`)
cuelga el bus en duro: silencio total, sin panic, sin watchdog visible.
Contexto previo verificado en vivo (#570/#571): D1/D2/D3 rc=0, H1/H2/H3/H4/H5/H6,
F1/F2/F3/F4, H7, P1/P2/P3/P3-pwrOK, S0, S1-rst1, S2-gen9, K44 A–E con valores
esperados (`rst=1 bootcfg=2 cfg=0x4052 initres=0`, fence `0/80c808a0`, itcm/icache OK).
Chip tratado como **a7xx** (Adreno 732, `qcom,adreno-gmu-732.0`, fence `0x32/0x8a0`).
Tablet viva en L8, **no flashear sin autorización del dueño**.

## 0. Caveat honesto: L8 acota a la VENTANA del release, no a la instrucción

`gmu_write` es `writel()` sin `wmb()` posterior (`a6xx_gmu.h:146`). Tras el writel,
L8 hace `uke_poke` (write al **framebuffer por el mismo fabric**) + `pr_err` +
`pr_flush` (UART). Si el writel completa pero el CM3 liberado wed-gea el fabric
en nanosegundos con su primer fetch, el poke/flush posterior es lo que cuelga y
la traza es **idéntica** (pre-rst último testigo en ambos casos). Conclusión:
el asesino es "soltar el CM3", en una de estas dos formas inseparables por ACM:
**(w) el writel no completa** (slave sin respuesta) o **(f) el primer fetch del
CM3 wed-gea el fabric antes del siguiente acceso de CPU**. Cada causa abajo dice
a cuál de las dos formas corresponde y cómo un flash la separa.

## 1. Ranking de causas

### C1 — Primer fetch del CM3 contra GBIF halted / bus CX no saneado → wedge del fabric (forma f). RANK 1
- Mecanismo: el CM3 sale del reset y su primer acceso (fetch icache vía su bus
  propio) encuentra el GBIF en halt de una secuencia de reset anterior cuyo GDSC
  no colapsó. El halt wed-gea el fabric compartido; la CPU cuelga en su siguiente
  transacción (poke/flush L8), indistinguible de (w).
- Firma en traza: EXACTA a la observada — todo MMIO del slave GMU (siempre-on)
  funciona pre-release (K44 A–E), muerte justo al soltar. Ningún error previo
  porque el halt solo muerde cuando el CM3 intenta traficar.
- Apoyo vendor: `gen7_gmu_register_config()` hace `kgsl_regwrite(GEN7_GBIF_HALT, 0)`
  **inmediatamente antes** del boot con este comentario: *"We may have asserted
  gbif halt as part of reset sequence which may not get cleared if the gdsc was
  not reset. So clear it before attempting GMU boot."* (`adreno_gen7_gmu.c:969-974`).
  Nuestro path GMU **no** lo hace: el único clear GBIF vive en `hw_init()`
  (`a6xx_gpu.c:1191-1203`, `GBIF_HALT` + `RBBM_GBIF_HALT`), fase anterior, vía
  `gpu_write` (dominio GX, quizá colapsado entonces) y lejos del release.
- Mata/confirma en UN flash (L9a): `gpu_write(REG_A6XX_GBIF_HALT, 0)` +
  `gpu_write(REG_A6XX_RBBM_GBIF_HALT, 0)` + readbacks + poke, **entre S1 y el
  release**. Sobrevive a write-done → CONFIRMADA. Mismo punto de muerte → MUERTA.

### C2 — Secuencia reset invertida: SYSRESET=1 se afirma DESPUÉS de programar CM3_CFG (forma f). RANK 2
- Mecanismo: nuestro orden es `fw_start` (programa `CM3_CFG=0x4052`, `BOOT_CONFIG=2`,
  fence, HFI) → `a6xx_gmu_start` (**afirma `SYSRESET=1`, S1**) → programa nada →
  libera (`SYSRESET=0`). El vendor afirma el reset en el suspend (`sleep_sequence`:
  `SYSRESET=1 + wmb`) y programa `CM3_CFG/BOOT_CONFIG` **después**, justo antes de
  liberar. Si afirmar el reset revierte `CM3_CFG` a su valor HW (el comentario
  snapshot avisa que el bit NMI desvía a `__main`: *"Snapshots toggle the NMI bit
  which will result in a jump to the NMI handler instead of __main"*), el CM3
  liberado arranca en el handler NMI, fetchea basura y wed-gea el bus.
- Firma en traza: idéntica a C1 (muerte en la ventana). No deja huella previa
  porque los reads K44 pre-release leen el valor programado, no el post-reset.
- Mata/confirma en UN flash (L9b): tras S1, **re-escribir** `CM3_FW_INIT_RESULT=0`,
  `CM3_BOOT_CONFIG=2`, `CM3_CFG=0x4052`, fence, `HFI_QTBL_ADDR/INFO` + poke, y
  liberar. Sobrevive → CONFIRMADA (o co-causa con C1). Mismo punto → MUERTA.
- Nota: C1 y C2 comparten flash si L9 = C1+C2 en un solo hunk (un flash, dos
  pasos previos; si sobrevive, L10 los separa; si muere, ambas caen de golpe).
  Recomendado: **L9 = C1+C2 combinados** (ver §3).

### C3 — Reloj del bloque apagado al soltar el CM3 (forma w). RANK 3
- Mecanismo: el release arranca el dominio relojero del CM3/TCM cuyo padre está
  gated; el slave no responde al writel → la CPU cuelga en (w).
- En contra (fuerte): el MISMO slave responde a todas las lecturas K44/DTCM/ITCM
  pre-release; `clk_bulk_prepare_enable` rc=0 (H3 en vivo); D1/D2/D3 rc=0.
  A favor residual: `rc=0 ≠ reloj corriendo` (rate seteado, padre sin rate deja
  el GMU en reloj fantasma — el propio comentario `UKE-CM3DBG` en `:1876` lo dice).
- Firma esperada que NO tenemos: la línea `UKE-CM3DBG: clks core=%lu hub=%lu`
  (`:1880`, justo tras H3) debería estar en la ACM; el resumen #570 no la cita —
  **pedir al hermano `grep CM3DBG clks` en el log ACM completo**: si falta o da 0,
  C3 sube a RANK 1; si da 220M/200M, C3 casi muerta sin flashear.
- Mata/confirma en UN flash: pre-release, imprimir `clk_get_rate(core/hub)` +
  leer estado de reloj vía registro (no `clk_is_enabled`, no exportado) +
  re-votar `clk_set_rate` explícito. Cuelga igual con rates sanos impresos → MUERTA.

### C4 — Power-domain / colapso CX-GDSC / voto RPMh insuficiente (forma w/f). RANK 4
- Mecanismo: el CM3 al salir del reset dispara su voto RPMh (secuencia RSC/PDC);
  si el voto cae en regulador apagado o la GDSC CX está colapsada, la transacción
  se queda sin respuesta.
- En contra: H1 (`pm_runtime_get`), H2 (`gxpd_get`), H6 (`a6xx_rpmh_start`) y
  `set_initial_bw` pasaron en vivo; el slave GMU responde. El vendor vota BW DDR
  mínima **solo en first-boot**, no en re-boot — nuestro `set_initial_bw` es
  análogo suficiente.
- Mata/confirma en UN flash: pre-release, leer `RSCC_TCS*_DRV0_STATUS` + votar
  CX explícito + poke; mismo punto de muerte → MUERTA.

### C5 — Firewall/VMID/XPU: fetch del CM3 denegado a DDR (forma f). RANK 5
- Mecanismo: la CPU lee el GMU porque su VMID tiene permiso XPU sobre el slave;
  el CM3 es OTRO master (otro SID): su fetch del BO icache en DDR puede estar
  denegado por firewall → fault síncrono del CM3 → wedge del fabric. Explica por
  qué el MMIO de CPU funciona y el release mata.
- En contra: nada observable; a favor: nada observable. Es la causa "invisible
  por construcción" — la XPU no deja huella en ACM.
- Mata/confirma en UN flash (proxy): L9c = **NO liberar** (saltar también el write,
  `ret=0, FW_START`, seguir a HFI). Sobrevive → el release/fetch es el gatillo
  (confirma la familia C1/C2/C5/C6, mata fallo-del-write-puro). La XPU en sí solo
  se confirma desde TZ/hyp, fuera del presupuesto de un flash — decirlo así.

### C6 — SMMU SID5 sin mapping @0x4000: el fw-cuerpo nunca llegó a RAM del CM3 (forma f). RANK 6 (co-causa, no causa del hang)
- Mecanismo: el BO icache (iova `0x4000`, `SZ_16M-16K`, `a6xx_gmu.c:2947`) recibe
  el cuerpo del fw por `memcpy` (`fw_block_mem`, `:1339`), pero el CM3 lo consume
  por IOVA en **su dominio IOMMU propio**; si el attach/mapping falló, el primer
  fetch aborta → fault → wedge.
- Apoyos: `dtcm-magic` STALE (`0x40050001 & 0x1ff = 0x1 ≠ 0x100`, nota K23b en
  `:650-671`: el fw NO dejó el magic ⇒ la imagen no llegó a la RAM del CM3);
  precedente #449 (K19: `ioremap`+readl del SMMU → machine-check, docs/historia/AGENTS.md r3).
- Por qué rank 6 y no más: C6 explica qué fetch falla, pero necesita C1/C5 para
  convertir "fetch fallido" en "bus colgado en duro" (un abort limpio daría fault,
  no silencio). Es co-causa, no causa raíz del wedge.
- Mata/confirma en UN flash SIN colgar: pre-release, imprimir `icache.iova/size`,
  estado del dominio/attach (**solo estado, NINGÚN walk de tablas**: el walk colgó
  en #449). Dominio ausente → CONFIRMADA como co-causa; todo impreso OK + muerte
  en el mismo punto → MUERTA como explicación.

### C7 — Reset mal secuenciado en sentido estricto / falta `wmb()` tras el release (forma w). RANK 7 (última)
- El vendor hace `SYSRESET=0` + `wmb()` (`adreno_gen7_gmu.c:357-360`); nosotros
  `writel` pelado (`a6xx_gmu.h:146`, solo `gmu_write_bulk` lleva `wmb`).
  En ARM64 `writel()` ya ordena (`__iowmb`), y un defecto de orden daría
  comportamiento errático, NO un hang duro del bus 100% reproducible en 3
  bisectos (L6/L7/L8 mueren en el mismo punto). No hay medida de un flash que la
  discrimine (un readback colgaría igual con el bus muerto). Se fija el `wmb()`
  de gratis dentro de L9 sin reclamarle poder discriminante.

## 2. Qué hace el vendor ANTES de SYSRESET=0 que nuestro a6xx_gmu.c NO hace

Referencia: `adreno_gen7_gmu.c` (OnePlus SM7675, `cache/scratch/vendor/op-sm7675`).
Path de re-boot: `gen7_gmu_boot()` (`:1997`) → `gen7_gmu_device_start()` (`:347`).

| # | Vendor hace (pre-release) | Nuestro `a6xx_gmu.c` hace | Falta en nuestro path |
|---|---|---|---|
| 1 | `GEN7_GBIF_HALT = 0` + comentario gdsc-no-reseteada (`:974`) | Clear solo en `hw_init()` (`a6xx_gpu.c:1191`), fase anterior, vía GX | **SÍ → C1, va a L9** |
| 2 | Orden: reset afirmado en suspend → programa `CM3_CFG/BOOT_CONFIG/FENCE/HFI` → libera | Orden: programa todo en `fw_start` → afirma reset (S1) → libera sin reprogramar | **SÍ → C2, va a L9** |
| 3 | `SYSRESET=0` + `wmb()` (`:359-360`) | `writel` sin `wmb` | Sí (cosmético, gratis en L9) |
| 4 | Poll post-release = bit 8 de `FW_INIT_RESULT` (fw-vivo) | Poll = condición DTCM-magic `(val&mask)==reset_val`, que con el valor stale **nunca** cuadra (nota K23b) | Sí, pero POST-release: irrelevante para el hang; anotado para L10+ |
| 5 | `GENERAL_9 = log_wptr_retention` (restaura) | `GENERAL_9 = 0` (`:680-684`) | Sí, menor; preservar en L9 (1 línea) |
| 6 | `GENERAL_11 = vrb->gmuaddr` si existe | Nada | Menor; solo si `gmu->vrb` existe en este árbol |
| 7 | `gen7_cx_timer_init` | Nada análogo | NO requerido: solo en first-boot vendor, no en re-boot |
| 8 | Voto BW DDR mínimo | `a6xx_gmu_set_initial_bw` (OK en vivo) | Cubierto |
| 9 | `gen7_rscc_wakeup_sequence` (REQ BIT1 + polls) | `a6xx_rpmh_start` (H6 OK en vivo) | Cubierto |
| 10 | `gen7_gmu_load_fw` + `wmb()` tras escribir el fw | `a6xx_gmu_fw_load` cada cold-boot (F1–F4 OK en vivo) | Cubierto (con co-causa C6 pendiente) |
| 11 | Mensaje ACD al AOP vía mailbox (first-boot) | Nada (upstream msm no modela ACD) | Divergencia conocida, sin evidencia en traza; NO va a L9 |

## 3. Diseño del L9 (UN flash, un paso previo vendor)

**L9 = alineación vendor del pre-release (C1+C2+C7(+5)) en `a6xx_gmu_start()`,
entre S1 y el write, SIN tocar el resto.** Hunk único tras `S1-rst1`:

1. `gpu_write(REG_A6XX_GBIF_HALT, 0)` + `gpu_write(REG_A6XX_RBBM_GBIF_HALT, 0)` +
   readbacks + poke `L9-gbif` + flush (C1).
2. Re-escribir `CM3_FW_INIT_RESULT=0`, `CM3_BOOT_CONFIG=2`, `CM3_CFG=0x4052`,
   fence `BIT31|0x32<<18|0x8a0`, `HFI_QTBL_ADDR/INFO` + poke `L9-recfg` + flush (C2).
3. `GENERAL_9` = preservar (leer-antes-de-S1, escribir-tras-S1) en vez de 0 (5).
4. `wmb()` tras `SYSRESET=0` (C7, gratis).
5. Mantener L8: poke `write-done` inmediato + `goto nopoll-ok` (cero lecturas
   post-release; si L9 sobrevive, L10 reintroduce el poll VENDOR (bit 8), no el
   DTCM-magic que nunca cuadra).

Lectura (criterios inalterados +1): `L9-gbif/L9-recfg` sin `write-done` ⇒ C1/C2
inocentes, cae a C3/C5 (siguiente: L9c no-release + `grep CM3DBG clks` en la ACM);
`write-done`/`nopoll-ok` ⇒ **vendor tenía razón**, el release era secuenciación,
a por HFI/L10. Presupuesto: escritura nº21 en boot_a (17º override), dtbo s250,
gates batería/slots/lector como #572. Riesgo: BAJO (solo writes a registros ya
tocados en este path + GBIF, todos con readback; ningún walk SMMU, regla 3).

Pre-flash sin coste (pide al hermano, 0 escrituras): `grep "CM3DBG: clks" |
"CM3DBG: fw-map" | "K44"` en los logs ACM de #570–572 — decide C3/C6 antes de L9.

## Fuentes
- Traza: ledger del hermano `~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md`
  #570/#571/#572; pre-registro L8: `omarchy-uke/revision/BISECT-L8-BUILD-20261010.md`.
- Nuestro path: `build/kernel-pokes/k52-L8-tree/drivers/gpu/drm/msm/adreno/a6xx_gmu.c`
  (`a6xx_gmu_start` :632, `fw_start` :1434, `resume` :1826), `a6xx_gmu.h:140-155`,
  `a6xx_gpu.c:1191-1203` (GBIF clear en hw_init).
- Vendor: `~/.hermes/profiles/coder/cache/scratch/vendor/op-sm7675/vendor/qcom/
  opensource/graphics-kernel/adreno_gen7_gmu.c` (`device_start` :347,
  `power_config` :315, `register_config` :937, `boot` :1997, `first_boot` :1896).
- Reglas: SOLO PC este turno (árbol L8 no modificado, informe solo); tablet en L8.
