# Reglas permanentes de estabilidad (pacman/Omarchy) — uke, 22-oct-2026

Estado: **propuesta, NADA aplicado en la tablet.** Investigación en solo lectura. El acceso a la tablet se cortó a petición de la sesión de cámaras (ciclo 14) a mitad del análisis; lo que dependía de ella queda en «Pendiente de verificar en la tablet».

## 1. Hechos medidos (22-oct-2026)

- `/etc/pacman.conf` la posee **pacman 7.1.0** (`pacman -Qo`), con `backup=etc/pacman.conf` (%BACKUP% en la DB local). Un upgrade de pacman con el fichero modificado deja el nuevo en `pacman.conf.pacnew` y **conserva el local**. omarchy y omarchy-settings no lo empaquetan.
- Quien sí lo toca (scripts de `omarchy-4.0.6-1`, extraídos del .pkg de `~/backups/uke-qt612-20261022/`):
  - `omarchy-refresh-pacman` (`omarchy refresh pacman`): **sobrescribe entero** `/etc/pacman.conf` con la plantilla del canal y luego `pacman -Syyuu`. Es el único que destruiría `IgnorePkg`/`Include` puestos en `/etc/pacman.conf`. Deja `/etc/pacman.conf.bak`. Ofrece el hook de usuario `~/.config/omarchy/hooks/pre-refresh-pacman.d/` (ejecutado tras copiar la plantilla y antes del upgrade) pensado justo para añadir `IgnorePkg`/Include.
  - Migración `1791403252`: reordena secciones con awk preservando el prefijo (todo `[options]`), `cp -a` a `.bak` y luego `omarchy-update-system-pkgs`. Probado en el PC con la conf propuesta: **no la cambia** (cmp idéntico), el `Include` sobrevive. En la tablet no hay `[omarchy]`, así que el awk es no-op.
  - Migraciones `1787589206` y `1788112314`: solo `sed` sobre `[omarchy]` / `Server=`; no afectan a `[options]`.
- Comandos de Omarchy que hacen upgrade con la conf real (todos respetan `IgnorePkg`; ninguno pasa `--ignore`): `omarchy-update-system-pkgs` (`-Syu --noconfirm --overwrite '/usr/share/omarchy/*'`), `omarchy-refresh-pacman` (`-Syyuu`), `omarchy-reinstall-pkgs` (`-Suu`, permite **downgrade**), `omarchy-upgrade-to-quattro` (`-Syu`, `--overwrite='*'`, ver riesgo 4), `omarchy-update-keyring` (`-Sy` suelto: sincroniza DB sin upgrade, deja la DB «adelantada» pero no actualiza nada). `omarchy-update-aur-pkgs` usa `yay -Sua` (solo AUR/foreign: omarchy*, ttf-jetbrains…; `quickshell` no es foreign en la DB).
- El guard `00-omarchy-update-guard.hook` (`PreTransaction`, Upgrade, `AbortOnFail`) solo bloquea `pacman -Syu` **sin** `OMARCHY_UPDATE_PACMAN=1`/`OMARCHY_ALLOW_DIRECT_PACMAN=1`; no interfiere con IgnorePkg y **no protege** frente a `omarchy update`, que es justo el camino peligroso (exporta `OMARCHY_UPDATE_PACMAN=1`).
- Pacman 7.1.0 admite `Include` dentro de `[options]` y `IgnorePkg` con glob (`pacman-conf` lo expande: `IgnorePkg = linux-firmware*`; la simulación lo respeta).
- Timers del sistema (`systemctl list-timers`, 02:04): `systemd-tmpfiles-clean`, `fake-hwclock-save`, `uke-rtc-offset-save`, `shadow`, `archlinux-keyring-wkd-sync`. **Ningún timer actualiza paquetes ni Omarchy.** `archlinux-keyring-wkd-sync` solo toca el keyring (no pacman -Syu). Timers de usuario: 0 (comprobado con `systemctl --user` de root, sin sesión de omarchy; ver pendiente). `omarchy-migrate-notify.service` (usuario, al login, `WantedBy=graphical-session.target`) solo notifica migraciones pendientes; `omarchy-update-user-notify.service` en systemd es «not-found»/alias del anterior. El widget `SystemUpdate.qml` de la barra ejecuta `omarchy-update-available` (usa `checkupdates`, que copia la DB a un temp, no modifica nada; solo mira el paquete `omarchy`). Riesgo: la barra anima «hay update» y el dueño pulsa, lo cual lanza `omarchy update` → cubierto por IgnorePkg.

## 2. Reglas propuestas

Fichero nuevo `/etc/pacman.d/uke-hold.conf` (no empaquetado por nadie; `pacman.d/` ya contiene `mirrorlist` propio de Omarchy) y una línea en `[options]`:

```
# /etc/pacman.d/uke-hold.conf  (incluido desde [options] de /etc/pacman.conf)
# uke: kernel, firmware y mesa son propios o congelados; subirlos rompe arranque/WiFi.
IgnorePkg = linux-aarch64 linux-firmware* mesa quickshell
# firmware propio (gen71100, UKE-tplg, qca6750/wpss.*, ath11k/WCN6750 board/regdb)
NoUpgrade = usr/lib/firmware/qcom/* usr/lib/firmware/qca6750/* usr/lib/firmware/ath11k/WCN6750/*
```

y en `/etc/pacman.conf`, justo tras `HoldPkg = pacman glibc`:

```
Include = /etc/pacman.d/uke-hold.conf
```

Justificación de cada elemento:

- `linux-aarch64`: kernel real = boot.img de Android propio; el paquete (7.1.6) solo aporta `/boot/dtbs` y módulos que no se usan; subirlo ejecutaría hooks mkinitcpio/depmod sobre un `/lib/modules` ajeno.
- `linux-firmware*`: glob cubre los 12 instalados (`-whence`, `-amdgpu`, `-atheros`, … ) **y los paquetes nuevos que Arch vaya troceando** (en el mirror ya hay `-amd` y `-ti`, no instalados).
- `mesa`: congelado en 26.2.4 (el mirror ofrece 26.2.5); ojo: fijar mesa ≠ fijar sus dependientes; la simulación no muestra conflictos de dependencias.
- `quickshell`: **hallazgo de la simulación**: con `-Suu` (usado por `omarchy-reinstall-pkgs` y `omarchy-refresh-pacman -Syyuu`) pacman propone **bajar** `quickshell 0.3.2.r7.g2b4501a-1` (build propio) a `extra/quickshell 0.3.2-1`. Con `-Su` no. Hay que ignorarlo.
- `NoUpgrade`: si un paquete futuro entregase esos ficheros, pacman escribe `.pacnew` en vez de pisar el propio (con `IgnorePkg` ya no debería ocurrir; es cinturón y tirantes). Caveat: `NoUpgrade` solo actúa sobre ficheros que **ya existen** en el sistema; no impide que aparezcan ficheros nuevos ni borrados al eliminar un paquete.
- No se propone `NoExtract` (impediría instalar ficheros nuevos legítimos; ya hay protección por IgnorePkg) ni `IgnoreGroup` (los linux-firmware no están en grupo). `HoldPkg` no sirve: solo evita **desinstalar** (pide confirmación), no bloquea upgrades.

### Fichero a prueba de `omarchy refresh pacman`

Como `omarchy-refresh-pacman` reescribe `/etc/pacman.conf`, añadir el hook de Omarchy (se ejecuta como usuario con sudo caliente, ANTES del `-Syyuu`):

`~omarchy/.config/omarchy/hooks/pre-refresh-pacman.d/uke-hold` (ejecutable; el nombre sin `.sample`):
```
#!/bin/bash
CONF=/etc/pacman.conf
MARKER="Include = /etc/pacman.d/uke-hold.conf"
[[ -r /etc/pacman.d/uke-hold.conf ]] || exit 1
grep -qxF "$MARKER" "$CONF" && exit 0
sudo sed -i "0,/^HoldPkg.*/s||&\n$MARKER|" "$CONF"
```
(Pendiente de probar en la tablet; la plantilla stable/edge trae `HoldPkg = pacman glibc` en `[options]`, comprobado en `pacman-stable.conf`. La plantilla del canal además trae `Architecture = auto`, ``[omarchy]`` y `[multilib]`, que no sirven en aarch64: `refresh pacman` está de todos modos **desaconsejado** en la tablet.)

## 3. Comprobación (simulación en el PC, solo lectura)

DB real copiada de la tablet a las 02:04 (local 745 paquetes; sync core 21-oct, extra 22-oct 01:15) en `scratchpad/est/` (`mk.sh` adapta rutas y hace `pacman -Su --print`; `SigLevel=Never`, sin red, sin instalar nada):

| Conf | `-Su --print` |
|---|---|
| `/etc/pacman.conf` actual | 16 paquetes: `linux-aarch64 7.2.11-1`, 13 `linux-firmware-*` 20260916 (incl. `-amd`, `-ti` nuevos), `mesa 26.2.5-1` |
| actual + `IgnorePkg` directo con glob | vacío |
| actual + `Include` en `[options]` (la propuesta) | **vacío**; `pacman-conf` expande IgnorePkg (3-4 entradas) y los 3 NoUpgrade |
| propuesta con `-Suu` | vacío (sin `quickshell` en la lista, proponía el downgrade a 0.3.2-1) |
| lista explícita de 4 ignorados sin glob | deja pasar los 9 firmware restantes: **el glob es necesario** |

Sin errores de dependencias en ninguna variante. Sin efecto sobre instalaciones explícitas: `pacman -S mesa` (con o sin `--noconfirm`) **sí instala** la 26.2.5 (pacman solo pregunta; con `--noconfirm` el valor por defecto es sí). Lo mismo `omarchy-pkg-install`.

## 4. Aplicación y rollback (a ejecutar solo con el «libre» del gestor, un cambio)

```
# aplicar
install -m644 uke-hold.conf /etc/pacman.d/uke-hold.conf
cp -a /etc/pacman.conf /root/pacman.conf.pre-hold-20261022
sed -i '0,/^HoldPkg.*/s||&\nInclude = /etc/pacman.d/uke-hold.conf|' /etc/pacman.conf
pacman-conf IgnorePkg NoUpgrade          # debe listar 4 + 3
pacman -Su --print                       # debe quedar vacío (con DB sincronizada)

# rollback
cp -a /root/pacman.conf.pre-hold-20261022 /etc/pacman.conf; rm /etc/pacman.d/uke-hold.conf
```
Nota: `pacman -Su --print` no escribe; si hay que refrescar DB, hacer `-Sy` solo cuando lo autorice la sesión gestora (el `-Sy` suelto adelanta la DB). Tras instalar el hook de usuario: `chmod +x`, y probar con `bash -n`.

## 5. Más fuentes de inestabilidad

1. **`pacman -S` explícito de un ignorado** y `omarchy-upgrade-to-quattro` (`-Syu … --overwrite='*'` sobre `core_packages`): el nombre explícito ignora IgnorePkg. No ejecutar `omarchy upgrade-to-quattro` ni `omarchy-reinstall-pkgs` en la tablet; queda en el informe como «no ejecutar».
2. **Migraciones sin ejecutar (14)**: `omarchy migrate` las aplica; las que llaman a `omarchy-update-system-pkgs` (1791403252) están cubiertas por IgnorePkg. Revisar cada una antes (ver `QT612-IMPACTO-…`).
3. **systemd 262 rechaza comentarios al final de línea** (`Clave=valor  # …`). Búsqueda en `build/rootfs/deploy` (fuentes del repo): no queda ningún caso en `.service/.conf/.rules`; los 6 hallazgos de `grep` son comentarios finales en scripts de shell/Python (`uke-bt-resume`, `uke-autorotate`, `uke-bateria-lectura`) y un parche C: son válidos en shell/Python, **no** son ficheros de unidad. **Pendiente de verificar en la tablet** (sin acceso): `/etc/systemd`, `/etc/tmpfiles.d`, `/etc/sysctl.d`, `/etc/modules-load.d`, `/etc/udev/rules.d`, `~omarchy/.config/systemd` y ficheros de drop-in/units que NO viven en el repo (p. ej. los de paquetes de Omarchy). Sugerencia de comando de solo lectura para cuando se libere: `grep -rnE '^[[:space:]]*[A-Za-z][A-Za-z0-9._-]*[[:space:]]*=[^#"'"'"']*[[:space:]]#' /etc/systemd /etc/tmpfiles.d /etc/sysctl.d /etc/modules-load.d ~omarchy/.config/systemd /usr/lib/systemd/system 2>/dev/null` y `systemd-analyze verify` sobre las `uke-*`. (sysctl.d/tmpfiles.d/modules-load.d/udev admiten `#` solo al inicio de línea desde hace años; el riesgo real está en `Clave=` de units/conf de systemd.)
4. `omarchy-update-keyring` hace `pacman -Sy` suelto: si la sesión gestora lo ve, la DB se adelanta pero no se actualiza nada; no es un riesgo de por sí.

## 6. Pendiente de verificar en la tablet

- `pacman-conf IgnorePkg` tras aplicar, y que `pacman -Su --print` salga vacío con la **DB sync de ese momento** (la simulación usó la copia de las 02:04).
- Que `/etc/pacman.d/` y `~omarchy/.config/omarchy/hooks/pre-refresh-pacman.d/` existen con esos permisos (el hook de usuario no está probado).
- Lista real de `.sample`/hooks que ya existan; timers de usuario con la sesión de omarchy activa; el barrido de comentarios del punto 5.3.
- Que `NoUpgrade` con esos globs coincide con las rutas reales (`/usr/lib/firmware/qcom` etc., que no pude listar en la tablet); `pacman -Ql linux-firmware*` en la tablet no se pudo cotejar. En la DB local del PC la salida de `-Ql` con el filtro `qcom|qca6750|WCN6750` solo mostró `/boot/dtbs/qcom` de linux-aarch64, o sea que **los ficheros propios de firmware no pertenecen a ningún paquete** (consistente con estar sin dueño; hay que confirmarlo en la tablet).
- Riesgo residual: un `-Suu`/`-Syyuu` con `--overwrite='*'` (quattro) ignora NoUpgrade para esos ficheros.
