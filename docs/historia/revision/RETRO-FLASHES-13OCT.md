# RETRO-REGISTRO (borrador) — los 9 flashes del 13-oct-2026 sin fila en el ledger

**Estado:** BORRADOR para backfill de `~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md`.
**Deuda que cierra:** `docs/historia/ESTADO-VIVO.md:142-145` + nota de deuda declarada en la fila #613 del ledger
("Los flashes del 13-oct (L39, L39d, L39b, L40, L41, L42, s284, s285, s283) siguen sin fila propia").
**Numeración:** se usan `#R1…#R9` a propósito — **NO `#615+`**, que están reservados como secuencia viva
del ledger (el ledger iba por #614 la noche del 13-oct).
**Regla de shas:** ningún sha se inventa. Todos los shas de artefacto de abajo se verificaron por
`sha256sum` contra el fichero en disco el 13-oct (salidas en §0). Si algo no es verificable, su fila lo dice.
**Alcance:** solo lectura del proyecto hermano (ningún fichero de `~/proyectos/ubuntu-permanente/` tocado),
sin tablet, sin commit (esta redacción es solo el borrador en este repo).

## §0. Verificación de artefactos en disco (13-oct-2026, `sha256sum` reales)

Boot (todos 100663296 B):

| artefacto | sha256 en disco | mtime |
|---|---|---|
| `build/bootimg/boot-uke-k52L39.img` | `5e1d3e4c97c0f4adde665454b89f40971f95d0264df8393e76e9b607f38a996d` | 13-oct 13:07 |
| `build/bootimg/boot-uke-k52L39d.img` | `326d6ca953486cb07e03671cc3752cecf460adb033fa03765eb96f1b831c89ee` | 13-oct 13:15 |
| `build/bootimg/boot-uke-k52L39b.img` | `0f01c1985c6c09cfc2d809e8f298dd63a51f5372abd562956cc1edf6f4ee158c` | 13-oct 16:46 |
| `build/bootimg/boot-uke-k52L40.img` | `100fe1605d4882e492b0d60bdad833bf358a9d0f922f3aab73d99d3fb246206f` | 13-oct 16:56 |
| `build/bootimg/boot-uke-k52L41.img` | `c08170bcdb2ce02f3385cba37a75a529e96855ffe81f596a1333ceb5df25359a` | 13-oct 18:58 |
| `build/bootimg/boot-uke-k52L42.img` | `3328366b5c9482bdac12c40f86e35dccc30d07b488f2dedfe6422c35d850154c` | 13-oct 19:29 |

DTBO:

| artefacto | sha256 en disco | tamaño | mtime |
|---|---|---|---|
| `build/bootimg/s281-boot-dtbo-gpu-display-opp148.img` (F10, contexto, NO es uno de los 9) | `90e41a6b4b91f47451bb18c0518193997604df7362631f7f3946c3ad6481b437` | 607326 B | 13-oct 02:00 |
| `build/bootimg/s283-boot-dtbo-gpu-display-opp148-nogpr-bl.img` | `a8e7d4c06af2733445ccf40d15f2efcd1d076cc3702698665c3e5ff076c610d7` | 607905 B | 13-oct 16:46 |
| `build/bootimg/s284-boot-dtbo-gpu-display-opp148-nogpr-bl-geni.img` | `f6ed6ced41bf4bc1705e0a4cb736b7a0dba42dace1dd5b63f68f1b73c50f9454` | 609778 B | 13-oct 17:47 |
| `build/bootimg/s285-boot-dtbo-gpu-display-gpi-only.img` | `0b0b16b569e7212bd5f6dfa8a17d43c512a812f9950ca7bcd2084914d181bf06` | 608322 B | 13-oct 19:38 |

Corroboración cruzada (los informes citan los mismos shas antes/después de flashear):
L39 `L39-RESULTADO-20261013.md:4` + pre-registro `L39-PLAN-20261013.md:427`;
L39d `L39-RESULTADO-20261013.md:101`; L39b rollback `L39-RESULTADO-20261013.md:156`;
L40 `L39-RESULTADO-20261013.md:153`; L41 pre-registro `docs/historia/revision/G4-LANE-MAP-ANALISIS-20261013.md:93`;
L42 pre-registro `docs/historia/revision/G4-LANE-MAP-ANALISIS-20261013.md:143` + `NOTAS-OMARCHY.md:4197-4198`;
s283 `charge/repack-s283-report.txt:21` + `NOTAS-OMARCHY.md:4231` + ledger #613;
s284 `charge/repack-s284-report.txt:26`; s285 `charge/repack-s285-report.txt:22` + `NOTAS-OMARCHY.md:4215`.

Formato de cada fila: el del ledger (plantilla: filas #608–#612 y #613–#614 —
cabecera `### #Rn — …`, bloques `**Qué es.**`, `**Artefacto.**`, `**Resultado.**`).

---

### #R1 — L39 GAPS G5+G6 DE PHY (13-oct 13:08): el panel emitió luz por primera vez; muerte anterior a 3,5 s, sin log.

**Qué es.** Primer kernel con los timings de PHY del vendor (G6: 14 `TIMING_CTRL` calculados →
constantes `00 27 0a 0a 1b 19 0a 0b 0a 02 04 00 20 0f`, confirmadas en `stock-norm.dts:13266` + 5 nodos
o82; `L39-PLAN-20261013.md:114-137`) + `LANE_CTRL0 0x1f→0x15` (G5, `L39-PLAN-20261013.md:203-220`).
Plan completo: `build/gates/revision/L39-PLAN-20261013.md`. Batería 3530 mV — gate 3700 incumplido,
aceptado por instrucción explícita del dueño (`L39-PLAN-20261013.md:434`).
**Nota de deuda (atribución): L39 NO es un cambio único, son 4 variables** — G5 + G6 + hunk L38
heredado nunca flasheado solo (reset 100→15 ms) + 4 símbolos de config `=m→=y`
(`L39-RESULTADO-20261013.md:61-68`; el árbol ya contenía L38: `L39-PLAN-20261013.md:349-373`).
Si mueve la aguja no se sabrá cuál fue.

**Artefacto.** `build/bootimg/boot-uke-k52L39.img` (100663296 B) sha256
`5e1d3e4c97c0f4adde665454b89f40971f95d0264df8393e76e9b607f38a996d` ✓ en disco (§0),
pre-registrado ANTES de escribir (`L39-PLAN-20261013.md:424-437`; kernel `51eeeb37…`).
Partición `boot_a`; `set_active a`; dtbo ya puesto = s281/F10.

**Resultado.** `fastboot flash boot_a` 96 MB OKAY en 2,1 s (13:08:01), `set_active a` OK, reboot 13:08:21
(`L39-RESULTADO-20261013.md:11-18`). **El dueño vio la pantalla iluminarse** ("cargan líneas del log,
se pone blanca un poco, y luego se reinicia"; `L39-HALLAZGO-PANEL-LUZ-20261013.md:10-11`) — primera luz
del panel en 39 rondas. El boot falló después: caído a fastboot a las 13:12:28 con
`slot-unbootable:a:YES`, retry 0 (`L39-RESULTADO-20261013.md:18`). Reflash del mismo L39 a las 13:12:56
(sin USB, fastboot a ~15 s) y tercer arranque L39d a las 13:15:35 (sin USB 6+ min)
(`L39-HALLAZGO-PANEL-LUZ-20261013.md:17-21`). **ACM 0 B en los tres arranques** (`L39-RESULTADO-20261013.md:25-27`;
lector armado en fastboot donde no existe `/dev/ttyACM0`, `L39-RESULTADO-20261013.md:43-50`).
Lectura honesta: con `CONFIG_DRM_FBDEV_EMULATION=n` y sin `video=` nadie pidió commit ⇒ lo visto es
**luz sin imagen** (backlight/TDDI, enlace sin contenido), y la muerte es entre el probe de display
(~0,6 s) y el bind del UDC (~3,5 s) (`L39-HALLAZGO-PANEL-LUZ-20261013.md:35-41`).
Matiz posterior (13:4x): la luz NO puede ser mainline (KTZ sin nodo DT nunca probea; DCS 0x51 no toca
los LED) ⇒ estado persistido del ABL (`NOTAS-OMARCHY.md:4184-4187`, hipótesis). Rollback documentado:
L33 (`L39-RESULTADO-20261013.md:86-88`).

---

### #R2 — L39d `panic=600` (13-oct 13:15): ventana de pstore que no podía abrirse; 0 B esperado.

**Qué es.** Reintento instrumental del R1: idéntico kernel (byte-idéntico, `51eeeb37…`), solo
`panic=10 → panic=600` en cmdline (verificado token a token) para colgar 10 min ante un pánico y dar
ventana a SSH + pstore (`L39-RESULTADO-20261013.md:92-109`).

**Artefacto.** `build/bootimg/boot-uke-k52L39d.img` (100663296 B) sha256
`326d6ca953486cb07e03671cc3752cecf460adb033fa03765eb96f1b831c89ee` ✓ en disco (§0),
citado en `L39-RESULTADO-20261013.md:100-101`. Partición `boot_a`.

**Resultado.** Sin USB del todo (ni fastboot, ni red, ni ping) durante 6+ min; ACM 0 B
(`L39-HALLAZGO-PANEL-LUZ-20261013.md:21-23`).
**Nota de deuda (valor esperado ~0):** el propio informe declara la limitación ANTES del flash —
solo ayuda si el pánico ocurre DESPUÉS de que el USB levante; L39 muere entre ~0,6 s y ~3,5 s, así que
sigue sin consola, y `panic=` no puede ayudar porque abre la ventana después del pánico sin USB
(`L39-RESULTADO-20261013.md:106-109`; `L39-HALLAZGO-PANEL-LUZ-20261013.md:39-41`). Run con valor
medido nulo por diseño, no evidencia contra nada.

---

### #R3 — L39b + s283 (13-oct 16:47): el kernel que por fin arrancó hasta SSH; el panel no probea por falta de I2C.

**Qué es.** Config de vuelta a `=m` en los 3 símbolos de carga (revierte el `=y` de L39; commit `5c82899`)
+ panel a `drm_panel_of_backlight()` (backlight externo KTZ8866, commits `988af8b`/`9e7fa34`) sobre el
dtbo s283 con `backlight = <&ktz_bl_0>` resuelto. Contexto: `L39-RESULTADO-20261013.md:113-116`.

**Artefacto.** `build/bootimg/boot-uke-k52L39b.img` (100663296 B) sha256
`0f01c1985c6c09cfc2d809e8f298dd63a51f5372abd562956cc1edf6f4ee158c` ✓ en disco (§0),
citado como rollback en `L39-RESULTADO-20261013.md:156`. DTBO del run: s283 `a8e7d4c0…`
(`L39-RESULTADO-20261013.md:116`).

**Resultado.** El kernel **arrancó y llegó a SSH** (primera vez en muchas rondas), ACM funcionando.
**Pero no hay `card1`**: `panel-xiaomi-o82-dualdsi: failed to find external backlight`
(`L39-RESULTADO-20261013.md:117-123`). Causa raíz medida: el phandle SÍ resuelve
(`backlight = <0x703>` → `…/i2c@a80000/ktz8866@11` en `/proc/device-tree`), pero
**no hay ningún bus I2C en el puerto** (`/sys/class/i2c-adapter/` y `/sys/bus/i2c/devices/` VACÍOS;
`geni_spi a90000.spi: error -ENODEV: Failed to get tx DMA ch`) (`L39-RESULTADO-20261013.md:125-136`).
Primera causa concreta y medida del panel que no enciende (no es PHY/timings/reloj).
Hipótesis propia refutada en el mismo informe: faltar `dmas` en `qcom,geni-se-qup` — falso
(`qcom-geni-se.c:1571` no pide DMA; `L39-RESULTADO-20261013.md:141-144`).

---

### #R4 — L40 backlight no bloqueante (13-oct 17:0x/18:35): la muerte del SoC capturada con log por primera vez.

**Qué es.** Una línea de intención: el fallo duro de `drm_panel_of_backlight` pasa a `dev_warn`
(commit `9e7fa34`) para que el panel SÍ probee sin I2C y el enlace DSI sea medible
(`L39-RESULTADO-20261013.md:148-164`). Auditoría escéptica del paquete: `docs/historia/revision/REV-L40-KERNEL-C-20261013.md`.
**Nota de deuda (atribución): L40 tampoco es un cambio único** — mínimo 4 deltas no probados por
separado (G5, G6, PPS-dual, backlight-externo+warn) + reset 15 ms heredado (`docs/historia/revision/REV-L40-KERNEL-C-20261013.md:12-19`).

**Artefacto.** `build/bootimg/boot-uke-k52L40.img` (100663296 B) sha256
`100fe1605d4882e492b0d60bdad833bf358a9d0f922f3aab73d99d3fb246206f` ✓ en disco (§0),
citado en `L39-RESULTADO-20261013.md:151-153` (kernel `733c5d3e…`). Rollback: L39b `0f01c198…`.

**Resultado.** Flash L40 + s284: dtbo OK 0,048 s, boot OK 2,166 s, `set_active a`, reboot 18:34:52 →
**muerto a 70 s con ACM 0 B** (`L39-RESULTADO-20261013.md:168-171`; commit `2645f63`). Dos variables a la
vez (kernel L40 + overlay s284), sin atribuir — experimento de separación: L40 + s283 **arranca**
(`L39-RESULTADO-20261013.md:197-200`; `build/evidencia/L40/HALLAZGO-MUERTE-DSI.md:3-6`). Con L40+s283 la
muerte queda **capturada con log por primera vez** (`acm-L40b-s283.log.gz`, 382651 B): secuencia
`host-en → status=4 (FIFO) → prepare/reset COMPLETO → status=5 (FIFO+TIMEOUT) → cmd#0 → host-xfer → stop`,
7 vueltas idénticas, corte en `host-xfer` t=20.375873, sin pánico ni Call trace
(`build/evidencia/L40/HALLAZGO-MUERTE-DSI.md:8-52`). El comando entra en el FIFO del host y nunca sale:
apunta a G4 (lane map).

---

### #R5 — L41 G4 lane map (13-oct ~19:0x): run-1 INCONCLUYENTE por batería; run-2 REFUTA G4 con control.

**Qué es.** Solo los dos `writel` del lane map `0x21/0x84 → 0xAA/0xAA` sobre L40, etiquetado como
**hipótesis falsable, no fix** (el layout `0x12c-0x12f` no cierra; `LANE_CFG0=0xAA` sólido,
`LANE_CFG1=0xAA` sin respaldo; plan + predicción "el síntoma NO cambiará" ANTES del flash:
`docs/historia/revision/G4-LANE-MAP-ANALISIS-20261013.md:53-79,88-113`, commit `b81f733`).

**Artefacto.** `build/bootimg/boot-uke-k52L41.img` (100663296 B) sha256
`c08170bcdb2ce02f3385cba37a75a529e96855ffe81f596a1333ceb5df25359a` ✓ en disco (§0),
pre-registrado en `docs/historia/revision/G4-LANE-MAP-ANALISIS-20261013.md:90-97` (kernel `b61c6b89…`). DTBO: s283 (s284
descartado como wedge). Rollback: L40 `100fe160…` + s283.

**Resultado.** **Run-1: 0 B → INCONCLUYENTE, no evidencia** (nota de deuda de gate): a 3233 mV con corte
a ~3150 solo hay 83 mV de margen; con 3462 mV el mismo kernel arranca
(`build/evidencia/G4/VEREDICTO-G4-REFUTADO.md:33-39`). **Run-2 (control L40 vs L41, mismo s283, misma
sesión): secuencia y punto de parada idénticos** (`prepare → reset COMPLETO → cmd#0 → FIFO → FIFO|TIMEOUT
→ host-xfer → stop`; última línea `host-xfer` t=10.385 vs 9.996; recuentos variables = vueltas del
bucle de reintento) (`build/evidencia/G4/VEREDICTO-G4-REFUTADO.md:6-22`). **G4 REFUTADO**; confirma la
predicción pre-flash. Evidencia: `build/evidencia/G4/acm-L40-control.log.gz` + `acm-L41-g4.log.gz`.

---

### #R6 — L42 G7 SSC (13-oct 19:29–19:33): el gap mejor fundamentado tampoco mueve nada; G7 REFUTADO.

**Qué es.** Cambio único `config->enable_ssc = false → true` en `dsi_phy_7nm.c:1282`, con G4 revertido
antes (`0xAA` → `0x21/0x84`) para no apilar un cambio muerto; diff vs L40 = **una línea**
(`NOTAS-OMARCHY.md:4194-4199`; `docs/historia/revision/G4-LANE-MAP-ANALISIS-20261013.md:117-147`; commit `14b1562`). Era el gap
mejor fundamentado (path SSC completo, 3 parámetros con defaults exactos del vendor 31500/4800/2,
`ssc_center=0` = down-spread, DT con `qcom,dsi-pll-ssc-en` explícito;
`build/evidencia/G7/VEREDICTO-G7-REFUTADO.md:19-32`).

**Artefacto.** `build/bootimg/boot-uke-k52L42.img` (100663296 B) sha256
`3328366b5c9482bdac12c40f86e35dccc30d07b488f2dedfe6422c35d850154c` ✓ en disco (§0),
sha pre-registrado antes de escribir (`NOTAS-OMARCHY.md:4197-4199`; kernel `39149505…`).

**Resultado.** Mismo dtbo s283, misma sesión que el control L40: **misma secuencia, mismo punto de
parada** (cmd#0 5→3, status=4 3→3, status=5 5→3; última marca `host-xfer` 10.385 vs `cmd#0` 10.300;
recuentos = vueltas del reintento, variables) (`build/evidencia/G7/VEREDICTO-G7-REFUTADO.md:6-17`).
**G7 REFUTADO.** Saldo: el síntoma `cmd#0 → FIFO → TIMEOUT` sobrevive a OPP, G5, G6, G4, G7 y PPS-dual —
el modelo "enlace mal configurado" queda agotado; lo que queda es "el panel no está escuchando"
(`build/evidencia/G7/VEREDICTO-G7-REFUTADO.md:36-62`). Evidencia: `build/evidencia/G7/acm-L40-control.log.gz`
+ `acm-L42-ssc.log.gz`.

---

### #R7 — s284 GENI/I2C/DMA (13-oct 18:35, con L40): WEDGE a 70 s con 0 B.

**Qué es.** s283 + 9 fragmentos: 2 del GPI-DMA + 7 GENI (5 i2c + 2 spi); causa: compatibles vendor sin
match en mainline; validador con rutas derivadas del fragmento, gates verdes (commits `5f6ab95`,
`75c96cd`).

**Artefacto.** `build/bootimg/s284-boot-dtbo-gpu-display-opp148-nogpr-bl-geni.img` (609778 B) sha256
`f6ed6ced41bf4bc1705e0a4cb736b7a0dba42dace1dd5b63f68f1b73c50f9454` ✓ en disco (§0),
coincide con `charge/repack-s284-report.txt:26`. Partición `dtbo_a`.

**Resultado.** Flash OK junto a L40 (dtbo 0,048 s; boot 2,166 s; `set_active a`; reboot 18:34:52) →
**fastboot a los 70 s, `out/acm-L40.log` = 0 B** (`L39-RESULTADO-20261013.md:168-171`; commit `2645f63`).
No atribuye solo (dos variables con L40) — la atribución la cierra el R8 (s285 arranca) y la separación
L40+s283 (R4). Lo genuinamente nuevo: GPI-DMA e I2C bindean donde antes no
(`L39-RESULTADO-20261013.md:183-195`).

---

### #R8 — s285 solo GPI-DMA (13-oct ~19:38): ARRANCA; el wedge queda aislado en los GENI/I2C.

**Qué es.** Escalera s283 → s284 → s285: s285 = s283 + **solo los 2 fragmentos del GPI-DMA**
(generador `charge/mkdtbo-s285.py`; corrección propia de `fdtget` sin comillas documentada;
`NOTAS-OMARCHY.md:4211-4223`; commit `84ee942`).

**Artefacto.** `build/bootimg/s285-boot-dtbo-gpu-display-gpi-only.img` (608322 B) sha256
`0b0b16b569e7212bd5f6dfa8a17d43c512a812f9950ca7bcd2084914d181bf06` ✓ en disco (§0),
coincide con `charge/repack-s285-report.txt:22` y `NOTAS-OMARCHY.md:4215`. Gates: fdtoverlay verde,
5 nodos GENI intactos, paridad s283, `uke-dtbo-check.py` limpio (`NOTAS-OMARCHY.md:4216-4218`).

**Resultado.** **Arranca** (`build/evidencia/WEDGE/acm-s285-gpi-only.log.gz`):
los nodos `a00000/800000.qcom,gpi-dma` se recorren sin morirse; el I2C no probea ni una vez (compatibles
intactos); el SPI sigue roto (su `dmas` vacía); el panel repite `cmd#0 → FIFO → TIMEOUT`
(`build/evidencia/WEDGE/VEREDICTO-WEDGE-AISLADO.md:8-23`). **Veredicto: el GPI-DMA es inocuo; el
culpable es hacer que los 5 buses I2C proben por primera vez**
(`build/evidencia/WEDGE/VEREDICTO-WEDGE-AISLADO.md:14-28`). Siguiente peldaño propuesto: s286
(GPI + solo los 5 del I2C, sin SPI). Corrección honesta de la sesión: el `video done timed out` NO es
de s285 — con s283 también sale; la correlación real es el kernel L33 (anterior al parche L36)
(`NOTAS-OMARCHY.md:4233-4252`).

---

### #R9 — s283 baseline display (13-oct 19:53, con L33): vuelta al baseline; userspace SÍ, RNDIS NO.

**Qué es.** Vuelta al baseline tras G4/G7/wedge: `boot_a` ← L33 + `dtbo_a` ← s283
(`NOTAS-OMARCHY.md:4230-4231`; `docs/historia/ESTADO-VIVO.md:66-74`). s283 = s281 (OPP 148648750) + `qcom,gpr`
disabled + backlight KTZ resuelto (paridad verificada en `NOTAS-OMARCHY.md:4216-4218`).

**Artefacto.** `build/bootimg/s283-boot-dtbo-gpu-display-opp148-nogpr-bl.img` (607905 B) sha256
`a8e7d4c06af2733445ccf40d15f2efcd1d076cc3702698665c3e5ff076c610d7` ✓ en disco (§0),
coincide con `charge/repack-s283-report.txt:21` y la fila #613 del ledger. Kernel del run: L33
`bc8b1ca6…` (flasheado 19:44).

**Resultado.** Con L33+s283 el aparato **llega a userspace** (`sshd[765] Server listening`,
`Reached target Graphical Interface`) pero **no hay interfaz RNDIS en el PC** ⇒ sin SSH; cable/puerto
OK (en fastboot enumeran `18d1:d00d`): falla la parte de red del composite gadget
(`NOTAS-OMARCHY.md:4263-4272`; `docs/historia/ESTADO-VIVO.md:113-121`). Firmas ACM medidas (secuencia y punto de
parada comparables, recuentos variables): L33+s283 = cmd#0 ×3, status=4 ×34, status=5 ×0, video-done ×3,
corta 10,29 s; L33+s285 = ×3/×36/×0/×4, 10,34 s (`NOTAS-OMARCHY.md:4254-4261`; `docs/historia/ESTADO-VIVO.md:101-111`).
Batería 3419–3440 mV toda la tarde (< gate; `NOTAS-OMARCHY.md:4279-4283`).
**Nota de alcance:** s283 se escribió al menos 2 veces el 13-oct (con L39b ~16:47 y baseline 19:53;
más el reflash #613 del 20:12, que SÍ tiene fila propia en el ledger) — esta fila cubre el run de
baseline documentado, no cada escritura física (ver §1, no verificable).

---

## §1. Lo que NO se pudo verificar (declaración explícita)

1. **Horas exactas y duraciones fastboot de cada escritura.** Solo tienen tiempo medido: L39 13:08:01
   (2,1 s) + reflash 13:12:56 + L39d 13:15:35 (`L39-HALLAZGO-PANEL-LUZ-20261013.md:17-21`); s284+L40
   18:34:52 (dtbo 0,048 s / boot 2,166 s; `L39-RESULTADO-20261013.md:170`); L39b 16:47, L40 17:0x/18:35
   (por § de informe); L41 18:58 y L42 19:29 (por mtime + commits `b81f733`/`14b1562`, no por log de
   fastboot); s285 ~19:38 (mtime); s283 19:53 (`NOTAS-OMARCHY.md:4231`). No hay transcript de fastboot
   por flash.
2. **`battery-voltage` y `slot-retry-count` por flash.** Solo constan: L39 3530 mV pre-flash
   (`L39-PLAN-20261013.md:434`) y 3439 mV al cierre (`L39-HALLAZGO-PANEL-LUZ-20261013.md:110-112`);
   L41-run1 3233 mV / run-2 3462 mV (`VEREDICTO-G4-REFUTADO.md:33-39`); tarde 3419–3440 mV
   (`NOTAS-OMARCHY.md:4279-4283`); slots del baseline 19:44–20:0x (`docs/historia/ESTADO-VIVO.md:73`).
   No hay `getvar all` por flash.
3. **Contenido de la pantalla de L39.** Solo testimonio del dueño, sin log ni foto
   (`L39-HALLAZGO-PANEL-LUZ-20261013.md:10-11,23-29`); preguntas abiertas §2 del hallazgo sin respuesta
   registrada. El matiz "luz del ABL, no mainline" es hipótesis (`NOTAS-OMARCHY.md:4184-4187`).
4. **Número exacto de escrituras físicas del día.** La deuda dice 9 flashes; el día contiene además el
   reflash de L39 (13:12:56, misma imagen) y el reflash L33+s283 de #613 (con fila propia). Si el ledger
   cuenta escrituras físicas, son ≥11; si cuenta artefactos/run, son 9. El backfill debe fijar el criterio.
5. **F10/s281 (dtbo OPP) NO está en los 9** aunque se flasheó (flash OK 0,051 s a 3415 mV, OPP verificado
   a 148645532 Hz; `docs/historia/revision/EJECUCION-F10-OPP-20261013.md:9-52`). Su flash pertenece al ciclo documentado en
   `docs/historia/revision/EJECUCION-F10-OPP-20261013.md` (¿12-oct tardío o 13-oct temprano? el informe dice 13-oct sin hora y el
   pre-registro es `6383cdd` del 13-oct 02:04). Queda fuera de #R1–#R9 por la definición de la deuda
   (`docs/historia/ESTADO-VIVO.md:144-145` no lo lista); si el ledger lo exige, es una décima fila a añadir.
6. **L41-run1 (0 B a 3233 mV):** hora y log no conservados (solo citado en el veredicto G4); se registra
   como INCONCLUYENTE por la regla adoptada, no como run del experimento.
7. **`Image.gz` intermedios** (`b61c6b89…` L41, `39149505…` L42, `733c5d3e…` L40, `51eeeb37…` L39): citados
   en pre-registros pero no re-verificados en disco en esta pasada (solo los `.img` completos del §0).
