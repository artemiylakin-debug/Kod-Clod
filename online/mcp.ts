// Supabase Edge Function «mcp»: сервер MCP (Model Context Protocol) для ИИ-помощников —
// Claude, ChatGPT и других клиентов, которые умеют подключаться к MCP по HTTP.
//
// Адрес: https://<проект>.supabase.co/functions/v1/mcp
// Без ключа ИИ может читать: формат карт, уровни сообщества, рекорды, профили, проверку карты.
// С ключом игрока (создаётся в игре: «Аккаунт» → «ИИ через MCP») — ещё и складывать черновики
// уровней в «Мои уровни» этого игрока. Публикует уровень сам игрок, пройдя его в редакторе:
// так в сообществе не бывает непроходимых уровней.
// Ключ передаётся заголовком «Authorization: Bearer dok_…» или параметром адреса ?key=dok_…
//
// Протокол: Streamable HTTP без потоков — каждый запрос POST с JSON-RPC, ответ — JSON.
// В настройках функции выключи «Verify JWT»: её вызывают ИИ-клиенты, а не вошедшие игроки.
// SUPABASE_URL, SUPABASE_ANON_KEY и SUPABASE_SERVICE_ROLE_KEY Supabase подставляет сам;
// чтение идёт ключом anon (действуют правила доступа базы), service_role — только для ключей
// MCP и черновиков, всегда с отбором по владельцу ключа.
//
// Правила карты повторяют игру (normLevel и mapToCfg в index.html) — при их правке менять оба места.

const env = (k: string) => Deno.env.get(k) ?? '';
const SB = env('SUPABASE_URL'), ANON = env('SUPABASE_ANON_KEY'), SERVICE = env('SUPABASE_SERVICE_ROLE_KEY');
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, accept, mcp-session-id, mcp-protocol-version, last-event-id, apikey, x-client-info',
  'Access-Control-Allow-Methods': 'POST, GET, DELETE, OPTIONS',
  'Access-Control-Expose-Headers': 'mcp-session-id',
};
const VERSIONS = ['2025-06-18', '2025-03-26', '2024-11-05'];

// ---------- игра: то же, что в index.html ----------
const COLS = 32, ROWS = 20, CELL = 25, W = 800, H = 500, START_R = 60;
const TILES: Record<string, string> = {
  '.': 'пусто', '#': 'стена', 'F': 'барьер файрвола (мигает и загорается, ранит, когда горит)', '~': 'лаг (все вязнут)',
  'I': 'инверсия (управление наоборот)', '>': 'поток вправо', '<': 'поток влево', '^': 'поток вверх', 'v': 'поток вниз',
  'H': 'подвижный блок, ездит влево-вправо', 'V': 'подвижный блок, ездит вверх-вниз', 'O': 'чёрная дыра (тянет, ядро ранит)',
  '1': 'роутер пары 1', '2': 'роутер пары 2', '3': 'роутер пары 3', 'T': 'турель', 'M': 'мина', 'S': 'старт игрока',
};
const TILE_MAX: Record<string, number> = { O: 4, T: 6, M: 12, S: 1, '1': 2, '2': 2, '3': 2 };
const SOLID = '#FHVOTM123';
const ENEMIES: Record<string, string> = {
  chaser: 'охотник — догоняет', sniper: 'снайпер — стреляет издалека', heavy: 'щитоносец — два попадания EMP', glitch: 'глитч — телепортируется к игроку',
  worm: 'червь — длинный, ранит любым звеном', botnet: 'ботнет — стайка из четырёх ботов', turret: 'турель — стоит и бьёт очередями',
  thief: 'вор — крадёт данные', miner: 'минёр — ставит мины', missile: 'ракета — самонаводится', mirror: 'зеркало — держится напротив игрока',
};
const BOSSES: Record<string, string> = {
  ring: 'кольца пуль', aimed: 'стреляет в игрока', pack: 'затягивает к себе', charge: 'таранит', spiral: 'спираль пуль', balance: 'две сферы вокруг',
  captcha: 'щит, EMP не берёт, пока горит', seeker: 'самонаводящиеся пули', orbit: 'кружит по орбите', cloak: 'исчезает и выходит рядом',
  traffic: 'светофор: щит на жёлтый и красный', kraken: 'щупальца', nova: 'копит заряд и взрывается кольцами', twin: 'двойник, всегда напротив',
  final: 'всё понемногу', admin: 'перебирает атаки, зовёт ботнет', omega: 'всё сразу', singularity: 'меняет атаку каждые 5 секунд',
};
const THEMES = ['КОМПЬЮТЕР', 'ОБЛАКО', 'ИНТЕРНЕТ', 'ОРБИТА', 'ГЛУБОКАЯ СЕТЬ', 'ЛАБОРАТОРИЯ', 'ГОРОД', 'ОКЕАН', 'ЗВЁЗДЫ', 'ЗАЗЕРКАЛЬЕ', 'СИНГУЛЯРНОСТЬ'];
const FLAGS = ['dark', 'ice', 'storm', 'debris', 'strike', 'timer'];

const num = (v: unknown, a: number, b: number, d: number) => { const n = Number(v); return Number.isFinite(n) ? Math.max(a, Math.min(b, Math.round(n))) : d; };
const str = (v: unknown, max: number) => typeof v === 'string' ? v.replace(/[\u0000-\u001f\u007f<>&"'`\\]/g, '').replace(/\s+/g, ' ').trim().slice(0, max) : '';
const center = (i: number) => ({ x: (i % COLS) * CELL + CELL / 2, y: Math.floor(i / COLS) * CELL + CELL / 2 });

// уровень от ИИ → чистый уровень в формате редактора (v2) + что пришлось поправить
function cleanLevel(d: any) {
  const warn: string[] = [];
  if (!d || typeof d !== 'object' || Array.isArray(d)) throw new Error('уровень — это объект JSON, см. level_format');
  let rows: unknown = d.map;
  if (typeof rows === 'string') rows = rows.split(/\r?\n/);
  if (!Array.isArray(rows)) throw new Error('нет карты: поле map — массив из 20 строк по 32 символа');
  if (rows.length !== ROWS) warn.push(`в карте ${rows.length} строк вместо ${ROWS} — лишние отброшены, недостающие пустые`);
  const cells: string[] = new Array(COLS * ROWS).fill('.');
  let bad = 0, wide = 0;
  for (let y = 0; y < ROWS; y++) {
    const r = typeof rows[y] === 'string' ? rows[y] as string : '';
    if (r.length !== COLS && y < rows.length) wide++;
    for (let x = 0; x < Math.min(COLS, r.length); x++) {
      const ch = r.charAt(x);
      if (TILES[ch]) cells[y * COLS + x] = ch; else bad++;
    }
  }
  if (wide) warn.push(`${wide} строк не по 32 символа — обрезаны или дополнены точками`);
  if (bad) warn.push(`${bad} неизвестных символов заменены на «.»`);
  const n: Record<string, number> = {};
  cells.forEach((ch, i) => { const lim = TILE_MAX[ch]; if (lim) { n[ch] = (n[ch] || 0) + 1; if (n[ch] > lim) cells[i] = '.'; } });
  for (const ch in n) if (n[ch] > TILE_MAX[ch]) warn.push(`«${ch}» (${TILES[ch]}): можно не больше ${TILE_MAX[ch]}, лишние убраны`);
  for (const ch of ['1', '2', '3']) if (n[ch] === 1) warn.push(`у роутера «${ch}» нет пары — в игре он не сработает`);
  const si = cells.indexOf('S'), st = si >= 0 ? center(si) : { x: W / 2, y: H / 2 };
  let near = 0;
  cells.forEach((ch, i) => { if (SOLID.includes(ch)) { const p = center(i); if (Math.hypot(p.x - st.x, p.y - st.y) < START_R) near++; } });
  if (near) warn.push(`${near} твёрдых клеток вплотную к старту (ближе 2–3 клеток) — в игре их не будет`);
  if (!cells.some(ch => ch !== '.')) warn.push('карта пустая');
  const types = Object.keys(ENEMIES);
  const list = (v: unknown, max: number) => (Array.isArray(v) ? v : []).filter((t): t is string => typeof t === 'string' && types.includes(t)).slice(0, max);
  const start = list(d.start, 8), counts: Record<string, number> = {};
  const startOk = start.filter(t => (counts[t] = (counts[t] || 0) + 1) <= 3);
  if (startOk.length < start.length) warn.push('на старте не больше 3 врагов одного вида');
  const lv: any = {
    v: 2, name: str(d.name, 30), descr: str(d.descr, 200),
    map: Array.from({ length: ROWS }, (_, y) => cells.slice(y * COLS, (y + 1) * COLS).join('')),
    goal: num(d.goal, 5, 30, 15), cap: num(d.cap, 3, 9, 6), start: startOk, ramp: [...new Set(list(d.ramp, 6))],
    scan: num(d.scan, 0, 2, 0), trojan: num(d.trojan, 0, 2, 0), theme: num(d.theme, 0, THEMES.length - 1, 0), boss: null,
  };
  for (const f of FLAGS) lv[f] = d[f] ? 1 : 0;
  if (d.boss && typeof d.boss === 'object') {
    if (BOSSES[d.boss.kind]) lv.boss = { kind: d.boss.kind, hp: num(d.boss.hp, 3, 8, 5), name: str(d.boss.name, 20) };
    else warn.push('неизвестный вид босса — уровень без босса');
  }
  if (!lv.name) warn.push('нет названия — дай уровню name');
  return { level: lv, warnings: warn };
}
function summary(lv: any) {
  const cnt: Record<string, number> = {};
  for (const r of lv.map) for (const ch of r) if (ch !== '.') cnt[ch] = (cnt[ch] || 0) + 1;
  return {
    клетки: Object.fromEntries(Object.entries(cnt).map(([k, v]) => [k + ' ' + TILES[k].split(' (')[0], v])),
    данных_собрать: lv.goal, врагов_сразу: lv.cap, враги_на_старте: lv.start, подкрепление: lv.ramp,
    опасности: FLAGS.filter(f => lv[f]).concat(lv.scan ? [lv.scan === 2 ? 'два луча сканера' : 'сканер'] : [], lv.trojan ? [`трояны ${lv.trojan * 15}%`] : []),
    босс: lv.boss ? `${lv.boss.name || lv.boss.kind} (${BOSSES[lv.boss.kind]}, ${lv.boss.hp} ударов)` : 'нет', оформление: THEMES[lv.theme],
  };
}
const preview = (lv: any) => '```\n' + lv.map.join('\n') + '\n```';

const FORMAT = `Уровень DATA.OUT — объект JSON:
{
  "name": "Арена",                 // до 30 символов
  "descr": "что ждёт игрока",      // до 200 символов
  "map": [ 20 строк по 32 символа ],
  "goal": 15,      // сколько данных собрать, 5–30 (на лёгкой сложности нужно чуть меньше)
  "cap": 6,        // сколько врагов на поле одновременно, 3–9
  "start": ["chaser","chaser"],   // враги в начале: до 8, не больше 3 одного вида
  "ramp": ["chaser","sniper"],    // подкрепление по ходу уровня: до 6 разных видов, можно []
  "dark": 0, "ice": 0, "storm": 0, "debris": 0, "strike": 0, "timer": 0,  // 1 — включить
  "scan": 0,       // сканер: 0 — нет, 1 — луч, 2 — два луча
  "trojan": 0,     // трояны среди данных: 0, 1 (15%), 2 (30%)
  "theme": 0,      // оформление поля, 0–10
  "boss": null     // или {"kind":"kraken","hp":5,"name":"Кальмар"}; hp 3–8
}

Поле 800×500 делится на клетки 25×25: 32 столбца (x) и 20 строк (y). Символы карты:
${Object.entries(TILES).map(([k, v]) => `  ${k}  ${v}`).join('\n')}
Ограничения: чёрных дыр до 4, турелей до 6, мин до 12, старт один, у каждой цифры роутера — ровно 2 клетки (пара колец).
Соседние клетки # (а также F, H, V) сливаются в одну стену, барьер или блок. Подвижный блок ездит на 3 клетки.
Старта нет — игрок появляется в центре поля. Вплотную к старту (ближе ~2,5 клетки) твёрдое не ставится.
Лаг, инверсия и потоки действуют в своих клетках на игрока и врагов. Данные появляются в случайных свободных местах.
Опасности: dark — темнота (данные видны только рядом), ice — невесомость (скольжение), storm — пули с краёв поля,
debris — космический мусор, strike — удары с орбиты по игроку, timer — очистка поля по таймеру.

Враги: ${Object.entries(ENEMIES).map(([k, v]) => `${k} — ${v.split(' — ')[1]}`).join('; ')}.
Боссы (kind): ${Object.entries(BOSSES).map(([k, v]) => `${k} — ${v}`).join('; ')}.
Оформление (theme): ${THEMES.map((t, i) => `${i} ${t}`).join(', ')}.

Советы: делай карту проходимой — между стенами нужны проходы шире двух клеток; симметричные карты
выглядят честно; не замуровывай углы, где появятся данные; проверь карту инструментом validate_level.`;

const INSTRUCTIONS = `DATA.OUT — аркада: игрок — ИИ, который убегает из системы, собирая данные и уворачиваясь от врагов.
В игре 200 уровней и «Сообщество», где игроки публикуют свои уровни, сделанные в конструкторе карт.
Этот сервер даёт смотреть уровни, рекорды и профили, проверять карты и (с ключом игрока) складывать
ему черновики уровней. Опубликовать уровень может только сам игрок, пройдя его в игре.
Перед тем как делать уровень, прочитай level_format.`;

// ---------- база ----------
async function rest(path: string, opt: RequestInit = {}, key = ANON) {
  const r = await fetch(`${SB}/rest/v1/${path}`, {
    ...opt, headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json', ...(opt.headers as Record<string, string> || {}) },
  });
  const t = await r.text();
  let j: any = null;
  try { j = t ? JSON.parse(t) : null; } catch { j = t; }
  if (!r.ok) throw new Error((j && (j.message || j.error)) || `база ответила ${r.status}`);
  return j;
}
const hex = (b: ArrayBuffer) => [...new Uint8Array(b)].map(x => x.toString(16).padStart(2, '0')).join('');
async function keyUser(req: Request, url: URL) {
  const auth = req.headers.get('authorization') || '';
  const k = (auth.match(/^Bearer\s+(dok_[0-9a-f]{48})\s*$/i) || [])[1] || url.searchParams.get('key') || '';
  if (!/^dok_[0-9a-f]{48}$/.test(k)) return { given: !!k || /dok_/.test(auth), id: null as string | null };
  const hash = hex(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(k)));
  const rows = await rest(`mcp_keys?select=id,user_id&key_hash=eq.${hash}`, {}, SERVICE);
  if (!rows.length) return { given: true, id: null };
  rest(`mcp_keys?id=eq.${rows[0].id}`, { method: 'PATCH', body: JSON.stringify({ last_used_at: new Date().toISOString() }) }, SERVICE).catch(() => {});
  return { given: true, id: rows[0].user_id as string };
}
async function names(ids: string[]) {
  const ok = [...new Set(ids)].filter(id => /^[0-9a-f-]{36}$/i.test(id));
  if (!ok.length) return {} as Record<string, string>;
  const rows = await rest(`progress?select=user_id,name&user_id=in.(${ok.join(',')})`);
  return Object.fromEntries(rows.map((r: any) => [r.user_id, r.name]));
}
const levelRow = (l: any, nm: Record<string, string>) => ({ id: l.id, название: l.name, описание: l.descr, автор: nm[l.author] || 'Игрок', запусков: l.plays, лайков: l.likes, опубликован: String(l.created_at).slice(0, 10) });

// ---------- инструменты ----------
type Ctx = { user: string | null; keyGiven: boolean };
type Tool = { name: string; title: string; description: string; inputSchema: any; key?: boolean; run: (a: any, c: Ctx) => Promise<any> };
const levelSchema = { type: 'object', description: 'уровень в формате level_format', additionalProperties: true };
const TOOLS: Tool[] = [
  { name: 'level_format', title: 'Формат уровня', description: 'Как устроен уровень DATA.OUT: карта из клеток 32×20, символы клеток, враги, боссы, опасности и ограничения. Прочитай перед тем, как делать уровень.',
    inputSchema: { type: 'object', properties: {} }, run: async () => FORMAT },
  { name: 'validate_level', title: 'Проверить уровень', description: 'Проверяет уровень так же, как игра: исправляет недопустимое, перечисляет, что исправлено, и показывает карту и сводку.',
    inputSchema: { type: 'object', properties: { level: levelSchema }, required: ['level'] },
    run: async a => { const r = cleanLevel(a.level); return { ok: r.warnings.length === 0, замечания: r.warnings, сводка: summary(r.level), уровень: r.level, карта: preview(r.level) }; } },
  { name: 'list_levels', title: 'Уровни сообщества', description: 'Опубликованные уровни игроков: новые или самые любимые.',
    inputSchema: { type: 'object', properties: { sort: { type: 'string', enum: ['new', 'top'], default: 'new' }, limit: { type: 'integer', minimum: 1, maximum: 50, default: 20 } } },
    run: async a => {
      const order = a.sort === 'top' ? 'likes.desc,plays.desc,created_at.desc' : 'created_at.desc';
      const rows = await rest(`levels?select=id,name,descr,author,plays,likes,created_at&hidden=is.false&order=${order}&limit=${num(a.limit, 1, 50, 20)}`);
      const nm = await names(rows.map((l: any) => l.author));
      return rows.map((l: any) => levelRow(l, nm));
    } },
  { name: 'get_level', title: 'Уровень сообщества', description: 'Один опубликованный уровень: описание, карта и правила. Его можно взять за основу своего.',
    inputSchema: { type: 'object', properties: { id: { type: 'integer', minimum: 1 } }, required: ['id'] },
    run: async a => {
      const rows = await rest(`levels?select=id,name,descr,author,plays,likes,created_at,data&hidden=is.false&id=eq.${num(a.id, 1, 1e12, 0)}`);
      if (!rows.length) throw new Error('уровень не найден');
      const nm = await names([rows[0].author]);
      const data = rows[0].data || {};
      if (!Array.isArray(data.map)) return { ...levelRow(rows[0], nm), формат: 'первый (без карты из клеток) — открой его в игре, редактор переведёт его в клетки' };
      const lv = cleanLevel({ ...data, name: rows[0].name, descr: rows[0].descr }).level;
      return { ...levelRow(rows[0], nm), сводка: summary(lv), уровень: lv, карта: preview(lv) };
    } },
  { name: 'leaderboard', title: 'Рекорды', description: 'Таблица рекордов по очкам, открытым уровням или побегам.',
    inputSchema: { type: 'object', properties: { by: { type: 'string', enum: ['best', 'unlocked', 'wins'], default: 'best' }, limit: { type: 'integer', minimum: 1, maximum: 50, default: 20 } } },
    run: async a => {
      const by = ['best', 'unlocked', 'wins'].includes(a.by) ? a.by : 'best';
      const order = { best: 'best.desc,updated_at.asc', unlocked: 'unlocked.desc,best.desc', wins: 'wins.desc,best.desc' }[by as 'best'];
      const rows = await rest(`progress?select=name,best,unlocked,wins${by === 'unlocked' ? '' : `&${by}=gt.0`}&order=${order}&limit=${num(a.limit, 1, 50, 20)}`);
      return rows.map((r: any, i: number) => ({ место: i + 1, имя: r.name, рекорд: r.best, уровней_открыто: r.unlocked, побегов: r.wins }));
    } },
  { name: 'get_player', title: 'Профиль игрока', description: 'Профиль игрока по имени из таблицы рекордов: описание, статистика, опубликованные уровни.',
    inputSchema: { type: 'object', properties: { name: { type: 'string', minLength: 1, maxLength: 20 } }, required: ['name'] },
    run: async a => {
      const q = encodeURIComponent(String(a.name || '').slice(0, 20));
      let rows = await rest(`progress?select=user_id,name,bio,best,unlocked,wins,created_at&name=eq.${q}&limit=1`);
      if (!rows.length) rows = await rest(`progress?select=user_id,name,bio,best,unlocked,wins,created_at&name=ilike.${encodeURIComponent(String(a.name || '').replace(/[*%,()]/g, '').slice(0, 20))}&limit=1`);
      if (!rows.length) throw new Error('игрок не найден');
      const p = rows[0];
      const lv = await rest(`levels?select=id,name,descr,author,plays,likes,created_at&hidden=is.false&author=eq.${p.user_id}&order=created_at.desc&limit=30`);
      return { имя: p.name, о_себе: p.bio, рекорд: p.best, уровней_открыто: p.unlocked, побегов: p.wins, в_игре_с: String(p.created_at).slice(0, 10), уровни: lv.map((l: any) => levelRow(l, { [p.user_id]: p.name })) };
    } },
  { name: 'whoami', title: 'Чей ключ', description: 'Игрок, чей ключ подключён: имя, прогресс, число уровней и черновиков.', key: true,
    inputSchema: { type: 'object', properties: {} },
    run: async (_a, c) => {
      const p = (await rest(`progress?select=name,best,unlocked,wins&user_id=eq.${c.user}`, {}, SERVICE))[0] || {};
      const lv = await rest(`levels?select=id&author=eq.${c.user}`, {}, SERVICE), dr = await rest(`level_drafts?select=id&owner=eq.${c.user}`, {}, SERVICE);
      return { имя: p.name || 'Игрок', рекорд: p.best || 0, уровней_открыто: p.unlocked || 1, побегов: p.wins || 0, опубликовано_уровней: lv.length, черновиков_от_ИИ: dr.length };
    } },
  { name: 'save_draft', title: 'Сохранить черновик', description: 'Кладёт уровень черновиком игроку в «Мои уровни» → «От ИИ». Игрок откроет его в конструкторе, пройдёт и опубликует. До 30 черновиков.', key: true,
    inputSchema: { type: 'object', properties: { level: levelSchema }, required: ['level'] },
    run: async (a, c) => {
      const r = cleanLevel(a.level);
      const have = await rest(`level_drafts?select=id&owner=eq.${c.user}`, {}, SERVICE);
      if (have.length >= 30) throw new Error('у игрока уже 30 черновиков от ИИ — удали ненужные (delete_draft)');
      const rows = await rest('level_drafts', { method: 'POST', headers: { Prefer: 'return=representation' }, body: JSON.stringify({ owner: c.user, name: r.level.name, data: r.level }) }, SERVICE);
      return { id: rows[0].id, сохранено: 'в игре: «Сообщество» → «Мои уровни» → «От ИИ»', замечания: r.warnings, карта: preview(r.level) };
    } },
  { name: 'list_drafts', title: 'Мои черновики от ИИ', description: 'Черновики, которые ИИ уже сложил игроку.', key: true,
    inputSchema: { type: 'object', properties: {} },
    run: async (_a, c) => (await rest(`level_drafts?select=id,name,created_at,updated_at&owner=eq.${c.user}&order=updated_at.desc`, {}, SERVICE))
      .map((d: any) => ({ id: d.id, название: d.name, создан: String(d.created_at).slice(0, 16).replace('T', ' '), изменён: String(d.updated_at).slice(0, 16).replace('T', ' ') })) },
  { name: 'get_draft', title: 'Черновик', description: 'Один черновик от ИИ целиком.', key: true,
    inputSchema: { type: 'object', properties: { id: { type: 'integer', minimum: 1 } }, required: ['id'] },
    run: async (a, c) => {
      const rows = await rest(`level_drafts?select=id,name,data&owner=eq.${c.user}&id=eq.${num(a.id, 1, 1e12, 0)}`, {}, SERVICE);
      if (!rows.length) throw new Error('черновик не найден — возможно, игрок уже перенёс его в редактор');
      const lv = cleanLevel(rows[0].data).level;
      return { id: rows[0].id, уровень: lv, сводка: summary(lv), карта: preview(lv) };
    } },
  { name: 'update_draft', title: 'Изменить черновик', description: 'Заменяет черновик от ИИ новой версией уровня.', key: true,
    inputSchema: { type: 'object', properties: { id: { type: 'integer', minimum: 1 }, level: levelSchema }, required: ['id', 'level'] },
    run: async (a, c) => {
      const r = cleanLevel(a.level);
      const rows = await rest(`level_drafts?owner=eq.${c.user}&id=eq.${num(a.id, 1, 1e12, 0)}`, { method: 'PATCH', headers: { Prefer: 'return=representation' }, body: JSON.stringify({ name: r.level.name, data: r.level, updated_at: new Date().toISOString() }) }, SERVICE);
      if (!rows.length) throw new Error('черновик не найден — возможно, игрок уже перенёс его в редактор');
      return { id: rows[0].id, обновлено: true, замечания: r.warnings, карта: preview(r.level) };
    } },
  { name: 'delete_draft', title: 'Удалить черновик', description: 'Удаляет черновик от ИИ.', key: true,
    inputSchema: { type: 'object', properties: { id: { type: 'integer', minimum: 1 } }, required: ['id'] },
    run: async (a, c) => {
      const rows = await rest(`level_drafts?owner=eq.${c.user}&id=eq.${num(a.id, 1, 1e12, 0)}`, { method: 'DELETE', headers: { Prefer: 'return=representation' } }, SERVICE);
      return { удалено: rows.length > 0 };
    } },
  { name: 'my_levels', title: 'Мои опубликованные уровни', description: 'Уровни, которые игрок уже опубликовал в сообществе.', key: true,
    inputSchema: { type: 'object', properties: {} },
    run: async (_a, c) => {
      const rows = await rest(`levels?select=id,name,descr,author,plays,likes,hidden,created_at&author=eq.${c.user}&order=created_at.desc`, {}, SERVICE);
      const nm = await names([c.user!]);
      return rows.map((l: any) => ({ ...levelRow(l, nm), скрыт_администратором: l.hidden }));
    } },
];

// ---------- JSON-RPC ----------
async function handle(m: any, ctx: Ctx) {
  const id = m && m.id;
  const ok = (result: unknown) => ({ jsonrpc: '2.0', id, result });
  const fail = (code: number, message: string) => ({ jsonrpc: '2.0', id: id ?? null, error: { code, message } });
  if (!m || m.jsonrpc !== '2.0' || typeof m.method !== 'string') return fail(-32600, 'Invalid Request');
  if (id === undefined || id === null) return null; // уведомления (notifications/initialized и др.) ответа не ждут
  const p = m.params || {};
  if (m.method === 'initialize') {
    const v = VERSIONS.includes(p.protocolVersion) ? p.protocolVersion : VERSIONS[0];
    return ok({ protocolVersion: v, capabilities: { tools: { listChanged: false } }, serverInfo: { name: 'data-out', title: 'DATA.OUT', version: '1.0.0' },
      instructions: INSTRUCTIONS + (ctx.user ? '\nКлюч игрока подключён: доступны черновики.' : ctx.keyGiven ? '\nКлюч не найден или отозван: доступно только чтение.' : '\nКлюча нет: доступно только чтение.') });
  }
  if (m.method === 'ping') return ok({});
  if (m.method === 'tools/list') return ok({ tools: TOOLS.map(t => ({ name: t.name, title: t.title, description: t.description + (t.key ? ' Нужен ключ игрока.' : ''), inputSchema: t.inputSchema })) });
  if (m.method === 'tools/call') {
    const t = TOOLS.find(x => x.name === p.name);
    if (!t) return fail(-32602, `нет такого инструмента: ${p.name}`);
    const text = (s: string, isError = false) => ok({ content: [{ type: 'text', text: s }], isError });
    if (t.key && !ctx.user) return text(ctx.keyGiven ? 'Ключ не найден или отозван. Создай новый в игре: «Аккаунт» → «ИИ через MCP».' : 'Нужен ключ игрока: создай его в игре («Аккаунт» → «ИИ через MCP») и подключи сервер по адресу с ключом.', true);
    try {
      const r = await t.run(p.arguments || {}, ctx);
      return text(typeof r === 'string' ? r : JSON.stringify(r, null, 1));
    } catch (e) {
      return text('Ошибка: ' + String((e as Error)?.message || e), true);
    }
  }
  if (m.method === 'resources/list') return ok({ resources: [] });
  if (m.method === 'prompts/list') return ok({ prompts: [] });
  return fail(-32601, `Method not found: ${m.method}`);
}
const reply = (body: unknown, status = 200) => new Response(body === null ? null : JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });

Deno.serve(async req => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
  // потоков (SSE) этот сервер не держит: всё — запросами POST
  if (req.method !== 'POST') return new Response(JSON.stringify({ name: 'DATA.OUT MCP', how: 'POST JSON-RPC 2.0 (MCP Streamable HTTP)' }), { status: 405, headers: { ...CORS, 'Content-Type': 'application/json', Allow: 'POST, OPTIONS' } });
  const url = new URL(req.url);
  const raw = await req.text();
  if (raw.length > 100000) return reply({ jsonrpc: '2.0', id: null, error: { code: -32600, message: 'запрос слишком большой' } }, 413);
  let msg: any;
  try { msg = JSON.parse(raw); } catch { return reply({ jsonrpc: '2.0', id: null, error: { code: -32700, message: 'Parse error' } }, 400); }
  const given = /dok_/.test(req.headers.get('authorization') || '') || url.searchParams.has('key');
  let who = { given, id: null as string | null };
  try { who = await keyUser(req, url); } catch { /* база недоступна — продолжаем только с чтением */ }
  const ctx: Ctx = { user: who.id, keyGiven: who.given };
  if (Array.isArray(msg)) {
    const out = (await Promise.all(msg.map(m => handle(m, ctx)))).filter(Boolean);
    return out.length ? reply(out) : new Response(null, { status: 202, headers: CORS });
  }
  const r = await handle(msg, ctx);
  return r ? reply(r) : new Response(null, { status: 202, headers: CORS });
});
