#!/usr/bin/env python3
"""check-cam.py <base.dtb> <fusionado.dtb> -- comprueba el DT fusionado con los 4 overlays de camara (solo PC).
Verifica: (1) que solo cambian los nodos previstos; (2) que cada phandle de los nodos de camara resuelve al nodo esperado;
(3) los datos de Android que el overlay debe respetar (gpios, direcciones, rails). Sale !=0 si algo no cuadra."""
import struct, sys
import libfdt

base = libfdt.Fdt(open(sys.argv[1], 'rb').read())
merged = libfdt.Fdt(open(sys.argv[2], 'rb').read())
fails = []


def bad(m):
    fails.append(m); print('FALLO:', m)


def ok(m):
    print('   ok ', m)


def subs(f, off):
    try:
        c = f.first_subnode(off)
    except libfdt.FdtException:
        return
    while True:
        yield c
        try:
            c = f.next_subnode(c)
        except libfdt.FdtException:
            break


def props(f, off):
    out = {}
    try:
        po = f.first_property_offset(off)
    except libfdt.FdtException:
        return out
    while True:
        pr = f.get_property_by_offset(po)
        out[pr.name] = bytes(pr)
        try:
            po = f.next_property_offset(po)
        except libfdt.FdtException:
            break
    return out


def tree(f):
    t = {}
    def walk(off, path):
        t[path] = props(f, off)
        for c in subs(f, off):
            walk(c, path.rstrip('/') + '/' + f.get_name(c))
    walk(0, '/')
    return t


def phmap(t):
    m = {}
    for p, pr in t.items():
        if 'phandle' in pr and len(pr['phandle']) == 4:
            m[struct.unpack('>I', pr['phandle'])[0]] = p
    return m


tb, tm = tree(base), tree(merged)
ph = phmap(tm)
ALLOWED = ('/soc/pinctrl@f000000/uke-cam-rear-rst-hi', '/soc/pinctrl@f000000/uke-cam-front-rst-hi', '/soc/pinctrl@f000000/uke-cam-front-rst-lo', '/soc/clock-controller@ade0000', '/soc/qcom,cci0@ac15000', '/soc/isp@acb6000',
           '/soc/qcom,qupv3_1_geni_se@8c0000/i2c@880000', '/__symbols__', '/__fixups__', '/__local_fixups__')

print('== 1. nodos cambiados/anadidos respecto a la base')
changed = [p for p in tm if p not in tb or tm[p] != tb[p]]
for p in changed:
    if not p.startswith(ALLOWED):
        bad('nodo fuera de lo previsto: %s' % p)
removed = [p for p in tb if p not in tm]
if removed:
    bad('nodos desaparecidos: %s' % removed[:5])
if not fails:
    ok('%d nodos cambiados, todos bajo los 4 raices previstas; ninguno desaparecido' % len(changed))


def cells(p, k):
    v = tm[p][k]
    return list(struct.unpack('>%dI' % (len(v) // 4), v))


def s(p, k):
    return tm[p][k].rstrip(b'\0').decode()


def expect(cond, m):
    ok(m) if cond else bad(m)


print('== 2. camcc')
cc = '/soc/clock-controller@ade0000'
c = cells(cc, 'clocks')
expect(len(c) == 6, 'camcc.clocks: relleno IFACE (1 celda), rpmhcc 0, rpmhcc 1, sleep_clk')
expect(ph.get(c[0]) == '/soc/clocks/sleep_clk', 'IFACE = relleno (sleep_clk): gcc-cliffs no registra GCC_CAMERA_AHB_CLK')
expect(ph.get(c[1], '').endswith('/clock-controller') and c[2] == 0 and ph.get(c[3], '').endswith('/clock-controller') and c[4] == 1, 'tcxo y tcxo_ao = rpmhcc 0 y 1')
expect(ph.get(c[5]) == '/soc/clocks/sleep_clk', 'sleep_clk')
expect(cells(cc, '#power-domain-cells') == [1], '#power-domain-cells = 1')

print('== 3. CCI0 y sensor trasero (datos de Android)')
cci = '/soc/qcom,cci0@ac15000'
expect(s(cci, 'compatible').startswith('qcom,sm8650-cci'), 'cci0 compatible sm8650-cci/msm8996-cci')
expect(cells(cci, 'interrupts') == [0, 426, 1], 'cci0 SPI 426 (vendor 0x1aa), 3 celdas')
expect(cci + '/i2c-bus@0' in tm and cells(cci + '/i2c-bus@0', 'reg') == [0], 'i2c-bus@0 declarado (cci_reset espera en master[0]; sin él oops)')
sp = cci + '/i2c-bus@1/camera@10'
expect(sp in tm, 'camera@10 (0x20 de 8 bit = 0x10) en i2c-bus@1 (cci-master=1)')
names = [ph.get(x, '?').split('/')[-1] for x in cells(sp, 'pinctrl-2')]
expect(names == ['cam_sensor_mclk0_active', 'uke-cam-rear-rst-hi'], 'rst_release = mclk0 activo + uke_cam_rear_rst_hi (%s)' % names)
hi = '/soc/pinctrl@f000000/uke-cam-rear-rst-hi'
expect(tm[hi]['pins'].rstrip(b'\0') == b'gpio14' and 'output-high' in tm[hi], 'estado de reset liberado = gpio14 output-high (Android gpio-reset: 0xe)')
expect('reset-gpios' not in tm[sp], 'sin reset-gpios (gpiolib-shared lo rechazaria; el driver usa pinctrl)')
for supp, want in (('dovdd-supply', 'regulator-pmxr2230-l20'), ('avdd-supply', None), ('dvdd-supply', 'regulator-pmr735a-l6')):
    t = ph.get(cells(sp, supp)[0], '?')
    expect((t.endswith(want) if want else t == '/soc/gpio-regulator@1'), '%s -> %s' % (supp, t.split('/')[-1]))
expect(cells(sp, 'assigned-clock-rates') == [19200000], 'MCLK0 19,2 MHz')
pdm = cells(sp, 'power-domains')
expect(ph.get(pdm[0]) == cc and pdm[1] == 0, 'sensor con power-domains = camcc TITAN_TOP_GDSC (%s %s)' % (ph.get(pdm[0]), pdm[1] if len(pdm) > 1 else '?'))
mc = cells(sp, 'clocks')
expect(ph.get(mc[0]) == cc and mc[1] == 96, 'MCLK0 = camcc CAM_CC_MCLK0_CLK (96 en sm8650)')
for k in ('pinctrl-0', 'pinctrl-1'):
    names = [ph.get(x, '?').split('/')[-1] for x in cells(sp, k)]
    ok('%s = %s' % (k, names))
pc = [ph.get(x, '?').split('/')[-1] for x in cells(cci, 'pinctrl-0')]
expect(set(pc) == {'uke_cci_i2c_scl1_active', 'uke_cci_i2c_sda1_active'}, 'cci pinctrl = gpio73/gpio72 (master 1)')
for ch in ('qcom,cam-sensor0', 'qcom,actuator0', 'qcom,eeprom0', 'qcom,i2c_standard_mode', 'qcom,i2c_fast_mode',
           'qcom,i2c_fast_plus_mode', 'qcom,i2c_custom_mode'):
    expect(s(cci + '/' + ch, 'status') == 'disabled', 'hijo vendor %s deshabilitado' % ch)

print('== 4. camss')
cs = '/soc/isp@acb6000'
expect(s(cs, 'compatible') == 'qcom,cliffs-camss', 'camss compatible')
names = tm[cs]['reg-names'].rstrip(b'\0').split(b'\0')
regs = cells(cs, 'reg')
expect(len(names) * 2 == len(regs), 'reg-names (%d) y reg coinciden' % len(names))
expect(len(tm[cs]['interrupt-names'].rstrip(b'\0').split(b'\0')) * 3 == len(cells(cs, 'interrupts')), 'interrupts 3 celdas por nombre')
expect(len(tm[cs]['clock-names'].rstrip(b'\0').split(b'\0')) * 2 == len(cells(cs, 'clocks')), 'clocks = 2 celdas por clock-name')
ep1 = cs + '/ports/port@1/endpoint'
ep0 = sp + '/port/endpoint'
expect(ph.get(cells(ep1, 'remote-endpoint')[0]) == ep0 and ph.get(cells(ep0, 'remote-endpoint')[0]) == ep1, 'enlace csiphy1 <-> ov13b10 en los dos sentidos')
expect(cells(ep0, 'data-lanes') == [0, 1, 2, 3], 'ov13b10 4 lanes (posiciones 0..3 como camss/Android)')

print('== 5. frontal')
fb = '/soc/qcom,qupv3_1_geni_se@8c0000/i2c@880000'
fs = fb + '/camera@10'
expect(s(fb, 'status') == 'okay' and s(fb, 'compatible') == 'qcom,geni-i2c', 'i2c@880000 okay + compat geni-i2c')
expect(fs in tm and s(fs, 'compatible') == 'ovti,ov08d10', 'ov08d10 en 0x10')
# ciclo 23: reset por pinctrl (gpio3 en `gpios` del cam-sensor1 vendor -> gpiolib-shared)
expect('reset-gpios' not in tm[fs], 'frontal sin reset-gpios (el driver usa pinctrl)')
for nm, lvl in (('uke-cam-front-rst-hi', 'output-high'), ('uke-cam-front-rst-lo', 'output-low')):
    n = '/soc/pinctrl@f000000/' + nm
    expect(n in tm and tm[n]['pins'].rstrip(b'\0') == b'gpio3' and lvl in tm[n], '%s = gpio3 %s (Android gpio-reset 0x3)' % (nm, lvl))
expect(tm[fs].get('pinctrl-names', b'').split(b'\0')[:3] == [b'default', b'sleep', b'rst_release'], 'frontal pinctrl default/sleep/rst_release')
expect('power-domains' in tm[fs], 'frontal con power-domains (MCLK4 en titan_top)')
for v in ('qcom,cam-sensor1', 'qcom,eeprom1'):
    expect(s(fb + '/' + v, 'status') == 'disabled', 'hijo vendor %s apagado' % v)
expect(ph.get(cells(fs, 'dvdd-supply')[0], '').endswith('regulator-pm_v6c-l3'), 'dvdd = pm_v6c_l3')
expect(ph.get(cells(fs, 'avdd-supply')[0]) == '/soc/gpio-regulator@3', 'avdd = gpio-regulator@3 (gpio160)')
e4 = cs + '/ports/port@4/endpoint'; f4 = fs + '/port/endpoint'
expect(ph.get(cells(e4, 'remote-endpoint')[0]) == f4 and ph.get(cells(f4, 'remote-endpoint')[0]) == e4, 'enlace csiphy4 <-> ov08d10')

print()
print('RESULTADO:', 'OK' if not fails else 'FALLOS=%d' % len(fails))
sys.exit(1 if fails else 0)
