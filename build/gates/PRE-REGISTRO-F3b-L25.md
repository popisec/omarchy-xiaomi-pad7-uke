# PRE-REGISTRO F3b/L25 — 12-oct (LISTO PARA FLASH, NO EJECUTADO)

> Continuación de `PRE-REGISTRO-F3-L24.md`. L24 wedgeó; este es el experimento que lo sustituye,
> según la tabla de lectura que L24 dejó abierta.

## Por qué L25

El análisis de `wedge-l24-bootloop.log` concluir (y se verificó contra el código) que **quitar
`video=DSI-1:d` NO causó la muerte**: el SoC muere en `dpu_kms_hw_init()` → `msm_kms_init_vm()`
(~4,0989 s) y el efecto de `:d` (`connector->force`, `drm_connector.c:173`) se aplica ~0,4 ms
**después**. `:d` era causalmente inerte en ese punto.

Lo que sí es letal es **saltar el BCR dejando vivo el scanout del ABL**. Falta **exonerar `:d`
por completo**, y esa es exactamente la variable que L25 aísla.

## Artefacto

- **Fichero**: `build/bootimg/boot-uke-k52L25.img`
- **sha256**: `04cd49803b9a640212a09386cde6b6992494a30e785d22138609e66d987aeb28`
- **Tamaño**: 100663296 B (= `partition-size:boot_a`, exacto)
- **Cmdline**: 606 B = base L19 (580 B, byte-idéntica a k64) **+ ` msm.uke_skip_mdss_reset=1`**
- ✅ **`video=DSI-1:d` PRESENTE** ← **la diferencia clave respecto a L24**
- ✅ `msm.uke_skip_mdss_reset=1` presente
- ✅ `msm.uke_panel_inherit` ausente (0 en el binario)
- **Árbol**: `build/kernel-pokes/k52L25-tree` · **diff**: `build/gates/patches/l25-panel-probe-instrumentation.diff`
- **Repack**: `docs/historia/gates-palawan/repack-k52L25.py` · gates G0–G8 verdes

## Qué añade respecto a L24

**Instrumentación del panel con `uke_poke`** (que es `pr_err` → **visible por ACM aunque con
`loglevel=4`**, a diferencia de las `pr_info` del panel):

| Miga | Dónde |
|---|---|
| `K47-pan-probe` | entrar en `o82_probe()` |
| `K47-pan-probe-ok` | antes de cada `devm_mipi_dsi_attach` |
| `K47-pan-probe-attach-ok` | después de cada attach |
| `K47-pan-pwron` / `-ok` | entrar/salir de `o82_power_on` |
| `K47-pan-prep` | entrar en `o82_prepare()` (ya existía) |

Motivo: `o82_probe()` **no tenía ninguna miga**, así que hoy es imposible distinguir "el panel no probó"
de "probó pero el host/PHY mató al SoC antes del prepare". Esto lo resuelve.

## Tabla de lectura pre-registrada (decidida ANTES del flash)

| Resultado | Significado |
|---|---|
| **Arranca y vive** | `:d` queda **exonerado**. El BCR es load-bearing para el bind con splash vivo, pero no es el asesino del panel ⇒ el asesino está en el **prepare** (o en el link DSI). Avanza a la hipótesis del prepare |
| **Wedgea a ~4,09 s igual que L24** | `:d` exonerado **y** el asesino es puramente **skip × bind del DPU**: reprogramación en caliente de RCG compartidos (`clk_rcg2_shared_enable` → `parked_cfg=0`) o reescritura de VBIF AMEMTYPE. **Siguiente experimento:** gatear `dpu_runtime_resume` (vbif + clk_bulk) manteniendo el skip del BCR |
| **Vive pero sin imagen** | Igual que L19: el `:d` fuerza conector off. Confirma que `:d` es el bloqueo de la imagen |
| **Muerre antes de 4 s** | Fase anterior al bind del DPU — mirar las migas nuevas para localizar |

En **todos** los casos, las migas `K47-pan-probe*` dicen si el panel llega a probarse.

## Preflight (en orden)

1. [ ] **`slot-retry-count:a`** — está en **7** ⚠️ (el techo). Un wedge más lo lleva a `unbootable`.
       **Decidir antes**: ¿se acepta el riesgo, o se recupera primero el contador?
2. [ ] **Batería ≥ 3700 mV** con cargador (última lectura: 3544 mV ⚠️).
3. [ ] `fastboot flash boot_a boot-uke-k52L25.img` → **leer de vuelta hasheando a 100663296 B**
4. [ ] **`fastboot set_active a`** (sin esto cae a B)
5. [ ] Lector ACM armado **antes** del reboot
6. [ ] `fastboot reboot`

## Recuperación probada (usada con L24, funcionó)

```
fastboot flash boot_a <L19>   # sha 71d89ca6e875941b75af012ac24d20fb7690de407fa341923f2d896557ee51a9
fastboot set_active a          # limpia slot-unbootable
fastboot reboot
```
→ Verificado: `slot-unbootable:a` pasó de `yes` a `no`, SSH vivo, FD735 + GLES + card0/card1.

## Riesgo asumido

L25 lleva **el mismo gate que wedgear L24**. Si vuelve a hacer boot loop, el slot A puede caer a
`unbootable` otra vez. La recuperación está probada y es un comando, pero **cada ciclo wedgeado cuesta
un reset del contador** y `slot-retry-count:b` está en 6 (cercano a su propio techo).

**Recomendación: cargar la tablet y dejar el contador en un valor holgado antes de ejecutar esto.**