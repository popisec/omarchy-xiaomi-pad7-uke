# Cotejo DCS / encendido: vendor (DT + traza) vs driver panel-xiaomi-o82-dualdsi.c

Fecha 17-oct-2026. Solo lectura. Rutas abreviadas:
- DT = `build/android/dt-full-uke-android/base/soc/qcom,mdss_mdp@ae00000/qcom,mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid/` (blobs en `qcom,mdss-dsi-display-timings/timing@{120,90,144}/`)
- TL = `build/android/vendor-harvest-20261017b/panel-on-timeline.txt`; TR = `trace-offon.txt`; DM = `dmesg.txt` (misma carpeta)
- DRV = `build/kernel-pokes/k52-L16-tree/drivers/gpu/drm/panel/panel-xiaomi-o82-dualdsi.c`
- MGR = `.../drivers/gpu/drm/msm/dsi/dsi_manager.c`; HOST = `.../msm/dsi/dsi_host.c`

Decodificacion con python3 -I (formato de registro: dtype, last, vc, ack, wait, dlen_hi, dlen_lo, payload). Todos los blobs de comandos decodifican limpios (longitud total exacta).

## 1. Veredicto resumido

1. El contenido de la tabla ON del driver es **byte-exacto** frente al vendor (cmds 0..103, 964 B, comparado programaticamente contra `timing@120/qcom,mdss-dsi-on-command`: 0 diferencias, incluidos cabeceras y delays). Orden y bytes de b3/b2/0x11/0x29 tambien coinciden. No hay comandos que falten ni sobren DENTRO del set ON.
2. Las diferencias reales estan en el **orden/entorno de envio**, no en los bytes:
   - (A) el motor de video del DSI esta ON antes de enviar los 108 DCS (vendor: OFF hasta despues del PPS);
   - (B) el PPS (set 0x13 del vendor, 1 cmd) se envia 2 veces y en momento distinto (antes del sleep-out; vendor: una vez, tras 0x29+120 ms);
   - (C) los 108 DCS del vendor van TODOS como DCS long write 0x39 (incluso 0x11/0x29 y las escrituras de 2 B); el driver deja que mainline elija 0x05/0x15;
   - (D) reset: orden y polaridad coinciden; el ultimo delay es 100 ms en vez de 15 ms (cambio deliberado r7);
   - (E) faltan 3 sets posteriores (0xf4 timing-switch HS, dimming-on, cabc-off) y el cmd set 4 vacio.

## 2. Decodificacion del DT (panel 42_02_0b)

Solo existe `qcom,mdss-dsi-on-command` (108 cmds, 998 B, `dsi_lp_mode`) por timing. **No hay pre-on ni post-on** en el nodo: los sets 0 y 2 de la traza son vacios, coherente.

Props de nodo relevantes: `qcom,mdss-dsi-reset-sequence` = (0,10) (1,3) (0,3) (1,15) [valor, ms]; `qcom,platform-reset-gpio` = <0x16b 2 0> (gpio global 363 = TLMM 335 fisico en la traza); `qcom,mdss-dsi-lp11-init`; `tx-eot-append`; `traffic-mode non_burst_sync_event`; `dma-trigger trigger_sw`; `mdp-trigger none`; `panel-broadcast-mode` y `cmd-sync-wait-broadcast` presentes; `dsi-ctrl-num` = <0 1>; `mi,mdss-panel-on-dimming-delay` = 0x12c (300 ms).

### 2.1 ON-command timing@120 (108 cmds)

Todos dtype 0x39 (DCS long write), last=0, vc=0, byte4 = 0x40 (en todos salvo los cmds 6, 12, 74, 105, 106, 107 que tienen 0x00; ver nota LP), wait=0 salvo cmd 106.

| # | payload | nota |
|---|---------|------|
| 0-1 | ff 27 / fb 01 | pagina 27 |
| 2-6 | d0 31, d1 20, d2 38, de 43, df 02 | |
| 7-12 | 08 24 0a, 0c 1e 00, 10 1e 00, 80 57 09, 84 2d 00, 88 2d 00 | |
| 13-14 | ff 23 / fb 01 | pagina 23 (curvas) |
| 15-56 | 00 80, 01 84, 05 f6, 06 02, 11 03, 12 2a, 15 d0, 16 16, 29 0a, 30..41 (gamma), 2a 13, 45..54 | |
| 57-74 | ff 23, fb 01, 58..67 (gamma) | |
| 75-84 | ff 25/fb 01/0f 20; ff 2a/fb 01/c4 82; ff 26/fb 01/3b 06/4b 06 | |
| 85-94 | ff 22/fb 01/c4 06; ff f0/fb 01/fa 05/76 16; ff 20/fb 01/30 00 | |
| 95-98 | ff 10, fb 01, **51 0f ff** (brillo DCS 0x51), 53 24 | |
| 99 | 3b 03 94 1a 04 04 00 | VESA-like timing DDIC |
| 100 | 90 03 | habilita DSC en DDIC |
| 101 | 91 ab 28 00 18 d2 00 02 b2 02 9f 00 0b 04 86 02 dc (17 B) | PPS interno del DDIC (dec_delay 0x2b2, scale_inc 0x29f, nfl 0x486: coincide con lo ya anotado en DRV:627-630) |
| 102 | 92 10 f0 | |
| 103 | 9d 01 | |
| 104 | b3 40 | 120 Hz (144: b3 00 / 90: b3 80) |
| 105 | b2 91 | 120 Hz (144: b2 00 / 90: b2 00) |
| 106 | 11, **wait=120 ms (0x78)** | sleep out |
| 107 | 29, wait=0 | display on |

Diferencia entre timings: solo cmds 104 y 105 (b3/b2).

### 2.2 Otros sets del DT (timing@120)
- OFF (3 cmds, LP, dtype 0x05): `28` wait 20; `10` wait 100; `4f` wait 0.
- timing-switch-video (4 cmds, **HS**, 0x39): `ff 10`, `fb 01`, `b2 91`, `b3 40` (120 Hz; 144 y 90 cambian solo b2/b3).
- dimmingon (4): 0x39 `ff 27`, 0x39 `d1 28`, 0x15 `ff 10`, 0x15 `53 2c` (LP).
- cabcoff (2): 0x15 `ff 10`, 0x15 `55 00`; cabcmovieon/stillon/uion (2 c/u), disable-insert-black (2), insert-black-screen (2), pen-clear (3: ff10, fb01, b2 80).

### 2.3 Supply entries (`dsi_panel_pwr_supply_O82`, phandle 0x6b3)
vddil8b 1.9 V, vsp 5.8 V (0x588040 uV), vsn 5.8 V; los tres con enable-load 300000 uA, post-on-sleep 2 ms, post-off-sleep 2 ms. Orden entradas: vddil8b, vsp, vsn.

## 3. Correspondencia de los cmd sets de la traza

Evento `dsi_panel_tx_cmd_set` = (tipo, estado, n_cmds). Identificacion (inferida por recuento de cmds y repeticion; el DT no nombra los tipos):

| Traza (TL linea) | t (ms) | Interpretacion | Evidencia |
|---|---|---|---|
| set 0, n=0 (TL:17) | +42.4 | PRE_ON vacio | no hay pre-on en el DT |
| set 1, n=0x6c=108 (TL:19) | +42.8 .. +46.0 y +166.6 | ON | 108 cmds = on-command. Se envian 0..106 (hasta 0x11) en ~3.2 ms, espera 120 ms, y 0x29 sale a +166.6 (cmd engine on/off en TL:48-49) |
| set 2, n=0 (TL:52) | +167.0 | POST_ON vacio | sin post-on en el DT |
| **set 0x13, n=1 (TL:53)** | +168.3 | **PPS (1 cmd generado en runtime por sde)**: INFERENCIA (no hay ningun set de 1 cmd en el DT; se envia justo antes de arrancar el video engine) | n=1; `qcom,mdss-dsi-on-command` no lo contiene; vendor CAF genera PPS con sde_dsc_create_pps_buf_cmd |
| VIDEO ENGINE ON (TL:58-59) | +168.8 | dsi_ctrl_set_vid_engine_state | |
| set 4, n=0 (TL:62) | +173.0 | vacio (no identificado) | |
| **set 0xf4, estado=1, n=4 (TL:63)** | +173.0 .. +180.3 | **timing-switch-video (HS, 4 cmds)** | n=4 y estado 1 = HS; se repite en cada cambio de timing (TR:11117, 11714, 13054, 13659, 14504, junto a set_video_timing 0x103d/0x905) |

Tras eso el KTZ8866 (+180.6, i2c): reg08=3f, 04=00, 05=00 y luego 08=7f, 04=06, 05=23 (TL:68-70). Los sets 0xf9/0xfb/0x19 de TR (:4829, 5002, 5106) son cabc/dimming de Mi, ~30-50 ms despues (DM: "cabc off", "dimming 1" ~270 ms tras ON, retardo 300 ms del DT).

## 4. Tabla de diferencias

Gravedad: **P** = probable causa de negro; **D** = desconocida / posible; **I** = inocua o muy improbable.

### Diferencia 1 (P): motor de video DSI ON antes de los DCS (vendor: OFF)
- Vendor: los 108 DCS (+42.8..+167) y el PPS (+168.3) se transmiten con el video engine apagado (solo cmd engine); `dsi_ctrl_set_vid_engine_state` se activa en +168.8, despues del PPS (TL:58-59).
- Driver: `prepare_prev_first = true` (DRV:959) hace que el pre_enable del bridge DSI corra antes de `o82_prepare`; `dsi_mgr_bridge_pre_enable` llama a `msm_dsi_host_enable()` (MGR:304, 311) que pone `DSI_CTRL_VID_MODE_EN | ENABLE` (HOST:2630, 1255-1259). Es decir, VID_MODE_EN ya esta activo cuando salen reset, 108 DCS, b3/b2, 0x11/0x29, y PPS.
- Indicio del propio proyecto: HOST:1267-1270 y DRV:663-670, 695-701: las lecturas BTA devolvian ret=0 con video ON y se probo (L68-L72) apagar VID_MODE_EN, retirado por dejar el FIFO en error.
- Riesgo: DCS en LP intercalados con un video engine ya activo (sin pixeles aun del MDP) no reproducen el contexto vendor; puede dejar al DDIC sin recibir/validar la secuencia. Es la diferencia estructural mas relevante; no se puede confirmar solo con lectura.

### Diferencia 2 (P/D): PPS distinto en numero y momento
- Vendor: UN solo PPS (set 0x13, 1 cmd), tras 0x29, antes del video engine (TL:53, +168.3).
- Driver: PPS #1 en `o82_prepare` entre el cmd 103 y b3/b2/0x11, es decir con el DDIC aun en sleep-in (DRV:413-461, envio a ambos links en 445-448); PPS #2 en `o82_enable` (DRV:636-638), despues de que el video engine ya corre, y encima L65 hace 12 lecturas BTA (DRV:672-693).
- Ninguno coincide con el orden vendor (post-0x29 y pre-video). Ademas el PPS #1 llega antes del sleep-out. Gravedad D: el DDIC ya tiene su DSC programado por cmds 100-102 (`90 03`, `91...`, `92 10 f0`) con valores que coinciden con el RC del driver, asi que el PPS DSI puede ser redundante para el DDIC, pero el vendor lo envia y el orden esta invertido respecto al vendor.

### Diferencia 3 (D): dtype de transmision
- Vendor: dtype 0x39 en los 108 cmds, incluso 2 B (`ff 27`) y 1 B (`11`, `29`).
- Driver: usa `mipi_dsi_dcs_write_buffer_multi` => len 1 = 0x05 SHORT_WRITE, len 2 = 0x15 SHORT_WRITE_PARAM, len>=3 = 0x39 (drm_mipi_dsi.c:932-947). El switch de DRV:241-247 solo comprueba el dtype para validar y descarta la cabecera (DRV:195-216 lo documenta).
- Resultado: de los 108 cmds, 98 (96 de 2 B + 2 de 1 B: 0x11 y 0x29) dejan de ser long write 0x39 y pasan a short write 0x15/0x05; solo los 10 de >=3 B (8 de 3 B, uno de 7 B, el de 17 B) siguen como 0x39. Muchos DDIC aceptan ambos, pero el vendor fuerza long write y es lo unico validado en este panel. Un DDIC Novatek en pagina de comandos con short write de 2 B suele aceptarlo; no hay evidencia de que falle. Mitigacion posible: enviar con `mipi_dsi_generic/dcs` forzando MIPI_DSI_DCS_LONG_WRITE via `mipi_dsi_device_transfer` con msg.type=0x39.

### Diferencia 4 (I/D): reset
- Orden y polaridad identicos: fisico 0 (10 ms), 1 (3 ms), 0 (3 ms), 1 (final) (DRV:271-294 con gpiod activo-bajo: valor 1 = fisico 0; probe pide GPIOD_OUT_HIGH = asertado, DRV:858-864; vendor TL:11-16 y DT reset-sequence 0/10 1/3 0/3 1/15). La polaridad ACTIVE_LOW del nodo DT del overlay no pude verificarla en el arbol (el nodo vive en mkdtbo-*.py/overlay); DRV:858 (comentario) y DRV:267-270 lo dan por supuesto.
- Delays: 10/3/3 ms coinciden (usleep_range 10000/3000/3000). **Final: 100 ms (DRV:291, "r7 discriminador") vs 15 ms del vendor** (reset-sequence ultima entrada 0x0f; TL:16 -> primer DCS +15 ms en TL:17). El log de pr_info de DRV:293 aun dice "release2(15ms)". Un reset-high mas largo no deberia romper un DDIC; en un TDDI (NT36532 comparte reset con el touch segun DM) podria alterar la ventana de arranque del touch, no del display. Gravedad I.
- Relacion con el reloj DSI: en el vendor las clocks byte/pclk/esc DSI se habilitan 0.1 ms antes del reset (TL:10-11) y el set_video_timing se programa antes (TL:7-8). En el driver el host se enciende (power_on) antes de prepare por prepare_prev_first (cumple lo mismo). Gravedad I.

### Diferencia 5 (I): tiempo desde reset hasta primer DCS
Vendor +15 ms exactos (TL:16->17); driver +100 ms. Coherente con la Diferencia 4. I.

### Diferencia 6 (I, verificado igual): espera de 120 ms tras ON
- Vendor: `wait=120` en cmd 106 (0x11); 0x29 sale ~120.6 ms despues (TL:44-49: +46.0 -> +166.6).
- Driver: 0x11, `mipi_dsi_msleep(120)`, 0x29 (DRV:486-491). **Si respeta la espera de 120 ms** entre sleep-out y display-on. El vendor ademas no envia nada entre 0x11 y 0x29 y el driver tampoco. Bien. (Nota: el driver usa un unico msleep de 120 ms; el vendor lo hace en la capa de transmision con usleep, mismo efecto.)
- Despues de 0x29 el vendor no espera nada antes de PPS+video (+1.7 ms); el driver pasa a enable() sin espera. I.

### Diferencia 7 (D): sets posteriores que el driver no envia
- Set 0xf4 timing-switch-video (HS, 4 cmds: ff10, fb01, b2 91, b3 40) enviado en +173.0 tras el video engine. El driver nunca lo envia (DRV:476-483 solo b3/b2 en LP en el tail ON; el TODO en DRV:471-474 lo reconoce). Los valores b2/b3 son los mismos que ya van en el set ON, asi que a 120 Hz es practicamente un reenvio idempotente. I a 120 Hz; imprescindible para 144/90 Hz (hoy solo se expone 120 Hz, DRV:800).
- dimming-on (4 cmds, `ff27 d1 28`, `ff10 53 2c`) y cabc-off (`ff10 55 00`) los lanza Mi tras el ON (retardo 300 ms): no afectan al encendido; solo comportamiento de brillo. I.
- Set 4 (n=0): vacio. I.
- Set 2 post-on y set 0 pre-on: vacios. Nada que enviar.

### Diferencia 8 (I): modos LP/HS y destino de links
- ON/OFF: vendor `dsi_lp_mode` => driver `MIPI_DSI_MODE_LPM` (DRV:812) => LP. Coincide. timing-switch-video es HS en el vendor; el driver no lo envia (Dif. 7).
- Byte de cabecera 0x40 vs 0x00 (cmds 6, 12, 74, 105-107 con 0x00): en el parser CAF solo `data[3]==1` pide ACK, por lo que 0x40 no hace nada de sustancia; el driver lo ignora (DRV:195-216). (Interpretacion del parser de memoria, no verificada contra fuentes CAF aqui.)
- last=0 en todos: CAF fuerza `last_command` en el ultimo del set; con driver cada cmd es una transferencia independiente. Equivalente en la practica (traza vendor: ciclo cmd-engine por comando).
- Destino dual: vendor broadcast (`panel-broadcast-mode`, `cmd-sync-wait-broadcast`). Driver: `mipi_dsi_dual_dcs_write_buffer_multi` llama a dsi[0] y luego dsi[1]; con `is_sync_needed` (MGR:35, 61-62, DT-dependiente) la llamada de DSI_0 es no-op y la de DSI_1 dispara ambos links (MGR:517-518, 520-545, 556-561). Resultado: un envio sincronizado a los 2 links = broadcast, igual que el vendor. Si `is_sync_needed` no estuviera activo, se envia a cada link por separado (tambien valido pero sin trigger simultaneo). El PPS se envia llamando una vez por link, igual semantica. OFF: bucle por link con `mipi_dsi_dcs_*` (DRV:535-547), mismo patron. I.
- Reads de L65: no existen en la secuencia vendor de encendido (el vendor solo lee diagnostico/ESD). Extra pero sin escritura. I.

### Diferencia 9 (I, verificado igual): rieles y OFF
- Rieles: vddil8b -> vsp -> vsn, load 300 mA, 2 ms (DT 2.3 vs DRV:326-339, `O82_SUPPLY_ENABLE_LOAD_UA` DRV:51). Igual. El driver ademas habilita vci (L19, 2.6 V) antes (DRV:311-323), que el vendor no ciclo (en la traza solo vsp/vsn conmutan, TL:1-6: vsp +0.0, vsn +2.5 ms, coincide con 2 ms del driver, +0.5 de jitter). I.
- OFF: 0x28, 20 ms, 0x10, 100 ms, 0x4f = identico a DT (DRV:529-547, orden y delays). I.

## 5. Tabla DSC (host) — solo cotejo rapido

DT: bpc 10 (0xa), bpp 8, slice 800x24 (0x320 x 0x18), slice-per-pkt 1, DSC 1.1 (0x11), block-pred presente, scr-version ausente, topology (2,2,2). DRV:780-790: version 1.1, 800x24, 2 slices por link, 10 bpc, 8 bpp, block_pred true. Coincide.

## 6. Orden vendor reconstruido vs driver (resumen lineal)

Vendor: vsp(+0) -> vsn(+2.5) -> timing video (+8.6) -> clks DSI (+10.7) -> reset 0/10.1/1/3.2/0/3.2/1 (+10.8..+27.3) -> [+15] set0 vacio, set ON: 104 cmds + b3 + b2 + 0x11 (LP, video OFF, ~3.2 ms) -> **120 ms** -> 0x29 -> set2 vacio -> **PPS (1 cmd)** -> **video ON** -> set 4 vacio -> **0xf4 timing HS** -> KTZ.

Driver: vci -> vddil8b -> vsp -> vsn (2 ms c/u) -> [host ya con VID_MODE_EN ON] -> reset 0/10/1/3/0/3/1 + **100 ms** -> 104 cmds (LP) -> **PPS #1 a ambos links** -> b3 -> b2 -> 0x11 -> **120 ms** -> 0x29 -> (backlight KTZ por core DRM) -> enable(): **PPS #2** + 12 lecturas BTA.

## 7. Orden de sospecha para "negro"

1. Dif. 1: VID_MODE_EN ya activo durante toda la secuencia DCS (vendor: OFF hasta el final del PPS).
2. Dif. 2: PPS #1 antes del sleep-out (el vendor lo envia tras display-on) y PPS #2 con video ya en marcha.
3. Dif. 3: tipos 0x05/0x15 en vez de 0x39 en el cable.
4. Resto (reset 100 ms, sets 0xf4/dimming/cabc) improbables; no explican negro a 120 Hz.

Pruebas atacables sin hardware nuevo (propuestas, no ejecutadas): (a) forzar msg.type=0x39 en `o82_send_panel_cmds` y en b3/b2/0x11/0x29; (b) mover PPS a despues de 0x29 y quitar PPS #1; (c) parar VID_MODE_EN antes del reset y arrancarlo tras el PPS usando `msm_dsi_host_video_engine_set()` (DRV:41), que ya existe; (d) volver el reset final a 15 ms para aislar variables.

## 8. Limitaciones
- Los tipos 0x13 (PPS) y 4 son inferencias por recuento de cmds; el DT no los nombra.
- La polaridad ACTIVE_LOW real del overlay y el valor efectivo de `is_sync_needed` en el dtbo vivo no se han comprobado aqui.
- Comparacion hecha solo con los ficheros indicados; no se ha ejecutado nada ni tocado el hardware.
