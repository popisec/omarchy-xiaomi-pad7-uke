# BASE ESTABLE — reconstrucción histórica del 11-oct y protocolo (auditoría post-mortem)

> Solo-PC. Cero flashes. Fuentes: FLASH-LEDGER #588–#601, ESTADO-VIVO (05:0x),
> CRITICA-PANTALLA-20261011b, CRITICA-KIT-E1, PLAN-PANEL-WEDGE, y los logs ACM del día
> (`/tmp/acm-*.log`, `out/acm-trigger-035245.log`) + el contenido real del initramfs
> embebido en los boot images (extraído y leído en el PC, /tmp/k22x, /tmp/k51x).

---

## 1. Secuencia EXACTA de flashes del 11-oct

Escrituras nº37–nº54 + F1/par-estable (estimación 14 escrituras, ~11 boots, ~9 pares).
Leyenda de confianza: **P**=probada (evidencia directa), **p**=probable, **A**=asumida.

| # | Hora | boot_a | dtbo_a | Resultado observado | Conf. |
|---|------|--------|--------|---------------------|-------|
| 1 | ~01:0x #588 Nº37/38 | L18 `d3dcf944` | s275-r2 `67a65bc1` | Panel nace (card1-DSI-1+WB); ADSP defer por ICC | P |
| 2 | ~01:3x #589 Nº39 | **L19 `71d89ca6`** | s275-r2 | Carga OK (ADSP running, charger_pd), batería **2%**, Charging 500 mA | P |
| 3 | ~01:4x #590 Nº40 | L19P `7b6ec7e9` (sin `:d`) | s275-r2 | Wedge a ~20 s → fastboot; captura perdida | P |
| 4 | ~02:0x rollback Nº41 | L19 | s275-r2 | Estable restaurado | P |
| 5 | ~02:1x #591 Nº42 | L19P (re-flash) | **s276 `ef01ed56`** | Wedge ~40 s en bucle → fastboot | P |
| 6 | ~02:2x rollback Nº43 | **L19** | **s275-r2** | **PAR ESTABLE**: SSH productivo (scp 612 MB), uptime llega a 3773 s | P |
| 7 | 03:52–03:59 #595 | (0-flash) | (0-flash) | Trigger `echo on` → wedge determinista, captura completa; reboot y vuelve | P |
| 8 | ~04:0x #596 Nº47 | L20 `71765b16` | **s277 `4a8a7a51`** | Slot B primero (contador agotado); en A: DSI **-2**, sin card1; SSH OK | P |
| 9 | ~04:1x #596 bisect | L19 | s277 | Mismo -2 → kernel exonerado; SSH OK → #597 WiFi en vivo (04:3x) | P |
| — | ~04:50 | — | — | **Tablet desaparece del bus** (batería o glitch; muerte sucia sin captura) | P |
| 10 | ~15:2x #599 Nº50 | L21 `7d178b01` | s278-nostrip `5fcfbc84` | **Wedge 4,1 s** (pre-userspace) | P |
| 11 | ~15:4x #599-ter Nº52 | L21E1b `7b50adf6` | s278-nostrip | Bucle de reboots → fastboot (fbcon=map:1 NO lo evita) | P |
| 12 | ~15:5x #600 | L19 | s278-nostrip | Wedge único ~4,1 s (el kernel bueno también) | P |
| 13 | ~16:1x #601a | L19 | s278-nostrip-**nowdt** `41aca29f` | Ledger dice wedge 4,2 s; PERO `acm-nowdt2.log` (16:15) muestra este par **llegando a 47,2 s** con pid1 congelado a 6,66 s → **hay ≥2 boots mezclados sin distinguir** | p |
| 14 | ~16:1x #601b | L19 | s278-nostrip-**nowifi** `23af204b` | pid1 **ABRT 6,65 s**; tormenta novatek hasta 46 s | P |
| 15 | ~16:2x #601c | L19 | **s276** | pid1 **ABRT 6,69 s**; consola calla a 47,17 s | P |
| 16 | ~17:1x (F1 crítica-b) | L19 | **s275-r2** | pid1 **ABRT 16,65 s**; ext4 10 grupos a 9,72 s; calla ~47 s | P |
| 17 | ~17:3x (par-estable) | L19 (re-flash) | s275-r2 (re-flash) | pid1 **ABRT 6,60 s**; **mismos 10 grupos ext4** a 9,34 s; calla 47,04 s; sin SSH 10+ min | P |

**Corrección al relato del dueño**: el "par estable de la mañana" L19+s275-r2 solo estuvo
realmente en flash de 02:2x a 04:0x. De 04:0x a 15:2x los slots trajeron **L19+s277**.
Cuando a las 17:1x se volvió al par bueno, **los artefactos eran los mismos pero el sistema
no**: el rootfs había cambiado (§2a).

---

## 2. Confounders del bisect de la tarde

**(a) Corrupción ext4 del rootfs — PROBADA y subestimada.**
- La huella es idéntica en TODOS los boots de tarde que llegaron a userspace: los mismos
  10 grupos (17,18,21–26,29,30) con las MISMAS discrepancias de free-clusters, en
  `acm-par-estable.log` (9,34 s), `acm-f1-boot.log` (9,72 s), `acm-s276-final.log` (9,72 s),
  `acm-nowdt2.log` (9,27 s), `acm-nostrip-nowifi.log` (9,27 s). Es un daño ON-DISK
  persistente, no ruido de un boot.
- Ya existía por la mañana (boot bueno: buddy errors a 6,87 s en grupos 9–16,23,24 +
  `inode #73734 deleted inode referenced: 73765` repetido todo el día, incl. el 44,3 s) —
  pero pid1 sobrevivía. En la tarde, pid1 muere en los 5/5 boots con userspace (ABRT a
  6,6–16,7 s) y por la mañana en 0/1.
- **La regla "e2fsck en frío" no se saltó: fue imposible de cumplir.** Verificado en el PC:
  los boot images de la serie k52 (incluido L19 `71d89ca6`) embeben
  `build/init/uke-k22-initramfs.cpio.gz`, cuyo `ukeinit` (s181) **NO contiene e2fsck**:
  monta la raíz `ro,noload` (sin replay del journal) y remonta rw. El gate
  `e2fsck -f -p` + shell de emergencia de `build/init/ukeinit-arch` (líneas 233–300) es
  solo fuente, **nunca horneado**. Cada boot montó rw sobre un fs sucio y cada wedge murió
  sin sync: la corrupción creció todo el día. El antídoto existía: el initramfs
  `uke-k51-sleep-fsck` lleva `bin/e2fsck-k50` y ejecuta `e2fsck -fy` ANTES de montar
  (comentario #510: "la corrupción acumulada por las muertes sucias mataba el arranque a
  ~8,2 s" — pasó ANTES y se curó igual).
- (b) Batería — PROBABLE cofactor: 2 % a 01:3x cargando a 500 mA por el PC; desaparición
  a las 04:50; ~10,5 h en negro; toda la tarde solo con potencia USB del PC. Estado real
  desconocido (sin SSH no hay telemetría). Puede explicar muertes no deterministas
  (brownouts, escrituras UFS fallidas → más corrupción).
- (c) Slots — PROBADA la trampa (#596: contador A agotado → arrancaba el B); mitigada con
  `set_active a`. Ningún boot capturado de tarde cayó al B (todos muestran pokes UKE).
- (d) Otras: capturas ACM con `[missed]` justo en la ventana del ukeinit (el rc del fsck
  jamás se vio); calor no medido; ABL intacto todo el día (no es variable).

---

## 3. Hipótesis separadas y rankeadas

| Hip. | Qué la apoya de verdad | Qué la refuta | Confounder que la explicaría |
|---|---|---|---|
| **H4 ext4 → pid1 freeze (fuerte, nº1)** | ABRT 6,6–16,7 s en 5/5 boots de tarde con 4 dtbos distintos, incluido el par estable reflasheado; 0/1 por la mañana; huella ext4 idéntica entre boots; mecanismo systemd (crash handler → "Freezing execution"); precedente #510 curado con e2fsck -fy | Ninguna directa | — |
| **H1 frags WiFi → wedge 4,2 s (nº2, fenómeno distinto)** | nostrip (con frags WiFi) muere a 4,1–4,2 s con L19, L21 y L21E1b (3 kernels); nowifi/nowdt/s276/s275-r2 pasan de 6,6 s | `acm-nowdt2.log` (nowdt llegó a 47,2 s) — atribución del ledger a "wedge 4,2 s de nowdt" confundida | Ninguno fuerte; es dtbo-dependiente real |
| **H2 watchdog muerde ~40 s (débil)** | El USB re-enumera en un boot (16:14:59→81) | La firma 46–47 s aparece CON el frag (nowifi) y SIN él (s276, s275-r2 ×2, nowdt2); mainline qcom_wdt no arma el timer en probe; base-DTB sin nodo watchdog | La muerte de ~47 s es de H4, no del WDT |
| **H3 rail-1896 mata a 46–47 s (débil)** | s276 (única diferencia = rail) murió a 47,17 s | El par s275-r2 (rail 1304) muere IGUAL (47,04 y ~47 s) | H4 cubre ambas muertes |
| **H5 enable-wedge TDDI (PROBADO pero ortogonal)** | Captura completa #595: IRQ ESD 86/87 dentro del reset, muerte ≤100 ms tras w4-done, clase panic; repro 100 % determinista | No explica nada de los boots de tarde (ninguno tocó el panel) | — |

Lectura parsimoniosa: hubo **dos problemas mezclados**: (1) el wedge del panel-enable
(H5, de mañana, capturado y cerrado como fenómeno), y (2) el colapso de la tarde, donde el
bisect midió **dos firmas**: la de 4 s (frags WiFi, H1, real) y la de pid1-ABRT/47 s
(H4, rootfs) — esta última atribuida sucesivamente al watchdog, al rail y a s276, cuando
en realidad estaba presente también en el par "bueno".

---

## 4. BASE ESTABLE — definición con criterios medibles

BASE ESTABLE = par **L19 `71d89ca6…` + s275-r2 `67a65bc1…`** con **rootfs que pasa fsck**,
verificada por TODOS estos criterios en un mismo boot:

1. **pid1 vivo**: cero líneas `systemd[1]: Caught <ABRT>` en consola/dmesg y ≥40 líneas
   normales de systemd (la firma del boot bueno de mañana).
2. **SSH por NCM arriba** y `uptime > 300 s` continuo (sin reboot intermedio).
3. **GPU viva**: escalera GMU completa → zap rc=0, sin fallos nuevos vs. el boot bueno.
4. **Consola limpia de fs**: NINGÚN `EXT4-fs error` nuevo tras el boot (los buddy errors
   de 9,3 s deben desaparecer tras el fsck en frío).
5. **Una sola enumeración USB** (sin bucle ni caída a fastboot).
6. **Carga legible**: `status=Charging` con cargador + `bateria.sh` funcional (ADSP running).

Mientras 1–6 no pasen juntos, **todo resultado de flash de kernel/dtbo NO es interpretable**
— esa es la lección central de la tarde.

## 5. Protocolo numerado para alcanzarla (sin mezclar)

1. **CARGAR PRIMERO, no flashear**: cargador de pared ≥1 h (descarta H-batería de raíz y
   estabiliza el UFS). La tablet arrastra desde las 04:50 sin carga fiable.
2. **UN repack con fsck** (paso (i) pedido): boot = kernel L19 byte-idéntico + initramfs
   CON e2fsck. Existen dos caminos: (a) repack de L19 usando
   `build/init/uke-k51-sleep-fsck-initramfs.cpio.gz` (lleva `bin/e2fsck-k50 -fy` antes de
   montar, rc a kmsg, y el fallback telnetd de s181); o (b) hornear `ukeinit-arch` (con su
   gate `e2fsck -f -p` + shell de emergencia por ttyGS0 en rc=4+) en un cpio nuevo.
   **OJO**: `repack-k52L19.py` (línea 27) embebe el k22 SIN fsck — hay que cambiar
   `K13_INITRAMFS` o regatearlo. Pre-registrar sha en el ledger ANTES de flashear.
   dtbo_a = s275-r2 `67a65bc1` (sha re-verificado hoy en la crítica-b).
3. **Flash único**: `fastboot flash boot_a … && fastboot flash dtbo_a … && fastboot
   set_active a && fastboot reboot` (set_active SIEMPRE, lección #596).
4. **Verificación con lector continuo** (`acm-reader.sh` de la crítica-b, no `timeout cat`):
   buscar en consola `K50: e2fsck rc=` (primera vez hoy que se vería) y chequear los 6
   criterios de §4. Si rc=4+ y `ukeinit-arch`: queda shell de emergencia en ttyGS0 (no
   reboot-loop) — ahí se puede fsck a mano o extraer diagnóstico.
5. **SOLO BASE ESTABLE pasa → un avance de pantalla por ciclo**: testigos armados
   (witness+sampler), disparador **modetest** (nunca `echo on`), UNA sola variable por
   flash, pre-registrada. Tras CUALQUIER wedge: volver a 1–2 (el wedge es muerte sucia que
   re-corrompe el fs; reintentar sobre fs sucio = medir ruido).
6. **Medio plazo**: hornear el gate fsck en TODA la serie k52 (que la regla viva en el
   artefacto, no en el source) y la unidad `uke-bootcap.service` de la crítica-b.

## 6. La pregunta incómoda: ¿por qué el mismo par arrancó a la mañana y no a la tarde?

Diferencias posibles y cómo se discriminan:

| Diferencia | Estado | Discriminador |
|---|---|---|
| **Rootfs** (corrupción creció: 10 grupos nuevos; pid1 ABRT solo de tarde) | **PROBADA** (huellas idénticas entre boots; ningún fsck corrió nunca) | Paso 2: si tras `e2fsck -fy` en frío el par arranca, queda cerrado |
| **Batería** (2 % → 10,5 h en negro → solo USB de PC toda la tarde) | PROBABLE | Paso 1: 1 h de cargador de pared y boot SIN reflash |
| **Contenido real de los slots** (04:0x–15:2x fue L19+s277, no el par bueno) | PROBADA (ledger + ESTADO-VIVO) | Ya resuelto: desde 17:1x hay L19+s275-r2 |
| Watchdog frag / rail 1896 / frags WiFi | PROBADAS como NO causa de la muerte del par bueno (el par sin nada de eso muere igual) | F3a (`s279-wdtonly`) ya no urge; solo si BASE ESTABLE no cierra |
| Calor, estado RAM, ABL | ASUMIDAS menores (boots fríos, ABL intacto, sin sensor accesible) | Solo si 1+2 no cierran |

**Respuesta corta**: no es que el par "dejara de arrancar": es que el **sistema** bajo el
par cambió. El kernel y el dtbo son byte-idénticos a los de la mañana; la raíz que
montaron no. Con pid1 congelado a los 6,6 s por el fs sucio (montado `noload`, sin fsck
posible en esos images), no hay SSH, y la consola enmudece a los ~47 s porque la tormenta
novatek termina y la cola diferida se vacía — silencio que NO prueba muerte del SoC
(discriminador rápido: ¿el gadget USB sigue enumerado tras 47 s? ¿cae a fastboot?).
