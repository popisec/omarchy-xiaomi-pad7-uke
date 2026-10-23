# kernel-config — un `.config` por kernel, no por intento

Cada kernel que se compiló dejó su `.config` aquí. **74 ficheros, pero solo 17
contenidos distintos**: muchas compilaciones no cambiaron nada de la
configuración, así que sus `.config` son copia byte a byte del anterior.

El único que **no** es del linaje histórico es `senemos-ouke5.config`: es la
config del kernel vigente (§Kernel de `HARDWARE.md`).

Los duplicados están como **symlinks** al fichero canónico, para que:

- Los scripts que los referencian por nombre (`docs/historia/gates-palawan/build-k23b.sh` →
  `build/kernel-config/k23b.config`) sigan funcionando sin cambios.
- No se repitan 14 MB de texto idéntico en cada clon.
- Se vea de un vistazo qué kernels comparten configuración.

## Tabla de equivalencias

| Contenido (sha256 corto) | Ficheros | Canonónico | Qué es |
|---|---|---|---|
| `652b926d29a5` | 19 | `k52L0-bateria.config` | Config de **batería** de la serie k52L: `k52L0..k52L16` (incluye `k52L16-chipid`) |
| `ede19fdc6ee1` | 16 | `k52L76r.config` | Config de la serie k52L58→k52L77b. **Ojo: `k52L77b.config` (el último) es idéntico a `k52L58.config`**: desde k52L58 hasta k52L77b no cambió ni una línea de la config |
| `c57849f09813` | 10 | `k47-pantalla.config` | Config de **pantalla**: `k34`…`k44` y las `-pantalla` de k47/k49 |
| `8d088de0ba3e` | 7 | `k23b.config` | La primera config del port (k23b→k33, y `pantalla.config`) |
| `65c5608c7432` | 7 | `k52L49.config` | k52L49→k52L56 |
| `cb0592b48f5b` | 2 | `k45-pantalla.config` | `k45-pantalla`, `k46-pantalla` |
| `0b13328f2904` | 2 | `k52L44.config` | `k52L44`, `k52L45` |
| `984d0a55267e` | 2 | `k52L47.config` | `k52L47`, `k52L48` |
| `1852ad45ce7d` | 1 | `fix528-build-uke.config` | Build de fix (528) |
| `b697fc534469` | 1 | `fix529-build-uke.config` | Build de fix (529) |
| `6f606216fb0b` | 1 | `k50-pantalla.config` | — |
| `d6cb67621a58` | 1 | `k51-pantalla.config` | — |
| `454525d815e1` | 1 | `k52-bateria.config` | Config de batería de la serie k52 (no k52L) |
| `6bbcde95cd36` | 1 | `k52L43.config` | — |
| `d23716dbed6f` | 1 | `k52L60.config` | — |
| `f1e1fe0d91e4` | 1 | `k52L63.config` | — |
| `49acb337852d` | 1 | `senemos-ouke5.config` | **La del kernel vigente** (senemos ouke5). Es la única con `CONFIG_LOCALVERSION=""` (las del linaje palawan llevan `-palawan`) |

## Qué cambió entre configs (y qué NO)

Que dos `.config` sean idénticos **no** significa que los dos kernels se
comportaran igual: entre ellos cambiaron los **parches** y el **código**, que es
lo que de verdad
define el comportamiento. Por eso hay 74 ficheros y solo 17
contenidos: el port se iteró sobre el kernel, no sobre su configuración.

El histórico de qué cambió en cada ciclo está en los informes de
`build/gates/revision/` y en los scripts de build del linaje palawan, archivados en
`docs/historia/gates-palawan/build-k*.sh`.

## Regenerar

`build/gates/build-k*.sh` toman su config de aquí:

```sh
CFG=$R/build/kernel-config/k52L76r.config
```

Para reconstruir el árbol sin duplicados:

```sh
cd build/kernel-config
md5sum *.config | sort | uniq -w32 --all-repeated=separate
```
