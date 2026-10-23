# U2-POSTFW — Muerte post-fallo-de-fw (K13+s260, kernel #17): traza, log, diseño K16 y plan

> 30-sep-2026 noche. SIN tablet (solo lectura de árbol `/var/tmp/uke-k13-tree`, logs `/var/tmp/k14*.log` y docs de gates).
> Fuentes: PRE-REGISTRO #P36-#P40, prepara/G1-gpu-render.md, k14-cycle.log (2574 líneas, 9 boots).

---

## 1. TRAZA: ¿el fallo del SQE aborta limpio o continúa al GMU?

**Aborta LIMPIO. El GMU jamás arranca. La teoría "wedge en readl sin fw" queda REFUTADA para el boot.**

Cadena file:line (árbol k13):

1. `adreno_request_fw()` — `drivers/gpu/drm/msm/adreno/adreno_gpu.c:527-605`. Tres intentos: directo
   `qcom/gen71100_sqe.fw` (:542-556), legacy sin prefijo (:558-572), helper `request_firmware` (:574-588).
   Los 3 → -ENOENT a las 4,2 s porque el rootfs AÚN NO está montado (el open del fbdev ocurre en fase
   initrd; switch_root llegó a 15,7 s en el boot sano #82) y `firmware_class.path=/vendor/...` tampoco
   está montado. Sale por :590-593 con `ERR_PTR(-ENOENT)` (el 2º print del log: `[drm:adreno_request_fw] *ERROR*`).
2. `adreno_load_fw()` — `adreno_gpu.c:607-628`: `if (IS_ERR(fw)) return PTR_ERR(fw);` (:622-623).
   Aborta al primer fw que falle; no intenta el GMU.
3. `adreno_load_gpu()` — `adreno_device.c:68-107`: `ret = adreno_load_fw(adreno_gpu); if (ret) return NULL;`
   (:92-95). **Crítico**: este retorno ocurre ANTES de `pm_runtime_enable` (:100) y de
   `pm_runtime_get_sync` (:103). El dispositivo GPU queda con runtime PM deshabilitado ⇒ nunca hay
   `a6xx_gmu_pm_resume` (`a6xx_gpu.c:2132`) ⇒ nunca `a6xx_gmu_resume` (`a6xx_gmu.c:1350`) ⇒ nunca
   `a6xx_gmu_fw_start` (:958) ⇒ **ningún readl de `FW_INIT_RESULT`**. El CM3 no se toca.
4. `load_gpu()` — `msm_drv.c:198-207`: `priv->gpu = adreno_load_gpu(dev)` — el NULL se asigna y se ignora.
5. `msm_open()` — `msm_drv.c:265-272`: llama `load_gpu(dev)` (:270) y `return context_init(dev, file)`
   — **la apertura del drm file TERMINA EN 0**. Todo consumidor posterior soporta priv->gpu==NULL
   (p. ej. `msm_gpu_create_private_vm`, `msm_gpu.c:860-866`: `if (!gpu) return NULL`).

**Empírico**: 0 apariciones de Z4/H1-H10/F1-F4/P1-P3/S1-S4/CM3DBG/G1-G4 en TODO k14-cycle.log
(grep count = 0 sobre 9 boots). El GPU murió en silencio antes de despertarse. El ENOENT NO mata el sistema.

### ¿Y entonces por qué muere el sistema entero?

El asesino está en el CONTINUADOR del msm_open, no en el fallo del fw:

- `msm_drm_kms_post_init()` — `msm_kms.c:392-399` — tras registrar card0 llama
  `drm_client_setup(ddev, NULL)` (:399) → `drm_fbdev_client_setup` (`drivers/gpu/drm/clients/drm_client_setup.c:35-50`)
  → el cliente fbdev abre el drm file (ahí salta el ENOENT, 4,2 s) y **SIGUE**: fbdev emulation →
  primer modeset real → enable del panel o82 (dual-DSI DSC) → primer scanout DMA por el dominio del
  fallback attach_group (dpu+mdss+unsec_cb, grupo de 3 en un dominio, parche K13).
- Ese tramo (4,2→13,8 s) es la ventana que la consola ACM pierde SIEMPRE por la inundación de printk
  (en el boot sano #82: k14-live.log:92-113, `[missed 4864 bytes]` en 0,32 s y siguiente línea a 13,8 s).
  En los 9 boots capturados del ciclo, tras ~4,0-4,2 s NO vuelve a salir NADA — ni siquiera el punto
  13,8 s de "deferred probe timeout" que en #82 SÍ sale (k14-live.log:113) ⇒ **el cuelgue es ≤13,8 s**,
  es decir dentro del tramo fbdev-modeset/panel/primer-scanout (o ukeinit S123/UFS, menos probable).
- **Por qué muere TODO y no solo el GPU**: cmdline lleva `hung_task_timeout_secs=20 hung_task_panic=1`
  y `kernel.panic_on_rcu_stall=1`. Cualquier tarea bloqueada >20 s (el hilo del component bind /
  deferred_probe_work_func → drm_client_setup → fbdev modeset, o un kworker de fbcon/DPU) panic-ea el
  SISTEMA COMPLETO; `panic=10` re-arranca. El dump de la tarea colgada NO aparece en el log porque en
  ese momento la consola (y posiblemente el bus que alimenta USB) ya no emite. Con la ACM "presente
  parpadeante" (#P38), cada ciclo re-enumeraría el USB ⇒ firma compatible con ciclos de ~30-40 s
  (colgado +20 s hung_task +10 s panic) × 7 (boot_index 26→32) y latch final del ABL.
- **Estado de esta hipótesis**: fuerte pero NO observada directamente (no hay ni panic ni hung-task
  dump en el log). Lo único observado con certeza: kms pasa, card0 nace, ENOENT a 4,1-4,2 s, y el
  sistema deja de emitir consola para siempre en ese boot.

---

## 2. EL LOG: qué hay DESPUÉS del error de fw (kernel #17)

Mapa de /var/tmp/k14-cycle.log: 9 boots capturados — 2 del kernel #16 (boot_index 22, 25) y **7 del #17**
(boot_index 26, 27, 28, 29, 30, 31, 32). El ENOENT se capturó en 4 de los 7 ciclos #17
(4,203 s / 4,208 s / 4,103 s / 4,147 s). Tras el error: **NI GMU FW_INIT, NI panic, NI silencio
estructurado — silencio TOTAL y luego el banner del siguiente boot.** Los ciclos 27/30/31 ni siquiera
llegan a mostrar el ENOENT (la consola pierde el trozo 3,97→fin; mismo `[missed 932 bytes]` en el mismo
punto 4,02-4,03 s: caída determinista).

Últimas ~25 líneas legibles del ciclo más completo (boot 29, líneas 2196-2220), anotadas:

```
[    4.092513] sd 0:0:0:1: [sdb] 3072 4096-byte logical blocks   ← UFS ya enumerado (LUNs)
[    4.092552] sd 0:0:0:1: [sdb] Write Protect is off
[    4.092619] sd 0:0:0:0: [sda] Write cache: enabled...
[    4.092671] sd 0:0:0:1: [sdb] Write cache: disabled...
[    4.092951] sd 0:0:0:3: [sdc] 2048 4096-byte logical blocks
[    4.092983] sd 0:0:0:3: [sdc] Write Protect is off
[    4.093047] sd 0:0:0:3: [sdc] Write cache: enabled...
[    4.093211] sd 0:0:0:4: [sde] 499712 4096-byte logical blocks
[    4.093250] sd 0:0:0:4: [sde] Write Protect is off
[    4.093312] sd 0:0:0:4: [sde] Write cache: enabled...
[    4.093371] sd 0:0:0:2: [sdd] 3072 4096-byte logical blocks
[    4.093407] sd 0:0:0:2: [sdd] Write Protect is off
[    4.093644] sd 0:0:0:5: [sdf] 16384 4096-byte logical blocks
[    4.093697] sd 0:0:0:5: [sdf] Write Protect is off
[    4.093788] sd 0:0:0:5: [sdf] Write cache: enabled...
[    4.093792] sd 0:0:0:2: [sdd] Write cache: disabled...
[    4.103432] msm_dpu ae01000.display-controller: Direct firmware load for qcom/gen71100_sqe.fw failed with error -2   ← 1er intento (directo qcom/) ENOENT
[    4.103455] msm_dpu ae01000.display-controller: [drm:adreno_request_fw] *ERROR* failed to load gen71100_sqe.fw        ← adreno_request_fw sale -ENOENT (tras 3 intentos)
[    4.105472] sd 0:0:0:2: [sdd] Attached SCSI disk               ← ÚLTIMAS 5 líneas del boot:
[    4.105804] sd 0:0:0:3: [sdc] Attached SCSI disk               ←   el kernel SIGUE vivo ~3 ms después
[    4.106007] sd 0:0:0:5: [sdf] Attached SCSI disk               ←   del ENOENT (no fue el fw quien mató)
[    4.106549] sd 0:0:0:0: [sda] Attached SCSI disk
[    4.106665] sd 0:0:0:1: [sdb] Attached SCSI disk
                                                                    ← SILENCIO ABSOLUTO: ni F1/S1 del GMU
                                                                    ←   ni "deferred probe timeout" (13,8 s)
                                                                    ←   ni ukeinit S123 (~5-6 s) ni systemd (16 s)
[    0.000000] Linux version 7.2.0-rc2-palawan ... #17 ...        ← boot siguiente (boot_index+1)
[    0.000000] random: crng init done
```

Contraste decisivo: **kms fallando = vida** (stock #82, k14-live.log: kms -19 a 13,93 s + Oops
`dead000000000108` en dpu_kms_destroy — y el sistema vivió >7189 s con consola fluyendo);
**kms pasando = muerte muda** (9/9 boots de prueba, #16 y #17, sin una sola línea post-4,2 s).

---

## 3. K16 (SOLO DISEÑO): ¿(a) fw, (b) fallo no-fatal, (c) both?

**(c), pero redimensionado — y con una corrección al enunciado:**

- **(b) YA ES EL COMPORTAMIENTO ACTUAL.** El fallo de fw ya aborta limpio y el KMS+fbdev siguen
  (§1, pasos 2-5). Un parche que devuelva -EPROBE_DEFER sería CONTRAPRODUCENTE: `load_gpu` no es un
  probe (nadie re-probaría), y el retry real ya existe — el ENOENT es por-llamada: el SIGUIENTE
  `open()` de card0 con rootfs montado SÍ encuentra el fw (fwloc queda UNKNOWN hasta el éxito,
  adreno_gpu.c:532). "GPU opcional" ya existe de serie: fbcon no usa el GPU.
- **fbcon NO necesita el GPU — cita del mecanismo**: `msm_kms.c:399` llama
  `drm_client_setup(ddev, NULL)` → `drm_client_setup.c:43-49` (`CONFIG_DRM_FBDEV_EMULATION`) →
  `drm_fbdev_client_setup` → cliente fbdev genérico (drm_fb_helper): 100% camino display. El ÚNICO
  contacto con el GPU es el EFECTO LATERAL de abrir el drm file: `msm_open` → `load_gpu`
  (`msm_drv.c:270`), cuyo fallo se ignora (:265-272). **SÍ habría fbcon en pantalla con el fw
  fallando — si el propio modeset del fbdev no fuera lo que wedgea** (§1: la evidencia apunta a eso).
- **(a) el fw correcto es IRRELEVANTE para el boot y NECESARIO solo para render**: el open del fbdev
  ocurre a 4,2 s, en fase initrd — el rootfs (donde el fw YA ESTÁ: `pacman -Qk uke-gpu-firmware` = 14
  files 0 missing, VERIFICACION-ORQUESTADOR.md:793-802; G1 §2.2) se monta DESPUÉS. Con el fw
  instalado, el boot de mañana sacará el MISMO ENOENT a 4,2 s. Poner el fw en el initrd exigiría
  repack del boot.img y SÓLO serviría para arrancar el CM3 EN EL BOOT = maximizar el riesgo wedge
  (G1 §4) justo cuando nadie mira. NO hacerlo.
- **Lo que SÍ vale un parche K16** (pequeño): gate para GPU-bajo-control + aislar el modeset (§4/§5).

---

## 4. CM3 wedge: migas existentes y primera miga tras cargar el sqe.fw

**Migas ya en el kernel k13 (grep del árbol):**
- `adreno_device.c:241-251`: G1-bind / G2-initFAIL / G2-initOK / G3-icc; `a6xx_gpu.c`: G4-llc.
- `a6xx_gpu.c:2142-2144`: **Z4-gmuresume** / Z4-gmuresFAIL / Z4-gmuresOK (en `a6xx_gmu_pm_resume`).
- `a6xx_gmu.c` cadena completa: H1-rpm (:1362) → H2-gx (:1366) → H3-clk(:1377)/H3-clkFAIL →
  CM3DBG clks (:1384) → H4-mmio (:1399) → H5-boot (:1418) → [fw_start :958] H6-rsc(:999)/FAIL →
  H7-fw(:1001)/FAIL → F1-fwloop(:906) → F2-itcm(:914)/F2-dtcm(:920) → F3-loopOK(:934) → F4-verOK(:936)
  → CM3DBG fw-map(:950) → P1-initres(:1007) → P2-qtbl(:1012) → P3-pwr(:1078)/P3-pwrOK(:1080) →
  [a6xx_gmu_start :291] CM3DBG dtcm-magic(:311) → S1-rst1(:316) → S2-gen9(:327) → S3-rst0(:331) →
  **sondeo `gmu_poll_timeout(FW_INIT_RESULT)`** → S4-poll(:335) → H8-cm3(:1087)/FAIL →
  H9-hfiq(:1106)/FAIL → H10-hfi(:1427)/FAIL.

**Primera miga tras cargar el sqe.fw**: la carga del SQE en sí no pinta nada (es `request_firmware`
en CPU). El arranque del CM3 empieza en el primer runtime-resume: **Z4-gmuresume → H1-rpm**; la firma
del wedge conocido (ramaa 24-sep, G1 §4) es **última marca S3-rst0 con S4-poll ausente** — el primer
`readl` del sondeo de `FW_INIT_RESULT` no vuelve. `CM3DBG dtcm-magic` distingue "imagen no llegó a la
RAM del CM3" de "CM3 no termina". El canario fino L14 (`uke-cm3-ladder.diff`, ya compilado OK,
build/cm3-ladder/) pincha el readl exacto.

**Gate para K16 (GPU bajo control)**: parámetro de módulo msm, p. ej. `msm.uke_skip_load_gpu` (0644,
flipable en caliente), consultado al inicio de `load_gpu()` (`msm_drv.c:198-207`): con 1, no llamar a
`adreno_load_gpu` — el fbdev queda KMS-only y el CM3 jamás arranca AUNQUE el fw esté presente; luego,
con doble captura viva (measure-cm3.sh, build/cm3-ladder/), se abre card0 a mano (eglinfo/modetest) y
la escalera Z4→H1→…→S4 dice hasta dónde llegó. Complemento: aplicar `uke-cm3-ladder.diff` (canario
L14) al mismo K16. NOTA: mientras el initrd no lleve fw, el estado de arranque YA deja el GPU dormido
(ENOENT inofensivo) — el gate solo es imprescindible si algún día se mete fw al initrd o si userspace
abre card0 solo.

---

## 5. PLAN FINAL (3 pasos, sin ejecutar; gates: batería ≥3750 mV, lector de consola activo ANTES)

**Estado hoy**: tablet en fastboot; slot b = boot_b `boot-ukek13.img` (d71ea2b5…) + dtbo_b `s260`
(6fbb5173…); misc limpia; fw ya instalado en el rootfs del sistema viva; mesa/libdrm/mesa-utils
AUSENTES en el rootfs (G1 §6).

- **PASO 1 — kernel bueno + SSH (1 flash o 0)**: flash `boot_b` =
  `build/backup-par-bueno/boot_b-lee.img` (ffff8c51…) [variante 0-flash si el ABL lo permite:
  `fastboot boot boot_b-lee.img`]. dtbo_b NO se toca (s260 con kernel bueno = kms -19/-22 = estable,
  demostrado #P39). Boot → SSH → (i) VERIFICAR (no scp por defecto): `pacman -Qk uke-gpu-firmware` y
  `sha256sum` de `/usr/lib/firmware/qcom/gen71100_sqe.fw` + `/usr/lib/firmware/gen71100_sqe.fw`
  (8 rutas; deben casar con `build/gates/firmware-gpu.sha256`) — solo reinstalar el paquete si falta;
  (ii) `pacman -S --needed mesa libdrm mesa-utils` + `sync` (para el render a mano del paso 3);
  (iii) preparar doble captura viva + copiar `measure-cm3.sh` dentro.
  *Corrección al enunciado*: el fw NO requiere flash ni repack (ya está en el rootfs) y el
  "siguiente boot lo prueba" no prueba el fw en el boot — el boot SIEMPRE sacará el ENOENT de 4,2 s.
- **PASO 2 — 1 flash (boot ya construido), PANTALLA OBSERVADA**: flash `boot_b` = `boot-ukek13.img`
  (d71ea2b5…); dtbo_b = s260 queda. Reboot mirando EL PANEL (pregunta decisiva #P38, sigue sin
  respuesta) + lector de ciclos. Mirar: (a) ¿texto fbcon en pantalla en la ventana viva?
  (b) ENOENT ~4,2 s y cero migas GMU después (abort limpio, confirmación); (c) pantalla NEGRA ⇒ el
  cuelgue es el modeset/panel/primer-scanout del fbdev — el fw no cambia esto; (d) separación entre
  banners ⇒ calibra hung_task(+20 s)+panic(10) vs cuelgue instantáneo.
- **PASO 3 — condicional, 1 flash (repack del k13)**: si pantalla negra → repack `boot-ukek13.img`
  con cmdline extra `video=DSI-1:d` (conector disabled: fbdev sin modeset = sin scanout).
  - Sobrevive (SSH estable con KMS) ⇒ asesino = enable del panel / scanout ⇒ siguiente batalla es
    DISPLAY (por qué el ABL aborta el fragment@1710 del s261; alternativa "dpu solo"), con el GPU
    aún dormido.
  - Muere igual ⇒ NO es el panel ⇒ sospecha pasa al dominio del fallback attach_group (SMMU) ⇒ migas
    en msm_iommu/dpu en K16.
  - En paralelo, K16 definitivo: `msm.uke_skip_load_gpu=1` + ladder L14 para el render/CM3 bajo
    control (pasos de G1 §5c: doble captura, marca kmsg, apertura única desprendida, veredicto por
    última marca).

Orden de flashes/boots mínimo: **1 flash (lee) + 1 boot SSH → 1 flash (k13) + 1 boot observado →
[condicional] 1 flash (k13+video=d)**. Cero repacks de initrd, cero fw en initrd, cero bombeo del CM3
sin captura.
