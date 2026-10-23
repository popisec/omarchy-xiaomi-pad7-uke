# T2 — Estrategia pantalla: catálogo DPU, árbol comunitario, arming, CM3 y PLAN K14

Fecha: 30-sep-2026. Autor: agente revisor T2. **Sin tablet** (cero fastboot/adb/ssh/ttyACM0).
Árbol auditado: `/var/tmp/uke-k13-tree` (K13 real). Referencia comunitaria: `~/gpu-work/palawan-build`
(clon PRISTINO de `codeberg.org/palawan-mainline/linux`, rama `palawan/v7.2-rc2`, head `0d9f7fdf7`
del 9-jul-2026) y `~/gpu-work/palawan-linux` (clon del hermano, head `d1c7ef2e0` del 28-sep).
Lecturas previas: PRE-REGISTRO-PANTALLA.md (#P1–#P36), R2, G1, ESTADO-VIVO.

---

## 0. Resumen ejecutivo (4 líneas)

1. **El catálogo SÍ es de Palawan** (no prestado): `catalog/dpu_10_1_palawan.h` (DPU 10.1 =
   exactamente la revisión leída 0xa0010000) y se elige por COMPATIBLE, no por revisión. Cubre el
   O82 dual-DSI-DSC (INTF_1/INTF_2 DSI, 4 LM, 4 PP, 2 DCE/3 DSC). Un watch-item de pairing DSC.
2. **La causa estructural del -22 de K11/K12 es NUESTRA desviación del DT comunitario**: la
   comunidad pone `iommus` SOLO en el mdss padre; el s260 lo duplicó en el display-controller →
   grupo de 2 → `-EINVAL` de `iommu_attach_device` (iommu.c:2206). **La celda K12-kernel + s258
   (grupo de 1) NUNCA se probó** — y ambos artefactos ya existen con sha verificado.
3. **El arming YA cumplió su papel** (K10 lo probó manual, K11 horneado a 4 s, SMMU bindeado con
   sistema vivo). El -19 de K13/#P36 NO puede venir del diff K13 (solo pr_info + fallback que no
   llega a ejecutarse): en ese boot el SMMU no llegó a bindear (0 salida de probe en consola) —
   boot envenenado, no regresión.
4. **PLAN K14 = K12 + s258, cero compilación.** Alinearse con palawan-mainline NO es mejor que
   parchear: su árbol NO resuelve el handoff del apps-smmu (su arm-smmu es stock, sin nada de
   handoff); su valor es la referencia DT/catálogo, que ya incorporamos y de la que nos
   desviamos solo en el s260.

---

## 1. ¿El catálogo DPU matchea la revisión 0xa0010000?

**Sí, y por las dos vías.** En este árbol el catálogo se elige por **compatible**, no por el valor
de la revisión: `dpu_kms.c:1166-1172` lee `core_rev` (solo lo imprime:
`pr_info("dpu hardware revision:0x%x\n")`) y saca el catálogo de
`of_device_get_match_data()` → `dpu_hw_catalog.c:1514`
`{ .compatible = "qcom,palawan-dpu", .data = &dpu_palawan_cfg }` — que es el compatible de
NUESTRO DT (`qcom,palawan-dpu`, R2 §1). La revisión decodificada 0xa0010000 = major 0xA=10,
minor 0x1, step 0 = **DPU 10.1.0**, y el catálogo declara
`palawan_mdss_ver = { .core_major_ver = 10, .core_minor_ver = 1 }`
(`dpu_10_1_palawan.h`, final) — **coincidencia exacta de versión**.

- **No es prestado**: fichero dedicado con copyright 2026 de **Alexandr Zubtsov (USUARIO@example.invalid)**,
  el mismo autor del árbol comunitario; incluido en `dpu_hw_catalog.c:784`.
- **Byte-idéntico al de la comunidad**: `diff` de `catalog/dpu_10_1_palawan.h` entre
  `~/gpu-work/palawan-build` y `/var/tmp/uke-k13-tree` = sin diferencias.

### Inventario del catálogo (`catalog/dpu_10_1_palawan.h`) y adecuación O82 dual-DSI-DSC

| Bloque | Palawan | Suficiencia para el O82 (3200×2136@120, bonded DSC) |
|---|---|---|
| CTL | 4 (0x15000..0x18000) | OK |
| SSPP | 13 (2 VIG + 4 DMA + DMA4-cursor) | OK |
| LM (mixers) | **4**, pares (0,1)/(2,3), `has_src_split`, `has_3d_merge`, `max_linewidth 8192` | OK: 3200 px → 2 LM con src-split (1600+1600) |
| DSPP | 3 | OK |
| PINGPONG | 4 (PP_0..3, merge_3d_0/1) + 4 CWB | OK |
| DSC | **3 bloques / 2 DCE** (`dce_0` dual-slice @0x80000 = DSC_0/DSC_1; `dce_1` @0x81000 = DSC_2) | Suficiente (topología num_dsc=2), ver watch-item |
| INTF | 4: **INTF_1 = DSI ctrl 0 (0x35000), INTF_2 = DSI ctrl 1 (0x36000)**, INTF_0/3 DP | **EXACTO** para dual-DSI |
| WB / CWB | 1 WB_2, 4 CWB | OK |
| VBIF | **prestado**: `&sm8650_vbif` | watch-item (ver abajo) |
| PERF | LUTs `sc7180_*` con `/* FIXME: lut tables */` | no bloquea primera luz (rendimiento/QoS) |

**INTF numbering contra el DT fusionado**: coherente. Fragment@1105 del payload s260:
`port@0` = `dpu_intf1_out` → `dsi@ae94000` (master) y `port@1` = `dpu_intf2_out` → `dsi@ae96000`
(símbolos en `/var/tmp/t2-s260.dts:3730-3731`), y el catálogo declara INTF_1↔MSM_DSI_CONTROLLER_0,
INTF_2↔MSM_DSI_CONTROLLER_1. No hay que renumerar nada.

**Topología que producirá el driver** (verificado en código): 2 phys encoders → `num_intf=2`;
con DSC → `num_dsc=2` (`dpu_encoder.c:687-692`); `num_dsc == num_intf` ⇒ `_dpu_rm_dsc_alloc`
(NO pair-mode, `dpu_rm.c:616-622`); con la regla de paridad `_dpu_rm_pingpong_dsc_check`
(`dpu_rm.c:507-513`): DSC_0(even)→PP_0, DSC_1(odd)→PP_1.

**Watch-item DSC (no bloqueante, con síntoma)**: DSC_0 y DSC_1 son los DOS slice-encoders del
MISMO DCE (base 0x80000, sblk distintos). Mainline asignará ambos a interfaces distintas (una por
INTF). Es la topología que el propio catálogo del autor de la HW permite, pero es la única pieza
del pipeline que no podemos verificar sin luz. **Si la primera imagen sale con mitades
izq/der corruptas o errores `dsc` en el primer modeset**, la primera sospecha es el pairing
(candidato de remonte: preferir DSC_0+dsc_2, un encoder por DCE); NO tocar nada de esto antes de
ver el fallo. Diferencias restantes vs sm8650 (de donde sale la familia 10.x): sm8650 tiene 6 DSC
(3 DCE) y más LM; palawan recorta a 2 DCE — coherente con un SoC de una sola pantalla interna.

---

## 2. El árbol comunitario codeberg.org/palawan-mainline/linux

Canal: clon local PRISTINO `~/gpu-work/palawan-build` (rama `palawan/v7.2-rc2`, head `0d9f7fdf7`,
9-jul-2026) + WebFetch a Codeberg. **Codeberg NO registra ninguna actividad 23–30 sep-2026**
(página de actividad, semana 2026-09-23→30: "no commit activity"): el clon local está al día.

### 2.1 Qué tiene SU display que el nuestro no (y viceversa)

| Pieza | Comunidad (`palawan-build`) | Nuestro K13 | Veredicto |
|---|---|---|---|
| `dpu_10_1_palawan.h` | idéntico | idéntico | nada que portar |
| `dpu_kms.c` | idéntico | idéntico (el bug del doble-priv-obj-fini de R2 §5.4 está TAMBIÉN upstream — no hay fix comunitario del UAF) | nada que portar |
| `msm_iommu.c` / `msm_kms.c` | sin NUESTRO fallback attach_group ni migas | + UKE-K13 (solo instrumentación) | el nuestro es un superconjunto |
| `a6xx_gmu.c` / `adreno_device.c` | sin pokes | + pokes F/S/H/P | superconjunto |
| `arm-smmu-qcom.c` / `arm-smmu.c` | **stock mainline, CERO código de handoff** | + todo el sistema UKE (barrido, pineo, arming, guardas) | **la comunidad NO ha resuelto el handoff del apps-smmu** |
| DT: `iommus` del display | **SOLO en el mdss padre** (`palawan.dtsi:3341+`, `iommus = <&apps_smmu 0x1c00 0x2>`); display-controller SIN iommus | mdss padre (fragment@1105) **Y** display-controller (s260 fragment@1709) = **duplicado** | **esta es LA desviación** |
| DT: apps-smmu | `qcom,palawan-smmu-500`, `qcom,smmu-500`, `arm,mmu-500`, **reg 1 MiB** | `qcom,qsmmu-v500` (único), reg 2 MiB | su compatible matchea arm-smmu STOCK ⇒ probea nativo a ~0,3 s con reset completo — exactamente la secuencia que en esta tablet mató (s251 mudo; K2 murió leyendo SMRs). En la uke NO está demostrado que ese camino sobreviva |
| DT de referencia display | `palawan-qrd.dts` / `lamma-qrd.dts:655-697`: `&mdss` okay + panel SINGLE-DSI + DP | el nuestro: dual-DSI + panel O82 integrado | **nadie ha demostrado dual-DSI**; nuestro panel va POR DELANTE de la referencia |

### 2.2 URLs y diferencias concretas

- `https://codeberg.org/palawan-mainline/linux` (rama `palawan/v7.2-rc2`, sin actividad reciente;
  clon local verificado). Ficheros citados: `arch/arm64/boot/dts/qcom/{palawan,lamma}.dtsi`,
  `{palawan,lamma}-qrd.dts`, `drivers/gpu/drm/msm/disp/dpu1/catalog/dpu_10_1_palawan.h`,
  `drivers/iommu/arm/arm-smmu/arm-smmu-qcom.c`.
- `~/gpu-work/palawan-linux` = mismo upstream + commits del hermano (`20f0df992` panel O82 dual-DSI
  DSC + touch NT36xxx; `59e9e0f6e` plan display fase 4; `d1c7ef2e0` SoC cliffs/UFS/icc...).
  `xiaomi-uke.dts:518-519` tiene el enchufado del display como **TODO comentario** — es decir,
  ni el hermano en el clon comunitario llegó a enchufar el display por esa vía: toda la cadena
  viva (panel/DSI/PHY) vive en NUESTRA cadena dtbo (s2xx), que es más avanzada.

### 2.3 ¿Alinearse con él es mejor que seguir parcheando?

**No como reemplazo; sí como regla de estilo — y ya se puede aplicar gratis.** Razones:
1. Su árbol **no aporta nada para el apps-smmu** (el único eslabón que nos falta): arm-smmu stock
   sin handoff; su apps-smmu probea a 0,3 s por `arm,mmu-500` con reset completo, que en esta
   tablet midió letal (mapa de minas ESTADO-VIVO; s251/K2/K7). Nuestro sistema de arming+pineo es
   la única vía demostrada viva (K10/K11).
2. Su DT de display **valida el nuestro con UNA diferencia**: el iommus duplicado del s260. Esa
   alineación se consigue con un dtbo que YA EXISTE (s258), sin rebase, sin perder ni un parche.
3. Rebasear = perder 13 kernels de instrumentación que es lo único que permite diagnosticar sin
   ojos, para ganar un catálogo y un DTS que ya tenemos.

---

## 3. ¿El arming temprano ya cumplió su papel? (sí — K14 no lo toca)

| Hito | Evidencia |
|---|---|
| Mecánica arm+bind funciona con sistema vivo | K10 (#P30): arm+bind por SSH a 156/435 s → SMMU probe completo, 16 grupos, UFS DMAeando por su mapeo BL, handoff verificado (idx 6 PINADO, CB 69 desde arriba) |
| Arming horneado funciona en la ventana | K11 (#P32): `UKE-K11: armando probe a 3s` → REINTENTO 3,96 s → SMMU BINDEADO → dpu auto-re-probea a 4,1 s |
| El fallo restante es del lado display | K11 -22 (pineo no-vivo del handoff), K12 -22 (grupo de 2 por el s260) — ambos DT/kernel-display, no arming |

**El -19 de K13/#P36 es un boot envenenado, no una regresión del código.** El diff K13
(`patches/k13-grupo-iommu.diff`) es: pr_info en `init_domain_context` (arm-smmu.c), migas +
fallback `iommu_attach_group` en `msm_iommu.c`, y migas en `msm_kms.c` — **nada de eso puede
poner `dev->iommu_group` a NULL**. `device_iommu_mapped()` = `dev->iommu_group != NULL`
(`include/linux/device.h:916-918`): el -19 de las 13,973/14,019 s significa que en ESE boot el
apps-smmu nunca llegó a bindear. La consola de ese boot lo corrobora
(`~/proyectos/out/uke-k13-console.log`): se ve el eco del arming ("UKE-K11 armando probe por
sysfs", interleave garbled) pero **cero líneas del probe** (no hay "probing hardware
configuration", ni "preserved", ni "Adding to iommu group"), y el mismo fichero captura un
**bucle de banners de K13 (#17) muriendo enseguida** + un boot del kernel bueno (#82) en medio.
Además el dpu probó a 13,97 s (patrón deferred-timeout de 10 s), NO a 4,1 s (patrón bind-triggered
de K11/K12). Conclusión: en ese arranque el arming no produjo un bind — estado envenenado por el
latch/bucle previo (o el eco no llegó a sysfs), **imposible de atribuir al fallback K13**, que con
grupo de 1 ni siquiera llega a ejecutarse.

**Veredicto**: el arming se queda EXACTAMENTE como está (K12 = cmdline K11 356 B sin
`uke_smmu_probe` + ukeinit horneado). K14 no toca arming, no toca arm-smmu.

---

## 4. CM3/GPU: estado de la escalera en K13 y el wedge del arranque K13

### 4.1 Qué lleva K13 por defecto (grep en `/var/tmp/uke-k13-tree`)

- **Escalera MEDIA, activa SIEMPRE, sin parámetro** (`a6xx_gmu.c`): `F1-fwloop/F2-itcm/F2-dtcm/
  F3-loopOK/F4-verOK` (:906-936, carga de firmware), `H6-rsc(H7-fw)`, `P1-initres/P2-qtbl/
  P3-pwr(OK)` (:986-1080), `H8-cm3(FAIL)` y `H9-hfiq(FAIL)` (:1084-1104), y el bloque CM3
  `S1-rst1/S2-gen9/S3-rst0/S4-poll` (:316-335) con el canario de imagen
  `UKE-CM3DBG: dtcm-magic=...` (:308-312, imprime si el fw llegó a la RAM que fetcha el CM3).
  En `adreno_device.c:241-251`: `G1-bind/G2-initFAIL/G2-initOK/G3-icc`.
- **La escalera FINA NO está en K13**: no hay `L00..L16` ni canario `L14` (grep = 0). El canario
  fino (`build/cm3-ladder/uke-cm3-ladder.diff`, un readl único de `FW_INIT_RESULT` antes del
  sondeo) requiere aplicar el diff y recompilar — quedó probado en frío sobre el árbol K12
  (INFORME-CM3 §1: aplica -p1 y compila OK).
- **No existe palanca para NO arrancar el CM3 al registrarse card0**: `load_gpu()` no tiene
  guarda (`msm_drv.c:198-207`), `msm_open` llama `load_gpu` sin condición (:265-272) y el cliente
  fbdev abre la card en el mismo initcall del post-init (cadena completa verificada en R2 §4.4 y
  G1 §4). `separate_gpu_kms=1` por cmdline está refutado operativamente (ledger #409) y
  `drm.active=` vacío dejaría sin fb0/fbcon.

### 4.2 ¿El wedge del boot1 K13 cuadra con el load_gpu del fbdev?

**Cuadra como hipótesis principal, con dos observaciones que lo matizan:**

- A FAVOR: kms init en K13 boot1 pasó (el -22 no mata en bucle y el fix del grupo estaba en el
  kernel) ⇒ card0 ⇒ fbdev ⇒ `load_gpu` ⇒ CM3 en el mismo initcall (~4,2 s, o +2-3 min si el
  helper de firmware demora). El wedge conocido del hermano (última marca `S3-rst0`, el readl de
  `FW_INIT_RESULT` no vuelve, sin watchdog)produce exactamente "consola/ssh mueren sin pánico".
  La escalera MEDIA de K13 habría dejado las migas exactas en consola... que no se capturó.
- EN CONTRA (matiz 1): #P35 demostró que había **BCB "bootloader" sucio** causando bucle de
  reinicios, y que con el kernel bueno la tablet arrancó estable — es decir, los "boots siguientes
  mueren en segundos" tienen un explicación ALTERNATIVA probada (BCB), y **la tesis "el wedge del
  CM3 persiste entre reboots suaves" queda sin evidencia sólida** (el kernel bueno arrancó bien
  después del supuesto wedge).
- MATIZ 2: el -19 de #P36 (SMMU sin bindear) ocurrió ANTES de card0 — ese boot ni llegó al CM3.
  El "wedge contaminando" del encargo es plausible como estado del platform (por eso K14 exige
  power-cycle físico), pero no está medido.

**Para K14 esto significa**: al lograr card0, el CM3 se disparará SOLO. Hay que asumirlo con la
captura armada y el protocolo de G1 §5 (verificar card0 por sysfs SIN abrir nada; la escalera
media de K13/K12 ya distingue fw-no-llegó (`dtcm-magic`) de CM3-no-arranca (`S3-rst0` sin
`S4-poll`). NO pre-aplicar la escalera fina (otra variable); se aplica en K15 solo si el wedge se
confirma.

---

## 5. PLAN K14 rankeado (máx 3)

### Matriz de pruebas que deja la serie (la celda vacía manda)

| | dtbo s258 (iommus SOLO mdss) | dtbo s260 (iommus duplicados) |
|---|---|---|
| **K11 kernel** (pineo no-vivo bug) | PROBADO → -22 (#P32) | — |
| **K12 kernel** (pineo solo-vivo) | **NUNCA PROBADO** ← | PROBADO → -22 grupo de 2 (#P33/#P34) |
| **K13 kernel** (fallback attach_group) | — | PROBADO → -19 boot envenenado (#P36) |

### K14-A (RECOMENDADA): K12 kernel + dtbo s258 — alinear el DT con la comunidad

- **Parche mínimo: CERO ficheros nuevos, CERO compilación.** Flash de artefactos existentes con
  sha verificado hoy en disco:
  - `boot_b` ← `build/bootimg/boot-ukek12.img` = `7c6bfe0d91a58ae11fe78dcb4c8294f3963a477e67228136bc2818cae0f4c240`
  - `dtbo_b` ← `build/bootimg/s258-panel-gpio2.img` = `f4663ff86b30e23ca48982358030c3d7afbc274246f27d2964398d49d522b371`
  (equivale a: mismo kernel que el -22 de #P33, y DESHACER el fragment@1709 del s260; el único
  cambio experimental vs el último boot bien entendido K12/s260 es el dtbo = **una sola variable**).
- **Mecánica esperada**: arming horneado ~4 s → SMMU bindea → el mdss entra en grupo de 1 →
  dpu re-probea 4,1 s → `msm_kms_init_vm` elige `mdss_dev` (mdp_dev sin iommus) →
  `msm_iommu_new(mdss_dev)` → `iommu_attach_device` grupo de 1 → OK → K12: `handoff no-vivo
  sid=0x1c00 → attach normal` (el stream 0x1c00 NO está vivo según K10/K11 ⇒ escribir su
  S2CR es la clase "índice libre", medida segura) → KMS vm → `Initialized msm` → **card0** →
  fbdev → CM3 (riesgo conocido, §4).
- **Riesgo**: bajo. Es la configuración del autor del catálogo (DT) con el kernel que ya arregla
  el pineo. Riesgo residual 1: que el -22 de K11 (con este mismo DT) viniera de otra cosa distinta
  del pineo — precisamente por eso K12 (el fix del pineo) con s258 es el experimento correcto.
  Riesgo residual 2: el CM3 al abrir card0 (inherente a CUALQUIER éxito: no hay card0 sin CM3).
- **Tiempo a card0**: 1 ciclo de flash + 1 arranque; card0 a ~4,2 s del kernel si todo va.
- **Cómo saber si falla**: migas en consola (ttyGS0 vive a 3,57 s; arming a ~4 s = ventana K10 con
  consola). Diccionario: (a) -19 otra vez ⇒ el arming volvió a no bindear (ambiental: power-cycle
  físico, verificar misc/BCB, NO culpar al kernel); (b) -22 con "Adding to iommu group" presente ⇒
  leer las migas UKE-POKE/UKE-K12 del attach: si aparece `PINADO` para 0x1c00 el pineo no quedó
  limpio; si el attach completa y aun así -22, la fuente está más abajo (migas UKE-K13 no
  disponibles en K12 — si hace falta esa visibilidad, pasar a K14-B); (c) freeze tras
  `Initialized msm`/`G1-bind` ⇒ CM3: última miga = diagnóstico (§4); (d) éxito: fbcon enciende
  sola (cmdline lleva `console=tty0 fbcon=map:0`), verificar por G1 §5a SIN abrir card0.

### K14-B (alternativa, si se quiere máxima visibilidad en el MISMO flash): K13 kernel + s258

Idéntica a K14-A pero con `boot-ukek13.img` (`d71ea2b5…`): añade las migas
`UKE-K13: init_domain_context/alloc_context_bank` y el fallback `attach_group` (INERT con grupo
de 1). Coste: el kernel K13 arrastra la sospecha (refutada analíticamente, §3) del -19 y NO es
una sola variable vs el último boot (kernel+dtbo cambian). Elegir solo si el dueño prioriza el
diagnóstico fino del fmt/CB sobre la disciplina de una variable. La escalera fina del CM3
(`uke-cm3-ladder.diff`) NO va en ninguno de los dos: se reserva para K15 con el diff aplicado.

### K14-C (NO recomendada para K14; camino de convergencia posterior): rebase a palawan-mainline

Portar el board a `~/gpu-work/palawan-build` (xiaomi-uke.dts con `&mdss` okay estilo QRD,
iommus mdss-only, apps-smmu `qcom,palawan-smmu-500`) y abandonar el fork de pokes. Honestamente:
**es peor HOY** — pierde el arming/handoff (su arm-smmu stock con reset completo a 0,3 s es la
secuencia que midió letal en esta tablet, s251/K2/K7), pierde 13 kernels de instrumentación y no
aporta código display que no tengamos ya (catálogo y msm idénticos). Su valor real es de
referencia (ya aplicado: el dtbo s258 ES la alineación). A revisitar solo cuando la pantalla esté
estable, para converger upstream (y de paso reportar el fix del dtbo).

---

## 6. Tres reglas de proceso para no quemar boots (13 kernels hasta hoy)

1. **Una variable por flash, elegida por la matriz antes del flash.** K13 violó la disciplina: se
   cambió el kernel (fallback) SIN haber probado la celda K12+s258 que la matriz tenía vacía, y el
   -19 envenenó la interpretación. Toda fila #P nueva declara su celda (kernel × dtbo) y por qué
   esa y no la adyacente.
2. **Sin evidencia armada NO hay boot de experimento**: captura de consola verificada VIVA
   (marcador en /dev/kmsg visible en el fichero) + gate batería ≥ 3750 mV por getvar + `misc`/BCB
   verificados limpios + rollback escrito. Se perdieron las migas de K8 (#P25) y TODA la de
   K13 (#P34-bis/#P36) por lector muerto; el BCB sucio convirtió 1 resultado en 3 boots de ruido.
3. **Al primer desenlace inesperado (mudo, bucle de banners, latch a fastboot): PARAR.** Power-cycle
   físico, volver al par bueno (boot_b-lee `ffff8c51…` + dtbo bueno), y solo con el sistema
   estable se rediseña. Encadenar reboots/flashes sobre estado sospechoso costó el latch de K13
   (3 boots) y el falso "pasa lo mismo" de #P36; #P26-bis ya demostró que hasta el kernel bueno
   "muere" fuera de condiciones (batería).

---

## Anexo — evidencia citada (todo leído en esta revisión)

- Catálogo/match: `/var/tmp/uke-k13-tree/drivers/gpu/drm/msm/disp/dpu1/{dpu_hw_catalog.c:784,1514,
  dpu_kms.c:1166-1172, catalog/dpu_10_1_palawan.h}`; pairing: `dpu_rm.c:507-622`,
  `dpu_encoder.c:687-692`.
- DT fusionado: payload s260 descompilado en `/var/tmp/t2-s260.{dtb,dts}` (fragment@1105 con
  `iommus = <0x129 0x1c00 0x02>` en el mdss, :133; fragment@1709 del s260 en el
  display-controller; símbolos intf1/intf2 :3728-3737).
- Comunidad: `~/gpu-work/palawan-build` (head `0d9f7fdf7`, 9-jul-2026; `palawan.dtsi:3341` mdss
  con iommus; apps-smmu `qcom,palawan-smmu-500`+`arm,mmu-500` reg 1 MiB; `arm-smmu-qcom.c` sin
  handoff) y `~/gpu-work/palawan-linux` (head `d1c7ef2e0`, 28-sep; `xiaomi-uke.dts:518-519`).
  Codeberg: 0 commits 23–30-sep-2026.
- Diffs y errores: `build/gates/patches/k12-pinlive.diff`, `k13-grupo-iommu.diff`;
  `iommu.c:2197-2207` (check grupo de 1), `include/linux/device.h:916-918`
  (`device_iommu_mapped`), `msm_iommu.c` (attach/attach_group), `msm_kms.c:182-216`,
  `iommu.c:2080-2107` (`__iommu_paging_domain_alloc_flags`: UNMANAGED, no pasa por
  def_domain_type).
- K13 #P36: `~/proyectos/out/uke-k13-console.log` (banners #17 en bucle + #82 bueno; -19 a
  13,973/14,019 s; eco de arming sin salida de probe).
- CM3: `/var/tmp/uke-k13-tree/drivers/gpu/drm/msm/adreno/{a6xx_gmu.c:308-335,906-935,986-1104,
  adreno_device.c:69-130,241-251}`, `msm_drv.c:198-207,265-272`; escalera fina NO aplicada
  (grep L00-L14 = 0); protocolo en `build/cm3-ladder/INFORME-CM3.md` y G1 §5.
- Artefactos K14-A verificados hoy por sha256sum: `build/bootimg/boot-ukek12.img` =
  `7c6bfe0d…`, `build/bootimg/s258-panel-gpio2.img` = `f4663ff8…`.
