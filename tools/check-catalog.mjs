// Тест: каталог облика и границы актов в online/security-6.0.sql совпадают с index.html.
// Запуск: node tools/check-catalog.mjs (выход 1 — расходятся: обнови функцию data_out_items в базе).
import { readFileSync } from 'node:fs';
import { catalog } from './cosmetics-catalog.mjs';
const sql = readFileSync(new URL('../online/security-6.0.sql', import.meta.url), 'utf8');
const m = sql.match(/select '(\{.*\})'::jsonb/);
const inSql = m && JSON.stringify(JSON.parse(m[1]));
const inGame = JSON.stringify(catalog());
if (inSql !== inGame) { console.error('каталог в security-6.0.sql расходится с index.html'); process.exit(1); }
console.log('каталог облика в базе совпадает с игрой');
