# два независимых замера одних и тех же k: если промахи не совпадают — это шум, настройка точна
import json, math, sys, statistics
from collections import defaultdict
ta, tb = sys.argv[1], sys.argv[2]; T0, T1 = float(sys.argv[3]), float(sys.argv[4])
def load(t):
    d = defaultdict(list)
    for r in json.load(open('curve/%s.json' % t)):
        if r['r'] != 'time': d[r['lv']].append(r['hits'])
    return d
A, B = load(ta), load(tb)
T = lambda lv: T0 + (T1 - T0) * (lv - 1) / 499
lv = [l for l in range(1, 501) if A[l] and B[l]]
ma = {l: statistics.mean(A[l]) for l in lv}; mb = {l: statistics.mean(B[l]) for l in lv}
da = [ma[l] - T(l) for l in lv]; db = [mb[l] - T(l) for l in lv]
xa, xb = statistics.mean(da), statistics.mean(db)
cor = sum((x - xa) * (y - xb) for x, y in zip(da, db)) / math.sqrt(sum((x - xa) ** 2 for x in da) * sum((y - xb) ** 2 for y in db))
M = {l: (ma[l] + mb[l]) / 2 for l in lv}
json.dump(M, open('curve/%s+%s.H.json' % (ta, tb), 'w'))
print('сдвиг от цели %+.2f / %+.2f; корреляция промахов %.2f' % (xa, xb, cor))
dec = [statistics.mean(M[l] for l in range(i + 1, i + 11) if l in M) for i in range(0, 500, 10)]
inc = sum(1 for i in range(1, len(dec)) if dec[i] > dec[i - 1])
print('по десяткам уровней растёт %d из %d раз; первые десятки: %s' % (inc, len(dec) - 1, ' '.join('%.2f' % x for x in dec[:8])))
print('последние десятки:', ' '.join('%.2f' % x for x in dec[-6:]))
print('уровень 1: %.2f (цель %.2f), 2: %.2f, 3: %.2f' % (M[1], T(1), M[2], M[3]))
