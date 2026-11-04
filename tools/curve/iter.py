# шаг замкнутого цикла: уровень замерен со своим k → поправить k по промаху мимо цели.
# Чувствительность сложности к k — по общей кривой g (свои для уровней с боссом и без);
# замер «сжимается» к цели по числу попыток (шум), шаг ограничен — чтобы не раскачать
import json, math, re, sys
from collections import defaultdict
kin, tag, kout = sys.argv[1], sys.argv[2], sys.argv[3]
T0, T1 = float(sys.argv[4]), float(sys.argv[5])
KMIN, KMAX = 0.05, 2.5
K = json.load(open(kin))
runs = defaultdict(list)
for r in json.load(open('curve/%s.json' % tag)):
    if r['r'] != 'time': runs[r['lv']].append(r['hits'])
src = open('data_out_v5.html', encoding='utf-8').read()
m = re.search(r'\nconst LEVELS=\[(.*?)\n\];', src, re.S)
boss = [('boss:' in e) for e in re.split(r'\n  \{name:', m.group(1))[1:]]
G = {True: [(0.15, 0.14), (0.3, 0.24), (0.55, 0.67), (1.0, 1.0), (1.4, 1.71), (1.8, 2.84), (2.3, 3.84)],
     False: [(0.15, 0.25), (0.3, 0.45), (0.55, 0.83), (1.0, 1.0), (1.4, 1.28), (1.8, 1.83), (2.3, 2.17)]}
def elast(b, k):
    pts = G[b]
    for (k0, g0), (k1, g1) in zip(pts, pts[1:]):
        if k <= k1 or k1 == pts[-1][0]:
            return max(0.4, math.log(g1 / g0) / math.log(k1 / k0))
def target(lv): return T0 + (T1 - T0) * (lv - 1) / 499
out, err, big = [], [], 0
for lv in range(1, 501):
    k = K[lv - 1]; hs = runs[lv]; T = target(lv)
    if not hs: out.append(k); continue
    n = len(hs); M = sum(hs) / n
    Meff = (M * n + T * 3) / (n + 3)          # недоверие к малому числу попыток
    e = elast(boss[lv - 1], k)
    f = ((T + 0.15) / (Meff + 0.15)) ** (1 / e)
    f = min(1.6, max(0.6, f)) ** 0.6           # шаг с затуханием: у боссов сложность резко зависит от k
    k2 = min(KMAX, max(KMIN, k * f))
    out.append(round(k2, 3)); err.append(abs(M - T) / (T + 0.15))
    if abs(M - T) > 0.5 * (T + 0.3): big += 1
json.dump(out, open(kout, 'w'))
print('%s: средний промах %.0f%%, сильно мимо цели %d уровней' % (tag, 100 * sum(err) / len(err), big))
