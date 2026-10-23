# ATAQUE-OMARCHY-OFFLINE — frente escritorio/actualización sin tablet (17-oct-2026, noche)

Objetivo F6 (sesión Omarchy) + F8 (`omarchy update` sin abortar). Sin tablet accesible;
todo verificado contra `build/stage-escritorio/` (pkgs 11-oct) y ledger hermano (solo lectura).
NO se editó ningún fichero existente; artefactos nuevos en `artifacts/omarchy/`.

## 0. Mecánica real (medida, no supuesta)

- `omarchy update` = `update-requires-free-space` → prune → `snapshot create` (sin snapper:
  exit 127, tolerado) → `update-dev` → `update-keyring` → **`update-system-pkgs`
  (`pacman -Syu`)** → **`omarchy-migrate`** → hook post-update → aur → mise → orphans →
  analyze → status → `update-restart`. Fuente: `omarchy-4.0.4-2/usr/bin/omarchy-update:28-63`.
- `omarchy-migrate` corre cada `/usr/share/omarchy/migrations/*.sh` sin marcador en
  `~/.local/state/omarchy/migrations/<fichero>` con `bash -euo pipefail`, y él mismo lleva
  `set -euo pipefail`: **el primer fallo aborta la tanda, no deja marcador y se reintenta en
  cada login/update**. Fuente: `usr/bin/omarchy-migrate:88-97`.
- **Sellado oficial**: el paquete trae las 106 semillas en
  `etc/skel/.local/state/omarchy/migrations/` → un usuario NUEVO nace con todo marcado.
  El `alarm` de la uke es anterior a las semillas ⇒ 106 pendientes (ledger #634). Sellar =
  crear el marcador (misma semántica que upstream, sin puentear nada).
- 106 migraciones en pkg (contadas del tarball) = las "106 pendientes" del ledger. Las
  128 de docs/informes/A-port-omarchy-aarch64.md:63 corresponden a un commit anterior; el número vigente es 106.

## 1. Clasificación (detalle en `artifacts/omarchy/migrations-uke-lists.txt`)

- **SELLAR 1**: `1781984677` (snapper normalize). Sin `/etc/snapper/configs/root` fuerza el
  repair vía `install/config/snapper.sh`, que exige binario snapper ausente (y rootfs ext4):
  **fallo seguro → atasca migrate + cada update**. Es el único killer confirmado.
- **EJECUTAR ~25** (resuelven en ALARM extra u `omarchy.db` edge/aarch64 del 11-oct, 178 entradas):
  todos los `omarchy-pkg-add` de migraciones resuelven (mpv-mpris, dua-cli, udiskie,
  cups-pk-helper, ddcutil, lsp-plugins, libvips, qrencode, qt6-imageformats, yt-dlp, zbar,
  sof-firmware, vulkan-intel, networkmanager, herdr, omacalc, tensaku, ttfx, libfprint-git,
  mise-bin, quickshell-git…). `paru` no existe en ningún repo pero **ninguna migración lo usa**
  (AUR va por `yay`, presente en edge). Queridas en uke: `1782002156` (NM enable),
  `1784568652` (mask NM-wait-online), `1784914435` (wifi powersave off), `1781793381` (udiskie,
  que DESKTOP-OMARCHY-REVISION §6 echa en falta). Vigilar: `1784672586` (cambia a
  quickshell-git; `1787399318` lo revierte luego al empaquetado — orden temporal, compatibles),
  `1788124236` (sshd hardening con patrón `skip()`+exit 0, no bloquea; **verificar
  `authorized_keys` de alarm antes**: la tablet vive del SSH por NCM).
- **NOOP ~80** por guardas verificadas en fuente: `1789325478` (`uname -m==x86_64 || exit 0`),
  `1789444024` (solo si kernel presente), T2/Broadcom/NVIDIA/Limine (`lspci` en condición `if`,
  `omarchy-cmd-present limine-mkinitcpio || exit 0`, guards de fichero), `1784809452`
  (`command -v snapper || exit 0`), `1784401744` (array hw vacío en Qualcomm), `1782049344`
  (`rm -f` + `|| true`). Resto: config de usuario sin deps de arch.

## 2. Wrappers (borradores en `artifacts/omarchy/`, NO instalados)

- (a) `omarchy-pkg-add-tolerant.sh`: clasifica por `pacman -Q` (instalado) / `pacman -Si`
  (en repos) / resto (skip con aviso, exit 0); UNA transacción para los instalables; fallo
  real de pacman → exit 1. Límite: DBs obsoletas hacen parecer "irresoluble" lo nuevo
  (aviso pide `pacman -Sy`). Instalación prevista: `/usr/local/bin` por precedencia PATH,
  `/usr/bin` intacto (A §7 lección 5).
- (b) `omarchy-update-restart-uke.sh`: si `/usr/lib/modules/$(uname -r)` existe pero ningún
  paquete lo posee → kernel externo (boot.img), omite el prompt con aviso; si un paquete
  posee módulos de otra versión → prompt (caso futuro linux-aarch64). Resto verbatim.
- (c) `seal-migrations-uke.sh`: ejecuta cada pendiente aislada (fallo no aborta tanda),
  sella solo la lista SELLAR con motivo en log, `--pending/--dry-run/--verify`. Uso como
  `alarm` con sudo caliente.

## 3. Checklist primer `omarchy update` por NCM/USB (con red, sin WiFi)

Pre (PC): `build/gates/uke-ssh.sh` con enlace a 192.168.42.129; `df /` en tablet ≥10 GiB
libres o `update-requires-free-space` aborta (bypass solo `OMARCHY_UPDATE_FORCE=1`).
G0 tablet: `slot-retry-count:b`≥3, batería ≥3700 mV, consola ACM con lector único.
G1 DBs: `pacman -Sy` + `pacman -Si herdr quickshell-git` resuelven (edge/aarch64 vivo).
G2 sellado: `--dry-run`, luego run; exige fallidas=0 salvo reintento manual (las OK ya
tienen marcador, no re-correr todo). G3 update: `omarchy update -y` (no interactivo; con
TTY y tiempo, sin `-y` para ver prompts de conflicto `--ask`); NUNCA `pacman -Syu` directo
(guard `00-omarchy-update-guard.hook` AbortOnFail; bypass `OMARCHY_ALLOW_DIRECT_PACMAN=1`
solo para `-S <paquete>` puntuales, jamás `-Su`). NUNCA `omarchy refresh pacman`
(reescribe `pacman.conf` con plantilla que incluye `[multilib]` x86-only; personalizar vía
hook `~/.config/omarchy/hooks/pre-refresh-pacman.d/`, patrón `add-custom-repo.sample` de
omarchy-settings). Avisos esperados no fatales: `archlinux-keyring` "target not found"
(ALARM usa archlinuxarm-keyring; el script termina en exit 0), "No Snapper configs" (exit 1
tolerado como 127/continuar). G4 post: `omarchy-migrate --pending` vacío (exit 1 = sin
pendientes, es el "todo OK"), `pgrep quickshell` + `hyprctl version`, sddm vivo.
**Abortar si**: cae el enlace NCM a mitad de transacción (re-conectar, `pacman -Syu` NO;
re-lanzar `omarchy update`, que reanuda), OOM (MemTotal debe ser 7,2 GiB, no 1,6), o prompt
de conflicto que nadie puede responder sin dueño (dejar pendiente, anotar).

## 4. sddm / primer arranque (nota breve)

Ledger #609: sddm ya `enabled` (symlink display-manager persistido). `omarchy-settings`
aporta `etc/sddm.conf.d/{10-theme,10-wayland}.conf`; autologin `Session=omarchy` se hizo a
mano (DESKTOP-OMARCHY-REVISION §1, contenido no verificado). `omarchy-provision-owner`
corre en tty1 ANTES de sddm (unidad autoborrable, `usr/bin/omarchy-provision-owner:7`) y su
`keyboard_form` (`:583-587`) + user/pass por `chpasswd` (`:740-741`) exigen **teclado USB
físico** (sin OSK en tty1/greeter). Si el usuario `alarm` ya existe y el primer arranque
gráfico ya ocurrió (#634), provision-owner probablemente ya consumió su marcador
(`/var/lib/omarchy/provisioning/pending`); verificar antes de enchufar teclado:
si el marcador no existe, no hace falta teclado. `provision-first-run` (login) instala hooks
post-update (voxtype/fingerprint/agent) y habilita user units; sus pasos fallidos reintentan
al próximo login (no bloquean).

## 5. Riesgos y pendientes

- Deriva edge: `omarchy.db` local (11-oct) trae `hyprland-0.56.2-5` vs staged `-4`, y
  `omarchy-chromium{,-bin}-148` existe en edge/aarch64 (mitiga "chromium x86-only").
  Re-validar `pacman -Si` de la lista EJECUTAR el día del update.
- `1784672586` instala `quickshell-git` desde edge: compila contra Qt del momento; si rompe
  el shell, `1787399318` (misma tanda, posterior) lo devuelve al empaquetado.
- Sin red NCM no hay update (keyring hace `--recv-keys keys.openpgp.org`, `mise up`, yay).
- Esta noche NO se pudo contrastar upstream (`omacom/omarchy` rama quattro) por falta de
  tiempo/web; la clasificación usa solo el pkg staged + DBs locales (evidencia autocontenida).

Evidencia: `F-plan-por-fases.md` F6 (líneas ~1140-1210) y F8 (~1340-1370);
`docs/informes/A-port-omarchy-aarch64.md:63,85,143-144,214,226,233-234,258-259,437,455-457,500`;
`docs/informes/C-hyprland-quickshell-aarch64.md:319`; `DESKTOP-OMARCHY-REVISION.md:1-76`;
ledger `#609` (510 pkgs, sddm enabled), `#634` (escritorio en pie, 106 pendientes), `#635-637`;
`build/stage-escritorio/{omarchy-4.0.4-2,omarchy-settings-4.0.4-6,db-sync/sync/omarchy.db}`.
