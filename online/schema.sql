-- Таблица прогресса и рекордов DATA.OUT.
-- Выполни один раз в Supabase: SQL Editor → New query → вставь этот файл → Run.

create table if not exists public.progress (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  name       text not null default 'Игрок' check (char_length(name) between 1 and 20),
  unlocked   int  not null default 1 check (unlocked between 1 and 21),
  best       int  not null default 0 check (best between 0 and 1000000),
  wins       int  not null default 0 check (wins between 0 and 100000),
  color      int  not null default 0 check (color between 0 and 3),
  shape      int  not null default 0 check (shape between 0 and 2),
  updated_at timestamptz not null default now()
);

-- время последнего сохранения ставит сама база
create or replace function public.progress_touch() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
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
