# Revista del proyecto hermano (`ubuntu-permanente`) — 28-sep-2026

> Solo lectura sobre `~/proyectos/ubuntu-permanente/` y `~/gpu-work/`. Sin tocar la tablet.
> Objetivo: lo accionable para `omarchy-uke`. Citas como `fichero:línea` (líneas del `docs/`
> del hermano; para el ledger, nº de entrada + cita literal).
> Correcciones a nuestras propias hipótesis del encargo van marcadas con ⚠️.

---

## 0. Lo que esta revisión corrige de lo que creíamos

Tres cosas del encargo quedan matizadas por la evidencia:

1. **#227 NO dice que el slot A quedara muerto.** La "firma EXACTA del ABL" es el patrón USB
   `full-speed + error -71, dos intentos, se rinde` = la firma de que el ABL cayó a fastboot
   y ningún kernel enumeró (coincide con H9 de su ronda 9). Es un síntoma, no un diagnóstico
   del slot. Y el slot A **sí volvió a la vida después**: #232 (19-sep) reflasheó la ROM EEA
   completa en A (incluido `set_active a`) y Android arrancó allí.
2. **#272 NO prueba que "el ABL rechaza los vendor_boot repackeados".** El propio hermano lo
   corrigió en #275: los 3 rechazos (s140/s141/s142) tenían la **cadena DTB rota** (el salto
   por `totalsize` caía en ceros; el stock tiene 4 FDT, no 3). La hipótesis del hash AVB murió
   por dos vías (digest correcto y aun así rechazo; s38 sin vbmeta aceptado) y el ABL unlocked
   no verifica (`Skipping boot verification`, R-01). Un repack con cadena intacta + digest
   recomputado **debería** ser aceptado (construyeron el s143 "chain-tile"; ver §1.6).
3. **`unlocked: yes` ⇒ todo su andamiaje AVB/hashtree es decorativo en esta máquina** (R-01,
   R-02). Confirmado por su lado varias veces; no gastar ni un ciclo en firmas.

---

## 1. El slot A: todo lo que saben

### 1.1. #227, literal (docs/FLASH-LEDGER.md:10)

- Pre-registro 17-sep 11:38. Particiones: `dtbo_a` (`s110-dtbo-uno.img`,
  `7e950dce…`) + `boot_a` (`boot-konly-s110-uno.img`, `0f8bef19…`). Gate GO.
- Resultado (`#227 — RESULTADO (11:39)`, ledger:36):
  > "Flash: dtbo_a OKAY (0.047 s) + boot_a OKAY (0.403 s) a las 11:29 → ESCRITO EN UFS, sin error."
  > "11:29:19 new full-speed USB device number 22 → device descriptor read/64, error -71"
  > "= la firma EXACTA del ABL (full-speed, +1-2 s, dos intentos, se rinde): coincide con H9 de la ronda 9."
  > "el fork no enumero (o no llego a arrancar). NO se puede distinguir sin leer la pantalla."
- **Lectura pendiente que nunca se hizo**: la pantalla (fila verde de uke_poke + sello).
  El #232 pisó `boot_a`/`dtbo_a` antes de leerla (ledger:248-252: "la lectura de la #227 quedó
  sin hacer: el #232 pisó boot_a/dtbo_a; las imágenes están en disco").
- #228 (ledger:48) repara el slot B como canal de lectura; A queda intacto con s110-uno.

### 1.2. Todos los flashes conocidos en el slot A

| Entrada | Partición(es) A | Resultado |
|---|---|---|
| #227 (17-sep) | `boot_a`+`dtbo_a` (s110-uno, mainline) | Escrito OK; sin enumeración USB (firma ABL/-71) |
| #232 (19-sep) | ROM EEA completa: `boot_a, init_boot_a, vendor_boot_a, dtbo_a, recovery_a, vbmeta_a, vbmeta_system_a, super, userdata, metadata` + `set_active a` (ledger:211) | **Slot A restaurado a Android stock; Android arrancó** (21-sep, cf. ledger #273/§#230-nota). Se pierde s110-uno (autorizado) |
| #233 (19-sep) | `init_boot_a` ← Magisk `b3cfc9b7…` (ledger:260) + `boot_b` fork | Bucle de lectura ramoops; A con Magisk+su operativo |
| #384/#385 (24-sep) | `erase boot_a init_boot_a vendor_boot_a dtbo_a` + `erase super` (ledger:3208) | **Slot A desmantelado** (orden del dueño). `userdata` NO se toca (es el rootfs Ubuntu) |
| #406 (25-sep mañana) | `boot_a`=`boot_b`=`avb/boot-s205-k5mods.img` (`52a7ae22…`) y `dtbo_a`=`dtbo_b`=`s207-nogpr` (`fe0bc14c…`) (ledger:3987 §5) | Mismo par bueno en ambos slots; Ubuntu arranca; carga en frío OK |
| #409 (25-sep tarde) | `boot_a`=`boot_b`=`avb/boot-s209-ubwc.img` (`f6946f35…`); `dtbo_a`=`dtbo_b`=`s208-display-charge` (`27e8939a…`) (ledger:4110) | Ubuntu arranca; display a un paso (VSP/VSN pendientes) |
| #427 (26-sep, nota de operación) | Observación: tras un flash a `b`, la tablet arrancó del slot **a** (kernel #81 = s238) | **Flashear `b` no garantiza arrancar de `b`**; comprobar `getvar current-slot` + hash por `dd` |
| #444 (27-sep, nuestro) | Solo `userdata` (Arch). Explícito: "Lo que NO he tocado: `boot_a`, `boot_b`, `dtbo_b`, `vendor_boot_b`, `vbmeta` y `misc`" | Slot A sigue con lo último que el hermano dejó |

Búsqueda expresa post-#384 de restauración de `vendor_boot_a`, `init_boot_a` o `super`:
**NO EXISTE en el ledger (#385–#444)**. Las únicas escrituras en A tras el desmantelamiento
son `boot_a`/`dtbo_a` (#406, #409). Conclusión: **hoy `vendor_boot_a` e `init_boot_a` son
ceros (nuestra medición) y `super` (sda31) sigue borrado; `boot_a`/`dtbo_a` contienen
imágenes Ubuntu (`s209`+`s208` salvo que el #435 u otro posterior tocara A — el #435 solo
toca `boot_b`/`dtbo_b`, ledger:5405)**.

### 1.3. ¿Arrancó alguna vez un mainline en el slot A?

- s110-uno (#227): sin evidencia (pantalla nunca leída). **No demostrable.**
- s38 (#238, citado en #275, ledger:1202): **ARRANCÓ en a y en b** — corrección histórica
  mayor del propio hermano ("el 'mismo patrón que s38' de #272 era falso"). Es la prueba de
  que el ABL acepta imágenes sin vbmeta/footer cuando la estructura es válida.
- Desde #406, el slot A arranca kernels Ubuntu (s205, s209) — mainline-fork, no Android.
- Con DT mainline puro en A: no hay evidencia de éxito.

### 1.4. `erase super` y dónde vive cada cosa

- #384 (ledger:3208): `fastboot erase super` = "10,5 GB del sistema Android, sda31".
  Ledger:3150-3157: `sda30` = rescue, `sda31` = super, `sda32` (`105,9 GB`) = userdata.
  Nota #230 (ledger:231): `partition-size:userdata = 0x1A767FB000`, `super = 0x2A0000000`.
- La ROM EEA es "paquete de SLOT A (super.img con extents _a; flash_all.bat termina en
  set_active a)" (ledger:216-218). Rollback de lo borrado: reflashear ROM stock
  (`~/gpu-work/uke-rom-edl`, ledger:3227).
- Regla de operación (#230-nota, ledger:233): el ABL puede rechazar `erase` y aceptar
  `flash` de sparse; para resetear datos, **escribir sparse en vez de borrar**.
  ⚠️ Pero para `userdata`, sparse encima de otra imagen deja **rootfs frankenstein**
  (no limpia huecos): **siempre imagen cruda** (#444).

### 1.5. Cmdline del kernel bueno, ENTERA (sin resumir)

Del constructor del s240 (gpu-work/ramaa/s21, `*s240*report*.txt`:8-9), 255 B, y el s244 la
hereda sin cambios salvo kernel (`s244-boot-repack-report.txt:1-8`):

```
mem=2048M rdinit=/ukeinit panic=10 memmap=0x1A12800$0xE3940000 console=tty0 fbcon=map:0
hung_task_timeout_secs=20 hung_task_panic=1 watchdog_thresh=10 console=ttyGS0,115200
fw_devlink=permissive clk_ignore_unused pd_ignore_unused arm-smmu.disable_bypass=0
```

La s181 (299 B, `s185-boot-repack-report.txt:7`) añade `initcall_blacklist=pmic_glink_init`
y `softlockup_panic=1`. El `vendor_boot` stock suma por **bootconfig**: `swiotlb=noforce`,
`disable_dma32=on` (inerte, R-53), `kasan=off` (ronda 37 §2).

Recursos que el cmdline exige (checklist de restauración del slot A):

1. `rdinit=/ukeinit` — el init vive en el **ramdisk de `boot`** (R-17: el ramdisk del
   `vendor_boot` stock pisa `/init`; por eso el nuestro se llama `/ukeinit`). Sin `boot_a`
   con ese ramdisk no hay userspace aunque el kernel arranque.
2. `memmap=0x1A12800$0xE3940000` — reserva de 26 MB en `0xE3940000` (ventana ramoops/pstore
   del layout stock; R-10: sin parámetros `ramoops.*` no hay `last_kmsg`).
3. `console=ttyGS0,115200` — gadget USB serie (canal ACM). Sin el `vendor_boot` stock que
   trae la config del gadget, el canal puede no existir.
4. `fw_devlink=permissive`, `clk_ignore_unused`, `pd_ignore_unused` — sin ellos, probes
   diferidos matan el arranque (era s149-s170).
5. `arm-smmu.disable_bypass=0` + bootconfig `swiotlb=noforce` — el DMA del WLAN depende de
   este par (ronda 37 §2; nuestro parche `s244` ignora el `noforce`).
6. Todo `androidboot.*`/slot suffix viene del ABL por slot: con el slot A sin `vendor_boot_a`,
   el kernel de A pierde bootconfig entero.

### 1.6. Vendor_boot: lo que realmente valida el ABL

#275 (ledger:1202), la entrada más valiosa para nosotros:

1. El stock tiene **4 FDT** (A@0x207b000 msm-id 0x266, B@0x20EF122 0x278, C@0x216301D 0x283
   **= este aparato**, D@0x21D5307 0x282). Los totalsize suman exactamente `dtb_size`.
2. Regla del ABL (H3): **camina la cadena por `totalsize` y exige magics válidos + fin
   exacto en `0x207b000+dtb_size`**. Gate obligatorio: simular la caminata en la imagen final.
3. s38 (#238) arrancó sin vbmeta ni footer ⇒ **unlocked no verifica AVB**.
4. Los DTB de referencia están en `~/gpu-work/stock-dtbs/` (stock-fdt0..3.dtb) y el constructor
   válido es el `s143 "chain-tile"` (`~/gpu-work/ramaa/s21/vendor_boot-s143-chain-tile.img`,
   `89f54bb7…`: totalsize de C `0x16114→0x722EA` + digest recomputado, ledger:1230).
   ⚠️ No verifiqué si el s143 llegó a flashearse; mirar la entrada siguiente a #276.

---

## 2. Hardware resuelto y medido que podemos reutilizar

### 2.1. GPIO74/75 + proxy (RESUELTO, reutilizable tal cual)

- El vendor trae los reguladores en el fragmento @98 del payload stock:
  `display_panel_vsp/vsn` (TLMM 74/75, 5,8 V) (ESTADO-ACTUAL.md:438).
- El driver `reg-fixed-voltage` falla con `can't get GPIO` porque la lookup de gpiolib
  apunta a chips proxy `gpiolib_shared.proxy.N`, que solo existen si está cargado el
  **módulo del fork `gpio-shared-proxy.ko`** (ESTADO-ACTUAL.md:295; ledger #410:4164).
- Medido: con el módulo cargado, `uke_panel_vsp/vsn supplying 5800000uV` (ESTADO-ACTUAL.md:202,
  ledger:4169). Sin él, panel en probe diferido.
- Reutilización: el `.ko` está en su árbol; en el nuestro hay que compilar el equivalente
  o portar el módulo + nodos DT propios (ellos usan nodos propios con `target-path`,
  no los del vendor: ESTADO-ACTUAL.md:438-440). Phandles del DT base que ya midieron:
  `tlmm` 0x16b, `L8B` 0x14f, `apps_smmu` 0x129, `mc_virt` 0x188, máximo 0x531
  (ESTADO-ACTUAL.md:436).

### 2.2. Reguladores del display + pmxr2230_l8 (RESUELTO)

- `vddil8b`/`pmxr2230_l8` registrado con `min/max = 0` en el dtbo: el core leía voltaje y
  el driver devolvía `-ENOTRECOVERABLE` ⇒ -131 (ESTADO-ACTUAL.md:332).
- El payload stock trae @100 `L8B` a 1,9 V (`0x1cfde0`) (ESTADO-ACTUAL.md:438).
- Cadena completa verificada en #410 (ESTADO-ACTUAL.md:202): VSP/VSN + L8B OK, `msm_dsi`/
  `msm_dsi_phy` bindean, **panel PROBEA** (`/sys/class/backlight/ae94000.dsi.0`,
  `panel-xiaomi-o82-dualdsi`). Driver: `panel-xiaomi-o82-dualdsi.c` (dual-DSI 3200×2136,
  DSC 1.1, 108 comandos init, backlight DCS) en `~/gpu-work/w4-panel/`.
- Último bloqueo de display: SMMU (`no IOMMU, bailing out` ⇒ -19) — dtbo s212/s214
  construidos, pero **el bind del apps-smmu wedgea el arranque** (#418, R-39/R-40).
  ⚠️ Para Hyprland este es el muro, no el panel.

### 2.3. ADSP (RESUELTO, cadena de carga COMPLETA — fase 5 cerrada)

- Orden de carga (`bin/uke-adsp-load-tablet.sh`, ref en ESTADO-ACTUAL.md:302):
  `qcom_q6v5_pas qcom_glink_smem qrtr_smd qcom_pd_mapper pmic_glink qcom_battmgr` + `echo start`.
- Dos bugs cazados con datos (ledger #406, ESTADO-ACTUAL.md:344): `qcom_pd_mapper` no
  matcheaba `qcom,cliffs*` (parche: añadir a `qcom_pdm_domains[]` → `sm8550_domains`) y el
  bucle `qcom,gpr` (`Domain ID not specified`, 6420 fallos/38 min, batería agotada) ⇒
  `status="disabled"` en dtbo s207.
- Medido en frío: `PDR: Indication … charger_pd, state: 0x1fffffff`, `status=Charging`
  1,19 A (ledger #406 §3). Sonda QRTR propia: 13 servicios del ADSP, ninguno 0x40 hasta
  cargar el pd_mapper (R-35/R-36).
- Dialecto battmgr: 0x50 parcheado; 0x13 con `complete(&ack)` + `-ENODATA` (0 B log/10 s,
  ledger #408). Cosmético abierto: respuestas cruzadas 0x13↔MODEL_NAME.
- "Manómetro": **no hay nada con ese nombre en su repo** (grep vacío). Lo más cercano:
  (a) la sonda QRTR de servicios (R-35), (b) `voltage_now` como única medida fiable de
  carga (ronda 34 §6: no fiarse del signo de `current_now`), (c) `input_current_limit`
  SDP 500 mA solo-lectura (ronda 33 §5). Si el "manómetro" es otra cosa, decir cuál.

### 2.4. WLAN (a medio resolver — lo más caliente)

- Estado: WCN6750 responde (chip_id, fw `WLAN.MSL.3…`), QMI completo, BDF cargado, `qmi
  firmware ready` + rings… y **reset silencioso ~7,33 s tras el inicio del probe** (3/3
  medidas: 7.319/7.333/7.350 s, ledger #441:5643). Sin oops/pstore/PDR ⇒ invisible al APSS.
- Perseguido más allá del reset: sí — kprobes en `ath11k_pcic_write32/read32` con
  `trace_pipe` a disco (ronda 38 §1): 119 escrituras, muerte al terminar el **pipe 7 CE**
  (`0x1b8e004 ← 0x8000`). Falta el **kretprobe** (¿retornan las escrituras? bus vs firmware).
- Hipótesis viva: orden MSI en `hal.c:268/:347` — MSI armado (LSB→MSB+ENABLE→data) **antes**
  de base/tamaño/ID del anillo (ronda 38 §4). Parches `s247` (MSI→base, sin efecto, #437) y
  `s248` (sin MSI, reset idéntico, #441) ya descartan "MSI mal direccionado".
- Firmware instalado y verificado por sha (wpss.mdt `e2d14e4f…`, amss `c42e06f5…`, #434);
  rutas planas `ath11k/WCN6750/hw1.0/` (R-47 corrige lo del `firmware-name`).
- DMA: resuelto con nuestro enfoque (pool swiotlb fallback `s244`, `mapped [mem
  0xe7000000-0xeb000000]`, cero overflow, #433). R-52–R-56 entierran `mem=`,
  `disable_dma32`, y confirman banco `0x880000000+`.
- ⚠️ Trampa operativa: scripts que hacen `rm blacklist-ath11k` sin restaurarla dejan
  autoprobe en bucle que **gasta reintentos de slot** (#441:5620; ronda 39 §4: blacklist
  con `sync`, EXT4 ya en 879 errores).

### 2.5. CM3/GMU y FASE 3 (ABIERTA — reencuadrada por R-57, aportación nuestra)

- Síntoma: `a6xx_gmu_start` cuelga al soltar reset (`SYSRESET=0`); `S3-rst0` último poke,
  `S4-poll` nunca (TRABAJO-PENDIENTE.md:101; ledger #389/#390).
- Verificado OK: relojes, MMIO, RSC/PDC, firmware en TCM, HFI, power_config, OPP
  (`GMU OPP table OK: 2 opps`, #417). Firmware exonerado por sha (6 copias idénticas,
  R-57).
- R-57 (REFUTADO.md:193, nuestra): el cuelgue **no está en la carga sino en el `resume`**
  (solo corre al primer `open()` de `/dev/dri`); el primer acceso del CM3 es MMIO directo
  a ITCM/DTCM, no SMMU; `IOMMU_PRIV` es bit de permiso, no contexto. Vías vivas por orden:
  (1) `gmu_chipid 0x70b0000` de la entrada catálogo `0x43030b00` (ruta de 735, nunca validada
  en GMU) — **leer el ID real instrumentando en arranque, nunca `devmem` en runtime**
  (ronda 33); (2) reloj/power CX tras `power_config`; (3) `F4-verOK` no prueba ejecución.
- Test en caliente listo sin flashear: `dtbo s242-cm3-clon` + `uke-cm3-test.sh`
  (ESTADO-ACTUAL.md:26-28); bloqueado por el `-EBUSY` del bind manual tras el oops del
  desmontaje DRM (#432, ronda 39 §2). Techo de 3 ciclos consumido: no gastar flashes en H1.

### 2.6. Lecturas MMIO/registros aprovechables

- Regla dura (ronda 33 §1, ledger #393): **nunca SMMU/regmap/MMIO en runtime** (cuelga);
  instrumentar solo en arranque. Nunca volcar clock-controller con GDSC apagados
  (ESTADO-ACTUAL.md:446).
- Método que sí funciona: **kprobes/kretprobes de los accesos del driver** con trace
  continuo a disco (ronda 38 §1-2), `pr_info` inmediato alrededor del primer `readl`
  (TRABAJO-PENDIENTE.md:113), y la escalera de pokes `uke_poke` para acotar "muere ENTRE
  X e Y" (LECCIONES.md:226 §14.2).
- Referencia dorada: `criticas/ufs-referencia-android/dmesg-android.txt` — el Android
  stock con apps-smmu bindeado (TBU incluidos). Sirve para comparar dominios/SIDs.

---

## 3. Lo que hay que evitar (refutaciones y lecciones aplicables)

### (a) Restaurar el slot A

- **R-09** (REFUTADO.md:9): "hay que restaurar algo en el slot b" murió porque el diff era
  cero — pero advierten que era **inferencia** (§B: nunca leyeron de vuelta una partición).
  Nosotros SÍ medimos A: ceros. No inferir, medir.
- **B-01** (REFUTADO.md:44): nunca leyeron una partición de vuelta; `fastboot fetch` **no
  soportado** (medido #427/#428). Nuestra vía de verificación es `dd`+sha desde OS vivo.
- **R-13**: `set_active` dejó el ABL sordo 2/2 (reescribe entrada+CRC+cabeceras).
  Una escritura grande por ventana; `flash` sí aguanta.
- **R-44/R-50/R-51**: en fastboot NO carga (3662→3655 mV); el ABL lee ~3,4 V mientras el
  kernel reporta 4,42 V (`battery-soc-ok: no` ⇒ cae a fastboot). Con display: cargador de pared.
- **#444 (nuestra)**: sparse sobre `userdata` = frankenstein; **siempre cruda**. `dd` con la
  partición montada corrompe (journal encima).
- **REGLAS-PARTICIONES.md:8-50**: R1 (solo `set_active` cambia slot), R2 (sin re-dump no hay
  reboot), R10 (cierre completo o sesión no cerrada), R11 (gpt-switch vetado tras el brick
  del 11-sep).

### (b) Arrancar un kernel instrumentado

- **R-01/R-02**: AVB decorativo (unlocked). No tocar `vbmeta` (regla C.5).
- **R-12**: `fastboot boot` usa el **DTBO del slot activo** ⇒ con A activo, DT stock sin
  receta ⇒ fallo estéril. Último recurso y solo con `b` activo.
- **R-11**: `Rebooting`/`Booting` los imprime el cliente; prueba de vida = `getvar`.
- **R-17**: el ramdisk del `vendor_boot` stock pisa `/init` ⇒ nuestro init en `/ukeinit` +
  `rdinit=/ukeinit`. **Obligatorio para cualquier boot en A.**
- **CONFIG-BUENO.md:10-24**: gate `gate-s83.sh` (12 configs, 13 símbolos, `Image.gz` ≥16 MB);
  verificar por símbolos/config embebido, nunca por cadenas; la caída s88→s89 (498 opciones)
  costó 3 sesiones.
- **LECCIONES §14.8** (LECCIONES.md:253): `make` en foreground = noop silencioso; **builds
  desprendidos** (`setsid nohup … &`) + `ARCH=`/`MAKE=` explícitos.
- **Ronda 34-37**: doble captura **consola ACM + `ssh 'dmesg -w' > fichero`** (la serie
  pierde la cola al cortar el reset); `dmesg -n 7` antes de evidencia INFO (los DBG son
  nivel 6); `sync` antes de `sysrq-b`; `/tmp` es tmpfs (imágenes a `/root`); contar líneas
  antes de creerse un `WARN_ONCE` desaparecido.
- **R-29/R-30/R-31/R-32/R-33**: no reintroducir `separate_gpu_kms`, no culpar pmic_glink/ADSP
  (arranca bien), no culpar nodos DT sueltos del wedge.
- **#427/#428**: flashear `b` ≠ arrancar de `b`; `fastboot continue` como diagnóstico
  (`Load Error` = imagen ilegible, no contador).

### (c) Escalera de pokes

- **Ronda 33 §1** (LECCIONES.md:388): SMMU solo en arranque; `arm-smmu` tiene
  `suppress_bind_attrs` (sin fichero `bind`; EPERM confunde).
- **R-18**: las lecturas SPMI de hijos de PMIC cuelgan (martillo: solo `pm7550ba@7` +
  repetidor eUSB2); las escrituras no.
- **LECCIONES §14.1** (LECCIONES.md:226): `gpiochip_add_data` lee todos los pines ⇒
  `valid-mask` donde haya huecos (patrón-hermano del tcsrcc).
- **R-24**: literales `<0x…>` como phandle cuelgan (solo etiquetas; el ABL reubica vía
  `__local_fixups__`). **R-27**: el dtbo conserva payload stock+s134; el ABL ignora
  `/delete-node/`.
- **Ronda 36 §2-3** (LECCIONES.md:542): al recompilar payload, tirar `__symbols__/
  __fixups__/__local_fixups__` y regenerar con `dtc -@`; `target-path` solo resuelve
  contra el base (lo creado por el overlay se edita en origen).
- **Ronda 35 §7**: referencia a nodo del propio overlay siempre por etiqueta; el gate
  comprueba coincidencia, no valor.
- **Ronda 39 §1**: comparar la FORMA del nodo vendor (reg/hijos/clocks), no solo el
  compatible, antes de repuntar (apps-smmu: 2 `reg` + hijos TBU vs 1 `reg` mainline).

### (d) Camino a Hyprland

- **R-39/R-40/R-42**: el bind del apps-smmu wedgea (bisección s217/s222); el watchdog s221
  bindea y mete bucle de reinicios ⇒ **sin red de recuperación**. El arreglo A solo
  wedgea (#431). Vía viva: A′ (forma correcta del nodo) — offline con gates.
- **#409**: `msm.separate_gpu_kms=1` no arranca este kernel (2 intentos, 0 líneas).
- **R-25/R-28**: OPP cargado no desbloquea CM3; un probe de GPU por arranque (clon, no unbind).
- **R-34**: ADSP arranca sin wedges (sin iommus, memcpy a DDR física) — el modelo a imitar.
- **#407**: sin display, `gdm` en bucle agota logind y mata SSH ⇒ `mask gdm` +
  `multi-user.target` hasta tener panel.
- **R-45**: `uke-battery.service` es no-op (ruta Android inexistente).

---

## 4. Herramientas reutilizables (preferir las suyas donde se dice)

| Script | Qué hace | Veredicto |
|---|---|---|
| `bin/uke-console-cap.sh` | Captura ACM permanente con reapertura por vuelta (caza X9DUMP-block) | **Mejor que el nuestro: adoptar** (drena siempre; sin él los `write()` se bloquean) |
| `bin/uke-fastboot-watch.sh` | Vigía: `set_active a+b` + reboot; tras N caídas restaura par bueno (`s244`+`s229`); fichero pausa `/tmp/uke-fastboot-watch.pause`; cuenta reseteada solo al ver Ubuntu (ronda 39 §3) | **Adoptar** (con pausas durante flashes). Es nuestra red en fastboot-no-carga |
| `bin/uke-dtbo-check.py` | `fdtoverlay` + chequeo de phandles de props críticas y GPIOs | **Gate obligatorio antes de flashear dtbo** (cazó el s206 roto). Mejor que fiarse del merge a mano |
| `bin/uke-flash.sh` | Flash autónomo adb→fastboot con `set_active b` | Útil; adaptar serial/partición |
| `bin/flash-s209.sh` + `verify-s208.sh` | Flash boot+dtbo en ambos slots con relectura+gates; evidencia display/DRM | Reutilizar patrón para el ciclo de A |
| `bin/uke-fase3-collect.sh` | Recoge evidencia CM3 (avisa si no hay captura; exige `dmesg -n 7`) | Reutilizar tal cual para FASE 3 |
| `bin/uke-fase4-deploy.sh` | Despliegue display | Revisar antes de usar (era pre-s214) |
| `bin/uke-gpu-probe/bind/cycle.sh`, `uke-hwinit-test.sh` | Bring-up GPU en caliente, bind por `drivers_probe` | Reutilizar (respetar: sin `bind` en arm-smmu) |
| `bin/uke-wifi-deploy.sh`, `uke-wifi-firmware-stage.py` | Despliegue ath11k + staging de firmware con sha | Reutilizar; anteponer `mkdir -p` (R-49) |
| `bin/uke-shell.sh`, `uke-first-contact.sh` | SSH persistente por fichero+`tail`; primer contacto con diagnóstico | Adoptar para operación sin sesiones nuevas |
| `bin/uke-adsp-load-tablet.sh` / `uke-adsp-load.sh` | Carga ADSP en tablet / desde PC (orden de 6 módulos + `echo start`) | Referencia (carga ya funciona) |
| `bin/uke-acm-drainer.py`, `uke-recover-watch.sh`, `uke-autowatch-s215.sh` | Drenaje ACM, recuperación, autowatch desprendido | Patrones; el autowatch como ejemplo de ciclo autónomo |
| `~/gpu-work/ramaa/s21/s2*-boot-repack.py` + `*-report.txt` | Constructores de boot con gates (sha, marker del parche, `unpack_bootimg`, footer AVB) | **Adoptar el patrón** para nuestros repacks (s230–s244 son el modelo) |
| `criticas/ronda-35/smmu-default-identity.patch`, `wifi-arranque.patch`, `ronda-29/dispcc-no-pm-runtime.patch` | Arreglo B IOMMU, arranque WiFi, dispcc sin runtime PM | Revisar contra nuestro árbol (B ya está en el suyo desde 25-sep 20:55) |
| `criticas/mega-bootimg.py` | Descarga del ZIP Linux-UKE de MEGA | Histórico; no necesario |
| `vigia-e12.sh`, `vigia-e4.sh` (raíz) | Vigías antiguos | Obsoletos frente a `uke-fastboot-watch.sh` |
| ⚠️ `uke-wifi-trace.sh:46` (citado #441; no está en `bin/`) | Borra la blacklist y no la restaura ⇒ autoprobe en bucle | **NO usar** sin parche (guardia + `sync`) |

---

## 5. Preguntas abiertas (resolubles quizá desde nuestro lado)

1. **Reset WLAN ~7,33 s** (ledger #441/#442): 3 medidas, falta la 4ª limpia (r10e
   pre-registrado). Discriminador pendiente: kretprobe en `ath11k_pcic_write32` (¿retorna
   la escritura al pipe 7?) + orden MSI de `hal.c`. Nuestro kernel instrumentado puede
   poner los kretprobes sin gastar flashes (módulo).
2. **CM3: ¿`resume` o silicio?** (TRABAJO-PENDIENTE.md:63-136): diff fork↔upstream limpio
   salvo catálogo `0x43030b00`; falta validar `gmu_chipid` real y power CX. Nuestro árbol
   limpio + instrumentación en arranque es el sitio ideal.
3. **A′: forma correcta del repunte del apps-smmu** (ESTADO-ACTUAL.md:26-28; ronda 39 §1):
   nodo vendor 2 `reg` + hijos TBU vs 1 `reg` mainline. Offline, con gates. Nadie lo ha
   construido.
4. **Display end-to-end**: con SMMU resuelto, `modetest` + táctil `evtest` (driver
   `novatek-nt36532-spi.c` en `~/gpu-work/w5-touch/`, sin verificar en vivo).
5. **Firmware del BT**: no está en `modem_a`; buscar en el resto de particiones firmware
   (TRABAJO-PENDIENTE.md:22-24). Tenemos el mapa de particiones.
6. **Watchdog útil**: `reg` corregido ⇒ bucle de reinicios (#418; TRABAJO-PENDIENTE.md:87).
   Falta `max_timeout`/`reg_offset_data_kpss` del APSS de este SoC.
7. **Deuda operativa**: ext4 con ~880 errores (`e2fsck` en frío + `norecovery`), sin RTC,
   ruido UFS devfreq -22, TTF cruzado (cosmético).
8. **s143 chain-tile**: ¿se flasheó? Si no, es la prueba de que el ABL acepta vendor_boot
   con cadena intacta — decide si podemos tocar `vendor_boot_a`.

---

## 6. Lo que no está en su documentación principal y merece la pena

- `criticas/ronda-36/wifi-ronda*.md` (12 informes): la caza del `-EIO` y del reset, con
  trazas y comandos. Lo más denso y reutilizable del repo.
- `criticas/ronda-36/gpu-a-prima-apps-smmu.md`: informe A′ del IOMMU (base del punto 3 de §5).
- `criticas/f2-slot/` (`.bin` de GPT primaria/backup/misc): **backups de GPT por si hay
  que comparar o reparar atributos de slot**. No tocar sin R12.
- `criticas/kernel-nuevo/parches-s42b.diff` + `lector-ramoops.py`: arqueología útil
  (formato ramoops del stock).
- `criticas/ufs-referencia-android/dmesg-android.txt`: **referencia dorada** del Android
  (SMMU bindeado, TBU, reguladores, UFS) para comparar contra nuestro dmesg.
- `criticas/evidencia-linux-uke/boot.img` (`c4b7b815…`): imagen Linux-UKE conocida buena
  (la que reparó B en #228).
- `docs/historico/` (7 ficheros): el estado por días; `TRABAJO-PENDIENTE-21SEP.md` muestra
  qué ya se cerró.
- `halium/stage1*`, `initboot/` (`pack-initboot.py` + stage1 e12/e13): el camino init_boot
  alternativo si el ramdisk de `boot_a` no bastara.
- `~/gpu-work/stock-dtbs/` (fdt0-3): los 4 DTB del vendor_boot, ya extraídos.
- `~/gpu-work/w5-touch/novatek-nt36532-spi.c` + DTS/yaml: **driver del táctil**, listo para
  compilar en nuestro árbol.
- `~/gpu-work/w4-panel/`: driver + DTS del panel O82 y su PORT-TODO.
- `~/gpu-work/initramfs-uke/` (`build.sh`, `pack-bootimg.sh`): constructor de initramfs+boot
  mínimo.
- `~/gpu-work/ramaa/s21/` (cientos de imágenes + constructores + reports con sha): **el
  archivo de artefactos** — cualquier imagen citada en el ledger está aquí.
- `~/gpu-work/ramaa/s22/rootfs.simg`: el Ubuntu de `userdata` para restaurarlo.
- `~/gpu-work/uke-staging/firmware/qcom/`: firmware GPU verificado (el que usó el probe bueno).
- `~/gpu-work/fw-qrd8635/`: copias de firmware de OTRO origen (sqe/zap difieren) — no mezclar.
- `~/gpu-work/PINNED-HEAD.txt`, `SHA-BACKUP-*.txt`, `gpt-*-backup.bin`: pins y respaldos con
  fecha; útiles como punto de comparación.
- `criticas/README.md`: advierte que los informes son fechados y que ante contradicción
  manda `ESTADO-ACTUAL.md` + última entrada del ledger. Aplicar la misma regla a esta revista.

---

## 7. Decisión propuesta (accionable)

1. Restaurar A en este orden: `vendor_boot_a` stock (cadena válida) → `init_boot_a` stock →
   `boot_a`+`dtbo_a` con nuestro kernel (`/ukeinit` + cmdline §1.5) → `super` **solo si**
   hace falta Android (para mainline no hace falta: el rootfs vive en `userdata`/sda32).
   Verificar cada paso por `dd`+sha desde B, no por `getvar`.
2. Adoptar ya: `uke-console-cap.sh`, `uke-fastboot-watch.sh` (+pausa), `uke-dtbo-check.py`
   como gate, doble captura, `dmesg -n 7`, blacklist con `sync`.
3. No gastar ciclos en: AVB/firmas, `fastboot boot` con A activo, SMMU en runtime,
   `devmem` en runtime, `mem=` como herramienta DMA, `set_active` sin necesidad.
4. Desde nuestro árbol limpio: kretprobes WLAN (pregunta 1), instrumentación de arranque
   del chipid del GMU (pregunta 2), A′ offline (pregunta 3).
