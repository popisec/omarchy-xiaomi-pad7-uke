# Suspensión en la uke (kernel senemos v3) — 18-oct-2026

Validada por etapas (orden del dueño), con `uke-pmtest.sh` (desacoplado con systemd-run; log en /var/log/uke-pmtest.log):

| Etapa | Resultado |
|---|---|
| `pm_test=freezer` + freeze | rc 0 en 5 s |
| `pm_test=devices` + freeze (todos los drivers suspenden/reanudan) | rc 0, dmesg sin errores; WiFi, táctil (recarga gen 3), carga, ADSP/WPSS, display (underrun 0) y Hyprland de vuelta |
| s2idle real, `rtcwake -m freeze -s 20` | dormida 22 s, despertar por IRQ 184 `pm8xxx_rtc_alarm`; todo de vuelta |
| `systemctl suspend` (con `MemorySleepMode=s2idle`) + alarma RTC 30 s | `PM: suspend entry (s2idle)` → despertar a los 32 s; suspend_stats 4 OK / 0 fallos |

Configuración (en la tablet y en `root/`):
- `/etc/systemd/sleep.conf.d/10-uke-s2idle.conf`: solo s2idle; el `deep` del kernel (PSCI SYSTEM_SUSPEND) NO está probado.
  Hibernación prohibida y sus targets enmascarados (sin swap, sin probar).
- `omarchy-sleep-lock.service` enmascarado para el usuario omarchy (`~/.config/systemd/user/… -> /dev/null`): la cuenta no
  tiene contraseña y no hay teclado ni teclado en pantalla → el bloqueo dejaría la sesión atascada. Revertir:
  `systemctl --user unmask omarchy-sleep-lock.service` cuando haya forma de desbloquear.
- Fuentes de despertar con wakeup=enabled: `pmic_pwrkey` (botón de encendido; logind HandlePowerKey=ignore), `gpio-keys`,
  alarma RTC.

**Despertar con el botón de encendido: OK** (18-oct 01:38, IRQ 120 `pmic_pwrkey`, `systemctl suspend` sin alarma RTC).
**Botón = suspender (bind de Hyprland → uke-power-button): confirmado por el dueño** — suspende, despierta y se queda despierta.
No verificado: consumo en reposo (no hay `qcom_stats`; medir con una suspensión larga y la caída de capacidad),
suspensiones largas, hypridle (no corre; su config suspende a los 30 min y
bloquea a los 5) y la tapa/funda (hall).

## WiFi tras suspender (18-oct 10:35)
Al suspender, mac80211 desconecta (`reason=3 locally_generated`, sin WoWLAN). Normalmente reconecta en ~5 s, pero tras 3
suspensiones seguidas (01:45) el escaneo de wpa_supplicant quedó atascado 9 h en SCANNING sin resultados hasta un
`wpa_cli scan` manual. Arreglo: el gancho `uke-resume-stamp` lanza (desacoplado) un escaneo a los 3 s y `reassociate` si a los
20 s no está COMPLETED. Probado: `systemctl suspend` + alarma 15 s → CONNECTED 5 s tras reanudar, ping OK.
(La traza `qdss already disabled` de clk.c al reanudar es del reloj de coresight; inocua para el WiFi, pendiente aparte.)
