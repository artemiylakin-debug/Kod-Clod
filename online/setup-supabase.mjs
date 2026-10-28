// Настройка базы DATA.OUT в Supabase одной командой — вместо ручных шагов 1, 2 и 7 из SETUP.md.
//
//   SUPABASE_ACCESS_TOKEN=... node online/setup-supabase.mjs
//
// Токен создаётся на supabase.com/dashboard/account/tokens (это доступ ко всему аккаунту Supabase:
// не публикуй его, а после настройки можно удалить). Скрипт:
//   1) создаёт проект «data-out» (или берёт готовый из SUPABASE_PROJECT_REF) и ждёт его запуска;
//   2) выполняет online/schema.sql — таблицы прогресса, рекордов и поддержки;
//   3) задаёт адрес сайта для входа;
//   4) разворачивает функции ru-login и yoomoney-hook (без проверки JWT — их вызывают до входа);
//   5) записывает секреты функций: SITE_ORIGIN и те из VK_APP_ID, YANDEX_CLIENT_ID,
//      YANDEX_CLIENT_SECRET, YOOMONEY_SECRET, что заданы в окружении;
//   6) вписывает адрес проекта и открытый ключ anon в online-config.js.
// Пароль базы генерируется случайно и нигде не сохраняется: игре он не нужен, а сбросить
// его можно в настройках проекта. Нужен Node.js 18 или новее.

import { readFile, writeFile } from 'node:fs/promises';
import { randomBytes } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const env = (k, d = '') => process.env[k] || d;
const API = env('SUPABASE_API', 'https://api.supabase.com');
const TOKEN = env('SUPABASE_ACCESS_TOKEN');
const SITE_URL = env('SITE_URL', 'https://artemiylakin-debug.github.io/Kod-Clod/');
const SITE_ORIGIN = new URL(SITE_URL).origin;
const REGION = env('SUPABASE_REGION', 'eu-central-1');

if (!TOKEN) {
  console.error('Нет SUPABASE_ACCESS_TOKEN. Создай токен на supabase.com/dashboard/account/tokens и передай его в окружении.');
  process.exit(1);
}

async function api(method, path, body, raw) {
  const r = await fetch(API + path, {
    method,
    headers: Object.assign({ Authorization: 'Bearer ' + TOKEN }, raw ? {} : { 'Content-Type': 'application/json' }),
    body: raw ? body : body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await r.text();
  if (!r.ok) throw new Error(method + ' ' + path + ' → ' + r.status + ': ' + text.slice(0, 300));
  try { return JSON.parse(text); } catch { return text; }
}
const step = (t) => console.log('• ' + t);
const sleep = (ms) => new Promise((ok) => setTimeout(ok, ms));

// 1. проект
let ref = env('SUPABASE_PROJECT_REF');
if (!ref) {
  const orgs = await api('GET', '/v1/organizations');
  const org = orgs.find((o) => o.id === env('SUPABASE_ORG')) || orgs[0];
  if (!org) throw new Error('В аккаунте Supabase нет организации — создай её на supabase.com/dashboard.');
  step('Создаю проект data-out в организации «' + org.name + '», регион ' + REGION);
  const p = await api('POST', '/v1/projects', {
    name: 'data-out', organization_id: org.id, region: REGION,
    db_pass: randomBytes(24).toString('base64url'),
  });
  ref = p.id || p.ref;
}
step('Проект ' + ref + ': жду запуска (обычно 1–3 минуты)');
for (let i = 0; ; i++) {
  const p = await api('GET', '/v1/projects/' + ref);
  if (p.status === 'ACTIVE_HEALTHY') break;
  if (i > 60) throw new Error('Проект так и не запустился, статус: ' + p.status);
  await sleep(5000);
}

// 2. таблицы
step('Создаю таблицы (online/schema.sql)');
await api('POST', '/v1/projects/' + ref + '/database/query', { query: await readFile(join(here, 'schema.sql'), 'utf8') });

// 3. адрес сайта: на него Supabase возвращает после входа через Google и Apple
step('Задаю адрес сайта ' + SITE_URL);
await api('PATCH', '/v1/projects/' + ref + '/config/auth', { site_url: SITE_URL, uri_allow_list: SITE_URL, external_email_enabled: true });

// 4. функции
for (const name of ['ru-login', 'yoomoney-hook']) {
  step('Разворачиваю функцию ' + name);
  const form = new FormData();
  form.append('metadata', JSON.stringify({ name, entrypoint_path: 'index.ts', verify_jwt: false }));
  form.append('file', new Blob([await readFile(join(here, name + '.ts'), 'utf8')], { type: 'application/typescript' }), 'index.ts');
  await api('POST', '/v1/projects/' + ref + '/functions/deploy?slug=' + name, form, true);
}

// 5. секреты функций
const secrets = [{ name: 'SITE_ORIGIN', value: SITE_ORIGIN }];
for (const k of ['VK_APP_ID', 'YANDEX_CLIENT_ID', 'YANDEX_CLIENT_SECRET', 'YOOMONEY_SECRET']) if (env(k)) secrets.push({ name: k, value: env(k) });
step('Записываю секреты функций: ' + secrets.map((s) => s.name).join(', '));
await api('POST', '/v1/projects/' + ref + '/secrets', secrets);

// 6. открытые настройки игры
const keys = await api('GET', '/v1/projects/' + ref + '/api-keys');
const anon = (keys.find((k) => k.name === 'anon') || keys.find((k) => k.type === 'publishable') || {}).api_key;
if (!anon) throw new Error('Supabase не отдал открытый ключ anon');
const cfgPath = join(here, '..', 'online-config.js');
let cfg = await readFile(cfgPath, 'utf8');
cfg = cfg.replace(/supabaseUrl: '[^']*'/, "supabaseUrl: 'https://" + ref + ".supabase.co'")
         .replace(/supabaseKey: '[^']*'/, "supabaseKey: '" + anon + "'");
await writeFile(cfgPath, cfg);
step('online-config.js: вписаны адрес проекта и открытый ключ');

console.log('\nГотово. Теперь закоммить online-config.js — через минуту сайт начнёт требовать вход.');
console.log('Для кнопок VK ID и Яндекс ID впиши их ID в online-config.js (шаги 3 и 4 в SETUP.md)');
console.log('и запусти скрипт ещё раз с SUPABASE_PROJECT_REF=' + ref + ' и нужными секретами в окружении.');
