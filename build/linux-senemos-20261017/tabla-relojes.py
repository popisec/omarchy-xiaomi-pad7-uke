#!/usr/bin/env python3
# Tabla de relojes del display: L76R / senemos reposo / senemos plano / vendor (Android). Solo lee capturas del repo.
import re, sys
B = '~/proyectos/omarchy-uke/build/'
F = [('L76R', B+'linux-l76r-20261017/drm/clk.txt'),
     ('sen-reposo', B+'linux-senemos-20261017/reposo/clk.txt'),
     ('sen-plano', B+'linux-senemos-20261017/plano/clk.txt'),
     ('vendor', B+'android/vendor-harvest-20261017b/clk-summary.txt')]
WANT = ['xo_board','bi_tcxo','disp_cc_xo_clk_src','disp_cc_pll0','disp_cc_pll1','disp_cc_mdss_mdp_clk_src','disp_cc_mdss_mdp_clk',
        'disp_cc_mdss_ahb_clk','disp_cc_mdss_esc0_clk','disp_cc_mdss_esc1_clk','disp_cc_mdss_vsync_clk',
        'disp_cc_mdss_pclk0_clk','disp_cc_mdss_pclk1_clk','disp_cc_mdss_byte0_clk','disp_cc_mdss_byte1_clk',
        'disp_cc_mdss_byte0_intf_clk','disp_cc_mdss_byte1_intf_clk','gcc_disp_hf_axi_clk','dsi0vco_clk']
def parse(p):
    d = {}
    for l in open(p, errors='replace'):
        m = re.match(r'^(\s*)(\S+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(-?\d+)\s+(\d+)\s+([YN?])\s*(.*)$', l.rstrip('\n'))
        if m:
            d[m.group(2)] = (int(m.group(3)), int(m.group(6)))
    return d
D = [(n, parse(p)) for n, p in F]
print('%-30s' % 'reloj (en/prep, Hz)' + ''.join('%-26s' % n for n, _ in D))
for w in WANT:
    row = '%-30s' % w
    for n, d in D:
        row += ('%-26s' % ('%d  %d' % d[w])) if w in d else '%-26s' % '-'
    print(row)
