# CRÍTICA-PLAN — ¿seguimos el plan F? Axiomas, atajos y presupuesto (2026-10-10, solo lectura)

> Solo PC. No flashea, no toca la tablet. Tablet viva en L8+s250 (ledger #572).
> Manda el ledger hermano `~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md` #553–#572.
> Lee: `docs/historia/ESTADO-VIVO.md` (10-oct 01:55), `F-plan-por-fases.md`, `REGLAS.md`, `OBJETIVOS.md`,
> `BISECT-L0…L8`, `S250-DTBO-GPU-SERIE.md`, `docs/historia/revision/INV-KGSL-RE-20261008.md`, `docs/historia/revision/INV-GMU-BIN-20261008.md`,
> `docs/historia/revision/VIAS-GPU-20261008.md`, `docs/historia/revision/PLAN-C3-DISENO-20261009.md`, `CRITICA-W6-*`.

## 0. Veredicto en una frase

**El objetivo F1a/F1b sigue vigente y el método L0–L8 lo ha acercado más que nada anterior,
pero la disciplina del plan F está rota en presupuesto y la ruta vendor-RE → L9 solo es mínima
si se poda a un flash de constantes; hay un atajo real para el PANEL (no soltar el CM3),
ninguno para la GPU, y el hermano no midió lo que L8 ya midió.**

## 1. Desviaciones detectadas (F y REGLAS contra ledger)

### D1. Presupuesto de escrituras: desviación grave, normalizada por overrides (la más urgente)
- Regla: `REGLAS.md` §2 — **≤2 escrituras/día**, día agotado por escrito en la fila.
- Realidad: **20 escrituras hoy** (#553–#572: 19 en `boot_a` + s250 en `dtbo_a`), **16 overrides
  consecutivos del dueño**. Cada fila lo anota, así que no es clandestino, pero es
  **desviación normalizada**: el override dejó de ser excepción y pasó a ser el modo.
- F §5-riesgos y `docs/historia/PLAN-SIGUIENTE-v4.md` §1 presuponían cadencia lenta con re-meditación entre
  ciclos; a 20/día no hay ventana de crítica entre flash y flash (W6 ya cazó una cadena así:
  k65–k67 con veredictos luego invalidados).
- Acción: volver a ≤2/día salvo override nominal con motivo; todo lo propuesto abajo cabe en
  **1 flash** (+1 solo si habla).

### D2. k65–k70: 6 veredictos emitidos sobre base sucia, luego invalidados (desviación de método, YA CORREGIDA)
- k65 (D1+D2+D3), k66 (sin D3), k67 (sin D2), k68/k69/k70 (plan C): **6/6 silencios pre-consola**
  leídos como veredictos diferenciales (D3 exonerado, D2 exonerado, D1 nº1…).
- `CRITICA-W6-AXIOMAS` demostró que el diferencial no existía: **k64 nunca se flasheó** (#554),
  **k63+s273 ya era silencioso sin D1/D2/D3** (#548d), dtbo s273 constante y confundido,
  árbol-base sucio (k52-tree acumulado). Los 6 silencios eran idénticos porque morían antes.
- Corrección: la escalera **L0–L5 re-hizo el trabajo en limpio** (L0==k52b2 validado por
  comportamiento #561; L1=K64 inocente #562; L2=D1 inocente #563; L3=C1 inocente #564;
  L4a=D2 inocente #565; L4b=poll inocente #566; L4c=D3 inocente #567; L5=combinación inocente #568).
  Los veredictos viejos están **sustituidos, no parchados**. No reabrir k65–k70 sin evidencia nueva.

### D3. El plan F no contiene la escalera L0–L8 ni el probe s250 (desviación de plan, JUSTIFICADA)
- F describe F1a (render/GLES) y F1b (KMS/panel) con cuellos IOMMU/Mesa/pd-mapper; el asesino real
  resultó ser **el write `SYSRESET=0` que suelta el CM3 del GMU** (#572: ni `write-done` sale),
  con D1/D2/D3/C1/poll exonerados **en vivo con rc=0** (#570). F no preveía este muro ni su
  instrumentación (pokes con `pr_flush`, bisección un-hunk-por-flash, dtbo s250 de serie).
- Veredicto: desviación **legítima** — F es el qué, L0–L8 es el cómo que F no detallaba.
  Pero F §5-tabla de riesgos y §7-checklists están **obsoletos** para F1a/F1b: hablan de Mesa/a732
  (retirado: el kernel reporta `0x43030b00`, `OBJETIVOS.md`-descartados) y no del dominio GMU.
  Marcar F-riesgos-F1a/F1b como sustituidos por esta crítica + `INV-KGSL-RE` + `VIAS-GPU`.

### D4. Orden GPU→panel invertido en la práctica, confirmado en la teoría (desviación APARENTE, RESUELTA)
- F y versiones viejas de `OBJETIVOS.md` trataban F1a/F1b casi en paralelo; el 1-oct se reescribió
  a "juntos" con orden real **GPU→panel** (`card0` solo existe con GPU sana).
- s250+L5 lo confirma: `card0+renderD128` aparecen **sin abrir la GPU** (probe completo G1→G9,
  `[drm] Initialized msm`, #569). El panel-CPU vive sin CM3; el panel-acelerado exige CM3.
  No es desviación: es el plan corregido funcionando.

### D5. Canal de evidencia por debajo del estándar que el propio proyecto exige (desviación de método, ABIERTA)
- `REGLAS.md` exige doble captura (ACM + `ssh dmesg -w`), `pr_flush` tras miga que decide rama,
  y nada de instrumentación ilegible en el sitio previsto.
- K65–K67 violaron el espíritu (silencios "0 bytes con lector armado" sin log archivado,
  `CRITICA-W6-EVIDENCIA` los clasifica como RELATO). L6–L8 lo cumplen (trazas ACM completas con
  último testigo nombrable). Pero el wedge actual **sigue sin pstore/ramoops** (no sobrevive al
  power-cycle), sin WDT que muerda, sin volcador sda30 armado — cada flash ciego cuesta un retry
  y devuelve una sola línea ("muere aquí"). `VIAS-GPU` V9+V5 siguen **diseñados, no aplicados**.
- Acción: no más flashes ciegos sin V9/V5 o equivalente (§5-paso 1).

### D6. Slot/rollback: F supone B intacto y recuperación ejercida; lo primero se cumple, lo segundo no
- B intacto (6:6) se cumple a hoy. Pero la F8-definición ("recuperación ejercida 1 vez") sigue
  pendiente, y #570 demostró que el contador de A **no es monótono ni seguro**: un solo ciclo
  malo (sysrq-b + cuelgues) lo llevó de 6:6 a **1:6**, recuperado a 5:6 solo porque L0 habló.
  "A en 5:6" no es colchón: es **un mal ciclo del fastboot**.

## 2. Axiomas: qué sigue en pie y qué cayó (tras L0–L8 + s250)

Referencia: `docs/historia/revision/CRITICA-W6-AXIOMAS-20261009.md` (a)–(e). Actualización a #572:

| Axioma W6 | Entonces | Ahora | Por qué |
|---|---|---|---|
| (a) silencio pre-USB 4+ min = muere en probe GMU/resume | NO SOSTENIDO como diferencial (k65–k67 morían antes del kernel) | **SUSTITUIDO por (a') SOSTENIDO**: boot OK + muerte **al abrir card0** en punto nombrable | L0/L1/L2/L3/L4a/L4b/L4c/L5 hablan por SSH (n=8 boots); s250 probea de serie (#569); L6 llega a `S2-gen9→K44-A`, L7 a `k44e-ok→K19-dumpOK→k25-ok→pre-rst`, L8 a `pre-rst` sin `write-done` (#570–#572). Los 6 mudos viejos quedan invalidados; los 8 hablas nuevos los reemplazan |
| (b) `pr_err` pasa el tope K41 | SOSTENIDO en fuente, VACUO en runtime | **SOSTENIDO Y VALIDADO en runtime** | L6 (11 pokes) + L7 (7) + L8 (2) salen por ACM con `pr_err+pr_flush` en el linaje k52-`a6xx_gmu_resume`. El tope `MAX=4` sigue en fuente y los testigos lo atraviesan en vivo |
| (c) WDT resetea ~2 min si hay wedge | CADUCADO para este linaje | **SIGUE CAÍDO** | L6–L8 "cuelgan y rebootean" sin WDT armado demostrable; `CONFIG_QCOM_WDT=y` pero `HANDLE_BOOT_ENABLED` lo mata y nadie lo abre (`VIAS-GPU` V5); el revival sigue siendo físico/botones. No usar retry-count como oráculo ni planear "drenaje WDT" |
| (d) `dd boot_a` por SSH = flash verificado | SOSTENIDO como bytes, SOBRE-EXTENDIDO como bootabilidad | **PARCIAL: sube un escalón, sin llegar a "verificado"** | L0 habla ⇒ bytes + bootabilidad de `boot_a` en ese ciclo (mejor que n=1 de #554). Sigue sin cubrir `dtbo_a`, flags de slot, AVB, ni aceptación por el ABL. Exigir `dd` de **ambas** particiones + `getvar all` antes/después |
| (e) `aop_a==aop_b` es sano | NO SOSTENIDO (solo "existe y es dumpable") | **SIGUE CAÍDO** | `3353ea91…` ELF32 RISC-V en ambas slots = igualdad esperada de fábrica, sin golden/stock/version-string. W3-AOP sí sostiene lo útil ("el AOP arbitra rails por nombre, no es el votante GX"), pero "sano" sigue sin prueba. Coste de cierre: `strings`/header + stock, 0 flashes |

Axiomas nuevos (todos con n=1, frágiles — tratar como provisionales, no como suelo):
- **N1 (fuerte): D1, D2, D3, C1, poll-vendor y su combinación son inocentes.** Exoneración en limpio
  L1–L5 + confirmación en vivo D1/D2/D3 `rc=0` en L6 (#570). Es el resultado más sólido del ciclo.
- **N2 (fuerte): el probe GPU de serie funciona** (s250: G1→G9, `Initialized msm`, card0+renderD128,
  #569; #409 muerto). s250 es el dtbo de trabajo; su variante sin-cmdline (`78ea1760…`) queda de recambio.
- **N3 (el hecho): mata el `gmu_write(SYSRESET,0)`** (#572). Ni `write-done` (L8) ni `post-rst` (L7)
  ni S3 salen; las lecturas del CM3 en reset son seguras (K44-B/C/D/E ok). Es el propio write,
  ni siquiera el primer readl. **Este es el muro; todo lo demás es comentario.**
- **N4 (débil): s273 fue inocuo para k52b2/L0; s250 es el dtbo vivo.** No generalizar inocuidad
  fuera del kernel con el que se midió.

## 3. ¿Vendor-RE → L9 es el camino mínimo? ¿Hay atajo?

### 3.1 Qué dice el vendor que nosotros no hacemos (INV-KGSL-RE §7, condensado)
Orden vendor `gen7_gmu_boot`: CX-GDSC → bulk-clks → ahb-timeout-detect + cx-timer-init →
RSCC-wake (REQ=2, poll ACK, espera ≤100 ms, REQ=0) → load_fw (bulk a ITCM/DTCM + `dsb`) →
**register_config (17 writes)** → irq_enable → `[dev+0x2f4c]=0` + `dmb` → **SYSRESET=0 único**
(sin asertar antes, **cero lecturas MMIO entre cfg y rst0**) → `dsb` → poll `FW_INIT_RESULT&0x1ff==0x100`.
Diferencias reales tras la rectificación §8 (fence `0x80c808a0` NO es vendor-only):
**vendor-only: `0x1f8f0=1`, `0x1f8f1=1` (las dos primeras), `0x1f984=1`, `0x1f985=runtime`,
`0x1f9cd/0x1f9ce/0x1f9cf/0x1f9d0`=runtime/base, base GMU+0=`0x3c45`**, más precondiciones
(cx_gdsc + ahb-timeout + cx-timer) y disciplina (sin `SYSRESET=1` previo, sin lecturas intermedias,
HFI/fences DESPUÉS de que el CM3 corre).

### 3.2 Atajo "quitar nuestras lecturas / no hacer rst1": YA REFUTADO como causa primaria
- L7 demuestra que **todas las lecturas K44/K63 en reset son seguras** (valores esperados, fence
  `0/80c808a0`, `K19-dumpOK`). L8 elimina **todas** las lecturas tras el write (el compilador
  borra el bloque S4 inalcanzable: cero lecturas GMU tras el write en el binario) y **sigue
  matando en el write**. La ventana rst1→rst0 no es el asesino en cold boot (XBL ya trae rst1;
  nuestro rst1 extra es no-op). No gastar un flash en "L9 = L8 sin K44".

### 3.3 Atajo "no soltar el CM3 y usar el GMU de otra forma": REAL para el PANEL, FALSO para la GPU
- **Para F1b (panel): el atajo EXISTE y ya está en la mano.** s250+L5 exponen `card0+renderD128`
  sin soltar el CM3; `PLAN-C3` (k71, `c3-defer`) lo convierte en harness USB-vivo (stub en
  `a6xx_gmu_pm_resume` → `-EAGAIN`, `priv->gpu=NULL`, DRM/KMS/DPU intactos, bring-up manual por
  sysfs+workqueue). k52b2 es la prueba de existencia de ese estado. Sirve para pintar el panel
  por CPU, avanzar F1b/F3/F4/F6-prep y diagnosticar con SSH vivo.
- **Para F1a (GPU): NO hay atajo.** `HFI_START`/`FW_START` exigen el CM3 corriendo el body
  (`INV-GMU-BIN`: stub ITCM 476 B → scatter → body en icache IOVA 0x4000); sin SYSRESET=0 no hay
  `FW_INIT_RESULT==0x100`, sin él no hay HFI, sin HFI no hay `hw_init`. "GMU sin CM3" = DPU-only.
  C3 es rodeo útil, no sustituto de L9. No venderlo como tal.

### 3.4 "¿El hermano ya lo midió en su ronda 29?": sí hasta el poll, no hasta el write
- Hermano #395 (`CM3-HANG-INVESTIGACION`): estableció lo estructural (body en BO icache IOVA 0x4000
  tras SID 5; primer acceso GMU→SMMU→DDR = fetch al soltar reset; diff fork limpio; ACTLR 0x303 vs
  vendor 0x32b; `UKE-CM3DBG` + clks + dtcm-magic). Su H1 = **wedge en el primer `readl` del poll**
  (`S3-rst0` + CM3DBG, sin `S4-poll`), con plan en caliente s249+clon (#443) **pendiente de ventana
  del dueño (nunca ejecutado)**. R-25 (OPP sin tabla) ya lo falsó como bloqueo.
- L8 va **un paso más adentro**: mata el write, ni siquiera el primer readl. Nada del hermano mide
  el write puro (su instrumento medía hasta el poll). Queda abierto y nuestro lo suyo: **ACTLR/CB1
  del SID 5** (V1 de `VIAS-GPU`) y los valores runtime vendor-only. No repetir #395; continuar desde #572.

### 3.5 Veredicto: L9-mínimo SÍ es el camino, podado a un flash de constantes
L9-mínimo = base L5/s250 + **SOLO `0x1f8f0=1` + `0x1f8f1=1`** (las dos primeras del register_config,
constantes, coste 2 líneas en `fw_start` antes de `FW_INIT_RESULT=0`), manteniendo nuestra disciplina
(sin `SYSRESET=1` previo extra, sin lecturas nuevas, con `pr_flush`, poke `write-done` + bypass-nopoll
heredado de L8 para lectura limpia). Lectura en §5-paso 2. Todo lo runtime (`0x1f984/5`, `0x1f9cd–d0`,
base `0x3c45`) queda para L10 **solo si L9 habla a medias o con evidencia nueva** (REGLAS: techo
3 ciclos por hipótesis, 1 cambio por ciclo). La réplica completa de 17 writes + valores runtime
adivinados NO es mínima y violaría la regla de un cambio.

## 4. Presupuesto y plan si el próximo flash gasta el último retry

Estado (ledger #572): `boot_a`=L8 `3fd83bc3…`, `dtbo_a`=s250 `f0dc934d…`, batt 3846 mV,
**slots 5:6, B intacto 6:6**. Nota honesta: 5:6 = 5 restantes si la escala es 6:6=lleno
(#562 "A recuperó un reintento", #570 "1:6 tras el ciclo malo"); el "¡a 1 del límite!" del encargo
solo cuadra si el límite operativo local es "no bajar de 5" — en todo caso #570 prueba que
**un ciclo puede quemar 4+ retries de golpe**, así que 5:6 no es colchón.

Plan de contingencia (pre-escribir ANTES del próximo flash, 0 escrituras):
1. **Pre-stage en PC**: par-B dorado verificado por sha — `boot-ukek13-dsid.img` `e0ee47dc…` +
   `s260-boot-dtbo-dpu-iommus.img` `6fbb5173…` (`SHA-BUENOS.txt:48-49`, copias en
   `build/backup-par-bueno/`); par-A de reparación — **L0 `boot-uke-k52L0.img` `935350f7…` +
   dtbo s273** (combo que habla, n=múltiple) con s269 `8893fe37…` como segunda opción;
   variante s250-sin-cmdline `78ea1760…` a mano. `fastboot getvar all` (los 4 contadores) antes y después.
2. **Si A cae a 0/unbootable o a fastboot sin salida**: NO insistir en A. `set_active b` →
   verificar `slot-retry-count:b` → boot B → SSH → cargar (`uke-adsp-load.sh` + `bateria.sh --umbral 3700`,
   cargador de pared, en fastboot NO carga) → `getvar battery-voltage` ≥3700 mV →
   revivir A **solo** con L0+s273 (1 flash, pre-registro, lector armado, vigía con pausa).
   Precedente de reset de contadores: `set_active a` + `set_active b` (#453, #5772).
3. **Regla de parada de slots**: si tras el próximo flash A ≤1 restante, **congelar flashes a A**,
   restaurar A=L0+s273 y pasar a solo-lectura + C3/panel-CPU hasta re-negociación explícita del
   presupuesto con el dueño (REGLAS: la fila del ledger dice "día agotado" cuando toca).

Puerta de B con qué imagen: **B = K13-dsid + s260, nada experimental.** L0/L9/s250 no pisan B
salvo orden explícita del dueño con fila propia. B es rollback, no segundo banco de pruebas.

## 5. Top-3 riesgos reales ahora mismo

1. **Quedarse sin banco experimental por quemar A (probabilidad media, impacto crítico).**
   20 flashes/día + wedges que queman retries en racimo (#570: 6:6→1:6) + fastboot que descarga
   (R-44) + carga que solo existe con la cadena ADSP arriba. Sin A no hay L9; si se toca B por
   impaciencia no hay rollback. Mitigación: §4 + volver a ≤2/día + gate batería/cargador/lector/vigía.
2. **L9 ciego: el wedge no deja evidencia y cada intento cuesta un retry.**
   El write cuelga el bus en duro (sin `write-done`, sin pstore, ramoops muerto en power-cycle,
   WDT sin armar). Sin V9 (arming 6 s + volcador sda30 + pstore en initramfs) + V5 (WDT 12 s →
   reset caliente con ramoops legible) el L9 devuelve 1 bit por flash. Mitigación: paso 1 antes
   del flash; si L9 calla sin traza nueva, no hay L10 por insistencia.
3. **Falsa llave por valores runtime adivinados + stacking de variables.**
   `0x1f984/5`, `0x1f9cd–d0`, base `0x3c45` dependen de campos del `kgsl_device` que solo existen
   en un boot vendor (V3-Android instrumentado, coste alto). La tentación será meterlos todos
   "por si acaso" + precondiciones CX/clks en el mismo flash → veredicto ilegible y vuelta a la
   era k65–k70. Mitigación: L9 = constantes primero; runtime solo con captura previa (print nuestro
   en el mismo punto) o RE que identifique `[x+0xb8]`/`[dev-0x2d0]`/`[dev+0x1920]`; 1 cambio por ciclo.

## 6. Plan mínimo de 3 pasos con criterio de parada

**Paso 1 — 0 flashes: canal de rescate + RE mínima (PC + testbed vivo).**
- V9: arming GPU-on a ≥6 s + retry `filp_open(/dev/sda30)` + pstore montado en initramfs +
  restaurar volcador 15 s (diseño hecho en `VIAS-GPU` V9; aplicarlo al cpio K34-fw). V5: WDT armado
  12 s antes del open (diseño hecho en V5; verificar nodo `watchdog@17c10000` en s250 fusionado).
- V1-lite: en `adreno_gen7_gmu.c:1868-1885` + `kgsl.asm` confirmar precondiciones ordenadas
  (cx_gdsc → clks → ahb-timeout/cx-timer → RSCC-wake) y semántica de `0x1f8f0/f1` (posición prominente,
  constantes); revisar ACTLR/CB1-SID5 pendiente del hermano sin re-hacer #395.
- Criterio de paso: V9/V5 listos para hornear en el flash del paso 2 (o declarados innecesarios por
  escrito si el dueño acepta 1 flash ciego más, con motivo en la fila). Sin esto, no hay paso 2.

**Paso 2 — 1 flash: L9-mínimo (L5/s250 + `0x1f8f0=1, 0x1f8f1=1`, sin rst1 extra, sin lecturas nuevas).**
- Artefacto: repack G0–G8 verdes, cmdline 580 B = k64 (`12559c46…`), cpio k52b2, perfil L0+L5+L6–L8
  + 2 writes nuevos, negativos limpios; pre-registro en el ledger ANTES del flash con sha;
  gates: batt ≥3700 mV + cargador, slots antes/después, lector único armado SIN `timeout`,
  vigía con pausa, B dorado a mano.
- Lectura (ACM + `dmesg -w` por SSH si vive):
  | Último testigo | Veredicto |
  |---|---|
  | `nopoll-ok` (o S4/HFI tras el write) | **LLAVE**: el CM3 vive con las 2 constantes → HFI→card0; siguiente: hornear resto vendor-only de a uno |
  | `write-done` sin `nopoll-ok` | write seguro, asesino = primer readl (entonces sí, poll/SMMU-fetch: V1/ACTLR) |
  | `pre-rst` sin `write-done` (como hoy) | **falta precondición de reloj/power** (GMU_PWR_CLK/hub, voto CX previo, RSCC-wake) o el CM3 necesita fw-start previo — NO añadir runtime a ciegas; ir al paso 3 |
- Criterio de parada local: cualquier veredicto con traza archivable (log ACM + sha + foto de slots)
  cierra el paso; "calla sin bytes nuevos con lector armado" NO es veredicto y exige repetir (n≥2)
  antes de declarar.

**Paso 3 — bifurcación con parada global (0–1 flashes).**
- Si L9-LLAVE: L10 = +1 variable (siguiente vendor-only por orden vendor o precondición que la traza
  pida), mismo rigor. Si L9-PRE-RST: **congelar GMU-flashes** y ejecutar C3-defer (k71, diseño listo
  en `PLAN-C3`) para panel-CPU USB-vivo + RE offline de runtime values (print en el mismo punto,
  V1 profunda, V7-patch-gmu.bin como bisección quirúrgica si V1 lo pide).
- **Parada global (cualquiera dispara stop):** A ≤1 retry restante → restaurar A=L0+s273 y
  solo-lectura; 3 ciclos sin movimiento en `dmesg` sobre la misma hipótesis → refutada (REGLAS,
  techo 3); batt <3700 mV sin cargador → ni se entra a fastboot; dueño retira override → día agotado
  por escrito. La parada se escribe en el ledger, no se negocia en el chat.

## 7. Anexos (trazabilidad mínima)

- Shas que mandan: L8 `3fd83bc3…`, s250 `f0dc934d…` (variante sin-cmdline `78ea1760…`),
  L0 `935350f7…`, B-dorado `e0ee47dc…`+`6fbb5173…`, cmdline k64 580 B `12559c46…`,
  AOP `3353ea91…` (no-salud), cpio-6oct `ebc2de46…`.
- Ledger: #561 L0 habla → #562 K64 → #563 D1 → #564 C1 → #565 D2 → #566 poll → #567 D3 →
  #568 combinación → #569 s250 probe → #570 L6 (S2→K44-A) → #571 L7 (2 candidatos) → #572 L8 (mata el write).
- Hermano: #395 CM3-HANG (SID5/fetch, ACTLR, diff limpio) → #443 plan s249 caliente (no ejecutado) →
  R-25 OPP falsado → ronda-29 REFUTADO R-24…R-34 (DT/OPP/unbind/ADSP).
- Documentos que esta crítica deja obsoletos en lo F1a/F1b: F §5-riesgos-GPU y §7-checklist-GPU
  (sustituidos por §§1–6 + INV-KGSL-RE + VIAS-GPU + PLAN-C3); veredictos k65–k70 del ledger
  #553–#560 (sustituidos por #561–#568); "k64 que se flasheó" (nunca existió, #554).
- Lo que NO se hizo aquí: ningún build, ningún repack, ningún flash, ningún `set_active`,
  ninguna lectura de `/dev/ttyACM0`. Solo lectura de repo + ledger + disco.
