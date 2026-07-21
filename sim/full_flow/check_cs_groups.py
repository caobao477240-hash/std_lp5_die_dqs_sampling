from pathlib import Path
import sys
sys.path.insert(0, r'E:\project\std_lp5_die_clk800M\tools')
from analyze_lp5_pin_events import parse_vcd, edge_times, scalar_value_at, vector_value_at
vcd=Path(r'E:\project\std_lp5_die_clk800M\sim\full_flow\init_gf_pinout_wave.vcd')
_ids,_vids,edges,vec=parse_vcd(vcd)
ck_rise=[t for t,o,n in edges['ck_t_a'] if o in '01' and n=='1']
# list groups of consecutive CK rising edges with CS=1 near first GF write/read time
rows=[]
for t in ck_rise:
    cs=scalar_value_at(edges['cs0_a'],t)
    if cs=='1':
        ca=vector_value_at(vec['ca_a'],t)
        cw=vector_value_at(vec['gf_cnt_write'],t)
        cr=vector_value_at(vec['gf_cnt_read'],t)
        gw=scalar_value_at(edges['gf_en_write'],t)
        gr=scalar_value_at(edges['gf_en_read'],t)
        rows.append((t,ca,cw,cr,gw,gr))
# group consecutive cs high ck rises separated by 5000ps (200M CK period)
groups=[]; cur=[]; last=None
for r in rows:
    if last is None or r[0]-last <= 6000:
        cur.append(r)
    else:
        groups.append(cur); cur=[r]
    last=r[0]
if cur: groups.append(cur)
for g in groups:
    if any(r[4]=='1' or r[5]=='1' for r in g):
        print('GROUP', g[0][0], g[-1][0], 'nCK=', len(g), 'gf_w/r=', any(r[4]=='1' for r in g), any(r[5]=='1' for r in g))
        for r in g[:12]:
            print('  t=%8d ca=%02x cw=%s cr=%s gw=%s gr=%s'% (r[0], -1 if r[1] is None else r[1], r[2], r[3], r[4], r[5]))
        print()
        if sum(1 for gg in groups[:groups.index(g)+1] if any(rr[4]=='1' or rr[5]=='1' for rr in gg)) >= 10:
            break
