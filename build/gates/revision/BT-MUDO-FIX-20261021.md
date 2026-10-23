# BT: arreglo propuesto para el chip «mudo» en frío y prueba lista (21-oct-2026)

Encargo (vía sesión padre, deseo del dueño de trabajar en paralelo): con la tablet ocupada por la sesión de audio (M1), **solo en el PC y sin tocar la tablet**, proponer un arreglo concreto para que el chip del BT no quede mudo y dejar la prueba lista para cuando se libere y el dueño la autorice. No se ha abierto ninguna conexión a la tablet para esto.

## 0. Resumen

- **Qué falla**: en ~30 % de los arranques en frío el WCN6750 no contesta al **primer** comando vendor (`0xfc00`, leer versión) y el driver agota sus 4 intentos (`Retry BT power ON:0..2`). Es **todo o nada**: cuando contesta lo hace ~17 ms después del comando. El chip **sí se enciende** en todos los intentos (SW_CTRL sube, CTS baja a ≤ 0,15 s de BT_EN alto). No es WL_EN, ni rails, ni firmware, ni pines (descartados con medidas, `BT-MUDO-20261019.md` §3/§7 y `bt-20261019/README.md`).
- **Lo que ya mitiga** (desplegado el 19-oct): reintento por ciclos completos (`--down` + nuevo encendido, hasta 3) en `uke-bt-up.sh` y espera del escritorio hasta 70 s mientras `uke-bt` reintenta. En el bucle de 12 encendidos rescató un caso mudo; en arranques reales (ouke5) el primer ciclo siempre bastó (2 de 2), así que **aún no se ha visto actuar en frío**.
- **Qué se propone para atacar la causa** (preparado, sin desplegar): un **`hci_uart.ko` con los tiempos de encendido del WCN6750 ajustables en caliente** (defaults = serie) y una **medición controlada** de la tasa del primer intento con distintos retardos, con y sin carga de WiFi/CPU. Si la hipótesis de carrera es cierta, un `uke_bt_boot_ms` mayor (150–300 ms) debería subir el primer intento a ~100 % y dejar la mitigación por ciclos como red de seguridad; si no lo es, la medición lo **refuta** en ~10 min de prueba y se pasa a las cargas de fondo (WiFi/CPU).
- **Qué necesito del dueño**: tablet libre ~25 min, ACM+USB conectados (la prueba apaga/enciende el BT repetidamente: auriculares y lápiz se cortan) y su orden para `deploy.sh --go --service --hciqca` + `bt-medir.sh`.

## 1. Evidencia (con su fuente)

| Hecho | Dato | Fuente |
|---|---|---|
| Arranques con BT en el journal (ouke3–ouke5) | 17: **mudos 5 (29 %)**, 1.er intento OK 8 (47 %), recuperados por los reintentos del driver 4 | `BT-MUDO-20261019.md` §1 (journal de la tablet) |
| Episodios «dentro de un arranque» (≥ 40 s de uptime: `--down`/bucles/pruebas de otras sesiones) | 30 únicos: **1.er intento OK 22 (73 %)**, mudos 1 (3 %), éxito por intento 69 % | análisis offline de los `*dmesg*.log` del repo (esta sesión, 21-oct; posibles solapes entre logs, orden de magnitud sólido) |
| Bucle propio de 12 encendidos (en reposo) | 1.er intento OK 6/12 (50 %), 1 ciclo mudo de 13 (8 %), éxito por intento 55 % | `BT-MUDO-20261019-datos/bucle-12.txt` |
| Latencia de respuesta en intentos buenos | siempre ~117 ms desde el inicio del intento (≈ 50 ms BT_EN bajo + 50 ms espera + ~17 ms de respuesta) | `docs/historia/revision/BT-MUDO-20261019-datos/dmesg-intento.txt`, `dmesg-bt` del arranque |
| En los intentos fallidos | SW_CTRL=1 y CTS=0 (el chip «listo») pero 0 bytes recibidos (`tx:20 rx:0`) | muestreo a 0,15 s y `/proc/tty/driver/msm_serial`, 19-oct |
| Estado «apagado» de Android = el de Linux | BT_EN/SW_CTRL bajos, WL_EN alto, rails del BT sin votos, PA apagada | `bt-20261019/bt-apagado-20261020/` |
| **En arranque el encendido parece peor que en reposo** | 1.er intento OK 47 % (8/17, arranque) frente a 73 % (22/30, dentro de un arranque): **sugerente, no significativo** (Fisher exacto, dos colas, p = 0,11) | cálculo propio con los dos grupos anteriores |
| Último dato sin verificar | la sesión padre informa de otro mudo en el arranque v6 (`bluetooth.service` fallando); **no hay log en el repo** y no se ha leído la tablet | mensaje del 21-oct |

## 2. Qué dice el código (kernel 7.2.9-senemos, `drivers/bluetooth/hci_qca.c`, idéntico en ouke5 y ouke6) y Android

- `qca_regulator_init` (WCN6750, ~l. 1810): rails en bloque (ya encendidos por el WiFi: no hay evento real), **BT_EN a 0, 50 ms, a 1, 50 ms**, lee SW_CTRL (solo `bt_dev_dbg`) y sigue con `qca_set_speed(INIT_SPEED)` y `qca_port_reopen()`.
- `qca_port_reopen` (l. 1748): cierra y reabre el puerto «para sincronizar RTS/CTS» y termina con **`hci_uart_set_flow_control(hu, false)`**: **el primer comando sale con el control de flujo apagado**, es decir, sin esperar a que el chip declare RTS «listo». Un comando enviado antes de que la ROM del chip lea la UART **se pierde** y el driver no lo reenvía: espera el timeout (2,1 s) y repite **todo el encendido**.
- Android (`btpower.ko`): BT_EN bajo 52 ms, **WL_EN=1**, +56 ms BT_EN alto; SW_CTRL 0 → 1; después el HAL abre `ttyHS0` y habla (su retardo propio no es visible).
- Por tanto el margen entre «chip listo» y «primer comando» en Linux es **~50 ms + `set_speed` + reapertura de puerto**, y el fallo es indistinguible de «el comando llegó demasiado pronto». Es compatible con el patrón todo-o-nada y con que sea peor en pleno arranque (CPU/IO/WiFi cargados alteran los tiempos del host y del chip compartido), pero **no está demostrado**.

## 3. Hipótesis (por orden) y cómo se contrastan

| # | Hipótesis | Predicción | Prueba (lista) |
|---|---|---|---|
| H1 | Carrera: el primer comando sale antes de que el chip lea la UART (50 ms justos) | subir `uke_bt_boot_ms` (150, 300) sube el 1.er intento a ~100 %; el tiempo de subida de SW_CTRL de los intentos MALOS es mayor que el de los buenos | `bt-medir.sh -c "50:50:0 50:150:0 50:300:0 50:50:300" -n 20` |
| H2 | Contención en el arranque (WiFi/WPSS asociando, escaneos, CPU) retrasa al chip compartido o al host | el control (50:50:0) empeora con `-w`/`-l` respecto a reposo (73 %) hacia el 30–45 % de los arranques | `bt-medir.sh -c "50:50:0" -n 30 -w` y `-l` |
| H3 | Reapertura del puerto / pinctrl (los pines pasan de GPIO a UART al abrir) glitchea justo cuando el chip arranca | ninguna espera lo arregla; el fallo no depende de WiFi/CPU | si H1 y H2 se refutan: probar a no reabrir el puerto o a fijar el estado de pines antes (parche adicional) |
| H4 | Rail de PA (`pmr735a_s3`) ausente | **muy improbable** (el HCI precede al RF; 8 de 17 arranques funcionan sin ella) | no se prueba por ahora |

## 4. Arreglo propuesto, por capas

0. **Ya desplegado**: ciclos completos (`UKE_BT_CYCLES=3`) + espera del escritorio extendida. Con ~30 % de arranques que fallan el primer ciclo, tres ciclos (12 intentos) dejan la probabilidad de ROJO definitivo en décimas de %, a costa de +~20 s por ciclo fallido y de retrasar el escritorio hasta 70 s en esos casos.
1. **Preparado** (esta sesión): `hciqca/hci_qca-uke-tiempos.patch` → `out-hciqca/hci_uart.ko`: parámetros `uke_bt_low_ms` (50), `uke_bt_boot_ms` (50), `uke_bt_swctrl_ms` (0) en `/sys/module/hci_uart/parameters/` y `uke_bt_*` por `modprobe`. **Con los defaults el módulo se comporta como el de serie** (verificado: alias, dependencias y símbolos indefinidos idénticos al de serie; valores iniciales 50/50/0 leídos del ELF). Si `uke_bt_swctrl_ms > 0` sondea SW_CTRL tras subir BT_EN y registra a los cuántos µs subió (`uke: SW_CTRL=1 a los N us`): **mide el tiempo de arranque del chip en cada intento**, que es la observación que falta para H1.
2. **Si H1 se confirma**: fijar el valor mínimo que lleve el 1.er intento a ≥ 95 % (con margen) en `/etc/modprobe.d/uke-bt-hci.conf` (`options hci_uart uke_bt_boot_ms=<ms>`; +<ms> de arranque solo en el encendido del BT) y mantener los ciclos como red de seguridad. Validar con ≥ 8 arranques en frío (si el mudo fuese del 29 %, la probabilidad de ver 0 mudos en 8 por azar es ~6 %; con 10 consecutivos VERDE a la primera, ~3 %).
3. **Si H1 se refuta y H2 se confirma (recordar que «peor en arranque» hoy es solo p = 0,11)**: mover el encendido del BT a **después de que el WiFi se asiente** de verdad (esperar `wpa_state=COMPLETED` + N s de silencio de `ath11k`, no «8 s tras `uke-wifi`») o ponerle prioridad a la secuencia; coste: BT más tarde en el arranque.
4. **Si ninguna**: H3 (parche de reapertura) y, en último término, reintento más rápido (reenviar el primer comando a los 300 ms sin repetir todo el encendido; requiere parche mayor).

## 5. Prueba lista (para cuando se libere la tablet y el dueño la autorice)

Preparación (PC, ya hecha): `hciqca/build-hciqca.sh` → `out-hciqca/hci_uart.ko` (vermagic `…-ouke5`, que es también el release del kernel v6); `deploy.sh` con la parte nueva `--hciqca`; `bt-medir.sh` y `analiza-medicion.py`; `harness/test-hciqca.sh` (verde) y todo `build.sh` (`RESULTADO: OK`).

1. **Condiciones**: tablet libre (sin audio/cámara usándola), cargador, ACM con un solo lector y `ssh … dmesg -w` por USB (el WiFi y el BT comparten chip: la prueba puede tumbar el WiFi; **usar USB, no Tailscale**), avisar a las sesiones (el BT se corta ~25 min).
2. **Despliegue** (no carga nada): `build/rootfs/deploy/bt/deploy.sh --go --service --hciqca` (`--service` lleva el `uke-bt-up.sh` con `UKE_BT_HCI_OPTS`; `--hciqca` instala el `hci_uart.ko` parcheado en `updates/` y `bt-medir.sh` en `/usr/local/sbin/`). Comprobar `modinfo -n hci_uart` → `updates/`.
3. **Medición** en la tablet (como root, por USB): 
   - `bt-medir.sh -n 20` (4 configuraciones × 20 rondas en orden aleatorio ≈ 8–10 min): H1.
   - `bt-medir.sh -c "50:50:0" -n 30 -w -o /root/medir-wifi.log` y `… -l -o /root/medir-cpu.log` (≈ 4 min cada una): H2. 
   - Cada script restaura el BT con los valores por defecto al terminar o al abortar (Ctrl-C).
4. **Análisis** en el PC: `python3 -I hciqca/analiza-medicion.py <log>` (tasa del 1.er intento con IC de Wilson, p de Fisher frente al control, distribución de SW_CTRL por resultado).
5. **Decisión**: ver §4 (capa 2/3/4). Criterios: «MEJORA» = p < 0,05 y 1.er intento ≥ 90 % en ≥ 20 ciclos; para dar por bueno un valor, 0 mudos en ≥ 40 ciclos y luego ≥ 8 arranques en frío.
6. **Abortar si** hay faults del kernel (el script para solo) o `modprobe hci_uart` rechaza las opciones (el script lo dice y sale; significa que el módulo instalado no es el parcheado).
7. **Vuelta atrás**: `ssh root@192.168.42.129 'rm -f /usr/lib/modules/$(uname -r)/updates/hci_uart.ko /usr/local/sbin/bt-medir.sh /usr/local/sbin/bt-consumo.sh && depmod -a && /usr/local/sbin/uke-bt-up.sh --down && UKE_BT_CYCLES=3 /usr/local/sbin/uke-bt-up.sh --service'` (o `deploy.sh --go --revert`, que quita **todo** el BT). El `hci_uart.ko` de serie nunca se toca (queda en `kernel/`).

## 6. Riesgos y límites

- El `hci_uart.ko` de `updates/` sustituye al de serie para **todos** los usuarios del módulo, pero solo `uke-bt-up.sh` lo carga (autocarga bloqueada por la blacklist): sin la prueba en marcha, nadie lo usa. Con defaults = serie.
- La medición apaga y enciende el chip decenas de veces: ya se hizo 12 veces sin faults; cada ciclo es el mismo encendido que en el arranque. Si apareciese un fault (SMMU u otro), el script para.
- El análisis estadístico con n=20 por configuración detecta diferencias grandes (p. ej. 50 % → 95 %), no pequeñas; si el resultado es dudoso, ampliar `-n`.
- **No se ha comprobado en la tablet que `modprobe hci_uart uke_bt_boot_ms=…` funcione tal cual con la `uke-bt-up.sh` instalada**: la opción `UKE_BT_HCI_OPTS` es nueva (probada con mocks y harness: 103 + 49 + hciqca; el despliegue la lleva con `--service`).
- Dependencias sin cubrir: el mudo del arranque v6 que menciona la sesión padre no está en el repo; conviene leer su log (journal `-b` de ese arranque) antes de la prueba para confirmar que es el mismo patrón y no, p. ej., un problema de módulos/`modules.dep`.

## 7. Ficheros (todo en `build/rootfs/deploy/bt/`)

`hciqca/hci_qca-uke-tiempos.patch`, `hciqca/build-hciqca.sh`, `hciqca/bt-medir.sh`, `hciqca/analiza-medicion.py`, `out-hciqca/hci_uart.ko` (+ `hci_uart-control.ko`: mismas fuentes sin parche, para comprobar la reconstrucción), `harness/test-hciqca.sh`, `deploy.sh --hciqca`, `uke-bt-up.sh` con `UKE_BT_HCI_OPTS`, y los defaults de `build.sh`/`deploy.sh` ahora apuntan al árbol ouke5.

## 8. Actualización (21-oct 01:40, con la tablet «libre»; solo lectura por Tailscale): el log persistente cambia las prioridades

Leído `/var/log/uke-bt.log` completo (539 líneas; copia en `BT-MUDO-20261019-datos/uke-bt.log-20261021.txt`, sin direcciones BD). Cada arranque deja una línea de resultado, así que es la fuente más fiable (el journal ya no conserva los arranques viejos: `journald` a 150 M). Resultados por kernel y tipo (`uke-bt-up` a las 20-oct y antes):

| kernel | tipo | n | VERDE | 1.er intento OK | VERDE tras 1–2 reintentos del driver | MUDO (ROJO/AMARILLO) |
|---|---|---|---|---|---|---|
| ouke4 | arranque | 10 | 6 | 3 | 3 | **4** |
| ouke5 (incluye v6) | arranque | 9 | 9 | 4 | 5 | **0** |
| ouke4 | manual (bucles, pruebas) | 19 | 16 | 9 | 7 | 3 |
| ouke5 | manual | 1 | 1 | 1 | 0 | 0 |

- **Desde el 20-oct 06:53Z (ouke5, v5 y v6) los 9 arranques han sido VERDE**; el último a las 23:27Z (01:27 CEST) fue el reinicio del micrófono M1b con el kernel v6 (banner #6): VERDE a la primera, 0 timeouts. **El «mudo en v6» que indicó la sesión padre no aparece en este log**: el último ROJO es del 19-oct 08:16Z (ouke4) y lo único posterior es el `no encuentro el modulo uke_bt_b` del primer arranque ouke5 (módulos aún sin instalar, ya explicado). Lo más probable es que se leyera un arranque en curso (con `Retry BT power ON` en el dmesg) como mudo.
- Mudos por arranque, ouke4 4/10 frente a ouke5 0/9: **p = 0,087** (Fisher, dos colas): sugerente, no concluyente. El 1.er intento OK es parecido (3/10 frente a 4/9, p = 0,65): lo que mejora en ouke5 es que **cuando el 1.er intento falla, los reintentos del driver lo rescatan** (5/5 frente a 3/7, p = 0,081). Muestras pequeñas.
- La opción A (ciclos) solo ha actuado **una vez** en el log (el bucle del 19-oct, iteración 5); en arranques reales no ha hecho falta.
- **Consecuencias**: (1) la urgencia de la prueba de §5 baja; el arreglo en capas de §4 sigue siendo válido, pero la mitigación actual (ciclos) cubre lo observado; (2) si se hace la medición, lo que más información da es el **tiempo de arranque del chip (SW_CTRL)** en los intentos fallidos, y comparar **ouke4 frente a ouke5** (¿qué cambió en el arranque?: el parche 0045 de rails de cámara, `uke-audio-amps` y otros servicios nuevos, la restauración de userdata, el `journald` reducido…) antes de culpar a los 50 ms; (3) mientras no vuelva a verse un mudo en ouke5, **no desplegar nada nuevo** es una opción razonable: el parche queda preparado.

## 9. Actualización (21-oct ~14:20, sin tablet): la prueba de §5 ya se ejecuta de una vez

- **`ciclo-prueba.sh`** (PC, `build/rootfs/deploy/bt/`) encadena §5.2–§5.4 (`deploy` → `medir` → `carga`) con compuertas (host USB, un lector ACM, release == vermagic, batería, adaptador) y para ante la
  primera etapa que falle; añade la etapa `suspension` (veredicto VERDE/ROJO con auriculares) y `consumo` (D3). Probado con un `ssh` simulado: `harness/test-ciclo.sh`, 32 comprobaciones.
  Sin `--go` solo imprime el plan (cero `ssh`). Plan completo y decisiones: `BT-ESTADO-PARA-EL-DUENO-20261021.md` §5–§6.
- `deploy.sh --hciqca` instala ahora también `bt-consumo.sh` (además de `bt-medir.sh` y el `hci_uart.ko` parcheado); `--revert` quita los tres.
- Cambio de criterio respecto a §5.5: sigue valiendo, pero con 0 mudos en 9 arranques de ouke5 (§8) la medida es opcional, no urgente.

## 10. CORRECCIÓN (21-oct 20:40, primer despliegue real): `extra/` NO se busca; el parcheado va a `updates/`

Al ejecutar `deploy.sh --go --service --sleep --hciqca` en la tablet, el propio script remoto abortó con «depmod no prefiere el hci_uart parcheado»: `modinfo -k <krel> -n hci_uart` seguía apuntando a `kernel/drivers/bluetooth/hci_uart.ko`.
Causa (medida en la tablet con kmod 34.2): `/usr/lib/depmod.d/search.conf` = `search updates extramodules built-in`; **`extra/` no figura** (sí `updates/`, que ya usa el módulo `snd-q6apm` parcheado de la sesión de audio). La suposición «depmod prefiere `extra/`» de §4–§7 era errónea (nunca se había comprobado fuera del PC). Arreglo: `deploy.sh --hciqca` instala ahora `hci_uart.ko` en `updates/`, borra el residuo de `extra/` y exige que `modinfo -n hci_uart` resuelva a `updates/` (prueba nueva en `harness/test-deploy-sim.sh`); `--revert` retira ambos. Verificado tras el 2.º despliegue: `modinfo -n hci_uart` → `…/updates/hci_uart.ko` (sha256 `493ef41c951f…` == `out-hciqca/hci_uart.ko`), el de serie intacto (`6fb2c51a36e4…`) y **el `hci_uart` en memoria sigue siendo el de serie** (solo parámetro `irq_polarity`). Consecuencia a tener en cuenta: **desde ahora el siguiente encendido del BT (`uke-bt-up.sh`) carga el parcheado con sus valores por defecto (50/50/0 = serie)**; es su primera carga en hardware.
