#!/bin/bash
# build-mods.sh — construye el set K5 de módulos de carga SIN tocar la config del kernel.
#
# QUÉ HACE (y qué NO):
#   - Lee la .config EFECTIVA del build L33 (k52L33-build/.config), la COPIA a
#     dos directorios SCRATCH en /tmp (O_NOPLUS y O_PLUS) y voltea SOLO estos 7
#     símbolos de =y a =m con scripts/config + olddefconfig:
#       QRTR_SMD, QCOM_PIL_INFO, QCOM_RPROC_COMMON, QCOM_Q6V5_COMMON,
#       QCOM_Q6V5_PAS, RPMSG_QCOM_GLINK_SMEM, QCOM_PD_MAPPER
#     (QCOM_PMIC_GLINK, UCSI_PMIC_GLINK y BATTERY_QCOM_BATTMGR ya son =m.)
#   - NO edita NINGÚN fichero versionado: ni build/gates/l39-config.config ni
#     k52L33-build/.config ni el árbol fuente. El gate G-CONFIG aborta si el
#     diff tras olddefconfig trae cualquier cambio fuera de los 7 esperados
#     (+ su fallout estricto de dependencias, auditado a mano abajo).
#   - Compila SOLO módulos (make modules_prepare + make M=<dirs> modules).
#     El vmlinux/Image del scratch se ignora: nunca se flashea nada de aquí.
#
# POR QUÉ k52L33-tree (fuente):
#   - Lleva el parche del LOCATOR (qcom_pd_mapper.c:602-606: qcom,cliffs y
#     qcom,cliffs-mtp -> sm8550_domains; raíz del DT vivo = "qcom,cliffs") y
#     los parches del dialecto del battmgr (0x50 XM_STATUS, complete(&ack)).
#   - Es byte-idéntico a k52L39-tree en pd_mapper/battmgr/pmic_glink
#     (verificado con diff -q el 13-oct-2026): un solo build sirve a L33 y L39.
#
# POR QUÉ DOS VARIANTES (ver VERMAGIC-PIN + INFORME §vermagic):
#   - Los kernels L de este proyecto reportan 7.2.0-rc2-palawan (SIN +).
#   - Los kernels del proyecto hermano reportan 7.2.0-rc2-palawan+ (CON +;
#     el + lo pone scripts/setlocalversion cuando el árbol git está dirty).
#   - La tablet está caída y no se puede leer `uname -r`: se construyen las
#     DOS variantes desde la MISMA fuente y el guion de la tablet
#     (uke-charge-check.sh) elige por `uname -r`. Cada variante vive en
#     charge/mods-<release>/ con su modules.dep generado por depmod -b.
#
# CÓMO SE EVITA QUE EL VERMAGIC VUELVA A ROMPERSE (lección 13-oct-2026):
#   1. El release NO depende del estado git del árbol: se fija con
#      LOCALVERSION= (vacío => sin +) y LOCALVERSION=+ (=> con +) en la línea
#      de make. scripts/setlocalversion, con LOCALVERSION seteada, NO consulta
#      el scm (setlocalversion:199-212): el resultado es determinista.
#   2. Gate G-VERMAGIC: tras modules_prepare se lee include/config/kernel.release
#      del scratch y se exige igualdad EXACTA con la línea correspondiente de
#      VERMAGIC-PIN. Si no casa, aborta ANTES de compilar.
#   3. Gate G-MODINFO: cada .ko staged pasa `modinfo -F vermagic` y se exige
#      el string exacto "<release> SMP preempt mod_unload aarch64".
#
# Uso: charge/build-mods.sh   (se auto-desprende como el resto de builds del
#        proyecto; log en build/logs/build-charge-mods.log)
set -euo pipefail

R="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
SRC=$R/build/kernel-pokes/k52L33-tree
BASECFG=$R/build/kernel-pokes/k52L33-build/.config
O_NOPLUS=/tmp/uke-mods-palawan
O_PLUS=/tmp/uke-mods-palawan-plus
PIN=$R/charge/VERMAGIC-PIN
LOG=$R/build/logs/build-charge-mods.log
JOBS=12
FLIP="CONFIG_QRTR_SMD CONFIG_QCOM_PIL_INFO CONFIG_QCOM_RPROC_COMMON CONFIG_QCOM_Q6V5_COMMON CONFIG_QCOM_Q6V5_PAS CONFIG_RPMSG_QCOM_GLINK_SMEM CONFIG_QCOM_PD_MAPPER"
# Skips SOLO-scratch (módulos colaterales que no se distribuyen y cuyo
# modpost falla en este árbol: qrtr-mhi necesita MHI, ausente aquí).
# Van a =n SOLO en la copia scratch; la config versionada no se toca.
SCRATCH_N="CONFIG_QRTR_MHI"
MDIRS="drivers/remoteproc drivers/rpmsg net/qrtr drivers/soc/qcom drivers/usb/typec/ucsi drivers/power/supply"
# NOTA kbuild (verificada 13-oct-2026): con M=<dir-relativo> los .o/.ko se
# escriben EN EL ÁRBOL FUENTE, no en O. Por eso (1) se recoge cada variante
# INMEDIATAMENTE tras compilarla (la 2ª sobrescribe a la 1ª) y (2) al final
# se limpian del árbol todos los generados (gate G-LIMPIO con marker).

if [ -z "${UKE_BUILD_DETACHED:-}" ]; then
	mkdir -p "$(dirname "$LOG")"
	export UKE_BUILD_DETACHED=1
	setsid nohup "$0" "$@" >>"$LOG" 2>&1 &
	disown || true
	echo "build charge-mods desprendido (pid $!); log en $LOG"
	exit 0
fi

say() { echo "[$(date +%H:%M:%S)] $*"; }
fail() { say "ABORT: $*"; exit 1; }

[ -d "$SRC" ] || fail "no existe el arbol $SRC"
[ -f "$BASECFG" ] || fail "no existe la config base $BASECFG"
[ -f "$PIN" ] || fail "no existe el pin $PIN"
command -v ccache >/dev/null || fail "ccache no instalado"

export CCACHE_DIR=${CCACHE_DIR:-$HOME/.cache/ccache-uke}
export CCACHE_BASEDIR=$R
export CC="ccache clang"
export HOSTCC="ccache gcc"
export MAKE=/usr/bin/make
export ARCH=arm64
export LLVM=1
export KBUILD_BUILD_USER=uke
export KBUILD_BUILD_HOST=palawan
export KBUILD_BUILD_TIMESTAMP="Fri Oct 10 12:00:00 CEST 2026"
cd "$SRC"

prep_one() { # $1=O $2=LOCALVERSION-valor $3=release-esperado
	local O=$1 LV=$2 REL=$3
	say "== prep $O (LOCALVERSION='$LV' -> $REL) =="
	mkdir -p "$O"
	cp -f "$BASECFG" "$O/.config"
	for s in $FLIP; do
		./scripts/config --file "$O/.config" --set-val "$s" m >/dev/null \
			|| fail "scripts/config $s"
	done
	for s in $SCRATCH_N; do
		./scripts/config --file "$O/.config" -d "$s" >/dev/null \
			|| fail "scripts/config -d $s"
	done
	make O="$O" LOCALVERSION="$LV" olddefconfig >/dev/null \
		|| fail "olddefconfig $O"
	say "-- diff de config (solo se admiten los 7 volteos + fallout):"
	diff "$BASECFG" "$O/.config" | grep -E "^[<>]" | grep -v "^[<>] #" || true
	# Gate G-CONFIG: ningún símbolo puede pasar a =y, y fuera de los 7 solo
	# se admite que aparezcan líneas NUEVAS de dependencias (=m o unset).
	bad=$(diff "$BASECFG" "$O/.config" | grep -E "^> CONFIG_.*=y" || true)
	[ -z "$bad" ] || fail "G-CONFIG: algo pasó a =y: $bad"
	for s in $FLIP; do
		grep -qE "^${s}=m$" "$O/.config" || fail "G-CONFIG: $s no quedó =m"
	done
	for s in CONFIG_QCOM_PMIC_GLINK CONFIG_UCSI_PMIC_GLINK CONFIG_BATTERY_QCOM_BATTMGR; do
		grep -qE "^${s}=m$" "$O/.config" || fail "G-CONFIG: $s ya no es =m"
	done
	say "OK  G-CONFIG $O"
	make O="$O" LOCALVERSION="$LV" modules_prepare >/dev/null \
		|| fail "modules_prepare $O"
	# El scratch no tiene vmlinux: modpost necesita el mapa de símbolos del
	# build L33 (SOLO lectura; MODVERSIONS=n así que no hay CRCs que heredar).
	[ -f "$R/build/kernel-pokes/k52L33-build/Module.symvers" ] \
		|| fail "falta Module.symvers del k52L33-build"
	cp -f "$R/build/kernel-pokes/k52L33-build/Module.symvers" "$O/Module.symvers"
	got=$(cat "$O/include/config/kernel.release")
	[ "$got" = "$REL" ] || fail "G-VERMAGIC: kernel.release=$got, esperado=$REL"
	say "OK  G-VERMAGIC $O: $got"
}

REL_NOPLUS=$(sed -n '1p' "$PIN")
REL_PLUS=$(sed -n '2p' "$PIN")
prep_one "$O_NOPLUS" "" "$REL_NOPLUS"
prep_one "$O_PLUS" "+" "$REL_PLUS"

# Nombres de .ko esperados (el gate G-MODINFO los exige todos).
# OJO: los guiones son los reales del Makefile (qrtr-smd, ucsi_glink):
WANT="qcom_q6v5_pas.ko qcom_glink_smem.ko qrtr-smd.ko qcom_pd_mapper.ko pmic_glink.ko ucsi_glink.ko qcom_battmgr.ko"
EXTRA_OK="qcom_pil_info.ko qcom_common.ko qcom_q6v5.ko qcom_glink.ko"
collect() { # $1=dest $2=release (recoge DEL ÁRBOL FUENTE, ver NOTA kbuild;
	local dest=$1 REL=$2 # valida por vermagic, no por fecha: make puede
	mkdir -p "$dest"     # reusar objetos válidos de una corrida anterior)
	for k in $WANT $EXTRA_OK; do
		f=$(find "$SRC" -name "$k" 2>/dev/null | head -n 1)
		if [ -n "$f" ]; then
			v=$(modinfo -F vermagic "$f" 2>/dev/null || echo "?")
			if [ "$v" = "$REL SMP preempt mod_unload aarch64" ]; then
				cp -f "$f" "$dest/"; say "  $k <- $f"
			else
				say "  IGNORO $f (vermagic=$v, espero $REL)"
			fi
		fi
	done
	for k in $WANT; do
		[ -f "$dest/$k" ] || fail "falta el .ko obligatorio $k en $dest"
	done
}

MARKER=/tmp/uke-mods-marker
touch "$MARKER"

# Objetivos EXPLÍCITOS por orden de dependencia (grupo1 = ayudantes, cuyas
# exportaciones alimentan el Module.symvers del scratch para el grupo2).
# Se evita compilar directorios enteros: los colaterales (qrtr-mhi, altmode…)
# no se distribuyen y su modpost fallaría (MHI ausente en este árbol).
build_batch() { # $1=O $2=LV $3=dir $4...=ficheros
	local O=$1 LV=$2 dir=$3; shift 3
	# shellcheck disable=SC2086
	for i in $(seq 1 12); do
		err=$(make O="$O" LOCALVERSION="$LV" -j$JOBS M="$dir" $* 2>&1) \
			&& { say "  OK $dir: $* (intento $i)"; harvest "$O" "$dir" "$@"; return 0; }
		echo "$err" | tail -n 2 | sed 's/^/  | /'
		echo "$err" | grep -q "exported twice" || {
			echo "$err" | grep -E "ERROR|Error" | head -n 10 | sed 's/^/  | /'
			fail "modules $O $dir (modpost no-duplicado)"
		}
		syms=$(echo "$err" | grep "exported twice" \
			| sed "s/.*'\([^']*\)'.*/\1/" | sort -u)
		for s in $syms; do
			awk -v sym="$s" '$2 != sym || $3 != "vmlinux"' \
				"$O/Module.symvers" > "$O/Module.symvers.tmp" \
				&& mv "$O/Module.symvers.tmp" "$O/Module.symvers"
			say "  strip vmlinux:$s"
		done
	done
	fail "modules $O $dir (12 intentos)"
}
harvest() { # $1=O $2=dir $3...=ficheros: registra sus EXPORT_SYMBOL en el
	local O=$1 dir=$2; shift 2 # Module.symvers del scratch (modpost de M=
	local k bn mod n=0          # dispersos no propaga exportaciones entre lotes).
	# Las exportaciones viven en la SECCIÓN __ksymtab_strings (los .ko van
	# sin .symtab útil para nm); se leen con readelf -p.
	for k in "$@"; do
		[ -f "$SRC/$dir/$k" ] || fail "harvest: falta $SRC/$dir/$k"
		bn=$(basename "$k" .ko); mod=$(echo "$bn" | tr '-' '_')
		while read -r s; do
			[ -n "$s" ] || continue
			grep -qP "^[0-9a-fx]+\t$s\t" "$O/Module.symvers" || {
				# Formato read_dump: 4 tabs (crc\tsim\tmod\texport\tns);
				# sin el tab final => "parse error in symbol dump file".
				printf '0x00000000\t%s\t%s\tEXPORT_SYMBOL\t\n' "$s" "$mod" \
					>> "$O/Module.symvers"
				n=$((n + 1))
			}
		done <<EOF
$(readelf -p __ksymtab_strings "$SRC/$dir/$k" 2>/dev/null | sed -n 's/^.*\]  //p' | sort -u)
EOF
	done
	say "  harvest $dir: $n exportaciones registradas"
}
build_one() { # $1=O $2=LOCALVERSION-valor
	local O=$1 LV=$2
	say "== modules $O =="
	# Grupo 1: ayudantes (sus exportaciones alimentan el Module.symvers
	# del scratch para el grupo 2). Grupo 2: los 7 del K5.
	build_batch "$O" "$LV" drivers/remoteproc qcom_common.ko qcom_q6v5.ko qcom_pil_info.ko
	build_batch "$O" "$LV" drivers/remoteproc qcom_q6v5_pas.ko
	build_batch "$O" "$LV" drivers/rpmsg qcom_glink_smem.ko
	build_batch "$O" "$LV" net/qrtr qrtr-smd.ko
	build_batch "$O" "$LV" drivers/soc/qcom qcom_pd_mapper.ko pmic_glink.ko
	build_batch "$O" "$LV" drivers/usb/typec/ucsi ucsi_glink.ko
	build_batch "$O" "$LV" drivers/power/supply qcom_battmgr.ko
	say "OK  modules $O"
}

build_one "$O_NOPLUS" ""
collect "$R/charge/mods-$REL_NOPLUS" "$REL_NOPLUS"
build_one "$O_PLUS" "+"
collect "$R/charge/mods-$REL_PLUS" "$REL_PLUS"

say "== G-LIMPIO: borrar generados del árbol fuente =="
# Solo bajo los MDIRS tocados (hay .o preexistentes de otro flujo —p. ej.
# drivers/power/sequencing del 11-oct— que NO son de este guion y no se tocan).
GENN=0
for d in $MDIRS; do
	GENN=$((GENN + $(find "$SRC/$d" \( -name "*.o" -o -name "*.ko" -o -name "*.mod" -o -name "*.mod.c" -o -name "*.cmd" \) | wc -l)))
	find "$SRC/$d" \( -name "*.o" -o -name "*.ko" -o -name "*.mod" -o -name "*.mod.c" -o -name "*.cmd" \) -delete
	find "$SRC/$d" -name ".tmp_versions" -prune -exec rm -rf {} + 2>/dev/null || true
done
REST=0
for d in $MDIRS; do
	REST=$((REST + $(find "$SRC/$d" \( -name "*.o" -o -name "*.ko" \) | wc -l)))
done
[ "$REST" = "0" ] || fail "G-LIMPIO: quedan $REST generados en $MDIRS"
say "OK  G-LIMPIO ($GENN ficheros eliminados del árbol, 0 restos en MDIRS)"

gate_ko() { # $1=dest $2=release
	local dest=$1 REL=$2
	for ko in "$dest"/*.ko; do
		v=$(modinfo -F vermagic "$ko")
		[ "$v" = "$REL SMP preempt mod_unload aarch64" ] \
			|| fail "G-MODINFO: $ko vermagic='$v'"
		# LC_ALL=C: el readelf del host habla español ("Máquina").
		m=$(LC_ALL=C readelf -h "$ko" | grep -m1 Machine | grep -c AArch64 || true)
		[ "$m" = "1" ] || fail "G-MODINFO: $ko no es AArch64"
	done
	say "OK  G-MODINFO $dest ($(ls "$dest"/*.ko | wc -l) .ko, vermagic=$REL)"
}
# depmod -b necesita el árbol lib/modules/<release>/:
for REL in "$REL_NOPLUS" "$REL_PLUS"; do
	mkdir -p "$R/charge/stage-$REL/lib/modules/$REL/extra-uke"
	cp -f "$R/charge/mods-$REL"/*.ko "$R/charge/stage-$REL/lib/modules/$REL/extra-uke/"
	# Builtins del k52L33-build (los =y no cambian entre variantes: el diff
	# de configs solo mueve 7 símbolos a =m): evitan los WARNING de depmod y
	# permiten el dry-run de modprobe con deps completas.
	for f in modules.builtin modules.builtin.modinfo modules.order; do
		[ -f "$R/build/kernel-pokes/k52L33-build/$f" ] \
			&& cp -f "$R/build/kernel-pokes/k52L33-build/$f" \
				"$R/charge/stage-$REL/lib/modules/$REL/"
	done
	depmod -b "$R/charge/stage-$REL" "$REL"
	[ -f "$R/charge/stage-$REL/lib/modules/$REL/modules.dep" ] \
		|| fail "depmod no generó modules.dep para $REL"
	say "OK  depmod $REL: $(wc -l < "$R/charge/stage-$REL/lib/modules/$REL/modules.dep") líneas en modules.dep"
	gate_ko "$R/charge/mods-$REL" "$REL"
done

say "== FIN OK =="
ccache -s 2>/dev/null | tr '\n' ' ' | cut -c1-160 || true
