# C5b ciclo 14 — plan (preparado 22-oct-2026 sin ejecutar; orden del dueño: «sí» a preparar la instrumentación que pidió la revisión independiente)
Motivo (`docs/historia/revision/CAMARAS-REVISION-SUBAGENTES-20261022.md`): hasta ahora (a) todos los contadores del RX cubren solo los primeros 400 IRQ (~13 ms) de un stream que dura hasta 12 s, (b) no hay volcado al parar (`head -6` lo cortaba), (c) el único buffer de 4118400 B no se guardó ni se verificó, y (d) los log por IRQ en el ISR eran un riesgo (M1). Este ciclo corrige las cuatro cosas. **Hipótesis a decidir**: H2 (ECC del CSID con otro orden de bits/lane que el sensor), H1 (contador cuenta correcciones), H4 (`long0` latcheado), y qué distingue un stream que devuelve buffer de uno que no.
Ejecutar requiere orden del dueño para ESTE ciclo + «tuya». `build/rootfs/deploy/camaras/c5-ciclo14.sh --check | --go`; módulos nuevos `out-ciclo14/` (ouke5, 0 avisos, `--check` OK). Sin flash ni reinicio, ~9 min, batería ≥ 30 %, ACM lector único, doble captura.

## Cambios de código (CSID gen3 de `uke-camss`; por defecto sin efecto)
- `uke_stat=1`: cuenta **por bit todas las IRQ de RX y de RDI0 durante TODO el stream** (sin printk en el ISR; contadores en memoria) y las vuelca **en una línea al parar** (`uke-stat0: t=… rx_irq=… rdi_irq=… primer_SOF=…ms(rx_irq=…) RX[ b0:… b4:… ] RDI0[ b4:… b12:… ]`). Reset al arrancar. El tiempo del **primer SOF** (RDI bit 12) y el nº de IRQ de RX hasta entonces quedan registrados.
- Con `uke_cap_ctrl=0x2b3`: volcado de los 8 registros de captura (`uke-cap0 sof` en el primer SOF y `uke-cap0 stop` al parar; hasta ahora el `stop` no se veía).
- Al parar, **se enmascaran RX y RDI0** (revisión B4). Presupuestos de log en 0 (sin `dev_info` por IRQ).
## Matriz (42 streams, `0x4800` escrito antes de `MODE_SELECT`; imagen normal)
- 2104×1560: 10 rondas de (0x7e, 0x76, 0x74) + 6 rondas extra de 0x7e = 36 streams, intercalados para no confundir deriva con configuración.
- 4208×3120 (modo de Android; WC esperado **0x1068 = 4208·10/8 = 5260**; si `long0` cambia de 0x0a46 a 0x1068, `long0` sigue al modo ⇒ **descarta H4**): 6 streams con 0x7e.
- Cada stream: timeout 10 s; se imprime `uke-stat0`, `uke-cap0 sof/stop` y `BUF` con **bytes, bytes no nulos y sha256** del buffer. Se guardan hasta **6 buffers** como `/root/b14-N.raw` → `out/b14-N.raw` (no versionados: son imágenes del sensor del dueño).
## Cómo se lee (pre-registrado)
- **Buffer con contenido**: `nonzero` ≈ `bytes` y, en el PC, `raw10-to-png.py` da una imagen reconocible ⇒ PASS parcial real (hito de frame validado). `nonzero`≈0 o sha repetido entre buffers ⇒ el buffer se devolvió vacío: la cadena de memoria no recibe datos y se descarta el «frame».
- **Qué distingue un stream que devuelve buffer**: comparar su `uke-stat0` (cuentas de bits 4–7 SOT, 20 ECC, 14 WARNING_ECC, 23 underflow, y RDI0 b4/b12/b3 SOF/EOF, `primer_SOF`) con los demás durante el stream completo; buscar un bit RDI0 (p. ej. EOF b3/b9) que solo aparezca en los que devuelven buffer.
- **H1 vs H2**: correlar `b14` (WARNING_ECC) y `b20` (ECC) con `ecc alta/baja` de `uke-cap0 stop`: si `b20 ≈ ecc alta` en todo el stream ⇒ el contador cuenta errores; si `b14 ≈ ecc baja` ⇒ la mitad baja son correcciones.
- **Tasa**: n de buffers con 0x7e/0x76/0x74 sobre 16/10/10 streams (el ciclo 12/13 dio 1/17 con 0x7e). Con ≥ 3 buffers se puede comparar configuraciones; con 0–1, solo se descarta que 0x76/0x74 mejoren.
- **Abortar**: Oops/SMMU, batería < 30 %, `dmesg -w` sin crecer, o `capctrl` ≠ 0x2b3 en `uke-cap0`.
