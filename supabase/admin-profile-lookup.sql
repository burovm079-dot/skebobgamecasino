-- SKEBOB GAME: admin profile lookup and online presence
-- Run once in Supabase SQL Editor after admin-money.sql.

create table if not exists public.player_presence (
  user_id uuid primary key references auth.users(id) on delete cascade,
  last_seen timestamptz not null default now()
);

alter table public.player_presence enable row level security;
revoke all on public.player_presence from anon, authenticated;

create or replace function public.player_presence_ping()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Требуется авторизация';
  end if;
  insert into public.player_presence(user_id,last_seen)
  values(auth.uid(),now())
  on conflict(user_id) do update set last_seen=excluded.last_seen;
end;
$$;

revoke all on function public.player_presence_ping() from public;
grant execute on function public.player_presence_ping() to authenticated;

create or replace function public.admin_lookup_player(p_nickname text)
returns table(player_nickname text, player_balance numeric, is_online boolean, last_seen timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_id uuid;
  target_nickname text;
  target_balance numeric;
  seen_at timestamptz;
begin
  if auth.uid() is null or not exists (
    select 1 from public.game_admins a where a.user_id=auth.uid()
  ) then
    raise exception 'Нет доступа к проверке профилей';
  end if;

  if p_nickname is null or char_length(trim(p_nickname)) < 2 then
    raise exception 'Введи корректный nickname';
  end if;

  select p.user_id,p.nickname
    into target_id,target_nickname
  from public.player_profiles p
  where lower(trim(p.nickname))=lower(trim(p_nickname))
  limit 1;

  if target_id is null then
    raise exception 'Игрок с таким nickname не найден';
  end if;

  select coalesce((s.game_state->>'balance')::numeric,20)
    into target_balance
  from public.player_saves s
  where s.user_id=target_id;

  if target_balance is null then target_balance:=20; end if;

  select pp.last_seen into seen_at
  from public.player_presence pp
  where pp.user_id=target_id;

  return query select target_nickname,target_balance,
    (seen_at is not null and seen_at > now()-interval '90 seconds'),
    seen_at;
end;
$$;

revoke all on function public.admin_lookup_player(text) from public;
grant execute on function public.admin_lookup_player(text) to authenticated;
