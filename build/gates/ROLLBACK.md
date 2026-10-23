# ROLLBACK F5 — manual de vuelta atrás, en orden de ejecución

Principio: **el slot `a` es Ubuntu gracias a B1 y el seguro está en el PC.**
Cada sección dice CUÁNDO usarla, los comandos exactos y cómo verificar.
Verificado contra `LECCIONES.md`/`REFUTADO.md` del hermano (notas de compatibilidad
entre paréntesis). Nada de lo aquí escrito contradice una lección pagada.

## 0. Antes de cualquier rollback: no empeorar

- Consola ACM capturando (un solo lector) + `dmesg -w` por SSH a fichero si hay SSH
  (doble captura obligatoria, regla 4).
- `sync` antes de cualquier `sysrq-b`/`reboot`; `/tmp` es tmpfs: las imágenes van a
  `/root`, no a `/tmp` (regla 5).
- Prohibido `reboot -f` y `systemctl reboot` sin `sync` previo (regla 5).

## 1. Rollback PARCIAL (falla el boot.img Arch, el rootfs está bien o da igual)

Cuándo: tras B4 la tablet no llega a SSH en 90 s, o llega pero Arch no levanta
(`switch_root` fallido, systemd muerto) y se quiere volver a lo conocido.

```bash
# Desde el PC, tablet en fastboot (forzar con Power 15-20 s si cuelga; R-42: sin watchdog no hay auto-reset):
fastboot set_active a          # el boot.img s244 de Ubuntu, puesto en B1
fastboot getvar slot-retry-count:a   # registrar en el ledger
fastboot reboot
# Verificación: SSH <60 s + uname -r = 7.2.0-rc2-palawan+ + hostname de Ubuntu.
```

Solo se usa `fastboot set_active` para cambiar de slot (R1/R11; el brick del
11-sep-2026 fue por editar attrs GPT con `dd` — REFUTADO R-13/B-03).
Coste: 0 escrituras, ~2 min. El `boot_b` Arch queda intacto para reintentar otro día.

## 2. Rollback TOTAL (el rootfs Arch quedó mal y se quiere Ubuntu de vuelta)

Cuándo: B3 dejó `userdata` a medias/corrupto, o Arch monta pero es inservible y se
abandona F5 por hoy. Requiere que la tablet arranque Ubuntu del slot `a` (sección 1)
o al menos llegue a un shell con red USB.

```bash
# 1) volver al slot a (sección 1) y esperar SSH.
# 2) en el PC, servir el seguro:
cd ~/gpu-work/ramaa/s22 && sha256sum rootfs.img.gz   # debe dar b6d5411712b…
setsid nohup python3 -m http.server 8000 --bind 192.168.42.1 &
# 3) en la tablet por SSH (canal uke-fase2-install.py, ya funcionó):
P=/dev/disk/by-partlabel/userdata
[ -b "$P" ] || { echo "ABORT"; exit 1; }
head -c4 "$P" | od -An -tx1 | tr -d ' \n' | grep -qi '^ef53' || echo "AVISO: destino sin magia ext4 (esperable si B3 quedó a medias); se sigue"
sync
busybox wget -O - http://192.168.42.1:8000/rootfs.img.gz \
  | busybox zcat | busybox dd of="$P" bs=4M conv=fsync; echo "DD-RC=$?"
sync
# 4) verificación estricta (SIN noload: la corrupción recién escrita debe verse):
mount -t ext4 -o ro "$P" /mnt/x && ls -l /mnt/x/sbin/init /mnt/x/etc/hostname && umount /mnt/x && sync
# 5) reboot y SSH: Ubuntu de vuelta. Registrar mV final y slots en el ledger.
```

Tiempo: ~10 min (353 MiB por RNDIS). No gasta reintentos de slot.

## 3. Caso peor: NO arranca ningún slot (fastboot sí responde)

Cuándo: ambos slots agotados o `boot_a`/`boot_b` inválidos, pero `fastboot devices`
ve la tablet. **El ABL es intocable y sigue vivo** (nunca se flashea `abl_*`,
`vbmeta` ni `vendor_boot_*`): mientras haya fastboot, hay salida.

```bash
# a) Arrancar SIN ESCRIBIR por RAM (no gasta slots, no toca flash):
timeout 90 fastboot boot ~/gpu-work/ramaa/s21/avb/boot-s244-bounce.img
# Matiz R-12: 'fastboot boot' usa el DTBO DEL SLOT ACTIVO. Exigir current-slot=b
# (s229, el bueno) con 'fastboot getvar current-slot' antes; si está en a, el arranque
# llevará el DT stock y un fallo NO dice nada del kernel. Techo ~64 MiB sin fuente
# primaria: si rechaza la imagen, no concluir que el kernel no arranca.
# b) Una vez dentro por RAM (SSH/gadget), restaurar por el canal SSH:
#    - re-dd del rootfs Ubuntu (sección 2, pasos 2-4), y/o
#    - dd del boot bueno leído por contenido: dd if=/root/<img> of=/dev/disk/by-partlabel/boot_b
#      + lectura de vuelta con 'head -c <bytes-exactos>' para anular el pad de 96 MB (patrón #241),
#    - 'fastboot set_active a/b' + reboot.
# c) Si 'fastboot boot' también falla: existe el boot shell por RAM de rescate
#    (avb/boot-s136-rescue.img y s137-selfrecovery) como último recurso antes de parar.
```

Si NI fastboot responde (sin USB, sin consola): **parar**. Es territorio del brick del
11-sep (GPT): no improvisar `dd` sobre particiones de bootloader. Escalar al dueño con
la consola capturada hasta el final.

## 4. Tablet en fastboot SIN carga (el caso lento)

Hechos medidos: en fastboot la tablet NO carga (3.451→3.411 mV medido; entrada capada
a SDP 100-500 mA, B riesgo 17). Umbral GO: **≥ 3700 mV**.

```bash
fastboot getvar battery-voltage   # registrar; si < 3700 mV, STOP de escrituras
```

Qué hacer: **no flashear**; dejar la tablet APAGADA (no en fastboot: en fastboot
descarga) con **cargador de pared** (no USB de PC) hasta recuperar tensión; UFS a
Gear 1 con batería baja ⇒ lecturas/flash poco fiables (B riesgo 18). Solo lectura
(`getvar`) hasta volver a ≥ 3700 mV. Registrar mV inicial y final en cada fila.

## 5. Qué NO hacer NUNCA (cada línea costó un ciclo o un brick)

1. **`vbmeta` no se toca** (REFUTADO R-01: aparato unlocked, verificación ya salta sola).
2. **`vendor_boot_b` no se toca** (ledger #238: sustituirlo mató el arranque; su
   `/init` stock es el que hace que se use nuestro `rdinit`).
3. **Attrs GPT no se editan con `dd`** (brick 11-sep-2026; solo `fastboot set_active`).
4. **`dtbo_b` no se toca en F5** (es el `s229`; `fastboot boot` lo reutiliza por R-12).
5. **Un cambio por ciclo + fila pre-registrada** (dos sesiones en paralelo ya se
   pisaron: ledger #232/#233/#234, riesgo R30).
6. **No borrar la blacklist de ath11k sin restaurarla** (`uke-wifi-trace.sh:46` la
   borra ⇒ autocarga por modalias ⇒ gasta reintentos; ledger #441).
7. **No instrumentar SMMU en runtime ni volcar MMIO/regmap** (cuelga; regla 3).
8. **No usar `swiotlb=force`** (mata el mapeo MSI de ath11k; B §5.4) ni quitar `mem=`
   sin decisión D16.
9. **No borrar `~/gpu-work/ramaa/s22/rootfs.img.gz`** hasta cerrar F5 (es el seguro).
10. **≤ 2 escrituras/día**; si `slot-retry-count:b` < 3, solo lectura.
