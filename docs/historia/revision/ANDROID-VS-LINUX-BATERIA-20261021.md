# Batería y carga: Android frente a Linux en uke (cierre, 21-oct-2026)

Cierra `docs/historia/revision/CARGA-LENTA-DRIVERS-20261020.md` y `docs/historia/revision/ANDROID-BATERIA-MAPA-20261020.md`. Evidencia en esos informes, en `build/android/bateria-20261019/` (capturas) y en `build/gates/revision/BATERIA-20261019.md`. Mediciones del 19–20 oct; lo no re-medido en 14 días caduca (4-nov).

## 1. Fuente de datos única: el gauge del ADSP
| | Android (`qti_battery_charger`, Xiaomi) | Linux (`qcom_battmgr` mainline + parche Uke) |
|---|---|---|
| Origen | gauge `fg1_*` por pmic_glink/ADSP | el mismo gauge por pmic_glink/ADSP |
| % exacto | `fg1_rsoc/100` = `fg1_rm/fg1_fcc` (±0,011 pt); UI `capacity` suavizada/retrasada | `charge_counter/charge_full` (µAh) = el mismo `rm`; `capacity` entero |
| `charge_counter` | mAh | **µAh** |
| signo de `current_now` | **> 0 = descarga**, < 0 = carga | **> 0 = carga**, < 0 = descarga |
| `status=Charging` | aunque la batería descargue (fuente < consumo) | ídem |
| tipo de cargador | `usb_real_type` (SDP/PD_PPS…), `quick_charge_type`, `cp_mode`, `pdo2`, `apdo_max` | solo `usb_type` genérico y `input_current_limit`; sin `ucsi`/typec |
**Conclusión**: no hay discrepancia de gauge. El 27 % vs 60 % del 19-oct era carga real entre medidas.

## 2. Quién decide la corriente: el firmware ADSP, en los dos
Trazas Android (`qbg_update_status`): al arrancar `BattAuth-2000`/`i_sdp-100`; con el puerto del PC `PdAuth-5780`/`chg_det-500` (500 mA, SDP; la batería descarga aunque diga Charging); con cargador PD/PPS 33 W `StepChgJeit-5350`/`chg_det-3000`, `cp_mode=4`, bus 9,25 V, **sin** autenticación Xiaomi (`pd_verifed=0`). Android solo aporta el nivel térmico (`tl`). En Linux, mismo hardware y mismo firmware:
| situación | Android | Linux |
|---|---|---|
| cargador PD/PPS 33 W | ~12 W a la batería (+2,6–2,9 A a 4,45 V, 72 %) | **19,7 W** (+4,45 A a 4,43 V, 93 %); cae a 15 W al 96 % |
| puerto del PC (SDP) | 500 mA (`chg_det-500`) | 100 mA por defecto del firmware ⇒ **no cargaba**; con `uke-icl` 500 mA; con otro cable llegó a 1 A |
| ICL máximo aceptado | — | 500000 por el parche Uke (`qcom_battmgr.c:1077`); 900000+ da EINVAL |
Causa de «cargaba bien en Android y no en Linux» por el PC: ICL 100 mA tras el arranque en Linux (el gadget no fija ICL; falta `usb-psy-name` en el DT) más un consumo despierto mayor. Arreglado con `uke-icl` (udev + arranque + log).

## 3. Consumo (lo medido; Android sin referencia limpia)
- Linux (20-oct, entrada USB constante con cargador de pared): **DPMS off 1,39 ± 0,05 W**; pantalla 5 %/60 Hz 2,43 ± 0,07 W; +0,45 W a 120 Hz; WiFi asociada 0,36 W; perfiles CPU/GPU sin efecto medible en reposo.
- Android (20-oct, con PC): ~2,9 ± 0,3 W pero con YouTube y la sesión del lápiz activas (no es reposo); `current_now` por adb sesgado al alza (0,48 A vs 0,20 A de las trazas del ADSP). Referencia en reposo limpio: **sin medir** (el «~1,4 W de Android» es una cifra heredada, no medida por esta sesión).
- Cifras absolutas de «sistema» de mis medidas del 19-oct estaban infladas ≈1,9 W (ver `BATERIA-20261019.md`).

## 4. Qué queda y cómo medirlo (PC, sin tocar la tablet hasta que audio la libere)
- Carga rápida en Linux con el cargador de pared y sin cable al PC: `build/rootfs/deploy/bateria/carga-rapida/medir-linux-carga-rapida.sh 180` (por Tailscale `root@uke`; mejor con <80 % de batería; compara con `pared-*.txt` de Android). Capturar VBUS (9 V) no se pudo antes.
- Drenaje real en Linux sin cable: `.../medir-linux-descarga.sh` (espera Discharging ≥20 %; fases pantalla encendida 90 s y DPMS off 120 s; restaura la pantalla con trap y respaldo `systemd-run`).
- Android: `medir-android-descarga.sh` y `medir-android-carga-rapida.sh` (en `build/android/bateria-20261019/`), cuando la tablet vuelva a Android.
- Sin autorización y sin hacer: `usb-psy-name` en el DT y `MaxPower` del gadget (CARGA-LENTA, propuestas 2–3), `fw_devlink.sync_state=timeout` (OPTIM-KERNEL), táctil/`bt-agent`.
