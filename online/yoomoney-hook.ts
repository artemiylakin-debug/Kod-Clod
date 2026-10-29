// Supabase Edge Function «yoomoney-hook»: ЮMoney сообщает сюда о каждой поддержке игры.
//
// Игра отправляет игрока на страницу оплаты ЮMoney, а в метке (label) платежа передаёт его id.
// После оплаты ЮMoney присылает сюда уведомление. Функция проверяет подпись уведомления
// секретом из настроек кошелька, записывает платёж и отмечает игрока как поддержавшего —
// после этого игра открывает ему набор «Поддержка» и звезду в рекордах.
//
// Секрет задаётся в Supabase → Edge Functions → Secrets (в коде его нет):
//   YOOMONEY_SECRET   «Секрет для проверки подлинности» со страницы yoomoney.ru/transfer/myservices/http-notification
// SUPABASE_URL и SUPABASE_SERVICE_ROLE_KEY Supabase подставляет сам.
// В настройках функции выключи «Verify JWT»: её вызывает ЮMoney, а не игрок.

import { createClient } from 'jsr:@supabase/supabase-js@2';

const env = (k) => Deno.env.get(k) ?? '';
const text = (body, status = 200) => new Response(body, { status, headers: { 'Content-Type': 'text/plain' } });

// сравнение за одно и то же время, сколько бы символов ни совпало
function sameHex(a, b) {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

async function sha1hex(s) {
  const d = await crypto.subtle.digest('SHA-1', new TextEncoder().encode(s));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return text('нужен POST', 405);
  const secret = env('YOOMONEY_SECRET');
  if (!secret) return text('не задан YOOMONEY_SECRET', 500);

  const f = new URLSearchParams(await req.text());
  const g = (k) => f.get(k) ?? '';
  // подпись по правилам ЮMoney: поля через «&» в этом порядке, секрет — между codepro и label
  const line = [g('notification_type'), g('operation_id'), g('amount'), g('currency'), g('datetime'),
    g('sender'), g('codepro'), secret, g('label')].join('&');
  if (!sameHex(await sha1hex(line), g('sha1_hash').toLowerCase())) return text('неверная подпись', 400);
  // поддержка — только в рублях (код валюты 643)
  if (g('currency') !== '643') return text('ok');

  // проверка из настроек кошелька и платежи, которые ещё не зачислены, ничего не открывают
  if (g('test_notification') === 'true') return text('ok');
  if (g('unaccepted') === 'true' || g('codepro') === 'true') return text('ok');
  // без id игрока — поддержка без аккаунта: спасибо, но открывать набор некому
  const label = g('label');
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(label)) return text('ok');
  const amount = Number(g('withdraw_amount') || g('amount')) || 0;

  const admin = createClient(env('SUPABASE_URL'), env('SUPABASE_SERVICE_ROLE_KEY'), { auth: { persistSession: false } });
  // один платёж — одна строка: повторное уведомление о той же операции ничего не меняет
  const ins = await admin.from('donations').insert({ operation_id: g('operation_id'), user_id: label, amount });
  // 23505 — уже записан, 23503 — такого игрока нет; на остальные ошибки ЮMoney пришлёт уведомление ещё раз
  if (ins.error && ins.error.code !== '23505') {
    if (ins.error.code === '23503') return text('ok');
    return text('ошибка базы: ' + ins.error.message, 500);
  }
  const sup = await admin.from('supporters').upsert({ user_id: label }, { onConflict: 'user_id', ignoreDuplicates: true });
  if (sup.error) return text('ошибка базы: ' + sup.error.message, 500);
  return text('ok');
});
