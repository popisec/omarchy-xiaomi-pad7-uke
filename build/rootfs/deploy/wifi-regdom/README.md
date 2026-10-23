# WiFi: dominio regulador ES + red del portátil (20-oct-2026)

**Síntoma**: la tablet veía RED-EJEMPLO-1 (5500 MHz, canal 100 DFS, y 2462 MHz) pero no asociaba («ssid-not-found», CONN_FAILED).
**Causas medidas**:
1. Faltaba `wireless-regdb` (`cfg80211: failed to load regulatory.db`) → dominio global «00» (canal 100 y canal 11 solo pasivos).
   Instalados `wireless-regdb 2026.09.03-1` e `iw 6.17-1` por `pacman -U` desde el mirror de ALARM (con .sig; la tablet no tenía red).
   ES persistente: `/etc/conf.d/wireless-regdom` (WIRELESS_REGDOM="ES") + `modprobe.d/uke-regdom.conf` (`cfg80211 ieee80211_regdom=ES`).
   (El phy self-managed de ath11k ya decía ES/DFS-ETSI, como Android.)
2. El router está en modo de transición WPA2/WPA3 (PSK+SAE, MFP); el supplicant elige SAE y SAE necesita la contraseña, no el PSK
   derivado de 64 hex («SAE: No password available»). El perfil guarda la contraseña en el keyfile de NM (root 600), copiada del
   portátil por tubería sin mostrarse ni pasar por argumentos ni por el repo.
3. chrony no tenía hook de NM: sus fuentes seguían offline → `dispatcher.d/20-uke-chrony` (`chronyc onoffline`) y
   `systemctl enable NetworkManager-dispatcher` (estaba deshabilitado: sin él no corre ningún script de dispatcher.d).
**Resultado**: wlan0 conectada (192.0.2.11, 5500 MHz 160 MHz, 1,9 Gbit/s, −43 dBm), autoconnect prioridad 20, NTP sincronizado,
desfase del RTC guardado. El perfil antiguo RED-EJEMPLO-3_5G se conserva.
