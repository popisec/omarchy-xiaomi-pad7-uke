# uke-tapa — cerrar la funda = suspender (hall → gpio-keys)
Overlay `dts/uke-tapa.dtso` (nodo `/soc/uke-hall`, gpio-keys sobre TLMM 99=SW_LID y 100=SW_TABLET_MODE, activo-bajo, wakeup-source),
cargado en caliente por `uke_tapa.ko` (cargador genérico de `../bt/module/uke-ovl.h`). Informe: `build/gates/revision/TAPA-HALL-20261018.md`.
- `./build.sh [--live-dtb F]` compila dtbo + ko y pasa el gate fdtoverlay (base y vivo).
- `./deploy.sh` plan | `--check` | `--install` (ko, drop-in logind, servicio; sin cargar) | `--load` | `--arm` (enable) | `--revert`.
- Reversa inmediata: `ssh … rmmod uke_tapa`. Interruptor de arranque: `touch /etc/uke/no-tapa`.
- Input llamado `uke-hall` (NO "Lid Switch": el Omarchy liga ese nombre a omarchy-system-lid-close, que bloquea).
- Variante horneada (futuro flash, SIN flashear): el mismo fragmento como nodo hijo de `/soc` en el dtbo; `tlmm` phandle 0x16b.
