#!/bin/bash
# build-v8b-propios.sh — 23-oct-2026: recompila los .ko PROPIOS de la tablet contra un arbol de build, con las MISMAS recetas del repo
# (build/rootfs/deploy/*), sin escribir en las carpetas del repo: todo va a build/kernel-pokes/optim-ouke6/v8b-propios/<modo>/ (ignorado).
#   repro : contra el arbol ouke5 (senemos-ouke5/build) y compara el sha con el .ko INSTALADO en la tablet (medido 23-oct por SSH):
#           si coincide, la receta queda demostrada (build reproducible) y su salida ouke8 es de fiar.
#   ouke8 : contra build8 (v8b, release -ouke8). Exige build8/modroot (= modinst de build-v8b.sh).
# DESPRENDIDO (regla 6): setsid nohup bash build/gates/build-v8b-propios.sh <modo> >/dev/null 2>&1 &
# Cada familia es independiente: un fallo se anota y se sigue con la siguiente. Resumen en <salida>/RESUMEN.txt.
set -uo pipefail
MODO=${1:?repro|ouke8}
R=/home/USUARIO/proyectos/omarchy-uke
D=$R/build/rootfs/deploy
case "$MODO" in
  repro) KB=$R/build/kernel-pokes/senemos-ouke5/build; KT=$R/build/kernel-pokes/senemos-ouke5/linux-7.2.9 ;;
  ouke8) KB=$R/build/kernel-pokes/optim-ouke6/build8; KT=$R/build/kernel-pokes/optim-ouke6/linux-7.2.9 ;;
  *) echo "modo $MODO"; exit 2 ;;
esac
O=$R/build/kernel-pokes/optim-ouke6/v8b-propios/$MODO
[ -n "${SOLO:-}" ] || rm -rf "$O"; mkdir -p "$O"
exec > "$O/build${SOLO:+-$(echo $SOLO | tr " " _)}.log" 2>&1
export KB KT
KREL=$(cat "$KB/include/config/kernel.release")
echo "[propios] $MODO KB=$KB KREL=$KREL inicio $(date -Is)"
[ -d "$KB/modroot/lib/modules/$KREL" ] || { echo "falta $KB/modroot/lib/modules/$KREL (bt/hciqca la necesitan)"; }
fam() {  # fam NOMBRE comando...   (SOLO="a b" limita las familias)
  local n=$1; shift
  [ -z "${SOLO:-}" ] || [[ " $SOLO " == *" $n "* ]] || return 0
  mkdir -p "$O/$n"
  echo "== [$n] $*"
  if ( cd "$O/$n" && OUT="$O/$n" "$@" ) > "$O/$n/receta.log" 2>&1; then echo "   [$n] OK"; else echo "   [$n] FALLO rc=$? (ver $n/receta.log)"; fi
}
fam audio      bash "$D/audio/build-module.sh"
fam fs19xx     bash "$D/audio/fs19xx/build.sh"
fam q6apm      bash "$D/audio/q6apm-port/build.sh"
fam bt         bash "$D/bt/build.sh"
fam hciqca     bash "$D/bt/hciqca/build-hciqca.sh"
# camaras: variante del ciclo 24 (la instalada): sondas de depuracion + nombre qcom-camss (receta de c5-ciclo12..15.sh SIN UKE_CPHY_RX_HZ + c5-ciclo24.sh; verificado por sha)
fam camaras    env CPPX=-DWITH_IOMMU UKE_SENSDBG=1 UKE_RXIRQ=1 UKE_CSID_LOG=1 UKE_PHY_LOG=1 UKE_CAMSS_NAME=qcom-camss bash "$D/camaras/build.sh"
fam vcm        bash "$D/camaras/vcm/build-vcm.sh"
# qcom-stats y tapa: sus build.sh escriben en su carpeta out/ del repo => misma receta, replicada aqui con salida en $O
qstats() { S=$(mktemp -d); cp "$D"/bateria/qcom-stats/src/* "$S/"
  env -u MAKEFLAGS -u MFLAGS -u MAKELEVEL MAKE=/usr/bin/make ARCH=arm64 LLVM=1 /usr/bin/make -C "$KB" M="$S" modules > "$S/make.log" 2>&1 || { cat "$S/make.log"; return 1; }
  [ -s "$S/uke_qcom_stats.ko" ] || return 1; cp "$S/uke_qcom_stats.ko" "$OUT/"; rm -rf "$S"
  [ "$(modinfo -F vermagic "$OUT/uke_qcom_stats.ko" | cut -d' ' -f1)" = "$KREL" ]; }
tapa() { S=$(mktemp -d); cp "$D"/tapa/module/Kbuild "$D"/tapa/module/uke_tapa.c "$S/"
  env -u MAKEFLAGS -u MFLAGS -u MAKELEVEL MAKE=/usr/bin/make ARCH=arm64 LLVM=1 UKE_OVL_DIR="$D/tapa/out" UKE_OVL_HDR="$D/bt/module" \
    /usr/bin/make -C "$KB" M="$S" modules > "$S/make.log" 2>&1 || { cat "$S/make.log"; return 1; }
  [ -s "$S/uke_tapa.ko" ] || return 1; cp "$S/uke_tapa.ko" "$OUT/"; rm -rf "$S"
  [ "$(modinfo -F vermagic "$OUT/uke_tapa.ko" | cut -d' ' -f1)" = "$KREL" ]; }
export -f qstats tapa; export D KREL
fam qcom-stats bash -c qstats
fam tapa       bash -c tapa

# --- correspondencia con lo instalado en la tablet (destino:fichero de salida:sha16 instalado 23-oct) ---
cat > "$O/mapa.txt" <<'EOF'
extra/uke_audio_e2d.ko         audio/uke_audio_e2d.ko          57efddc6b44b761f
extra/uke_audio_e3.ko          audio/uke_audio_e3.ko           4cb583d3d2251967
extra/uke_audio_e5.ko          audio/uke_audio_e5.ko           a9e4b7b0ef33f175
extra/uke_audio_e7i2c.ko       audio/uke_audio_e7i2c.ko        9004ad56a758bc73
extra/uke_audio_e8a.ko         audio/uke_audio_e8a.ko          8f39831040f56855
extra/uke_audio_e8b.ko         audio/uke_audio_e8b.ko          2f8e8fb9b33cdf12
extra/uke_audio_e9a.ko         audio/uke_audio_e9a.ko          85516d3a7a31535c
extra/uke_fs19xx.ko            fs19xx/uke_fs19xx.ko            2bafe13f872328c8
updates/snd-q6apm.ko           q6apm/snd-q6apm-uke.ko          be7eeecbf901c8f0
updates/q6apm-lpass-dais.ko    q6apm/q6apm-lpass-dais-uke.ko   80e6045c24435b67
extra/uke_bt_a.ko              bt/uke_bt_a.ko                  cf7b4ee350535c6e
extra/uke_bt_b.ko              bt/uke_bt_b.ko                  8c7f579b3f81a71b
extra/uke_bt_uart.ko           bt/uke_bt_uart.ko               6cf35d48a8e07a43
updates/hci_uart.ko            hciqca/hci_uart.ko              493ef41c951f76a7
extra/uke_qcom_stats.ko        qcom-stats/uke_qcom_stats.ko    923617ab783ae05c
extra/uke_tapa.ko              tapa/uke_tapa.ko                285d244988f5afe1
camaras/uke_cam_camcc.ko       camaras/uke_cam_camcc.ko        e32413e297a19d65
camaras/camcc-cliffs-uke.ko    camaras/camcc-cliffs-uke.ko     72306f63dc90dc1c
camaras/uke_cam_rear.ko        camaras/uke_cam_rear.ko         6a4fa4c28ec12e71
camaras/uke_ov13b10.ko         camaras/uke_ov13b10.ko          bd616d896aa5d369
camaras/uke_cam_camss.ko       camaras/uke_cam_camss.ko        161ad52c94d0f745
camaras/uke_cam_front.ko       camaras/uke_cam_front.ko        477d8956d5d7fce6
camaras/uke_ov08d10.ko         camaras/uke_ov08d10.ko          2d64470b373a7cb4
camaras/uke-camss.ko           camaras/uke-camss.ko            c89992964baed146
camaras/uke_rpmh_ldob14.ko     vcm/uke_rpmh_ldob14.ko          16da40a5dcab3b67
camaras/uke_cam_lens.ko        vcm/uke_cam_lens.ko             695b6a917b5e1ecb
camaras/uke_dw9714.ko          vcm/uke_dw9714.ko               5d30c41e82a2ca40
EOF
{
  echo "# $MODO ($KREL) $(date -Is) — destino  salida  sha16  vermagic  [repro: == instalado?]"
  while read -r dst src want; do
    f=$O/$src
    if [ -s "$f" ]; then
      s=$(sha256sum "$f" | cut -c1-16); vm=$(modinfo -F vermagic "$f" | cut -d' ' -f1)
      if [ "$MODO" = repro ]; then [ "$s" = "$want" ] && r=IGUAL || r=DISTINTO; else [ "$vm" = "$KREL" ] && r=vermagic-ok || r=VERMAGIC-MAL; fi
      printf '%-28s %-32s %s %s %s\n' "$dst" "$src" "$s" "$vm" "$r"
    else printf '%-28s %-32s %s\n' "$dst" "$src" "NO-GENERADO"; fi
  done < "$O/mapa.txt"
} > "$O/RESUMEN.txt"
cat "$O/RESUMEN.txt"
echo "[propios] FIN $(date -Is)"
