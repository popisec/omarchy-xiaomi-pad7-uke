# NOTA — initramfs k22b (volcador arreglado) para el próximo repack (14-oct-2026)

> Hecho tras #620. El initramfs embebido en los boot.img es `uke-k22-initramfs.cpio.gz`
> (`08780e35…`) y su `ukeinit` **sí lanza** `/dump-log.sh` (cada 15 s × 80, en background),
> pero el `dump-log.sh` traía `P=/dev/sda30` **hardcoded** y en el initramfs la UFS enumera
> **sdb30 = rescue** (en el sistema vivo es sda30; el orden se invierte entre initramfs y
> sistema — medido 13-oct y hoy). Resultado: 0 dumps desde el initramfs en los boots recientes.

## Artefacto nuevo

- `build/init/uke-k22b-initramfs.cpio.gz`
  sha256 `fa40a1bbd331157ea9f28c5f211d8268103567850eeec944c36228a1c2f2a113` (1013984 B).
- Contenido: idéntico al k22 salvo `dump-log.sh` (ahora con resolución por PARTLABEL +
  fallback por existencia sda30/sdb30; el `blkid`/`findfs` no existen en el busybox del
  initramfs, pero el fallback `[ -e /dev/sdX30 ]` cubre ambos casos).
- Verificado: extraído de nuevo, 42 ficheros, `ukeinit` byte-idéntico, sintaxis OK.

## Cambios para el próximo clon de repack

1. `K13_INITRAMFS = R + "/build/init/uke-k22b-initramfs.cpio.gz"`
   y `K13_INITRAMFS_SHA = "fa40a1bbd331157ea9f28c5f211d8268103567850eeec944c36228a1c2f2a113"`.
2. El gate de initramfs del repack (G3: «initramfs embebido byte-idéntico al del k52b2»)
   pasa a comparar contra el **k22b** (la referencia cambia: el byte-idéntico ya no aplica
   al k52b2).
3. Fuente del script arreglado: `build/gates/dump-log.sh` (con el FIX 14-oct; ya commiteado).

## Nota de alcance

El volcador del initramfs cubre la ventana temprana (0–20 min, cada 15 s) y escribe
`forklog.txt` + `forklog-<uptime>.txt` (rolling 25) en **rescue**. Para la ventana post-
switch_root (los crashes display-ON) hay además el **volcador del sistema** (`uke-dump`,
LOGFS, cada 20 s, instalado en la tablet el 14-oct). Entre los dos, la ventana completa.
