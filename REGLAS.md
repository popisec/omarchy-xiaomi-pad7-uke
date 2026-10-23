# REGLAS — omarchy-uke (canónico)

> **Este fichero es el que se cita.** El runbook y los informes antiguos hablan de
> "las 15 reglas de ESTADO-VIVO" y de un `REGLAS.md` que no existían (creados el
> 1-oct-2026, hallazgo §8.1 del plan v4). Aquí están todas, agrupadas por de dónde
> vienen y con su coste real ya pagado.
>
> Jerarquía: `docs/historia/AGENTS.md` = contexto y protocolo de notas. `docs/historia/ESTADO-VIVO.md` = estado
> del aparato (cambia cada ciclo). **`REGLAS.md` = las reglas, que no cambian.**
> `F-plan-por-fases.md` = el plan por fases. Informes `A`–`G` = referencia congelada.

## 0. Las cinco que no se negocian

1. **Nunca romper el arranque bueno.** Backup del par antes de cada experimento,
   **sha256 pre-registrado ANTES de flashear**, y verificación por sha256 de la
   lectura vuelta **hasheando al tamaño exacto de la imagen** (96 MiB: así se
   anula el pad de ceros; patrón ledger #241).
2. **Un cambio por ciclo**, con su fila pre-registrada en
   `build/gates/PRE-REGISTRO-PANTALLA.md` y en el ledger del proyecto hermano
   `~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md`.
3. **Semáforo inter-proyecto**: antes de flashear, comprobar que el hermano no
   tiene sesión viva en la tablet (su `ESTADO-ACTUAL.md` + últimas filas del
   ledger). Un solo mecanismo de slot por sesión.
4. **Solo lectura** al inspeccionar, y **un único lector** de `/dev/ttyACM0`.
   ⚠️ **Corrección de 1-oct-2026 (decisión del dueño):** esta regla decía antes
   «**No leer `/dev/ttyACM0`**» y fue un error de lectura. El bloqueo del kernel
   ocurre al **escribir** sin lector, así que **leer es lo que lo previene** y lo
   que hace legible el cuelgue. Queda: **nunca dos lectores a la vez**, y **debe
   haber uno abierto** durante todo el arranque (el 1-oct, no leerlo hizo perder
   el diagnóstico del «zombi» #450). Ver `docs/historia/AGENTS.md`.
5. **La tablet no está para experimentos destructivos**: hay `misc` BCB en
   `reboot-bootloader` y el ext4 arrastra **~908 errores** (medido el 26-sep;
   ver `docs/informes/B-arranque-arch-uke.md`). Antes de
   tocar nada: `e2fsck` en frío + backup + limpiar BCB.

## 1. Método (pagadas por el proyecto hermano — no repetirlas)

Origen: `~/proyectos/ubuntu-permanente/docs/LECCIONES.md` y `REFUTADO.md`
(~56 refutaciones, 37+ rondas). Cada una con su whence para que puedas
verificarla en vez de creérmela.

1. **Gate `fdtoverlay` antes de flashear cualquier `dtbo`**:
   `fdtoverlay -i <base.dtb> -o <merged> <overlay.dtbo>` en verde +
   `build/gates/uke-dtbo-check.py`. Un overlay con un phandle por etiqueta o un
   `__local_fixups__` colgado wedgea el arranque (LECCIONES 35.7/36.2).
2. **`dmesg -n 7` antes de archivar evidencia de `KERN_INFO`**: las
   `UKE-CM3DBG`/`UKE-POKE` son nivel 6 y desaparecen con el nivel por defecto.
   Sin esto se concluye «no hay evidencia» donde hay «fallo».
3. **Nunca instrumentar el SMMU en runtime, nunca volcar rangos de registros
   MMIO/regmap**: cuelga la tablet (LECCIONES ronda 33). Instrumentar **solo en
   el arranque**, que es el momento de verdad.
4. **Doble captura obligatoria antes de declarar algo ausente**: consola ACM
   **y** `ssh … 'dmesg -w' > fichero`. La consola a 115200 **pierde la cola de
   líneas** cuando el reset la corta, y eso ya dio un «sin errores» falso
   (ledger #428 → #429).
5. **`sync` antes de `sysrq-b`/`reboot`**; `/tmp` es tmpfs (las imágenes van a
   `/root`); prohibido `reboot -f` y `systemctl reboot` sin `sync`. Y **un
   "reinicio limpio" no es «hecho» hasta que se confirma por consola/ping que la
   máquina cayó y volvió** (#P49: "Rebooting." a 385 s → congelación a 387 s).
6. **Builds siempre desprendidos** (`setsid nohup … &`) y con `env
   MAKE=/usr/bin/make` / `ARCH=arm64` / `LLVM=1` explícitos: en primer plano el
   `make` es un **no-op silencioso** y un build «OK» vacío es indistinguible de
   uno roto.
7. **`fastboot boot` usa el `dtbo` del slot activo** (REFUTADO R-12): un fallo
   estéril se lee como «el kernel no arranca». Su techo (~64 MiB) no tiene
   fuente primaria.
8. **Los cambios de runtime NO persisten** tras reinicio salvo que se horneen en
   la imagen: el rootfs es ext4 persistente, pero el arranque regenera `/etc`
   (los módulos en `extra/` sí sobreviven).
9. **Cuidado con scripts que borran y no restauran**
   (`uke-wifi-trace.sh:46` borra la blacklist de `ath11k` y no la vuelve a
   poner ⇒ el módulo se autocarga por modalias y **gasta reintentos de slot**;
   pasó en la ronda 10, ledger #441). ⚠️ Ese script **no está en este repo**
   (vive en el árbol externo `~/gpu-work/`); lo que sí está es su efecto medido
   en `build/gates/revision/PIPELINE-PANEL-20261014/WIFI-ESTADO.md`.
10. **Identificar `/dev/sdX` por contenido, no por letra**; gates `[ -f ]` y de
    magia de partición antes de cualquier `dd` (REFUTADO R-49: `dd
    if=<un directorio>` escribe basura).
11. **Antes de hipotetizar, lee `REFUTADO.md` y `LECCIONES.md`** del hermano.
    **Techo de 3 ciclos por hipótesis**: al tercero sin movimiento en `dmesg`, la
    hipótesis se anota como refutada, no se intenta un cuarto flash.
12. **Los decode de registros se comprueban contra el header del driver, no de
    memoria** (1-oct-2026, lección cara: el volcado del CM3 imprimía
    `type = s2cr & 0x3` cuando `S2CR.TYPE` es `GENMASK(17,16)`, y durante dos
    días se leyó un `TRANS` como `BYPASS`; ver `NOTAS-OMARCHY.md` 1-oct).
13. **Una miga que decide una rama tiene que estar flushed antes del write que
    puede colgar** (`uke_poke()` no hace `pr_flush`; desde K23b se añade
    `pr_flush` explícito tras `S3-rst0`).
14. **Nada de instrumentación cuyo resultado no se pueda leer en el sitio
    previsto**: si la evidencia solo sale por `dmesg` y la sesión SSH no llega,
    es como si no existiera (rama C/F del plan v4).
15. **Toda afirmación externa lleva fecha de medición.** Lo que no se re-mida en
    14 días pasa a «caducado» (esto habría evitado el error de `E`: cita de
    terceros de ago-2026 dada por buena el 26-sep).

## 2. Operativas de cada ciclo

- **Batería**: `fastboot getvar battery-voltage` ≥ **3700 mV** para flashear, y
  **cargador de pared** (en fastboot no carga). Registrar mV inicial y final. Si
  fastboot aparece con batería baja: `set_active b` → arrancar el par estable →
  `prepara/uke-adsp-load.sh` + `prepara/bateria.sh --umbral 3700` → fastboot por
  teclas. **Prohibido reintentar slots en fastboot sin mV leído.**
- **Slots**: `fastboot getvar all` (los 4 `slot-retry-count`) antes y después de
  cada flash; todo a **A**, **B = rollback** y no se toca. `set_active a|b`
  sirve como reset de contadores.
- **Consola**: lector **único**, con el patrón **sin `timeout`** (el `timeout 2
  cat` pierde la ventana 3,95–4,18 s, que es justo donde muere el arranque) y
  nodo verificado (`ls /dev/ttyACM*`: re-enumeración = loop ciego).
- **Vigía fastboot**: armado **con pausa** (`touch
  /tmp/uke-fastboot-watch.pause`) mientras se flashea, y `rm -f` solo tras leer
  el desenlace. Sin vigía, un A agotado cae a fastboot sin rescate.
- **e2fsck antes de cada ciclo** con reboots sucios, con el flujo **probado** del
  `docs/historia/RUNBOOK-SIGUIENTE.md` Paso 4 (el §A.2 de `P7-fsck-f9.md` quedó refutado en
  vivo por el ledger #446: journald resucita y sshd muere en el kex con `/` en
  ro). Empezar por `-fn`, montar ro **siempre** con `norecovery`, y tener una
  sesión SSH persistente abierta **antes** del remount.
- **Zombi**: si el userspace muere con el kernel vivo (~280–400 s), **capturar
  primero, fsck después**; no confiar en `systemctl reboot` sin confirmación.
- **Arranques experimentales**: power-cycle en frío mejor que `fastboot reboot`
  (#P17).
- **Presupuesto**: ≤2 escrituras por día y el día se agota por escrito en la
  fila del ledger (ver `docs/historia/PLAN-SIGUIENTE-v4.md` §1/§4 para el conteo real).

## 3. Documentación

- **Todo hallazgo va a fichero, no al chat**: commit + `docs/historia/ESTADO-VIVO.md` +
  entrada fechada en `NOTAS-OMARCHY.md` (qué se hizo, qué se comprobó con
  comando o URL, qué queda pendiente). Si contradice un informe `A`–`G`, se
  corrige el informe.
- **Lo que no se puede perder va en git**: código, informes y **los parches del
  kernel**. Los `.img` de 96 MiB y los árboles de build quedan fuera por su
  peso, pero su reconstrucción tiene que existir: un parche sin diff es
  código perdido (1-oct: K19–K23 vivían solo en un directorio ignorado;
  cerrado con `build/gates/patches/ACUMULADO-*.diff` + `gen-diff-acumulado.py`).
- **Los shas de lo que está en la tablet, en `SHA-BUENOS.txt`**, no solo en el
  chat ni en el informe del ciclo.
- **Nada de "memoria"**: este proyecto no guarda contexto entre sesiones. Si no
  está escrito, no existe.
