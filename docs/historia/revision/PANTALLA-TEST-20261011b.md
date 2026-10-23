# PANTALLA-TEST-20261011b — repro deliberada del wedge del panel o82 (con captura completa)

**Resultado: WEDGE REPRODUCIDO (5ª vez, firma idéntica) — CAPTURA COMPLETA CONSEGUIDA.**
La tablet murió y el WDT la trajo de vuelta solo (~≤40 s). Evidencia cosechada:
`build/evidencia/pantalla-20261011b/` (dmesg.log 1,6 MB con testigo UFS + `wedge/` del
sampler E3 + `acm-pantalla-20261011b.log` del PC).

## 1. Preparación

- SSH vivo (kernel L19 `7.2.0-rc2-palawan`, rootfs k521). `/root/` NO tenía testigos
  (rootfs del 5-oct): scp de `uke-wedge-sampler.sh` y `uke-ufs-witness.sh` → /root/, chmod +x.
- Ambos armados y verificados: witness 3 loops (dmesg.log creciendo, sync 0,2 s) y sampler
  4 loops (pids 1047/1048/1050/1052 vivos; rails.log y tlmm.log a ~25 Hz, irq.count 3034→3080 en 2 s).
- `dmesg -n 7`. Estado pre-disparo: card1-DSI-1 `disconnected`/`disabled` (base verde),
  lsmod vacío, ts 1790296277600. Baseline sampler: vsp/vsn 5.800.000 µV `disabled`,
  L8 1.304.000 µV `unknown`; g2 out-low, g74/75 out-low, g168/169 in-high (pull-down).
- **modetest descartado como disparador**: está instalado (`/usr/bin/modetest`), pero el
  conector DSI-1 (id 36) nace `disconnected` con **0 modos** — un `modetest -s` no puede
  hacer enable real sobre él (y `-D ruta` no abre por busid en esta build; solo posicional).
  Se usó el disparador ALTERNO documentado del plan §2/#595: `echo on > status`.

## 2. Disparo y muerte

- Captura ACM armada en el PC (`acm-loop.sh /tmp/acm-pantalla-20261011b.log`, pid 1542332).
- TRIGGER marcado en /root/witness/dmesg.log (wall 1790296456284) e inmediatamente
  `echo on > /sys/class/drm/card1-DSI-1/status`. El canal SSH colgó al instante (rc=124
  a los 30 s sin devolver ni un byte). Sondeo: a +40 s SSH de vuelta con **uptime 0 min**
  → reinicio (WDT/PMIC) sin intervención. Nunca hizo falta power-cycle.

## 3. Análisis del tramo pre-muerte (lo que #590/#591 nunca dieron)

Secuencia completa en dmesg.log (líneas 19790-19839, kmsg t=712.032→712.1139):

```
712.032  K47-pan-modes (fbcon detect tras el force+hotplug; get_modes ×2)
712.038  K47-enc-mset / K47-mgr-mset / K47-crtc-en / K47-phy-en / K47-7nm-en (×2, dual-DSI)
712.043  K47-host-pwr / K47-pll-prep / K47-host-en / K47-pan-prep
712.086  P82 power_on: vddil8b → vsp → vsn ENABLED, TODAS OK
712.096  K48-rst-A (assert 10ms) → w1-done → K48-rst-A-ok
712.106  release OK (w2-done); K49: ESD IRQs registradas
712.107  **ESD irq 86 (gpio168) val=0 y ESD irq 87 (gpio169) val=0 — DURANTE el assert**
712.110  rst release OK (w3-done) → assert2(3ms) OK (K48-rst-A2-ok)
712.1139 K48-w4-done   ← ÚLTIMA LÍNEA. Muerte ≤ ~20-100 ms después. NULs (corte a mitad de página)
```

Hallazgos medidos ( sampler `wedge/`):

- **Rieles: NINGUNO cayó.** Última muestra sincronizada (t≈712.13, +100 ms tras TRIGGER):
  `vsp=5800000:enabled vsn=5800000:enabled l8=1304000:enabled` — los tres a nominal y
  enabled justo antes de morir. El sub-sospechoso AOP/rail (vsp/vsn conmutados crudos)
  **no muestra colapso de rail a nivel regulador**.
- **TLMM: g168/g169 cayeron a LOW** (de in-high a in-low en la última muestra; único cambio
  en las 7.391 líneas del log). g74/g75 HIGH (enable de vsp/vsn asertado). g2 leyó HIGH en
  esa última muestra ~16 ms tras el assert2 (que lo puso LOW) — muestra única a 25 Hz con
  sync 0,5 s: o carrera con la muerte, o el reset ya no conducía; queda como observación
  abierta, no como conclusión.
- **IRQs**: irq.now final (snapshot atómico pre-muerte): `86 ×1 (gpio168 uke-o82-esd)`,
  `87 ×2 (gpio169 uke-o82-esd)`, touch 188 ×0. El irq-full-7760 (1,6 s antes) ya tenía 87 ×1.
  **El TDDI aserta sus dos líneas de ESD/INT durante el reset** — mecanismo nº1 del plan
  (boot del MCU TDDI que actúa sobre 168/169) confirmado EN VIVO otra vez.
- **Consola ACM**: última línea impresa `K47-pan-modes` (712.032); el kmsg siguió hasta
  712.1139 → el modeset tomó console_lock y todo printk posterior quedó en cola; ni panic,
  ni Oops, ni watchdog jamás impresos. Muerte silenciosa también a nivel consola.
- **Cero evidencia del mecanismo nº2**: ningún `arm-smmu ... fault`, ningún error sde/dsi,
  ningún `-131/-16` del L8 en todo el tramo pre-muerte (solo spam devfreq/UNIPRO preexistente).
- **pureason del boot siguiente: `0x80110`, pdreason 0x2** — distinto de TODOS los boots
  previos registrados en evidencia (`0x800001` ×8, `0x800011` ×3). Perfil de reset anómalo,
  coherente con el perfil WDT-reboot del wedge del CM3 (semántica de bits sin decodificar).
- Post-reboot: card1-DSI-1 de nuevo `disconnected/disabled` (video=DSI-1:d intacto); ruido
  menor nuevo: `spi_master spi0: noqueue transfer failed` en t=5,4/6,6 s del boot nuevo.

## 4. Conclusión y siguiente paso

- F1B SIGUE ABIERTO: el panel nunca llegó a tener imagen (muerte determinista en el mismo
  punto: tras rieles OK y la 4ª escritura GPIO, con ESD 86/87 asertando en el assert).
- Siguiente paso recomendado (barato, 0-flash): **falsificar el mecanismo nº1** — repetir el
  enable con las IRQs ESD 86/87 **enmascaradas antes del reset** (el registro K49 ocurre
  dentro de prepare; enmascararlas por sysfs/IRQ antes de escribir `status` evita que el
  handler corra). Si sobrevive → el asesino viaja por la vía de la IRQ. Si muere igual →
  el TDDI actúa eléctricamente sobre los pines y toca pasar a E1/E2 (flash del artefacto
  #594 `boot-uke-k52L19E1.img` con enable bajo control total, per plan §3).
- La tablet está viva, SSH OK, sin testigos armados (los loops murieron con el reboot);
  acm-loop del PC parado. El dueño puede mirar la pantalla física: debería estar negra
  (force-off de nuevo); la ventana de enable duró ~80 ms.
