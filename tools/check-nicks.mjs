// Проверка ников тем же детектором, что в игре (раздел «БЕЗОПАСНОСТЬ НИКОВ» в index.html).
// node tools/check-nicks.mjs "max2016" "PixelHunter"   — или имена построчно на вход:
// (выгрузка из базы: select name from progress) | node tools/check-nicks.mjs
import fs from 'fs';
const html = fs.readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const a = html.indexOf('// ================= БЕЗОПАСНОСТЬ НИКОВ'), b = html.indexOf('function nickGuard(', a);
if (a < 0 || b < 0) { console.error('раздел «БЕЗОПАСНОСТЬ НИКОВ» не найден в index.html'); process.exit(1); }
const { nickRisk, safeNick } = new Function(html.slice(a, b) + ';return {nickRisk,safeNick};')();
let names = process.argv.slice(2);
if (!names.length && !process.stdin.isTTY) names = fs.readFileSync(0, 'utf8').split('\n').map(s => s.trim()).filter(Boolean);
if (!names.length) { console.error('нужны ники: аргументами или построчно на вход'); process.exit(1); }
let risky = 0;
for (const n of names) {
  const r = nickRisk(n); risky += r;
  console.log((r ? 'ПОХОЖ НА ИМЯ  ' : 'ok            ') + n);
}
console.log(`\nвсего ${names.length}, похожих на имя: ${risky}`);
if (process.env.SEED) console.log('безопасный ник для', process.env.SEED, '—', safeNick(process.env.SEED));
