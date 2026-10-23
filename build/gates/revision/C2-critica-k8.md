# C2 — Crítica hostil del parche K8 (handoff) y de la imagen `boot-ukek8.img`

Fecha: 2026-09-29 (tarde). Autor: agente crítico C2. **Sin tablet** (no adb/fastboot/ssh/ttyACM0).
Fuentes leídas enteras o en las zonas citadas: `build/gates/patches/k8-handoff.diff`,
`INFORME-K8-BUILD.md`, `PRE-REGISTRO-PANTALLA.md` (#P8–#P24), `revision/R1-smmu-kseries.md`,
el árbol resultante `/var/tmp/uke-k8-tree/drivers/iommu/arm/arm-smmu/{arm-smmu.c,arm-smmu.h,
arm-smmu-qcom.c,arm-smmu-impl.c}`, el DT `~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img` (fdtdump) y
`/var/tmp/k8-check/merged.dtb`, y los ficheros de instrumentación `drivers/soc/qcom/uke-{panic-fb,prevlog}.c`.

Todo `file:line` de este informe es del **código resultante** (árbol K8), no del diff.

## 0. Verificación independiente del artefacto (hecha por C2, no copiada del informe)

| comprobación | resultado |
|---|---|
| `sha256(build/bootimg/boot-ukek8.img)` | `5e34596a230d2d645ad8dcc68dcba5c23bc58bf2a6c6468a526a66bb687d54e2` ✔ (== informe) |
| forma | 100663296 B, `ANDROID!`, `kernel_size`@8 = 16572290 |
| payload kernel @4096 descomprimido por C2 | 41355776 B, sha `ae4485dbf48016162665d33e038c91c477f55a9972b59df3bf6c8b17ecfc5ff1`, magic @56 = `41 52 4d 64` ✔ |
| payload gzip sha | `fad9a1600d81ba6d…` ✔ |
| cmdline | **byte a byte la de K7** (382 B); sin `uke_handoff` ⇒ modo 1 (barrido completo) por defecto ✔ |
| `uke_handoff=2` pre-empaquetada | `/var/tmp/uke-k8/boot-ukek8-h2.img` difiere **solo** en ` arm_smmu.uke_handoff=2` ✔ |
| strings en la Image | 82 `UKE-POKE`, `arm_smmu.uke_handoff` presente, migas K8 presentes ✔ |
| DT efectivo | `qcom,handoff-smrs = <0x1c00 0x02>` en base y en `merged.dtb` (línea 13716) ✔ |
| `qcom,smmu_sde_unsec_cb` | `iommus = <0x129 0x1c00 0x02>` ✔ · `qcom,smmu_sde_sec_cb` = `0x1c01 0x00` (NO cubierto por el par) |
| `ufshc@1d84000` | `iommus = <0x129 0x60 0x00>` + `qcom,iommu-dma="fastmap"`, addr-pool <0x1000 0xfffff000> |

**El artefacto es íntegro y el árbol del build coincide con los sha del informe** (`arm-smmu.c`
`4c1beba1…`, `arm-smmu.h` `d687b11f…`). La crítica siguiente es de diseño y de lectura, no de integridad.

## 1. Tabla de huecos (hueco → file:line → severidad)

Severidad: **MATA** = puede colgar/matar el sistema o hacer inútil el objetivo; **RIESGO** = puede
gastar un flash o llevar a una conclusión falsa o degradar la función; **COSMÉTICO** = doc/forma.

| # | hueco | file:line (árbol K8) | sev. |
|---|---|---|---|
| H1 | **El pineo NO cubre el reset que se ejecuta**: F4 `TLBIALLH/NSNH` globales, F5 RMW de sCR0, F6 `impl->reset` (sACR + `CB_ACTLR` ×71 del CPRE) y F7 `tlb_sync + write sCR0` (quita `CLIENTPD`, toca `USFCFG`/`GF*`) siguen armados con `uke_reset_mask=12`; el pineo solo mira SMR/S2CR. | `arm-smmu.c:2777-2825` (F4 :2779-2780, F5-7 :2787-2822), `arm-smmu-impl.c:118-148` | **MATA** |
| H2 | **Ningún CB está protegido**: `arm_smmu_write_context_bank` escribe CBAR/CBA2R/TCR/TTBR/MAIR/SCTLR de un índice cuya vida el BOOTLOADER no declara; y el quirk escribe CB70 *antes* de que exista ningún pineo. La "reserva desde arriba" elige **69** (70 lo tiene el quirk) sin ningún dato de que 69/68 estén libres. | `arm-smmu.c:1300-1402` (escrituras :1324/:1361/:1399), llamadas :1596/:1657/:2768; asignador :1420-1421 + :777-784; quirk `arm-smmu-qcom.c:546-551` | **MATA** |
| H3 | **El pineo por DT condena al display a no traducir por el CB del kernel**: el SID 0x1c00/0x02 se pina y `install_s2crs` hace `continue` ⇒ el S2CR nunca apunta al CB nuevo; pero `msm_iommu` sí crea su propio dominio y programa un CB (69/68). La foto/modetest no puede ser evidencia de éxito. El vendor hace lo contrario: escribe el S2CR cuando el dominio tiene otro type/cbndx. | `arm-smmu.c:1992-1996`, `:2178-2181`; `arm-smmu-qcom.c:709-727`; `drivers/gpu/drm/msm/msm_iommu.c:752`; ref. vendor `/var/tmp/uke-k8/ref/xiaomi-arm-smmu.c:1901-1909` | **RIESGO (misión)** |
| H4 | **La muerte muda a 0,44 s no deja miga recuperable**: ttyGS0 nace a 3,57 s; el ring solo se lee si el boot sobrevive; `X9PREV` nunca ha funcionado (todos los logs: `zona no valida sig=140039da sz=0`); el kmsg_dumper solo corre en *panic* y el timer que repinta el FB es de 2 s (en #P17/#P22/#P23 no disparó: la pantalla quedó en la splash del ABL). El barrido además solo imprime progreso cada 16 índices. | `uke-panic-fb.c:480-503` (dumper), `:506-533` (timer 2 s); `uke-prevlog.c:38-49`; `arm-smmu.c:728-730` | **RIESGO (diagnóstico)** |
| H5 | **h2 no aísla el barrido**: modo 2 pina solo lo que la RAM ya sabe (`smrs[].valid` = idx 0 con `uke_smr_max=0`) ⇒ el storm vuelve a escribir idx 1..109 (el asesino medido de K4c). Que h2 muera muda NO exonera al barrido: con h2 el barrido no corre y el asesino conocido sigue armado. La fila 1 del árbol de desenlaces del INFORME usa h2 como discriminador y no lo es. | `arm-smmu.c:709-722` (pins modo 2), `:1991-2013` (attach), `:2070-2074` (2º bucle) | **RIESGO (metodológico)** |
| H6 | **Divergencia RAM↔HW en los pineados**: el attach reclama el índice y, si la RAM no lo tenía válido, escribe `smrs[idx] = sid/mask del maestro NUEVO, valid=1` **sin tocar el HW** ⇒ `find_sme` ve un SMR que no existe en el hardware; otro maestro puede casar por subconjunto ese índice (falso match) y compartir un SME cuyo HW es del BL. Sin miga de aviso. | `arm-smmu.c:1998-2003` (+ `find_sme` :1886-1895) | RIESGO (latente) |
| H7 | **"Antes de cualquier escritura" es falso**: `qcom_smmu_cfg_probe` ya escribió `S2CR(109)` y CBAR/SCTLR(70) (vía cfg_probe, :3441) antes de `uke_handoff_preparar` (:3485). Si SMR(109) fuera un mapeo vivo, el barrido lo pina **después** de que su S2CR esté pisado y ya no se puede arreglar. | `arm-smmu-qcom.c:537-551` vía `arm-smmu.c:3441`; preparación `arm-smmu.c:3485` | RIESGO / COSMÉTICO |
| H8 | **El UFS depende de un estado del BL que K8 cambia sin medir**: el kernel lo trata IDENTITY y el HW sigue con S2CR(0)/CB22 del BL, pero K8 reescribe sCR0 (`CLIENTPD→0`) y hace el barrido `CB_ACTLR`; no se comprueba que las tablas del CB del BL sigan siendo coherentes (el kernel pudo reusar esa memoria). Un mapeo TRANS del BL ya no compatible = fallo de UFS/mount a 13,8-15,6 s, que es el gate real. | `arm-smmu.c:3265-3267` (RMR: `CLIENTPD=1` incondicional), `:2797-2822`; escape actual = repack `mask=4/0` (R1 §6.a avisa que `mask=0` deja `CLIENTPD=1`) | RIESGO |
| H9 | Doc: "los tres puntos de escritura" / "ANTES del primer acceso que escribe algo"; el §2.5 del INFORME omite que el CB del pineado no está protegido y que el S2CR del quirk no pasa por los guards. | `arm-smmu.c:3481-3484`; INFORME §2.2/§2.5 | COSMÉTICO |
| H10 | Fuga lógica: un índice pinado por DT (no vivo en el BL) nunca se invalida al liberar (`free_sme` devuelve `false` y no resetea) ⇒ queda "valid=1 en RAM" para siempre; refuerza H6. | `arm-smmu.c:1916-1922` | COSMÉTICO |

**Lo que sí está bien (crédito donde toca)**: el fix del bug ALTA de R1 §7.1 es correcto y suficiente
(`arm_smmu_free_sme` devuelve `false` **antes** de tocar RAM y el llamante no escribe, `:1916-1922` +
`:2155-2158`); no hay **ninguna** lectura nueva de S2CR (`uke_dump_bl_state` la evita, `:478-490`);
los guards cubren todos los caminos SMR/S2CR salvo el quirk (H7); y la anti-regresión del arranque
desarmado es real (§4 abajo).

## 2. Respuestas a las preguntas de demolición

### Q1 — PINEO: cobertura y "antes de cualquier escritura"

- **El barrido corre tarde**: `uke_handoff_preparar` se llama en `arm-smmu.c:3485`, y antes de ese
  punto `qcom_smmu_cfg_probe` ya escribió `S2CR(109)` y CBAR+SCTLR de CB70 (`arm-smmu-qcom.c:537-551`).
  La afirmación del comentario `:3481-3484` ("ANTES del primer acceso que escribe algo") es **falsa**.
- **Caminos SMR/S2CR cubiertos** (verificado con `grep` de todas las escrituras a `GR0_SMR`/`GR0_S2CR`):
  `write_smr` (`:1724`, guard `:1716`), `write_s2cr` (`:1755`, guard `:1737`) — y como el guard va
  antes de `impl->write_s2cr`, cubre también `qcom_smmu_write_s2cr` (`arm-smmu-qcom.c:685`) —,
  `write_sme` (`:1765`), `free_sme`→`master_free_smes` (`:1916`/`:2156`), `install_s2crs`
  (`:2178`), reset fase2 (`:2757-2758` llama a `write_sme`, queda cubierto si alguien la enciende).
  `arm_smmu_test_smr_masks` (escrituras directas `:1846/:1854`) se salta con handoff activo
  (`:1816`). `rmr_install_bypass_smr` no escribe SMR/S2CR (solo sCR0 y RAM).
- **Lo que NO cubre**: sCR0 (`:3267` siempre, `:2822` en F7), TLBIALLH/NSNH (`:2779-2780`), el barrido
  `CB_ACTLR`×71 de F6 (`arm-smmu-impl.c:118-148`) y **todos los CB** (`:1324/:1361/:1399`). Es decir:
  el invariante "no se toca un registro vivo del BL" se cumple para SMR/S2CR y se incumple para sCR0 y CBs.
- **¿Y un SMMU con VALID=1 en un idx cuyo SMR la RAM no puede satisfacer?** Ese es el caso normal:
  con `uke_smr_max=0` la RAM solo conoce el idx 0. El barrido K8 lo cubre porque lee el HW y pina por
  índice (`:731-736`), así que la escritura de ese índice se bloquea. El hueco es el inverso: si un
  índice está **vivo sin SMR-VALID** (p. ej. el BL lo tiene por S2CR/stream-indexing), el pineo no lo ve.
- **¿Puede `arm_smmu_write_context_bank` pisar un CB vivo?** Sí: no tiene guarda, y el único
  obstáculo es la elección de índice. El CB del pineado es desconocido (no se puede leer, #P13), pero
  eso **no** protege al CB 69/68 que el driver elige para el wifi/DPU: si el BL usa ese índice, se
  reprograma en caliente un CB en uso (peor que morir: puede corromper datos en silencio).

### Q2 — HANDOFF-SMRS: parseo, 0x1c00 vs 0x1c01, DMA de los pineados

- **El parseo es de pares (id, mask), no un rango de SIDs** (`arm-smmu.c:655-694`:
  `of_property_count_elems_of_size(..., sizeof(u32)*2)` + lectura de los índices `2i`/`2i+1`).
  Coincide con el vendor (`ref/xiaomi-arm-smmu.c:3025-3044`) y con el commit CodeLinaro 8fa3cef.
  `<0x1c00 0x02>` = **un** par: id 0x1c00 con máscara 0x02 (bit 1 don't-care ⇒ casa 0x1c00 y 0x1c02).
- **El mdss de nuestro DT usa 0x1c00/0x02** (`qcom,smmu_sde_unsec_cb`, base-dtb:13591) y **también
  existe 0x1c01/0x00** (`smmu_sde_sec_cb`, :13599), que **NO** casa el test de subconjunto
  (`(0x2 & 0)==0 == mask` ✔ pero `(0x1c00^0x1c01) & ~0x02 = 1 ≠ 0` ⇒ no es handoff). Correcto: el
  banco seguro se queda fuera del pineo, que es lo deseable.
- **Qué le pasa al DMA de un maestro pineado**: su SMR/S2CR no se escriben ⇒ el HW conserva la
  traducción del BL, pero el kernel cree que el maestro está en el dominio que le dio
  `def_domain_type` (IDENTITY para todos salvo el wifi, `arm-smmu-qcom.c:722-726`). Para un maestro
  IDENTITY, iommu-dma usa dma-direct (direcciones físicas) y el resultado depende de lo que el BL
  dejara: si es BYPASS, las direcciones físicas pasan (funciona); si es TRANS con tablas del BL,
  se traducen por tablas ajenas (fallo o corrupción silenciosa). **No hay forma de saberlo sin leer
  el S2CR, y en el caso del display el kernel además adjunta su propio dominio traducido
  (`msm_iommu.c:752`), así que sus IOVAs no pueden funcionar con el SID pinado (H3).**
- **¿Aceptable para display y UFS?** Para el display: no (H3), aunque el *bind* sí ocurrirá y por eso
  `card0` puede aparecer — cuidado con leer eso como éxito. Para el UFS: el SMR(0) preservado es la
  opción menos mala, **pero** K8 sigue reescribiendo sCR0 (H1/H8) y nada garantiza que las tablas del
  CB del BL sigan siendo válidas una vez el kernel reusa esa memoria. El gate real sigue siendo
  `EXT4-fs (sda32): mounted` a ~15,6 s.

### Q3 — CB DESDE ARRIBA: 70 vs 69, CB69 vivo, "ningún CB escrito"

- Se reserva desde 70 pero el quirk ya hizo `set_bit(70)` (`arm-smmu-qcom.c:546`) ⇒ `test_and_set_bit`
  falla y el primero cae en **69** (`arm-smmu.c:777-784`). El razonamiento está en el código.
- **Si el BL usa CB69 (o CB68, o CB70)**: no hay nada que lo detecte ni lo proteja; el wifi es el
  único `def_domain_type==0` (`arm-smmu-qcom.c:722-726`) y el DPU adjunta su propio dominio ⇒ **al
  menos un CB nuevo se programa siempre** vía `arm_smmu_write_context_bank` (`:1596`). Con SMR/S2CR
  el diseño es "medir y no tocar"; con CB es "adivinar y rezar". Es la asimetría principal del parche.
- **¿Hay forma de no escribir ningún CB si el primer maestro es pineado?** El primer attach
  (`1de0000.qcedev`, identidad) no escribe CB (solo S2CR de SME) — eso ya pasa. Pero el wifi y el DPU
  lo fuerzan después. La única forma limpia sería que el domino traducido del maestro pineado
  reutilizara el CB del BL (lo que hace el lineage) o que no hubiera dominios traducidos — ninguna
  de las dos está en K8.

### Q4 — VENTANA: qué escribe el probe armado que el pineo no protege

Con `mask=0xc` se ejecutan: **F4** `TLBIALLH`/`TLBIALLNSNH` = `0xffffffff` (`:2779-2780`) —
invalidación global de TLB, no destructiva por arquitectura pero global; **F5** RMW de sCR0
(`:2787`) — solo RAM; **F6** `arm_mmu500_reset`: RMW de `sACR` + **`CB_ACTLR` de los 71 CBs**
(`arm-smmu-impl.c:118-148`) — escribe en CBs vivos; **F7** `tlb_sync_global` + **write de sCR0**
(`:2821-2822`) con `CLIENTPD=0` y `USFCFG` según `disable_bypass=0` — **habilita la SMMU**. Y antes,
incondicional, `rmr_install_bypass_smr` había escrito `sCR0 |= CLIENTPD` (`:3265-3267`). Ninguna de
estas escrituras pasa por el pineo, y **no existe ninguna medición de F4-F7 a 0,44 s**: las
supervivencias (#P15, k4c 51,6 s, K6 disparo 2) son de ventanas tardías, con otro estado del BL y
otro tráfico. Que "sobrevivieran tarde" **no protege su ejecución temprana**: al contrario, a 0,44 s
puede haber DMA del propio BL (splash/UFS/dwc3 del fastboot recién soltado) y el paso
`CLIENTPD=1 → 0` es exactamente el momento en que el SMMU pasa de estar apagado a traducir con el
estado heredado. Este es el hueco que el INFORME convierte en conclusión errónea (H1/H5).

### Q5 — ANTI-REGRESIÓN: verificada

- **Desarmado (`uke_smmu_probe=0` o sin token)**: el probe devuelve `-EPROBE_DEFER` en el bloque
  temprano (`:3332-3343`) y, en las siguientes entradas, en `:3358-3367`, **antes** de
  `devm_kzalloc`, de `cfg_probe` y de `uke_handoff_preparar` (`:3485`). Ninguna línea de K8 corre.
- **`uke_handoff=0`**: `uke_handoff_activo()` (`:615-619`) es false ⇒ `uke_pinado` (`:622-628`)
  false, `uke_alloc_cb_arriba` no se usa (`:1420`), el bloque del attach no entra (`:1991`), el
  barrido/DT no corren (`:752`) y el único cambio de comportamiento es el texto de
  `test_smr_masks` (`:1816-1818`, ahora imprime `uke_handoff=%d`). Equivalencia K7 correcta.
- **Caminos nuevos incondicionales**: solo `uke_handoff_preparar(smmu)` para *todos* los SMMU
  (incluido kgsl 0x3da0000), que sale en la primera línea por `uke_handoff_activo`; y las llamadas a
  `uke_pinado()` dentro de `write_smr/write_s2cr/write_sme`, que para kgsl hacen una lectura de
  propiedad DT (`uke_smmu_es_apps`, `:141-148`) por escritura. Coste despreciable, sin allocs ni
  MMIO nuevos. `arm-smmu-qcom.c` no se toca (byte a byte).
- **Modo 2**: no lee ningún SMR nuevo (cierto, `:709-722`), pero ver H5.

### Q6 — ESCALERA: qué desenlaces no tienen miga previa

Desenlaces y su miga:

| desenlace | ¿miga? |
|---|---|
| muere en el attach con las escrituras de K5 → | sí: las migas de `attach: ESCRIBIR SME idx=…` + `pr_flush` (`:2098-2130`) solo sirven si el sistema sobrevive a la escritura — **la delatora es post-mortem, no hay** |
| muere tras fase7 (la muerte residual de #P15) | última miga `reset fase7 …` (`:2820`); **sin desglose F5/F6/F7** (bit3 agrupa los tres, `:222-226`) ⇒ índice irrecuperable como en R1 §7.2 |
| muere dentro del barrido K8 | solo `barrido SMR %d/%u` cada 16 (`:728-730`) ⇒ resolución 16, y **nada si el sistema queda wedgeado** |
| muere en `CB_ACTLR`×71 (F6) | **ninguna** miga por CB (`arm-smmu-impl.c:118-148`) — hueco heredado, R1 §7.2 |
| muere al programar el CB nuevo (wifi/DPU) | miga sí: `write_context_bank idx=%d` (`:1309-1311`), pero el índice que mata es el *nuevo*, no el del BL |
| **muerte muda a 0,44 s sin panic** | **NINGUNA** (H4): ttyGS0 no existe, `X9PREV` invalidada en todos los logs, el FB dumper necesita panic y el timer de 2 s no llega. Ni foto ni dmesg |
| UFS/mount no llega (13,8-15,6 s) | las migas están en el ring y el sistema vive ⇒ se lee `dmesg`, pero **no hay ninguna miga que diga si el sCR0 reescrito rompió el mapeo del BL** |

**Migas que faltan (para K9)**: (a) pintar el checkpoint en el framebuffer del ABL de forma
**síncrona** antes de cada escritura dudosa del probe (no depender del timer de 2 s ni del panic);
(b) una línea por CB en el bucle `CB_ACTLR` del CPRE; (c) separar `UKE_RESET_F567` en F5/F6/F7;
(d) una miga que imprima si el índice elegido para el CB nuevo colisiona con algo que el DT declara.

### Q7 — Si K8 muere mudo a 0,44 s: ¿tiene sentido h2? Ranking de causas

**h2 no es un buen siguiente paso como "discriminador del barrido"** (H5): con h2 el barrido no
existe, el asesino medido de K4c (write del SME idx=1) sigue armado y por tanto h2 muere mudo con
altísima probabilidad; su resultado no exonerará ni condenará la lectura del banco. h2 solo sirve
como "¿pasa algo si no leo?" cuando el resto del probe fuera inofensivo, y no lo es.

**Ranking de causas de una muerte muda de K8 a 0,44 s** (de más a menos probable):

1. **F4/F5/F6/F7 tempranos** (sCR0 `CLIENTPD→0` + `CB_ACTLR`×71 + `TLBIALL*`) sobre un estado del BL
   que sólo se midió con las fases tardías — nunca se ejecutaron a 0,44 s. Es el candidato que K8 no
   cambia y que su informe no considera.
2. **La lectura del banco SMR(1..109)**: es la apuesta declarada del parche (la única lectura no
   medida). Legítima como sospecha, pero no demostrable desde una muerte muda (H4).
3. **La escritura del CB nuevo (69) o de un SMR que el BL tiene vivo sin VALID**: CB69 no está
   verificado; el pineo solo cubre SMR VALID=1.
4. **La tormenta de attach otra vez** (mismo asesino que K4c, con el índice cambiado): el pineo
   debería cubrirlo si el barrido leyó bien; si el asesino es el S2CR/`SMR` de un índice *no vivo*
   pero protegido por TZ, el pineo no lo ve.

## 3. VEREDICTO sobre la imagen actual (tal cual, `5e34596a…`)

**FLASH: SÍ, con dos condiciones de lectura.** El artefacto está verificado (integridad, payload,
cmdline, params), la anti-regresión del arranque desarmado es real y K8 escribe *estrictamente menos*
SMR/S2CR que K7 (el riesgo físico no es mayor que el de los tres flashes de K7, todos recuperables).
Pero:

1. **Una muerte muda NO es evidencia de que mate el barrido de SMR.** Con H1/H2 en pie, F4-F7/CB69
   son candidatos igual de válidos y jamás medidos a 0,44 s. La fila "muda ⇒ el barrido de lecturas
   mata" del INFORME §6 es una conclusión no soportada.
2. **Si el objetivo del flash es la foto/`card0`, esta imagen no la puede dar** (H3): el SID del
   display pinado por DT hace que el DPU nunca use el CB del kernel. Éxito de K8 = sobrevivir +
   migas + `Adding to iommu group` + UFS/EXT4; el display es K9.

No hay ningún defecto de integridad ni de anti-regresión que justifique un NO-FLASH. Si el dueño
quiere gastar el flash en el display, entonces sí sería NO-FLASH: ese flash rinde más en un K9 con
la corrección 1.

## 4. Las 3 correcciones prioritarias para K9 (parche mínimo)

**C1 — Que el SID del display pueda ser del kernel (misión).**
En `arm_smmu_master_install_s2crs()` (`arm-smmu.c:2178`), en vez de `continue` para un índice
pinado, escribir el **S2CR** cuando el dominio destino sea traducido (`type == S2CR_TYPE_TRANS`),
sin tocar nunca el SMR (el SMR sigue pinado). Es exactamente lo que hace el vendor
(`ref/xiaomi-arm-smmu.c:1901-1909`: escribe el S2CR cuando `type`/`cbndx` difieren; solo se salta el
SMR). Añadir un param `uke_handoff_own_trans` (default 1) para A/B. ~10 líneas. Riesgo asumido:
escribir el S2CR de un índice vivo nunca se ha medido aislado (el único S2CR escrito+releído con
éxito fue el 109 del quirk); por eso el param.

**C2 — No reescribir sCR0 con handoff + separar F5/F6/F7 (seguridad + diagnóstico).**
En `uke_reset_mask_efectiva()` (`:277-289`), si `uke_handoff` está activo y nadie tocó el param,
devolver solo `UKE_RESET_F4` (dejar `CLIENTPD` como esté y no correr `impl->reset`); y partir
`UKE_RESET_F567` (`:222-226`, uso `:2785`) en F5/F6/F7 para poder aislar la escritura final de sCR0
con un repack (cierra el hueco de R1 §7.2 y el ítem "muere tras fase7"). Además, empaquetar ya la
imagen `mask=4` por repack (sin recompilar) como rung-2 real, en sustitución de h2 como
"discriminador". ~15 líneas.

**C3 — Instrumento que sobreviva al wedge (una muerte muda debe hablar).**
Exportar desde `uke-panic-fb.c` un `uke_eyes_paint_now(const char *line)` que pinte **una línea**
(en la zona de cabecera del FB del ABL, sin repintar los 26,8 MB) y llamarlo de forma **síncrona**
justo antes de cada acceso dudoso del probe: cada lectura del barrido (al menos cada 8), cada fase
del reset, cada reserva de CB, cada `write_sme`. Es el único oráculo que sobrevive a un colgado duro
(el panel sigue escaneando 0xE3940000; el timer de 2 s y el kmsg_dumper no). Opcional barato si hay
rebuild: `uke_handoff=3` = barrido + pineo + DT + CB arriba pero **storm sin escrituras HW** (dry-run)
para aislar por fin "barrido/reset" de "escrituras del attach" en un solo flash. ~20-25 líneas.

## 5. Anexo — lo que NO he podido verificar (límites de esta crítica)

- No hay tablet: no se ha ejecutado ningún acceso al HW; todo es estático + lo ya medido en los logs.
- La interpretación de "#P14: el UFS traducía por CB22" es del informe; la firma (muerte al escribir
  SCTLR=0 de CB22) admite también un maestro distinto con CB22 vivo. De ahí que H8 quede como RIESGO
  y no como MATA.
- `X9PREV` se ha comprobado en los logs existentes (`zona no valida` en todos); si el canal se
  arreglara para K9, el balance de H4 cambiaría.
