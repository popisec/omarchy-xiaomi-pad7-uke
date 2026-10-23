# CRÍTICA KIT E1 (pre-flash) — 11-oct-2026

Revisión del kit del protocolo E0→disparador-0-flash→E1 (`gates/revision/PLAN-PANEL-WEDGE-20261011.md`,
repack-k52L19E1.py, uke-wedge-sampler.sh, uke-ufs-witness.sh, out/acm-loop.sh) ANTES de usarlo.
Solo-PC; nada flasheado; repack NO re-ejecutado. Verificación de artefacto hecha por sha/bytes (lectura).

## VEREDICTO EN UNA LÍNEA

**NO-GO tal cual.** Dos defectos de diseño, no de ejecución: (a) el kernel E1 **SÍ enciende el
panel en el arranque** (fbcon toma fb0 aunque no haya `console=tty0`; el presupuesto del
experimento está roto) y (c) `echo on > status` **no hace commit** (no es un disparador).
Ambos tienen arreglo cmdline-only. El resto del kit (repack gates, witness, sampler tras mis
fixes) está correcto.

---

## (a) E1 cmdline con `fbcon=map:0` — **FALLO CRÍTICO: el panel se enciende en el arranque igual**

La hipótesis «quitar console=tty0 ⇒ fbcon no puede tomar el panel» es **falsa en este kernel**.
La toma de control de fbcon en 7.2-rc2 NO depende de que haya consola printk en el VT:

1. `k52L19-build/.config:5258` → `# CONFIG_FRAMEBUFFER_CONSOLE_DEFERRED_TAKEOVER is not set`
   (config idéntica en k52L17; VERIFICADO diff). Con eso, `fbcon.c:160` compila
   `#define deferred_takeover false` y **todo el mecanismo de toma diferida vía dummycon
   (fbcon.c:3326-3340, dummycon.c:32-67) está compilado fuera**. `fbcon_start()` no hace nada.
2. Sin token `fbcon=`, `con2fb_map_boot` queda **a ceros** (BSS: `fbcon.c:118-119`,
   `static signed char con2fb_map_boot[MAX_NR_CONSOLES];` — nunca se inicializa a −1; el init
   de `fb_console_init` solo limpia `con2fb_map`).
3. `register_framebuffer` → `fbcon_fb_registered` (fbmem.c:535) → `do_fb_registered`
   (fbcon.c:2956): con `deferred_takeover == false` cae al bloque de siempre
   (fbcon.c:2969-2982): `con2fb_map_boot[0]==0 == idx(fb0)` → `ret = do_fbcon_takeover(1)`.
   **Es decir: fbcon toma fb0 en el primer registro del framebuffer, sin console=tty0 y sin
   fbcon=map:0.** Con `fbcon=map:0` presente (cmdline E1, 553 B verificada en el artefacto)
   el match es explícito y pasa igual.
4. `do_fbcon_takeover` (fbcon.c:607-620) → `do_take_over_console(&fb_con, …)` → bind →
   `fbcon_init` (fbcon.c:1088), que hace el modeset por diseño: fbcon.c:1186-1199 —
   *"We must always set the mode… We need to do it in fbcon_init() to prevent screen
   corruption"* → `info->fbops->fb_set_par(info)` = `drm_fb_helper_set_par` → commit atómico →
   enable del encoder/DSI → **encendido en frío del panel o82 en el kernel = el wedge**.
   El propio `drm_fb_helper.c` lo documenta ("__drm_fb_helper_initial_config_and_unlock",
   líneas 1617-1653, registra el fb; el commit lo dispara el bind de fbcon).

Consecuencia: **el artefacto #594 (ca8cd4bd…) NO es «estable por diseño»**: en el arranque E1
repetiría el enable de #505/#590/#591 ANTES del SSH y sin testigos armados = otra muerte ciega.
(L19 vigente se salva únicamente porque `video=DSI-1:d` fuerza el conector OFF y el fbdev
nunca encuentra display con el que registrar fb.)

**Arreglo (cmdline-only, mantiene el kernel byte-pinneado 5582dcc2…):**
`fbcon=map:1` en vez de `fbcon=map:0`. Con `map:1`, el parser (`fbcon.c:506-519`) pone
`con2fb_map_boot[*]=1` para TODOS los VCs; como solo existe fb0 (idx 0), el match de
`do_fb_registered` falla y `info_idx` queda −1 → **sin takeover en boot**. No hay otra vía
automática: `fbcon_select_primary` exige `video_is_primary_device` (=0 en arm64 para devices
de plataforma), el notifier de dummycon no existe (DEFERRED off) y el único otro caller
(`fb_switch_outputs`→`fbcon_remap_all`, fbmem.c:693) es de vga-switcheroo (PCI). El enable
posterior queda en manos del disparador manual (modetest; ver (c)). «map:1» es del mismo
tamaño que «map:0» ⇒ cmdline sigue en 553 B. Nuevo repack (E1b) = mismo script con ese token
en G2 y la rama G6 correspondiente + **nuevo sha pre-registrado en el ledger antes de flash**.
Alternativa más fuerte (cambia el kernel, rompe el pin y añade una variable): rebuild con
`CONFIG_FRAMEBUFFER_CONSOLE=n`. Recomiendo map:1.

## (b) uke-wedge-sampler.sh — **corregido** (5 bugs, 2 avisos)

Verificado contra la rootfs objetivo (Arch ARM, sh=bash, coreutils):

- `date +%s%3N`: OK con coreutils (la rootfs es Arch). BUSYBOX imprimiría "3N" SIN error, así
  que el `|| date +%s` no protegía nada → añadido auto-cheque en `arm` que avisa en rails.log.
- `usleep`: **no existe en coreutils/Arch** → en cada tick un fork+exec fallido. Sustituido por
  `sleep 0.04` (GNU sleep acepta decimales), en rails y tlmm.
- `sync -f DIR`: válido (coreutils sync -f acepta cualquier path, incluido un dir; sincroniza
  el filesystem que lo contiene). Sin cambio.
- `xargs -r kill < PIDF`: GNU xargs ok, pero **arm no truncaba el PIDF**: tras un boot muerto
  con pids rancios, `stop`/rearm podría `kill` un pid RECICLADO (mismo bug que CRITICA-A2 #1
  corrigió en el witness). Ahora `arm` comprueba pid a pid y trunca si están muertos.
- Fallback debugfs de tlmm **ROTO**: el patrón ` grep$g ` no matchea el formato de ESTE árbol
  (`gpiolib.c:5424`: `" gpio-%-3u (%-20.20s|%-20.20s) %s %s %s%s"` → ` gpio-2   (…|…) out hi`),
  y `CONFIG_GPIO_SYSFS` no está en el .config de L19 (el fallback es el camino NORMAL, no la
  excepción). Resultado: tlmm.log con `g169=` vacío — el dato clave del mecanismo nº1 no se
  habría capturado. Reescrito: 1 lectura + 1 awk por tick que cubre AMBOS formatos (mainline y
  el downstream ` gpio2   : out low …` del comentario original), conservando el campo `gN=…`.
  De paso baja de ~16 a 2 forks/tick.
- `irq.now` era truncado+reescrito cada tick: una muerte entre truncar y grep dejaba el
  último snapshot VACÍO. Ahora escribe `.tmp` + `mv` (rename atómico). Eliminada la lectura
  de `irq.prev` (fichero que nunca se escribía); cabecera de ficheros corregida.
- Avisos en `arm`: <3 rieles en regmap y debugfs/gpio no legible.
- Carga a 25 Hz: ~16-18 forks/tick × 25 ≈ 400 forks/s ≈ 0,3 core en SM7675 con bash —
  notable pero tolerable; los bucles siguen escribiendo hasta el stall del WDT. No he tocado
  HZ (es diseño del protocolo). Validado: `sh -n` OK y el awk probado contra los dos formatos.

## (c) Disparador `echo on > /sys/class/drm/card1-DSI-1/status` — **NO dispara el enable; es un no-op de commit**

En este árbol, `status_store` (drm_sysfs.c:188-225) NO pone `connector->status`: pone
`connector->force` (`"on"` → `DRM_FORCE_ON`) y llama a `connector->funcs->fill_modes(...)`
(re-sondeo). `fill_modes` rellena EDID/modos — **no hay commit, no hay enable del DSI**; el
panel sigue donde está. El force=ON solo afecta al PRÓXIMO modeset que haga alguien.

Disparador correcto: un commit atómico de userspace — `modetest` (que el propio plan ya tiene
como fallback, y que en el proyecto ya mató la tablet 2× en K13: `modetest -c`, #P43, en
docs/historia/PLAN-SIGUIENTE-v2.md:102-103 — es decir, está instalado y SÍ dispara):

```bash
modetest -D /dev/dri/card1 -s "$(cat /root/conn.txt):32002136@XR24"   # conn.txt = "<conn_id>@<crtc_id>"
```

CONEXO: el nombre del conector. Regla confirmada (drm_sysfs.c:364):
`dev_set_name(kdev, "card%d-%s", dev->primary->index, connector->name)` con
`connector->name` = `kasprintf("%s-%d", "DSI", type_id)` (drm_connector.c:266) ⇒ el conector
es `DSI-1`, pero **el número de card depende del orden de sonda GPU↔MDSS**: la historia del
proyecto esperaba `card0-DSI-1` (docs/historia/revision/V4-panel-dpu.md:26) y docs/historia/revision/PRE-RENDER-20261010.md:30 vio un boot
solo con `card0` y cero conectores. El `card1-DSI-1` del plan es una suposición sin medida
citada. **Descubrirlo en runtime** (`ls /sys/class/drm/ | grep DSI`) y no hardcodearlo.

## (d) repack-k52L19E1.py — mecánica correcta; 2 gaps menores

Verificado SIN re-ejecutar (bytes + reporte de la ejecución real, todos los gates verdes):

- Artefacto en disco: sha256 = ca8cd4bd3304b738fa2f9453bb382eb2c0974791f7ac4b7a68d353c2185eab57
  == pre-registro #594 (FLASH-LEDGER.md:11942-11957). ✔
- Kernel extraído del L19P flasheado (G0): byte-idéntico al de E1, 16712428 B,
  sha 5582dcc20d834ab9… ✔ (pin más fuerte que mtime; justificado en el comentario G0).
- Cmdline: 553 B byte-idéntica a k64 − `video=DSI-1:d ` − `console=tty0 `; `console=ttyGS0,115200`
  presente; `fbcon=map:0` presente (que es justo el problema de (a)). ✔ mecánica, ✘ diseño.
- G6: la rama E1 (`k64 SIN video= NI console=tty0`, línea 412-413) dispara correcta — el
  reporte real la muestra. El log de G2 («dsid con video=DSI-1:d», línea 210) es **mentiroo
  en E1** (no hay video=): cosmético, confundiría la auditoría del reporte.
- G3 sobre el kernel extraído: POKE=113 y familia L11 pasaron en la ejecución real (reporte).
- G4/G8: kernel sobrescrito en PAGE con chequeo de hueco a ceros y unpack round-trip rc=0;
  sin efectos laterales observados. (Nit: `K13_KSZ=16577409` está desactualizado vs el kernel
  real 16712428; solo dimensiona la zona de exclusión vía max(), no hay bug.)
- **Gap: K64IMG no tiene pin sha en G0** (se lee en G2/G6 sin verificación). Hoy lo salva el
  sha del artefacto final (#594), pero el próximo repack (E1b) debería fijar
  `boot-uke-k64-vendorcfg.img` = `cc8f896a17eecc247633874ec46d67d1ec3d2ae74debbe8af4dc871650302e96`
  (calculado hoy) en G0.

## (e) Huecos del protocolo (lo que falta antes del disparo)

1. **acm-loop.sh exige argumento y el plan §2 lo llama sin él** (`out/acm-loop.sh`): `LOG=$1`
   vacío ⇒ `: > "$LOG"` muere y no se escribe nada del ACM. Usar
   `out/acm-loop.sh /root/acm-panel.log` (o similar) — y el LOG está en el PC, no en la tablet.
2. **`/root/conn.txt` se usa en §2 pero nadie lo crea.** Añadir paso 0:
   `modetest -D /dev/dri/cardX | grep -E 'DSI|CRTC'` → escribir `"<conn_id>@<crtc_id>"` a
   conn.txt (cuidado: #P43 muestra que hasta `modetest -c` fue letal 2× en K13 —
   ejecutarlo con los testigos ya armados).
3. **Foto pre-disparo** (no existe en §2): `ls -l /sys/class/drm/` + status/enabled/modes de
   cada conector + `/proc/interrupts` completo + `/proc/cmdline` completa + `/proc/version`,
   a un fichero en /root/witness (el cabecero del witness solo guarda tokens grep'eados de la
   cmdline, no la cmdline viva). Resuelve además de paso el nombre real cardN-DSI-1 de (c).
4. **debugfs**: el sampler (y el witness ftrace) asumen /sys/kernel/debug y /sys/kernel/tracing
   montados; systemd Arch los monta, pero si el port lo cambió, tlmm saldría en `gN=?` (ahora
   avisado en arm).
5. Menor: el aviso del plan de «si sobrevive 60 s» debería decir explícitamente que E0/§2 se
   hace con el par vigente L19 (con `video=DSI-1:d` el fbdev ni registra fb, así que el
   disparo del 0-flash SIEMPRE será modetest; `echo on` nunca enciende).

---

## GO / NO-GO

**NO-GO para ejecutar el protocolo tal cual está.** Condiciones para GO:

1. Rehacer E1 → **E1b** con `fbcon=map:1` (kernel pinneado intacto, cmdline 553 B), gates
   G2/G6 ajustados, pin sha de K64IMG añadido en G0, **nuevo sha pre-registrado en el ledger**
   y solo entonces flashear. (#594 tal cual NO se flashea: wedge ciega garantizada por diseño.)
2. Sustituir el disparador `echo on > status` por **modetest** (`status=on` puede quedarse
   como paso previo inocuo para forzar el conector a usable), con conn.txt generado en la
   propia sesión y el nombre del conector descubierto en runtime.
3. Añadir la foto pre-disparo del §(e).3 y corregir la invocación de acm-loop con su LOG.

El sampler corregido y el witness son reutilizables sin cambios adicionales. E0 y el análisis
de firmas del §1 del plan no necesitan modificación.
