# Omarchy en la Xiaomi Pad 7 «uke» (SM7675, aarch64)

Instrucciones para cualquier sesión de opencode abierta en este directorio.

> 🔌 **CONEXIÓN POR WIFI (20-oct-2026):** la tablet está en Tailscale: `ssh -i build/rootfs/uke-arch-root -o BatchMode=yes root@uke`
> (100.64.0.10, IP anonimizada). Úsala por defecto; el USB de abajo queda como respaldo (y para fastboot/consola ACM). Ver `build/rootfs/deploy/tailscale/`.
>
> ⚠️ **CONEXIÓN (corregido 12-oct-2026).** La vía real es **RNDIS sobre USB a `192.168.42.129`**:
> `ssh -i build/rootfs/uke-arch-root -o BatchMode=yes root@192.168.42.129`. La IP de mDNS que citaba
> este fichero **caducó** (la red pasó a `192.168.0.x`; el PC está en `192.0.2.10/24`).
>
> ⚠️ **ESTADO DEL APARATO: SOLO `docs/historia/ESTADO-VIVO.md` MANDA.** Los pares «buenos»/vigentes citados en
> este fichero (y en el README) son HISTÓRICOS (era s244-bounce, 26-sep). El par en la
> tablet cambia con cada flash del proyecto: al empezar, lee `docs/historia/ESTADO-VIVO.md` y las últimas
> filas de `build/gates/PRE-REGISTRO-PANTALLA.md`; las copias del par vigente están en
> `build/backup-par-bueno/` con shas en `build/gates/SHA-BUENOS.txt`. Los scripts `bin/…`
> citados viven en `~/proyectos/ubuntu-permanente/bin/` (proyecto hermano, solo lectura).

## Qué es este proyecto

Llevar **Omarchy** (Arch + Hyprland 0.56 + shell Quickshell) a la tablet **uke**, en
x86→aarch64, sobre el kernel mainline `7.2.9-senemos` (árbol base
[MCC45TR/senemos-uke-kernel-mainline](https://github.com/MCC45TR/senemos-uke-kernel-mainline) +
parches propios) y arrancando por `boot.img` de
Android (slots A/B). pmOS queda como **referencia técnica y red de seguridad**, no como
destino. La vía buena es el repo `edge/aarch64` de Omarchy (148 paquetes, ya incluye
`omarchy-4.0.4-1` el 26-sep; desde el 22-oct la tablet corre `omarchy 4.0.6-1`); **`stable/aarch64` da 404** para el paquete de escritorio.

**Ya se ejecuta en la tablet**: el port está en marcha y lo que funciona está medido en
[`docs/historia/ESTADO-VIVO.md`](docs/historia/ESTADO-VIVO.md) (arranque de Arch desde `boot_b`, escritorio Omarchy, panel,
táctil, lápiz, WiFi, BT, audio, batería, cámaras). Este fichero se quedó congelado en el arranque
del proyecto y su «mapa de documentos» describe el estado del 26-sep: **no lo uses como estado
actual**. Para el estado de hoy manda `docs/historia/ESTADO-VIVO.md`; para el plan, `F`; para el índice, `G`.

⚠️ El proyecto de origen `~/proyectos/ubuntu-permanente` sigue trabajando en la tablet: antes de
tocarla, comprueba su `ESTADO-ACTUAL.md` y las últimas entradas de su ledger (regla 3 de
[`REGLAS.md`](REGLAS.md)).

## Mapa de documentos

| Fichero | KB | Contenido |
|---|---|---|
| `docs/informes/A-port-omarchy-aarch64.md` | 59 | Qué recompilar/parchear para aarch64; el árbol de Omarchy es agnóstico de arquitectura |
| `docs/informes/B-arranque-arch-uke.md` | 95 | initramfs, cmdline `rdinit`, BCB, contador de slots, sin UEFI/Limine |
| `docs/informes/C-hyprland-quickshell-aarch64.md` | 64 | Hyprland con API Lua, Quickshell, shell en aarch64, Adreno 732 |
| `docs/informes/D-capa-tablet-fallback.md` | 67 | Qué de `texp-*` (Bash/Python + `hyprctl`) funciona sin el shell de Omarchy |
| `docs/informes/E-paquetes-aarch64-soc.md` | 42 | `pacman`/AUR en la tablet: kernel, firmware WCN6750 + gen71100, mesa/freedreno, libwacom, qbootctl |
| `F-plan-por-fases.md` | 132 | **El plan ejecutable**: F0–F8 con criterio de «hecho» medible, camino crítico, 32 riesgos, 20 decisiones del dueño (D1–D20) |
| `docs/historia/G-auditoria-documental.md` | 48 | **Índice maestro**: inventario, contradicciones verificadas en vivo, cobertura temática, huecos y los 17 arreglos de §6 (12 aplicados) |
| `NOTAS-OMARCHY.md` | — | **Bitácora viva de hallazgos de las sesiones** (léelo primero, actualízalo al terminar) |

Los **7 informes (A–G) están cerrados** (26-sep; ya no hay segunda copia que comparar por md5, ver «Contexto externo»). Pendientes
de escribir (huecos declarados por `G`): `H-backup-restauracion-uke.md`,
`I-lapiz-uke.md` (NT36532 → kernel → libinput → libwacom → Hyprland tablet-v2 → app) y la
parte operativa de recuperación fastboot/brick.

**Al empezar una tarea de ejecución, lee `F` primero**: es el plan con el orden y los criterios
de «hecho». **`G` es el índice maestro**: si buscas algo, empieza por ahí. Ojo con `G §3.1`,
que **corrige a `E`** en el punto del repo `edge` vs `stable`.

## Reglas de trabajo (no negociables)

- **Nunca romper el arranque bueno.** Todo experimento con backup del par, **sha256
  pre-registrado en el ledger ANTES de flashear** y verificación por sha256 de lectura vuelta
  **hasheando al tamaño exacto de la imagen** (anula el pad de ceros de los 96 MB; patrón
  ledger #241).
- **La tablet no está para experimentos destructivos**: hay `misc` BCB en
  `reboot-bootloader`, ext4 con ~908 errores (medido 26-sep) y no carga en fastboot. Antes de tocar nada:
  `e2fsck` en frío + backup + limpiar BCB.
- **Solo lectura** al inspeccionar la tablet. `/dev/ttyACM0`: **un solo lector a la vez**, y en
  modo lectura es **imprescindible** tener uno abierto (si el buffer se llena, los `write()` del
  kernel se bloquean y el cuelgue no se puede ni registrar).
  > **Corrección 1-oct-2026 (decisión del dueño).** Esta regla decía antes "**No leer
  > `/dev/ttyACM0`**", y el 1-oct bloqueó con ella justo cuando la tablet arrancaba sin
  > levantar sshd (el "zombi" #450): **no leer la consola es lo que hace perder el diagnóstico**.
  > La prohibición era una lectura equivocada de su propio motivo: el bloqueo del kernel ocurre
  > al **escribir** sin lector, así que **leer es lo que lo previene**. Queda: **nunca dos lectores
  > a la vez** y nunca dejar la sesión sin lector durante un arranque.
- **Un cambio por ciclo**, con fila pre-registrada en el ledger del proyecto de origen
  (`~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md`).
- ⚠️ **Semáforo inter-proyecto**: antes de flashear, comprobar si el proyecto de origen tiene una
  sesión viva en la tablet (su `ESTADO-ACTUAL.md` + últimas entradas del ledger). Un solo
  mecanismo de slot por sesión.
- **Todo hallazgo con URL o con evidencia del dispositivo. Nada de memoria.**
- **Nunca versionar binarios del fabricante** (firmware `.mdt/.bNN/.mbn/.bin`, `.ko`/`.so`/ejecutables de Android, imágenes
  de particiones, ACDB): van a carpetas ignoradas o a `~/backups/`, citados por sha256. El 20-oct-2026 se sacaron 223 que se
  habían colado (copia en `~/backups/uke-vendor-blobs-20261020/`); siguen en el historial antiguo: **no publicar el repo tal cual**.

### Reglas de método pagadas por el proyecto hermano (añadidas 27-sep-2026)

Estas costaron ciclos reales en `~/proyectos/ubuntu-permanente`. **No las repitas.** Cada una con su
origen para que puedas verificarla:

1. **Gate `fdtoverlay` antes de flashear cualquier `dtbo`**: `fdtoverlay -i <base.dtb> -o <merged>
   <overlay.dtbo>` en verde, y `bin/uke-dtbo-check.py`. Un overlay con un phandle por etiqueta o un
   `__local_fixups__` colgado wedgea el arranque (LECCIONES.md ronda 35.7/36.2).
2. **`dmesg -n 7` antes de cualquier evidencia de KERN_INFO**: los `UKE-CM3DBG` son nivel 6 y
   desaparecen con el nivel por defecto. Sin esto se concluye «no hay evidencia» en vez de «fallo».
3. **Nunca instrumentar SMMU en runtime, nunca volcar rangos de registros de MMIO/regmap**:
   cuelga la tablet (LECCIONES.md ronda 33). Instrumentar solo en el arranque.
4. **Doble captura obligatoria antes de declarar algo ausente**: consola ACM **y**
   `ssh … 'dmesg -w' > fichero`. La consola a 115200 **pierde la cola de líneas** cuando el reset la
   corta, y eso ya produjo un «sin errores» falso (ledger #428 → #429).
5. **`sync` antes de `sysrq-b`/`reboot`**; `/tmp` es tmpfs (las imágenes van a `/root`); prohibido
   `reboot -f` y `systemctl reboot` sin sync.
6. **Builds siempre desprendidos** (`setsid nohup … &`) y con `env MAKE=/usr/bin/make` / `ARCH=`
   explícitos: en primer plano el `make` es un **no-op silencioso** y un build «OK» vacío es
   indistinguible.
7. **`fastboot boot` usa el `dtbo` del slot activo** (REFUTADO R-12): un fallo estéril se leerá
   como «el kernel no arranca». Y su techo real (~64 MiB) no tiene fuente primaria.
8. **Cambios de runtime en la tablet NO persisten** tras reinicio salvo que hornees en la imagen
   (el rootfs es ext4 persistente, pero los cambios en `/etc` los revierte el arranque si el
   sistema los regenera; y los módulos en `extra/` sí sobreviven).
9. **Cuidado con scripts que borran cosas y no las restauran** (`uke-wifi-trace.sh:46` borra la
   blacklist de ath11k y no la vuelve a poner ⇒ el módulo se autocarga por modalias y **gasta
   reintentos de slot**; pasó en la ronda 10, ledger #441).
10. **Identificar `/dev/sdX` por contenido, no por letra**; gates `[ -f ]` y de magia de partición
    antes de cualquier `dd` (REFUTADO R-49: `dd if=<un directorio>` escribe basura).
11. **Antes de hipotetizar, lee `REFUTADO.md` y `LECCIONES.md`** del proyecto hermano: ya hay ~56
    refutaciones y 37+ rondas. **Techo de 3 ciclos por hipótesis**: al tercero sin movimiento en
    `dmesg`, la hipótesis se anota como refutada, no se intenta un cuarto flash.

### Presupuesto de operación (gate por ciclo, añadido 27-sep-2026)

Un ciclo **no** es gratis. Antes de la primera escritura de cada sesión, y en la fila del ledger:

- **Batería**: `fastboot getvar battery-voltage` ≥ **3700 mV** para flashear; con el display
  experimental, **cargador de pared** (en fastboot no carga); registrar mV inicial y final.
- **Slots**: leer y registrar `fastboot getvar all` (los 4 `slot-retry-count`) antes y después;
  **≤ 2 escrituras por día**; si `slot-retry-count:b` < 3, ese día solo lectura.
- **Consola**: `bin/uke-console-cap.sh` armado **antes** del flash + el vigía
  `bin/uke-fastboot-watch.sh` apuntando al par bueno (`s244-bounce` + `s229`), con
  `touch /tmp/uke-fastboot-watch.pause` mientras flashes y `rm -f` al terminar.
- **Red de recuperación**: el watchdog del `s229` **no está arreglado** (R-42) ⇒ un cuelgue del
  CM3 exige reset físico. **No cuentes con recuperación automática.**

## Protocolo de notas (obligatorio)

Este proyecto no guarda memoria entre sesiones; el knowledge vive en los ficheros. Al
**empezar** una tarea: lee `docs/historia/ESTADO-VIVO.md`, `NOTAS-OMARCHY.md` y el informe(s) implicado(s)
antes de proponer nada. Al **terminar**:

1. **Commit**. Todo cambio va con commit y mensaje que diga qué se corrigió y con qué
   evidencia. El repo se inicializó el 27-sep-2026 y **esta carpeta es la única copia**: no
   hay taller remoto ni sincronización por `md5sum` entre máquinas (G §5.2 queda obsoleto).
2. Actualiza `docs/historia/ESTADO-VIVO.md` (una página: par vigente, slot, mV, última entrada del ledger
   del proyecto de origen, próximos 3 pasos). Es el **único fichero que se edita a menudo**.
3. Añade una entrada fechada en `NOTAS-OMARCHY.md` con: qué se hizo, qué se comprobó
   (comando + salida o URL), qué quedó pendiente.
4. Si el hallazgo contradice algo escrito en un informe `A`–`G`, **corrige el informe** y
   anótalo en la bitácora; no lo dejes solo en el chat. Los arreglos que `G §6` dejó
   pendientes se marcan como aplicados **en el propio `G §6`** (o se añade una sección
   «arreglos aplicados»). **Aplicados a 27-sep-2026: 1–11, 14.**
5. Si algo es hipótesis no verificada, márcalo como tal en la entrada.
6. **Toda afirmación externa lleva fecha de medición.** Lo que no se re-mida en 14 días pasa
   a «caducado». Esto habría evitado el error de `E` (cita de terceros de ago-2026 dada por
   buena el 26-sep).

### Informes A–G: congelados

Desde el 27-sep-2026 los informes `A`–`G` son **material de referencia, no documentos vivos**.
No se editan para añadir hallazgos: se corrigen **solo** erratas factuales (con commit que
cite la evidencia) o se anota la corrección en `NOTAS-OMARCHY.md` y en el propio informe con
un aviso al principio. El estado que manda es `docs/historia/ESTADO-VIVO.md` + `F` (que es lo ejecutable).

## Contexto externo (no está aquí)

- **Todo vive en esta carpeta.** No hay taller de investigación remoto, ni segunda copia, ni
  sincronización entre máquinas: se trabaja y se versiona aquí con git.
- ⚠️ **Documentación base heredada: NO disponible.** Los informes A–G citan `tablet-lapiz-2026/`
  (portabilidad, lápiz, escritorios, distros ARM, dotfiles de Omarchy), pero **esa carpeta no existe
  en esta máquina** (comprobado 27-sep-2026). No cuentes con ella: lo que hay es el proyecto hermano.
- Historia de la tablet en esta máquina: `~/proyectos/ubuntu-permanente/` (estado vivo, 18
  ficheros en `docs/`) y `~/proyectos/ubuntu-uke/` (archivo de intentos de arranque).
- Rama de GPU/SMMU: `~/gpu-work/`.
