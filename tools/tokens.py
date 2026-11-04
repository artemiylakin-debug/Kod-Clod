#!/usr/bin/env python3
# Сколько токенов ушло на каждое задание автора — по журналу сессии Claude Code.
# Запуск: python3 tools/tokens.py [журнал.jsonl]; без аргумента берётся самый свежий журнал
# в ~/.claude/projects/. Задание — от сообщения автора до следующего его сообщения
# (продолжение после сжатия контекста считается тем же заданием).
# «Всего» — всё, что модель прочитала и написала: повторное чтение контекста из кэша,
# новый ввод и вывод. Ответы считаются по message.id, повторы строк журнала не удваиваются.
import glob, json, os, sys

path = sys.argv[1] if len(sys.argv) > 1 else max(glob.glob(os.path.expanduser('~/.claude/projects/*/*.jsonl')), key=os.path.getmtime)
msgs, seen, tasks = [], set(), []
for line in open(path, encoding='utf-8'):
    try:
        o = json.loads(line)
    except ValueError:
        continue
    m = o.get('message') or {}
    if o.get('type') == 'user' and not o.get('isSidechain') and not o.get('isMeta'):
        c = m.get('content')
        parts = c if isinstance(c, list) else [{'type': 'text', 'text': c or ''}]
        if any(isinstance(x, dict) and x.get('type') == 'tool_result' for x in parts):
            continue
        text = ''.join(x.get('text', '') for x in parts if isinstance(x, dict) and x.get('type') == 'text').strip()
        if not text or text.startswith('<') or text.startswith('[Request interrupted'):
            continue
        if text.startswith('This session is being continued'):
            continue  # сжатие контекста — то же задание
        tasks.append((o['timestamp'], ' '.join(text.split())[:70]))
    elif o.get('type') == 'assistant' and m.get('usage') and m.get('id') not in seen:
        seen.add(m['id'])
        u = m['usage']
        msgs.append((o['timestamp'], u.get('cache_read_input_tokens', 0),
                     u.get('input_tokens', 0) + u.get('cache_creation_input_tokens', 0), u.get('output_tokens', 0)))

def total(t0, t1):
    s = [0, 0, 0, 0]
    for t, cache, new, out in msgs:
        if t0 <= t and (t1 is None or t < t1):
            s[0] += 1; s[1] += cache; s[2] += new; s[3] += out
    return s

mln = lambda n: f'{n / 1e6:.2f}'
for i, (t, text) in enumerate(tasks):
    n, cache, new, out = total(t, tasks[i + 1][0] if i + 1 < len(tasks) else None)
    print(f'{t[:16]}  ответов {n:4}  всего {mln(cache + new + out):>7} млн  (кэш {mln(cache)}, новый ввод {mln(new)}, вывод {mln(out)})  | {text}')
n, cache, new, out = total('', None)
print(f'вся сессия: ответов {n}, всего {mln(cache + new + out)} млн (кэш {mln(cache)}, новый ввод {mln(new)}, вывод {mln(out)})')
