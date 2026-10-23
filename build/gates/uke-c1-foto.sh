#!/bin/sh
# uke-c1-foto.sh — foto de estado power (C1 ampliada, RONDA-A2 vía 5)
#
# Ejecutar EN LA TABLET justo ANTES de cada open de card0 (y opcionalmente
# tras la recuperación del boot siguiente, sobre el dmesg del boot nuevo).
# Escribe a /root/witness/ (UFS) para que sobreviva al reset.
# Solo lectura: nada de esto toca estado del dispositivo.

DIR=/root/witness
TS=$(date +%s)
F=$DIR/c1-$TS.txt

{
  echo "=== C1 FOTO $TS (pre-open) ==="
  echo "--- cmdline bootinfo:"
  cat /proc/cmdline | tr ' ' '\n' | grep -E 'bootinfo|uke_|panic|watchdog' 
  echo "--- GDSC (pm_genpd_summary):"
  grep -E -B1 -A2 'gpu|gmu|cx|gx' /sys/kernel/debug/pm_genpd/pm_genpd_summary 2>/dev/null
  echo "--- regulators GPU (regulator_summary):"
  grep -E -A1 'kgsl|gpu|cx|gfx' /sys/kernel/debug/regulator/regulator_summary 2>/dev/null
  echo "--- interconnect GPU (se sabe: vacío en reposo — confirmar pre-muerte):"
  grep -iE 'gpu|gmu|kgsl' /sys/kernel/debug/interconnect/interconnect_summary 2>/dev/null || echo "(sin líneas GPU o fichero ausente)"
  echo "--- clocks GPU/GMU (clk_summary):"
  grep -iE 'gpu|gmu|gfx' /sys/kernel/debug/clk/clk_summary 2>/dev/null
  echo "--- devfreq registrado:"
  ls /sys/class/devfreq/ 2>/dev/null
  echo "--- remoteproc (se sabe: vacío):"
  ls /sys/class/remoteproc/ 2>/dev/null || echo "(ninguno)"
  echo "--- rpmh debugfs (mainline no la expone — verificar):"
  ls /sys/kernel/debug/rpmh/ 2>/dev/null || echo "(ausente en mainline)"
  echo "--- iommu grupos GPU:"
  ls /sys/kernel/iommu_groups/0/devices/ /sys/kernel/iommu_groups/1/devices/ 2>/dev/null
  echo "--- drv GMU/GPU estado sysfs:"
  for d in /sys/bus/platform/devices/*kgsl-3d0 /sys/bus/platform/devices/*gmu; do
    echo "$d:"; grep -E 'state|power/' -r "$d" 2>/dev/null | head -4
  done
  echo "=== FIN C1 ==="
} >> "$F" 2>&1
sync
echo "C1 foto en $F ($(wc -l < "$F") líneas)"
