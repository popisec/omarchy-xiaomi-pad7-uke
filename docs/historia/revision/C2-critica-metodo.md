# C2 — Crítica de método: el proyecto escribe el protocolo y lo incumple

**Alcance**: filas #450–#480 del `FLASH-LEDGER.md` (1-oct ~16:0x → 2-oct, ciclos K24→K38),
`docs/historia/gates-palawan/flash-k24.sh`, `docs/historia/gates-palawan/repack-k18.py`, `docs/historia/gates-palawan/build-k24.sh`
(y hermanos k30/k33/k34/k37/k38), `build/gates/uke-consola-lector2.sh`.
**Tesis**: la disciplina declarada ("un cambio por ciclo, sha256 pre-registrado ANTES de
flashear, predicción escrita antes de medir", rollback, presupuesto) se cumple en el
papel — shas y predicciones P-numeradas existen — pero **falla sistemáticamente en los
efectos**: lo que se verifica es el artefacto, nunca el efecto. Todos los fracasos de la
nightly (parámetro que nunca se aplicó, imagen que nunca se escribió, slot quemado con el
"limitador" puesto, consola que pierde el veredicto) pasaron **a través** de gates verdes.

Método de esta crítica: cada cargo cita fila del ledger y fichero:línea. Lo que el
proyecto hizo bien se acredita explícitamente — un auditor que solo lista culpas no es
creíble.

---

## 1. "Una escritura por ciclo" — recuento: NO se cumplió

Balance de la ventana: **~11 escrituras efectivas en `boot_a` en ~24 h** (K30 #466, K33
#469/#470, K33b #470, restore #471, ukek13-plain #471-bis intentado-fallido, mm43 #472-bis,
quiet #473, K34 #477, K35 #477, K36 #478, K37 #479-bis — más restores #457/#461 fuera de
ventana), **0 en `dtbo`**, todas sobre **el único slot arrancable** (b `unbootable` toda
la ventana). Los ciclos multi-variable, uno por uno:

- **#469 (K33): TRES cambios en un ciclo, declarado.** Sonda UKE-K32 + fix UKE-K33 +
  blindaje del unwind, justificado como "son la MISMA hipótesis". La justificación es
  honesta pero la regla estricta no admite excepciones por afinidad: si P32 (GMU mapea)
  falla y P34 (sin Oops) también, no se puede atribuir a sonda vs fix vs blindaje. De
  hecho ocurrió lo peor: **ninguna predicción P30–P35 era medible** porque el parámetro
  nunca se aplicó (#470) — tres cambios quemados en un ciclo ciego.
- **#465-bis: cambio de artefacto tras pre-registro.** Las predicciones P20–P22 se
  escribieron contra `d1c24835…` y el artefacto flasheado fue otro (`a818d666…`,
  +`hung_task_panic=0`). La re-registración existe, pero el argumento "no es una variable
  de la hipótesis" (§1.5) asume lo que habría que probar: `hung_task_panic` cambia el
  comportamiento de reboot, que es exactamente el observable que quema reintentos de slot
  (ver §5). Cambiar el aparato de medida a mitad de experimento no es "sin confounds".
- **#473 (quiet): TRES deltas de cmdline en un artefacto** — quitar `video=` + mantener
  `memmap=0x2B00000` + añadir `loglevel=4` — presentado como "arreglo de la medida, sin
  tocar el kernel". Pero `memmap=43M` **era** la variable de hipótesis P60 de #472-bis,
  colada como "aunque #472-bis [dijo] que no es la causa, es un bug real y no cuesta
  nada". Una variable refutada como causa que viaja de extranjis en el siguiente ciclo es
  exactamente lo que la regla "un cambio" prohíbe.
- **#476/#477 (K34): CINCO deltas vs el par bueno en un solo flash** — firmware en
  initramfs + `uke_kgsl_keep=0` + sin `video=` + `loglevel=4` + `memmap43`. Las
  predicciones P90–P93 reparten un delta por predicción, pero un solo boot no aísla: si
  P90 y P91 hubieran cambiado a la vez, la atribución sería imposible. Salió cara (P90 OK,
  P91 falla), **por suerte, no por diseño**. El propio ledger admite el patrón en #477
  (K35 = "mismo kernel, sin recompilar", 1 variable — ese sí limpio, acreditado).
- **#478 (K36): dos deltas** — `loglevel=6` + `hung_task_panic=0` — y la segunda trae su
  propia hipótesis (P113: "un wedge no quema el slot"). Dos hipótesis, un ciclo.
- **#471 y #479-bis: filas mixtas resultado + restore + rediseño + pre-registro.**
  #471 contiene la restauración (1 escritura), el experimento `video=` (otra escritura) y
  sus P50–P53; #472-bis contiene resultado, imagen corregida y flash. La estructura
  comprime el límite pre-registro/post-resultado hasta hacerlo inverificable para un
  lector externo: todo está "pre-registrado" porque la fila lo dice, no porque exista un
  sello temporal independiente.
- **Reflashes y recuperaciones mezclados con experimentos**: restores en #457, #461,
  #471-P1, #479-bis. Cada restore es 1–2 escrituras no asociadas a ninguna hipótesis,
  pero consumen el mismo slot y resetean contadores (ver §5), contaminando la
  contabilidad de "qué probó cada escritura".

**Parches de imagen a mano** (la categoría que el proyecto dice haber superado con
repacks versionados): #463 (parche cmdline 2 B, verificado "2 bytes cambiados" —
acreditado como limpio en diseño); **#471-bis (parche in-place offset 44, 356→384 B, que
rompió el tamaño y produjo el FAILED silencioso de #472)**; #472 (recorte "solo pad").
Tres parches manuales en la nightly, uno con consecuencia directa.

**Veredicto §1**: la regla "un cambio por ciclo" se violó en **#469, #473, #476/K34,
#478** (multi-delta) y se estiró en **#465-bis, #471, #479-bis** (filas mixtas). Solo
**#463, #466(K30-intento), #470(K33b-cmdline), #477(K35), #471-bis(diseño)** fueron
diseños de una variable — y dos de ellos nunca llegaron a ejecutarse como diseñados
(#466 sin medida; #471-bis sin escritura real).

## 2. Instrumentación que miente: el gate verde como falso "OK"

### 2.1. El parámetro fantasma: `uke_gmu_shared` nunca se aplicó (#470)

El hallazgo que invalida K24, K25-medición, K30 y K33 de un plumazo: en código built-in el
kernel antepone el nombre del módulo, el parámetro real es **`msm.uke_gmu_shared`**, y el
token desnudo fue ignorado siempre (`Unknown kernel command line parameters ...
uke_gmu_shared=0, will be passed to user space`). Consecuencias que el ledger registra
pero cuyas implicaciones de método no extrae:

- La "config #4" (s260 + shared=0) que se diagnosticó **tres semanas** "nunca se midió"
  (#470, textual). K24 concluyó "shared=0 no viable bajo s260, el GPU ni probean" (#456)
  sobre un kernel que corría shared=1. **Esa conclusión sigue escrita en #456 sin banner
  de retractación.**
- **#467 titula "P21 CONFIRMADA" con el antecedente falso.** P21 decía "si sale
  `ret=-34` ⇒ el TTBR1 no era la causa (el dominio del GMU también lo tiene)". El -34 se
  midió con dominio **compartido** (shared=1 real), luego la implicación no se puso a
  prueba; que el consecuente ocurra sin el antecedente no confirma nada. #470 corrige el
  fondo pero **el titular #467 queda como "CONFIRMADA"**. Un ledger que no enmienda sus
  titulares es un instrumento que miente a su lector futuro.
- **Ningún gate comprobaba el efecto.** Los gates G2/G6 verifican que el token esté en la
  cmdline del artefacto; nada verifica `/sys/module/msm/parameters/uke_gmu_shared`
  post-arranque. Un check SSH de una línea (el P40, escrito en #470 **después** del daño)
  habría cazado el bug en K24. La disciplina verifica la **intención** (token presente),
  nunca la **eficacia** (parámetro aplicado).

### 2.2. La imagen que nunca se escribió: 28 B y un "OK" mentiroso (#472)

El flash de #471-bis respondió OK-ish pero fastboot devolvió
`FAILED (remote: 'Error flashing partition : 0000000B')` porque el parche a mano dejó la
imagen en 100.663.324 B (28 B sobre `partition-size`). **El ciclo "midió" un kernel que
no estaba en la partición.** El gate de tamaño se añadió después a `flash-k24.sh`
(acreditado: reacción correcta y rápida). Pero el script **sigue** con dos gates que dan
falso OK hoy mismo:

- **`flash-k24.sh:42` — el check de sha es una tautología.**
  `[ "$sha" = "$(sha256sum "$IMG" | cut -d' ' -f1)" ]` compara el sha consigo mismo:
  pasa siempre, verifica nada. Un gate que no puede fallar no es un gate, es decoración.
- **`flash-k24.sh:87` — el estado del flash se pierde en el pipe.**
  `timeout 300 fastboot flash boot_a "$IMG" 2>&1 | tail -2 || die` — el exit status es el
  de `tail`, que es 0 aunque fastboot diga FAILED. **Un `FAILED (remote: ...)` imprime
  "OK boot_a escrito".** Es exactamente la clase de bug que produjo el "OK mentira" de
  #472, y sigue en el script de flash vigente. El gate de tamaño cubre el oversize, pero
  **ninguna** otra causa de FAILED quedaría detectada.
- **`flash-k24.sh:99` — el script arma el lector v1, el acusado.** Tras declarar el v1
  "descartado para arranques" porque presuntamente cuelga la tablet dentro de printk
  (#466), el propio guion de flash lanza `uke-consola-lector.sh` (v1) antes del reboot.
  O el v1 es peligroso y el script es temerario, o no lo es y el descarte fue teatro. En
  ambos casos el proyecto se contradice a sí mismo en el mismo fichero.

### 2.3. Gates que certifican presencia, no corrección

- **`repack-k18.py` G3/G3c y `build-k24.sh:90-128`**: cuentan ocurrencias de cadenas
  (`WALK iova=`, `MAPPING ENCONTRADO`, `HUECO`). R9-B2 demostró que el caminador
  "fabrica evidencia" (lee AttrIndx bits[4:2] en vez del tipo bits[1:0]; máscara que
  corta en el bit 40): **los veredictos de K24 son indistinguibles del ruido** (#465-R9,
  textual). El gate dio verde a un instrumento que mentía. Contar strings no valida
  semántica.
- **Gates que fallan al revés**: #460-bis exigió un nombre de campo (`uke_gpu_mmu`) que
  no puede existir en el binario; el gate de mtime bloqueó un rebuild legítimo; el gate
  de K33 exigió cadenas del blindaje que el compilador inlinó (hubo que pasar a
  `llvm-objdump` manual — el paso "a mano" que los gates dicen eliminar). Gates que ora
  dejan pasar basura, ora bloquean trabajo válido: calibración ausente en ambas
  direcciones.
- **Precedente #P1 (serie pantalla, mismo repo)**: gate fdtoverlay verde mientras el ABL
  ignoraba el fragmento no-numérico; el experimento "midió" un DT que nunca se aplicó.
  Misma enfermedad que #470 y #472: **verificar el artefacto, nunca el efecto**.
- **Readback abandonado**: #453 verificó la escritura con `sha256(boot_a leído)` — la
  única prueba de escritura real de todo el corpus. Ningún ciclo K30–K38 repitió la
  relectura; se confía en el OKAY de fastboot (+ gate de tamaño desde #472). Regresión
  de la disciplina dentro de la misma nightly.

**Veredicto §2**: el proyecto tiene gates de **construcción** razonables (cazaron bugs
reales: §6) y **cero gates de efecto** (parámetro aplicado, fragmento aplicado,
escritura persistida, slot superviviente). Todos los desastres de la nightly fueron
fallos de efecto con gates de construcción en verde.

## 3. Predicciones: formalmente pre-registradas, materialmente huecas

Acrédito primero: el proyecto escribe P-numeradas antes de flashear en casi todos los
ciclos (#463 P17–19, #465 P20–22, #469 P30–35, #470 P40–44, #477 P100–105, #478 P110–113,
#479 P120–122). Es más disciplina que la mayoría de proyectos. Los huecos:

- **Predicciones contra configuraciones fantasma.** P20–P22 (K30) y P30–P35 (K33) se
  escribieron contra `shared=0`, configuración que nunca existió en el aparato (#470).
  Pre-registrar la predicción correcta para el experimento equivocado no es disciplina,
  es ritual. Y #467 reclamó "P21 CONFIRMADA" sobre ese vacío (§2.1).
- **Hipótesis post-hoc con etiqueta de honestidad pero con consecuencias.**
  #466 formula la culpa del lector v1 como "NO PROBADA... es culpa de MI herramienta" y
  acto seguido **cambia el tooling** (lector2, v1 descartado). Una hipótesis no probada
  puede motivar una precaución; aquí motivó un veredicto ("Bug corregido", "el v1 queda
  descartado") que el propio flash-script desmiente (§2.2). Precaución sí; veredicto, no.
- **Reinterpretaciones retroactivas sin banner.** #458 reescribe #456-K24 como "cerrado
  con causa raíz" cuando el veredicto contemporáneo de K24 fue P2 ("no dice nada del
  wedge"). Actualización bayesiana legítima, pero la fila #456 no lleva enmienda: un
  lector que entre por #456 lee una conclusión superada. Igual que el titular #467.
- **Predicciones recicladas entre artefactos.** #472: "mismas [P60–P63] que #471-bis, que
  aún no se habían medido" — aceptable una vez; pero la cadena #471-bis→#472→#472-bis→#473
  re-adhiere las mismas preguntas a cuatro artefactos distintos (plain, mm43-oversize,
  mm43, quiet) sin que ninguna medición intermedia las ancle. Cuando todo es "aún no
  medido", nada está pre-registrado: está pospuesto.

## 4. Hipótesis durmientes y techo de 3 ciclos (docs/historia/AGENTS.md r11)

El techo ("al tercero sin movimiento en dmesg, refutada, no cuarto flash") se superó en
toda la línea:

| Hipótesis | Ciclos que la tocan | Techo |
|---|---|---|
| Quitar `:d` ⇒ panel/detección (P17–19, P50–53, P60–63, P70–72, P90–92, K34-OK) | **#463, #471, #471-bis, #472-bis, #473, #474, #477 = 7** | ×2 |
| Solape splash/s19fb como causa del cuelgue (#468 hallazgo, P60–63, P70, P70-matizado) | **#468, #471-bis, #472, #473, #474 = 5** | excedido |
| `-ERANGE`/dominio del GMU (K25, K26, K27, K30, K33, K33b, K34-P91, K35-P103) | **8** | ×2.6 |
| H2 "el volcado SMMU es el wedge" (#458 no decide, #459 P10/11, #460 P15, #469 P35, #480 "testeable") | **5 invocaciones, 0 decisiones** | peor caso: ni se testea ni se entierra |
| PHY/detección DSI (#462 no flasheado, #463, #468-paso-0, #471) | 4 | excedido |

Agravantes:

- **H2 es la hipótesis zombi**: se invoca en cinco filas y la propia R7 (#463) registra
  que "H2 sigue sin decidirse". El proyecto la mantiene viva como "siguiente paso" sin
  pagar nunca su precio (arreglar B2 antes de encender el dump). Una hipótesis que no se
  puede testear con el instrumento actual debería refutarse por impracticable, no
  heredarse.
- **El dtbo s260↔s263 flip-floppeó 4 veces en una noche** (#458 s260, #459 s263, #460
  s263, #461 restore s260) con justificaciones opuestas ("s263 no discrimina" #454 →
  "s263 hace que el attach funcione" #459 → "s263 es inviable" #460 → "s263 es
  obligatorio" #460-reconsiderado). Cada flip = 1 escritura. Esto es thrashing, no
  bisección.
- **Refutaciones que no se entierran**: el solape de memoria se descarta como causa en
  #472-bis ("P61=FALSO... queda descartada") pero `memmap43` sigue viajando en K34/K35/
  K36/K37 "porque es un bug real y no cuesta nada" (#473, #476, #479). Si no es la causa,
  es peso muerto que confunde el próximo debug de `reserved mem`. Refutar y conservar a
  la vez es no refutar.
- Atenuante real: #464 hace balance honesto ("6 configuraciones, 6 fallos") y R6/R7
  corrigen mecanismos falsos (K27-no-op, K25-H2). La autocrítica existe; lo que falta es
  el **freno**: ningún mecanismo detiene el cuarto flash.

## 5. Seguridad de datos y slots: lo que se pudo perder y lo que sigue en riesgo

### 5.1. Daños y casi-daños registrados (todos con fila)

- **#450→#451: el fsck rompió el arranque.** `e2fsck -f -y` sobre la raíz (1347 bloques
  multi-reclamados, un journal descartado por decisión automática sin backup de los
  bloques perdedores — solo se salvó el log) + `mask` de journald que **persistió en
  /etc** y dejó a systemd sin sshd. Recuperación ejemplar vía `fastboot boot`
  (cero escrituras, #451 — acreditado como el mejor ciclo de la ventana en método). Pero
  la secuencia prueba que **un ciclo "0 escrituras de particiones" puede dejar la
  máquina inarrancable** por estado persistente en el rootfs. El presupuesto cuenta
  flashes, no mutaciones persistentes.
- **#475: unbind/bind del DPU en runtime** dejó el DRM a medias (self-admitido "error
  mío"). Recuperado por reboot. Misma lección: el daño no necesita un flash.
- **Dos estados de CERO slots arrancables**: #452 (ambos `unbootable`, retry 0) y #471
  (K33b quemó a: 139→146, retry 0; b ya lo estaba). En ambos la salvación fue que el ABL
  entrara a fastboot. Si el ABL hubiera quedado en bootloop sin fastboot, la
  recuperación habría exigido EDL/desmontaje con el dueño ausente. El proyecto operó dos
  veces sin red de seguridad y lo registra sin extraer la regla.
- **Lecturas sistemáticamente mal atribuidas de los contadores**: #466 dice "el propio
  flash consumió 2 reintentos" cuando retry fue **5→7 (subió: el flash REARMA a 7**,
  igual que #453 midió "bajó a 7" — en realidad rearmó a lleno). #454 ya había tenido que
  corregir "escribir limpia unbootable" por "set_active repone contadores". Tres
  lecturas del mismo mecanismo, tres atribuciones distintas. Quien no entiende el
  contador no puede presupuestarlo.

### 5.2. La afirmación `hung_task_panic=0` es falsa en su forma fuerte

El proyecto la usa en tres versiones incompatibles:

- #454 (correcta): "`=0` hace que cueste 1 [reintento]. **Mitiga, no protege.**"
- #465-bis (límite): "limitador de riesgo" — compatible con la anterior.
- #479/#480 (falsa): "un wedge **no** queme reintentos" (P113-adjunto), "impidió además
  que quemara reintentos del slot" (#480).

**#471 refuta la versión fuerte con medición**: K33b llevaba `hung_task_panic=0` en
cmdline (#470) y quemó el slot entero (7 boots, 139→146, `unbootable:a:yes retry 0`).
Aritmética obvia que el proyecto no escribe: `=0` evita el **bucle** de panic-reboot
(7 de golpe); un kernel que wedgea **cada boot** quema 1 por boot, y 7 boots = slot
muerto igual. El "limitador" solo limita el ritmo, no el total. Y #480 afirma la versión
fuerte **sin evidencia**: no registra ningún `getvar` post-ciclo (grep: cero menciones a
slot/retry/getvar en #480). Afirmación sobre contadores sin leer contadores.

### 5.3. El "rollback" no es rollback y el estado actual es desconocido

- Con b `unbootable` desde #452 hasta #480, "rollback a `build/backup-par-bueno/`" no es
  volver a un slot arrancable: es **reflashear por fastboot tras power-cycle físico con
  el dueño presente**. El proyecto lo sabe (#463: "no hay rollback arrancable... la
  vuelta es power-cycle + fastboot + reflash") y aun así rotula cada ciclo "Rollback: 1
  escritura" como si fuera red de seguridad. Una red que exige al dueño de madrugada no
  es red.
- **Lo que haría falta para no quemar el último slot**: (a) rehabilitar b ANTES de
  experimentar (probado que funciona, #453 — nunca hecho en la nightly: b quedó
  `unbootable` de #452 a #480); (b) usar `fastboot boot` para los ensayos (probado
  cero-coste, #451 — nunca usado en K30–K37, once flashes evitables); (c) regla de parada
  por consola: no dejar 7 boots fallidos en bucle (K33b 139→146 desatendido); (d) getvar
  antes/después de CADA ciclo, incluido #480 que lo omite.
- **Estado irrecuperable ahora mismo**: no consta brick (K37 wedgea en S3-rst0 pero el
  ABL/fastboot sigue accesible históricamente). Lo que sí consta es **ignorancia**: tras
  #480 no hay `slot-retry-count`, ni `unbootable`, ni batería. Si a está en retry bajo
  con b `unbootable`, el próximo boot fallido = tercer estado de cero slots. El ciclo que
  presume de localizar el cuelgue original no midió si le queda cuerda para el siguiente.

### 5.4. Sobre "flashes ilimitados"

El GO de #456 ("no tienes límite para flasheos... procede") levantó presupuesto Y método
(lecturas SMMU). Dos matices adversariales: (1) el GO es del 1-oct para K24; la nightly
del 2-oct lo trata como permanente y lo complementa con GOs informales por fase ("tu
trabaja" #459, "haz el fix y sigue" #460) — **scope-creep sin condición de parada
escrita**; (2) flashes ilimitados ≠ slots ilimitados. La escasez era la única función
forzante de cuidado; eliminada, el ritmo subió a 11 escrituras/día sobre el único slot
vivo, y bajo ese régimen ocurrieron el overflow de tamaño (#472) y la quema con
limitador puesto (#471). La correlación no prueba causalidad, pero el proyecto no puede
afirmar que la exención "mantuvo la disciplina" (§#456) cuando sus peores fallos de
disciplina son posteriores a ella.

### 5.5. El `:d` como "discriminador nuestro"

R8 acredita el origen: ausente en vendor_boot/init_boot stock y cmdline viva — lo
ponemos nosotros (#P42). Correcto y verificado. Pero la etiqueta "discriminador"
infravalora su rol estructural, medido después: con `DRM_FORCE_OFF` el driver **se salta
la detección**; quitarlo ejecuta un camino que cuelga (#463), primero atribuido a
detección/DSI, luego a solape de memoria (#471-bis, refutado #472-bis), luego a firmware
SQE ausente (#474, confirmado #476/#477). El `:d` enmascaraba **dos bugs independientes**
(fw fuera del initramfs + `-ERANGE`) bajo una "baseline estable". Un control que oculta
dos variables no es baseline: es confound con nombre amable. El proyecto llegó al mismo
sitio por el camino largo; el coste fue #463 + #471 + #472 + #473, cuatro ciclos que el
techo no permitía.

## 6. El lector2: mejora real, promesa incumplida, defectos propios

Acrédito: el diagnóstico del v1 (cierra el fd cada 5 s) es plausible, el diseño del v2
(fd permanente + watchdog de inode) ataca la causa correcta, y el bug del pkill
auto-homicida se cazó en prueba (#466). Dicho esto:

- **Perdió líneas aún, y en el peor momento.** Con lector2 armado: #471 (`[missed 4933
  bytes]`, `[missed 2870 bytes]`, tramo crítico perdido + kernel ajeno clang 23.1.1 sin
  explicar); #474 (421 líneas, 6 pérdidas — suficiente por suerte); **#479 (130 líneas de
  >10.000, `[missed 4983][missed 851]`)**; **#480 (`[missed 9753 bytes]` justo después de
  `S3-rst0`: el veredicto del sondeo S4-pollOK/FAIL está en la cola perdida — #480-bis
  lo admite y matiza su propia conclusión principal)**. La promesa "para no perder
  líneas" es empíricamente falsa: el lector2 fija el extremo lector, pero la pérdida
  ocurre en el **gadget USB** (overrun a `loglevel=6`, cola que no drena antes del
  wedge). Arreglaron el grifo cuando la fuga estaba en el depósito.
- **Limitaciones que el proyecto NO ha medido**: throughput máximo sostenido del ACM;
  tamaño de los buffers del gadget y del host; qué pasa ante un glitch USB del PC
  (precedente 28-sep: hub EMI); configuración termios del nodo (el `cat` hereda lo que
  haya — la lección termios-RAW de #270 se aplicó al drainer, del lector2 no consta);
  crecimiento del LOG sin rotación; y la condición de carrera propia: entre el último
  `stat` y la reapertura tras re-enumeración hay hueco — el comentario del código admite
  que el sondeo a 2 s "costaba los primeros segundos" (#471-bis, boot 154 perdido en
  `[0.000000]`) y lo bajó a 0,2 s, es decir **más sondeo para tapar el hueco del sondeo**.
- **Defectos en el propio script**: `uke-consola-lector2.sh:41` lleva un `pgrep`
  sintácticamente roto (`'cat <pgrep -c -f 'cat -f' 2>/dev/null3'` — comillas anidadas):
  el contador "deben ser 1" no puede funcionar; el operador **no puede verificar la
  regla de un solo lector** con la herramienta prevista. Y no hay exclusión mutua entre
  v1 y v2: si lector2 corre y `flash-k24.sh:99` arranca v1, hay **dos lectores** — la
  condición que "hace perder el diagnóstico" (o cuelga el kernel, según la teoría del
  día) creada por el propio tooling.
- **La hipótesis fundacional sigue "NO PROBADA"** (#466, textual). El proyecto actuó
  como si el v1 hubiera colgado la tablet (descarte + relectura de docs/historia/AGENTS.md con permiso
  del dueño) sobre una hipótesis que él mismo marcó no probada — y que #467 dejó sin
  resolver (K30 arrancaba bien por SSH al reboot; la pérdida de consola del boot 137
  sigue sin explicación). Cambiar reglas con permiso sobre hipótesis no probadas es
  exactamente el patrón "pienso sobre la marcha" que el protocolo dice prohibir.

## 7. Veredicto y exigencias mínimas

El proyecto no es indisciplinado en el sentido barato (inventa datos): pre-registra
shas, numera predicciones, admite errores (R7, retractación s264, #480-bis) y reacciona
rápido (gate de tamaño en #472). **Es indisciplinado en el sentido caro: sus controles
verifican representaciones, no realidad.** Sha del artefacto pero no tamaño (hasta
#472); token en cmdline pero no parámetro aplicado (#470); marcador en binario pero no
semántica del instrumento (B2); OKAY de fastboot pero no persistencia (#472, precedente
#P1e); predicción pre-registrada pero contra configuración fantasma; rollback nominal
pero sin slot arrancable; lector "sin pérdidas" que pierde el veredicto.

Exigencias mínimas antes del próximo flash (K38):

1. **Gates de efecto obligatorios**: post-boot `/sys/module/*/parameters/` (habría
   cazado #470 en K24); readback-sha tras cada flash (habría cazado #472 sin depender
   del mensaje de fastboot); `set -o pipefail` o verificación explícita del estado de
   `fastboot flash` (el `| tail -2` actual miente); getvar de slots+batería antes Y
   después de cada ciclo (ausente en #480).
2. **Reparar o retirar**: la tautología de `flash-k24.sh:42`, el pipe de `:87`, el
   `pgrep` roto de `lector2:41`, y el armado del v1 en `flash-k24.sh:99` (v1 o v2, no
   ambos; con lock de un solo lector).
3. **Devolver la escasez o su equivalente**: rehabilitar b a estado arrancable ANTES de
   K38, o ensayar K38 por `fastboot boot` (#451). Flashear el único slot vivo por
   undécima vez con b `unbootable` no es "riesgo aceptado", es ruleta con el trabajo de
   tres semanas (rootfs userdata) como apuesta colateral — que ningún flash toque
   userdata es suerte de layout, no mérito de procedimiento.
4. **Enterrar hipótesis**: H2 (5 invocaciones, 0 decisiones) se testea en K38 o se
   declara impracticable; el solape de memoria sale de las cmdlines si ya está
   descartado como causa; el titular #467 se enmienda; la versión fuerte de
   `hung_task_panic=0` se retira del ledger (#479/#480) dejando la de #454.
5. **Techo con dientes**: la próxima hipótesis que llegue a su tercer ciclo sin
   movimiento en `dmesg` se cierra por procedimiento, aunque el dueño haya dado flashes
   ilimitados. El GO autoriza gastar flashes; no autoriza gastar el método.
