// Лист значков DATA.OUT для Figma: берёт ICONS из index.html и раскладывает их сеткой в SVG без <use>
// (Figma переводит его в редактируемые векторы). Запуск: node tools/make-icons-svg.mjs design/data-out-icons.svg
import { readFileSync, writeFileSync } from 'node:fs';
const src = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const a = src.indexOf('const ICONS={'), b = src.indexOf('\n};', a);
const ICONS = Function('return ' + src.slice(a + 'const ICONS='.length, b + 2))();
const names = Object.keys(ICONS), cols = 10, cell = 120, W = cols * cell + 60, H = Math.ceil(names.length / cols) * 140 + 120;
let o = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">`;
o += `<rect width="${W}" height="${H}" fill="#f4f6fa"/>`;
o += `<text x="30" y="52" font-family="Rubik" font-weight="900" font-size="30" fill="#0b2545">DATA.OUT — значки</text>`;
o += `<text x="30" y="80" font-family="Rubik" font-weight="500" font-size="14" fill="#475569">Цветная заливка и тёмно-синий контур 1,7 px на сетке 24×24 — в одном стиле с кнопками. ${names.length} шт.</text>`;
names.forEach((n, i) => {
  const x = 30 + (i % cols) * cell, y = 110 + Math.floor(i / cols) * 140;
  o += `<g id="${n}"><rect x="${x}" y="${y}" width="${cell - 12}" height="126" rx="16" fill="#fff" stroke="#0b2545" stroke-width="2"/>`;
  o += `<g transform="translate(${x + (cell - 12) / 2 - 30} ${y + 14}) scale(2.5)" fill="none" stroke="#0b2545" stroke-width="1.7" stroke-linejoin="round" stroke-linecap="round">${ICONS[n]}</g>`;
  o += `<text x="${x + (cell - 12) / 2}" y="${y + 112}" font-family="Rubik" font-weight="700" font-size="13" fill="#0b3954" text-anchor="middle">${n}</text></g>`;
});
writeFileSync(process.argv[2], o + '</svg>');
console.log('ok', names.length);
