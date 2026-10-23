# PRE-REGISTRO F10/OPP — flash pendiente: OPP-148648750 del host DSI (solo dtbo)

> **F10 es el flash más seguro del proyecto: el OPP vive en el dtbo, no en el kernel.**
> No toca `boot.img`, ni kernel, ni initramfs, ni `userdata`. Un solo cambio (el OPP).
> **NO ejecutado. NO flasheado. Preparado y verificado en PC el 13-oct-2026.**
> Hallazgo que lo motiva: `build/gates/revision/HALLAZGO-OPP-BYTE-CLK-20261013.md`.

## 0. SSH previo (13-oct-2026, dos intentos) — PENDIENTE, no bloqueante para construir

```
ssh -i build/rootfs/uke-arch-root -o BatchMode=yes root@192.168.42.129
→ Connection timed out (2 intentos, 13-oct noche). Tablet ausente.
```

- **NO confirmado en vivo** que `byte_clk = 187500000`. Es la primera medición a hacer
  cuando haya SSH (paso 4, sin gastar ningún flash).
- Si el `clk_summary` dice 187500000, el diagnóstico queda CONFIRMADO antes de flashear.
- Si dice otro valor, parar y re-diagnosticar (tercera fila de la tabla).

## 1. El hecho (verificado en PC contra los artefactos, no inferido)

| Qué | Valor | Fuente |
|---|---|---|
| Tabla OPP del host DSI en el dtbo flasheado | `{187500000, 300000000, 358000000}` | payload del s275-r2 decompilado (`mdss_dsi_opp_ml`), coincide con `fase4-display.dts:390-401` |
| Lo que pide mainline | `byte_clk = 118.918800 MHz` | `dsi_host.c:639-682` (`dsi_byte_clk_get_rate`: pclk·bpp/8·lanes) vía `dsi_calc_clk_rate_6g` |
| Lo que aplica el OPP | `ceil(118918800) → 187.500000 MHz` ⇒ bitclk **1500 Mbps/lane** | `dev_pm_opp_set_rate()` (`dsi_host.c:390-391`) |
| Lo que corre Android | `148.648750 MHz` (= `panel-clockrate` 1189190000/8) | DT stock + `mi_disp_printk` (ver HALLAZGO §7: 1189190000, no 1190269040) |
| Exceso | **+26,2 %** sobre la tasa validada por el vendor | 187,5 / 148,64875 |
| Timings PHY | calculados para la tasa *pedida*, ejecutados a la real ⇒ **4/7 bajo mínimos MIPI** | `dsi_phy.c:374-470` (cálculo propio, no medición — HALLAZGO §7) |

Encaje con la firma: PLL lock OK + `err_work_state=4` FIFO + DCS en LP sí llegan
(van por escape clock) + `VIDEO_DONE` nunca completa + muerte tras `K48-w4-done`.

## 2. Artefacto (construido, verificado, no reconstruir)

| | |
|---|---|
| Imagen | `build/bootimg/s281-boot-dtbo-gpu-display-opp148.img` |
| **sha256 (pre-registrado)** | `90e41a6b4b91f47451bb18c0518193997604df7362631f7f3946c3ad6481b437` |
| Tamaño exacto | **607326 B** (s275-r2: 607282 B ⇒ **+44 B**, un nodo pequeño) |
| Partición `dtbo_a` | `0x1800000` = **25165824 B** (cabe: 607326 < 25165824) |
| sha256 del fichero **padeado con ceros a 25165824 B** (patrón de lectura de vuelta) | `aae3ce4259091c44e4c207a90645f8db80a8fc85a9879fba6b5e4c9faca4fd78` |
| Constructor | `build/bootimg/mkdtbo-s281.py` = clon exacto de `mkdtbo-s275.py` + G2b (injerto OPP) + G6b (gate OPP). Diff entre scripts: solo G2b/G6b/renombres (verificado por `diff`). |
| Report de gates | `build/bootimg/repack-s281-report.txt` (G0–G7 + G2b + G6b, todos verdes) |
| Reproducible | sí: pins G0 (s274/s269/base por sha) intactos; `.img` fuera de git (`build/bootimg/*.img`), el código + este pre-registro sí versionados |

**Cambio único** (fuente, orden ascendente = entrada más baja por valor):
```dts
mdss_dsi_opp_ml: opp-table {
        opp-148648750 { opp-hz = <0x00 0x8dc332e>; };   /* NUEVO: 148648750 = 0x8dc332e, verificado */
        opp-187500000 { opp-hz = <0x00 0xb2d05e0>; };
        opp-300000000 { opp-hz = <0x00 0x11e1a300>; };
        opp-358000000 { opp-hz = <0x00 0x1556a580>; };
};
```
Con esto, `ceil(118918800)` cae en **148.648750** ⇒ bitclk **1189,19 Mbps/lane** = `panel-clockrate` del DT de Xiaomi.

## 3. Verificación del resultado (lo que lo hace "seguro")

- [x] **Gates del constructor verdes**: G0 pins, G1 extract, G2 frags, **G2b injerto**
  (ancla única dentro de la tabla DSI, hex `0x8dc332e == 148648750` chequeado en código,
  sin duplicados, queda como entrada más baja), G3 phandles→labels (mismo set que s275),
  G4 dtc, **G5 `fdtoverlay` verde**, G6 semántica (GPU/SMMU-CX/GMU/display/o82/touch/bootargs),
  **G6b OPP en el merged** (set `{148648750, 187500000, 300000000, 358000000}`, mín = 148648750),
  G7 dt_table + roundtrip (`607326 B`).
- [x] **Diff estructural viejo↔nuevo (payloads decompilados con `dtc`): UN SOLO HUNK**:
```
15030a15031,15034
> 						opp-148648750 {
> 							opp-hz = <0x00 0x8dc332e>;
> 						};
>
```
  Todo lo demás byte-idéntico en estructura (verificado en `/tmp/diff281`, `diff old.dts new.dts`).
- [x] **Checker hermano** (`uke-dtbo-check.py`, regla docs/historia/AGENTS.md nº1): s275 → 4266 nodos /
  1791 phandles; s281 → **4267 nodos (+1 = el OPP) / 1791 phandles idénticos**, mismo único
  aviso pre-existente en ambos (`FALTA touchscreen@0`: expectativa obsoleta, el nodo real es
  `novatek@0` con `touchscreen-size-x=2136`). Paridad total.
- [x] **Rollback verificado**: `build/bootimg/s275-boot-dtbo-gpu-display.img` **y**
  `build/backup-par-bueno/s275-boot-dtbo-gpu-display.img` dan el mismo sha
  `67a65bc161b645d8664c4ba3fd1bfeaa9a92637bc52a1669feab9784fa7e01df`.
  Padeado a 25165824 B: `aa0d32010fa00c40dee3bd2ab8af54ef230ed112e7053e3917d31103784c37ce`.

### Desviaciones de gates documentadas (no son cambios del artefacto)

1. **G6 ADSP**: el gate absoluto heredado del s275 ("912 debe quitar cx-supply") es **rancio**:
   medido del propio s275-r2 flasheado, su merged conserva `cx-supply=<0x185>` (dtc v1.8.1
   descarta `/delete-property/` en overlays — precedente `mkdtbo-s280.py`, verificado en vivo
   12-oct). Ningún rebuild fiel puede pasarlo. En s281 se exige **paridad con el s275**
   (`185 == 185`), misma formulación que s280. El artefacto no cambia por esto.
2. **frag912/913 omitidos**: el s275-r2 vivo NO los trae (diff de payloads 12-oct, mismo
   precedente s280); el `mkdtbo-s275.py` actual sí los añade (drift posterior al s275-r2).
   Para diferir del vivo en UN SOLO hunk, s281 los omite (son `__overlay__` vacíos = no-ops).
   Sin esto el diff salía con 2 hunks.
3. **Orden en el merged**: el payload lleva la tabla ascendente (148→358) pero el merged la
   muestra descendente (358→148+nuevo al final). Comportamiento **idéntico en el s275 de
   referencia** (su payload 187→358 también mergea 358→187): es el modo de fusión de
   `fdtoverlay`, pre-existente. Inocuo: el core OPP inserta ordenado por tasa y `set_rate`
   usa ceil por valor, no por posición.
4. `build/bootimg/repack-s275-report.txt` está **contaminado**: lo sobrescribió la corrida del
   s277 (describe `s277-boot-dtbo-full.img`, 608875 B). Pre-existente, no mío; s281 escribe su
   propio `repack-s281-report.txt` (el bug de nombre del s277 no se replica).

## 4. Rollback (un solo reflash del dtbo viejo, segundos, sin kernel)

El dtbo viejo es el punto de rollback, con sha verificado en dos copias (§3):

```
fastboot flash dtbo_a build/backup-par-bueno/s275-boot-dtbo-gpu-display.img  # sha 67a65bc161b6…
fastboot set_active a ; fastboot reboot
```

## 5. Preflight (MEDIR en el momento del flash — la tablet está ausente ahora)

- [ ] Batería `fastboot getvar battery-voltage` ≥ **3700 mV**. Último conocido: **3555 mV**
  (rango citado 3555–3571, bajo gate) ⇒ **cargador de pared antes de flashear** (en fastboot no carga).
  Registrar mV inicial y final.
- [ ] `fastboot getvar all`: anotar los 4 `slot-retry-count` + `slot-unbootable` antes y después.
  Último conocido: `slot-retry-count:a = 3`. **≤ 2 escrituras por día** (regla del proyecto).
- [ ] **Secuencia frente a F9/L38**: F9 (boot L38) sigue pendiente. Un cambio por ciclo ⇒
  **F10 NO el mismo día que F9**; el dueño secuencia (F10 va sobre el boot que esté vivo en
  slot `a` en ese momento; línea base: muerte en `K48-w4-done`).
- [ ] Semáforo inter-proyecto: `ESTADO-ACTUAL.md` + últimas filas del ledger hermano antes de tocar.
- [ ] sha del s281 verificado antes de escribir (`90e41a6b…`, `607326 B`).

## 6. Procedimiento exacto

```
fastboot flash dtbo_a build/bootimg/s281-boot-dtbo-gpu-display-opp148.img
# lectura de vuelta: leer la particion dtbo_a (25165824 B) y comparar con
#   aae3ce4259091c44e4c207a90645f8db80a8fc85a9879fba6b5e4c9faca4fd78
#   (sha del fichero padeado con ceros a 0x1800000)
fastboot set_active a          # SIEMPRE, sin excepcion
# lector ACM armado ANTES del reboot (un solo lector; sin lector el write() del
# kernel bloquea y el diagnostico se pierde)
fastboot reboot
```

Tras el boot: SSH (~20 s) → `dmesg -n 7` → `diag-watch-ssh.sh` por SSH con `setsid`
(el embebido se atasca tras switch_root) → trigger Hyprland-direct a modo **preferido**
(nunca 60 Hz forzado) → **doble captura obligatoria** (ACM + `dmesg` SSH; ACM es lossy).

Medición clave (cero flashes, también válida ANTES con L33 viva):
```
grep -i -E 'byte|dsi' /sys/kernel/debug/clk/clk_summary   # esperado tras F10: 148648750
```

## 7. Tabla de lectura pre-registrada (decidida ANTES del flash)

| Resultado | Lectura |
|---|---|
| `byte_clk` = 148,6 MHz y el SoC pasa de `K48-w4-done` a los 108 DCS | **CONFIRMADO**: el OPP era el asesino |
| `byte_clk` baja a 148,6 pero sigue muriendo en `w4-done` | El OPP era necesario pero no suficiente → siguiente gap (G4 lane map, G8 orden reset/enable, G6 timings) |
| Sigue en 187,5 MHz | El OPP no se aplicó → el nodo que lo consume es otro; parar y re-diagnosticar |

## 8. Riesgos y qué NO se toca

- **NO se toca**: `boot.img` (slot a y b), kernel, initramfs, `userdata`, `misc`/BCB, GPT.
  Solo `dtbo_a`. `boot_b`/`dtbo_b` quedan intactos como red de seguridad.
- Riesgo principal: si el DT resultante no aplicara (p. ej. otro consumidor del OPP), el
  síntoma sería "sigue en 187,5" (fila 3 de la tabla) — recuperable con el rollback del §4.
- Riesgo de proceso: flashear sin batería (gate 3700 + cargador) o sin `set_active a`
  (el ABL caería al slot B). Ambos cubiertos en el preflight.
- La medición de `byte_clk` del vendor (148,648750) viene de logs de Android, no de hardware
  propio; y los "4 parámetros bajo mínimos" son cálculo sobre fórmulas, no medición (§1).
  El flash es barato y reversible precisamente porque la prueba es empírica.
