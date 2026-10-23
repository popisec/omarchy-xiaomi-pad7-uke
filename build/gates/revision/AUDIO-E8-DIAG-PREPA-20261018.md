# AUDIO — E8 diagnóstico del silencio: lectura de registros de los 4 FS19xx preparada en el PC — 18-oct-2026

**No se tocó la tablet en esta etapa.** Situación medida: con `uke_fs_play=1` los 4 amps se habilitan y paran con rc 0 (sin errores I²C), el WAV de 1 kHz a −40 dBFS sale por el TDM y el dueño **no oye nada** con vol 0x20 ni con 0x40.

## Qué hay (solo lectura)
- `fs19xx/uke_fs19xx.c` (nuevo `out/uke_fs19xx.ko`, sha `48e399ff…`): archivo **debugfs** `/sys/kernel/debug/uke_fs19xx/regs` que, al leerlo, hace **lecturas I²C** (nada de escrituras, ni clave 0xCA91) de 0x00-0x1F y de los registros usados por reg_init/start_up (0x20-0x22, 0x24, 0x29, 0x30, 0x39, 0x3A, 0x3C, 0x41, 0x45-0x4C, 0x5F) de cada amp, más `on/inited/mask/pos`. Se puede leer con los amps en marcha.
- `fs19xx/diag.sh` (se ejecuta en la tablet): vuelca (1) en reposo, (2) a mitad de un PCM de silencio con `uke_fs_play=1`, vol 0x20, (3) tras parar. Cambia solo `uke_fs_vol`/`uke_fs_play` (restaura `N`), el mezclador y `aplay /dev/zero` 5 s.
- Rutas del vendor usadas como guía: `fsm_reg_dump` (misma ventana de registros).

## Hipótesis de por qué no suena (INFERIDO, a contrastar con el volcado)
1. **Volumen demasiado bajo (la más probable).** El registro de volumen es de 8 bit y Android usa **235-243** (de 255). Si el paso es de 0,5 dB, 0x40 son ≈ −95 dB y 0x20 ≈ −110 dB: inaudible con un tono a −40 dBFS. El tope actual `uke_fs_volmax=0x80` (≈ −64 dB) tampoco bastaría. Los registros de volumen (0x16) y de estado dirán el valor real aplicado.
2. **Slots TDM.** `info[16]` (posición) vale 8/2/4/1 en 0x34/0x35/0x36/0x37: parece un *one-hot* de slot (3,1,2,0). Con PCM de 2 canales el ADSP solo llena los slots 0-1 (`slot_mask = 0x3`), por lo que solo 0x37 y 0x35 recibirían datos, y solo si el preset programa esa selección (no verificado). No explicaría el silencio total por sí sola.
3. **Línea de datos.** El ACDB da `data_oe = 1` (¿solo SD0/gpio8?) y el DT usa gpio8 y gpio9: los amps podrían colgar de ambas líneas.
4. Detección de reloj/PLL: el estado de los registros 0x00-0x0F tras `start_up` (bits de bloqueo del PLL, I²S) lo dirá.
5. Mapa de escena/0x4C, o amplificador protegido a la espera de `FSADSP`.

## Procedimiento propuesto (autorización del dueño; vigía + doble captura; ACM un lector)
- **D-0** Cambiar el módulo sin reiniciar: `rmmod uke_audio_e8b` (último overlay; ~15 s por los timeouts del APM, medido), `rmmod uke_fs19xx`, copiar el `.ko` nuevo a `extra/`, `depmod`, `modprobe uke_fs19xx` (autocarga; DEVID ×4 como siempre), `insmod uke_audio_e8b`.
- **D-1** `bash -s < fs19xx/diag.sh`. Se aborta ante error I²C, calor o ruido anormal.
- **D-2** Con los datos: decidir una **escalera de volumen** (p. ej. 0x80 → 0xA0 → 0xC0 → 0xE0) con el WAV de −40 dBFS, ≤ 3 s por escalón, subiendo el tope `uke_fs_volmax` solo con la autorización expresa del dueño (riesgo físico: sin FSADSP ni monitor térmico).
Reversa: `uke_fs_play=N`; descargar como arriba; pines: solo reiniciando.

## Riesgos
Lectura de registros de estado: riesgo mínimo (el vendor los lee en su monitor). Posible efecto «limpiar al leer» en algún registro de estado del amp (no documentado): sin consecuencias para esta prueba. El cambio de módulo implica retirar y cargar de nuevo la tarjeta e8b (cierre del grafo del ADSP con 3 timeouts de 5 s, medido sin oops). La sesión BT puede suspender/reiniciar la tablet: coordinar.
