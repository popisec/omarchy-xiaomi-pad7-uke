# DECISIÓN PENDIENTE: tamaño de `misc` y de la imagen de limpieza del BCB

Fecha: 28-sep-2026. Estado: **pendiente de medición en el aparato. No se ha flasheado nada.**
Local: sin tablet, sin flash, sin dd (ver §5).

## 1. El problema: dos números distintos que el plan confunde

Hay DOS magnitudes distintas y los documentos las mezclan:

- **(a) Tamaño de la PARTICIÓN `misc`** (`sda12`): **4 MB / 4 MiB**.
- **(b) Tamaño de la IMAGEN de limpieza** (ceros a flashear): **8192 B**.

Citas verificadas (línea exacta a 28-sep-2026):

| Fuente | Dice |
|---|---|
| `docs/informes/B-arranque-arch-uke.md:36` | Partición: "`misc` (`sda12`, 4 MB)" |
| `docs/informes/B-arranque-arch-uke.md:403` | Partición: "`misc` (`sda12`, 4 MB) contiene el Bootloader Control Block" |
| `docs/informes/B-arranque-arch-uke.md:1133` | Partición: tabla "`misc` \| `sda12` \| 4 MiB" |
| `docs/informes/B-arranque-arch-uke.md:414` | Imagen: "**`misc.img` son 8192 B de ceros**" |
| `docs/informes/B-arranque-arch-uke.md:875` | Imagen: "`fastboot flash misc misc-zeros.img # 8192 B de ceros (misc.img de la ROM = ceros)`" |
| `docs/informes/B-arranque-arch-uke.md:1185` | Riesgo 4: "Limpiar `misc` a ceros (8192 B)" |
| `docs/informes/B-arranque-arch-uke.md:874` | **Contradicción interna de B**: "`dd if=/dev/zero of=/dev/block/by-name/misc bs=4096 count=1`" = **4096 B**, la mitad de los 8192 B de la línea siguiente (:875) |

Imprecisiones de `F-plan-por-fases.md` (verificadas):

- `F-plan-por-fases.md:233`: "`bcb-clean.bin` | 2048 B, y B §4.5 dice que `misc` son **8192 B** ⇒ **el artefacto es la mitad**". Doble error: (i) B §4.5 dice que la **imagen** es 8192 B y la **partición** 4 MB, no que "misc son 8192 B"; (ii) 2048 B no es la mitad de 8192 B, es la **cuarta parte** (2048 × 4 = 8192).
- `F-plan-por-fases.md:235-239` ("La trampa de F0"): "B §4.5 documenta que la partición `misc` son **8192 B**". Falso: B documenta la partición como 4 MB (:36, :403, :1133). Lo que B cifra en 8192 B es la imagen de ceros.
- `F-plan-por-fases.md:1429` (tabla resumen F0): repite la confusión ("la partición son 8192").
- `F-plan-por-fases.md:276-283` (F0 paso 3) pide medir el tamaño real en el aparato y aun así genera con `count=8` (8192 B) sin esperar a la medida; `F-plan-por-fases.md:304` (F0 paso 6) fija el flash en "el fichero de 8192 B".

Artefactos existentes (medidos 28-sep-2026):

- `build/misc-zeros-4m.img`: **4194304 B, todo ceros**, sha256 `bb9f8df61474d25e71fa00722318cd387396ca1736605e1248821cc0de3d3af8` (variante "partición entera").
- `build/gates/misc-zeros-8192.img`: **8192 B**, sha256 `9f1dcbc35c350d6027f98be0f5c8b43b42ca52b7604459c0c42be3aa88913d47` (generado por `build/gates/bcb-clean-8192.py`).
- `~/gpu-work/bcb-clean.bin`: **2048 B** de ceros, **ningún script lo usa**. No flashearlo: escribir 2048 B y dar por limpio el BCB deja el resto intacto con falsa sensación de arreglo.

## 2. Por qué importa: flashear 8192 B en 4 MiB deja el resto intacto

`fastboot flash misc <img>` escribe exactamente `len(img)` bytes al inicio de la partición y **no toca el resto**. Si la partición mide 4 MiB y se flashean 8192 B, quedan 4 MiB − 8 KiB con el contenido viejo.

Hoy eso parece inocuo porque el campo que decide es `command[0:32]` (offset 0, cubierto por cualquier opción) y el BCB medido es `"reboot-bootloader"` ahí (`B:403-404`, lectura de 4 KiB). El riesgo es el caso no cubierto: si este ABL —del que ya consta que **no implementa `bootonce-*` y nunca limpia el BCB** (`B:407-413`)— lee cualquier otro campo del bloque más allá del offset 8192 (recovery, status, campos vendor), el BCB viejo seguiría vivo después de una limpieza "exitosa" según el criterio de relectura de 4 KiB (`B:877`, `F:304`), porque ese criterio solo mira los primeros 4 KiB. Es el mismo patrón que la trampa del fichero de 2048 B, una escala mayor: verificar solo lo escrito y declarar limpio lo no mirado.

## 3. Qué hay que MEDIR en el aparato antes de decidir (solo lectura)

Las tres, por SSH con la tablet arrancada (canal que funciona; `adb` no existe allí, `fastboot fetch` no verificado):

```bash
ls -l /dev/disk/by-partlabel/misc
blockdev --getsize64 /dev/disk/by-partlabel/misc
dd if=/dev/disk/by-partlabel/misc bs=4096 count=1 2>/dev/null | od -A d -t x1z | head -8
# o el equivalente que ya usó B: leer command[0:32] con Python (B:403-404)
```

Qué decide cada una:

1. `ls -l …/misc` — **identidad, no tamaño**: resuelve la etiqueta al `sdX` real. Decide que estamos midiendo `misc` y no otra partición (letras `sdX` inestables entre arranques; REFUTADO R-49). Sin esto, las otras dos medidas no valen.
2. `blockdev --getsize64` — **tamaño exacto de la partición en bytes**. Decide entre las opciones del §4: si da `4194304`, el artefacto de 4 MiB encaja al byte y la opción (b) es viable; si da otro valor, ambas imágenes hay que regenerarlas y el 8192 queda sin ancla.
3. Volcado de los primeros bytes / `command[0:32]` — **estado del BCB hoy**. Decide si la limpieza sigue pendiente (¿sigue `"reboot-bootloader"`?) y localiza el campo que manda; además fija la referencia contra la que se comparará la relectura post-limpieza (criterio de hecho de F0 paso 6).

Ninguna escribe nada: las tres son lectura.

## 4. Las tres opciones, con coste y riesgo

- **(a) Flashear 8192 B de ceros** (`build/gates/misc-zeros-8192.img`). Coste: un flash pequeño, dentro del presupuesto normal de un ciclo. Riesgo: deja 4 MiB − 8 KiB con el BCB viejo (§2); si el ABL lee más allá del offset 8192, la limpieza es aparente. Es la opción que el plan da por hecha sin haber medido.
- **(b) Flashear los 4 MiB enteros** (`build/misc-zeros-4m.img`, ya generado y verificado todo-ceros). Coste: un flash de 4 MiB — trivial frente a los 96 MiB de un `boot` (el tamaño no es objeción: fastboot mueve imágenes mucho mayores a diario). Riesgo: el normal de cualquier escritura (presupuesto: batería ≥ 3700 mV, contadores de slot, fila de ledger pre-registrada, consola + vigía). Ventaja: elimina la pregunta entera — no hay "resto" que auditar ni campo sin mirar.
- **(c) Limpieza in situ con `dd` sobre la partición** (`dd if=/dev/zero of=/dev/block/by-name/misc …` desde la tablet). Coste: cero flashes fastboot, pero exige el tamaño exacto (`count`) medido en el §3: con `count` de menos deja resto sucio, con `count` de más se escribe fuera de la partición. Riesgo: un `dd` con `of=` equivocado o `count` mal calculado es el error clásico de este proyecto (R-49, R-12); además B se contradice a sí mismo aquí (:874 dice 4096 B, :875 dice 8192 B), así que la receta de B no se puede seguir a ciegas.

**Recomendación: (b), 4 MiB enteros, tras confirmar con `blockdev` que la partición mide 4194304 B.** Razón: es la única opción que no depende de saber hasta qué offset lee el ABL —dato que no tenemos y que el plan nunca midió— y su coste (un flash de 4 MB) es despreciable frente al riesgo que elimina. Si `blockdev` diera otro tamaño, regenerar el artefacto al tamaño medido y mantener (b). Solo si el flash estuviera vetado por presupuesto (contadores bajos, batería) usar (c) con `count` calculado del `blockdev` medido, nunca con los números de B. La opción (a) queda como fallback documentado, no como defecto.

## 5. Estado: nada flasheado, F0 paso 6 pendiente

A 28-sep-2026 **no se ha escrito `misc`**: el semáforo del proyecto hermano (`docs/historia/ESTADO-VIVO.md`, ledger #444) registra que ni ellos ni este proyecto han tocado `misc`, y esta sesión ha sido solo lectura (sin tablet, sin flash, sin dd). **F0 paso 6 (limpiar el BCB y releer) sigue pendiente**, bloqueado por la medición del §3 y por esta decisión.

## 6. De dónde sale el 8192 y por qué el gate lo vigila

El número 8192 **sale del plan, no de una medición del aparato**: B lo afirma (`misc.img` de la ROM, :414/:875) pero la única lectura documentada en el dispositivo es de 4 KiB para `command[0:32]` (:403-404), que no mide ni la partición ni valida el 8192. Por eso `build/gates/bcb-clean-8192.py` —que genera la imagen de 8192 B— incluye un gate que relee la sección F0 del plan y **aborta si el plan deja de declarar 8192**: su supuesto es "el plan dice 8192", y si el plan cambia (p. ej. tras aceptar esta decisión e ir a 4 MiB), el script debe abortar en vez de generar un artefacto con una premisa caducada. Cuando se resuelva esta decisión a favor de (b), ese script y sus referencias en F0 deberán actualizarse o retirarse en consecuencia.
