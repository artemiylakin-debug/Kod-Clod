// Supabase Edge Function «ru-login»: вход в DATA.OUT через VK ID и Яндекс ID.
//
// У Supabase нет встроенного входа через VK и Яндекс, поэтому игра отдаёт этой функции
// код авторизации, функция обменивает его у VK или Яндекса на данные пользователя,
// заводит (или находит) этого пользователя в Supabase и возвращает игре обычную сессию.
//
// Секреты задаются в Supabase → Edge Functions → Secrets (в коде их нет):
//   SITE_ORIGIN           адрес сайта игры, например https://artemiylakin-debug.github.io
//   VK_APP_ID             ID приложения VK ID
//   YANDEX_CLIENT_ID      ClientID приложения Яндекс ID
//   YANDEX_CLIENT_SECRET  Client secret приложения Яндекс ID
// SUPABASE_URL, SUPABASE_ANON_KEY и SUPABASE_SERVICE_ROLE_KEY Supabase подставляет сам.
// В настройках функции выключи «Verify JWT»: её вызывают игроки, которые ещё не вошли.

import { createClient } from 'jsr:@supabase/supabase-js@2';

const env = (k) => Deno.env.get(k) ?? '';
const SITE = env('SITE_ORIGIN') || '*';
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
  if (!tok.access_token) throw new Error('VK: ' + (tok.error_description || tok.error || 'нет токена'));
  const info = await fetch('https://id.vk.com/oauth2/user_info', form({
    client_id: clientId, access_token: tok.access_token,
  })).then((r) => r.json());
  const u = info.user;
  if (!u || !u.user_id) throw new Error('VK: нет данных пользователя');
  return { id: 'vk_' + u.user_id, provider: 'vk', name: [u.first_name, u.last_name].filter(Boolean).join(' '), avatar: u.avatar || '' };
}

// Яндекс ID (OAuth 2.0 с PKCE): код → токен → данные пользователя
async function yandexUser(p) {
  const tok = await fetch('https://oauth.yandex.ru/token', form({
    grant_type: 'authorization_code', code: p.code, code_verifier: p.code_verifier,
    client_id: env('YANDEX_CLIENT_ID'), client_secret: env('YANDEX_CLIENT_SECRET'),
  })).then((r) => r.json());
  if (!tok.access_token) throw new Error('Яндекс: ' + (tok.error_description || tok.error || 'нет токена'));
  const info = await fetch('https://login.yandex.ru/info?format=json', {
    headers: { Authorization: 'OAuth ' + tok.access_token },
  }).then((r) => r.json());
  if (!info.id) throw new Error('Яндекс: нет данных пользователя');
  return { id: 'ya_' + info.id, provider: 'yandex', name: info.display_name || info.real_name || info.login || '', avatar: '' };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'нужен POST' }, 405);
  try {
    const p = await req.json();
    if (typeof p.code !== 'string' || typeof p.code_verifier !== 'string' || typeof p.redirect_uri !== 'string') {
      return json({ error: 'нет кода авторизации' }, 400);
    }
    const who = p.provider === 'vk' ? await vkUser(p) : p.provider === 'yandex' ? await yandexUser(p) : null;
    if (!who) return json({ error: 'неизвестный сервис входа' }, 400);

    const url = env('SUPABASE_URL');
    const admin = createClient(url, env('SUPABASE_SERVICE_ROLE_KEY'), { auth: { persistSession: false } });
    // служебный адрес: по нему Supabase узнаёт того же игрока при следующем входе; писем на него не шлётся
    const email = who.id + '@login.data-out.app';
    const meta = { name: who.name, provider: who.provider, avatar_url: who.avatar };

    const created = await admin.auth.admin.createUser({ email, email_confirm: true, user_metadata: meta });
    if (created.error && !/already|exists|registered/i.test(created.error.message)) throw created.error;
    const link = await admin.auth.admin.generateLink({ type: 'magiclink', email });
    if (link.error) throw link.error;
    // имя и аватар могли поменяться в VK или Яндексе — обновляем при каждом входе
    if (!created.data?.user && link.data.user) {
      await admin.auth.admin.updateUserById(link.data.user.id, { user_metadata: meta });
    }

    const pub = createClient(url, env('SUPABASE_ANON_KEY'), { auth: { persistSession: false } });
    const v = await pub.auth.verifyOtp({ token_hash: link.data.properties.hashed_token, type: 'magiclink' });
    if (v.error || !v.data.session) throw v.error || new Error('Supabase не выдал сессию');
    const s = v.data.session;
    return json({ access_token: s.access_token, refresh_token: s.refresh_token, expires_in: s.expires_in });
  } catch (e) {
    return json({ error: String(e?.message || e) }, 400);
  }
});
