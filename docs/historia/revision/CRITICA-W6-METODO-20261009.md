# CRÍTICA-W6-MÉTODO (2026-10-09): deriva de gates, árbol mutable, n=1 y sesgo

Audita el MÉTODO del 9-oct, no las hipótesis (D1/D2/D3, AOP, register_config).
Evidencia: `repack-k18.py` vs `repack-k65/66/67.py`, reports G0–G8 de los 3 bootimgs,
`build-k65/66/67.sh`, diffs `k65/k66/k67/k68`, ledger #550b–#556, NOTAS-OMARCHY, ESTADO-VIVO.
Probes propios (solo lectura, `/tmp`, `--dry-run`): verificar §2.

Veredicto de una línea: los gates conservan dientes de **empaquetado y procedencia**
(G4-ceros, G6-confinamiento, G3-negativos, G7-preregistro, G8-roundtrip — todos verdes
y reales hoy), pero **ningún gate verifica identidad de fuente ni valores cuantitativos**,
que es justo lo que cambió hoy. El repack confirma que el binario se parece a lo que el
coordinador cree haber construido; no detecta que construyera otra cosa.

## 1. Deriva de gates: qué se relajó, qué muerde, qué colaría

### 1a. Relajaciones k18 → k65 (heredadas por k66/k67)

| Check | k18 | k65/66/67 | Estado |
|---|---|---|---|
| `UKE-K17: dtcmR val=` (cuantitativo) | exigido | relajado a `S0-dtcmR` presencia | DIENTE PERDIDO |
| G3b dump corregido K23b (GEO/CBbase/decode S2CR, 6 marcadores) | exigido con `--gate-k23b` | eliminado ("no aplica a este linaje") | DIENTE PERDIDO |
| G3c caminador K24 (WALK/MAPPING/HUECO/veredicto + prohíbe `e[4]` plano) | exigido siempre | eliminado | DIENTE PERDIDO |
| cpio embebido | `== K12/K13` (sha absoluto conocido) | `== cpio del k64` (referencia relativa) | ANCLA PERDIDA |
| cmdline final | referencia k13 + append exacto | `byte-idéntica al k64` (580 B) | MÁS FUERTE, pero condicional (ver C6) |
| G0 árbol | `k18-tree` + 4 fuentes (mtime) | `k52-tree` + mismos 4 (mtime) | IGUAL DE ROMO (ver §2) |
| G3 testigos variante (K65/K66/K67 x1 + negativos D3/D2) | n/a | añadidos | DIENTE NUEVO, real |

Verificado en binario hoy: k64 lleva `S0=1, val=0, k19_dump=0, caminador=0, K24=0,
K23b=0, register_config=1` — la justificación fáctica ("k64 tampoco los lleva") es cierta.
El problema no es fáctico, es lógico: **k64 no se flasheó nunca** (#554, NOTAS 2442:
"#550b es inferencia sin flash"). Una inferencia sin flash se convirtió en precedente
para soltar los dos gates que garantizan que el discriminador dice la verdad (G3b nació
porque el dump mentía geometría; G3c porque el discriminador leía basura fuera de la
tabla). Es blanqueo de precedente: lo no-medido autoriza a dejar de verificar.

### 1b. Gates que MUERDEN todavía (crédito donde toca)

- **G4** hueco-tras-kernel ceros; **G6** confinamiento vs s240 (caza escrituras fuera de
  zona); **G3 negativos** (`UKE-K65:D3` ausente en k66, `D2/D3` ausentes en k67 —
  anti-confusión de variante, verificado); **G2/G6** cmdline 580 B `==k64` (ejercido:
  reports muestran dsid+10 appends, 580 B); **G7** sha + preregistro previo al flash
  (#553/#555/#556 traen shas); **G8** roundtrip `unpack_bootimg` (corrió, rc=0, hoy).
- **build-k\*.sh** (capa previa al repack): must/mustnt sobre Image crudo + gates de
  config (ARCH_QCOM, INITRAMFS→K34-fw, fw dentro del cpio). Reales.

### 1c. Qué corrupción COLARÍA hoy por G0–G8 (concreto)

- **C1 — errata cuantitativa en el código variante (la más grave).** G3 solo cuenta
  *format strings*. `clk_set_rate(core, 22000000)` (un cero menos),
  `mask 0x1ff→0x1fff`, `reset_val` cambiado, `0x1f9cf` con chipid mal recompuesto,
  rate D2 a otro valor: el testigo `pr_err("...220M rc=%d")` sigue x1, el tamaño sigue
  en ±256 KiB → **todo verde con el reloj equivocado**. Ninguna capa (repack ni build)
  verifica un solo operando numérico. El `rc=%d` que lo delataría solo existe en runtime,
  y el instrumento (consola) está muerto.
- **C2 — edición en fichero no vigilado.** G0 mira 4 ficheros (`arm-smmu.c`,
  `a6xx_gmu.c`, panel, `uke-panic-fb.c`). Cambios en `gpucc-palawan.c` (las `ftbl_*`
  de las que depende TODA la racionalidad D1/D2), `gdsc.c`, OPP core, Kconfig/Makefile,
  `.config` (vía olddefconfig), DTS/dtbo, `ukeinit`, `mkcpio` → G0 ciego.
- **C3 — contaminación del árbol entre variantes.** G0 es *frescura* (mtime fuente <
  mtime Image), no *identidad*. Árbol contaminado + build posterior = G0 verde por
  construcción. Restos de otra variante sin strings propios (un `pr_flush` movido, un
  orden de writes cambiado, un hunk revertido a medias) son invisibles.
- **C4 — cpio corrupto compartido con k64.** El gate es `cpio == k64`, no `cpio == bueno`.
  Si el cpio del k64 perdiera un fw o un nodo, k65/66/67 lo heredan con sello verde.
  (Mitigado hoy por los gates de contenido del build-k*.sh — pero el repack ya no ancla.)
- **C5 — linaje copy-paste.** k67/k68 llevan bloques `UKE-K66:` (GENERAL_10/poll) copiados.
  Un fix posterior en el bloque de k66 no propaga a k67/k68; el repack no lo ve (strings
  iguales). Divergencia silenciosa entre hermanos.
- **C6 — cmdline latente.** La exigencia `==k64` vive DENTRO del `if CMD_APPEND:`.
  Invocado sin `--cmdline-append`, el repack empaquetaría la cmdline dsid de 370 B con
  G6 verde (dif 0 vs k13d) y rompería el "única variable = kernel" sin quejarse. Hoy no
  disparó (los 3 reports muestran los flags), pero la fuerza del gate depende de flags
  CLI en vez del manifiesto del target. Misma familia: nadie valida token a token la
  cmdline de 580 B del k64 (referencia nunca flasheada, reproducida por fe — incluye
  `uke_kgsl_keep=0`, que convive sin gate con el check G3 de *presencia* del param).
- **C7 — dtbo fuera de todo gate.** s273 (experimental: F1 power-domains CX en kgsl-smmu
  + F2 `qcom,qmp`→GMU) no lo mira ningún repack, y los criterios "única variable" lo
  ignoran. El control #554 (`k52b2+s273` arranca) es **GPU-off y no atraviesa el path
  GMU que s273 modifica**: no exculpa a s273 en ninguno de los silencios GPU-on (§4-B4).
- **C8 — G1/G5 protocolarios.** G1 inspecciona la base, no el producto. G5 exige magias
  AVB0/AVBf, no validez de firma/bootabilidad. Forma ≠ arrancable.

Fixes §1: **F1** G3d cuantitativo — hashear `a6xx_gmu.c` en el repack y exigir igualdad
con el sha pre-registrado de la fila del ledger (cierra C1+C2+C3 de un golpe; el repack
ya conoce `R`/tree). A medio plazo: gate de inmediatos por desensamblado
(rates/máscaras/reset_val/GENERAL_10) como ya se hace con el unwind blindado en
`flash-k42.sh`. **F2** G0 por contenido: `sha256` de las fuentes (añadir `gpucc-palawan.c`
+ `gdsc.c`) vs shas pre-registrados, no mtime. **F3** cpio con doble ancla: `== sha
K34-fw conocido` ADEMÁS de `== k64`. **F4** cmdline `==k64` incondicional para el linaje
+ lista cerrada de los 10 tokens requeridos. **F5** dtbo como variable declarada: su sha
en cada fila y criterio (§4-B4).

## 2. Árbol mutable en serie: reproducibilidad

### 2a. Hechos probados (probes `--dry-run` sobre copia en /tmp, árbol intacto)

- `k52-tree` está en `.gitignore` (`build/kernel-pokes/`, "nunca ha estado en el índice"):
  **cero archivos bajo versión**. `git log`/`status` dentro solo reflejan el repo padre.
- El árbol actual = variante k68 (grep: `UKE-K68` x9, K65/K66/K67 x0; `patch -R --dry-run
  k68` limpio).
- Revertido k68 en copia → estado S con `UKE-K65` x4. Sobre S, **k66 y k67 aplican
  forward limpios** (0 rejects). Estructura real: `S0 --k65--> S1 --k66/k67/k68--> variantes
  hermanas`, cada diff *squasheado y autocontenido* (hunks @866/@1066 anclados en mainline,
  hunk @2306 anclado en bloque K65). NO hay apilado k65→k66→k67.
- `build-k65/66/67.sh` **no aplican ningún parche** (cero líneas `patch`/`git apply`):
  la mutación S1→variante la hizo cada subagente a mano (revertir+aplicar sin registro),
  y el script compila lo que haya. "Todo versionado" es falso en el punto crítico:
  los diffs están versionados, **su aplicación no**.
- S0 (base) contiene el delta K25..K42 "que SOLO VIVE EN EL ÁRBOL" (hueco reconocido en
  el propio `build-k65.sh`, #492-errata): la base declarada tampoco existe como objeto.

### 2b. Respuesta: ¿reproducible cada Image desde diff + base?

En principio SÍ (cada diff aplica limpio sobre S1 — probado), pero **no verificado y no
cerrado**: sin hash de S0/S1, sin registro de las reversiones intermedias y sin rebuild
de comparación, nada excluye que el árbol en cada build llevara estado no declarado
(C3). Un `patch --dry-run` limpio hoy no prueba el árbol de ayer.

### 2c. Test exacto (TEST-R, 5 min + opcional 60 min)

```bash
cp -a build/kernel-pokes/k52-tree /tmp/TEST-R && cd /tmp/TEST-R
patch -p1 -R < build/gates/patches/k68-d2solo.diff   # volver a S1 (k68 es el aplicado)
grep -c UKE-K65 drivers/gpu/drm/msm/adreno/a6xx_gmu.c  # esperado: 4 (= S1)
sha256sum drivers/gpu/drm/msm/adreno/a6xx_gmu.c        # registrar como S1.hash
for n in 66 67 68; do
  patch -p1 --dry-run < build/gates/patches/k${n}-*.diff \
    && echo "k$n: aplica limpio sobre S1" || echo "k$n: NO APLICA (deriva sin declarar)"
done
# Fuerte (kernel crítico): O limpio + config versionada + S1 + kn.diff, rebuild,
# y sha256(Image.gz) == sha flasheado de la fila del ledger. KBUILD ya fija
# USER/HOST (uke/palawan): el reproducible por sha es exigible.
rm -rf /tmp/TEST-R
```

Fixes §2: **F6** receta cerrada — el build script aplica `patch -p1 < kn.diff` sobre base
con `set -e` y falla si hay rejects; registra `sha256` del fuente pre/post. **F7** base
con hash: snapshot de S0/S1 (quitar `k52-tree` de `.gitignore` o `SHA-ARBOL-K*.txt` como
ya existe para K24) y cada diff generado contra base hasheada, sha en el ledger. **F8**
TEST-R como gate pre-build, no como auditoría post-hoc.

## 3. n=1 por kernel + presupuesto: qué flashes sobraban

Contabilidad: budget 2/día (ESTADO-VIVO: "AGOTADO 2/2"). Escrituras: #553 k65 (nº1),
#554 restore k52b2 (nº2, en budget), #555 k66 (nº3, override 1), #556 k67 (nº4, override 2).
Slot B con retry 6 e imagen vieja (#554): **A es el único slot sano**, y se jugó 2 veces
más con outcomes modalmente no-informativos.

- **#554 restore: NECESARIA.** Y su valor-control (dtbo) está sobrevendido (§4-B4), pero
  la restauración misma era obligada (A llevaba k63 colgado desde #548).
- **#553 k65: EVITABLE.** Bundle de 3 variables (D1+D2+D3) con instrumento muerto conocido
  (02:50 ya había dado silencio-cero-bytes). La autopsia W3 que luego mató a D3 en código
  (GDSC sin `set_performance_state` + OPP con clk sin fijar → abort pre-USB) no necesitó
  ningún dato del flash: era lectura de fuente disponible antes. Autopsia-primero →
  k66-primero ahorraba 1 flash. El propio resultado lo admite: "Sin evidencia NO hay
  veredicto" — un n=1 que su diseño condenaba a n=0.
- **#555 k66: PREMATURA (sin baseline).** La referencia k64, ancla de comparabilidad de
  TODA la serie (gates, cmdline, cpio, criterios), **no se flasheó jamás**. Sin k64,
  "silencio igual" no tiene comparador: ¿igual a qué — a k63 (otra variante) o al baseline?
  Si k64 calla también, la serie D entera persigue ruido de baseline y sobran k65/66/67.
  El flash más informativo del día era k64, y no se hizo mientras se quemaban 3 de variante.
- **#556 k67: MITAD DIFERIDA.** El split D1/D2 necesita ambas mitades para concluir (los
  propios criterios: "k68 decide"). Gastar el override nº2 en una mitad inconclusiva por
  diseño, dejando el payoff para un 5º flash (k68, mañana), es el fallo presupuestario
  puro: los pares se planifican juntos o no se empiezan. Añadido: revival entre el hang
  k66 y el flash k67 ("tablet en fastboot", método no registrado: ¿botones? ¿WDT?) =
  variable residual no controlada entre n=1s.
- **Lenguaje sin error bars.** "EXONERADO"/"nº1" sobre n=1 con cero bytes y confusores
  (batería 4025→4013→4018 mV anotada, bien; retries/slot-metadata, WDT, timing de revival:
  no). Cada silencio se trata como decisivo; ninguno se replica.

Cuenta: **2 de 4 evitables** (k65 vía autopsia-previa; k67 diferido/emparejado con k68 o
supeditado a baseline), 1 prematuro por falta del control que más importaba (k64 mismo),
1 necesario. Y el flash que calibraba el instrumento no existe.

Fixes §3: **F9** "sin baseline no hay serie": la referencia se flashea antes que la primera
variante; sin habla del baseline, la serie no arranca. **F10** prohibir bundles
multivariables con instrumento muerto (autopsia en fuente primero — W3 demostró que rinde
más que un flash). **F11** mitades como par planificado o nada; réplica (n≥2) antes de
"EXONERADO/CONDENADO", o lenguaje degradado a "compatible con". **F12** override con precio
por escrito (qué se sacrifica mañana + retries A/B) y veto si A es el único slot sano y el
outcome modal es no-informativo; método de revival registrado como variable.

## 4. Sesgo de confirmación: decidir primero, medir después

Ordenados por gravedad (método, no personas):

1. **#550b: RESULTADO sobre un kernel no flasheado.** "k64 RESULTADO: CONGELA TAMBIÉN…",
   "CONCLUSIÓN FINAL DEL CICLO", cierre de la vía software-APSS — y #554/NOTAS-2442:
   "k64 nunca se flasheó… #550b es inferencia sin flash". Lenguaje de outcome sin
   measurement. Encima se cita como premisa ("conclusión #550b en pie", criterios #553).
   Fix: prohibir secciones RESULTADO/CONCLUSIÓN sin artefacto medido; degradar #550b a
   HIPÓTESIS en el ledger (una línea).
2. **Blanqueo de precedente k64→k65/66/67** (§1a): la inferencia autoriza soltar G3b/G3c/
   dtcmR-val, mover el ancla del cpio a k64 y exigir "comparabilidad con k64" behavior.
   Presencia-en-binario (`register_config x1`) confundida con funciona. Fix: F1–F4; la
   referencia de gates debe estar flasheada o marcada NO-CALIBRADA en cada fila que la cite.
3. **Silencio pre-etiquetado como informativo.** Los criterios asignan significado al
   silencio ANTES de medir ("D3 EXONERADO", "D2 EXONERADO") bajo supuesto de causa única
   nunca declarado. Con instrumento muerto, el outcome modal (cero bytes) siempre "avanza":
   cara-gano-cruz-también. La gate negativa prueba el BUILD (el binario no lleva D3),
   no la CAUSA. Fix: F11 + exigir en cada criterio la línea "si silencio: compatible con
   {H1,H2,H3}, no decide" salvo baseline hablante.
4. **Control #554 sobrevendido.** `k52b2(GPU-off)+s273` arranca ⇒ "s273 inocuo" ⇒ dtbo
   exculpado para la serie. Pero s273 toca paths GMU (F1/F2) que un boot GPU-off jamás
   ejercita: el control no atraviesa el camino sospechoso. Fix: F5 — control GPU-ON para
   dtbo (o s269 fijado durante la serie D); ninguna conclusión-dtbo desde k52b2.
5. **Bundle k65 uninterpretable por diseño** (§3): 3 variables × instrumento muerto; los
   criterios prometían discriminación que el silencio no podía entregar. Fix: F10.
6. **Overrides por la parte interesada (2× el mismo día).** "Dueño presente con botones"
   es a la vez la mitigación del riesgo y la autoridad que levanta el budget — sin
   re-precio del riesgo (slot único sano, B retry 6). Un budget que cede 2 veces seguidas
   es un apunte contable, no un control. Fix: F12.
7. **Informes de diseño no escritos a disco.** #551: los 4 subagentes "interrumpidos antes
   de escribir… viven SOLO en este ledger y en la conversación". Los diseños W2/W3/W4 que
   justifican quemar slots son inauditables justo donde se decide. Fix: regla dura — sin
   informe en disco no hay flash (el propio #551 propone "guardar incremental": convertirlo
   en gate).
8. **Higiene de clones (menor).** Labels "(K18-dsid)" en reports k65/66/67, código muerto
   (flag `--gate-k23b`, ramas CMD_APPEND que hoy solo sirven de andamio), G0 anunciando
   "4 fuentes" mientras la identidad no se verifica. Divergencia futura entre clones.
   Fix: un solo repack parametrizado por manifiesto
   (kernel-dir + diff-sha + cmdline-ref-sha + cpio-sha + testigos/negativos); podar o
   marcar HISTÓRICO lo muerto.

## 5. Qué hacer mañana (orden)

1. Degradar #550b a hipótesis (1 línea en ledger) hasta flashear k64. 2. F1+F2 (sha de
   fuente en repack + G0 por contenido): 1 h, cierra la familia C1–C3. 3. F6+F7 (receta
   cerrada + base con hash) + TEST-R como gate. 4. Decidir k68 bajo F9/F11/F12: o baseline
   k64 primero, o par k67/k68 ya a medias — pero con precio escrito y dtbo fijado (F5).
   5. Regla informe-en-disco-antes-de-flash (F7-nota #551 ya lo pide).
