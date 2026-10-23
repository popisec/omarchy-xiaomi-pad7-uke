# PENDIENTES — 14-oct-2026 (~21:3x, solo lectura, sin USB)

Hito actual: **escritorio Omarchy iluminado** (greeter sddm visible + luz KTZ + sesión sin OOM).
Tablet NO alcanzable (DESKTOP-OMARCHY-REVISION §5: USB disconnect 20:37, ping 100% loss).

## YA HECHO HOY (no duplicar)

- H1: causa luz = KTZ8866 PWM_ENABLE, confirmada en vivo (flip 0x53→0x52 + brillo). `KTZ-PWM-ENABLE.md:70-79`.
- H2: muerte del commit resuelta (fix SMMU A1b, L52). `docs/historia/ESTADO-VIVO.md:63-70`.
- L53/L54 medidos (KTZ idéntico; raíles descartados), L55 superado/revertido. Ledger #628–#631.
- L56 artefacto `3e68abe8…` + L57 `ebe94093…` construidos y gateados; D16 aprobado (ledger #632–#633).
- Escritorio: plumbing listo (home alarm, configs, autologin, disco 97%, uke-dump parado). Ledger #632.
- Auditorías A/B: `DESKTOP-OMARCHY-REVISION.md`, `KERNEL-CONSOLIDADO.md`.

## (1) Kernel / flash inmediato

1. **Terminar build L58 + repack + pre-registro.** Build en vuelo (0×DONE 21:0x; Image stale). Evidencia: `docs/historia/revision/PIPELINE-PANEL-20261014/CRITICA-L58.md:7-16`. Acción: esperar `DONE k52L58-BUILD-OK`, exigir `mtime(Image.gz)>mtime(.config)`, clonar `repack-k52L57.py` con gates zram nuevos (`docs/historia/revision/PIPELINE-PANEL-20261014/CRITICA-L58.md:29-42`), pre-registrar sha ANTES de flashear. **Alta. BLOQUEA.**
2. **Flash L58 (cold boot) + verificar luz desde probe.** Evidencia: `CRITICA-L56.md:40-44`; ledger #632 (criterio PASA = luz ~5 s). Acción: `flash boot_a` + `set_active a` + reboot; `dmesg|grep -c UKE-L56` → 2; sysfs `2-0011` 0→4095 visible. Rollback L54 `1d641e63…`. **Alta. BLOQUEA.**
3. **Verificar RAM completa + DMA.** Evidencia: `L57-MEM.md:28-35`. Acción: `grep MemTotal /proc/meminfo` (≈7,x GB) + `dmesg|grep -iE "swiotlb|ath11k.*(error|fail)"`; doble captura (consola + `dmesg -w`). Riesgo: wifi/DMA en RAM alta sin `mem=`. **Alta. BLOQUEA.**
4. **Activar swap zram 4G lz4.** Evidencia: `KERNEL-CONSOLIDADO.md:13-23`; `docs/historia/revision/PIPELINE-PANEL-20261014/CRITICA-L58.md:44-59`. Acción: unit oneshot `zram-swap.service` (`zramctl --find --size 4G --algorithm lz4` + mkswap/swapon -p 100), `enable`, verificar `/proc/swaps` + `comp_algorithm=[lz4]`. **Media. No bloquea** (red de OOM con RAM completa).

## (2) Userspace / escritorio

5. **Journal de la sesión: comandos live pendientes.** Evidencia: `DESKTOP-OMARCHY-REVISION.md:49-55`. Acción (con enlace): `journalctl -b _UID=1000`, `grep -i oom -B3 -A3`, `ps … --sort=-rss` a +4/+8/+12 s, `hyprland.log|grep -iE 'monitor|commit|render|drm'`. **Alta. BLOQUEA la verificación** (orden de víctimas OOM no verificado).
6. **Mesa/freedreno: chipid `0xffff43030b00` fuera de tabla → llvmpipe.** Evidencia: `KERNEL-CONSOLIDADO.md:31-37` (medido 11-oct `fd_pipe_new2: unsupported GPU id 0x0`). Acción: turf del otro subagente; en tablet: `eglinfo -B|grep -i renderer`, `ls -l /dev/dri/`. **Alta. BLOQUEA el render real** (greeter va, Hyprland exige GLES).
7. **`omarchy.desktop` de `/usr/local` hecho a mano.** Evidencia: `DESKTOP-OMARCHY-REVISION.md:10-12,66-72`. Acción: `cat` + comparar con `hyprland-uwsm.desktop` del stage; hornear el bueno en el overlay. **Media. No bloquea** (la sesión arrancó).
8. **`udiskie` ausente del stage (autostart falla en silencio).** Evidencia: `DESKTOP-OMARCHY-REVISION.md:69-70`. Acción: añadir al stage o quitar la línea de `autostart.lua`. **Baja. No bloquea.**

## (3) Hardware

9. **WiFi ath11k: reset silencioso ~7,33 s (F3).** Evidencia: `F-plan-por-fases.md:743-748`; staging firmware OK (#434). Acción: `medir-wlan-reset.sh` (kretprobes bus-vs-firmware) en vivo; vigilar tras L58 (RAM alta). **Media. No bloquea el hito** (bloquea SSH/red sin cable).
10. **Batería invisible desde Arch (solo `fastboot getvar`).** Evidencia: `NOTAS-OMARCHY.md:803-861` (faltan `qrtr_smd` + firmware ADSP). Acción: ninguna (deuda de imagen, no camino crítico); medir siempre en fastboot antes de escribir. **Media operativa. No bloquea.**
11. **Táctil NT36532 / lápiz / libwacom (F4/F7), audio WCD939X, cámara, bluetooth.** Evidencia: `F-plan-por-fases.md:150-158,718+` (F3–F4 no empezados en este linaje); `KERNEL-CONSOLIDADO.md:38-42` (wcd/sdw `=m` presentes, sin cambios). Acción: tras escritorio vivo: `/dev/input`, `libinput list-devices`, `dmesg|grep -i nt36`. **Baja (lápiz: media a futuro). No bloquean.**

## (4) Recuperación / brick

12. **Hemorragia de slot: sin `qbootctl`, cada arranque gasta reintento (`Successful: 0`).** Evidencia: `NOTAS-OMARCHY.md:790-792` (riesgo nº1). Acción: decisión de dueño pendiente (ejecutar `qbootctl` o marcar éxito por slot); leer `getvar all` (4 contadores) antes/después de cada ciclo. **Alta operativa. No bloquea el hito inmediato.**
13. **Watchdog muerto (R-42): un cuelgue exige reset físico.** Evidencia: `NOTAS-OMARCHY.md:794`; `F-plan-por-fases.md:466-470`. Acción: cargador de pared + ≤2 escrituras/día + vigía fastboot al par bueno. **Media. No bloquea.**
14. **Gates dtbo (`fdtoverlay` + `uke-dtbo-check.py`) antes de cada flash de dtbo.** Evidencia: docs/historia/AGENTS.md regla 1; `F-plan-por-fases.md:533`. Acción: proceso, sin dtbo pendiente hoy (s287 se queda). **Media proceso.**
15. **e2fsck/ext4 y `misc` BCB.** Sin evidencia nueva hoy; proceso estándar pre-flash. **Baja.**

## (5) Docs

16. **Informes H (backup/restauración) e I (lápiz) sin escribir.** Evidencia: `docs/historia/G-auditoria-documental.md:531-532,622` (§6-quinquies: siguen pendientes). Acción: H = política + `backup-par-bueno.sh`; I = cadena NT36532→app. **Media-baja. No bloquean.**
17. **Operativa de recuperación fastboot/brick (resto de k).** Evidencia: `docs/historia/G-auditoria-documental.md:593-595`. Acción: añadir a F §5 o anexo de H. **Baja. No bloquea.**
18. **G §6 menores restantes: 13 (playlist 1.23.0), 15 (commit pinneado plugin), 28 (re-mediciones 14 días: `edge` 148 pkgs caduca ~10/14-oct).** Evidencia: `docs/historia/G-auditoria-documental.md:561-578,632`. Acción: re-`curl` del `.db` + anotar. **Baja. No bloquean.**

## Resumen: los 5 pendientes más importantes (en orden)

1. **Terminar y gatear L58** (build DONE + repack con gates zram + pre-registro ledger) — sin esto no hay flash.
2. **Flashear L58 y verificar luz desde el probe + sysfs** (UKE-L56 ×2) — cierra el hito de luz persistente.
3. **Verificar `MemTotal` ≈7 GB + sesión Omarchy sin OOM** (journal + top RSS) — cierra el hito de escritorio.
4. **Mesa/freedreno chipid** (salir de llvmpipe) — único bloqueo estructural restante del render.
5. **`qbootctl` / hemorragia de slot** — riesgo nº1 del proyecto; decidir antes de que un contador llegue a 0.
