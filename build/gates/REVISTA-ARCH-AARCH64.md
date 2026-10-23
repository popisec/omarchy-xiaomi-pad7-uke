# REVISTA ARCH/aarch64 para uke — estado real de los repos (28-sep-2026)

**Fecha de medición: 28-sep-2026, ~15:05–17:00 UTC.** Todo lo numerado abajo se midió hoy desde el PC
(`curl -sSI`, descarga de los `.db`, GitHub/Codeberg/GitLab APIs, `git ls-remote`, AUR RPC).
Cero escrituras en la tablet, cero flash, cero ssh. **DATO** = medido hoy con fuente citada.
**INFERENCIA** = conclusión marcada como tal. Lo que no se pudo comprobar en línea va como
**NO VERIFICADO**. Lo que exige estar delante de la tablet va como **[REQUIERE TABLET]**.

Última revisión anterior conocida: 27-sep-2026 (NOTAS-OMARCHY.md). Los deltas contra esa fecha
van con 🔺.

---

## 1) Estado real de los repos, con fecha de hoy

### 1.1 Omarchy: `edge/aarch64` y `stable/aarch64`

**DATO** (medido 28-sep-2026 15:03 UTC, `curl -sSI https://pkgs.omarchy.org/...`):

| Canal | `.db` | `last-modified` | Paquetes (`/desc`) | `omarchy-4.0.4-1` |
|---|---|---|---|---|
| `edge/aarch64` | 200 (35 350 B) | **28-sep-2026 12:25 UTC** | 🔺 **159** (era 148) | 200 ✅ (120 MB, sha `4bc142f6…` en el `desc`) |
| `stable/aarch64` | 200 (10 268 B) | **28-sep-2026 05:01 UTC** | 🔺 **34** (era 22) | **404** (persiste) |

Fuente: `https://pkgs.omarchy.org/edge/aarch64/omarchy.db`,
`https://pkgs.omarchy.org/stable/aarch64/omarchy.db` (descargados y contados con
`tar tf … | grep -c '/desc$'`).

- `edge` sigue trayendo el escritorio: `omarchy-4.0.4-1`, `omarchy-settings-4.0.4-4`
  (🔺 era `-2`), `hyprland-0.56.2-4` (🔺 era `-3`), `quickshell-git-0.3.0.r20.g28771c7-4`,
  `walker-2.17.1-1`, `omarchy-walker-1.0.0-2`. El `desc` de `omarchy` pide
  `hyprland quickshell uwsm sddm xdg-desktop-portal-hyprland wireplumber pipewire …`
  (quickshell/uwsm/sddm **no** están en el repo: vienen de ALARM `extra`, ver §1.3).
- 🔺 `stable` crece (22→34) y **ahora incluye `hyprland-0.56.2-4` + `hyprpm`**, pero sigue
  **sin** `omarchy` ni `omarchy-settings` (cero entradas `omarchy-*` de escritorio; solo
  `omarchy-billboard-generator`). La trampa de `G §3.1` sigue vigente con números nuevos:
  **la vía es `edge`, nunca `stable`**.
- 🔺 Paquetes nuevos en `edge` desde el 27-sep (selección con implicación para nosotros):
  `linux-aurora-7.1.12.aurora2-11` + `-headers` (kernel para Apple Silicon/Asahi,
  `url: github.com/aurora-silicon/linux`, `conflicts: linux-asahi`),
  `omarchy-mac-boot-20260927-1` («Apple Silicon boot support: initramfs, in-place
  encryption, Limine»), `m1n1-aurora`, `uboot-asahi-2026.07.asahi2-4`,
  `google-chrome-154.0.8037.57-1` (**aarch64**, según su `desc`),
  `omarchy-chromium-148.0.7778.96-21`, `nvidia-open-dkms-615.71.09-1.2` (aarch64),
  `omarchy-steam-fex`, `avd-fw`, `v4l2-relayd`, `wayfreeze`, `omarchy-dev`
  (`4.0.0.r6663.g3faafba-1`). **DATO** verificado en los `desc` del `.db`; el porqué de
  un Chrome/nvidia aarch64 en el repo no se investigó (fuera de alcance, no afecta a uke).

### 1.2 Repo oficial de paquetes `omacom-io/omarchy-pkgs` — vía aarch64 ABIERTA y ACTIVA

**DATO** (GitHub API, 28-sep-2026):

- Existe rama `add-aarch64-support` pero es **vieja** (`5b28e55d`, «Update docs»,
  **30-oct-2025**): arqueología, no la vía actual.
- La vía actual son **PRs con CI nativo ARM**: #681 «Rebuild aarch64 natively»
  (mergeado 27-sep, runners `ubuntu-24.04-arm`; antes se construía bajo QEMU en x86),
  #671 (movió los builds de PR aarch64 a runners ARM). Hay tracker automático que
  fija `_commit` y auto-mergea (`#684`, mergeado 27-sep).
- 🔺 **#701 mergeado HOY 28-sep-2026**: «omarchy-settings-dev: ship the full set on
  aarch64 for runtime-profile sources» (zram, oomd, zswap, sysctl, USB autosuspend).
  El repo publica aarch64 **a diario**.
- 🔺 **#695 abierto HOY 28-sep**: «Build linux-firmware from source and follow Arch's
  releases unattended» (motivo: `[core]` va antes que `[omarchy]` en el pacman.conf y
  un shim de firmware publicado el 17-sep **nunca fue seleccionado**). Relevante para
  §3a: upstream ya discute ser dueño de su firmware.
- Otros abiertos con olor a tablet: #687 Goodix `27c6:5201` en libfprint (lector sin
  driver upstream — mismo patrón que nuestro NT36532), #685 «Build LM Studio for
  aarch64», #506 «Apple Silicon Wi-Fi defaults as a settings add-on», #466
  `brcmfmac-awdl-dkms` aarch64, #616 «Update aarch64 AVD driver».
- Los PRs citan el proceso en `.omarchy/package.json` (`auto_merge`) y el foro de
  discusión `omacom/omarchy` (discussions #13362, #13488). Fuente:
  `https://api.github.com/repos/omacom-io/omarchy-pkgs/pulls?...` (30 PRs listados hoy)
  + README de `omarchy-mac/omarchy-pkgs-aarch64` (push **28-sep-2026 05:37 UTC**, 12
  issues abiertos), que documenta que el tooling oficial «already supports ARM»
  (`./bin/build --arch aarch64`).
- Hay paquetes kernel propios en el repo oficial, pero **x86/Asahi**: `linux-omarchy`
  (#440, y #678 «keep Intel IOMMU off by default on Dell XPS» — mergeado 27-sep),
  `linux-aurora` (Mac). **Ningún kernel qcom.** **INFERENCIA**: un `linux-uke` no cabe
  en su scope (ellos hacen x86 + Apple Silicon); el userspace tablet sí podría
  (ver §3a).

### 1.3 Arch Linux ARM (`extra`/`core` aarch64) — sin cambios desde el 27-sep

**DATO** (`archlinuxarm.org/packages/aarch64/<pkg>`, títulos 200 verificados hoy;
versiones extraídas del HTML):

| Paquete | Versión hoy | = 27-sep | Nota |
|---|---|---|---|
| `mesa` | `1:26.2.3-1` | ✅ igual | Último estable upstream (tags §1.4) |
| `vulkan-freedreno` | `1:26.2.3-1` | ✅ igual | Turnip, `provides=vulkan-driver` |
| `hyprland` | `0.56.2-3` | ✅ igual | = último upstream (v0.56.2, 5-ago-2026, GitHub API) |
| `quickshell` | `0.3.1-1` | ✅ igual | = último upstream (v0.3.1, 21-ago-2026, GitHub API) |
| `linux-aarch64` | `7.2.8-1` | ✅ igual | Multi-platform, sin palawan (E §2.1 sigue válido) |
| `linux-firmware-qcom` | `20260916-1` | ✅ igual | Sin `gen71100` (WHENCE §1.4 + medida en tablet 27-sep) |
| `libwacom` | `2.20.0-1` | ✅ igual | El bus SPI sigue sin soporte (código citado en E §2.4, no re-verificado hoy) |
| `iio-sensor-proxy` | `3.9-1` | ✅ igual | Vía de rotación |
| `squeekboard` | `1.43.1-5` | ✅ igual | OSK disponible sin AUR |
| `wvkbd`, `lisgd`, `qbootctl`, `pd-mapper` | **404** | ✅ igual | Siguen solo-AUR, **pero** ver 🔺 §1.5 |

### 1.4 Mesa / freedreno / firmware upstream — verificado hoy

- **Mesa 26.2.3 sigue siendo el último estable**: `git ls-remote` a
  `gitlab.freedesktop.org/mesa/mesa.git` (28-sep-2026) muestra `mesa-26.2.3` como tag
  26.2.x más alto (26.2.0–26.2.3 presentes; 26.1.x llega a 26.1.6). ALARM va al día.
- **El `0x43030a00` (732) sigue ausente de Mesa upstream**: `grep -c 43030a00` = **0**
  tanto en `main` (`fd-main.py`, 1671 líneas, descargado hoy de
  `gitlab.freedesktop.org/mesa/mesa/-/raw/main/.../freedreno_devices.py`) como en el
  tag `mesa-26.2.3`. El `0x43030B00` (`FD735`) sí está (líneas 1216-1217). **DATO**,
  reproduce E §2.3.
- 🔺 Matiz que **debilita R1** (era «sin parche no hay GPU»): el kernel del proyecto
  reporta **`0x43030b00`** (DT `qcom,adreno-43030b00` + `adreno-gmu-732.0`,
  NOTAS-OMARCHY 27-sep), ID que Mesa main **ya conoce**. Si el silicio confirma B00,
  **no hace falta parchear Mesa** (decisión D15, pendiente de cierre **[REQUIERE TABLET]**:
  basta el `chipid` del `dmesg` F1a).
- `lfdevs/mesa-for-android-container` PR #93 («unofficial support for Adreno 732»):
  **mergeado el 28-jul-2026** (GitHub API: `merged_at 2026-07-28`, última actividad
  11-sep-2026). Sigue siendo un downstream de contenedores Android (backend KGSL),
  **no** upstream Mesa: transportable como parche al PKGBUILD `mesa`/`mesa-git` si D15
  sale B00=falso. Fuente: `https://api.github.com/repos/lfdevs/mesa-for-android-container/pulls/93`.
- **GLES anunciado por freedreno**: «up to OpenGL ES 3.2 and desktop OpenGL 4.5»;
  **Turnip: Vulkan 1.3** para Adreno 6xx (lista de chips en `freedreno_devices.py`).
  Fuente: `https://docs.mesa3d.org/drivers/freedreno.html` (leída hoy). **NO MEDIDO en
  la tablet**: lo que anuncie `eglinfo`/`vulkaninfo` en uke sigue pendiente de F1a
  **[REQUIERE TABLET]**.
- `WHENCE` de `linux-firmware` (kernel.org, descargado hoy): `grep -c gen71100` = **0**
  (solo gen70500/70900/71500/71700/80000/…). El paquete propio `uke-gpu-firmware`
  sigue siendo insustituible. Fuente:
  `https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/WHENCE`.

### 1.5 AUR (qcom + tablet) — 🔺 EL CAMBIO GRANDE desde el 27-sep

**DATO** (PKGBUILDs leídos hoy de `aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=<pkg>`):

| Paquete | Versión | `arch=` hoy | Efecto |
|---|---|---|---|
| `qbootctl` | 0.2.2-1 | `($CARCH)` ✅ | `makepkg` directo en aarch64, sin parche |
| `pd-mapper` | 1.1-1 | `(aarch64 x86_64)` ✅ | idem (**era la trampa R2/R6 de E**) |
| `tqftpserv` | 1.2-1 | `(aarch64 x86_64)` ✅ | idem |
| `rmtfs` | 1.2-1 | `(aarch64 x86_64)` ✅ | idem |
| `wvkbd-deskintl` | 0.19.4-1 | incluye `aarch64` ✅ | el OSK de Omarchy compila tal cual |
| `lisgd` | 0.4.0-1 | incluye `aarch64` ✅ | gestos táctiles sin parche |
| `rot8-git` | 1.0.0+r112 | `("x86_64" "aarch64")` ✅ | rotación sin parche |

**La «trampa AUR en aarch64» de E §2.5 / R6 queda REFUTADA para estos siete paquetes**:
ya declaran aarch64 (sea porque el mantenedor lo añadió o porque E no lo midió a nivel
de PKGBUILD — no se puede datar el cambio sin historial; lo que importa es el estado
de hoy). Nota: `pd-mapper` en AUR es reciente (RPC: `FirstSubmitted` ene-2026,
grupo `qcom-icnss-wlan`, mant. `supertecnogym`).

### 1.6 `palawan-mainline/linux` y pmOS — sin movimiento

- Codeberg API (hoy): default `palawan/v7.1`, `updated 2026-07-09`, 0 stars/forks/issues;
  ramas `palawan/v7.2-rc2 @ 0d9f7fdf72` y `palawan/v7.1 @ 94a1e2329f` — **mismos SHAs
  que midió E**. Parado desde el 9-jul (2,5 meses). Fuente:
  `https://codeberg.org/api/v1/repos/palawan-mainline/linux`.
- pmaports (GitLab API, hoy): **no existe `device-xiaomi-uke`** (barridas las 329
  entradas de `device/testing` + `device/community`: 0 menciones a uke/sm7675/pad-7;
  los Xiaomi llegan hasta `nabu`/`pipa`). La wiki tiene página
  «Xiaomi Pad 7 (xiaomi-uke)» (índice de búsqueda) pero está tras Anubis (no legible
  sin JS hoy) y **no hay recipe**: pmOS es referencia técnica, no fuente de paquetes
  para uke. Fuente: `https://gitlab.postmarketos.org/api/v4/projects/226/...`.
- DanctNIX sigue vivo (`archmobile.mirror.danctnix.org`, 436 artefactos hoy) como
  plantilla de mini-repo + kernel por dispositivo (`linux-pinetab2-7.1.8`,
  `linux-megi-6.18.39`).

### 1.7 Hyprland/Quickshell tablet (lápiz, rotación, teclado) — lo que el repo ya trae

**DATO** (documentación upstream, consultada hoy):

- Hyprland implementa `input:tablet:` (`output`, `transform`, `region_position`,
  `region_size`, `relative_input`, `left_handed`, `active_area_*`),
  `input:touchdevice:` (`transform`, `output`) y gestos `workspace_swipe_touch`.
  Fuente: wiki Hyprland (vía `wiki.hypr.land/0.45.0/Configuring/Variables`,
  parser `hyprls` y tabla ArchWiki «Graphics_tablet»: Hyprland = map-to-monitor ✅,
  map-to-region ✅, botones ❌). La versión empaquetada (0.56.2) es la última
  upstream: **nada que compilar por el lado compositor**.
- Rotación = `iio-sensor-proxy` (ALARM ✅) + script (`iio-hyprland` de JeanSchoeller,
  citado en la comunidad; **NO VERIFICADO** su estado hoy) o `rot8-git` (AUR ✅
  aarch64). Gestos táctiles = `lisgd` (AUR ✅). OSK = `squeekboard` (ALARM ✅) o
  `wvkbd-deskintl` (AUR ✅, el que usa Omarchy).
- Lápiz NT36532: el bloque sigue como lo dejó E (libwacom ✅ binario, falta `.tablet`
  + bus SPI sin soporte + **driver de kernel del NT36532 inexistente**). Nada nuevo
  en repos que lo mueva; es trabajo de kernel/DT, no de paquetes.

---

## 2) Qué le falta a Omarchy-aarch64 para un tablet real (orden de bloqueo)

1. **Camino GPU** — El repo trae **cero** pila gráfica propia (ni `mesa`, ni
   `vulkan-freedreno`, ni kernel qcom en `edge`: ver §1.1). Todo viene de ALARM
   (`mesa 26.2.3` + freedreno, GLES 3.2 / GL 4.5 / Vulkan 1.3 anunciados por docs,
   **no medidos en uke**). Si D15 confirma chip-id B00 → **cero trabajo de paquetes**.
   Si sale A00 → aplicar PR #93 sobre el PKGBUILD de `mesa` (medio día, ver §3c).
   **[REQUIERE TABLET]** solo para el `chipid` y el `eglinfo`.
2. **Shell + compositor** — Resuelto por paquetes: `omarchy` 4.0.4-1 + `hyprland`
   0.56.2-4 + `quickshell` 0.3.1-1 de ALARM (ya instalado en la tablet el 27-sep
   según NOTAS). Sin problema conocido de compilación aarch64: **upstream publica
   ARM de forma rutinaria** (CI nativo §1.2) y ALARM lo empaqueta al día.
3. **Capa tablet** — Todo existe como paquete **excepto lo que es kernel**:
   rotación/gestos/OSK ✅ (§1.7); lápiz 🟡 (falta driver NT36532 + `.tablet` +
   parche bus SPI — nada empaquetable hasta tener el nodo input del kernel).
4. **Carga/red de paquetes** — `edge` trae de todo menos lo qcom; el resto está en
   ALARM+AUR (§1.3, §1.5). Nada que inventar.
5. **Rotos en x86→aarch64** — Hoy: **ninguno conocido** en nuestro camino crítico.
   Los siete AUR ya declaran aarch64 (§1.5). El caso `pinta`/`obs-studio` (recetas
   x86-only con blobs) es del fork Mac, no nos toca. Lo único con `arch` raro es
   `google-chrome`/`nvidia-open-dkms` en `edge`, irrelevantes para uke.

---

## 3) Lo que se puede añadir

### a) Aportar a los repos de Omarchy (vía abierta, con proceso)

**DATO**: el repo oficial acepta y publica aarch64 a diario con CI nativo ARM,
auto-merge y `upstream.sh` con `sha256sums` por arquitectura (f illnesses §1.2:
#681, #684, #701). **INFERENCIA**: un PR bien formado para aarch64 tiene recorrido;
no es un buzón muerto.

| Candidato | Esfuerzo | Beneficio | Nota |
|---|---|---|---|
| `qbootctl` + unidad `-m` en multi-user (patrón DanctNIX/CachyOS) | Bajo (PKGBUILD existe; solo packaging+servicio) | Medio-bajo para ellos (sin tablets qcom), **alto para nosotros** si lo mantenemos en nuestro mini-repo | Probablemente fuera de su scope; mejor mini-repo propio |
| Settings tablet (rotación `iio-sensor-proxy`, gestos `lisgd`, OSK) como add-on tipo #506 | Medio | Medio (reutiliza su patrón «settings add-on») | El precedente #506 (Apple Wi-Fi defaults) dice que el formato cabe |
| `linux-uke` / firmware qcom en `omarchy-pkgs` | Alto + scope dudoso | Bajo para ellos | **No proponer**: su scope es x86+Asahi; seguir el modelo `linux-aurora` en repo propio |
| Reportar `arch` x86-only que encontremos (estilo #685) | Mínimo | Bajo-medio, buena vecindad | Hacerlo de paso |

**Acción concreta**: abrir issue/discusión en `omacom/omarchy` preguntando si quieren
el add-on tablet (con el precedente #506 citado); en paralelo, mini-repo propio con
la forma DanctNIX (PKGBUILD + repo + keyring — E §1.3).

### b) Traer de otro sitio

| Fuente | Qué | Esfuerzo | Beneficio |
|---|---|---|---|
| AUR (¡ya aarch64!) | `qbootctl`, `pd-mapper`, `tqftpserv`, `rmtfs`, `wvkbd-deskintl`, `lisgd`, `rot8-git` | **Mínimo** (`makepkg` en la tablet o cross) | Alto: cierra todo el userspace qcom+tablet sin parches |
| Alpine/pmOS (recetas, no binarios) | `qbootctl-openrc/-systemd` (unidades de servicio de Casey Connolly), esquema de 105 subpaquetes de firmware | Bajo (copiar recetas) | Medio: servicio `qbootctl -m` + paquete firmware mínimo bien partido |
| DanctNIX | Plantilla PKGBUILD kernel-por-dispositivo + repo firmado | Bajo-medio | Medio: no reinventar `linux-uke-*.pkg` |
| `JeanSchoeller/iio-hyprland` | Rotación automática vía `iio-sensor-proxy` + `hyprctl` | Bajo | Medio (confort tablet); **NO VERIFICADO** hoy, re-check antes de usar |
| lfdevs PR #93 | Parche Adreno 732 para `mesa` | Medio-bajo | Solo si D15 sale A00 (plan B ya localizado y con fuente) |

pmOS **no** aporta nada específico de uke (sin recipe, §1.6): queda como referencia
técnica, tal como manda el proyecto.

### c) Reemplazar trabajo manual por paquetes Arch

| Hecho a mano | Reemplazo | Veredicto |
|---|---|---|
| `qbootctl` cross-compilado a mano (27-sep, `build/slot/`) | AUR `qbootctl` (`$CARCH`) | 🔺 **Reemplazable**: compilar con `makepkg` en la tablet para tenerlo trazado por pacman (el binario instalado sigue válido; no reinstalar por capricho) |
| `uke-gpu-firmware` propio (3 blobs vendor) | Nada (WHENCE=0 hoy) | **Sin reemplazo**: mantener; vigilar el #695 (si Omarchy construye `linux-firmware` desde fuente, el `gen71100` seguirá faltando igual — es blob vendor, no upstream) |
| Mesa de ALARM + parche pendiente | Seguir con ALARM `mesa`/`vulkan-freedreno` 26.2.3 | **Sin acción** hasta D15; si B00, el «parche Mesa» (R3) se retira del todo |
| `pd-mapper` in-kernel (plan A) vs AUR (plan B) | AUR `pd-mapper` 1.1-1 aarch64 listo | El plan B ya no cuesta nada; el plan A sigue vigente (módulo `qcom_pd_mapper` en la config buena) |
| Claves/repos a mano | Mini-repo propio firmado (forma DanctNIX) | Hacerlo cuando haya ≥3 paquetes propios (kernel+firmware+settings): hoy hay 1 (firmware) → aún no urge |

---

## 4) Bloqueos reales de la vía Omarchy (solo lo que ningún paquete evita)

1. **Bring-up de la GPU en el kernel (F1a/CM3).** Abrir `renderD128` (`hw_init` →
   `a6xx_gmu_resume` → arranque del CM3) es el cuelgue duro medido por el hermano;
   watchdog muerto + batería invisible = sin paracaídas ni manómetro. Ningún
   paquete lo mueve: es DT/nodo GMU + firmwares (ya instalados) + silicio.
2. **Display (F1b): PHY DSI + panel + reguladores.** `qcom,dsi-phy-v5.2` sin match en
   mainline, driver de panel o82, y vsp/vsn colgados del GPIO/pinctrl (auditoría
   27-sep). Puro kernel/DT.
3. **Hemorragia de slot** (`Successful: 0`, `qbootctl` instalado pero sin ejecutar).
   El remedio es un binario que ya existe; el bloqueo es la **decisión de escritura
   en GPT**, no la disponibilidad del paquete (§3c la abarata, no la resuelve).
4. **RAM 2 GiB sin swap** para Hyprland+Quickshell+Mesa (D16, decisión del dueño).
5. **Lápiz NT36532**: falta el driver de kernel; sin nodo input no hay `.tablet` ni
   parche SPI que valga.

## 5) Recomendación: una tarde de subagente, éxito medible

**Hacer (orden, todo sin tablet salvo donde se indica):**

1. **Cerrar D15 sin flashear (1–2 h).** Releer los logs F1a ya capturados (`build/`
   + `out/`) buscando el `chipid`/`compatible` que reportó el probe (`0x43030b00` vs
   `0x43030a00`). Éxito medible: **una línea en NOTAS diciendo B00 o A00 con cita
   de log**. Si B00 → retirar R3 del plan (cero trabajo Mesa). Si A00 → dejar
   preparado (no construido) el `PKGBUILD` de `mesa` con el PR #93 como parche.
   Solo si los logs no lo contienen: **[REQUIERE TABLET]** `measure-cm3.sh` en
   caliente, 0 flashes.
2. **Convertir el userspace qcom en paquetes trazables (2–3 h, en el PC + tablet
   en solo-lectura salvo `makepkg`).** `makepkg` de los 7 AUR (§1.5) contra
   `pkgs.files` cacheados o en la propia tablet; archivar los `.pkg.tar.zst` en
   `build/pkg/` con sha. Éxito medible: **7 paquetes construidos sin parchear
   ningún `arch=`**, refutando R6 por construcción. (Instalarlos ya es decisión con
   ledger, no de esta tarde.)
3. **Abrir la conversación upstream (30 min).** Borrador de discusión para
   `omacom/omarchy` (add-on tablet, precedente #506) + lista de `arch=` x86-only
   que nos crucemos. Éxito medible: texto en `build/gates/` listo para pegar.

**Y la conclusión valiosa si nada de lo anterior desbloquea píxeles:** decirlo tal
cual — *el bloqueo es kernel/HW (CM3 + DSI + reguladores) y la vía de paquetes está
cerrada al 100 %*; la tarde rinde igual porque convierte «nos falta algo de Arch»
(incertidumbre) en «no nos falta nada de Arch» (dato con fecha).

---

### Fuentes (todas consultadas el 28-sep-2026)

| Fuente | URL | Qué se sacó (DATO) |
|---|---|---|
| Omarchy edge/aarch64 `.db` | `https://pkgs.omarchy.org/edge/aarch64/omarchy.db` | 159 pkgs, `last-modified` 28-sep 12:25 UTC, `omarchy-4.0.4-1` presente |
| Omarchy stable/aarch64 `.db` | `https://pkgs.omarchy.org/stable/aarch64/omarchy.db` | 34 pkgs, `last-modified` 28-sep 05:01 UTC, sin escritorio, 404 del pkg |
| omarchy-pkgs PRs/issues (API) | `https://api.github.com/repos/omacom-io/omarchy-pkgs/...` | #701 mergeado 28-sep, #695/#687/#685 abiertos, CI ARM #671/#681, kernel #440/#678 |
| omarchy-pkgs-aarch64 README | `https://github.com/omarchy-mac/omarchy-pkgs-aarch64` | push 28-sep, tooling oficial `--arch aarch64`, ramas de la API |
| ALARM paquetes | `https://archlinuxarm.org/packages/aarch64/{mesa,vulkan-freedreno,hyprland,quickshell,linux-aarch64,linux-firmware-qcom,libwacom,iio-sensor-proxy,squeekboard}` | versiones §1.3 + 404 de wvkbd/lisgd/qbootctl/pd-mapper |
| AUR PKGBUILDs | `https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h={qbootctl,pd-mapper,tqftpserv,rmtfs,wvkbd-deskintl,lisgd,rot8-git}` | `arch=` con aarch64 (§1.5) |
| AUR RPC v5 | `https://aur.archlinux.org/rpc/v5/info/...` | versiones y mantenedores |
| Mesa `freedreno_devices.py` main + tag | `https://gitlab.freedesktop.org/mesa/mesa/-/raw/{main,mesa-26.2.3}/src/freedreno/common/freedreno_devices.py` | 0× `43030a00`, 1× `43030B00` |
| Mesa tags | `git ls-remote https://gitlab.freedesktop.org/mesa/mesa.git` | 26.2.3 = último estable |
| lfdevs PR #93 (API) | `https://api.github.com/repos/lfdevs/mesa-for-android-container/pulls/93` | mergeado 28-jul-2026, solo downstream |
| Mesa docs freedreno | `https://docs.mesa3d.org/drivers/freedreno.html` | GLES 3.2 / GL 4.5 / Turnip Vulkan 1.3 |
| Hyprland/Quickshell releases (API) | `https://api.github.com/repos/{hyprwm/Hyprland,quickshell-mirror/quickshell}/releases/latest` | v0.56.2 (5-ago), v0.3.1 (21-ago) |
| Hyprland wiki (tablet/touch) | `https://wiki.hypr.land/0.45.0/Configuring/Variables`, ArchWiki `Graphics_tablet` | `input:tablet:` + touchdevice + swipe_touch |
| linux-firmware WHENCE | `https://git.kernel.org/.../linux-firmware.git/plain/WHENCE` | 0× `gen71100` |
| palawan-mainline (API) | `https://codeberg.org/api/v1/repos/palawan-mainline/linux` (+ `/branches`) | parado 9-jul, mismos SHAs que E |
| pmaports (API) | `https://gitlab.postmarketos.org/api/v4/projects/226/repository/tree?...` | sin `device-xiaomi-uke` (329 entradas testing) |
| pmOS wiki uke | `https://wiki.postmarketos.org/wiki/Xiaomi_Pad_7_(xiaomi-uke)` | **NO VERIFICADO** (Anubis exige JS; solo consta su existencia en el índice) |
| DanctNIX mirror | `https://archmobile.mirror.danctnix.org/danctnix/aarch64/` | vivo, 436 artefactos, plantilla kernel-por-dispositivo |
| `iio-hyprland` | citado vía comunidad (Framework/GPD) | **NO VERIFICADO** hoy; re-check antes de usar |
