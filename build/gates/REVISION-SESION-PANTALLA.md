# REVISION-SESION-PANTALLA — revisión adversarial de la sesión del 28-sep (tarde/noche)

> **SG-REVIEW**, 28-sep-2026. Objetivo auditado: *que la pantalla funcione del todo*.
> Método: lectura completa de `docs/historia/PLAN-PANTALLA.md`, `PRE-REGISTRO-PANTALLA.md`, los 7 informes de
> subagentes y la evidencia; **verificación con `sha256sum`/`stat`** de todos los artefactos citados;
> minado de la captura de consola (`~/proyectos/out/uke-ubuntu_console.log`, 477 275
> líneas, `grep -a` porque el fichero es binario) y de los logs del vigía de rescate.
> **0 escrituras en la tablet, 0 commits.** Todo hallazgo lleva `fichero:línea` o comando+salida.
> Etiquetas: DATO = medido/citado con fuente; INFERENCIA = deducción; NO VERIFICADO = sin fuente.

---

## 0. Veredicto de una línea

- **"Panel vivo" AGUANTA** el escrutinio: en el boot con `s258` el panel prueba y hace attach
  (stack `o82_probe`→`dsi_dev_attach`→`component_add` en consola:465866-465884) y desaparecen las 4
  líneas de error del reset gpio (consola:443390-443393 es el último boot con ellas).
- **"Solo falta SMMU" NO es exacto**: el bloqueo inmediato es el `-19` (sin `iommu_group`), pero el
  master bind ya revienta con Oops en el unwind (preexistente), DSI1 sigue con
  `phy driver is not ready` en el mismo boot, y la premisa que justifica el pivote a kernel
  ("el compatible wedgea el arranque") **no está medida** (H1/H2).
- La sesión **termina sin registro del desenlace del K1** (sin fila de resultado, sin commit) y con
  el rollback pendiente y el vigía en pausa desde 19:40 (H2).

---

## 1. Shas y tamaños: lo que cuadra y lo que no (comando: `sha256sum`, `stat -c%s`)

| Referencia | Sha citado | Sha real hoy | Tamaño | Veredicto |
|---|---|---|---|---|
| `s238-boot-dtbo-dedup-gpio.img` | `bdb361df…0022` | `bdb361df…0022` | 607 534 B | OK |
| `s251-boot-dtbo-apps-smmu-bind.img` (control de gates) | `78eb2645…` | `78eb2645…` | 607 674 B | OK |
| `s255-canarias.img` | `bad87bdf…` | `bad87bdf…` | 607 765 B | OK |
| `s256-regonly.img` | `2b45b337…` | `2b45b337…` | 607 885 B | OK |
| `s257-gpio.img` | `7c05e305…` | `7c05e305…` | 608 341 B | OK |
| `s258-panel-gpio2.img` | `f4663ff8…` | `f4663ff8…` | 608 469 B | OK |
| `boot-ukek1-gate1.img` | `a1eb174e…` | `a1eb174e…` | 96 MiB | OK |
| `boot_b-lee.img` (backup) | `ffff8c51…` | `ffff8c51…` | 96 MiB | OK |
| `base-dtb.img` | `3f973c78…` | `3f973c78…` | 1 888 256 B | OK |
| `panel_xiaomi_o82_dualdsi.ko` | `98902587…` | `98902587…` | 387 432 B | OK |
| **A′ original (`s253`)** | **`eeb57d95…` (607 714 B)** | **`53653d1a…` (607 945 B)** | — | **✗ H4: ruta sobrescrita por el build de P1d** |
| P1b (`4f284efa…`) y P1c (`2c134ec3…`) | citados | **ningún fichero** | — | **H4: perdidos** |

No hay ningún sha mal copiado en lo que existe; el problema son las dos filas `✗` (H4).

---

## 2. Hallazgos

### H1 — GRAVE — "s253d wedgeó ⇒ el compatible es el tóxico": la premisa del pivote a kernel no está sostenida

**Qué se afirma**: `PRE-REGISTRO-PANTALLA.md:58` (#P1g-s256): *"el tóxico del s253d es el
COMPATIBLE: al matchear, el probe del arm-smmu wedguea el arranque (mudo)"*; de ahí el giro a
kernel (K1). `INFORME-SMMU-CLK.md:336` lo usa como cierre del espacio DT ("`s253d` (compatible
triple) → wedge").

**Evidencia en contra o nula**:
1. El único checkpoint guardado del estado de `dtbo_b` en esa ventana es
   `build/evidencia/2026-09-28/veredicto-p1e.md` (mtime y cabecera 19:39:45). Su salida (línea 7)
   es `6d43391438954bd44eac0ad5db5c3394ac54f49092fa068553f4cb68e0ce30df` al leer
   `head -c 607945 /dev/disk/by-partlabel/dtbo_b` — que **no es** el sha del artefacto
   (`53653d1a…`, 607 945 B) — y su línea 8 muestra `compatible = "qcom,qsmmu-v500"` (vendor), sin
   ninguna línea de canario. Es decir: a las 19:39:45 **dtbo_b no contenía s253d**.
2. La razón es inmediata: `out/rescate-pantalla.log` registra a las **19:39:04** *"fastboot
   detectado — acción 1/4: restaurar dtbo_b s238"* y reboot. El vigía había restaurado s238 **41 s
   antes** de la verificación. Cualquier boot posterior a 19:39:04 ya era s238.
3. La fila P1e reconoce que el *"primer boot REAL con s253d"* quedó **pendiente**
   (`PRE-REGISTRO:56`), y el guion que ejecutó ese ciclo reiniciaba con `sysrq-b`
   (`ciclo1-flash-s253.sh:53`). Con los propios datos de P1e (las escrituras `dd+sysrq-b` no
   persistían), **no consta que s253d llegara a arrancar nunca**.
4. El propio `INFORME-SMMU-CLK.md:568-571` dice que s253d tuvo *"un boot a login sin red"* **y**
   *"otro mudo pre-consola"*. Un boot a login con el compatible triple aplicado **refutaría** que el
   compatible wedgee siempre; no hay fichero que documente esos dos boots.
5. Y todos los ciclos P1–P1d, por definición de P1e (`PRE-REGISTRO:56-57`), corrieron **sin la
   escritura en disco**: lo que arrancaba era el s238 que el vigía restauraba. Las caídas a fastboot
   cada ~12 min ocurrieron **con s238** (`rescate-pantalla.log`: 18:40, 18:54, 19:06, 19:18 de
   vuelta en Arch, con restauración previa) ⇒ un "wedge" de 10 min en esa ventana **no es
   distinguible** de la ruleta battery-soc.

**Arreglo propuesto**: marcar la hipótesis como **NO VERIFICADA** en el registro; tachar la
explicación de la fila #P1 (fragmento no numérico) por refutada; y para decidir de verdad:
reconstruir A′ limpio (H4), flashear por **fastboot** (canal fiable), **leer `dtbo_b` y
`/proc/device-tree/.../compatible` en vivo** en el primer arranque y archivar la salida. Solo
entonces se puede decir "el compatible wedgea" o "no wedgea".

### H2 — GRAVE — El K1 se lanzó sin gate 0 y su desenlace no está registrado; el árbol de decisión del #P5 no funciona con consola ACM

**Qué se afirma**: `PRE-REGISTRO-PANTALLA.md:75-85` pre-registra **gate1 directo** (token ON) con
la justificación: *"las migas discriminan: mudo PRE-consola = kernel/config (rollback y parar); mudo
TRAS migas = SMMU localizado (la miga última dice el registro)"*.

**Por qué no es válido**:
1. La consola útil es el gadget **ACM (`ttyGS0`), que nace en el init de usuarios** — documentado
   por el propio proyecto: `EVIDENCIA-PANTALLA-28sep.md:278-282` y
   `PRE-REGISTRO-F5-B1.md:1137-1163` ("el cuelgue precede a la consola (ttyGS0 nace en el init)").
   Las migas `UKE-POKE` del probe (device_initcall/retry) son **invisibles** en un boot que no llega
   a userspace; para leerlas hace falta `dmesg` vivo, que exige justo lo que no ocurrió.
2. `INFORME-K1-BUILD.md:294-315` (§7) dice explícitamente lo contrario de lo que se hizo:
   *"gate 0... **no se debe gastar el gate 1 sin un gate 0 verde**"*, y para eso se diseñó el token.
3. Del desenlace (mute pre-consola) **no hay ningún artefacto**: 0 commits después de `2a7493d`
   (21:07, que solo mete el pre-registro y el informe); el `PRE-REGISTRO` no tiene fila de
   resultado del #P5; en la consola no hay ni una línea del K1 (`grep -ac` de
   `arm_smmu_device_probe|desarmado|REINTENTO|cfg_probe|uke_smmu_probe` = **0**) y el log termina a
   las 21:07 tras un `Rebooting` seguido de silencio (`consola:477180-477275`).
4. El vigía de rescate estaba **en pausa desde 19:40** (`/tmp/rescate-pantalla.pause`;
   `rescate-pantalla.log` acaba en 19:39:04), así que **nada restaura `boot_b` automáticamente**.
   El rollback está pendiente y el estado actual de la tablet no consta en ningún fichero.

**Nota (artefacto concurrente, visto durante esta revisión)**: a las 21:25 apareció en el repo,
sin commitear, `build/gates/patches/k2-arming.diff` (de otra línea de trabajo): su cabecera ya
reinterpreta el mute del K1 — *"con el token en la cmdline el reintento del deferred probe entraba
demasiado pronto (antes de que la consola/SSH estuvieran vivos) y el arranque moría mudo
pre-consola"* — y propone armar el experimento en caliente en vez de por cmdline. Corrobora H2
(el árbol de decisión del #P5 era inválido), pero **no es un registro del resultado del #P5**: eso
sigue faltando.

**Riesgo asociado (no registrado)**: la "pantalla blanca del ABL" que se interpreta como *"el ABL
ya puede dibujar porque el DT del panel está arreglado"* es INFERENCIA sin archivo; con el relato
de 0 enumeraciones USB, la alternativa "la tablet se quedó sin batería / cayó a bootloader" no está
descartada (batería 3 432 mV / 2 % a las 18:20, `PRE-REGISTRO:12-14`).

**Arreglo propuesto**: (1) rollback verificado por fastboot (`boot_b ← ffff8c51…`, ya en disco);
(2) fila #P5 con resultado, hora y sha; (3) re-ejecutar **gate 0** con el mismo binario y el dtbo
s258 para separar "el Image no arranca" de "el probe cuelga"; (4) para mutes, decidir de antemano
cómo se leerá el diagnóstico (p. ej. pstore/ramoops o `mtdoops`, que la cmdline ya configura) y no
prometer migas que la ACM no puede entregar antes del init.

### H3 — GRAVE — Artefactos A′ perdidos/sobrescritos: lo documentado no se puede repetir ni auditar

**Datos**:
- `build/bootimg/s253-boot-dtbo-aprima.img` hoy es `53653d1a…`, 607 945 B (build de P1d, mtime
  19:11). El A′ original (`eeb57d95…`, 607 714 B) fue **sobrescrito en la misma ruta**;
  `INFORME-A-PRIMA.md:452-462` y `INFORME-GPIO-RESET.md:348-350` siguen piniendo `eeb57d95…` a esa
  ruta: **hoy es falso**.
- P1b (`4f284efa…`) y P1c (`2c134ec3…`) **no existen** en el repo ni en `/tmp`, `/var/tmp`
  (búsqueda por sha sobre los `.img`/`.dtbo`/`.dtb` < 2 MB; `/tmp/opencode/s253/` solo contiene el
  build de P1d).
- `s253-GATES.log:92-93` (la evidencia "G0–G10 TODO VERDE") corresponde al artefacto **perdido**;
  el artefacto que sobrevive (P1d, con canarios 158/159 + A′@160) solo tiene el gate **G11**, del
  que **no hay log**.

**Arreglo propuesto**: política "un artefacto = un nombre con su sha" (nunca sobrescribir);
declarar perdidos e irrecuperables los tres shas; reconstruir A′ limpio para el re-test de H1 con
log de gates archivado.

### H4 — MEDIO — El "ÉXITO" de s258 sobredeclara: el master NO liga y el unwind revienta con Oops

**Qué se afirma**: `PRE-REGISTRO:61` (#P4-s258): *"0 líneas de error… ambos DSI host bindean al
master (solo posible con panel adjunto). Cadena: panel ✓ DSI ✓ PHY ✓ GPU ✓ — master muere SOLO en
`no IOMMU`"*.

**Qué muestra la consola del boot con s258** (el último boot de usuario del log, tras el shutdown
de `consola:453854`):
- `consola:454005` y `465814`: `msm_dsi ae96000.dsi: dsi_get_phy: phy driver is not ready` — DSI1
  **no** tiene el PHY listo en ese mismo boot, así que "ambos DSI host bindean" no se sostiene tal cual.
- `consola:454016-454029` y `465821-465834`: `dpu_kms_mmu_init failed: -19` → `msm_drm_kms_init:
  kms hw init failed: -19` y a continuación `Unable to handle kernel paging request at
  dead000000000108` → `Oops` en `drm_atomic_private_obj_fini` desde `dpu_kms_destroy`
  (stack `o82_probe`→`devm_mipi_dsi_attach`→`dsi_host_attach`→`dsi_dev_attach`→`component_add`→
  `try_to_bring_up_aggregate_device`→`msm_drm_bind`→`msm_drm_uninit`). **El "0 líneas de error" solo
  es cierto acotado a las 4 líneas del panel.**
- El Oops es **preexistente** (misma firma `dead000000000108` en todos los boots del día:
  `consola:9308, 18860, 37083, …, 432007`), no un daño del s258; pero el master bind **falla**, no
  liga.
- Lo que sí prueba el stack, y es el dato fuerte del día: el panel **probea y hace attach**
  (`o82_probe+0x298`) — esto es lo que sostiene "panel vivo".

**Arreglo propuesto**: corregir la fila: "panel prueba ✓; master bind intentado y fallido en -19,
con Oops preexistente en el cleanup; DSI1 con phy no listo". Añadir al criterio de cierre "card0
sin Oops", porque hoy el camino de fallo del master deja el kernel tainted (G S W) en cada boot.

### H5 — MEDIO — El guion de flash canónico encarna el canal ya prohibido y está hardcodeado

`docs/historia/gates-palawan/ciclo1-flash-s253.sh` (commiteado en `20910d5`, 19:38, **sin corregir** pese a que ese
mismo commit documenta la lección):
- `:11` sha hardcodeado = `53653d1a…` (solo puede flashear el s253d).
- `:48` "verificación" = `head -c $SIZE /dev/disk/by-partlabel/dtbo_b | sha256sum` **sin
  `drop_caches`** ⇒ puede servirse de caché de página (es exactamente el fallo que P1e descubrió).
- `:53` reinicio con `echo b > /proc/sysrq-trigger` ⇒ el canal que P1e declara no persistente.
- `docs/historia/PLAN-PANTALLA.md:70-72` sigue prescribiendo ese canal (`dd … + sync + relectura sha256 +
  reinicio sysrq-b`) como el de F2.

**Arreglo propuesto**: reescribir el guion (fastboot flash como canal por defecto, o
`dd conv=fsync` + `sync` + `echo 3 > drop_caches` + relectura sin caché + reboot limpio), sin sha
hardcodeado, y actualizar el plan. Que un guion commiteado no pueda ejecutar el flujo que su propio
commit declara correcto es una trampa para el próximo operador.

### H6 — MEDIO — Registro con filas duplicadas/contradictorias y horas imposibles

- `#P3-s257` aparece **dos veces** (`PRE-REGISTRO:59` con el resultado y `:60` como "EJECUTADA …
  Ver resultado arriba"); `#P4-s258` aparece **dos veces** (`:61` con `✅ ÉXITO` y `:62`
  "EJECUTANDO" — una pre-registración **posterior** al resultado).
- Orden temporal imposible: `#P1d` "~19:3x" (`:55`) va **antes** en el fichero que `#P1e` "19:2x"
  (`:56`), y el artefacto de P1d tiene mtime **19:11**. El par P1e/P1d no puede tener esas horas.
- La fila `#P1` mantiene la explicación "el ABL no ve `fragment@s253` (nombre NO numérico)"
  (`:52`) que P1e refuta (todo el misterio = escrituras no persistentes, `:56-57`), sin tachar.
- El "Estado del canal (18:20)" (`:8-18`) dice *"Ningún ciclo se ejecuta hasta que la tablet vuelva
  por USB y la batería pase el gate"*, pero el #P1 se ejecutó a las **18:37** (`:52`) y el vigía ya
  había visto fastboot a las 18:32 (`rescate-pantalla.log`). El waiver de batería está en
  `docs/historia/ESTADO-VIVO.md:7-9` (autorización del dueño), no en el registro; no hay lectura de batería por
  ciclo.
- La tabla "Shas de la serie s253-s257" (`:66-72`) se titula s253-s257 pero solo lista s255/s256/s257:
  sin s253a-d, sin s258 y sin tamaños.

**Arreglo propuesto**: una fila por ciclo, cronológica, con columnas "pre-registrada (hora)",
"ejecutada (hora)", "veredicto", "evidencia"; y una nota de mantenimiento que tache lo refutado.

### H7 — MEDIO — La serie s255–s258 no tiene constructor ni log de gates en el repo

- El único constructor es `build/bootimg/mkdtbo-s253.py`, y escribe **siempre**
  `build/bootimg/s253-boot-dtbo-aprima.img` (`:126-129`); su `main()` actual inserta
  **incondicionalmente** los canarios 158/159 y el A′ en `fragment@160` (`:646-666`, `:728-729`).
  Con ese script no se pueden producir `s255-canarias.img`, `s256-regonly.img`, `s257-gpio.img` ni
  `s258-panel-gpio2.img` (nombres y contenidos distintos); no hay ningún otro script en el repo con
  mtime posterior a 19:10.
- Los gates que el registro cita como verdes ("G-GPIO-1..6", "G-GPIO2-1/2/4", "G11") **no tienen
  log**: `s253-GATES.log` es de las 18:11 y no contiene G11; los únicos restos de s257/s258 son
  `/tmp/s257*.dtb`, `/tmp/s258*.dtb` (tmpfs, volátil) y los informes.
- Ruido de copia-pega: `mkdtbo-s253.py:950-979` valida 158/159/160 pero imprime *"primero=1708
  (A′), ultimo=1709 (canary)"*.

**Arreglo propuesto**: guardar en el repo el constructor de la serie final y los logs de gates (son
offline y baratos), y sha de cada fragmento.

### H8 — MEDIO — Controles citados sin salida archivada

- `#P4-s258` cita como control `pin 2: GPIO f000000.pinctrl:514` (debugfs) — no hay salida
  guardada; el boot sí prueba el panel (H4), pero el control citado es **NO VERIFICADO** en repo.
- `#P1f-s255` ("canarios vivos") no tiene volcado de `/proc/device-tree` archivado; lo que hay es el
  contenido del dtbo (`/tmp/s255-final.dts:14-17`, `uke,canary-smmu`) y el relato del registro.
- La fila `#P1` ("el fragmento NO SE APLICÓ… master DPU bindeó dsi0+dsi1+kgsl") cita un dmesg que no
  está en el repo.
- La medición de que el panel probaba con s238+módulo (12:10) sí está citada con fuente verificable
  (`/tmp/uke-autorecolecta.log:98-116` — `gpio_shared_proxy 20480 1`, `devices_deferred` vacío,
  backlight con `device -> ae94000.dsi.0`), y `dmesg-arch.txt:1640-1672` confirma el defer previo y
  el `phy driver is not ready`. Esa parte está bien.

**Arreglo propuesto**: por ciclo, archivar `dmesg`, `/sys/kernel/debug/devices_deferred`,
`/sys/kernel/debug/gpio`/`pinmux-pins` y `od` del DT; sin eso, el registro no cumple su propia
regla "comando+salida".

### H9 — MEDIO — Documentos canónicos viejos y lecciones de hoy sin escribir

- `docs/historia/PLAN-PANTALLA.md` (18:24, anterior a toda la serie): su diagrama da GPIO2 como hueco abierto y
  A′ (`s253`) como arreglo del hueco 1; su F2 lista `s253`/`s254`; no menciona s255–s258 ni el K1.
  Y prescribe el canal dd+sysrq-b (`:70-72`).
- `docs/historia/ESTADO-VIVO.md` (16:58): dice `dtbo_b = s238` y "slot A mudo 4/4"; nada de la tarde.
- `NOTAS-OMARCHY.md` (17:16): sin nada de la serie.
- Lecciones de hoy **no canónicas** (grep en `NOTAS-OMARCHY.md`, `docs/historia/ESTADO-VIVO.md`, `docs/historia/PLAN-PANTALLA.md`
  y `REGLA-UN-SOLO-LECTOR.md`): "dd+sysrq-b" solo aparece en `docs/historia/PLAN-PANTALLA.md:71` (y ahí como
  prescripción, no como lección); "drop_caches", "battery-soc" y "ruleta" = **0 apariciones**. El
  patrón canario y el bug de `pinctrl-cliffs` (#83) solo viven en informes de subagente y en el
  mensaje de commit.
- La evidencia viva recogida a las 18:32 (`build/evidencia/2026-09-28/device-tree.tar.gz`,
  `dmesg-arch.txt`, `config-kernel-live.txt`, `ssh-nodos-vivos.txt`) existe, pero
  `EVIDENCIA-PANTALLA-28sep.md:486-487` (§11) los sigue dando por **PENDIENTES** y
  `SHA-EVIDENCIA-28SEP.txt` (18:24) no los cubre (ni cubre `veredicto-p1e.md`).
- `EVIDENCIA-PANTALLA-28sep.md:397-408` (§10.4) afirmó "3 instancias en DOS nodos vendor"; era
  erróneo (son 3 nodos) y la corrección solo está en `INFORME-GPIO-RESET.md:243-246`, no en el
  propio informe.

**Arreglo propuesto**: actualizar PLAN/ESTADO-VIVO/NOTAS con la serie s255–s258+K1 y un acta de
lecciones (canal fiable; ruleta battery-soc y su efecto sobre la atribución; el vigía que restaura
s238 enmascara wedges y borra el experimento; patrón canario; gate0; #83 pendiente); anexo de
enmiendas a EVIDENCIA + sha de los ficheros vivos.

### H10 — MENOR — Riesgos abiertos que hoy podrían estar mal (y cómo refutarlos barato)

| Afirmación de hoy | Cómo se refuta barato |
|---|---|
| "El compatible de A′ wedgea el arranque" | flash fastboot de A′ reconstruido + `cat compatible` vivo y `dmesg` en el primer boot (H1) |
| "El mute del K1 es del probe del SMMU" | gate 0 con el mismo binario (token off) y dtbo s258; si arranca, el Image está bien y el mute es del probe; si no arranca, es el Image (H2) |
| "La pantalla blanca = splash del ABL" | foto/registro del estado real de la tablet y `getvar`/contadores; hoy no hay archivo |
| "s258 dejó la cadena limpia" | mirar el Oops del unwind y el phy1 en la consola del boot s258 (`consola:454005-454029`, `465814-465834`) |
| "El panel controla el brillo (systemd-backlight)" | el servicio falla en todos los boots (`consola:175581-175588` y ss.); `max_brightness=4095`, `brightness=307`, `bl_power=0` (`uke-autorecolecta.log:113-115`): el device responde pero el servicio sale con error; falta la causa (journal/dmesg) |

### H11 — MENOR — Afirmaciones presentadas como DATO con alcance discutible

- `INFORME-PHY-PANEL.md:27-30` ("el driver del panel NO está en el kernel de ESTE proyecto") es
  correcto solo para `build/kernel-pokes`; el kernel **en marcha** (#82) y el **K1** lo llevan `=y`
  (`EVIDENCIA:324`, `INFORME-K1-BUILD.md:66-70`). El plan (`:36-37`) lo dice bien; conviene unificar.
- `INFORME-PHY-PANEL.md:148-153`: del bind de los dos PHY (#410, verificable en
  `PRE-REGISTRO-F5-B1.md:266` y `uke-autorecolecta.log:70-72`) se concluye que el rail de 98 000 µA
  es "correcto para este hardware": el bind no mide el rail; es INFERENCIA (el propio informe lo
  matiza, pero la frase "luego el 8650 es correcto" suena a DATO).
- `INFORME-GPIO-RESET.md:5-16` titula "Causa raíz" al proxy ausente; era la causa del **defer**, no
  del fallo final observado (-EINVAL, con otra causa encadenada, `INFORME-GPIO-EINVAL.md:1-11`).
  La corrección existe, pero el primer informe no la referencia.
- `PRE-REGISTRO:33` (evidencia de éxito del #P1) y `:83` (K1) están bien como **expectativas**; no
  deben leerse como resultados (H1/H2).

---

## 3. Lo que falta para "la pantalla del todo", con lo que hoy se sabe

Orden propuesto (cada paso con evidencia archivada y sha):

1. **Desbloquear la tablet**: rollback por fastboot de `boot_b` (`ffff8c51…`) y confirmar
   `dtbo_b = s258` (`f4663ff8…`); registrar el estado (contadores, batería). Hoy no consta en ningún
   fichero y el vigía está pausado (H2).
2. **Cerrar la pregunta abierta del SMMU con un experimento válido**: A′ limpio reconstruido (H3) y/o
   K1 **pasando por gate 0** (H2), con lectura viva de `dtbo_b`/`compatible` y `dmesg`; el criterio
   del plan (bind + `Adding to iommu group` + desaparición de `no IOMMU`) sigue vigente.
3. **Cuando apps-smmu bindee**: `card0`/modeset. Ojo al Oops del unwind del master
   (`drm_atomic_private_obj_fini`), que hoy aparece en **todos** los boots: el criterio de cierre no
   es "no hay `-19`" sino "card0 + sin Oops" (H4).
4. **DSI1/PHY1**: hoy `ae96000.dsi` falla con `phy driver is not ready` en el boot s258 (aunque en
   el boot 12:10 ambos PHY constan ligados, `uke-autorecolecta.log:70-72`): comprobar si es un
   defer de orden que se resuelve (el plan no lo exige para card0 con panel en DSI0, pero sí para
   el panel dual).
5. **Backlight funcional**: el device existe y responde (`max 4095`, `brightness 307`,
   `uke-autorecolecta.log:99-115`) pero `systemd-backlight@…` falla en cada boot
   (`consola:175581-175588`); falta la causa.
6. **GPU/CM3 y Hyprland** (F2.4/F3 del plan): escalera CM3 antes de abrir la GPU; firmware en la
   tablet; `/dev/watchdog`/watchdog dtbo pendientes.
7. **Permanencia**: driver del panel (ya `=y` en #82/K1; el `.ko` sobra salvo kernel-pokes), el
   parche de `pinctrl-cliffs` (#83, 2 líneas,
   `INFORME-GPIO-EINVAL.md:186-204`) o mantener el puente DT con su nota; auto-carga y dtbo final.
8. **Cierre documental**: H6 (registro), H9 (docs y lecciones), H7/H8 (constructores y controles).

---

## 4. Nota metodológica de esta revisión

- No se ha tocado la tablet (ni adb, ni fastboot, ni SSH); no se ha modificado ningún fichero
  existente; este informe es el único fichero nuevo. **Sin commit.**
- Comandos de reproducción de las comprobaciones clave:
  ```bash
  cd ~/proyectos/omarchy-uke/build/bootimg && sha256sum *.img | grep -E "s238|s25[5-8]|ukek1"
  sha256sum ../backup-par-bueno/boot_b-lee.img ~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img
  cat ../gates/s253-GATES.log | tail -20
  cat ../evidencia/2026-09-28/veredicto-p1e.md
  grep -a "panel-xiaomi\|already requested\|o82_probe\|dsi_get_phy\|UKE-POKE" ~/proyectos/out/uke-ubuntu_console.log | tail
  ```
