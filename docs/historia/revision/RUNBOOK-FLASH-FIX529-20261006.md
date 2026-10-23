# RUNBOOK FLASH-FIX529 — boot de validación #531 (6-oct-2026, revisor del flash)

Revisión línea a línea de `docs/historia/gates-palawan/flash-fix529.sh` + verificación en disco de todos
los artefactos (shas recalculados HOY por el revisor, sin tocar hardware; tablet en
Android slot b). Veredicto y incidencias al final (§G).

**Verificación de artefactos en disco (6-oct, por el revisor)**

| Artefacto | sha256 (recalculado hoy) | B | Rol |
|---|---|---|---|
| `build/bootimg/boot-uke-fix529.img` | `1f1f8703147d99467e4f7d1ee3e657af4512eb7f36c2e2d58bbbd3d8e89c33d6` | 100663296 | → boot_a (exacto a partición) |
| `build/bootimg/s268-boot-dtbo-validation.img` | `f2dede80e7452fd084420f841aae5f419e45d8d33a3ce0037e95e36df674c44b` | 609343 | → dtbo_a (≤ partición) |
| `/var/tmp/rootfs-uke-k521.img` (v8) | `bd2b30294aee99897ca7e86cb4843317cdf545ee08f1694aac1bc3ccf101899c` | 4294967296 | → userdata (solo FLASH_USERDATA=1) |
| `build/bootimg/boot-ukek49-esd-plyoff.img` (dorada) | `6988dc7b4f94383503e655fe41c8a7096591d1813690fa56e98b791c41aeea67` | 100663296 | rollback §E-2 |
| `build/bootimg/s266-boot-dtbo-esd.img` (dorada) | `15fdbbd3d265c393baac69c2e19884fe72417e6c304692db3fafacc8fdc7d695` | 608801 | rollback §E-2 (fijo en flash-k49.sh) |
| `/var/tmp/rootfs-v7-backup-20261006.img` (v7) | `5f9f00fe0704a5742bac9829b19a6107208c44e0b80c9eb47f3c487f1fdea169` | 4294967296 | rollback §E-2 |
| `build/android/flash-b/boot-stock.img` | `f5ea7d90c51695e46ee4b13e8ce7324f57805cb27743a934f578c9f032097a59` | | rollback §E-3 |
| `build/android/flash-b/init-boot-b-MAGISK.img` | `b3cfc9b787a9cb652553922c726f266bb812bd7e6c8fb1f436aa643dc89005a6` | | rollback §E-3 |
| `build/android/flash-b/dtbo-b-stock.img` | `27e61d21fd6a0858135e322eef9e8a223f6612ad24b1913fd7d9d680d602b3d8` | | rollback §E-3 |
| `build/android/flash-b/vendor-boot-stock.img` | `3ee6d4ac5fefc6ea9dbe9e6ed48b298762ad273f4592e3acc56e4439f096a208` | | rollback §E-3 |
| `…/WOZEUXM_16.0/images/recovery.img` | `babce84ee0388e735eff29220ea56b317c3b30272205e1fba9539d12b6079f09` | | rollback §E-3 |
| `…/WOZEUXM_16.0/images/userdata.img` (factory) | `85611e6164ab02820cf7bfee8db993662958f915d8fb16e40f93bdf902c446e6` | | rollback §E-3 |
| `…/WOZEUXM_16.0/images/metadata.img` | `3c48f3cd27d3ac844fd1480ff0711f12d6d9e13846b7207d4f5d93a282fb4216` | | rollback §E-3 |
| `…/WOZEUXM_16.0/images/misc.img` | `9f1dcbc35c350d6027f98be0f5c8b43b42ca52b7604459c0c42be3aa88913d47` | | rollback §E-3 |

## A. PRE (antes de poner la tablet en fastboot)

1. **Batería ≥ 3700 mV** (regla del dueño; el guard del ABL rechaza <~3450 con
   `battery-soc-ok:no`, #521/#526). Ideal ≥3900 o con cargador conectado para estabilidad.
2. **El dueño** pone la tablet en fastboot (vol− + USB o `adb reboot bootloader` ANTES de
   desconectar Android — una vez en fastboot **adb NO interviene en nada de este runbook**).
3. En el PC, comprobar `fastboot devices`: debe listar **`SERIE0001`** y ser el ÚNICO
   dispositivo fastboot. Si hay otro aparato en fastboot, desconectarlo (INCIDENCIA I-1:
   el script no fija serial).
4. Opcional (solo lectura, decisión del dueño): con la tablet AÚN en Android y root Magisk,
   capturar dd|sha256 de boot_a/dtbo_a como referencia extra. NO es requisito: el ABL no
   soporta `fastboot fetch` (#526), los shas de referencia viven en el ledger (boot_a=
   plyoff `6988dc7b…` flasheado 4-oct 17:22; dtbo_a=s266 `15fdbbd3…`), y el ledger #525–#530
   acredita que en toda la fase Android NADA escribió en slot a (todo fue a `_b` o
   super/userdata/metadata/misc; el doble set_active solo refrescó retry-containers).
5. Confirmar que los 3 shas del script siguen en disco (tabla superior): boot `1f1f8703…`,
   dtbo `f2dede80…`, rootfs v8 `bd2b3029…`. (Verificados por el revisor hoy; re-ejecutar
   `sha256sum` si algo cambió desde entonces.)

## B. Ejecución exacta (en el PC, como dueño; NUNCA un agente)

```sh
cd ~/proyectos/omarchy-uke
export FIX_BOOT="$PWD/build/bootimg/boot-uke-fix529.img"
export FIX_BOOT_SHA=1f1f8703147d99467e4f7d1ee3e657af4512eb7f36c2e2d58bbbd3d8e89c33d6

# B.1 DRY-RUN (cero escrituras — verificado: el camino dry no contiene flash/set_active/reboot)
docs/historia/gates-palawan/flash-fix529.sh --dry-run
```

Qué debe imprimir cada gate (en orden; script líneas 44–112):
- `shas pre-registrados`: FIX_BOOT_SHA == sha del ledger #530 (línea 47: si exportas otro
  boot, ABORTA), sha real de boot == FIX_BOOT_SHA y sha de s268 == `f2dede80…` (líneas 56–63);
  si `FLASH_USERDATA=1`, sha del rootfs == `bd2b3029…` (líneas 64–68).
- `tablet en fastboot` (línea 71).
- `boot_a: imagen 100663296 B / particion 100663296 B` (EXACTO, línea 85) y
  `dtbo_a: imagen 609343 B / particion 25165824 B` (≤, línea 86); con FLASH_USERDATA=1
  también `userdata: imagen 4294967296 B / particion …` (≤, línea 94).
- `bateria = XXXX mV` y **ABORTA si < 3700** (líneas 100–103; NO hay exención en este
  script — una exención sería decisión manual del dueño editando a mano, no del script).
- `slots ANTES:` (current-slot b esperado; slot a retry:3+, unbootable:no).
- `=== DRY-RUN: gates superados, NO se ha escrito nada ===` (líneas 108–112) y sale 0.

```sh
# B.2 FLASH REAL — primera vuelta con FLASH_USERDATA=1 SÍ o SÍ
#     (el userdata actual de la tablet es el factory-Android: sin esto Arch no tiene rootfs)
FLASH_USERDATA=1 docs/historia/gates-palawan/flash-fix529.sh
```

Tiempos esperados (todos exigen rc=0 + **OKAY**, script líneas 116–124):
- `boot_a` (100 MB): ~1–5 s. `dtbo_a`: <1 s.
- `userdata` (4 GiB): **30–40 s; manda el OKAY, no el reloj** (el v7 tardó 35 s; el
  timeout interno del script es 300 s — de sobra incluso en USB2). INCIDENCIA I-2: el
  script no avisa de esta duración; no tocar la tablet hasta ver `OK  userdata escrito`.
  Si expirara el timeout a mitad de escritura: userdata queda a medias → repetir el MISMO
  comando (la escritura es idempotente).
- `set_active a` (líneas 126–129) tras TODAS las escrituras; después imprime
  `slots DESPUES:` (current-slot **a**, slot a retry 7, unbootable:no).
- Arma el **lector2** antes de reiniciar (líneas 134–138; regla: nunca arrancar sin lector)
  y lanza `fastboot reboot` él mismo (línea 141) — el dueño no tiene que reiniciar nada.

El script NO verifica el contenido escrito post-flash (imposible: este ABL no soporta
fetch, #526). La única verdad es post-boot: checklist §D paso 9.

## C. Qué mirar en la PANTALLA durante el boot

- **0–15 s, texto ABL**: si aparece `battery-soc-ok:no` = guard del ABL (ni intenta
  entregar al kernel): poner cargador y repetir desde fastboot. No es fallo del flash.
- **5–40 s, logo Xiaomi/animación** = kernel arriba (handoff hecho). Muerte después del
  logo = userspace (ir a §E-1). Negro total sin texto = apagón seco (cargar, §E-1).
- **~40 s: UKE-DIAG** en la consola del lector2 (`/var/tmp/uke-console2.log`; también
  UKE-FIX en kmsg). Después la red USB gadget sube sola (192.168.42.0/24 horneada en la
  imagen, `10-uke-usb.network`).
- **SSH**: `ssh root@192.168.42.129` (desde el PC, por el enlace USB).

## D. Checklist post-boot (EN ORDEN; #531)

1. `ssh root@192.168.42.129` — entra sin interacción (clave horneada).
2. **Hub GPU 200 MHz**: `grep -E 'hub|gpll0' /sys/kernel/debug/clk/clk_summary` →
   `gpu_cc_hub_clk_src` (y hub_cx_int/hub_aon) = **200000000**. (No hay token cmdline:
   el hub se valida leyendo el clk, BOOT-PKG §3.)
3. **Táctil**: `dmesg | grep -i novatek` (probeo OK) + `grep -w 54 /proc/interrupts`
   (línea msmgpio-54, novatek) + `evtest` con eventos reales en 2136×3200 (esquinas
   opuestas; si no reporta con EDGE_FALLING, el cambio a EDGE_RISING es un s269 de 1 línea).
4. **Batería/ADSP**: `cat /sys/class/power_supply/battery/{voltage_now,status,...}`
   poblado (ADSP arriba + PDR charger_pd); `dmesg` SIN «PDM: no support for the platform»
   y CON «PDR … msm/adsp/charger_pd». `voltage_now ≥ 3900` o `Charging`.
5. **WiFi**: `ip link` → `wlan0` presente; dmesg con «Booting fw image qca6750/wpss.mdt».
6. **BT**: `bluetoothctl list` → controlador hci0.
7. **adc5 SIN probe** — ESPERADO, no es fallo (pendiente kernel-side: whitelist del
   populate `vadc@9000` + canales vendor 0x710/0x717/0x7a1; BOOT-PKG §1e).
8. `echo v8 > /etc/uke-rootfs-version` (deuda guardrail 3: la imagen no lo lleva de fábrica).
9. **Captura para el ledger** (única verdad): `dd if=/dev/block/bootdevice/by-name/boot_a | sha256sum`
   → `1f1f8703…`; `dtbo_a` → `f2dede80…`. Cualquier desviación = el ABL escribió donde no
   debía: parar y documentar.
10. Asentar #531 en FLASH-LEDGER (resultado por punto, 2–9).

## E. ÁRBOL DE ROLLBACK

**E-1. Boot muerto (< 7 intentos; el ABL quema retry y devuelve a fastboot).**
El dueño pone la tablet en fastboot (como siempre), cargar si la batería < 3700,
`--dry-run` y retry ×1 con el mismo comando B.2. (Plan-recuperación FASE 3.18.)

**E-2. Dorada de vuelta** (validación fallida; slot a ya es current — solo cambia el par):
```sh
cd ~/proyectos/omarchy-uke
export K49_BOOT="$PWD/build/bootimg/boot-ukek49-esd-plyoff.img"        # 6988dc7b… (VERIFICADO en disco)
export K49_BOOT_SHA=6988dc7b4f94383503e655fe41c8a7096591d1813690fa56e98b791c41aeea67
docs/historia/gates-palawan/flash-k49.sh --dry-run          # dtbo_a=s266 15fdbbd3… va FIJO dentro (línea 19/21)
docs/historia/gates-palawan/flash-k49.sh                    # boot_a + dtbo_a + lector2 + reboot
# userdata v7 (el kernel k49 NO traga los módulos fix529 de la v8):
fastboot flash userdata /var/tmp/rootfs-v7-backup-20261006.img   # 5f9f00fe… (~35 s, esperar OKAY)
```
OJO (INCIDENCIA I-4): **sin `K49_BOOT` exportado, flash-k49.sh flashea `boot-ukek49-esd.img`
(`d4b96f95…`), el kernel SIN plyoff — NO es la dorada**. docs/historia/revision/BOOT-PKG-20261006.md §6 llama a la
dorada «k49-esd-plyoff `d4b96f95…`»: el nombre es plyoff pero el sha que imprime es el del
esd; el sha correcto de la plyoff es `6988dc7b…` (ledger :9377/:9686, PLAN-recuperación,
verificado en disco). vendor_boot_a/init_boot_a están STOCK y NO se tocan (PLAN: ciclo
aparte con sus backups de `build/backup-par-bueno/` solo si hiciera falta).

**E-3. Volver a Android** (renuncia temporal a Arch). AVISA: flashear el userdata factory
**sacrifica la v8 de Arch** — para volver a Arch haría falta re-flash de la v8
(`FLASH_USERDATA=1`, §B.2). El slot b está INTACTO (Android corre ahora mismo desde él;
ledger #526-SNAPSHOT/#527), así que la vía mínima es solo userdata + set_active:
```sh
# MÍNIMO (slot b íntegro — es el estado actual):
fastboot flash userdata /var/tmp/rom/uke_eea_global_images_OS3.0.303.0.WOZEUXM_16.0/images/userdata.img  # 85611e61… (~1 min, sparse)
fastboot set_active b && fastboot reboot
# COMPLETO (solo si se duda de la integridad del slot b; shas verificados hoy):
#   boot_b     ← build/android/flash-b/boot-stock.img           (f5ea7d90…)
#   init_boot_b← build/android/flash-b/init-boot-b-MAGISK.img   (b3cfc9b7…)
#   dtbo_b     ← build/android/flash-b/dtbo-b-stock.img         (27e61d21…)
#   vendor_boot_b ← build/android/flash-b/vendor-boot-stock.img (3ee6d4ac…)
#   recovery_b ← …/WOZEUXM_16.0/images/recovery.img            (babce84e…)
#   vbmeta_b / vbmeta_system_b ← flash-b/vbmeta-b-dump.img (0f7399d9…) / vbmeta-system-b-dump.img (b4c81eaa…) SOLO si se tocaron
#   metadata ← …/images/metadata.img (3c48f3cd…) · misc ← …/images/misc.img (9f1dcbc3…)
#   super: NO tocar (Android ya monta desde el actual; si hiciera falta:
#          /var/tmp/super-b-final.img 11f05e2d… reconstruido y verificado, #527)
```

**Última línea** (PLAN-recuperación FASE 3.21): stock íntegro de `build/backup-par-bueno/`
+ EDL dump `gpu-work/uke-rom-edl/`. BCB raro: `build/gates/bcb-clean-8192.py` como ciclo aparte.

## F. GO / NO-GO

**GO si y solo si TODAS:**
1. Shas de los 3 artefactos verificados en disco hoy (tabla §top): boot `1f1f8703…` ✓,
   dtbo s268 `f2dede80…` ✓ (NO el s266), rootfs v8 `bd2b3029…` ✓ — **VERIFICADO por el
   revisor 6-oct**.
2. `--dry-run` verde: los 5 gates imprimen OK y el mensaje `NO se ha escrito nada`.
3. Batería ≥ 3700 mV en fastboot (el script la mide y ABORTA si no; sin exención posible).
4. `fastboot devices` muestra SOLO `SERIE0001` (I-1: el script no fija serial).
5. `FLASH_USERDATA=1` en la primera vuelta (el userdata actual es factory-Android, #530).
6. Lo lanza el dueño, presente durante todo el flash (lector2 + observación de pantalla).

**NO-GO si CUALQUIERA falla**: batería < 3700 (esperar a cargar; el guard ABL rechazaría
igualmente <~3450); cualquier sha desviado; dry-run rojo; otro aparato en fastboot o
`SERIE0001` ausente; dueño ausente. En NO-GO la tablet se queda como está (en fastboot no
drena más de lo normal; opcional: volver a Android con §E-3-mínimo mientras tanto).

## G. VEREDICTO E INCIDENCIAS DEL SCRIPT

**VEREDICTO: GO** (condicionado a F). El script es fiel al calco flash-k49.sh, el camino
`--dry-run` está limpio de escrituras (solo flash/set_active/reboot existen, en las líneas
116/127/141, todas tras el exit del dry en 108–112), los shas se verifican ANTES de
cualquier contacto con fastboot, el guard de batería BLOQUEA (die, línea 103) sin exención,
el orden boot→dtbo→userdata→set_active a→lector2→reboot es correcto, y no escribe ninguna
partición prohibida (boot_b/vbmeta/super/misc/metadata jamás aparecen). `bash -n` OK.
Sin defecto bloqueante. Incidencias (documentadas, NO corregidas — decisión del dueño):

- **I-1 (MEDIA)** — Sin `-s SERIE0001`: todas las llamadas fastboot (líneas 71, 76, 78, 89,
  100, 106, 116, 127, 132, 141) van sin serial. Con >1 aparato en fastboot falla cerrado
  (getvar falla → die en línea 82, antes de escribir), pero el gate de la línea 71 daría OK
  con cualquier OTRO móvil en fastboot como único dispositivo. **Fix propuesto**: envolver
  en `FB="fastboot -s SERIE0001"` (con timeout) y exigir `SERIE0001` en la salida de
  `fastboot devices`.
- **I-2 (BAJA)** — El script no avisa de la duración del flash de userdata (~30–40 s;
  el dato vive en PLAN/ledger). **Fix**: `say "userdata: ~30-40 s, esperar OKAY (timeout 300 s)"`
  antes de la línea 124.
- **I-3 (BAJA)** — `FLASH_USERDATA` solo acepta el literal `1` (líneas 34/50); `true`/`yes`
  lo silencian. Fail-safe y avisado (línea 54), pero puede confundir. **Fix**: rechazar
  valores distintos de 0/1 en el parse de entorno.
- **I-4 (DOC, fuera del script)** — docs/historia/revision/BOOT-PKG-20261006.md §6 (líneas 175–176) llama a la
  dorada «k49-esd-plyoff `d4b96f95…`»: ese sha es de `boot-ukek49-esd.img` (SIN plyoff);
  la plyoff real es `6988dc7b…`. Seguir ese texto a la letra flashea el kernel equivocado
  en el rollback. **Fix**: corregir el doc; en la práctica usar §E-2 de este runbook.
- **I-5 (COSMÉTICA, lector2)** — `uke-consola-lector2.sh` línea 41 tiene un `pgrep` garbled
  (`'cat <pgrep -c -f 'cat -f' 2>/dev/null3'`): parsea OK (bash -n verde) y solo afecta al
  display de `--status`; el armado del lector (lo que llama el flash, líneas 135–138) no se
  ve afectado. **Fix**: restaurar `pgrep -c -f 'cat /dev/ttyACM'`.
- **Nota (sin incidencia)** — `timeout 300` del flash vale para los 4 GiB del v8 incluso en
  USB2 (~2 min); timeout de escritura a mitad → repetir el mismo flash (idempotente).
