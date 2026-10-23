# RESUMEN DE SESIÓN — 12-oct-2026 (pantalla Xiaomi Pad 7 «uke»)

> Documento único de traspaso. Recoge todo lo que se hizo, lo que se erredó y lo que se decidió.
> Fuentes primarias: `docs/historia/ESTADO-VIVO.md`, `NOTAS-OMARCHY.md`, `build/gates/revision/`,
> `~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md`.
> **Nada de lo que sigue está sin medir**: cada afirmación lleva su evidencia.

---

## 1. Conclusión en una frase

**El aparato está sano y el objetivo casi está; el único bloqueo que queda es la pantalla, y el
instrumento que se estaba usando para diagnosticarla (la consola ACM) es *lossy* y yaqjaba al menos
un resultado falso.** El panel TDDI nunca ha ejecutado su `prepare` en ningún ciclo.

---

## 2. Estado actual del aparato (medido al cierre)

| Qué | Valor |
|---|---|
| Par en slots | **slot a = L25 `04cd4980…`** + dtbo_a = s275-r2 |
| Kernel | mainline 7.2-rc2 «palawan» + `msm.uke_skip_mdss_reset=1` (BCR saltado) + `video=DSI-1:d` |
| Conexión | **RNDIS/USB `192.168.42.129`** — `ssh -i build/rootfs/uke-arch-root root@192.168.42.129` |
| Uptime | 28 min, 993 MB libres, load bajo |
| GPU | **FD735 + GLES 3.2** (Mesa/freedreno, mainline) |
| Panel | probean ✓, enganchado a los 2 hosts DSI ✓, **`prepare` NO corre** (`K47-pan-prep`=0) |
| Conector | `disconnected` / `disabled` (efecto de `:d`) |
| Slots | `slot-retry-count:a` = 6-7 ⚠️ · `slot-unbootable:a` = no · `current-slot:a` |
| Batería | ~3570 mV ⚠️ (gate del proyecto: ≥3700; en fastboot no carga) |
| Escritorio | rootfs con **510 paquetes Omarchy** instalado y verificado (hyprland 0.56.2, quickshell, sddm+NM) |

---

## 3. Los cuatro hallazgos que cambian el diagnóstico

### 3.1 La pantalla negra de L19 no era un fallo — era `video=DSI-1:d`
Con `:d` el conector queda `disabled` y **`o82_prepare` nunca corre** (0 marcas `UKE-P82`). El
backlight a 307/4095 era **remanente del ABL**, no de Linux (rails `use=0`, PLLs 0/0, `/dev/fb*` no
existe). Consecuencia: para probar el BCR había que además quitar `:d`.

### 3.2 El aborto de L22b fue un **panic**, no un cuelgue
`bootinfo.pureason=0x800011` (clase panic). Y contra lo que decía un informe, **ramoops SÍ está
activo** (`pstore: Registered ramoops as persistent store backend`, 4 MiB @`0xa7000000`), aunque
persistió 0 ficheros de ese panic.

### 3.3 El gate `dispcc.uke_skip_pll` **nunca disparó**
`KBUILD_MODNAME` del objeto es `dispcc_sm8550` (`Makefile:171`); la cmdline decía
`dispcc.uke_skip_pll=1`. Un prefijo mal no avisa. → **L22b fueron 3 gates, no 4** y la lectura del
ledger #612 era falsa.

### 3.4 El BCR es *load-bearing* para el bind, pero no es el asesino del panel
- **L24** (BCR saltado + sin `:d`): boot loop, muerte ~4,0 s en `dpu_kms_hw_init`/`msm_kms_init_vm`.
- **L25** (BCR saltado + **con** `:d`): **vive**; DPU bindea a 3,965 s, `K47-tx-alloc` alcanzado, panel
  probean ×5, ambos DSI enganchados. Llega exactamente al punto donde L24 moría.
- ⇒ `:d` era **causalmente inerte** en la muerte de L24 (se aplica ~0,4 ms después del punto de muerte).
  **Lo letal era el skip del BCR sobre un scanout del ABL vivo**, no el `:d`.

---

## 4. Correcciones de errores propios (importante leerlas)

| # | Error | Corrección |
|---|---|---|
| 1 | Atribuí la muerte de L24 a "quitar `:d`" | El código muestra que `:d` se aplica **después** del punto de muerte. Lo letal era el skip del BCR |
| 2 | "0 marcas `UKE-P82:` ⇒ el prepare no corrió" | Esas marcas son `pr_info`, filtradas con `loglevel=4`. Su ausencia **no prueba nada** |
| 3 | **"L26: `K47-pan-probe`=0 ⇒ el panel ni probean"** | **Medición inválida.** El ACM es *lossy* a 115200. El log de L25 —**vivo**, donde `dmesg` por SSH da `K47-pan-probe`=5— **también da 0 en ACM**. Esas marcas nunca están en la consola. Es el «sin errores» falso de #428→#429 y la regla 4 (doble captura obligatoria) |
| 4 | El artefacto L22 original se perdió (sobrescrito por L22b con el mismo nombre) | Recuperado como diff de los gates; el L22 exacto ya no es reconstruible sin revertir, pero el diff existe |
| 5 | Los gates de L22b estaban en el árbol **sin diff**, y el árbol no era repo git | Violaba REGLAS. Diff generado y verificado (`l22b-mdss-reset-vbif-clk.diff`) |

**Hecho sólido de L26: solo murió a 4,03 s tras `vsync_clk … -22`.** El resto es desconocido.

---

## 5. Vías de fuerza bruta — veredicto de la crítica (3 subagentes adversariales)

Plan evaluado: `build/gates/revision/PLAN-FUERZA-BRUTA-20261012.md` (BF-1..BF-4).

| Vía | Veredicto | Motivo |
|---|---|---|
| **BF-1** raw modeset sobre L25 | ⚠️ incoherente | Conector `disconnected` no acepta modeset. Pero su pregunta se responde **sin flashear** |
| **BF-2** copiar secuencia vendor | ⚠️ **ya está hecha** | Existe `SECUENCIA-ENCENDIDO-ANDROID-O82-20261012.md`: secuencia real extraída del `msm_drm.ko`. **Los 108 DCS de `o82_prepare` son idénticos byte a byte.** Quedan **5 diferencias concretas**, no 108 |
| **BF-3** replay de registros MMIO | ❌ **MUERTA** | Lee miles de regs con sub-bloques clock-gated que no responden (stall AXI) y regs W1C que **se limpian al leer** ⇒ el dump altera lo que mide. Viola LECCIONES ronda 33 |
| **BF-4** kernel vendor SDE | ❌ **MUERTA al objetivo** | SDE no es KMS estándar ⇒ Hyprland no arranca. La GPU pasa a KGSL ⇒ **se pierde freedreno FD735**. Compra panel sin escritorio |

**Las 5 diferencias que quedan frente al vendor** (de `SECUENCIA-ENCENDIDO`):
orden host-antes-que-DCS; reset asertado desde el probe; falta el rail `vci`/L19; sleep 100 ms vs
15 ms; falta el doble reset. El techo real está en **host/PHY/clocks**, no en el panel.

---

## 6. Hipótesis refutadas con medición (no reabrir)

| Hipótesis | Refutación |
|---|---|
| IRQ fantasma del mdss | `dsi_isr`×2 + `msm-kms` en **0**, quietas 49 s |
| Colapso del GDSC | `mdss_gdsc = on`; `pd_ignore_unused` funciona |
| ESD 86/87 del TDDI son la causa | 1 edge por línea, 36 ms de vida posterior = **síntoma** |
| SMMU-panel | Refutada (#445) |
| El vsync `-22` retargeta clocks | `set_rate` falló ⇒ no escribió ⇒ inocuo |
| El "killer unificado" CM3/GPU era el panel | Premisa caída (#595/#608) |
| `modetest` cuelga porque el open DRM carga GPU | #P43: cuelga igual sin la carga GPU |

**Apoyada con huella en log**: clobber de RCG compartido
(`mdp_clk_src: rcg didn't update` 0,31 s; `mdp_clk` quedó en 514 MHz congelado por `clk_ignore_unused`).

---

## 7. Ruta recomendada (convergió 3/3 críticos)

**Principio**: dejar de apostar el sistema entero al panel en cada flash.

1. **Cero flashes — arreglar el instrumento.** `dmesg -n 7` + captura por SSH, o subir `loglevel`
   en la cmdline. Toda conclusión tomada del ACM debe marcarse como no verificada.
2. **BF-5a headless (0 slots).** `WLR_BACKENDS=headless` + `wayvnc`/VNC: **validar el escritorio
   Omarchy sin panel**. Esto desriesga el objetivo entero.
3. **BF-5b split (0 flashes).** Sobre L25 vivo, por sysfs y SSH:
   - **excitar el panel solo** (reguladores, `gpio2`, backlight) sin tocar el DPU;
   - **bindear el DPU sin el TDDI** contra un sink (vkms/writeback).
   Separa «mata el panel» de «mata el DPU» — la pregunta aún abierta.
4. **Después, un flash de UNA variable**, con criterios pre-registrados.

---

## 8. Reglas del proyecto que se violaron (y por qué importa repetirlas)

- **Regla 4 — doble captura obligatoria.** El ACM a 115200 pierde la cola; el fallo se lee como
  «no hay evidencia». Ya ocurrió al menos dos veces (L26 aquí; #428→#429 antes)
- **Regla «un cambio por ciclo».** L22b metió 3-4 gates en un boot; uno era fantasma (prefijo). Resultado no atribuible.
- **Regla «un parche sin diff es código perdido».** Los gates de L22b vivían solo en el árbol, sin git.
- **Presupuesto de batería** ≥3700 mV y **≤2 escrituras/día**. En fastboot no carga: bajar de 3700 es inevitable sin cargador.

---

## 9. Artefactos clave y shas

| Artefacto | sha256 | Nota |
|---|---|---|
| `boot-uke-k52L19.img` | `71d89ca6e875941b75af012ac24d20fb7690de407fa341923f2d896557ee51a9` | par bueno de recuperación |
| `boot-uke-k52L25.img` | `04cd49803b9a640212a09386cde6b6992494a30e785d22138609e66d987aeb28` | **el que está flasheado** |
| `boot-uke-k52L24.img` | `3854fcff9b8389a44f3b7849906e308a8c5d2d37872ad86c2f6255a8385824d0` | boot loop (murió 4,03 s) |
| `boot-uke-k52L26.img` | `b512f722d7457bf0241e2ba9c9280e1e048e15e67eb71472f4bd9ad36dad5429` | boot loop; medición parcial inválida |
| `l22b-mdss-reset-vbif-clk.diff` | (fichero) | revierte L22b → L22 |
| `l24-skip-mdss-reset.diff` / `l25-panel-probe-instrumentation.diff` | (fichero) | hunk del skip + instrumentación del panel |

---

## 10. Documentos clave del proyecto

| Fichero | Para qué |
|---|---|
| `docs/historia/ESTADO-VIVO.md` | estado del aparato (fuente de verdad) |
| `NOTAS-OMARCHY.md` | bitácora viva; la sesión 12-oct está al final |
| `build/gates/revision/PLAN-PANTALLA-20261012.md` | plan de pantalla F0–F5 |
| `build/gates/revision/PLAN-FUERZA-BRUTA-20261012.md` | BF-1..BF-4 (evaluados, mayormente muertos) |
| `build/gates/revision/SECUENCIA-ENCENDIDO-ANDROID-O82-20261012.md` | **secuencia real del panel**, extraída del `msm_drm.ko` |
| `build/gates/PRE-REGISTRO-F3b-L25.md` / `-F3c-L26.md` | criterios de lectura previos al flash |
| `build/evidencia/wedge-l24-bootloop.log`, `wedge-l26-bootloop.log` | logs de los boot loops |
| `~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md` | ledger de flashes (hermano) |

---

## 11. Lo que NO se hizo (y por qué)

- **No se flashó L25 con `:d` fuera** más allá de L26, porque L26 murió y su medición fue inválida;
  no se repitió con doble captura. Queda pendiente si se quiere confirmar.
- **No se clonó el fuente vendor de display** (BF-2): ya está extraído en `SECUENCIA-ENCENDIDO`.
- **No se tocó BF-3/BF-4**: vetados por la crítica (riesgo de cuelgue/brick y de matar el objetivo).
- **No se flashó nada sin `set_active a`** ni sin verificar sha previo.