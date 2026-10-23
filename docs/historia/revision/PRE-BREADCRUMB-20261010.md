# PRE-BREADCRUMB (10-oct-2026, SOLO-PC, sin builds): leer el breadcrumb del CM3 post-release sobre base L11

Solo diseño. Tablet no tocada, sin builds, sin repack, sin ledger, sin copiar árboles.
Un solo fichero creado (este).

Estado: **#575 = L11 NO-HFI** (poll vendor sin `L11-pollok`, CM3 suelto, muerte en
`HFI queues -110`, máquina viva) + **#576 = L12 TÓXICO** (hunk fw-map cuelga tras
`recfg-ok`) + **#577 = L13s MATA EN EL WRITE** (`recfg2-ok` sale y luego muere en
pre-rst/write: el restore RS es tóxico; GENERAL_10/8 ni inocentes ni culpables aún).
Si la vía RS queda refutada, el mudo es **fetch del body (SMMU SID5 @0x4000)** o
**stub desviado (NMI)**. Este diseño es el camino k61-breadcrumb citado en RE-STUB §2:
**leer el breadcrumb post-release separa stub-en-WFI de body-muerto en UN flash**,
con UN solo `readl`, sobre **base L11 pura (NO L12, NO L13s)**.

## 1. Fundamento (INV-GMU-BIN §2, verificado contra el binario real)

- El ITCM (476 B) es un boot stub, no el fw. Reset `@0x104` → lee DTCM CM3
  `0x10007fdc`, acumula stages con `(viejo<<8)+stage`, re-fija MSP/VTOR, ejecuta
  caches + 2 polls (`0x1f40a` POLL-1, `0x1f409` POLL-2), scatter-loader desde el body
  y `bl 0x4008` (primer fetch fuera del ITCM, INV-GMU-BIN §4).
- NMI `@0x144` escribe stage **3**, HardFault `@0x158` escribe stage **4**; ambos caen a
  `0x140: wfi / b 0x140` (lazo sin tráfico AHB: **vivo, sin INIT_RESULT, sin HFI,
  sin cuelgue** = arquetipo del mudo #575). FENCE/HFI/GENERAL no los toca el stub.
- Dirección host del breadcrumb: `REG_A6XX_GMU_CM3_DTCM_START + 0xff7`
  (`0x1c400+0xff7`, DTCM CM3 `0x10007fdc`; el `+0xff8` de K58/S0 es el vecino
  pre-cargado `0x40050001`, NO evidencia de ejecución). Baseline = `0xffffffff`
  (bloque 14 del binario, verificado en PC).
- Aritmética del shift-register (32 bits, verificada a mano contra INV-GMU-BIN §6):
  reset `(0xffffffff<<8)+1 = 0xffffff01`; stage `0x14`: `0x14+(x<<8)` →
  `0xffff0114`; `0x15` → `0xff011415`; `0x16` → `0x01141516`.
- El **body** también escribe `0x10007fdc** (stages 5, 6, 7, 8, 0xe, 9, 0xa, 0xb, 0xc,
  0x10, tail 0x11; BARRIDO-W2-RE-VOTOGX §3a). Patrón exacto de escritura del body no
  REado a nivel instrucción: cualquier avance más allá del patrón stub = body vivo.
- Trampa conocida: la tabla de vectores en ITCM `0x1000` la deja el scatter a **cero**
  y solo el body la rellena (INV-GMU-BIN §4): excepción temprana antes de `bl 0x4008`
  cae en vectores nulos → HardFault (stage 4) sin que el body haya corrido.

## 2. Ventana segura: por qué este readl no cuelga (precedente K44 + L11)

1. **Misma esclava, misma primitiva.** El read es `gmu_read()` = `readl()` sobre el
   recurso GMU del DT, igual que las 12 lecturas K44 A–E que sobreviven en TODOS los
   boots (#570–#577, valores esperados `rst=1 bootcfg=2 cfg=0x4052 initres=0`,
   `itcm0=10007f80/itcm1=00000105`, fence `0/80c808a0`). Cero SMMU, cero ioremap,
   cero walks (REGLAS.md r3 + LECCIONES r33; #449 colgó con ioremap+readl del SMMU).
2. **Precedente post-release más fuerte que K44: el propio poll L11.** Tras
   `SYSRESET=0`, L11 ya hace ~1000 `readl` de `FW_INIT_RESULT` sobre la misma esclava
   **con el CM3 suelto y la máquina viva** (#575: `S4-pollFAIL` + `nopoll-ok` +
   `HFI -110` salen). Un `readl` más de la misma esclava, en el mismo estado, es la
   misma clase de acceso ya probada viva.
3. **El fabric está vivo en el punto de lectura en ambas ramas.** Rama FAIL (#575
   medida): todo el epílogo drena. Rama OK: K44' (diseñado en L11 `:836-856`, aún
   nunca ejecutado porque el poll nunca dio OK) presupone máquina viva; el BC va en
   el mismo punto.
4. **El CM3 no puede pelear este acceso.** En WFI (stages 3/4) no trafica el AHB
   (`wfi/b .`); si el body corre, es UN `readl` alineado de 32 bits (atómico, sin
   tearing observable que cambie el veredicto: §3 usa byte bajo + patrón).
5. **Disciplina de drenaje.** `poke + pr_err + pr_flush` inmediatos (patrón L10/L11):
   el valor queda en ACM/pstore antes del camino HFI, que en el peor caso da -110
   con máquina viva.
6. **NO se relee el baseline pre-release.** La ventana pre-release `+0xff7` quedó
   taint por el hunk L12 (RE-L12 la rankea sospechosa nº3, aunque RAM/mmu son más
   probables). El baseline ya está verificado en PC contra el binario
   (`0xffffffff`, PRE-L12-FW §3 + RE-FWLOAD §2): no hace falta re-pisarla.

Riesgo **BAJO** (misma clase que el poll que ya sobrevive). Residuo honesto: es la
primera lectura DTCM post-release (K44' nunca corrió); si ESTE readl colgara, el dato
también informa (path DTCM-host wedged post-release → revertir, cae a L13-hunk-mitad).

## 3. Valores: qué separa cada rama

Regla primaria = **byte bajo** (último stage escrito);upper bytes = progreso al
interrumpir (p. ej. NMI tras el reset ≈ `0xffff0103`, HardFault en polls ≈ `0x01141504`).

| `bc` post-release | Veredicto |
|---|---|
| `0xffffffff` | CM3 **no ejecutó ni una instrucción**: reloj/dominio del CM3, vector de reset o release sin efecto. NO es fetch (el stub ni arrancó). Palanca: GDSC/clk del dominio, BOOT_CONFIG/CFG efectivos |
| `…01` (p. ej. `0xffffff01`) | Reset handler corrió, muerte antes del primer MMIO. Improbable (los polls leen bien desde el host); si sale, bloque cache-ops sin reloj visto desde el AHB del CM3 |
| `…0114` (p. ej. `0xffff0114`) | **Colgado en POLL-1** (`0x1f40a` bit0): bloque cache-ops sin reloj/energía. Palanca: GDSC/clk de ese dominio (INV-GMU-BIN §6: leer `0x1f40a` + GDSC desde el host en el mismo boot, ya cubierto por K44'/ENV) |
| `…011415` (p. ej. `0xff011415`) | **Colgado en POLL-2** (`0x1f409` bit0), misma palanca |
| `0x01141516` | Stub completo (polls OK, scatter OK): murió en el **fetch SMMU SID5→CB1 de `@0x4000`** (hipótesis C6-fetch) o en `bl 0x4008`. Palanca: capa CB/mapeo (RE-FWLOAD §4: K39/K20/shared sin flash), GBIF, NO el DTCM |
| byte bajo `0x03` | **Stub en WFI por NMI** (stage 3, handler `@0x144`): stub desviado, máquina viva y muda. Palanca: bit NMI de CM3_CFG / secuencia snapshot (L10 ya limpia `0x4052` tras S1: si sale `…03`, el toggle ocurre DESPUÉS o por otra vía) |
| byte bajo `0x04` | **Stub en WFI por HardFault** (stage 4, handler `@0x158`): fetch/excepción temprana (vectores ITCM `0x1000` aún a cero, scatter contra SMMU). Palanca: CFSR/fault del CM3, fuentes del scatter |
| más allá del patrón stub (stages body 5–11, low byte fuera de `{01,14,15,16,03,04,FF}` o palabra que avanza sobre `0x01141516`) | **Body corriendo**: el mudo NO es stub ni fetch. Cruzar con `INIT_RESULT` (bit 8) y HFI: `pollOK + HFI -110` = fw vivo pero HFI mudo (capa HFI_QTBL/BO); `pollFAIL` + body-stages = el fw corre sin señalar (chipid/log: reabre la vía RS por otra puerta) |

Cruces obligatorios en la misma línea (§4 los imprime juntos): último `val` de
`INIT_RESULT` + `ret` del poll + `bc`. `bit8=1` con body-stages = fw señaló;
`bit8=0` con `0x01141516` = stub OK pero `__main` no señala.

## 4. Hunk mínimo sobre base L11 (diseño; NO aplicar hasta activar)

Base: `k52-L11-tree` (hunks L12 y L13s **excluidos**). Un solo bloque en
`a6xx_gmu_start()`, **después del bloque `if (!ret) { K44'… }` y antes del
`if (ret) DRM_DEV_ERROR`** (`:832-858` L11): corre en AMBAS ramas (OK y FAIL),
con `val` (último INIT_RESULT) y `ret` ya en la mano, máquina viva en ambas.
Cero cambios de lógica, cero structs perseguidos, cero RAM, cero SMMU:

```c
	/* UKE-BC (diseño PRE-BREADCRUMB-20261010): breadcrumb post-release.
	 * Base L11 (SIN L12/SIN RS). El CM3 ya está suelto y el poll decidió
	 * (ret/val en la mano); la máquina está viva en ambas ramas (#575).
	 * UN solo readl a la misma esclava GMU del poll/K44 (regla 3 intacta).
	 * Baseline pre-release NO releído (taint L12; verificado en PC =
	 * 0xffffffff). Byte bajo = último stage (§3): 03=NMI-WFI, 04=HardFault-WFI,
	 * 01141516=stub-OK/fetch-muerto, ffffffff=CM3-no-ejecutó. */
	{
		u32 bc = gmu_read(gmu, REG_A6XX_GMU_CM3_DTCM_START + 0xff7);
		uke_poke("BC-bc");
		pr_err("UKE-BC: bc=%#x (esp patron §3) initres-last=%#x ret=%d\n",
		       bc, val, ret);
		pr_flush(120, false);
	}
```

Intactos: S0/S1/S2, K44 A–E, K25, L10-gbif/recfg, `L7-pre-rst`, write + `wmb()`,
`write-done`/`post-rst`/S3, poll vendor `(0x1ff)==0x100`, K44', epílogo, HFI.
Gates predichos para el clon de `build-k52L11.sh`: fuente `BC-bc`/`UKE-BC:` x1;
binario `BC-bc` + `UKE-BC:` x1, `UKE-POKE` = **113** (el poke nuevo no duplica el
literal: fusión TU como L11-pollok/L12-fwmap/RS-recfg2); **gate L11-WRITE intacto**
(el hunk escribe FUERA de la ventana pre-rst~write-done: 10 insns, 1 `str`); poll
vendor `and #0x1ff/cmp #0x100` intacto; negativos (`UKE-L1:`, `GENERAL_10/8`,
`L12-fwmap`, `RS-recfg2`) x0.

## 5. Criterios de lectura (flash futuro, con doble captura ACM + `dmesg -w`)

| Último testigo en ACM | Veredicto |
|---|---|
| sin `BC-bc` (muerte en `S4-pollFAIL/OK` o antes) | El readl post-release mata (inesperado: misma clase que el poll) → revertir; DTCM-host wedged post-release es dato nuevo, cae a L13-hunk-mitad |
| `UKE-BC: bc=0xffffffff` | CM3 no ejecutó (reloj/dominio/vector). Vía fetch/C6 MUERTA como explicación; a por GDSC/clk/BOOT_CONFIG efectivos |
| `bc=…03` | Stub-en-WFI-NMI (stage 3). Vía stub-config CONFIRMADA como mecanismo; GENERAL_10/8 inocentes del mudo; a por NMI/CFG post-S1 |
| `bc=…04` | Stub-en-WFI-HardFault (stage 4). Scatter/fetch temprano; a por fuentes del scatter y CFSR |
| `bc=0x01141516` | Stub OK, body no llega: **fetch SMMU SID5 `@0x4000`**. Vía RS inocente; a por capa CB (RE-FWLOAD §4 sin flash primero) o L13-hunk-mitad |
| `bc` con stages del body | Body vivo: a por HFI_QTBL/mapeo si `pollOK+HFI-110`, o reabrir RS por otra puerta si `pollFAIL` |
| `bc=…0114` / `…011415` | Polls del stub colgados: dominio cache-ops sin reloj (palanca GDSC/clk, no SMMU ni config) |

## 6. Activación (coordinador, NO ahora)

`cp -a k52-L11-tree k52-BC-tree` + §4 + `diff -U4` → patch (round-trip
`patch -p1 --dry-run` + `cmp`) + `build-k52BC.sh` clon de L11 (+gates §4,
POKE=113) + repack clon (G3 con `BC-bc`/`UKE-BC:` x1, `UKE-L1:` anclado) + fila de
ledger ANTES de flashear. Presupuesto y gates (batería/slots/lector) los fija el flash.
Nomenclatura `BC` (no `L14`): evita colisionar con el L14 que el coordinador asigne a
RS-bisect o L13-hunk-mitad.

## 7. Notas honestas

- El patrón exacto de escritura del body en `0x10007fdc` no está REado a instrucción;
  la fila "body corriendo" concluye por exclusión del patrón stub + stages listados en
  W2-RE §3a, no por codificación verificada.
- Si L10 ya limpia el bit NMI (`0x4052&0x200=0` tras S1), un `…03` implicaría toggle
  posterior (snapshot path) o vector NMI por otra causa: el flash lo separa del fetch
  pero no nombra el toggler.
- Que S1 conserve o borre el breadcrumb pre-cargado es irrelevante aquí: el reset
  handler lo reescribe con `01` en su primera instrucción; `0xffffffff` post-release
  solo puede significar no-ejecución.
- Semántica exacta de los bits de BOOT_CONFIG/FENCE no documentada (como en RE-STUB
  §7): este diseño no depende de ella.

## Fuentes

- Traza: ledger #574 (L10 LLAVE), #575 (L11 NO-HFI), #576 (L12 TÓXICO), #577 (L13s
  mata en el write) en `~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md`.
- Nuestro path: `build/kernel-pokes/k52-L11-tree/.../adreno/a6xx_gmu.c`
  (`a6xx_gmu_start` `:632-875`: S0 `:640`, S1 `:683`, K44 `:701-740`, L10-recfg
  `:760-792`, release `:804`, poll `:832-833`, K44' `:836-856`, epílogo `:858-875`;
  `fw_start` GENERAL_10/8 `:1590-1599` solo pre-S1), `a6xx_gmu.h:140-180`
  (`gmu_read`/`gmu_poll_timeout`), `generated/a6xx_gmu.xml.h` (DTCM `0x1c400`,
  SYSRESET `0x1f800`, BOOT_CONFIG `0x1f801`, CFG `0x1f82d`, INIT_RESULT `0x1f81c`,
  GENERAL_8/9/10 `0x1f9cd/ce/cf` a7xx).
- Binario: INV-GMU-BIN §§1c/1d/2/4/6 (stub/NMI/WFI/breadcrumb, `bl 0x4008`,
  tabla `ffffffff/ffffff01/ffff0114/ff011415/01141516/…04`).
- Vías hermanas: RE-STUB §§2/4/5 (única divergencia GENERAL_10/8, hunk RS, camino k61),
  RE-L12 (ranking tóxico: RAM > mmu > DTCM), RE-FWLOAD §§2–4 (carga-mapeo vendor-equivalente,
  discriminadores K39/K20/shared sin flash), PRE-L12-FW (ventana K44-probada, regla 3),
  CRITICA-HW §§C6/C7/§2 (fetch co-causa, `wmb()`), DISENO-K61 §§3.2–3.4 (stages,
  bracketed reads, whitelist MMIO), BARRIDO-SSH-ÍNDICE §4 (tabla discriminadora),
  VIAS-GPU P1/P2 (fronteras release/polls/scatter/body), W2-RE-VOTOGX §3a (stages del body).
