from pathlib import Path
import sys
sys.path.insert(0, r'E:\project\std_lp5_die_clk800M\tools')
from analyze_lp5_pin_events import parse_vcd, scalar_value_at, vector_value_at

vcd = Path(r'E:\project\std_lp5_die_clk800M\sim\full_flow\full_flow_check_wave.vcd')
_ids, _vids, edges, vec = parse_vcd(vcd)

# Build CK_t edge list with CS/CA around first real GF WRITE and first GF READ.
def dump_window(name, start_ps, end_ps):
    print('==', name, '==')
    active = []
    for t, old, new in edges['ck_t_a']:
        if old not in ('0','1') or new not in ('0','1'):
            continue
        if not (start_ps <= t <= end_ps):
            continue
        cs = scalar_value_at(edges['cs0_a'], t)
        ca = vector_value_at(vec['ca_a'], t)
        cw = vector_value_at(vec['gf_cnt_write'], t)
        cr = vector_value_at(vec['gf_cnt_read'], t)
        gw = scalar_value_at(edges['gf_en_write'], t)
        gr = scalar_value_at(edges['gf_en_read'], t)
        edge = 'R' if new == '1' else 'F'
        mark = '<-- CS' if cs == '1' else ''
        print(f'{t:9d} CK_t_{edge} CS={cs} CA={ca:02x} cntW={cw} cntR={cr} gfW={gw} gfR={gr} {mark}')
        if cs == '1':
            active.append((edge, ca))
    print('CS-active CK_t edges:', ' '.join(f'{e}:{ca:02x}' for e, ca in active))
    print()

# First normal write command around 1.95 us; first read around 12.10 us.
dump_window('first GF WRITE after fix', 1940000, 1970000)
dump_window('first GF READ after fix', 12090000, 12130000)
