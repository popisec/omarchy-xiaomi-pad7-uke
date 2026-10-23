# VERIF-HERMANO-PANTALLA — ¿qué boots encendieron la pantalla? (14-oct-2026, SOLO LECTURA)

## Veredicto en una frase
Ningún kernel propio (fork ni mainline) ha encendido el panel **por sí mismo**; toda luz
documentada vino del **ABL** (splash/texto) o del **painter** escribiendo en el framebuffer
del splash heredado (`0xE3940000`). El stack DRM vendor sí bindeó completo (con LOG), pero
sin luz visible probada.

## 1. Luz REAL con contenido visible al ojo (categoría a) — testimonio, sin fichero de log
- **Painter del fork, 19→21-sep** (`ubuntu-permanente/docs/FLASH-LEDGER.md` #242 l.433,
  #247 l.589, #249-#250, #331): dueño lee en pantalla barra verde + sellos (`s110-uno`,
  `s113-pokes`, `rst-TO`, log de 1096 líneas). Receta: kernel fork + dtbo con
  `splash_region` + `no-map` (s131-FIXED frag.126/127; el dtbo STOCK la declara SIN
  no-map ⇒ painter OFF, l.1951) + `set_active b` antes (solo el PRIMER arranque hace el
  traspaso de splash, l.1935). 1 foto Pixel citada (#247) **no preservada en repo**.
- **Android stock slot a, 21-sep** (#287 l.1434: dueño confirma "splash HyperOS y crash
  instantáneo"; #298: "Android YA ARRANCA en el slot a"). La pregunta "¿se ve el logo
  HyperOS?" quedó **pendiente** (#298 l.1649). Testimonio parcial.
- **ABL**: "solo las 2 líneas del ABL" sin pintor (#239-#242); pantallas de texto
  `unbootable` (foto pendiente, l.403). Testimonio.

## 2. Con LOG preservado (pero SIN luz visible probada)
- **T13/B7, 04-sep** (`ubuntu-uke/dump/observabilidad/core-bisect-20260904-2040/T13-b7-fix-arranca/dmesg.txt`):
  bind vendor completo — `Successfully bind display panel 'qcom,mdss_dsi_o82…'`,
  `ktz8866 probe sucess` ×2, `Registered DISP CC clocks`, adb 11 s. Receta (§RECETA):
  kernel GKI 6.1.176 `be9e5296` (MODVERSIONS=y) + `fastboot boot`, RAMDISK_SZ=0
  (ramdisk stock ⇒ arranca **Android**, no Ubuntu). Luz: NO probada (sin testimonio visual).
- **sanity-b9b, 05-sep** (`ubuntu-uke/dump/observabilidad/ubuntu-20260905-0043/`):
  `sanity-b9b.txt` (card0, ktz dual, `boot_completed=1`) + `sanity-b9b-screencap.png`
  — verificado hoy: el PNG es **negro 2136×3200**. "screencap OK" = el comando funcionó,
  no que hubiera imagen.
- **Fork #410, 25-sep** (ledger l.4110): panel probea (`/sys/class/backlight/ae94000.dsi.0`,
  `uke_panel_vsp/vsn supplying 5800000uV`) pero `no IOMMU, bailing out` ⇒ sin `/dev/dri`.
  Receta: boot-s209 `f6946f35` + dtbo s211 + `gpio-shared-proxy.ko`. Observado por SSH/dmesg.

## 3. Negativos (útiles): M1/M2/simplefb siempre negros
M1 (DT propio) y M2 (U-Boot, latido VERDE start.S) → negro + vuelta a fastboot ~2 min
(#327-#329); el ABL apaga el panel (`DisableDisplay`) con DTB no-stock. `fastboot boot`
SIN dance ⇒ sin handoff de splash ⇒ painter apagado aunque el kernel viva (#324).

## Implicación para omarchy-uke
El precedente útil no es un driver DRM sino el **painter sobre splash heredada tras dance**:
la luz requiere que el ABL deje el panel escaneando. KTZ al máximo + DRM OK sin luz apunta a
falta de encendido/scanout del panel (DCS/power), no de backlight.
