# ANDROID-HIST1-HERMANO — 2026-10-16 (agente HIST-1, ámbito hermanos ubuntu-permanente + ubuntu-uke)

> Solo lectura. Fuentes: `ubuntu-permanente/docs/` (FLASH-LEDGER.md 13.817 líneas, LECCIONES, REFUTADO,
> CONFIG-BUENO, AL-DESPERTAR-RECUPERACION, REGLAS-PARTICIONES, ESTADO-ACTUAL, historico/) e
> `ubuntu-uke/` (docs/, stock/, dump/, ROM, HARDWARE-KNOWN-PLAN.md). El proyecto omarchy-uke lo cubre
> HIST-2 (docs/historia/revision/ANDROID-HIST2-OMARCHY-20261016.md); aquí solo se cita cuando el ledger lo referencia.

---

## A. Las restauraciones de Android que el dueño hizo (cronología con cita)

**R1 — 17-sep (#230): primer Android stock en B (prueba de UFS).** GO textual del dueño «Sí, prueba
Android en B», sabiendo que Android formatea userdata (FLASH-LEDGER.md:99-118). Se flasheó
boot_b←boot stock `f5ea7d90…` e init_boot_b←stock `5228e6e2…` (FLASH-LEDGER.md:102-107). **No llegó a
ejecutarse**: la tablet se apagó por batería (3242 mV, soc-ok no) y la sesión derivó en EDL
(FLASH-LEDGER.md:154-160). Dato útil que dejó: `fastboot erase` puede ser rechazado por el ABL mientras
`flash` de imagen sparse se acepta → «ESCRIBIR sparse en vez de borrar» (FLASH-LEDGER.md:233-234).

**R2 — 19-sep (#231): plan «cadena AVB completa del slot B»** — 8 particiones `_b` de pequeño a grande
(vbmeta_b, vbmeta_system_b, init_boot_b, dtbo_b, boot_b, vendor_boot_b, recovery_b, misc) con
**vbmeta stock SIN flags**, misc de ceros, `set_active b` SOLO al final, batería ≥3700 mV (umbral GO
de la ronda-14, FLASH-LEDGER.md:177-209). Este plan es la plantilla del flash de Android que se usó
después. Ese mismo día el plan cambió a reset completo:

**R3 — 19-sep (#232): RESET DE FÁBRICA con la ROM EEA oficial en SLOT A** (GO textual: «no tengo ningún
dato, si lo va a arreglar, borra todo y pon android», FLASH-LEDGER.md:211-227). Secuencia exacta:
boot_a, init_boot_a, vendor_boot_a, dtbo_a, recovery_a, vbmeta_a, vbmeta_system_a, **super (8,2 GB
sparse), userdata (757 MB sparse), metadata (2,2 MB sparse), set_active a**, reboot. **NO se flasheó el
bootloader** (abl/xbl/tz/… explícitamente excluidos: «es lo único que puede dejar el aparato
irrecuperable», FLASH-LEDGER.md:220-222). Ni GPT, ni persist, ni countrycode (:223-224).
**Resultado**: Android pasó ABL/AVB pero crasheaba en bucle (splash HyperOS + crash instantáneo,
FLASH-LEDGER.md:1432-1435); el dueño lo arregló pasando por recovery — «el BCB con `--wipe_data` hizo
que el recovery formateara los datos y el sistema completo el arranque» (FLASH-LEDGER.md:1622-1624).
**Android quedó sano en slot a** y sirvió de rollback durante toda la era fork.

**R4 — 19-sep (#233): root Magisk en A.** init_boot_a ← Magisk `b3cfc9b7…` (Magisk 30.7 sobre el init
stock de ESTA ROM; APK en `ubuntu-uke/stock/tools-dayd/Magisk-v30.7.apk`) + limpieza de misc (el BCB
`boot-recovery` residual de un `adb reboot recovery` hacía abortar a magiskinit; un `adb reboot` normal
NO limpia el BCB, FLASH-LEDGER.md:282-289). Root verificado: `su` = /debug_ramdisk/su uid 0
(FLASH-LEDGER.md:289-293).

**R5 — 21-sep: Android como rollback + borrado lógico.** El dueño arrancó Android para cargar
(FLASH-LEDGER.md:1432-1435); control E2: el kernel STOCK por `fastboot boot` arrancó Android completo
(ADB gadget 18d1:4e11, FLASH-LEDGER.md:1633-1637). En #300/#301 el dueño autorizó borrar Android
(«Android no lo uso, puedes borrarlo del todo»): `flash userdata rootfs-perm.simg`, `flash misc
misc.img` (limpia el BCB de wipe), `set_active b` (FLASH-LEDGER.md:1677-1725). Android quedó «sin
/data» en el slot a.

**R6 — 24-sep (F9, #384/#385): DESMANTELAMIENTO de Android** (orden explícita del dueño,
FLASH-LEDGER.md:3208-3227): `fastboot erase boot_a init_boot_a vendor_boot_a dtbo_a` +
`fastboot erase super`. **vbmeta_a NO se borró** («sin efecto, se conserva por prudencia», :3213-3214).
Tampoco misc, GPT, ni firmware.

**R7 — 30-sep (F9-E1, #446): re-composición del slot A.** Lectura previa E0: vendor_boot_a=`425382d5…`
e init_boot_a=`2daeb1f3…` NO a ceros pero inválidos (la GPT reconstruida #P31 solapaba regiones; de
hecho `2daeb1f3…` es el sha del dump de `fsg` — la lectura de init_boot_a leía la zona de EFS,
FLASH-LEDGER.md:5837-5839 vs `ubuntu-uke/dump/efs-20260905/sha256sums.txt`). F9-E1 flasheó
vendor_boot_a + init_boot_a **con las copias stock medidas** (`build/backup-par-bueno/`:
vendor_boot_b-lee=`3ee6d4ac`, init_boot_b-lee=`5228e6e2`) + boot_a=K13 Linux; el slot A volvió a
arrancar Linux completo y F9 se cerró (FLASH-LEDGER.md:5845-5861).

**R8 — 5-oct (#525-#527): LA ÚLTIMA RESTAURACIÓN COMPLETA DE ANDROID, en slot B, «como el primer
día».** GO del dueño: «hazlo como el primer día» y «flashea android aunque falle»
(FLASH-LEDGER.md:9902-9906). Dos fallos documentados antes del éxito:
1. Flash mínimo (boot/init_boot/dtbo) falló: userdata era ext4 de Arch, Android no puede montarlo
   (FLASH-LEDGER.md:9866-9872, #525).
2. **Hallazgo mayor (#527): el super del aparato NO tenía las particiones dinámicas `_b`** — el paquete
   oficial EEA es de SLOT A (super con extents `_a`; `flash_all.bat` termina en set_active a;
   FLASH-LEDGER.md:214-216 y #527:9936-9946). lpunpack del super en crudo: `_b` con 0 bytes.
**Lista de flash que FUNCIONÓ (procedimiento real, FLASH-LEDGER.md:9958-9962)**: ROM oficial
OS3.0.303.0.WOZEUXM completa en slot b — boot (`f5ea7d90`), init_boot **MAGISK** (`b3cfc9b7`),
vendor_boot (`3ee6d4ac`), dtbo (dump `27e61d21`), vbmeta×2 (dumps `0f7399d9`/`b4c81eaa` — NO los del
tgz), recovery (`babce84e`), countrycode, **super de fábrica (168 s de escritura)**… y para el slot b,
**super-b reconstruido offline con lpmake** (`super-b-final.img` `11f05e2d…`, verificado end-to-end
con simg2img→lpunpack→cmp: las 8 particiones `_b` byte-idénticas a las `_a`; receta completa con
metadata-size 65536, metadata-slots 3, --virtual-ab, device 11274289152, grupos 11263803392 y los 8
tamaños, FLASH-LEDGER.md:9948-9951 y 9938-9946) + userdata factory sparse (`85611e61`) + metadata
(`3c48f3cd`) + misc (ceros `9f1dcbc3`) + **doble `set_active a` + `set_active b`** (limpia
unbootable y repone retry=7; `set_active` sobre el slot ya activo es un no-op, #301
FLASH-LEDGER.md:1727-1731, medido de nuevo en #526:9895-9899). **Resultado: Android 16 arrancó
(wizard), Magisk root OK, captura integral hecha** (FLASH-LEDGER.md:9958-9968). Todo el hardware
funcionó en stock: pantalla (panel `o82_42_02_0b_dualdsi_dsc_vid`), táctil NT36532, WiFi WCN6750,
carga vía pmic_glink→ADSP, GPU Adreno732 viva (FLASH-LEDGER.md:9969-10001, #527:10003-10038).

**R9 — 6-oct (#530-#532): vuelta a Arch.** `flash boot_a` + `dtbo_a` + **`FLASH_USERDATA=1`**
(userdata ← rootfs v8 `bd2b3029…`) + `set_active a` (`docs/historia/gates-palawan/flash-fix529.sh`,
FLASH-LEDGER.md:10169-10175, 10200-10205). Tras bisects, la tablet quedó en la dorada del slot a
(FLASH-LEDGER.md:10170-10180, #532). **Estado de boot_b desde entonces, según el propio ledger, es
incierto**: 9-oct #554 «Slot B = imagen vieja (anterior al ciclo); su retry 6 lo confirma roto»
(FLASH-LEDGER.md:10926-10928) y 11-oct #596 «booteó el SLOT B (k13-dsid viejo)»
(FLASH-LEDGER.md:11979) — afirmaciones en tensión con las escrituras Android confirmadas del 5-oct.
**Conclusión operativa: NO asumir nada sobre el contenido actual de boot_b; el runbook lo reflashea
entero.** Además 11-oct #604: `fastboot -w` + `erase userdata` + `format:ext4 userdata` + `erase
metadata` ejecutados sin problema (FLASH-LEDGER.md:12141-12143) — o sea que `erase`/`format` de
userdata sí funcionan hoy en este ABL (matiza la nota del 17-sep).

**¿Se restauraron alguna vez los dumps EFS? NO.** Ninguna entrada del ledger toca modemst/fsg/spunvm;
grep de `efs|modemst|imei` en LECCIONES/REFUTADO/REGLAS-PARTICIONES: 0 resultados. El modem es
WiFi-only por DT (`remoteproc-mss status=disabled`, #527:10036) y el NV está intacto de fábrica
(modemst1 = modemst2 = fsg byte a byte: `2daeb1f3…`, dump/efs-20260905/LEEME.md:22-25).

---

## B. Inventario del stock en disco HOY (ubuntu-uke + copias)

### B.1 `ubuntu-uke/stock/images/` (extraídos del tgz oficial; SHA256SUMS verificados hoy)
| fichero | tamaño | sha256 |
|---|---|---|
| dtbo.img | 20 MB | `39ce170abef8e37d30c92f54f52625e62394180cfcc9c8af93799eee013b471d` |
| init_boot.img | 8 MB | `5228e6e2e5e9d903c352104738377e957e7cbd1ae67d7a3ffa97cb09cbef4a8d` |
| vbmeta.img | 8 KB | `3ef89cc9a75fc762448d733b2400713f2d13af9dd966a2b8ecec68632ad917bc` |
| vendor_boot.img | 96 MB | `3ee6d4ac5fefc6ea9dbe9e6ed48b298762ad273f4592e3acc56e4439f096a208` |
**Falta aquí `boot.img`** (no está en stock/images; la copia del tgz mide 96 MB).

### B.2 ROM oficial extraída: `ubuntu-uke/ROM-OS3.0.303.0.WOZEUXM/uke_eea_global_images_OS3.0.303.0.WOZEUXM_16.0/images/` (shas medidos hoy)
| partición | tamaño | sha256 |
|---|---|---|
| boot.img | 96 MB | `f5ea7d90c51695e46ee4b13e8ce7324f57805cb27743a934f578c9f032097a59` |
| recovery.img | 100 MB | `babce84ee0388e735eff29220ea56b317c3b30272205e1fba9539d12b6079f09` |
| vbmeta_system.img | 4 KB | `ddff9fb183762ed66f29ffa758776716a96c61fe8da0eac07417fac6f34a5eba` |
| misc.img | 8 KB (ceros) | `9f1dcbc35c350d6027f98be0f5c8b43b42ca52b7604459c0c42be3aa88913d47` |
| metadata.img | 2,2 MB | `3c48f3cd27d3ac844fd1480ff0711f12d6d9e13846b7207d4f5d93a282fb4216` |
| userdata.img | 757 MB sparse | `85611e6164ab02820cf7bfee8db993662958f915d8fb16e40f93bdf902c446e6` |
| super.img | 8,2 GB sparse (solo extents `_a`) | `9ef2e024327e0ac613ff221195b6b6add34fd42b37863103205efb1e132b7485` |
| (tgz original) ROM-OS3.0.303.0.WOZEUXM.tgz | 7,7 GB | — (ubuntu-uke/, raíz) |

### B.3 Copias certificadas del slot b en `omarchy-uke/build/android/flash-b/` (shas verificados hoy)
boot-stock `f5ea7d90…` · dtbo-b-stock **dump** `27e61d21fd6a0858…` · init-boot-b-**MAGISK**
`b3cfc9b787a9cb6…` · vbmeta-b-**dump** `0f7399d952e018e6…` · vbmeta-system-b-**dump**
`b4c81eaa0d6c8dd4…` · vendor-boot-stock `3ee6d4ac…`. (Mismo Magisk en
`ubuntu-uke/incoming/f3/flash-day/magisk_patched-30700_ZhZwr.img`, mismo sha.)

### B.4 Dumps EFS: `ubuntu-uke/dump/efs-20260905/` (7/7 verificados triple-hash, LEEME.md:56-62)
modemst1 `2daeb1f3…` · modemst2 `2daeb1f3…` · fsg `2daeb1f3…` (idénticos: NV de fábrica sin tocar) ·
fsc `30e14955…` · modem_a `05c73ee4…` (202 MB) · modem_b `4e33ce4d…` (202 MB) · spunvm `07f238fe…`
(32 MB). **OJO**: las copias offsite documentadas (`/mnt/ssd120/uke-backups/efs-20260905/` y
`/home/USUARIO/backups/uke/efs-20260905/`, LEEME.md:86-88) **NO existen hoy en esas rutas** (unidad
sin montar o movida) — la única copia viva es la del repo.

### B.5 ¿Alcanza para restaurar Android completo? — SÍ, con UNA pieza a reconstruir
- boot/init_boot/dtbo/vendor_boot/vbmeta_b/vbmeta_system_b/recovery/misc/metadata/userdata: TODO en
  disco con sha (B.2+B.3).
- **FALTA: `super` con extents `_b`.** El `super-b-final.img` (`11f05e2d`) del 5-oct vivía en /var/tmp
  y **ya no existe** (verificado). Se reconstruye offline sin tablet: `lpunpack` sobre el super.img
  oficial (B.2) → 8 particiones `_a` → `lpmake` con la receta exacta de #527
  (FLASH-LEDGER.md:9938-9946). El «super de fábrica» tal cual solo sirve para Android en slot a.
- Para la VUELTA a Linux: rootfs en `omarchy-uke/build/rootfs/` — `rootfs-uke-k521.img` (v8,
  `bd2b30294aee9989…`, 4 GiB, sha del sidecar verificado) y `arch-rootfs.img` (27-sep, 8 GB). **Pero
  el userdata actual de la tablet es posterior** (wipe + formato fresco del 11-oct #604, con el rootfs
  reconstruido in situ con fixes de octubre: adsp.b40 42c86837, sddm, etc., #651) — reflashear v8
  pierde esos cambios en vivo (ver §D).

---

## C. Gotchas documentados (todos con cita)

1. **AVB/vbmeta: NO tocar.** El ABL desbloqueado imprime «Device is unlocked, Skipping boot
   verification» (FLASH-LEDGER.md:341-342, #299.3:1667-1670). Las flags `--disable-verity
   --disable-verification` se probaron (#235) sin efecto y se revirtieron (#240); REFUTADO R-01/R-02
   las da por muertas 3× (REFUTADO.md:13-14). Regla dura: «No tocar vbmeta» (REFUTADO.md:61).
   **Además el fastboot 37.0.0 de Arch tiene un parcheador de `--disable-verity` roto** (pierde el
   lseek y sin `--apply-vbmeta` ignora las flags en silencio con OKAY engañoso; #299.4:1665-1667).
   Los vbmeta del aparato (dumps `0f7399d9`/`b4c81eaa`) difieren de los del tgz (`3ef89cc9`/`ddff9fb1`):
   usar los dumps, como hizo el 5-oct (#527:9948-9949).
2. **misc/BCB.** La imagen de limpieza son **8192 B de ceros** (no 2048 — un fichero de 2 KiB deja 6 KiB
   de BCB viejo; `omarchy-uke/build/gates/bcb-clean-8192.py`). Un `adb reboot` normal NO limpia el BCB;
   un BCB `boot-recovery` residual envenenó el arranque de magiskinit (#233:286-289) y el BCB
   `bootonce-bootloader` quedó como residuo permanente (#241:398-401). El recovery SÍ obedece un BCB
   `--wipe_data` (así se arregló el reset de fábrica, :1623-1624). El ABL no implementa `bootonce-*`
   y el cambio de slot es por GPT/`set_active` (:239-241).
3. **userdata/FBE: Android SIEMPRE reformatea userdata en el primer arranque** — inevitable y ya
   aceptado dos veces por el dueño (#232 GO; #299.2:1657-1659 «fue consecuencia inevitable»). El ext4
   de Arch no es montable por Android (#525:9866-9872). metadata se borra/reescribe junto a userdata
   (#232, #526, #604). Para el día D hay que presupuestar la PÉRDIDA del rootfs vivo y su re-creación.
4. **EFS**: nunca hizo falta restaurarla; solo en emergencia total (sin IMEI/WiFi/BT) y SOLO con los
   ficheros de esta unidad, por by-name exacto (dump/efs-20260905/LEEME.md:64-79).
5. **Slots**: los contadores viven en los attrs GPT de boot_a/boot_b, bits 48-55 (#302.4:1750-1758).
   `set_active` sobre el slot YA activo es no-op y no limpia `unbootable` — el desbloqueo son DOS
   comandos `set_active a` + `set_active b` (#301:1727-1731; medido: unbootable:b yes→no, retry 7,
   #526:9895-9899). **`fastboot flash` NO resetea el contador: flash + set_active SIEMPRE** (#596:11979;
   medido 13-oct: tras flash+set_active, unbootable a yes→no y retry 0→7, #614:12383-12385). El ABL
   aparca en fastboot tras 7 arranques fallidos (LECCIONES §5:62-63). El ABL también «miente» en
   estados wedged: ante un rechazo de una imagen conocida-buena, primero `fastboot reboot-bootloader`
   (LECCIONES §15:269-274).
6. **vendor_boot_a / init_boot_a: la premisa «borradas 24-sep» está CADUCADA.** F9 las borró el 24-sep
   (#384/#385:3210-3227), pero F9-E1 las re-flasheó el 30-sep con las copias stock (`3ee6d4ac` /
   `5228e6e2`, #446:5845-5861) y desde entonces ninguna escritura de octubre las tocó (todas fueron
   boot_a/dtbo_a). vbmeta_a es stock desde #232 (nunca se borró en F9). Slot a HOY = cadena Linux
   completa: boot_a=L73 `a671d293…` + dtbo_a=s288 (#651:13770-13774) sobre vendor_boot/init_boot/vbmeta
   stock.
7. **El dtbo lo aporta el SLOT, no el kernel** — `fastboot boot` usa el dtbo del slot activo (#301 L4:
   1737-1739; REFUTADO R-12:24). `fastboot boot` además no es herramienta de iteración fiable aquí
   (REFUTADO.md:58).
8. **Lista negra intocable**: bootloader (xbl/abl/tz/…), GPT con herramientas propias (R11: el
   gpt-switch causó el brick del 11-sep; REGLAS-PARTICIONES.md:43-51), persist, countrycode
   (REFUTADO.md:61). Reparación de GPT solo byte-exacta (R12:49-51).
9. **Batería**: gate GO ≥3700 mV medido 3× (ronda-14, :189); el ABL no intenta arrancar con
   `battery-soc-ok:no` (~<3400-3600 mV; #526:9891-9893, #614:12368). **En fastboot la tablet NO carga**
   y drena ~12 mV/min (#614:12365-12366); «EDL carga» fue RETRACTADO (#527(3):9934) — cargar con
   cargador de pared apagada. A 434 mV murió en pleno `Writing 'boot_b'` dejando contenido desconocido
   (#423, citado en #614:12378).
10. **initramfs en Android 13+ vive en init_boot, no en boot** (#229:85-86) — por eso un flash de boot
    solo «restaura el kernel» y no basta para volver a Android con ramdisk.
11. **El primer arranque de Android necesita un toque humano** para activar depuración USB (solo
    relevante si se quiere adb/captura; #524:9790-9793). Para un restore «a ciegas» no bloquea.
12. **No mezclar: nunca `-s SERIAL` en la era ubuntu-permanente** (#231:207) frente a los scripts de
    omarchy que fijan `fastboot -s SERIE0001` (#531:10184-10186). El serial existe (`SERIE0001`); el
    runbook usa fastboot a secas (convención de los procedimientos que funcionaron).

---

## D. Recomendación de slot y orden: **restaurar Android en B; dejar L73+rootfs en A como rollback**

Razonamiento (costes medidos en el ledger):
1. **userdata se destruye en ambos casos** (C.3): el primer arranque de Android reformatea userdata
   esté el Android en a o en b. Por tanto «coste de vuelta a Linux» = reflash de userdata con un
   rootfs + `set_active a` — **igual en ambas opciones** (~35-40 s de escritura medida,
   #301:1696, #537 nota userdata 40,6 s).
2. **Android en a costaría MÁS escrituras y destruiría el sistema en marcha**: el super actual del
   aparato tiene los extents `_b` poblados (el super-b-final del 5-oct; nada lo ha reescrito desde
   entonces: ni #604 ni los flashes de octubre tocan super). Un Android en a exigiría re-flashear el
   super oficial `_a` (8,2 GB sparse, ~168 s, #527:9959-9960) MÁS toda la cadena del slot a
   (boot/init_boot/dtbo/vendor_boot/vbmeta_a), pisando L73+s288 — que es justamente el kernel con el
   que se está iterando el panel (#651-#652) — y luego volver requeriría re-flashear L73
   (`omarchy-uke/build/bootimg/boot-uke-k52L73.img`, presente en disco) + dtbo s288 + userdata.
   Estrictamente peor: ≥9 escrituras frente a ~3.
3. **Android en b es el procedimiento PROBADO de punta a punta** (5-oct, R8): misma lista, mismos shas,
   resultado verificado (HyperOS arranca, root, todo el HW OK). Además deja el slot a intacto: si
   Android falla, `set_active a` devuelve el L73 vivo sin tocar nada (el ABL cae a a por agotamiento
   de b, #596:11979).
4. Único prerequisito: **reconstruir `super-b-final` offline** (lpmake, receta #527) porque se perdió
   de /var/tmp. 10 min de PC, 0 riesgo para la tablet.
5. Antes de empezar, **rescatar el estado del rootfs vivo** (la pieza que no tiene imagen en disco):
   con la tablet en L73 por SSH, tar de /etc, base de pacman, /root, /usr/local, /lib/firmware
   (adsp.b40 `42c86837`), lista de servicios enabled (patrón A.2 de #446:5843). El rootfs v8 de disco
   es base pero pierde los fixes de octubre.

---

## RUNBOOK — Restaurar Android (HyperOS OS3.0.303.0.WOZEUXM) en slot b, rollback L73 en a

> Disciplina obligatoria (REGLAS-PARTICIONES.md, CONFIG-BUENO, LECCIONES §6): una fila de ledger
> pre-registrada con shas ANTES de escribir (R7); un comando getvar como prueba de vida, nunca
> «Booting» (REFUTADO C.1); parar al primer getvar vacío y ciclo frío Power 15-20 s (REFUTADO C.4);
> sin `-s serial`, sin sufijos `_ab`, sin `-w` global.

**Fase 0 — PC, sin tablet (una vez)**
1. `lpunpack super.img` (de `ubuntu-uke/ROM-.../images/`, sha `9ef2e024…`) → 8 imgs `_a`.
2. `lpmake` con la receta de #527 (FLASH-LEDGER.md:9938-9946): metadata-size 65536, metadata-slots 3,
   `--virtual-ab`, device super:11274289152, grupos `qti_dynamic_partitions_a/_b` de 11263803392, las 8
   particiones `_b` pobladas con las `_a`. Verificar end-to-end: `simg2img → lpunpack → cmp` byte a
   byte; anotar el sha256 nuevo.
3. `python3 build/gates/bcb-clean-8192.py` → misc-zeros-8192 (o usar `misc.img` del ROM, `9f1dcbc3`).
4. Verificar con `sha256sum -c` los artefactos de B.2/B.3; copiarlos a un dir de staging permanente
   (no /var/tmp).
5. Pre-registro en FLASH-LEDGER.md: tabla partición←imagen←sha, gates, criterios de aborte.

**Fase 1 — backup del rootfs vivo (tablet en L73, por SSH 192.168.42.129)**
6. tar fuera de la tablet: `/etc`, `/var/lib/pacman/local`, `/root`, `/usr/local`,
   `/lib/firmware/adsp.b40`, `systemctl list-unit-files --state=enabled`, versión de kernel/dtbo en
   uso. Verificar sha del tar. (Sin esto, la vuelta a Linux parte del v8 de disco.)

**Fase 2 — fastboot (dueño pone la tablet: Power+Vol↓ desde Linux, o `reboot bootloader`)**
7. GATE: `fastgetvar battery-voltage` **≥3700 mV medido 3×**; si `battery-soc-ok:no` → NO flash:
   cargar en pared apagada (fastboot no carga y drena; EDL retractado).
8. `fastboot getvar current-slot` + `getvar slot-retry-count:a|b` + `getvar slot-unbootable:a|b`
   (foto al ledger).
9. Flashes slot b, de pequeño a grande (orden #231/#526):
   ```
   fastboot flash misc           misc.img            # 9f1dcbc3, limpia BCB
   fastboot flash vbmeta_b       vbmeta-b-dump.img   # 0f7399d9 (dump 3-sep, NO el del tgz)
   fastboot flash vbmeta_system_b vbmeta-system-b-dump.img  # b4c81eaa
   fastboot flash init_boot_b    init-boot-b-MAGISK.img    # b3cfc9b7 (root; stock=5228e6e2 si no se quiere root)
   fastboot flash dtbo_b         dtbo-b-stock.img    # 27e61d21 (dump)
   fastboot flash boot_b         boot-stock.img      # f5ea7d90
   fastboot flash vendor_boot_b  vendor-boot-stock.img  # 3ee6d4ac
   fastboot flash recovery_b     recovery.img        # babce84e
   fastboot flash metadata       metadata.img        # 3c48f3cd
   fastboot flash userdata       userdata.img        # 85611e61 sparse 757 MB (~15 s envío; BORRA el rootfs)
   fastboot flash super          super-b-final.img   # reconstruido Fase 0 (~168 s)
   ```
   Cualquier FAILED → PARAR (criterio ronda-16:277-279). vbmeta_a/vbmeta_system_a/super del slot a:
   no se tocan aparte del propio super (único, compartido).
10. **Doble desbloqueo de slots**: `fastboot set_active a` + `fastboot set_active b` (el doble es lo
    que limpia unbootable y repone retry=7; el simple sobre el ya-activo es no-op). Verificar con
    `getvar slot-retry-count:b` (=7) y `slot-unbootable:b` (=no).
11. `fastboot reboot` UNA vez. NO encadenar más comandos.
12. (Opcional, captura) el primer arranque de Android pide toque humano para depuración USB
    (#524); sin él, el restore se valida por pantalla/USB-MTP.

**Fase 3 — verificación post-arranque (checklist 10 min, criterios #230/#527)**
13. Pantalla: logo/animación HyperOS 5-40 s = kernel arriba; texto ABL 0-15 s = rechazo pre-handoff;
    negro total = apagón/batería (criterio #527:9952-9955).
14. USB: gadget ADB/MTP 18d1:… en lsusb (NO 18d1:d00d fastboot); si adb: `boot_completed=1`,
    IMEI/WiFi/BT presentes (EFS intacta), carga real por pmic_glink (ADSP), panel `o82_42_02_0b`.
15. Lectura de estado para el ledger: `fastboot getvar fbreason`, `battery-soc-ok`,
    `slot-retry-count:a|b`, `current-slot`.

**Fase 4 — rollback a Linux (el día que haga falta)**
16. Entrar en fastboot (Power+Vol↓; `adb reboot bootloader` si hay adb).
17. GATE batería ≥3700 (3×). `fastboot set_active a` → verificar unbootable:a=no, retry=7.
    boot_a=L73/dtbo_a=s288 NO se tocan (intactos). Si el rootfs se quiere exactamente como estaba:
    rehornear userdata desde el tar de Fase 1 + staging (receta #529/#530); si vale la base:
    `FLASH_USERDATA=1`-equivalente: `fastboot flash userdata rootfs-uke-k521.img` (v8 `bd2b3029`,
    ~40 s) y reaplicar fixes de octubre (adsp.b40, sddm, servicios).
18. `fastboot reboot`. Verificación: SSH 192.168.42.129, dd|sha de boot_a, fila de cierre en ledger
    (REGLAS R10: cierre completo o sesión no cerrada).

**Gates de aborte (transversales)**: batería <3700 (medida 3×) → parar; cualquier FAILED de flash →
parar; getvar vacío → Power 15-20 s y reintentar una vez; el slot a queda siempre como salida
(`set_active a` basta: su cadena L73+stock nunca se escribe en este runbook).
