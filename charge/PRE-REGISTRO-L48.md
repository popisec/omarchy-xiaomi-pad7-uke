# PRE-REGISTRO L48 — migas del bind/post-bind del DPU (14-oct-2026, tarde-noche)

> Fila lista para el ledger ANTES de flashear. **NO flasheado aún** (build en curso).

## Qué es

`L48 = L47 + 14 señales nuevas K48 (instrumento)`. **Sin variable de comportamiento** (las
migas son inertes: `pr_err` + pintado). Base: L47 (`b320616b…`: L46 + 7 migas K47 + `FBDEV=n`).

- **Motivo (L47 FALLA-A)**: la muerte display-ON (~50 s) ocurre **post-bind** del DPU
  (`Initialized msm-kms minor 1` sí se imprimió), sin commit, con el burst `sync_state` de
  clocks/**GDSC** del display justo antes. Nadie mide hoy: el rate del OPP, los pasos del
  enable/resume (mdss/DPU), el mmu/vbif, el **suspend** post-bind, ni acota la muerte.
- **Señales** (`l48-migas.diff` = prep + susp; ya aplicadas al árbol; gate por-tag medido):
  `K48-opp-rate` (valor numérico), `mdss-en-in/ok` (×2 c/u), `res-clk-in/ok`, `hw-resume-ok`,
  `hw-mmu-ok`, `res-vbif-ok`, `res-enc-ok`, `hw-vbif-ok`, `post-init`, **`K48-alive-%d`**
  (heartbeat +3/+8/+15 s; formato único en el binario), `dpu-susp` + `mdss-susp` (hueco §9 de
  la crítica: ¿quedaron clocks ON/OFF tras el bind?).
- **FASE-1 (sembrado SRC/parked_cfg): NO procede** (CRITICA-L48 §10): el OPP ya siembra 514 MHz
  antes del primer enable (`dpu_kms.c:1313-17` + rama core `CLK_SET_RATE_PARENT`). `K48-opp-rate`
  lo verifica en vivo: **si lee ≠ 514000000 → FASE-1 revive en L49**. Acotación: esto cancela
  «parked_cfg=0», NO el rewrite-en-vivo (`clk_rcg2.c:1437` incondicional) — línea 1b/inherit futura.

## Artefactos (a completar con el build)

- Kernel: `build/kernel-pokes/k52L48-build/` (config `k52L48.config` = L47 con FBDEV=n).
- Boot: `build/bootimg/boot-uke-k52L48.img` (repack clon, display-ON 566 B) — sha pendiente.
- **dtbo: s287 se queda**.
- Evidencia previa: `out/h2-dumps-l46/` (restaurado del commit `976f714` — los `uke-*` por
  uptime **se sobreescriben entre boots**; CRITICA-L48 §4).

## Criterio pasa/falla (6 ramas — CRITICA-L48 §11)

- **PASA**: vive >6 min **sin `atom-tail`** ⇒ L47 fue entorno/flaky (C6). → **modetest
  condicional**: `modetest -M msm-kms -c` (solo lectura) → **un intento** `-s 36@<crtc>:<modo
  de la lista>`. **PASA-MODESET** (nueva rama): si sddm modesetea solo y vive → éxito total
  (casilla propia).
- **FALLA-COMMIT**: hubo `atom-tail` (userspace modeseteó).
- **FALLA-POST**: `post-init` sí, sin `atom-tail`; los `alive` acotan 3/8/15 s. **Sin ACM
  commiteado = INCONCLUYENTE** (CRITICA-L48 §3: el ACM de L47 no cubría la ventana).
- **FALLA-BIND**: falta alguna K48 esperada → **la última miga = punto** (ojo: `mdss-en` ×2).
- **FALLA-TEMPRANA**: <20 s ⇒ otra muerte.
- **Triage extra**: si tras el bind aparece `L6-open` (GPU) y muere ahí → pista GPU/GMU.
- Regla: la última miga = «murió EN o DESPUÉS»; `K48-opp-rate` con 4 lecturas prescritas
  (514M OK / 0 → FASE-1 / otro → investigar / ausente → la miga no corrió).

## Runbook

1. **Pre**: `fastboot getvar all` (retries a/b; **si a<3, NO flashear hoy**); batería ≥3700 mV
   (excepción del dueño si no); **cargador de pared** si es posible; commitear el ACM actual y
   armar **lector único nuevo** (`out/acm-L48.log`) + dumper (ya activo en la tablet).
2. `fastboot flash boot_a` L48 + `set_active a` + reboot.
3. Verificar por SSH (si vive) y/o por **ACM + dumps** (si muere): K48 disparadas, `alive`,
   `L6-open`, `sync_state`.
4. Si PASA: modetest condicional (1 intento). Si cuelga: reset físico y parar.
5. **Tope del día: L48 + rollback = 2 escrituras** (CRITICA-L48 §12).

## Rollback

`fastboot flash boot_a` L45 `83647c454709c1e895ef9904879cff79b3ed8ac7196988cec104b6711ccab059`
(o L47 `b320616bc4414537ac5bc5d2277c064bcd9ab23edf2de98251ff47027f0660d0`); dtbo s287 intacto.
