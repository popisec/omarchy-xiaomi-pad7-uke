# CRÍTICA HIPÓTESIS 20261011 — el bisect del wedge de arranque, una por una

Crítica post-#601. Solo-PC, solo-lectura de la tablet. Todo lo afirmado aquí está verificado
contra fichero (logs, fuentes, imágenes); lo que no, va marcado **ABIERTO**.

## 0. Tres hechos nuevos que reordenan todo el tablero (verificados hoy en el PC)

1. **El init que corre NO es `ukeinit-arch`**: el cmdline del L19 realmente flasheado
   (`boot-uke-k52L19.img`, sha `71d89ca6…` = el del ledger) dice **`rdinit=/ukeinit`**, y el
   initramfs embebido en el Image (gzip miembro @35467896 del kernel crudo, extraído y
   desempaquetado) contiene **`/ukeinit` = s118-cons** (init s172): **no corre e2fsck NUNCA**;
   monta `ro,noload` → verifica `/sbin/init` → `remount,rw` → `switch_root`. El fichero
   `build/init/ukeinit-arch` (con e2fsck -f -p, die(), watchdog de 12 s, volcador a sda30)
   **no está en el cpio** y su token cmdline (`rdinit=/ukeinit-arch`) no está en el boot.img.
   Toda la hipótesis H4 y parte del razonamiento del #601 parten de un init que no existe
   en la imagen.
2. **Por qué la consola no muestra nada del init en ningún boot** (misterio del enunciado):
   el s118 escribe sus migas por `/dev/kmsg` SIN prefijo de nivel → LOG_INFO(6), y la cmdline
   lleva **`loglevel=4`** → la consola ACM (ttyGS0, que SÍ está en la cmdline) solo imprime
   nivel <4 (err y peores). Los `say()` de ukeinit-arch a `$TTY=/dev/tty0` tampoco saldrían
   por el ACM (tty0 es el fbcon del panel). **Un die() de ukeinit-arch sería invisible por
   diseño**; y el silencio del s118 no indica nada.
3. **La tarde falló también con el par bueno, con firma idéntica**: el par estable
   reflasheado (L19+s275-r2, 17:36) murió a **47,04 s** con la misma secuencia final que s276
   (give-up novatek nº7 a 47,01 → `cannot find modalias …goodix-berlin@0` → ola W:
   qupv3_1/gpio_key/arm-scmi → `arm-scmi … protocol:0x10 failed` → silencio). Y TODOS los
   boots de la tarde que alcanzaron systemd sufrieron **`systemd[1]: Caught <ABRT> …
   Freezing execution`** (nowifi 6,65; nowdt2 6,66; s276 6,69; par-estable 6,60; f1 16,65).
   El boot bueno de la mañana (03:52): **cero ABRT**, storm de 6 ciclos que termina en 40,87,
   sin goodix ni ola 3, vivo ≥3773 s. **Mismo boot.img byte-idéntico, distinto
   comportamiento: hay una variable de ESTADO (rootfs/hardware), no de DTBO.**
   Dato de contexto del fs: los errores `ext4_mb_generate_buddy` al montar aparecen en TODOS
   los boots (también el bueno, 6,87 s) y el journald del bueno repite `inode #73734 …
   deleted inode referenced: 73765` cada ~26 s hasta los 3773 s: el rootfs arrastra
   corrupción estable y NADIE la repara al arrancar (no hay fsck en el init que corre).

---

## 1. Las 5 hipótesis, una por una

| # | Hipótesis | A FAVOR | EN CONTRA | CONFOUNDERS | Experimento mínimo |
|---|---|---|---|---|---|
| **H1** | Los frags WiFi (1701/1702/1704-1707) wedgean el boot a ~4,2 s | En los 3 boots que murieron a 4,1-4,2 s (L21+nostrip, L21E1b+nostrip, L19+nostrip) los frags wifi estaban; nowifi (sin wifi) no wedgeó a 4 s. Con L19+s277 (wifi DT presente) tampoco hubo wedge temprano —coherente con que el driver es módulo y no carga—, lo que YA debilita el mecanismo DT | **El log «nowdt» contradice el ledger**: `acm-nowdt2.log` (wifi+rail, SIN wdt) NO muere a 4,2 s: llega a 47,24 s con firma completa y ABRT de systemd a 6,66 s. Si ese log es el nowdt real, la exclusión «wifi sí, wdt no» se cae; si es el nowifi mal etiquetado, el bisect no tiene trazabilidad de nombres (ningún /tmp log documenta el wedge de 4,2 s del nowdt). Además el wedge de 4,1 s solo ocurrió en boots con `console=tty0 + fbcon=map:0` (k64) + DSI vivo (nostrip arregla el DSI) → el fbcon-takeover del panel (#595) es un competidor no excluido | 3 variables juntas en los boots de 4,1 s (wifi+wail1896+fbcon tty0); el label nowdt/nowifi dudoso; el «estado tarde» (H6) contamina todo | Sobre base limpia y cargada: flash **s278-nostrip-nowifi + cmdline E1b (sin tty0)** con sha pre-registrado. Si sobrevive >300 s → el wedge de 4 s era fbcon/panel, no los frags. Si wedgea → repetir con nowdt. Un flash, variable única |
| **H2** | El frag 1460 (kpss-wdt) arma el WDT y muerde a ~40 s | La muerte nowifi a 46,2 s con desconexión+re-enum USB encaja «a ojo» con un bite+reboot | **Refutada por el fuente y por los tiempos.** `qcom-wdt.c`: el probe **NO arma** el timer (solo re-arma si `WDT_EN` ya estaba a 1 —nadie lo dejó así—); default `timeout=30 s`. Nadie alimenta el WDT en estos boots (systemd muere a 6,6 s; el s118 no arma nada). Si se armara en el probe (~1,5 s), el bite sería ~31,5 s, no 40-46. No hay UNA línea de WDT (ni `watchdog`, ni bark, ni pretimeout) en ningún log. Y hay muertes a 46-47 s **sin el frag 1460** (s276, par estable). El «device no nace» de #596/#598 sigue sin explicarse, pero ya no hace falta: el driver no puede morder solo | La re-enum USB de 16:14:59→:81 prueba un RESET, no un bite de WDT (cualquier wedge+rescate externo o bite de otro WDT lo da). El bucle E1b (~4,2 s/ciclo) es temporalmente INCOMPATIBLE con un bite de 30 s | Ya ejecutado de facto: s276 y par-estable (sin frag 1460) mueren igual a 47 s → WDT exonerado. No gastar más flashes aquí; si algún día se quiere sellar: s279-wdtonly (F3a de CRITICA-PANTALLA) sobre base sana |
| **H3** | El rail L8 a 1896 temprano mata a ~46-47 s (TDDI despierta) | Era el mejor parseo del #601 (dos boots rail-1896 mueren a 46-47; el rail-1304 vivía) y el mecanismo (apply_uV ~0,5 s, TDDI viva) es plausible | **Refutada como discriminante hoy**: el par estable (rail **1304**, sin wdt, sin wifi) murió a 47,04 s con la MISMA firma. El rail ya no separa nada en la tarde. Además el driver no llama a set_voltage y con min≠max el registro no aplica nada —el «apply_uV a 0,5 s» requiere revisar el merged real (ABIERTO)—. Puede seguir siendo agravante del estado del TDDI (H5), no causa del fenómeno de 47 s | El «todos los rail-1896 mueren 46-47» era un sesgo de selección: TODOS los boots de la tarde morían a 46-47, rail incluido o no | Cae gratis con el experimento de H6 (par estable sano = rail 1304). Si la base sana bota sin rail y el s276 (rail) muere, H3 renace con un control real |
| **H4** | La corrupción ext4 cuelga el boot a ~47 s porque e2fsck -f -p corre (o cuelga) antes de montar | El fs ESTÁ sucio y empeorando: buddy errors al montar en todos los boots, journald con deleted-inode recurrente en el bueno, 9 wedges sin unmount limpio | **Mecanismo refutado tal cual**: el init que corre es el s118 y **no hay e2fsck** (hecho 0.1); el mount ocurre a ~6,9 s en todos los boots, no hay crawl de fsck; y la muerte de 47 s es un wedge del KERNEL en la ola diferida (la última línea es arm-scmi, pid1 lleva muerto 40 s), no un silencio de fsck. PERO el **tema** H4 (estado del rootfs como variable de la tarde) es de lo más sólido: el ABRT determinista de systemd a 6,6 s SOLO en la tarde apunta a daño persistente del rootfs (¿unidades/estado/coredumps escritos por las sesiones de la mañana 03:52-04:50?) | El ABRT podría ser ambiental (batería/memoria) en vez de fs; el fs ya estaba sucio en la mañana y systemd vivía —el delta de la tarde es el ABRT, no la suciedad base | 0 flashes: desde el recovery Android (slot B intacto) o por SSH si la base sana bota: leer `/var/lib/systemd/coredump` (¿pid1 core?), `df` (¿/var lleno?), y diff del estado systemd vs la mañana. Si el ABRT persiste con base sana → rootfs; se repara montando el userdata por PC/recovery y limpiando |
| **H5** | El enable del panel wedgea por el boot del TDDI (ESD 86/87 en el reset, muerte ≤100 ms post-w4) | Captura #595 sólida y verificada hoy: ESD 86/87 con val=0 DENTRO de w2 (3773,167), w4-done 3773,174, muerte ≤100 ms, apr flood sigue 53 ms (otras CPUs vivas), pureason=0x800011 | No está refutada por la tarde: es un fenómeno de ENABLE/re-enable del panel, no de boot. Lo que sí debe separarse: los wedges de 4,1 s de la tarde podrían ser ESTE mismo mecanismo vía fbcon-takeover (k64 tiene `console=tty0 fbcon=map:0` y nostrip deja el DSI vivo → el primer modeset del boot ES un enable de panel), no un efecto de los frags wifi | El estado eléctrico del TDDI (rail 1896 lo despierta desde t=0,5 s; batería/calor) cambia entre boots; #591 mostró wedge del enable con rail 1896 —no limpia el rail de la ecuación | El F1 de CRITICA-PANTALLA: par estable + modetest con captura armada (trigger limpio). Solo tiene sentido sobre base sana |

---

## 2. H6 — la hipótesis que faltaba: «el turno de la tarde es un problema de ESTADO, no de DTBO»

**Enunciado**: entre 04:50 y 15:47 la tablet cambió de estado (rootfs degradado por las
sesiones/wedges de la madrugada + estado eléctrico del TDDI/PMIC tras ~11 h sin USB y 9
resets sucios), y ESE estado produce los dos fenómenos nuevos de la tarde: (a) ABRT
determinista de systemd a 6,6 s (explica «sin SSH» en TODOS los boots, incluido el par
bueno) y (b) el wedge de ~47 s en la ola diferida (explica «consola muerta a 47 s» en TODOS
los dtbos). Los frags wifi/wdt/rail son ruido de bisect sobre un sustrato que ya no es el de
la mañana.

**Evidencia**: mismo boot.img (sha verificado) vivo ≥3773 s de madrugada y muerto a 47 s de
tarde; ABRT 5/5 boots de la tarde con systemd vs 0/1 de la mañana; firma terminal idéntica
(give-up nº7 del novatek + goodix modalias + ola W:3 + arm-scmi) en 5 boots con 4 dtbos
distintos; el arm-scmi falla IGUAL en el bueno (0,39/4,08/4,18 s) sin morir → el fallo scmi
es huésped, no asesino; las 46-47 s coinciden con el FIN del storm (6,14 s × 7) en todos.

**En contra**: no explica por sí sola el wedge de 4,1 s de los nostrip (ahi el fbcon/panel
es mejor candidato); no hay medida de batería/temperatura (ABIERTO).

**Experimento mínimo (el más barato de todos, 1 flash ya conocido)**: batería al 100 % (o
con carga externa) + power-cycle largo → flash del par estable EXACTO (L19 `71d89ca6…` +
s275-r2 `67a65bc1…`) + `set_active a` + ACM lector continuo. Ver SOLO dos cosas: ¿ABRT a
6,6 s? ¿muerte a 47 s? Si ninguna aparece → H6 confirmada y la tarde entera era
contaminación; si aparecen → hardware crónico y el bisect de la tarde era válido.

---

## 3. Ranking final (cuánto explica cada una con menos)

1. **H6 (estado de la tarde)** — única que explica TODOS los fallos de la tarde (4,1*, 46,
   47 y «sin SSH» del par bueno) sin añadir mecanismos nuevos. *Los 4,1 s los comparte con
   fbcon/panel.
2. **H5 (panel/TDDI en el enable)** — el fenómeno #595 está medido y cerrado; probablemente
   sea también el wedge de 4,1 s vía fbcon-takeover. Sigue viva y es la que abre el camino
   de la pantalla.
3. **H4-tema (rootfs sucio → ABRT de systemd)** — mecanismo e2fsck refutado (no corre),
   pero es la cara de software de H6 y explica el «sin SSH» universal de la tarde.
4. **H3 (rail 1896)** — refutada como discriminante hoy; degradada a posible agravante del
   estado del TDDI.
5. **H1 (frags WiFi → wedge 4 s)** — sin soporte trazable (el log nowdt la contradice, el
   driver wifi ni siquiera carga con L19); rehacer solo sobre base sana.
6. **H2 (watchdog bite 40 s)** — refutada por el fuente (no auto-arma, 30 s default) y por
   las muertes a 46-47 s sin frag wdt. Descartar.

**Orden de ataque**: E0 de H6 (cargar + par estable + mirar ABRT/47 s) → si sano, E3 (E1b +
nostrip, sella fbcon vs wifi) → luego F1/modetest de la crítica para la pantalla. Nada de
flashear frags wifi/wdt hasta tener base limpia dos veces seguidas.
