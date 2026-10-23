# C1 — Crítica técnica adversarial (2-oct-2026)

Rol: refutar, no confirmar. Árbol verificado: `build/kernel-pokes/k18-tree`
(líneas citadas de ESE árbol; K37/K38 añaden pokes pero no cambian la lógica
citada salvo donde se indica). Logs: `build/logs/`. Ledger hermano
`~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md` (#467–#480).

Veredictos arriba, pruebas abajo. "Hipótesis" = no medido. Todo hallazgo trae
su modo de fallo concreto o no cuenta.

---

## 1. Afirmación 1 (ERANGE = TTBR1 vs iovas bajos; `shared=0` lo evita): SE SOSTIENE, pero con dos grietas

### 1.1 Lo que el código confirma, literalmente

- `drivers/iommu/io-pgtable-arm.c:591-599`: `iaext = (s64)iova >> cfg->ias`;
  con quirk TTBR1 `iaext = ~iaext`; `WARN_ON(iaext || paddr >> cfg->oas)` →
  `-ERANGE`. Es el ÚNICO `return -ERANGE` de `arm_lpae_map_pages`. Con quirk,
  cualquier `iova < 2^ias` da `iaext = ~0 ≠ 0` ⇒ rechazo categórico. Correcto.
- `drivers/iommu/arm/arm-smmu/arm-smmu.c:1950-1956` (mainline, no poke):
  con TTBR1 `aperture_start = ~0UL << ias`; sin él `aperture_end = (1UL<<ias)-1`.
- `drivers/iommu/arm/arm-smmu/arm-smmu-qcom.c:369-382` (números del árbol
  CON pokes; el `return 0` es mainline): `if (!qcom_adreno_smmu_is_gpu_device(dev))
  return 0;` ANTES de fijar el quirk. GMU = SID 5
  (`arch/arm64/boot/dts/qcom/palawan.dtsi:2501`, `iommus = <&adreno_smmu 5 0x0>`;
  GPU en `:2381` con SID 0) ⇒ sale por el `return 0`, sin quirk. Correcto.
- Iovas fijos bajos del GMU: `a6xx_gmu.c:2808` `debug=0x60400000`, `:2817`
  `dummy=0x60000000`, `:2826` `icache=0x04000`; ventana `0x0..0x80000000` en
  `:2063`. Correcto.
- `msm.uke_gmu_shared=0` ⇒ `a6xx_gmu_memory_probe` (`a6xx_gmu.c:2043-2060`)
  toma la rama `msm_iommu_new(gmu->dev, 0)` (dominio propio) en vez de compartir
  el mmu de la GPU. Medido en #478: desaparece `UKE-K20: COMPARTIENDO`,
  `gmu init ret` sin `-34`, sin `WARNING io-pgtable-arm.c:599`. Coherente.
- Otras fuentes de `-ERANGE` en el camino, descartadas (spot-check, no solo R6):
  `drm_mm.c`/`drm_gpuvm.c` devuelven `-ENOSPC`/`-EINVAL`/`-EEXIST`, nunca
  `-ERANGE`; `msm_iommu.c:691-695` propaga; el lado `paddr >> oas` es imposible
  con `mem=2048M` (toda la RAM < 4 GB ⇒ `paddr>>32 == 0`); `dev_pm_opp`
  devuelve `-ERANGE` pero `a6xx_gmu_pwrlevels_probe` (`a6xx_gmu.c:2420+`) lo
  traga (`ret = 0` inicial, sin propagación al `ret` de `gmu_init`).

### 1.2 GRIETA A — K31 refutó a R6 con una medición que #470 demostró vacía, y #478 lo des-refuta

K31 §"reemplaza a R6" dice que el sujeto de R6 (compartir ⇒ TTBR1) es FALSO,
apoyado en K30 (`shared=0` + `-ERANGE`). Pero #470 probó que K30 corrió con
`shared=1` real (parámetro desnudo ignorado). Luego #478 mide el par limpio:

- compartido (K34) → `-34` + `WARNING :599` (dominio TTBR1 de la GPU);
- propio (K35) → sin `-34` (dominio sin quirk por el `return 0`).

Eso es EXACTAMENTE el sujeto de R6. Conclusión: **la "refutación" de R6 en la
cabecera de K31/R6 está obsoleta y debe revertirse; R6 tenía razón en mecánica
Y en sujeto.** El nudo abierto real nunca fue "compartir vs propio" (resuelto),
sino por qué el cfg compartido llevaba TTBR1 — que también está resuelto: lo
lleva porque es el dominio de la GPU (SID 0), no por herencia misteriosa.
Las hipótesis (a)/(b) de K31 (`is_gpu_device` confunde el SID; herencia del CB
del BL) eran necesarias solo bajo la premisa falsa de "dominio propio con
quirk". Con #478 esa premisa muere: **(a) y (b) no son hipótesis abiertas, son
hipótesis que ya no hacen falta**. Mantenerlas abiertas gasta ciclos.

### 1.3 GRIETA B — El mecanismo `return 0` es lectura de código, NO medición

La sonda que lo probaría (`UKE-K32`, `arm-smmu-qcom.c:390-430`) emite a
`pr_info`/`pr_warn` mezclados y el proyecto la declara invisible a `loglevel=4`
(P111 pendiente). El `gmu init ret` sin `-34` es COMPATIBLE con el `return 0`,
pero también con cualquier otro dominio sin quirk (p. ej. distinto `ias`/`oas`
negociado, `fmt` distinto). No se ha medido `quirks/ias/oas/aperture` del
dominio propio del GMU NI UNA VEZ. Modo de fallo si se da por hecho: un futuro
`-ERANGE`/`-EBUSY` en otra config se diagnosticará mal por asumir un quirk
medido que nunca se midió. Barato de cerrar: K38 ya propone subir K32 a WARN;
hasta entonces, "el `return 0` evita el quirk" es hipótesis (fuerte, pero
hipótesis).

### 1.4 Detalle menor pero real: `is_gpu_device` desreferencia `fwspec` sin NULL-check

`arm-smmu-qcom.c:228-241`: `fwspec->num_ids` sin comprobar NULL (el propio
comentario UKE-K33 lo admite). Modo de fallo: device sin fwspec ⇒ Oops en
`init_context`, no `-ERANGE`. No afecta a la cadena actual (GMU tiene fwspec),
pero el "helper seguro" del proyecto solo existe en su árbol, no upstream.

---

## 2. Afirmación 4 (`firmware_class.path` oculta `/usr/lib/firmware`): REFUTADA

### 2.1 El código dice lo contrario de lo afirmado

`drivers/base/firmware_loader/main.c:471-479`:

```c
static char fw_path_para[256];
static const char * const fw_path[] = {
        fw_path_para,                    /* custom, mayor prioridad */
        "/lib/firmware/updates/" UTS_RELEASE,
        "/lib/firmware/updates",
        "/lib/firmware/" UTS_RELEASE,
        "/lib/firmware"                  /* <-- sigue aquí */
};
```

y `fw_get_filesystem_firmware` (`:506-600`) itera TODO el array: `if
(!fw_path[i][0]) continue;` … `rc = kernel_read_file_from_path_initns(...)`;
si falla, `continue` al siguiente. **El path custom es un intento MÁS, de mayor
prioridad; no elimina ni sombrea ningún fallback.** La afirmación 4, tal como
está redactada ("hace que el cargador NO vea /usr/lib/firmware"), es falsa en
este kernel.

Dos remates:

- El valor del ABL (`/vendor/firmware_mnt/image,/vendor/firmware,…`) entra en
  `fw_path_para` como UN solo string con comas (`module_param_string`, `:485`,
  no trocea). `snprintf("%.*s/%s%s")` construye UNA ruta con comas incrustadas
  ⇒ `ENOENT` siempre ⇒ `continue`. El path custom del ABL estaba MUERTO y era
  inofensivo, no un secuestrador.
- **P90 refuta la afirmación con el propio experimento del proyecto**: K34
  carga el SQE desde `/lib/firmware` del initramfs CON `firmware_class.path`
  del ABL intacto en la cmdline (prefijo de 356 B preservado, #476-bis). Si el
  custom path ocultara los fallbacks, P90 habría sido imposible.

### 2.2 La historia correcta es solo timing, y explica TAMBIÉN por qué falló `/vendor`

A ~4.1 s, `kernel_read_file_from_path_initns` opera en el mount ns de init,
cuya raíz es el initramfs (pre-`switch_root` del ukeinit). Pre-K34:

- `/lib/firmware/...` del initramfs: existe el directorio, FALTA el fichero
  (medido: `cpio -it | grep -c gen71100` = 0 en K12/K22, #476) ⇒ `-2`.
- `/vendor/firmware/qcom/` copiado en #475: vive en la rootfs ext4, que a las
  4.1 s AÚN NO ESTÁ MONTADA ⇒ `-2` igualmente. **P80 FALLIDO queda explicado
  sin invocar ningún shadowing**: la ruta llega tarde, no está bloqueada.

`regulatory.db` sigue fallando en K34 por el mismo motivo puro (no se horneó;
solo se hornearon los 3 blobs GPU) — control negativo que confirma el modelo
timing y sobra al modelo path-shadowing.

### 2.3 Lo que el proyecto debe corregir por escrito

U1 §1 ("los paths de `firmware_class.path` … se caen solos; `/lib/firmware`
del initramfs decide") es correcto y contradice la afirmación 4 del encargo.
La afirmación 4 debe marcarse REFUTADA y sustituirse por: "a 4.1 s solo existe
el initramfs; todo firmware temprano va horneado". Nada de `/vendor` servirá
jamás para un consumidor de probe temprano — lección general, no solo GPU.

---

## 3. Contradicción no resuelta: K13 "estable" NUNCA ejecutó el CM3

El proyecto compara el wedge de K37 contra la estabilidad del par bueno K13
como si K13 hubiera superado S3. Falso:

- En K13 no había firmware alcanzable a 4.1 s (initramfs sin blobs; rootfs aún
  sin montar) ⇒ `adreno_load_fw` falla ⇒ `fw[ADRENO_FW_GMU]` NULL ⇒ en el
  primer `resume`, `a6xx_gmu_fw_start` (`a6xx_gmu.c:1376-1384`) hace
  `WARN(!fw) + return -ENOENT` con `H7-fwFAIL`, ANTES de `a6xx_gmu_start`.
  El CM3 jamás sale de reset en K13. `card0` existe (#471) porque el DRM se
  registra antes de `load_gpu` — presencia de `card0` ≠ GPU funcional ≠ CM3
  ejecutado.
- K34/K37 es **la primera vez en el proyecto que el CM3 ejecuta una
  instrucción**. El "progreso S1→S3" no es progreso contra K13; es territorio
  nuevo. Las muertes S1→S2 de #447/#452 eran de la era del volcado K19 (H2,
  ver §5.3).

**Control que falta y que decide más que cualquier sonda (0 recompilación)**:
mismo kernel K37 + cmdline CON `video=DSI-1:d` (display off) + firmware en
initramfs. Si el CM3 supera S3 ⇒ el wedge es interacción con la vía display
encendida (DPU/RPMH/potencia concurrente), no SMMU/CB. Si wedgea igual ⇒
SMMU/CB/contenido-firmware. Un ciclo, una variable. No se ha hecho.

Consecuencia para la afirmación 2 ("el cuelgue original, localizado"): lo
localizado es el PRIMER fetch del CM3 en la historia del proyecto, no "el
cuelgue original" (aquel nunca tuvo firmware; su firma S1→S2 pertenece a otra
causa, probablemente H2). El título de #480 induce a error.

---

## 4. El cuelgue en S3-rst0: lo que el proyecto no ha considerado

### 4.1 Hallazgo estructural: el dominio propio del GMU NO tiene fault handler ⇒ el silencio es lo ESPERADO, no una pista

- `msm_iommu_new` (`drivers/gpu/drm/msm/msm_iommu.c:736-810`, la que usa el
  GMU con `shared=0`): hace `iommu_attach_device` y NADA más. **No instala
  ningún fault handler.**
- `msm_iommu_gpu_new` (`:820-846`): `iommu_set_fault_handler(...,
  msm_gpu_fault_handler, ...)` en `:841`. `msm_iommu_disp_new` (`:817`):
  instala el suyo.
- R6 §5 argumenta: "si el fetch no resolviera, el SMMU elevaría context fault
  (hay handler)… El silencio apunta a otra capa". **Eso era verdad con dominio
  compartido y es FALSO con dominio propio**: cualquier fault del CB del GMU
  (fetch a iova sin mapear, permiso, TTBR0 corrupto) es mudo por construcción.
  Modo de fallo concreto: `icache@0x4000` mal copiado / QTBL apuntando fuera /
  TTBR0 rancio ⇒ context fault ⇒ nadie lo imprime ⇒ exactamente el silencio
  medido. El proyecto busca el wedge en relojes/relés mientras la causa más
  barata (un fault invisible) sigue sobre la mesa. Test barato: instalar
  `msm_gpu_fault_handler` (o un `pr_warn` mínimo) en `msm_iommu_new` — un
  ciclo de build, cero riesgo SMMU.

### 4.2 "El poll está esperando" (#480-bis): REFUTADO por ausencia de H8/H9

- `gmu_poll_timeout` es `readl_poll_timeout` (`a6xx_gmu.h:177-179`): un
  `readl` en bucle. **Un `readl` colgado en el bus no retorna jamás; ningún
  timeout lo rescata.** Si el primer `readl` de `FW_INIT_RESULT` cuelga el
  interconnect (firma que el propio U1 §5 ya describió: "wedge de bus en el
  primer readl del sondeo"), S4 no puede imprimirse por diseño.
- Si en cambio el poll retornara (timeout a los 100 ms — nótese: la llamada
  `a6xx_gmu.c:717-718` pasa `100, 100000` = intervalo 100 µs, timeout 100 ms;
  el ledger dice "100 ms, 100000 ms", unidades ×1000 erradas), el código
  SEGUIRÍA imprimiendo: `S4-pollFAIL` (`:719`), `H8-cm3FAIL`, `H5-fwstartFAIL`
  y el resto del arranque (otros drivers, systemd). Nada de eso aparece y no
  hay SSH ⇒ **no fue un timeout limpio; fue un wedge duro** (bus colgado en
  el `readl`, o CPU muerta) **o** muerte de la consola con arranque vivo —
  y la ausencia de SSH excluye lo segundo. El `[missed 9753 bytes]` tras S3
  impide afirmar "muere EN S3", pero sí permite afirmar "muere SIN SALIR del
  tramo S3→S4", que es lo único que el diagnóstico necesita. La cautela de
  #480-bis es honesta pero su hipótesis benigna ("podría estar esperando")
  debe marcarse REFUTADA: un poll que espera no silencia el resto del boot.

### 4.3 Candidato nº1 del proyecto ("SID 5 no reprogramado al CB nuevo"): formulado al revés

Con `shared=0`, `msm_iommu_new` → `iommu_attach_device` → `arm_smmu_attach_dev`
REESCRIBE SMR/S2CR del SID 5 al CB nuevo por diseño mainline. "No se
reprogramó" es, sin cualificar, probablemente FALSO. Los modos de fallo
concretos compatibles con el código son tres, y el proyecto solo contempla el
primero de forma vaga:

- (i) Reprogramado BIEN, pero el CB nuevo traduce con TTBR0/TLB rancios: K37
  lleva `arm_smmu.uke_kgsl_keep=0` ⇒ reset mainline completo del kgsl-smmu
  (default `uke_kgsl_keep=1` en `arm-smmu.c:154`; el 0 lo anula) ⇒ fases 2/3/4
  SÍ corren ⇒ S2CR/CB/TLB parten de cero. Este es el camino mainline normal;
  si aquí hay bug, es bug upstream, no del proyecto.
- (ii) Reprogramado BIEN, pero el fetch FAULTA (contenido/QTBL/BOOT_CONFIG) y
  es mudo por §4.1. **Mi candidato principal.**
- (iii) Desviado por los hacks de preservación del propio proyecto: con los
  defaults (`uke_attach_log=0`, `uke_protect_smr0=0` — ambos 0 por defecto en
  `arm-smmu.c:396` y `:419-435`) NO hay desvío en K37, así que (iii) queda
  DESCARTADO para K37 (bien), pero OJO: cualquier ciclo futuro con
  `uke_attach_log=2` o `protect_smr0=1` + `shared=0` reintroduce el desvío del
  SID 5 a otro CB — interacción documentada en el propio comentario K5 y no
  contemplada en el plan K38. Si K38 activa esas sondas a la vez que mide el
  CB, la medida sale contaminada por el instrumento.

### 4.4 Candidato nº2 ("icache en TTBR0 pero el CM3 usa TTBR1/PASID"): vago hasta ser infalsable

El CM3 (SID 5, S1, sin per-instance) camina el TTBR0 del CB al que apunta su
S2CR. No hay PASID en este camino (el mecanismo TTBR0/TTBR1 por instancia es
solo GPU vía `get_ttbr1_cfg`/`set_ttbr0_cfg`, que el GMU ni registra: esas
punterías solo se instalan en la rama GPU de `init_context`,
`arm-smmu-qcom.c:440-450`). Para que este candidato cuente debe reformularse
como: "el CB al que apunta S2CR(5) no es el del dominio del GMU" — que es el
candidato nº1 con otro nombre — o retirarse. Tal como está, duplica el nº1 sin
mecanismo propio.

### 4.5 Candidatos que faltan (con modo de fallo concreto cada uno)

- (iv) **Contenido del firmware, no su presencia**: P90 prueba que el SQE se
  CARGA, no que sea el correcto para este SKU. El proyecto ya sabe (U1 §2) que
  el ZAP del QRD tiene otra firma y lo rechazó; el mismo riesgo existe para
  `gen71100_gmu.bin`/`sqe.fw` (volcado vendor: ¿de ESTA tablet o de otra
  unidad/SKU?). Modo de fallo: CM3 ejecuta basura ⇒ no escribe
  `FW_INIT_RESULT` ⇒ poll expira… (pero ver §4.2: exóta con ruido, no silencio;
  para silencio total haría falta además wedge de bus por fetch salvaje —
  posible pero de segundo orden). Test: comparar shas contra volcado de ESTA
  unidad + `dtcm-magic` post-S3 (imposible si wedgea; entonces BOOT_CONFIG).
- (v) **Secuencia pre-S3 propia de A7xx**: `BOOT_CONFIG=0x02`, `CM3_CFG=0x4052`,
  `AHB_FENCE_RANGE`, `chipid` reconstruido (`a6xx_gmu.c:1390-1462`), QTBL con
  `gmu->hfi.iova`. Todo escrito ANTES de soltar el reset y nunca cuestionado.
  Modo de fallo: `BOOT_CONFIG`/`chipid` erróneo para SM8635 ⇒ el CM3 arranca en
  vector equivocado ⇒ sin `FW_INIT_RESULT`. Es la zona más cercana al punto de
  muerte y la menos auditada (el proyecto audita SMMU pero no estos cinco
  registros).
- (vi) **Contención display-encendido**: K37 es el primer arranque con DPU
  activo Y CM3 ejecutando. `fw_start` hace `a6xx_rpmh_start`, votos ARC/BW,
  `power_config` (`:1463-1465`) antes de `gmu_start`; el DPU concurrente vota
  lo suyo. Modo de fallo: rail/reloj compartido colapsa al arrancar el CM3 ⇒
  el `gmu_write(SYSRESET,0)` de `:709` es la última escritura que sale. El
  control de §3 (K37 + `:d`) lo decide de un plumazo.
- (vii) **Relojes**: la línea `clks core=… hub=…` de K37 EXISTE en la captura
  (#480 la cita: `core=220000195 hub=400000000`); el proyecto la imprime pero
  no la juzga. `clk_set_rate(200 MHz/150 MHz)` en el resume
  (`a6xx_gmu.c:1755-1756`) vs medidos 220/400 MHz ⇒ los `set_rate` NO
  prendieron (padres/constraints) o la medida es de otra época (esa línea es
  del log 1818, era s260). Hay que citar los valores DE LA CAPTURA K37, no
  asumirlos. Si el hub va a 400 MHz cuando el fw espera 150 MHz, el timing
  interno del CM3/HFI puede romperse. Hipótesis, con número concreto que
  mirar.

---

## 5. Techo de 3 ciclos: lo que debe marcarse REFUTADO ya

| # | Hipótesis | Ciclos consumidos | Veredicto que propongo |
|---|---|---|---|
| H2 | El volcado SMMU (K19) causa el wedge | K25 (dump off, sigue el problema), K36/K37 (wedge con `uke_smmu_dump` default 0, `a6xx_gmu.c:360-361`) | **REFUTADA**. El wedge existe sin volcado. Cerrar H2 y no reabrirla sin evidencia nueva. |
| P91 | `uke_kgsl_keep=0` arregla el `-ERANGE` | K34 (medido `-34` persistente, #477) | **REFUTADA** (el proyecto la da por fallida pero no la archiva; archivarla). Era además implausible: el keep afecta al reset del SMMU, no al quirk del dominio. |
| FW-path | `firmware_class.path` sombrea `/lib/firmware` | #475 (vendor no sirve), #476 (initramfs sí), P90 con path activo | **REFUTADA** por código (`main.c:471-479`, bucle con fall-through) y por experimento. Sustituir por modelo timing (§2.2). |
| OVERLAP | Solape `splash_region`/`s19fb` causa el cuelgue sin `:d` | #471-bis, #472-bis (P61 FALSO dos veces) | Ya refutada por el proyecto — mantenerla cerrada; que no reaparezca como "bug a arreglar antes del CM3" (es cosmético hasta tener imagen). |
| POLL-WAIT | Tras S3 el kernel "espera en el poll" | K37 (ausencia de H8/H9 + resto del boot + SSH; §4.2) | **REFUTADA**. Lo que sigue a S3 es wedge duro o nada; no un timeout limpio. |
| K31-cabecera | "R6 se equivocó en el sujeto" | #470 (K30 midió shared) + #478 (par limpio shared/propio) | **OBSOLETA**. Revertir la cabecera de K31/R6: R6 acertó sujeto y mecánica. Las hipótesis (a)/(b) de K31 se disuelven (ver §1.2). |
| K13-base | "K13 = CM3 funcionando, referencia de estabilidad" | §3 (K13 nunca liberó el CM3) | **REFUTADA como referencia**. K13 es referencia de "probe sin CM3", no de "CM3 sano". El control válido es K37+`:d` (pendiente). |

---

## 6. Lo que SÍ se sostiene (para no tirar nada válido)

- Mecánica TTBR1/iova-bajo + `return 0` del SID 5 + `msm.uke_gmu_shared=0`
  como palanca (§1.1). P101/P103/P105 de #478 son medidas reales.
- Firmware en initramfs como condición necesaria (P90). U1 §1/§4 correctos.
- S3-rst0 como primer punto donde el CM3 ejecuta de verdad en-proyecto (#480,
  con la corrección de #480-bis sobre S4: lo cierto es "sin salida del tramo
  S3→S4", no "muere EN S3").
- Blindaje del unwind (`bo->obj = NULL`): sin Oops en #478 ⇒ aguanta; era
  necesario y funcionó.
- Regla operativa de no instrumentar SMMU en runtime: el wedge de bus en
  `readl` (§4.2) la justifica a posteriori — cualquier sonda post-S3 corre el
  mismo riesgo que el poll.

## 7. Próximo ciclo sugerido (orden adversarial: lo más barato y lo que más cierra)

1. **K37 + `video=DSI-1:d`** (solo cmdline, 1 escritura): el control de §3.
   Decide display vs SMMU de una vez. Si supera S3, todo el plan SMMU/CB se
   aparca y se persigue (vi).
2. **Fault handler en `msm_iommu_new`** (build, §4.1): convierte el silencio en
   diagnóstico. Si tras S3 aparece un context fault con `iova=0x4000…`, el
   misterio se acaba ahí.
3. **K38 (sondas a WARN) solo DESPUÉS de 1–2**, y con `uke_attach_log=0` +
   `protect_smr0=0` explícitos para no contaminar la medida del CB (§4.3-iii).
   Auditar antes los cinco registros pre-S3 de (v) por lectura de código
   (0 flashes): `BOOT_CONFIG`, `CM3_CFG`, `AHB_FENCE`, `chipid`,
   `HFI_QTBL_ADDR` contra downstream SM8635.
4. No reabrir H2, FW-path, OVERLAP, POLL-WAIT ni (a)/(b) sin evidencia nueva.
   Están en la tabla de §5.
