# L66-ADSP-ICC — revert L19 + fragmento dtbo @2404 (fix AUTH_AND_RESET -22)

Fecha: 2026-10-15. Base: `ADSP-AUTH-22.md` (MEDIDO 14-oct). Causa: sin votos DDR el TZ
rechaza `AUTH_AND_RESET(1)`; L19 (`qcom_q6v5.c`) anula el `icc_get` fallido a NULL y el
DT vendor apunta a `0x187/0x189` sin driver. Fix = 2 piezas inseparables. NO build en
este prep; lo hace el ejecutor.

## 1. Pieza kernel: revert del hunk L19

- Hunk: `build/kernel-pokes/k52-L16-tree/drivers/remoteproc/qcom_q6v5.c:349-358`
  (+ 4 guardas `q6v5->path ? …` en líneas 49/57/85/175). Diff original:
  `build/gates/patches/k52L19-icc.diff`. L18 (`qcom_q6v5_pas.c:548-555`) NO se toca
  (el diff solo toca `qcom_q6v5.c` — verificado).
- Revert: `/tmp/ukefix/l66-l19-revert.diff` (5 hunks: 4 guardas → `icc_set_bw`
  directo; rama NULL/`pr_warn` → `return dev_err_probe(... "failed to acquire
  interconnect path")` + gate `pr_info("UKE-L66: icc paths requeridos (L19 revertido)")`).
- Verificado en copia /tmp: `patch -p1 --dry-run` RC=0, aplicado OK, reverse dry-run
  RC=0. El ejecutor lo versiona como `build/gates/patches/k52L66-icc-revert.diff`.

## 2. Pieza dtbo: fragmento @2404 para el s288

- Fuente hermano (literal): `~/proyectos/ubuntu-permanente/criticas/ronda-29/ADSP-Y-CARGA.md`
  §2.1 `fragment@1201` (en ledger #398 renumerado @1301 sobre s190 → s196, OK en Ubuntu 25-sep):
  `target-path="/soc/remoteproc-adsp@03000000"`, `interconnects=<0x188 3 0x188 512>`,
  `cx-supply;` vacía. Con L18 la `cx-supply` es redundante pero se conserva (fiel al @1301).
- Valores verificados hoy en NUESTRA base (`~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img`):
  `mc_virt`=`/soc/interconnect@1` phandle `0x188` (`qcom,cliffs-mc_virt`, bound en L64);
  IDs `3`=MASTER_LLCC, `512`=SLAVE_EBI1 (`palawan.c:1851-1852`); nodo ADSP con vendor
  `0x187/0x188/0x189` + `cx-supply=<0x185>` (defer eterno hoy).
- Nuestro dtbo: s287 acaba en `fragment@2403`; el nuevo es **@2404**. Builder:
  `charge/mkdtbo-s288.py` = clon de `mkdtbo-s287.py` (G0 pins s287 `9f3d2b00…` + base
  `3f973c78…`; G1 extrae payload y exige max=2403; G2 injerta @2404; G4 valla:
  `interconnects` del ADSP; G5 paridad s287; G6 dt_table+roundtrip).
  Gates: `fdtoverlay` verde + `build/gates/uke-dtbo-check.py` limpio (regla #1: además
  `fdtoverlay -i base -o merged nuevo.dtbo` a mano antes de flashear).

## 3. Build + prueba + rollback

- Kernel k52L66: árbol `k52-L16-tree` (= fuente del L64, verificado en `build-k52L64.log`)
  + revert; config `k52L64.config` (sin cambios: carga sigue =m); salida `k52L64-build`→
  `k52L66-build`; repack clon de `repack-k52L64.py` (cmdline 622 B = L63 byte a byte) →
  `boot-uke-k52L66.img`. dtbo s288 por §2.
- Prueba forense: (a) `fastboot boot boot-uke-k52L66.img` = 0 escrituras, PERO solo prueba
  el kernel (lección #7: `fastboot boot` usa el dtbo del slot activo = s287 vendor-icc →
  ESPERADO: defer `failed to acquire interconnect path`, sin `UKE-L66`, arranque sano a
  SSH; si wedgea → reset físico, slot intacto). (b) Si (a) OK: flash `dtbo+s288` + `boot`
  = 2 escrituras (techo diario) y reboot.
- **PASA** = `remoteproc1: adsp is now up` + PDR `charger_pd` + `qcom-battmgr-bat` con
  valores (fin del `-EAGAIN`) + `Charging`. Doble captura obligatoria (regla #4):
  `uke-console-cap.sh` en ACM + `ssh … 'dmesg -w'` a fichero; `dmesg -n 7` (regla #2).
- Rollback: boot L64 `84bc0e44…` + dtbo s287 `9f3d2b00…` (slot bueno actual).
- Pre-flash (no negociable): semáforo hermano (`ESTADO-ACTUAL.md`+ledger), `battery≥3700mV`,
  `getvar all` antes/después, `e2fsck` en frío + BCB limpio, vigía al par bueno en pausa
  durante el flash, `sync` antes de reboot. Paso 0 coste-cero antes: `echo stop/start` a
  `remoteproc1` + `dmesg` (si repite -22, descarta estado TZ).
