# Revisión del kernel v7 (ledger #675) — 22-oct-2026, solo PC

Revisado: `.config`, parches, imagen, script de flash y procedimiento de módulos. **Veredicto: apto para pedir autorización, con los 2 riesgos residuales de abajo declarados.**

## Qué se comprobó (evidencia)
| Punto | Resultado |
|---|---|
| Parches | `0045` y `0046` presentes en `optim-ouke6/linux-7.2.9` (grep `UKE_CAMERA_IFE_SID` y `ldoc3`, en `build-v7.sh` y el repack); copia de `senemos-ouke6` |
| Config | v7 = base ouke5 + **56 símbolos**, todos en la lista permitida de `repack-senemos-v7.py` G0 (netfilter/nft/zram/TEO/rutas); **ningún `=y` degradado**, sin PSI, `MODVERSIONS` sigue off. `CRYPTO_ZSTD` y `ZSTD_COMPRESS` pasan de `m` a `y` (por eso 2 módulos menos). Ver diff completo en `build7/.config` vs `.config.base` |
| Opciones de cámara | `MEDIA`/`V4L2`/`I2C_QCOM_CCI` sin cambios (no están entre los 56) |
| Imagen | `Image` 50 698 752 B (+397 KB frente a v6 50 301 440); `image_size` 53 477 376 B, **margen 13,0 MiB (13 631 488 B)** bajo el techo de 64 MiB del ABL; banner `#7`, release `…-ouke5` |
| Boot | repack G0–G8 OK; `unpack_bootimg` OK; `flash-senemos-v7-gated.sh --check` OK (shas del boot, tarball v7, rollbacks v6…v1, DT) |
| Camino de flash | 1 escritura (`boot_a`), 0 a `dtbo_a` (gate estático); fastboot gates de v6 intactos (≥3700 mV, retry b ≥3, lector ACM único) + G10 de slot |
| Módulos propios | `nm -u` de los 13 `.ko` de audio/BT y los de cámara/tapa: **ninguno importa símbolos de red** (`init_net`, `net_generic`, `__dev_get_by*`, `skb*`, `nf_*`; las `v4l2_async_nf_*` de camss son de V4L2, no de netfilter) ⇒ el cambio de `struct net` (NF_TABLES, IP_MULTIPLE_TABLES) no les afecta. Riesgo que el ledger declaraba «no verificado» queda **acotado por evidencia** |
| Módulos del kernel | tarball v7: 1 134 `.ko` (32 nuevos: nf_tables, nft_*, xt_*, zram, zsmalloc; 2 menos). Se instalan **después** de arrancar v7 (`--post-modules`), nunca antes: con la misma release cargarían en el v6 vigente con otra disposición de `struct net` |

## Fallo encontrado y corregido en esta revisión
- `--rollback-modules` restauraba **todo** `lib/modules/<release>` desde la copia hecha en `--pre`: habría pisado con versiones antiguas los `.ko` de `extra/` y `updates/` que audio/BT/cámaras instalen entre `--pre` y el rollback. Ahora excluye `extra*` y `updates*` y solo restaura `kernel/` + `modules.*`. `--check` sigue OK.

## Riesgos residuales (no eliminables en el PC)
1. **Arranque**: si v7 no arranca, el rollback es `--rollback v6` (1 escritura, fastboot a mano). Sin flash no hay más evidencia; el cambio funcional de arranque es solo cmdline (`cpuidle.governor=teo audit=0`) + built-ins de ruta/zstd.
2. **`audit=0`**: desactiva auditd/`auditctl` del kernel; `uke-bootguard`, `systemd` y PAM no lo usan (sin reglas hoy). Si algo lo necesitara, `audit=1` en el siguiente boot.
3. **TEO** puede cambiar residencias de cpuidle (esperado a favor); medir con s2idle/drenaje antes y después (`deploy/optimizacion/medidas/`).

## Material nuevo junto a v7
- `deploy/optimizacion/zram/` (`deploy.sh check|apply|revert|status`): unidad `uke-zram` (swap de 4 GiB zstd, prioridad 100, `swappiness=100`, `page-cluster=0`). **Solo tras arrancar v7 y `--post-modules`**; gate `modinfo zram`. Sin aplicar.
- `deploy/optimizacion/medidas/`: los 5 scripts de medida con `selftest.sh` (29/29 en seco).

## Efecto del `-Syu` de userland previsto antes de v7 (systemd 262.1, mkinitcpio 42.2; ignorando `linux-aarch64` y `linux-firmware*`) — análisis del 22-oct
- **Initramfs / mkinitcpio: no afecta.** El initramfs (`uke-k34-fw-k52b2`, con `/ukeinit`) va **embebido en el Image** (`CONFIG_INITRAMFS_SOURCE` de la config, comprobado por G3 del repack); no se genera en la tablet. Al ignorar `linux-aarch64` no hay hook de mkinitcpio sobre un kernel. Tampoco se toca `/lib/modules/<release>` (ningún paquete lo posee): los módulos instalados y el backup del `--pre` sobreviven al `-Syu`.
- **systemd 262 con el kernel v7: compatible.** Su README (`v262`, medido hoy) pide kernel ≥5.10 (recomendado ≥5.14); v7 es 7.2.9. Las opciones de config que exige/recomienda (DEVTMPFS, CGROUPS, CGROUP_BPF, BPF_SYSCALL, FHANDLE, INOTIFY, SIGNALFD, TIMERFD, EPOLL, UNIX/NET, NET_NS, USER_NS, IPV6, AUTOFS_FS, SECCOMP(+FILTER), KCMP, TMPFS_XATTR/POSIX_ACL, BLK_DEV_BSG, DMIID) están **todas** en `build7/.config`. PSI solo lo usa `systemd-oomd` (opcional): v7 no lo activa.
- **`--post-modules`**: usa `depmod`, `modprobe`, `systemd-run`, `nft`. Tras el `-Syu` `kmod` seguirá siendo 34.x en el mirror y los módulos van sin comprimir (como ouke5); el script ahora **avisa en vez de fallar** si falta `nft`/`iptables-nft` (hay que bajar `nftables` e `iptables-nft` del mirror ALARM con `.sig` y `pacman -U`, tras mirar dependencias; los módulos del kernel ya están).
- **Ganchos de suspensión**: `system-sleep/uke-bt-sleep` y `systemctl suspend` siguen en systemd 262; los scripts de medida usan `systemd-run`/`systemctl` estándar. Revisar tras el `-Syu` que `uke-boot-ok.service`, `uke-bt` y `uke-audio` siguen activos (un `--post` de v6 los comprueba ya).
- **Orden recomendado**: `-Syu` (otro ciclo, dueño presente) → comprobar arranque en frío con v6 → **solo entonces** `--pre`, flash y `--post`/`--post-modules` de v7: así si algo falla se sabe a qué cambio atribuirlo (un cambio por ciclo).

## Revisión por subagentes independientes (22-oct) y qué se hizo
Tres revisores en solo lectura, sin conocer mis conclusiones (flash/repack, scripts de medida, config/deploys). Hallazgos aceptados y corregidos en el PC:
- **Flash v7**: G10 comprobaba `Successful=1` en toda la salida (daba verde por el slot b) → ahora parsea el **slot actual** con `qbootctl` sin `-a`; `--post-modules` ya no aborta si falla el último `cat` de zram; copia de seguridad de módulos **verificada** (`zstd -t` + sha) y `--rollback-modules` extrae a un directorio temporal y **no borra nada antes de validarlo**; `--pre` se niega si la tablet ya corre v7; mensaje de «Volver» corregido; G9 respeta `/etc/uke/no-bt|no-audio`; `nft_prueba` se borra siempre.
- **Residual aceptado**: tras `--rollback v6` la tablet arranca con módulos v7 en una release v6 hasta correr `--rollback-modules` (el script lo avisa en el mensaje de «Volver»). Riesgo bajo: nada del arranque autocarga netfilter/zram.
- **Config**: ninguna objeción; `iptables-legacy` **no** funcionará en v7 (solo iptables-nft/nft; las opciones `*_NF_*` de la rama legacy no entran porque `*_LEGACY` está off), 22 `.ko` propios sin símbolos de red (`nm -u`).
- **Userspace**: `coredump` recalibrado tras el resize (`MaxUse=512M`, `ExternalSizeMax=1G`, `KeepFree=2G`); `deploy.sh` ya no sobrescribe `antes.txt` en un segundo `apply`, el `revert` restaura `uke-fix.service` y `check` hace `bash -n`; `uke-zram` con `mem_limit` (75 %) y `Before=swap.target`. `SyncIntervalSec=5m` es el valor por defecto de systemd (lo grave se sincroniza igual): se anota, no se cambia.
- **Cifras**: margen del Image 13,0 MiB (no 13,6) y selftest 28/28.

### Tercer revisor (scripts de medida) — corregido
`medir-mic-ab.sh`: el `timeout` del ssh era igual a la duración del tramo (cortaba la llamada) → ahora tramo+ajuste+60 s; el %/h usaba 28,8 Wh → usa `charge_full`×3,9 V (≈34,5 Wh; 0,05 W ≈ 0,14 %/h) y avisa de que los W por corriente van ~20-24 % por encima del gauge; `poner`/trap ya no descartan errores (verifican el estado del micro tras cada cambio, abortan si no se pudo poner, avisan si no se restaura y se niegan a medir si no pueden leer el estado inicial); solo cuentan filas `Discharging`. `probar-refresco-bateria.sh`: el PASA exige **ver la transición** del cargador y mide la latencia. `medir-s2idle.sh`: el `check` ya no da OK con el script roto; el runner comprueba el rc de la suspensión y desarma la RTC si falla; mW a 4,2 V. `leer-journal-wifi.sh`: avisa si `root@uke` no responde (usar el USB). `selftest.sh`: tests más estrictos (3,88 %/h exacto, `rtcwake -m disable`, caso sin transición, estado del micro) → **29/29**. Sin corregir (menores): marcas de >2 días en `.csv.gz` en `medir-drenaje-uso.sh`, etiquetas con comas, gate de «sin cable al PC» de la carga rápida solo por host.
Aviso a audio: `mic-abierta.sh --revert` imprime «restaurada» aunque no exista la base (la cadena remota acaba en `echo`) y usa `HOSTIP` en vez de `UKE_HOST`.
