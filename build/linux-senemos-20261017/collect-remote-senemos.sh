#!/bin/sh
# SOLO LECTURA (cat/ls/dmesg). Uso: ssh ... 'sh -s -- <seccion>' < collect-remote-senemos.sh
# Derivado de build/linux-l76r-20261017/drm/collect-remote.sh. Diferencias:
#  - NO lee state, kms, crtc-*/state, crtc-*/crc, hw_log_mask, shrink (regla dura de la sesion).
#  - dri se descubre por nombre (ae01000.display-controller; dri/0 es un symlink a el).
dump(){ for f in "$@"; do [ -f "$f" ] || continue; echo "=== $f"; timeout 10 cat "$f" 2>&1 | head -c 400000; echo; done; }
B=/sys/kernel/debug/dri/ae01000.display-controller
D=/sys/kernel/debug
case "$1" in
dri-reposo)
 dump $B/name $B/clients
 for d in $B/encoder-*; do dump $d/status $d/bridges; done
 dump $D/dri/bridges
 for d in $B/crtc-*; do dump $d/status; done
 dump $B/DSI-1/*
 dump $B/debug/core_irq $B/debug/core_perf/* $B/debug/danger/* $B/debug/vbif/*
 for d in $B/debug/sspp/*; do dump $d/*; done
 echo "=== LISTADO"; ls -la $D/dri/ ;;
dri-plano)
 for d in $B/encoder-*; do dump $d/status; done
 for d in $B/crtc-*; do dump $d/status; done
 dump $B/debug/core_irq $B/debug/core_perf/* $B/debug/danger/* ;;
regdetail)
 # detalle por regulador (debugfs, solo software): consumidores con min_uV/max_uV = votos de nivel MMCX/MX/CX
 for r in $D/regulator/*mmcxlvl-pm_v8_s6_level $D/regulator/*cxlvl-pm_v6c_s1_mmcx_sup_level $D/regulator/*cxlvl-pm_v6c_s1_level $D/regulator/*mxlvl-pm_v8_s8_level $D/regulator/*mxclvl-pm_v6c_s6_level $D/regulator/*mxclvl-pm_v6c_s6_mmcx_voter_level $D/regulator/*ldob8-pmxr2230_l8 $D/regulator/*ldob4-pmxr2230_l4 $D/regulator/*ldob2-pmxr2230_l2 $D/regulator/display_panel_vsp $D/regulator/display_panel_vsn; do
  [ -d "$r" ] || continue
  echo "##### $r"; find "$r" -type f | sort | while read f; do printf '%s: ' "${f#$r/}"; timeout 5 cat "$f" 2>&1 | tr '\n' ' '; echo; done
 done ;;
opp)
 for o in $D/opp/*display* ; do [ -d "$o" ] || continue; echo "##### $o"; find "$o" -type f | sort | while read f; do printf '%s: ' "${f#$o/}"; timeout 5 cat "$f" 2>&1 | tr '\n' ' '; echo; done; done ;;
sysdrm)
 for d in /sys/class/drm/*; do echo "=== $d"; for a in status enabled dpms modes; do [ -f $d/$a ] && { echo "-- $a"; timeout 5 cat $d/$a; }; done; done ;;
irq) cat /proc/interrupts ;;
clk) cat $D/clk/clk_summary ;;
icc) cat $D/interconnect/interconnect_summary ;;
icc-graph) cat $D/interconnect/interconnect_graph ;;
reg) cat $D/regulator/regulator_summary ;;
genpd) cat $D/pm_genpd/pm_genpd_summary; for d in $D/pm_genpd/*; do [ -d $d ] && for f in $d/*; do dump $f; done; done ;;
iommu) for g in /sys/kernel/iommu_groups/*; do echo "=== $g: $(cat $g/name 2>/dev/null) type=$(cat $g/type 2>/dev/null)"; ls $g/devices; done; ls -la $D/iommu* 2>&1 ;;
dmesg) dmesg ;;
rpmh)
 echo "=== cmd-db"; ls -la $D/cmd-db; timeout 10 cat $D/cmd-db 2>&1 | head -c 400000
 echo "=== mailbox_summary"; timeout 10 cat $D/mailbox/mailbox_summary 2>&1
 echo "=== remoteproc"; for r in /sys/class/remoteproc/*; do echo "$r $(cat $r/name 2>/dev/null) $(cat $r/state 2>/dev/null)"; done
 echo "=== ls rpmh/aoss"; ls -la $D/qcom_aoss $D/qcom_socinfo 2>&1
 echo "=== opp"; ls $D/opp 2>&1 | head -60
 echo "=== ls regulator"; ls $D/regulator 2>&1 | head -200 ;;
sistema)
 echo "=== uname"; uname -a
 echo "=== cmdline"; cat /proc/cmdline
 echo "=== devices_deferred"; cat $D/devices_deferred
 echo "=== lsmod"; lsmod
 echo "=== uptime"; uptime; cat /proc/loadavg
 echo "=== backlight"; for b in /sys/class/backlight/*; do echo "$b $(cat $b/brightness) / $(cat $b/max_brightness) bl_power=$(cat $b/bl_power)"; done
 echo "=== platform devices display"; ls /sys/bus/platform/devices | grep -Ei 'ae0|ae9|mdss|dsi|disp|smmu|dpu|rsc|icc|interconnect' ;
 echo "=== driver binding"; for d in ae00000.display-subsystem ae01000.display-controller ae94000.dsi ae96000.dsi ae94400.phy ae96400.phy af00000.clock-controller; do [ -e /sys/bus/platform/devices/$d ] && echo "$d -> $(readlink /sys/bus/platform/devices/$d/driver 2>/dev/null)"; done
 echo "=== kernel config display"; zcat /proc/config.gz 2>/dev/null | grep -E 'CONFIG_DRM_MSM|CONFIG_INTERCONNECT|CONFIG_QCOM_ICC|CONFIG_ARM_SMMU|CONFIG_QCOM_RPMH|CONFIG_QCOM_COMMAND_DB|CONFIG_PHY_QCOM|CONFIG_SM_DISPCC' ;;
esac
