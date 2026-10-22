#!/usr/bin/env bash
# Сборка веб-версии BlockCraft: экспорт Godot (Web, без потоков) → сжатие движка → страница-оболочка.
# Результат в build/site: index.html (обычный хостинг), artifact.html (публикация без своего <head>),
# index.js, index.audio.worklet.js, engine.txt (движок), game.txt (данные игры).
#
#   GODOT=/путь/к/godot tools/build_web.sh
set -euo pipefail

GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXPORT="$ROOT/build/web"
SITE="$ROOT/build/site"

mkdir -p "$EXPORT" "$SITE"
touch "$ROOT/build/.gdignore"
"$GODOT" --headless --path "$ROOT" --export-release "Web" "$EXPORT/index.html"

# Движок (~35 МБ) и данные игры сжимаются gzip и кладутся в base64-тексты: хостинги страниц
# часто не отдают .pck/.gz и ограничивают размер файла. Страница скачивает и распаковывает их сама.
rm -f "$SITE"/index.wasm.gz "$SITE"/index.pck
gzip -9 -n -c "$EXPORT/index.wasm" | base64 -w 0 > "$SITE/engine.txt"
gzip -9 -n -c "$EXPORT/index.pck" | base64 -w 0 > "$SITE/game.txt"
cp "$EXPORT/index.js" "$EXPORT/index.audio.worklet.js" "$SITE/"

python3 - "$EXPORT/index.html" "$ROOT/web/shell.html" "$SITE" <<'PY'
import json, re, sys
exported, shell_path, site = sys.argv[1:4]
html = open(exported, encoding="utf-8").read()
config = json.loads(re.search(r"const GODOT_CONFIG = (\{.*?\});", html).group(1))
config["canvasResizePolicy"] = 0      # размер canvas задаёт страница
config["ensureCrossOriginIsolationHeaders"] = False
config.pop("serviceWorker", None)
shell = open(shell_path, encoding="utf-8").read()
import os
assets = {
    "index.wasm": {"src": "engine.txt", "size": os.path.getsize(f"{site}/engine.txt"),
                   "type": "application/wasm", "progress": True},
    "index.pck": {"src": "game.txt", "size": os.path.getsize(f"{site}/game.txt"),
                  "type": "application/octet-stream", "progress": False},
}
page = shell.replace("/*GODOT_CONFIG*/", json.dumps(config, ensure_ascii=False))
page = page.replace("/*ASSETS*/", json.dumps(assets))
assert "/*GODOT_CONFIG*/" not in page and "/*ASSETS*/" not in page
open(f"{site}/artifact.html", "w", encoding="utf-8").write(page)
head = ('<!doctype html>\n<html lang="ru">\n<meta charset="utf-8">\n'
        '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">\n')
open(f"{site}/index.html", "w", encoding="utf-8").write(head + page + "\n</html>\n")
print("config:", json.dumps(config))
PY
ls -la "$SITE"
