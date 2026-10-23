# FIX-A1b: reclaim quirúrgico del display tras el abort de L51 — 14-oct-2026

> Solo lectura del árbol (con A1 aplicado); diff `/tmp/ukefix/fix-smmu-b.diff` (176 lín, 9 hunks, dry-run OK contra el árbol vivo; **aplica directo, sin revert previo**: reemplaza los hunks A1). No compila ni flashea; no toca la tablet.

## 0. Qué mató L51 (MEDIDO, `out/CAPTURA-L51-acm.log`, ledger #626)

- `wmask=0x1C0` global escribió SMEs ajenas OK (idx5/6/7 GENI/gpi, lín. 113-137) pero `write_sme idx=8` (`soc:qcom,smmu_sde_unsec_cb`, sid `0x3fff`, lín. 141-143/197) → `synchronous external abort` en `arm_smmu_write_sme` (lín. 199), kworker `deferred_probe` (lín. 213-217/281): sin UFS/scsi ni display (cero migas `FIX-A1`: `grep -c`=0) → `/ukeinit` al rescate (lín. 353).
-	idx5/6/7 (misma página GR0, mismo tipo/cbndx) OK ⇒ el abort es específico del idx8 (HIPÓTESIS: S2CR/SMR de ese índice con control de acceso de TZ/bloque SDE apagado; la micro-ubicación S2CR-vs-SMR no se distingue: la miga quirk no salió, pero el fragmento `0.4108` prueba interleaving en la captura).
- Lección: prohibido el wmask global; el fix programa SOLO la entrada del display.

## 1. Mecanismo A1b (fuerza: diseño; la traducción sigue HIPÓTESIS primaria de `docs/historia/revision/PIPELINE-PANEL-20261014/L50-SMMU.md`)

- Con `uke_write_mask=0x0` (cero escrituras nuevas para el resto), el reclaim arma `uke_force_sme_idx=N` / `uke_force_cb_idx=CB` y los gates los admiten con miga+flush: `attach_sme` (`arm-smmu.c:2558`), `install_s2cr` (`:2682`), `write_context_bank` (`:1606`); el CB se elige en `init_domain_context` tras `alloc_context_bank` (`:1866`) solo si el fwspec del dev es `0x1c00/0x2` (solo la DPU lo tiene, `docs/historia/revision/PIPELINE-PANEL-20261014/L50-SMMU.md` §2). Flags se consumen tras usarse (re-armado idempotente en re-probe).
- Escrituras HW del ciclo: **solo 3 grupos**: SMR(2)+S2CR(2) (vía `write_sme`, que escribe S2CR primero, `:2145`) y CB69 (vía `write_context_bank`, guarda K9-b de reparto desde arriba intacta, `:1566`; CB70-quirk intacto, `:1543`). El resto de maestros queda RAM-only como en L50 (que booteó hasta 1389 s).
- Sin TLB extra: antes del primer DCS no hay tráfico del display (cero entradas rancias), el CB es nuevo y la F4 ya invalidó en el probe; paridad con mainline (el attach no invalida).

## 2. Por qué idx8 no se toca + riesgo residual

- El scan localiza por LECTURA SMR (segura #P9) solo índices cuyo HW casa `sid 0x1c00/mask 0x2` (medido idx2, barrido lín. 17: `PIN SMR(2) HW=0x80021c00 [handoff-smrs]`); idx8 (`0x3fff`) no casa ⇒ ningún gate lo admite. Otros PIN (0/1/3/4: UFS/qcedev/audio/gpi, lín. 15-21) intactos.
- Riesgo residual BAJO-MEDIO, partido en dos instantes (crítica §2; L50 `:1904` vs `:2027`): la 1ª escritura SMR(2)/S2CR(2) es a ~4.082 s, **pre-UFS** (sda lista ~4.190 s) ⇒ un abort ahí repite clase-L51 (sin rescate rico); solo CB69 + install (~47 s, `:2836`) son post-UFS con rescate `/ukeinit` viable. Además solo hay READS de SMR(2) probados: S2CR(2) y CB69 son novedad de escritura (el BL los escribió en su era, no este boot). Mitigación: miga+`pr_flush` ANTES de cada escritura. **Runbook ramificado por instante** (§6).

## 3. R5/qcedev: mitigado en código, sin cirugía de count

- qcedev reclama idx2 en RAM primero (lín. 79-83, sids `0x480/0x481`, count=1, cero escrituras HW: PINADO). A1b **no exige `count==0`** (el A1 de L51 sí, y habría rehusado): reescribe la copia RAM al SID display (necesario: `write_smr` lee la RAM) y comparte el count (mainline-normal para igual recurso; nadie hace unbind).
- Seguro porque el hold de qcedev es solo-RAM + sid-disjunto (su `0x481` no casa `0x1c00/0x2`: nunca usó HW idx2; su tráfico va por defecto/BYPASS) + el release con wmask 0x0 está silenciado (`:2597` intacto). Válido en ambos órdenes de probe (el scan lee HW, no RAM).

## 4. Cmdline L52 (MEDIDA del img L51: 638 B → **608 B**)

- `boot-uke-k52L51.img[44:44+1536]` = 638 B; quitar ` arm_smmu.uke_write_mask=0x1C0` (30 B, sin doble espacio) = **608 B**. Tokens: base 580 −`video=DSI-1:d` +`iomem=relaxed` +`arm_smmu.uke_disp_reclaim=1`; **`uke_write_mask` ausente** (default 0).
- Invocación: `--cmdline-append=-video=DSI-1:d,iomem=relaxed,arm_smmu.uke_disp_reclaim=1` en `repack-k52L51.py → repack-k52L52.py`.

## 5. Gates del repack (binario)

- Cmdline 608 B; exige `arm_smmu.uke_disp_reclaim=1` y **ausencia de `uke_write_mask`**; `TOKS_KEPT` igual; `video=` ausente.
- `UKE-POKE` = **121** (=115+6; base L50 sin A1 — o 117−2+6 desde L51 con su reemplazo). `FIX-A1b` = **6** (contar el token largo: `FIX-A1` es subcadena). `uke_disp_reclaim` = **1** (nombre de param; la DESC no se emite — verificado en L51: `FIX-A1` binario = 2 = solo pr_info). K50 ×18, S4-DIAG ×4, talla Image ±512 KB igual que L51. (Conteo fuente verificado en `arm-smmu.c.A1b`; re-verificar con `strings` al compilar.)

## 6. Criterio + runbook L52

- PASA = migas `FIX-A1b` (reclaim + force SME/S2CR/CB) + **boot completo hasta SSH** (el fallo L51 fue de boot) + superar `K47-host-xfer` (`dsi_host.c:1791`) en el modetest.
- NULO = sin miga reclaim (`grep -c FIX-A1b` = 0): no se interpreta (el fix no actuó; revisar cmdline `uke_disp_reclaim=1`, no leer como FALLA).
- Señal de apoyo (NO criterio): faults del CB69/display post-47 s = traducción viva; **pantalla basura ≠ FALLA** (§8). `grep qcedev` post-boot para confirmar el hold R5 intacto.
- FALLA = boot roto (rollback **L50**, no L51) o misma muerte con reclaim presente (traducir no era; siguiente: FIX-B clocks / A2-bypass re-diseñado sin wmask global). **Muerte a ~4.08 s** (tras la miga force-SME, sin sda) = clase-L51 repetida ⇒ rollback + re-diseño; **muerte ~47 s** (CB69/install, con sda) = rollback con rescate rico.
- Runbook = `docs/historia/revision/PIPELINE-PANEL-20261014/L50-PREP.md` §5 + `stty -F /dev/ttyACM0 raw -echo` antes de capturar (lección L51: evita el interleave) + lector único + checkpoint sda-ready (~4.19 s) + evidencia primaria netconsole/`dmesg -w` (el spam de faults puede saturar el ACM a 115200).
- Presupuesto y red de siempre: batería ≥3700 mV, slots pre/post, ≤2 escrituras/día, ACM lector único + vigía, fila ledger ANTES, sddm OFF, dtbo s287 se queda.

## 7. NO verificado + follow-up

- Que S2CR(2)/CB69 acepten escritura (primer intento; §2); prioridad idx-bajo del SMMU (la dirime el ciclo); SID emitido por el cmd-DMA; variante link-clk (FIX-B intacto en `/tmp/ukefix/fix-clk-guard.diff`, re-chequear dry-run al fusionar).
- Follow-up (no bloquea, crítica §5.5): las 3 admisiones force-idx (`:1614` ctxbank, `:2598` alloc, `:2725` install en copia A1b) no llevan guarda `uke_smmu_es_apps`: en kgsl-smmu podrían soltar migas espurias (comportamiento intacto: fuera del armado `wmask_on()` es true y el camino es el nominal; la miga lleva `dev=` y se distingue). Añadir la guarda cuando se toque el fichero.

## 8. Ventana del splash 4 s→modeset: basura + fault storm ESPERADOS (crítica §3)

- 4.08–47 s: S2CR(2) con tipo BYPASS-ish de defaults RAM; 47 s–modeset: TRANS→CB69 con tablas KMS sin el FB del splash ⇒ **pantalla probablemente basura desde ~4 s + tormenta de faults** (~60+/s con handler disp) hasta el DCS. Esperado y no-fatal (los scanout-faults no wedgen la CPU); es señal POSITIVA (faults en CB69 = traducción viva). No leerlo como FALLA ni como PASA por sí solo.
