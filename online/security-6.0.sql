-- DATA.OUT 6.0 — защита данных в базе. Файл можно запускать повторно.
-- 1) Отзывает лишние права на запись, которые Supabase выдаёт новым таблицам по умолчанию:
--    от записи и так защищают правила RLS, но лишнее право — это одна ошибка до дыры (TRUNCATE RLS не проверяет).
-- 2) Проверяет правдоподобие прогресса, который присылает игра: открывать уровни, набирать рекорд и биты
--    можно не быстрее, чем это возможно в игре, побег — только с открытым последним уровнем,
--    надеть можно только свой предмет облика, купить — только на заработанные биты.
--    Значения, которые уже лежат в базе, не трогаются: проверяется только то, что меняется.
--    Неправдоподобное не отвергается, а урезается до допустимого — так игра никогда не «ломается»
--    на сохранении, а честный игрок, играющий очень быстро, догонит своё на следующих сохранениях.
-- 3) Журнал регистраций для ограничения их числа в функции ru-login.
-- Администраторы и сервер (service_role, функции) проверку не проходят — им можно всё, как и раньше.

-- ---------- 1. права ----------
revoke insert, update, delete, truncate on public.donations from anon, authenticated;
revoke insert, update, delete, truncate on public.supporters from anon;
revoke update, truncate on public.supporters from authenticated;
revoke insert, update, delete, truncate on public.progress from anon;
revoke delete, truncate on public.progress from authenticated;
revoke truncate on all tables in schema public from anon, authenticated;
-- новые таблицы впредь без прав на запись: каждая выдаёт их себе явно (как в schema.sql)
alter default privileges in schema public revoke insert, update, delete, truncate on tables from anon, authenticated;

-- ---------- 2. проверка прогресса ----------
-- каталог облика и границы актов — копия из index.html (tools/cosmetics-catalog.mjs);
-- при новых предметах или актах обновлять вместе с игрой (тест tools/check-catalog.mjs это проверяет)
create or replace function public.data_out_items() returns jsonb
language sql immutable set search_path = '' as $fn$
  select '{"c":[{},{},{},{},{"p":150},{"p":150},{"p":250},{"p":250},{"p":350},{"p":400},{"p":500,"a":2},{"p":700,"a":4},{"p":1500},{"p":2000,"s":1},{"p":800},{"p":1100,"a":8},{"p":1400,"a":11},{"p":2000,"s":1},{"p":2000,"s":1},{"p":1700,"a":14},{"p":2000,"a":17},{"p":2300,"a":20},{"p":2600,"a":23},{"p":2900,"a":26}],"s":[{},{},{},{"p":200},{"p":300},{"p":500},{"p":600},{"p":600,"a":3},{"p":800,"a":5},{"p":2000,"s":1},{"p":900}],"t":[{},{"p":200},{"p":350},{"p":500},{"p":700},{"p":1000},{"p":400,"a":1},{"p":2000,"s":1},{"p":1200,"a":9},{"p":2000,"s":1},{"p":900},{"p":666}],"h":[{},{"p":150},{"p":300},{"p":400},{"p":450},{"p":600},{"p":900,"a":6},{"p":2000,"s":1},{"p":1000,"a":7},{"p":1300,"a":10},{"p":2000,"s":1},{"p":2000,"s":1},{"p":1200},{"p":700},{"p":500},{"p":800},{"p":1000},{"p":900},{"p":600},{"p":350},{"p":400},{"p":1600,"a":13},{"p":1900,"a":16},{"p":2100,"a":18},{"p":2600,"a":23}],"ends":[10,20,39,59,79,99,119,139,159,179,199,219,239,259,279,299,319,339,359,379,399,419,439,459,479,499]}'::jsonb
$fn$;

-- пройден ли акт n (с единицы), как actDone в игре
create or replace function public.data_out_act_done(n int, unlocked int, wins int) returns boolean
language sql immutable set search_path = '' as $fn$
  select case
    when n < 1 then true
    when n < jsonb_array_length(public.data_out_items()->'ends')
      then unlocked > (public.data_out_items()->'ends'->>(n - 1))::int + 1
    else unlocked >= (public.data_out_items()->'ends'->>-1)::int + 1 and wins > 0
  end
$fn$;

create or replace function public.progress_guard() returns trigger
language plpgsql set search_path = '' as $fn$
declare
  cat jsonb := public.data_out_items();
  el numeric;      -- секунд с прошлого сохранения
  o_unl int := 1; o_best int := 0; o_wins int := 0; o_earned int := 0; o_own text := '';
  cost int := 0; it text; r jsonb; k text; idx int; ok boolean; sup boolean;
begin
  -- сервер, владелец проекта и администраторы игры не проверяются
  if current_user not in ('anon', 'authenticated') or public.is_admin() then return new; end if;
  if tg_op = 'UPDATE' then
    o_unl := old.unlocked; o_best := old.best; o_wins := old.wins; o_earned := old.earned; o_own := old.own;
    el := greatest(0, extract(epoch from now() - old.updated_at));
  else
    -- первая запись аккаунта: в расчёт идёт не больше 10 минут с регистрации
    el := least(600, greatest(0, extract(epoch from now() - coalesce((select u.created_at from auth.users u where u.id = new.user_id), now()))));
  end if;

  -- уровни: каждый новый — не чаще раза в 10 секунд
  new.unlocked := least(new.unlocked, o_unl + 1 + floor(el / 10)::int);
  -- побег — только с открытым последним уровнем и по одному за сохранение
  if new.wins > o_wins then
    new.wins := case when new.unlocked >= (cat->'ends'->>-1)::int + 1 then o_wins + 1 else o_wins end;
  end if;
  -- рекорд: не больше 300 очков на открытый уровень и не быстрее 5 очков в секунду (+100 сразу)
  if new.best > o_best then
    new.best := least(new.best, greatest(o_best, least(o_best + 100 + floor(el * 5)::int, new.unlocked * 300)));
  end if;
  -- биты: не быстрее 6 в секунду (+200 сразу)
  if new.earned > o_earned then
    new.earned := least(new.earned, o_earned + 200 + floor(el * 6)::int);
  end if;

  -- купленное: только предметы с ценой и на сумму не больше заработанного
  if new.own is distinct from o_own then
    ok := true;
    foreach it in array string_to_array(new.own, ',') loop
      continue when it = '';
      k := left(it, 1); idx := substr(it, 2)::int;
      r := cat->k->idx;
      if r is null or r->'p' is null then ok := false; exit; end if;
      cost := cost + (r->>'p')::int;
    end loop;
    if not ok or cost > new.earned then new.own := o_own; end if;
  end if;

  -- надетое: только своё (бесплатное, купленное, за пройденный акт, за поддержку)
  sup := exists (select 1 from public.supporters s where s.user_id = new.user_id);
  foreach k in array array['c', 's', 't', 'h'] loop
    idx := case k when 'c' then new.color when 's' then new.shape when 't' then new.trail else new.hat end;
    continue when tg_op = 'UPDATE' and idx = case k when 'c' then old.color when 's' then old.shape when 't' then old.trail else old.hat end;
    r := cat->k->idx;
    ok := r is not null and (
      (r->'p' is null and r->'a' is null and r->'s' is null)
      or (r->'p' is not null and (k || idx) = any (string_to_array(new.own, ',')))
      or (r->'a' is not null and public.data_out_act_done((r->>'a')::int, new.unlocked, new.wins))
      or (r->'s' is not null and sup));
    if not ok then
      idx := case when tg_op = 'UPDATE' then case k when 'c' then old.color when 's' then old.shape when 't' then old.trail else old.hat end else 0 end;
      if k = 'c' then new.color := idx; elsif k = 's' then new.shape := idx; elsif k = 't' then new.trail := idx; else new.hat := idx; end if;
    end if;
  end loop;
  return new;
end $fn$;
revoke execute on function public.progress_guard() from public;
drop trigger if exists progress_guard on public.progress;
create trigger progress_guard before insert or update on public.progress
  for each row execute function public.progress_guard();

-- ---------- 3. журнал регистраций ----------
-- функция ru-login пишет сюда хеш адреса каждой регистрации и считает их за час; игрокам таблица не видна
create table if not exists public.signup_log (
  ip_hash text not null,
  at      timestamptz not null default now()
);
create index if not exists signup_log_ip_at_idx on public.signup_log (ip_hash, at desc);
alter table public.signup_log enable row level security;
revoke all on public.signup_log from anon, authenticated;
