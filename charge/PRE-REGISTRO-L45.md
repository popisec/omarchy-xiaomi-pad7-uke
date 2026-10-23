# PRE-REGISTRO L45 — orden panel↔KTZ: propagar `-EPROBE_DEFER` en el probe del panel (14-oct-2026)

> **Pre-registrado en el ledger (fila #619 — Nº72) el 14-oct 00:2x, ANTES de flashear.**
> Build 00:12 (`DONE k52L45-BUILD-OK`) + repack gates verdes. Batería: excepción del dueño
> (14-oct: «da igual la batería») — se anota el mV de fastboot antes de escribir.

## Shas pre-registrados

- **boot** `build/bootimg/boot-uke-k52L45.img` (100663296 B):
  `83647c454709c1e895ef9904879cff79b3ed8ac7196988cec104b6711ccab059`
- Image.gz: `63a0b06b26bf51739b798cb1c6582c9d3c40ef43d20583995c067a4e95c1c715`

## Qué es (cierra el "paso 7" del ROADMAP: backlight)

`L45 = L44 + un hunk` en el probe del panel o82: si `drm_panel_of_backlight()` devuelve
`-EPROBE_DEFER` (el KTZ aún no probeó), **devolverlo** para que el core reintente el probe del panel
cuando aparezca el backlight. Motivo medido (#618): el panel probea a t=0.715 s y el KTZ a t=4.33 s;
el aviso `sin backlight externo (KTZ8866): ret=-517` se tragaba el defer y el panel quedaba con
`backlight=NULL` para siempre (one-shot). El `dev_warn` queda SOLO para errores no-defer (sin
phandle). Marcador nuevo: `UKE-L45: backlight externo resuelto (KTZ8866)` (x1).
Diff: `build/gates/patches/l45-panel-defer.diff`.

## Artefactos

- Kernel: `build/kernel-pokes/k52L45-build/arch/arm64/boot/Image.gz` (build con `k52L45.config` =
  copia de `k52L44.config`).
- Boot: `build/bootimg/boot-uke-k52L45.img` — repack OBLIGATORIO `--dsid`:
  `python3 docs/historia/gates-palawan/repack-k52L45.py --dsid`.
- **dtbo: NO se toca** (s286 `33d153f2…`).

## Criterio pasa/falla

PASA (por SSH; sin regresión L43/L44):
1. `dmesg | grep -c 'UKE-L43-ICC'` ≥1 **y** `X9I2C-icc-get-ok` ≥1 (sin regresión).
2. KTZ: `probe sucess end` ≥1 + `2-0011` con driver no vacío + `/sys/class/backlight/2-0011`
   (max 4095).
3. **`dmesg | grep -c 'sin backlight externo'` = 0** (el panel ya no se queda sin él).
4. **`dmesg | grep -c 'UKE-L45'` = 1** (el panel RE-probeó y resolvió el backlight).

FALLA: wedge / 0 B / fastboot / regresión L43 / panel en defer indefinido (sin `UKE-L45`; si el KTZ
no llegara a probear, el panel quedaría pendiente — riesgo declarado y ya medido como improbable:
el KTZ probea en L44).

## Rollback

- `boot_a` ← L44 `13c9454de90cb875ae31b479bed64a5a37b54713cebf4459ac1c5599a6eb4e25` (o L43
  `5a6d1dee…` / L19 `71d89ca6…`); dtbo intacto.

## Nota de alcance

Con esto el **backlight queda cerrado de punta a punta** (canal L44 + enlace panel L45). Siguiente:
`vci` (P0) y G8; después, el kernel con display activado para atacar la muerte del DCS.

## Resultado (14-oct 00:4x) — PASA

Medido por SSH tras el flash (#619): `UKE-L43-ICC` 1 + `icc-get-ok` 1; KTZ `probe sucess end` 1 +
driver `ktz8866` + backlight 2-0011 (max 4095); **`sin backlight externo` = 0**; **`UKE-L45` = 1**.
Prueba de luz con display apagado: regs movidos, **sin luz visible** (coherente: el encendido del
panel alimenta la cadena LED; L39 lo vio con display on). Rollback no necesario.
