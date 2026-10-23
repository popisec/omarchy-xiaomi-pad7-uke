# ANDROID-HIST2-OMARCHY-20261016 — HIST-2: historial de restauración Android y artefactos del repo omarchy-uke

> Agente HIST-2, 16-oct-2026. Ámbito: SOLO `~/proyectos/omarchy-uke` (git log + docs +
> artefactos). Solo lectura + este informe. Sin fastboot/dispositivos. 545 commits en la rama
> (`git log --oneline | wc -l`).

## A. Menciones a restaurar Android / «vuelta atrás» en la historia del repo

### A.1 Las 2 vueltas a Android que se EJECUTARON (documentadas desde este repo)

**Documento canónico: `docs/guias/LINUX-A-ANDROID-IDA-VUELTA.md`** (commit `efa0483`, 5-oct-2026: «Receta
canónica Linux↔Android: las 2 vueltas verificadas…, reglas duras LV-R1..R10»). Certifica:

- **1ª vez (17→19 sep, ledger hermano #230–#233)**: reset de fábrica destructivo en slot a con la
  ROM oficial EEA completa (`for p in boot init_boot vendor_boot dtbo recovery vbmeta vbmeta_system;
  fastboot flash ${p}_a …` + super + userdata + metadata + `set_active a`), 8 particiones, se pierde
  Linux. Android 16 + Magisk root (#233). Trampa BCB: `adb reboot recovery` dejó `boot-recovery` en
  `misc`; limpieza con 8 KiB de ceros (sha `9f1dcbc3…` — hoy `build/gates/misc-zeros-8192.img`,
  re-verificado en disco). Vuelta a Linux el 21-sep (#300/#301) con `flash userdata rootfs-perm.simg`.
- **2ª vez (4→5 oct, #522–#525)**: **flash mínima en slot b** (3 imágenes), slot a con la dorada
  intacta como rollback instantáneo. Lección pagada: **Android no arranca con userdata de Linux** —
  el #525 falló por dejar el ext4 v7 y la corrección es `erase userdata` + `erase metadata` +
  `set_active b` + `reboot` ANTES del primer boot. Reglas duras LV-R1..R10 (líneas 184-206):
  erase siempre antes (R1), vbmeta no se toca (R2), super jamás flasheado (R3), slot a intocable en
  era dorada + jamás bootloader/GPT/persist/countrycode (R4), batería ≥3450 ABL / gate ≥3700 (R5),
  verificar el parseo del gate (R6), set_active fresco o doble (R7), dtbo/init_boot por dumps del
  aparato no por tgz (R8), pstore antes de salir (R9), fila de ledger pre-registrada por flash y
  erase (R10).
- Receta §2 (ida) y §3 (vuelta) verificadas; **OJO: la §3 «receta VUELTA» está CADUCADA** — apunta a
  la dorada k49-plyoff `6988dc7b…` + s266 + `flash-k49.sh` (4-oct), que ya no es el par vigente
  (hoy es L73 + s288, ver §C/D).

### A.2 Commits relevantes (grep sobre `git log --all`)

| Commit | Fecha | Qué dice |
|---|---|---|
| `efa0483` | 5-oct | Receta canónica ida/vuelta (ver A.1) |
| `5648424` | 5-oct | `PLAN-recuperacion-dorada`: procedimiento verificado ida/vuelta; hallazgos «vbmeta_system_a sin copia», trampa K49_BOOT |
| `f263347` | 28-sep | Ciclo F5-B1: **restaurar slot A** (vendor_boot_a + init_boot_a stock) + boot-pokes |
| `1bc14b5` / `de25239` | 10-oct | #581 restauración k52b2+s273 (shas OK) |
| `9c7c392` | 9-oct | Testbed restaurado k52b2 (#554) |
| `78987fc` | 6-oct | ESTADO-VIVO: base dorada restaurada, receta k18-tree (#532) |
| `276a5d3`/`06adf5a` | 5-oct | Android capturado (#527-prepare, #528) |
| `9f5d613` | 5-oct | `uke-snapshot-android.sh` transcrito y corregido |
| `7e19648` | 27-sep | V2 pre-registrado: restaurar Ubuntu para responder con datos |
| `78adef7`, `b23125b`, `dc2d2c7`, `2d56db9`, `f2121be` | 29-sep→2-oct | Sucesivas restauraciones del «par bueno» de Linux tras experimentos |
| `824065b`, `c8a234a` | 15-oct | RE Android cerrado (gaps + ángulo DDIC) — ingeniería inversa del vendor Android para la pantalla, no restauración |

Conclusión: **sí hubo 2 rondas reales de restaurar Android** (sep y oct), ambas ejecutadas por el
proyecto de origen y documentadas/canonizadas desde ESTE repo; además, restauraciones recurrentes
del lado Linux (slot a/par bueno) son el pan de cada ciclo.

### A.3 La imagen de «vuelta atrás» de 370 MB de Ubuntu — **NO EXISTE ya en su ruta documentada**

- Definición: `~/gpu-work/ramaa/s22/rootfs.img` (8 GiB ext4) y su comprimida `rootfs.img.gz`
  (**370 MB**, exactamente 369.822.577 B, sha `b6d5411712b…`) — `F-plan-por-fases.md:925`,
  `README.md:155`, `build/gates/ROLLBACK.md` §2 (paso `cd ~/gpu-work/ramaa/s22 && sha256sum
  rootfs.img.gz`) y `build/gates/SHA-BUENOS.txt` («**NO BORRAR rootfs.img.gz: es el seguro de F5**»,
  «SEGURO DE VUELTA ATRÁS»).
- **Verificado hoy en disco: `~/gpu-work/ramaa/s22/` NO EXISTE** (`ramaa/` salta de `s21` a `s23`).
  Búsqueda global (find por nombre `rootfs.img.gz` en ~ y por tamaño 360–400 MB en
  proyectos/gpu-work//var/tmp): **0 resultados**. La imagen de 370 MB de Ubuntu está **PERDIDA** de
  su ruta canónica. La advertencia de `ROLLBACK.md` §5.9 («no borrar hasta cerrar F5») no se cumplió
  (o el directorio se archivó sin dejar copia localizable). NOTA: para la restauración **Android**
  esto no bloquea (la vuelta atrás de Android es slot a + userdata Linux, no el Ubuntu original).
- **Sustituto vivo**: la imagen de vuelta Linux es `rootfs-uke-k521.img` (4 GiB, Arch v7/v8), en
  `/var/tmp` (VOLÁTIL según aviso de la receta §2) y copiada a `build/rootfs/`. Ver §B y §D para el
  problema de shas.

## B. Inventario de artefactos NO-Linux en build/ (shas re-verificados hoy en disco)

### B.1 `build/android/flash-b/` — flash-list Android stock slot b (la del #523, receta §1.2)

| Fichero | Tamaño | sha256 | Papel |
|---|---|---|---|
| `boot-stock.img` | 96 MiB | `f5ea7d90c51695e46ee4b13e8ce7324f57805cb27743a934f578c9f032097a59` | boot Android stock (idéntica al #230) |
| `init-boot-b-MAGISK.img` | 8 MiB | `b3cfc9b787a9cb652553922c726f266bb812bd7e6c8fb1f436aa643dc89005a6` | init_boot del dump real 3-sep con Magisk 30.7 |
| `dtbo-b-stock.img` | 24 MiB (25.165.824 B) | `27e61d21fd6a0858135e322eef9e8a223f6612ad24b1913fd7d9d680d602b3d8` | dtbo stock — dump de PARTICIÓN entera (NO el `dtbo.img` del tgz, LV-R8) |
| `vendor-boot-stock.img` | 96 MiB | `3ee6d4ac5fefc6ea9dbe9e6ed48b298762ad273f4592e3acc56e4439f096a208` | stock ya en device desde 28-sep; no se flashea |
| `vbmeta-b-dump.img` | 128 KiB | `0f7399d952e018e6d869044d0fedfda788a9b8df4f183cd5cc08f4a4bc8dd8a4` | sanity; no se toca |
| `vbmeta-system-b-dump.img` | 128 KiB | `b4c81eaa0d6c8dd43e59098dc11253ede13eb81c68525b5e468be8fdbff59d78` | dump lado b |
| `README-capturas.md`, `uke-snapshot-android.sh`, `uke-snapshot-r2.sh`, `uke-snapshot-r15.sh` | — | — | scripts de captura por adb |

### B.2 `build/backup-par-bueno/` — mezcla de stock Android + pares Linux

| Fichero | sha256 (hoy) | Papel |
|---|---|---|
| `init_boot-stock.img` | `5228e6e2e5e9d903c352104738377e957e7cbd1ae67d7a3ffa97cb09cbef4a8d` | init_boot stock (igual al tgz oficial #230) |
| `init_boot_b-lee.img` | `5228e6e2…` (idéntico al anterior) | lectura de vuelta del device |
| `vendor_boot-stock.img` | `3ee6d4ac5fefc6ea9dbe9e6ed48b298762ad273f4592e3acc56e4439f096a208` | vendor_boot stock (base del DT, intocable #238) |
| `vendor_boot_b-lee.img` | `3ee6d4ac…` (idéntico) | lectura de vuelta |
| `boot-ukek13-dsid.img`, `boot-uke-k52L19.img`, `s260-…`, `s275-…` | (Linux, ver SHA-BUENOS.txt) | pares Linux de rollback del slot b |

### B.3 Limpieza de misc/BCB y slots

- `build/misc-zeros-4m.img` (4 MiB, sha `bb9f8df61474d25e71fa00722318cd387396ca1736605e1248821cc0de3d3af8`)
  — **la imagen correcta** para limpiar BCB (misc mide 4 MiB; la de 8 KiB deja BCB viejo vivo:
  `DECISION-misc-BCB.md` §2, #P52).
- `build/gates/misc-zeros-8192.img` (8 KiB, sha `9f1dcbc3…`) — la del #233 (histórica; preferir la de 4 MiB).
- `build/gates/bcb-clean-8192.py` — limpieza fina del BCB (64+4 B).
- `build/slot/`: `qbootctl-aarch64` + `PROCEDIMIENTO-SLOT.md` + `slot-log.tsv`. **Los contadores de
  slot viven en atributos GPT (bits 48-63), no en misc** (`PROCEDIMIENTO-SLOT.md:61-64`); la única
  vía de escritura documentada es `qbootctl -m`, **prohibida sin decisión del dueño** (riesgo brick
  11-sep). `fastboot flash + set_active` rehabilita slots (medido #614/#P52-RESULTADO).

### B.4 Evidencia Android ya capturada (5-oct)

`build/evidencia/pre-android-20261005/getvar-all-antes.txt` (estado pre-ida) ·
`build/evidencia/android-snap/` (uke-r1-manual.tgz 50 KB, uke-r15-20260625-114251.tgz 298 KB,
dt-r15.tar.gz) · `build/evidencia/android-full/` (uke-full-20261005.tar.gz 3,7 MB) ·
`build/evidencia/android-full-gaps/`, `stock-dt/`. **GO ya validado del snapshot #522-bis.**

### B.5 Huecos y falsas expectativas

- **NO hay** en el repo imágenes stock de `userdata`/`super`/`metadata`/`recovery` Android. Están en
  la ROM oficial: `~/proyectos/ubuntu-uke/ROM-OS3.0.303.0.WOZEUXM.tgz` (7.755.648.268 B, **intacta
  hoy**) y extraída en `~/gpu-work/uke-rom-edl/uke_eea_global_images_OS3.0.303.0.WOZEUXM_16.0/images/`
  (**existe hoy**, con boot.img, dtbo.img, super.img, userdata.img, metadata.img…).
- `build/backup/` NO tiene nada Android: `tablet-20261013/` (etc-config + pacman list) y
  `trees-historicos/` (k13/k18 .tar.zst) = solo Linux.
- **`vbmeta_system_a` sigue SIN captura de bytes** (solo getvar, `partition-size: 0x20000` en
  `pre-android-20261005/getvar-all-antes.txt:222-223`); hueco declarado LV-R2 y paso 0.3 de
  `PLAN-recuperacion-dorada.md` — **capturarla ANTES de la ida a Android**.
- **Inconsistencia de sha del rootfs de vuelta**: `build/rootfs/rootfs-uke-k521.img` (4 GiB, mtime
  5-oct 16:32) hashea HOY `5f9f00fe0704a5742bac9829b19a6107208c44e0b80c9eb47f3c487f1fdea169` = **v7**,
  pero su sidecar `rootfs-uke-k521.img.sha256` y el audit (`docs/historia/revision/AUDIT-ARTEFACTOS-20261006.md:17`) declaran
  `bd2b3029…` = **v8**. En `/var/tmp` están hoy AMBOS: `rootfs-v7-backup-20261006.img` (5f9f00fe,
  6-oct) y `rootfs-v8-backup-20261007.img` (bd2b3029, 7-oct). La copia del repo es la v7, no la v8
  que dice su .sha256. Resolver cuál es la de vuelta y re-copiar ANTES del erase (receta §2 paso 0).

## C. Estado del aparato según la doc (para encuadrar la restauración)

Fuente: `docs/historia/ESTADO-VIVO.md` cabecera 16-oct ~13:0x (mando: ledger hermano
`~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md` #553–#652).

- **Slots HOY**: `current-slot:a` · **boot_a = L73 `a671d293f738a6325bd18cb4a63a17a52c449b0af2e53adeb9700256960bd37d`**
  (flasheado 16-oct ~12:4x; imagen presente en `build/bootimg/boot-uke-k52L73.img`, sha re-verificado
  en disco hoy ✓; pre-registro #651, commit `1004ac9`) · **dtbo_a = s288
  `02d403c518346bf5a3757c5519eb8ca205f8f75af078cfde2e03d9d49e702dfb`** (presente y ✓ en
  `build/bootimg/s288-…adsp.img`). **Slot b = par hermano** (el repo mantiene copias verificadas del
  par histórico: k13-dsid `e0ee47dc…` + s262/s260 en `backup-par-bueno/`).
- **Arranque vivo**: SSH 192.168.42.129, escritorio Omarchy ARRIBA (Hyprland+quickshell, sddm activo
  a mano), PPS OEM en vivo (gates UKE-L73 verdes), **Charging** (adsp.b40 reparado en vivo; sha
  `42c86837…`, ritual anti-corrupción en cada sesión). Veredicto visual del dueño pendiente.
- **Rollbacks declarados**: L71 `5e13addf…` / L70 `f2e820d2…` (escritura futura) — y la vuelta
  registrada en el ledger como **#652** (hermano).
- **Batería**: gate duro de escritura **≥3700 mV** (en fastboot NO carga, R17 de F-plan:1482);
  guard ABL <3450 mV (`battery-soc-ok:no`). El flash L73 se hizo con **3414 mV por excepción
  explícita del dueño**; el 16-oct 00:2x estuvo AGOTADA (475–557 mV, ~9 h en fastboot) — el caso
  documentado exige cargador de pared ≥45 W en apagado. Antes de la restauración: re-medir.
- **misc/BCB**: última limpieza documentada = `flash misc` 4 MiB de ceros el 1-oct (#P52, sha
  `bb9f8df6…` verificado); medición posterior #P52-RESULTADO: la misc solo lleva el BCB
  (`command="bootloader"`), los contadores viven en GPT. El ABL tampoco limpia nunca el
  `bootonce-bootloader` que Android escribe (#241) — **revisar/limpiar misc tras la vuelta**.
- **Contadores de retry**: última medición completa 13-oct (`docs/historia/ESTADO-VIVO.md:437`): a=6, b=6;
  tras flash+set_active a=7 (rehabilitación medida #614). No re-medidos desde el flash L73 →
  medir en fastboot antes de la ida.
- **Advertencia de caducidad**: la propia `docs/historia/ESTADO-VIVO.md` lleva aviso de que las capas intermedias
  (12/13-oct) están caducadas; lo que manda es el ledger.

## D. Parte del runbook que toca a ESTE repo

### D.0 Qué está listo aquí para la ida a Android (receta = `docs/guias/LINUX-A-ANDROID-IDA-VUELTA.md` §2)

1. Flash-list slot b completa y verificada: `build/android/flash-b/` (shas en §B.1 — los 3 a
   flashear: boot f5ea7d90, init_boot b3cfc9b7, dtbo 27e61d21; vendor_boot_b 3ee6d4ac ya en device).
2. ROM oficial íntegra fuera del repo (si hiciera falta vía sparse del #230):
   `~/proyectos/ubuntu-uke/ROM-OS3.0.303.0.WOZEUXM.tgz` + `~/gpu-work/uke-rom-edl/…/images/`.
3. Scripts de snapshot: `build/android/uke-snapshot-android.sh` (+r2/r15) — criterio GO #522-bis
   (≥6 familias discriminantes).
4. Gates de batería: reutilizar el patrón de `docs/historia/gates-palawan/flash-l73-gated.sh` (getvar battery-voltage
   con parseo verificado a mano — LV-R6; 1ª lección del ejecutor nocturno fallido, §1.2).
5. **Pre-ida obligatorio desde el repo**: (a) capturar `vbmeta_system_a` (hueco abierto, §B.5);
   (b) leer pstore (LV-R9); (c) registrar shas del par vigente L73+s288 (ya en §C) y del userdata;
   (d) **resolver la v7/v8 del rootfs de vuelta y copiarla a sitio persistente** (§B.5) — el erase
   de userdata destruye el ext4 Linux.

### D.1 Qué copiar/verificar de aquí (checklist de artefactos)

```bash
cd ~/proyectos/omarchy-uke
sha256sum build/android/flash-b/{boot-stock,init-boot-b-MAGISK,dtbo-b-stock}.img   # §B.1
sha256sum build/bootimg/boot-uke-k52L73.img   # a671d293… (par de vuelta)
sha256sum build/bootimg/s288-…adsp.img        # 02d403c5… (dtbo_a NO se toca en la ida)
sha256sum build/misc-zeros-4m.img             # bb9f8df6… (limpieza BCB post-vuelta)
ls -la ~/gpu-work/uke-rom-edl/uke_eea_global_images_OS3.0.303.0.WOZEUXM_16.0/images/
```

### D.2 Cómo VOLER a L73 después (la receta §3 del canonical está CADUCADA — usar esta)

1. **useradata primero** (si fue borrada): `fastboot flash userdata <rootfs-uke-k521.img>` con sha
   verificado ANTES (~35 s; esperar OKAY). Decide v7 (5f9f00fe, copia del repo) vs v8 (bd2b3029,
   `/var/tmp/rootfs-v8-backup-20261007.img`) — la doc más reciente de decisiones (BOOT-PKG-20261006,
   RUNBOOK-FLASH-FIX529) operaba con v8; la copia local del repo es v7.
2. **boot_a** ← `build/bootimg/boot-uke-k52L73.img` (a671d293): reutilizar
   `docs/historia/gates-palawan/flash-l73-gated.sh` (única escritura `boot_a` + `set_active a` + gates de batería +
   verificación SSH/kmsg; NOTA: sus gates de pantalla L73 fallarán en el primer boot hasta tener el
   rootfs arriba — para la vuelta basta flash+set_active+reboot, o editar los checks a no-fatales).
   **dtbo_a no se toca** (s288 debe seguir: verificar sha por lectura/`getvar`/lectura viva).
3. `set_active a` fresco (repone retry=7; si A ya activo: doble `set_active a`+`set_active b`,
   LV-R7) + `reboot`.
4. Post: `misc` a ceros 4 MiB si el BCB quedó sucio (Android escribe `bootonce-bootloader` que este
   ABL no limpia, #241) — ciclo aparte con fila propia; `uke-slot-check.sh fastboot` para contadores;
   ritual adsp.b40 (`42c86837…`) al primer SSH.
5. **Rollback ya registrado en #652** (ledger hermano): la deuda documental de ESTE repo es (a)
   nueva sección en `docs/historia/ESTADO-VIVO.md` con par/restauración y shas, (b) ACTUALIZAR
   `docs/guias/LINUX-A-ANDROID-IDA-VUELTA.md` §3 y `PLAN-recuperacion-dorada.md` (ambos apuntan a la dorada
   k49+s266 muerta), (c) dejar fila LV-R10 por cada flash y por el erase (el pre-registro vive ya en
   el ledger hermano, no en `PRE-REGISTRO-PANTALLA.md`, cerrado en #P52-NOTA).

### D.3 Scripts del repo que tocan particiones (no flashear por error)

- Solo `_a` (seguros de reusar como patrón): `flash-l59…l74-gated.sh` (boot_a), `flash-k49.sh`
  (boot_a+dtbo_a, CADUCO), `flash-k23b.sh` (boot_a; su comentario menciona boot_b solo como rescate),
  `ciclo-restaurar-slot-a.sh` (vendor_boot_a+init_boot_a+boot_a; «NUNCA TOCA boot_b NI dtbo_b»).
- Tocan `boot_b`/`dtbo_b` (históricos, con banner de REFUTADO/obsolescencia): `auto-flash-s233/s234/s236.sh`
  (dtbo_b, F5 era), `rescate-fastboot-pantalla.sh` (dtbo_b s238 + doble set_active), `check-session-b.sh`,
  `medir-avb.sh`, `diag-f1a.sh`. Ninguno pertenece a la era actual; NO reusar sin leer su cabecera.
- Solo lectura: `uke-slot-check.sh`, `backup-par-bueno.sh` (lee boot_b/dtbo_b con magic + sha).

## Limitaciones de este informe

- El estado retry/BCB/batería «HOY» solo lo certifica una medición en fastboot (no ejecutada: solo
  lectura); lo aquí escrito es lo último documentado (16-oct ~13:0x + ledger hermano).
- La búsqueda de la imagen de 370 MB cubrió ~ (prof. 5), /var/tmp y ~/gpu-work;
  no descarta una copia en un disco externo no montado ni dentro del tgz de otro proyecto hermano.
- El ledger hermano (#652 y resto) es ámbito del otro agente; aquí solo se cita como mando.
