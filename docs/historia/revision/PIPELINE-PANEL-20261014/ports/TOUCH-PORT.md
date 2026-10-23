# TOUCH-PORT — porte del táctil NT36532 a k52-L16-tree (15-oct-2026, sin tablet, sin tocar el árbol)

## 1. Fuentes (todas re-medidas hoy; autor/repo/commit, GPL)

- Senemos kernel `MCC45TR/senemos-uke-kernel-mainline` (GPL; HEAD `fe53eb0b5707`, 15-oct-2026):
  `patches/7.2.10/` (40 parches, ninguno de táctil), `configs/uke.config` (56 lín: sin
  `INPUT_TOUCHSCREEN`, solo `PINCTRL_CLIFFS=y`+`INPUT_UINPUT=m`), `src/boot/` (sin DTS de
  táctil; `sm7675-uke-pinctrl.dtsi` solo retoca `qupv3_se3`+fs19xx). **Conclusión: senemos
  NO tiene nada portable de táctil salvo 0003 (TLMM, ya lo tenemos) y 0017 (abajo).**
  Su "táctil 🟢" corre en el kernel Fedora/COPR 7.2.9-1.39 (`MCC45TR/uke-linux`, tabla HW
  15-oct-2026; "test records are private" = sin logs públicos).
- `MCC45TR/senemos.../patches/7.2.10/0003-cliffs-tlmm.patch` (TLMM cliffs, GPL Qualcomm;
  nuestro `pinctrl-cliffs.c` ya lo trae) y `0017-cliffs-gpio-function-flag.patch`
  (`FUNCTION(gpio)`→`MSM_GPIO_PIN_FUNCTION(gpio)`; fix del double-claim gpio119 WCD939x).
- Donante `linuxgamer/uke-fedora` (GPL): `references/archive/palawan-7.2/kernel/files/
  nt36532-uke.c` (742 lín, draft sin validar HW) + nodo táctil en `.../kernel/files/
  sm7675-xiaomi-uke.dts` (≈lín. 660: `compatible="novatek,NVT-ts"`, LEVEL_LOW, 10 MHz,
  supplies L22B/L8B, `firmware-name=..._csot.bin`). Su `kernel/configs/uke.config` usa
  `GOODIX_BERLIN_SPI=m` y conserva el DTBO stock (nodos `novatek@0`+`goodix-berlin@0`).
- Nuestro lado: `docs/historia/revision/REV-TACTIL-20261005.md` (DT vivo vendor + driver propio verificado vs
  `nt36532_touch.ko`), `fase4-touch.dts` (staging hermano `~/gpu-work/ramaa/s21/dtbo-gpu/`,
  solo lectura: IRQ RISING verificado vs flags `0x2001` del .ko, bus QUP0-SE4 + fixes).

## 2. Qué tenemos / qué falta

| Pieza | Nuestro estado | Origen del dato |
|---|---|---|
| Driver NT36532 SPI | ✅ `novatek-nt36xxx-spi.c` (657 lín, `NT36XXX_SPI=y` en k52L64:3163) | árbol (leído) |
| Donante nt36532-uke.c | ❌ NO portar: EVENT_BUF `0x2FE00`≠verificado `0x125800`, pide fw+supplies que el nodo vendor no tiene, compatible `novatek,NVT-ts`≠nuestro driver | comparativa hoy |
| Nodo DT táctil | ❌ falta (`xiaomi-uke.dts:533` dice "driver por portar": desfasado) | árbol (leído) |
| IRQ gpio54 | ❌ falta en DT (vendor usa `novatek,irq-gpio`; sin `interrupts` ⇒ `spi->irq=0` ⇒ "no IRQ specified") | REV-TACTIL §1-3 |
| Pinctrl bus 16-19 | ✅ `qup_spi4_*` de palawan.dtsi = vendor pin a pin | REV-TACTIL §2 |
| Flag gpio 0017 | ❌ falta (`FUNCTION(gpio)` en `pinctrl-cliffs.c:1571`; macro existe en `pinctrl-msm.h:32`) | diff hoy |

## 3. Parche `ports/0001-touch-nt36532.patch` (hunk a hunk; dry-run RC=0, DTS compila con dtc)

- H1 `pinctrl-cliffs.c`: `FUNCTION(gpio)`→`MSM_GPIO_PIN_FUNCTION(gpio)` = porte literal de
  senemos 0017 (1 línea; permite coexistir estado pinctrl-gpio con consumidor GPIO).
- H2 `xiaomi-uke.dts` comentario: retira el TODO desfasado ("driver por portar…nt36672a").
- H3 `xiaomi-uke.dts` `&spi4{…touchscreen@0}`: espejo del nodo vendor (compatible/CS/19.2 MHz
  exactos), `interrupts-extended=<&tlmm 54 EDGE_RISING>` (0x2001 del .ko = ONESHOT+RISING;
  REV-TACTIL proponía FALLING: queda como alternativa de 1 línea), size 2136x3200 (dmesg
  vendor), sin reset/supplies (TDDI, opcionales en el driver), cero pinctrl nuevo.
  Verificado: `dtc` exit 0 (solo warnings preexistentes) y el `.dtb` trae el nodo con
  `interrupts-extended=<0x6d 0x36 0x1>`, sizes `0x858/0xc80`.

## 4. Plan de test (tras display; TDDI exige panel alimentado)

1. Aplicar (`patch -p1`, es el inverso del dry-run ya verde), build desprendido, 1 flash con
   ledger+sha pre-registrado (presupuesto: ≥3700 mV, ≤2 escrituras/día). 2. `dmesg|grep -i
   nt36` → esperar `probe ok: irq …`; `cat /proc/bus/input/devices` → `Novatek NT36xxx`;
   `evtest` 1 dedo en esquinas + `point_layout` 0/1/2. 3. Criterio: 10 slots MT con eventos
   independientes (referencia: tabla HW senemos 14-oct). Si IRQ muda → re-flash con FALLING.
   NOTA DE RUTA: con DTBO derivado del vendor el nodo vivo lo aporta el DTBO; el fix en esa
   ruta es el overlay `fase4-touch.dts` (ya existe en staging hermano, sin probar en HW).

## 5. Riesgos + rollback

1. Layout de dedo sin verificar (único unknown gordo; mitigado con `point_layout`). 2. Polaridad
   IRQ (RISING vs FALLING; 1 línea, 1 ciclo). 3. Flash TDDI muda = fw de flash corrupta (fase 2:
   portar updater + `novatek_nt36532_o82_fw_csot.bin` de `/odm/firmware`). 4. Hallazgo lateral
   (NO portado, fuera de ámbito): `palawan.dtsi:3870` declara `tlmm@pinctrl@f100000` con
   `qcom,palawan-tlmm`, pero el HW es `f000000`+`qcom,cliffs-pinctrl` (stock2 DT lín. 7664);
   si el DT nativo llega a arrancar, el gpiochip no bindea. Rollback: revertir el parche
   (`patch -R`), el driver queda compiled-in pero sin nodo no hace nada; slot bueno intacto.
