# Plan tras el hito (17-oct ~22:4x): kernel MCC45TR + nuestro rootfs = panel con imagen y 'uke-arch login'

Estado: slot a = boot senemos 4894a841 + dtbo_a STOCK; userdata = rootfs Arch 8 GiB. Sin USB/SSH (gadget no aparece).

1. Conexion (bloqueante): kernel v2 con USB gadget (dr_mode/rol del DWC3 en su overlay) + modulos generados.
   -> SENEMOS-V2-USB-20261017.md, boot-uke-senemos-7.2.9-v2.img, flash-senemos-v2-gated.sh (solo boot_a).
2. Modulos: instalar /lib/modules/<release> de su build en el rootfs (tar | ssh) + depmod.
3. Carga: nuevo stack para su kernel (ADSP PAS manual + pmic_glink/battmgr de su build). -> deploy/carga, CARGA-SENEMOS.
4. WiFi: WPSS + ath11k AHB, firmware BDF o82gl/regdb/WPSS desde capturas Android. -> deploy/wifi, WIFI-SENEMOS.
5. Omarchy + GPU: paquetes offline de stage-escritorio (Hyprland, quickshell, sddm autologin), firmware gen71100,
   migraciones offline. -> deploy/omarchy, OMARCHY-SENEMOS.
6. Despues: tactil NT36532 (su panel gestiona el reset compartido), BT, audio, KTZ dual (su 0025), qbootctl -m (decision).
7. Con SSH: medir su estado (ICC, MMCX, PHY, ACTLR, underrun) frente a L77b para saber que nos faltaba exactamente.
Cada flash con fila de ledger y orden del dueño; fastboot siempre a mano (Power+Vol-).
