# C3 — Crítica adversarial de lo escrito HOY (2-oct-2026)

**Rol**: revisor escéptico, solo-lectura salvo este fichero. **No se ha tocado la tablet.**
**Leído íntegro**: `docs/historia/ESTADO-VIVO.md`, `docs/historia/revision/K31-causa-raiz-erange.md`, `docs/historia/revision/PLAN-2OCT-pantalla-y-gpu.md`,
`docs/historia/revision/K24-diseno-desde-evidencia.md`, `docs/historia/revision/R6-gmu-erange.md`, `docs/historia/revision/R8-repaso-android.md`, `docs/historia/revision/R9-busqueda-errores.md`,
`docs/historia/revision/R10-repaso-general.md`, `docs/historia/AGENTS.md`, ledger `#465–#480` (`FLASH-LEDGER.md:6830–7828`).
**Tesis**: lo escrito hoy contiene una medición invalidada que se sigue citando como hecho
(`#470` invalida `#467`, pero `ESTADO`, `K31`-cuerpo y `PLAN` siguen afirmándola),
varias generalizaciones "NUNCA/SIEMPRE" con n=1–2, y dos documentos rectores
(`ESTADO`, `PLAN`) congelados en `#467` cuando el ledger ya va por `#480`.

---

## 0. Veredicto en 8 líneas

1. La afirmación estrella de hoy ("con dominio propio también falla `-ERANGE`, compartir NO era
   la causa") es **FALSA por parámetro nunca aplicado** (`#470`). `ESTADO:19-21,54,88` y el cuerpo
   de `K31` la siguen afirmando; solo el banner de `K31` la retracta.
2. `docs/historia/ESTADO-VIVO.md` y `PLAN-2OCT` están **obsoletos al leerlos**: describen K30 como "pendiente de
   medir" y prescriben "sonda (a)/(b)" cuando el ledger ya mapeó el GMU (`#478` P103 OK), ya arrancó
   sin `:d` (`#477`), ya encontró el firmware (`#476`) y ya llegó a `S3-rst0` (`#480`).
3. La generalización "el firmware NUNCA estuvo disponible" (`#476`) es un **overclaim**: solo se
   midieron 2 cpio, y contradice `K24 §1` (GMU fw v4.5.1 F3/F4 OK). Lo que nunca estuvo disponible
   fue el **SQE en initramfs temprano**, no "el firmware".
4. "El cuelgue ORIGINAL, localizado" (`#480`) lo **matiza el propio autor 20 líneas después**
   (`#480-bis`: `[missed 9753 bytes]`, S4 desconocido). Citar `#480` sin `#480-bis` es citar media fila.
5. Hay **reversales en 24 h** sin marcar como tales: `#468` "pantalla bloqueada por GMU" vs `#471`
   "pantalla NO depende del GMU"; `#474` "cuelgue es GMU detrás de SQE" vs `#475` "SQE falla también
   con `:d`, causa es `firmware_class.path`".
6. `R6 §4` (s263+compartir como arreglo) sigue legible como prescripción cuando **es K26 medido
   y fallido** (`-EBUSY`, R10 C3). El banner de `R6` dice "mecánica correcta, sujeto equivocado" pero
   el cuerpo §4 no se tocó.
7. Conteo de hoy: **~9 escrituras en un día natural** con `slot b` en 0/`unbootable` todo el día,
   un flash fantasma (`#472`: 28 B de más, `OK` mentiroso), un ciclo triple (`#469`: sonda+fix+
   blindaje) y un `unbind/bind` en runtime con disculpa (`#475`). Ver §5.
8. Lo que hay que creer hoy: `R8` (stock/SID5/SSC/43 MB/6 números), `R9` B1–B3 (lectura de código),
   la cadena mecánica TTBR1 (`R6 §1–§3`, `K31` cadena de 5 filas), `#470` (prefijo `msm.`), `#476–#480`
   (firmware→mapeo→S3). Todo lo demás, verificar antes de flashear.

---

## 1. Afirmaciones de hoy: medida / inferida / inventada

| # | Afirmación (dónde) | Veredicto | Por qué |
|---|---|---|---|
| A1 | "con `uke_gmu_shared=0` (dominio propio) el GMU **sigue** dando `-ERANGE` ⇒ compartir NO era la causa" (`ESTADO:19-21`, `ESTADO:54` fila 7, `ESTADO:88`, `K31` cuerpo L17-23, `#467:7045-7053`) | **INVALIDADA (era medida, hoy falsa)** | `#470:7261-7295` demuestra que `uke_gmu_shared=0` desnudo **fue siempre ignorado** (`/sys/module/msm/parameters/uke_gmu_shared = 1` pese a cmdline + `Unknown kernel command line parameters` en log). K24, K30 y K33 corrieron con `shared=1`. El `-ERANGE` medido es el del dominio compartido TTBR1 (coherente con `R6`). Solo el banner de `K31:3-15` lo admite; el cuerpo y `ESTADO` no se corrigieron. |
| A2 | "`K30 lo ha REFUTADO` … `R6 se equivocó en el sujeto`" (`K31:17-23`) | **REFUTACIÓN REFUTADA** | Depende de A1. Con `#470`, K30 no refuta nada del sujeto. El banner (`K31:3-15`) dice "sí invalida la afirmación de que con dominio propio también falla", pero el subtítulo de abajo (`K31:17-23`) sigue diciendo lo contrario **en el mismo fichero**. Contradicción interna, no matiz. |
| A3 | "`msm.uke_gmu_shared` es el nombre real (prefijo del módulo)" (`K31:3-5`, `#470:7280-7289`, `#477:7631-7635`) | **MEDIDA (esta sí)** | Tres patas independientes: sysfs=1 vs cmdline=0 (`#470:7276-7278`), `Unknown kernel command line parameters` en log (`#470:7284-7286`), y desaparición de `UKE-K20: COMPARTIENDO` + P101 OK tras el prefijo (`#478:7675`). Crédito donde toca: es el hallazgo metodológico más sólido del día. Lo no escrito: la auditoría completa (¿`uke_smmu_dump` desnudo también se ignora? ¿`uke_kgsl_keep`?). Ver §6. |
| A4 | "el firmware de la GPU NUNCA estuvo disponible" / "el DPU nunca ha tenido firmware" (`#476:7560-7570`) | **INFERIDA (overclaim, n=2)** | Medido: `cpio -it \| grep -c gen71100 = 0` en **dos** cpio (`uke-k22`, `uke-k12`). "NUNCA en este proyecto" exigiría todos los kernels (K25/K30/K33/…). Además contradice `K24 §1` (fw GMU v4.5.1 F3/F4 OK): lo que faltaba era **`gen71100_sqe.fw` en initramfs temprano** (petición a ~4.1 s, rootfs aún sin montar), no "el firmware". El propio `#476` lo delimita bien en el cuerpo pero lo generaliza en el título. Y `#475:7527-7531` ya había "arreglado" el fw en `/vendor/firmware` (persistente, hash OK) para luego declarar P80 FALLIDO (`#476:7571-7573`): dos "fixes" sucesivos del mismo `-2`, el primero inútil. |
| A5 | "hemos llegado al cuelgue ORIGINAL del proyecto" (`#478:7685-7690`); "EL CM3 LLEGA A S3-rst0 POR PRIMERA VEZ. El cuelgue original, localizado" (`#480:7753`) | **INFERIDA (prematura)** | P103 OK (mapea) + cuelgue silencioso a ~4.15 s sin error ni Oops es progreso real. Pero "original" exige identidad con `#447/#452` (S1→S2 sin S3), y `#480-bis:7800-7821` retracta: `[missed 9753 bytes]` justo tras S3, S4-pollOK/FAIL perdidos ⇒ "no puedo afirmar que el kernel muera ahí: podría ser el poll esperando". La corrección de honestidad está en la misma fila y casi nadie la cita. Citar `#480` sin `#480-bis` es fabricar certeza. |
| A6 | "sin `video=` la tablet arranca" (`#477:7611-7613`, K34) vs "quitar `:d` ⇒ el arranque se cuelga (medido)" (`ESTADO:69-70`, `#471-bis`, `#472-bis`) | **AMBAS MEDIDAS, DISTINTO KERNEL (falta acotar)** | `#471-bis`/`#472-bis` (kernel bueno K13 sin fw en initramfs): sin `:d` NO arranca. `#477` (K34 con SQE en initramfs): sin `:d` SÍ arranca y llega a login+SSH. `ESTADO:69-70` solo conserva la primera y omite la segunda (congelado en `#467`). La frase correcta: "sin `:d` cuelga **si el SQE no está en initramfs**; con K34 arranca pero sin DRM". No está escrita en ningún doc del proyecto. |
| A7 | "`slot a` en retry 7: si 7 es el máximo, un solo arranque fallido deja CERO slots" (`ESTADO:37-39`, `#466:6990-6994`) | **INFERIDA (máximo no medido)** | Medido: flash consume 2 reintentos (5→7, `#466:6989-6991`), `b` en 0/`unbootable`. "7 es el máximo de este bootloader" no tiene fuente (ningún `getvar` lo dice, ningún doc del ABL citado). Se repite como hecho en `ESTADO`, `PLAN:122`, `#465-bis`, `#469`. Formulación honesta: "a en 7 con b muerto; **si** 7 fuera el máximo…". El riesgo operativo es el mismo, la certeza no. |
| A8 | "bajo s260 la tablet arranca con red aunque el GMU falle (medido en K25) ⇒ el error se lee por SSH" (`ESTADO:83-86`, `#465:6840-6843`, `PLAN:101-103`, R10 §2) | **MEDIDA UNA VEZ, FALLIDA COMO GARANTÍA** | K25 tuvo red; **K30 `#466:7002-7016` NO**: 146 líneas vs 16–17 k, parada en [36.9 s], sin gadget/NCM/SSH. La causa probable fue la herramienta (lector v1 `timeout 5 cat` cerraba el fd, `#466:7011-7016`), no el kernel — pero eso convierte "s260 como arnés" en "s260 + lector2 + suerte". El diseño era correcto; presentarlo como propiedad del dtbo, no. |
| A9 | "arreglo mínimo: s263 + dominio compartido K20" (`R6 §4`, `R6:184-192`) | **REFUTADA COMO PRESCRIPCIÓN** | `#464`/`R10 C3`: s263+sharing **es K26 y dio `-16`** (n=2: K26 lado GMU, K27 lado GPU; grupo SID 5 admite un solo attach). R10 C3 lo dice claro ("acierta el mecanismo y falla la prescripción; quedarse con §1–§3 y §6, descartar §4.3-operativo"), pero `R6` cuerpo §4 sigue prescribiéndolo y `PLAN:17-18` lo re-cita sin el descargo. |
| A10 | Cadena `#474`: "sin `:d` el DPU pide SQE ⇒ lo inicializa el GMU que falla con `-ERANGE` ⇒ el DPU se atasca ⇒ cuelgue" (`#474:7493-7500`) | **INFERIDA Y SUPERADA EN LA FILA SIGUIENTE** | `#475:7520-7525` mide que el SQE falla **también con `:d`** y la causa es `firmware_class.path=/vendor/…` inexistente en nuestra rootfs (rutas que llegan tarde), no el GMU. `#474` queda como hipótesis intermedia fósil. Bien que `#475` la corrija; mal que ambas queden como "cadena REAL" sin marcar la primera como muerta. |
| A11 | "K24 supera mapeos, llega a S3/F3/F4" (`R6:156-157`) vs "s260+shared=0: GPU no probean, sin diagnóstico" (`PLAN:79`, `ESTADO:51`, `#464`) | **EMPATE DE INFERENCIAS (ambas sin base tras `#470`)** | Los dos relatos describen ciclos con token desnudo (= `shared=1` real). R10 C9 lo vio antes de `#470` ("init-OK vs probe-OK pueden ser verdad a la vez"); tras `#470` hay que añadir: **ninguno midió dominio propio**. K30-remide tampoco lo midió. Solo K35 (`msm.` prefijo, `#478` P101/P103 OK) mide dominio propio por primera vez. |
| A12 | "el fix UKE-K33 funciona en (a) y (b), la sonda solo explica" (`#469:7194-7198`) | **INFERIDA, NUNCA PROBADA** | Sin dominio propio, `init_context` del GMU no corre y `UKE-K33` no aparece (`#470:7293-7295`). `#477-bis:7650-7670` lo corrige bien: con dominio propio el `return 0` de `arm-smmu-qcom.c:369` ya evita TTBR1 ⇒ UKE-K33 es defensa en profundidad, no el mecanismo. P102 reformulada a P102bis (que NO aparezca es lo correcto). La frase de `#469` debe leerse con la enmienda de `#477-bis`, no sola. |

---

## 2. Contradicciones internas (qué manda)

| # | Choque | Qué manda |
|---|---|---|
| C1 | `ESTADO` fila 7 (`ESTADO:54`: "s260+shared=0 K30 → `-ERANGE` MEDIDO, compartir NO era la causa") vs `#470` (parámetro nunca aplicado) | **Manda `#470` + banner `K31:3-15`**. La fila 7 es falsa hoy; fue `shared=1`. R10 E1/E2 habían quedado bien corregidos (fila 1 = `shared=1`, fila 5 = s263+shared=0 no probada — `ESTADO:48,52`, `PLAN:76,80`), pero la fila 7 reintroduce el mismo error que E1 denunciaba. |
| C2 | `K31` banner (`K31:3-15`: "sí invalida que con dominio propio también falla") vs `K31` cuerpo (`K31:17-23`: "K30 lo ha REFUTADO… R6 se equivocó en el sujeto") y cadena (`K31:25-32`: "da igual que comparta o no") | **Manda el banner**. El cuerpo es pre-`#470` y no se reescribió. Lectura segura: cadena mecánica (VM `0x0..0x80000000` + iovas <4 GB + TTBR1 rechaza <4 GB, `K31:36-42`) **sí**; "probado con dominio propio" **no**. |
| C3 | `ESTADO:65-72` ("quitar `:d` cuelga en detección; no es el arreglo") vs `#477` ("K34 ARRANCA SIN `:d`") y `#474/#475` (cuelgue = firmware, no detección) | **Mandan `#477`/`#476`/`#480`**. `ESTADO` congelado en `#467`. La frase "el cuelgue está en el camino de detección, no en el flag" era la mejor lectura con K13; con K34 es el SQE/initramfs y después el GMU. |
| C4 | `#468:7125-7131` ("sin GPU no hay DRM ⇒ la pantalla NO puede arreglarse; prioridad invertida: primero GMU") vs `#471:7328-7332` ("con el kernel bueno el GPU funciona y el DRM existe, luego la pantalla NO depende del GMU… Mi conclusión de #468 era correcta pero no [basta]") | **Manda `#471` matizado por `#477`**: K13 comparte mmu y probean (vía compartida funciona); K34 sin `:d` arranca pero sin `card0` porque el GMU no mapea. "Sin GPU no hay DRM" es verdad estructural (DRM nace del platform del GPU); "pantalla bloqueada por GMU" era verdad solo para kernels con `-ERANGE`. El autor se corrige (`#471:7330-7332`, con typos "yany/mio" — §4), pero `ESTADO:10-12` conserva la versión `#468`. |
| C5 | `#474` (culpa al GMU detrás del SQE) vs `#475` (culpa a `firmware_class.path` + rootfs tardía) | **Manda `#475` + `#476`**. `#474` es hipótesis intermedia. El plan que deriva de `#474` ("volver a UKE-K33") es correcto por casualidad, no por esa cadena. |
| C6 | `ESTADO:75-93` ("K30 FLASHEADO, PENDIENTE DE MEDIR", "siguiente paso: sonda (a)/(b)") y `PLAN:99-107` (P20/P21/P22, "ciclo en marcha #465") vs ledger `#468–#480` | **Manda el ledger**. P20/P21 murieron en `#470`; P22 (dump=1) quedó bloqueada por R10 §2 (B2 fabrica evidencia + B3 cuelga resume) y superada por K34-38; la sonda (a)/(b) quedó bypassed por `#477-bis` (el `return 0` la hace innecesaria) y pendiente solo como WARN (`#480` K38 propuesto). |
| C7 | `R6` banner ("sujeto equivocado, mecánica correcta") vs `R6` cuerpo §2–§4 (dominio propio "mapearía bien", "K24 supera mapeos", prescripción s263+compartir) | **Manda banner + R10 C3**: quedarse con `R6 §1–§3, §6` (rastreo `-ERANGE`, `io-pgtable-arm.c:599`, doble-put de BOs), descartar §4-operativo y la frase "K24 supera mapeos" (pre-`#470`). |
| C8 | `#466` ("INALCANZABLE, consola muda desde [36.9 s]", `ESTADO:27`) vs `#467` ("SSH funciona", misma imagen K30) | **Manda la conjunción**: la imagen no determina la observabilidad; el lector sí. Lección ya extraída (lector2, `#466:7030-7036`), pero `ESTADO:27` fija solo la primera mitad como "estado". |
| C9 | Taquigrafía "icache@0x4000 cae en la baja y por eso `-ERANGE`" (`ESTADO:56-57`, `PLAN:17-18,82-84`) vs `R6:103-109` + R10 E6 (primera víctima `debug@0x60400000`, icache ni se intenta) | **Mandan `R6`/R10**. Cuarta supervivencia de la versión imprecisa tras una reescritura (R10 E6). No cambia decisiones; sí credibilidad. |
| C10 | `PLAN:93-97` ("el rechazo con o sin TTBR1", "K24 sin diagnosticar") vs `R6 §3` (en plano el `0x4000` sí mapea) | **Manda `R6`**, como ya dictaminó R10 E3. `PLAN` reabre lo que `R6` cerró. Tras `#478` P103 OK (mapea con dominio propio sin TTBR1) la frase de `PLAN` es doblemente falsa. |

---

## 3. Documentos obsoletos que aún se leen como vigentes

- **`docs/historia/ESTADO-VIVO.md` (reescrito 2-oct ~03:1x, congelado en `#467`)**: ignora `#468–#480` (cero menciones a SQE/initramfs, prefijo `msm.`, K34–K38, S3-rst0). Sus "próximos 3 pasos" (`ESTADO:119-128`: flashear K30, "ronda R10 ya hecha", memmap>SSC) ya ocurrieron o mutaron. Su tabla (fila 7) es falsa tras `#470`. **No usar como estado; usar el ledger `#476–#480` + §1 de este informe hasta reescribir.**
- **`docs/historia/revision/PLAN-2OCT-pantalla-y-gpu.md` (2ª reescritura)**: su "ciclo en marcha K30" (`PLAN:99-103`), su orden (`PLAN:113-118`: K30 → Paso 0 PHY → SSC) y sus 3 candidatos pantalla presuponen el modelo "detección/memmap" previo al firmware. Tras `#476–#478` el orden real fue firmware→`msm.`→S3, y el SSC/memmap quedaron como bugs reales pero no causales (`#472-bis` P61 FALSO, `#474` P70). **No ejecutar su orden; archivar como pre-firmware.**
- **`docs/historia/revision/K24-diseno-desde-evidencia.md`**: el banner superior (`K24:3-22`) es correcto y debe obedecerse (no ejecutar §1/§2/§4/§5b). Pero §4 (`K24:142-162`: "con s263 la máquina NO se muere") sigue legible y ya fue degradado a hipótesis con confounds (`K24 §5d-D1`); y §5b (shared=0 bajo s260) describe un ciclo que **nunca corrió como dice** (`#470`). Mantener por trazabilidad C1/C2, no por plan.
- **`docs/historia/revision/R6-gmu-erange.md`**: conservar por cadena y mediciones (ID1/TLB/rangos), citar **solo** como "mecánica correcta, sujeto y prescripción superados" (su propio banner `R6:3-20`). Su §4.3-operativo (s263+K20) es K26 fallido.
- **`docs/historia/revision/R7-auditoria-2oct.md`**: alcance `#450–#461`; no cubre `#465+`. Su §E (ambigüedad sesión-vs-día en "≤2/día", R10 E7) sigue sin fijar criterio, y hoy hubo ~9 escrituras (ver §5). No citarlo como gate de hoy.
- **`docs/historia/revision/R10-repaso-general.md`**: su §2 ("K30 bien planteado, evita B1, B2 dormido") presupone `shared=0` efectivo — falso pre-`#470`. Su enmienda P22a/P22b (no `dump=1` hasta F3+F4) **sí sigue vigente** y es lo que impidió quemar un ciclo en evidencia fabricada. Su E5 ("ESTADO paso 2 obsoleto al nacer") hoy es E5².
- **`docs/historia/revision/R5-panel-dual-dsi.md`**: su prescripción PHY-okay queda **cerrada en negativo** por `#468:7133-7144` (ambos DSI y PHY ya `okay` en DT vivo; `dsi_get_phy` era deferral). Archivar; no flashear D1/F5 por esa vía. Sigue válido su método (DT vivo manda, no el base) y su aviso de `:d` como confusor.
- **Siguen vigentes**: `R8` (stock/SID 5/SSC/43 MB/6 números — referencia de fábrica), `R9` B1/B2/B3/D1 (lectura de código; B1-MMU vs segundo UAF-GEM de `#467` son dos bugs distintos — ver §6), `K31` cadena mecánica + nudo (a)/(b) reformulado por `#477-bis`/`#480`, `#470` (prefijo), `#476–#480` (firmware→mapeo→S3).

---

## 4. Basura CJK / typos colados hoy

| Dónde | Qué | Detalle |
|---|---|---|
| Ledger `#465-bis:6931` | `，` fullwidth (U+FF0C) | "`d1c24835…`，resultó" — coma CJK en vez de `,`. Buscar `，` en el ledger solo da esta línea. |
| Ledger `#467:7069`, `#241:5947` | mojibake `hab��a` | UTF-8 truncado ("había"). Dos ocurrencias. |
| Ledger `#467:7070` | "R9 Routó" | Probablemente "rotuló/documentó". Ininteligible tal cual. |
| Ledger `#471:7321` | "No se haaudcado" | Falta espacio ("ha audac…/auditado"). Fila que declara causa abierta (K33b no arranca) con typo en la palabra clave. |
| Ledger `#471:7331-7332` | "no yany que…" + "mio compartido" | "yany" (¿"ya ni"?) y "mio" por "mmu". En la autocorrección `#468→#471`, el párrafo más citado. |
| Ledger `#472-bis:7461` | "Hintió" | Spanglish ("hinted"). |
| Ledger `#478:7680` | "anticipationó" | Spanglish ("anticipó"). |
| Ledger `#465:6900` | "motivo de choose" | Slip al inglés ("de elegir"). |
| Ledger `#465/R8:6903` | "2amada premisa" | "llamada". Título de sección. |
| Ledger `#472-bis:7432` | "sí écritió" | "escribió". En la frase que afirma que el flash esta vez sí fue real — la palabra que da fe está mal escrita. |
| `ESTADO:43` | "no lalazada" | "…falta el diagnóstico, no lalazada" (¿"la lazada"?). Encabezado de la sección GPU. |
| `K24:161` | `請` (U+8ACB) | "en lugar de請 un power-cycle". CJK suelto en el hallazgo de coste cero. |
| `K24:271` | "Could be" | "el propio dump Could be lo que cuelga". Slip al inglés en §5c. |
| `AGENTS:62` | `火影` | "el 1-oct火影 bloqueó…" (CJK en la corrección del dueño). Preexistente, pero hoy se cita como regla viva. |

Ninguno cambia el silicio; todos cambian la confianza: un ledger con `OK mentiroso` (`#472`), mojibake y Spanglish en las filas decisivas no es un instrumento de precisión.

---

## 5. Reglas de `docs/historia/AGENTS.md` incumplidas hoy (con evidencia)

1. **"sha256 pre-registrado ANTES de flashear + verificación por lectura al tamaño exacto"** — **INCUMPLIDA en `#472`**. Imagen de 100.663.324 B (28 B sobre `partition-size:boot_a = 0x6000000`), `fastboot: FAILED 0000000B`, pero el ciclo anterior (`#471-bis` 13:53:19 `OK boot_a escrito`) **nunca escribió nada** y el script reportó `OK`. El gate de tamaño se añadió **después** (`#472:7418-7420`). La regla 10 (gates `[ -f ]`/magia antes de `dd`) tiene el mismo espíritu.
2. **"Un cambio por ciclo"** — **INCUMPLIDA en `#469` (K33)**. Tres cambios en un ciclo (sonda K32 + fix K33 + blindaje unwind, `#469:7180-7192`), justificados como "misma hipótesis". Además `#465-bis` añade `hung_task_panic=0` al artefacto K30 (defendido como "no variable", `#465-bis:6938-6941` — aceptable pero segundo cambio lógico), y `#476`/K34 apila firmware + `uke_kgsl_keep=0` + memmap + loglevel en la cmdline. La regla admite la excepción cmdline (`K24 §5d-D3`), pero `#469` son 3 cambios de **código**.
3. **"≤2 escrituras por día; si `retry:b`<3, ese día solo lectura"** — **INCUMPLIDA por volumen**. El 2-oct natural acumula: `#466` K30b (1) + `#471` restore (1) + `#471-bis` ukek13 (1, fantasma) + `#472-bis` mm43 (1) + `#473` quiet (1) + K34 (1) + K35 (1) + K36 (1) + K37 (1) ≈ **9 escrituras**, con `slot b` en 0/`unbootable` **todo el día** (`#466:6989`, `#471:7316-7318`). No hay exención escrita del dueño para el 2-oct en las filas (la citada es "7 el 1-oct con exención", `PLAN:123`). R7 §E / R10 E7 ya advirtieron que el criterio sesión-vs-día no está fijado.
4. **"Nunca romper el arranque bueno / no hay rollback arrancable"** — **RIESGO MATERIALIZADO dos veces**. `#471:7315-7318` y `#471-bis:7367-7370` dejan **CERO slots arrancables** (`a:yes retry 0` + `b:yes`), salvados solo por fastboot + reflash manual del par bueno. `ESTADO:37-39` y `PLAN:122` lo advierten, pero se flasheó igual sin power-cycle garantizado (el dueño no estaba la noche K30, `#465-bis:6933-6935`).
5. **"`/dev/ttyACM0`: un solo lector, siempre uno abierto; builds desprendidos"** — **INCUMPLIDA y con causa probable**. `#466:7011-7016` admite que el lector v1 (`timeout 5 cat` en bucle) cerraba el fd cada 5 s y pudo colgar la tablet en `printk` (pérdida 146 vs 16 k líneas, parada en 36.9 s, sin gadget). Corregido con lector2 (`#466:7030-7036`). Y `#469-bis:7227-7237`: build con `-j$(nproc)`=16 y 548 procesos ⇒ `Error 127`, más `O=` a directorio inexistente — contra la regla 6 y la lección añadida ("nunca `-j$(nproc)`").
6. **Regla 3: "nunca instrumentar SMMU en runtime / solo en arranque" + "unbind/bind"** — **INCUMPLIDA en `#475:7533-7539`**. `unbind/bind` de `ae01000.display-controller` en runtime dejó el DRM a medias (`/sys/class/drm` solo `version`); el autor pide disculpas y lo fía a reinicio. La sonda K32/K33 (solo `pr_info`, `#469:7184`) sí la cumple; el `dump=1` sigue correctamente apagado (R10 §2.2).
7. **"Techo de 3 ciclos por hipótesis" (regla 11)** — **EXCEDIDO para "shared/TTBR1"**. K25 → K26 → K27 → K30 → K33 → K33b → K35 son 7 ciclos sobre la misma hipótesis. Atenuante real: `#470` demuestra que los 5 primeros no probaban lo que decían (parámetro ignorado), así que el contador honesto reinicia en K35 (P101/P103 OK). Pero entonces debió anotarse como refutada-la-medición, no como racha.
8. **"Semáforo inter-proyecto / e2fsck+backup+BCB antes de tocar"** — **SIN EVIDENCIA en `#465–#480`**. Ninguna fila cita `ESTADO-ACTUAL.md` del hermano ni sesión viva; ningún e2fsck/BCB de hoy (el fs "CERRADO" citado en `ESTADO:35` es de `#450/#457`). Backup del par bueno sí existe y se usó dos veces (`#471`, `#479-bis`) — cumplimiento parcial.
9. **"Protocolo de notas: commit + ESTADO + NOTAS al terminar"** — **INCUMPLIDO**. `docs/historia/ESTADO-VIVO.md` no se toca desde `#467` (tres generaciones de hallazgos sin volcar: firmware, `msm.`, S3). Ninguna fila `#465–#480` cita commit del repo omarchy-uke. La regla dice que `ESTADO` "es el único fichero que se edita a menudo" (`AGENTS:131-132`); hoy fue el que menos se editó.

Cumplido hoy (consta): batería ≥3700 en cada gate (`#465-bis:6948-6951`, `#466:6993-6994`), `getvar all` antes/después la mayoría de ciclos, predicciones pre-registradas P20–P122 antes de medir, rollback declarado en cada fila, y la autocorrección `#470`/`#477-bis`/`#480-bis` (honestidad que permite esta crítica).

---

## 6. Lo que NO se escribió y debería

1. **Auditoría completa del prefijo `msm.`** (el hallazgo de `#470` generalizado). Si `uke_gmu_shared` built-in exige `msm.`, ¿qué pasa con `uke_smmu_dump` desnudo (P22 lo proponía desnudo, `PLAN:106-107`), `uke_kgsl_keep`, `uke_attach_log` (este sí iba con `arm_smmu.` y funcionaba)? La regla "todo `module_param` built-in lleva prefijo" no está en ningún fichero del proyecto. Es la lección más barata del día y no está escrita.
2. **K33b quemó el slot sin diagnóstico y se abandonó** (`#471:7315-7324`): 7 arranques (139→146), `retry 0`, consola con `[missed]` y un `Linux version clang 23.1.1` que "no es ninguno de los nuestros". "Queda abierto y NO se afirma causa" es honesto; que no tenga número de hipótesis ni plan de cierre (¿imagen corrupta? ¿slot accounting? ¿mystery kernel?) lo convierte en cabo suelto con poder de veto sobre UKE-K33.
3. **El principio "early-probe necesita initramfs"** (`#476:7562-7575`). La corrección `/vendor/firmware` → initramfs (P80 FALLIDO → P90 OK) es un invariante del aparato (DPU probean a ~4.1 s, rootfs sin montar), no una anécdota. Debería ser regla operativa (dónde va cada fw según quién lo pide y cuándo), no solo narrativa de fila.
4. **P91 FALLIDO silencioso** (`#477:7619-7620`: `uke_kgsl_keep=0` NO arregla `-ERANGE`, "no se afirma causa"). Correcto no afirmar; incorrecto no abrir hipótesis: ¿qué regresión mete la instrumentación posterior a K13? Se archivó porque K35 funcionó, pero K13-vs-K34 difieren en más que el fw.
5. **Dos UAF distintos sin reconciliar**: R9-B1 (doble-destroy `msm_mmu` compartido) vs `#467` (doble-put/unmap GEM con `shared=0`, `pc=0x10000000c`). `#467:7068-7072` dice "segundo UAF, no es B1" — bien. Pero R9 no se actualizó, y los fixes R10 §3 (F1 `bo->obj=NULL`, F2 guarda B1, F3 walk, F4 B3) **no constan como aterrizados** en ningún ledger posterior. ¿Siguen pendientes con CM3 ya en S3? Nadie lo dice.
6. **K38 existe solo en la cola del ledger** (`#480:7823-7828`: K32/K33 a WARN + sonda SME↔CBnDx del SID 5). No está en ningún doc de omarchy-uke, ni en `PLAN`, ni en `ESTADO`. El próximo ciclo real del proyecto vive en 6 líneas al final de una fila del proyecto hermano.
7. **Criterio "≤2/día" y "7 es el máximo"** siguen sin fijarse (R10 E7). Tras un día de ~9 escrituras y dos "cero slots", el proyecto necesita una línea: día natural vs ventana 24 h, qué cuenta como escritura (¿el flash fantasma cuenta? ¿el restore cuenta?), y el máximo real del ABL (¿7? ¿se leyó en algún `getvar` o manual?).
8. **Pantalla tras K34**: `#477:7622-7629` (arranca sin `:d` pero sin `card0`/CRTC/modos porque el GPU no probean) + `#478` (con GMU mapeando, cuelga en CM3) + `#468` (overlap `splash_region`/`s19fb` real pero no causal, `#472-bis`) = el estado consolidado "pantalla: arranca, sin DRM, sin CRTC, a la espera del CM3" **no está en ningún fichero del proyecto**. Los 3 candidatos R8 §7 (memmap/SSC/o82) se ordenaron bajo el modelo muerto ("hang en detección") y nunca se retiraron formalmente tras el reframe a firmware/GMU.

---

*Fin C3. Si algo de lo de arriba es falso, que se corrija con `fichero:línea` o nº de fila, no con memoria.*
