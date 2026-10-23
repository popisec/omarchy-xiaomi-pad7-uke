#!/bin/sh
# SOLO LECTURA. Uso: collect-remote.sh <seccion>
dump(){ for f in "$@"; do [ -f "$f" ] || continue; echo "=== $f"; timeout 10 cat "$f" 2>&1 | head -c 400000; echo; done; }
B=/sys/kernel/debug/dri/ae01000.display-controller
case "$1" in
dri1)
 for f in state clients framebuffer gem gem_names fb kms mm name shrink; do dump $B/$f; done
 for d in $B/encoder-*; do dump $d/status $d/bridges; done
 for d in $B/crtc-*; do dump $d/state $d/status; done
 dump $B/DSI-1/* $B/Writeback-1/*
 dump $B/debug/core_irq $B/debug/core_perf/* $B/debug/danger/* $B/debug/vbif/*
 for d in $B/debug/sspp/*; do dump $d/*; done
 echo "=== LISTADO dri/0"; ls -la /sys/kernel/debug/dri/ /sys/kernel/debug/dri/3d00000.qcom,kgsl-3d0/
 for f in name clients gem gem_names mm; do dump /sys/kernel/debug/dri/3d00000.qcom,kgsl-3d0/$f; done ;;
sysdrm)
 for d in /sys/class/drm/*; do echo "=== $d"; for a in status enabled dpms modes; do [ -f $d/$a ] && { echo "-- $a"; timeout 5 cat $d/$a; }; done; done ;;
irq) cat /proc/interrupts ;;
clk) cat /sys/kernel/debug/clk/clk_summary ;;
icc) cat /sys/kernel/debug/interconnect/interconnect_summary ;;
reg) cat /sys/kernel/debug/regulator/regulator_summary ;;
genpd) cat /sys/kernel/debug/pm_genpd/pm_genpd_summary; for d in /sys/kernel/debug/pm_genpd/*; do [ -d $d ] && for f in $d/*; do dump $f; done; done ;;
iommu) for g in /sys/kernel/iommu_groups/*; do echo "=== $g: $(cat $g/name 2>/dev/null) type=$(cat $g/type 2>/dev/null)"; ls $g/devices; done; ls -la /sys/kernel/debug/iommu* 2>&1 ;;
dmesg) dmesg ;;
journal) journalctl -k --no-pager 2>&1 | tail -n 3000 ;;
esac
