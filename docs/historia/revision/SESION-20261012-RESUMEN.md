# SESIÓN 12-oct (madrugada) — BASE RECUPERADA + PANTALLA HEREDADA: crónica y estado

> Resumen ejecutivo para el dueño. Todo lo que sigue está en el ledger (#604–#612) y en
> los informes de `build/gates/revision/`. Última acción: reflashear L19 base (02:54) para
> volver al arranque estable — la tablet quedó sola esperando ese boot.

## 1. Lo que se ganó esta noche (los 3 grandes)

1. **El aparato está SANO** (#604/#605): tras el wipe total que ordenaste, el k52b2 arrancó
   limpio. El congelamiento de la tarde NUNCA fue hardware ni batería.
2. **El rootfs era el asesino de la tarde** (#606/#607): la imagen k521 (v8, 4 GiB) se
   flashea por fastboot en 33 s y da SSH en 70 s. Con ella, el **L19 arrancó en 80 s y
   `eglinfo` dice freedreno FD735 + GLES 3.2** — F1a verificado en la base nueva.
3. **El escritorio está COMPLETO y verificado** (#609): 510 paquetes (473 del stage + deps),
   hyprland 0.56.2, quickshell, sddm y NetworkManager **enabled**, omarchy 4.0.4-2 con
   dotfiles. 679 MB libres. F6 = un reboot con pantalla de distancia.

## 2. La pantalla: la cadena de descubrimientos

| Paso | Descubrimiento |
|---|---|
| Tu observación física | El panel **SÍ enciende**: splash del ABL + líneas de log visibles → luego se apaga. El panel funciona; lo mata el kernel al tocarlo. |
| Estrategia invertida | Heredar el panel vivo (estilo cont_splash de Android) en vez de re-inicializarlo. |
| L22 (agente) | Hunk `msm.uke_panel_inherit=1`: probe del panel sin rieles/reset/init-DCS + DPU saltando vbif/encoders. Resultado: **pantalla ENCENDIDA (negro con backlight)** — el panel heredado sobrevive. |
| Tu timing | El apagón de la IMAGEN es "en los primeros segundos" → no era el DPU (4,1 s). |
| L22b (crítico + build) | El asesino real en el código: **`msm_mdss_reset()`** — reset duro de 20 ms del display core a ~0,4-0,5 s, antes del panel. L22b lo salta (y el vbif de hw_init, el clk_bulk y las PLLs del dispcc). |
| Test L22b | **NO llegó a probarse visualmente**: el boot L22b aborta en ~1 s (log → blanco → negro → reboot). Causa sin diagnosticar: los gates nuevos dejan el display en un estado que cuelga el arranque, o cascó antes del lector ACM (0 bytes capturados). |

## 3. Estado de salida (02:54)

- **boot_a = L19** (`71d89ca6…`, el estable) reflasheado y reboot en marcha — la tablet
  debería volver al estado verde de la base oficial (SSH + freedreno) cuando arranque.
- dtbo_a = s275-r2 (sin tocar). rootfs k521 con **escritorio completo** (intacto).
- El árbol k52-L16-tree lleva los hunks L22+L22b aplicados (compilan: build DONE).
- Artefactos listos: `boot-uke-k52L22.img` L22 original (`59445d2e…`, probado: pantalla
  encendida-negro) y L22b (`3ba47abd…`, pre-registrado #612, sin probar visualmente).

## 4. El siguiente ciclo (cuando retomes)

1. **Arrancar el L19 base y verificar los 6 criterios** (SSH+uptime, freedreno, 0 EXT4
   errors, carga, 1 enumeración, sin ABRT de pid1). [en marcha al escribir esto]
2. **Depurar el L22b con consola**: el reboot a ~1 s dejó de firmarse en el ACM (lector
   0 bytes — revisar por qué el acm-loop no capturó; quizá el init abortó antes de montar
   el gadget USB). Candidato: al saltar msm_mdss_reset/clk_bulk, algún subsistema (uart
   del ACM, UFS) dependiente del display-clocks falla. Opción pragmática: gatear L22b
   SOLO para msm_mdss_reset (sin clk_bulk ni dispcc) — aislar cuál de los 4 gates mata.
3. **Con el gate correcto**: panel heredado vivo de verdad → fase 2 (modeset propio sobre
   el panel heredado, documentada en docs/historia/revision/PANEL-INHERIT-20261012.md).
4. Luego: SDDM (F6), WiFi (nmcli), y el rootfs de 106 GB solo usa 4 GiB → resize2fs.

## 5. Lecciones del día (las que cambian el proceso)

- **El wipe + k521 + fastboot es la vía de recuperación**: 40 min de cero a base verde.
- **Un wedge = umount sucio = rootfs cada vez peor**: la regla e2fsck era imposible (los
  boot.img llevaban cpio sin e2fsck) — o se añade e2fsck al initramfs o cada wedge cuesta.
- **La pantalla física del dueño es un instrumento de medición**: el timing "primeros
  segundos" reordenó el ranking de sospechosos más que cualquier log.
- **Una variable por ciclo** — los bisect de la tarde con 3 deltas a la vez midieron ruido.
