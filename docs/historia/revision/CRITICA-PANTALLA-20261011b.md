# CRÍTICA PANTALLA 20261011b — el wedge de 47 s de s276 y el plan siguiente

Revisión crítica posterior al boot wedged L19+s276 (muerte a t≈47,2 s). Solo-PC: lectura de
logs, dtbo merged, driver del panel, base-DTB y la instrumentación del kernel. Todo lo que
afirmo aquí está verificado contra fichero; lo no verificable va marcado como abierto.

Fuentes medidas para esta crítica:
- `/tmp/acm-s276-final.log` (el boot wedged s276, muere a 47,174 s)
- `out/acm-trigger-035245.log` (el boot bueno L19+s275-r2 #595; corre ≥ 523,8 s)
- `build/evidencia/wedge-trigger-20261011/tablet-witness/` (dmesg del witness hasta 3773,2 s = la muerte #595)
- `mkdtbo-s276.py` / `mkdtbo-s278.py` · driver `panel-xiaomi-o82-dualdsi.c` (árbol k52-L16)
- base-DTB (`~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img`, decompilado) y frag 1460 de s269
- `kernel-pokes/k52-L16-tree/drivers/base/dd.c` (semántica de los markers `UKE-POKE: W:`)

---

## (a) La hipótesis del crawl 4,2→47,2 s: REFUTADA en su forma fuerte; lo que los logs muestran de verdad

### (a.1) El crawl NO es de s276: es idéntico en el boot bueno

La comparación directa de los dos logs desmonta la premisa «los probe-holds se serializan
(5 s × 9) solo con s276»:

| Evento | s276 (muerto) | s275-r2 #595 (bueno) |
|---|---|---|
| Ola W: 1 (ola diferida) | 4,088–4,094 s (ufshc, arm-scmi, qupv3_0, qupv3_1, apps-smmu, display-controller) | 4,081–4,087 s (mismos 6) |
| vsync -22 | 4,0948 s | 4,0879 s |
| `dma-names missing` spi@a90000 | 4,1858 s | 4,1869 s |
| Ola W: 2 | 4,183 s (arm-scmi, qupv3_0) | 4,184 s (arm-scmi, qupv3_0) |
| 1er timeout novatek SPI | **4,3902 s** | **4,3901 s** |
| Give-ups `SPI write @0xff failed` | 7 (10,40 → 47,14 s, periodo 6,14 s) | 6 (10,27 → 40,87 s, periodo 6,14 s) |
| systemd | `Caught <ABRT>` y **freeze a 6,69 s** | 41 líneas normales, sin ABRT |
| Fin del storm → cola | goodix modalias 47,168 + ola W: 3 (qupv3_1, gpio_key, arm-scmi) 47,168–47,174 → **muerte ≤ 6 ms** | nada: sin goodix, sin gpio_key, sin ola 3; vive ≥ 523,8 s |

Puntos que se derivan de la tabla:

1. **El modelo «5 s × 9» no encaja.** La cadencia real es una tormenta del driver
   novatek-nt36xxx-spi: timeout de transfer SPI (~2,08 s) × 2 + backoff = ciclo de 6,14 s;
   6 ciclos en el bueno, 7 en s276. El comienzo es IDÉNTICO al microsegundo (4,390). La causa
   del storm es estructural y compartida: `spi@a90000` no tiene DMA — **el frag 1430 añade
   `dmas;` y `dma-names;` VACÍOS** (verificado en el s269.dts: propiedades sin valor), de modo
   que `of_dma_request_slave_channel` falla (-ENODEV) y el touch TDDI nunca contesta por SPI
   en ninguno de los dos boots. No es la TDDI «que empieza a hablar» por el rail: calla igual
   a 1304 mV y a 1896 mV.
2. **Los markers `UKE-POKE: W:` son la ola diferida.** Verificado en
   `drivers/base/dd.c` (cámara S128): cada `W:<dev>` es una iteración de
   `deferred_probe_work_func` — UN solo hilo que procesa la lista diferida en serie. Por eso
   «se serializan»: un probe síncrono de ~43 s (novatek) mantiene el worker ocupado y todo lo
   que se difiera detrás espera. Pero esto ocurre igual en el boot bueno — y ahí la cola
   queda VACÍA tras 4,19 s. Lo s276-específico es que la cola NO está vacía a 47,17 s
   (qupv3_1, gpio_key, arm-scmi se sondean por primera vez ahí).
3. **gpio_key NO toca pines del panel** (crítica preventiva): su vol_up es PMXR2230 GPIO 6
   (PMIC), no TLMM 168/169. Puede ser el último probe de la cola, no el asesino eléctrico obvio.
4. **systemd murió a 6,69 s en s276** (ABRT + freeze; no aparece en el log bueno, aunque
   podría estar en un hueco `[missed]`). Con pid1 congelado no hay SSH ni NCM: el boot s276
   es inarmable post-hoc. Es un dato s276-específico adicional que ningún modelo «rail-only»
   explica de sobra.
5. **La muerte final es silenciosa y clase wedge** (sin bark, sin fault, sin panic-printed),
   el mismo perfil que #595: la CPU que corre la ola muere sin una línea más.

### (a.2) El patrón transversal que el bisect no vio: TODOS los boots con rail-1896 mueren ~46-47 s

- s276 (rail 1896, sin wdt, sin wifi): **muere 47,17 s**.
- s278-nostrip-nowifi (rail 1896 + watchdog frag): **muere ~46 s** (atribuido al WDT).
- s275-r2 (rail 1304): **vive ≥ 523 s** (y el witness llega a 3773 s).

Dos hechos debilitan la atribución del bisect («el frag watchdog muerde a ~40 s»):
1. El base-DTB NO tiene `watchdog@17c10000` (verificado) y mainline `qcom_wdt` NO arma el
   timer en probe (solo registra; nadie abre /dev/watchdog) — es decir, el frag 1460 como
   mucho crea un device que no muerde. En ESTADO-VIVO #4 el device ni siquiera se creaba.
2. El único boot con rail a 1304 que ha llegado lejos es el bueno; los dos rail-1896 que
   sobrepasaron los 4 s murieron a ~46-47 s. **El parseo parsimonioso: la muerte de ~46-47 s
   es la firma del rail-1896 temprano, no del watchdog.**

### (a.3) Cómo puede el rail matar a 47 s — la cadena candidata (abierta, con un hueco)

Cadena: L8 a 1896 desde el registro (~0,4-0,5 s) → la TDDI tiene su VDDIO en spec → su MCU
arranca (aunque su SPI no contesta) → en algún punto ~41-47 s actúa (IRQ/ESD/líneas) → muerte
silenciosa. Encaja con #595 (reset liberado → TDDI arranca → ESD 86/87 en w2 → muerte ≤100 ms
tras w4) y con el dato de que a 1304 mV (bajo el UVLO del IO) la TDDI es un ladrillo
electricalmente mudo.

**Hueco honesto**: el driver hace `devm_gpiod_get(reset, GPIOD_OUT_HIGH)` en su probe
(~4,1 s), así que desde ahí el reset está asertado. La ventana de «TDDI viva sin reset» es
0,5→4,1 s (pinctrl default del pin, estado heredado del ABL) — la MCU tendría que haber
arrancado en esos ~3,6 s y ser ella la que actuase a 47 s, o bien el reset no está tan
asertado como creemos (el estado real del pin 0,5-4,1 s no está medido). El experimento F2
(§c) compra esta respuesta sin más construcción.

**Veredicto (a)**: el crawl es una constante compartida (tormenta novatek + dma-names vacío
del frag 1430), no el diferenciador. El diferenciador es la cola diferida no vacía + el
freeze de systemd + la muerte silenciosa a 47,17 s — y por eliminación (única diferencia DT)
el rail-1896 es el sospechoso principal, con el watchdog del bisect probablemente exonerado.

---

## (b) El plan vigente y F1b: ambos refutados; F1b no tiene ni camino ni motivo

1. **«L19+s276 estable + enable por SSH» está muerto tres veces**: muerte de boot a 47,17 s
   (hoy), boots #590/#591 con el wedge del enable a 20-40 s, y el freeze de systemd a 6,69 s
   que impide armar nada por SSH. s276 no es una plataforma; es otro paciente.
2. **F1b («subir L8 solo en el enable») no tiene camino runtime**: verificado en el driver
   (`panel-xiaomi-o82-dualdsi.c`): usa `devm_regulator_bulk_get_const` +
   `regulator_set_load` + `regulator_enable` — **no llama a `set_voltage` en ninguna parte**.
   Con `min=1304000/max=1896000` el core no aplica nada al registrar (apply_uV solo con
   min==max), el rail queda al settled de cmd-db (1304)… y nadie lo sube jamás. La ventana
   DT-only es un no-op; implementar el raise exige un hunk en el driver = rebuild L-serie
   (rompe el byte-pin del kernel). Y no hay path userspace (sysfs regulator no expone
   escritura de tensión).
3. **Peor: F1b ya no tiene pregunta que responder.** El rail está exonerado como causa del
   wedge del enable DESDE #591 (L19P+s276: panel encendido por fbcon con el rail a 1896 →
   wedge igual). Y hoy sabemos que el rail-1896 temprano tiene SU PROPIA firma letal (47 s).
   Gastar un flash en F1b compraría la respuesta a una pregunta cerrada con una variable
   que ahora es la principal sospechosa del nuevo problema.

---

## (c) Plan propuesto (3 pasos, orden por ratio información/riesgo)

### F1 — Restaurar el par bueno y reproducir el wedge del enable con trigger correcto (1 flash, todo ya construido)

```bash
# en fastboot:
fastboot flash dtbo_a build/bootimg/s275-boot-dtbo-gpu-display.img   # s275-r2, sha 67a65bc161b645d8… (verificado hoy)
fastboot set_active a && fastboot reboot
```

Boot sano conocido (≥ 523 s, SSH arriba). En la primera sesión SSH (antes de tocar nada):
1. **Instalar la unidad systemd temprana de captura** (§d) — hace los boots futuros
   incapturables-por-ACM capturables sin pérdida, y es lo que permite el paso F2.
2. Armar `uke-ufs-witness.sh` + `uke-wedge-sampler.sh` + `out/acm-loop.sh` (con LOG).
3. **Foto pre-disparo** (§e.3 de CRITICA-KIT-E1): sysfs drm, /proc/interrupts, cmdline, conn.txt.
4. **Disparador = modetest, no `echo on`** (CRITICA-KIT-E1 (c)): descubrir card/conn en
   runtime, `modetest -D /dev/dri/cardN -s "$(cat /root/conn.txt):3200x2136@XR24"`.

Qué compra: (i) cierra la contradicción #595 (si `echo on` no commitea, ¿qué wedgeó? — el
modetest garantiza que la repro pase por el camino de commit real); (ii) da una 2ª captura del
enable con el sampler corriendo y sin huecos; (iii) si sobrevive 60 s, **FOTO** — el milestone
del panel vivo (ver §e). Riesgo: bajo (dtbo existente, par conocido). Si wedgea: es la repro
esperada, con captura completa.

### F2 — Capturar la muerte s276 de 47 s con captura sin pérdidas (mismo dtbo s276, 0 construcciones)

Tras F1 (unidad temprana instalada): reflashear s276
`ef01ed5640a6f9c52c1a0da7fed5b07331d30d4140c4c6f864c31686c3673b27` (verificado hoy),
`set_active a`, reboot. La unidad temprana (DefaultDependencies=no, arranca ~2-4 s, `dmesg >
dump` + `dmesg --follow`) sobrevive al freeze de pid1 (los hijos ya lanzados siguen) y
captura el tramo 4,2→47,2 COMPLETO — incluida la ventana que el ACM perdió — más, si la
unidad lanza el sampler, rails/TLMM/IRQ a 25 Hz hasta el stall.

Qué compra: la respuesta directa a (a) — qué pasa en 4,2-47,2 (¿hay actividad ESD/K49?
¿cuándo muere systemd y por qué? ¿qué hace el drain final?) y quién muere a 47,17 s
(¿gpio_key/qupv3_1/arm-scmi… o nada de lo sondeado?). El timeline completo sin un solo
`[missed]`. Riesgo: nulo (boot ya visto; solo captura).

### F3 — Sellado del bisect + camino del panel (según F2; máximo 2 flashes más)

- **F3a (sellado, 1 flash)**: variante `s279-wdtonly` = s275-r2 (rail min/max = 0, SIN
  reescritura a 1896) + frag 1460 — maquinaria lista en mkdtbo-s278.py (variante nueva con
  `COPIAR = BASE_COPIAR + ['1460']` y el rewrite de 1410 condicionado). Predicción si el
  modelo rail-1896 es correcto: **sobrevive** → watchdog exonerado del bite de ~46 s, la
  firma 46-47 s queda monopolizada por el rail. Nuevo sha pre-registrado en el ledger antes
  de flash.
- **F3b (fix del panel, DT-only si F2 confirma TDDI-viva)**: variante `s279-railhold` = s276
  + pinctrl del pin `platform-reset-gpio` forzado asertado desde el estado boot/sleep del
  frag 1103 (el reset se aserta ANTES de que la TDDI tenga tensión). Predicción: el boot
  s276 deja de morir a 47 s. Es el discriminador causal barato del mecanismo nº1 sin tocar el
  kernel; su éxito abre el fix definitivo del enable (mantener la TDDI en reset hasta tener
  el link DSI, o la variante driver con hunk de 1 línea en `o82_reset` si hace falta).

Qué NO hacer: F1b (§b), flashear s277/strip (muerto), y no perseguir el watchdog como causa
de los ~46 s sin el F3a que lo selle.

---

## (d) Protocolo de captura: el ACM pierde bytes por diseño; la captura fiel va EN-tablet

Diagnóstico del lector actual (`out/acm-loop.sh`): `timeout 3 cat` + `sleep 0.3` = cierre y
reapertura del tty cada ~3,3 s; en cada hueco se pierde lo que llegue (sin lector el buffer
del ldisc se desbota), además de los bytes en vuelo al cerrar. De ahí los `[missed N bytes]`
— 4,4 KB y 96 KB en el log bueno. El tramo 4,2-47,2 s es justo el más denso (storm + ola
diferida + systemd).

Arreglo en dos capas:

1. **Capa fiel (EN-tablet, pérdida 0): unidad systemd temprana.**

```ini
# /etc/systemd/system/uke-bootcap.service  (enable -f; DefaultDependencies=no)
[Unit]
DefaultDependencies=no
After=local-fs.target
[Service]
Type=simple
ExecStart=/bin/sh -c 'mkdir -p /root/witness/bootcap; dmesg > /root/witness/bootcap/dmesg.boot; exec dmesg --follow --ctime >> /root/witness/bootcap/dmesg.boot'
ExecStartPost=/root/uke-wedge-sampler.sh arm
RemainAfterExit=no
[Install]
WantedBy=sysinit.target
```

El dump inicial del ring buffer cubre 0→inicio de la unidad SIN pérdida (buffer ~81 MB
sobrado para 47 s aunque el spam qcom,apr corra a ~45 KB/s), y el `--follow` cubre hasta el
stall (proceso hijo independiente del freeze de pid1). Con esto cualquier boot — incluido uno
ciego — llega con timeline completo + sampler. Copiarla y `systemctl enable` en la sesión SSH
de F1; cada boot posterior queda capturado de nacimiento.

2. **Capa temprana (PC, 0→SSH): lector continuo** en vez de `timeout 3 cat`:

```bash
#!/bin/bash
# acm-reader.sh LOG — un solo lector de larga vida; reabre solo si el tty desaparece
LOG="$1"; : > "$LOG"
while :; do
  if [ -e /dev/ttyACM0 ]; then
    stty -F /dev/ttyACM0 raw -echo 2>/dev/null
    cat /dev/ttyACM0 >> "$LOG" 2>/dev/null   # vive hasta que el tty desaparece
  fi
  sleep 0.05
done
```

Hueco de pérdida residual solo en re-enumeración USB (~ms), no cada 3,3 s.

---

## (e) Criterio de éxito y la FOTO

- **F1 (repro enable con modetest)**: éxito = (a) wedge reproducido con captura completa
  (timeline UFS + sampler + ftrace del witness hasta el stall) → el mecanismo nº1 queda
  medido en el camino de commit real; o (b) **sobrevive 60 s con frame en pantalla → FOTO**
  (móvil al panel; el patrón XR24 del modetest es visible) — milestone «panel vivo» cerrado
  sin ningún flash adicional. Criterio de no-ambigüedad: si `echo on` fue incapaz de
  commitear, la única repro válida del camino de producción es modetest; repetir `echo on`
  no cierra nada.
- **F2 (captura s276)**: éxito = timeline 0→47,2 s sin `[missed]` + sampler sincronizado +
  identificación del evento a 47,17 s (drenaje/gpio_key/arm-scmi vs ESD/K49 vs rail). Falla
  solo si la unidad temprana no arranca antes de 4,2 s (mitigable: mover a
  `After=systemd-tmpfiles-setup.service` o a un hook de initramfs si la rootfs lo permite).
- **FOTO (modetest en el par correcto)**: requisitos exactos — (1) card/conn descubiertos en
  runtime (`ls /sys/class/drm | grep DSI`; `modetest -D /dev/dri/cardN` para conn y crtc;
  escribir `"<conn_id>@<crtc_id>"` en /root/conn.txt CON los testigos ya armados: `modetest
  -c` mató la tablet 2× en K13); (2) comando `modetest -D /dev/dri/cardN -s
  "$(cat /root/conn.txt):3200x2136@XR24"`; (3) cronómetro: si a 60 s sigue vivo, foto +
  `stop` de sampler/witness. El «par correcto» no se supone: en boots previos el DSI ha nacido
  como `card1-DSI-1`, pero la regla es descubrirlo siempre (CRITICA-KIT-E1 (c)).

---

## Apéndice — artefactos verificados hoy (PC)

| Artefacto | sha256 (comprobado hoy) |
|---|---|
| s275-r2 (`s275-boot-dtbo-gpu-display.img`) | `67a65bc161b645d8664c4ba3fd1bfeaa9a92637bc52a1669feab9784fa7e01df` |
| s276 (`s276-boot-dtbo-gpu-display-rail.img`) | `ef01ed5640a6f9c52c1a0da7fed5b07331d30d4140c4c6f864c31686c3673b27` |
| s278-nostrip-nowifi | `23af204b4d5b1e126cea9f25adfcf5c8b5df7a8c93d49f1bdc9ef4783f0ec523` |

Datos duros citados: base-DTB sin watchdog (fdtget rc=1; dtc limpio); frag 1430 = `dmas;`
`dma-names;` vacíos (s269.dts); driver panel sin `set_voltage` (grep completo); reset
hardcodeado en `o82_reset()` (10/3/3/100 ms); `W:` = iteración de la ola diferida
(`dd.c`, cámara S128); storm novatek periodo 6,14 s con give-ups 6 (bueno) vs 7 (s276);
systemd ABRT+freeze 6,69 s solo en s276; gpio_key = PMIC GPIO 6.
