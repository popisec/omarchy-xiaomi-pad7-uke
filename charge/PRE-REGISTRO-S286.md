# PRE-REGISTRO s286 — dtbo con UN solo bus I2C, el del KTZ8866 (SIN flashear, 13-oct-2026)

> Fila lista para pegar en `~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md`
> ANTES de cualquier flash (regla: sha pre-registrado). No flashear sin
> batería ≥ 3700 mV, `slot-retry-count` leído y consola ACM con lector único.
> **NO flasheado aún** (construido + gates verdes solo en PC).

## Artefacto

- Fichero (NO versionado, en `.gitignore` como el resto de `build/bootimg/*.img`):
  `build/bootimg/s286-boot-dtbo-gpu-display-gpi-i2c-ktz.img`
- sha256: `33d153f2cec617e2a7c8512559d57a06e1a9c15844b57106ee0891374aa2f419`
- Tamaño: 608530 B (límite partición dtbo: 0x1800000, sobra sitio)
- Base: `s285-boot-dtbo-gpu-display-gpi-only.img`
  (`0b0b16b569e7212bd5f6dfa8a17d43c512a812f9950ca7bcd2084914d181bf06`, flasheado:
  arranca) + UN SOLO fragmento `@2402` (= `@2202` de
  `build/gates/FRAGMENTO-GENI-I2C-DMA.dts`, `target-path =
  "/soc/qcom,qupv3_0_geni_se@ac0000/i2c@a80000"`). Constructor versionado:
  `charge/mkdtbo-s286.py`.
- Informe de construcción: `charge/repack-s286-report.txt`.

## Cambio único (peldaño 6 del auditor)

`s286 = s285 + GPI(intacto) + solo el bus i2c@a80000` (wrapper0 SE0, reg
`0xa80000`, alias stock `qupv3_se0_i2c`). El fragmento pone `compatible =
"qcom,geni-i2c"` + `clock-names = "se"` + `dmas` 3-celdas al GPI `0x1df` de
su wrapper + `dma-names = "tx","rx"`. Efecto: **ese bus probea por primera
vez** y el `ktz8866@11` del panel puede bindear.

## Por qué ESE bus y no otro

1. El `panel.backlight` de s283 resuelve al `ktz8866@11` que vive bajo
   i2c@a80000 (verificado fdtget en el merged m286: `ph == bl`). s286 existe
   para que ese bus probee.
2. Alias stock verificado en esta máquina:
   `build/evidencia/stock-dt/stock2-Cliffs7P-uke.dts:21204` (`qupv3_se0_i2c`
   → ese path).
3. DT vivo Android (`build/evidencia/android-snap/dt-r15`): `ktz8866@11`
   existe bajo i2c@a80000 junto a `wcd939x_i2c@e` (bus probado
   eléctricamente); en base el bus ya está `status="ok"`.
4. Declaración dual documentada (NO bloquea): dt-r15 también trae
   `ktz8866@11` bajo i2c@890000 (`qupv3_se12_i2c`, alias stock2:21232), pero
   el panel NO apunta ahí, en base está `status="disabled"`, y 1-vs-2 chips
   físicos solo lo dirime `i2cdetect se0/se12` en la tablet (pendiente,
   ESTADO-VIVO:147-155). El probe vendor no hace I/O (REV-KTZ8866 §1), así
   que un nodo fantasma es inofensivo; el techo de 1 bus por flash deja se12
   para un peldaño posterior. Efecto colateral: el vecino `wcd939x_i2c@e`
   del mismo bus también verá su driver si existe en mainline (inevitable).

## Evidencia previa

- ÉXITO: s283 arranca (376 KB de log); s285 (s283 + solo GPI) arranca
  (VEREDICTO-WEDGE-AISLADO.md).
- WEDGE: s284 (s283 + GPI + 7 GENI) wedgea a 70 s con 0 B de consola.
- Rollback de ESTE flash: `s285…` = `0b0b16b5…bf06` (mismo par, slot buddy).

## Gates (todos verdes el 13-oct-2026, salidas en `charge/repack-s286-report.txt`)

1. `fdtoverlay -i base-dtb.img -o merged s286.dtbo` => RC 0 (igual que el ABL).
2. Bus del KTZ con fences 1+2+2b: compatible mainline + `clock-names=se` +
   `dma-names=tx,rx` + `dmas` de 8 celdas con phandles al phandle real del
   `gpi-dma@a00000` + proto 3 (I2C) en ambas entradas.
3. GPI intacto de s285 (2/2 `sm6350` + channels + mask) + los otros 6 GENI
   intactos prop por prop + diff exhaustivo libfdt: 4267 nodos, cero cambios
   fuera del bus.
4. Paridad s285: gpr `disabled`, `backlight` resuelto al ktz, OPP DSI
   {148648750, 187500000, 300000000, 358000000}, panel idéntico.
5. `build/gates/uke-dtbo-check.py s286.img base-dtb.img` => RC 0, `OK: el
   stack display existe en el arbol merged y todas sus referencias
   resuelven`. (Nota: se usa la copia local con el perfil táctil
   `novatek@0` de uke; la del proyecto hermano difiere solo en eso.)
6. `dt_table` (1 entrada) + roundtrip `dtbo-extract.py` bit-identico.

## Fila propuesta para el ledger

> ### #NNN — PRE-REGISTRO s286 un-bus-I2C-KTZ (dtbo, sin flash).
> `s286-boot-dtbo-gpu-display-gpi-i2c-ktz.img` sha256
> `33d153f2…2f419` (608530 B) = s285 (`0b0b16b5…`) + fragment@2402 con el
> bus `…/qupv3_0_geni_se@ac0000/i2c@a80000` a mainline (KTZ8866 0x11 del
> panel; se12/i2c@890000 intacto por el techo de 1 bus). Gates: fdtoverlay
> verde + fences GENI + 6 GENI intactos + paridad s285 + uke-dtbo-check.py
> limpio. Flash pendiente (slot buddy del s285, con batería ≥ 3700 mV).

## Riesgo específico de ESTE flash + criterio pasa/falla (auditor §3.6)

Hacer probear un bus I2C por primera vez es lo que (en paquete de 7)
wedgeó s284. Pasa: arranca + `/sys/class/i2c-adapter` no vacío + KTZ une
(`ktz8866@11`). Falla: wedge/0 B ⇒ ese bus aísla el wedge; NO se prueba
otro bus en el mismo día (techo 1 bus por flash). Verificación post-flash:
doble captura (ACM + SSH `dmesg`), `fdtget` del compatible en
`/sys/firmware/devicetree`, `dmesg | grep -i "geni-i2c\|ktz8866"`.
