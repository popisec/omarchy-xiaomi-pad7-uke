# KERNEL-CONSOLIDADO — auditoría kernel vs escritorio Omarchy · 14-oct-2026

Base: `build/kernel-config/k52L56.config` (8992 lín) + Kconfig del árbol vivo
`build/kernel-pokes/k52-L16-tree` (solo lectura) + `docs/historia/revision/MESA-TABLET-20261011.md`.
**Tablet NO accesible desde aquí** (sin interfaz RNDIS en este host, ping a
192.168.42.129 100% pérdida): lo marcado ⛔ es NO-MEDIDO hoy, resto MEDIDO en ficheros.

## 0. Cómo se construye el config (MEDIDO)
Sin fragmentos: un solo `.config` versionado (`k52L56.config`); `build-fast.sh:100`
corre `make olddefconfig`. Siguiente kernel = copiar `k52L56.config`, aplicar §1–2,
`olddefconfig`, build desprendido de siempre. L56==L55 en config (diff vacío).

## 1. PRIORIDAD 1 — zram builtin (causa raíz del `modprobe zram` fallido)
El fallo NO es falta de `CONFIG_ZRAM` (está `=m`, backend ZSTD, `MULTI_COMP=y`):
es que **los `=m` in-tree no viajan al rootfs** (MEDIDO: `k52L56-build` tiene **0 `.ko`**,
`staging/usr/lib/modules` solo trae `extra/` + despliegues manuales scp+depmod).
Todo `=m` no desplegado a mano está muerto en la tablet. Solución: builtin.
| línea exacta | razón | riesgo | verificación post-arranque |
|---|---|---|---|
| `CONFIG_ZRAM=y` (era `m`) | swap comprimida sin depender del rootfs | BAJO (+~60 KB Image, código maduro) | `echo 1G >/sys/block/zram0/disksize && mkswap /dev/zram0 && swapon -p 100 /dev/zram0; cat /proc/swaps` |
| `CONFIG_ZSMALLOC=y` (era `m`; `select` de ZRAM, poner explícito) | allocator de zram, mismo motivo | BAJO | `grep zsmalloc /proc/vmallocinfo` |
| `CONFIG_ZRAM_BACKEND_LZ4=y` (nueva; ZSTD se queda) | compresor rápido para swap en cores pequeños; zstd sigue disponible (`MULTI_COMP=y`) | MÍNIMO (bool, +~30 KB) | `cat /sys/block/zram0/comp_algorithm` muestra `lz4` |
| (sin rebuild) quitar `mem=2048M` | YA HECHO en L57 (`ebe94093…`, ledger). D16 aprobado | ver `L57-MEM.md` (vigilar ath11k/DMA) | `grep MemTotal /proc/meminfo` (≈7,x GB) + `dmesg \| grep -iE "swiotlb\|ath11k.*(error\|fail)"` |

## 2. PRIORIDAD 2 — default lz4 (opcional, mismo build)
| línea exacta | razón | riesgo | verificación |
|---|---|---|---|
| `CONFIG_ZRAM_DEF_COMP_LZ4=y` (choice: sustituye a `DEF_COMP_ZSTD`) | menor latencia de swap; zstd queda elegible por recompresión | BAJO | `cat /sys/block/zram0/comp_algorithm` → `[lz4]` por defecto |

## 3. PRIORIDAD 3 / SIN CAMBIO — veredicto por subsistema (MEDIDO en config)
- **Gráficos: COMPLETO, NO TOCAR.** `MSM/KMS/DPU/DP/DSI/PHYs/GPU_STATE=y`,
  `SCHED=y`, `UDMABUF=y`, `HEAPS+SYSTEM+CMA=y`, `DMA_CMA=y`, `SYNC_FILE=y`,
  `ICC_QCOM_PALAWAN=y`, `GDSC=y`, `QCOM_SCM=y`, `CMA_AREAS=20`. El bloqueo
  freedreno es de **mesa userspace** (MEDIDO 11-oct: `fd_pipe_new2: unsupported GPU
  id 0x0`, cae a llvmpipe; chipid 0xffff43030b00 fuera de tabla) → turf del otro
  subagente. `FBDEV_EMULATION=n` SE QUEDA (Hyprland usa DRM/GBM, no fbdev).
  ⛔ NO-MEDIDO hoy: render node (`/dev/dri/`) y probe Adreno 732 en `dmesg`.
- **Servicios: todo presente.** `EVDEV=y`, `INPUT_UINPUT=m` (lín. 3216),
  `FUSE=m`, `USER_NS=y`, `BPF_SYSCALL/JIT=y`, `CGROUPS+MEMCG/BLK/PIDS/FREEZER/DEVICE/BPF=y`,
  `TMPFS(+ACL+XATTR)=y`, `PSI=y`, `UHID=m`, `OVERLAY_FS=m`, `BINFMT_MISC=m`. Sin cambios.
- **Red/audio: sin cambios.** `ATH11K(+AHB/PCI)=m`, parche swiotlb ya en árbol;
  `WCD939X(+SDW)=m` presente — audio no bloquea escritorio. No proponer nada más.
- **NO proponer:** `ZSWAP` (sin partición swap; zram es la vía), `ZPOOL/ZBUD/Z3FOLD`
  (zram usa zsmalloc directo), `DEBUG_INFO_BTF` (peso), nada de SMMU/display (FIX-A1b vivo).

## 4. Pendiente cuando haya SSH (para quien tenga la tablet)
`ls -l /dev/dri/; dmesg|grep -iE "msm|adreno|gpu|zap|gmu"; ls /usr/lib/modules/7.2.0-rc2-palawan/kernel/mm/; eglinfo -B|grep -i renderer`
