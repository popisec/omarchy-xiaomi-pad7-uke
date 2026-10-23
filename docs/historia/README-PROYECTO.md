# Omarchy en la Xiaomi Pad 7 «uke» (SM7675, aarch64) — proyecto

> ⚠️ **Documento histórico** (27-sep-2026), conservado por contexto. El README vigente es el
> [`../../README.md`](../../README.md), el estado actual está en
> [`../../ESTADO-VIVO.md`](../../ESTADO-VIVO.md) y el plan en
> [`../../F-plan-por-fases.md`](../../F-plan-por-fases.md). La publicación es una **instantánea
> sin historial**, así que los hashes de commit que aquí se citan no existen en este repo.

> **Ubicación original: pc-build → `~/proyectos/omarchy-uke/`** (misma máquina y hermano de
> `~/proyectos/ubuntu-permanente/` y `~/proyectos/ubuntu-uke/`). **Una sola copia, con control de
> versiones** (`git init` 27-sep-2026). No hay taller de investigación remoto ni sincronización
> entre máquinas: todo se escribe y versiona aquí.

**Objetivo:** **Omarchy (Arch + Hyprland + shell Quickshell) corriendo en la tablet**, en x86→aarch64,
sobre el kernel propio mainline 7.2-rc2 «palawan» y arrancando por `boot.img` de Android (slots A/B).

**Cambio de objetivo (26-sep-2026):** el destino deja de ser postmarketOS. pmOS queda como
**referencia técnica y red de seguridad**, pero el objetivo pasa a ser **llevar Omarchy a aarch64**
(primero a esta tablet; el port se documenta de forma reutilizable).

## Decisión de base: **Arch/aarch64, no Alpine** (26-sep-2026, con datos)

Comparativa cerrada por evidencia, no por gusto:

| Criterio | Arch/aarch64 (Arch Linux ARM + repo Omarchy) | Alpine/pmOS |
|---|---|---|
| Hyprland | **0.56+** (el que exige Omarchy 4, config Lua) | **0.54.3** — sin el API Lua que usa Omarchy |
| `hyprpm` (plugins) | disponible | **no existe** (`-DNO_HYPRPM=true`) → `hyprgrass` ni por la vía documentada |
| Shell Quickshell | en Arch Linux ARM como paquete | hay que construir y mantener |
| Paquetes Omarchy | repo propio `pkgs.omarchy.org` con **aarch64 ya publicado** | inexistente |
| Arranque | a mano (boot.img Android + A/B) | infraestructura pmOS (`qbootctl`, A/B, initramfs) |

**El hallazgo que decide:** el árbol de Omarchy es **agnóstico de arquitectura** (461 scripts bash,
186 QML, 128 migraciones, 22 temas); en `omacom/omarchy-pkgs`, `omarchy` y `omarchy-settings` **ya
declaran `arch=('x86_64' 'aarch64')`** con `depends_aarch64` y un `package()` que descarta el stack
x86 (Limine/snapper). **Estado medido en vivo (26-sep-2026):** `stable/aarch64/omarchy.db` → **200 con
22 paquetes, sin el escritorio**; **`edge/aarch64/omarchy.db` → 200 con 148 paquetes, incluidos
`omarchy-4.0.4-1` y `omarchy-settings-4.0.4-2`** (y `hyprland 0.56.2-3`, `quickshell 0.3.1-1`).
Solo dan 404 las rutas de directorio y el paquete de `stable/aarch64`. **La vía para la uke es
`edge`, nunca `stable`** → no hay que construir el repo nosotros. Ver `docs/informes/A-port-omarchy-aarch64.md`
y §3.1 de `docs/historia/G-auditoria-documental.md` (que corrige a `E` en este punto).

## Subproyectos (rama de trabajo)

| # | Subproyecto | Pregunta que responde | Informe |
|---|---|---|---|
| A | **Port de Omarchy a aarch64** | Qué exactamente hay que recompilar/parchear (paquetes, repo rolling, `pacman`, AUR, los «x86-only» del menú) y cómo lo hizo Fydetab | `docs/informes/A-port-omarchy-aarch64.md` |
| B | **Arranque Arch ARM en la uke** | Cómo arranca Arch ARM con `boot.img` Android + slots A/B + kernel propio, sin UEFI/Limine: initramfs, cmdline (`rdinit`), BCB, contador | `docs/informes/B-arranque-arch-uke.md` |
| C | **Hyprland 0.56 + Lua + Quickshell en aarch64** | Compilar Hyprland con el API Lua de Omarchy, Quickshell y el resto del shell en aarch64 (dependencias, parches, rendimiento en Adreno 732) | `docs/informes/C-hyprland-quickshell-aarch64.md` |
| D | **Capa tablet y lápiz fuera de Omarchy (fallback)** | Qué de `texp-*` (Bash/Python + `hyprctl`) es reutilizable sin el shell de Omarchy, para tener capa tablet aunque el shell falle | `docs/informes/D-capa-tablet-fallback.md` |
| E | **Herramientas de Arch ARM para el SoC** | `pacman`/AUR/aarch64 en la tablet: qué paquetes existen para SM7675 (kernel, firmware WCN6750 + gen71100, mesa/freedreno, libwacom, qbootctl) y qué hay que construir | `docs/informes/E-paquetes-aarch64-soc.md` |
| F | **Plan por fases (F0–F8)** | El plan ejecutable: qué hacer en qué orden, con criterio de «hecho» medible, camino crítico, 32 riesgos y 20 decisiones del dueño (D1–D20) | `F-plan-por-fases.md` |
| G | **Auditoría documental** | ¿Está todo documentado? Inventario, contradicciones verificadas en vivo, cobertura temática y huecos | `docs/historia/G-auditoria-documental.md` |

## Estado de los informes

| Informe | KB | Estado |
|---|---|---|
| `docs/informes/A-port-omarchy-aarch64.md` | 59 | ✅ cerrado |
| `docs/informes/B-arranque-arch-uke.md` | 95 | ✅ cerrado |
| `docs/informes/C-hyprland-quickshell-aarch64.md` | 64 | ✅ cerrado |
| `docs/informes/D-capa-tablet-fallback.md` | 67 | ✅ cerrado |
| `docs/informes/E-paquetes-aarch64-soc.md` | 42 | ✅ cerrado |
| `F-plan-por-fases.md` | 87 | ✅ cerrado |
| `docs/historia/G-auditoria-documental.md` | 28 | ✅ cerrado |

**Los 7 informes están cerrados** y versionados en git (commit inicial `a9dac1b`, 27-sep-2026).
Suma: ~442 KB de investigación con fuente. Desde el 27-sep son **material de referencia
congelado**: lo que se actualiza es `docs/historia/ESTADO-VIVO.md` y `F-plan-por-fases.md`.

**Huecos declarados por G** (sin informe dueño todavía): **backup/restauración** →
`H-backup-restauracion-uke.md`; **lápiz de punta a punta** (NT36532 → kernel → libinput → libwacom →
Hyprland tablet-v2 → app) → `I-lapiz-uke.md`; y la parte operativa de **recuperación fastboot/brick**.
Los 17 arreglos concretos detectados (enlaces rotos, citas caducadas) están en `G` §6; el del README
ya está aplicado.

## Documentos base (heredados) — ⚠️ NO ESTÁN EN ESTA MÁQUINA

> **Comprobado el 27-sep-2026:** `ls -d ~/proyectos/tablet-lapiz-2026` → **no existe**. Los 11
> documentos base que se listaban aquí (y que el informe `F` reproduce en su anexo) **no están
> disponibles en esta máquina**: vivían en la carpeta del taller de investigación, que ya no forma
> parte del proyecto. **Los informes A–G los citan, pero aquí no se puede consultar nada que no esté
>citado literalmente dentro de los informes o en el proyecto hermano.**
>
> **Lo que sí está en esta máquina** es el proyecto hermano `~/proyectos/ubuntu-permanente/`
> (abajo), que contiene el conocimiento vivo de la tablet.

Documentos que los informes A–G citan y que **no están aquí** (lista para recuperarlos si hacen
falta):

- **Portabilidad Ubuntu → nueva base**: `ubuntu-a-pmos/01..05` (inventario, apt→apk,
  arranque/kernel/servicios, datos y apps, plan) + `01b-lista-paquetes-tablet.txt` (605 paquetes).
- **Lápiz en Linux**: `informe-stylus-linux-2026.md`, `informe-lapiz-linux-arm64-wayland-2026.md`.
- **Escritorios y lápiz**: `informe-escritorios-tablet-lapiz-2026.md`.
- **Distros para tablet ARM**: `informe-distros-tablet-arm64.md`.
- **pmOS vs UT / experiencias**: `pmos-vs-ut-actividad.md`, `experiencias-usuarios-pmos-vs-ut.md`,
  `pmos-apps-escritorio-arm64.md`, `ubuntu-touch-vs-alternativas.md`.
- **Hyprland tablet + dotfiles Omarchy** (56 KB, 52 URLs): `hyprland-tablet-y-dotfiles-omarchy.md`.
- **Gaps dentro del propio proyecto de origen**: `REGLAS-PARTICIONES.md` (la fuente de los riesgos
  R1–R12 de B), `CONFIG-BUENO.md`, `LECCIONES.md`, `REFUTADO.md`.

### Historia de la tablet en esta máquina (no duplicar, solo enlazar)

- **`~/proyectos/ubuntu-permanente/`** — estado vivo del port. En `docs/` hay **18 ficheros**:
  `README.md`, `FLASH-LEDGER.md` (**438 KB**, el ledger), `ESTADO-ACTUAL.md`, `OBJETIVOS.md`,
  `TRABAJO-PENDIENTE.md`, `LECCIONES.md`, `REFUTADO.md`, `SESION-24SEP-GPU.md`, `SESION-23SEP.md`,
  `SESION-24SEP.md`, `SESION-24SEP-NOCHE.md`, **`REGLAS-PARTICIONES.md`** (citado por el informe B
  como fuente de sus riesgos R1–R12), `CONFIG-BUENO.md`, `AL-DESPERTAR-22SEP.md`,
  `AL-DESPERTAR-RECUPERACION.md`, `ESTADO.md`, `INVESTIGACION-2122.md`, `MIGRACION-PORT-MODERNO.md`
  e `historico/`. En la raíz: `kernel-ports/`, `initboot/`, `rootfs/`, `bin/`, `criticas/`, `out/`.
- **`~/proyectos/ubuntu-uke/`** — archivo histórico de los intentos de arranque de Ubuntu (~7,7 GB):
  en `docs/` están **`plan-port-cliffs-clock.md` (79 KB, el mayor y muy relevante para el arranque)**,
  `UBUNTU-BOOT.md`, `analisis-20260905/RECIPE-KNOWN-GOOD.md`, `plan-gki-ubuntu.md`,
  `PLAN-ESTRATEGICO-20260905.md`, `SESION-20260906.md` y `sesion-tablet/`; en la raíz
  `HARDWARE-KNOWN-PLAN.md` (39 KB, plan de hardware conocido), `tools/mkubuntu-boot.sh` +
  `ciclo-ubuntu.sh`, `init v4`, dumps EFS (`modemst1/2`, `fsg`, `modem_a/b`, `spunvm`), `stock/`,
  `vendor-src/`, ROM stock. **Material directo para el informe B** (arranque).
- **Rama de trabajo de la GPU/SMMU**: `~/gpu-work/` (árbol `palawan-linux`, parches, scripts `ramaa/sNN-*`).

## Reglas de trabajo

> **Las reglas viven en [`REGLAS.md`](REGLAS.md)** (creado el 1-oct-2026: el runbook y varios
> informes citaban unas "15 reglas" que no estaban escritas en ningún sitio). El estado del
> aparato —qué par hay en la tablet ahora mismo— **solo lo dice
> [`docs/historia/ESTADO-VIVO.md`](docs/historia/ESTADO-VIVO.md)**; los pares citados aquí fueron los buenos de su día y
> están superados.

- **Nunca romper el arranque bueno**: el par vigente **cambia con cada flash** del proyecto. No
  lo tomes de este README: léelo de `docs/historia/ESTADO-VIVO.md` y de las últimas filas de
  `build/gates/PRE-REGISTRO-PANTALLA.md`; las copias de los pares buenos están en
  `build/backup-par-bueno/` con sus shas en `build/gates/SHA-BUENOS.txt`. Todo experimento se
  hace con **backup del par**, **sha256 pre-registrado antes de flashear** y lectura de vuelta
  por sha256 al tamaño exacto de la imagen.
- **La tablet NO está para experimentos destructivos**: `misc` BCB en `reboot-bootloader`, ext4
  con errores, y **en fastboot no carga** (umbral GO ≥ 3700 mV). Antes de tocar nada: `e2fsck`
  en frío + backup + limpiar BCB.
- **Solo lectura** al inspeccionar la tablet; **no leer `/dev/ttyACM0`** (un solo lector de
  consola).
- **Un cambio por ciclo**, con fila pre-registrada en
  `build/gates/PRE-REGISTRO-PANTALLA.md` y en el ledger del proyecto de origen.
- ⚠️ **Semáforo con el proyecto de origen**: `~/proyectos/ubuntu-permanente` puede tener sesión
  viva en la tablet. **Antes de tocar el dispositivo, comprobar en su `ESTADO-ACTUAL.md` y en
  las últimas entradas de `docs/FLASH-LEDGER.md` si la hay**, y si la hay, no flashear.
- Todo hallazgo se escribe con URL o con evidencia del dispositivo. **Nada de memoria.**

## Estado

- 26-sep-2026: proyecto creado y documentado. **7 informes cerrados (A–G)**, ~442 KB con fuente.
  Auditoría documental (`G`) hecha: 5 contradicciones resueltas y 2 huecos declarados
  (`H-backup-restauracion-uke.md`, `I-lapiz-uke.md`).
  **Este proyecto no ha ejecutado nada en la tablet** (pero el proyecto de origen sí: su ledger iba
  por **#442** el 27-sep). Estado del aparato: kernel `7.2.0-rc2-palawan+` (#82), par
  **`s244-bounce` + `s229`** en slot b. Ver `docs/historia/ESTADO-VIVO.md` para el detalle que cambia.
  > ⚠️ **Actualizado 2-oct-2026**: el párrafo anterior es histórico (era 26-sep). Este proyecto **sí**
  > ha ejecutado en la tablet (ciclos K23–K42, ledger hermano #443–#491). El par operativo es
  > `boot-ukek13-dsid.img` (`e0ee47dc…`) + `s260` en **slot a**; **solo `docs/historia/ESTADO-VIVO.md` manda**.
- **Fase 1 (F5) = abandonar Ubuntu y conseguir el primer boot de Arch.** El runbook está en
  `F-plan-por-fases.md` §F5. Principio: **no se cambia la cadena de arranque, se cambian dos payloads**
  (el `Image.gz`, que se reutiliza tal cual, y el initramfs). El `userdata` se sobrescribe con una
  imagen de Arch ARM de 8 GiB escrita por el mismo canal que ya funcionó (`wget | zcat | dd`), y la
  vuelta atrás son los 370 MB de la imagen de Ubuntu, que sigue en disco. D19 y D20 son las dos
  decisiones que faltan.
- **28-29 sep (sesión PANTALLA)**: objetivo declarado = la pantalla del todo. **EL PANEL PROBEA**
  (dtbo s258; bug del port pinctrl-cliffs esquivado por DT), el ABL dibuja splash, y el apps-smmu
  quedó acorralado por la serie de kernels K1-K6 (mapa de minas completo en docs/historia/ESTADO-VIVO.md;
  insight: Android binda el SMMU 7 ms antes de que el UFS arranque — la ventana temporal).
  Bitácora: `build/gates/PRE-REGISTRO-PANTALLA.md` (#P1-#P16). Pendiente: K7 (ventana Android) →
  bind → card0 → foto; luego GPU/CM3, táctil, e2fsck.
- 27-sep-2026: **revisión crítica con 4 subagentes** (ver `NOTAS-OMARCHY.md`). Hallazgos que cambian el
  plan: el par bueno era otro; `E` afirmaba un 404 que es falso (`edge/aarch64` publica 148 paquetes);
  y la incógnita del **chip ID de la GPU queda resuelta por lectura de código**: el kernel **no lee el
  silicio**, parsea el `compatible` del DT, que dice `0x43030b00` ⇒ **Mesa `main` ya lo conoce y el
  parche de Adreno 732 probablemente NO hace falta**. F1 se ha partido en F1a/F1b y F3 se ha
  reescrito con la evidencia del ledger.
- **28-29 sep noche (sesión PANTALLA en autonomía)**: panel VIVO (s258) y apps-smmu aislado fase
  a fase (serie K1-K7, `build/gates/PRE-REGISTRO-PANTALLA.md` #P8-#P21). K7 (cmdline armada,
  probe a 0,4449 s) = muerte muda con el confundidor `fastboot reboot` descubierto; K8 diseñado
  (port handoff del kernel lineage, vía H de `build/gates/revision/R4-nuevas-vias.md`).
  F9 probablemente resuelto (P7: vendor_boot_a/init_boot_a borradas el 24-sep). TODAS las
  funciones preparadas sin tablet en `build/gates/prepara/` (rotación, lápiz .ko, wifi, BT,
  energía, instalador Omarchy, fsck, audio) + 857 módulos kernel compilados. Decisivo y gratis:
  **arranque en frío de K7** (ver `docs/historia/RUNBOOK-MAÑANA.md`).
- **29-30 sep (LA GRAN SESIÓN)**: de "el SMMU mata siempre" a **card0 NACIDO**. Serie K7-K13
  (+dsid/fw): arming horneado a 4 s con handoff real, kms init completo, `card0-DSI-1` +
  `renderD128` con el sistema estable (`video=DSI-1:d`). Bloqueo final medido al milímetro
  (host DSI arrastrado al dominio paging) y **K16 diseñado** (split de grupos — diseño
  ejecutable en `build/gates/K16-DISENO.md`). Además: F9 RESUELTO (GPT reconstruida, #P31),
  instalador Omarchy auditado-GO, todas las funciones preparadas, brownout/gates/BCB/consola
  documentados como reglas. 43 filas en `PRE-REGISTRO-PANTALLA.md`.
- **30 sep / 1 oct (maratón de madrugada, #P44-#P49)**: **F9 CERRADO** (el slot A arranca Linux
  completo; slot A = experimental con fallback a B) · **e2fsck CERRADO** (corrupción estructural
  reparada; el drift del no-journal se regenera y se mitiga con fsck antes de cada ciclo) ·
  **WiFi causa-raíz** (GPIO 156 bt-enable en modo egpio) · **KILLER UNIFICADO pantalla+GPU
  localizado** (el release del CM3, S3-rst0: el kgsl-smmu no traducía el fetch del CM3 — el panel
  es inocente) y **desactivado capa a capa**: K16 (split grupos) → K18 (`uke_kgsl_keep`) → s263
  (dtbo: GPU y GMU al mismo SID 5) → K20 (`uke_gmu_shared`: un solo dominio) → K22 (**fw GPU
  horneados en el initramfs**: cargan a los 4,07 s del arranque y la escalera GMU completa corre
  en el boot) → **K23** (`8e7ed4f9…`, fix del dump; flasheado esperando el power-cycle de la
  mañana — ver `docs/historia/ESTADO-VIVO.md` para el plan numerado). El resto (WiFi dtbo, Omarchy) después.
