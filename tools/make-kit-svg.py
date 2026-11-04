# Набор кнопок DATA.OUT для Figma: SVG без фильтров (Figma переводит его в редактируемые слои).
# Те же цвета и размеры, что в CSS игры (раздел «КНОПКИ» в index.html).
import sys
from xml.sax.saxutils import escape
OUT = sys.argv[1]
NAVY = '#0b2545'
ST = {  # стиль: лицо, бортик, текст, подпись
    'play': ('#22c55e', '#15803d', '#ffffff', 'Играть · главное действие'),
    'primary': ('#0ea5e9', '#0369a1', '#ffffff', 'Разделы меню'),
    'secondary': ('#ffffff', '#b6c3d1', '#0b3954', 'Назад · мелкие действия'),
    'buy': ('#facc15', '#c28a04', '#5b3a00', 'Купить · награды'),
    'event': ('#a855f7', '#7e22ce', '#ffffff', 'Ивенты'),
    'danger': ('#f43f5e', '#be123c', '#ffffff', 'Поддержать · лайк'),
}
DIS = ('#d6dde5', '#aab6c3', '#7b8a9a')
LABEL = {'play': 'Играть', 'primary': 'Уровни', 'secondary': 'Назад', 'buy': 'Купить за ◈ 250', 'event': '⚡ Ивенты', 'danger': '♥ Поддержать'}
o = []
def rr(x, y, w, h, r, fill, extra=''):
    o.append(f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" rx="{r:.1f}" fill="{fill}" {extra}/>')
def text(x, y, s, size, fill, weight=800, anchor='middle', extra=''):
    o.append(f'<text x="{x:.1f}" y="{y:.1f}" font-family="Rubik" font-weight="{weight}" font-size="{size}" fill="{fill}" text-anchor="{anchor}" {extra}>{escape(s)}</text>')
def button(x, y, w, h, style, state='default', label='', r=14, d=5, size=15, name=''):
    f, e, t = ST[style][:3] if state != 'disabled' else DIS
    o.append(f'<g id="{escape(name or ("Button/" + style + "/" + state))}">')
    if state == 'pressed':
        y += d - 1; d = 1
    rr(x - 2, y + d - 2, w + 4, h + 4, r + 2, NAVY)          # обводка бортика
    rr(x, y + d, w, h, r, e)                                  # бортик
    rr(x, y, w, h, r, NAVY)                                   # обводка
    rr(x + 2, y + 2, w - 4, h - 4, r - 2, f)                  # лицо
    if state != 'disabled':
        rr(x + 2, y + 2, w - 4, (h - 4) * 0.58, r - 2, 'url(#hl)')   # блик
    if label:
        ty = y + h / 2 + size * 0.36
        if state != 'disabled' and t == '#ffffff':
            text(x + w / 2, ty + 2, label, size, '#000000', extra='fill-opacity="0.22"')
        text(x + w / 2, ty, label, size, t)
    o.append('</g>')
def chip(x, y, w, label, on=False, lock=False, dis=False):
    f, e, t = ('#0ea5e9', '#0369a1', '#ffffff') if on else (('#e5eaf0', '#c3ccd6', '#8796a6') if dis else (('#f6f8fb' if lock else '#ffffff'), '#b6c3d1', '#0b3954'))
    h = 30
    o.append(f'<g id="Chip/{escape(label)}">')
    rr(x - 2, y + 1, w + 4, h + 4, 17, NAVY); rr(x, y + 3, w, h, 15, e)
    rr(x, y, w, h, 15, f, f'stroke="{NAVY}" stroke-width="2"' + (' stroke-dasharray="5 3"' if lock else ''))
    text(x + w / 2, y + 20, label, 13, t, 700)
    o.append('</g>')
def control(cx, cy, R, label, f, e, size=12):
    o.append(f'<g id="Control/{escape(label)}">')
    o.append(f'<circle cx="{cx}" cy="{cy + 5}" r="{R + 2}" fill="{NAVY}"/><circle cx="{cx}" cy="{cy + 5}" r="{R}" fill="{e}"/>')
    o.append(f'<circle cx="{cx}" cy="{cy}" r="{R}" fill="{f}" fill-opacity="0.9" stroke="{NAVY}" stroke-width="2"/>')
    o.append(f'<circle cx="{cx}" cy="{cy}" r="{R - 2}" fill="url(#rhl)"/>')
    text(cx, cy + size * 0.36 + 2, label, size, '#000000', 900, extra='fill-opacity="0.3"')
    text(cx, cy + size * 0.36, label, size, '#ffffff', 900)
    o.append('</g>')
def section(x, y, title):
    text(x, y, title, 13, '#64748b', 700, 'start', 'letter-spacing="2"')

W, H = 1580, 1130
o.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">')
o.append('<defs><linearGradient id="hl" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity="0.38"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>'
         '<radialGradient id="rhl" cx="0.5" cy="0.28" r="0.55"><stop offset="0" stop-color="#fff" stop-opacity="0.45"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient>'
         '<linearGradient id="lv" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#c084fc"/><stop offset="1" stop-color="#9333ea"/></linearGradient>'
         '<linearGradient id="bar" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#a2a"/><stop offset="1" stop-color="#d946ef"/></linearGradient></defs>')
rr(0, 0, W, H, 0, '#f4f6fa')
text(40, 62, 'DATA.OUT — кнопки', 36, NAVY, 900, 'start')
text(40, 92, 'Середина между Subway Surfers, Stumble Guys и Brawl Stars: толстая обводка, блик сверху, бортик снизу; при нажатии кнопка проседает. Шрифт — Rubik.', 15, '#475569', 500, 'start')

# цвета
section(40, 140, 'ЦВЕТА · ЛИЦО / БОРТИК / ТЕКСТ')
x = 40
for k, (f, e, t, cap) in ST.items():
    for i, c in enumerate((f, e, t)):
        o.append(f'<circle cx="{x + 18 + i * 34}" cy="172" r="15" fill="{c}" stroke="{NAVY}" stroke-width="2"/>')
    text(x, 208, cap.split(' ·')[0], 12, NAVY, 700, 'start')
    text(x, 224, f'{f} / {e}', 11, '#64748b', 500, 'start')
    x += 150
o.append(f'<circle cx="{x + 18}" cy="172" r="15" fill="{NAVY}"/>')
text(x, 208, 'Обводка', 12, NAVY, 700, 'start'); text(x, 224, NAVY, 11, '#64748b', 500, 'start')

# кнопки: стиль × состояние
section(40, 270, 'КНОПКА · СТИЛЬ × СОСТОЯНИЕ')
for j, s in enumerate(('Обычная', 'Нажата', 'Недоступна')):
    text(170 + j * 260 + 110, 298, s, 13, '#475569', 700)
for i, k in enumerate(ST):
    y = 318 + i * 74
    text(40, y + 31, ST[k][3].split(' ·')[0], 13, NAVY, 700, 'start')
    for j, state in enumerate(('default', 'pressed', 'disabled')):
        button(170 + j * 260, y, 220, 50, k, state, LABEL[k])
text(40, 778, 'Радиус 14 · обводка 2 · бортик 5 (нажата — 1) · отступы 11/14 · Rubik ExtraBold 15', 12, '#64748b', 500, 'start')
# малая
section(40, 820, 'МАЛАЯ КНОПКА · .sm')
button(40, 836, 120, 36, 'secondary', 'default', 'Играть', r=11, d=4, size=13, name='Button/sm')
button(176, 836, 120, 36, 'play', 'default', 'Забрать', r=11, d=4, size=13, name='Button/sm-primary')
button(312, 836, 120, 36, 'danger', 'default', '♥ 12', r=11, d=4, size=13, name='Button/sm-like')
# чипы
section(470, 820, 'ЧИПЫ · ВЫБОР')
chip(470, 840, 90, 'Лёгкая', on=True); chip(570, 840, 96, 'Средняя'); chip(676, 840, 120, 'ФИАЛКА ◈ 250', lock=True); chip(806, 840, 100, '4 · ОРБИТА', dis=True)
# метка
section(40, 920, 'МЕТКА')
button(40, 936, 210, 50, 'primary', 'default', '🏅 Достижения', name='Button/with-badge')
o.append(f'<g id="Badge"><rect x="226" y="926" width="30" height="22" rx="11" fill="#c22" stroke="#fff" stroke-width="2"/>')
text(241, 942, '4', 12, '#ffffff', 800); o.append('</g>')
# игровые
section(470, 920, 'КНОПКИ НА ПОЛЕ (ТЕЛЕФОН)')
control(530, 990, 42, 'РЫВОК', '#0ea5e9', '#0369a1', 13)
control(630, 1000, 32, 'EMP', '#a855f7', '#7e22ce')
control(720, 1000, 32, 'ПОДНОЖКА', '#f97316', '#c2410c', 8)
control(810, 1000, 32, 'EMP', '#94a3b8', '#64748b')
text(810, 1058, 'перезарядка', 11, '#64748b', 500)

# макет меню телефона
PX, PY, PW, PH = 1110, 150, 430, 930
section(PX, PY - 14, 'ГЛАВНОЕ МЕНЮ · ТЕЛЕФОН')
rr(PX, PY, PW, PH, 26, '#eef2f7', f'stroke="{NAVY}" stroke-width="2"')
for gx in range(PX + 20, PX + PW, 40):
    o.append(f'<line x1="{gx}" y1="{PY + 2}" x2="{gx}" y2="{PY + PH - 2}" stroke="#0078961f"/>')
X, Y, IW = PX + 22, PY + 22, PW - 44
rr(X, Y, IW, PH - 44, 14, '#ffffff', f'stroke="#005577" stroke-width="2"')
cx = X + IW / 2; ix = X + 16; iw = IW - 32
text(cx, Y + 52, 'DATA.OUT', 30, '#005577', 900, extra='letter-spacing="3"')
text(cx, Y + 74, 'v6.0 · ПОБЕГ ИЗ КОРЗИНЫ', 11, '#668899', 500, extra='letter-spacing="2"')
cy = Y + 92
o.append('<g id="LevelCard">')
rr(ix - 2, cy + 3, iw + 4, 66, 16, NAVY); rr(ix, cy + 5, iw, 62, 14, '#a855f7'); rr(ix, cy, iw, 62, 14, '#ffffff', f'stroke="{NAVY}" stroke-width="2"')
o.append(f'<circle cx="{ix + 34}" cy="{cy + 31}" r="21" fill="url(#lv)" stroke="{NAVY}" stroke-width="2"/>')
text(ix + 34, cy + 38, '7', 18, '#ffffff', 900)
text(ix + 66, cy + 24, 'ФАЙЛ', 14, '#aa22aa', 800, 'start', 'letter-spacing="1"')
rr(ix + 66, cy + 31, iw - 84, 8, 4, '#00557711'); rr(ix + 66, cy + 31, (iw - 84) * 0.62, 8, 4, 'url(#bar)')
text(ix + 66, cy + 53, 'опыт 248 / 400 до уровня 8', 11, '#668899', 500, 'start')
o.append('</g>')
y = cy + 84
button(ix, y, iw, 50, 'buy', label='📅 Награда дня ждёт — день 3 из 7!', name='Menu/reward'); y += 64
button(ix, y, (iw - 10) / 2, 50, 'primary', label='🎯 Задания 1/3', name='Menu/quests')
button(ix + (iw + 10) / 2, y, (iw - 10) / 2, 50, 'primary', label='🏅 Достижения', name='Menu/ach'); y += 76
button(ix, y, iw, 54, 'play', label='Продолжить: уровень 37', size=17, name='Menu/continue'); y += 68
button(ix, y, iw, 50, 'primary', label='Новая игра', name='Menu/new'); y += 64
bw = (iw - 20) / 3
for row in (('Уровни', 'Рекорды', 'Облик'), ('Аккаунт', 'Как играть', 'Настройки')):
    for i, s in enumerate(row):
        button(ix + i * (bw + 10), y, bw, 46, 'primary', label=s, size=13, name='Menu/' + s)
    y += 60
button(ix, y, iw, 50, 'event', label='⚡ Ивенты · админ-абуз и турнир', name='Menu/events'); y += 64
button(ix, y, iw, 50, 'primary', label='Гонка · мультиплеер', name='Menu/race'); y += 64
button(ix, y, iw, 50, 'primary', label='Сообщество · уровни игроков', name='Menu/community'); y += 64
button(ix, y, iw, 50, 'danger', label='♥ Поддержать игру', name='Menu/donate')
o.append('</svg>')
open(OUT, 'w', encoding='utf-8').write('\n'.join(o))
print('ok', OUT)
