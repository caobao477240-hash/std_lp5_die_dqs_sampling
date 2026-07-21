from pathlib import Path
import sys
sys.path.insert(0, r'E:\project\std_lp5_die_clk800M\tools')
from analyze_lp5_pin_events import parse_vcd, scalar_value_at, vector_value_at

vcd = Path(r'E:\project\std_lp5_die_clk800M\sim\full_flow\full_flow_check_wave.vcd')
_ids, _vids, edges, vec = parse_vcd(vcd)

# Group CS-active CK_t edges during init only. Print compact groups around MRW/MRR.
groups = []
cur = []
last_t = None
for t, old, new in edges['ck_t_a']:
    if old not in ('0','1') or new not in ('0','1'):
        continue
    if t > 1300000:
        break
    cs = scalar_value_at(edges['cs0_a'], t)
    ca = vector_value_at(vec['ca_a'], t)
    edge = 'R' if new == '1' else 'F'
    if cs == '1':
        if cur and last_t is not None and t - last_t > 6000:
            groups.append(cur)
            cur = []
        cur.append((t, edge, ca))
        last_t = t
    else:
        if cur:
            groups.append(cur)
            cur = []
        last_t = None
if cur:
    groups.append(cur)

for idx, g in enumerate(groups[:24]):
    seq = ' '.join(f'{e}:{ca:02x}' for _, e, ca in g)
    rseq = ' '.join(f'{ca:02x}' for _, e, ca in g if e == 'R')
    print(f'INIT_GROUP[{idx:02d}] t={g[0][0]}..{g[-1][0]} edges={len(g)}')
    print('  all:', seq)
    print('  R  :', rseq)
    print()
