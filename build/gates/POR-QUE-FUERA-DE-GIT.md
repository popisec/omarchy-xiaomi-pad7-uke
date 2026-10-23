# Por qué estos artefactos están fuera de git

Política del proyecto (.gitignore, línea 1): **"Artefactos grandes o
derivados: fuera de git. Git lleva el CÓDIGO y los INFORMES"**.
Lo que sigue son DERIVADOS: cada uno se regenera con un comando conocido
a partir de una fuente versionada o del dispositivo. El sha manda, no el
fichero. Los shas también están en `build/gates/SHA-BUENOS.txt`.

## Los dos grandes (100663296 B cada uno, salidos del índice el 28-sep-2026)

| Fichero | sha256 | Tamaño |
|---|---|---|
| `build/bootimg/boot-pokes.img` | `530a0ef62111e817e90f87520529f8f8ea141146642b99a47e8c611cdc2fdcd2` | 100663296 B |
| `build/backup-par-bueno/boot_b-lee.img` | `ffff8c51265ff03c84cff15ffdb275f396a666a491eb5d67580be705321db99e` | 100663296 B |

El commit 946fb93 los metió en git por error (~200 MB de blobs).
Se sacaron del índice con `git rm --cached` (siguen en disco).
También salieron del índice los `s23x/s25x-boot-dtbo-*.img`,
`boot-arch-diag.img` y los `build/logs/*.log` (spam de compilador).

## Cómo se regeneran

**`boot-pokes.img`** — reempaquetado del boot bueno con el kernel de pokes:

    python3 docs/historia/gates-palawan/repack-boot-pokes.py

El script parte de `build/backup-par-bueno/boot_b-lee.img` (gate G0 exige
su sha `ffff8c51…99e`) y del kernel compilado en
`build/kernel-pokes/arch/arm64/boot/Image`, y publica el sha resultante.
El kernel se recompila con `build/gates/build-pokes.sh` (desprendido,
`MAKE=/usr/bin/make`, `ARCH=arm64`, `LLVM=1`, O propio; el parche lo pone
`build/gates/patch-uke-smmu-pokes.py`).

**`boot_b-lee.img`** — backup del `boot_b` bueno, se vuelve a leer de la
tablet por SSH y se verifica al tamaño exacto (96 MiB = 100663296 B) para
anular el pad de ceros (patrón ledger #241):

    ssh <tablet> 'dd if=/dev/disk/by-partlabel/boot_b bs=1M' \
      | head -c 100663296 > build/backup-par-bueno/boot_b-lee.img
    head -c 100663296 build/backup-par-bueno/boot_b-lee.img | sha256sum
    # esperado: ffff8c51265ff03c84cff15ffdb275f396a666a491eb5d67580be705321db99e

## Por qué el historial conserva los 200 MB y no se reescribe

docs/historia/AGENTS.md: "esta carpeta es la ÚNICA copia" de todo el trabajo. Reescribir
el historial (filter-branch / filter-repo / rebase) sobre la única copia
es más peligroso que el problema: si algo sale mal, se pierde el registro.
Los blobs quedan en el historial del commit 946fb93 y anteriores, pero el
índice ya no los lleva y el `.gitignore` impide que vuelvan a entrar.
`.git` no volverá a crecer por esta vía; el tamaño actual (~460 MB) es el
techo, no el suelo.
