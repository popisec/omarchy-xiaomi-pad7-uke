# CRÍTICA TOTAL k65→R0 — auditoría despiadada (10-oct-2026, solo PC, 0 flashes)

Fuentes: `NOTAS-OMARCHY.md` ll.2381–fin (ledgers #535–#580), `build/gates/revision/`
(BARRIDO-W2/W3/W4/W5, PLAN-C/C2/C3, CRITICA-W6-*, BISECT-L0–L7, CRITICA-L8/HW/PLAN,
RE-GBIF/RS/RSALT/STUB/TIMING/WAITS/L12/FWLOAD, PRE-L12/PRE-RENDER/PRE-BREADCRUMB),
`revision/` (BISECT-L8–L15, S250), hermano (`SESION-24SEP-GPU.md`, `ESTADO-ACTUAL.md`,
FLASH-LEDGER #409/#411/#425/#487, AVB-Y-VBMETA.md, R7/R8).

OJO de archivo: `docs/historia/ESTADO-VIVO.md` dice que el ledger #553–#580 está en el
FLASH-LEDGER del hermano; ese fichero termina en #491. El registro real #553–#580
está en `NOTAS-OMARCHY.md`. Puntero documental roto — corregirlo.

## 1. Tabla de veredictos: qué se sostiene y qué cae

Leyenda: ✅ SOSTENIBLE · ❌ CAÍDO · ❓ INDETERMINADO (compatible con los datos,
sin fuerza probatoria).

| # | Veredicto emitido | Auditoría |
|---|---|---|
| #553–#554 k65 mudo + restauración k52b2 | k65 calla; testbed restaurado, k64 nunca se flasheó | ✅ el silencio; ✅ la reconstrucción (#550b era inferencia). Pero todo lo construido sobre "k64" como baseline es fantasma |
| #555 "D3 exonerado" (k66) | binario sin D3 calla ⇒ D3 no es el asesino único | ❓ como exoneración: **4 variables a la vez** (D3 fuera + poll vendor + G10 + G8). Solo ✅ acotado: D3-inútil (GDSC sin `set_performance_state`, ref fuente) |
| #556 "D2 exonerado, D1 nº1" (k67) | sin D2 calla ⇒ D2 inocente | ❓: control 1-variable real pero **D1 corre antes que D2** — muerte en D1 deja a D2 sin ejecutar (testigos D2 ≈ 0). Empate D1×K64×enable-path sin partir |
| #559 k69/C1 5/5 mudo | voto CX no resucita | ❓: muerte pre-testigo; no distingue "rdpm ausente" de "muerte pre-resume / gadget roto". El 6/6 idéntico con k63-sin-D (#548d) apunta a instrumento muerto, no a causa |
| #560 k70/C2 6/6 mudo | réplica vendor no resucita | ❓ por lo mismo; k68 (discriminante real) se saltó sin flashear (#558) |
| #561 L0 HABLA | base reconstruida arranca | ✅ (no-byte-igualdad declarada y acotada a IKCONFIG) |
| #562 L1 "K64 inocente" | register_config no mata | ❓: K64 vive en `a6xx_gmu_fw_start`, **camino frío sin probe GPU** (pre-s250). Supervivencia ≠ ejecución del hunk; testigo post-flash nunca verificado. Inconsistencia sin aclarar: #562 anota card0 pero #569 dice "/dev/dri por primera vez" |
| #563 L2 "D1 inocente", #564 L3 "C1 inocente", #565 L4a "D2 inocente", #566 L4b "poll inocente", #567 L4c "D3 inocente" | cada hunk por separado no tumba el arranque | ❓ cada una: **n=1, criterio = solo SSH+ACM, ningún testigo (`UKE-L2`, `UKE-L3`, `D2`, `poll`, `D3`) verificado en dmesg/ACM**. Los negativos en binario sí se verificaron (higiene de build creíble) — eso prueba contenido, no ejecución |
| #568 L5 "la combinación tampoco mata" | D1+D2+D3 juntos no tumban arranque | ✅ como hecho de supervivencia; ❓ como exoneración (sin K64/C1/poll, hereda caveat de ejecución) |
| #569 s250 ARRANCA | probe GPU de serie, card0+renderD128 | ✅ en lo que afirma. No afirma nada sobre hw_init/CM3 (nadie abrió card0 todavía) |
| #570 L6 "cuelgue en ~10 líneas S2→S3" | traza hasta `K44-A`, muere antes de `S3-rst0`; D1/D2/D3 rc=0 | ✅ como localización n=1; las exoneraciones en vivo (rc=0) son otra ventana (pre-release) y sobreviven al flake |
| #571 L7 "2 candidatos" | lecturas en reset seguras; mata soltar (write SYSRESET) o tocar suelto (poll S4) | ✅ acotación |
| #572 L8 "MATA EL WRITE" | `k25-ok → L7-pre-rst`, sin `write-done` | ❓ FIRME-no-CERRADO (la propia CRITICA-L8 lo dejó así: ventana [write…fin-flush-`write-done`] sin resolver, flush asíncrono 120 ms). n=1 |
| #573 L9 "asesino por sustracción" | sin write vive (`write-done → nopoll-ok`, `open rc=0`) | ❌ como prueba determinista tras R0 (ver §4). Diseño 1-línea limpio, pero n=1 por brazo no excluye flake |
| #574 L10 "LLAVE" (C1+C2) | `pre-rst → write-done → post-rst → S3 → nopoll-ok` sin cuelgue | ❌ como confirmación causal (ver §4). Agravante: `L10-gbif/recfg` **ni salen por nombre en el grep** — el criterio fue solo "el write sobrevive" |
| #575 L11 "CM3 suelto mudo" (`HFI -110`) | fix vivo, poll vendor tampoco ve fw | ❌ como caracterización estable: es **un draw** de una distribución que con sha idéntica también produce muerte-en-gbif y muerte-en-pre-rst |
| #576 L12 "fw-map TÓXICO" | muere en `recfg-ok → L12-fwmap` | ❌ atribución empírica: morir entre recfg y pre-rst está dentro de la varianza base (4/6 del 0/6 mueren ahí con L11 puro). Sobrevive el defecto estático (guarda `!virt` no cubre `ERR_PTR`) como código, no como causa medida. Observación ambigua (¿salió el `pr_err` o no? ACM sola no distingue "no corrió" de "corrió sin drenar") |
| #577 L13s "restore RS TÓXICO" | `RS-recfg2-ok → pre-rst`, muere sin `write-done` | ❌: ya desmontado pre-R0 por RE-RS/RE-RSALT (reads refutados por testigos posteriores, writes por `recfg2-ok` drenado; stub no lee G10/8 en write→write-done). Ni se fijó si `L7-pre-rst` salió |
| #578 L14 "ES TIMING" | muere igual sin writes | Mitad ✅: `saved==posts1` ⇒ S1 no borra G10/8 (medida pre-muerte con drenaje vivo, sobrevive). ❌ "es TIMING" como causa positiva: no se sigue; timing-vs-fluke quedó abierto y R0 lo cierra como flake |
| #579 L15 "MUERE EN GBIF, release frágil al timing" | `k25-ok → L10-gbif`, reboot | ❌ la explicación ("cada hunk añade un flush y la ventana se mueve"): **falsa para L15** — RE-GBIF §3 prueba ventana pre-GBIF L11≡L15 (54≡54 insns); flushes ejecutados 9 = 9 en supervivientes y muertos. Re-etiqueta del flake |
| #580 R0 "FLAKE" + 0/6 | misma sha L11 muere en `gbif`; 6 opens → 6/6 muertes en puntos distintos | ✅ el único resultado replicado de toda la serie (n=6). Invalida §4 |

## 2. El axioma que nunca se verificó

**Determinismo del instrumento.** Toda la serie k65→L15 presupone: mismo binario ⇒
misma muerte, y silencio ⇒ muerte por el hunk. R0+0/6 lo refutan de frente:
misma sha, muertes en `gbif/recfg` (2/6) y `pre-rst/write` (4/6), ni intra-boot
estable. Axiomas hermanos jamás verificados:

1. **El lector ACM como instrumento**: "lector armado, cero bytes" sin `tee`, sin
   log archivado, sin foto/getvar en k65–k70 (testimonio, no artefacto); pstore
   jamás leído pese a `pr_flush`/`always_kmsg_dump`.
2. **Muerte pre-código vs gadget roto**: en silencio total son indistinguibles, y
   la escalera L0–L5 solo distingue con/sin testigos *si hay traza*.
3. **Baseline**: k64-nunca-flasheado usado como suelo (#550b), mapa rancio
   (k63+s273 creído k52b2), dtbo s273 experimental constante, cmdline 580 B +
   cpio K34-fw congelados como constantes ciegas a bug común, enable-path (C5)
   intacto en todo L0–L5.
4. **n=1 por flash con batería cayendo 3868→3779 mV** (bump aislado en L13s):
   GDSC/rails marginales como confusor inseparable en cada contraste.

## 3. Evidencia mal leída (lista corta, cada una con coste)

1. **#562 "card0/renderD128" vs #569 "/dev/dri por primera vez"**: sin aclarar qué
   era ese card0 de L1, #562 no prueba nada GPU. Coste: L1 usado como exoneración.
2. **"492 B" de cmdline** (offset mal leído; real 580 B) + ancla cpio relativa
   (`==k64`, no absoluta). Coste: constantes comunes nunca auditadas.
3. **28/28 de k68 con doble-backslash era ficción de gate** (K43 single-backslash
   lo desvela en C2). Coste: confianza en gates no ejecutados.
4. **L10 sin `L10-gbif/recfg` en el grep**: se declaró "C1/C2 confirmadas" con el
   write sobreviviendo una vez. Coste: la LLAVE nunca tuvo su propio testigo.
5. **#579 "cada hunk añade un flush"**: falso para L15 (54≡54, 9=9). Coste: una
   teoría timing construida sobre un conteo que nadie hizo hasta RE-TIMING.
6. **`rc=0 ≠ reloj corriendo`** (CRITICA-L8 §3): D1/D2 "inocentes de verdad" en
   #570 vale para cuelgue-duro, no para reloj parado. La línea `UKE-CM3DBG: clks`
   pedida por CRITICA-HW **nunca fue respondida** — `grep` pendiente en las ACM
   #570–#580, coste cero, sin hacer.
7. **Cambio de firma L8-era (cuelgue DURO) → L13s/L14/L15 (reboot)** leído como
   mismo fenómeno; apunta a watchdog/fabric-timeout, no a stall MMIO (RE-TIMING C3).
8. **CRITICA-W6 aceptada en acta e ignorada en práctica**: baseline k64 (P5),
   protocolo anti-testimonio (P4 tee+getvar+foto+dd), prohibir bundles
   multivariables con instrumento muerto, k68 antes que plan-C (VIAS), vías
   0-flash (pstore-mtdoops, desensamblar enable_clks, golden-state con debugfs).
   #552 sigue solo-ledger.

## 4. Impacto del flake 0/6 sobre L10 (llave) y L11 (mudo) — y arrastre

R0: L11-sha-`78295439…` (la de #575, que llegaba a `nopoll-ok`) muere en `gbif`.
0/6: 6 opens / 3 boots / mismo L11 → 6/6 muertes, 2 en gbif/recfg, 4 en
pre-rst/write. Con tasa base ~0/6 de supervivencia en el linaje L11:

- **L9**: una supervivencia aislada entra en la varianza. Evidencia fuerte
  provisional, nunca cierre. Cae como prueba.
- **L10-LLAVE**: el write+fix sobrevivió una vez; la misma familia muere en
  `gbif` (pre-fix) y en `pre-rst` (post-fix) indistintamente. **Cae como
  confirmación causal de C1+C2.** Sobrevive como hecho histórico n=1.
- **L11-mudo**: un draw. **Cae como caracterización del sistema** ("fw no en RAM
  o stub no corre"). Todo el programa L12–L15, que presupone "L11 llega al poll
  siempre", **pierde su premisa**.
- **L12/L13s/L14-causa/L15**: re-etiquetados del mismo flake (§1), salvo
  `saved==posts1` (medida, sobrevive) y el ranking estático RE-L12 (código, no causa).
- **Sobreviven al flake** (otra ventana o no dependen de supervivencia):
  exoneraciones pre-release L1–L5 + rc=0 en vivo (#570, n=8 boots que hablan);
  K44-lecturas en reset seguras; gates binarios (POKE=113, `and #0x1ff`,
  ventana L11-WRITE 10 insns, GBIF L11≡L15); y el hallazgo que R0 **refuerza**:
  la ventana GBIF→write→poll es frágil/no-determinista. El muro existe; su
  etiqueta causal no.

## 5. Lo que el lado Android/ABL/XBL/TZ explica y nadie midió

Estado heredado al entrar Linux (R8, ESTADO-ACTUAL, #409/#411/#425/#487):

- **Cola ABL**: compone vendor_boot + bootconfig + tokens runtime
  (`mtdoops.boot_index`, `block2mtd`…) **al final**, con buffer finito: el sobrante
  **se corta por la cola de nuestra cmdline** (#425: `mem=` entraba o no según los
  dígitos de `boot_index`). En duplicados **gana el último** (#487: nuestro
  `loglevel=4` vs ABL `loglevel=6`; `always_kmsg_dump=0` vs `=1`): **`loglevel=4`
  nunca surtió efecto en K13–K40**. Fuente de no-determinismo inter-boot jamás
  controlada en la serie L (¿qué tokens ABL cambian entre los 3 boots del 0/6?).
- **splash 43 MB @0xE3940000 vs nuestro `memmap` 26 MB: OVERLAP**, 17 MB de
  framebuffer ABL desprotegidos; `mem=` no quita el banco `0x88…`; CMA en
  `0x88a000000`.
- **s229 vigente = sin watchdog funcional** (`0.watchdog … -EBUSY`); s221 mostró
  que con WDT bindeado la tablet entra en bucle 7→0. Ningún reset actual es el
  APSS-WDT: candidatos **timeout de fabric / WDT de XBL (~2 min) / reset
  secure-PMIC**. pstore vacío no discrimina (vacío en panic, WDT y wedge: DDR
  no sobrevive ni a reboot ordenado, mtdoops nunca adjunto).
- **C1 en contexto de potencia equivocado** (RE-GBIF F4): el vendor limpia
  GBIF_HALT en `hw_init` con rails+clks votados; nuestro C1 toca `gpu->mmio`
  (isla GX) en `gmu_start`, donde el voto GX del host viene después y en Adreno
  732 los rails GX los vota el propio fw tras arrancar. `readl` a esclava
  dormida = stall síncrono → reboot. Mecanismo con sustento, sin determinismo.

Mecanismos firmware capaces de muertes no-deterministas en GBIF/write, sin medir:

1. **Votos RPMH/AOP que Linux pisa** (CX/MX, `ignore_unused`, RSCC-PDC, contienda
   TCS con ADSP/WPSS). Lectura: `clk_summary`, `regulator_summary`,
   `pm_genpd_summary`, `interconnect_summary`, `/sys/kernel/debug/rpmh/*`,
   estados remoteproc, dmesg `rpmh_rsc_send_data`; frío vs tras probe.
2. **GDSC GX/CX retenidos por TZ/AOP** (`CX=0/GX=1`, `rcg didn't update`).
   Lectura: `pm_genpd_summary` + `clk_summary` + DT vivo.
3. **Estado SMMU heredado del BL** (S2CR/SMR, SID5 vs SID0, `handoff-smrs`
   ignorado). Lectura: `/sys/kernel/debug/iommu/*`, dmesg `handoff: … PINADO`.
   Prohibido `devmem`/bind en runtime (#410).
4. **TZ/SCM** (zap-shader `0x9899a000`, CBs seguros, `use_tz`). Lectura:
   `/proc/iomem`, DT vivo `reserved-memory/chosen`, dmesg `qcom_scm/scmi`,
   `getvar` (solo lectura).
5. **Puente ASYNC/GBIF posted-vs-stall** (writel perdido en silencio, readl que
   para la CPU). Lectura: deltas de capturas archivadas (`k25-ok`/`L10-gbif`/
   `gbif-ok` + `[missed N]`), rates y `dtcm-magic`; no tocar MMIO a ciegas.
6. **GPLL0/bi_tcxo compartido con USB/UFS** (firma `USB full-speed + error -71`
   rebajada a no-concluyente por batería #423). Lectura: `clk_summary`
   (padre/rate/enable-count), correlación consola-USB vs muertes.
7. **Handoff splash/memoria** (§ overlap). Lectura: `/proc/iomem`, `reserved mem`,
   `/proc/cmdline`, `uke-console-cap.sh`.

## 6. Lo que toca (cero flashes hasta estabilizar)

1. Recargar a **batería ≥3850 mV** (fija confusor voltaje), luego **N≥10 opens de
   card0 en el mismo boot** del L11 vivo (lo que #580 ya ordena), anotando último
   testigo por intento. Estima tasa base y distribución de sitios.
2. **Doble canal obligatorio** por open: ACM + `dmesg -w` + foto LAST-POKE +
   pstore tras reboot. Separa watchdog-reboot de stall seco; distingue
   `UKE-POKE:` de `UKE-Lx:` (lag ACM).
3. **`grep "CM3DBG: clks"` en ACM #570–#580** (petición CRITICA-HW C3, coste cero,
   pendiente): ausente/cero ⇒ reloj a RANK 1; 220M/200M ⇒ C3 casi muerta.
4. **Discriminadores RE-FWLOAD §4 sin flash**: `dmesg | grep -E "UKE-K39|UKE-K20|
   UKE-K13"`, `uke_gmu_shared`, `iommu_groups`, `grep -i "fault.*iova"`.
5. Regla de lectura: si a batería alta N opens estabilizan hasta HFI ⇒ base
   estabilizable (ahí sí, L16-ciego vendor-estilo como hardening); si la
   dispersión persiste con firmas watchdog ⇒ vía estabilización
   (rails/GDSC/medida), **no más hunks**; si K39/faults ⇒ capa CB.
6. Deuda de método antes del próximo flash: P4 (tee+getvar+foto+dd), testigos
   post-flash obligatorios en el criterio HABLA, n≥2 o lenguaje "compatible con",
   k68 pendiente (#558) o archivado explícito, corregir puntero ledger en
   docs/historia/ESTADO-VIVO.md.
