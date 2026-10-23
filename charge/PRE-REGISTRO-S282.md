# PRE-REGISTRO s282 — dtbo anti-`qcom,gpr` (SIN flashear, 13-oct-2026)

> Fila lista para pegar en `~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md`
> ANTES de cualquier flash (regla: sha pre-registrado). No flashear sin
> batería ≥ 3700 mV, `slot-retry-count` leído y consola ACM con lector único.

## Artefacto

- Fichero (NO versionado, en `.gitignore` como el resto de `build/bootimg/*.img`):
  `build/bootimg/s282-boot-dtbo-gpu-display-opp148-nogpr.img`
- sha256: `00c3410677eaa15d801024a2e9b0e0213cefd028a4372fee913b4d21eee168d0`
- Tamaño: 607458 B (límite partición dtbo: 0x1800000, sobra sitio)
- Base: `s281-boot-dtbo-gpu-display-opp148.img`
  (`90e41a6b4b91f47451bb18c0518193997604df7362631f7f3946c3ad6481b437`, ya flasheado)
  + UN SOLO fragmento `@2200` (`target-path = "/soc/remoteproc-adsp@03000000/glink-edge/qcom,gpr"`,
  `status = "disabled"`). Constructor versionado: `charge/mkdtbo-s282.py`.
- Informe de construcción: `charge/repack-s282-report.txt`.

## Gates (ambos verdes el 13-oct-2026, salidas en `charge/repack-s282-report.txt`)

1. `fdtoverlay -i base-dtb.img -o merged s282.dtbo` => RC 0 (igual que el ABL).
2. `build/gates/uke-dtbo-check.py s282.img base-dtb.img` => RC 0, `OK: el stack
   display existe en el arbol merged y todas sus referencias resuelven`.
   Nota: el script necesitó un ajuste documentado (perfil táctil `novatek@0`
   en vez de `touchscreen@0`; el s281 ya flasheado fallaba el perfil viejo).
3. Paridad s281 verificada en el merged: OPP DSI {148648750, 187500000,
   300000000, 358000000}, iommus display-controller, bootargs, touch,
   cx-supply del ADSP; canales qrtr/pmic_glink/fastrpc intactos.
4. `gpr status=disabled` en el merged (fdtget).

## Fila propuesta para el ledger

> ### #NNN — PRE-REGISTRO s282 anti-gpr (dtbo, sin flash).
> `s282-boot-dtbo-gpu-display-opp148-nogpr.img` sha256
> `00c34106…ee168d0` (607458 B) = s281 (`90e41a6b…`) + fragment@2200 con el
> nodo `…/glink-edge/qcom,gpr` en `disabled` (trampa #406: apr -22 en bucle).
> Gates: fdtoverlay verde + uke-dtbo-check.py limpio + paridad s281.
> Flash pendiente (slot buddy del s281, con batería ≥ 3700 mV).

## Riesgo específico de ESTE flash

Un dtbo que no aplique deja el gpr vivo y el bucle vuelve (udevd 99 %,
batería). Verificación post-flash obligatoria (en `charge/uke-charge-run.sh`
paso 4 + `fdtget /sys/firmware/devicetree/.../status` del nodo gpr y
`dmesg | grep -c "Domain ID not specified"` = 0).
