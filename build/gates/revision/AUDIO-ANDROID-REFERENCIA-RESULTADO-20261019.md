# AUDIO — referencia de Android: **encontrada la causa probable del silencio: los registros del PLL de los FS19xx** — 19-oct-2026 11:23

Captura hecha en Android HyperOS (slot b, root Magisk, adb) con el dueño reproduciendo sonido por los altavoces. Android no tiene `i2c-dev`, pero sí **tracefs con eventos `i2c`**: `audio-ref-trace.sh` registró todas las transacciones del bus 4 (los 4 FS19xx 0x34-0x37) durante ~59 s. Datos en `build/android/audio-ref-20261019/` (`trace/20-trace.txt`, `android-fs19xx-sequence.txt`).

## Secuencia del driver vendor al arrancar/parar el altavoz (idéntica en los 4 amps, MEDIDO)
Arranque (≈ 45 ms): `R 0x14 → 0x0204` (try_init: ya configurado, **no** repite reg_init) · `R 0x17 → 0x980b` · `R 0x04 → 0x00a3` · `W 0x17 ← 0x980b` · `W 0x0b ← 0xca91` (clave) · **`W 0xa1 ← 0x0260` · `W 0xa2 ← 0x0540` · `W 0xa3 ← 0x0018`** · `W 0x0b ← 0x0000` · `W 0x11 ← 0x00ef` · `W 0x10 ← 0x0000` · `W 0x16 ← 0xf3c0` (volumen 243) · `W 0x30 ← 0x0210` · `R 0x4c → 0x76ab` ×2 (bit 3 ya a 1: sin escritura).
Parada: `R 0x14` · `W 0x30 ← 0x0310` · `W 0x10 ← 0x0001` · (35 ms) · `W 0x11 ← 0x0000`.

## La diferencia con lo que escribía nuestro driver
Nuestro driver escribía en el PLL (a 6,144 MHz) **`A1=0xC000, A2=0x005D, A3=0x0260`**; Android escribe **`A1=0x0260, A2=0x0540, A3=0x0018`**. La causa: la tabla del vendor (`g_fs19xx_pll_tbl`, 12 B por entrada) tiene el valor útil en las palabras **[2],[3],[4]**, no en [0],[1],[2]; el RE leyó con un desplazamiento equivocado (la dirección `UNK_001024d4` del decompilado de `fs19xx_start_up` apuntaba 4 bytes más adentro que el inicio de la tabla). **Con el PLL de los amps mal configurado, aunque el BCLK llegara y los registros de estado cambiaran, la ruta de audio interna del amp no podía funcionar: es la explicación más simple de todo el silencio medido** (reloj detectado + amps «habilitados» + 0 sonido a cualquier nivel/formato/carril).
El resto de la secuencia coincide con la nuestra (orden de 0x17/clave/PLL/0x11/0x10/0x16/0x30; el volumen lo escribíamos antes de 0x10 por seguridad; `0x4c` sin escritura al coincidir el bit 3).

## Correcciones aplicadas en el PC (compiladas; sin desplegar: la tablet está en Android)
- `fs19xx/uke_fs19xx.c`: tabla PLL con las palabras [2],[3],[4] de cada entrada (**solo la fila de 6,144 MHz está verificada** contra Android: `0260/0540/0018`; las demás se derivan con el mismo desplazamiento) y `try_init` como el vendor (lee `0x14`; solo repite `reg_init` si no vale `re25<<1`). `.ko` nuevo en `out/` (sha `09b2eb74…`).
## Siguiente
1. **Volver a Linux** cuando las sesiones BT y lápiz den su «listo» (batería ya lo dio): `backup-userdata.sh --restore-plan` → `flash userdata` (copia verificada `6bd9c632…`), `set_active a`, reboot, `misc` si hace falta (fila #665-#666; manos del dueño en fastboot).
2. En Linux: desplegar `uke_fs19xx.ko` corregido y repetir el tono (vol bajo, −18 dBFS): **debería sonar**. Después, quitar los topes de prueba y dar un volumen/ruta razonables (`FSM_Scene` 0, vol 243 como Android).
