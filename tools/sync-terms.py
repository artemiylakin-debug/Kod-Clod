#!/usr/bin/env python3
"""Переносит текст TERMS.md в те два места, где соглашение лежит в виде HTML:
  - <template id="terms-tpl" data-version="…"> в index.html (его показывает игра);
  - <article> в terms.html (отдельная страница).
Номер редакции берётся из строки «### Редакция X.Y.Z» в TERMS.md и ставится в data-version.
Остальные атрибуты шаблона (например data-accepts — редакции, принятие которых засчитывается) не трогаются.

  python3 tools/sync-terms.py                      # index.html и terms.html в корне репозитория
  python3 tools/sync-terms.py файл.html …          # другие файлы (например исходник игры вне репозитория)
  python3 tools/sync-terms.py --terms другой.md    # другой источник текста
"""
import html, re, sys, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def inline(t):
    t = html.escape(t, quote=False)
    t = re.sub(r'\*\*(.+?)\*\*', r'<b>\1</b>', t)
    t = re.sub(r'(?<![*\w])\*(.+?)\*(?![*\w])', r'<i>\1</i>', t)
    t = re.sub(r'(?<!["=>])(https?://[^\s<]+)', r'<a href="\1" target="_blank" rel="noopener">\1</a>', t)
    return t

def to_html(md):
    out = []
    for ln in md.split('\n'):
        ln = ln.rstrip()
        if not ln:
            continue
        m = re.match(r'^(#{1,3}) (.+)$', ln)
        if m:
            out.append('<h%d>%s</h%d>' % (len(m.group(1)), inline(m.group(2)), len(m.group(1))))
        elif ln == '---':
            out.append('<hr>')
        else:
            out.append('<p>%s</p>' % inline(ln))
    return '\n'.join(out)

def main(argv):
    terms = os.path.join(ROOT, 'TERMS.md')
    if '--terms' in argv:
        i = argv.index('--terms'); terms = argv[i + 1]; del argv[i:i + 2]
    targets = argv or [os.path.join(ROOT, 'index.html'), os.path.join(ROOT, 'terms.html')]
    md = open(terms, encoding='utf-8').read()
    ver = re.search(r'^### Редакция (\S+)\s*$', md, re.M)
    if not ver:
        sys.exit('в TERMS.md нет строки «### Редакция X.Y.Z»')
    ver = ver.group(1)
    body = to_html(md)
    for path in targets:
        src = open(path, encoding='utf-8').read()
        new = src
        if '<template id="terms-tpl"' in src:
            def tpl(m):
                attrs = re.sub(r'data-version="[^"]*"', 'data-version="%s"' % ver, m.group(1))
                return '<template id="terms-tpl"%s>\n%s\n</template>' % (attrs, body)
            new, n = re.subn(r'<template id="terms-tpl"([^>]*)>.*?</template>', tpl, new, count=1, flags=re.S)
            if n != 1:
                sys.exit(path + ': не нашёл <template id="terms-tpl">')
        if '<article>' in src:
            new, n = re.subn(r'<article>\n.*?\n</article>', lambda m: '<article>\n%s\n</article>' % body, new, count=1, flags=re.S)
            if n != 1:
                sys.exit(path + ': не нашёл <article>')
        if new == src:
            print(path + ': без изменений (редакция %s)' % ver)
        else:
            open(path, 'w', encoding='utf-8').write(new)
            print(path + ': обновлено, редакция %s' % ver)

if __name__ == '__main__':
    main(sys.argv[1:])
