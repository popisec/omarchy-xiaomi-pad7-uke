# V3 — Huellas docales: afirmaciones que la corrección del 1-oct deja falsas o caducadas (auditoría solo-lectura, sin tablet)

**Fecha:** 1-oct-2026 (tarde). **Agente:** solo lectura; NO toca la tablet, NO commitea, NO edita
ficheros ajenos. **Método:** `grep` sobre todos los `*.md` del repo (raíz + `build/gates/` como
evidencia de apoyo), `ls`/`[ -f ]` para cada ruta citada, contraste contra los dos hechos nuevos.

## Los dos hechos nuevos (no re-descubiertos; vienen de `V2-critica-k23b.md` + banner de v4)

- **H1 — decode S2CR invertido:** `a6xx_gmu.c:324` imprimía `type = s2cr & 0x3`,
  `cbndx = (s2cr>>16)&0xff`, cuando `arm-smmu.h:113-120` define `S2CR_TYPE = GENMASK(17,16)`
  y `S2CR_CBNDX = GENMASK(7,0)`. Dato real: `SMR(1)=0x80000005` válido id 5 +
  `S2CR(1)=0x00000001` = **SID 5 (icache CM3) VÁLIDO en TRANS por CB1**. Refutado: «SMR
  inválido → unmatched → bypass» y «programar SMR/S2CR/CB antes del release». K24 = mapear
  icache@0x4000 **en la tabla de CB1**.
- **H2 — geometría MMU-500:** `palawan.dtsi:2536-2539` (`reg = <0x3da0000 0x40000>`,
  `compatible = … "arm,mmu-500"`; arranque: `SMMUv2 … 22 context banks`). **CB0 = 0x20000,
  stride 4 KB** (CB1 = 0x3dc1000). Los bucles del dump (`0x8000+i*0x1000` = tabla S1CD, no CB;
  `(i<<16)` = stride SMMUv3) **ninguno leía CB1**. El ioremap de 2 MB de K23 se sale del
  recurso (0x40000) hacia `gpu_qtb@0x3de8000`.
- **Par en la tablet hoy** (`SHA-BUENOS.txt` + `docs/historia/ESTADO-VIVO.md`): `boot_a` = K23 `8e7ed4f9…` +
  `dtbo_a` = s263 `fe06fccc…`; slot b = K13-dsid `e0ee47dc…` + s260 `6fbb5173…`. El par
  `s244-bounce` (`ffff8c51…`) + `s229` (`d2a29ea5…`) y el `s240-mem2g` son **históricos**.

## Clases

- **FALSO HOY** — afirma lo contrario de H1/H2 o del par vigente; quien lo siga actúa mal.
- **CADUCADO** — era verdad con fecha, supera o rozará los 14 días de `REGLAS.md` §1.15, o cita
  un estado del aparato que ya cambió; hay que re-medir o marcar.
- **Cosmético** — banner/cabecera ya lo mitiga, o es precisión de cita; no induce a error solo.

Lo que NO puedo corregir yo (no son mis ficheros) queda como **propuesto**. Solo `G §6` lo toco.

---

## FALSO HOY

### F1 (grave, operativo) — `docs/historia/ESTADO-VIVO.md:24-27`: «K23 = ioremap 2 MB — el dump ahora completa»
> Dice: *«K23 = ioremap 2 MB (3 líneas) → … el dump ahora completa y S3 por fin ejecutará»*.
> Debería decir: el ioremap de 2 MB **se sale del recurso** (0x40000 → `gpu_qtb`) y los bucles
> leen direcciones equivocadas (H2): el dump K23 es **ilegible por construcción** y S3 sigue
> incierto. Lo correcto es lo que ya dice el banner de v4: K23b antes de K24.
> Propuesto (ESTADO-VIVO no es mío; el banner superior ya manda al árbol v4, pero este párrafo
> del cuerpo sigue afirmando lo refutado).

### F2 (grave, operativo) — `docs/historia/ESTADO-VIVO.md:39-41`: «leer la sección CBpage del dump K23 (ahora completa)»
> Dice (rama del plan-al-despertar): *«leer la sección **CBpage** del dump K23 (ahora completa):
> si hay CB con TTBR0… → K24»*. Debería decir: con K23 **no hay CBpage utilizable** (H2: ningún
> bucle leía CB1 = 0x3dc1000; las `CBpage(2/3)` plausibles son CB0/CB16 mal etiquetadas —
> `docs/historia/RUNBOOK-SIGUIENTE.md:57-59` ya lo advierte). La rama solo es evaluable con K23b.
> Propuesto. Atenuante: la sección lleva cabecera HISTÓRICO y el banner manda a v4 §P0.4.

### F3 — `docs/historia/PLAN-SIGUIENTE-v3.md:125-128`: K24 «K19-style: programar a mano SMR+S2CR+CB»
> Dice: *«Si el dump muestra `SME(5)` inválido (SMR/S2CR sin traducir) → **K19-style**:
> programar a mano SMR id=5 mask=0 + S2CR translate→CB + CB…»*. Debería decir: subcaso 1
> **refutado el 1-oct** (H1: el S2CR ya está en TRANS por CB1); el diseño vigente es v4 §P2.4
> (mapear en tabla de CB1). v3 está sustituido por v4, pero quien abra v3 por historial lee un
> diseño refutado sin aviso en el punto exacto. Propuesto: una línea de banner en v3 §P2.

### F4 — `build/gates/revision/V1-critica-plan-v3.md:56-57`: «espacio CB ~0x110000», lecturas dentro
> Dice: *«toda dirección que lee … cae en el espacio CB … dentro del espacio CB ~0x110000 de
> #P49»*. FALSO por H2: el recurso acaba en 0x40000, CB0..21 = 0x20000..0x35000; el 2º bucle
> (`i<<16`, i≥4) lee **fuera del SMMU** y el ioremap de 2 MB invade `gpu_qtb`. La propia V2 §2
> lo refuta. Debería decir: anotación «refutado por V2 §2 (geometría MMU-500)».
> Propuesto (fichero de `build/`, no mío). Es el ítem «espacio CB hasta ~0x110000» del encargo:
> vive en V1:57 y en `PRE-REGISTRO-PANTALLA.md:448` («el espacio CB llega a ~0x110000»).

### F5 — `build/gates/revision/V2-critica-k23b.md:85-86`: «no hay ningún fichero A1»
> Dice: *«la referencia … **no existe**: no hay ningún fichero A1 en este proyecto ni en el
> hermano»*. FALSO: existe `build/gates/prepara/A1-auditoria-instalador.md` (30-sep-2026,
> auditoría del instalador, con §4 «Método EXACTO de internet por USB (NCM), sin WiFi»).
> Verificado con `ls` hoy. Debería decir: «A1 vive en `build/gates/prepara/` (no en la raíz);
> las citas v2-P3.5 / v3:100 / v4:151 son resolubles pero sin ruta».
> Propuesto. Ironía registrada: el informe de revisión necesita su propia revisión en este punto.

### F6 (grave, operativo) — `F-plan-por-fases.md` §F0 y procedimientos: el par `s244/s229` como vigente
> Dicen, como instrucción ejecutable HOY: `F:79` («el par bueno `boot s240-mem2g` + `dtbo s229`
> en slot b»), `F:295-296,337` (backups y shas `ffff8c5126…`/`d2a29ea5…`), `F:312`
> (`head -c … | sha256sum` → debe dar `ffff8c5126…`), `F:926,987` (shell = s244-bounce),
> `F:1520` (gate F0: «2 sha256 del par bueno verificados contra `ffff8c51…`/`d2a29ea5…»`).
> Debería decir: el par operativo es K13-dsid `e0ee47dc…` + s260 `6fbb5173…` (slot b) y
> K23 `8e7ed4f9…` + s263 `fe06fccc…` (slot a); los shas viejos son histórico (están en
> `SHA-BUENOS.txt:historico/` + `backup-par-bueno/historico/`). Un F0 ejecutado al pie de la
> letra hoy **falla el gate contra shas que ya no están en la tablet**.
> Propuesto (F congelado; G §3.7 ya documenta el patrón de citas viejas). No lo corrijo yo.

### F7 — `docs/informes/B-arranque-arch-uke.md:307,867-868,966,972`: «par vigente `s240-mem2g`» / shell s244
> `B:307` («Cmdline verificada … la del par bueno `s240-mem2g`»), `B:867-868` («el par vigente
> es `boot s240-mem2g` + `dtbo s229`»), `B:966,972` (SHELL/SHA_SHELL = s244 `ffff8c51…`).
> Histórico desde el 26-sep tarde (`NOTAS-OMARCHY.md:106-107` ya lo registró). Propuesto: aviso
> en cabecera de B (B congelado). `B:1270-1271` (tabla de artefactos s244/s240) es coherente
> como histórico y no se toca.

---

## CADUCADO

### C1 — `docs/informes/E-paquetes-aarch64-soc.md:299`: serie battmgr «v4, 15-sep-2026»
> Puntero upstream del 15-sep: el 1-oct tiene 16 días → **supera los 14 de `REGLAS.md` §1.15**.
> Re-verificar la serie (`power: supply: qcom_battmgr: add Xiaomi taoyao support`) antes de usarla.
> Propuesto (E congelado; anotar en NOTAS, no mío).

### C2 — `E:251`: `quickshell … 21-ago-2026` como metadato de versión
> Fecha de build, no afirmación re-medible; A1 (30-sep) re-verificó los repos en vivo (200 HOY),
> así que el canal sigue sano. Solo caducará si se fija un mirrorlist sin re-medir (el propio
> E:R7 ya avisa «puede ser transitorio»). Propuesto: nada hasta que se fije el mirrorlist.

### C3 — Medición `edge/aarch64` 148 paquetes (G §3.1, 26-sep; re-verificada por A1 el 30-sep)
> Vigente hoy (5 y 1 días, dentro de plazo). **Caduca ~10/14-oct** si nadie la re-mide.
> Dejo el aviso en G §6 (nuevo ítem 28): re-`curl` de los dos `.db` antes de fijar canal.

### C4 — `B:314,992`: `arm-smmu.disable_bypass=0` como «token no negociable» de la cmdline
> Era el token del par s240; la cmdline vigente (K13-dsid 356 B, K23 dsid) no se ha contrastado
> aquí contra esa lista de «cinco tokens». No afirmo que sea falso — solo que **no está medido
> en el par vigente**. Propuesto: contrastar `B:307-314` contra la cmdline de `SHA-BUENOS.txt`
> (ítem nuevo en G §6).

### C5 — `docs/historia/PLAN-PANTALLA.md:38-43`: mecanismo «con 1 MiB los CB caían fuera del mapeo ⇒ oops mudo»
> Ojo: habla del **apps-smmu @0x15000000**, no del kgsl-smmu @0x3da0000 de H2 — son dispositivos
> distintos y H2 **no lo refuta directamente**. Pero el razonamiento «tamaño de reg[0] ⇒ base de
> CB» usa la misma familia de fórmulas que H2 corrige, así que el mecanismo candidato queda
> **sospechoso hasta re-derivarlo con el ID1 del apps-smmu**. CADUCADO (re-derivar), no falso.
> Propuesto.

---

## Cosmético (con banner que ya mitiga, o precisión sin riesgo operativo)

- **m1 — `docs/historia/AGENTS.md:21-22`** (cuerpo cita `s244-bounce ffff8c5126… + s229 d2a29ea5…` como estado):
  la cabecera del propio fichero ya dice que son HISTÓRICOS y manda a ESTADO-VIVO. Resto:
  una frase en el cuerpo («histórico desde 26-sep») para quien aterriza a mitad de fichero.
- **m2 — `README.md:146-147`** («par `s244-bounce` + `s229` en slot b» en §Estado): termina con
  «Ver `docs/historia/ESTADO-VIVO.md` para el detalle que cambia». Refrasear a pasado («era el … hasta el
  30-sep»). Es el pendiente v3-§8.2 / v4:325, aún abierto → pasa a G §6 como ítem 21.
- **m3 — `docs/historia/RUNBOOK-MAÑANA.md:31-32`** (rollback a s244/s229): el fichero lleva banner SUPERSEDED
  30-sep y manda a RUNBOOK-SIGUIENTE + v2. Solo nota: si se resucita, el rollback vigente es
  `set_active b` (K13-dsid + s260, intacto), no flashear los shas viejos.
- **m4 — Citas A1 sin ruta** (`docs/historia/PLAN-SIGUIENTE-v2.md:45`, `v3:100`, `v4:151`): el fichero existe
  (ver F5); falta la ruta `build/gates/prepara/`. Una línea en cada una.
- **m5 — `docs/historia/RUNBOOK-SIGUIENTE.md`** ya está reescrito el 1-oct (cita a REGLAS.md:12-13, árbol de
  6 ramas, aviso K23 `CBpage(2/3)` en :57-59): **sin huellas**; queda como ejemplo de lo bien
  actualizado. La cita rota a «15 reglas» que v3 §8.1 denunciaba ya no existe en el fichero.
- **m6 — `OBJETIVOS.md`**: fila 5 ya incorpora H1 (TRANS por CB1, 1-oct) y fila 1 la
  reconstruibilidad (ACUMULADO-*.diff); la queja v3-§8.3 («fila 6 cita tras K19») ya no se
  reproduce (`grep K19` vacío hoy). Sin huellas pendientes → se marca aplicado en G §6.
- **m7 — Conteos menores**: V2:116 («18 migas son 16») ya es cosmético autocontenido; G §6
  encabezado «NO aplicados» se reconcilia en §6-ter pero el título sigue despistando → lo
  aclaro en mi edición del §6 (es mi fichero).

## Rutas citadas que NO existen (verificadas con `ls` hoy)

| Cita | Realidad |
|---|---|
| «A1-auditoria-instalador» a secas (v2:45, v3:100, v4:151) | existe en `build/gates/prepara/A1-auditoria-instalador.md` (F5 refuta el «no existe») |
| `bin/uke-*.sh` (docs/historia/AGENTS.md, F:1018…) | viven en el proyecto hermano / `build/gates/`; AGENTS ya avisa que están en `~/proyectos/ubuntu-permanente/bin/` (solo lectura) — documentado, OK |
| `A-port…:495` re-check, `F:~1090` roto | verificados como aplicados en G §6 (ítems 12/17, ver §6-quater) |

## Resumen de conteo

- **FALSO HOY: 7** (F1–F7; graves operativos: F1, F2, F6).
- **CADUCADO: 5** (C1–C5; ninguno bloquea hoy; C1 y C3 tienen fecha de re-medición).
- **Cosmético: 7** (m1–m7; m5 y m6 son «ya está bien», constan para cerrar el grep).
- Corregibles por mí (mis ficheros): **solo las entradas de G §6** (hecho en §6-quater).
  Todo lo demás queda **propuesto** (informes A–G/F congelados + ficheros de otros agentes).
