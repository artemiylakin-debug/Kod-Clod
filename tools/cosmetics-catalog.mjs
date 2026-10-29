// Каталог облика для проверки в базе: цены и условия получения предметов из index.html
// в виде JSON. Запуск: node tools/cosmetics-catalog.mjs — печатает JSON, который вставляется
// в функцию public.data_out_items() (online/security-6.0.sql). Тест tools/check-catalog.mjs
// сверяет, что база и игра знают одно и то же.
import { readFileSync } from 'node:fs';
const src = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const grab = (name) => {
  const i = src.indexOf('const ' + name + '=[');
  if (i < 0) throw new Error('нет ' + name);
  return Function('return ' + src.slice(i + name.length + 7, src.indexOf('\n];', i) + 2))();
};
// у вещи может быть и цена, и бесплатный путь (акт или поддержка)
const rule = (it) => ({ ...(it.price ? { p: it.price } : {}), ...(it.act ? { a: it.act } : {}), ...(it.sup ? { s: 1 } : {}) });
export const catalog = () => ({
  c: grab('SKIN_COLORS').map(rule), s: grab('SKIN_SHAPES').map(rule),
  t: grab('TRAILS').map(rule), h: grab('HATS').map(rule),
  // последний уровень (с нуля) каждого акта: предмет «за акт n» открыт, когда пройден акт n
  ends: grab('ACTS').map((a) => a.end),
});
if (import.meta.url === `file://${process.argv[1]}`) console.log(JSON.stringify(catalog()));
