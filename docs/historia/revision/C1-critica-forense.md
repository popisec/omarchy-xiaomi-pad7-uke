# C1 — Crítica forense de la secuencia del 29-sep (K8)

**Autor**: agente crítico C1 · **Fecha**: 29-sep-2026, ~14:38 (reloj de la máquina)
**Método**: sin tablet (prohibido fastboot/adb/ssh/ttyACM0). Solo lectura de journal del PC,
ficheros y artefactos del agente. Ningún commit, ningún cambio fuera de este fichero.
**Objetivo**: demoler o sostener H1/H2/H3 con evidencia verificable.

---

## 0. Aviso metodológico (dos trampas encontradas, afectan a la fiabilidad del orquestador)

1. **`journalctl -k --since/--until` MIENTE en boots anteriores.** Verificado:
   `journalctl -k --since "2026-09-29 00:00" --until "2026-09-29 03:00" | wc -l` = **1**,
   mientras que `journalctl -k -b -1 | grep -c 'usb 3-3'` = **288**. Todas las ausencias que
   afirmo abajo las he comprobado con **greps por boot (`-b 0`, `-b -1`)**, no por rango horario.
2. **Las marcas de wall del bloque de hibernación del kernel son un artefacto.** El tramo
   `Freezing user space processes … ACPI: PM: Preparing to enter system sleep state S4` aparece
   sellado a las 11:36:25 (la reanudación), pero su hora real es 11:14:30-11:14:42: la prueba es
   que `systemd-sleep: Performing sleep operation 'hibernate'` y `kernel: PM: hibernation:
   hibernation entry` (monotónico `[3700.44]`) sí llevan 11:14:30, y `root hub lost power` lleva
   `[3712.999]` — es decir, el kernel pasó de monotónico 3700 a 3713 (12,5 s) a través de un
   sueño de 21m55s, y journald re-estampó al reanudar los printk que quedaron en el ring buffer.
   **Consecuencia práctica: cualquier "hora" leída de ese bloque no es la hora del suceso.**

---

## 1. (a) Reconstrucción minuto a minuto (con citas literales)

Todo lo que sigue está en el journal del PC (boot 0 = arrancado hoy a las 10:12:51; última línea
disponible: 14:30:25). Nada de esto es inferencia salvo donde lo marco como tal.

### Mañana — antes del asunto (contexto y baseline)

| hora | hecho | cita |
|---|---|---|
| 10:12:51-54 | Arranque en frío de **K7** (#P23). Muerte muda. | `usb 3-3: new full-speed USB device number 2/5/6 using xhci_hcd` + `device descriptor read/64, error -71` ×4 → **silencio** |
| 10:46:46-50 | La tablet **vuelve sola a fastboot** (34 min después). | `usb 3-3: new full-speed USB device number 7/8` + `-71` → `10:46:50 usb 3-3: New USB device found, idVendor=18d1, idProduct=d00d` · `Product: Android` · `Manufacturer: Google` · `SerialNumber: SERIE0001` (**high-speed**) |
| 10:46:50 → 11:14:02 | Sesión fastboot continua (dev 9), **cero eventos USB**. Aquí ocurre el flash de K8: `boot-ukek8.img` mtime **11:05:18**, `/var/tmp/uke-k8/verify-k8.py` 11:06:36, `INFORME-K8-BUILD.md` 11:10:15, `PRE-REGISTRO-PANTALLA.md` 11:12:08. | (mtime de ficheros; el flash no generó log alguno — ver §6.2) |

### El arranque de K8

| hora | hecho | cita literal |
|---|---|---|
| **11:14:02** | `fastboot reboot` de K8. La tablet abandona el fastboot. | `usb 3-3: USB disconnect, device number 9` |
| **11:14:03-04** | **Firma de muerte muda** (idéntica a #P17/#P22/#P23): full-speed, descriptor ilegible, y **ningún** high-speed detrás. | `usb 3-3: new full-speed USB device number 10` · `device descriptor read/64, error -71` ×2 · `usb 3-3: new full-speed USB device number 11` · `device descriptor read/64, error -71` → **nada más** |
| **11:14:30** | **El PC se hiberna solo**: upower ve la batería del **portátil** al 2 %. | `systemd-logind[759]: suspend-then-hibernate requested from client PID 1835 ('upowerd') (unit upower.service)...` · `systemd-sleep[96090]: BAT0: Found battery with capacity below threshold (2% <= 5%).` · `systemd-sleep[96090]: Performing sleep operation 'hibernate'...` · `kernel: PM: hibernation: hibernation entry` |
| 11:14:30 → 11:36:25 | **PC apagado (S4)**. Hueco real en el journal: `journalctl --since 11:15 --until 11:36:20 \| wc -l` = **1**. | — |
| **11:36:25** | **Reanudación de S4 del PC.** Los 4 root hubs del PC se re-energizan; re-enumeran solo los dos dispositivos que siguen físicamente vivos en el PC (cámara y BT); en el puerto de la tablet (3-3) **no hay nadie**. | `tailscaled[869]: monitor: time jump detected (slept 21m55s), probably wake from sleep` · `[3712.998821] ACPI: PM: Waking up from system sleep state S4` · `[3712.999067] usb usb1: root hub lost power or was reset` · `usb usb2/usb3/usb4: root hub lost power or was reset` · `usb 3-8: reset high-speed USB device number 3 using xhci_hcd` · `usb 3-10: reset full-speed USB device number 4 using xhci_hcd` · `[3713.014] Restarting tasks: Done` · `[3714.068] PM: hibernation: hibernation exit` |
| 11:36:28 | El PC vuelve a red. | `NetworkManager: dhcp4 (wlan0): state changed new lease, address=192.0.2.16` |
| **11:37:56** | **No es un segundo reboot.** Es el stdout diferido de la orden del orquestador, congelada por la hibernación (21m55s); el comando se lanzó a las ~11:14:02 y su salida se escribió al reanudar: | artefacto `~/.zcode/.../sess_6983cd9f.../call_e42b55a722b64a3a8684e63b-stdout.log`: `Rebooting OKAY [ 0.001s]` · `Finished. Total time: 0.151s` · `sin_ACM0` |
| **11:41:39-40** | 1.º de tres **conectores nuevos en el puerto de la tablet** (3-3), con la firma muerta exacta; nadie enumera. | `usb 3-3: new full-speed USB device number 12` + `-71` ×2 · `... number 13` + `-71` |
| **13:47:00-01** | 2.º conector, idéntico. | `number 14` + `-71` ×2 · `number 15` + `-71` |
| **14:13:06** | 3.º conector, idéntico. | `number 16` + `-71` ×2 · `number 17` + `-71` |
| 14:26:59 / 14:27:01 | Sesión SSH del usuario (sesión 8, ~2 h) que cierra y reabre. Actividad del PC, no de la tablet. | `sshd-session[211748]: Disconnected from user usuario` · `Session 8 logged out` |
| 14:30:25 | Última línea del journal. | `iwd[749]: event: roam-scan` |

### Lo que NO existe (ausencias verificadas por boot, no por rango horario)

- **`1d6b:0104` / `UKE fork shell` / `cdc_acm` / `ttyACM0`: 0 ocurrencias en todo el boot de hoy**
  (`journalctl -k -b 0 | grep -cE '1d6b:0104|UKE fork|cdc_acm'` = **0**; en boot −1 = 28).
  La tablet **no ha presentado su gadget vivo ni una sola vez hoy**. La última vez fue
  `sep 29 01:22:30 cdc_acm 3-3:1.2: ttyACM0: USB ACM device`.
- **`18d1:d00d` (fastboot): 1 sola ocurrencia en el boot de hoy**, a las 10:46:50. Ninguna
  después de 11:14:02. La tablet no ha vuelto a ofrecer fastboot en todo el día.
- **Nada del proyecto se tocó después de las 11:12:08** (`find ~/proyectos -newermt
  "2026-09-29 11:12:30" -type f` → **vacío**). El flash de K8 no tiene log.
- **`~/proyectos/out/uke-console-k7.log` no existe** (el fichero prometido por #P17 no está en
  disco). El script real, `~/proyectos/out/captura-robusta.sh`, escribe
  `~/proyectos/out/uke-console-viva.log`, cuyo mtime es **01:23:48** → no hubo captura durante
  el K8. Tampoco hay proceso de captura vivo ni `/dev/ttyACM0` ahora mismo.

---

## 2. Baseline de firmas USB medidas (el instrumento que faltaba)

Extraído del journal. **Estas firmas son reproducibles y son el único discriminante disponible
sin tocar la tablet.**

| Desenlace | Firma en el PC | Latencia medida |
|---|---|---|
| **VIVE** (kernel arranca, gadget OK) | preludio `full-speed` + `-71` (1-2 device numbers) → **`new high-speed USB device number N`** → `idVendor=1d6b idProduct=0104` · `Product: UKE fork shell` · `Manufacturer: Xiaomi Pad 7 Linux` · `SerialNumber: UKE-S120` → `cdc_acm 3-3:1.2: ttyACM0: USB ACM device` | **9-12 s** tras dejar fastboot (medido 13 veces entre el 28-sep 22:56 y el 29-sep 01:22: 22:56:41, 23:47:42, 00:05:05, 00:06:10, 00:23:44, 00:24:36, 00:50:53, 00:51:45, 00:54:56, 00:55:47, 01:19:51, 01:20:42, 01:22:30) |
| **VUELVE AL ABL/fastboot** (boot muerto, watchdog del ABL) | preludio `full-speed` + `-71` → **`new high-speed USB device number N`** → `idVendor=18d1 idProduct=d00d` · `Product: Android` · `SerialNumber: SERIE0001` | **4-5 s** tras el disconnect (22:55:23→22:55:27; 23:42:01→23:42:05; 00:04:25→00:04:29; 00:59:04→00:59:08) |
| **MUERE MUDA** (handoff BL→kernel sin nadie al mando) | `full-speed` + `device descriptor read/64, error -71` (2-3 device numbers) y **silencio absoluto**; a veces rebote (devs 70-77 con `Device not responding to setup address`) antes de volver a fastboot | sin follow-up (K7 frío #P23 10:12; K8 11:14; y el wedge de 01:40) |
| Retorno del watchdog del ABL tras una muda | `18d1:d00d` high-speed **sin** preludio largo | **22 s** (#P22 03:05:07), **11,7 min** (#P17-bis 01:51:57), **34 min** (10:46:50) |

**Lectura del preludio**: el `full-speed + -71` es la PHY dwc3 que el BL dejó levantada (pull-up
puesto) sin nadie que conteste a los control-transfers (`-71` = EPROTO: el descriptor nunca
llegó). Cuando el kernel arranca, re-enumera él mismo en high-speed y funciona. Por eso la
**ausencia del high-speed posterior** es lo que mata — no el `-71`.

---

## 3. (b) Veredicto por hipótesis

### H1 — «la tablet desapareció del USB a las 11:36 porque el ABL rechazó arrancar con batería 3545 mV (< gate ~3700) y quedó en pantalla de carga/apagada» → **REFUTADA**

1. **Error de tiempo.** La tablet desapareció del USB a las **11:14:02**
   (`usb 3-3: USB disconnect, device number 9`), 22 minutos antes. Su último rastro en el bus es
   `11:14:04 … error -71`. A las 11:36:25 la tablet llevaba rato fuera y **el PC estaba
   reanudando su propia hibernación**.
2. **El evento de 11:36:25 no puede ser de la tablet.** `root hub lost power or was reset` lo
   emite el core USB del PC en el camino de reanudación de S4, **una vez por controlador
   xHCI del PC** (usb1..usb4) — está impreso entre `ACPI: PM: Waking up from system sleep state
   S4` y `PM: hibernation: hibernation exit`. Un periférico no "pierde la energía" de 4 root
   hubs del anfitrión; lo que hace el resume es re-energizar los buses, y por eso re-enumeran
   cámara (3-8) y BT (3-10), que son de este PC. Que la tablet no aparezca solo dice que **en el
   puerto 3-3 no había nadie presentando pull-up a esa hora** — no dice nada de la batería.
3. **Es un mensaje rutinario de este PC, no una anomalía.** `journalctl --since 2026-09-20 |
   grep -c 'root hub lost power'` = **22 líneas en 9 episodios** (20-sep 23:09, 21-sep 05:43,
   22-sep 09:30 y 12:13, 23-sep 16:52 y 17:02, 24-sep 02:49, 29-sep 01:50, 29-sep 11:36), todos
   dentro de ciclos de suspensión/reanudación y todos con la firma `tailscaled: time jump
   detected (slept …), probably wake from sleep`. En el de 22-sep 09:30 no había tablet
   conectada y aun así salió (2 líneas) → **es del PC, se mire por donde se mire.**
4. **La cifra "3545 mV" no tiene ningún artefacto.** `grep -rn "3545"` en gates/, /var/tmp,
   ~/proyectos/out y en los logs del agente solo devuelve tamaños AVB (`35454976`). Las lecturas
   de batería registradas son otras: **3824 mV** (01:51, #P17-bis), **3668 mV** (10:08, #P22),
   y de días previos 3399/3780/4232. Y sobre todo: **un `getvar` a las 11:36-11:37 era
   imposible** — no hubo ninguna enumeración fastboot (`18d1:d00d`) entre 11:14:02 y las 14:13
   (0 eventos), así que no existía dispositivo al que preguntarle.
5. **El mecanismo contradice la documentación del propio proyecto.** `prepara/P5-energia.md:21`
   dice que cuando el ABL no acepta la batería (`battery-soc-ok:no`, lee ~3,4 V) **cae a
   fastboot**, y `:375` que en fastboot no carga. Nunca se ha observado una "pantalla de carga"
   del ABL en este proyecto; sí se ha observado 9 veces la caída a fastboot `18d1:d00d`. Si el
   ABL hubiera rechazado el arranque con la tablet enchufada, el journal tendría un
   `18d1:d00d`: no lo tiene.
6. **Explicación alternativa que da cuenta de TODO el journal** (y que encaja sin residuo):
   `fastboot reboot` a las 11:14:02 → K8 muere mudo en el handoff (firma de §2) → a las 11:14:30
   **el portátil se hiberna porque su propia batería está al 2 %** → S4 de 21m55s → a las
   11:36:25 la reanudación re-energiza los 4 root hubs y re-enumera los 2 dispositivos que siguen
   vivos en el PC; el puerto 3-3 está vacío (tablet muerta y/o desenchufada) → 3 conectores
   posteriores en 3-3 (11:41, 13:47, 14:13) que fallan todos con la firma muerta. Esta lectura
   usa las 4 líneas de root hub, la cámara, el BT, la ausencia de la tablet, el hueco de 22 min y
   las 3 rachas de `-71`; H1 deja sin explicar el hueco, las 3 rachas y la no-aparición.

### H2 — «pantalla BLANCA = splash del ABL congelado = kernel muerto a los ~0,44 s» → **PARCIALMENTE REFUTADA**

- **"Splash del ABL" : SOSTENIDO.** Es la lectura correcta del panel: `docs/historia/ESTADO-VIVO.md:26` ("**El
  ABL dibuja su splash** (pantalla blanca vista)") y `R3-vendor-diff.md §4.6` ("la pantalla está
  encendida desde el ABL (**splash continuo**) y Android no la toca hasta el UI"; primer DPMS en
  Android a los 10,4983 s). El kernel no toca el panel hasta que el DPU bindea.
- **"= kernel muerto" : REFUTADO como inferencia desde la pantalla.** Por los propios documentos,
  un **arranque SANO sin DPU también deja la pantalla en el splash del ABL** (nadie la apaga ni
  la repinta). Es decir: **la pantalla blanca es AMBIGUA por construcción**. Lo único que prueba
  es "el SoC tiene energía y el ABL alcanzó a dibujar". No distingue muerto de vivo-sin-display.
  El proyecto ya lo había avisado dos veces y sigue sin resolverse:
  `REVISION-SESION-PANTALLA.md:117` ("la 'pantalla blanca del ABL' … es INFERENCIA sin archivo")
  y `:273` ("«La pantalla blanca = splash del ABL» | cómo se refuta barato: **foto/registro del
  estado real de la tablet**; hoy no hay archivo").
- **"a los ~0,44 s" no se ha medido hoy.** 0,4449 s es la **predicción** de #P20 ("el probe armado
  corre a los 0,4449 s"), y la tabla de desenlace de `INFORME-K8-BUILD.md:365` la repite como
  escenario. Hoy no hay consola, ni pstore, ni migas: **nadie midió ningún instante de muerte**.
  Presentarlo como "firma de muerte a 0,44 s" es convertir una predicción pre-registrada en
  medición.
- **¿Mantiene el splash durante HORAS?** La evidencia del proyecto dice que **no es el desenlace
  esperado**: tras cada muerte muda observada, el watchdog del ABL devolvió la tablet a fastboot
  en 22 s (#P22), 11,7 min (#P17-bis) o 34 min (10:46 hoy). Y un apagado real sí apaga el panel:
  `docs/historia/RUNBOOK-MAÑANA.md:8` describe el power de 10 s como **"pantalla en blanco/splash → negro"**.
  Si a las 14:22 seguía blanca tras 3 h 8 min, o el watchdog no disparó (fallo distinto de una
  muerte muda normal) o la tablet no estaba en ese estado (p. ej. apagada y en pantalla de carga,
  que es lo que dice H1 — incompatible con "blanca congelada").
- **Conclusión honesta**: el desenlace "K8 murió mudo" **SÍ se sostiene**, pero **por el USB**
  (cero `1d6b:0104`/`cdc_acm` hoy, firma de §2), no por la pantalla. Llamar a la pantalla "firma
  inequívoca" (#P23) es un exceso: es la firma de "SoC con energía + ABL dibujó", y nada más.

### H3 — «K8 podría estar VIVO desde las 11:35; el reset de los root hubs a las 11:36:25 mató el lado PC del USB y la tablet siguió arrancada; los chequeos de las 14:22 no vieron nada porque estaba desenchufada (en cargador)» → **REFUTADA**

1. **Ancla temporal equivocada**: el arranque de K8 es de las **11:14:03**, no de las 11:35. El
   "11:35/11:36" del orquestador es el **despertar del PC** más el stdout diferido de su propio
   comando (§0.2 y §1). El "desde las 11:35" no existe en el journal.
2. **El reset de los root hubs no mató nada del PC.** Fue el camino de reanudación, y dejó el bus
   **funcionando**: en el mismo resume re-enumeraron 3-8 y 3-10, y **5 min después** (11:41:39) el
   puerto 3-3 admitió un conector nuevo (dev 12). Un USB "roto" no acepta device numbers nuevos.
3. **Si K8 viviera, el gadget habría estado arriba desde ~11:14:15** (todo arranque vivo lo
   enumera en 9-12 s: tabla §2), y cualquier re-enchufe posterior habría dado la enumeración
   limpia `1d6b:0104` + `cdc_acm` + `/dev/ttyACM0`. Los tres conectores posteriores (11:41:39,
   13:47:00, 14:13:06) muestran lo **contrario**, y hoy hay **0** ocurrencias de `1d6b:0104`/
   `cdc_acm` en todo el boot. Además, un K8 vivo habría dado NCM/SSH (el login por ttyGS0 está
   esperado a los 3,57 s, `INFORME-K8-BUILD.md:358`).
4. **La premisa "estaba desenchufada del PC (en cargador)" no se sostiene** tal cual: hay tres
   eventos de conector en el puerto de la tablet (3-3) a las 11:41:39, 13:47:00 y 14:13:06, es
   decir dentro de la ventana "en cargador de pared sin PC". O el relato de horas es impreciso, o
   en esos tres instantes la tablet (o su cable) estaba en el PC y falló al enumerar. En cualquier
   caso, **a las 14:13:06 la tablet estaba eléctricamente conectada al PC y no ofrecía ni gadget
   ni fastboot**, 9 minutos antes de la comprobación de las 14:22.
5. **Lo único aprovechable de H3** es la intuición general (un reset del host puede enmascarar a
   un vivo). Es legítima, pero aquí **ya está falsada** porque los tres conectores posteriores
   eran la ocasión perfecta para que un K8 vivo se anunciara y no lo hizo. Y su refutación cuesta
   0 €: mirar si aparece `1d6b:0104` (ver §5).

### Resumen de veredictos

| Hipótesis | Veredicto |
|---|---|
| H1 (ABL/batería 3545 mV, desaparición a las 11:36) | **REFUTADA** (tiempo, mecanismo, cifra sin artefacto, y explicación alternativa completa) |
| H2 (pantalla blanca ⇒ muerto a 0,44 s) | **REFUTADA como inferencia de la pantalla**; "K8 murió mudo" **SOSTENIDA por el USB**; "0,44 s" **NO MEDIDO** (es la predicción de #P20) |
| H3 (K8 vivo desde 11:35, USB-PC roto por el resume) | **REFUTADA** (ancla temporal falsa, bus del PC sano, 0 enumeraciones de gadget, 3 fallos de enumeración en el puerto de la tablet) |

---

## 4. Respuestas a las preguntas de demolición

**Q1.** No, `root hub lost power` no encaja con un rechazo de batería del ABL: es la firma del
resume de S4 del PC, una por controlador, y es rutinaria aquí (22 líneas/9 episodios desde el
20-sep, incluida una sin tablet conectada). La explicación alternativa es la de §3-H1.6.
**¿Puede un dispositivo colgar un xHCI entero?** No de esta forma: los 4 root hubs son
controladores distintos del PC; lo que se apaga y re-energiza en bloque es el PC. Un periférico
puede dejar un puerto en `-71`/disabled (y de hecho lo hace: 3-3 lleva así todo el día), pero no
"perder la energía" de 4 root hubs. **¿Eventos previos?** Sí, 8 episodios previos (20-24 sep),
todos en reanudaciones: la comparación que pedía el orquestador **refuta** su lectura.

**Q2.** Sí, es completamente ambigua: un boot sano sin DPU deja el splash del ABL en pantalla
(`docs/historia/ESTADO-VIVO.md:26`, `R3 §4.6`), y un sistema muerto a 0,44 s deja ese mismo splash congelado.
El ABL no apaga el panel (lo entrega al kernel); lo que apaga el panel es un apagado real
(`docs/historia/RUNBOOK-MAÑANA.md:8`: "blanco/splash → negro"). Por tanto: pantalla encendida = "SoC con
energía y ABL dibujó"; pantalla negra = apagado real. Nada más. Para distinguir vivo-sin-display
de muerto hay que mirar el **USB**, no el panel.

**Q3.** Al re-enchufar un K8 vivo se vería, en 9-12 s: `usb 3-3: new full-speed … -71` (preludio)
→ `new high-speed USB device number N` → `idVendor=1d6b idProduct=0104` · `Product: UKE fork
shell` · `Manufacturer: Xiaomi Pad 7 Linux` · `SerialNumber: UKE-S120` → `cdc_acm 3-3:1.2:
ttyACM0: USB ACM device` → aparece `/dev/ttyACM0` (y NCM/SSH). **Alternativa simple que lo
distingue en 10 s**: enchufar al PC con un `journalctl -kf` ya armado y leer 15 s (§5). No hace
falta flashear, ni consola, ni SSH.

**Q4.** La señal que separa "murió mudo" de "vivo con USB-PC roto" es la **enumeración
high-speed posterior al preludio**: `1d6b:0104` (vivo) vs `18d1:d00d` (ABL/fastboot) vs
**nada** (muerto). Para las 11:35-11:37 ya no se puede recuperar nada más (el journal no tiene
más), pero **la ausencia de las dos primeras firmas en todo el día es concluyente**.
**Faltan** (y hay que pedirlos/capturarlos): (1) la captura de consola — prometida y **no
existente**; (2) el log del flash con relectura de sha y `getvar` de gates; (3) una foto del
estado real del panel (pedida por `REVISION-SESION-PANTALLA.md:273` y aún inexistente tras 4
mudas); (4) `lsusb -t` / sysfs del puerto en el momento del fallo (attached-pero-wedged vs
not-attached); (5) `pstore`/`ramoops` leído tras cada muda (la cmdline ya reserva la región; es
justo el caso para el que existe).

**Captura mínima a instalar AHORA** (barata, sin tocar la tablet):
```
# 1) registro continuo del bus, con monotónico y hora propia
nohup journalctl -kf -o short-monotonic -n0 > ~/proyectos/out/usb-$(date +%Y%m%d-%H%M).log 2>&1 &
# 2) quién está en el puerto 3-3 (y con qué velocidad) en cada evento
nohup udevadm monitor --udev --kernel --subsystem-match=usb --property >> ~/proyectos/out/usb-$(date +%Y%m%d-%H%M).log 2>&1 &
```
más, por cada evento en 3-3, un snapshot con `date -Is; lsusb -t; cat /sys/bus/usb/devices/3-3/{speed,idVendor,idProduct}`.
Y tres reglas de higiene: (a) la captura de consola debe estar **viva y verificada** antes del
flash (`captura-robusta.sh` escribe `uke-console-viva.log`, **no** `uke-console-k7.log`: el
pre-registro nombra un fichero que no existe); (b) **cada comando importante debe escribir su
propia hora** (`date -Is`) en el log — el mtime del harness se congela con la hibernación y fue
lo que produjo la cronología falsa de "flash 11:33 / reboot 11:35:30"; (c) tras cada muda,
`pstore`/`ramoops`.

**Q5.** Lista explícita de cosas dadas por hechas hoy sin medirlas, en §6.

---

## 5. (c) El experimento de 10 segundos que separa las vivas

**E1 — re-enchufe observado (coste: 15 s, 0 flasheos; lo ejecuta el usuario, C1 no toca la tablet).**

1. Armar la escucha (en el PC):
   `journalctl -kf -o short-monotonic -n0 | grep --line-buffered -E '3-3|1d6b:0104|cdc_acm|18d1' | tee -a ~/proyectos/out/e1-plug.log`
2. Enchufar el cable de la tablet al **mismo puerto del PC** (3-3, el de siempre) y **leer 15 s**.
3. Resultado:
   - **(a)** `1d6b:0104` + `UKE fork shell` + `cdc_acm … ttyACM0` → **K8 VIVE**: existe kernel
     arrancado sin display; la pantalla blanca es solo el splash del ABL. Siguiente paso: NCM/SSH
     y re-bind del panel (R2 §7). (Y desmonta H1/H2 de golpe.)
   - **(b)** `18d1:d00d` → el ABL está en fastboot: el arranque de K8 murió y el watchdog lo
     devolvió (o el ABL nunca hizo handoff). En ese momento, y solo entonces, tiene sentido
     `fastboot getvar battery-voltage,battery-soc-ok,current-slot,slot-retry-count:b` (2 s) para
     tener la batería **real** en vez de la cifra fantasma.
   - **(c)** preludio `full-speed` + `-71` y **silencio** → murió mudo en el handoff (K8 muerto,
     confirmación de las firmas de #P17/#P22/#P23, ahora sí **medida para K8**).
4. Si no se quiere ni enchufar: no hay atajo. Con la tablet fuera del PC **no hay ninguna
   observación posible** — y eso es exactamente lo que pasó entre las 11:14 y las 14:13.

*Nota*: E1 no distingue "K8 vive pero su gadget no bindea" (nunca visto: todo arranque vivo
enumeró `cdc_acm`). Si saliera (c) habría que leer `pstore`/`ramoops` antes de dar K8 por muerto.

---

## 6. (d) Suposiciones no medidas (lista explícita, con cita)

1. **«la tablet desapareció del USB a las 11:36»** — medido: **11:14:02**. El 11:36:25 es el
   resume del PC. *(H1; journal citado en §1.)*
2. **«batería 3545 mV»** — sin ningún artefacto (`grep -rn 3545` en gates/, /var/tmp,
   ~/proyectos/out y logs del agente: solo tamaños AVB). Las lecturas reales registradas son
   3824 (01:51), 3668 (10:08), y de días previos 3399/3780/4232. Y sin sesión fastboot entre
   11:14:02 y 14:13 no pudo medirse a las 11:36. *(H1.)*
3. **«el ABL rechazó arrancar … y quedó en pantalla de carga/apagada»** — el mecanismo
   documentado es **caer a fastboot** (`prepara/P5-energia.md:21`), no quedarse en pantalla de
   carga; y si hubiera caído a fastboot enchufada, el journal tendría `18d1:d00d` (no lo tiene).
   *(H1.)*
4. **«pantalla blanca = splash del ABL congelado = kernel muerto a los ~0,44 s»** — la pantalla
   es ambigua por los propios documentos (`docs/historia/ESTADO-VIVO.md:26`, `R3 §4.6`,
   `REVISION-SESION-PANTALLA.md:117` y `:273`), y **0,44 s es la predicción de #P20**, no una
   medición de hoy (sin consola, sin pstore, sin migas). *(H2.)*
5. **«flash 11:33, fastboot reboot ~11:35:30»** — falso: el reboot es **11:14:02**
   (`USB disconnect, device number 9`) y el flash ocurrió entre 10:46:50 y 11:14:02 (sesión
   fastboot continua; mtimes 11:05:18/11:06:36/11:10:15/11:12:08). El 11:37:56 es el stdout
   **diferido** de un comando congelado por la hibernación. *(Cronología del orquestador.)*
6. **«K8 podría estar VIVO desde las 11:35»** — sin artefacto; contradicho por 0 `1d6b:0104`/
   `cdc_acm` en todo el boot y por 3 fallos de enumeración en 3-3. *(H3.)*
7. **«los chequeos a las 14:22 no vieron nada porque la tablet estaba desenchufada del PC (en
   cargador)»** — hay conectores en 3-3 a las 11:41:39, 13:47:00 y **14:13:06** (9 min antes del
   chequeo), los tres con la firma muerta. "Desenchufada" no es compatible con 14:13:06. *(H3.)*
8. **«Captura: `~/proyectos/out/uke-console-k7.log` (vacío)»** — el fichero **no existe**. El
   script real escribe `uke-console-viva.log` (mtime 01:23:48 ⇒ no capturó nada del K8) y no hay
   proceso de captura vivo. *(#P17, #P24, usuario.)*
9. **«Canal: captura consola + SSH» (#P24)** — ninguno de los dos existió: sin `/dev/ttyACM0`, sin
   fichero de captura, y el propio stdout del orquestador dice `sin_ACM0` (11:37:56). *(#P24.)*
10. **«bucle de panic ~30 s» (#P23 / tabla de K8)** — el arranque de K8 **no rebotó nada**: 2
    device numbers en 1,2 s y silencio. El rebote de ~20 s es del caso de #P22 (03:04); atribuirlo
    a K8 es importar la firma de otro boot. *(INFORME-K8-BUILD.md:365, #P23.)*
11. **«la tablet estuvo en cargador de pared, sin PC, entre ~11:40 y ~14:22»** — no medido; los
    tres conectores de 3-3 lo contradicen en su versión estricta. *(Cronología del usuario.)*
12. **«pantalla abierta (blanca) a las 14:22» y «en blanco, no se ve nada a las ~15:0x»** — no hay
    foto ni registro. Además, a las **14:37:56** (reloj de la máquina) el journal no tiene nada
    posterior a 14:30:25, así que "las ~15:0x" está en el futuro de ese reloj: o las horas del
    relato son estimaciones, o el reloj está desviado (`systemd-timesyncd` sincronizó a las
    11:36:31). No se puede fechar cuándo cambió el panel. *(Cronología del usuario.)*
13. **Implícito: «el mensaje de root hub = se reseteó el puerto de la tablet / se rompió nuestro
    USB»** — el mensaje es **por root hub** (controlador del PC), no por puerto/dispositivo, y
    aparece en S3 y S4. *(H1/H3.)*

---

## 7. Anexo — comandos usados (reproducibles)

```
journalctl -k --since "2026-09-29 11:25" --no-pager
journalctl -k -o short-monotonic --since "2026-09-29 11:20" --until "2026-09-29 11:45" --no-pager
journalctl -b 0 -o short-monotonic --since "2026-09-29 11:14:25" --until "2026-09-29 11:15:00" --no-pager
journalctl --since "2026-09-25" --no-pager | grep -n 'lost power'
journalctl --since "2026-09-20" --no-pager | grep -c 'root hub lost power'
journalctl -k -b 0  --no-pager | grep -cE '1d6b:0104|UKE fork|cdc_acm'     # 0
journalctl -k -b -1 --no-pager | grep -cE '1d6b:0104|UKE fork|cdc_acm'     # 28
journalctl -k -b 0  --no-pager | grep -E '18d1|Product: Android'          # solo 10:46:50
journalctl -k -b -1 --no-pager | grep -iE 'usb 3-3|1d6b:0104|ttyACM|cdc_acm'
find ~/proyectos -newermt "2026-09-29 11:12:30" -type f         # vacío
ls -la ~/proyectos/out/uke-console-k7.log                                  # no existe
cat ~/proyectos/out/captura-robusta.sh                                     # escribe uke-console-viva.log
cat ~/.zcode/cli/exec/sess_6983cd9f-.../call_e42b55a722b64a3a8684e63b-stdout.log
ps aux | grep -E 'ttyACM|captura-robusta'   ;  ls /dev/ttyACM*             # nada
```
