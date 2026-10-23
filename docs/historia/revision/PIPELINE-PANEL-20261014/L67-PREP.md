# L67-PREP — BTA readback del DDIC listo para flash (15-oct-2026, noche)

> Estado al escribir: build k52L67 en marcha; tablet **apagada** (batería 2,856 V, cap 0; ver
> ledger #645). El flash queda pendiente de fastboot (orden del dueño: «si está en fastboot,
> flashealo»). Este doc = runbook compacto del ciclo.

## 1. Qué es L67 (una variable: la lectura)

- **L67 = L66 + hunk L65-BTA** (`l65-bta-read.diff`): 10 lecturas DCS **LP** en `o82_enable`
  post-PPS (0x0A/0x0B/0x0C/0x0D + 0x04 GET_DISPLAY_ID × 2 links), fail-safe (solo `pr_info`;
  el retorno lo decide el bloque PPS de L63/L64, intacto).
- Marcadores: `UKE-L65` ×2 (fuente/binario) + `uke_poke("L65-bta")` ×1. No toca PPS ni vídeo.
- Por qué: `err=0` solo prueba el DMA del host (CRITICA-RONDA2 §2); jamás hemos leído el DDIC.
  Criterio ampliado (ANGULO-DDIC §2): **0x0A = oráculo de 3 bits** (D7 booster, D4 sleep-out,
  D2/D3 display-on): `0x9C` ⇒ DDIC despierto ⇒ queda solo vídeo (C6); `ret<=0`/0x00/0xFF ⇒ sordo
  ⇒ link/PHY/vci. VOID si no hay línea `UKE-L63` en el dmesg (uke_panel_inherit).

## 2. Artefactos y gates (PC, 0 escrituras)

| Pieza | Ruta | Nota |
|---|---|---|
| Kernel | `build/kernel-pokes/k52L67-build/` (tag k52L67) | config `k52L67.config` = k52L66.config (carga `=m` intacta; sin cambios de config) |
| Repack | `docs/historia/gates-palawan/repack-k52L67.py` | clon L66: gates heredados + `UKE-L65=2` + `L65-bta=1`; cmdline 622 B == L66 byte a byte; G0 exige panel .c más viejo que Image.gz |
| Boot | `build/bootimg/boot-uke-k52L67.img` | sha256 `56e7b1e5a6b328802ae9421a67d82c0df149dc1bc46e40418afbb415580f4d79` (100663296 B) — pre-registrado #646 |
| Flash | `docs/historia/gates-palawan/flash-l67-gated.sh` | SOLO `boot_a` (1 escritura; dtbo s288 ya en slot a) + `set_active a`; gate batería ≥3300 (aviso <3700, orden explícita del dueño); checks BTA + ADSP/PDR/Charging al boot |
| Rollback | L66 `1aa5a1f1…` / L64 `84bc0e44…` (+ s287 si se toca dtbo) | |

## 3. Parte de CARGA (exigido: «que lo que flashees tenga la parte para cargar»)

- Kernel: mismo config que L66 ⇒ ADSP/PDR/charger_pd igual que el boot que YA carga (`=m` en
  rootfs + revert L66). **No se toca el rootfs** (adsp.b40 bueno + `uke-adsp-load.sh` endurecido
  con `sha256sum -c` desplegados hoy; 56/56 verificados).
- dtbo: s288 ya en slot a (fragmento @2404 `interconnects mc_virt` + `cx-supply`) — no se reflashea.
- Post-boot del script: `remoteproc1=state`, `adsp is now up`, `charger_pd`, `qcom-battmgr-*`
  con valores y `status` (PASA esperado: `Charging` si hay fuente; `Discharging` con pared apagada).

## 4. Runbook del flash (cuando haya fastboot)

```
bash docs/historia/gates-palawan/flash-l67-gated.sh     # imprime getvar all + batería, flashea boot_a, reboot,
                                        # espera SSH y vuelca: UKE-L65 (10 líneas) + contexto + CARGA
```
Juicio (prefijado): ver §1. Si `0x0A≈0x9C` ⇒ siguiente ciclo = motor vídeo (FLUSH/HS_TIMER/DB_MODE)
o byte-clock; si sordo ⇒ vci/doble-reset/EOT; **prohibido tocar vídeo si el DDIC no responde**.

## 5. Contexto de la noche

- Ronda 2 de crítica aplicada a fondo: RE Android completo (§5 de ENABLE-COMPARISON + C5-auditoría),
  repaso «ángulo DDIC» (`ANGULO-DDIC-20261015.md`), RE-gaps (`RE-ANDROID-GAPS-20261015.md`).
- **Ciclos ahorrados/refutados**: SPLIT_LINK (Android no lo programa: paridad por omisión mutua),
  `compression_mode_ext`/0x07 (no existe en vendor: la PPS va por vía única 0x0A), «DCS en HS» ya caído.
- **Candidato nuevo (RE-GAPS §3, único bit abierto del timing)**: mainline activa **widebus**
  (dsc && DSI 6G ≥ v2.5; uke = v2.8) ⇒ `bits_per_pclk=30` ⇒ **ACTIVE_H=0x01CB0020 (H=427)**, mientras
  el vendor (sin rama widebus) escribe **H=534 (0x02360020)**. Discriminante 0-flash con L67 vivo y
  commit arriba: **una sola lectura** `devmem 0xae94024` (ACTIVE_H ctrl0: base 0xae94000 + io_offset 4
  + rnndb ACTIVE_H=0x20; dirección CORREGIDA por CRITICA-L67 B1) **+ ancla** `devmem 0xae94028` =
  ACTIVE_V (0x08EC0094 esperado ⇒ confirma el modelo de mapa). NO volcar rangos. → `0x02360020` =
  paridad vendor / `0x01CB0020` = widebus-mainline (candidato nº1-bis del próximo ciclo).
- `docs/historia/revision/PIPELINE-PANEL-20261014/PANTALLA-COMPLETA-2.md` está **corrupto** (todo NULs, también en git desde 8cecc0a): usar
  `CRITICA-RONDA2` + `COMPARATIVA` + `ANGULO-DDIC`. Pendiente: reconstruirlo o borrarlo.
