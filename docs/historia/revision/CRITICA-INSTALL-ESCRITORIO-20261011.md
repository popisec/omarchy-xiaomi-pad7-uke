# CRÍTICA — install-escritorio.sh (stage-escritorio) — 2026-10-11

Revisión a prueba de apagón del instalador del cierre de escritorio Omarchy uke
(Xiaomi Pad 7, aarch64). Auditoría del fichero original + inventario del stage +
correcciones aplicadas. Trabaja solo en el PC; tablet apagada.

---

## 1. Veredicto

**GO**, condicionado a espacio: el nuevo `install-escritorio.sh` es reanudable,
instala en 33 lotes topológicos con df-gate por lote, verifica sha256 antes de
cada `pacman -U`, corre bajo `setsid+nohup` (inmune a corte de SSH) y deja
registro por lote/paquete. Si el df-gate corta (exit 42), el sistema queda
CONSISTENTE y se reanuda con el mismo comando.

El script original era **NO-GO**: ver §2(a) — su `pacman -U ./*.pkg.tar.zst`
solo habría instalado 5 de 473 paquetes.

---

## 2. Auditoría del script original (respuesta punto por punto)

### (a) ¿Idempotente y reanudable? — NO, y bug CRÍTICO de glob
- `pacman -U --noconfirm ./*.pkg.tar.zst` **sin `--needed`**: al re-ejecutar
  reinstalaba todo (y sobreescribía versiones iguales).
- **CRÍTICO**: el glob `./*.pkg.tar.zst` solo casa con **5 de 473** paquetes:
  el stage real tiene **468 `.pkg.tar.xz`** (ALARM sirve xz; solo omarchy-*
  + quickshell + ttf-jetbrains son zst). La "transacción única" habría
  instalado keyring, omarchy, omarchy-settings, quickshell y una fuente,
  fallando por dependencias (omarchy pide hyprland/sddm/etc. no incluidos).

### (b) ¿Gestión de espacio? — NO
- Cero comprobaciones de disco. El cierre completo pesa **2.643 MB instalados**
  (medido de `.PKGINFO`), en un rootfs userdata con **~546 MB libres**. La
  transacción única habría rellenado el disco con certeza a mitad de
  extracción → rootfs corrupto (ya ocurrió una vez por apagón).
- Sin plan B ante "disco lleno a mitad de transacción": pacman aborta con la
  DB posiblemente inconsistente y sin guía de recuperación.

### (c) ¿Orden topológico? — Correcto en su diseño, inviable en la práctica
- Con TODOS los paquetes en una transacción, pacman ordena internamente
  (deps antes que paquetes; ciclos intra-transacción OK). Diseño correcto
  PERO incompatible con el límite de espacio (b). Al trocear en lotes, el
  orden ya no lo garantiza pacman → hay que precalcularlo.
- Ciclos REALES detectados en el cierre (verificados en `.PKGINFO`):
  `libglvnd ↔ mesa` y `gdk-pixbuf2 ↔ glycin ↔ librsvg`. Cualquier troceo
  ingenuo (alfabético) los parte; deben viajar en el MISMO lote.
- `cmake` (117 MB instalados) solo lo necesita `hyprpm` (compilador de
  plugins de Hyprland). Candidato a exclusion si falta espacio (ver §5).

### (d) ¿Verificación sha256 contra manifest? — NO existía
- Sin manifest. Cualquier byte corrupto en la copia SSH/NCM explotaría a
  mitad de instalación, con el disco justo: el peor escenario posible.
- **Generado ahora**: `manifest.sha256` (473 entradas, `sha256sum` real sobre
  el stage del PC).

### (e) ¿Corte de SSH a mitad de lote? — Desprotegido
- `install` corría en primer plano del SSH: un corte manda SIGHUP y mata
  pacman **dentro de una transacción** (riesgo exacto de la corrupción ya
  sufrida). Sin tmux/nohup ni reanudación.

### (f) ¿Registro por paquete? — NO
- Solo stdout de la sesión SSH. Tras un apagón no había forma de saber qué
  lotes/paquetes quedaron instalados salvo reconstruirlo a mano.

---

## 3. Inventario del stage (verificado hoy en el PC)

| Check | Resultado |
|---|---|
| Paquetes presentes | **473** (468 `.pkg.tar.xz` + 5 `.pkg.tar.zst`), 635 MB comprimidos |
| Arquitectura | 100% `aarch64` o `any`; 0 `x86_64` |
| Duplicados de pkgname | **0** (473 pkgnames únicos; `cairomm`/`cairomm-1.16`, `glibmm`/`glibmm-2.68`, `libsigc++`/`libsigc++-3.0`, `lua`/`lua54` son pkgnames distintos, correcto) |
| Dependencias | **0 dependencias sin cubrir** dentro del stage (todas las `depend` resuelven contra pkgname/provides del propio stage; el resto se asume ya instalado en la tablet por ALARM base) |
| Provides ambiguos | 3 (`wayland-compositor`, `ttf-font-nerd`, `xdg-desktop-portal-impl`) — ninguno usado como `depend` dentro del stage; sin impacto |
| sha256 | `manifest.sha256` con las 473 entradas, regenerado y cotejado contra `lotes/` (mismo conjunto, sin duplicados) |

### lotes/ (generados por Tarjan SCC sobre .PKGINFO, atómicos por SCC)
- **33 lotes**, cap ~30 pkgs / ~100 MB instalados por lote; máximo 171.6 MB
  (lote-14, `llvm-libs` solo — no divisible).
- Orden: keyring primero (fijado), glibc→libs→mesa+libglvnd (mismo lote,
  lote-21)→gtk3/gtk4→qt6→hyprland stack (lote-30)→NetworkManager (lote-31)→
  **omarchy al final (lote-32, 127 MB)**.
- Cada línea de lote: `fichero tam_bytes pkgname pkgver` — el instalador usa
  `pkgname+pkgver` para saltar exactamente lo ya instalado.
- Los 2 SCC cíclicos viajan íntegros en un lote: pacman los resuelve dentro
  de su transacción, como en una instalación de un solo golpe.

---

## 4. Correcciones aplicadas (install-escritorio.sh reescrito)

Mismo estilo (bash estricto `set -euo pipefail`, subcomandos copy/install);
añadidos `install-fg` (1er plano, depuración) y `status`.

1. **Reanudable**: por lote, se comparan `pkgname+pkgver` contra `pacman -Q`;
   lo ya instalado a la versión exacta se salta (ni sha256 ni df ni pacman).
   Un lote 100% instalado se marca `SKIP` en el log. Re-ejecutar `install`
   siempre es seguro.
2. **df-gate por lote**: antes de tocar nada, `df -Pm /` debe dar
   `libres ≥ tamaño_instalado_de_pendientes + 25 MB` (holgura para la DB y
   tmp de pacman). Si no: **exit 42 limpio**, cero cambios, mensaje de cómo
   reanudar. Como el gate corre ANTES de `pacman -U`, ya no existe el
   escenario "pacman sin sitio a mitad de transacción" salvo fuga externa.
3. **Verificación sha256 por lote** contra `manifest.sha256` (coincidencia
   exacta de campo, no substring) antes de cada `pacman -U`. Corrupto o
   faltante → exit 1 con instrucción de re-copiar.
4. **Post-chequeo por lote**: `pacman -Qk` sobre lo recién instalado (detecta
   extracción truncada por apagón/disco) + `sync` tras cada lote (minimiza la
   ventana de corruptura de DB en un apagón).
5. **Locks huérfanos**: si existe `/var/lib/pacman/db.lck` y no hay pacman
   vivo (típico tras el apagón), se elimina; si hay pacman vivo, aborta.
6. **Inmune a corte de SSH**: `install` se auto-lanza con
   `IES_BG=1 setsid nohup ... >>/root/install-escritorio.log`; el padre
   devuelve el PID y ordena `tail -f`. Corte de SSH = el lote en curso
   termina; re-entrar y ejecutar `install` de nuevo reanuda.
7. **Registro**: log con timestamps por lote (`SKIP/OK`/MiB/libres),
   `pacman -Qq` antes (`/root/pkg-antes.txt`) y después
   (`/root/pkg-despues.txt`) → `diff` da exactamente qué cambió la sesión.
8. **copy()**: añade `pacman.conf` de staging a los excludes, **incluye el
   propio script** en el stage (el original lo excluía: la tablet no habría
   tenido cómo instalar), y verifica en la tablet `ls *.pkg.tar.* | wc -l`
   + `sha256sum -c manifest.sha256` tras la copia.

### Bugs encontrados y corregidos durante la batería de pruebas
- `grep -Fxf` para cruzar lote↔manifest nunca casaba (casa línea completa
  `hash␣␣fichero`, no el nombre): sustituido por `awk` con campo exacto.
- Falta de `IES_BG=1` en el entorno del hijo demonizado → re-daemonización
  infinita (fork bomb en el banco de pruebas); corregido.

### Banco de pruebas (pacman/systemctl/df falsos, stage recortado en /tmp)
- RUN 1: instala pendientes, salta instalados exactos, OK de lote, servicios.
- RUN 2: todo `SKIP`, exit 0 (idempotencia).
- df-gate con 10 MiB libres → mensaje limpio y **exit 42**.
- Paquete truncado → detectado por sha256, **exit 1**.
- Daemonize: el hijo completa y no re-bifurca; `status` lee log + df + pacman.
- `lotes == orden.txt == manifest.sha256`: 473 ficheros, mismo conjunto.

---

## 5. Presupuesto de espacio (el riesgo que queda)

- Cierre completo: **2.643 MB instalados**. Mayores: `llvm-libs` 171.6 MB,
  `qt6-declarative` 143.6, `omarchy` 127.0, `cmake` 117.2, `noto-fonts` 112.0,
  `python` ~80, `qt6-base` ~90, `mesa` ~75.
- De la sesión interrumpida quedan ~217/473 instalados; gran parte eran
  **upgrades de paquetes ALARM ya presentes** (delta de espacio pequeño), así
  que el grueso del espacio restante lo comen los paquetes NUEVOS grandes
  (mesa/qt6/hyprland stack/omarchy).
- Con ~546 MB libres es posible que los últimos lotes grandes NO quepan. El
  df-gate lo detectará lote a lote y cortará limpio (exit 42) dejando todo lo
  anterior instalado y consistente. Plan de contingencia documentado:
  1. Reclamar ~140 MB saltando `cmake`+`hyprpm` (solo sirve para compilar
     plugins de Hyprland; nada del cierre depende de él en runtime): quitar
     sus líneas del `lotes/*.txt` correspondiente y borrar los ficheros del
     stage. Recalcular antes de tocar: los lotes afectados son el lote-19
     (`cmake`) y lote-30 (`hyprpm`).
  2. `pacman -Sc` (limpiar caché) y revisar `/var/log`, journals.
  3. Mover el stage a /data y hacer bind-mount… solo si todo lo anterior falla.

---

## 6. Secuencia exacta para la próxima sesión SSH

### En el PC (copiar el stage)
```bash
cd ~/proyectos/omarchy-uke/build/stage-escritorio
# 1) descubrir la IP/PUERTO SSH de la tablet por mDNS (NO memorizar):
avahi-browse -artp 2>/dev/null | grep '_adb-tls-connect._tcp;local;.*api=' \
  | sed 's/.*local;//;s/;.*api=/ -> /;s/"//g'
# 2) copiar + verificación sha256 en destino (el script NO excluye ya al instalador):
./install-escritorio.sh copy IP:PUERTO      # → "sha256 OK" al terminar
```
(Si SSH no está activo en la tablet: `adb push` del stage a
`/data/local/tmp/stage-escritorio` y `su -c 'mv ... /root/stage-escritorio'`,
verificando luego a mano `cd /root/stage-escritorio && sha256sum -c manifest.sha256`.)

### En la tablet (instalar)
```bash
ssh root@IP
/root/stage-escritorio/install-escritorio.sh status   # dónde quedó la sesión anterior
/root/stage-escritorio/install-escritorio.sh install  # auto-daemoniza; devuelve PID
tail -f /root/install-escritorio.log                  # seguimiento (Ctrl-C no lo mata)
# si aparece "ESPACIO INSUFICIENTE ... exit 42":
#   liberar espacio (ver §5) y volver a ejecutar 'install' — reanuda solo.
# si el SSH se corta: reconectar y re-ejecutar 'install' (idempotente).
```

### Verificación final de ESTA fase (pre-arranque gráfico)
```bash
/root/stage-escritorio/install-escritorio.sh status
pacman -Q | wc -l                                   # sin errores de DB (criterio principal)
diff /root/pkg-antes.txt /root/pkg-despues.txt      # qué instaló exactamente esta sesión
df -h /                                             # espacio libre restante
systemctl is-enabled NetworkManager sddm            # enabled / enabled
```
Criterio de éxito: `pacman -Q` sale sin errores, 473/473 del cierre resueltos
(con la base previa habrá ~más), y queda espacio libre razonable.
**NO verificar aquí** `hyprctl version` ni `pgrep quickshell`: eso es para
DESPUÉS del arranque gráfico (SDDM → sesión omarchy/uwsm).

---

## 7. Ficheros

| Fichero | Estado |
|---|---|
| `build/stage-escritorio/install-escritorio.sh` | REESCRITO (a prueba de apagón) |
| `build/stage-escritorio/manifest.sha256` | NUEVO (473 entradas) |
| `build/stage-escritorio/lotes/lote-00..32.txt` | NUEVOS (topológicos, SCC-atómicos) |
| `build/stage-escritorio/lotes/orden.txt`, `lotes/resumen.txt` | NUEVOS (orden global / resumen humano) |
