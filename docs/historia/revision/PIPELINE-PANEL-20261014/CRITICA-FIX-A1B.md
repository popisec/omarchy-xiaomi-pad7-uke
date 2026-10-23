# CRÍTICA adversarial FIX-A1b (reclaim quirúrgico) — 14-oct-2026

## VEREDICTO: **PASA** compilar+flashear L52 (con correcciones §5, sin rebuild)

## 1. Diff verificado (copia /tmp, árbol intacto)

- 9 hunks, solo `arm-smmu.c`; forward dry-run + apply real sobre copia OK.
- Reemplazo limpio de A1: `FIX-A1b:` pr_info=6, `FIX-A1:` viejo=0, residuo
  `wmask 6+7+8`=0; `count==0` solo en 4 sitios preexistentes (480/491/2516/
  3933), ninguno en el reclaim; release-write intacto (miga ×1).
- Force-idx no alcanza reset (fases no lo consultan) ni otros maestros
  (`idx!=force` ⇒ silenciados como en L50); únicas escrituras HW posibles:
  SMR(2)+S2CR(2) (alloc), CB69 (init), S2CR(2) (install). Free path sin hunk.
- R5 ambos órdenes: qcedev-antes (medido) ya pasó sus gates; qcedev-después
  obtiene otro idx (RAM idx2=display, sin match) y se silencia. Sin unbind,
  el count compartido es inerte. `uke_bl`/preserve/early-continue no
  neutralizan (RAM s2cr[2]=BYPASS≠TRANS: el install no hace early-continue).

## 2. Riesgo CB69 (novedad): contexto partido en dos escrituras

- Primera escritura (SMR(2)/S2CR(2), ~4.082 s) es **pre-UFS** (sda lista a
  4.190 s; dmesgw L50 :1904 vs :2027): un abort ahí repite clase-L51. El
  §2 del doc ("UFS ya vivo") es FALSO para esta escritura; solo CB69 +
  install (~47 s, :2836) son post-UFS. Corregir §2 y ramificar runbook.
- S2CR(2)-write y CB69-write son ambas novedad (solo READS de SMR(2)
  probados): "probado accesible" sobrestima. Riesgo residual BAJO-MEDIO,
  concentrado a 4.08 s; a 47 s el rescate es rico aunque aborte el CB.
- Orden real ya es el seguro (SMR/S2CR a 4 s, CB a 47 s): sin cambio.

## 3. Hueco no analizado: ventana de traducción del splash (4 s → modeset)

- 4.08–47 s: S2CR(2)=BYPASS-ish (defaults RAM); 47 s–modeset: TRANS→CB69
  con tablas KMS sin el FB del splash ⇒ pantalla probablemente basura
  desde ~4 s + fault storm (~60+/s con handler disp) hasta el DCS.
- Esperado no-fatal (scanout-faults no wedgen CPU) y útil como señal
  (faults CB69 = traducción viva), pero: (a) no leer basura como FALLA;
  (b) el spam puede saturar ACM-115200 — la evidencia primaria es
  netconsole+`dmesg -w`, no ACM. Añadir al runbook como observación
  esperada. Sin mitigación de código (pre-leer el CB sería acceso nuevo
  en SMMU haunted: prohibido por regla).

## 4. Aritmética: un error de fórmula, valores bien

- Cmdline L52=608: MEDIDO img L51=638 B (extraído del header) −30
  (` arm_smmu.uke_write_mask=0x1C0`) =608 ✓ (=580+28). Gate 608 correcto.
- `UKE-POKE`=121 correcto pero la fórmula del doc es falsa:
  115+6−2=119, no 121. Lo correcto: 115+6 (base L50 sin A1) o 117−2+6.
  Corregir texto; el valor del gate queda. `FIX-A1b`=6 ✓ (6 pr_info;
  comentarios no emiten). `uke_disp_reclaim`=1 ✓ (patrón param estándar).
- Ausencia de `uke_write_mask` como gate: correcta (default 0; TOKS_KEPT
  no lo trae; el gate binario del nombre del param no depende de cmdline).
  Al clonar el repack: quitarlo del append, exigir ausencia en cmdline.

## 5. Correcciones exigidas (doc/runbook; sin rebuild)

1. §5: fórmula → `121 (=115+6; base L50 sin A1)` (o `117−2+6`).
2. §2: partir el riesgo CB69 en dos (4.08 s pre-UFS clase-L51 / 47 s
   post-UFS con rescate rico). UFS-vivo solo desde sda-ready.
3. Criterio: añadir caso **NULO** (sin miga reclaim no se interpreta) +
   señal de apoyo (faults CB69/display post-47 s = traducción viva) +
   basura de pantalla ≠ FALLA + grep `qcedev` post-boot.
4. Runbook = L50 §5 + `stty -F /dev/ttyACM0 raw -echo` (SÍ incluir:
   higiene estándar, inofensivo, evita el interleave de L51) + lector
   único + checkpoint sda-ready + rollback **L50** (ya lo dice).
5. Menor opcional (follow-up, no bloquea): las 3 admisiones force-idx
   (:1614/:2598/:2725 en copia) sin guarda `uke_smmu_es_apps` pueden
   soltar migas espurias en kgsl-smmu (comportamiento intacto:
   `wmask_on()=true` fuera del armado; la miga lleva `dev=` y se
   distingue). Añadir la guarda cuando se toque el fichero.
