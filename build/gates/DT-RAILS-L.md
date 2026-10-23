# Los 22 rails `rpmh-regulator-ldob*` y la REGLA DE LA REJILLA (27-sep-2026)

Generado por `build/gates/dump-rails-l.py <base.dts> <merged-s229.dts>`.

base = `~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img` (DTB de vendor del slot b)
live = `fdtoverlay -i base.dtb -o merged.dtb s229.dtbo` (s229 es el par bueno; s236 solo anade
`enable-gpios` —propiedad que el codigo NI LEE, ver §3 de la auditoria— y mi fragmento 154)

```
rail   BASE min  LIVE min  LIVE max   init-v    hw  punto de rejilla en [min,max]regla
l1       880000    880000    958000   880000  nldo  880000 uV                   PASA
l2       880000    880000    950000   880000  nldo  880000 uV                   PASA
l3       880000    880000    920000   880000  nldo  880000 uV                   PASA
l4      1200000   1200000   1200000  1200000  nldo  1200000 uV                  PASA
l5      1200000   1200000   1200000  1200000  nldo  1200000 uV                  PASA
l7      1800000   1800000   1800000  1800000  pldo  1800000 uV                  PASA
l8      1800000         0         0  1900000     -  apply_uV FALSO (min o max = 0)PASA
l9       756000    756000    816000   756000  nldo  760000 uV                   PASA
l10      866000    866000    931000   866000  nldo  872000 uV                   PASA
l11     1800000   1800000   1800000  1800000  pldo  1800000 uV                  PASA
l12        None      None      None     None     -  apply_uV FALSO (min o max = 0)PASA
l13     2700000   2700000   3300000  2700000  pldo  2704000 uV                  PASA
l14     2700000   2800000   2800000  2800000  pldo  2800000 uV                  PASA
l15     1504000   1504000   3544000  1504000  pldo  1504000 uV                  PASA
l16     2900000   3200000   3200000  3200000  pldo  3200000 uV                  PASA
l17     2700000   2700000   3300000     None  pldo  2704000 uV                  PASA
l18     2000000   2000000   3000000  2000000  pldo  2000000 uV                  PASA
l19     2600000   2600000   3544000  2600000  pldo  2600000 uV                  PASA
l20     1620000   1620000   3544000  1620000  pldo  1624000 uV                  PASA
l21     1620000   1620000   3544000  1620000  pldo  1624000 uV                  PASA
l22     2700000   3300000   3300000  2700000  pldo  NINGUNO ((3300000-1504000)/8000=224.5)FALLA (-131)
l23     1650000   1800000   1800000  1650000  pldo  1800000 uV                  PASA

La regla predice que FALLAN: ['l22']
Medido en dmesg con s236:  l8 (por mi overlay, min=max=1900000 -> 49.5 pasos) y l22 (224.5)
=> 2 de 2. La regla queda AJUSTADA a la medida; no es una conjetura.

PREDICCION FALSABLE para el proximo arranque (esta linea DEBE preceder a cada -131):
    Setting <min>-<max>uV
y NO debe aparecer para ningun otro rail. Si aparece Setting y aun asi hay -131, la regla es falsa.
```

## Lo que este cuadro corrige

La version anterior de esta tabla sostenia la regla «si `min_uV && max_uV` (o sea `apply_uV`),
el registro falla con -131». **Es falsa**, y por poco he actuado sobre ella: de los 22 rails,
19 tienen `apply_uV` y solo fallan 2. La regla buena es la de la rejilla de 8 mV, y esta
**AJUSTADA a la medida 2/2**, no supuesta. Un subagente adversarial la contrasto con la mia
y tenia razon; la he vuelto a verificar yo contra el codigo antes de aceptarla.

## Nota sobre l17

`init-voltage` de `l17` sale como `None`: en el payload de s229 la propiedad esta corrupta
literalmente (`init-v = "", "/]"`). **Y aun asi `l17` se registra**, lo que confirma que el
reintento del core basta por si solo y que `rpmh_vrm_vendor_apply_init()` no hace falta para el
exito: basta con que el reintento cachee un selector valido.
