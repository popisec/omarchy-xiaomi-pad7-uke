# VERIF-K52B2-PANTALLA — revisión del kernel/imagen k52b2 (14-oct-2026)

Solo lectura; todo medido salvo lo marcado [HIPÓTESIS]. Fichero:línea como evidencia.

## 1. Qué era el k52b2 [MEDIDO]

- Ciclo #534 del proyecto hermano (6-oct-2026): testbed estable GPU-off, SSH/batería/card0
  (`~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md:10286-10310`, `NOTAS-OMARCHY.md:2409-2418`).
- Imagen `build/bootimg/boot-uke-k52b2-bateria.img` (6-oct 17:30, 100663296 B); kernel =
  **k18-tree + config k52-bateria** (= k49-pantalla + grupo A energía), commit `4bf4bdb`
  (`git show 4bf4bdb --stat`); vermagic `7.2.0-rc2-palawan` sin `+` (ledger:10288).
- DTBO compañero: **s269** (`8893fe37…`); initramfs `build/init/uke-k34-fw-k52b2-initramfs.cpio.gz`;
  diag `uke-k52b2-diag-initramfs.cpio.gz` (report `build/init/repack-uke-k52b2-diag-initramfs-report.txt`).
- Rol posterior: rollback perpetuo y referencia de gates (p.ej. `docs/historia/gates-palawan/repack-k52L50.py:392-423`
  exige initramfs embebido byte-idéntico al del k52b2).

## 2. Display/backlight del k52b2 [MEDIDO en binario + fuentes + config]

- Backlight **INTERNO DCS 0x51**, sin KTZ: `o82_bl_update_status()` →
  `mipi_dsi_dcs_set_display_brightness_large()` en ambos links, registrado con
  `devm_backlight_device_register(... dev_name(dev) ...)` = device `ae94000.dsi.0`
  (`build/gates/patches/k49-fuentes/panel-xiaomi-o82-dualdsi.c.post-k49:484-523`).
- Niveles: MIN 4 / MAX `0xfff` (4095) / INIT `0x133` (307) (`:42-45`). El `307/4095` medido en
  vivo es el INIT del driver, no luz real (ver §3).
- Binario verificado (Image extraído del bootimg, offset 4096, gzip): `K47-pan-bl` ×1
  (el poke dentro de `o82_bl_update_status`), `UKE-P82` ×21, `ktz`/`KTZ` ×**0**, `cont_splash` ×0,
  `simplefb` ×0 (`/tmp/opencode/k52b2-Image`, comandos en sesión).
- Config `build/kernel-config/k52-bateria.config`: `CONFIG_BACKLIGHT_KTZ8866` **not set**
  (`:5226`), `CONFIG_DRM_PANEL_XIAOMI_O82_DUALDSI=y` (`:5120`),
  `CONFIG_DRM_FBDEV_EMULATION=y` (`:4864`), `CONFIG_SYSFB_SIMPLEFB` not set (`:2006`).
- DT: el nodo `panel@0` **no trae propiedad `backlight`** (fusión s238,
  `build/gates/EVIDENCIA-PANTALLA-28sep.md:189-198`) ⇒ el driver registra el interno siempre.
- Cmdline del k52b2 (497 B, header bootimg @64): `... console=tty0 fbcon=map:0 ...
  **video=DSI-1:d** ... memmap=0x2B00000$0xE3940000 ...` (extraída con python, sesión).
  **Conector DSI deshabilitado + región splash del ABL (`0xe3940000`, 43 MB) reservada.**

## 3. ¿Encendía la pantalla? NO por Linux [MEDIDO + inferencia marcada]

- Con `video=DSI-1:d` el conector nace `disabled` ⇒ `o82_prepare` **nunca corre** (0 marcas
  `UKE-P82:` en el boot vivo L19; `NOTAS-OMARCHY.md:2911-2915`). Sin prepare no hay DCS 0x51
  ni `backlight_enable` (`panel-...c:400`, citado en `NOTAS-OMARCHY.md:2927-2929`).
- Lo visible era el **splash del ABL congelado**: `memmap` lo preserva y nada de Linux lo toca
  (`NOTAS-OMARCHY.md:2960-2964`: "backlight 307/4095 ... es remanente del ABL, no de Linux").
- El dueño recuerda "pantalla encendida" = ese splash/retro del ABL, no un encendido por Linux.
- `out/acm-r33.log` (captura del 13-oct, 70435 líneas; mezcla boots con pokes `UKE-POKE`
  SMMU + bloque `---K49---` con `UKE-K49: esd gpio` en `:14582-14584`): el
  `systemd-backlight@backlight:ae94000.dsi.0 FAILED` repetido (`:4727` y ~10 más) prueba que
  el **device interno existía pero systemd no podía guardar/cargar brillo** — coherente con
  panel registrado en probe pero jamás preparado. El `FAILED` es síntoma, no luz.
  [HIPÓTESIS menor: el motivo exacto del FAILED (sin `actual_brightness` válido) no se leyó
  `systemctl status` en vivo; el device existiendo está medido por el nombre de la unidad.]

## 4. Qué difiere hoy (L52) [MEDIDO]

| | k52b2 | L52 (`k52L52.config`, `k52-L16-tree` + L43–L52) |
|---|---|---|
| Backlight | interno DCS 0x51 | **externo KTZ8866** (`CONFIG_BACKLIGHT_KTZ8866=y` `:5226`; panel usa `drm_panel_of_backlight`, DT `backlight = <&ktz_bl_0>`) |
| FBDEV | `DRM_FBDEV_EMULATION=y` | `=n` (refutado H2-muerte; `repack-k52L52-report.txt:24`) |
| Cmdline | 497 B **con** `video=DSI-1:d` | 608 B **sin** `:d` (display-ON) + `iomem=relaxed` + `arm_smmu.uke_disp_reclaim=1` |
| Commit DRM | nadie lo pide | commit completa, vídeo ON, 184 s vivo (#627, `NOTAS-OMARCHY.md:4687-4690`) |
| KTZ | inexistente | al máximo (`0x08=0x7f`, nivel `0x7FF`) sin luz → frente boost→LEDs o receta |

## 5. Recomendación concreta

Probar el **camino interno DCS 0x51 como vía alternativa en un build display-ON**: el DCS
llega al panel (L19: `K47-pan-bl`+`host-xfer` 7,72 s, `NOTAS-OMARCHY.md:2913-2914`) y el vendor
no lo usa para brillo ([MEDIDO] `NOTAS-OMARCHY.md:4141-4144`: vendor va por KTZ + sets
0xfb/0xfc) — es decir, es un camino **no intentado con vídeo vivo**. Concreto: sobre el árbol
L52, reactivar `o82_create_backlight()` interno (revert parcial del hunk L44 `988af8b`,
manteniendo el nodo KTZ en DT como fallback) y exponer `brightness` por sysfs con el commit
ya estable; éxito = DCS 0x51 medido en `host-xfer` + luz. Riesgos: (a) doble registro si el
core también enlaza el KTZ → gatear a un solo `backlight` por build; (b) el DCS-glow sin
boost no da luz si el problema es físico (KTZ al max ya lo sugiere) → este test **discrimina
receta vs hardware**, no lo arregla todo; (c) 1 escritura de slot, presupuesto ≤2/día, con
rollback a L52 (`0cd89f96…`). No reflashear nada k52b2: su "luz" era splash ABL, no receta.
