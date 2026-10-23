# FIX display-ON: SMMU (primario) + guarda de clocks (secundario) — 14-oct-2026

> Solo lectura del árbol; diffs generados sobre copia en `/tmp/ukefix/`, dry-run OK contra el árbol real sin tocarlo. Diffs: `/tmp/ukefix/fix-smmu.diff` (A1), `docs/historia/revision/PIPELINE-PANEL-20261014/fix-bypass.diff` (A2), `docs/historia/revision/PIPELINE-PANEL-20261014/fix-clk-guard.diff` (B).

**Recomendado: FIX-A1** (reclaim de la entrada BL del display + `uke_write_mask=0x1C0`). Requiere flash (build+repack). Nada de esto es aplicable en runtime (§5).

## 1. Hueco en F1 de forensia A (MEDIDO en código; la prioridad es HIPÓTESIS prioritaria)

- El BL deja el SID del display (`0x1c00/0x2`, `palawan.dtsi:3357/3379`) VIVO en HW en idx bajo PINADO: `PIN SMR(2) HW=0x80021c00` (dmesg ~1799); el attach del kernel reclama idx libre 20 solo en RAM (dmesg ~1904-1909, `docs/historia/revision/PIPELINE-PANEL-20261014/L50-SMMU.md` §3).
- `arm_smmu_write_sme` escribe SMR+S2CR (`arm-smmu.c:2122`), `install_s2crs` solo S2CR (`:2559`), `write_context_bank` el CB (`:1505`); las tres están tras gates `wmask` bits 6/7/8 (`:2507`, `:2629`, `:1589`; bits en `arm-smmu.h:616-624`).
- **Corrección a F1**: `0x180` (bits 7+8) es insuficiente — sin bit 6 el SMR(20) jamás selecciona el SID en HW. Mínimo cmdline: **`0x1C0`** (bits 6+7+8).
- **Hueco**: aun con `0x1C0`, HW tendría DOS entradas para el SID (idx2 BL + idx20 nueva). El SMMU v2 da prioridad al **idx más bajo que casa** (HIPÓTESIS arquitectónica; coherente con `find_sme`, que devuelve el primer match, `arm-smmu.c:2223`), luego el tráfico seguiría a `S2CR(2)`→CB del splash. F1/A0 probablemente FALLA en el mismo punto.

## 2. FIX-A1 primario: reclaim opt-in de la entrada del display

- Diff `fix-smmu.diff` (2 hunks en `arm-smmu.c`): param `uke_disp_reclaim` (defecto 0 = K8/K12 intacto) + en `alloc_smes` tras `idx=ret`: si el claimant es `sid 0x1c00/mask 0x2`, se localiza la entrada BL por LECTURA SMR (segura #P9; S2CR no se lee, #P13), se des-pinea SOLO ese idx y el camino normal lo reescribe (SMR+S2CR→TRANS→CB69). Sin entrada BL reutilizable, idx intacto.
- Cmdline del ciclo: `arm_smmu.uke_write_mask=0x1C0 arm_smmu.uke_disp_reclaim=1` (conservar `uke_keep_boot=1`, `uke_reset_mask=12`).
- Riesgo MEDIO: solo se toca la entrada de ESE sid + CB69 (reservado desde arriba, guarda K9-b en `:1543`); los otros 4 idx PIN del BL (UFS idx0 incluido) ni se leen-mas ni se escriben. Si CB69 estuviera mal, el fault caería en CB69 con handler K39/disp (`:759-768`, `:819-829`) → imprime en vez de wedge mudo. Reversión: params a `0x0`/`0` = comportamiento exacto anterior.
- PASA = netconsole supera `K47-host-xfer` (`dsi_host.c:1791`); FALLA mismo punto = no era traducción.

## 3. FIX-A0 (bisección barata, sin código): solo `uke_write_mask=0x1C0`

- Repack sin compilar. Pronóstico HIPÓTESIS: falla igual (§1); si PASARA, la hipótesis de prioridad era falsa y A1 sobra. Hacerlo solo si sobra presupuesto de flashes (≤2/día).

## 4. FIX-A2 discriminante: BYPASS 1 ciclo (NO aplicar con A1)

- Diff `docs/historia/revision/PIPELINE-PANEL-20261014/fix-bypass.diff` (autocontenido, 3 hunks): mismo reclaim con `uke_disp_bypass=1` + en `install_s2crs` fuerza `S2CR_TYPE_BYPASS` (`arm-smmu.h:115-117`) solo al fwspec del display. Mismo cmdline `0x1C0`.
- Firma si la vía SMMU es correcta: el DCS COMPLETA (fetch a PA `0x1000`, basura): la muerte se mueve tras `K47-host-xfer` (aparecen S4-DIAG de 70/200 ms en `dsi_host.c:1467` o continúa el init; el panel ignora la basura). Muerte idéntica ⇒ causa NO es traducción (apunta a R1/clocks). Riesgo MEDIO-BAJO (lectura DMA de 2 B a PA baja; no vale como fix: el scanout exige traducción).

## 5. FIX-B secundario: guarda de re-voto en `xfer_prepare` (fuerza: HIPÓTESIS débil)

- R1 (`docs/historia/revision/PIPELINE-PANEL-20261014/L50-DCS-VENDOR.md` §3): `xfer_prepare` re-ejecuta `set_rate+enable` por transferencia (`dsi_host.c:2197-2198`) tras el voto de `power_on` (`:2535`), ×2 hosts en dual-sync (`dsi_manager.c:518,525`). En la 1ª transferencia es ≈no-op (enable refcountado, set_rate a igual rate) ⇒ débil; PERO la variante `v2_9` reparenta a PLL por transferencia (`dsi_host.c:415-432`) y se desconoce cuál ata este SoC (`dsi_cfg.c:263-296`) — si es v2_9, R1 sube a media.
- Diff `docs/historia/revision/PIPELINE-PANEL-20261014/fix-clk-guard.diff` (4 hunks pequeños): flag `uke_link_rate_set` en `struct msm_dsi_host` (junto a `power_on`, `:187`), set en `power_on` (`:2557`), clear en `power_off` (`:2598`), guarda solo del `set_rate` en prepare (el `enable` sigue incondicional). No cambia arquitectura.
- Coordinación: el otro subagente pokea `xfer_prepare`/`dsi_host.c` — aplicar INSTRUMENTO primero y re-chequear `patch -p1 --dry-run` al fusionar; este diff no añade pokes.

## 6. Gates del ciclo (un cambio por ciclo; regla inter-proyecto vigente)

- PASA/FALLA §2. Build: `strings` (S4-DIAG×4 + testigos), base `docs/historia/gates-palawan/repack-k52L49.py` → `repack-k52L5x.py`, sha256, **fila ledger pre-registrada ANTES de flashear**. Rollback: L49 `ccfdea9d…` / L48 `0b1d22c4…`, dtbo s287 se queda, sddm OFF. Presupuesto: batería ≥3700 mV, slots pre/post, ACM lector único + vigía, `fastboot boot` preferido.
- Runtime con 0 flashes: NO. Los 3 params son 0644 pero el attach ya ocurrió (~4 s); re-programar exigiría re-attach (unbind/bind del display en vivo = inseguro). A0 = repack sin compilar; A1/A2/B = build + repack + flash.

## 7. NO verificado

- Prioridad idx-bajo en este SMMU (solo A0/A1 la dirimen en vivo); SID emitido por el motor cmd-DMA (asumido `0x1c00/0x2`, `docs/historia/revision/PIPELINE-PANEL-20261014/L50-SMMU.md` §3); variante link-clk que ata (6g vs v2_9); valor `dma_base` en el boot mortal (lo cubre F0/S4 del instrumento, no duplicado aquí).
