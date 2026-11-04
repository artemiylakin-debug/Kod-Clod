import json, statistics, re, sys
# python3 curve/compare.py <замер «было»: *.H.json> <замер «стало»: *.H.json> (их пишет verify.py)
def load(f): return {int(a): b for a, b in json.load(open(f)).items()}
src=open('data_out_v5.html',encoding='utf-8').read()
m=re.search(r'const ACTS=\[(.*?)\n\];',src,re.S); ends=[int(x) for x in re.findall(r'end:(\d+)',m.group(1))]
def act(lv):
    i=lv-1;a=0
    while a<len(ends)-1 and i>ends[a]:a+=1
    return a
def rank(v):
    s=sorted(range(len(v)),key=lambda i:v[i]);r=[0]*len(v)
    for j,i in enumerate(s):r[i]=j
    return r
for name,f in (('БЫЛО',sys.argv[1]),('СТАЛО',sys.argv[2])):
    H=load(f); L=sorted(H)
    trend={l:statistics.median([H[x] for x in range(l-10,l+11) if x in H and x!=l]) for l in L}
    sp=[l for l in L if H[l]>2*trend[l]+0.3]
    big=max((H[l]-trend[l],l) for l in L)
    acts=[statistics.mean(H[l] for l in L if act(l)==a) for a in range(len(ends))]
    rl=rank([float(l) for l in L]);rh=rank([H[l] for l in L]);n=len(L)
    sp_cor=1-6*sum((x-y)**2 for x,y in zip(rl,rh))/(n*(n*n-1))
    up=sum(1 for i in range(1,len(acts)) if acts[i]>acts[i-1])
    print('%s: уровень 1 = %.2f, уровни 2–10 в среднем %.2f; резких скачков (вдвое выше соседей) %d, самый большой +%.1f (ур. %d);'%(name,H[1],statistics.mean(H[l] for l in range(2,11)),len(sp),big[0],big[1]))
    print('   связь сложности с номером уровня (0 — никакой, 1 — строго растёт): %.2f; акты растут друг за другом %d из %d раз'%(sp_cor,up,len(acts)-1))
    print('   по актам:',' '.join('%.2f'%a for a in acts))
