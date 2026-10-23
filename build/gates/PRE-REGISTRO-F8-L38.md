# PRE-REGISTRO F8/L38 — 13-oct · **reset del panel a los 15 ms del vendor**

## La variable

Una línea en `o82_reset()` (`panel-xiaomi-o82-dualdsi.c:293`):

```c
- usleep_range(100000, 101000);   /* r7: 15->100ms, discriminador temporal */
+ usleep_range(15000, 15100);
```

Más corregir el log mentiroso (`release2(15ms)` mientras dormía 100 ms).

## Por qué esta

El vendor (`dsi_panel_reset`, `.ko` texto+`0x155ed8`) usa la secuencia del DT de Android
`(0,10),(1,3),(0,3),(1,15)` con `usleep_range_state(ms*1000, …, TASK_UNINTERRUPTIBLE)`.
**El último release son 15 ms.** Los tres primeros sleeps ya coincidían.

El 100 ms era el **"discriminador temporal" de la ronda r7**: un valor inventado para medir
dónde moría, que se quedó en el árbol y hoy está **en el camino del fallo**: el SoC muere en
`K48-w4-done`, justo antes de este sleep. Ese sleep es el que **saca el panel de reset**;
con 100 ms el panel pasa ese tiempo despierto y luego le llega el resto de golpe.

Todo lo demás de la secuencia audita **idéntico** (pin TLMM, niveles físicos, gpios,
reguladores, PHY antes del reset, LP11). Es la única divergencia del vendor.

## Advertencia honesta de atribución

L38 = L37 (PPS) + reset a 15 ms. **Son dos cambios respecto a L36.** Pero las PPS **nunca
se ejecutaron** en L37 (el SoC muere antes, en el reset), así que el reset es la **única
variable efectiva** del ciclo. Si L38 sobrevive y la pantalla se enciende, no sabremos si
fue el reset o también las PPS — y no hace falta saberlo: las PPS hacen falta igualmente.
Si sobrevive y **no** hay imagen, entonces el reset era el bloqueo y las PPS son el siguiente
freno.

## Artefacto

- **sha256**: `338d921cb6203a65938d6fd598186c1ceb9fc3e63cab8b238b7ce0e75e03ba73`
- Kernel: `a159c8d7e20c5589987da70e75f8bf204c3beb4ef24833427928943d7c61b7ae`
- Cmdline: 585 B, **idéntica a L37** (`systemd.mask=sddm`, sin `video=`)
- Gates: reset a 15 ms (marca x1), PPS pack/send/done x1, early-return de L36 dentro
  (cadena x0), fbdev ausente, UKE-POKE 113 / K47- 27 intactas

## Doble captura obligatoria

1. Lector ACM **antes** del reboot.
2. `dmesg` por SSH + watcher v2. **Segregar los ficheros por boot** antes de comparar
   (el turno pasado mezclé ficheros de tres arranques distintos).
3. Trigger con `monitor=DSI-1,preferred` (**no inventar frecuencia**; el panel declara
   120/144 Hz, y en L35/L36 forcé 60, que no existe).

## Tabla de lectura

| Resultado | Lectura |
|---|---|
| **Sobrevive y el panel se enciende** | Reset era el bloqueo + PPS修正. Pantalla |
| Sobrevive pero sin imagen | El reset era el bloqueo; ahora el freno es otro (orden del motor, máscara de error) |
| Sigue muriendo en `K48-w4-done` | Los 15 ms no son la causa ⇒ ACS pierde líneas y el punto real es otro |
