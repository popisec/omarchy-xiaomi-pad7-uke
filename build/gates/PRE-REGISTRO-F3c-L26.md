# PRE-REGISTRO F3c/L26 — 12-oct 05:4x (LISTO, EN EJECUCIÓN)

## Por qué este experimento

L25 demostró que el skip del BCR **sobrevive al bind del DPU** (`msm_dpu ... bound ae94000.dsi` a
3,965 s, punto exacto donde L24 moría). Con `:d` el conector queda `disabled` y `o82_prepare` nunca
corre. **L26 quita `:d`** — el único bloqueo conocido — sobre **el mismo kernel de L25**, para que por
fin se ejecute un `prepare` real del panel.

## Artefacto

- **sha256**: `b512f722d7457bf0241e2ba9c9280e1e048e15e67eb71472f4bd9ad36dad5429`
- **Tamaño**: 100663296 B (exacto)
- **Kernel**: el MISMO de L25 (`Image.gz` sha `d81bb6eb9f2f…`) — **solo cambia la cmdline**
- **Cmdline**: 592 B = L19 (580 B) **− ` video=DSI-1:d`** + ` msm.uke_skip_mdss_reset=1`
- ✅ `video=DSI-1:d` **AUSENTE** (la diferencia clave)
- ✅ `msm.uke_skip_mdss_reset=1` presente
- ✅ `msm.uke_panel_inherit` ausente
- Gates G0–G8 verdes. G2 y G6 reescritos y verificados con igualdad exacta.

## Dato gratis que ya tengo

El panel **probeen y se engancha a los 2 hosts DSI** (L25: `K47-pan-probe` a 0,49 s,
`attach-ok` ×2). Las 6 migas `K47-pan-probe*` son `pr_err` ⇒ visibles con `loglevel=4`.

## Tabla de lectura pre-registrada

| Resultado | Significado |
|---|---|
| **`K47-pan-prep` > 0 y el sistema vive** | El `prepare` corrió sin matar el SoC ⇒ **el panel TDDI sí se puede encender**. Camino a display real |
| **`K47-pan-prep` > 0 y wedge** | El `prepare` es el asesino (fenómeno B). `o82_reset`/`o82_power_on` matan el SoC — coincide con `ESD-MASK-TEST` |
| **Muerte antes de `K47-pan-prep`** | El bind/modeset con conector habilitado vuelve a matar. Habría que gatear `dpu_runtime_resume` (vbif + clk_bulk) manteniendo el skip del BCR |
| **`pan-pwron` > 0 pero `pan-pwron-ok` = 0** | Los rails del panel no levantan (vddil8b/vsp/vsn) |

## Preflight

- [ ] Batería, `slot-retry-count:a` (⚠️ va justo; un wedge más → `unbootable`, recuperación probada)
- [ ] sha verificado antes de escribir
- [ ] `set_active a` **siempre**
- [ ] lector ACM armado antes del reboot

## Recuperación probada

```
fastboot flash boot_a build/bootimg/boot-uke-k52L19.img   # sha 71d89ca6…
fastboot set_active a
fastboot reboot
```