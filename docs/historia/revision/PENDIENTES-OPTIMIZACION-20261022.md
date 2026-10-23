# PENDIENTES de optimización — cierre de sesión (22-oct-2026)

Todo lo hecho está commiteado; la tablet no se toca desde este documento. Lo de la sesión batería (fusionada) está integrado: ver `docs/historia/revision/PENDIENTES-BATERIA-20261022.md` y `docs/historia/revision/OPTIMIZACION-PLAN-INTEGRADO-20261022.md`.

## Hecho (resumen, con evidencia en `docs/historia/revision/OPTIMIZACION-20261020.md` §3, §5, §6)
journald 150M + vacuum (746→114 MB), coredump recalibrado (512M/1G/2G libres), THP `madvise`, `systemd-homed` off, rtkit 0.14-2, plugins navidrome/hyprmoncfg fuera de la barra, `uke-fix.service` simplificado (**verificar en un arranque en frío que sshd arranca**), `/` ampliado 7,9 G→105 G tras `e2fsck` (backup `~/backups/uke-rootfs-20261020.tar.zst`, sha256 en su `.sha256`, 2,2 GB: borrable cuando el dueño quiera). Lint de comentarios en línea (systemd ≥262) en `deploy.sh check`.

## 1. Kernel v7 (ledger #675, PRE-REGISTRADO, sin orden del dueño) — en este orden
Material: `build/bootimg/boot-uke-senemos-7.2.9-v7.img` (sha `0f86cd77129ca643d97c6010fb8049cae2f807bedb82462228e492b6cb9650e4`), `build/gates/flash-senemos-v7-gated.sh` (`--check` OK), revisión en `docs/historia/revision/OPTIMIZACION-V7-REVISION-20261022.md` (3 revisores independientes; hallazgos aplicados).
1. **Turno de tablet + `bash flash-senemos-v7-gated.sh --pre`** (tablet en v6, SSH): deja el tarball de módulos v7 en `/root/v7-staging` y una copia **verificada** de los módulos actuales. No toca `/lib/modules`. Es la primera prueba real de los cambios remotos del script (backup y rollback no se han ejecutado nunca).
2. **Orden del dueño + fastboot a mano + cargador de pared**: `bash build/gates/flash-senemos-v7-gated.sh` (1 escritura `boot_a`; gates ≥3700 mV, retry b ≥3, lector ACM único; `uke-bootguard`/vigía apuntando a v6). Registrar en el ledger: mV, `getvar all` antes/después, retry-count.
3. `--post` automático (G1–G10) y luego `--post-modules` (instala módulos v7 + `depmod -a` completo + `nft`/`zram`). Verificar `qbootctl` (sin `-a`): slot actual `Successful: 1` tras `uke-boot-ok` (90 s).
4. **nftables e iptables-nft** (`pacman`, **pasándolos por la sesión gestora**, con `.sig` y comprobando dependencias): imprescindibles para probar `nft`/Tailscale TUN en el paso 3. Sin ellos `--post-modules` solo avisa.
5. Tras v7 estable: `zram/deploy.sh apply` (swap 4 GiB zstd, `mem_limit` 75 %); revertir con `zram/deploy.sh revert`.
Rollback: `--rollback v6` (`a9641556…9577`, 1 escritura) y **enseguida** `--rollback-modules` por SSH. Un cambio por ciclo; techo 3 ciclos por hipótesis. Siguiente ciclo posible (v8, solo con orden): `fw_devlink.sync_state=timeout deferred_probe_timeout=30` (0,1–0,4 W, riesgo medio) y `usb-psy-name`+`MaxPower`.

## 2. Medidas sin cable (scripts listos en `build/rootfs/deploy/optimizacion/medidas/`, `selftest.sh` 29/29; todos con `UKE_TURNO=1` y turno de tablet)
Medir s2idle y drenaje **antes y después de v7** (TEO cambia cpuidle). Necesitan al dueño: desenchufar (≥30–40 %), y para s2idle autorizar `modprobe qcom_stats` si se quieren residencias AOSD/CXSD.
- **M1 micro siempre abierto** (`medir-mic-ab.sh run`): A B A B con pantalla DPMS off; si ΔW > 0,05 W (~0,14 %/h) proponer al dueño dejar la base (`mic-abierta.sh --revert`). Corta el audio unos segundos por cambio; restaura el estado inicial. Hoy la tablet tiene la variante «siempre abierto» instalada (B).
- **B3 s2idle sin cable** (`medir-s2idle.sh arm 1800` → `report`): desenchufar antes; gancho `uke-bt-sleep` instalado.
- **B2 drenaje con uso real** (`medir-drenaje-uso.sh start|stop|report`), referencia 21-oct: 3,88 %/h (~25,8 h; pantalla 5 %/60 Hz 1,97 W; DPMS off 0,93 W).
- **B4 carga rápida** (`medir-carga-rapida.sh run 180`): <80 %, cargador de pared PPS 33 W, por Tailscale (no por el USB del PC).
- **B1 refresco en batería** (`probar-refresco-bateria.sh run 120`): ver desenchufar→60 Hz y enchufar→120 Hz con latencia (PASA solo con transición observada).
- **B5 modo carga**: `pureason` de un encendido normal por botón (`0x40010` = cargador; audio da `0x40001`); si coinciden, `forzar-escritorio`. **B6**: referencias Android sin medir (descarga limpia y carga rápida; requieren volver a Android, decisión del dueño; baja prioridad).

## 3. WiFi caído (21-oct 23:29): analizado, sin cambios
`docs/historia/revision/WIFI-CAIDO-20261021-ANALISIS-20261022.md`: NM recibió un SIGTERM externo a las 23:29:36 y nadie lo reinició (no fue un fallo); tormenta de D-Bus (2 139 avisos) ese arranque, 0 en el actual. Pendiente barato con turno: ver si `uke-wifi-nm.service` tiene `Restart=` y valorar `Restart=on-failure`/vigilancia de wlan0; identificar al emisor (¿prueba de otra sesión?). Avisos de regulatorio ath11k (`-22`) tras cada suspensión: benignos hasta ahora.

## 4. Otros pendientes de userspace (decisión del dueño)
- hypridle más corto (120/180/900 s; ~0,3–0,8 W en uso), visible: propuesta en `docs/historia/revision/OPTIM-USERSPACE-20261020.md`.
- Sondeo del táctil por IRQ/adaptativo (0,2–0,5 W): sesión táctil.
- Caché de pacman (274 MB, una versión por paquete): `paccache -rk1` no podó nada; limpiar tras el `-Syu`.
- Menores sin corregir de los scripts: marcas de >2 días en `.csv.gz` (`medir-drenaje-uso.sh`), etiquetas con comas, gate «sin cable al PC» de carga rápida solo por host.

## 5. Dónde está todo
Informes: `build/gates/revision/OPTIMIZACION-{20261020,KERNEL-PROPUESTA-20261021,PLAN-INTEGRADO-20261022,V7-REVISION-20261022}.md`, `docs/historia/revision/WIFI-CAIDO-20261021-ANALISIS-20261022.md`. Despliegues y scripts: `build/rootfs/deploy/optimizacion/` (`deploy.sh`, `zram/`, `medidas/`, `kernel/` con `ouke7.config`, `cmdline-propuesta.txt`, borrador de ledger). Flash: `build/gates/{flash-senemos-v7-gated.sh,repack-senemos-v7.py}`; build en `build/kernel-pokes/optim-ouke6/` (build7, ignorado por git). Ledger #675 en `~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md`.
