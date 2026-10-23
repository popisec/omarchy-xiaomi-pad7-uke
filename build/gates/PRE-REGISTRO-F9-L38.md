# PRE-REGISTRO F9/L38 — flash pendiente: reset del panel a 15 ms del vendor

> **F9 ejecuta el artefacto L38, ya construido y verificado. NO existe ningún build L39,
> y construirlo ahora violaría "un cambio por ciclo"** (apilaría una variable sin probar
> sobre otra sin probar). L38 está pre-registrado (F8), construido (`DONE L38-BUILD-OK`
> 12-oct 20:33), verificado dos veces (report del repack + verificación independiente
> 13-oct 00:2x, abajo) y **nunca flasheado** (no hay `out/diag-L38`, no hay entrada de
> resultado en NOTAS). Este F9 es su hoja de ejecución.

## Artefacto (ya existe, verificado, no reconstruir)

| | |
|---|---|
| Imagen | `build/bootimg/boot-uke-k52L38.img` |
| **sha256** | `338d921cb6203a65938d6fd598186c1ceb9fc3e63cab8b238b7ce0e75e03ba73` |
| Tamaño | 100663296 B |
| Kernel (Image.gz) | sha `a159c8d7e20c5589987da70e75f8bf204c3beb4ef24833427928943d7c61b7ae` |
| dtbo (sin tocar) | `build/bootimg/s275-boot-dtbo-gpu-display.img`, sha `67a65bc161b6…` |

Verificación independiente 13-oct 00:2x (kernel extraído del boot.img, `gunzip`, conteo
en el binario crudo de 41556480 B — NO sobre el `.gz`, donde todo da 0):

| marca | L38 | esperado (F8) |
|---|---|---|
| `L37-pps-pack` / `send` / `done` | ×1/×1/×1 | ×1 |
| `L38: 100->15ms` | ×1 | ×1 |
| `L36-timing-flush-retirado` | ×1 | dentro |
| `wait for video done timed out` | ×0 | ×0 (early-return L36 dentro) |
| `L34-timing-flush` | ×0 | retirado |
| `msm_fbdev_driver_fbdev_probe` | ×0 | fbdev ausente |
| `UKE-POKE` | ×113 | intactas |
| `K48-w4-done` | ×1 | presente |

Report del repack: `build/bootimg/repack-build/bootimg/boot-uke-k52L38-report.txt`
(G0–G8 verdes). Build: `build/logs/build-L38.log` (`DONE L38-BUILD-OK`).

## Cmdline exacta (585 B, byte-idéntica a L37, extraída del header v4)

```
mem=2048M rdinit=/ukeinit panic=10 memmap=0x1A12800$0xE3940000 hung_task_timeout_secs=20 hung_task_panic=1 watchdog_thresh=10 console=ttyGS0,115200 fw_devlink=permissive clk_ignore_unused pd_ignore_unused arm-smmu.disable_bypass=0 arm_smmu.uke_smr_max=0 arm_smmu.uke_keep_boot=1 arm_smmu.uke_attach_log=2 arm_smmu.uke_reset_mask=12 memmap=0x2B00000$0xE3940000 loglevel=4 msm.uke_gmu_shared=0 arm_smmu.uke_kgsl_keep=0 hung_task_panic=0 printk.always_kmsg_dump=0 plymouth.enable=0 msm.uke_s3_stage=3 msm.uke_rescue=1 msm.uke_probe_hold_ms=5000 systemd.mask=sddm msm.uke_skip_mdss_reset=1
```

Sin `video=` (sin `DRM_MODE_FORCE_*`) · sin `fbcon`/`console=tty0` · con
`systemd.mask=sddm` (generador: el sistema **se recupera solo** tras una muerte —
ya no hacen falta ciclos de recuperación manual) · con `msm.uke_skip_mdss_reset=1`.

## La variable (una sola, efectiva, contra L36)

```c
/* panel-xiaomi-o82-dualdsi.c:294, verificado en k52L33-tree */
- usleep_range(100000, 101000);   /* r7: discriminador temporal */
+ usleep_range(15000, 15100);     /* vendor: (0,10),(1,3),(0,3),(1,15) */
```

Línea base válida: **L36** (murió en `K48-w4-done`, ACM 98 s). Las PPS de L37 nunca
se ejecutaron (muerte anterior) ⇒ el reset es la única variable efectiva del ciclo.
Si el reset pasa, las PPS corren por primera vez (segunda variable *aguas abajo*,
lectura cubierta en la tabla).

## Preflight (MEDIR en el momento del flash — la tablet está ausente ahora)

- [ ] Batería `fastboot getvar battery-voltage` ≥ **3700 mV**. Último valor conocido:
  **3555 mV** (bajo gate) ⇒ **cargador de pared antes de flashear**, y en fastboot no carga.
- [ ] `fastboot getvar all`: anotar los 4 `slot-retry-count` antes y después.
  Último conocido: `a=3` (tras el envenenamiento de L33). Si `a` está alto, el flash
  sigue siendo recuperable por el mask de sddm, pero cada muerte gasta slot.
- [ ] Lector ACM armado **antes** del reboot (un solo lector; sin lector el `write()`
  del kernel bloquea y el diagnóstico se pierde).
- [ ] `fastboot flash boot_a … && fastboot set_active a && fastboot reboot`
  (**`set_active a` SIEMPRE** — sin eso el ABL cae al slot B).

## Procedimiento tras el boot

1. SSH a `192.168.42.129` (`-i build/rootfs/uke-arch-root`) a los ~20 s.
2. Lanzar `diag-watch-ssh.sh` por SSH con `setsid` (**el embebido se atasca tras
   switch_root**). **Segregar ficheros por boot** (no mezclar arranques: el RTC no
   está puesto y en L37 se leyó el fichero equivocado).
3. `dmesg -n 7` antes de cualquier afirmación de ausencia.
4. Trigger con Hyprland-direct al **modo preferido** (NO forzar 60 Hz — no existe;
   el panel declara 120/144 Hz; L35/L36 usaron un modo inexistente):
   `monitor=DSI-1,preferred,auto,1` + `WLR_BACKENDS=drm WLR_RENDERER=pixman` +
   `--i-am-really-stupid` (root lo exige). `systemd.mask=sddm` es generador: **no
   intentar `unmask` en caliente** (imposible) ni arrancar sddm.
5. Doble captura obligatoria: ACM + `dmesg` SSH. **ACM es lossy**: "0 marcas" =
   "sin dato", nunca "sin evento".

## Tabla de lectura pre-registrada (decidida ANTES del flash)

| Resultado | Lectura |
|---|---|
| **Pasa `K48-w4-done`, llega `L37-pps-*` / `cmd#0` / DCS** | El reset-15 ms movió el punto. El bloqueo era el release2. Siguiente: leer si las PPS se envían bien (primera ejecución real) y qué pasa después |
| **Sobrevive y hay imagen** | Reset era el bloqueo + PPS necesarias. Pantalla. Verificar modo/fps y pasar a FASE 3 del ROADMAP |
| **Sobrevive pero sin imagen** | El reset era el bloqueo; el freno ahora es otro (orden del motor, máscara de error, bpc=10). Gap-list G4/G5/G8 |
| **Sigue muriendo en `K48-w4-done` (doble captura, modo preferido)** | Los 15 ms no son la causa. Ojo ACM-lossy: el punto real puede ser otro. Siguiente: G1 (skip VBIF redefinido) o H1-débil (`HS_TIMER_CTRL ← 0x4BB80`) |
| **Muerte pre-SSH / boot envenenado** | `systemd.mask=sddm` debe recuperar solo al siguiente boot. Si no: recuperación manual (abajo). Cada intento cuesta slot, no solo flash |

## Recuperación (verificada: ficheros presentes, shas coinciden)

```
fastboot flash boot_a build/bootimg/boot-uke-k52L25-diag.img   # sha e2c2ccc54520… ✓ presente
fastboot flash dtbo_a build/bootimg/s275-boot-dtbo-gpu-display.img  # sha 67a65bc161b6… ✓ presente
fastboot set_active a ; fastboot reboot
```

## Por qué L38 y no otra cosa (ni FASE 1, ni L39 nuevo)

- **ROADMAP FASE 1a/1c (sembrar SRC): REFUTADAS con código + medición.** `dpu_kms.c:1304-1308`
  (`dev_pm_opp_find_freq_floor(ULONG_MAX)` + `dev_pm_opp_set_rate`) corre en `kms_init`
  (`msm_kms.c:294`) **antes** que `hw_init` (`msm_kms.c:307`); la tabla OPP tiene techo
  514 MHz (`palawan.dtsi:3464`); medido en vivo SRC a 514 MHz. `parked_cfg=0` es falso.
  Sembrar otra vez sería s280 con otro disfraz (1 build + 1 flash + 1 slot a la basura).
- **La muerte del bind (~4 s) que FASE 1 atacaba YA NO EXISTE**: era el commit automático
  de `drm_fbdev_emulation`, muerto con L33 (`CONFIG_DRM_FBDEV_EMULATION=n`,
  `msm_fbdev_driver_fbdev_probe` ×0 verificado). El boot llega a SSH a los 20 s.
- **La muerte viva está en el commit, en el reset del panel**, y 100→15 ms es la **única
  divergencia del vendor** en toda la secuencia (verificada en `.ko` + árbol; todo lo
  demás audita idéntico). Es el cambio de una variable más limpio disponible.
- **Advertencia honesta**: L33-con-100 ms llegó MÁS lejos (`cmd#0` + `video-done timeout`)
  que L34+ (`w4-done`), así que el sleep no explica solo la regresión L33→L34 (el flush
  la movió; retirado en L36 sin recuperar el alcance, pero L36/L37 solo tienen ACM lossy
  + modo 60 Hz inexistente ⇒ su punto de muerte es BLANDO). L38 se lee contra L36 con
  modo preferido + doble captura, no contra L33.
