# L50-PREP — El netconsole no estaba roto: la `remote_mac` estaba rancia (14-oct-2026, tarde)

> Subagente preparador del ciclo L50. **Solo lectura** en tablet (SSH: `ip`, `sysfs`, contadores;
> ni un `echo`, ni reboot, ni ACM) y árbol (`build/kernel-pokes/k52-L16-tree` NO tocado;
> diff de contingencia generado sobre copia en `/tmp` y verificado con `patch -p1 --dry-run`).
> Base leída: `docs/historia/revision/PIPELINE-PANEL-20261014/BRIEF.md`, `docs/historia/revision/PIPELINE-PANEL-20261014/L49-PREP.md`, NOTAS-OMARCHY.md (14-oct 17:xx), docs/historia/ESTADO-VIVO.md (14-oct
> 17:xx), ledger #622-bis/#623, y código del árbol vivo (rutas abajo).

## 1. Qué he leído (fichero:línea de lo relevante)

- `drivers/usb/gadget/function/u_ether.c:457` (`eth_start_xmit`, el `ndo_start_xmit` real de
  `usb0` en la tablet) → `:538-554` (llama a `dev->wrap`, `NULL` = frame multi-frame
  bufferizado, `goto multiframe`), `:591-600` (`drop`/`multiframe`: devuelve el `req` a la
  freelist, retorna `NETDEV_TX_OK`), `:716-722` (`eth_netdev_ops`: **sin `ndo_poll_controller`**,
  sin NAPI en todo el fichero).
- `drivers/usb/gadget/function/f_ncm.c:107` (`TX_TIMEOUT_NSECS 300000`), `:949-1004`
  (`package_for_tx`: cancela el timer, finaliza el NTB, limpia `skb_tx_data`), `:1006-1141`
  (`ncm_wrap_ntb`: **copia** con `skb_put_data` a un skb nuevo `:1113-1114`, arma el hrtimer
  `:1095-1096`, retorna `NULL` = "bufferizado, aún no enviar"), `:1147-1164`
  (`ncm_tx_timeout`: el flush es `ndo_start_xmit(NULL)` desde softirq), `:1782`
  (`supports_multi_frame = true`), `:1559` (timer en modo `HRTIMER_MODE_REL_SOFT`).
- `drivers/net/netconsole.c:1864-1896` (`netpoll_send_udp`), `:1800-1811` (`push_eth`:
  `h_dest = np->remote_mac` — **MAC estática configurada, sin ARP**), `:1878`
  (`LL_RESERVED_SPACE(np->dev)` sí se reserva — la reserva es correcta).
- `net/core/netpoll.c:50-75` (`netpoll_start_xmit`), `:165-190` (`netpoll_poll_dev`: sin NAPI
  ni `poll_controller` no hace nada — correcto, no es un error), `:224`
  (pool `alloc_skb(MAX_SKB_SIZE)`), `include/linux/netpoll.h:31-36` (`MAX_SKB_SIZE` =
  eth+ip+udp+1460 —0962c2 holgado para un poke).
- `drivers/net/usb/cdc_ncm.c:1523-1553` (`cdc_ncm_tx_fixup`), `:1361` (copia con `skb_put_data`
  a `skb_out` nuevo — **no toca el headroom del skb de entrada**).
- `drivers/soc/qcom/uke-panic-fb.c:238` (`char uke_lastpoke[44]` en `.bss` = **RAM normal**),
  `:260-275` (setters), `:499-504` (solo se pinta en cabecera del dumper).

## 2. Causa raíz: MAC de destino rancia, no el TX del netpoll (medido en ambos extremos)

Medido hoy (solo lectura):

- Tablet (SSH): netconsole `target1`: `remote_mac=02:00:5e:00:00:09`, `remote_ip=192.168.42.1`,
  `remote_port=6666`, `dev_name=usb0`, `enabled=1`. `usb0` UP con `192.168.42.129`,
  MAC propia `02:00:5e:00:00:0a`. **La tabla ARP de la tablet dice que el PC es
  `02:00:5e:00:00:01`**. Contadores: `tx_packets=202`, **`tx_dropped=0`, `tx_errors=0`**.
- PC: `enp0s20f0u3` MAC real **`02:00:5e:00:00:01`** (`192.168.42.1/24`, UP).

Cadena causal: `push_eth` pone `h_dest = 02:00:5e:00:00:09` (netconsole.c:1800) → el frame
egresa bien por el gadget (contadores limpios) → el PC lo marca OTHERHOST (dst ≠ su MAC) y lo
descarta antes del socket UDP → el receptor nunca lo ve. El UDP de usuario usa la MAC
fresca del ARP → llega. **Encaja al 100 % con lo observado** (setup OK, "tests en el stream"
= lado printk OK, cero UDP en el PC, cero drops en la tablet). Origen del ranciamiento: las
MAC del gadget/host son aleatorias por boot/enumeración (13-oct: "MAC aleatoria por boot
tumba el perfil NM"); la `remote_mac` se configuró con el valor de un boot anterior.

Corrección de etiqueta: en la tablet **NO corre `cdc_ncm`** (ese es el lado host = el PC).
El lado tablet es `f_ncm.c + u_ether.c` (device). La hipótesis del ledger ("TX del netpoll
sobre el `cdc_ncm`") apuntaba al lado equivocado del cable.

## 3. Hipótesis refutadas (dicho en voz alta, con código)

- **H-headroom** (`LL_RESERVED_SPACE` 16 < ~20 del NCM → drop): REFUTADA. Ningún wrap/fixup
  lee el headroom del skb de entrada: `ncm_wrap_ntb` copia a skb nuevo (f_ncm.c:1113-1114) y
  `cdc_ncm_fill_tx_frame` igual (cdc_ncm.c:1361). Además netconsole reserva
  `LL_RESERVED_SPACE(dev)` (netconsole.c:1878) y el pool es de ~1.5 KB (netpoll.h:32).
  Ningún parche a `netpoll.c` para reservar `needed_headroom` tiene objeto: **no proponerlo**.
- **H-URB/poll_controller**: REFUTADA como causa del silencio en estable. El lado gadget no
  tiene URBs (`usb_ep_queue`, u_ether.c:579; completions por IRQ del UDC) y el flush lo hace
  el hrtimer de 300 µs (f_ncm.c:1095) en softirq — funciona con el sistema vivo (prueba:
  `tx_dropped=0` + UDP de usuario llegando por el **mismo** camino
  `eth_start_xmit→wrap→timer→ep_queue`). La ausencia de `ndo_poll_controller`
  (u_ether.c:716-722) solo importa en el instante del wedge (ventana final <300 µs ≈ ~1 poke;
  asumible; §5 la contempla).
- **H-sysfs-`uke_lastpoke`**: NO VIABLE post-reset. Vive en `.bss` (uke-panic-fb.c:238) → el
  reboot lo pone a cero; y si viviera en la región reservada, el ABL la repinta con el splash.
  **No proponer sysfs**; el `LAST-POKE` solo sirve en foto pre-reset (ya circular por raíles
  apagados, ledger #623).
- **H-`/dev/mem`**: ya refutada en #623 (arm64 + `STRICT_DEVMEM`; `iomem=relaxed` no aplica).

## 4. Cambio propuesto

- **Vía principal (Gate A): NINGÚN cambio de kernel, 0 escrituras.** El fix es de configuración:
  reescribir `remote_mac` con la MAC vigente del PC **en el momento del test** + re-enable +
  test `/dev/kmsg` que debe LLEGAR (criterio §5). Si el Gate A pasa, L50 = 0 flashes y el
  modetest nombra el punto con la tabla de `docs/historia/revision/PIPELINE-PANEL-20261014/L49-PREP.md` §5.1 (sigue vigente).
- **Contingencia (Gate B, SOLO si el Gate A falla): `docs/historia/revision/PIPELINE-PANEL-20261014/l50-ncm-sync-flush.diff`** (adjunto,
  dry-run OK contra el árbol vivo). Añade a `f_ncm.c` el param
  `usb_f_ncm.ncm_sync_flush` (defecto 0) + flush síncrono en `ncm_wrap_ntb` tras anexar el
  datagrama (`package_for_tx` + `return skb2`, sin esperar al hrtimer). Elimina la carrera
  timer-vs-wedge: cada UDP del netconsole queda en `usb_ep_queue` (el dwc3 lo saca al cable
  aunque la CPU se clave justo después). Activación en runtime
  (`/sys/module/usb_f_ncm/parameters/ncm_sync_flush`, 0 flashes extra para activarlo).
  Coste: mata el batching NTB (más transfers USB; SSH sigue funcionando) — solo para el ciclo
  de captura. **No es el plan; es el plan B con su propio criterio.**

## 5. Criterio prefijado + runbook L50

Pre-vuelo (igual que #623: `getvar all`, mV, semáforo inter-proyecto, ACM lector único +
dumper v3 armados, vigía en pausa solo si hay flash, fila ledger pre-registrada).

**Gate A — canal (0 escrituras, dueño + SSH + PC):**

1. PC: `ip link show enp0s20f0u3` → anotar MAC vigente (`CE:...`). Receptor armado:
   `out/netconsole-recv.sh out/netconsole-l50.log` (fondo, con `date` de inicio).
2. SSH (sddm sigue `inactive`; no tocar): leer `tx_packets` de `usb0` ( basal ).
3. SSH: `echo <MAC-vigente> > /sys/kernel/config/netconsole/target1/remote_mac`
   + `echo 0/1 > .../enabled` (re-armar; ver `dmesg | tail`: "network logging started").
   (Escritura en configfs volátil = configuración del test, no flash; se pierde al reboot.)
4. SSH: `echo L50-PROBE-$(date +%s) > /dev/kmsg`; leer `tx_packets` (debe +1) y mirar el
   log del PC. **PASA-A = la línea L50-PROBE aparece en el PC en <5 s.**
   Repetir 3× (las MAC pueden churnar si el USB re-enumera; si la MAC del PC cambió entre
   el paso 1 y el 4, volver al 1).
5. Opcional en paralelo (0 coste, canales independientes): `ssh ... 'dmesg -w' > out/l50-dmesgw.log`
   (TCP; backup) + dumper v3 sigue a 2 s (tercer canal).

**Si PASA-A → el test (0 escrituras):** cámara a la pantalla (aunque negra: respaldo),
un solo `modetest -M msm-kms -s 36@85:0` por SSH → al cortarse, **última línea del
`netconsole-l50.log` = el punto** (tabla L49-PREP §5.1; granularidad esperada ~1 poke: solo
la ventana final <300 µs puede perderse). Reset físico; recoger dumper + `l50-dmesgw.log`
+ `ls /sys/fs/pstore`; fotografiar solo si hay algo (pantalla negra esperada). **L50 = fix
quirúrgico del punto (F1 link-clocks candidato nº1), no más instrumento.**

**Si FALLA-A (3 intentos con MAC vigente y nada llega) → Gate B (1 escritura):**
build L49 + `docs/historia/revision/PIPELINE-PANEL-20261014/l50-ncm-sync-flush.diff` → `boot_a` (dtbo s287 se queda; sddm off); gates:
literal `ncm_sync_flush` en `strings` + param en `/sys/module/usb_f_ncm/parameters/`;
runbook = Gate A + `echo 1 > .../ncm_sync_flush` antes del modetest. Rollback: L49
`ccfdea9d…` (estable) o L48 `0b1d22c4…`. Si B también falla, el canal netconsole se declara
inviable y se pasa al `dmesg -w` por SSH como primario (ya recogido en paralelo) — no un
tercer flash el mismo día.

## 6. Riesgos y refutaciones que aplican

- **Churn de MAC**: la `remote_mac` es válida solo mientras el USB no re-enumere; el runbook
  la re-mide en cada intento (pasos 1→4). Si el dueño re-conecta el cable, repetir el paso 1.
- **E6**: el Gate A no perturba nada (0 código). El diff B solo cambia batching USB, no
  clocks/GDSC/display — perturbación mínima y acotada al TX del gadget.
- **R-12** (`fastboot boot` usa el dtbo del slot): el Gate B flashea `boot_a` de verdad.
- **R-42/R-44**: reset físico + cargador de pared; un solo `modetest -s` por boot estable.
- Presupuesto §7: Gate A **0 escrituras**; Gate B 1 (+rollback = tope 2/día, con exención del
  dueño en fila como en #620-622). El modetest no escribe.

## 7. Presupuesto

- L50 nominal (Gate A + test): **0 escrituras**. Contingencia (Gate B): **1 escritura**
  (`boot_a`); rollback = 2ª solo si procede. Total ≤2 = tope diario.
- Qué NO hacer: parche de headroom en `netpoll.c` (refutado §3); sysfs de `uke_lastpoke`
  (inviable §3); `msleep` en el enable-path (perturbador, L49-PREP §1b); tocar
  sddm/DT/GDSC/VBIF/OPP; dos lectores ACM; compilar nada hasta FALLA-A.

## 8. Qué he verificado y qué no (honestidad)

Verificado (medición o fichero:línea): MAC del PC (`02:00:5e:00:00:01`), `remote_mac`
rancia (`72:75...`), ARP de la tablet coherente con el PC, `tx_dropped=0`/`tx_packets=202`,
`push_eth` usa la MAC estática (netconsole.c:1800), reserva correcta (:1878), copia sin
headroom en ambos wraps (f_ncm.c:1113, cdc_ncm.c:1361), timer 300 µs + flush por
`xmit(NULL)` (f_ncm.c:107/1095/1147), ausencia de `poll_controller`/NAPI en el gadget,
`uke_lastpoke` en `.bss` (:238), diff B con dry-run OK, árbol intacto (`git status` limpio
en `drivers/` y `net/`). **No verificado**: que tras corregir la MAC el UDP llegue (es
exactamente el Gate A — el experimento que falta); el mecanismo OTHERHOST-drop lo doy por
estándar del stack (si Gate A falla, el propio runbook lo falsará y activa el Gate B).
Hipótesis marcadas: granularidad ~1 poke en el wedge (ventana 300 µs).
