# P2-CTRL-STAGING — `modetest` + `eglinfo` en la tablet (sin WiFi, por NCM-USB)

> Para **P2-ctrl** (sonda de panel, 0 escrituras — docs/historia/PLAN-SIGUIENTE-v4.md §P2.1) y **P1**
> (`eglinfo -B`, criterio OBJ 5). Generado 1-oct-2026. No flashea nada: solo instala
> userspace por SSH.

## 1. Qué hay stageado (verificado)

- Directorio: `build/pkg/staging-p2-ctrl/` — **40 `.pkg.tar.xz` (60 MB)**, `MANIFEST.sha256`
  (40/40 OK, `sha256sum -c`), `INSTALAR.txt`, más caché `core.db`/`extra.db` del mirror.
- Fuente: `http://mirror.archlinuxarm.org/aarch64` (repos `core`+`extra`), cierre de
  dependencias calculado contra las `.db` reales por `build/gates/stage-p2-ctrl.py`
  (semillas: `libdrm` → `modetest`, `mesa-utils` → `eglinfo`; virtual/sonames resueltos
  por `%PROVIDES%`, p. ej. `libgl`→`libglvnd`, `opengl-driver`→`mesa`).
- Todo lo demás del cierre ya está en la tablet (`build/rootfs/PACKAGES-OVERLAY.txt`,
  173 pkgs) o en la base ALARM: **0 dependencias sin resolver**.
- Clave: `libdrm-2.4.134-1` (contiene `usr/bin/modetest`),
  `mesa-utils-9.0.0-7` (contiene `usr/bin/eglinfo`),
  `mesa-1:26.2.3-1` (contiene `usr/lib/dri/msm_dri.so`, freedreno/MSM).
  Shas de `libdrm` y `mesa-utils` cotejados además contra el `%SHA256SUM%` declarado
  en la `.db` del repo (no solo contra el manifiesto local).
- Regenerar / reverificar en el PC:
  ```bash
  python3 build/gates/stage-p2-ctrl.py --list      # grafo, no descarga
  python3 build/gates/stage-p2-ctrl.py --download  # (re)baja los 40 + MANIFEST + INSTALAR.txt
  python3 build/gates/stage-p2-ctrl.py --verify    # sha256sum -c MANIFEST.sha256
  ```

## 2. Paso 0 — levantar el enlace USB (una vez por sesión de PC)

Método exacto en `build/gates/prepara/A1-auditoria-instalador.md` **§4**; resumen:

```bash
ip link                                         # anotar <IF> del gadget (enp0s20f0u3/enx…)
nmcli dev set <IF> managed no
sudo ip addr add 192.168.42.1/24 dev <IF>
sudo ip link set <IF> up
ping -c2 192.168.42.129                         # la tablet; debe responder
ssh -i ~/proyectos/omarchy-uke/build/rootfs/uke-arch-root root@192.168.42.129
```

Sin este ping no seguir. (El §4 de A1 trae además NAT/proxy para dar internet a la
tablet; **para este staging no hace falta**: los paquetes ya están en el PC.)

## 3. Paso 1 — copiar al tablet (en el PC)

```bash
ssh -i ~/proyectos/omarchy-uke/build/rootfs/uke-arch-root root@192.168.42.129 'mkdir -p /root/p2'
(cd ~/proyectos/omarchy-uke/build/pkg/staging-p2-ctrl && sha256sum -c MANIFEST.sha256)  # 40/40 antes de copiar
scp -i ~/proyectos/omarchy-uke/build/rootfs/uke-arch-root \
    ~/proyectos/omarchy-uke/build/pkg/staging-p2-ctrl/*.pkg.tar.* root@192.168.42.129:/root/p2/
```

## 4. Paso 2 — instalar (en la tablet, por SSH)

```bash
ls /root/p2/*.pkg.tar.* | wc -l     # debe decir 40
pacman -U --noconfirm /root/p2/*.pkg.tar.*    # TODOS a la vez: el grafo se resuelve en local
```

## 5. Paso 3 — comprobaciones (en la tablet)

```bash
modetest -M msm -c     # P2-ctrl peldaño (d): debe listar conectores (se espera DSI-1)
eglinfo -B             # criterio OBJ 5: se espera freedreno + GLES 3.2 sobre renderD128
```

Registrar salida + `dmesg -w` capturado al PC (doble captura, una sola apertura
desprendida — v4 §P2.1). **P2-ctrl es diagnóstico: no cierra OBJ 6** aunque salga verde.

## 6. Si `pacman -U` protesta por dependencias

1. Reintentar el comando tal cual (todos los paquetes a la vez, no por grupos: por
   grupos SÍ faltan deps entre ellos y la protesta es falsa).
2. Si nombra una dependencia `D` ausente: mirar si `D` está en la tablet como
   **fichero pero sin registrar en la db de pacman** — el overlay se extrajo con
   bsdtar sin scriptlets y hay paquetes sin registrar (A1 §2.1):
   `ls /usr/lib/libD*`, `ldconfig -p | grep D`, `pacman -Q D`.
   - Ficheros presentes ⇒ runtime OK: reinstalar el conjunto con
     `pacman -U --noconfirm --nodeps /root/p2/*.pkg.tar.*` y **anotar qué `D`
     obligó al `--nodeps`** (el cierre contra la repo era completo; es skew de db,
     no falta real).
   - Ficheros ausentes ⇒ parar, NO `--nodeps`: ese paquete hay que stagearlo
     (bajarlo del mismo mirror al mismo `/root/p2/` y repetir desde §4). Avisar:
     significa que el overlay/base de la tablet no trae lo que la repo exige
     (p. ej. versión de `glibc`/`gcc-libs` más vieja que la requerida).
3. Si la protesta es por **conflicto de ficheros** (`X existe en el sistema`):
   es el overlay sin registrar pisado por el paquete stageado — mismo contenido,
   dueño distinto. Resolver con `pacman -U --noconfirm --overwrite '/usr/lib/*,/usr/bin/*' …`
   solo sobre los ficheros en conflicto, nunca `--overwrite '*'` a ciegas.

## 7. Por qué NO `pacman -S`

Sin WiFi no hay mirror alcanzable desde la tablet (y el NAT del §4 de A1 es para el
instalador completo, no para esto). `pacman -S` necesita la sync-db y red; `pacman -U`
con el conjunto de cierre completo en `/root/p2/` instala lo mismo sin tocar la base
ni la red. Equivalente funcional para 40 paquetes con 0 deps externas.

## 8. Nota sobre la cita «A1-auditoria-instalador §4»

El plan v4 (§P0.1/P2) cita ese §4 como canal USB. Un borrador intermedio (v2) afirmó por
error que ese fichero no existía; **la corrección ya consta en NOTAS-OMARCHY.md
(1-oct-2026): el fichero SÍ existe** — `build/gates/prepara/A1-auditoria-instalador.md`,
30-sep, y su §4 es exactamente el método NCM-USB (PC `192.168.42.1`, tablet
`192.168.42.129`). Este documento no lo sustituye: lo complementa (A1 §4 = levantar el
enlace; aquí = qué paquetes copiar e instalar por ese enlace). Regla que lo pagó: una
cita se comprueba con `ls`, no de memoria.
