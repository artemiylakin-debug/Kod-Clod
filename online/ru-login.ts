// Supabase Edge Function «ru-login»: вход в DATA.OUT через VK ID и Яндекс ID
// и регистрация аккаунтов на самом сайте (логин и пароль, без сторонних сервисов).
//
// У Supabase нет встроенного входа через VK и Яндекс, поэтому игра отдаёт этой функции
// код авторизации, функция обменивает его у VK или Яндекса на данные пользователя,
// заводит (или находит) этого пользователя в Supabase и возвращает игре обычную сессию.
//
// Аккаунт на сайте функция только создаёт (без письма на почту — почты у игрока нет);
// входит в него игра сама, обычным входом Supabase по паролю.
//
// Секреты задаются в Supabase → Edge Functions → Secrets (в коде их нет):
//   SITE_ORIGIN           адрес сайта игры, например https://artemiylakin-debug.github.io
//   VK_APP_ID             ID приложения VK ID
//   YANDEX_CLIENT_ID      ClientID приложения Яндекс ID
//   YANDEX_CLIENT_SECRET  Client secret приложения Яндекс ID
// SUPABASE_URL, SUPABASE_ANON_KEY и SUPABASE_SERVICE_ROLE_KEY Supabase подставляет сам.
// В настройках функции выключи «Verify JWT»: её вызывают игроки, которые ещё не вошли.
//
// Защита (6.0): регистраций по логину — не больше SIGNUP_PER_HOUR в час с одного адреса (журнал
// public.signup_log, в нём только хеш адреса); логин, занятый в обход игры неподтверждённой
// регистрацией Supabase, освобождается; игроку не уходят внутренние тексты ошибок сервера.

import { createClient } from 'jsr:@supabase/supabase-js@2';

const env = (k) => Deno.env.get(k) ?? '';
// без SITE_ORIGIN — адрес официального сайта, а не «любой сайт»
const SITE = env('SITE_ORIGIN') || 'https://artemiylakin-debug.github.io';
const SIGNUP_PER_HOUR = 5;
const CORS = {
  'Access-Control-Allow-Origin': SITE,
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (body, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });
const form = (fields) => ({
  method: 'POST',
  headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
  body: new URLSearchParams(fields),
});

// VK ID (OAuth 2.1 с PKCE): код → токен → данные пользователя
async function vkUser(p) {
  const clientId = env('VK_APP_ID');
  const tok = await fetch('https://id.vk.com/oauth2/auth', form({
    grant_type: 'authorization_code', code: p.code, code_verifier: p.code_verifier,
    client_id: clientId, device_id: p.device_id, redirect_uri: p.redirect_uri, state: p.state,
  })).then((r) => r.json());
  if (!tok.access_token) throw new Shown('VK: ' + (tok.error_description || tok.error || 'нет токена'));
  const info = await fetch('https://id.vk.com/oauth2/user_info', form({
    client_id: clientId, access_token: tok.access_token,
  })).then((r) => r.json());
  const u = info.user;
  if (!u || !u.user_id) throw new Shown('VK: нет данных пользователя');
  return { id: 'vk_' + u.user_id, provider: 'vk', name: [u.first_name, u.last_name].filter(Boolean).join(' '), avatar: u.avatar || '' };
}

// Яндекс ID (OAuth 2.0 с PKCE): код → токен → данные пользователя
async function yandexUser(p) {
  const tok = await fetch('https://oauth.yandex.ru/token', form({
    grant_type: 'authorization_code', code: p.code, code_verifier: p.code_verifier,
    client_id: env('YANDEX_CLIENT_ID'), client_secret: env('YANDEX_CLIENT_SECRET'),
  })).then((r) => r.json());
  if (!tok.access_token) throw new Shown('Яндекс: ' + (tok.error_description || tok.error || 'нет токена'));
  const info = await fetch('https://login.yandex.ru/info?format=json', {
    headers: { Authorization: 'OAuth ' + tok.access_token },
  }).then((r) => r.json());
  if (!info.id) throw new Shown('Яндекс: нет данных пользователя');
  return { id: 'ya_' + info.id, provider: 'yandex', name: info.display_name || info.real_name || info.login || '', avatar: '' };
}

const exists = (e) => /already|exists|registered/i.test(e?.message || '');

// служебный адрес аккаунта на сайте. Латинский логин и есть адрес (так заведены первые аккаунты);
// в адресе не бывает русских букв и пробелов, поэтому для остальных логинов адрес — начало SHA-256
// от логина. Игра (siteEmail в index.html) считает так же — по этому адресу она и входит
async function siteEmail(login) {
  if (/^[a-z0-9_-]+$/.test(login)) return login + '@player.data-out.app';
  const h = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode('data-out:' + login)));
  return 'u' + [...h.slice(0, 20)].map((x) => x.toString(16).padStart(2, '0')).join('') + '@player.data-out.app';
}

async function sha256hex(s) {
  const h = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s)));
  return [...h].map((x) => x.toString(16).padStart(2, '0')).join('');
}
// адрес игрока — первый в x-forwarded-for; хранится только хеш с солью проекта
const ipHash = (req) => sha256hex('data-out-ip:' + ((req.headers.get('x-forwarded-for') || '').split(',')[0].trim() || 'unknown'));

// ошибки, которые можно показать игроку как есть; остальные — общим текстом, подробности — в журнал функции
class Shown extends Error {}

const session = (s) => json({ access_token: s.access_token, refresh_token: s.refresh_token, expires_in: s.expires_in });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'нужен POST' }, 405);
  try {
    const p = await req.json();
    const url = env('SUPABASE_URL');
    const admin = createClient(url, env('SUPABASE_SERVICE_ROLE_KEY'), { auth: { persistSession: false } });
    const pub = createClient(url, env('SUPABASE_ANON_KEY'), { auth: { persistSession: false } });

    // регистрация на сайте: логин и пароль; служебный адрес нужен Supabase как имя для входа.
    // Логин — русские или латинские буквы, цифры, «_», «-» и пробелы; регистр не важен,
    // а имя в игре остаётся таким, как его набрали
    if (p.provider === 'site') {
      const name = typeof p.login === 'string' ? p.login.normalize('NFC').replace(/\s+/g, ' ').trim() : '';
      const login = name.toLowerCase();
      const password = typeof p.password === 'string' ? p.password : '';
      if (!/^[a-z0-9а-яё_ -]{3,20}$/.test(login)) return json({ error: 'логин — от 3 до 20 знаков: буквы, цифры, пробел, «_» или «-»' }, 400);
      if (password.length < 8 || password.length > 72) return json({ error: 'пароль — от 8 до 72 символов' }, 400);
      // не больше SIGNUP_PER_HOUR регистраций в час с одного адреса; журнал недоступен — не мешаем регистрации
      const ih = await ipHash(req);
      const since = new Date(Date.now() - 3600e3).toISOString();
      const recent = await admin.from('signup_log').select('ip_hash', { count: 'exact', head: true }).eq('ip_hash', ih).gte('at', since);
      if (!recent.error && (recent.count ?? 0) >= SIGNUP_PER_HOUR) return json({ error: 'слишком много регистраций с этого адреса — попробуй через час' }, 429);
      const email = await siteEmail(login);
      const make = () => admin.auth.admin.createUser({
        email, password, email_confirm: true,
        user_metadata: { name, provider: 'site' }, app_metadata: { data_out: 'site' },
      });
      let created = await make();
      if (created.error && exists(created.error)) {
        // логин мог занять кто-то обычной регистрацией Supabase в обход игры: такой аккаунт не подтверждён
        // (почты нет) и войти в него нельзя — освобождаем логин. Аккаунты игры (метка data_out) не трогаем
        const found = await admin.auth.admin.generateLink({ type: 'magiclink', email });
        const u = found.data?.user;
        if (u && u.app_metadata?.data_out !== 'site' && !u.email_confirmed_at) {
          const del = await admin.auth.admin.deleteUser(u.id);
          if (!del.error) created = await make();
        }
      }
      if (created.error) {
        if (exists(created.error)) return json({ error: 'этот логин уже занят' }, 409);
        throw created.error;
      }
      await admin.from('signup_log').insert({ ip_hash: ih });
      const s = await pub.auth.signInWithPassword({ email, password });
      if (s.error || !s.data.session) throw s.error || new Error('Supabase не выдал сессию');
      return session(s.data.session);
    }

    if (typeof p.code !== 'string' || typeof p.code_verifier !== 'string' || typeof p.redirect_uri !== 'string') {
      return json({ error: 'нет кода авторизации' }, 400);
    }
    const who = p.provider === 'vk' ? await vkUser(p) : p.provider === 'yandex' ? await yandexUser(p) : null;
    if (!who) return json({ error: 'неизвестный сервис входа' }, 400);

    // служебный адрес: по нему Supabase узнаёт того же игрока при следующем входе; писем на него не шлётся
    const email = who.id + '@login.data-out.app';
    const meta = { name: who.name, provider: who.provider, avatar_url: who.avatar };

    // app_metadata меняет только сервер: по метке видно, что аккаунт завела эта функция
    const created = await admin.auth.admin.createUser({ email, email_confirm: true, user_metadata: meta, app_metadata: { data_out: who.provider } });
    if (created.error && !exists(created.error)) throw created.error;
    const link = await admin.auth.admin.generateLink({ type: 'magiclink', email });
    if (link.error) throw link.error;
    if (!created.data?.user) {
      // адрес мог заранее занять кто-то через обычную регистрацию Supabase, чтобы потом войти
      // в чужой аккаунт по своему паролю, — такой аккаунт не отдаём
      if (link.data.user?.app_metadata?.data_out !== who.provider) {
        return json({ error: 'аккаунт для этого входа создан не игрой — напиши автору игры' }, 409);
      }
      // имя и аватар могли поменяться в VK или Яндексе — обновляем при каждом входе
      await admin.auth.admin.updateUserById(link.data.user.id, { user_metadata: meta });
    }

    const v = await pub.auth.verifyOtp({ token_hash: link.data.properties.hashed_token, type: 'magiclink' });
    if (v.error || !v.data.session) throw v.error || new Error('Supabase не выдал сессию');
    return session(v.data.session);
  } catch (e) {
    if (e instanceof Shown) return json({ error: String(e.message).slice(0, 200) }, 400);
    console.error('ru-login', e);
    return json({ error: 'не получилось — попробуй ещё раз чуть позже' }, 400);
  }
});
