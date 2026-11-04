#!/bin/sh
# curve/run.sh TAG DIFF — все 500 уровней, 4 процесса; KALL / KMAP / INF / SEEDS из окружения
cd "$(dirname "$0")/.."
TAG=$1; DF=${2:-easy}
for k in 0 1 2 3; do
  LVS=$(python3 -c "print([i for i in range(500) if i%4==$k])")
  LV="$LVS" SEEDS="${SEEDS:-[7,101,4242,9001,31337,555]}" DIFF=$DF PAGE=${PAGE:-wrapped.html} OUT=curve/$TAG.$k.json node botcal.js &
done
wait
python3 - "$TAG" <<'PY'
import json,sys
tag=sys.argv[1];res=[];errs=[]
for k in range(4):
    d=json.load(open('curve/%s.%d.json'%(tag,k)));res+=d['res'];errs+=d['errs']
json.dump(res,open('curve/%s.json'%tag,'w'))
n=[r for r in res if r['r']!='time']
print(tag,'runs',len(res),'stuck',len(res)-len(n),'hits/run %.2f'%(sum(r['hits'] for r in n)/len(n)),'errs',errs[:2])
PY
