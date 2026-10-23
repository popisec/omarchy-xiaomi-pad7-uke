# LINUX → ANDROID → LINUX — receta canónica ida y vuelta de la uke

> ✅ **Documento canónico (5-oct-2026).** Escrito por el orquestador de la sesión a partir de la
> investigación documental de **las 2 veces que la tablet pasó de Linux a Android**. Todos los
> sha256 re-verificados en disco hoy 5-oct. Rellena el hueco declarado por la auditoría G
> («la parte operativa de recuperación fastboot/brick»). **Manda el ledger**
> (`~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md`); este documento es la receta, no el registro.
> El estado del aparato ahora mismo solo lo dice `docs/historia/ESTADO-VIVO.md`.

## 0. La conclusión (leer primero)

Hubo exactamente **2 vueltas a Android ejecutadas**:

| | 1ª vez: 17→19 sep (#230–#233) | 2ª vez: 4→5 oct (#522–#525) |
|---|---|---|
| Estrategia | **Reset de fábrica destructivo en slot a**: ROM oficial EEA completa (8 particiones de arranque + super + userdata + metadata). Se pierde el Linux | **Flash mínima en slot b** (3 imágenes), slot a con la dorada intacta como rollback instantáneo |
| Motivo | Probar que la UFS estaba sana + recuperar adb/carga (la UFS no enumeraba para Linux) | **Snapshot de referencia de fabricante** (GPU/GMU/CM3, TLMM panel+táctil, hub-clock, ACTLR CB5, handoff SMMU) sin perder nada |
| Resultado | Android 16 + Magisk root en slot a (#233, #242). Duró hasta el 21-sep | **Fallo inicial** (userdata sin borrar) → corrección en #525, erase pendiente de ejecutar a la última evidencia |

**La lección maestra (pagada dos veces):** *Android no arranca con la userdata de Linux, y no se
puede hacer a medias.* El `init` de Android no monta el ext4 y cae → el ABL devuelve a fastboot
**antes** de poder formatear nada. Ya lo predijo el #228 (17-sep: «un Android arrancando con la
userdata de Ubuntu es lo que formatea userdata») y lo pagó el #525. **El erase de userdata+metadata
va ANTES del boot, no después.**

Lo que **nunca** se toca en ninguna de las dos direcciones: bootloader completo, GPT, `persist`,
`countrycode`, `vbmeta`/`vbmeta_system` (el ABL unlocked los ignora, medido en #236-D1) y —en la era
dorada— **el slot a**.

---

## 1. Las 2 veces (histórico verificado, con fila de ledger)

### 1.1 — 1ª vez (17→19 sep, #230–#233): reset de fábrica con la ROM oficial

**Fase 1a (17-sep, #230) — Android stock SOLO en slot b, como prueba diagnóstica** (Linux vivo en
slot a; esto no cuenta como vuelta del aparato):

```bash
fastboot flash boot_b      $ROM/images/boot.img        # f5ea7d90c51695e46ee4b13e8ce7324f57805cb27743a934f578c9f032097a59
fastboot flash init_boot_b $ROM/images/init_boot.img   # 5228e6e2e5e9d903c352104738377e957e7cbd1ae67d7a3ffa97cb09cbef4a8d
# coste aceptado por el dueño: Android formatea userdata (ahí vivía el rootfs Ubuntu de B)
```
`$ROM = ~/gpu-work/uke-rom-edl/uke_eea_global_images_OS3.0.303.0.WOZEUXM_16.0/images` (el tgz
íntegro vive también en `~/proyectos/ubuntu-uke/ROM-OS3.0.303.0.WOZEUXM.tgz`, 7.755.648.268 B).
Android crasheaba tras pasar ABL/AVB → «el fallo está en la capa de sistema» (#232).

**Fase 1b (19-sep, #232) — RESET DE FÁBRICA en slot a.** GO textual del dueño: *"no tengo ningun
dato, si lo va a arreglar, borra todo y pon android"*. Secuencia (~3 min de escritura, todo sparse
del paquete oficial):

```bash
for p in boot init_boot vendor_boot dtbo recovery vbmeta vbmeta_system; do
  fastboot flash ${p}_a $ROM/images/$p.img
done
fastboot flash super    $ROM/images/super.img      # 8,2 GB sparse
fastboot flash userdata $ROM/images/userdata.img  # 757 MB sparse
fastboot flash metadata $ROM/images/metadata.img  # 2,2 MB sparse
fastboot set_active a
fastboot reboot
```

- **Verificación previa** (#231): los 7 descriptores AVB de la ROM coinciden dígito a dígito, y el
  `ro.boot.vbmeta.digest=647b6599…` que el aparato cargó el 3-sep es exactamente
  `sha256(vbmeta|boot_vbmeta|recovery_vbmeta|vbmeta_system)` de esa ROM ⇒ «estos bytes ya arrancaron aquí».
- **Root Magisk después** (#233): `init_boot_a` ← Magisk 30.7 (`b3cfc9b787a9cb652553922c726f266bb812bd7e6c8fb1f436aa643dc89005a6`,
  el dump real del 3-sep), `su = /debug_ramdisk/su`.
- **Trampa BCB** (#233): un `adb reboot recovery` dejó `boot-recovery` en `misc` y abortaba
  magiskinit («Charger mode or ramdisk is recovery») → limpiar `misc` con `misc.img` (8 KB de ceros,
  sha `9f1dcbc3…`). Este ABL tampoco limpia nunca el `bootonce-bootloader` que Android escribe (#241).
- **Cierre de la era** (21-sep, #300/#301): vuelta a Linux con `fastboot flash userdata
  rootfs-perm.simg` (~1 GB) + fork por slot b.

### 1.2 — 2ª vez (4→5 oct, #522–#525): flash mínima en slot b para el snapshot

Estado de partida: slot a = **dorada** (`boot_a` k49-plyoff `6988dc7b4f94383503e655fe41c8a7096591d1813690fa56e98b791c41aeea67`,
`dtbo_a` s266 `15fdbbd3…`, userdata v7 `5f9f00fe…`); slot b = par bueno `e0ee47dc` + s262.

**Flash-list (#523), SOLO slot b** — assets en `build/android/flash-b/` (shas re-verificados hoy):

| Partición | Imagen | sha256 | Origen |
|---|---|---|---|
| `boot_b` | `boot-stock.img` | `f5ea7d90c51695e46ee4b13e8ce7324f57805cb27743a934f578c9f032097a59` | tgz oficial (idéntica a la de #230) |
| `init_boot_b` | `init-boot-b-MAGISK.img` | `b3cfc9b787a9cb652553922c726f266bb812bd7e6c8fb1f436aa643dc89005a6` | **dump real del 3-sep** (`~/proyectos/ubuntu-uke/dump/20260903-073613/partitions/init_boot_b.img`), Magisk 30.7 |
| `dtbo_b` | `dtbo-b-stock.img` | `27e61d21fd6a0858135e322eef9e8a223f6612ad24b1913fd7d9d680d602b3d8` | **dump completo de la partición** del 3-sep (25.165.824 B). NO usar el `dtbo.img` del tgz (`39ce170a…`, 20 MB): no es la partición entera |
| `vendor_boot_b` | **NO tocar** | ya stock `3ee6d4ac…` desde 28-sep | |
| `vbmeta*` | **NO tocar** | sanity del dump: `0f7399d9…` | ABL unlocked lo ignora (#236-D1) |
| `super` | **NO tocar** | jamás flasheado; fingerprint del dump = EXACTAMENTE la ROM del tgz (#525) | |
| `userdata` | ~~no pre-flash~~ | ← **EL ERROR** | «Android la formateará» era falso |

El ejecutor nocturno (`/var/tmp/uke-noche-ejecutor.sh`) **jamás flasheó**: su gate de batería
(`grep -oE '[0-9]+'` sobre `getvar battery-voltage`) devolvía vacío y salió a las 12:35 tras 1 h 42
min «sin flashear» (`/var/tmp/uke-noche.log`). Los flashes fueron **manuales del dueño**; el #525
certifica el resultado: «boot stock (f5ea7d90), init_boot MAGISK (b3cfc9b7), dtbo stock (27e61d21)
— todos ×2 OKAY».

**El fallo** (`/var/tmp/uke-bootretry.sh`, log 13:07–13:09): 3 reintentos de `set_active b` +
`reboot` con 3547/3517/3521 mV → todos de vuelta a fastboot en ~40 s ⇒ **«el fallo NO es batería»**.
Diagnóstico del dueño (#525): la flash-list mínima dejó `userdata = nuestro ext4 v7`; Android no
puede montarlo → init cae → ABL devuelve a fastboot. **Corrección (los «4 comandos», ~5 s en
fastboot): `erase userdata` + `erase metadata` + `set_active b` + `reboot`.** A la última evidencia
(log hasta 14:10 del 5-oct) el erase constaba pendiente y `build/evidencia/android-snap/` no existía.

---

## 2. La receta IDA — Linux dorada → Android (la que hay que ejecutar la próxima vez)

**Paso 0 — Pre-vuelo (gates, en el PC):**
- Batería de la tablet ≥ 3450 mV (guard del ABL; exitosos medidos 3461/3476, fallidos ≤3401). El
  gate duro del ciclo es **≥3700**. OJO: verificar el parseo de `getvar battery-voltage` a mano —
  fue lo que mató al ejecutor nocturno.
- Copia de seguridad de la imagen de vuelta: `rootfs-uke-k521.img` (4 GiB) vive en **`/var/tmp`
  (VOLÁTIL)** — copiarla a `~/proyectos/omarchy-uke/build/rootfs/` y anotar su sha256 ANTES de borrar nada.
- Capturar `vbmeta_system_a` (`fastboot fetch vbmeta_system_a`): **no hay copia local** y vive en
  `/dev/sda`, no en `/dev/sde` (NOTAS-OMARCHY). Sin esa captura, el paso 0.3 del
  `PLAN-recuperacion-dorada.md` queda abierto.
- Leer el pstore ANTES de ir a Android: el primer boot con dtbo stock lo destruye
  (`persistent_ram_zap`, #230).
- Anotar los shas de la dorada (están en `docs/historia/ESTADO-VIVO.md`).

**Paso 1 — Flash-list slot b** (las 3 imágenes de §1.2, con sha256 antes y lectura de vuelta
después; «la única verdad», guardrail 10 del #521):

```bash
FB=/opt/android-sdk/platform-tools/fastboot      # o el fastboot del sistema
A=~/proyectos/omarchy-uke/build/android/flash-b
sha256sum -c <<< "f5ea7d90…  $A/boot-stock.img"   # (los 3, completos)
$FB flash boot_b      $A/boot-stock.img
$FB flash init_boot_b $A/init-boot-b-MAGISK.img
$FB flash dtbo_b      $A/dtbo-b-stock.img
```

**Paso 2 — EL PASO QUE NO SE PUEDE SALTAR:**
```bash
$FB erase userdata
$FB erase metadata
```
(Si el ABL rechazara `erase`, la vía del 17-sep es **flash sparse** de `userdata.img`/`metadata.img`
del paquete oficial — #230, nota técnica.)

**Paso 3 — Slot y arranque:**
```bash
$FB set_active b
$FB reboot
```
`set_active` fresco **repone retry=7**. Si el slot ya estaba activo, `set_active` responde OKAY sin
tocar nada: el desbloqueo son DOS comandos, `set_active a` + `set_active b` (#301).

**Paso 4 — Toque humano (inevitable, userdata nueva):** wizard → saltarlo → 7 toques en
«Versión OS» → Opciones de desarrollador → Depuración USB → autorizar el PC.

**Paso 5 — Snapshot:**
```bash
adb push ~/proyectos/omarchy-uke/build/android/uke-snapshot-android.sh /data/local/tmp/
adb shell su -c "sh /data/local/tmp/uke-snapshot-android.sh"
adb pull <tgz>  ~/proyectos/omarchy-uke/build/evidencia/android-snap/
```
Criterio GO ya validado (#522-bis): ≥6 familias discriminantes nuevas (hub-clock delta, ACTLR CB5,
TCM_RET, estado TBU, 12 regs CM3, TLMM del panel con panel vivo — pista TLMM 54 = IRQ del táctil
novatek, #524).

---

## 3. La receta VUELTA — Android → dorada

```bash
FB=/opt/android-sdk/platform-tools/fastboot
# 1) userdata de vuelta (imagen de 4 GiB; sha256 ANTES de flashear; tarda ~35 s)
$FB flash userdata <rootfs-uke-k521.img>
# 2) par dorado en slot a — TRAMPA K49_BOOT: sin estas vars flashea el kernel SIN plyoff
#    (docs/historia/gates-palawan/flash-k49.sh líneas 18-20; sha por defecto d4b96f95… ≠ dorada 6988dc7b…)
export K49_BOOT=<ruta a boot-ukek49-esd-plyoff.img>  K49_SHA=6988dc7b4f94383503e655fe41c8a7096591d1813690fa56e98b791c41aeea67
bash ~/proyectos/omarchy-uke/docs/historia/gates-palawan/flash-k49.sh        # boot_a k49-plyoff + dtbo_a s266
# 3) slot activo y reboot
$FB set_active a
$FB reboot
```
Verificación viva: ssh al rootfs (claves del staging, root), `dmesg` de la dorada, y BCB limpio si
hubiera (`misc` a ceros). El plan completo con fases 0–3 y rollback al par bueno `e0ee47dc`+s262
está en `build/gates/revision/PLAN-recuperacion-dorada.md`.

---

## 4. Reglas duras de la ida/vuelta (obligatorias; estilo REGLAS-PARTICIONES)

1. **LV-R1 — userdata Linux ⇏ Android.** Nunca arrancar Android con el ext4 de Linux dentro:
   `erase userdata` + `erase metadata` SIEMPRE antes del primer boot. Prohibido «a medias».
2. **LV-R2 — vbmeta no se toca.** El ABL unlocked los ignora (medido). `vbmeta_system_a` sin copia
   local: capturarla antes de cualquier experimento.
3. **LV-R3 — super jamás flasheado en la era dorada.** Antes de asumirlo, fingerprint contra el
   dump sep-2026 (= ROM del tgz EEA).
4. **LV-R4 — Slot a intocable en la era dorada.** Toda la ida va a slot b; el rollback de la dorada
   es `set_active a`. Lo que jamás se flashea en NINGUNA dirección: bootloader completo, GPT,
   `persist`, `countrycode` (#232: «es lo único que puede dejar el aparato irrecuperable»).
5. **LV-R5 — Batería con umbral medido.** <3450 mV = ABL ni intenta (`battery-soc-ok:no`; en
   fastboot la tablet NO carga). Gate operativo ≥3700 mV.
6. **LV-R6 — Verificar el gate, no solo tenerlo.** El parseo de `getvar battery-voltage` del
   ejecutor nocturno devolvía vacío 1 h 42 min. Todo gate se prueba una vez a mano antes de
   confiar en él.
7. **LV-R7 — set_active fresco o doble.** Fresco repone retry=7; sobre slot ya activo es un OKAY
   vacío. Desbloqueo = `set_active a` + `set_active b`.
8. **LV-R8 — dtbo/init_boot: dumps del aparato, no el tgz a ciegas.** El `dtbo.img` del tgz no es
   la partición entera; valen los dumps del 3-sep con sha verificado.
9. **LV-R9 — pstore antes de salir.** El boot de Android con dtbo stock hace `persistent_ram_zap`.
10. **LV-R10 — fila de ledger pre-registrada por cada flash y por el erase**, con sha256 del
    artefacto antes y lectura de vuelta después. Sin fila, no hay flash (regla general del proyecto).

---

## 5. Evidencia

| Fuente | Qué certifica |
|---|---|
| Ledger #228–#230 | Predicción del formateo de userdata; prueba slot b; nota sparse-vs-erase; ROM en disco |
| Ledger #231–#233 | Pre-registro y cadena AVB del reset de fábrica; Magisk; trampa BCB/misc |
| Ledger #241–#242 | `bootonce-bootloader` sin limpiar; Android 16 vivo, retry=7 con set_active fresco |
| Ledger #300–#301 | Vuelta a Linux del 21-sep; regla del set_active doble |
| Ledger #521–#525 | Guard de batería; criterio GO y flash-list del snapshot; el fallo a-medias y la corrección (erase) |
| `~/proyectos/omarchy-uke/build/gates/revision/PLAN-recuperacion-dorada.md` | Plan ida/vuelta verificado; trampa K49_BOOT; vbmeta_system_a sin copia |
| `~/proyectos/omarchy-uke/build/android/` | `flash-b/` (4 imágenes con sha verificado hoy), `uke-snapshot-android.sh`, `README-capturas.md` |
| `~/proyectos/ubuntu-uke/dump/20260903-073613/partitions/` | `init_boot_b.img` (`b3cfc9b7…`) y `dtbo_b.img` (`27e61d21…`), shas verificados hoy |
| `/var/tmp/uke-noche.log`, `uke-noche-ejecutor.sh`, `uke-bootretry.sh` | El ejecutor que no flasheó; los 3 reintentos 13:07–13:09 («el fallo NO es batería») |
| `/var/tmp/rootfs-uke-k521.img` | Imagen de vuelta (4 GiB, 4-oct 02:10) — **copiar a sitio persistente antes del erase** |
