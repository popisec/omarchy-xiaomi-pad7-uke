# PRE-REGISTRO F3e/L28 — 12-oct · **LA COMBINACIÓN QUE NUNCA SE HA PROBADO**

- **sha256**: `4d818dc5121c2eb9919dae2948ec80a5256f7b9fdc8c534651022be97e278692`
- **Kernel**: el MISMO de L27 (`k52L27-build`, 5 correcciones de fidelidad Android incluidas —
  verificado descomprimiendo el Image: `L27-prev-first-off`, `L27-gpios-hiz`, `L27-vci-absent`,
  `L27-bl-enable`, `L27-rst-twice`, `msm_mdss_reset SALTADO` = 1 cada una)
- **Cmdline**: 592 B = L19 (580) **− ` video=DSI-1:d`** + ` msm.uke_skip_mdss_reset=1`
- ✅ `video=DSI-1:d` AUSENTE · ✅ skip presente · ✅ sin herencia

## Por qué este es el ciclo decisivo

| | Orden correcto (`prepare_prev_first=false`) | Orden invertido (`=true`) |
|---|---|---|
| **con `:d`** | L25, **L27** ✅ viven | — |
| **sin `:d`** | **← L28, NUNCA PROBADO** | L26 ✗ murió a 4,03 s |

L26 murió al quitar `:d` **pero con el orden invertido**. L27 corrigió el orden pero mantuvo `:d`
(a propósito). **L28 combina ambas correcciones**: por fin un `prepare` real con clocks/PHY/host
antes de rails, y el reset ya no asertado desde el probe.

## Tabla de lectura

| Resultado | Lectura |
|---|---|
| **Imagen + log vivo** | El **orden** era el bloqueo ⇒ **panel encendido en mainline**. Primer display real |
| `K47-pan-prep`>0, `K47-pan-pwron-ok`=0 | Los rails no levantan (vci/L19 ausente + orden) ⇒ el problema es alimentación, no orden |
| `K47-pan-prep`>0, negro, vivo | El prepare corrió bien pero el TDDI no enciende ⇒ problema en el link, no en el orden |
| **Wedge con `K47-pan-pwron`>0** | Muerte DENTRO de `o82_power_on`/`o82_reset` (fenómeno B). Las migas dicen en qué rail |
| Wedge antes de `K47-pan-prep` | El bind/modeset con conector habilitado sigue matando ⇒ siguiente puerta: gatear `dpu_runtime_resume` |

## Medición

**Sólo por SSH (`dmesg`).** El ACM pierde la ventana 0,5–4,0 s (probado: L27 tampoco trae esas
migas en ACM). Regla 4: doble captura obligatoria.

## Recuperación

```
fastboot flash boot_a build/bootimg/boot-uke-k52L25.img   # sha 04cd49803b9a…
fastboot set_active a ; fastboot reboot
```
