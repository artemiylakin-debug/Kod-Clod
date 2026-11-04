#!/bin/sh
# готовит рабочую папку для подбора кривой сложности: тело игры из index.html (data_out_v5.html — по нему
# скрипты читают LEVELS и ACTS) и его обёртку для браузера (wrapped.html — в ней играет бот)
# использование: tools/curve/prepare.sh <рабочая папка>   (дальше все команды — из неё)
set -e
W="$1"; R="$(cd "$(dirname "$0")/../.." && pwd)"
mkdir -p "$W/curve"
sed -n '/<body>/,/<\/body>/p' "$R/index.html" | sed '1d;$d' > "$W/data_out_v5.html"
{ printf '<!doctype html><html><head><meta charset="utf-8"><style>[hidden]{display:none!important}</style></head><body>'; cat "$W/data_out_v5.html"; printf '</body></html>\n'; } > "$W/wrapped.html"
cp "$R/tools/curve/botcal.js" "$W/"
cp "$R/tools/curve/run.sh" "$R/tools/curve/iter.py" "$R/tools/curve/verify.py" "$R/tools/curve/compare.py" "$W/curve/"
chmod +x "$W/curve/run.sh"
echo "готово: $W"
