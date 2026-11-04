# Экраны DATA.OUT в стиле «минимализм как в магазине» для Figma: SVG без фильтров (Figma переводит его в слои).
# Запуск: python3 tools/make-screens-svg.py design/data-out-screens.svg
# Цвета и размеры — те же, что в CSS игры (разделы «КНОПКИ» и «главное меню» в index.html).
import sys
from xml.sax.saxutils import escape
OUT = sys.argv[1]
NAVY = '#0b2545'
o = []
def rr(x, y, w, h, r, fill, extra=''):
    o.append(f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" rx="{r:.1f}" fill="{fill}" {extra}/>')
def text(x, y, s, size, fill, weight=800, anchor='middle', extra=''):
    o.append(f'<text x="{x:.1f}" y="{y:.1f}" font-family="Rubik" font-weight="{weight}" font-size="{size}" fill="{fill}" text-anchor="{anchor}" {extra}>{escape(s)}</text>')
def lipbox(x, y, w, h, r, face, edge, d=5, name='', dash=False):
    """коробка в обводке с бортиком снизу: как .mbtn / .tile / .card"""
    o.append(f'<g id="{escape(name)}">' if name else '<g>')
    rr(x - 2, y + d - 2, w + 4, h + 4, r + 2, NAVY)
    rr(x, y + d, w, h, r, edge)
    rr(x, y, w, h, r, NAVY)
    rr(x + 2, y + 2, w - 4, h - 4, r - 2, face, ' stroke="#0b2545" stroke-dasharray="5 3"' if dash else '')
def end():
    o.append('</g>')
def button(x, y, w, h, label, face, edge, txt, size=15, pressed=False, name=''):
    d = 5
    if pressed:
        y += 4; d = 1
    lipbox(x, y, w, h, 14, face, edge, d, name or 'Кнопка/' + label)
    rr(x + 2, y + 2, w - 4, (h - 4) * 0.58, 12, 'url(#hl)')
    ty = y + h / 2 + size * 0.36
    if txt == '#ffffff':
        text(x + w / 2, ty + 2, label, size, '#000000', extra='fill-opacity="0.22"')
    text(x + w / 2, ty, label, size, txt)
    end()
def tile(x, y, w, h, ic, label, sub='', badge='', face='#ffffff', edge='#b6c3d1', pressed=False):
    d = 4
    if pressed:
        y += 3; d = 1
    lipbox(x, y, w, h, 16, face, edge, d, 'Плитка/' + label)
    text(x + w / 2, y + 36, ic, 26, '#0b3954', 500)
    text(x + w / 2, y + 58, label, 12, '#0b3954')
    if sub:
        text(x + w / 2, y + 72, sub, 10, '#668899', 700)
    if badge:
        rr(x + w - 22, y - 9, 28, 20, 10, '#cc2222', 'stroke="#ffffff" stroke-width="2"')
        text(x + w - 8, y + 5, badge, 11, '#ffffff')
    end()
def phone(x, y, w, h, title):
    text(x, y - 16, title, 13, '#64748b', 700, 'start', 'letter-spacing="2"')
    rr(x, y, w, h, 28, '#ffffff', f'stroke="{NAVY}" stroke-width="2"')

W, H = 1900, 1090
o.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">')
o.append('<defs><linearGradient id="hl" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity="0.34"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>'
         '<linearGradient id="lv" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#c084fc"/><stop offset="1" stop-color="#9333ea"/></linearGradient>'
         '<linearGradient id="bar" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#aa22aa"/><stop offset="1" stop-color="#d946ef"/></linearGradient></defs>')
rr(0, 0, W, H, 0, '#f4f6fa')
text(40, 60, 'DATA.OUT — минимализм, как в магазине', 34, NAVY, 900, 'start')
text(40, 90, 'Меньше текста — крупные карточки с обводкой и бортиком. У каждой кнопки анимация нажатия: проседает на бортик за 70 мс.', 15, '#475569', 500, 'start')

# --- 1. главное меню ---
X, Y, PW = 40, 150, 390
phone(X, Y, PW, 860, 'ГЛАВНОЕ МЕНЮ')
ix, iw = X + 20, PW - 40
text(ix, Y + 40, 'artemiy123', 14, '#0b3954', 800, 'start'); text(ix, Y + 56, 'сохранено в аккаунте', 11, '#668899', 500, 'start')
lipbox(X + PW - 128, Y + 26, 108, 30, 15, '#fff7d6', '#c28a04', 3, 'Биты'); text(X + PW - 74, Y + 46, '◈ 1 925', 14, '#5b3a00'); end()
text(X + PW / 2, Y + 110, 'DATA.OUT', 32, NAVY, 900, extra='letter-spacing="5"')
text(X + PW / 2, Y + 130, 'ПОБЕГ ИЗ КОРЗИНЫ', 11, '#668899', 500, extra='letter-spacing="2"')
cy = Y + 148
lipbox(ix, cy, iw, 62, 14, '#ffffff', '#a855f7', 5, 'Уровень игрока')
o.append(f'<circle cx="{ix + 34}" cy="{cy + 31}" r="21" fill="url(#lv)" stroke="{NAVY}" stroke-width="2"/>'); text(ix + 34, cy + 38, '12', 17, '#ffffff', 900)
text(ix + 66, cy + 24, 'ПРОГРАММА', 14, '#aa22aa', 800, 'start'); rr(ix + 66, cy + 31, iw - 84, 8, 4, '#e6eef5'); rr(ix + 66, cy + 31, (iw - 84) * 0.55, 8, 4, 'url(#bar)')
text(ix + 66, cy + 53, 'опыт 360 / 650 до уровня 13', 11, '#668899', 500, 'start'); end()
button(ix, cy + 82, iw, 48, '📅 Награда дня ждёт — день 3 из 7!', '#facc15', '#c28a04', '#5b3a00')
button(ix, cy + 146, iw, 56, '▶ Играть · уровень 363', '#22c55e', '#15803d', '#ffffff', 18)
tw, th, gy = (iw - 20) / 3, 88, cy + 226
tiles = [('🗺️', 'Уровни', '', ''), ('🎨', 'Облик', '', ''), ('🎯', 'Задания', '1/3', '2'), ('🏅', 'Достижения', '21/57', '3'), ('⚡', 'Ивенты', '', ''), ('🏁', 'Гонка', '', ''),
         ('🧩', 'Сообщество', '', ''), ('🏆', 'Рекорды', '', ''), ('👤', 'Аккаунт', '', ''), ('⚙️', 'Настройки', '', ''), ('❓', 'Как играть', '', ''), ('❤️', 'Поддержать', '', '')]
for k, (ic, l, sub, b) in enumerate(tiles):
    face, edge = ('#f5edff', '#7e22ce') if l == 'Ивенты' else (('#fff1f3', '#f9a8b8') if l == 'Поддержать' else ('#ffffff', '#b6c3d1'))
    tile(ix + (k % 3) * (tw + 10), gy + (k // 3) * (th + 16), tw, th, ic, l, sub, b, face, edge)
text(X + PW / 2, gy + 4 * (th + 16) + 14, '🏁 Ближе всего: «ТРИСТА» — 300 уровней', 11, '#668899', 500)
text(X + PW / 2, gy + 4 * (th + 16) + 34, 'Рекорд 973 · уровней 362 из 500 · «лёгкая»', 11, '#8796a6', 500)

# --- 2. уровни ---
X = 480
phone(X, Y, PW, 720, 'УРОВНИ')
ix = X + 20
text(X + PW / 2, Y + 58, 'УРОВНИ', 26, '#005577', 900, extra='letter-spacing="3"')
text(ix, Y + 96, '🗺️ Акты', 14, NAVY, 800, 'start'); text(ix + 66, Y + 96, '18 из 26 пройдено', 11, '#668899', 600, 'start')
acts = [(17, 'ПУСТЫНЯ ДАННЫХ', 'пройден'), (18, 'ЛУНА', 'пройден'), (19, 'МАРС', '2 / 20')]
for k, (n, nm, st) in enumerate(acts):
    ax = ix + k * 128
    sel = k == 2
    lipbox(ax, Y + 110, 118, 100, 14, '#f0f9ff' if sel else '#ffffff', '#0369a1' if sel else '#b6c3d1', 4, 'Акт/' + nm)
    if sel:
        rr(ax - 4, Y + 106, 126, 108, 17, 'none', 'stroke="#38bdf8" stroke-width="3"')
    text(ax + 59, Y + 140, str(n), 24, '#0284c7', 900); text(ax + 59, Y + 164, nm, 11, '#0b3954')
    rr(ax + 22, Y + 175, 74, 20, 10, '#dcfce7' if st == 'пройден' else '#eef2f7'); text(ax + 59, Y + 189, ('✓ ' if st == 'пройден' else '') + st, 11, '#166534' if st == 'пройден' else '#0b3954'); end()
text(X + PW / 2, Y + 240, 'АКТ 19 · МАРС · УРОВНИ 361–380', 11, '#668899', 600, extra='letter-spacing="1"')
for k in range(10):
    lx, ly = ix + (k % 2) * ((iw - 8) / 2 + 8), Y + 256 + (k // 2) * 72
    n = 361 + k
    open_ = n <= 363
    lipbox(lx, ly, (iw - 8) / 2, 58, 12, '#ffffff' if open_ else '#d6dde5', '#b6c3d1' if open_ else '#aab6c3', 4, f'Уровень/{n}')
    text(lx + 12, ly + 22, str(n), 16, '#0284c7' if open_ else '#8796a6', 900, 'start')
    text(lx + 12, ly + 38, ['КРАСНАЯ ПЫЛЬ', 'КРАТЕР', 'ПОЛЯРНАЯ ШАПКА', 'КАНЬОН', 'ВУЛКАН ОЛИМП', 'РОВЕР', 'БУРЯ', 'БАЗА', 'ДЮНЫ', 'ФОБОС'][k], 11, '#0b3954' if open_ else '#7b8a9a', 700, 'start')
    text(lx + 12, ly + 51, 'роутеры · босс' if open_ else 'закрыт', 9, '#668899', 500, 'start'); end()
lipbox(ix, Y + 640, iw, 46, 14, '#ffffff', '#b6c3d1', 5, 'Кнопка/Назад'); text(X + PW / 2, Y + 668, 'Назад', 15, '#0b3954'); end()

# --- 3. после уровня ---
X = 920
phone(X, Y, PW, 480, 'ПОСЛЕ УРОВНЯ')
ix = X + 20
text(X + PW / 2, Y + 58, 'УРОВЕНЬ 362 ПРОЙДЕН', 22, '#005577', 900, extra='letter-spacing="2"')
px = X + 60
for lab, bg, fg, wdt in [('Очки 48', '#eef4fa', NAVY, 90), ('◈ +106', '#fff3c4', '#5b3a00', 84), ('♥♥♥♥♥', '#eef4fa', '#e02444', 90)]:
    rr(px, Y + 78, wdt, 30, 15, bg); text(px + wdt / 2, Y + 98, lab, 14, fg, 700); px += wdt + 10
rr(ix, Y + 126, iw, 92, 12, '#ffffff', 'stroke="#aa22aa" stroke-dasharray="4 3"')
text(X + PW / 2, Y + 148, '+96 опыта · уровень игрока 12 · ПРОГРАММА', 12, '#668899', 600)
rr(ix + 12, Y + 158, iw - 24, 8, 4, '#e6eef5'); rr(ix + 12, Y + 158, (iw - 24) * 0.6, 8, 4, 'url(#bar)')
text(X + PW / 2, Y + 186, '🏅 Достижение «ТРИСТА» · ◈ +200', 12, '#22aa66', 600)
text(X + PW / 2, Y + 206, '🎯 Задания дня: 2 из 3 — награда ждёт в меню!', 12, '#668899', 600)
lipbox(ix, Y + 236, iw, 72, 16, '#f6fbff', '#b6c3d1', 4, 'Дальше'); text(ix + 14, Y + 256, 'ДАЛЬШЕ', 10, '#668899', 700, 'start', 'letter-spacing="1"')
text(ix + 14, Y + 276, '363 · ПОЛЯРНАЯ ШАПКА', 16, NAVY, 800, 'start'); text(ix + 14, Y + 294, 'Собери 14 данных — откроется портал', 12, '#668899', 500, 'start'); end()
button(ix, Y + 328, iw, 56, '▶ Дальше', '#22c55e', '#15803d', '#ffffff', 18)
lipbox(ix, Y + 400, iw, 46, 14, '#ffffff', '#b6c3d1', 5, 'Кнопка/Меню'); text(X + PW / 2, Y + 428, 'Главное меню', 15, '#0b3954'); end()

# --- 4. анимация нажатия ---
X, Y2 = 920, Y + 530
text(X, Y2 - 16, 'АНИМАЦИЯ НАЖАТИЯ · У КАЖДОЙ КНОПКИ', 13, '#64748b', 700, 'start', 'letter-spacing="2"')
rr(X, Y2, 920, 380, 24, '#ffffff', f'stroke="{NAVY}" stroke-width="2"')
text(X + 30, Y2 + 44, 'Обычная → нажата: сдвиг вниз, бортик 5 → 1 px, 70 мс. Отпустил — возвращается.', 14, '#475569', 500, 'start')
text(X + 30, Y2 + 64, 'Кнопкам без своего стиля — общее нажатие: вниз на 2 px и чуть меньше (0,97).', 14, '#475569', 500, 'start')
text(X + 140, Y2 + 104, 'Обычная', 12, '#668899', 700); text(X + 380, Y2 + 104, 'Нажата', 12, '#668899', 700)
button(X + 40, Y2 + 120, 200, 50, 'Уровни', '#0ea5e9', '#0369a1', '#ffffff')
button(X + 280, Y2 + 120, 200, 50, 'Уровни', '#0ea5e9', '#0369a1', '#ffffff', pressed=True)
button(X + 40, Y2 + 196, 200, 50, '▶ Играть', '#22c55e', '#15803d', '#ffffff')
button(X + 280, Y2 + 196, 200, 50, '▶ Играть', '#22c55e', '#15803d', '#ffffff', pressed=True)
text(X + 590, Y2 + 104, 'Плитка', 12, '#668899', 700); text(X + 720, Y2 + 104, 'Нажата', 12, '#668899', 700)
tile(X + 540, Y2 + 120, 104, 88, '🎨', 'Облик')
tile(X + 670, Y2 + 120, 104, 88, '🎨', 'Облик', pressed=True)
for k, (lab, on, pr) in enumerate([('Лёгкая', True, False), ('Средняя', False, False), ('Средняя', False, True)]):
    cx = X + 540 + k * 112
    yy = Y2 + 262 + (2 if pr else 0); d = 1 if pr else 3
    rr(cx - 2, yy + d - 2, 104, 34, 17, NAVY); rr(cx, yy + d, 100, 30, 15, '#0369a1' if on else '#b6c3d1'); rr(cx, yy, 100, 30, 15, '#0ea5e9' if on else '#ffffff', f'stroke="{NAVY}" stroke-width="2"')
    text(cx + 50, yy + 20, lab, 13, '#ffffff' if on else '#0b3954', 700)
text(X + 540, Y2 + 320, 'Чипы: выбран · обычный · нажат', 11, '#668899', 600, 'start')
o.append('</svg>')
open(OUT, 'w', encoding='utf-8').write('\n'.join(o))
print('ok', OUT)
