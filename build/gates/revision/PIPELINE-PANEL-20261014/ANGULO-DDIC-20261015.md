# ÁNGULO-DDIC — qué necesita el panel o82 para la primera imagen (15-oct-2026)

> Solo lectura, 0 flash. Premisa: negro-con-luz, commit OK, `err=0` pre+post, PPS dims OK.
> Lo ya cerrado no se repite (ronda 2 + COMPARATIVA). Aquí solo: condiciones mínimas
> vistas desde el DDIC + lo que NADIE miró. [M]=medido fichero:línea · [H]=hipótesis.

## 1. Tabla de condiciones mínimas (cold power-on → primera imagen)

| # | Condición DDIC | Android [M] | Nosotros | Test discriminante |
|---|---|---|---|---|
| C1 | Rails analógicos (vci 2,6 V + vddio) ANTES de soltar reset | L19 votado en pre_prepare (ANDROID-CADENA §3.2) | vci en árbol vivo (`o82:59,308,857`) pero **voto en vivo jamás verificado** (S1-VCI §4 pide `use 1`, sin log) | 0-flash: `regulator_summary` por SSH si L66 viva; si `use 0` → S1 no llegó al vivo |
| C2 | Reset válido (doble pulso vendor) + lanes en LP11 durante reset | Doble reset pre_prepare+prepare, LP11-init (`stock_uke.dts:13250`) | **Un solo pulso** (COMPARATIVA:9); NON_CONTINUOUS sigue (`o82:791-792`) | Solo si L65 NAK: 1-flash s3a/segundo reset; si L65 responde, C2 cerrada sin flash |
| C3 | Init-bytes idénticos (incl. `0x53=0x24`, `0x51=0x0FFF`, bloques `0x90-0x9D`) | 108 regs LP, `dt=0x39` (PANTALLA-COMPLETA §3) | Byte-idéntico [M] (ANDROID-CAMINO §3); `0x53=0x24`=BCTRL+dimming ON, `0x51`=máx ⇒ emisión permitida, coherente con "hay luz" | Cerrada. No tocar |
| C4 | `0x11` latchado (sleep-out) + `0x29` (display-on) | #106/#107, único wait 120 ms | Enviados, `err=0` = solo DMA host (ronda 2 §2) | **L65 lee `0x0A`: D4=1 (out of sleep) + D2/D3=1 (display on+normal)** → C4 probada por bits, no por `err` (§2) |
| C5 | Descompresor DSC armado | Bloque init `0x9D=0x01` (`o82:183`) preconfigura el IC; `update_pps` existe pero con splash nunca se envía (PPS-COMPARA §2) | Bloque `0x9D` enviado [M] (mismo blob); PPS pre+post [M] (L62/L64) | 0-flash offline: auditar si algún cmd del blob es *compression-enable* explícito y si `picture_parameter_set` basta sin `compression_mode_ext` (nadie lo miró; ronda 2 §1c lo pide). Si el `0x9D` es el switch, la rama PPS queda cerrada del todo |
| C6 | Stream vídeo HS válido (timing aplicado, clock continuo, byte-rate correcto) | `FLUSH=1/DB_MODE=0/HS_TIMER=0x4BB80` + byte 148,6 M [M] (PANTALLA §4) | Nada de FLUSH/HS_TIMER en `.c` [M] (S4 §2.4); byte pedido 118,9 M vs 148,6 M [M] (S6 §2.4); clock pedido continuo ausente | 0-flash: `clk_summary` en vivo (ronda 2 §6.1, hueco mayor). 1-flash: ciclos ENABLE-COMPARISON 1a-1c |
| C7 | BLLP en LP + EOT coherente para CMD y BTA | `bllp-power-mode` vacío=LP; `rx-eot-ignore/tx-eot-append` (S6 §2.1) | Mainline añade EOT por defecto [M código] — coherente, sin programar timers LP/HS [M] (S4 §1: ningún `.c` los toca) | No tocar antes de L65; un NAK BTA con C1/C2 OK reabre EOT/timeouts |
| C8 | Sin blankeo por brillo (`0x51` runtime no usado, KTZ externo, dimming+300 ms) | Case 3 → KTZ tras 1ª trama+300 ms; `0x51` init = registro (CAMINO §2) | KTZ-ON post-modeset [M]; luz funciona ⇒ pata cerrada | Cerrada como causa del negro (luz ON = emisión habilitada) |

## 2. Lo NUEVO que aportan estas 4 notas (nadie las escribió)

1. **`0x0A` es un oráculo de 3 bits, no un "escucha/no-escucha".** L65-BTA.md §4 define
   binario (`ret==len` ⇒ responde). Decodificado MIPI DCS: **D7=booster, D4=sleep-out
   (`0x11` latchó), D2/D3=display-on+normal (`0x29` latchó).** Un `0x9C` (D7+D4+D3+D2)
   prueba C4 entera y convierte L65 en el parte de defunción de TODA la rama DCS/power:
   DDIC despierto + negro ⇒ solo queda C6 (vídeo). Pedir el decode en el criterio PASA.
2. **`0x0B/0x0C` NO comparan contra el init.** Los `0x36=0xF3`/`0x3A=0xEF` del array
   (`o82:126,129`) son registros de página vendor, no MADCTL/COLMOD DCS (valores
   imposibles en DCS estándar). Valor esperado = defaults del DDIC (desconocidos, iguales
   en Android por blob idéntico): cualquier reply ∉ {0x00,0xFF} prueba escucha+vigilia,
   sin comparación. Evita un falso FALLA.
3. **L65 puede salir VOID por `inherit`.** `o82_enable:613-616` retorna 0 pre-BTA si
   `uke_panel_inherit()` (igual que el prepare `359-368`). Gate previo al juicio:
   exigir línea `UKE-L63` en el mismo dmesg; sin ella el test no existió, no "falló".
4. **En AMOLED, negro-con-luz ⇒ DDIC probablemente despierto [H].** Píxel emisivo:
   sordo/en-reset/sleep = negro absoluto sin emisión; luz con contenido negro =
   escaneando negro = C1–C5 OK y C6 muerto. Discriminante 0-flash T2 (DPMS 3→0,
   CADENA-USERSPACE §4): si el negro parpadea/cambia, DDIC vivo y C6 confirmado sin flash.

## 3. Ranking nuevo: CONDICIONAL a L65 (difiere del plano 1-2-3-4)

- **Paso 0 (0 flash, hoy si L66 viva):** `clk_summary` (byte/bit por link) + T2 DPMS +
  `regulator_summary` (L19 `use`) + `getvar all`. El clock decide C6 sin flashear.
- **1) L65/BTA con decode §2.1 (1 flash).** Sigue siendo el test correcto — pero con
  criterio ampliado a bits, no binario. Ningún otro test discrimina 5 condiciones a la vez.
- **Si `0x0A≈0x9C` (despierto): 2) motor vídeo FLUSH/HS_TIMER/DB_MODE, 3) byte-clock
  (si el paso 0 no lo cerró), 4) s6-noncontinuous DEMOTADO** (transporte LP probado
  `err=0`×2 + BTA responde en LP ⇒ el clock solo puede morder en HS-vídeo, no en DCS).
- **Si NAK/`ret<=0` (sordo): 2) C1 vci en vivo, 3) C2 doble-reset (s3a), 4) C7 EOT/timeouts;
  prohibido tocar C6** (orden ronda 2 §5-acción 2, vigente).
- **C5-auditoría (0 flash, en paralelo):** si confirma que `0x9D` es el switch y la PPS es
  decorativa, se cierra la rama PPS definitivamente y se cancela cualquier futuro flash PPS.
