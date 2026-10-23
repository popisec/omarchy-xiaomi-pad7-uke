# PLAN PANEL-WEDGE — protocolo E0→E1→E3 (11-oct-2026)

> Fuente: informe del investigador del wedge (2º relanzamiento, cerrado 11-oct, agente
> general-purpose). Pre-registro del artefacto E1 en el ledger del hermano (**#594**).
> Estado del aparato al escribir esto: tablet APAGADA (batería); par vigente
> L19 `71d89ca6…` + s275-r2 `67a65bc1…` en slot a.

## 0. Lo que cambió con el informe (hallazgos que ordenan el plan)

1. **Android nunca ejecuta el encendido en frío en el kernel.** La captura golden
   (`android-full/extracted-full/15-common/dmesg-full.txt`) empieza en t=5,75 s con el
   panel YA encendido (`power_status value: 1`): el ABL hereda el panel (cont_splash) y
   el kernel nunca corre power_on→reset→init-DCS. **El port ha wedged 3 veces en un
   camino que en Android corre el bootloader.** No hay secuencia golden del kernel que
   copiar — el enable del port es territorio nuevo.
2. **Los parámetros vendor del panel son IGUALES en el port** (verificado contra el DT
   vivo Android): rieles (vddil8b 1900 mV ≈ 1896, vsp/vsn 5800 mV, enable-load 300 mA,
   post-on-sleep 2 ms), pinctrl gpio2 active/suspend, reset `<0 10 1 3 0 3 1 15>`.
   **El rail L8 quedó definitivamente exonerado** (#591: en spec y wedgea igual).
3. **Descartados con medida**: la 4ª escritura GPIO2 (#508: `w4-done` impreso, muerte a
   +74,9 ms — el boot del MCU TDDI completa y ACTÚA), SMMU silenciado (el token
   `uke_smmu_probe=1` está PROHIBIDO en L19P; el SMR 0x1c00/2 llegó al HW), gpio_key.
4. **Mecanismo nº1 (vivo)**: el evento del boot del TDDI a +75 ms (MCU Novatek despierta
   su parte táctil/ESD y actúa sobre los pines 168/169). Sub-sospechoso: **vsp/vsn son
   reguladores por GPIO 74/75 gestionados por el AOP en Android** (`proxy-supply`/
   `proxy-consumer-enable` en `display_gpio_regulator@0`); el port los conmuta crudos
   (frags 156/157) — un fallo de rail visto por el AOP/RPMh mata el SoC en silencio con
   WDT-reboot (mismo perfil que el wedge del CM3 del GMU).
5. **Mecanismo nº2 (abierto)**: fault IOMMU real en el primer fetch — solo si la muerte
   es POST-reset (punto sin capturar).

## 1. E0 — cosecha sin flashear (PRIMERA COSA al tener SSH)

El testigo UFS (`uke-ufs-witness.sh`) puede haber quedado armado en los boots de
#590/#591. La traza pre-muerte estaría YA en flash:

```bash
ssh root@192.168.42.129
ls -la /root/witness/ 2>/dev/null && tail -80 /root/witness/dmesg.prev.log
```

Qué buscar en las últimas ~20 líneas antes del hueco (firmas del informe):
- última miga K48: `K48-w4-done` vs `K47-pre-init` vs `cmd#N`; ¿hay líneas ENTRE la miga y la muerte?
- `K49-esd-irq` (la IRQ del TDDI ya está cableada desde K49)
- `arm-smmu ... fault` (global/context), errores sde/dsi (`cmd dma tx failed`, `PLL lock`,
  `video done timed out`), `-131/-16` del L8, spam de IRQ (nvt-ts), y la firma de reloj del
  reboot del WDT.
- Si NO estaba armado: armarlo ya (`/root/uke-ufs-witness.sh arm`) para el resto del protocolo.

## 2. Disparador 0-flash — repro deliberada sobre el par vigente (sin tocar slots)

El par L19+s275-r2 tiene card1-DSI-1 nacida con panel force-off (`:d`). El enable se
dispara POR SSH con captura completa armada:

```bash
# 1) armar la captura (en el PC, consolas separadas):
out/acm-loop.sh                        # lector ACM que reabre en la re-enumeración
# 2) en la tablet:
/root/uke-ufs-witness.sh arm           # dmesg+ftrace → UFS, sync 0,2 s
/root/uke-wedge-sampler.sh arm         # E3: rieles + TLMM + IRQs (25 Hz, sync 0,5 s)
dmesg -n 7
# 3) EL DISPARADOR (el enable deliberado):
echo on > /sys/class/drm/card1-DSI-1/status
#    (alternativa si status no dispara enable real:)
#    modetest -D /dev/dri/card1 -s "$(cat /root/conn.txt):3200x2136@XR24"   # conector de card1
# 4) si sobrevive 60 s: foto + `uke-wedge-sampler.sh stop` + cerrar testigo.
```

- **Muere igual** (con SSH vivo hasta el stall): la muerte está en la secuencia del enable
  Y el dmesg+sampler de UFS dan la firma → analizar con la checklist del §1.
- **Sobrevive**: el asesino necesita el CONTEXTO del arranque (timing/orden) → E1 (§3)
  separa enable-vs-boot con el modeset bajo control total.

## 3. E1 — flash del kernel estable-por-diseño (el artefacto pre-registrado)

**Artefacto #594**: `build/bootimg/boot-uke-k52L19E1.img` (100663296 B)
sha256 `ca8cd4bd3304b738fa2f9453bb382eb2c0974791f7ac4b7a68d353c2185eab57`
(cmdline 553 B = k64 sin `video=DSI-1:d` ni `console=tty0`; kernel byte-pinneado al de
L19P/L19 flasheados `5582dcc2…`; repack-k52L19E1.py G0-G8 verdes).

```bash
# ventana fastboot:
fastboot flash boot_a build/bootimg/boot-uke-k52L19E1.img
# dtbo NO se toca (s275-r2 sigue)
fastboot reboot
```

Al arrancar: SSH vivo, **pantalla probablemente muerta pero NADIE toca el panel**. Entonces
repetir el §2 completo (armar capturas → `echo on > status` o `modetest`). Esto separa:

| Resultado | Conclusión |
|---|---|
| Wedgea en el enable manual | La muerte está DENTRO de la secuencia del enable, con dmesg completo y sampler sincronizado hasta el stall (lo que #590/#591 nunca dieron) |
| Sobrevive el enable manual | El asesino necesita el contexto del arranque (orden host-phy/reset del informe; siguiente = E2 `uke_dsi_host_late`) |

**Rollback**: L19 `71d89ca6…` + s275-r2 `67a65bc1…` (boot_a solamete; dtbo sin tocar).

## 4. E3 — el sampler (ya escrito, sin tablet)

`build/gates/uke-wedge-sampler.sh` — rieles L8/vsp/vsn + GPIO 2/74/75/168/169 + IRQs a
`/root/witness/wedge/` a 25 Hz con sync 0,5 s. Dice **si 168/169 aseveran justo antes de
morir** (mecanismo nº1) y **si un rail cae** (sub-sospechoso AOP). Copiarlo a la tablet en
la primera sesión SSH (`scp build/gates/uke-wedge-sampler.sh root@192.168.42.129:/root/`).

## 5. Qué NO hacer (reglas del informe)

- NO flashear s277 (#592) ni L20 (#593) antes de cerrar el panel con E0/0-flash/E1:
  contaminarían el experimento (una variable por ciclo).
- NO reintentar `video=DSI-1:d` quitado ni console=tty0 en E1: son EL experimento.
- El enable manual es la repro: si muere, muere con captura — no es un fallo del protocolo.

## 6. Después del panel (recuerdo del orden vigente)

Escritorio (~217/473, lotes `--needed`) · WiFi P2 (`echo start` al wpss, discriminador
7,33 s) · #592 s277 + #593 L20 cuando F1b esté cerrado · BT (CONFIG_SERIAL_QCOM_GENI) y
stylus después.
