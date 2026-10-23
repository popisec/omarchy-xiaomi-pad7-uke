# C4 — Auditoría de la hipótesis "CM3 arranca con config de reset" (pre-S3)

Fecha: 2026-10-02. Árbol auditado: `build/kernel-pokes/k18-tree`
(`drivers/gpu/drm/msm/adreno/a6xx_gmu.c`), contrastado con
`~/gpu-work/palawan-linux/drivers/gpu/drm/msm/adreno/a6xx_gmu.c` y
`registers/adreno/a6xx_gmu.xml`. Sin flash, sin tocar la tablet.

## 1. Veredicto: la hipótesis es FALSA en su premisa

La hipótesis dice: *"No escribe ningún registro de configuración del CM3
(ni `CM3_CFG`, ni `BOOT_CONFIG`, ni escalador de direcciones)"* entre
`S2-gen9` y `S3-rst0`. Eso es cierto **solo si se mira `a6xx_gmu_start()`
aislada** (`a6xx_gmu.c:632`), que en efecto solo hace `SYSRESET=1` (:673),
los ceros de `GENERAL_9`/`PWR_COL_CP_RESP` (:680–:684) y `SYSRESET=0` (:709).

Pero `a6xx_gmu_start()` **no es toda la secuencia**: la llama
`a6xx_gmu_fw_start()` en `a6xx_gmu.c:1467`, y ANTES de esa llamada ya ha
escrito, en este orden:

- `a6xx_gmu.c:1390`: `CM3_FW_INIT_RESULT = 0` (limpia resultado previo).
- `a6xx_gmu.c:1391`: **`CM3_BOOT_CONFIG = 0x02`**.
- `a6xx_gmu.c:1395–1396`: `HFI_QTBL_ADDR/INFO` (iova de las colas HFI).
- `a6xx_gmu.c:1410–1413`: `AHB_FENCE_RANGE_0` (ventana del fence AHB).
- `a6xx_gmu.c:1419`: **`CM3_CFG = 0x4052`**, con el comentario mainline
 -original (`:1415–:1418`): *"Snapshots toggle the NMI bit which will result
  in a jump to the NMI handler instead of __main. Set the M3 config value
  to avoid that."*
- `a6xx_gmu.c:1463–1465`: `a6xx_gmu_power_config()` (`ICACHE_CONFIG=0x1`,
  `DCACHE_CONFIG=0x1` en `:1205–:1206`), y recién entonces `a6xx_gmu_start()`.

`palawan-linux` confirma que no es invento del proyecto: idénticos writes en
sus líneas `1006` (`BOOT_CONFIG, 0x02`) y `1034` (`CM3_CFG, 0x4052`), con el
mismo comentario del NMI. Es mainline/downstream de serie.

Corrección menor al enunciado: no se escriben "los tres" ceros; solo una rama
del `if/else` ejecuta (`:679–:684`). En esta GPU (a7xx) solo se escribe
`A7XX_GMU_GENERAL_9 = 0`, cuyo significado está documentado en el propio
código (`:676–:678`): *"Set the log wptr index"* — puntero del log, **no**
config del CM3. Ponerlo a 0 es inocuo para el fetch.

## 2. ¿Existe un "base del icache" o "address scaler" del CM3?

No hay evidencia en el árbol de tal registro:

- `registers/adreno/a6xx_gmu.xml` define `GMU_CM3_SYSRESET` (0x1f800),
  `GMU_CM3_BOOT_CONFIG` (0x1f801), `GMU_CM3_FW_BUSY`, `GMU_CM3_FW_INIT_RESULT`
  y `GMU_CM3_CFG` (0x1f82d) **sin campos de bit** (solo offsets). Nada que se
  llame scaler/base/AHBNAME del CM3.
- `CM3_CFG = 0x4052` es, según su comentario, anti-NMI para snapshots, no una
  base de direcciones.
- `BOOT_CONFIG = 0x02` no tiene comentario en el árbol; su semántica exacta
  (fuente de arranque) **la desconozco** — pero se escribe siempre, luego el
  CM3 **no** arranca "con la config de reset".
- El `0x4000` del icache **no lo calcula el CM3 desde un registro**: viene de
  dos lados que ya coinciden por construcción: la imagen de fw trae bloques
  con `addr ≈ 0x4000` y `fw_block_mem()` (`:1248–:1255`) los copia al BO
  icache porque ese BO se aloja en iova `0x4000` (`:2837–:2838`,
  `SZ_16M - SZ_16K @ 0x04000`). Los bloques `@0x0` van a ITCM por MMIO
  (`:1298–:1303`) y los `@dtcm_base` (que en a7xx/a8xx es `0x10004000`,
  `:1272–:1275`) a DTCM (`:1304–:1309`). No hay tercer término configurable.

Queda una variante sutil de la hipótesis que sí hay que cerrar: "¿y si
`SYSRESET=1` (`:673`) **borra** `CM3_CFG`/`BOOT_CONFIG`, de modo que lo
escrito en `:1391`/`:1419` no llega a `S3-rst0` (`:709`)?". Respuesta: **no**,
por argumento de diseño mainline — ese orden (config primero, reset después)
es el de serie y funciona en todos los SoC soportados; si el reset limpiase
esos registros, mainline no arrancaría en ningún sitio. `SYSRESET` resetea el
núcleo Cortex-M3, no los registros de envoltura del GMU. La hipótesis no se
salva por esta vía.

## 3. ¿Qué haría el bootloader? ¿El kernel lo pisa?

Si ABL/XBL arrancó el GMU (splash), pudo dejar `CM3_CFG`/`BOOT_CONFIG` con
sus valores **y** el TCM con su fw. Pero da igual para esta hipótesis: el
kernel **reescribe** ambos registros (`:1391`, `:1419`) en cada `fw_start`,
frío o tibio, así que no hereda config del BL — la sustituye. Lo único que
"pisa con ceros" es `GENERAL_9`, que es el wptr del log (downstream lo
guarda/restaura en poweroff; mainline lo pone a 0). Sin efecto sobre el fetch.

El punto del BL que **sí** importa y el proyecto no ha mirado (§5-F) es el
contenido del TCM, no los registros: ver §5.

## 4. Discriminantes baratos (SIN flash: relectura de capturas/binarios)

Ordenados de más barato a menos barato. Ninguno requiere flashear; los tres
primeros ni siquiera requieren build:

- **D1 — ¿fue cold o warm boot?** `a6xx_gmu_resume()` decide por
  `A7XX_CX_MISC_TCM_RET_CNTL == 1` (`:1791–:1792` → warm). Si el BL dejó
  `TCM_RET=1`, el kernel **salta `fw_load`** (`:1376`) y no recarga ITCM/DTCM
  (los pokes `F1-fwloop` `:1291`, `F2-itcm` `:1299`, `F2-dtcm` `:1305`
  **faltarían** en la captura). CM3 con fw stale del BL + dominio IOMMU nuevo
  = fetch a iovas ajenas = `S4-pollFAIL` sin tocar ningún registro. Mirar las
  capturas existentes: presencia/ausencia de `F1/F2` decide warm vs cold.
- **D2 — palabra inicial del DTCM en el .bin.** `S0-dtcmR` (`:640`) lee
  `DTCM_START+0xff8` **antes** de recargar: es la ejecución anterior (stale).
  Extraer del fw (`qcom/gen71100_*` en la initramfs) el bloque que cubre
  `dtcm_base+0xff8` y comparar su palabra inicial con el `dtcm-magic`
  logueado (p.ej. `0x40050001`). Si son **iguales**, el CM3 no escribió nunca
  (muerto antes de ejecutar). Si **difieren**, algo ejecutó (CM3 del BL o del
  kernel) y la muerte es posterior — la hipótesis "primer fetch" pierde fuerza.
- **D3 — `failed to match fw block`.** Si la imagen no corresponde a esta GPU,
  algún bloque cae fuera de icache/dcache/dummy y sale el error de `:1313–
  :1315`. Grep en capturas existentes + histograma de `addr` de bloques del
  .bin contra `[0x4000, 0x1000000)`. Cero coste.
- **D4 — P141 ya está en vuelo** (ledger #483 y ss.): el fault-handler dirá si
  hubo fallo SMMU en `0x4000` (mapeo/contexto, hipótesis K24) o silencio
  total (el CM3 nunca emitió el fetch: reset/reloj/fuente de arranque/fw).
  No anticiparlo; esperar el dato.
- **D5 — readback en arranque (un solo ciclo, si D1–D4 no deciden).**
  Añadir en el path de arranque (nunca runtime, regla 3 de docs/historia/AGENTS.md) una
  lectura de `CM3_CFG`/`BOOT_CONFIG`/`ICACHE_CONFIG` después de escribirlos
  (`:1391`/`:1419`/`:1205`) y otra justo antes de `S3-rst0` (`:709`). Si
  devuelven `0x4052/0x02/0x1` en ambos puntos, la hipótesis queda **enterrada
  por medición directa**. Un `readl` puntual en el path de error/arranque es
  del mismo tipo que el `dtcmR` (`:640`) que ya se hace; no es "volcar rangos".

## 5. Alternativas que el proyecto NO ha considerado

- **A. Warm boot con fw stale del BL (la más seria).** §4-D1. `TCM_RET_CNTL`
  (`:1365` lo pone a 1; `:1791` lo lee) decide `GMU_WARM_BOOT` y salta la
  recarga. Todo lo medido (mapeos OK, S3 alcanzado, silencio) es compatible
  con "CM3 ejecuta el fw del BL contra el dominio nuevo". El poke `H5-boot`
  (`:1804`) no registra el valor de `status`: ni siquiera se sabe qué camino
  se tomó.
- **B. La condición del poll puede ser un falso negativo.** El poll
  (`:717–:718`) espera `(FW_INIT_RESULT & mask) == reset_val` con
  `mask/reset_val` derivados del magic DTCM (`:642–:648`, lógica heredada
  downstream: `0xbabeface` vs `(x & 0x1ff) == 0x100`). Si el fw de esta GPU
  señaliza el éxito con otro valor, el CM3 puede estar **vivo y sano** y el
  poll fallar igual 100 s. El `0x40050001` observado cae en la rama `else`
  (`mask=0x1ff`), y nada en el árbol demuestra que `0x100` sea lo que este fw
  escribe en `FW_INIT_RESULT` (registro **distinto** del DTCM+0xff8 del que
  sale la máscara). Cruzar con D2/D4 antes de tocar registros.
- **C. AHB fence, no SMMU.** `AHB_FENCE_RANGE_0` se programa en `:1410–:1413`
  con `upper=0x32/lower=0x8a0` (rama a7xx). Si esa ventana no cubre el camino
  del fetch, el bloqueo es por fence (bit `FENCE_ERR`, ya en la máscara IRQ
  `:1500–:1503`) y **no** genera fault SMMU: P141 saldría "silencio" y
  parecería "CM3 muerto" siendo "CM3 bloqueado". Tras un timeout, un `readl`
  puntual de `AHB_FENCE_STATUS` en el path de error lo distingue (registro
  GMU, no SMMU; mismo nivel de riesgo que el `dtcmR` existente).
- **D. `chipid` que el fw rechaza.** `GENERAL_10` (`:1442`) recibe el chipid
  (`:1421–:1434` o `gmu_chipid` del catálogo). Si la entrada de catálogo no
  corresponde al SM8635/Adreno 735 real, algunos fw se niegan a poner
  `INIT_RESULT`. Verificar `chip_id` detectado vs esperado; el driver no lo
  loguea (solo la versión del fw, `:1322–:1325`).
- **E. Relojes encendidos pero a rate imposible.** El hecho 6 prueba
  `prepare_enable` (`:1758`), no el rate. El propio código lo sospecha
  (`:1765–:1769`, log `clks core/hub`). Leer ese log en capturas existentes:
  `core=0/hub=0` o rates que el fw no espera son indistinguibles de "CM3
  muerto". Cero flashes.
- **F. `HFI_QTBL_ADDR` como primer acceso real.** Se escribe en `:1395` con
  `gmu->hfi.iova` (BO con iova automática, `:2873`). Si ese BO no quedó
  visible para el SID 5, el primer fault del CM3 sería en el HFI, no en el
  icache — P141 lo dirá por la dirección (cf. P142 del ledger).

## 6. Regla de seguridad (incidente UAF/`0x10000000c`)

- **No escribir S2CR/CBAR/CFGR/TTBR de ningún CB con `SME→TRANS` vivo del
  BL** (los `S2CR(n)=0x00020000` heredados). El código actual solo los lee
  (paseo K19/K24); mantenerlo así: lectura o nada.
- **No tocar `AHB_FENCE_RANGE_0` a ciegas**: es la ventana que mantiene vivo
  el acceso del GMU; un valor experimental puede convertir un timeout
  recuperable en un wedge de bus (congelamiento en el primer `readl`, firma
  K25). Solo lectura de `AHB_FENCE_STATUS` en path de error.
- **No tocar `RSCC`/votos FAL (`:1356–:1357`, `:940-s` en apagado),
  `PDC`/secuenciador (`:1140–:1187`), ni `GX GDSC` fuera del orden de
  `resume`**: son el orden de encendido; alterarlos puede dejar el rail a
  medio subir, firma idéntica a "CM3 muerto" pero causada por nosotros.
- **`CM3_SYSRESET` solo en la secuencia existente** (`:673`/`:709` y el halt
  de apagado `:1589`): un `=1` olvidado o fuera de orden deja el núcleo en
  reset contra un dominio recién creado — indistinguible del bug perseguido.
- **Nada de MMIO/SMMU en runtime** (regla 3 de docs/historia/AGENTS.md, vigente): toda
  lectura nueva, en el path de arranque o en el path de error del poll, con
  `pr_info` + `pr_flush`, como ya hacen `S0-dtcmR` y `S3-rst0`.

## 7. Recomendación

**No gastar un flash en la hipótesis formulada** (config de reset): su premisa
contradice `a6xx_gmu.c:1391` + `:1419` + `:1467`, y no existe en el árbol
ningún registro de "base del icache del CM3" que la sostenga. Orden propuesto
sin flashes: D1 (warm/cold en capturas) → D2 (palabra inicial del .bin) →
D3 (bloques sin match) → E (rates en logs) → esperar P141. Solo si todo eso
sale nominal, un único ciclo con el readback D5, que decide por medición
directa.
