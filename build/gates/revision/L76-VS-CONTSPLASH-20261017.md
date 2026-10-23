> **CORRECCION 17-oct ~12:45 (captura sleep20, build/android/vendor-harvest-20261017b/sleep20/README.md):** el punto 2
> estaba MAL inferido. El vendor SI apaga: 0x28, 0x10 (dt 0x05), reset GPIO335 a 0, vsn OFF, vsp OFF; el wake parte de rieles
> apagados. Las ventanas anteriores empezaban con la pantalla ya apagada por timeout. Diferencia real con nuestro boot: el ABL
> deja vsp/vsn encendidos y L76 hace el reset + init SIN ciclar rieles. Candidato: ciclo de rieles opcional al inicio de prepare
> (reset 0 -> vsn off -> vsp off -> espera -> secuencia normal). La conclusion "inherit sigue aparcado" no cambia.

# ¿Cambia el cont_splash el plan de L76? — No (17-oct)

Evidencia:
1. Arranque en frio vendor (build/android/coldboot-20261017): "cont_splash enabled" a 3.603 s, sin reset ni DSI_CMD_SET_ON:
   el vendor HEREDA el enlace vivo del ABL.
2. Wake del vendor (vendor-harvest-20261017b: trace-offon.txt y kprobe/trace-kprobe-offon.txt, ventanas desde MARK_SLEEP):
   durante el apagado NO hay ningun paquete DSI (ni 0x28/0x10), ni regulator_disable de vsp/vsn, ni toque del GPIO 335.
   Al despertar: regulator_enable vsp/vsn (refcount; sin disable previo visible) -> reset 0/1/0/1 -> 104 DCS -> 0x11 -> 0x29 -> PPS -> VID.
   => (INFERIDO) el camino de wake parte de un panel con rieles vivos y sin video, y lo re-inicializa por reset + init completo.
3. Nuestro arranque: el ABL deja el panel encendido con sus rieles; mainline resetea el MDSS (BCR) y el video se corta;
   L76 hace reset 0/1/0/1 + init completo sobre rieles vivos = el mismo estado de partida que el wake del vendor.
4. Heredar como el vendor (inherit) exige hand-off sin resetear MDSS/DSI/PLL; mainline no lo soporta y ya se aparco el
   12-oct (ESTADO-VIVO §"Estado del enfoque panel-inherit": luz del ABL con imagen muerta, upstream AÑADE el reset).

Decision: L76 se mantiene con init completo (camino de wake del vendor). El modo uke_panel_inherit sigue solo como
diagnostico (L76 ya enciende el video tambien en esa ruta). Sin cambios de codigo.
Pendiente opcional: confirmar con una captura de sleep mas larga (>10 s) que el vendor no apaga rieles en suspend.
