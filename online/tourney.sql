-- ТУРНИР НЕДЕЛИ (раздел «Ивенты» в игре). Можно запускать повторно.
-- Каждую субботу с 11:00 до 21:00 по Москве все проходят один уровень; в таблице — лучшее время
-- каждого игрока за неделю. Записать результат можно только в эти часы и только за текущую неделю —
-- это проверяет база по своим часам, поэтому перевод часов на телефоне не поможет. Лучшее время не
-- ухудшается. Читать таблицу может любой, убрать подозрительный результат — администратор игры.
create table if not exists public.tourney(
  week    text not null,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name    text not null default '',
  ms      integer not null,
  at      timestamptz not null default now(),
  primary key (week, user_id),
  constraint tourney_week_check check (week ~ '^[0-9]{4}-W[0-9]{2}$'),
  constraint tourney_name_check check (char_length(name) <= 20 and name !~ '[[:cntrl:]<>]'),
  constraint tourney_ms_check check (ms between 5000 and 3600000)
);
create index if not exists tourney_week_ms on public.tourney(week, ms, at);
alter table public.tourney enable row level security;
revoke all on public.tourney from anon, authenticated;
grant select on public.tourney to anon, authenticated;
grant insert (week, name, ms) on public.tourney to authenticated;
grant update (week, name, ms) on public.tourney to authenticated;
grant delete on public.tourney to authenticated;
drop policy if exists tourney_read on public.tourney;
create policy tourney_read on public.tourney for select using (true);
drop policy if exists tourney_ins on public.tourney;
create policy tourney_ins on public.tourney for insert to authenticated with check (user_id = (select auth.uid()));
drop policy if exists tourney_upd on public.tourney;
create policy tourney_upd on public.tourney for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
drop policy if exists tourney_del on public.tourney;
create policy tourney_del on public.tourney for delete to authenticated using ((select public.is_admin()));

-- суббота 11:00–21:00 по Москве, текущая ISO-неделя (как weekKey в игре), лучший результат не ухудшается
create or replace function public.tourney_guard() returns trigger
language plpgsql set search_path = public, pg_temp as $$
declare msk timestamp := now() at time zone 'Europe/Moscow';
begin
  if extract(isodow from msk) <> 6 or extract(hour from msk) < 11 or extract(hour from msk) >= 21 then
    raise exception 'турнир сейчас закрыт' using errcode = 'P0001';
  end if;
  if new.week <> to_char(msk, 'IYYY-"W"IW') then
    raise exception 'не та неделя турнира' using errcode = 'P0001';
  end if;
  if tg_op = 'UPDATE' then
    new.week := old.week; new.user_id := old.user_id;
    if new.ms >= old.ms then new.ms := old.ms; new.at := old.at; else new.at := now(); end if;
  else
    new.user_id := auth.uid(); new.at := now();
  end if;
  return new;
end $$;
drop trigger if exists tourney_guard on public.tourney;
create trigger tourney_guard before insert or update on public.tourney
  for each row execute function public.tourney_guard();
