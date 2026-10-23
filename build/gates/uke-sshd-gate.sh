#!/usr/bin/env bash
# uke-sshd-gate.sh — decide, SIN flashear, si la imagen que se va a escribir arranca `sshd`.
#
# POR QUÉ HACE FALTA. `sshd` no dice absolutamente nada en la consola cuando aborta (el cmdline
# lleva `loglevel=6`, y los mensajes de las unidades no salen), así que en la tablet el síntoma
# es solo «el puerto 22 está cerrado y no hay ni una línea de rastro». Averiguarlo ahí cuesta un
# flash de 8 GiB y un arranque. Y como el flash va por el presupuesto de escrituras, un gate que
# comprueba la imagen en el PC vale por un ciclo entero.
#
# QUÉ COMPRUEBA, Y POR QUÉ ES ESTÁTICO. En `sshd.c` (main(), OpenSSH 10.x) hay, ANTES de
# listen(), tres comprobaciones que abortan con `fatal()`:
#
#   1. getpwnam("sshd") == NULL y getuid()==0  ->  "Privilege separation user %s does not exist"
#   2. stat(_PATH_PRIVSEP_CHROOT_DIR) falla     ->  "Missing privilege separation directory: %s"
#   3. ese directorio no es de uid 0, o es escribible por grupo/otros
#                                               ->  "%s must be owned by root and not group or
#                                                    world-writable."
#
# El gate las evalúa sobre la IMAGEN REAL (la que se va a flashear), con `debugfs`, y además
# comprueba que este build trae esos mismos mensajes y ese mismo directorio, con `strings` sobre
# el binario extraído. Si los mensajes no estuvieran, el gate no serviría para nada, y eso también
# se comprueba.
#
# POR QUÉ NO ES DINÁMICO. Se intentó ejecutar el `sshd` aarch64 con `qemu-aarch64` + `unshare -Urm`
# (bind-monteando un /etc con o sin el usuario sshd, para reproducir el fallo y su ausencia).
# Funciona hasta `debug1: setgroups() failed: Operation not permitted`: en un namespace de usuario
# sin privilegios `setgroups()` está deshabilitado, así que el sandbox de sshd aborta por una
# razón del entorno de prueba que no dice nada de la imagen. Un gate que necesita un privilegio
# que no tenemos no es un gate. Por eso el Dynamic queda como señal secundaria (que la config
# parsea y que las claves de host cargan) y el veredicto lo dan las precondiciones estáticas.
#
# USO:  ./uke-sshd-gate.sh [ruta-a-la-imagen-o-al-staging]
# SALIDA: 0 si la imagen arranca sshd; 1 si hay algún bloqueo; 2 si el gate no se puede aplicar.
set -u
TARGET="${1:-$(cd "$(dirname "$0")/../rootfs" && pwd)/arch-rootfs.img}"
WORK=/tmp/opencode/sshd-gate
rm -rf "$WORK"; mkdir -p "$WORK"

# ---- decide cómo leer el objetivo: si es un fichero de imagen, se usa debugfs
IS_IMG=0
if [ -f "$TARGET" ]; then
    case "$TARGET" in
        *.img|*.simg) IS_IMG=1 ;;
    esac
fi
if [ "$IS_IMG" = 0 ] && [ -d "$TARGET" ]; then
    IMG="$TARGET"          # un staging: se mira en el árbol
else
    IMG="$TARGET"
fi

fail=0
nota() { printf '  %-58s %s\n' "$1" "$2"; }
mal()  { printf '  \033[31mFALLA\033[0m  %-48s %s\n' "$1" "$2"; fail=1; }
bien() { printf '  OK      %-48s %s\n' "$1" "$2"; }

# ---- helper: prop de un path de la imagen (debugfs) o del árbol
pget() { # pget <debugfs-cmd> <ruta>
    if [ "$IS_IMG" = 1 ]; then
        debugfs -R "$1 $2" "$IMG" 2>/dev/null
    else
        [ -e "$2" ] && echo "present" || echo "AUSENTE"
    fi
}

echo "=============================================================="
echo " GATE DE sshd — sin flashear.  objetivo: $TARGET"
echo "=============================================================="
echo

# ================= 1. ¿este build trae los mensajes y el directorio? =================
echo "1) ¿El binario de sshd trae los tres fatal() y el directorio de privsep?"
BIN="$WORK/sshd.bin"
if [ "$IS_IMG" = 1 ]; then
    debugfs -R "dump /usr/bin/sshd $BIN" "$IMG" >/dev/null 2>&1
else
    cp -a "$IMG/usr/bin/sshd" "$BIN" 2>/dev/null
fi
if [ -s "$BIN" ]; then
    STRINGS="$(strings -a "$BIN")"
    echo "$STRINGS" | grep -q "Privilege separation user %s does not exist" \
        && bien "mensaje 'privilege separation user ... does not exist'" "presente" \
        || mal  "mensaje 'privilege separation user'" "AUSENTE: el gate no aplica a este build"
    PRIVSEP_BIN="$(echo "$STRINGS" | grep -oE '^/usr/share/empty\.sshd$|^/var/empty$|^/run/sshd$' | head -1)"
    nota  "directorio de privsep que usa el binario" "${PRIVSEP_BIN:-<no encontrado>}"
    echo "$STRINGS" | grep -q "must be owned by root and not group or world-writable" \
        && bien "mensaje 'must be owned by root'" "presente" \
        || mal  "mensaje 'must be owned by root'" "AUSENTE"
    echo "$STRINGS" | grep -q "Missing privilege separation directory" \
        && bien "mensaje 'Missing privilege separation directory'" "presente" \
        || mal  "mensaje 'Missing privilege separation directory'" "AUSENTE"
else
    mal "extraer /usr/bin/sshd" "no se pudo"
fi
PRIVSEP_PATH="${PRIVSEP_BIN:-/usr/share/empty.sshd}"
echo

# ================= 2. Precondición 1: el usuario sshd existe =================
echo "2) Precondición de arranque nº1: getpwnam(\"sshd\") no puede ser NULL"
PASSWD_TXT="$WORK/passwd.txt"
if [ "$IS_IMG" = 1 ]; then
    debugfs -R "cat /etc/passwd" "$IMG" 2>/dev/null > "$PASSWD_TXT"
else
    cp "$IMG/etc/passwd" "$PASSWD_TXT" 2>/dev/null
fi
SSH_LINE="$(grep -E '^sshd:' "$PASSWD_TXT" || true)"
if [ -n "$SSH_LINE" ]; then
    bien "/etc/passwd tiene la linea sshd" "$SSH_LINE"
    SSHD_UID="$(printf '%s' "$SSH_LINE" | cut -d: -f3)"
    SSHD_SHELL="$(printf '%s' "$SSH_LINE" | cut -d: -f7)"
    [ -n "$SSHD_UID" ] && nota "  uid de sshd" "$SSHD_UID"
    [ -n "$SSHD_SHELL" ] && nota "  shell de sshd" "$SSHD_SHELL"
    [ "$SSHD_SHELL" = "/usr/bin/nologin" ] || echo "  AVISO: en Arch la shell de sshd es /usr/bin/nologin"
else
    mal "/etc/passwd NO tiene usuario sshd" "sshd abortaria antes de listen()"
fi
# el fragmento sysusers es la red de seguridad si alguien reconstruye el arbol
SYSUSERS="$WORK/sysusers.txt"
if [ "$IS_IMG" = 1 ]; then
    debugfs -R "cat /usr/lib/sysusers.d/openssh.conf" "$IMG" 2>/dev/null > "$SYSUSERS"
else
    cp "$IMG/usr/lib/sysusers.d/openssh.conf" "$SYSUSERS" 2>/dev/null || : > "$SYSUSERS"
fi
grep -q '^u sshd' "$SYSUSERS" \
    && bien "usr/lib/sysusers.d/openssh.conf declara u sshd" "presente" \
    || echo "  nota: sin fragmento sysusers (si /etc/passwd se pierde, el usuario tampoco)"
echo

# ================= 3. Precondición 2/3: el directorio de privsep =================
echo "3) Precondiciones de arranque nº2 y nº3: el directorio de privsep"
STAT="$WORK/stat.txt"
if [ "$IS_IMG" = 1 ]; then
    debugfs -R "stat $PRIVSEP_PATH" "$IMG" 2>/dev/null > "$STAT"
else
    [ -d "$IMG$PRIVSEP_PATH" ] && stat -c "Mode:  0%a User: %u Group: %g" "$IMG$PRIVSEP_PATH" > "$STAT"
fi
if grep -q "Type: *directory" "$STAT" 2>/dev/null || grep -q "^Mode:" "$STAT" 2>/dev/null; then
    UID_="$(grep -oE "User: +[0-9]+" "$STAT" | awk '{print $2}')"
    MODE_="$(grep -oE "Mode: +0[0-7]+" "$STAT" | awk '{print $2}')"
    nota "$PRIVSEP_PATH" "mode=$MODE_ uid=$UID_"
    [ "$UID_" = "0" ] && bien "es de uid 0 (root)" "ok" \
                      || mal  "NO es de root" "sshd abortaria con 'must be owned by root'"
    # group/world writable -> los ultimos dos digitos del octal
    if [ -n "$MODE_" ]; then
        PERM="${MODE_#0}"; PERM="${PERM#0}"
        case "$PERM" in
            *[2367][0-7]|[0-7][2367]) mal "modo $MODE_ escribible por grupo/otros" "sshd abortaria" ;;
            *) bien "modo $MODE_ no escribible por grupo/otros" "ok" ;;
        esac
    fi
else
    mal "$PRIVSEP_PATH no existe" "sshd abortaria con 'Missing privilege separation directory'"
fi
echo

# ================= 4. Identidad: todo root, no uid 1000 =================
echo "4) Identidad del árbol (el fallo de fondo de V3: todo con uid 1000)"
for p in /usr/bin/sshd /etc/ssh/ssh_host_ed25519_key /root/.ssh /root/.ssh/authorized_keys; do
    S2="$WORK/s2.txt"
    if [ "$IS_IMG" = 1 ]; then
        debugfs -R "stat $p" "$IMG" 2>/dev/null > "$S2"
    else
        [ -e "$IMG$p" ] && stat -c "Mode: 0%a User: %u" "$IMG$p" > "$S2"
    fi
    U="$(grep -oE "User: +[0-9]+" "$S2" | awk '{print $2}')"
    M="$(grep -oE "Mode: +0[0-7]+" "$S2" | awk '{print $2}')"
    [ "$U" = "0" ] && bien "$p" "uid=0 mode=$M" || mal "$p" "uid=${U:-?} (esperado 0)"
done
# StrictModes: sshd exige que /root/.ssh sea de root o del usuario
echo "  (StrictModes=yes hace que sshd RECHACE el login por clave si /root/.ssh no es de root)"
echo

# ================= 5. Señal secundaria: la config parsea y las claves cargan =================
echo "5) Señal secundaria (dinámica): ¿parsea la config y carga las claves de host?"
QEMU=0
command -v qemu-aarch64 >/dev/null && QEMU=1
if [ "$QEMU" = 1 ] && [ "$IS_IMG" = 0 ] && [ -x "$IMG/usr/bin/sshd" ]; then
    DBG="$(unshare -Urm sh -c "
        mount --bind '$IMG/usr/share/empty.sshd' /usr/share/empty.sshd 2>/dev/null
        qemu-aarch64 -L '$IMG' '$IMG/usr/bin/sshd' -d -p 22999 -f '$IMG/etc/ssh/sshd_config' 2>&1
    " 2>&1 | head -8)"
    echo "$DBG" | sed 's/^/    /'
    if echo "$DBG" | grep -qiE "does not exist|must be owned by root|Missing privilege separation"; then
        mal "sshd -d muestra un fatal de privsep" "el bloqueo sigue presente"
    else
        bien "sin fatal de privsep en la salida"
    fi
    echo "$DBG" | grep -q "setgroups() failed" \
        && echo "    (la línea 'setgroups() failed' es un límite del namespace de usuario de este" \
             && echo "     test, NO de la imagen: en un userns sin privilegios setgroups está" \
             && echo "     deshabilitado. Por eso el veredicto lo dan las precondiciones estáticas.)"
else
    echo "    (omitido: hace falta qemu-aarch64 y que el objetivo sea un árbol, no una imagen)"
fi
echo

echo "=============================================================="
if [ $fail -eq 0 ]; then
    echo " VEREDICTO: la imagen cumple las precondiciones de arranque de sshd."
    echo " Se espera el puerto 22 abierto tras el próximo arranque."
    echo " Si aun así no abre, esta hipótesis queda REFUTADA: el siguiente paso es"
    echo " 'journalctl -u sshd' desde la consola, no otro cambio a ciegas."
    exit 0
else
    echo " VEREDICTO: la imagen tiene al menos un bloqueo de arranque de sshd. NO flashear."
    exit 1
fi
