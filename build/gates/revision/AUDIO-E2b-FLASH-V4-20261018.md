# AUDIO — E2b: flash del kernel v4 (ouke4) — 18-oct-2026 ~15:2x — PASA (23/24 gates, el 24º resuelto)

Orden del dueño: «Flashea v4 ya e instala los módulos ouke4 por USB/SSH tras el arranque». Ledger #661 (resultado escrito, sin commit en el repo hermano).
- Fastboot (manual del dueño): 3895 mV, slot a, retry a=7 b=6; lector ACM único armado; `flash-senemos-v4-gated.sh` sin argumentos: 1 escritura (`boot_a`), `set_active a`, reboot.
- **boot_a releído == `fc9309a3…`; dtbo_a == stock `27e61d21…`**; `uname -r` = `7.2.9-senemos.1.4054.3-ouke4`; SSH por USB a ~1 min.
- **Desvío del procedimiento (declarado):** el `--pre` no se había hecho (la tablet estaba ya en fastboot). Consecuencia medida: al arrancar sin `/lib/modules/…-ouke4`, `uke-carga`, `uke-wifi`, `uke-bt` fallaron y `uke-touch` no ligó (autoload sin modules.alias).
  Recuperación por SSH: tarball + `uke_audio_e2/e2b.ko` + depmod (1106 .ko), `uke-carga`, `uke-wifi`, `udevadm trigger` (spi0.0 → `uke-touch` activo), `uke-desktop` reiniciado (el G3 de `--post` para sddm).
- Gates (`build/logs/senemos-post-20261018-152709.txt`): 23 PASA / 1 FALLA (uke-touch, ya activo). Sin faults/rechazos de SMMU, GPU enlazada, `renderD128`, underrun 0, ADSP running (recovery disabled), WiFi, desktop.
- Efecto sobre el audio: **aún no probado**. Siguiente (autorización aparte): `pacman -S libyaml`, instalar `fastrpc-uke-a56e9d4d.tar`, `insmod uke_audio_e2b.ko`, `modprobe fastrpc`, `uke_audio_e2.ko`, `systemctl start adsprpcd_audiopd`, con vigía y doble captura.
- Pendiente BT: `uke-bt.service` failed hasta que la sesión BT instale sus `uke_bt_*.ko` ouke4. Rollback disponible: `--rollback v3` (módulos ouke3 intactos).
