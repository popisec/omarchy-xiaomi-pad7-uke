# Ofensiva GPU 3-oct-2026 — síntesis de 3 subagentes + verificaciones propias (ledger #515/#516)

## Muertas hoy sin flashear
- TBU gpu_qtb@3de8000: el dmesg ANDROID de esta tablet muestra los 9 TBUs con probe fallido
  («Unable to get the transactiontracker-base») y la GPU funciona — mainline comparable
  (sm8250/8550/8650) arranca SIN nodos TBU. K48-TBU ARCHIVADO.
- Warm-boot/TCM-retention: pokes F1-fwloop/F2-itcm presentes en capturas → fw se carga (frío).
- Zap como causa del muro: se carga en hw_init DESPUÉS del CM3 (jamás ejecutado en boot medido).
  BOMBA LATENTE: DT pide «qcom/uke/gen71100_zap.mbn», initramfs lleva «qcom/gen71100_zap.mbn»
  (request_firmware_direct sin fallback) → arreglar antes de que caiga el muro.

## Deltas vivos contra vendor/mainline
1. hub_clk real 400 MHz vs 200 MHz exigido (clk_set_rate ignora rc y corre antes de prepare).
2. ACTLR 0x32b: vendor lo aplica a TODOS los SIDs del kgsl-smmu (incl. GMU/SID5); upstream no
   escribe ACTLR para el CB del GMU.
3. Poll FW_INIT_RESULT usa DTCM STALE del boot anterior para elegir 0xbabeface vs 0x100
   (a6xx_gmu.c:640-648) — falso-FAIL posible con CM3 sano.
4. DT: rscc reclamado por GPU y GMU a la vez; mboxes=aop caído; vendor sin reloj demet;
   qsmmu-v500 con 2º reg tcu-base 0x3de6000; secure vendor CB2/SID2 vs mainline SID1;
   zap region real 8 KB @0x9899a000.
5. qmp_send(acd) existe (a6xx_gmu.c:2570) pero condicionado a opp-acd-level — sin miga que
   confirme que corre.

## Datos vendor clave (gen7-11-0 / Adreno732, chipid 0x43030b00)
- SIDs: user=0, secure=2, gmu=5 (CB5). GMU FW versión 4.5.0. GENERAL_10 = REV 0x070b0000 ✓.
- fw vendor: gen71100_{sqe.fw,gmu.bin,zap.mbn} (zap firmado por SKU — el del QRD 8635 NO vale).
- gmufreq 220/550 MHz; gmu_hub_clk_freq 200 MHz; gmem 1.5 MB; gdsc cx@0x3d9908c gx@0x3d99034.

## Plan rankeado (ejecutar tras recuperar acceso con rootfs v3)
C1 repack `msm.uke_smmu_dump=1` (kernel K44 existente) → WALK CB1 iova 0x4000 = PA real del
   fetch del icache (cierra el único modo de fallo no excluido: traducción válida a PA malo).
C2 repack sin `msm.uke_gmu_shared=0` → A/B stall-vs-wedge; posible máquina VIVA en el muro.
C3 hub 200 MHz (rc + orden + assigned-clocks).
C4 ACTLR del CB del GMU (1 línea arm-smmu-qcom).
C5 migas de poll-stale + qmp_send(acd).
C6 diff formal DT portado vs base-uke.dts vs sm8650.dtsi (0 escrituras).
