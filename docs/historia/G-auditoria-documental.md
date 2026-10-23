# G — Auditoría documental del proyecto Omarchy «uke» + índice maestro

> 🔴 **INFORME CONGELADO — 27-sep-2026. Actualizaciones posteriores:**
> - **§5.2 (integridad entre copias) y §5.1 (rutas de SERVIDOR-01) quedan ANULADOS**: el proyecto
>   pasa a **copia única con git** en `~/proyectos/omarchy-uke/`. No hay taller remoto, ni segunda
>   copia, ni `md5sum` por SSH. Las rutas `/home/USUARIO/...` citadas en este informe **no existen**
>   para el proyecto. **Peor: los documentos base tampoco están en esta máquina**
>   (`~/proyectos/tablet-lapiz-2026/` no existe aquí, comprobado el 27-sep-2026) ⇒ **A–G citan
>   material que aquí no se puede abrir.**
> - **§6: arreglos 1–11 y 14 APLICADOS** (ver `NOTAS-OMARCHY.md`, entrada del 27-sep-2026).
>   Pendientes: 12, 13, 15, 16, 17.
> - **Addendum 28-sep-2026 (§1-bis, §2-bis, §3.7, §4-bis, §6-ter):** el índice se pone al día con el
>   cierre del 28-sep (F9, s251 inocente, `unlocked: yes`, r10e 4/4, s252/CM3/BCB). Los informes A–G
>   siguen congelados: lo nuevo va en addenda fechados, no reescribiendo lo del 27-sep.
> - El estado que manda ahora es **`docs/historia/ESTADO-VIVO.md`** y `F-plan-por-fases.md`, no este informe.
> - Se han escrito correcciones adicionales que este informe no anticipaba: el **chip ID de la GPU**
>   (`find_chipid()` parsea el DT, no el silicio) y el **`CONFIG_QCOM_PD_MAPPER` in-kernel**.

**Fecha:** 26-sep-2026 (Europe/Madrid) · **Método:** lectura en disco de los ficheros, extracción
programática de métricas (líneas, URLs, marcadores «no verificado», tablas de fuentes), **comprobación
en vivo con `curl`/`tar`** de las afirmaciones sobre `pkgs.omarchy.org`, y contraste de lo que existe
en la máquina de trabajo. **Nada investigado en internet**; cada cifra sale de un comando
pegado literalmente. Citas por `fichero:línea`.

> **Nota de tiempo (importante).** Mientras se hacía esta auditoría, **otro agente terminó el informe
> `F-plan-por-fases.md`** (apareció en disco a las 20:33, 87 469 B, 1103 líneas). Esta auditoría
> empezó con 6 ficheros (README + A–E) y **cierra con 7** (README + A–F). **F no estaba en el encargo
> como terminado**; se incorpora aquí al inventario y se contrasta su §9 con las contradicciones
> halladas. **F §9 es independiente y coincide con este informe** en las 5 contradicciones (§3).

**Alcance:** NO se edita ningún informe A–E ni el README. Los arreglos propuestos (§6) van
documentados, no aplicados.

---

## 1. Resumen ejecutivo — ¿está todo documentado?

**Casi. Sí en profundidad, no en consistencia.** (1) Los informes A–F existen, están cerrados y
A–E eran **idénticos byte a byte** en las dos copias de entonces (obsoleto: ya no hay dos copias; F llegó al
final, ver nota de tiempo). (2) **Los 11 enlaces de «documentos base» del README están ROTOS**:
apuntan a `../<fichero>` desde `docs/omarchy-uke/`, es decir `docs/<fichero>`, cuando los reales
viven en `docs/tablet-lapiz-2026/<fichero>` — y **F reproduce el mismo error** en su anexo. (3) El
**README se contradice consigo mismo** (tabla dice «los 5 cerrados», §Estado dice «A–D cerrados, E en
curso», y no lista F). (4) Hay **una contradicción factual grave** sobre el repo aarch64 de Omarchy:
A y C dicen que existe, **E dice 404 en todo** — la comprobación en vivo **da la razón a A y C y
refuta a E** (§3.1); **F ya la había resuelto igual, de forma independiente** (`F §9`). (5) Cobertura
temática: el Plan por fases (j) **ya lo cubre F**; siguen flojos **lápiz/stylus (h)** y
**backup/restauración (l)**, y **riesgos (k)** está repartido. No hay ningún tema crítico en el vacío
absoluto, pero el lápiz y el backup son los más flojos.

### 1-bis. Addendum 28-sep-2026 — ¿está todo documentado? (actualización, no reescritura)

Lo del §1 sigue en pie salvo en estos cinco puntos, todos con evidencia del día en
`NOTAS-OMARCHY.md` (cierre 28-sep), `F-plan-por-fases.md` y `docs/historia/ESTADO-VIVO.md`:

1. **F tiene una fase nueva, F9: el slot A no arranca imágenes nuevas (bloqueo nº1).**
   Aislamiento 28-sep (`boot_a` = pokes `11cf3482…` + `dtbo_a` = s238 bueno, sin s251) = cuarto
   arranque mudo (`F:579-596`, `PRE-REGISTRO-F5-B1.md:1137-1152`). Sin resolver F9 no se itera
   nada nuevo (ni F1a ni F1b ni F3).
2. **La vía del dtbo para el panel se REABRIÓ tras un día cerrada.** El s251 queda inocente de
   los mudos con boot nueva (el aislamiento sin s251 también queda mudo); "espacio dtbo cerrado"
   vuelve a hipótesis abierta (`F:480-488`, addendum en `build/bootimg/mkdtbo-s251.py:1-12`).
   La medición del wedge del s251 en slot B con kernel bueno (7→0) sigue en pie.
3. **El bootloader está DESBLOQUEADO (`fastboot getvar unlocked = yes`, medido).** Cierra toda
   la línea AVB/hashtree: el hashtree reempaquetado es decorativo
   (`build/gates/AVB-Y-VBMETA.md:157-163`, `medir-avb.sh`, `F:598-603`).
4. **El hueco de papel (lápiz, h) sigue abierto porque no se ha tocado.** Sin cambios desde el
   27-sep: ningún fichero nuevo de lápiz. Ver §4-bis.
5. **Veredicto global actualizado: «casi» sigue valiendo, pero el bloqueo cambió de sitio.**
   El 27-sep el riesgo era perder el par bueno o el árbol; el 28-sep el par bueno está verificado
   (`backup-par-bueno.sh --self-test` verde) y **lo que falta es entender por qué el slot A no
   arranca**. El índice ya no subestima backup (l) ni riesgos (k): ver §4-bis.

---

## 2. Inventario de ficheros

Comando base (en la copia de entonces): `ls -la` + `wc -l *.md` → 501 A · 1328 B · 626 C · 1213 D · 478 E ·
1103 F · 90 README = **5339 líneas**.

| Fichero | Bytes | Líneas | KB | URLs únicas | Dominios | `[NO VERIFICADO]`/«no verif.» | Tabla de fuentes |
|---|---:|---:|---:|---:|---:|---:|---|
| `README.md` | 6 402 | 90 | 6 | **0** | 0 | 0 | no |
| `docs/informes/A-port-omarchy-aarch64.md` | 58 592 | 501 | 57 | 13 | 7 | **6** | ✅ (`A:164`, `A:256`) |
| `docs/informes/B-arranque-arch-uke.md` | 95 257 | 1 328 | 93 | 28 | 12 | **6** | ✅ (`B:1285`) |
| `docs/informes/C-hyprland-quickshell-aarch64.md` | 63 835 | 626 | 62 | **104** | 32 | **17** | ✅ (6 tablas, `C:123`–`C:242`) |
| `docs/informes/D-capa-tablet-fallback.md` | 67 378 | 1 213 | 66 | **4** | 3 | **2** | ✅ (`D:350`, `D:1076`) |
| `docs/informes/E-paquetes-aarch64-soc.md` | 42 048 | 478 | 41 | 23 | 8 | **3** | ✅ (9 tablas, `E:88`–`E:251`, `E:462`) |
| `F-plan-por-fases.md` | 87 469 | 1 103 | 85 | — | — | **16** | parcial (cita informes por §, no URL) |
| **TOTAL** | **420 981** | **5 339** | **411** | **172** | — | **50** | 5/6 informes |

**Notas de integridad.**
- **`F-plan-por-fases.md` llegó durante la auditoría** (20:33; 87 469 B, 1 103 líneas, §F0–F8 + §9
  «Contradicciones resueltas»). Tiene **1 sola URL** (`grep -oE 'https?://…' | sort -u | wc -l` → 1) y
  **16 marcadores de no-verificado** (§8.1, 20 incógnitas): es un informe **derivado** que consolida
  A–E citándolos por sección, no una investigación con fuentes primarias propias.
- **172 URLs únicas** en A–E (215 apariciones brutas en C, 56 en B…). Reparto sesgado: **C concentra
  el 60 %** y **D solo aporta 4** (análisis de código citando `fichero:línea`, `D:8-10`).
- **34 marcadores de no-verificado** en A–E + 16 en F = **50**. C (17) es el más honesto; D (2) el más
  económico (su §11 «Riesgos y no verificado», `D:1120`+, es prosa).
- **F reproduce el enlace roto del README** en su anexo («Documentos base heredados … `../ubuntu-a-pmos/01..05`»,
  `F:~1090`), mismo error de ruta (§5.1).

### 2-bis. Ficheros nuevos del 28-sep-2026 (verificados contra el árbol real)

Todos existen en disco a 28-sep-2026 (comprobado con `[ -f ]`, 17/17 en `build/gates/` +
`build/cm3-ladder/` con 13 ficheros). Una línea de propósito cada uno:

| Fichero | Propósito (una línea) |
|---|---|
| `build/gates/backup-par-bueno.sh` | Backup del par bueno por SSH + relectura; `--self-test` verde 28-sep |
| `build/gates/bcb-clean-8192.py` | Genera la imagen de 8192 B de ceros para limpiar el BCB de `misc` |
| `build/gates/DECISION-misc-BCB.md` | Decisión: partición `misc` = 4 MiB (B) vs imagen 8192 B; recomienda 4 MiB tras `blockdev` |
| `build/gates/REGLA-UN-SOLO-LECTOR.md` | Incidente de los dos lectores ACM + regla: un solo lector de `/dev/ttyACM0` |
| `build/gates/AVB-Y-VBMETA.md` | Medición: `unlocked: yes`, AVB decorativo, vbmeta_a == vbmeta_b (`:157-158`) |
| `build/gates/medir-avb.sh` | Procedimiento repetible de la medición AVB (+ log `medir-avb-20260928-131843.log`) |
| `build/gates/firmware-wlan.sha256` | Manifiesto sha de los 16 ficheros del firmware WLAN |
| `build/gates/paquete-firmware-wlan.sh` | Empaqueta/instala el firmware WLAN (`--dry-run`: 24 ok) |
| `build/gates/firmware-gpu.sha256` | Manifiesto sha de los 3 blobs GPU vendor (gmu/sqe/zap) |
| `build/gates/paquete-firmware-gpu.sh` | Empaqueta/instala el firmware GPU (`--dry-run`: 15 ok) |
| `build/gates/patches/wlan-msi-orden.diff` | Parche MSI s247-equivalente, archivado como REFUTADO (ledger #437) |
| `build/gates/aplicar-parche-msi.sh` | Aplica el parche a una copia + compila `ath11k.ko` (build-ok 28-sep) |
| `build/gates/medir-wlan-reset.sh` | Kretprobes bus-vs-firmware del reset 7,33 s (pendiente validar en vivo) |
| `build/gates/R10E-NOTA.md` | Acta r10e recuperada (Δ=7,397 s, 4/4) + propuesta #445 para el ledger hermano |
| `build/gates/diag-f1a.sh` | Procedimiento de medida F1a (dtbo s252, sin flashear) |
| `build/gates/ciclo-restaurar-slot-a.sh` | Ciclo de flash que restaura `vendor_boot_a`+`init_boot_a` (**sin commitear a 28-sep: lo edita otra sesión**) |
| `build/gates/s252-GATES.log` | Gates del dtbo s252 (`c3677f95…`, 607 674 B, SIN FLASHEAR) |
| `build/cm3-ladder/` (13 ficheros) | Escalera CM3 del hermano + `measure-cm3.sh` en caliente + harness (`run-test.sh` 3/3 re-ejecutado) |
| `build/pkg/uke-gpu-firmware/` | PKGBUILD + 3 blobs vendor + `uke-gpu-firmware-1-1-any.pkg.tar.zst` (el `.pkg` fuera de git por `.gitignore`) |
| `build/rootfs/etc-base/` | Esqueleto `/etc` (cuenta `sshd` con nº de campos correcto + blacklist ath11k en `modprobe.d/`) |

---

## 3. Contradicciones entre informes — con veredicto y comprobación en vivo

Todos los `curl` se ejecutaron el **26-sep-2026 ~20:29-20:30 GMT**. Salida literal.

### 3.1 (GRAVE) ¿Existe el repo aarch64 de Omarchy? **A/C dicen SÍ, E dice 404**

**Qué dice cada informe.**
- **A** `A:21`: «`https://pkgs.omarchy.org/stable/aarch64/omarchy.db` → **200** — el repo aarch64 existe
  (22 paquetes)»; `A:301`: «existe pero no publica `omarchy` ni `omarchy-settings`».
- **C** `C:19`: «`https://pkgs.omarchy.org/edge/aarch64/omarchy.db` → **200**, con
  `omarchy-4.0.4-1-aarch64`, `omarchy-settings-4.0.4-2-aarch64` y ~148 paquetes»; `C:261`: «El bug
  #8645… **Hoy da 200**»; `C:311`: apuntar `[omarchy]` a **`edge`**.
- **E** `E:54`: «**`omarchy` no publica aarch64.** `pkgs.omarchy.org` devuelve **404** en todo (raíz,
  `/aarch64/`, `/x86_64/`…)»; `E:319`: «El repo oficial **no publica aarch64**»; `E:408` R7:
  «**`omarchy` aarch64 = 404 en todos los canales**»; `E:476` cierra «404 real de aarch64».

**Comprobación en vivo:**
```
$ curl -sI https://pkgs.omarchy.org/stable/aarch64/omarchy.db | head -1                      → HTTP/2 200
$ curl -sI https://pkgs.omarchy.org/edge/aarch64/omarchy.db   | head -1                      → HTTP/2 200
$ curl -sI https://pkgs.omarchy.org/edge/aarch64/omarchy-4.0.4-1-aarch64.pkg.tar.zst | head -1
HTTP/2 200    # content-length: 120291356 (114 MB) · last-modified: Wed, 23 Sep 2026 00:47:06 GMT
$ curl -sI https://pkgs.omarchy.org/stable/aarch64/omarchy-4.0.4-1-aarch64.pkg.tar.zst | head -1 → 404
$ curl -sI https://pkgs.omarchy.org/ | head -1 ; curl -sI https://pkgs.omarchy.org/aarch64/ | head -1
HTTP/2 404 ; HTTP/2 404
# Contenido real de los .db (descargados; son zstd, `tar tf` los lee):
$ tar tf ed.db | grep -c '/desc$'   -> 148     $ tar tf st.db | grep -c '/desc$'   -> 22
$ tar tf ed.db | grep '^omarchy'    -> omarchy-4.0.4-1/ · omarchy-settings-4.0.4-2/ ·
                                       omarchy-keyring-20251027-1/ · hyprland-0.56.2-3/ ·
                                       quickshell-git-0.3.0.r20.g28771c7-3/
$ tar tf x86.db | grep -c '/desc$'  -> 248    (stable/x86_64, control: coincide con `A:22`)
```

**VEREDICTO: A y C son CORRECTOS; E es FALSO para el estado de hoy.**
Estado real 26-sep-2026: **`stable/aarch64` → 200 con 22 paquetes SIN el núcleo del escritorio**
(coincide con A) y **`edge/aarch64` → 200 con 148 paquetes, incluidos `omarchy-4.0.4-1`,
`omarchy-settings-4.0.4-2` y `hyprland-0.56.2-3`** (coincide con C). El 404 de E solo es real en
**rutas de directorio** (`/`, `/aarch64/`, `/x86_64/` → 404) y en el **paquete de `stable/aarch64`**,
no en los `.db` ni en el paquete de `edge/aarch64`.
**Causa:** E no midió los `.db`; midió rutas de directorio y se apoyó en una **cita textual de un fork
de terceros** (`E:56-58`, `omarchy-mac/omarchy-pkgs-aarch64`: «edge/aarch64 and stable/aarch64 both
return 404»). Esa cita era cierta cuando se escribió (bug #8645 de Omarchy, 27-ago-2026) pero está
**obsoleta hoy**: C ya documenta que el bug se resolvió (`C:19`, `C:261`), con `edge` publicado el
**23-sep-2026** (`last-modified` de los `.db`). E es un **dato caducado de terceros sin re-medir**;
su R7 (`E:408`) y el plan de construir el repo (`E:319`) son hoy innecesarios.

> **Corolario:** la vía correcta **hoy** es `edge`, no `stable` (`C:311`). Quien lea **solo E** creerá
> que hay que compilar el repo entero; quien lea **solo A** creerá que el hueco es «ejecutar makepkg
> en ARM» (`A:31`), también obsoleto: `edge` ya trae los 148 paquetes construidos. A ya pide un
> re-check en su paso 1 (`A:495`); hecho hoy, se cierra con `edge`.
>
> **Corroboración independiente:** el informe **F §9** (tabla «Contradicciones entre informes,
> resueltas», fila 1) llega **al mismo veredicto sin esta comprobación en vivo** — «Ganan A y C; E
> estaba desactualizado… el hueco de *construir el repo* se reduce a publicar/edge, no a crearlo» —
> y añade el mismo matiz crítico (`omarchy` está en `edge`, **no** en `stable`). Dos análisis
> independientes coinciden: **E es el informe a corregir**.

### 3.2 (MEDIA) Versión del plugin tablet: **D v1.25.0 vs marketplace v1.23.0** — no es contradicción medible, es hueco de trazabilidad

**Qué dice cada informe.**
- **D** `D:6` y `D:1169`: «`maxt.tablet-experience` (**repo real:**
  `https://github.com/gmaxxxie/omarchy-tablet-experience`, **v1.25.0**, MIT)», y añade «el proyecto va
  por 1.2x y cambia rápido (v1.12 → v1.25)».
- La versión **`1.23.0` NO aparece en ningún informe**: `grep -rn "1\.23" *.md` solo devuelve
  `D:1080` (`fcitx5 5.1.23-1`, que no es el plugin). El dato «playlist v1.23.0» que se cita en el
  encargo **no está escrito en ningún sitio de estos 6 ficheros**.

**Veredicto: NO ES CONTRADICCIÓN INTERNA** — es un dato (v1.23.0 del playlist del marketplace)
**huérfano**: existe fuera de los informes y **no está referenciado con fuente** dentro de ellos. El
informe D, además, es honesto sobre la caducidad (`D:1169-1170`: «Pinnear el commit… no seguir `main`»),
y **C avisa del problema de fondo** (`C:510`): *«`maxt.tablet-experience` … **[NO VERIFICADO]** en esta
investigación — no encontré su repositorio; la búsqueda devuelve el plugin de marketplace
`cavacuz.tablet`»*. O sea: **C y D dan identidades distintas para el mismo plugin** (`maxt.tablet-experience`
vs `cavacuz.tablet`) y **D resuelve lo que C dejó abierto** (D sí clonó el repo real, `D:8-10`).
**Acción:** A/D deben fijar **una sola fuente de verdad** (repo `gmaxxxie/omarchy-tablet-experience`,
commit pinneado) y anotar la versión del **playlist del marketplace** (`1.23.0`) con su URL, hoy
inexistente en los informes.

### 3.3 (LEVE) Versión de Hyprland en Arch ARM: **C: 0.56.2-3 vs E: «no expuesta»**

**Qué dice cada informe.**
- **C** `C:18`, `C:32`, `C:202`, `C:273`: «`hyprland 0.56.2-3` en `extra/aarch64`» (con URL
  `archlinuxarm.org/packages/aarch64/hyprland`).
- **E** `E:219`: «`hyprland` ✅ `extra`, 64 MiB, 15-sep-2026 … `—` (**versión a confirmar contra
  0.56**)»; `E:420`: «**la ficha consultada no expuso el número**».

**Veredicto: NO CONTRADICCIÓN — E es cauto, C es preciso.** E no afirma lo contrario: dice que **no
pudo leer el número**. C lo da (`0.56.2-3`) con URL. **Se resuelve leyendo ambos: la verdad es
0.56.2-3** (C es la fuente canónica para este dato). Además, la comprobación en vivo **refuerza a C**:
el `.db` de `edge/aarch64` lista **`hyprland-0.56.2-3`** como dependencia del repo Omarchy
(entrada presente en `tar tf ed.db`). No hay conflicto.

### 3.4 (LEVE) Tamaño del repo aarch64: **A «22 paquetes» vs C «~148»** — ambos ciertos, canales distintos

- **A** `A:21`, `A:301`: 22 paquetes en `stable/aarch64`.
- **C** `C:19`: «~148 paquetes» en `edge/aarch64`.

**Veredicto: NO CONTRADICCIÓN.** Son **dos canales distintos**: **`stable`=22** (medido hoy: 22 ✅) y
**`edge`=148** (medido hoy: 148 ✅). El README (`README.md:30`) mezcla ambos al decir «publica
`pkgs.omarchy.org/stable/aarch64/omarchy.db` (**200**) pero **no** los 22 paquetes del escritorio» —
correcto — **pero omite que `edge` ya los trae**, lo que da una impresión más pesimista que la
realidad. **Acción en §6.**

### 3.5 (LEVE) Canal recomendado: **A «stable» (implícito) vs C «edge, no stable»**

- **A** `A:111` propone `Server = https://pkgs.omarchy.org/stable/$arch` (plantilla del `pacman.conf`).
- **C** `C:311`, `C:546`: «apuntar `[omarchy]` a **`edge`**, **no `stable`**: ahí no está el núcleo
  en aarch64».

**Veredicto: C tiene razón para la uke.** Con `stable` no aparecerían `omarchy`/`omarchy-settings`
(confirmado: `stable/aarch64` no los lista; `stable/aarch64/omarchy-4.0.4-1-...zst` → **404**). La
plantilla de A es **genérica del upstream**, no una recomendación para ARM; pero **alguien que siga A
al pie de la letra se queda sin escritorio**. Debe corregirse en A o anotarse el matiz.

### 3.6 Otros cruces revisados (sin contradicción)
- **BCB `misc` / brick / e2fsck:** coherentes entre README (`README.md:81-82`) y B (`B:36-37`,
  `B:837-855`, brick del 11-sep-2026 `B:840`).
- **Kernel:** README (`README.md:9`) mainline `7.2-rc2` «palawan» ↔ E (`E:251`) `palawan/v7.2-rc2`
  commit `0d9f7fdf720a`. Coherente.
- **Adreno 732 sin id upstream en Mesa:** C (`C:528`) y E (`E:29`, `E:406`) coinciden. Coherente.

### 3.7 (MEDIA, 28-sep-2026; CORREGIDA contra fuentes — ver NOTAS 28-sep cierre2) Conteo de mudos y citas del ciclo de slot A

**Lo que dice el registro (gana `PRE-REGISTRO-F5-B1.md`, contemporáneo de cada intento).**
El 28-sep hubo **cinco intentos** (NOTAS cierre §9): `dtbo_b` ← s251 (WEDGE medido 11:52–12:03,
retry 7→0, unbootable YES; rollback a s238 limpio 12:02) + tres pokes `boot_a`+`dtbo_a` con
s251 (shas `ed1a4403…` y `81fc9f00…` anulados por escrito por bugs propios + tercer intento;
los tres mudos) + aislamiento `boot_a` pokes `11cf3482…` + `dtbo_a` s238 bueno (**CUARTO**
arranque mudo, `RESULTADO 1137-1144`). Más la instalación previa de `dtbo_b` ← s238 (waiver
3483 mV) y su rollback: `s250` se CANCELÓ sin flashear.

**Corrección 1 (conteo).** Mudos escribiendo en el SLOT A = **cuatro** (tres con boot
nueva+s251 + uno de aislamiento), no cinco. El quinto flash de la serie fue en el slot B y
**SÍ arrancó** (s238, validado en caliente: reguladores, L8, DPU hasta `dpu_kms_hw_init`).
El wedge del s251 en B y los mudos en A son cosas DISTINTAS con causas distintas y no se
suman en una cifra: el wedge tiene mecanismo MEDIDO (enlazar `apps-smmu` con arm-smmu v2 →
stall de bus, sin consola porque `ttyGS0` nace tarde); los mudos NO tienen mecanismo medido
(candidata en curso: `vendor_boot_a`/`init_boot_a` vacías; ver Corrección 2).

**Corrección 2 (citas del hermano, verificadas en su `docs/FLASH-LEDGER.md`).**
- «`vendor_boot` es la base del device tree» es su **#236** (líneas 338–346: «la diferencia
  grande A<->B es el vendor_boot, que es la BASE DEL DEVICE TREE»), **NO su #336**: el #336
  (líneas 2557–2569) trata del LAST-POKE del s150/s151, nada de DT.
- «El ABL rechaza los `vendor_boot` reempaquetados» cita su #272 (líneas 1147–1155, rechazo
  del s140), pero el #272 quedó **matizado por su propio ledger**: el #275 (líneas 1214–1218)
  llama **mito** al «no acepta repacks» (el s38 sin vbmeta ni footer ARRANCÓ en a y en b;
  regla real H3 = la cadena DTB debe enlosar `dtb_size` por totalsize) y el #278 añade que
  aun con cadena perfecta un árbol C sustituido se rechaza (valida ALGO del contenido). La
  regla operativa (copiar stock byte a byte, sin transformaciones) sigue en pie —reforzada
  por el #278—, pero el mecanismo «rechaza reempaquetados» como fraseo general es el mito
  corregido, no la medida.
- **DATO vs INFERENCIA.** DATO (verificable en repos): 4 mudos en A con boot nueva; s238
  arranca en B; s251 wedgea en B; erase del 24-sep (hermano #384/#385, líneas 3208–3227).
  INFERENCIA (NO verificada independiente aquí; F9 §F9 lo marca): que `vendor_boot_a` /
  `init_boot_a` sigan a ceros HOY y que esa sea la causa de los mudos. La causa de los mudos
  sigue ABIERTA (F9).
- **Sin restauración posterior (respuesta a los 200 MB).** Buscado expresivamente en su
  ledger (#386–#444), sus `criticas/` y su `docs/`: **ninguna entrada restaura
  `vendor_boot_a`, `init_boot_a` ni `super`** tras el borrado #384/#385 (`vendor_boot_a` /
  `init_boot_a` solo aparecen en inventario, test Magisk #233 y el erase; `super` solo en
  #384/#385). El ciclo no duplica trabajo existente.

**Aplicado 28-sep:** cabecera de `ciclo-restaurar-slot-a.sh` corregida (4 mudos, #236,
#272 matizado por #275/#278) y commiteada (`f263347`); su plantilla de pre-registro,
corregida igual.

---

## 4. Cobertura temática — tabla tema → informe(s), con huecos ⚠️

Conteo por frecuencia de palabras clave sobre el texto en minúsculas de cada informe (orden de
magnitud, no precisión). **A**=port, **B**=arranque, **C**=Hyprland/Quickshell, **D**=capa tablet,
**E**=paquetes SoC.

| # | Tema | A | B | C | D | E | ¿Cubierto? |
|---|---|---:|---:|---:|---:|---:|---|
| a | Port de Omarchy / apps x86-only | **105** | 4 | 30 | 6 | 15 | ✅ A (dueño) |
| b | Arranque A/B + boot.img + `ukeinit` | 56 | **302** | 88 | 132 | 46 | ✅ B (dueño) |
| c | Kernel y parches | 71 | 147 | 29 | 8 | **159** | ✅ B (dueño) + E |
| d | Firmware SoC (gen71100/wpss/pd-mapper) | 6 | 26 | 0 | 0 | **165** | ✅ E (dueño) |
| e | GPU / Mesa / freedreno / a732 / GLES | 4 | 1 | **157** | 2 | 93 | ✅ C + E |
| f | Hyprland + Quickshell + config Lua | 62 | 9 | **284** | 128 | 10 | ✅ C (dueño) + D |
| g | Capa tablet / rotación / OSK | 12 | 2 | 28 | **158** | 14 | ✅ D (dueño) |
| h | **Lápiz / stylus / libinput / libwacom** | 1 | 1 | 4 | 31 | **56** | ⚠️ **INSUFICIENTE** |
| i | Datos y apps de usuario (migración) | 38 | 47 | 0 | 4 | 7 | ✅ A + B (referencia a `../ubuntu-a-pmos/04`) |
| j | Plan por fases | 8 | 22 | 3 | 1 | 2 | ✅ **F** (dueño, §F0–F8) |
| k | **Riesgos y recuperación (bricking, fastboot, BCB, e2fsck)** | 4 | **124** | 6 | 2 | 7 | ✅ **B + F §5 + `DECISION-misc-BCB.md` + `REGLA-UN-SOLO-LECTOR.md`** (ver §4-bis) |
| l | **Backup / restauración** | 10 | 35 | 0 | 19 | 11 | ✅ **`backup-par-bueno.sh` con self-test verde** (ver §4-bis) |

**Huecos y propuesta (sin investigar, solo qué informe lo cubriría):**

- **⚠️ (h) Lápiz/stylus — el más flojo.** E cubre el **empaquetado** (libwacom en ALARM, definición
  `.tablet` del NT36532, límite del bus SPI `E:159`, R5 `E:406`) y D la **captura de presión con GTK4
  `GestureStylus`** (`D:554-573`) y la **base de datos de `drawing-tablet`** (`D:787-818`). **Nadie
  cubre la cadena completa** driver kernel NT36532 (E la declara **fuera de alcance** `E:167`) →
  udev/hwdb → libinput → libwacom → Hyprland tablet v2 → app. **Informe propuesto: `I-lapiz-uke.md`.**
- **⚠️ (l) Backup/restauración — sin dueño.** B lo cubre operativamente (`B:849-855`: backup del par
  bueno, sha256 pre-registrado, R7), pero **no hay informe que defina la política**: qué se respalda
  (GPT, dumps EFS, `boot_b`/`dtbo`/`vbmeta`, rootfs), con qué herramienta y cómo se **restaura** de
  verdad. **Informe propuesto: `H-backup-restauracion-uke.md`.**
- **⚠️ (k) Riesgos/recuperación — repartido.** Concentrado en B (`B:837-855`), con §«riesgos» disperso
  en A–E (`A:§8`, `C:§7`, `D:§11`, `E:§5`). **F §5 lo consolida** (ver abajo), pero **falta la parte
  operativa** «qué hacer si queda en fastboot/brick» (solo en B). **Propuesta: añadir a F §5.**
- **✅ (j) Plan por fases — RESUELTO por F.** `F-plan-por-fases.md` (§F0–F8, camino crítico §4,
  riesgos §5, mapa «fase → informe» en anexo) **ya es el plan único** que faltaba. **Ya no es hueco.**
- **✅ Bien cubiertos sin huecos:** (a) port x86-only (A §5), (b) arranque A/B/ukeinit (B, 1328 líneas),
  (c) kernel (B §5 + E), (d) firmware SoC (E §2.1-2.3), (e) GPU/Mesa (C §5), (f) Hyprland/Lua/Quickshell
  (C §2-4), (g) capa tablet (D), (i) datos/migración (A + `../ubuntu-a-pmos/04-datos-y-apps.md`).

**Ningún tema obligatorio queda en el vacío absoluto.** De los tres ⚠️ originales, **(j) lo cerró F**
durante la auditoría y **(k) quedó parcialmente cerrado por F §5**; solo **(h) lápiz y (l) backup**
siguen sin informe dueño — los más urgentes porque (h) es la mayor incógnita técnica y (l) evita perder
la tablet.

### 4-bis. Corrección de cobertura 28-sep-2026 (la tabla ya no subestima k ni l)

- **(k) riesgos/recuperación: ya NO está "SOLO EN B".** Hoy tiene dueño operativo en
  `build/gates/`: `DECISION-misc-BCB.md` (qué tamaño limpiar y por qué) y
  `REGLA-UN-SOLO-LECTOR.md` (`REGLA-UN-SOLO-LECTOR.md:27-32`: incidente de dos lectores, tramo
  14:11–15:01 contaminado). Sigue pendiente la parte «qué hacer si queda en fastboot/brick»
  (solo en B): pasa a F §5 o a H.
- **(l) backup: ya NO está "SIN DUEÑO".** `build/gates/backup-par-bueno.sh --self-test` da
  VERDE 28-sep (boot `ffff8c51…` + dtbo `bdb361df…` + prueba negativa; ver NOTAS cierre §8).
  Lo que sigue sin existir es el **informe H** (política de qué se respalda y cómo se restaura):
  el script es el dueño operativo, no el documento.
- **(h) lápiz: sigue igual de flojo, sin maquillaje.** Cero ficheros nuevos de lápiz el 28-sep;
  la cadena NT36532 → app sigue sin informe dueño. Informe propuesto `I-lapiz-uke.md` (sin escribir).

---

## 5. Verificación de enlaces y de lo que existe en pc-build

### 5.1 Enlaces del README → documentos base: **TODOS ROTOS**

El README (§«Documentos base», `README.md:56-63`) enlaza con `../<fichero>`. Desde
🔴 **Sección anulada (ver aviso de cabecera).** En su día, desde la carpeta del taller, `../` no contenía ninguno:
```
$ ls <ruta-relativa-al-taller>/../informe-stylus-linux-2026.md
ls: cannot access '../informe-*.md': No such file or directory
```
Los ficheros reales vivían en la carpeta hermana del taller. 🔴 **27-sep-2026: esa carpeta no está
en esta máquina**, así que la tabla de abajo es histórica y la conclusión operativa es: **los
documentos base no están disponibles aquí.**

| Enlace escrito en README | Existe en `docs/` | Existe en `docs/tablet-lapiz-2026/` | Tamaño real |
|---|:---:|:---:|---:|
| `../ubuntu-a-pmos/01-inventario-tablet.md` | ❌ | ✅ | 64 145 B |
| `../ubuntu-a-pmos/02-apt-a-apk.md` | ❌ | ✅ | 51 112 B |
| `../ubuntu-a-pmos/03-servicios-kernel-arranque.md` | ❌ | ✅ | 50 453 B |
| `../ubuntu-a-pmos/04-datos-y-apps.md` | ❌ | ✅ | 54 601 B |
| `../ubuntu-a-pmos/05-plan-migracion.md` | ❌ | ✅ | 13 178 B |
| `../informe-stylus-linux-2026.md` | ❌ | ✅ | 38 980 B |
| `../informe-lapiz-linux-arm64-wayland-2026.md` | ❌ | ✅ | 23 998 B |
| `../informe-escritorios-tablet-lapiz-2026.md` | ❌ | ✅ | 29 174 B |
| `../pmos-vs-ut-actividad.md` | ❌ | ✅ | 30 532 B |
| `../experiencias-usuarios-pmos-vs-ut.md` | ❌ | ✅ | 50 442 B |
| `../hyprland-tablet-y-dotfiles-omarchy.md` | ❌ | ✅ | 56 574 B |

**11 de 11 enlaces rotos.** Ninguno está perdido — solo mal enrutado. **El prefijo correcto es
`../tablet-lapiz-2026/`.** **El error se repite en F** (`F:~1090`, «Documentos base heredados …
`../ubuntu-a-pmos/01..05`»), que copió las mismas rutas.

**Además:** en `tablet-lapiz-2026/` hay **5 ficheros que el README NO referencia y que son relevantes**:
`informe-distros-tablet-arm64.md`, `pmos-apps-escritorio-arm64.md`, `ubuntu-touch-vs-alternativas.md`,
`ubuntu-a-pmos/README.md`, `ubuntu-a-pmos/01b-lista-paquetes-tablet.txt`. **Hueco de índice.**

### 5.2 pc-build por SSH (solo lectura) — qué existe y qué debería estar en el README

```
$ sshpass -p … ssh -J PC-PORTATIL usuario@100.64.0.11 'ls -la ~/proyectos/omarchy-uke/ …'
~/proyectos/omarchy-uke/:
-rw-r--r-- 1 usuario usuario 58592 docs/informes/A-port-omarchy-aarch64.md
-rw-r--r-- 1 usuario usuario 95257 docs/informes/B-arranque-arch-uke.md
-rw-r--r-- 1 usuario usuario 63835 docs/informes/C-hyprland-quickshell-aarch64.md
-rw-r--r-- 1 usuario usuario 67378 docs/informes/D-capa-tablet-fallback.md
-rw-r--r-- 1 usuario usuario 42048 docs/informes/E-paquetes-aarch64-soc.md
-rw-r--r-- 1 usuario usuario  6402 README.md
```
🔴 **Obsoleto:** en su día los 6 md5 coincidían entre las dos copias. Hoy **no hay segunda copia** (ver aviso de cabecera):
`A=58fd1066…` `B=dddb3902…` `C=2e66ba04…` `D=0b30776d…` `E=7f92fb84…` `README=02ae843f…`.
**El README dice la verdad al afirmar «idénticos en las dos copias, md5 verificados»
(`README.md:53-54`).** El «~327 KB» del README es correcto (333 512 B reales = 326 KiB).

**Qué hay en pc-build que el README NO referencia (y debería):**
- **`~/proyectos/omarchy-uke/`: ningún `F-*.md`** → confirma que **F no existe** (ni local ni remoto).
- **`~/proyectos/ubuntu-permanente/docs/`** — existen **18 ficheros**, el README solo nombra 7
  (`README.md:67-69`). Los nombrados ✅ están todos. **Faltan por referenciar:**
  `REGLAS-PARTICIONES.md` (3,7 KB — **el más grave: B lo cita como fuente de R1–R12 en `B:398-416`
  y el README no lo menciona**), `AL-DESPERTAR-22SEP.md`, `AL-DESPERTAR-RECUPERACION.md`,
  `CONFIG-BUENO.md`, `ESTADO.md`, `INVESTIGACION-2122.md`, `MIGRACION-PORT-MODERNO.md`, `SESION-23SEP.md`,
  `SESION-24SEP.md`, `SESION-24SEP-GPU.md`, `SESION-24SEP-NOCHE.md`, `historico/`.
  **Tamaños:** `FLASH-LEDGER.md` = **447 983 B (438 KB)**, `ESTADO-ACTUAL.md` 42 698, `LECCIONES.md`
  54 438, `TRABAJO-PENDIENTE.md` 28 000, `REFUTADO.md` 20 824, `OBJETIVOS.md` 19 016.
- **`~/proyectos/ubuntu-uke/docs/`** — existen **7 entradas**, el README nombra 3 (`README.md:71-72`).
  **Faltan:** `plan-port-cliffs-clock.md` (**81 248 B = 79 KB**, el mayor — muy relevante para B),
  `plan-gki-ubuntu.md` (14 KB), `PLAN-ESTRATEGICO-20260905.md` (8,8 KB), `SESION-20260906.md` (9,6 KB),
  `sesion-tablet/`. El `analisis-20260905/` sí está nombrado (habría que confirmar que
  `RECIPE-KNOWN-GOOD.md` existe dentro).
- **`~/gpu-work/`** (`README.md:75`): **no listado** en este comando SSH → queda como pendiente de verificar.

> El README describe la ubicación canónica correctamente (`README.md:3-6`); el problema de rutas es
> 🔴 **Obsoleto:** era un problema de la copia del taller, no de esta carpeta. Y los documentos base
> **no están tampoco en esta máquina** (`~/proyectos/tablet-lapiz-2026/` no existe).

---

## 6. Lista accionable de arreglos (NO aplicados — para otro agente)

Numerados por fichero. «Actual» = texto exacto en disco; «Propuesto» = reemplazo.

### README.md
1. **[ROTO, grave]** Los 11 enlaces (`README.md:58-63`). **Actual:** `../ubuntu-a-pmos/01..05` ·
   `../informe-stylus-linux-2026.md` · `../informe-lapiz-linux-arm64-wayland-2026.md` ·
   `../informe-escritorios-tablet-lapiz-2026.md` · `../pmos-vs-ut-actividad.md` ·
   `../experiencias-usuarios-pmos-vs-ut.md` · `../hyprland-tablet-y-dotfiles-omarchy.md`.
   **Propuesto:** anteponer `tablet-lapiz-2026/` → `../tablet-lapiz-2026/<mismo fichero>`.
2. **[Contradicción]** `README.md:30`. **Actual:** «Upstream publica
   `pkgs.omarchy.org/stable/aarch64/omarchy.db` (**200**) pero **no** los 22 paquetes del escritorio».
   **Propuesto:** «`stable/aarch64/omarchy.db` → 200 con **22 paquetes sin el escritorio**;
   `edge/aarch64/omarchy.db` → 200 con **148 paquetes, incluidos `omarchy-4.0.4-1` y
   `omarchy-settings-4.0.4-2`** (medido 26-sep-2026). La vía para la uke es **`edge`**, no `stable`.
   Ver §3.1 de `docs/historia/G-auditoria-documental.md`.»
3. **[Contradicción interna]** `README.md:89` («Informes **A–D** cerrados, **E en curso**») choca con
   `README.md:53` («**Los 5 informes están cerrados**»). **Propuesto:** «Informes A–F cerrados
   (F añadido 26-sep-2026); ver `docs/historia/G-auditoria-documental.md`.»
4. **[Hueco]** `README.md:53` dice «los **6** ficheros» (README + 5 informes). Hoy hay **7** (README +
   A–F). **Propuesto:** «los 6 informes + README (7 ficheros)».
5. **[Hueco]** La tabla `README.md:45-51` no lista F. **Propuesto:** añadir
   `| F-plan-por-fases.md | 85 | ✅ cerrado (26-sep-2026) |`.
6. **[Hueco de índice]** Añadir a §«Historia de la tablet»: de `ubuntu-permanente/docs/` →
   `REGLAS-PARTICIONES.md` (citado por B), `CONFIG-BUENO.md`, `AL-DESPERTAR-RECUPERACION.md`,
   `REFUTADO.md`, `LECCIONES.md`, `TRABAJO-PENDIENTE.md`, `ESTADO-ACTUAL.md`, `FLASH-LEDGER.md`,
   `OBJETIVOS.md`, `MIGRACION-PORT-MODERNO.md`, `INVESTIGACION-2122.md`, `SESION-*`; de
   `ubuntu-uke/docs/` → `plan-port-cliffs-clock.md` (79 KB), `plan-gki-ubuntu.md`,
   `PLAN-ESTRATEGICO-20260905.md`, `SESION-20260906.md`.
7. **[Hueco]** §«Documentos base» omite `informe-distros-tablet-arm64.md`,
   `pmos-apps-escritorio-arm64.md`, `ubuntu-touch-vs-alternativas.md`,
   `tablet-lapiz-2026/ubuntu-a-pmos/README.md` y `01b-lista-paquetes-tablet.txt`.

### docs/informes/E-paquetes-aarch64-soc.md
8. **[CONTRADICCIÓN GRAVE — refutada] `E:54`.** **Actual:** «**`omarchy` no publica aarch64.**
   `pkgs.omarchy.org` devuelve **404** en todo (raíz, `/aarch64/`, `/x86_64/`…)». **Propuesto:**
   «**Hoy (26-sep-2026) los `.db` dan 200**: `stable/aarch64` (22 paquetes, sin escritorio) y
   **`edge/aarch64` (148 paquetes, con `omarchy-4.0.4-1`)**. Solo dan 404 las rutas de directorio y el
   paquete de `stable/aarch64`. Cerrado en C; medido en vivo en `docs/historia/G-auditoria-documental.md` §3.1.»
9. **[CONTRADICCIÓN] `E:319`, `E:408` (R7), `E:476`.** **Propuesto:** degradar a «404 solo en rutas de
   directorio y `stable/aarch64`; usar `edge` (medido 26-sep-2026)» y **retirar R7**; el plan de §3.5
   («construir el repo nosotros mismos») pasa a **innecesario hoy**.
10. **[Cautela obsoleta] `E:219` y `E:420`.** **Propuesto:** rellenar con **`hyprland 0.56.2-3`**
    (fuente `C:18`, `C:202`; presente en `edge/aarch64/omarchy.db`).

### docs/informes/A-port-omarchy-aarch64.md
11. **[Matiz]** `A:111` (`Server = …/stable/$arch`). **Propuesto:** añadir nota «para aarch64 usar
    **`edge`** (ver `C:311`); `stable/aarch64` no trae `omarchy` ni `omarchy-settings`».
12. **[Paso obsoleto]** `A:495` («re-check de `stable/aarch64`…»). **Propuesto:** marcar **hecho** — el
    re-check da que `stable` no los trae pero **`edge` sí** (§3.1 de G), sin build propio.
13. **[Trazabilidad]** A no menciona el playlist del marketplace (`1.23.0`, dato huérfano del encargo).
    **Propuesto:** añadir fila «playlist del marketplace: 1.23.0 (fuente: <URL>)» o eliminarlo.

### docs/informes/C-hyprland-quickshell-aarch64.md
14. **[Mejora]** `C:510` deja el plugin tablet como **[NO VERIFICADO]** («no encontré su repositorio…
    `cavacuz.tablet`»), mientras **D ya lo resolvió** (`D:6`). **Propuesto:** sustituir por «=
    `gmaxxxie/omarchy-tablet-experience` v1.25.0; análisis en `docs/informes/D-capa-tablet-fallback.md`.»

### docs/informes/D-capa-tablet-fallback.md
15. **[Precisión]** `D:6` fija **v1.25.0** sin URL de release ni commit. **Propuesto:** añadir «commit
    pinneado: `<sha>`» (hoy el dato vive solo en el encargo).

### docs/historia/G-auditoria-documental.md (este fichero)
16. Crear los informes de hueco: **`H-backup-restauracion-uke.md`** (§4-l) y **`I-lapiz-uke.md`** (§4-h);
    añadir a F §5 la recuperación operativa (fastboot/brick, §4-k).
17. **[F]** `F:~1090`: enlace roto `../ubuntu-a-pmos/01..05` → `../tablet-lapiz-2026/ubuntu-a-pmos/…`.

---

---

## §6-bis — Arreglos aplicados (27-sep-2026)

**Aplicados: 1–11 y 14.** Todos con commit y evidencia en `NOTAS-OMARCHY.md` (entrada del 27-sep).

| Arreglo | Qué se hizo |
|---|---|
| 1 (README, enlaces) | Sustituido el bloque «Documentos base» por la constatación de que **no están disponibles en esta máquina** (`tablet-lapiz-2026/` no existe aquí, comprobado 27-sep-2026) + la lista de lo que falta. |
| 2 (README, canal) | Corregido: `edge/aarch64` = 148 paquetes con `omarchy-4.0.4-1`; `stable` = 22 sin escritorio. |
| 3 (README, «5 cerrados» vs «E en curso») | Corregido: los 7 informes cerrados y versionados en git. |
| 4 (README, «6 ficheros») | Corregido: 7 informes + README + `docs/historia/ESTADO-VIVO.md` + `NOTAS` + `AGENTS`. |
| 5 (README, falta F en la tabla) | Añadido. |
| 6 (README, índice de `docs/` del hermano) | Ampliado con `REGLAS-PARTICIONES.md`, `LECCIONES.md`, `REFUTADO.md`, `CONFIG-BUENO.md`. |
| 7 (README, ficheros no referenciados) | Fusionado con el arreglo 1 (la carpeta no está aquí). |
| **8, 9 (E: 404 falso)** | **Aplicados en `E`**: §1.1 bloque 4, §3.5, R7 (retirado), tabla de fuentes, con el bloque `curl` completo. El plan de §3.5 de construir el repo queda **tirado**. |
| 10 (E: versión de hyprland) | Rellenado: `0.56.2-3` (medido 26-sep-2026), en `E §2` y en la lista de no verificados. |
| 11 (A: `stable` vs `edge`) | Resuelto en `F` (canal `edge`, R19) y en el README. **El texto de `A:111` no se tocó**: A está congelado, y la corrección queda en `F` + `NOTAS`. |
| 14 (C: identidad del plugin) | Resuelto: `maxt.tablet-experience` (repo `gmaxxxie/omarchy-tablet-experience`, v1.25.0 en repo / v1.23.0 en el marketplace del catálogo) **≠** `cavacuz.tablet` (v0.3.3), que es otro plugin. |
| **Extra** | `CONFIG_QCOM_PD_MAPPER=m` ya activo en el config bueno ⇒ `pd-mapper` de AUR pasa a plan B. |
| **Extra** | Chip ID resuelto por lectura de código (`0x43030b00`) ⇒ **R3 de F retirado** y la incógnita 2 cerrada. |

**Pendientes: 12, 13, 15, 16, 17** (menores: marketplace playlist, `mesa` en el registro, commit
pinneado del plugin, enlace del anexo de F —este ya corregido el 27-sep—, y `gpu-work/` por verificar).

### §6-ter — Reconciliación 28-sep-2026 (el §6 decía "NO aplicados"; el estado real es este)

`docs/historia/AGENTS.md` y el §6-bis ya dicen que 1–11 y 14 están aplicados; el cuerpo del §6 sigue
encabezado como "NO aplicados". Reconciliación, una por una:

| Arreglo | Estado real 28-sep |
|---|---|
| 1–7 (README) | ✅ Aplicados 27-sep (ver §6-bis). El §5.1/§5.2 de este informe queda como histórico |
| 8–10 (E: 404 falso, hyprland) | ✅ Aplicados 27-sep (ver §6-bis) + errata nueva del sqe aplicada 28-sep (`E:3-8`) |
| 11 (A: `stable` vs `edge`) | ✅ Aplicado vía F (R19) + README; `A:111` intacto a propósito (A congelado) |
| 12 (A:495, re-check) | ⏳ Pendiente formal: el re-check **está hecho** (da `edge`, §3.1) pero A no lleva la anotación; A congelado ⇒ anotar en F/NOTAS o cerrar como «resuelto fuera de A» |
| 13 (playlist marketplace 1.23.0) | ⏳ Pendiente (menor, trazabilidad) |
| 14 (C: identidad del plugin) | ✅ Aplicado 27-sep (ver §6-bis) |
| 15 (commit pinneado del plugin) | ⏳ Pendiente (menor) |
| 16 (informes H e I) | ⏳ Pendiente: **H sin escribir** (hay dueño operativo `backup-par-bueno.sh`, §4-bis); **I sin escribir ni empezar** |
| 17 (enlace anexo F) | ✅ Corregido el 27-sep (ver §6-bis); queda `gpu-work/` por verificar |
| 18 (nuevo 28-sep: errata sqe en E) | ✅ Aplicada: `E:3-8` (67348 QRD vs 66036 vendor) |
| 19 (nuevo 28-sep: cerrojo s251) | ✅ Hecho: `mkdtbo-s251.py:1-12`, no reflashear sin causa nueva |
| 20 (nuevo 28-sep: ciclo slot A) | ✅ Aplicado 28-sep (cierre2): `ciclo-restaurar-slot-a.sh` commiteado (`f263347`, --dry-run 10 ok) + §3.7 corregida contra fuentes (4 mudos en A, s238 en B SÍ arrancó, citas reales #236 y #272→#275/#278, sin restauración posterior hasta #444) |

### §6-quater — Reconciliación 1-oct-2026 (auditoría V3, solo lectura, sin tablet)

Verificación de hoy (`grep` + `ls`/`[ -f ]`): se marca lo que de verdad está aplicado y se
añaden los pendientes nuevos. Detalle en `build/gates/revision/V3-huellas-docales.md`.
(Nota de lectura: el encabezado del §6 —«NO aplicados»— es el título original del 26-sep; el
estado real vive en §6-bis + §6-ter + este §6-quater.)

| Arreglo | Estado real 1-oct |
|---|---|
| 12 (A:495, re-check) | ✅ Aplicado («resuelto fuera de A»): el re-check está hecho (§3.1, da `edge`), F lo porta (R19, `F:1468`) y el README lo dice; `A:111` intacto a propósito (A congelado) |
| 13 (playlist marketplace 1.23.0) | ⏳ Pendiente (verificado hoy: 0 referencias nuevas en ningún `*.md`) |
| 15 (commit pinneado del plugin) | ⏳ Pendiente (verificado hoy: ningún sha/commit del plugin en ningún `*.md`) |
| 16 (informes H e I) | ⏳ Pendiente (verificado hoy: `ls H-*.md I-*.md` vacío) |
| 17 (enlace anexo F) | ✅ Aplicado: el anexo de F (`F:1634-1639`) ya no lleva la ruta rota `../ubuntu-a-pmos` (nombres + aviso de no-disponibilidad + sustituto hermano); `~/gpu-work/` verificado que existe (contiene `abl-analysis`, scripts `44-*`, etc.) |
| v3-§8.1 («15 reglas» sin escribir) | ✅ Aplicado: `REGLAS.md` canónico creado el 1-oct; `docs/historia/RUNBOOK-SIGUIENTE.md:12-13` ya cita a REGLAS y la cita rota desapareció |
| v3-§8.3 (OBJETIVOS filas 1/6) | ✅ Aplicado: fila 1 trae la reconstruibilidad cerrada 1-oct (`ACUMULADO-*.diff`), fila 5/6 sin «tras K19» (`grep K19` vacío en OBJETIVOS) |
| 21 (nuevo 1-oct: README §Estado par viejo) | ⏳ Pendiente (menor): `README.md:146-147` cita `s244-bounce`+`s229` como estado; mitigado por «Ver ESTADO-VIVO» pero refrasear a pasado (viene de v3-§8.2/v4:325) |
| 22 (nuevo 1-oct: V1 «espacio CB ~0x110000») | ⏳ Pendiente: `V1-critica-plan-v3.md:56-57` refutado por V2 §2 (MMU-500: recurso hasta 0x40000, CB0..21 = 0x20000..0x35000); anotar sin reescribir |
| 23 (nuevo 1-oct: V2 niega el fichero A1) | ⏳ Pendiente: `V2-critica-k23b.md:85-86` dice que «no hay ningún fichero A1» pero existe `build/gates/prepara/A1-auditoria-instalador.md` (30-sep, con §4 USB); corregir la cita y añadir la ruta en v2:45/v3:100/v4:151 |
| 24 (nuevo 1-oct: ESTADO-VIVO ioremap/CBpage) | ⏳ Pendiente: `docs/historia/ESTADO-VIVO.md:24-27` («el dump ahora completa») y `:39-41` («CBpage ahora completa») refutados por H1/H2; el banner ya manda a v4 §P0.4 pero el cuerpo induce a error |
| 25 (nuevo 1-oct: v3 §P2 subcaso K19-style) | ⏳ Pendiente: `docs/historia/PLAN-SIGUIENTE-v3.md:125-128` («programar a mano SMR+S2CR+CB») refutado por el banner de v4; una línea de aviso en v3 §P2 (v3 sustituido pero se lee por historial) |
| 26 (nuevo 1-oct: F §F0 gate con shas viejos) | ⏳ Pendiente: `F:79,295-296,312,337,926,987,1520` verifican contra `ffff8c51…`/`d2a29ea5…`; el par operativo es K13-dsid+s260 (b) y K23+s263 (a) — un F0 literal hoy falla el gate |
| 27 (nuevo 1-oct: B par vigente + tokens) | ⏳ Pendiente: `B:307,867-868,966,972` (par `s240`/shell s244) histórico desde 26-sep; y `B:314,992` (`disable_bypass=0` «no negociable») sin contrastar contra la cmdline vigente |
| 28 (nuevo 1-oct: re-mediciones con fecha) | ⏳ Pendiente (regla 14 días): `edge/aarch64` 148 pkgs (G §3.1 26-sep, A1 30-sep) caduca ~10/14-oct; serie battmgr `E:299` (15-sep) ya caducada — re-verificar antes de usar |

## 7. Temas críticos en el vacío absoluto

**Ningún tema obligatorio está en el vacío absoluto** (los 12 tienen al menos un informe con contenido
real). Tres bloques críticos **no tienen informe dueño** y deben crearse:

1. **Backup / restauración real (⚠️ sin dueño, §4-l).** Hoy solo hay instrucciones operativas
   diseminadas en B (`B:849-855`) y el dato de que los dumps EFS están en `ubuntu-uke/`
   (`README.md:72`). **No existe** un procedimiento de backup verificado ni de **restauración
   completa**. **Informe propuesto: `H-backup-restauracion-uke.md`** (nombre `H` porque `F` ya
   está ocupado por el plan por fases).
2. **Lápiz/stylus de punta a punta (⚠️ insuficiente, §4-h).** La cadena
   `NT36532 → kernel driver → udev/hwdb → libinput → libwacom → Hyprland tablet v2 → app` no está
   cubierta por un solo informe; E la declara fuera de alcance (`E:167`). **Informe propuesto:**
   `I-lapiz-uke.md`.
3. **Recuperación operativa (⚠️ resto de k).** 🔴 **Ya NO falta el registro de riesgos** (F §5 lo
   consolidó), pero sí la parte **«qué hacer si la tablet queda en fastboot/brick»**, que sigue solo
   en B. Cabría añadirla a F §5 o a un anexo.

**Otros pendientes explícitos (de los propios informes):** confirmar que
`docs/analisis-20260905/RECIPE-KNOWN-GOOD.md` existe; verificar que `~/gpu-work/` existe en pc-build
(no listado aquí); corregir el enlace roto del anexo de F (`F:~1090`).

---

### Anexo — comandos de reproducción

```bash
cd ~/proyectos/omarchy-uke/ && ls -la && wc -l *.md               # inventario
curl -sI https://pkgs.omarchy.org/stable/aarch64/omarchy.db | head -1      # 200
curl -sI https://pkgs.omarchy.org/edge/aarch64/omarchy.db   | head -1      # 200
curl -sI https://pkgs.omarchy.org/stable/aarch64/omarchy-4.0.4-1-aarch64.pkg.tar.zst | head -1  # 404
curl -sI https://pkgs.omarchy.org/edge/aarch64/omarchy-4.0.4-1-aarch64.pkg.tar.zst   | head -1  # 200
curl -s https://pkgs.omarchy.org/edge/aarch64/omarchy.db | tar tf - | grep -c '/desc$'          # 148
curl -s https://pkgs.omarchy.org/stable/aarch64/omarchy.db | tar tf - | grep -c '/desc$'        # 22
# (anulado) la integridad entre copias ya no aplica: esta carpeta es la única, con git
sshpass -p … ssh -J PC-PORTATIL usuario@100.64.0.11 'cd ~/proyectos/omarchy-uke && md5sum *.md'
ls ~/proyectos/tablet-lapiz-2026/                                           # los 11 enlaces reales del README
```

### §6-quinquies — Reconciliación 2-oct-2026 (auditoría de "docs viejos con info mala", solo lectura local)

Verificado punto por punto contra mediciones del 2-oct (ledger hermano #487–#491). Sin tablet.

| Pendiente | Estado real 2-oct |
|---|---|
| B:679/§6.4 (hook oops "único canal de panics") | ✅ Corregido con errata in situ: el canal **nunca funcionó** (falta `/dev/block/by-name/`; `block2mtd` lo confirma en consola @3.495 s; `sda26` solo oops de fábrica jun-2026). Requisito anotado (symlinks o `/dev/sda26` por cmdline) |
| B:881-883 ("par vigente s240+s229 en slot b" + `fetch` + misc-limpia-slots) | ✅ Corregido con errata in situ: par real `boot-ukek13-dsid.img`+`s260` en slot a; `fetch` no existe en este bootloader; misc no rehabilita (contadores en GPT) |
| 21 (README §Estado par viejo) | ✅ Corregido: párrafo marcado histórico + actualización 2-oct (K23–K42, ledger #443–#491) |
| 24 (ESTADO-VIVO ioremap/CBpage) | ✅ Desaparecido en las reescrituras del 2-oct (verificado con `grep`: 0 ocurrencias) |
| PRE-REGISTRO-PANTALLA.md (termina en #P52) | ✅ Nota de reenvío al ledger (#475–#491 + shas K34–K42) añadida al final |
| 22 (V1 CB 0x110000) / 23 (V2 cita A1) / 25 (v3 P2) | ✅ Ya cubiertos (banner RETRACTADO en V1, cita correcta en V2:85-86, banner en v3). Sin acción |
| K31 ("con dominio propio también falla") | ✅ Ya autocorregido en el propio documento (líneas 18-22, revisión 2-oct). Sin acción |
| `:d` impuesto por ABL / `hung_task` protege slot | ✅ Ya corregidos (R8/R5/R10 + K24 "mitiga, no protege"). Sin acción |
| 13 (playlist) / 15 (plugin pin) / 16 (H e I) / 28 (re-mediciones) | ⏳ Siguen pendientes (nada operativo depende de ellos hoy) |
