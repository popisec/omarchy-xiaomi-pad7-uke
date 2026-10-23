# L59 — PPS DSC al panel (porte L37+L40 al vivo L58) · 14-oct-2026

## 1. Cambio
Un solo hunk en `drivers/gpu/drm/panel/panel-xiaomi-o82-dualdsi.c`:
`#include <drm/display/drm_dsc_helper.h>` + bloque PPS en `o82_prepare()`
tras init-cmds, antes de `freq_sel` (posición L39 verbatim).
Diff: `/tmp/ukefix/l59-dsc-pps.diff` (copia exacta del auditado
`docs/historia/revision/PIPELINE-PANEL-20261014/s5a-pps-dual-link.diff`; `patch -p1 --dry-run` OK contra el vivo con
offset +25; `-R --dry-run` OK). Ubicación origen:
`k52L39-tree/.../panel-xiaomi-o82-dualdsi.c:365-414`.

## 2. Racional (auditor, medido hoy en `CADENA-KERNEL-HW.md` §4)
Host comprime (`dri/1/state`: `dsc=85 85`, dos codificadores) pero el DDIC
nunca recibe la PPS: `grep -c picture_parameter_set` = 0 en el vivo y
`dmesg | grep -c UKE-L37` = 0. Stream DSC sin PPS = negro con sync OK,
exactamente lo observado. El hunk se perdió al reconstruir el árbol actual.
Ranking auditor: hipótesis nº 1; nº 2 = clock continuo (K48-A, NO en este
ciclo); nº 4–5 (MDP/fetch, backlight/sync) descartados.

## 3. Mecanismo (verificado)
`drm_dsc_pps_payload_pack()` (`drm_dsc_helper.c:99`) + 2×
`mipi_dsi_picture_parameter_set_multi()` (`drm_mipi_dsi.c:1553`), una por
link — el `_multi` solo transmite por `ctx->dsi` (`:1556`), el vendor lo
hace en broadcast. Precedente mainline: `panel-novatek-nt36532e.c:201-202`
(sheng, funciona). Posición: tras init, antes de 0x11/0x29 (igual que L39).
Cabo suelto declarado: `pic_width/height` del PPS salen del template (0 a
prepare-time; el host los rellena en modeset, `dsi_host.c:1034-1035`);
`pic_width=1600`/link esperado tras el split (`hdisplay/=2`, `dsi_host.c`
+ `slice_count=2`, 1600/800). Verificar bytes si sigue negro.

## 4. Gates
- Fuente: `strings Image | grep -c L37-pps` = 3, `grep -c UKE-L37` = 2.
- Vivos: `dmesg | grep UKE-L37` ≥ 1 (`PPS enviada`; ojo: UN solo pr_info
  aunque haya 2 envíos — los pokes `L37-pps-*` pintan framebuffer, NO dmesg).
- **PASA = la pantalla muestra CONTENIDO** (escritorio/patrón).
  **FALLA = negra con luz** (entonces cae la hipótesis nº 1; no apilar nada).

## 5. Runbook (ejecutor; NO build en este ciclo)
1. Pre-vuelo: batería ≥3700 mV, `getvar all` (slots), ACM único + vigía al
   par bueno, pre-registro sha en ledger del proyecto origen.
2. Aplicar diff sobre `k52-L16-tree`, build desprendido
   (`build-fast.sh --src .../k52-L16-tree ... --tag k52L59`), exigir DONE.
3. Repack clon L58 (display-ON, cmdline sin `video=DSI-1:d`), pre-registrar
   sha ANTES de flashear, flash cold-boot (cargador de pared).
4. Arrancar sddm (o modetest si no hay sesión); doble captura ACM + SSH.
5. Rollback: L58 `763d7869795e…8550` / L57 `ebe9409340db…682c`.

## 6. NO portar de L39 (S5 §2.1, vigente)
G5/G6/G7 PHY (inertes/refutados), L34-flush (daño medido), `=y` (wedge),
herencia→L24 (regresión), pokes K47 redundantes, reset-15ms (vive en S3).
