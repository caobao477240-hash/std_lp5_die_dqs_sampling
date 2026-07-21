from pathlib import Path
import sys
sys.path.insert(0, r'E:\project\std_lp5_die_clk800M\tools')
from analyze_lp5_pin_events import parse_vcd, scalar_value_at, vector_value_at
vcd=Path(r'E:\project\std_lp5_die_clk800M\sim\full_flow\full_flow_check_wave.vcd')
_ids,_vids,edges,vec=parse_vcd(vcd)
# Print both ck_t rising and falling around first real GF WRITE after CAS fix.
items=[]
for t,o,n in edges['ck_t_a']:
    if o in '01' and n in '01' and 1940000 <= t <= 1980000:
        items.append((t,'ck_t_rise' if n=='1' else 'ck_t_fall'))
for t,o,n in edges['ck_c_a'] if 'ck_c_a' in edges else []:
    pass
for t,kind in items:
    print('%9d %-10s cs=%s ca=%02x cntW=%s cntR=%s gw=%s gr=%s' % (
        t, kind,
        scalar_value_at(edges['cs0_a'],t),
        -1 if vector_value_at(vec['ca_a'],t) is None else vector_value_at(vec['ca_a'],t),
        vector_value_at(vec['gf_cnt_write'],t),
        vector_value_at(vec['gf_cnt_read'],t),
        scalar_value_at(edges['gf_en_write'],t),
        scalar_value_at(edges['gf_en_read'],t)))
