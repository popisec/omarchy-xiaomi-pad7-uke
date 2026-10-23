# PRE-REGISTRO F7/L37 — 13-oct · **enviar las PPS de DSC al panel o82**

## La variable

En `o82_prepare()`, justo tras los 104 DCS de init, enviar las Picture Parameter Set:

```c
drm_dsc_pps_payload_pack(&pps, &ctx->dsc);
mipi_dsi_picture_parameter_set_multi(&dsi_ctx, &pps);
```

Es literalmente lo que hace `panel-novatek-nt36532e.c:201-202`, el panel que **sí funciona**
en `sm8550-mainline` (sheng). Mismo packer, misma vía DCS.

## Por qué esta y no otra

La config DSC del o82 en mainline **coincide campo a campo** con la del vendor (verificada
sobre el `.ko`): DSC 1.1, 10bpc→8bpp, slice 800×24, 2 slices, block-pred ON.
**El vendor tampoco lleva PPS estática**: las genera en runtime con
`sde_dsc_create_pps_buf_cmd` y las manda como DCS Set-PPS desde
`dsi_display_enable → dsi_panel_update_pps`.

**La única diferencia era el envío.** En mainline, `grep 'pps'` en todo `msm/dsi/` = **0**.

## Trampas comprobadas antes de escribir

- `drm_dsc_pps_payload_pack` está en `drm/display/drm_dsc_helper.h`, **no** en `drm_dsc.h`.
- `slice_per_pkt` **no existe** en este mainline. **Pero sheng tampoco lo tiene ni lo
  parchea** y usa el mismo packer ⇒ no hace falta inventarlo. (El packer es de
  interpretación DP: `pps_3 = line_buf_depth | bpc<<2`.)

## Doble captura obligatoria (no repetir L34/L36)

1. Lector ACM **antes** del reboot.
2. `dmesg` por SSH, y trigger **fijado al modo real del panel (120 Hz)**, no a un 60 inexistente.

## Artefacto

- **sha256**: `aed378c321689df4cc04cc524a6c297c995ac9801382de30a5281fffb6f84869`
- Kernel: `cdde515e80f3ed9e1ed72de1ad8fd85f79108251fba722cd68b2487060382e8b`
- Cmdline: 585 B, **idéntica a L36**
- Gates: PPS pack/send/done x1 + log x1; early-return de L36 sigue dentro (cadena x0);
  fbdev ausente; UKE-POKE 113, K47- 27 intactas

## Tabla de lectura

| Resultado | Lectura |
|---|---|
| **El panel se enciende** | Las PPS eran el agujero. Pantalla |
|Sigue muriendo pero el log muestra `L37-pps-send` y ya pasa `K47-pre-init` | Envío correcto, el problema pasa a ser otro |
| `dsi_ctx.accum_err` al enviar | El panel rechaza la PPS ⇒ mirar `slice_per_pkt` |
