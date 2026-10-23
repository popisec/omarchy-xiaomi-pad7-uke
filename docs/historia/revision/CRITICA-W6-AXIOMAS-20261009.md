# CRÍTICA-W6-AXIOMAS — ataque a (a)-(e) (2026-10-09, solo lectura)

> Estado: tablet colgada en k67; testbed de respaldo k52b2+s273 (SSH vivo a las 04:3x, #554).
> Ledger manda: `~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md` #553–#556.
> Esta nota NO flashea, NO rebootea, NO toca la tablet. Solo lee repo + ledger + disco.

## Tabla

| Axioma | Evidencia que lo sostiene | Antigüedad | Explicación alternativa que encaja con TODO | Qué veredicto de hoy invalida si cae |
|---|---|---|---|---|
| (a) silencio pre-USB 4+ min con lector armado = el kernel muere en el probe GMU/resume | #553 k65 4 min cero bytes; #555 k66 6+ min cero bytes; #556 k67 4+ min cero bytes; reconstrucción #554 (02:50 = k63+s273, no k52b2) | **horas** (9-oct 04:x–13:x) | (i) muerte en ABL/dtbo/early-boot antes del kernel: s273 es F1+F2 experimental; el ABL ya colgó con DTB nuestros (#328) y su mergeador ignora /chosen (#496–#497); (ii) gadget USB roto por el propio s273/entorno host (cap 4096 B #490; wedge endpoint + `getvar` colgado + cura por reconectar cable #492); (iii) hambre de power/rails (D1/D2 tocan GPLL0/CX sin voto); (iv) **precedente interno: k63+s273 YA era silencioso con 0 bytes y sin D1/D2/D3** (#548d 8-oct 19:51; #548c–#548e) | Exoneración de D3 por k66 (#555) y de D2 por k67 (#556); "D1 sospechoso nº1"; dirección k68-D2-solo. Todo W3/W4 colapsa: los tres silencios son idénticos porque mueren en el mismo sitio ANTES de los testigos |
| (b) `pr_err` pasa el tope de consola K41 (validado por K43) | #488 K41 built (tope `UKE_CONSOLE_LOGLEVEL_MAX=4` en `printk.c`); #489 K41 medido (`missed` gigante fuera); #492 tope suprime `level>=4` (K42 0/7); #494 K43 `pr_err` 157–158 pokes/boot, P173/P174 | **7 días** (2-oct 18:40–22:36 → 9-oct) | (i) validado en linaje k18-tree/`adreno_bind`, NO en k52-tree/`a6xx_gmu_resume`: si la muerte es anterior al primer testigo D1, "pasa el tope" es vacuo; (ii) el tope sigue en fuente (verificado hoy: `k52-tree/.../printk.c:1305` `MAX=4`; gates build-k66 exigen marcador K41 + `pr_err` y prohíben `pr_warn`) pero el runtime k65+ **nunca emitió ni un `pr_err`** — indistinguible de "muerte antes del testigo"; (iii) cero bytes ≠ cero emits: cap host 4096 B + ACM atascado por ráfagas (#490, 3 boots sin entrega) + lector "armado" ≠ lector vivo | "Silencio con testigos `pr_err` = muerte antes de D1/D2" y todos los gates G8/log-recompuesto vacíos como prueba. La ausencia de `UKE-K65/K66/K67` deja de localizar nada |
| (c) el WDT resetea a ~2 min si hay wedge | #328/#329 m1-v3 OKAY→~2 min zombie→reset + síntesis UEFI-WDT-desarmado/XBL-WDT (#329); #492 K42 7 boots 23–34 s; #494 K43 6 boots 24–34 s | **figura "2 min": 3+ semanas** (mid-sep); ciclos 23–34 s: 7 días (2-oct) | (i) APSS-WDT roto en este linaje: sin watchdog arreglado el cuelgue exige reset físico (#5577/#5597; #411/#412, roto hasta s221) — ¿lleva k52-tree/s273 el nodo `watchdog@17c10000` funcional?; (ii) XBL-WDT solo cubre ciertas clases (stall-NoC #283/#286) — un colapso de rails/reloj puede matar el propio tick del WDT; (iii) k65/k66/k67 llevan 4–6 min SIN reset: o el WDT no está armado aquí o la muerte es tan temprana (ABL) que el pet sigue vivo; (iv) el "ciclo" no es automático: #494 el ABL cayó a fastboot SIN probar b | Plan "esperar drenaje WDT ~7 ciclos" (#553); leer retry-count como oráculo; "4+ min sin reset = wedge estable" (podría ser loop invisible sin re-enumerar USB por s273) |
| (d) `dd boot_a` por SSH = sha exacto verifica el flash | #554 9-oct 04:3x: `dd boot_a` = `18c749ea…` exacto tras reflash k52b2 | **horas, n=1** | (i) verifica BYTES del payload, no bootabilidad: retry/unbootable viven en metadata aparte; `dtbo_a` NO se verificó en #554 (se dejó s273 a propósito); AVB footer aparte; (ii) lectura por by-partlabel tras `set_active` puede mapear/contener caché — n=1 no lo descarta; (iii) precedente tooling: bug offset-64 dio basura `einit…` (#310); repack-k18 G2 esperaba 370 B con 350 en disco; sha-igual ≠ semántica-igual (padding cpio 320 KB, `kernel_size`+1 B K42→K43) | "Flash íntegro ⇒ testbed restaurado ⇒ s273 inocuo" (#554): el `dd` cubre `boot_a`, no `dtbo_a`; la inocuidad de s273 para k52b2 es n=1 sin control |
| (e) `aop_a=aop_b` idénticos es sano | #554 FASE 1: `aop_a=aop_b=3353ea91…` 524288 B ELF32 RISC-V + `aop_config`/xbl/tz/hyp/abl en `build/evidencia/aop-dump-20261009/` (verificado en disco: ambos `3353ea91c4…`) | **horas, n=1, sin referencia stock** | (i) ambas slots llevan la misma imagen de fábrica nunca actualizada: igualdad ESPERADA incluso corrupta/vieja; (ii) sin golden (sin dump stock, sin version-string, sin parseo de header más allá de ELF32) "idénticos" ≠ "sanos"; (iii) error sistemático de dump (misma herramienta/mismo mapeo) daría igualdad espuria; (iv) el AOP es un RISC-V separado: su igualdad no dice nada funcional (el voto GX puede estar roto en ambos igual) | "AOP sano ⇒ idea E desbloqueada pero depriorizada" (cierre FASE 1). Si el votante GX vive en AOP/TZ, la igualdad no lo exonera |

## Por axioma (corto)

### (a) El más peligroso — veredicto: NO SOSTENIDO como diferencial
- Lo que lo sostiene son TRES silencios de hoy (k65/k66/k67) + la reconstrucción del 02:50 (#554: A llevaba k63+s273; k64 **nunca se flasheó**, #550b sin flash detrás).
- Lo que lo rompe está en el propio ledger:
  - BARRIDO-W3 §0 afirma "k63/k64 al menos daban USB/consola". Falso contra el ledger: **k63+s273 re-flasheado 8-oct 19:51 dio 0 bytes, ACM ni enumeró** (#548d); #548c–#548e repiten freeze antes de S0/gadget. Y **k64 jamás booteó** (no hay diferencial k65-vs-k64).
  - O sea: el silencio PRE-EXISTE a D1/D2/D3. k66-sin-D3 y k67-sin-D2 "mueren idéntico" porque mueren antes de donde viven D1/D2/D3.
- Candidatas concretas antes del kernel: ABL con s273 (F1 voto-CX en kgsl-smmu + F2 `qcom,qmp`→GMU; ABL ya colgó con DTB nuestros #328; mergeador que ignora fragments #496–#497); gadget que no re-enumera tras freeze sin lector pre-armado desde el `continue` (#548c); RCG `hub_clk_src` derivado de GPLL0 compartido con USB (el propio análisis W4-K67 §1–2 admite el acoplo USB).
- Si (a) cae: **D3-exonerado (#555) y D2-exonerado (#556) son nulos**, D1-nº1 es humo, y k68-D2-solo es un tiro a ciegas. Lo único que sobrevive es ordinal: k52b2+s273 sí arranca (~60 s, SSH), k63/k65/k66/k67+s273 no.

### (b) Veredicto: SOSTENIDO en fuente, VACUO en runtime de hoy
- Fuente verificada HOY (solo lectura): `k52-tree/kernel/printk/printk.c:1305` lleva `UKE_CONSOLE_LOGLEVEL_MAX=4`; `build-k66.sh:110-156` gatea marcador K41 + `pr_err` presente + `pr_warn` ausente. El tope no se perdió en la migración.
- Pero la validación runtime (K43, 2-oct, linaje k18 `adreno_bind`) no transfiere a k52 `a6xx_gmu_resume`: los testigos D1/D2/D3 están en `resume`, y ningún boot k65+ mostró NI el primero (D1). Con muerte pre-`resume`, "pasa el tope" no predice nada observable.
- Más el host: tope 4096 B por línea canónica + `stty` que cuelga (#490) + ACM que se atasa con ráfagas (#490) + endpoint wedged que exige reconectar cable (#492). "Lector armado" no implica "ventana de captura viva".
- Si (b) cae (o se vuelve inaplicable): la ausencia de `UKE-K65/K66/K67` no distingue "muerte antes del testigo" de "testigo suprimido/perdido". Hace falta un testigo MÁS temprano que D1 (p. ej. `pr_err` en entrada de `probe`, o en `console_init` tardío) antes de leer silencios.

### (c) Veredicto: CADUCADO para este linaje hasta re-medir
- La figura "~2 min" es de la era RAM-boot/ABL (mid-sep, #328/#329). La era K42/K43 medía 23–34 s por ciclo CON fallback a fastboot — y #494 documenta que el ABL **cayó a fastboot sin probar b**, o sea el "ciclo automático" no existe en ese estado.
- k65 (4 min), k66 (6+ min), k67 (4+ min) sin reset ni re-enumeración contradicen "~2 min" en ESTOS kernels+dtbo. Dos lecturas posibles: WDT no armado/funcional aquí (¿nodo watchdog en s273? ¿`CONFIG_QCOM_WDT=y` en `k52-bateria.config`? — comprobar en PC, 0 flashes), o wedge tan duro/temprano que el WDT no tickea / el pet sigue vivo en ABL.
- Si (c) cae: el plan "drenaje WDT (~7 ciclos)" (#553) es espera indefinida; el revival es botones físicos, no tiempo. Y el retry-count como oráculo queda sospechoso (¿quién lo decrementa si no hay ciclo?).

### (d) Veredicto: SOSTENIDO como integridad de bytes, SOBRE-EXTENDIDO como "flash verificado"
- El `dd`+sha es la mejor evidencia de hoy de que `boot_a` lleva `18c749ea…` — no se discute el match.
- Pero "verifica el flash" promete de más: no cubre `dtbo_a` (el discriminador s273 quedó SIN verificar por `dd` en #554), ni flags de slot, ni AVB, ni que el ABL acepte el par. n=1, sin control.
- Precedentes de tooling que obligan a humildad: cmdline leída en offset 64 dio basura (`einit…`, #310); repack-k18 G2 esperaba 370 B con 350 en disco; K42→K43 cambió 1 byte (`kernel_size`+1) con cmdline idéntica.
- Si (d) cae en su forma fuerte: #554 prueba "boot_a = k52b2", NO "testbed restaurado por completo" ni "s273 inocuo en general" (solo: k52b2 arrancó UNA vez con s273 puesto).

### (e) Veredicto: NO SOSTENIDO como "sano" (solo como "existe y es dumpable")
- Verificado en disco hoy: `aop_a.bin` = `aop_b.bin` = `3353ea91c4…` (524288 B c/u). Eso prueba existencia + dumpabilidad (idea E desbloqueada: el binario AOP EXISTE), no salud.
- "Idénticos ⇒ sano" no tiene grupo control: sin dump stock / sin version-string / sin parseo de header+TOC, dos copias de fábrica iguales son el caso base, sanas o no. Un mapeo sistemático erróneo también daría igualdad.
- Si (e) cae: nada de FASE 1 sobre AOP como votante GX queda cerrado; la igualdad no puede usarse para depriorizar la vía AOP/TZ. Coste de cierre real: `strings`/parseo de header del `3353ea91…` + comparación contra ROM stock (0 flashes).

## El axioma más peligroso: (a)
- Porque sostiene DOS exoneraciones (D3, D2), UNA acusación (D1) y LA dirección del siguiente flash (k68). Si el silencio es pre-kernel, W3+W4 son una autopsia del dtbo/ABL etiquetada como autopsia del GMU, y k68 decide sobre un experimento que nunca corrió.
- Señal de alarma interna ya registrada: el propio ledger dice que k63 era silencioso SIN D1/D2/D3 (#548d) y que k64 nunca se flasheó (#554). El diferencial que funda (a) no existe con los datos de hoy.
- Acción mínima (0 escrituras, PC + testbed vivo): (1) comprobar en fuente si k65+ llevan algún `pr_err` ANTERIOR a D1 en el camino `probe` (si no, el silencio es ciego por construcción); (2) comprobar `CONFIG_QCOM_WDT` + nodo watchdog en s273/`k52-bateria.config` (decide si (c) puede salvar a (a) vía "sin reset = muerte pre-WDT"); (3) parsear el AOP `3353ea91…` (cierra (e) de verdad); (4) no flashear k68 hasta tener un testigo temprano que distinga ABL/dtbo de GMU/resume.

## Casos raros (cómo encajan)
- 02:50 (k52b2-silencio sin flash previo) → explicado como k63+s273 (#554). PERO deja un residuo que ataca (a): k63+s273 silencioso prueba que el silencio no necesita D1/D2/D3.
- `getvar` transitorio `< waiting >` con respuestas parciales + endpoint wedged (curado por `usbreset`/reconexión, #492) → ataca (a)+(b): el canal USB/fastboot falla solo; "sin USB" no es "sin kernel".
- cmdline en offset 64 dando basura (`einit…`, #310) → ataca (d): el tooling propio ya confundió offset una vez; el `dd` entero es robusto a eso, pero la lección es no sobre-leer un match.
- repack-k18 G2 esperando 370 B con 350 en disco → ataca (d): los gates de tamaño/prefijo son frágiles entre linajes (465 B K42 vs 580 B k64+); un gate verde no es comprensión.
