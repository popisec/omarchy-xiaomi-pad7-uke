# RE-DSI-CMD-FLAGS-SYNC — cómo envía el vendor los DCS/PPS a los dos links y en qué se diferencia mainline (17-oct-2026)

Solo análisis estático (sin adb, sin flash, sin compilar). Fuentes:
- Kprobe `dsi_message_tx`: `build/android/vendor-harvest-20261017b/kprobe/dsi-cmds-decoded.txt` (KPROBE).
- ftrace sde_evtlog: `build/android/vendor-harvest-20261017b/trace-offon.txt` (TRACE), `panel-on-timeline.txt` (TL).
- Volcado de registros con el link en reposo: `full-dsi{0,1}-ctrl-reg.txt` (REGS; offsets **físicos**, es decir, offset mainline + 4).
- Decompilado vendor `build/vendor-re/decomp/`: `dsi_display_set_cmd_tx_ctrl_flags.c` (FLAGS), `dsi_host_transfer_sub.c` (HTS),
  `dsi_message_tx.c` (MTX), `dsi_ctrl_cmd_tx_trigger.c` (TRIG), `dsi_ctrl_hw_cmn_kickoff_command.c` (KICK),
  `dsi_ctrl_hw_22_schedule_dma_cmd.c` (SCHED), `dsi_ctrl_hw_22_reset_trigger_controls.c` (RTC),
  `dsi_ctrl_dma_cmd_wait_for_done.c`, `dsi_panel_parse_misc_features.c`, `dsi_display_status_reg_read.c`.
- Mainline (árbol L16): `drivers/gpu/drm/msm/dsi/dsi_host.c` (HOST), `dsi_manager.c` (MGR),
  `drivers/gpu/drm/panel/panel-xiaomi-o82-dualdsi.c` (PANEL), `drivers/gpu/drm/drm_mipi_dsi.c`.
- DT vendor: `build/android/dt-full-uke-android/base/soc/qcom,mdss_mdp@ae00000/qcom,mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid/`.
  DT nuestro: `~/gpu-work/ramaa/s21/dtbo-gpu/fase4-display.dts` (copia en `build/gates/patches/k52L39-fuentes/fase4-display.dts:320-324`).
- Referencia (no es evidencia): techpack display CAF `msm/dsi/dsi_ctrl.h`, `dsi_ctrl.c`, `dsi_display.c`, `dsi_ctrl_hw_cmn.c`. Todo lo
  que sigue sale del decompilado y las trazas; los nombres CAF se usan solo porque el decompilado cuadra con ellos bit a bit.

---

## 1. Significado de los flags

### 1.1 `cflags` = `dsi_cmd_desc.ctrl_flags` (`*(u32*)(msg+0x34)`)

| Bit | Nombre CAF | Evidencia en el decompilado | En la traza |
|---|---|---|---|
| 0x001 | `DSI_CTRL_CMD_READ` | `dsi_ctrl_cmd_transfer.c`: `(param_2[0x34] & 1) == 0` → camino TX; si vale 1 → camino RX (max-return-size 0x37 + lectura) | 0 |
| 0x002 | `DSI_CTRL_CMD_BROADCAST` | FLAGS: se pone (`\|10`, junto con 0x8) si `ctrl_count != 1` y `!(msg->flags & 0x80)`. HTS: `(flags>>1)&1` elige el camino broadcast. MTX lo copia a `cmd.en_broadcast` (byte 9) → KICK lo escribe en **bit 31 de 0x3C** | 1 en ambos links |
| 0x004 | `DSI_CTRL_CMD_BROADCAST_MASTER` | HTS: `flags \| 4` solo para el ctrl `cmd_master_idx` (`display+0x198`). MTX → `cmd.is_master` (byte 10) → KICK **bit 30 de 0x3C**. TRIG: sin este bit = disparo SW del esclavo; con 0x2+0x4 = camino del maestro | 1 en ctrl0 (0x12e), 0 en ctrl1 (0x12a) |
| 0x008 | `DSI_CTRL_CMD_DEFER_TRIGGER` | FLAGS lo pone con BROADCAST. MTX: `hwflags = (f & 0x40) \| ((f>>3)&1)` → bit0 = `DSI_CTRL_HW_CMD_WAIT_FOR_TRIGGER`; KICK: `if (!(hwflags & 1)) writel(1, base+0x90)` → **no dispara** | 1; TRACE `kickoff_command:984 \| len \| 0x41` |
| 0x010 | `DSI_CTRL_CMD_FIFO_STORE` | FLAGS: si `ctrl+0x710` (cmd en FIFO) → 0x10; MTX: rama `kickoff_fifo_command` | 0 |
| 0x020 | `DSI_CTRL_CMD_FETCH_MEMORY` | FLAGS: si no hay FIFO → 0x20 (+0x80 si `tx_len > 0x100`). MTX: copia el paquete en el buffer DMA compartido y `msm_gem_sync` | 1 |
| 0x040 | `DSI_CTRL_CMD_LAST_COMMAND` | FLAGS: se pone **salvo** si `msg->flags & 0x40` (y no FIFO/NON_EMBEDDED). MTX: sin 0x40 solo **acumula** el paquete (`cmd_len += n`, sin kickoff); con 0x40 marca `hdr[3] \|= 0x80` (último paquete del lote) y hace el kickoff de **todo el lote**. Además MTX fuerza 0x40 si `BROADCAST\|FETCH` y `cmd_len + n > 0xF0` (lote de 240 B como máximo). TRIG: `if (!(f & 0x40)) return 0` | 0x12x→0x16x en el último de cada lote |
| 0x080 | `DSI_CTRL_CMD_NON_EMBEDDED_MODE` | FLAGS (tx_len > 256); MTX rama `pcVar12` | 0 |
| 0x100 | `DSI_CTRL_CMD_CUSTOM_DMA_SCHED` | FLAGS: en vídeo (`panel_mode == 1`) siempre; en cmd mode solo con `msg->flags & 0x20` o broadcast y si hay TE. MTX: llama a `dsi_configure_command_scheduling` (evtlog 0x523/0x54b) | 1 siempre |
| 0x200 | `DSI_CTRL_CMD_ASYNC_WAIT` | FLAGS: `(msg->flags & 0x10) << 5`, o `queue_cmd_waits` (`display+0x650`) si `post_wait_ms == 0` | 0 |

Valores de la traza: **0x12e** = CUSTOM_DMA_SCHED + FETCH_MEMORY + DEFER_TRIGGER + BROADCAST_MASTER + BROADCAST (ctrl0);
**0x12a** = lo mismo sin MASTER (ctrl1); **0x16e/0x16a** = lo mismo + LAST_COMMAND.

Prueba de que el corte a 240 B ocurre de verdad: KPROBE:88 y :206 (`ctrl=1 mflags=0x42 cflags=0x16a`, con ctrl0 en 0x12e en la
línea anterior). El kprobe captura los flags a la **entrada**. Cuando el maestro supera los 240 B, MTX escribe 0x40 en el
`msg->flags` compartido, y el esclavo ya lo recibe con 0x16a.

### 1.2 `mflags` = `mipi_dsi_msg.flags` (u16, `msg+2`)

| Bit | Significado (decompilado) | Nombre (ACK/CAF, referencia) |
|---|---|---|
| 0x01 | (no se usa en TX) | `MIPI_DSI_MSG_REQ_ACK` |
| **0x02** | MTX: `cmd.use_lpm = (msg->flags >> 1) & 1` (byte 11) → KICK **bit 26 de 0x3C** = transmisión en LP | `MIPI_DSI_MSG_USE_LPM` |
| 0x10 | FLAGS → `ASYNC_WAIT` | `MIPI_DSI_MSG_ASYNC_OVERRIDE` |
| 0x20 | FLAGS → `CUSTOM_DMA_SCHED` en cmd mode | `MIPI_DSI_MSG_CMD_DMA_SCHED` |
| **0x40** | FLAGS: si está, **NO** se pone `LAST_COMMAND` (el comando entra en el lote) | `MIPI_DSI_MSG_BATCH_COMMAND` |
| 0x80 | FLAGS: si está, **NO** se pone `BROADCAST` | `MIPI_DSI_MSG_UNICAST_COMMAND` |

Es decir, **0x42** = lote + LP (los 104 de init), **0x02** = último del lote en LP (`df 02`, `88 2d 00`, `11`, `29`, PPS,
`55 00`, `53 2c`), **0x40** = lote en HS y **0x00** = último en HS (`ff 10/fb 01/b2/b3`: el `timing-switch-video-command`,
que el DT declara `dsi_hs_mode`).

### 1.3 `qcom,cmd-sync-wait-broadcast` no es lo que parecía
`dsi_panel_parse_misc_features.c:61` lo guarda en `panel+0x8fc` (`sync_broadcast_en`). Su **único** consumidor en el TX/RX es
`dsi_display_status_reg_read.c:32`, la lectura ESD, que también lee del esclavo. **No interviene en el envío.** El broadcast de
TX sale solo de `ctrl_count > 1` (FLAGS). `qcom,mdss-dsi-panel-broadcast-mode` ni siquiera aparece como cadena en
`msm_drm.ko`. El DT vendor del o82 **no** tiene `qcom,mdss-dsi-dma-schedule-line/window`: vale el valor por defecto (línea 1).
También tiene `qcom,mdss-dsi-dma-trigger = "trigger_sw"` y `qcom,mdss-dsi-mdp-trigger = "none"`.

---

## 2. Mecanismo de envío dual del vendor

### 2.1 Secuencia (HTS = `dsi_host_transfer_sub` ≡ CAF `dsi_display_broadcast_cmd`)
Para **cada** `mipi_dsi_msg` de un set:
1. `dsi_ctrl_transfer_prepare(ctrl0)`, `(ctrl1)`: enciende el motor de comandos (`set_cmd_engine_state 1`) y los clocks.
2. `dsi_ctrl_cmd_transfer(master, flags|0x4)` → MTX(ctrl0): mete el paquete en el **buffer DMA compartido** (los dos ctrl tienen
   el mismo IOVA: REGS 0x48 = `0xfff2c000` en dsi0 **y** en dsi1). Sin LAST no hace nada más.
3. `dsi_ctrl_cmd_transfer(slave, flags)` → MTX(ctrl1), y después `dsi_ctrl_cmd_tx_trigger(slave)`, que retorna sin hacer nada si no hay LAST.
4. `dsi_ctrl_cmd_tx_trigger(master, flags|4)`, que tampoco hace nada sin LAST.
5. `transfer_unprepare` en los dos (el motor de comandos se apaga entre comandos: TL lo muestra encendiéndose y apagándose).

Cuando llega el **último** del lote (0x16e/0x16a), TRACE:46-65 (`32211.333751..333902`) da el orden real:
```
ctrl0 message_tx 0x16e len=0x30 → dsi_configure_command_scheduling (vídeo OFF: no programa nada)
      kickoff_command: 0x3C = BIT31|BIT30|BIT28|(LP?BIT26) ; 0x50 |= 0x110000 ; 0x48 = iova ; 0x4C = len ; 0x1CC |= 7 ; NO 0x90
ctrl1 message_tx 0x16a → igual, pero 0x3C = BIT31|BIT28|(BIT26) (sin BIT30) ; NO 0x90
ctrl1 cmd_tx_trigger 0x16a → (sin MASTER) trigger_command_dma: 0x90 = 1   ← se ARMA el esclavo
ctrl0 cmd_tx_trigger 0x16e → enable DMA_DONE irq; [bucle de línea si el vídeo está ON]; 0x90 = 1 ← el MAESTRO dispara los dos
ctrl0 unprepare → dma_cmd_wait_for_done (solo el maestro espera: ~100 µs con el vídeo OFF)
ctrl1 unprepare → clear_dma_status 0x2000001 (el esclavo también terminó: bit0 CMD_DMA_DONE)
```
Offsets físicos (= mainline + 4): 0x3C `CMD_DMA_CTRL` (mainline 0x38), 0x48/0x4C `DMA_BASE/LEN` (0x44/0x48), 0x50
`DMA_FIFO_CTRL` (bits 16/20: watermarks off; mainline no lo define), 0x84 `TRIG_CTRL` (0x80), 0x90 `TRIG_DMA` (0x8c),
0x100/0x104 `DMA_SCHEDULE_CTRL/CTRL2` (mainline 0xfc/0x100, no definidos), 0x1CC `VBIF_CTRL` según CAF (1c8; ver
PANEL-REVISION-REGDIFF:97).

**Estado de reposo medido (REGS):** dsi0 0x3C = `0xd0000000` (BROADCAST_EN + BROADCAST_MASTER + modo embedded; HS porque el
último fue HS), dsi1 0x3C = `0x90000000`; 0x84 = `0x80000004` en los dos (TE + DMA_TRIGGER=SW, **sin**
BLOCK_DMA_WITHIN_FRAME bit12, MDP_TRIGGER none); 0x90 = 1; 0x100 = 0; 0x50 = `0x00110000`; 0x1CC = 7.

**Conclusión de 2.1:** el envío es **broadcast hardware**. Cada link programa su propio DMA (misma dirección y misma longitud).
El esclavo se arma con su disparo SW, que con BROADCAST_EN=1 y MASTER=0 no transmite, y el **único disparo efectivo es el del
maestro**, que arranca los dos motores DMA en el mismo flanco. Los bytes llegan a los dos puertos del DDIC
**simultáneamente**, con skew ≈ 0, porque los dos links comparten PLL0 y byte clock. Además, cada lote de ≤240 B (≈8-30
comandos) sale como **una sola ráfaga DMA**: el set de init de 104 comandos son unas pocas ráfagas, no 104 transferencias.

### 2.2 LP/HS y programación por línea
- Init (set 1, 104 cmds), `11`, `29` y PPS (set 0x13): **LP** (mflags 0x02) y con el **motor de vídeo OFF** (TL: VID ON en
  +168.8 ms, después del set 0x13 = PPS). `dsi_configure_command_scheduling` entra y sale sin programar línea (TRACE
  `1355|0x2222` sin valor) porque `vid_engine_state != ON`.
- Con el vídeo ON (los sets `timing-switch` en **HS**, mflags 0x40/0x00, a partir de +277 ms): MTX→SCHED escribe
  `0x100 = 0x10000000 | línea` con **línea = VBP+VSW+VACTIVE+sched_line = 146+2+2136+1 = 2285 = 0x8ed** (TRACE: 6+2+1 veces
  `1355|0x2222|0x8ed`), que es la primera línea del VFP (26 líneas). TRIG (maestro) hace además un bucle con IRQs off: lee el
  line counter y, si está a menos de ≈100 µs de la línea programada (o justo en ella), hace `udelay(1000)` y repite. Después dispara. El
  DMA_DONE tarda entonces 2.8-7.2 ms (TRACE `wait_for_done` 32211.464035→.471206): el HW **retiene el DMA hasta la línea
  2285 del frame**. RTC pone 0x100/0x104 a 0 al limpiar. El vendor **no** usa BLOCK_DMA_WITHIN_FRAME.

---

## 3. Mainline (árbol L16) y nuestro panel

### 3.1 Host/manager
- DT: `qcom,dual-dsi-mode` + `qcom,master-dsi` + `qcom,sync-dual-dsi` en dsi0 (fase4-display.dts:320-324); dsi1 solo
  `dual-dsi-mode`. MGR:48-67 → `is_bonded_dsi = is_sync_needed = 1`, `master_dsi_link_id = DSI_0`.
- `msm_dsi_manager_cmd_xfer()` (MGR:495-547): `need_sync = IS_SYNC_NEEDED() && !is_read`. Si `id == DSI_0` **retorna len sin
  tocar el HW** (:517). Si `id == DSI_1`: `xfer_prepare(DSI_0)` (LP/HS en DSI_0, CMD_MODE_EN, DMA_DONE irq), `xfer_prepare(DSI_1)`,
  y `msm_dsi_host_cmd_tx(DSI_1)` construye el paquete en el `tx_gem` **de DSI_1**.
- `dsi_cmd_dma_tx()` (HOST:1563): `dsi_wait4video_eng_busy()` (con el vídeo ON espera VIDEO_DONE y después `usleep 2-4 ms`)
  → `msm_dsi_manager_cmd_xfer_trigger()` (MGR:550-565): `cmd_xfer_commit(DSI_0)` y luego `cmd_xfer_commit(DSI_1)`, cada uno
  `DMA_BASE`, `DMA_LEN`, `TRIG_DMA=1` (HOST:2550-2562). Se espera solo `dma_comp` de DSI_1 (200 ms).
- `CMD_DMA_CTRL`: HOST:912 lo escribe `FROM_FRAME_BUFFER|LOW_POWER` (0x14000000) y HOST:1289-1296 solo cambia bit26.
  **BROADCAST_EN (bit31, definido en dsi.xml:190) y bit30 no se escriben nunca.**
- `TRIG_CTRL` (HOST:917-925): TE + DMA_TRIGGER=SW + **BLOCK_DMA_WITHIN_FRAME** (6G ≥ v1.2) = `0x80001004`, frente al
  `0x80000004` del vendor. No hay programación por línea (`DMA_SCHEDULE_CTRL` no existe en mainline).
- Un paquete = una transferencia DMA (no hay lotes). `0x1CC` (VBIF_CTRL) y `0x50` (watermarks) no se tocan.
- Efecto secundario: las **lecturas por DSI_0** con sync nunca se disparan. `need_sync=false` (por `is_read`), pero
  `cmd_xfer_trigger(id=0)` retorna `false` → `dsi_cmd_dma_tx` devuelve `len` sin haber transmitido (MGR:556-557,
  HOST:1580-1604). Las lecturas por DSI_1 se envían a los **dos** links. Este punto vale para releer los resultados L65/L67/L68 del DSI_0.

### 3.2 Panel (PANEL)
- `o82_send_panel_cmds()` (:217-262), freq_sel/`11`/`29` (:478-490): `mipi_dsi_dual_dcs_write_buffer_multi(dsi[0], dsi[1])`
  (drm_mipi_dsi.c:1021-1030) = dos transfers, primero dsi[0] y luego dsi[1]. Con `need_sync`, el de dsi[0] es un no-op y el de dsi[1]
  hace los dos commits. PPS (:445-448 en prepare, :635-638 en enable) igual. Todo en LP (`MIPI_DSI_MODE_LPM`, :812),
  como el vendor. El dt lo elige el helper (0x05/0x15/0x39); el vendor manda 0x39 incluso con 1 byte (`11`, `29`): eso es C3 del plan.
- En nuestro árbol de diagnóstico, `msm_dsi_host_cmd_xfer_commit()` hace `pr_err("K50-commit")` **antes** de las escrituras
  (HOST:2555-2556). Entre el `TRIG_DMA` de DSI_0 y el de DSI_1 hay por tanto un printk completo, que con consola síncrona
  pueden ser de decenas de µs a ms.

---

## 4. Conclusión

**Hay diferencia real en la entrega, pero es de sincronía, no de contenido ni de modo:**

| Aspecto | Vendor | Mainline/nuestro | ¿Relevante? |
|---|---|---|---|
| Contenido por link | idéntico en los dos | idéntico en los dos (mismo buffer DSI_1) | no |
| LP/HS (init, 0x11, 0x29, PPS) | LP, vídeo OFF | LP. Con C2, vídeo OFF; hoy la PPS de `o82_enable` va con vídeo ON | C2 ya lo cubre |
| Simultaneidad | **broadcast HW**: un disparo del maestro arranca los 2 DMA (skew 0) | 2 disparos SW secuenciales: DSI_0 y luego DSI_1. Skew ≈ 3 escrituras MMIO (<1 µs) **+ el printk K50** | posible |
| Lotes | ≤240 B por ráfaga (LAST_COMMAND) | 1 paquete por DMA | improbable (el DDIC acepta cualquier hueco entre paquetes) |
| Programación DMA | por línea (VFP, 0x8ed) solo con vídeo ON | BLOCK_DMA_WITHIN_FRAME + espera SW de VIDEO_DONE | solo para DCS con vídeo ON |
| dt de 1 byte | 0x39 | 0x05 | C3 |

Un paquete DCS corto en LP (≈8 B a ~10 Mbit/s de LPDT + entrada/salida de escape) dura ~10-20 µs. Sin el printk, el skew de
mainline (<1 µs) deja los dos paquetes casi solapados. **Con** el printk K50, los paquetes pueden llegar al puerto B cuando el
puerto A ya ha terminado. ¿Puede importarle al DDIC dual-port (NT36532, TDDI Novatek)? Hay un argumento en contra con bastante
peso: el **NT36523 del Pad 5 (elish)** funciona en mainline con exactamente este mecanismo (`sync-dual-dsi` + envío dual
secuencial, `sm8250-xiaomi-elish-common.dtsi:608-610`). Un DDIC Novatek dual-port tolera triggers SW secuenciales.
Probabilidad de que esto sea **la** causa del negro: **baja** (≈10 %). El cambio, eso sí, es barato y elimina una variable
medida (REGDIFF fila 8 ya la marcaba como "no").

### Propuesta: **C6-SYNC — broadcast HW de comandos como el vendor**
(El plan ya usa "C6" para KTZ dual. Propongo renombrar aquel a C6-KTZ y llamar a este C6-SYNC.)

**HOST `dsi_host.c`**, dos helpers nuevos junto a `msm_dsi_host_cmd_xfer_commit()` (:2550), declarados en `dsi.h`:
```c
#define UKE_DSI_CMD_DMA_CTRL_BCAST_MASTER BIT(30) /* CAF kickoff_command: cmd->is_master */
void msm_dsi_host_cmd_xfer_setup(struct mipi_dsi_host *host, u32 dma_base, u32 len,
				 bool bcast, bool master)
{
	struct msm_dsi_host *msm_host = to_msm_dsi_host(host);
	u32 d = dsi_read(msm_host, REG_DSI_CMD_DMA_CTRL);

	d &= ~(DSI_CMD_DMA_CTRL_BROADCAST_EN | UKE_DSI_CMD_DMA_CTRL_BCAST_MASTER);
	if (bcast)
		d |= DSI_CMD_DMA_CTRL_BROADCAST_EN;
	if (bcast && master)
		d |= UKE_DSI_CMD_DMA_CTRL_BCAST_MASTER;
	dsi_write(msm_host, REG_DSI_CMD_DMA_CTRL, d);	/* LP bit26 ya puesto por xfer_prepare */
	dsi_write(msm_host, REG_DSI_DMA_BASE, dma_base);
	dsi_write(msm_host, REG_DSI_DMA_LEN, len);
	wmb();
}
void msm_dsi_host_cmd_xfer_kick(struct mipi_dsi_host *host)
{
	dsi_write(to_msm_dsi_host(host), REG_DSI_TRIG_DMA, 1);
	wmb();
}
```
En `msm_dsi_host_xfer_restore()` (:2386) hay que limpiar bits 31/30 de `CMD_DMA_CTRL`, para que las lecturas unicast no hereden el broadcast.

**MGR `dsi_manager.c`**: añadir `bool hw_bcast` a `struct msm_dsi_manager`. En `msm_dsi_manager_cmd_xfer()` hay que poner
`msm_dsim_glb.hw_bcast = need_sync;` antes de `msm_dsi_host_cmd_tx()` y `= false` después. En `msm_dsi_manager_cmd_xfer_trigger()`
(:550) el par de commits se sustituye por:
```c
	if (IS_SYNC_NEEDED() && msm_dsi0 && msm_dsim_glb.hw_bcast) {
		struct mipi_dsi_host *m = msm_dsi0->host;	/* DSI_0 = qcom,master-dsi (vendor cmd_master_idx 0) */
		msm_dsi_host_cmd_xfer_setup(m,    dma_base, len, true, true);	/* 0x38 = 0xd4000000 (LP) */
		msm_dsi_host_cmd_xfer_setup(host, dma_base, len, true, false);	/* 0x38 = 0x94000000 (LP) */
		msm_dsi_host_cmd_xfer_kick(host);	/* esclavo: arma (TRACE: ctrl1 trigger primero) */
		msm_dsi_host_cmd_xfer_kick(m);		/* maestro: dispara los dos */
		pr_info_once("UKE-L76-C6: bcast HW m=0x%08x s=0x%08x\n", ...readback 0x38 de ambos...);
		return true;
	}
	/* resto: camino original (lecturas) */
```
La espera se queda en `dma_comp` de DSI_1. El vendor demuestra que el esclavo también da DMA_DONE (`clear_dma_status 0x2000001`).
Hay que **quitar los `pr_err` K50** de `msm_dsi_host_cmd_xfer_commit()`/`dsi_cmd_dma_tx()`/`cmd_xfer()`, porque ensanchan el skew.
Gate: `UKE-L76-C6: bcast HW m=0xd4000000 s=0x94000000` y ningún `CMD_DMA_DONE timeout`. Si aparece un timeout, la causa es
el broadcast (falta el disparo del maestro o el orden está invertido) y hay que revertir C6.

**Opcionales (no en L76):**
- **C6b**: `TRIG_CTRL` sin BLOCK_DMA_WITHIN_FRAME (HOST:923-924) = `0x80000004`, para paridad. Solo con C2 en su sitio
  (todos los DCS con el vídeo OFF).
- **C6c**: `DMA_SCHEDULE_CTRL` (físico 0x100 = mainline 0xfc) `= BIT(28) | (vbp+vsw+vact+1)` antes del disparo cuando el vídeo esté ON,
  y 0 después. Solo hace falta para DCS en HS con vídeo (cambio de timing), no para el arranque.

**Empaquetado:** C6-SYNC es independiente de C1/C2/C3 y solo afecta a la entrega de DCS/PPS. Lo recomiendo en **L77**, o en L76
si el dueño quiere la paridad máxima de una vez, porque lleva gate propio y un modo de fallo claro: el timeout DMA.

---

## 5. Resumen (≤300 palabras)

**Flags.** cflags: 0x1 READ, 0x2 BROADCAST, 0x4 BROADCAST_MASTER, 0x8 DEFER_TRIGGER, 0x10 FIFO_STORE, 0x20 FETCH_MEMORY,
0x40 LAST_COMMAND, 0x80 NON_EMBEDDED, 0x100 CUSTOM_DMA_SCHED, 0x200 ASYNC_WAIT. 0x12e/0x12a = broadcast con disparo diferido
(maestro/esclavo), y 0x16x es el último de un lote. mflags: 0x02 = USE_LPM (bit26 de CMD_DMA_CTRL), 0x40 = BATCH (sin
LAST_COMMAND: el paquete se acumula en un buffer DMA compartido y el vendor parte el lote al llegar a 240 B, visible en el kprobe).
`qcom,cmd-sync-wait-broadcast` solo afecta a las lecturas ESD.

**Vendor.** Es broadcast **hardware**. Los dos ctrl programan su DMA con la misma dirección y longitud, con BROADCAST_EN
(bit31) y, solo en dsi0, BROADCAST_MASTER (bit30): reposo 0xd0000000 en dsi0 y 0x90000000 en dsi1. El esclavo se arma con
TRIG_DMA y el **disparo del maestro arranca los dos** a la vez. Init, 0x11, 0x29 y PPS van en LP y con el vídeo OFF. Con el
vídeo ON, los DCS en HS se retienen hasta la línea 0x8ed (la primera del VFP) mediante DMA_SCHEDULE_CTRL (0x100). TRIG_CTRL es
0x80000004, sin BLOCK_DMA_WITHIN_FRAME.

**Mainline.** `sync-dual-dsi` convierte el transfer de DSI_0 en un no-op. Después se escriben dos TRIG_DMA software
secuenciales, DSI_0 y luego DSI_1, con skew <1 µs. En nuestro árbol se añade un `pr_err` K50 entre los dos. No se usa
BROADCAST_EN, cada paquete es un DMA y se pone BLOCK_DMA_WITHIN_FRAME. El panel usa el helper dual (dsi[0] y luego dsi[1]).
Efecto secundario: las lecturas por DSI_0 nunca se disparan.

**Conclusión.** Contenido, LP y orden coinciden. La diferencia está en la simultaneidad (hardware frente a software) y en los
lotes. Es poco probable que sea la causa del negro (≈10 %): el NT36523 de elish funciona en mainline con ese mismo esquema
secuencial. Aun así es una paridad barata. **C6-SYNC**: helpers `msm_dsi_host_cmd_xfer_setup/kick` en dsi_host.c;
`msm_dsi_manager_cmd_xfer_trigger()` programa los dos links (bit31 y, en DSI_0, bit30), dispara primero el esclavo DSI_1 y
después el maestro DSI_0; se limpian los bits en `xfer_restore` y se quitan los printk K50. Gate
`UKE-L76-C6 m=0xd4000000 s=0x94000000`. Recomendado en L77, o en L76 con su gate.
