# PLAN de RECUPERACIÓN de la dorada (4-oct, subagente; verificado contra disco y ledger)

DORADA: boot_a=boot-ukek49-esd-plyoff.img (6988dc7b…), dtbo_a=s266 (15fdbbd3…),
userdata=/var/tmp/rootfs-uke-k521.img v7 (5f9f00fe…). Script: docs/historia/gates-palawan/flash-k49.sh
con K49_BOOT/K49_BOOT_SHA POR ENTORNO (¡sin K49_BOOT flashea el kernel SIN plyoff!).
dtbo s266 va fijo dentro del script. Rollback: par bueno e0ee47dc en build/backup-par-bueno/
(2 copias) + s262 (6eda5956…).

## Hallazgos clave
- vbmeta_a JAMÁS se escribió; vbmeta_a==vbmeta_b==0f7399d9… (131072 B, Flags 0) — sin
  copia local de vbmeta_system_a: CAPTURARLA antes del experimento Android (paso 0.3).
- ABL desbloqueado ignora verificación: la dorada arranca con vbmeta tal cual está.
- /etc/uke-rootfs-version NO existe en v7 (deuda guardrail 3): escribirla a mano al primer
  boot (guardrail 3).
- Red USB 192.168.42.129/24 va HORNEADA en la imagen (10-uke-usb.network) — vuelve sola.
- vendor_boot_a/init_boot_a en STOCK del 28-sep (backups en build/backup-par-bueno/ con shas).
- Flash userdata ~30-40 s; manda el OKAY, no el reloj.
- battery-soc-ok:no en consola = guard del ABL (no kernel «que no carga»): cargador y retry.

## FASE 0 — PRE (salvaguardas)
1. Batería: ≥3700 mV flashear; ≥3900/cargador para estabilidad.
2. Si viva: scp de /var/log/uke-cazador.log + journalctl -b + dmesg a build/evidencia/.
3. Captura dd|sha256 de boot_a dtbo_a vbmeta_a vbmeta_b vbmeta_system_a/b vendor_boot_a
   init_boot_a + /proc/cmdline → build/evidencia/particiones-pre-*.txt.
4. getvar all congelado a evidencia.

## FASE 1 — VUELTA (desde fastboot)
6. set_active a si hace falta; re-medir batería.
7. SOLO si el userdata fue borrado: fastboot flash userdata /var/tmp/rootfs-uke-k521.img
   (esperar OKAY; la clave SSH y la red vuelven con la imagen).
8. SOLO si el experimento tocó vbmeta: restaurar higiene (vbmeta_a/b ← gpu-work/vbmeta-stock-128k.img;
   vbmeta_system desde capturas del 0.3). Si fue solo slot b: omitir.
9. Dorada: flash-k49.sh --dry-run primero; luego real (exención de un solo uso si <3700).
   NO tocar vendor_boot_a/init_boot_a salvo restauración con sus backups como ciclo aparte.

## FASE 2 — POST (verificación EN ORDEN)
10. Consola: battery-soc-ok:no ⇒ cargador; UKE-DIAG ~40 s; UKE-FIX en kmsg.
11. SSH 192.168.42.129.
12. dd|sha256 de boot_a/dtbo_a (¡la única verdad!) == dorada.
13. voltage_now ≥3900 o Charging.
14. sshd active; uke-cazador **disabled**; uke-fix/uke-diag enabled; red arriba.
15. Escribir /etc/uke-rootfs-version a mano + changelog en ledger.
16. Ledger #52x; cierre de sesión = dorada + SSH verificado.

## FASE 3 — ROLLBACK
18. 7 muertes → fastboot es documentado (carga allí): --dry-run, set_active a, retry ×1.
19. Fallback slot b: flash boot_b=backup-par-bueno/boot-ukek13-dsid.img (e0ee47dc…) +
    dtbo_b=s262 (6eda5956…) + set_active b (guardrail 7: ejercitar de una vez).
20. BCB raro → build/gates/bcb-clean-8192.py como ciclo aparte.
21. Última línea: stock íntegro de backup-par-bueno + EDL dump gpu-work/uke-rom-edl/.
