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

-- границы значений: 100 уровней, до 50 предметов в каждом разделе облика
alter table public.progress drop constraint if exists progress_unlocked_check;
alter table public.progress add constraint progress_unlocked_check check (unlocked between 1 and 100);
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

-- время последнего сохранения и время принятия новой редакции соглашения ставит сама база
create or replace function public.progress_touch() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  if new.terms <> '' and (tg_op = 'INSERT' or new.terms is distinct from old.terms) then
    new.terms_at := now();
  elsif tg_op = 'UPDATE' then
    new.terms_at := old.terms_at;
  end if;
  return new;
end $$;
drop trigger if exists progress_touch on public.progress;
create trigger progress_touch before insert or update on public.progress
  for each row execute function public.progress_touch();

-- Таблицу рекордов видят все (в ней только имя, выбранное игроком, и числа),
-- а записать и поменять свою строку может только сам игрок.
alter table public.progress enable row level security;

drop policy if exists "progress read" on public.progress;
create policy "progress read" on public.progress
  for select using (true);

drop policy if exists "progress insert own" on public.progress;
create policy "progress insert own" on public.progress
  for insert to authenticated with check ((select auth.uid()) = user_id);

drop policy if exists "progress update own" on public.progress;
create policy "progress update own" on public.progress
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

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
alter table public.donations enable row level security;
revoke all on public.donations from anon, authenticated;

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
