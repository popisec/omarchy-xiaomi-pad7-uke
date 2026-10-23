# CRÍTICA ADVERSARIAL L47 — veredicto y correcciones (14-oct-2026, tarde)

> Subagente crítico. Base leída: `docs/historia/revision/PIPELINE-PANEL-20261014/BRIEF.md`, `H2-CRASH-CAPTURADO-20261014.md`,
> `build/gates/patches/l47-migas-enable.diff`, `docs/historia/gates-palawan/repack-k52L47.py`,
> `build/kernel-config/k52L47.config`, dumps `out/h2-dumps/uke-{8,28,48}.txt.gz` +
> serie control, árbol vivo `build/kernel-pokes/k52-L16-tree`,
> `L39-{PLAN,RESULTADO,HALLAZGO}`, `HALLAZGO-L33-DEATH-20261013.md`,
> `AUDITORIA-METODO-20261013.md`, `docs/historia/revision/PIPELINE-PANEL-20261014/MANANA.md`, `docs/historia/revision/PIPELINE-PANEL-20261014/PARA-EL-FLASH.md`,
> `docs/historia/ESTADO-VIVO.md`, ledger #618–#620. Tablet: solo lectura (SSH). Árbol/parche: no tocados.

## 0. Veredicto: APROBADO-CON-CAMBIOS

El ciclo está bien apuntado (la ventana H2 47–68 s cae exactamente dentro del tramo que
instrumenta) y la variable FBDEV=n tiene mecanismo y evidencia. Pero el dossier del ciclo
contiene **4 errores factuales** (§1–§2) que hay que corregir antes del flash, y el
criterio necesita una rama más (§3). Ninguno bloquea el flash una vez corregido el papel:
**el árbol vivo YA contiene las 7 migas correctas y el repack ya gatea bien** — lo que está
mal es el parche archivado y la descripción del ciclo, no el contenido a flashear.

## 1. Verificación del parche de migas: sitios correctos, artefacto rancio

### 1.1. Los 7 puntos de inserción nuevos están bien (verificado en el árbol, fichero:línea)

| # | Miga | Sitio en el árbol | ¿Dentro de la función? |
|---|---|---|---|
| 1 | K47-atom-tail | `msm_atomic.c:215-216`, primera sentencia de `msm_atomic_commit_tail()` | SÍ |
| 2 | K47-dpu-hw-in | `dpu_kms.c:1142`, primera sentencia de `dpu_kms_hw_init()` (op `.hw_init`, `dpu_kms.c:1072`) | SÍ |
| 3 | K47-kms-en-commit | `dpu_kms.c:443`, primera sentencia de `dpu_kms_enable_commit()` | SÍ |
| 4 | K47-dpu-res | `dpu_kms.c:1460`, primera sentencia de `dpu_runtime_resume()` (registrado en `dpu_pm_ops`, `dpu_kms.c:1505-1506`, luego SÍ se usa pese al `__maybe_unused`) | SÍ |
| 5 | K47-enc-en | `dpu_encoder.c:1343`, primera sentencia de `dpu_encoder_virt_atomic_enable()` | SÍ |
| 6 | K47-brg-pre-en | `dsi_manager.c:282`, primera sentencia de `dsi_mgr_bridge_pre_enable()` | SÍ |
| 7 | K47-mgr-phy-en | `dsi_manager.c:140`, primera sentencia de `dsi_mgr_phy_enable()` | SÍ |

Includes `<linux/uke-poke.h>` presentes en los 4 ficheros (`msm_atomic.c:14`,
`dpu_kms.c:16`, `dpu_encoder.c:12`, `dsi_manager.c:7`). Ninguna miga cae en comentario ni
en otra función. La cadena de llamada es coherente con el orden esperado:
`commit_tail` (`msm_atomic.c:226` llama `kms->funcs->enable_commit`) →
`enable_commit` → `pm_runtime_get_sync` (dispara `dpu-res`) → helper
`commit_modeset_enables` → crtc → encoder → bridge → mgr → phy.

### 1.2. ERROR 1 (factual): el parche NO verifica lo que dice — 4 hunks fallan contra el árbol

`patch -p1 --dry-run` del parche contra el árbol vivo (solo lectura, sin modificar):

- `msm_atomic.c`: **2/2 hunks FAILED** (ya aplicado).
- `dpu_kms.c`: hunk `dpu_runtime_resume` **FAILED** (ya aplicado); los otros dos "succeed
  with fuzz/offset" = el árbol derivó desde que se generó el parche.
- `dpu_crtc.c`, `dpu_encoder.c`, `dsi_manager.c`: "succeed with fuzz/offset" (p. ej.
  crtc a offset −252) = **riesgo de duplicar** la miga en otro sitio si alguien lo aplica.
- `dsi_phy.c`: **FAILED** (ya aplicado).

Causa (medida, no memoria): el commit `ea6f744` ("Prep L47") aplicó las 7 migas al árbol
vivo a las 12:15–12:20 (mtimes de los 6 ficheros); el parche se generó después contra un
estado que ya las tenía. **"dry-run OK, aplicado == árbol" es FALSO contra el árbol vivo.**
Si el dry-run se hizo contra otra copia, no está documentada cuál: sin esa trazabilidad la
afirmación no es evidencia.

### 1.3. ERROR 2 (factual): no son "9 migas nuevas" — son 7; el inventario de previas está mal

- `K47-crtc-en` y `K47-phy-en` **ya están en la imagen L46** (`strings` del
  `k52L46-build/.../Image`: 21 tags K47 únicos, incluyendo `crtc-en`, `phy-en`,
  `enc-mset`, `enc-help`, `mgr-mset`, `vid-en`, `7nm-en`, `pll-prep`, `host-pwr`,
  `pwr-OK`, `pan-dcs`, `pan-unprep`, `pre-init` — herencia de la era L33,
  cf. `HALLAZGO-L33-DEATH-20261013.md:12-40`, que ya mostraba `enc-mset/mgr-mset/
  crtc-en/phy-en/host-pwr/pll-prep/host-en` en el commit de sddm a t=207 s).
- El dossier dice "7 previas + 9 nuevas = 16". Real: **L46 lleva ~21 tags; L47 añade 7**.
- El propio `repack-k52L47.py:328-334` ya lo sabe ("las 9 migas… (K47-crtc-en y
  K47-phy-en YA existían en L46: no se gatean como nuevas)" y gatea **7 tags ×1**):
  el script contradice al dossier y el script tiene razón.
- **Corrección**: regenerar el parche con solo los 7 hunks nuevos (o archivarlo como
  "delta documentado L46→L47", no como "parche aplicable"). El gate válido es el del
  repack (por-tag ×1), no "contar K47- = 16".

### 1.4. ERROR 3 (bug real en el parche): `K47-phy-en` duplicado en `dsi_phy.c`

El diff trae DOS líneas `+uke_poke("K47-phy-en");` seguidas (líneas 89–90 del diff). El
árbol tiene UNA (`dsi_phy.c:742`). Aplicar el parche duplicaría (×2 por link ×2 links =
×4 por enable) y destruiría la firma L33 "phy-en ×2 = dual-link" (`HALLAZGO-L33:207.915`).
Al regenerar (§1.3), el hunk de `dsi_phy.c` se elimina entero (ya existe).

### 1.5. Camino caliente y E6: riesgo bajo pero con dos matices obligatorios

- La cita "E6: la instrumentación movió el punto que medía" remite en realidad a
  `AUDITORIA-METODO-20261013.md:53` (ronda L33→L37: un **flush/early-return funcional**
  quemó el termómetro `video_done`, L36) — no a pokes printk. Los pokes son
  funcionalmente inertes (`pr_err` + pintado lock-free sin `spin_lock`/`mutex` en
  `uke-panic-fb.c`; como asesinos están **falsados** en el proyecto hermano, X9
  s166/s167, citado en el propio `uke_poke()`). Aplicar E6 a los pokes es una
  extrapolación, no una lección: **corregir la cita**.
- Matiz 1 — `dpu-res` es **ambiguo**: `dpu_runtime_resume` también lo dispara
  `pm_runtime_resume_and_get()` de `dpu_kms.c:1165` (vía `hw_init`), no solo el commit.
  Regla de lectura prefijada: `dpu-res` aislado no prueba modeset; solo vale en la
  secuencia `atom-tail → kms-en-commit → dpu-res`.
- Matiz 2 — `dpu-hw-in` puede disparar en el bind (op `.hw_init`), incluso sin modeset.
  No usarlo como prueba de commit; es corchete, no señal.
- ¿Falta alguna función clave? Revisados `msm_atomic.c`, `dpu_kms.c`, `dpu_crtc.c`,
  `dpu_encoder.c`, `dsi_manager.c`, `dsi_phy.c`: el tramo commit→PHY queda cubierto sin
  huecos msm-owned. El único hueco real (commit-pedido vs tail-ejecutada: `msm` no
  sobreescribe `.atomic_commit`, el commit entra por core) lo cubren gratis las líneas
  fbdev del log (`pan-modes`+`fb0`, §2.1). **No añadir más pokes**: un cambio por ciclo
  (BRIEF regla 4; las migas son instrumento, no variable — combinación legítima porque
  son inertes, pero no ensancharla).

## 2. Crítica del cambio FBDEV=n: coherente, mecanismo confirmado, contraevidencia resuelta

### 2.1. La evidencia del dump existe (aunque H2 no la destaca)

`uke-48.txt.gz` líneas 2926–2933: `K47-pan-modes` → **`fbcon_init: detected unhandled
fb_set_par error, error code -16`** → `Console: switching to colour frame buffer device
400x133` → `fb0: sys_imageblit/fillrect: framebuffer is not in virtual address space` →
`fb0: msm-kmsdrmfb frame buffer device` → segundo `pan-modes` → burst `sync_state` →
silencio tras 47.6 s. H2 describe el silencio pero omite estas 5 líneas: son el eslabón
`get_modes → fbdev-setup → commit` y hay que incorporarlas a H2 (§1 del informe).

### 2.2. Mecanismo confirmado en el árbol (no es hipótesis)

`drm_client_setup()` (`drivers/gpu/drm/clients/drm_client_setup.c:42-53`): con
`CONFIG_DRM_FBDEV_EMULATION=n` y default `fbdev`, **no hace nada** (ni cliente fbdev, ni
auto-modeset al registrar). `msm_drm_kms_post_init` (`msm_kms.c:399`) la llama siempre ⇒
con =n desaparecen a la vez el auto-modeset de boot, el `fb0 msm-kmsdrmfb` y el takeover
de fbcon por esa vía. `k52L47.config` difiere de `k52L46-build/.config` en **exactamente
1 línea** (la 4864): variable única y limpia.

### 2.3. La contraevidencia L39/L33 NO invalida (resuelta con `.config` reales)

- El dossier teme: "L39 con FBDEV=n también moría". Verificado: **cierto que L39 llevaba
  =n** (`k52L39-build/.config:4861`, aunque el versionado `k39.config` diga =y —
  divergencia a anotar), **pero L39 moría a <3.5 s** (`HALLAZGO-L33-DEATH:173`), 44 s
  antes de la ventana fbcon/modeset de H2 y en otro linaje (PPS×2, reset 15 ms). No llegó
  al tramo que H2 localiza: no testea la hipótesis H2-fbdev.
- Igual para L33 (`k52L33-build/.config:4861` =n; vivía y el commit lo disparaba sddm a
  t=207 s). La lección de L33 es al revés: **con =n el sistema vive y el modeset lo puede
  disparar userspace** — eso es exactamente el diseño L47+modetest.
- El `-16` es `EBUSY` del `fb_set_par` de fbcon sobre un fb no mapeado a CPU: marcador,
  no asesino (el boot sigue hasta 47.6 s). No presentarlo como causa.

### 2.4. Qué más cambia con =n (revisado, sin sorpresas)

- `fb0` desaparece; `fbcon=map:0` y `console=tty0` de la cmdline quedan inertes (la
  consola sigue en `ttyGS0`/`ttynull`); `plymouth.enable=0` ya estaba; `FB_VFB` no está
  compilado (sin match en `k52L47.config`) así que `video=vfb:...` no crea fb alternativo;
  `FRAMEBUFFER_CONSOLE=y` queda sin fb al que bindearse (inerte).
- `diag-snapshot.sh`/volcador leen `dmesg`+sysfs DRM, no `/dev/fb0` (sin dependencia).
  `uke_poke()` pinta en región reservada propia, no en fb0 (no le afecta).
- ¿Enmascara en vez de curar? **Sí, por diseño**: =n retira el trigger (commit de boot),
  no arregla el enable. Por eso el ciclo SOLO concluye con la fase modetest (§3): un
  PASA-sin-modetest no es un PASA-diagnóstico.

## 3. Criterio y runbook corregidos

### 3.1. El PASA/FALLA del dossier es incompleto: con =n puede no haber modeset y las migas callarían en ambos casos

Reformulación prefijada (4 ramas, excluyentes):

- **PASA-A** (vive >6 min, sin `atom-tail`): =n retira el trigger de boot. No confirma ni
  refuta H2-fbdev → **modetest obligatorio en el mismo ciclo** (sin escritura extra).
- **PASA-B** (modetest completa el modeset sin muerte, con o sin luz): el enable-path
  funciona sin fbcon ⇒ el asesino era específico del cliente fbdev/takeover. Siguiente:
  vci/DCS con modeset userspace.
- **FALLA-B** (muerte con `atom-tail` + migas hasta el punto X): H2-fbdev confirmado como
  trigger; el asesino está en X (última miga impresa). Siguiente: clocks/GDSC en X.
- **FALLA-A** (muerte en ventana 47–70 s con =n pero SIN `atom-tail`): **H2-fbdev
  REFUTADO** como trigger; muerte independiente del modeset → releer H2 (sync_state/
  GDSC por otra vía). Que las migas callen aquí es lo ESPERADO, no un fallo del instrumento.
- **FALLA-C** (muerte <20 s, estilo L33/L39): otra muerte (los pokes o =n exponen otra
  vía) → no concluye sobre H2; comparar contra control display-off del mismo build.

Regla de lectura de migas (E6 bien aplicado): la última miga = "murió EN o DESPUÉS";
`dpu-res`/`dpu-hw-in` aislados no valen (§1.5).

### 3.2. modetest: verificado en vivo (solo lectura, 14-oct)

- Existe: `/usr/bin/modetest` en la tablet; driver DRM = **`msm`**
  (`modetest -M msm` abre `MSM Snapdragon DRM`; `/sys/class/drm/card1/device/driver` →
  `msm_dpu`); `/dev/dri/card1` presente.
- Comandos prefijados (en el boot L47 display-ON, por SSH): primero **solo lectura**
  `modetest -M msm -c` (esperar `card1-DSI-1: connected` + lista de modos); después
  **un solo intento** `modetest -M msm -s <conn-id>:<modo-preferido>` usando un modo DE
  LA LISTA (E6/L35-L36: prohibido inventar 60 Hz). Ojo: con display-off el `-c` hoy da
  `drmModeGetResources failed`; si persiste con display-ON, el fallback es sddm/greeter
  (vía L33) en otro ciclo, no insistir.
- Riesgo-slot (el constraint vinculante): H2 quemó `a:6→0` en ~5 boots; el watch
  físico es obligatorio (R-42: sin recuperación automática). **Un solo intento de
  modetest**; si cuelga, reset físico y parar (sin segundo intento el mismo día).
  Fallback prefijado: reflash L45 a `boot_a` (recovery, 1 escritura).

### 3.3. Presupuesto y pre-vuelo (advertencia real)

- Hoy 14-oct ya van ~6 escrituras físicas (#618, #619, #620×2, re-flash H2, restore
  L45): el gate "≤2/día" está de facto eximido por el dueño ("da igual la batería"),
  pero debe constar en la fila del ledger, no darse por supuesto.
- L47 = **1 escritura** (`boot_a`; `dtbo_a` s287 se queda). Pre-vuelo: `getvar all`
  (retries a/b + unbootable + mV inicial/final), ACM único + dumper armados, pausa del
  vigía durante el flash. recabar confirmación de que ningún slot quedó `unbootable`
  antes de flashear (si `a` sigue tocado del H2, el ciclo se mueve a mañana).

## 4. ¿Maximiza información por escritura? Casi — cambios concretos

1. **Regenerar `l47-migas-enable.diff`** (7 hunks: quitar `dpu_crtc.c` y `dsi_phy.c`,
   quitar 1 de las 2 líneas duplicadas donde corresponda) y archivarlo como delta
   documentado L46→L47; el gate que manda es el del repack (7 tags ×1, ya correcto).
   [bloqueante-papel, 10 min, sin coste de escritura]
2. **Corregir el dossier**: "9 migas/16" → "7 migas sobre 21 previas"; E6 citado al
   revés (§1.5); incorporar las 5 líneas fbcon a H2 §1; anotar la divergencia
   `k39.config` (=y) vs `k52L39-build/.config` (=n).
3. **Adoptar el criterio de 4 ramas + modetest obligatorio** (§3.1–§3.2) como criterio
   prefijado del ciclo (sustituye al PASA/FALLA binario).
4. **No añadir nada más** (ni `msm_atomic_commit`, ni pokes clk/GDSC): el hueco
   commit-pedido ya lo bracketean `pan-modes`/`fb0`; el resto es otro ciclo.
5. **No cambiar**: base L46+s287 ✓, variable única FBDEV=n ✓, display-ON 566 B ✓,
   repack clon + gates ✓, doble captura ✓.

Con 1–5 aplicados, el ciclo distingue {fbcon-takeover vs enable-path vs muerte
independiente} en UNA escritura + un modetest sin escritura: eso sí es máxima
información por escritura.
