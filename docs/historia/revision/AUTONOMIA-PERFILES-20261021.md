# Autonomía estimada y qué consume más (21-oct-2026, hecha en el PC sin la tablet)

Base: batería 38,27 Wh (UPower `energy-full`, 19-oct; 8811 mAh) y las medidas de `CONSUMO-DESGLOSE-20261020.md`
(entrada USB constante ⇒ deltas fiables ±0,07–0,13 W; el absoluto tiene incertidumbre abierta). Uso útil 90 % (95 → 5 %).
**No hay medida de uso real** (vídeo, navegador, juegos), de Bluetooth ni de suspensión: lo que sigue es un modelo de reposo.

## Autonomía por situación
| Situación (medida 20-oct) | W | autonomía (90 % útil = 34.4 Wh) |
|---|---|---|
| Reposo, pantalla apagada (DPMS off), WiFi+BT+Tailscale | 1.39 | 24.8 h |
| Pantalla 5 % (102/2047) a 60 Hz | 2.43 | 14.2 h |
| Pantalla 25 % a 60 Hz (2,43 + 0,94) | 3.37 | 10.2 h |
| Pantalla 50 % a 60 Hz (medido `ON_bl50`) | 4.48 | 7.7 h |
| Pantalla 50 % a 120 Hz (4,48 + 0,45) | 4.93 | 7.0 h |
| Pantalla 100 % a 60 Hz (medido `ON_bl100`) | 6.90 | 5.0 h |

- Día tipo «3 h de pantalla a 25 %/60 Hz y el resto en reposo con pantalla apagada»: **20.5 h** hasta el 5 % (3×3,37 W + resto a 1,39 W; si el reposo largo pasa a suspensión, más: **suspensión no medida**).
- Uso continuo con pantalla encendida: ~10 h a 25 %, ~7–8 h a 50 %. Cada +10 % de brillo ≈ −0,47 W.

## Qué consume más (ordenado, medido)
1. **Retroiluminación**: 2,3 mW por paso; 50 % = +2,0 W; 100 % = +4,5 W. El mayor consumidor.
2. **Pantalla encendida (panel + pipeline + sondeo táctil)**: +0,81 W incluso con el brillo a 0.
3. **Refresco**: 120 Hz +0,45 W, 90 Hz +0,28 W respecto a 60 Hz.
4. **WiFi asociada**: 0,36 W (`power_save` no mejoró de forma medible).
5. **Suelo del sistema despierto** (SoC, DDR, ADSP, BT del lápiz): ~1,0 W de los 1,39 W; hipótesis (no medida): raíles/relojes ignorados por la cmdline (`*_ignore_unused`).
6. `uke-touchd` ~11 % de un núcleo con pantalla encendida (0 con DPMS off): ≤0,1–0,3 W (hipótesis).
Sin efecto medible en reposo: perfiles CPU/GPU, tailscaled, `uke-bateria-log`, `rcu_expedited`.

## Perfiles (qué cambia de verdad en batería)
| Perfil | refresco | brillo | reposo (atenuar/pantalla off/suspender) | efecto esperado |
|---|---|---|---|---|
| Ahorro | 60 Hz | tope 25 % | 1/2/10 min | el más largo: ~10 h de pantalla, pantalla off a los 2 min |
| Equilibrado | 60 Hz (batería) | tope 50 % (nuevo) | 2/3/15 min | ~7–8 h de pantalla; uso general |
| Rendimiento | 120 Hz con cargador, 60 Hz en batería | sin tope | 2/3/15 min | igual consumo en reposo; solo cambia CPU/GPU bajo carga (no medido) |
Afinado hecho en el repo (**no desplegado**, la tablet no se toca): tope de brillo del perfil Equilibrado 50 % (el tope solo baja el brillo al cambiar de perfil, no es continuo). El refresco ya no depende del perfil.

## Pendiente cuando vuelva la tablet
- Recoger `/var/log/uke-bateria/*.csv` de este periodo (uso real sin cables) y pasar `uke-bateria-informe 7`: consumo por perfil y hora, procesos con más CPU, drenaje en suspensión (filas `resume`).
- Medir suspensión (≤0,3 W es hipótesis) y Bluetooth; validar el absoluto sin cargador con `medir-linux-descarga.sh`.
- Contrastar la autonomía de este modelo con el drenaje real (%/hora) del log.
- Desplegar el afinado del perfil Equilibrado (`deploy.sh apply`).

## Log recogido de la tablet (21-oct 22:43) — resultado
Copia en `build/logs/bateria-20261021/` (CSV del 19, 20 y 21-oct + arranques.log). **Sin uso real sin cables**: de 1384 muestras, 1361 son `Charging` y solo 6 `Discharging` (la tablet estuvo siempre conectada; sube de 26 % a 100 %). `uke-bateria-informe` etiqueta como «descarga» las filas con `Charging` y drenaje neto >0,3 W (cargador SDP débil), así que sus medias por perfil (Ahorro 1,31 W, Equilibrado 1,83 W…) NO son consumo de uso real: mezclan carga parcial, brillo 5 % y perfiles distintos. Suspensión: 7,75 h suspendida el 21-oct (12:46–20:32) **con cargador**: sin dato de drenaje (la batería subió de 74 % a 100 %).
Conclusiones útiles del log: (1) el reposo largo sí entra en suspensión sola; (2) IRQ más activas con el escritorio: arch_timer 679/s, IPI «Function call» 467/s, uke-touch 122/s (804 min), gpi-dma 165/s; (3) CPU acumulada: `python3` 11 007 s (logger/medidores/táctil; el táctil con pantalla encendida), Hyprland 988 s, tailscaled 896 s, quickshell 871 s; (4) `acb6000.isp_msm_csid0` 9400 IRQ/s durante 2 min (sesión de cámara).
Pendiente real: drenaje sin cable (desenchufar) y carga rápida (<80 %), con los scripts `medir-linux-descarga.sh` y `medir-linux-carga-rapida.sh`.
Desplegado 21-oct 22:5x: tope de brillo 50 % en Equilibrado (`/etc/uke/perfiles.conf`).

## MEDIDA REAL SIN CABLE (21-oct 22:45–22:51, Equilibrado, 99 %→100 %, 25 °C, por Tailscale) — corrige lo anterior
Datos: `build/rootfs/deploy/bateria/medidas/drenaje-linux-20261021-224548.csv` (`medir-linux-descarga.sh`). Descarga directa (sin entrada USB):
- **Pantalla encendida (brillo 5 %, 60 Hz en batería): 1,97 W** de media (34 muestras, 1,76–2,24).
- **Pantalla apagada (DPMS off): 0,93 W** de media (44 muestras, 0,76–1,57).
Los absolutos con cargador (1,39 W y 2,43 W) estaban **≈0,45 W por encima** de la medida directa; los deltas (brillo, refresco, WiFi) siguen siendo válidos. Autonomía recalculada (90 % útil = 34.4 Wh):
| Situación (drenaje real 21-oct + deltas del 20-oct) | W | autonomía |
|---|---|---|
| Pantalla apagada (DPMS off) | 0.93 | 37.0 h |
| Pantalla 5 %, 60 Hz | 1.97 | 17.5 h |
| Pantalla 25 %, 60 Hz (+0,94) | 2.91 | 11.8 h |
| Pantalla 50 %, 60 Hz (+1,8) | 3.77 | 9.1 h |
| Pantalla 50 %, 120 Hz (+0,45) | 4.22 | 8.2 h |

Día tipo (3 h de pantalla al 25 %/60 Hz y el resto con pantalla apagada): **≈31 h** hasta el 5 % (sin suspensión; con suspensión, más). Una sola pasada de 90/120 s; la suspensión y el uso real (vídeo/navegador) siguen sin medir.
