-- Таблицы DATA.OUT: прогресс и рекорды, поддержка игры.
-- Выполни в Supabase: SQL Editor → New query → вставь этот файл → Run.
-- Файл можно запускать повторно — например, после обновления игры: он только добавит новое.

create table if not exists public.progress (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  name       text not null default 'Игрок' check (char_length(name) between 1 and 20),
  unlocked   int  not null default 1,
  best       int  not null default 0 check (best between 0 and 1000000),
  wins       int  not null default 0 check (wins between 0 and 100000),
  color      int  not null default 0,
  shape      int  not null default 0,
  updated_at timestamptz not null default now()
);

-- облик и биты (магазин облика)
alter table public.progress add column if not exists trail  int  not null default 0;
alter table public.progress add column if not exists hat    int  not null default 0;
alter table public.progress add column if not exists earned int  not null default 0;
alter table public.progress add column if not exists own    text not null default '';
-- принятая редакция пользовательского соглашения и когда её приняли (время ставит база)
alter table public.progress add column if not exists terms    text not null default '';
alter table public.progress add column if not exists terms_at timestamptz;
-- профиль: описание «о себе», дата первого сохранения и скрытие игрока администратором
alter table public.progress add column if not exists bio        text not null default '';
alter table public.progress add column if not exists created_at timestamptz not null default now();
alter table public.progress add column if not exists hidden     boolean not null default false;

-- границы значений: 500 уровней, до 50 предметов в каждом разделе облика
alter table public.progress drop constraint if exists progress_unlocked_check;
alter table public.progress add constraint progress_unlocked_check check (unlocked between 1 and 500);
alter table public.progress drop constraint if exists progress_color_check;
alter table public.progress add constraint progress_color_check check (color between 0 and 49);
alter table public.progress drop constraint if exists progress_shape_check;
alter table public.progress add constraint progress_shape_check check (shape between 0 and 49);
alter table public.progress drop constraint if exists progress_trail_check;
alter table public.progress add constraint progress_trail_check check (trail between 0 and 49);
alter table public.progress drop constraint if exists progress_hat_check;
alter table public.progress add constraint progress_hat_check check (hat between 0 and 49);
alter table public.progress drop constraint if exists progress_earned_check;
alter table public.progress add constraint progress_earned_check check (earned between 0 and 100000000);
alter table public.progress drop constraint if exists progress_own_check;
alter table public.progress add constraint progress_own_check check (char_length(own) <= 600 and own ~ '^[csth0-9,]*$');
alter table public.progress drop constraint if exists progress_terms_check;
alter table public.progress add constraint progress_terms_check check (terms ~ '^[0-9.]{0,20}$');
alter table public.progress drop constraint if exists progress_bio_check;
alter table public.progress add constraint progress_bio_check check (char_length(bio) <= 200 and bio !~ '[[:cntrl:]]');

-- Администраторы игры видят в ней все таблицы и модерируют сообщество. Список правит только
-- владелец проекта — в SQL Editor или через MCP, например:
--   insert into public.admins (user_id) select id from auth.users where email = 'логин@player.data-out.app';
-- Из игры этот список не поменять.
create table if not exists public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  since   timestamptz not null default now()
);
alter table public.admins enable row level security;
revoke all on public.admins from anon, authenticated;
-- каждый видит в списке только себя — этого хватает, чтобы игра узнала, администратор ли ты
drop policy if exists "admins read own" on public.admins;
create policy "admins read own" on public.admins
  for select to anon, authenticated using (user_id = (select auth.uid()));
grant select on public.admins to anon, authenticated;

create or replace function public.is_admin() returns boolean
language sql stable security invoker set search_path = '' as $$
  select exists (select 1 from public.admins where user_id = (select auth.uid()));
$$;
revoke execute on function public.is_admin() from public;
grant execute on function public.is_admin() to anon, authenticated;

-- время последнего сохранения и время принятия новой редакции соглашения ставит сама база;
-- дату регистрации не меняет никто, скрыть игрока может только администратор (или владелец проекта)
create or replace function public.progress_touch() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  if new.terms <> '' and (tg_op = 'INSERT' or new.terms is distinct from old.terms) then
    new.terms_at := now();
  elsif tg_op = 'UPDATE' then
    new.terms_at := old.terms_at;
  end if;
  if tg_op = 'INSERT' then
    new.created_at := now();
  else
    new.created_at := old.created_at;
  end if;
  if current_user in ('anon', 'authenticated') and not public.is_admin() then
    new.hidden := case when tg_op = 'INSERT' then false else old.hidden end;
  end if;
  return new;
end $$;
drop trigger if exists progress_touch on public.progress;
create trigger progress_touch before insert or update on public.progress
  for each row execute function public.progress_touch();

-- Таблицу рекордов и профили видят все (в них только имя и описание, выбранные игроком, и числа),
-- кроме игроков, скрытых администратором. Записать и поменять свою строку может только сам игрок,
-- а администратор — любую (чтобы стереть оскорбительное имя или описание).
alter table public.progress enable row level security;

drop policy if exists "progress read" on public.progress;
create policy "progress read" on public.progress
  for select using (not hidden or (select auth.uid()) = user_id or (select public.is_admin()));

drop policy if exists "progress insert own" on public.progress;
create policy "progress insert own" on public.progress
  for insert to authenticated with check ((select auth.uid()) = user_id);

drop policy if exists "progress update own" on public.progress;
create policy "progress update own" on public.progress
  for update to authenticated
  using ((select auth.uid()) = user_id or (select public.is_admin()))
  with check ((select auth.uid()) = user_id or (select public.is_admin()));

grant select on public.progress to anon, authenticated;
grant insert, update on public.progress to authenticated;

-- Поддержка игры. Обе таблицы пишет только функция yoomoney-hook (ключом service_role).
-- donations — сами платежи: их не видит никто, кроме владельца проекта в Supabase.
create table if not exists public.donations (
  operation_id text primary key,
  user_id      uuid not null references auth.users(id) on delete cascade,
  amount       numeric(12,2) not null default 0,
  created_at   timestamptz not null default now()
);
create index if not exists donations_user_id_idx on public.donations (user_id);
alter table public.donations enable row level security;
revoke all on public.donations from anon, authenticated;
-- платежи из игры видит только администратор (суммы — в его панели)
drop policy if exists "donations admin read" on public.donations;
create policy "donations admin read" on public.donations
  for select to authenticated using ((select public.is_admin()));
grant select on public.donations to authenticated;

-- supporters — кто поддержал игру (без сумм): по ней игра ставит ★ в рекордах и открывает набор.
create table if not exists public.supporters (
  user_id uuid primary key references auth.users(id) on delete cascade,
  since   timestamptz not null default now()
);
alter table public.supporters enable row level security;
drop policy if exists "supporters read" on public.supporters;
create policy "supporters read" on public.supporters
  for select using (true);
revoke insert, update, delete on public.supporters from anon, authenticated;
grant select on public.supporters to anon, authenticated;
-- администратор может выдать или забрать ★ вручную (например, за поддержку другим способом)
drop policy if exists "supporters admin add" on public.supporters;
create policy "supporters admin add" on public.supporters
  for insert to authenticated with check ((select public.is_admin()));
drop policy if exists "supporters admin remove" on public.supporters;
create policy "supporters admin remove" on public.supporters
  for delete to authenticated using ((select public.is_admin()));
grant insert, delete on public.supporters to authenticated;

-- ================= СООБЩЕСТВО: УРОВНИ ИГРОКОВ =================
-- data — сам уровень (JSON из редактора). Игра проверяет его заново при каждой загрузке,
-- потому что это чужой ввод; база следит только за размером
create table if not exists public.levels (
  id         bigint generated always as identity primary key,
  author     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name       text not null check (char_length(name) between 1 and 30 and name !~ '[[:cntrl:]]'),
  descr      text not null default '' check (char_length(descr) <= 200 and descr !~ '[[:cntrl:]]'),
  data       jsonb not null check (jsonb_typeof(data) = 'object' and pg_column_size(data) <= 12000),
  plays      int not null default 0,
  likes      int not null default 0,
  hidden     boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists levels_author_idx on public.levels (author);
create index if not exists levels_created_idx on public.levels (created_at desc);
create index if not exists levels_likes_idx on public.levels (likes desc);
alter table public.levels enable row level security;

-- автора, счётчики и дату ставит база; скрыть уровень может только администратор
create or replace function public.levels_guard() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  if current_user not in ('anon', 'authenticated') then return new; end if;
  if tg_op = 'INSERT' then
    new.author := (select auth.uid());
    new.plays := 0; new.likes := 0; new.created_at := now();
    -- у игрока, скрытого администратором, новые уровни тоже скрыты
    new.hidden := exists (select 1 from public.progress where user_id = new.author and hidden);
    if (select count(*) from public.levels where author = new.author) >= 30 then
      raise exception 'не больше 30 уровней у одного игрока' using errcode = '23514';
    end if;
  else
    new.author := old.author; new.plays := old.plays; new.likes := old.likes; new.created_at := old.created_at;
    if not public.is_admin() then new.hidden := old.hidden; end if;
  end if;
  return new;
end $$;
drop trigger if exists levels_guard on public.levels;
create trigger levels_guard before insert or update on public.levels
  for each row execute function public.levels_guard();

drop policy if exists "levels read" on public.levels;
create policy "levels read" on public.levels
  for select using (not hidden or author = (select auth.uid()) or (select public.is_admin()));
drop policy if exists "levels add own" on public.levels;
create policy "levels add own" on public.levels
  for insert to authenticated with check (author = (select auth.uid()));
drop policy if exists "levels edit" on public.levels;
create policy "levels edit" on public.levels
  for update to authenticated
  using (author = (select auth.uid()) or (select public.is_admin()))
  with check (author = (select auth.uid()) or (select public.is_admin()));
drop policy if exists "levels remove" on public.levels;
create policy "levels remove" on public.levels
  for delete to authenticated using (author = (select auth.uid()) or (select public.is_admin()));
revoke all on public.levels from anon, authenticated;
grant select on public.levels to anon, authenticated;
grant insert (name, descr, data), update (name, descr, data, hidden), delete on public.levels to authenticated;

-- лайки и запуски: по одной строке на игрока и уровень, счётчики в levels пересчитывает база.
-- Свой уровень не лайкнуть и своими запусками не накрутить
create table if not exists public.level_likes (
  level_id   bigint not null references public.levels(id) on delete cascade,
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (level_id, user_id)
);
create index if not exists level_likes_user_idx on public.level_likes (user_id);
create table if not exists public.level_plays (
  level_id   bigint not null references public.levels(id) on delete cascade,
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (level_id, user_id)
);
create index if not exists level_plays_user_idx on public.level_plays (user_id);
alter table public.level_likes enable row level security;
alter table public.level_plays enable row level security;

create or replace function public.level_count() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_table_name = 'level_likes' then
    update public.levels set likes = greatest(0, likes + case when tg_op = 'INSERT' then 1 else -1 end)
      where id = case when tg_op = 'INSERT' then new.level_id else old.level_id end;
  else
    update public.levels set plays = plays + 1 where id = new.level_id;
  end if;
  return null;
end $$;
revoke execute on function public.level_count() from public, anon, authenticated;
drop trigger if exists level_likes_count on public.level_likes;
create trigger level_likes_count after insert or delete on public.level_likes
  for each row execute function public.level_count();
drop trigger if exists level_plays_count on public.level_plays;
create trigger level_plays_count after insert on public.level_plays
  for each row execute function public.level_count();

drop policy if exists "likes read own" on public.level_likes;
create policy "likes read own" on public.level_likes
  for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists "likes add own" on public.level_likes;
create policy "likes add own" on public.level_likes
  for insert to authenticated with check (user_id = (select auth.uid()) and exists (
    select 1 from public.levels l where l.id = level_id and not l.hidden and l.author <> (select auth.uid())));
drop policy if exists "likes remove own" on public.level_likes;
create policy "likes remove own" on public.level_likes
  for delete to authenticated using (user_id = (select auth.uid()));
revoke all on public.level_likes from anon, authenticated;
grant select, insert, delete on public.level_likes to authenticated;

drop policy if exists "plays read own" on public.level_plays;
create policy "plays read own" on public.level_plays
  for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists "plays add own" on public.level_plays;
create policy "plays add own" on public.level_plays
  for insert to authenticated with check (user_id = (select auth.uid()) and exists (
    select 1 from public.levels l where l.id = level_id and not l.hidden and l.author <> (select auth.uid())));
revoke all on public.level_plays from anon, authenticated;
grant select, insert on public.level_plays to authenticated;

-- ================= ПАНЕЛЬ АДМИНИСТРАТОРА =================
-- все аккаунты с прогрессом: только для администраторов (остальным — ошибка «нет доступа»)
create or replace function public.admin_players()
returns table (user_id uuid, login text, provider text, created_at timestamptz, last_sign_in_at timestamptz,
  name text, bio text, unlocked int, best int, wins int, hidden boolean, supporter boolean, levels int)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_admin() then
    raise exception 'нет доступа' using errcode = '42501';
  end if;
  return query
    select u.id, coalesce(u.raw_user_meta_data->>'name', ''), coalesce(u.raw_user_meta_data->>'provider', ''),
      u.created_at, u.last_sign_in_at, p.name, p.bio, p.unlocked, p.best, p.wins, coalesce(p.hidden, false),
      exists (select 1 from public.supporters s where s.user_id = u.id),
      (select count(*)::int from public.levels l where l.author = u.id)
    from auth.users u left join public.progress p on p.user_id = u.id
    order by u.created_at desc
    limit 1000;
end $$;
revoke execute on function public.admin_players() from public, anon;
grant execute on function public.admin_players() to authenticated;

-- ================= ИИ ЧЕРЕЗ MCP =================
-- Ключи, которыми игрок подключает ИИ-помощника к функции mcp. В базе лежит только SHA-256
-- ключа; сам ключ игрок видит один раз — при создании. Создаёт ключ функция mcp_key_create,
-- игрок видит и отзывает только свои ключи
create table if not exists public.mcp_keys (
  id           bigint generated always as identity primary key,
  user_id      uuid not null references auth.users(id) on delete cascade,
  label        text not null default '' check (char_length(label) <= 40),
  key_hash     text not null unique,
  created_at   timestamptz not null default now(),
  last_used_at timestamptz
);
create index if not exists mcp_keys_user_idx on public.mcp_keys (user_id);
alter table public.mcp_keys enable row level security;
revoke all on public.mcp_keys from anon, authenticated;
drop policy if exists "mcp keys read own" on public.mcp_keys;
create policy "mcp keys read own" on public.mcp_keys
  for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists "mcp keys remove own" on public.mcp_keys;
create policy "mcp keys remove own" on public.mcp_keys
  for delete to authenticated using (user_id = (select auth.uid()));
grant select (id, user_id, label, created_at, last_used_at), delete on public.mcp_keys to authenticated;

create or replace function public.mcp_key_create(label text default '') returns text
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := (select auth.uid());
  k text;
begin
  if uid is null then
    raise exception 'нужно войти в аккаунт' using errcode = '42501';
  end if;
  if (select count(*) from public.mcp_keys where user_id = uid) >= 5 then
    raise exception 'не больше 5 ключей — отзови ненужный' using errcode = '23514';
  end if;
  k := 'dok_' || encode(extensions.gen_random_bytes(24), 'hex');
  insert into public.mcp_keys (user_id, label, key_hash)
    values (uid, left(regexp_replace(coalesce(label, ''), '[[:cntrl:]]', '', 'g'), 40), encode(extensions.digest(k, 'sha256'), 'hex'));
  return k;
end $$;
revoke execute on function public.mcp_key_create(text) from public, anon;
grant execute on function public.mcp_key_create(text) to authenticated;

-- Черновики уровней, которые ИИ сложил игроку через MCP. Пишет их только функция mcp
-- (ключом service_role); игрок видит свои в «Мои уровни», переносит в редактор или удаляет
create table if not exists public.level_drafts (
  id         bigint generated always as identity primary key,
  owner      uuid not null references auth.users(id) on delete cascade,
  name       text not null default '' check (char_length(name) <= 30 and name !~ '[[:cntrl:]]'),
  data       jsonb not null check (jsonb_typeof(data) = 'object' and pg_column_size(data) <= 12000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists level_drafts_owner_idx on public.level_drafts (owner);
alter table public.level_drafts enable row level security;
revoke all on public.level_drafts from anon, authenticated;
drop policy if exists "drafts read own" on public.level_drafts;
create policy "drafts read own" on public.level_drafts
  for select to authenticated using (owner = (select auth.uid()));
drop policy if exists "drafts remove own" on public.level_drafts;
create policy "drafts remove own" on public.level_drafts
  for delete to authenticated using (owner = (select auth.uid()));
grant select, delete on public.level_drafts to authenticated;

-- Защита прогресса, права и журнал регистраций (обновление 6.0) — в online/security-6.0.sql:
-- его выполняют после этого файла (скрипт setup-supabase.mjs делает это сам).
