-- DATA.OUT — инструменты администратора: открытые уровни и биты игрока. Файл можно запускать повторно.
-- Выполнить в Supabase: SQL Editor → New query → вставить файл → Run (после schema.sql).
--
-- Игра сливает прогресс из аккаунта с прогрессом устройства «по максимуму», поэтому просто записать
-- игроку меньше уровней нельзя: его игра пришлёт прежнее число обратно. Поэтому правки администратора
-- хранятся отдельно, и игра игрока сама применяет их:
--   adm_lv / adm_rev — уровень, выставленный администратором, и номер этой правки;
--   adm_ack          — номер правки, которую игра игрока уже применила (пишет игра);
--   adm_bits         — сколько бит всего выдали (+) или списали (−) администраторы; баланс игрока —
--                      заработанное + adm_bits − цены купленного. Заработанное (earned) админ не трогает,
--                      поэтому выданные биты не теряются и не удваиваются при слиянии устройств.
-- Пока игра не применила последнюю правку уровней (adm_ack < adm_rev), её запись уровней не принимается —
-- так старая вкладка или старая версия игры не вернёт игроку снятые уровни.
-- Менять эти поля может только функция admin_adjust (её вызывает админ-панель игры).

alter table public.progress add column if not exists adm_rev  int not null default 0;
alter table public.progress add column if not exists adm_lv   int not null default 0;
alter table public.progress add column if not exists adm_ack  int not null default 0;
alter table public.progress add column if not exists adm_bits int not null default 0;
alter table public.progress drop constraint if exists progress_adm_bits_check;
alter table public.progress add constraint progress_adm_bits_check check (adm_bits between -100000000 and 100000000);

-- Игра сохраняет прогресс «upsert»-ом (INSERT … ON CONFLICT DO UPDATE). При нём Postgres сначала
-- вызывает триггер BEFORE INSERT для предлагаемой строки и только потом, при конфликте, BEFORE UPDATE,
-- причём изменения первого попадают в EXCLUDED. Поэтому для уже существующей строки ветка INSERT
-- ничего не меняет: проверка — в ветке UPDATE, где видна старая строка.
create or replace function public.progress_admin() returns trigger
language plpgsql set search_path = '' as $fn$
begin
  -- сервер, владелец проекта и функция admin_adjust (security definer) не проверяются
  if current_user not in ('anon', 'authenticated') then return new; end if;
  if tg_op = 'INSERT' then
    if exists (select 1 from public.progress p where p.user_id = new.user_id) then return new; end if;
    new.adm_rev := 0; new.adm_lv := 0; new.adm_ack := 0; new.adm_bits := 0;
    return new;
  end if;
  new.adm_rev := old.adm_rev; new.adm_lv := old.adm_lv; new.adm_bits := old.adm_bits;
  new.adm_ack := least(greatest(new.adm_ack, 0), old.adm_rev);
  if new.adm_ack < old.adm_rev then new.unlocked := old.unlocked; end if;
  return new;
end $fn$;
revoke execute on function public.progress_admin() from public;
drop trigger if exists progress_admin on public.progress;
create trigger progress_admin before insert or update on public.progress
  for each row execute function public.progress_admin();

-- Правка администратора: выставить открытые уровни (1…500) и/или выдать (+) либо списать (−) биты.
create or replace function public.admin_adjust(target uuid, set_level int default null, add_bits int default 0)
returns void
language plpgsql security definer set search_path = '' as $fn$
begin
  if not public.is_admin() then
    raise exception 'нет доступа' using errcode = '42501';
  end if;
  if set_level is not null and (set_level < 1 or set_level > 500) then
    raise exception 'уровень — от 1 до 500' using errcode = '22023';
  end if;
  if add_bits is null or abs(add_bits) > 10000000 then
    raise exception 'биты — не больше 10 000 000 за раз' using errcode = '22023';
  end if;
  update public.progress p set
    unlocked = coalesce(set_level, p.unlocked),
    adm_lv   = coalesce(set_level, p.adm_lv),
    adm_rev  = p.adm_rev + case when set_level is null then 0 else 1 end,
    adm_bits = least(100000000, greatest(-100000000, p.adm_bits + add_bits))
  where p.user_id = target;
  if not found then
    raise exception 'у игрока ещё нет прогресса' using errcode = 'P0002';
  end if;
end $fn$;
revoke execute on function public.admin_adjust(uuid, int, int) from public, anon;
grant execute on function public.admin_adjust(uuid, int, int) to authenticated;

-- Список игроков для админ-панели — теперь и с битами (заработано, куплено, выдано админом).
-- Набор столбцов поменялся, поэтому функцию нужно пересоздать.
drop function if exists public.admin_players();
create function public.admin_players()
returns table (user_id uuid, login text, provider text, created_at timestamptz, last_sign_in_at timestamptz,
  name text, bio text, unlocked int, best int, wins int, hidden boolean, supporter boolean, levels int,
  earned int, own text, adm_bits int)
language plpgsql stable security definer set search_path = '' as $fn$
begin
  if not public.is_admin() then
    raise exception 'нет доступа' using errcode = '42501';
  end if;
  return query
    select u.id, coalesce(u.raw_user_meta_data->>'name', ''), coalesce(u.raw_user_meta_data->>'provider', ''),
      u.created_at, u.last_sign_in_at, p.name, p.bio, p.unlocked, p.best, p.wins, coalesce(p.hidden, false),
      exists (select 1 from public.supporters s where s.user_id = u.id),
      (select count(*)::int from public.levels l where l.author = u.id),
      p.earned, p.own, p.adm_bits
    from auth.users u left join public.progress p on p.user_id = u.id
    order by u.created_at desc
    limit 1000;
end $fn$;
revoke execute on function public.admin_players() from public, anon;
grant execute on function public.admin_players() to authenticated;
