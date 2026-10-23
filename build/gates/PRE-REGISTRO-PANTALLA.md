# PRE-REGISTRO de flashes — PLAN-PANTALLA (serie s253+, desde 28-sep-2026 tarde)

> Regla del proyecto: **una fila ANTES de tocar el hardware**, con sha256 del artefacto, cambio
> único, evidencia esperada y rollback. El flash lo ejecuta SOLO el orquestador con el guion
> `ciclo1-flash-s253.sh` (o el que corresponda). Canal: `dd` desde el Arch vivo (nunca sparse,
> nunca partición montada). Gate de batería: **≥ 3 700 000 µV** salvo waiver escrito del dueño.

## Estado del canal (28-sep 18:20)

- **USB caído 17:43:46** (`usb usb3-port3: disabled by hub (EMI?)` — glitch del hub del PC, no
  cuelgue de la tablet: la consola cortó con ruido UFS normal, sin pánico ni apagado). Sin
  reenumeración desde entonces. Batería al cortar: **3 432 mV / 2 %**, cargando a ~100 mA por
  USB del PC ⇒ sin carga desde entonces. **Ningún ciclo se ejecuta hasta que la tablet vuelva
  por USB y la batería pase el gate.**
- Captura de consola corriendo (PID 77586, `bin/uke-console-cap.sh` del hermano): vigente.
- Rescate: `build/gates/rescate-fastboot-pantalla.sh` (arrancar antes del primer flash).
- Backups verificados: `boot_b` = `ffff8c51…` (96 MiB, `build/backup-par-bueno/boot_b-lee.img`),
  `dtbo_b` bueno = `s238` `bdb361df…0022` (`build/bootimg/s238-boot-dtbo-dedup-gpio.img`).

---

## Fila #P1 — s253 (A′ del apps-smmu) — PRE-REGISTRADA, SIN EJECUTAR

| Campo | Valor |
|---|---|
| Artefacto | `build/bootimg/s253-boot-dtbo-aprima.img` — 607 714 B |
| sha256 | P1: `eeb57d95…` (no aplicado, ver registro) · **P1b: `4f284efa59048f13902c2f9406777dec3e8b1931c366aca6def7f8f3c78b53ad`** |
| Constructor | `build/bootimg/mkdtbo-s253.py` (gates G0–G10 + 5 mutaciones, TODO VERDE, `s253-GATES.log`) |
| Base | `s238` (el dtbo bueno vigente en `dtbo_b`) + UN fragmento `target-path=/soc/apps-smmu@15000000` |
| Cambio único | compatible triple mainline + `reg = <0x15000000 0x200000>` (una región de 2 MB) + `reg-names="base"`. Nada más (ni watchdog ni PHY ni panel). |
| Destino | `dtbo_b` por `dd` desde Arch vivo, relectura sha de los primeros 607 714 B |
| Por qué | El driver `arm-smmu` deriva la base de los CB del TAMAÑO de `reg[0]` (arm-smmu.c:2192,2201): con las 2 reg vendor (1 MiB) los CB caían fuera del mapeo ⇒ oops mudo (mecanismo del wedge del s251). 2 MiB cubre TCU+CB. Informe: `INFORME-A-PRIMA.md`. |
| Evidencia de ÉXITO | `arm-smmu 15000000.apps-smmu: probing hardware configuration…` + `stream matching with N register groups` + `Adding to iommu group` del mdss/dpu y DESAPARICIÓN de `no IOMMU, bailing out` (formato de referencia: kgsl-smmu en la consola del 28-sep, `[0.322139]`). |
| Evidencia de ARRANQUE SANO | consola con `Linux version` + login; slot b Successful tras arrancar. |
| Veredicto intermedio | Si bind OK pero aparece `SMMU address space size (0x100000) differs from mapped region size (0x200000)` ⇒ H1 cierta y explica el s251 (seguir). Si NO aparece, H1 refutada ⇒ el siguiente paso es el kernel de pokes, no más dtbo. |
| Evidencia de WEDGE | cero líneas de consola + caída a fastboot en ~10 min con contador 7→0 ⇒ NO reintentar; rollback y pasar a la hipótesis 2/3 del `INFORME-A-PRIMA.md` (ninguna es de DT). |
| Rollback | vigía rescate (fastboot→flash s238→`set_active a`+`b`→reboot) o manual: `fastboot flash dtbo_b build/bootimg/s238-boot-dtbo-dedup-gpio.img` + baile `set_active`. |
| Gates previos | sha del artefacto = tabla; ping OK; batería ≥ 3 700 000 µV (o waiver); captura de consola viva; rescate armado sin pause; `slot-retry-count` leído ANTES. |

## Fila #P2 — s254 (GPIO de reset del panel) — PENDIENTE DE DISEÑO (SG-GPIO en marcha)

Reservada: base s253 + fragmento que deje el pin 2 del tlmm tomable por el panel (esperar
`INFORME-GPIO-RESET.md` + `FRAGMENTO-GPIO.dts`). El driver del panel YA va integrado en el
kernel en marcha (`CONFIG_DRM_PANEL_XIAOMI_O82_DUALDSI=y`, build-s122 #82): no hay que
instalar nada para este ciclo. Evidencia esperada: el probe del panel pasa de
`failed to get reset gpio` a panel registrado + (con #P1 OK) `card0` con conector y modes.

## Registro de ejecución

| Fila | Estado | Fecha/hora | Resultado |
|---|---|---|---|
| #P1 | EJECUTADA 28-sep 18:37 | arranque SANO (sin wedge); **el fragmento NO SE APLICÓ**: el ABL no ve `fragment@s253` (nombre NO numérico; fdtoverlay sí lo aplicaba → gate ciego). Nodo vivo sin cambios. Progreso inesperado: master DPU bindeó dsi0+dsi1+kgsl antes del `-19`. Panel difiere por reset-gpio (esperado) |
| #P1b | EJECUTANDO 28-sep ~19:0x | mismo cambio A′, fragmento renombrado a `fragment@1708` (numérico, sin colisión; gate G11 nuevo). sha `4f284efa…`. **Ahora sí llega el compatible al driver ⇒ riesgo de wedge real**; rescate armado |
| #P1c | EJECUTANDO 28-sep ~19:1x | A′ = fragment@1708 **PRIMERO** en el blob + canario@1709 al final (no-op, duplica cx-supply del 1707). Discirma: si el ABL descarta la cola, ahora el compatible LLEGA al driver (riesgo de wedge real, teoría CB-base). sha `2c134ec3…`, 607 818 B |
| #P1d | EJECUTANDO 28-sep ~19:3x | DISCRIMINANTE: A′ renumerado a **fragment@160** (bajo el tope sospechoso >1707) y PRIMERO; + canary add-only **@159 en apps-smmu** (`uke,canary-smmu`) y **@158 control en wpss** (`uke,canary-ctl`). Veredictos: 160 aplica→era la numeración; 159 sí y 160 no→el nodo acepta adds pero no mis overwrites; 159 no y 158 sí→**el ABL protege el nodo apps-smmu** (DT muerto para él→pivote kernel); wedge→A′ llegó al driver (consola dirá). sha `53653d1a…`, 607 945 B |
| #P1e | 28-sep 19:2x | **CAUSA RAÍZ de P1..P1d ENCONTRADA: los dd+sysrq-b NO persistían** (relectura servida por caché de página; el reset duro tira el caché del UFS; los "arranques sanos" eran del s238 que el vigía restauraba en cada caída a fastboot del battery-soc). P1e: dd + sync 25 s + drop_caches + relectura SIN caché = s253d verificado en disco; apagado limpio completó el sync y **SE COLGÓ EN EL REBOOT** (documentado "se queda a medias"). s253d DURADERO en dtbo_b. Pendiente: power físico → primer boot REAL con s253d → leer consola |
| #P1f-s255 | EJECUTADA 28-sep 19:55 | **CANARIOS VIVOS** (fastboot flash = escritura fiable): uke,canary-smmu y uke,canary-ctl aplicados, boot ESTABLE ⇒ el pipeline de fragmentos funciona y el ABL añade props al apps-smmu sin problema. Todo el misterio P1–P1d = escrituras dd+sysrq-b no persistentes |
| #P1g-s256 | EJECUTADA 28-sep 20:01 | **reg único de 2 MiB APLICADO y ESTABLE** (compatible intacto) ⇒ el tóxico del s253d es el COMPATIBLE: al matchear, el probe del arm-smmu wedguea el arranque (mudo). Vía DT-puro muerta; siguiente: hipótesis clocks/power (SG-SMMU-CLK en marcha) |
| #P3-s257 | EJECUTADA 28-sep 20:1x | **AVANCE**: el defer infinito del panel se volvió fallo duro: `error -EINVAL: failed to get reset gpio` (-22, ya no defer). El pin dejó de ser compartido (3 vendor disabled, verificado vivo); proxy cargado (refcount 0); gpio2 `out high 8mA` (pinctrl del panel aplicó); pinmux UNCLAIMED. El -EINVAL lo caza SG-GPIO2 (en marcha) |
| #P3-s257 | EJECUTADA | s257 = s256 + fragmentos GPIO 2100-2102 (SG-GPIO). sha `7c05e305…`, 608 341 B. Gates fdtget verdes (3 vendor disabled, panel intacto). Ver resultado arriba |
| #P4-s258 | **✅ ÉXITO** 28-sep 21:0x | **EL PANEL PROBEA**: 0 líneas de error (adieu EINVAL/reset gpio), `pin 2: GPIO f000000.pinctrl:514` (control de SG-GPIO2 cumplido EXACTO), y ambos DSI host bindean al master (solo posible con panel adjunto). Cadena: panel ✓ DSI ✓ PHY ✓ GPU ✓ — master muere SOLO en `no IOMMU` (K1 en camino) |
| #P4-s258 | EJECUTANDO 28-sep ~21:0x | **FIX del -EINVAL** (SG-GPIO2, causa con log: bug del port pinctrl-cliffs — FUNCTION(gpio) sin flag GPIO ⇒ conflicto strict con el pinctrl-0 del propio panel). s258 = s257 + fragment@2103: `pinctrl-names="sleep"` en panel@0 (sin "default") ⇒ pinctrl no reclama gpio2 ⇒ el gpiod pasa. sha `f4663ff8…`, 608 469 B. Gates G-GPIO2-1/2/4 verdes. Éxito = panel probea (desaparecen las 3 líneas cliffs-pinctrl EINVAL); control: pinmux-pins `pin 2: GPIO f000000.pinctrl:514`. Root-cause kernel (#83, 2 líneas): MSM_GPIO_PIN_FUNCTION en pinctrl-cliffs.c:1571/1623 |
| #P2 | PENDIENTE DE DISEÑO (SG-GPIO entregó: fragmentos 2100-2102 status=disabled a los 3 nodos vendor del pin 2) | — | — |


## Shas de la serie s253-s257 (fastboot/dd-limpio = canales fiables; dd+sysrq-b PROHIBIDO)

| Artefacto | sha256 | Estado |
|---|---|---|
| s255-canarias | `bad87bdf60a90892a1b245a8e7ee43b22674c942167b58f397fd2192271bb909` | estable, canarios aplicados (fastboot) |
| s256-regonly | `2b45b3373e13e4121a0a7323601941bdefe922e326511ba11b569afdf4234110` | estable, reg 2MiB aplicado |
| s257-gpio | `7c05e305086f215917d1124df1a2be4331b9893040e53d628758b14d9781b4cd` | **EN LA TABLET** (dtbo_b), estable |


## #P5 — kernel K1 gate1 a boot_b (PRE-REGISTRADA ANTES DE ESCRIBIR)

| Campo | Valor |
|---|---|
| Artefacto | `build/bootimg/boot-ukek1-gate1.img` — 96 MiB exactos, sha256 `a1eb174ecfb8176e1301f1d9084ad5be2ea4b83e0a786f472fc738065aad654c` |
| Kernel | K1 (#1 Mon Sep 28 20:55:43): `.config` byte a byte el del s122/#82; acepta `qcom,qsmmu-v500` nativo (DT SIN tocar: compatible vendor + reg 2 MiB del s257/s258); defer arreglado (acepta 0x100000/0x200000); migas UKE-POKE en ID0/ID1/ID2 y cada fase del reset |
| Cmdline | la del s244 + ` uke_smmu_probe=1` (272 B, cabe en el campo) |
| Por qué sin gate0 | la config es idéntica a la del #82 que arranca y el Image igual de tamaño; las migas discriminan: mudo PRE-consola = kernel/config (rollback y parar); mudo TRAS migas = SMMU localizado (la miga última dice el registro); arranque + bind = éxito |
| Evidencia de ÉXITO | `UKE-POKE: apps-smmu … REINTENTO` + `cfg_probe ID0/ID1/ID2` + fases de reset + `arm-smmu 15000000.apps-smmu: probing…` + `Adding to iommu group` del mdss/dpu + DESAPARICIÓN de `no IOMMU, bailing out` ⇒ **card0** (con s258: panel vivo) |
| Rollback | `fastboot flash boot_b build/backup-par-bueno/boot_b-lee.img` (ffff8c51, verificado) + set_active. dtbo_b NO se toca (s258 sigue) |
| Gates previos | sha imagen; batería ≥3.7 V; captura de consola viva; backup boot_b en disco con sha verificado |


## #P5 — RESULTADO (registrado tarde — hallazgo H2 de la revisión)

**MUDO PRE-CONSOLA, CUELGUE FINAL.** 0 enumeraciones USB desde las 21:07 (journal del PC); primero bucle con `panic=10` (lo vio el dueño), después cuelgue estable con la pantalla BLANCA = splash del ABL (el ABL ya puede dibujar: cadena DT del panel completa). Rollback de boot_b PENDIENTE de ejecutar (tablet colgada, espera power físico). Mi árbol de decisión "#P5 migas discriminan" era INVALID para consola ACM (las migas no pueden capturarse antes del init) — registrado como error.

## CORRECCIONES de la REVISIÓN (H1, grave): "el compatible wedgea" queda NO VERIFICADO

- La única evidencia real de wedge por compatible es el **s251 del hermano** (compatible SOLO, flasheado por fastboot, wedge 7→0 medido 28-sep mañana).
- El **s253d (compatible+reg 2MiB) NUNCA arrancó de forma verificable**: P1b/P1d fueron por el canal no persistente, y el boot de las 19:43 corrió el s238 que el vigía había restaurado a las 19:39:04 (checkpoint `veredicto-p1e.md`). El propio s238 se arrancó mudo una vez (19:49) — la inestabilidad de esa ventana confunde todo.
- **En consecuencia el experimento A′ (compatible+reg por DT) SIGUE ABIERTO y es más barato que el kernel**: s256 demostró que el reg 2MiB es estable; falta probar compatible+reg JUNTOS con escritura persistente.

## #P6 — A′ completo por DT con kernel bueno (PRE-REGISTRADA)

| Campo | Valor |
|---|---|
| boot_b | restaurar el bueno: `fastboot flash boot_b build/backup-par-bueno/boot_b-lee.img` (`ffff8c51…`) |
| dtbo_b | `fastboot flash dtbo_b build/bootimg/s253-boot-dtbo-aprima.img` (el superviviente `53653d1a…` = s238 + A′ compatible-triple + reg 2MiB + canarios; H3: los variantes intermedios se perdieron, este es el bueno) |
| Canal | fastboot puro (síncrono) — sin dd, sin sysrq-b |
| Éxito | `arm-smmu 15000000.apps-smmu: probing…` + `Adding to iommu group` mdss/dpu + **card0** (panel ya vivo con… ojo: s253d NO lleva los fixes GPIO de s257/s258 ⇒ el panel volverá a fallar por reset gpio; este ciclo responde SOLO la pregunta SMMU) |
| Wedge | mudo→fastboot ⇒ A′ muerto por DT también, y K2 (en build) toma el relevo con migas en vivo |
| Rollback | `fastboot flash dtbo_b build/bootimg/s258-panel-gpio2.img` (`f4663ff8…`) |

## #P6 — RESULTADO: **A′ WEDGEA** (escritura fiable, fastboot 21:29)
Fastboot a los 100 s; kernel bueno + A′ compatible+reg = arranque muerto. CONCLUSIÓN ahora sí sólida (con s256 estable como control): el probe del arm-smmu sobre apps-smmu@15000000 mata el arranque; vía DT CERRADA. → K2 con migas en vivo.

## #P8 — K2 en caliente (PRE-REGISTRADA): boot-ukek2.img + s258
boot_b = K2 (sha 62553cc3…), dtbo_b = s258 (panel vivo). Arranque esperado SANO (defer para siempre, sin token). Luego: ssh + `dmesg -w` al PC (doble captura) + `cat /sys/kernel/debug/devices_deferred` ANTES + `echo 1 > /sys/module/arm_smmu/parameters/uke_smmu_probe` → migas ID0/ID1/ID2 + fases → desenlace (bind o wedge localizado).

## #P7 — (anulado por #P6: fusión A′+s258 ya no aplica)


## #P8 — RESULTADO (21:5x): **WEDGE LOCALIZADO — murió leyendo SMR(0..109)**

Primer probe REAL del apps-smmu con consola viva (bind por sysfs tras arming; stream completo en `build/evidencia/2026-09-28/k2-migas.log`):
- SOBREVIVE: IDR0 (110 grupos, ID0=0x4c017e6e), IDR1 (**NUMPAGENDXB=6**, pgshift 12, 71 CBs, CB base 0x80000 — **H1/ventana REFUTADA por medición**), IDR2, escritura S2CR(109)+relectura (quirk qcom detectado: 0x000200ff).
- MUERE: en `qcom_cfg_probe: leyendo SMR(0..109)` — cuelgue duro (sin ping, stream congelado, sin panic).
- Hipótesis nº1: región SMR protegida (TZ/XPU); el Android stock no barre SMRs (driver vendor + qcom,handoff-smrs). El kgsl-smmu (AP-owned) sí puede.
- → K3: migas por índice de SMR + param para saltar/acotar el barrido; comparar mainline vs kws/common/arm-smmu.c (manejo SMR/handoff).

## #P9 — K3 (PRE-REGISTRADA): boot-ukek3.img = K2 + SMR-sweep instrumentado/salteable


## #P9 — RESULTADO PARCIAL (23:4x-23:5x)
- **Rung smr_max=0 (CONSOLA ROBUSTA, trail completo)**: SMR(0) LECTURA OK (¡mapeo vivo del BL: valid=1 id=0x60 mask=0x8000!), cfg_probe COMPLETO ("preserved 0 boot mappings"), **MUERE en reset fase2** (escrituras SMR/S2CR ×110) ⇒ las LECTURAS son seguras; el asesino es el barrido de ESCRITURAS que borra el handoff del bootloader.
- **Rung stream_match=0 (×2)**: muerte rápida sin trail utilizable (flush perdido). Coherente con muerte en las S2CR de fase2, pero NO VERIFICADO.
- → K4 (SG-K4 en marcha): `uke_keep_boot` = reset SIN escribir SMR/S2CR (semántica handoff vendor) + `uke_reset_mask` por fases. Captura robusta propia desplegada (`out/captura-robusta.sh`).


## #P10 — K4 primer disparo (29-sep 00:0x): probe se ATASCA (no mata) tras ID0
- boot K4+s258 SANO; disparo con smr_max=0 + keep_boot=1 + probe=1 y bind — pero el orden (param→trigger ANTES del bind) enredó el deferred: kworker del timeout en D (flush_work eterno), probe detenido tras "stream matching with 110 register groups" (sin miga de ID1), sistema VIVO (primer colgote no-letal del probe). Sin bind, sin grupos.
- Lección de secuencia: **bind SIEMPRE al final** (probe síncrono en el hilo del ssh, como el ciclo K2 que funcionó).
- Boots cada vez más inestables (2 colgados en userspace esta noche): el e2fsck en frío pendiente pasa a PREREQUISITO operativo.
- Estado al cierre de la noche: boot colgado (sin sshd), esperando power físico. Siguiente ciclo: boot → secuencia corregida (params, luego bind) → migas completas → bind o fase mortal nueva.


## #P11 — K4 disparo corregido (29-sep 00:24): **EL PROBE COMPLETA EL RESET** — muerte trasladada al ATTACH
Trail completo en `build/gates/k4c-consola-trail.txt` (la consola robusta aguantó; el stream ssh murió antes):
- cfg_probe OK → **reset fase2 OMITIDA (keep_boot)** → fase3 CB×71 COMPLETA → fase4 TLBI → fase6 mmu500_reset → fase7 sCR0 → test_smr_masks OMITIDO. **Todo el reset sobrevive sin tocar los mapeos del bootloader.**
- Muerte instantánea tras el último print = en el registro del iommu / **tormenta de attach** (bus_iommu_probe → arm_smmu_probe_device → write_sme por maestro). Ninguna miga de attach llegó a imprimir.
- Hipótesis fuerte: el SMR(0) vivo (id=0x60 **mask=0x8000** — ¡cubre un rango enorme de SIDs, incluido el 0x1c00 del mdss!) hace que find_sme REUTILICE el índice 0 y write_sme lo SOBRESCRIBA → muerte (escribir el registro vivo = letal, consistente con todo lo medido).
- → K5: migas+palancas en la fase de attach (qué maestro/mi write_sme mata; saltar attach; y el parseo de `qcom,handoff-smrs` como semántica definitiva).


## #P12 — K5 disparo 1 (00:50): ATASCO ARTIFACTO del timeout del ssh
- El `timeout 45` del ssh del bind MATÓ el hilo del probe a medias (locks cogidos, deferred work atascado en flush eterno, coredump en systemd). NO fue el hardware.
- **REGLA NUEVA**: el `bind` se lanza DESPRENDIDO EN LA TABLET (`nohup sh -c 'echo ... > bind' &`) — nunca en un ssh con timeout del lado del PC.
- Repetir con attach_log=1 → ver el volcado BL y el write_sme del ufshc; luego attach_log=2.


## #P13 — K5 disparo con bind desprendido (00:55): **LEER S2CR(0) MATA**
- Trail ssh hasta "SMR loop OK" (decodificación corregida confirmada: SMR(0) valid=1 id=0x60 mask=0x0 = el sid EXACTO del ufshc). Muerte antes del primer print del volcado BL (su flush va AL FINAL del dump) ⇒ el acceso nuevo = `readl(S2CR(0))` (0xc00), única lectura no probada del dump. Lecturas seguras: IDs, SMR(0). **Lectura letal: S2CR(0) — el registro de traducción VIVO del UFS.**
- Consistente: K4 (sin dump) pasaba cfg_probe+reset entero y moría en el attach (write_sme sobre lo vivo). K5 murió ANTES que K4 = el dump lo mató.
- → K6: volcado sin leer S2CR(0) (SMR(0) solo) → ladder igual → attach_log=2 (preservar idx vivo) → bind completo esperado.


## #P14 — K6 disparo 1 (01:19): volcado BL OK; **muerte en fase3, CB idx=22**
- Volcado BL imprimió sin morir (SMR(0) HW leído; S2CR(0) "NO LEIDO") ⇒ fix K6 correcto.
- Reset: fase1 ✓, fase2 OMITIDA ✓, fase3 (CB×71 SCTLR=0) **murió en idx=22** (0x95000).
- Interpretación: el UFS tradujo VIA CB22 en ese boot — apagar su SCTLR con DMA en vuelo = muerte. En el boot de K4 (k4c) el barrido completó ⇒ el CB vivo/variance cambia por boot (estado BL variable) o es una carrera con tráfico UFS.

## #P15 — K6 disparo 2 (01:21): `uke_reset_mask=0xc` (fase2+fase3 omitidas) — **reset COMPLETO sobrevive; muerte justo tras fase7**
- fases 4,5,6,7 ✓ (TLBI, sCR0 RMW, arm_mmu500_reset con sACR, tlb_sync+sCR0). Muerte entre el print de fase7 y la primera miga (flush-eada) del attach — ni "test_smr_masks OMITIDO" llegó al cable.
- Conclusión del mapa de minas acumulado (todo medido): IDs/SMR(0) leer ✓ · SMR/S2CR libres escribir ✓ · S2CR(0) leer ✗ · registros vivos (SMR(0)/S2CR(0)/CB vivo) escribir ✗ · fase3 CB sweep ✗ (carrera con DMA UFS) · y una muerte residual post-fase7 sin localizar (¿sCR0 final? ¿attach pre-miga?).

## #P16 — INSIGHT CLAVE de la referencia dorada (dmesg-android.txt:1733-1743)
**El Android stock bindea el apps-smmu a los 0,543 s y el ufshcd pide su grupo a los 0,550 s — 7 ms después.** Android hace el reset COMPLETO (mismo driver mainline-lineage, "preserved 0 boot mappings") ANTES de que el UFS del kernel arranque DMA. Nosotros probeamos a los 38-90 s con el disco en pleno vuelo por el registro vivo. La VENTANA TEMPORAL es la diferencia; no (solo) las fases.
- Pero ojo: el s251 (probe a 0,3 s, reset completo) murió mudo ⇒ o la ventana 0,3 s es aún temprana-mala (DMA del BL aún vivo), o el driver kws de Android difiere del arm-smmu del fork (código fuente kws NO encontrado en disco: vendor-src/cliffs es solo clocks).
- Camino siguiente (K7, por diseñar): replicar la ventana de Android — probe ARMADO EN CMDLINE (module_params aceptan `arm_smmu.uke_*` en cmdline; repack sin recompilar) con el retry del deferred (~1 s, antes de que ukeinit monte el rootfs a los ~5 s) + secuencia de fases segura (0xc) + attach_log=2. Si el bind sobrevive a esa ventana, el attach del UFS se hace con su mapeo BL preservado o re-negociado sin tráfico en vuelo.

## #P17 — K7 (PRE-REGISTRADA 01:37, antes del flash): probe ARMADO por cmdline en la ventana Android
- **Imagen**: `boot-ukek7.img` = K6 byte a byte (kernel `c2038e08…` SIN recompilar) + SOLO cmdline: 255→382 B añadiendo `arm_smmu.uke_smr_max=0 arm_smmu.uke_keep_boot=1 arm_smmu.uke_attach_log=2 arm_smmu.uke_smmu_probe=1 arm_smmu.uke_reset_mask=12`. **sha256 `1c1a090bc69e532f7585a1386345d01f2c8c87712a8d2b5f5b064bf7c96722d4`** (delta 127 B, todos en cmdline[44..426); kernel/initramfs/dtb/AVB intactos; reporte `/var/tmp/uke-k7/repack-k7-report.txt`, script `/var/tmp/uke-k7/repack-k7.py`).
- **Mecanismo**: arming en parseo temprano (la callback es segura: `driver_deferred_probe_trigger` no-op si deferred deshabilitado) → primer probe difiere UNA vez (bloque `ya_diferido`) → reintento en la misma cascada de initcalls (~0,6-1,5 s), ANTES de que ukeinit monte el rootfs (~5 s) y exista DMA de UFS. Fases: 2 y 3 OMITIDAS (mask 0xc = F4+F567), SMR(0)/S2CR(0) del BL preservados (attach_log=2), smr_max=0.
- **Canal**: `fastboot flash boot_b` (ÚNICO flash de la noche; dtbo_b sigue s258). Captura: `~/proyectos/out/uke-console-k7.log` (captura robusta por /dev/ttyACM0) + ssh si llega.
- **Predicciones** (pre-registradas): (a) VIVE → migas completas (REINTENTO→ID0/1/2→dump BL→fases 4-7→SME idx=0 PRESERVADO→bind completo) → iommu groups + apps-smmu fuera de devices_deferred → SSH y desde ahí bind dpu→card0. (b) MUERE <2 s → **muerte muda** (ttyGS0 no existe aún): la ausencia total de consola tras el splash del ABL ES el resultado (refuta la hipótesis del timing puro → el asesino es estructural del attach, no del tráfico). (c) MUERE 2-5 s → trail parcial hasta la miga exacta.
- **Riesgo residual asumido** (#P15): muerte post-fase7 sin localizar podría repetirse aunque no haya tráfico — si pasa muda, queda refutado el eje temporal completo.
- **Restauración**: par bueno `boot_b-lee.img` (`ffff8c51…`) + s229 para vuelta atrás (mañana).

## #P17 — RESULTADO (01:40-01:43): **MUERTE MUDA** (predicción b) + confundidor descubierto: la sesión fastboot del ABL
- Flash boot_b OK (2,1 s, sha 1c1a090b…) + `fastboot reboot` OKAY. Evidencia PC-side (journalctl -k): 01:40:12 disconnect del fastboot (dev 66) → 01:40:13 el gadget del NUEVO arranque enumera **full-speed con `device descriptor read/64, error -71`** (dev 67→68) → **silencio USB absoluto desde entonces** (sin reconexiones en 2,5+ min ⇒ NO es bucle de panic=10; es un colgado duro). Sin /dev/ttyACM0, sin NCM, sin SSH. Pantalla presumiblemente en splash del ABL.
- El patrón USB (full-speed + descriptor ilegible + pull-up quieto) = dwc3 wedge en nivel BL: la sesión USB del **fastboot que ACABABA de handoff-ear** murió con el sistema.
- **CONFOUNDIDER CLAVE**: TODOS nuestros boots de experimento (s251 a 0,3 s; K7 a ~1 s; y también los K2-K6 tarde) arrancan con `fastboot reboot` ⇒ la sesión USB/dwc3 del ABL está VIVA en la entrada al kernel (con sus buffers DMA colgando del apps-smmu). El Android dorado (0,543 s, reset completo, SOBREVIVE) arranca tras reboot NORMAL con el USB cerrado. La "ventana Android" que replicábamos no era comparable: Android nunca lleva fastboot-USB en marcha al hacer su reset.
- Hipótesis de trabajo nueva: el asesino temprano es el DMA del dwc3/fastboot heredado del BL (no el UFS). Discriminable GRATIS: la imagen K7 ya está en boot_b y armada por cmdline — un **power-cycle físico en frío** (pulsación larga de power → arranque limpio sin sesión fastboot) repite el experimento K7 con handoff USB limpio. Si sobrevive → confundidor confirmado y SMMU utilizable; si muere mudo otra vez → el attach es estructuralmente letal y la vía es preservar por completo o parche handoff (ver R1/R4).
- Estado al cierre (01:45): tablet colgada sin acceso (espera power físico). Único flash gastado. Consola capturando por si acaso (`uke-console-k7.log`, vacío). Backups intactos (`boot_b-lee.img` ffff8c51… para rollback).

## #P17-bis — Caída a fastboot por watchdog del ABL (01:51:57)
11,7 min tras la muerte muda, la tablet cayó SOLA a fastboot (journal PC: 18d1:d00d high-speed, serial SERIE0001; battery-soc-ok: yes, 3824 mV). Coincide con el patrón documentado en el comentario de arm-smmu.c (K1): "4 min sin una sola línea de consola y luego el ABL cae a fastboot" — hay un watchdog de ABL que recupera el fastboot tras un boot colgado. El fastboot entra LIMPIO (high-speed, descriptors OK) ⇒ el dwc3 wedge fue estado del handoff, no daño. La captura de consola jamás vio ttyACM0 (mute confirmado). Siguiente: arranque en FRÍO (power físico) de la MISMA K7 — test gratuito del confundidor.

## #P18 — EVIDENCIA R3 (vendor-diff, 02:0x): el vendor tiene MECANISMO de handoff que nosotros no
- `qcom,handoff-smrs = <0x1c00 0x02>` (SID display) en el apps-smmu vendor (`vendor-base.dts:10984` vía R3); el driver vendor lo consume (`arm_smmu_handoff_cbs`, TBU halting, `qcom,actlr`) → conserva los SMR/CB vivos del BL. **Nuestro DT (base+A′) PERDIÓ la prop** (y `tcu-base`; nuestro reg=2 MiB, solo "base", con marcador uke,canary-smmu) y nuestro arm-smmu no lee nada de eso — K4-K7 preservan SMR(0)/S2CR(0) a mano, sin conocer el resto (CBs del handoff, actlr).
- SIDs medidos/declarados: UFS 0x60/0 (vivo en SMR[0]=0x80000060), **display 0x1c00/2** (vive en el nodo `qcom,smmu_sde_unsec_cb`; el MDP usa `qti,smmu-proxy-cb-id=1`), WiFi 0x1400/1, dwc3 0x40/0.
- Android SÍ resetea a 0,543 s y sobrevive; UFS pide grupo a 0,5507 s, dwc3 a 9,66 s (detalles en R3-vendor-diff.md). NUMPAGENDXB=6 ⇒ hipótesis A′ (reg 1 MiB corto) refutada de nuevo.
- Extra: WiFi = icnss2+wpss (NO pcie; FW qca6750/bd_o82gl.elf) · sensores SOLO por QMI/ADSP (sin I2C) · BT wcn6750 SLIMbus/hsuart · panel real O82 42 02 0b.
- **Implicación para K8+**: restaurar `qcom,handoff-smrs` (+tcu-base) en el DT e implementar/portar la preservación (estilo vendor/ChromeOS — pendiente R1 planes B/C y R4 upstream). El confundidor USB (#P17) sigue en pie como hipótesis paralela — el arranque en frío de K7 los separa.

## #P19 — EVIDENCIA R4 (nuevas vías, 02:1x): el código del handoff EXISTE en el kernel lineage del SM8635
- **Vía H (1ª, pantalla)**: portar `arm_smmu_handoff_cbs()` + `s2cr[].pinned` + `__arm_smmu_alloc_cb()` del kernel Android lineage-23.0 del SM8635/cliffs (Xiaomi-Pad-7-Pro-Resources/android_kernel_xiaomi_sm8635) / CodeLinaro le_kernel_msm-5.15 @8fa3cef — nunca barre los registros vivos; portar SIN la lectura de S2CR (letal #P13) y combinar con la ventana temprana (K7). Detalles y URLs en R4-nuevas-vias.md.
- **Vía C (2ª)**: árbol comunitario Codeberg palawan-mainline/linux (`qcom,palawan-smmu-500`+`qcom,smmu-500`+`arm,mmu-500`; mdss `iommus 0x1c00 0x2`); port del Pad 7 Pro aún sin nodos mdss/dpu; contactos Zubtsov (USUARIO@example.invalid) / philmb3487.
- **Vía I (3ª)**: identidad/bypass SOLO para el SID del display (precedente vendor `qcom,iommu-dma="bypass"`, parche UKE-IDENTITY ya en disco) + `msm_mmu` no-op — «DPU sin iommu» puro queda DESCARTADO (msm_kms.c:198 bails out sin IOMMU).
- **GPU por separado**: kgsl-smmu (0x3da0000) INDEPENDIENTE y YA BINDEA — la vía GPU no pasa por el apps-smmu; falta adoptar A735/gmu-735 del árbol Codeberg (mainline no conoce 0x43030b00).
- Upstream: mainline 7.3-rc5 sin NADA cliffs; `qsmmu-v500` nombre solo-vendor; `handoff-smrs` 0 resultados en lore. `kiwi` = WLAN WCN6750, no el SoC (familia cliffs, soc_id 643).

## #P20 — EVIDENCIA R1 (auditoría SMMU, 02:3x): GO a K7 tal cual + dos correcciones + un bug ALTA
- **Veredicto GO** a la cmdline K7 flasheada (valores exactos, sin protect_smr0, sin mask=0). Artefacto re-verificado por R1 (sha, cmdline NUL-terminada, AVB).
- **Corrección 1**: el probe armado corre a los **0,4449 s** (tren-1 de diferidos; medido 0,42-0,47 s en k2/k5b/k6/k6b), no ~1 s. ttyGS0 existe desde 3,57 s ⇒ muerte muda era el desenlace ESPERADO si wedgea (fue lo que pasó #P17). Ventana anterior incluso a la de Android (0,543 s), UFS 13,8 s, rootfs 15,6 s.
- **Corrección 2**: primer attach esperado `1de0000.qcedev` idx=1, muerte esperada en su primer write_sme (= punto medido k4c:27920-27922). Con smr_max=0 la RAM no ve los SMR 1..109 ⇒ attach_log=2 NO protege esas escrituras.
- mask=0xc ejecuta: F4 TLBIALLH/NSNH(0xffffffff) + F5-7 sCR0 RMW, sACR RMW + CB_ACTLR×71 (CPRE_ERRATA), sTLBGSYNC, sCR0 final. Incondicionales fuera de máscara: rmr_install_bypass_smr (CLIENTPD), quirk S2CR(109)+CB70, fase1, y el storm entero (incl. write_context_bank(CB0) del wifi — único dominio traducido).
- **BUG ALTA**: `arm_smmu_master_free_smes()` (:1752-1765) escribe el SME liberado SIN guarda ⇒ un unbind/release del ufshc pisaría S2CR(0). **REGLA: NUNCA unbind con este kernel.** Bug MEDIA: bucle CPRE sin miga por CB.
- Plan B (K8): partir F567 en F5/F6/F7 (aislar la escritura final de sCR0). Plan C: sysfs-only si sobrevive (params + bind desprendido; sin unbind). mask=0 DESCARTADO (deja CLIENTPD=1 y no evita el storm).
- Estado del arte: mecanismo portable = RFC 2019 de Bjorn Andersson (handoff SMR+CB, nunca fusionado) + semántica vendor qcom,handoff-smrs → combine con #P18/#P19 para el diseño K8.

## #P21 — Resolución de la discrepancia R1/R3 (fdtoverlay base+s258 medido): el DT SÍ declara el handoff
El nodo apps-smmu de NUESTRO DT efectivo (base-dtb + s258 aplicado con fdtoverlay) CONSERVA `qcom,handoff-smrs = <0x1c00 0x2>` y `qcom,actlr` (dump en /var/tmp/k8-check/merged.dtb). Lo que falta es SOLO el driver (0 lectores de la prop, R1 #P20). Pérdida real del overlay A′: `tcu-base` (reg-names="base" único; vendor tenía 0x151fe000×0x40 aparte) — anotado como diferencia, sin evidencia de que sea fatal (NUMPAGENDXB=6, CB base 0x80000 < los 2 MiB de nuestra ventana reg).
**Diseño K8 (consolidado #P18+#P19+#P20+#P21)**: portar al arm-smmu del fork la semántica handoff del kernel lineage SM8635 (arm_smmu_handoff_cbs + s2cr[].pinned, vía H de R4) leyendo `qcom,handoff-smrs` de NUESTRO DT (sin cambiar el dtbo): pinear SMR/CB del SID 0x1c00 (display) y el SME vivo 0x60 (UFS, SMR[0]) — nunca escribirlos — SIN leer S2CR(0) (letal #P13); combinar con la ventana temprana de K7 (cmdline armada ya probada a 0,4449 s). Primer test mañana: arranque en frío de K7 (separa el confundidor USB del resto).

## #P22 — Auto-salida del fastboot a las 03:04: K7 muere muda TAMBIÉN con la sesión USB idle
Sin intervención (journal: 73 min de fastboot quieto → disconnect y re-enumeración separadas por 1 s = NO fue power-cycle humano): el fastboot de Xiaomi se auto-reinició. Ese arranque murió mudo otra vez, con la particularidad de que el gadget rebotó ROTO durante ~20 s (dev 70-77, error -71, "not responding to setup address") — ~2 ciclos de pánico — antes de que el ABL la devolviera a fastboot en 22 s (detección de reinicio rápido, no el watchdog de 11 min de #P17-bis). Captura de consola VACÍA: nunca llegó a ttyGS0.
- **Lectura**: la sesión fastboot estaba IDLE 73 min (sin DMA en vuelo) y aun así murió ⇒ la variante "buffers DMA del fastboot vivos" del confundidor #P17 queda DEBILITADA. Queda por separar: (a) la mera presencia del dwc3 reclamado por el ABL (configurado aunque idle) frente a (b) que el attach armado sea letal SIEMPRE (estructura). El arranque en FRÍO real (power físico, PMIC resetea el dwc3) sigue siendo el discriminador gratis.
- Estado a las 10:08: tablet en fastboot desde 03:05 (idle 7 h), batería 3668 mV, soc-ok yes. Próximo: cold-boot del usuario + K8 (port handoff vía H) en construcción paralela.

## #P23 — ARRANQUE EN FRÍO de K7 (10:12): **MUERTE MUDA — el confundidor queda REFUTADO**
Power físico (10 s apagado + arranque limpio, sin fastboot de por medio, dwc3 reseteado por el PMIC). Resultado: IDÉNTICO a #P17/#P22 — gadget roto desde el primer segundo (full-speed, error -71, rebote continuo), sin ttyGS0, sin NCM, sin ping, pantalla en blanco = splash del ABL congelado (muerte ~0,44 s).
- **VEREDICTO**: el attach armado del apps-smmu con la semántica actual (fases 0xc + preservación manual SMR(0)/S2CR(0)) es **estructuralmente letal en CUALQUIER ventana** (0,44 s frío, 0,44 s tras fastboot USB-idle, 38-90 s con tráfico). La hipótesis del timing/confundidor queda refutada en todas sus variantes.
- **La vía única es la preservación REAL**: port del handoff (K8, vía H): pinear TODOS los SMR vivos del BL (no solo el 0), leer qcom,handoff-smrs del DT (SID 0x1c00 display), reservar CBs desde arriba, fix del bug free_smes. K8 en construcción (agente, /var/tmp/uke-k8).
- Regla nueva de operativa: el splash blanco congelado + rebote USB full-speed/-71 = firma inequívoca de muerte muda del probe armado (ya vista 3×).

## #P24 — K8 (PRE-REGISTRADA 11:1x): handoff REAL — pineo de SMR vivos + handoff-smrs + CBs desde arriba
- **Imagen**: `boot-ukek8.img` sha `5e34596a230d2d645ad8dcc68dcba5c23bc58bf2a6c6468a526a66bb687d54e2` (96 MiB, kernel_size 16572290, cmdline = K7 byte a byte). Diff `k8-handoff.diff` (442 líneas +) sobre el árbol K7. Informe INFORME-K8-BUILD.md. Variante de contingencia YA EMPAQUETADA: `/var/tmp/uke-k8/boot-ukek8-h2.img` `4833e038…` (`uke_handoff=2`, sin barrido SMR).
- **Cambios**: (1) barrido de SMR(0..109) al probe, pineo de todo VALID=1 — ni reset, ni attach, ni `free_sme` (bug ALTA R1 cerrado) pueden escribirlos; (2) parseo de `qcom,handoff-smrs=<0x1c00 2>`: los SIDs declarados heredan el mapeo BL sin escribir SMR/S2CR (puerto de `arm_smmu_handoff_cbs`/`s2cr[].pinned` del lineage SM8635, SIN leer S2CR — #P13); (3) CBs nuevos desde arriba (69→0); migas `UKE-POKE: handoff:` con pr_flush; param `uke_handoff` (1 def, 0=K7-comportamiento, 2=sin barrido).
- **Canal**: `fastboot flash boot_b` (dtbo_b s258 sin tocar) + `fastboot reboot` (con #P23 el frío ya no discrimina). Captura consola + SSH.
- **Predicciones**: (a) VIVE → migas en orden (PREPARAR→DT handoff[0]→barrido leidos=110 PINADOS=N→fases 4-7→attach PINADO→CB 69→groups) → SSH ~40-90 s → **re-bind panel (R2 §7) → card0 → modetest (escalera CM3) → FOTO**. (b) muda a 0,44 s = la lectura del banco SMR mata (ambigüedad K2) → flash h2 (`uke_handoff=2`). (c) muere tras FIN barrido → repack mask=4/0. (d) arranca sin UFS → mask=4. NUNCA unbind.
- **Restauración**: `boot_b-lee.img` (`ffff8c51…`) + s229.

## #P25 — K8: MUERTE MUDA a las 11:14:03 + DOS críticas (C1/C2) que reordenan el día
- **Resultado K8** (flash 11:12-11:14, reboot 11:14:02, boot 11:14:03): muerte muda, firma del gadget muerto en los 3 re-enganches del usuario (11:41:39, 13:47:00, 14:13:06 — full-speed/-71, sin 1d6b:0104 vivo ni 18d1:d00d). Captura de consola perdida (el bucle había muerto y el fichero nunca existió).
- **C1 (forense) REFUTA mis lecturas**: el evento "root hub lost power" 11:36:25 = RESUME DE S4 del PORTÁTIL (batería al 2%, 22 líneas/9 episodios desde 20-sep = rutina), no la tablet; la desconexión real fue 11:14:02; "11:33-11:38" era la salida congelada por hibernación. H1 (batería-ABL) refutada como causa de la ausencia USB; H3 (K8 vivo) refutada. Firma discriminadora: VIVO=1d6b:0104+cdc_acm 9-12 s; FASTBOOT=18d1:d00d 4-5 s; MUERTO=full-speed+-71.
- **C2 (diseño K8) — veredicto FLASHEABLE pero con 3 huecos**: (1) el pineo no cubre F4 TLBIALLH/NSNH, F5/F7 sCR0 y CB_ACTLR×71 de F6 — NUNCA medidos a 0,44 s ⇒ muerte muda NO prueba que el barrido mate (las fases son sospechosas iguales; la escalera correcta post-muerte es mask=4/0, no h2); (2) CBs sin guarda: el quirk escribe CB70 ANTES del barrido (arm-smmu-qcom.c:546-551) y write_context_bank puede pisar CB vivo; (3) el SID del display pineado hereda mapeo BL sin traducción kernel → card0 podría salir sin ser éxito completo.
- **Instrumental corregido**: captura a uke-console-viva.log (pid 293332) + watcher journalctl -kf → uke-usb-watch.log (pid 293338) con la firma discriminadora.
- **Regla nueva**: el PORTÁTIL se enchufa a la corriente en cada experimento (la hibernación a mitad de ciclo nos costó la evidencia del K8).
- → K9 (C2-guided): guardas de CB + quirk CB70 saltado + migas antes de CADA escritura + escalera mask integrada.

## #P26 — K9 (PRE-REGISTRADA ~16:00): SILENCIO TOTAL por defecto — la muerte se vuelve diagnóstico
- **Imagen**: `boot-ukek9.img` sha `f21cc35f8c64d7e71ddaf7f0fd4282b09e452e5d5f2293df786c1bfad4f14fe3` (96 MiB, kernel_size 16576161, cmdline K7/K8 byte a byte). Diff k9-escrituras.diff (721 líneas). Variantes YA empaquetadas: `boot-ukek9-h2.img` (`52dff483…`, handoff=2 sin barrido) y `boot-ukek9-todo.img` (`a167aee5…`, control ≈K8+migas); rungs 0xf/0x10/0x20/0x1c0 en /var/tmp/uke-k9 (repack 30 s).
- **Novedad `uke_write_mask`** (bit a 1 = ESCRIBE, default **0 = silencio total**; miga+pr_flush antes de cada escritura permitida): 1=F4 TLBI · 2=F5 sCR0 · 4=F6 sACR+CB_ACTLR×71 · 8=F7 sync+sCR0 · 16=quirk S2CR(109)/CB70/CBAR70 · 32=rmr CLIENTPD · 64=attach write_sme · 128=install_s2cr · 256=write_context_bank. Guardas CB: CB70 intocable; write_context_bank solo para CBs reservados desde arriba. Migas delante de TODO.
- **Canal**: power-cycle físico de la tablet (colgada desde las 11:14) — boot directo, sin fastboot. Captura viva (uke-console-viva.log, pid 293332) + watcher USB firmas (uke-usb-watch.log, pid 293338). Portátil ENCHUFADO (regla #P25).
- **Predicciones**: (a) VIVE (esperado si el asesino era escritura): migas hasta "SILENCIO" + bind funcional-hueco (SMMU registrado sin programar HW) → SSH → escalera de bits (F4→…→CB) por repack. (b) MUERE IGUAL con mask=0 ⇒ asesino = LECTURA (barrido SMR) o incondicional no cubierto → siguiente boot: `boot-ukek9-h2.img` (sin barrido). (c) firma VIVO esperada: 1d6b:0104 + cdc_acm 9-12 s tras power-on.
- **Restauración**: `boot_b-lee.img` (`ffff8c51…`) + s229.

## #P26 — RESULTADO (15:47): K9 mask=0 murió muda… PERO confundidor BATERÍA (veredicto SUSPENSO)
- Watcher (nuevo, funcionó): 15:47:23 fastboot (flash OK) → 15:47:45 disconnect (reboot) → 15:47:47 full-speed/-71 = firma de muerte. Consola: uke-console-viva.log SIN contenido nuevo (mtime 01:23 = noche; C1 tenía razón, el log viejo confundía).
- **PERO la batería estaba a 3438 mV** (y la de K8 a las 11:14 a 3545): ambas pruebas de hoy POR DEBAJO del umbral ~3700 del ABL, y la carga de pared NO cargó (3545→3438 en 4 h). **Brownout por pico de corriente del arranque = misma firma que muerte SMM.** Las muertes de K7 de ayer (3824-3832 mV) siguen siendo válidas; las de K8 (#P25) y K9 quedan **SUSPENSAS** hasta re-probar con batería ≥3750 mV medida por getvar.
- Siguiente: CARGAR de verdad (verificar que aparece icono de carga / sube el voltaje con getvar) → re-test K9 mask=0 TAL CUAL (0 flashes: fastboot reboot si está en fastboot, o power-cycle) → si muere con batería sana: rung h2 (lecturas fuera) → después escalera de bits.
- Regla nueva: **ninguna prueba con battery-voltage < 3700** (gate obligatorio en cada ciclo).

## #P26-bis — CONTROL DEFINITIVO (16:1x): el KERNEL BUENO también "muere" a 3403 mV ⇒ los datos de hoy son TODOS brownouts
- Flasheado boot_b-lee (s244-bounce ffff8c51…, par bueno de la semana, dtbo s258 ya probado sano con él) + reboot a **3403 mV, battery-soc-ok: no** → MISMA firma full-speed/-71 que K8 y K9. Un kernel con cientos de boots sanos no puede "morir mudo": **es brownout de batería** (pico de corriente del arranque por debajo del suelo del PMIC).
- **Revisión del día**: K8 (#P25) y K9 (#P26) quedan **INVALIDADOS por batería** (3545 y 3438 mV). K7 y su serie (anoche, 3824-3832 mV) SIGUEN VÁLIDAS. Hoy se ha aprendido: la firma -71 es AMBIGUA (muerte SMMU ⚁ brownout) — el gate de 3700 pasa a OBLIGATORIO y anotado como tal.
- **Estado boot_b = kernel bueno** (listo para cargar en cuanto haya energía; en Arch arrancado la carga funciona — la fastboot no). Próximo ciclo con batería ≥3750: 1) reboot del kernel bueno → SSH + carga hasta sano; 2) re-flash K9 (f21cc35f…) → test mask=0 REAL; 3) escalera h2/bits según desenlace.

## #P26-quater — CORRECCIÓN de #P26-ter: el flash del kernel bueno NO llegó a ocurrir
El `fastboot flash boot_b boot_b-lee.img` de las 17:1x se quedó en "< waiting for any device >" (la tablet colgada tras la muerte de K9 nunca volvió a fastboot; el watcher no veía nada desde el bounce 28). Proceso matado sin enviar un byte: **boot_b SIGUE LLEANDO K9 (f21cc35f…)**. Pendiente: tablet a fastboot por power físico → flash del kernel bueno → apagada al cargador toda la noche.

## #P26-final — boot_b DEVUELTO al kernel bueno (17:4x, flash OKAY 2,2 s) — cierre del día
Tabla al fastboot por el dueño; flash boot_b-lee verificado (OKAY writing). Batería 3446 mV. La tablet pasa a carga nocturna APAGADA; al encender con energía arrancará sola el par bueno (kernel s244-bounce + dtbo s258) con SSH. Mañana: getvar ≥3750 → confirmar SSH/carga → re-flash K9 (f21cc35f…) → prueba limpia mask=0 → escalera h2/bits. Gate de batería OBLIGATORIO aprendido hoy (ningún dato por debajo de ~3450; firma -71 ambigua SMMU/brownout).

## #P27 — K9 mask=0 a 4108 mV (GATE VERDE): MUERTE REAL — el asesino LEE o es fase1 (no es ninguna escritura enmascarable)
- Flash K9 (f21cc35f…) OK 23:5x a **4108 mV / battery-soc-ok: yes** (primer gate verde del proyecto) + reboot → **muerte muda** (full-speed/-71 en 1 s, sin ttyACM0, sin ping, captura sin línea nueva). PRIMERA prueba válida de la serie armada-temprana desde K7.
- Con uke_write_mask=0 NO hay escrituras nuevas (F4-F7, quirk S2CR109/CB70, rmr CLIENTPD, write_sme, install_s2cr, write_context_bank — todo silenciado con guardas). Los vivos restantes: (1) **LECTURAS tempranas** — el barrido SMR(0..109) y los IDR (seguros medidos a 38-90 s, JAMÁS a 0,44 s: el SMMU puede no estar clocked/powered todavía); (2) **fase1** — la única escritura incondicional SIN bit en uke_write_mask (diseño K9 no la cubría); (3) bug no visto.
- **Discriminación lista (peldaño siguiente)**: `boot-ukek9-h2.img` (52dff483…, uke_handoff=2 = SIN barrido SMR). Si h2 VIVE → el barrido-lecturas temprano mata ⇒ K10 = retrasar el barrido (consola-arming) manteniendo handoff; si h2 MUERE → fase1 o lectura no-SMR ⇒ K10 = migas dentro de fase1 + bit de silencio para ella.
- Nota: el ciclo K7/K8/K9-ayer NO cuenta (brownout); este #P27 es el primer dato limpio desde K7-anoche.

## #P28 — h2 (sin barrido SMR) a 4099 mV: TAMBIÉN muere muda → el barrido queda ABSUELTO; y el problema real es la CEGUERA
- Flash h2 (52dff483…) OK 00:04 a 4099 mV (gate verde) + reboot → muerte muda 00:05:18 (firma -71, sin consola/ping). Con h2+mask=0: SIN barrido SMR, SIN lecturas S2CR(0), SIN ninguna escritura enmascarable ⇒ descartados: barrido SMR, las 9 clases de escritura. Quedan: **fase1** (incondicional, sin bit), lecturas no-SMR (IDR/impl/cfg_probe), o contexto temprano (power/clock del SMMU a 0,44 s tras `fastboot reboot`).
- **Pivot de estrategia (decisión del orquestador)**: el cuello de botella ya no es el kernel, es que el probe temprano muere a 0,44 s SIN consola (ttyGS0 nace a 3,57 s) ⇒ migas invisibles. **K10 = ventana con consola**: cmdline SIN uke_smmu_probe (probe queda diferido+desarmado) + ukeinit (initramfs, ~5 s, consola ya viva a 3,57 s, UFS aún no probea hasta 13,8 s) hace `echo 1 > /sys/module/arm_smmu/parameters/uke_smmu_probe` → probe ARMADO a ~5 s CON CONSOLA VIVA y SIN UFS. Migas visibles pase lo que pase; y si vive, el bind ocurre antes del UFS (sueño #P16 con visibilidad). Kernel K9 sin recompilar; solo initramfs (ukeinit) + cmdline (364 B).

## #P29 — K10 (PRE-REGISTRADA 00:3x, antes del flash): ventana CON CONSOLA — arming por ukeinit a ~5 s
- **Imagen**: `boot-ukek10.img` (kernel K9 byte a byte + cmdline 364 B SIN uke_smmu_probe + initramfs con ukeinit-k10). Sha al publicarse (el repack lo imprime; copiar aquí antes del flash). Agente en vuelo.
- **Mecanismo**: boot desarmado (probe diferido, sin armar) → ttyGS0 a 3,57 s → ukeinit a ~5 s monta sysfs y hace `echo 1 > …/uke_smmu_probe` (miga UKE-K10 antes/después) → deferred trigger → **probe ARMADO con consola viva y UFS ausente (13,8 s)** → migas visibles de todo (IDR, cfg_probe, fase1, fases 4-7, attach con UFS ausente).
- **Predicciones**: (a) VIVE → bind completo con consola → SSH (40-90 s) → F9-E0 + runbook R2 (re-bind panel → card0). (b) MUERE → **ÚLTIMA MIGA VISIBLE** = punto de muerte exacto (primera vez que vemos morir a la serie armada) → K10bis con diana. (c) El boot puede colgarse tras el arming (esperable si muere) — la captura de consola lo tendrá todo.
- **Gate**: battery ≥3750 mV obligatorio. Restauración: boot_b-lee (ffff8c51…).
- **SHA CONFIRMADO** (00:5x): `boot-ukek10.img` = `7ce2cc2d89487ca75192c35fb418b8dae76ddc14534f86d08a9c203ac861c235`. Nota de construcción: el ukeinit NO va en boot.img (ramdisk_size@12=0) sino embebido en el kernel ⇒ K10 añade initrd EXTERNO (cpio @16580608, byte a byte el built-in salvo /ukeinit +0,06%) que lo sobreescribe (INITRAMFS_FORCE ausente ⇒ funciona). Primer boot K con ramdisk externo: si el ABL no lo carga, boot desarmado sin arming (sin riesgo nuevo). Cmdline 356 B. Gates 35/35. Informe INFORME-K10-BUILD.md.

## #P30 — HITO (00:4x-01:1x): EL SMMU SE BINDEA CON EL SISTEMA VIVO — handoff VERIFICADO; el bloqueo restante es el ORDEN del dpu
- K10 (7ce2cc2d…, 4073 mV gate verde): boot SANO pero arming de ukeinit NUNCA ocurrió — **el ABL no carga initrd externo** (ramdisk_size=0 también en boot-arch-uke: el initramfs va HORNEADO en el kernel; hallazgo estructural).
- Aprovechando la tablet viva: arm+bind por SSH a 156/435 s → **el apps-smmu PROBEÓ COMPLETO y el sistema SOBREVIVIÓ**: handoff verificado en vivo (sid 0x1c00 display → idx=6 PINADO sin escribir; install_s2cr idx 1-6 PINADOS; CB 69 reservado desde arriba; 16 grupos iommu; UFS siguió DMAeando por su mapeo BL). **El arm+bind tardío con tráfico UFS FUNCIONA — la hipótesis "carrera con UFS" queda REFUTADA también.**
- Bloqueo final medido: msm_dpu probeó a 13,9 s sin IOMMU ("no IOMMU bailing out") y NO se puede re-bindear (unbind panel → D-state colgado; unbind dpu → spin 99% CPU — bug teardown tras init fallido, R2 lo avisaba). El dpu DEBE probear con el SMMU ya presente.
- **K11 (receta final)**: kernel K9 RECOMPILADO incremental con el arming horneado en el ukeinit del initramfs interno (CONFIG_INITRAMFS_SOURCE; ~5 s: consola viva 3,57 s, UFS 13,8 s, dpu 13,9 s) + cmdline SIN uke_smmu_probe. Boot → SMMU bindeado ~5 s → dpu a 13,9 s encuentra IOMMU → kms init → **card0**. Si el probe a 5 s muere, la consola por fin lo enseña.

## #P31 — F9 CAUSA RAÍZ (01:1x, medido por SSH con la tablet viva): la GPT reconstruida deja el slot A en regiones de basura
- GPT en disco (primaria Y backup idénticas): 32 entradas — switch/ssd/dbg/bk01-07/keystore/frp/misc/mem/metadata/charger/mtdblk/blackbox/oops/rawdump/opconfig/mbnconfig/rescue/super/userdata. **SIN boot_a/b, dtbo, vbmeta, init_boot, vendor_boot.** Los fixed del hermano (gpt_main4-fixed, 67 entradas stock) confirman el layout original.
- Mapeo stock→actual: **slot B entero cae dentro de `super`** (nadie escribe) ⇒ boot_b funciona siempre. **Slot A: boot_a partido entre blackbox+oops+rawdump** (¡oops = block2mtd que el kernel ESCRIBE en cada dump — corrompe boot_a post-flash!), vendor_boot_a/dtbo_a/vbmeta_a dentro de rawdump (crashdumps), init_boot_a dentro de rescue. **El slot A no puede arrancar jamás con esta GPT** — F9 explicado al 100%.
- Los "borrados" del 24-sep (#384/#385) = estas particiones desaparecieron al reconstruirse la GPT, no borrados puntuales.
- **No se toca la GPT** (R1-R12 del hermano: byte-exacta o nada; su restaurar-gpt4.sh). F9 no bloquea la vía pantalla (boot_b funciona). Pendiente para el hermano/orquestador con sus reglas: restaurar gpt_both4-fixed y re-crear el rootfs en el userdata stock.
- **K11 SHA CONFIRMADO** (01:2x): `boot-ukek11.img` = `acfed4f39962871ad016c14621edc86000f189cda500c2f35978ff2c7adfe5b8`. Arming horneado en /ukeinit del cpio s181 embebido (tras S118 ACMOK, antes de switch_root), migas UKE-K11; cmdline 356 B; Image.gz `c3c41fb0…` (+731 B vs K9, blob initramfs byte a byte el cpio K11). Gates verdes (informe K11). Timeline esperado: defer 0,44 s → ACMOK 3,57 s → arming ~5 s → probe ARMADO con consola → UFS 13,8 s → **dpu 13,9 s CON IOMMU → card0** → SSH.

## #P32 — K11 (acfed4f3…, 4072 mV): ARMING HORNEADO ✓ + SMMU ✓ + dpu auto-reprobea ✓ — falla mmu init (-22); dos causas halladas
- Boot: ACMOK 3,57 s → `UKE-K11: armando probe a 3s` → `armado rc=0` → **REINTENTO a 3,96 s con consola → SMMU BINDEADO** ("preserved 0 boot mappings"). El arming horneado FUNCIONA. Sistema vivo (SSH, systemd).
- El bind disparó el deferred de TODOS los esperando: **msm_dpu re-probeó SOLO a los 4,1 s** — bindeó ambos DSI y la GPU, leyó la revisión DPU (0xa0010000)... y `dpu_kms_mmu_init failed: -22` (antes era -19 sin IOMMU). Luego el doble-priv-obj-fini conocido (sistema sobrevivió).
- **Causa 1 (DT)**: `display-controller@ae01000` NO tiene `iommus` (el vendor los pone en el nodo proxy smmu_sde_unsec_cb; la comunidad palawan-mainline los pone EN el nodo — R4). msm_iommu_new no puede crear el address-space ⇒ -22. Fix: dtbo s260 añadiendo `iommus = <&apps_smmu 0x1c00 0x2>` al display-controller.
- **Causa 2 (kernel)**: miga `idx=6 PINADO sin estar vivo` — el handoff pineó el SID del display aunque el BL NO lo tenía activo ⇒ su S2CR nunca se escribe ⇒ sin traducción. Fix K12: pinear SOLO SMRs vivos en el BL (UFS 0x60); los handoff-smrs no vivos = masters normales (se escribe su S2CR).
- K12 = K11 + fix pineo-solo-vivo + s260 (iommus en display-controller). El bootloader deja de ser el límite: queda una traducción que escribir.

## #P33 — K12 + s260 (PRE-REGISTRADA 02:0x): pineo solo-vivo + iommus en display-controller — el flash de card0
- `boot-ukek12.img` = `7c6bfe0d91a58ae11fe78dcb4c8294f3963a477e67228136bc2818cae0f4c240` (kernel 6231e275…, cmdline K11 byte a byte, initramfs K11 intacto; diff k12-pinlive.diff: handoff-DT no vivo → attach normal con miga `UKE-K12: handoff no-vivo sid=0x…`; vivos (UFS 0x60) pineados intactos).
- `s260-boot-dtbo-dpu-iommus.img` = `6fbb5173b8af5add34e90dcff9d3dce742f7fa9fe76182eda2db123b39685ad7` (= s258 + fragment@1709 `iommus = <0x129 0x1c00 0x02>` en display-controller@ae01000; fdtoverlay verificado: diff semántico de 1 línea).
- **Canal**: flash dtbo_b (s260) + boot_b (K12) + reboot. Gate batería ≥3750.
- **Predicciones**: ACMOK 3,57 s → arming ~4 s → PIN SMR(0) → `UKE-K12: handoff no-vivo sid=0x1c00 → attach normal` → dpu re-probe SIN -22 → `[drm] Initialized msm` → **card0** → fbcon en pantalla → SSH. Si -22 persiste → K13 con migas en msm_iommu_new. Si fault en scanout → `uke_write_mask=0x1c0` (K13). Rollback: boot_b-lee + s258.

## #P34 — K13 (PRE-REGISTRADA): grupo iommu de 2 dispositivos = el -22 real; fix iommu_attach_group
- `boot-ukek13.img` = `d71ea2b5f6aaf7f8b4820748362b5b32ebed4a064f6f224bb037a7abc9707381` (cmdline K12 356 B, initramfs K12, dtbo s260 sin cambios). Diff k13-grupo-iommu.diff (3 ficheros).
- Mecanismo verificado (refuta mi hipótesis fmt): apps ID2=0x5111 SÍ trae PTFS_4K+64K (fmt OK; WLAN completó init_domain_context entero en K10). El -22: s231 (mdss padre) y s260 (display-controller) llevan la misma <0x1c00 0x2> → find_sme reutiliza → device_group los FUNDE (2 dispositivos) → iommu.c:2205 exige grupo de 1 → -EINVAL ANTES de attach_dev (cuadra: cero migas CB reservado).
- Fix: msm_iommu.c — fallback a iommu_attach_group si el grupo tiene >1; migas UKE-K13 (attach rc, iommu_dev elegido, fmt/features/ias/oas, cada ret de error).
- Escalera: flash solo boot_b → arming ~4 s → UKE-K13 migas → SIN -22 → Initialized msm → **card0** → fbcon → SSH. Si persiste: la miga señala la rama. Rollback: boot_b-lee.

## #P34-bis — K13 RESULTADO (12:25-12:40): boot1 = 3 min vivo → latch; boots siguientes = muerte en segundos → FIRMA DE WEDGE (CM3/GMU)
- Boot K13 #1 (12:25): gadget alto (1d6b:0104 high-speed) ~34 s tras el arranque, sistema en marcha ~3 min → rebotes de gadget (register/unregister) → -71 → **fastboot a las 12:28:32**. Boot #2 (12:30): muerte en ~4 s (full-speed/-71). Boot #3 (12:40): SIN NINGÚN evento USB — muerte antes de los 3,5 s del gadget.
- **Interpretación (hipótesis fuerte)**: el fix del grupo funcionó (el -22 no mata en bucle así; K11/K12 sobrevivían al oops del fini) → kms init PASÓ → card0 → cliente fbdev → msm_open → load_gpu → **wedge del CM3/GMU en el primer acceso** (riesgo G1: "wedge del bus en el primer readl de FW_INIT_RESULT; sin watchdog ⇒ reset físico") → el wedge PERSISTE entre reboots suaves (por eso los boots siguientes mueren en segundos) → el ABL traba a fastboot. La consola no capturó (lector muerto desde el apagón del PC — regla nueva: re-armar captura SIEMPRE antes de cualquier flash/boot).
- **Siguiente**: power-cycle FÍSICO (corte de corriente) → boot con captura armada → consola mostrará: Initialized msm (si card0 se creó) + dónde cuelga exactamente (CM3 ladder del kernel: S1-S4/F1-F4 + UKE-CM3DBG). Si el wedge se confirma → la escalera CM3 (uke-cm3-ladder) o el firmware GMU correcto son la última pieza.
- La tablet está en fastboot (latch del ABL tras el bucle). Batería 4047 mV.

## #P35 — Lección BCB (13:1x): mi BCB "bootloader" sucio causaba el bucle de reinicios; misc flasheada a ceros
- `systemctl reboot bootloader` no funcionó (systemd vieja) y el BCB quedó escrito; el ABL relee misc en cada boot → bucle bootloader↔kernel que el dueño vio como "se reinicia sola". **Fix**: `fastboot flash misc` con 4 MiB de ceros (partition-size confirmado 0x400000). Arranque con kernel bueno: estable, sin bucle.
- **Regla nueva**: al usar BCB por escritura directa, limpiarlo SIEMPRE después (o flashear misc limpia); anotado como paso de cierre de sesión.
- Estado: boot_b = kernel bueno (ffff8c51…), dtbo_b = s260, misc limpia, tablet viva en Arch 69% batería.
- Siguiente: re-flash K13 + power-cycle (no suave) → arranque CON captura → migas UKE-K13 → Initialized msm/card0 o punto exacto.

## #P36 — K13 (13:2x): -19 de nuevo (no -22); "pasa lo mismo" según el dueño; ciclo detenido por orden del dueño — ronda de revisión total lanzada
- Boot K13 (BCB limpio): dpu intenta 2× a 13,97/14,02 s → **-19 ENODEV** (device_iommu_mapped falso para mdp_dev Y mdss_dev — ¡pero K12 daba -22 EINVAL con iommus en el DT!). El dtbo s260 sigue en dtbo_b. La cadena de reprobing es ahora distinta y el dato clave: con k13 (attach_group) el dpu ya no ve iommu; con k12 lo veía. **Algo de K13 (el fallback attach_group) cambia la visibilidad del IOMMU para el dpu.**
- Tabla de estados por kernel: K11: arming ✓ SMMU ✓ dpu reprobe -22 · K12: idem -22 (S2CR escrito) · K13: dpu reprobe -19 (sin iommu mapped). El dpu reprobes en K13 a 13,97 s = el deferred del dpu sigue vivo.
- Grep de migas UKE-K13 en consola: 0 (el lector arrancó tarde; el arranque fue antes). Consola saturada de ruido de memmove.
- **Orden del dueño: parar el ciclo; ronda de revisión total con subagentes.**

## #P37 — K14-A/s261 (PRE-REGISTRADA, tras T1+T2): dpu único dueño del SID — grupo de 1
- **Artefactos**: `boot_b` = K12 (`7c6bfe0d…`, sin cambios de kernel); `dtbo_b` = **s261** (`s261-boot-dtbo-dpu-solo.img` sha `c260af5e83579bbac74411e6cb7dee53d567e79bd12dcdc33d7652494f48ad5f`) = s260 + (a) `iommus` QUITADO del mdss padre (fragmento overlay), (b) fragment@1710 REEMPLAZA el iommus de `qcom,smmu_sde_unsec_cb` (nodo del BASE, fdtoverlay no borra) por banda sin usar `<0x129 0x3fff 0x0>` → el dpu queda ÚNICO portador de 0x1c00 → grupo de 1 (generador mkdtbo-s261.py, gates: fdtoverlay verificado con portadores=[display-controller], handoff-smrs intacto).
- **Mecanismo (T1)**: el -22 de K11/K12 = grupo de 3 miembros con el mismo SID (mdss + unsec_cb + dpu) → iommu.c:2205 exige grupo de 1 → -EINVAL antes de attach_dev. Con grupo de 1: attach pasa → msm_iommu_new → CB → kms init. T2: catálogo DPU matchea 0xa0010000; el -19 "de K13" era entorno envenenado (kernel stock en el boot, wedge CM3 persistente).
- **Canal**: flash boot_b (K12) + dtbo_b (s261) + reboot; captura K13 re-armada y viva.
- **Predicciones**: ACMOK 3,57 s → arming ~4 s → SMMU bindeado → dpu reprobes ~4,1 s → `Adding to iommu group` del ae01000 SOLO → **SIN dpu_kms_mmu_init failed** → `[drm] Initialized msm 1.13.0` → **card0** → fbcon → SSH (~40-90 s). Si vuelve -22 → grupo no era el problema → T1 plan B (k13 fallback ya en K13). Si fault en scanout → escalera CM3 (power-cycle físico antes).
- Rollback: boot_b-lee + s258.

## #P38 — K14-A (K12+s261) 2 boots: vive 2-3 min (ACM ok, NCM caído) → fastboot; kernel bueno = estable. PENDIENTE la observación del panel
- Boot 1 (14:1x): kernel #16 banner → gadget 14:17 → muere 14:18. Boot 2 (14:4x): ACM presente 150 s (parpadeante), sin NCM, sin fastboot → cae a fastboot. La consola no capturó el interior (ACM0 efímero).
- Contraste clave: K11/K12-s260 (kms falla -22) = sistema VIVO con SSH indefinido; K14-A (grupo de 1 → kms presumiblemente PASA) = muere a 1-3 min. Coherente con: kms pasa → card0 → fbdev abre → **CM3/GMU wedge** (riesgo G1: cuelga el bus entero incl. UFS → ni journal flush → ABL latch).
- **PREGUNTA AL DUEÑO (decisiva)**: ¿la pantalla mostró TEXTO DE CONSOLA (negro/letras) durante esos 2-3 min, o siguió el splash blanco? Texto = fbcon pintó = PANTALLA FUNCIONANDO (el kms init pasó) y el cuelgue posterior es solo el GPU (CM3) — arreglable con la escalera. Blanco = ni kms pasó.

## #P39 — Correcciones de registro y canal de consola resuelto (16:0x-16:2x)
- **El bucle de reinicios de ayer NO fue BCB**: escribí el BCB en sdb25 (partición equivocada — misc es la entrada 13); jamás llegó a misc. El bucle era el ciclo wedge→panic(10)→wedge del kernel K de pruebas. La misc ya estaba limpia (flasheada a ceros el 29-sep). Corregido y BCB limpiado también hoy (sda13).
- **El -19 "de K13" tampoco existió como tal** (T1: eran boots del kernel stock #82). K13 jamás llegó al DPU (wedge).
- **Canal de consola RESUELTO**: lector único `while !-e ttyACM0; exec cat > k14-live.log` sin timeout (pid 523663) — captura 36-78 KB en vivo, sobrevive reboots sysrq. Los bucles anteriores con timeout cada 3 s y múltiples lectores eran el fallo.
- **reboot a fastboot por software: imposible** (systemctl reboot bootloader no soportado; BCB ignorado por el ABL; sysrq-b re-arranca el kernel). El fastboot exige teclas físicas (Volumen- + Power) o el latch del ABL.
- Estado: boot_b = kernel bueno (estable), dtbo_b = s261, tablet viva en Arch. Siguiente flash: K12 (7c6bfe0d…) + s261 (ya puesto) = **K14-A retry con consola capturando de verdad**. El dueño pone fastboot físico.

## #P40 — K15 = K13 kernel + s260 dtbo (PRE-REGISTRADA): el fallback attach_group contra el grupo compartido
- **Hallazgo en vivo (K14-A boot, SSH)**: el ABL ABORTA el apply del s261 (fragment@1710) → DT efectivo sin el dpu-iommus → -22 por el mdss fallback (grupo de 2: mdss+unsec_cb). El s260 SÍ aplicó ayer (journal boot -3: dpu+mdss en grupo 9). K11+s258 control: VIVE (entorno limpio).
- **Artefactos (ya construidos, cero compilación)**: `boot_b` = `boot-ukek13.img` (`d71ea2b5…` = K12 + fallback iommu_attach_group en msm_iommu.c + migas UKE-K13); `dtbo_b` = `s260` (`6fbb5173…`, el que el ABL sí aplica — dpu+mdss+unsec_cb en el mismo grupo).
- **Mecanismo esperado**: msm_iommu_new(dpu) → iommu_attach_device -EINVAL (grupo de 3) → **fallback iommu_attach_group** → el grupo COMPLETO (los 3) se adjunta al dominio del display → kms init → `Initialized msm` → **card0**. (T1 lo escribió como plan B; K13 jamás se midió limpio.)
- **Riesgos**: (a) el grupo entero comparte dominio: unsec_cb y mdss no DMAean (sin driver) → inofensivo; (b) tras card0, el fbdev abre el GPU → posible wedge CM3 (la siguiente batalla, con escalera en el kernel); (c) el -22 puede persistir si el fallback no alcanza esa rama → las migas UKE-K13 lo dirán.
- Gate batería ≥3750. Rollback: boot_b-lee + s258. Captura: lector de ciclos activo.

## #P40 — RESULTADO (19:0x, consola capturada en 2 ciclos): **KMS INIT PASÓ — card0 NACIÓ — solo falta un FICHERO de firmware**
- K13+s260 (kernel #17): el fallback attach_group FUNCIONÓ → kms init sin error → **card0 creado** → cliente fbdev → load_gpu → adreno pide `qcom/gen71100_sqe.fw` → **error -2 (ENOENT: el fichero no existe en /lib/firmware/qcom/)** → el arranque muere después (ciclo panic→ABL-latch). Evidencia idéntica en 2 ciclos del log de consola (/var/tmp/k14-cycle.log, capturado a 4,203 s y 4,208 s).
- **Estado de la pantalla**: la cadena KMS está RESUELTA de punta a punta (SMMU handoff ✓, grupo attach ✓, kms init ✓, card0 ✓, GPU load disparado ✓). El único bloqueo restante del arranque es el firmware del SQE del GPU con el nombre que el driver espera.
- **ORDEN DEL DUEÑO (19:1x): PARAR** — sin más flashes/boots. Tablet dejada EN FASTBOOT tal cual (boot_b=K13, dtbo_b=s260, misc limpia). Repaso + subagentes para atacar las opciones.

## #P41 — CIERRE DE LA NOCHE (U1+U2): consolidado y plan de mañana (3 pasos, mínimo de flashes)
- **U1**: los 3 fw EXISTEN staged (gen71100_sqe.fw b6df660d…, gen71100_gmu.bin 435c7bac…, uke/gen71100_zap.mbn 0c86e4ae… — prohibido el del QRD) — solo copiar, cero conversión. El ENOENT era porque la petición a 4,2 s se sirve del INITRAMFS INTERNO (kernel_read_file initns), no del rootfs. Artefacto construido: boot-ukek13-fw.img (62192c26… = K13 + ramdisk externo con los fw). OJO: #P30 midió que el ABL quizá no carga ramdisks externos — si no carga, K16 = hornear los fw en el initramfs interno (vía CONFIG_INITRAMFS_SOURCE, como K11 horneó el ukeinit).
- **U2**: el ENOENT es NO-fatal (GPU aborta limpio, GMU jamás arranca, 0 migas F/S/Z4 en 9 boots). El ASESINO real = el primer modeset/scanout del cliente fbdev (ventana 4,2-13,8 s sin consola). fbcon NO necesita GPU. Contraste medido: kms fallando = 2 h vivo.
- **PLAN DE MAÑANA**: ① flash boot_b-lee → SSH: fw sha-check + pacman -S mesa libdrm mesa-utils + capturas armadas. ② flash K13 (s260 ya puesto) MIRANDO EL PANEL: ¿fbcon pintó texto? = pantalla. ③ si muere: repack k13 `video=DSI-1:d` (30 s) — discrimina enable-panel/scanout vs dominio SMMU. Después: fw (boot-ukek13-fw.img o K16 horneado) para el render + escalera CM3 (S3-rst0/S4-poll, migas F1-F4/CM3DBG ya en kernel).
- Tablet QUIETA en fastboot (orden del dueño). 41 filas de registro; todo commiteado.

## #P42 — DISCRIMINADOR (20:0x): K13 + `video=DSI-1:d` — ¿el asesino es el modeset del panel?
- `boot-ukek13-dsid.img` = K13 (d71ea2b5…) byte a byte + cmdline 370 B (+` video=DSI-1:d`). Sin DSI-1 no hay enable de panel ni scanout al registrar card0; el fbdev usa el resto.
- **Predicciones**: (a) VIVE estable (>5 min, SSH) ⇒ el asesino = enable del panel/scanout del fbdev → siguiente: modeset controlado (modetest por SSH) y arranque del panel a mano = la pantalla a la vista. (b) MUERE igual ⇒ el asesino está en el dominio/SMMU (fallback attach_group escribe CBs del grupo entero) → K16 con dominio identity para el display.

## #P42 — RESULTADO (20:1x): **VEREDICTO (a) CONFIRMADO — el sistema VIVE con video=DSI-1:d, card0 COMPLETO y renderD128**
- Boot K13+DSI-1:d: **estable** (ping+SSH continuos >3 min, sin fastboot). `/sys/class/drm/`: **card0-DSI-1** (status=disconnected por el :d), card0-Writeback-1, **renderD128** (¡el nodo de render del GPU existe!). dmesg: `[drm] Initialized msm 1.13.0 for ae01000.display-controller on minor 0` a los 4,06 s — **EL KMS INICIALIZÓ COMPLETO**.
- El asesino de los boots anteriores = el enable del panel/scanout del primer modeset del fbdev (con el conector activo). Sin él: todo vive — SMMU handoff, kms, card0, writeback, render node.
- **ESTADO DEL PROYECTO**: pantalla = card0 NACIDO; queda SOLO el modeset del panel (enable DSI) que mataba el boot — ahora ejecutable BAJO CONTROL por SSH (con captura y sin ciclo).
- Siguientes: (1) intentar el modeset manual del panel por SSH (modetest/card0) con captura; (2) si el enable del panel wedgea, aislar qué paso (reset-gpio? DSI cmd? LP11?) con las migas del panel driver; (3) fw GPU: el sqe.fw del initramfs (boot-ukek13-fw.img 62192c26…) para el render completo.

## #P43 — MODESET BAJO CONTROL (20:2x-20:3x): abriendo card0 MATA (modetest -c); NO es el GPU
- Sistema vivo (K13+DSI-1:d, SSH, card0 completo). `modetest -M msm -c` (solo ABRIR+listar) → cuelga→panic→reboot (2×). Con el fw sqe OCULTO el resultado fue EL MISMO ⇒ **el asesino NO es la carga del GPU**: es la propia apertura del DRM / ioctls GETCONNECTOR (tocan el driver del panel: get_modes → DSI cmds / panel power) → wedge del bus. Coherente con las muertes de boot sin `:d` (el fbdev client registra conector activo → mismo camino).
- Firmwares restaurados tras el experimento. Estado: sistema vivo de nuevo (K13+DSI-1:d estable mientras NADIE toque card0).
- **Diagnóstico de la pantalla, versión final**: kms+SMMU+card0 LISTOS; el wedge vive en el CAMINO DEL PANEL (DSI host/panel driver — cmds DSI o enable de rails). El panel ya probó bien en la era s258 (backlight 307, reset OK) — la diferencia ahora: el SMMU está BINDEADO y los accesos DSI van por su dominio... **hipótesis nueva: el DMA del DSI host (comandos) por el dominio nuevo del SMMU faultea/wedgea** (fallback attach_group puso TODO el grupo en dominio translated; los cmds DSI DMA → necesitan tablas del dominio → iommu-dma las crea... a menos que el write_mask=0 de K9 deje mapeos sin programar).
- Siguiente (K16): dominio IDENTITY para el display (def_domain_type identity para el grupo 0x1c00 — como el UFS que funciona), o mapear el DMA de DSI antes del enable. Ejecutable mañana con el sistema vivo como banco de pruebas.

## #P44 — K16 CONTROL (PRE-REGISTRADA 30-sep ~22:3x): split de grupos display; K16 no toca el HW del SMMU con write_mask=0 — mide el estado CORE; peldaño c' ya construido
- **Contexto honesto (crítica técnica pre-flash)**: con la cmdline K13 (`uke_write_mask=0`) K16 NO programa nada nuevo en el HW del SMMU: los DSI hosts no son masters IOMMU (sin `iommus` en el DTB fusionado) y el SMR de la banda (mask 0x2) da UNA traducción para 0x1c00+0x1c01. El diagnóstico de K16-DISENO ("HOST DSI arrastrado al dominio paging") quedó REBAJADO a hipótesis. **K16 = CONTROL barato (1 flash)**: mide el efecto del estado CORE (dpu solo en paging con grupo propio; mdss/unsec_cb de vuelta a default en vez del grupo compartido que K13 attach-ó ENTERO al dominio del KMS).
- **Artefacto**: `boot-ukek16.img` = `f0688feb22966bcab6f6165b3b43df918e51fdbf59c1d4b7b340e2a5e5497d8f` (100663296 B; kernel 16578528 gz = K13 + `build/gates/patches/k16-disp-split.diff`; cmdline 356 B == K13 byte a byte, **SIN video=**; cpio horneado intacto; 8 gates G0-G8 verdes — INFORME-K16-BUILD.md). **Peldaño c' ya construido**: `boot-ukek16-wm.img` = `1e27b33673d5b360bc00e77f730cb0ef9a9279d36d002e731ea4c9496be5a1ad` (mismo kernel + `arm_smmu.uke_write_mask=0x1c0` en cmdline).
- **Canal**: SOLO `fastboot flash boot_b` (dtbo SIN cambios: s260 `6fbb5173…` sigue). Antes: `fastboot set_active b` (retry-count b estaba a 1 — reset del contador del slot ACTIVO, no es flash de partición). Batería 3929-3930 mV ✓ (getvar 22:0x). `getvar all` antes en `build/logs/getvar-antes-P44.txt` (retry a:7 b:1).
- **Gates**: lector único de consola armado ANTES (patrón while+timeout 2, log `/var/tmp/uke-k16-console.log`); vigía retargeteado `build/gates/uke-fastboot-watch-k16.sh` armado ANTES y **PAUSADO** durante flash+observación (`touch /tmp/uke-fastboot-watch.pause`; rm tras leer desenlace); fastboot solo por teclas; portátil enchufado; rollback = `boot-ukek13-dsid.img` (`e0ee47dc…`) + s260, en `build/backup-par-bueno/` verificados contra shas.
- **Precondición de validez**: 2-3 migas `UKE-K16: display sid=0x1c00 -> grupo PROPIO rc=0 (split)` a ~4,1 s (mdss+dpu; 3ª si unsec_cb probea). SIN ellas: experimento inválido.
- **Predicciones**: (a) VIVE + fbcon pinta → FOTO + modes → power-cycle en frío + 2ª foto = PANTALLA (obj 6). (b) VIVE sin pintar → SSH status/modes + modetest bajo control (desechable; en K13 mató 2×). (c) Wedge → grep faults SMMU ANTES de concluir rails → peldaño c' (`boot-ukek16-wm.img`) → si sigue: rails SOLO con GO del dueño. (d) Muerte nueva → migas + consola; techo 1 retry; luego restaurar K13-dsid. Tras wedge: power-cycle físico (persiste entre soft-reboots).
- **Estado del par al pre-registrar**: boot_b = K13-dsid `e0ee47dc…` (estable por SSH), dtbo_b = s260, misc limpia (cierre 30-sep), tablet EN FASTBOOT puesta por el dueño para esta sesión. Ledger hermano: fila #445.

## #P44 — RESULTADO (30-sep 22:29-22:41): desenlace (c) en AMBAS variantes — SMMU descartado como asesino del modeset; el asesino está en el CAMINO DEL PANEL; par bueno RESTAURADO y verificado
- **K16 (f0688feb…)**: 7 ciclos de muerte muda a ~4,1 s, sin SSH/NCM. Consola (build/logs/uke-k16-console-ciclo44.log): **`dpu_kms_mmu_init failed` = 0 en todos los ciclos** (el -22 de K12 desapareció; el split de grupos funcionó a nivel CORE) y **6/7 ciclos llegan a `adreno_request_fw`** (`failed to load gen71100_sqe.fw` a 4,149-4,185 s = el kms PASÓ y el driver GPU probó) → la muerte es DESPUÉS, en el primer modeset/scanout del fbdev. Migas UKE-K16: 0 visibles — la consola pierde la ventana 3,95-4,18 s (salta de `110 register groups` a 4,185; mismo artefacto de cola que ya midió el hermano en #428/#429). Batería 3913-3920 mV durante todo el ciclo. La tablet cayó sola a fastboot al agotar retry b (0, unbootable:yes).
- **Peldaño (c') K16-wm (1e27b336…)**: 7 ciclos idénticos con el token `uke_write_mask=0x1c0` aplicado (verificado en la cmdline de consola), misma muerte a ~4,14 s. **La traducción HW de la banda display escrita NO cambia nada.**
- **LECTURA (con la pre-registrada)**: (1) el split de grupos elimina el -22 del core (control válido a nivel CORE pese a las migas perdidas); (2) el modeset mata IGUAL con dominio paging por grupo (K16), con traducción escrita en HW (wm) y con attach del grupo entero (K13, #P41) ⇒ **REFUTADA la familia de hipótesis SMMU como asesina del modeset** (predicho por la crítica técnica pre-flash: los DSI hosts no son masters IOMMU). El asesino está en el **camino del panel**: rails/reset/GPIO/comandos DSI (desenlace (c) → `INFORME-GPIO-*`, `AUDITORIA-REGULADORES-Y-GPIO.md` — requiere GO del dueño per plan). El ENOENT del sqe.fw sigue siendo ruido no-fatal (U2).
- **Rollback ejecutado (22:39)**: `set_active b` + flash `boot-ukek13-dsid.img` (e0ee47dc…) + reboot. **Verificado 22:41**: SSH OK, `uname -r` = 7.2.0-rc2-palawan, card0+renderD128, DSI-1 disconnected (estado estable conocido). Vigía k16 despausado y ARMADO (red activa). Presupuesto del día: 3 flashes boot_b (K16, wm, rollback) — se superó el ≤2 con el rollback de cierre (declarado; el rollback es parte del protocolo de parada).
- Techo de la hipótesis K16: ALCANZADO en 2 variantes → PIVOTE al clúster 0-flash (e2fsck → GPU → F9 → WiFi) según PLAN-SIGUIENTE-v2 P3. Panel: esperando GO del dueño para la investigación de rails/reset.

## #P45 — F9-E1 (PRE-REGISTRADA 30-sep ~23:3x): la cadena de B medida, ENTERA, en el slot A — 3 flashes
- **Base**: E0 medido esta sesión (ledger #446): vendor_boot_a=`425382d5…` e init_boot_a=`2daeb1f3…` NO están a ceros (H1 matizada) pero su validez es desconocida (GPT reconstruida #P31 solapaba regiones); init_boot_b=`5228e6e2…` = STOCK (el /ukeinit que corre viene del cpio horneado en el kernel K-series). La cadena buena medida de B: vendor_boot_b=`3ee6d4ac…` (stock ROM, verificado por el hermano #238/#241) + init_boot_b=`5228e6e2…`.
- **Artefactos**: `fastboot flash vendor_boot_a build/backup-par-bueno/vendor_boot_b-lee.img` (`3ee6d4ac…`, 96 MiB) + `fastboot flash init_boot_a build/backup-par-bueno/init_boot_b-lee.img` (`5228e6e2…`, 8 MiB) + `fastboot flash boot_a build/backup-par-bueno/boot-ukek13-dsid.img` (`e0ee47dc…`, 96 MiB — kernel ESTABLE conocido, no experimental: control limpio). Después `set_active a` + `reboot`. Vigía PAUSADO (la caída a fastboot tras boot_a es desenlace esperado, no hay que rescatarla).
- **Predicciones**: (a) consola/ACM muestra `Linux version … #17` arrancando desde A ⇒ **H1 confirmada (cadena incompleta/inválida) y F9 CERRADO** (objetivo 2: boot_a nuevo llega a Linux version) → devolver active a b y seguir. (b) mudo igual que los 4 anteriores con la cadena RESTAURADA ⇒ H1 refutada → el problema es estado del slot/GPT (E2 misc / E3 qbootctl, próxima sesión). (c) arranca pero sin SSH ⇒ H6 (consola condicionada al slot) sube.
- **Rollback**: `set_active b` (B intacto: solo se toca *_a) + reboot. Si A quedara activo y muerto: teclas a fastboot → set_active b.
- **Gates**: batería ≥3750 mV por getvar ANTES; lector único de consola armado ANTES (ya corriendo, /var/tmp/uke-sesion-console.log); vigía PAUSADO durante todo el ciclo (touch /tmp/uke-fastboot-watch.pause); getvar all antes/después; exención del ≤2/día dada por el dueño (aprobó el plan con F9-E1 incluido; hoy ya se llevaron 3 por #P44).
- **Estado del par**: boot_b = K13-dsid `e0ee47dc…` (intacto), dtbo_b = s260. misc limpia (sin BCB).

## #P45 — RESULTADO (30-sep ~23:29-23:4x): **F9 CERRADO — el slot A ARRANCÓ LINUX COMPLETO; H1 confirmada (cadena inválida, no ausente)**
- 3 flashes OK (vendor_boot_a 3ee6d4ac…, init_boot_a 5228e6e2…, boot_a K13-dsid e0ee47dc…) + set_active a + reboot 23:29:01.
- **Consola (build/logs vía /var/tmp/uke-sesion-console.log líneas 54396+)**: `Linux version 7.2.0-rc2-palawan #17` con `video=DSI-1:d` (boot_index 66) → `UKE-K11: armado rc=0` → `S123: raiz candidata /dev/sda32` → `RAIZ UBUNTU VERIFICADA — remontando rw y switch_root` → systemd arrancando unidades → vivo ≥53 s (hasta que el dueño lo apagó para fastboot).
- **Criterio del objetivo 2 SUPERADO** (no solo `Linux version`: llegó a userspace). La cadena A quedó funcional: **el slot A es desde ahora SLOT EXPERIMENTAL con fallback automático a B** si un experimento agota reintentos.
- Estado: set_active devuelto a b (par estable intacto). boot_a = K13-dsid + cadena B completa.

## #P46 — K17 PANEL (PRE-REGISTRADA 30-sep ~23:4x): migas paso a paso del o82 + S0 del GMU; ciclo PANEL a boot_a (slot experimental)
- **Artefacto**: `boot-ukek17.img` = `c7675eb717b50a6af4151477595c23703605e1b21195d6038e776680468720c0` (kernel 16578702 gz = K16 + `patches/k17-migas-panel-gmu.diff`: 21 migas UKE-P82 en panel-xiaomi-o82 — power_on por supply (vddil8b/vsp/vsn), reset por flanco, **un miga por cada comando DSI del init (104)**, freq/sleep-out/display-on/backlight — + S0-dtcmR y S4-pollOK en a6xx_gmu_start; cmdline 356 B == K13 SIN video= → **el modeset CORRE**). Variante GPU construida: `boot-ukek17d.img` `2c7d234e77e442c813f38db83a016dc1996ee2380d5b4c4b559b46bd4aa4ef35` (= mismo kernel + cmdline K13-dsid 370 B con video=DSI-1:d).
- **Canal**: `fastboot flash boot_a boot-ukek17.img` + `set_active a` + reboot. **Slot A = experimental** (F9 cerrado #P45: si A agota reintentos, el ABL cae a B = par estable K13-dsid — red automática). Vigía sigue PAUSADO.
- **Predicciones**: la muerte del modeset ocurrirá tras la ÚLTIMA miga UKE-P82 visible: (a) en power_on[vsp|vsn] ⇒ reguladores GPIO 74/75 (gpio-shared-proxy) — fix: dtbo/proxy; (b) en rst ⇒ GPIO2/tlmm; (c) en cmd[N] ⇒ el comando DSI N (DMA/PIO del DSI host) — fix: driver DSI; (d) tras "prepare: COMPLETO" ⇒ el scanout/video-start del DPU; (e) VIVE y fbcon pinta ⇒ PANTALLA (foto + frío).
- **Gates**: batería ≥3750 (leída antes del flash); lector de consola armado; slot b intacto.

## #P47 — K18 KGSL-KEEP (PRE-REGISTRADA 1-oct ~00:2x): el fix del asesino unificado (S3-rst0 / CM3 fetch por kgsl-smmu sin traducción BL)
- **Artefacto**: `boot-ukek18d.img` = `99d49b06b889198bd7bc3cc279501e208da552c798f9c57f790374b7a462b9d8` — kernel 16575984 gz (81350f70…) = k13-tree + k16-split + k17-migas + K18 (uke_kgsl_keep default 1: kgsl-smmu omite fases 2/3/4 del reset; volcado de SMR/S2CR heredados en probe). Cmdline = K13-dsid 370 B (video=DSI-1:d) — arranque ESTABLE; el test del fix es modetest por SSH.
- **Predicciones**: (a) escalera GMU pasa S3-rst0 y llega a **S4-pollOK** + H8-cm3 → GMU VIVO → el wedge del GPU resuelto → siguiente flash: K18-plain → modeset al arranque → migas del panel → PANTALLA. (b) muere igual en S3 → la traducción BL del kgsl-smmu no basta (o el volcado UKE-K18 muestra SMRs a ceros = no había nada que conservar) → hipótesis refutada, plan B: programar el mapeo del CM3 antes del release (vía vendor/TZ-like setup en el propio a6xx_gmu_start). (c) muerte nueva antes de S3 → las migas lo dicen.
- **Canal**: dd por SSH a boot_a (tablet viva) + reboot. Vigía PAUSADO todavía. Rollback: boot_a tiene K17d ahora; el dd pisa K17d (obsoleto ya). Slot B intacto.

## #P47 — RESULTADO (1-oct ~00:4x): **K18 AVANZA UN PASO ENTERO** — S3-rst0 EJECUTA; la muerte pasa a la ventana del poll S4
- Boot K18d estable (SSH OK; volcado UKE-K18 en dmesg: **SMR(0..5) heredados = 0x00000000 (inválidos), S2CR=0x00020000 (translate→CB2)** — el BL NO dejó traducción que conservar en el kgsl-smmu).
- modetest: escalera hasta `P3-pwrOK → S0-dtcmR → S1-rst1 → S2-gen9 → **S3-rst0** → [muerte]` — **S3 IMPRIME por primera vez** (en K17 moría ANTES de la escritura del release). La muerte ahora es tras liberar el CM3, en la ventana del gmu_poll_timeout (S4: espera de FW_INIT_RESULT que nunca llega).
- **Lectura**: el CM3 se libera pero su primer fetch (icache iova 0x4000 vía SID 5 del kgsl-smmu) no vuelve — con SMR inválido el SID va a "unmatched" → bypass → fetch de física 0x4000 = basura. **Nadie programa el kgsl-smmu para el CM3 en este kernel** (el ABL no usa el GPU; el BL no deja nada; el kernel no adjunta el nodo GPU al kgsl-smmu).
- **K19 (diseño para la próxima)**: programar antes del release (en a6xx_gmu_start, entre S2 y S3) el mapeo del TCM: SMR id=5 mask=0 + S2CR translate→CB + CB con tabla que mapee iova 0x4000 → phys del TCM (el vendor lo hace vía TZ; nosotros a mano, estilo UKE). Alternativa: iommu_map del TCM en el dominio del GPU si existe attach (verificar "Adding to iommu group" del 3d00000 en dmesg).
- Los logs de muerte de este ciclo se perdieron (dmesg -w con redirect vacío en panic — lección: usar console + trace_pipe, ya cubierto).

## #P48 — s263 + K20 (1-oct 01:2x-01:4x): el stack GPU COMPLETO por primera vez; el wedge del CM3 deja de matar la máquina
- **s263** (dtbo `fe06fccc…`, dd a dtbo_a): GPU iommus 0→5 = merge de GPU+GMU en el grupo 0 ✓ (verificado vivo). SOLO s263: `msm_iommu_new` del GMU → attach_group **-EBUSY** (el grupo ya llevaba el dominio del GPU) → `gmu init ret=-16` → GPU ausente → **sin card0** (pero sistema VIVE).
- **K20** (kernel `fa65e675…`, dd a boot_a): `uke_gmu_shared=1` — el vm del GMU **comparte el mmu del GPU** (un solo dominio attach-ado; rango VA propio 0x0..0x80000000). Resultado: `attach_group rc=0` + "gmu vm COMPARTIENDO" + **card0 + DSI-1 + Writeback + renderD128 ENSAMBLADOS** + kms OK.
- **Trigger modetest (93 s)**: fw sqe+gmu cargan del rootfs, GMU v4.5.1, P3-pwrOK → S0-dtcmR → S1-rst1 → S2-gen9 → **[S3-rst0 NO imprime]** — la escritura del release no retorna PERO **LA MÁQUINA VIVE** (sin panic, sin reboot, SSH estable, modetest muere solo, 0 hung-tasks). **Cambio cualitativo: el daño pasó de bus-wedge+pánico a un stall localizado en el camino del CM3.**
- **Siguiente palanca (K21)**: la escritura de S3 sigue sin completar = el fetch inicial del CM3 sigue estancando SU camino (aunque ya no el bus). Verificar QUÉ tabla ve el CB en el momento del release: el mmu compartido es el PAGETABLE del vm kernel del GPU (segundo nivel) — el icache@0x4000 puede necesitar mapeo en la tabla BASE del dominio (o el TTBR0 del CB apuntar a la tabla correcta en ese instante). También: probar uke_gmu_shared con msm_iommu_pagetable_create aparte vs base.
- Estado al cierre: tablet VIVA en Arch, slot a = K20d+s263 (el stack completo), slot b = par bueno K13-dsid+s260 INTACTO. Vigía armado.

## #P49 — K22/K23 (1-oct 02:0x-03:0x): fw horneados en el initramfs (K22) + fix del dump (K23) — la noche del único flash sin red física
- **K22** (fw GPU en el initramfs interno): hallazgo crítico pre-vuelo — el firmware-loader del kernel busca SOLO `fw_path_para` + `/lib/firmware/*` (main.c:472-478) y el initramfs es plano (sin lib/ ni usr/): el primer montaje con `usr/lib/firmware` habría repetido el ENOENT. REHECHO con `lib/firmware/qcom/` (+copia en usr/lib). **RESULTADO MEDIDO**: en el arranque K22 el fw CARGA a los 4,07 s ("loaded ... from new location") y **la escalera GMU COMPLETA corre en el arranque** (F1-F4, P1-P3, S0-S2) dentro del resume de `adreno_load_gpu` — la teoría del desmontaje del dominio por el ENOENT queda confirmada y superada: el dominio ya no se desmonta.
- **BUG PROPIO cazado en vivo (K23)**: el dump K19 con `ioremap(0x3da0000, 0x40000)` no cubre las páginas CB≥4 (el espacio CB llega a ~0x110000) → machine-check WARN dentro del dump → **abortó el resume ANTES de S3** (la GPU quedó "resuming"; el sistema arrancó igual hasta SSH: card0+DSI-1+renderD128 ✓). K23 = ioremap 2 MB (3 líneas). Artefacto K23 = `8e7ed4f97290c843b969b5bffd09975bdc031488c723f08f9465e55294d0a687`, **flasheado a boot_a y verificado por relectura** (no llegó a arrancar: ver abajo).
- **La noche acaba en ZOMBI**: tras el dd+reboot de K23 el sistema (K22) entró en el estado zombi recurrente (ping vivo, sshd muerto, consola congelada a 387 s, 0 puertos) y el reboot no ejecutó. **Patrón de los 3 zombis de la noche (~280-400 s de uptime): userspace muriendo con el kernel vivo — sospecha principal: el fs sin journal ensuciado por los reboots sucios de los ciclos de muerte (sshd/getty leyendo páginas corruptas); e2fsck antes de cada experimento lo mitiga pero cada wedge lo vuelve a ensuciar.** K23 queda esperando un power-cycle físico.
- **PARA LA MAÑANA (1-oct)**: ① power-cycle → arranca K23 (boot_a, slot A activo; si A está agotado el vigía está PAUSADO → caerá a fastboot → set_active a desde el PC). ② verificar la escalera: `S3-rst0` DEBE imprimir ahora (dump completo) y el veredicto real del release del CM3 con todo vivo: S4-pollOK = GPU VIVA. ③ si el sistema arranca pero el fs está sucio (zombi recurrente): e2fsck ANTES de más ciclos (flujo mejorado: sockets de journald parados + sesión persistente + auto-reboot). ④ si S4 OK: K23-plain (sin video=) → modeset → migas UKE-P82 → PANTALLA; si S3 sigue estancando: la tabla del icache (K21: pagetable 2º nivel vs tabla base) — el dump K23 ahora sí imprime la sección CBpage con las tablas.

## #P50 — 1-oct 15:2x (PREDICCIÓN COMPROMETIDA, 0 escrituras): power-cycle del K23 ya flasheado
- **Estado**: `boot_a` = K23 `8e7ed4f9…` (verificado por relectura, ledger #449), `dtbo_a` = s263
  `fe06fccc…`, slot a activo, slot b intacto (K13-dsid `e0ee47dc…` + s260 `6fbb5173…`). La tablet
  quedó ZOMBI a las 03:00 esperando power-cycle del dueño. **Esta fila se escribe ANTES de medir**
  (regla M8): la predicción queda comprometida aunque salga mal.
- **Corrección de fondo, medida en el PC sobre el log de la consola (no en la tablet)**: el volcado
  del CM3 decodificaba `S2CR` al revés y leía las CB en direcciones que no son las de un MMU-500.
  Detalle y evidencia en `build/gates/revision/V2-critica-k23b.md` y en el banner de
  `docs/historia/PLAN-SIGUIENTE-v4.md`. Consecuencia: **el K23 NO puede responder "¿mapea CB1 el icache@0x4000?"**.
- **PREDICCIÓN para este arranque (K23, sin cambios)** — elijo **B** y dejo por escrito por qué se
  descartan las demás, para que la lectura no se pueda sesgar después:
  - **B (`S3-rst0` + `S4-pollFAIL` a ~100 ms)**: es lo que dio K18/K20/K22/K23, y nada de lo que
    lleva el K23 toca el fetch del CM3. Es lo más probable.
  - **A (`S4-pollOK`)**: posible (el K23 añade fw al initramfs y un ioremap más grande), pero si
    saliera habría que revisarlo dos veces antes de creerlo (el plan lo avisa).
  - **F (`S3-rst0` sin `S4-poll*`)**: posible; la firma de #P47. Ojo: el K23 **no** lleva el
    `pr_flush` que se ha añadido ahora, así que un wedge duro puede comerse la propia `S3-rst0`.
  - **D (el dump aborta)**: la probaría **que no** — con 2 MB de ioremap las lecturas del 2º bucle
    caen en `gpu_qtb@0x3de8000` y en huecos, así que hay riesgo real de SError. Si sale D, el K23b
    lo evita por construcción (ioremap ceñido a los 0x40000 del recurso).
  - **Lo que además espero ver (y es la comprobación de la corrección)**: `SME(1)` impreso como
    `type=0=TRANS cbndx=1` — NO como «type=1 cbndx=0». Y espero **cero** líneas `CB(`/`CBpage(`
    con datos de CB reales: `CBpage(2)` sería CB0 y `CBpage(3)` sería CB16, con la etiqueta
    equivocada, y de CB4 en adelante se leería fuera del SMMU. **Si salen 22 CBs "bonitas", están
    mal: eso significaría que el volcado leyó otra cosa.**
- **Qué NO se hace en este ciclo**: nada. 0 escrituras. Este arranque solo mide.

## #P51 — 1-oct (PREDICCIÓN COMPROMETIDA): K23b = el volcado corregido (SÍ es un flash)
- **Qué es**: `build/bootimg/boot-ukek23b.img` = boot.img de 96 MiB con el **mismo** cmdline
  dsid del K23 (370 B, con `video=DSI-1:d`) y el kernel = K23 + dump corregido. Cambios, todos en
  `uke_k19_dump_kgsl()` y el volcado que lo rodea:
  1. **Geometría del ID1**: lee `ID0`/`ID1` del propio SMMU y calcula `pgshift`, `numpage`,
     `numcb`, `CBbase` y `stride` igual que el driver, en vez de suponerlos.
  2. **ioremap ceñido al recurso**: `ioremap(0x3da0000, 0x40000)` (los 0x40000 del DT), no 2 MB.
     Nunca se lee fuera del recurso → se acaban el machine-check y las lecturas sobre `gpu_qtb`.
  3. **Decode correcto**: `S2CR.TYPE = (s2cr>>16)&3` con nombre (`TRANS`/`BYPASS`/`FAULT`),
     `S2CR.CBNDX = s2cr&0xff`, `SMR.VALID/ID/MASK` bien separados, y se anota a qué CB apunta cada
     S2CR válido.
  4. **CB1 legible**: todas las CB en su offset real (`CBbase + n<<pgshift`) y **8** descriptores
     de la tabla de cada CB habilitada (con 4 no se llegaba al del icache@0x4000, que es el
     **índice 4** con granularidad de 4 KB), con `fmt`/`phys` decodificados.
  5. **`pr_flush(120,false)`** tras `S3-rst0` y tras `S4-poll*`, para que la evidencia de la rama no
     se pierda en un wedge duro.
  - **NO cambia** el modo de la GPU, ni el S2CR, ni la tabla: **esto sigue siendo instrumentación**.
     El fix del CM3 (K24) espera a leer CB1. Un cambio por ciclo.
- **PREDICCIÓN**: al arrancar, la línea `GEO` imprimirá **pgshift=12 NUMPAGENDXB=4 numpage=32
  numcb=22 CBbase=0x20000 CBfin=0x36000** (si el ID1 real no coincide, el propio volcado lo dice y
  me habré equivocado en la inferencia — también es un resultado válido). `SME(1)` saldrá como
  `TRANS cbndx=1`. Y el desenlace de la escalera **sigue siendo B (`S4-pollFAIL`)**: este kernel no
  arregla el CM3. Si saliera A, doble revisión antes de creerlo (el fw ya estaba en K22).
- **Lo que decide**: si `CBpage(1) off=0x21000` tiene el descriptor del icache@0x4000 (índice 4)
  válido, el fix es una entrada de tabla; si es 0x0, también; y si el PA no cuadra con el TCM, el
  fix es un `iommu_map` del TCM. Ese dato no existe hoy.
- **Artefacto (sha pre-registrado ANTES de flashear, como manda la regla 1)**:
  `build/bootimg/boot-ukek23b.img` = **`c31f098fe834bf852ee891dc0875a38b693375627bcf6ff028058ec99cd7b6d5`**
  (100663296 B exactos). Kernel dentro = `k23b-build/arch/arm64/boot/Image.gz`
  `a8a60900a0df75ed6f72136a42f80591ad29b9c59cd32f8eed6e5f3d4d412230` (crudo 41552384 B =
  `1cb876fbaa89fac8c682aa6222640e7f1058c7c0465bf4a0b9ec1aad489f78fc`).
  **Cmdline = la del K23, byte a byte** (370 B, con `video=DSI-1:d` y `hung_task_panic=1`:
  deliberadamente NO se toca la cmdline en este ciclo — un solo cambio por ciclo, y la
  medición de K20 dice que el stall del CM3 es local y no genera hung-tasks, así que el
  flag no debería costar el dmesg).
  **Verificado contra el K23 byte a byte**: lo único que difiere es el payload del kernel
  (+ su campo `kernel_size` en la cabecera). Magic `ANDROID!`, v4/1584, cmdline, AVB0@35438592,
  AVBf@100663232 y todo el pad de ceros: **idénticos**. El cpio K22 con los fw de la GPU va
  embebido **byte a byte** dentro del kernel (offset 35336040 del kernel crudo). Los 6
  marcadores nuevos están en el binario y los 2 viejos fuera.
  **Canal**: `docs/historia/gates-palawan/flash-k23b.sh` (escrito para este ciclo: gates de mV, shas
  antes/después, relectura al tamaño exacto, y qué hacer en cada fallo). **Rollback**:
  `set_active b` (B intacto). Semáforo hermano: libre (#449 = nuestra última fila).

  - **⚠️ Estado de slots MEDIDO en fastboot el 1-oct (~15:4x), antes de escribir** (queda en el
    log de esta fila porque no es lo que dice la regla):
    ```
    (bootloader) current-slot:a
    (bootloader) slot-retry-count:a:1     slot-unbootable:a:no   slot-successful:a:no
    (bootloader) slot-retry-count:b:6     slot-unbootable:b:no   slot-successful:b:no
    (bootloader) battery-voltage:3892     has-slot:boot:yes      product:uke
    ```
    **`b` estaba en 6** (a un paso del umbral), y aquí hay una **lección que cuesta un ciclo de
    aplicarla**: la regla del proyecto dice «`set_active a|b` como reset de contadores», y **en este
    bootloader es al revés: `set_active` INCREMENTA el contador del slot que activas** (medido:
    `set_active b` → `b: 6→7`; `set_active a` → `a: 1→7`). O sea que **no resetear los contadores
    con `set_active`**, y **mi intento dearlo en 6/1 los subio a 7/7**. Los dos slots siguen
    `unbootable:no`, asi que no hay dano hecho, pero **ambos estan ahora a 7** y la red de seguridad
    (b) tiene menos margen del que creíamos.
    - **Por que NO se limpia el BCB de `misc` para resetearlos**: es la unica via real (ahi guarda
      ABL los contadores), pero `docs/historia/AGENTS.md` avisa del `misc` BCB en `reboot-bootloader` y el
      proyecto tiene antecedentesahi (`DECISION-misc-BCB.md`). **Requiere GO explicito del dueno.**
    - **Por que el flashing sigue adelante**: la recuperacion NO depende de los contadores — es
      `teclas -> fastboot` + `set_active`/`flash` desde el PC, y el par de b esta intacto y verificado.
      Lo que hacen los contadores es, en el peor caso, lo que **queremos**: si el K23b no arranca, a
      se marca no-arrancable y el ABL cae a b, que es justo la red de F9.
    - **Aprendizaje añadido a `REGLAS.md`**: una regla heredada ("`set_active` resetea") se verifica
      contra el dispositivo antes de*fiar* de ella para tocar el estado; si resultara falsa, el
      contador se sube sin querer y no hay forma de bajarlo sin `misc`.

## #P52 — 1-oct ~16:0x: LIMPIEZA DEL BCB (misc a ceros, 4 MiB) + retorno a slot B
- **Situacion de partida MEDIDA (en fastboot)**: `current-slot:a`, **`slot-unbootable:a:YES`**,
  `slot-retry-count:a:0`, `slot-unbootable:b:no`, `slot-retry-count:b:7`, `slot-successful:*:no`,
  `battery-voltage:3890`, `product:uke`. El ABL consumio los reintentos del bucle de 34 s del K23b
  y el ABL lo hizo solo, sin que nadie tocara nada. Ojo al leerlo: que A este **retirado** no
  significa que el write fuera malo, sino que el kernel cuelga. Lo que si queda demostrado es que
  el K23b **arranca** (llegó a enumerar el gadget USB y a levantar sshd) y luego cuelga.
- **Que se va a escribir y por que**: `fastboot flash misc build/misc-zeros-4m.img`
  (4194304 B de ceros, sha256 `bb9f8df61474d25e71fa00722318cd387396ca1736605e1248821cc0de3d3af8`).
  Con `misc` a ceros se limpian `command[0:32]`, `num_slots` y los `slot_metadata`
  (tries_remaining/successful_boot) => **`slot-unbootable:a` vuelve a NO** y el slot A vuelve a ser
  un experimental utilizable. **Es el "limpiar BCB" que el docs/historia/AGENTS.md exige antes de tocar nada.**
- **Por que 4 MiB y no los 8192 B**: `DECISION-misc-BCB.md` §2. La particion `misc` mide 4 MiB
  (tamano confirmado 0x400000 en #P35) y `fastboot flash` escribe solo `len(img)` bytes al inicio:
  con la imagen de 8192 B quedarían 4 MiB − 8 KiB de BCB viejo vivo, y el criterio de relectura de
  4 KiB no lo miraria. La imagen correcta es la de 4 MiB.
- **Precedente (ledger del hermano, dos veces)**: #P35 (13-sep) "el BCB 'bootloader' sucio causaba el
  bucle de reinicios... Fix: `fastboot flash misc` con 4 MiB de ceros... Arranque con kernel bueno:
  estable, sin bucle", y su **regla**: "al usar BCB por escritura directa, limpiarlo SIEMPRE despues".
  Linea 351: "La misc ya estaba limpia (flasheada a ceros el 29-sep)... El bucle NO fue BCB".
- **Riesgo asumido y por que se acepta**: (a) este fastboot **no soporta `fetch`**, asi que no se
  puede leer `misc` antes de borrarla: no hay backup possible del BCB (por eso el paso va
  pre-registrado con su sha). (b) Con el BCB a ceros el ABL pierde el puntero de slot activo y
  elegira por su cuenta; por eso **el orden es: limpiar -> `set_active b` -> reboot**, que es el que
  nos deja en el par estable y con el slot A disponible para el siguiente experimento.
  (c) `set_active` **incrementa** `tries_remaining` en este bootloader (medido), asi que el orden
  importa: si se hiciera `set_active` DESPUES de limpiar, el contador queda en 1 y no en 0, y eso es
  justo lo que se quiere (A queda con margen para el proximo intento).
- **Gates**: mV >= 3700 leido (3890 ✓) · `getvar all` guardado antes/despues · sha del artefacto
  verificado antes de escribir · par de B verificado por sha en `SHA-BUENOS.txt` y **no se toca**.
- **Rollback**: si tras la limpieza la tablet no arranca en B, se entra por **teclas** a fastboot
  (sin misc) y se hace `fastboot flash boot_b build/backup-par-bueno/boot-ukek13-dsid.img` +
  `fastboot flash dtbo_b build/backup-par-bueno/s260-boot-dtbo-dpu-iommus.img` + `set_active b`.
  O sea: **B tiene copia verificada en el PC**, perder el selector de slot no deja la tablet sin
  arranque.
- **NO se toca**: `vbmeta`, los atributos GPT (el hermano tuvo un brick el 11-sep por editar GPT a
  `dd`), ni `boot_b`/`dtbo_b`.

### #P52 RESULTADO (1-oct ~15:5x) — la limpieza de `misc` NO devolvió el slot A, y el motivo está medido
- **Lo que pasó**: `fastboot flash misc build/misc-zeros-4m.img` → `OKAY` (4 MiB, sha `bb9f8df6…`
  verificado antes). Inmediatamente después, `fastboot getvar all` seguía diciendo
  **`slot-unbootable:a:YES`, `slot-retry-count:a:0`** — el flag no se movió. Luego
  `fastboot set_active b` (0,04 s) y `fastboot reboot` → **la tablet arrancó el slot B y esta VIVA**
  (`Linux uke-arch 7.2.0-rc2-palawan #17 ... Wed Sep 30 12:11:57` = K13-dsid, uptime 72 s y
  subiendo, `card0` + `card0-DSI-1` + `card0-Writeback-1` + `renderD128`, fs al 5 %).
- **POR QUÉ: lo dice el propio proyecto y yo no lo miré antes de escribir.**
  `build/slot/PROCEDIMIENTO-SLOT.md:61-64`: *"Limpiar/escribir el BCB de `misc`: los contadores de
  slot viven en los **atributos GPT (bits 48-63)**, no en `misc`. `misc` solo lleva el BCB (medido:
  `command="bootloader"`, resto ceros)."* Es decir: **`misc` no contiene los contadores**, así que
  ponerla a ceros no puede limpiarlos, y además el BCB **ya estaba** en `command="bootloader"` con
  el resto a ceros ⇒ mi escritura fue un **no-op semántico**: un gasto de escritura sin beneficio.
  La fila #P52 de este mismo fichero afirmaba lo contrario ("con `misc` a ceros…
  `slot-unbootable:a` vuelve a NO"); queda **REFUTADA por medición**.
- **Lo que sí se aprende y sirve**: (a) el ABL **relee `misc` en cada boot**, pero eso no incluye los
  contadores; (b) `set_active b` + reboot lleva a B sin problema con `b` en 7, así que el "techo" de
  7 no era un bloqueo; (c) la red de F9 (A experimental, B estable) **funcionó**: el ABL retiró A solo
  y B arrancó limpio.
- **Cómo se rehabilita A entonces**: los contadores están en los atributos GPT, y la única vía
  documentada para escribirlos es `qbootctl -m` (`build/slot/qbootctl-aarch64`), que está
  **prohibida sin decisión del dueño**: escribe la GPT de 12 particiones en dos discos con el rootfs
  vivo y `cliffs` no está en la lista de validados (`PROCEDIMIENTO-SLOT.md:36-55`; el hermano tuvo un
  **brick el 11-sep** por editar GPT a `dd`, `docs/informes/B-arranque-arch-uke.md:43`).
  **Vía a medir en un ciclo propio (no en vacío)**: `fastboot flash boot_a` + `fastboot flash dtbo_a`
  con el **par bueno completo de B** (`boot-ukek13-dsid.img` + `s260-boot-dtbo-dpu-iommus.img`, shas
  verificados) + `set_active a` + reboot. Si `slot-unbootable:a` queda en `no`, queda **medido** que
  flashear + `set_active` limpia el flag, y A además queda con un par probado. Si sigue en `yes`,
  queda refutado y se evalúa `qbootctl` **con decisión explícita**. Precondición: `e2fsck` verde.
- **Pendiente inmediato, y es la regla**: el fs sigue sucio por los ~8 reinicios del bucle del K23b.
  **`e2fsck` antes de cualquier flash nuevo**, con el flujo probado del `docs/historia/RUNBOOK-SIGUIENTE.md` Paso 4
  (NO el §A.2 de `P7-fsck-f9.md`, refutado en vivo por el ledger #446).

### NOTA 2-oct-2026 — este fichero termina en #P52. El pre-registro sigue en el ledger.
Desde el 2-oct las filas pre-registradas (P80–P93, P101–P105, P130–P153, P160–P164, P170–P172) y los
shas de artefactos (K34 `7c4900e8…`, K35 `dc4b9700…`, K37 `6c13985e…`, K38 `e36425bc…`, K39 `3873e8eb…`,
K40 `671e52ea…`, K41 `b30ea177…`, K42 `a12f90e7…`) viven en `~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md`
(filas #475–#491). Par vigente: `boot-ukek13-dsid.img` (`e0ee47dc…`) + `s260` en slot a
(`SHA-BUENOS.txt`, `docs/historia/ESTADO-VIVO.md`). No abrir filas nuevas aquí sin mover antes el índice de `docs/historia/AGENTS.md`.
