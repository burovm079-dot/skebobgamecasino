-- SKEBOB GAME: timed player bans
-- Run this entire script in Supabase SQL Editor.

create table if not exists public.player_bans (
  user_id uuid primary key references auth.users(id) on delete cascade,
  nickname text not null,
  banned_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null
);

create index if not exists player_bans_expires_at_idx
  on public.player_bans (expires_at);

alter table public.player_bans enable row level security;
revoke all on public.player_bans from public, anon, authenticated;

create or replace function public.admin_ban_player(
  p_nickname text,
  p_months integer,
  p_days integer
)
returns table(player_nickname text, expires_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_user_id uuid;
  target_nickname text;
  ban_until timestamptz;
begin
  if auth.uid() is null or not exists (
    select 1 from public.game_admins a where a.user_id = auth.uid()
  ) then
    raise exception 'Недостаточно прав.';
  end if;

  if p_months is null or p_days is null
     or p_months < 0 or p_months > 120
     or p_days < 0 or p_days > 3650
     or (p_months = 0 and p_days = 0) then
    raise exception 'Укажи корректный срок блокировки.';
  end if;

  select u.id,
         coalesce(nullif(trim(p.nickname), ''),
                  nullif(trim(u.raw_user_meta_data ->> 'nickname'), ''),
                  'Игрок')
    into target_user_id, target_nickname
  from auth.users u
  left join public.player_profiles p on p.user_id = u.id
  where lower(coalesce(nullif(trim(p.nickname), ''),
                       nullif(trim(u.raw_user_meta_data ->> 'nickname'), ''),
                       'Игрок')) = lower(trim(coalesce(p_nickname, '')))
  limit 1;

  if target_user_id is null then
    raise exception 'Игрок с таким ником не найден.';
  end if;

  if exists (select 1 from public.game_admins a where a.user_id = target_user_id) then
    raise exception 'Нельзя заблокировать аккаунт администратора.';
  end if;

  ban_until := now() + make_interval(months => p_months, days => p_days);

  insert into public.player_bans(user_id, nickname, banned_by, expires_at)
  values (target_user_id, target_nickname, auth.uid(), ban_until)
  on conflict (user_id) do update
    set nickname = excluded.nickname,
        banned_by = excluded.banned_by,
        created_at = now(),
        expires_at = excluded.expires_at;

  player_nickname := target_nickname;
  expires_at := ban_until;
  return next;
end;
$$;

create or replace function public.get_my_player_ban_status()
returns table(is_banned boolean, expires_at timestamptz)
language sql
security definer
set search_path = ''
as $$
  select true, b.expires_at
  from public.player_bans b
  where b.user_id = auth.uid()
    and b.expires_at > now()
  limit 1;
$$;

revoke all on function public.admin_ban_player(text, integer, integer) from public, anon;
revoke all on function public.get_my_player_ban_status() from public, anon;
grant execute on function public.admin_ban_player(text, integer, integer) to authenticated;
grant execute on function public.get_my_player_ban_status() to authenticated;

notify pgrst, 'reload schema';

 
-- Администраторская разблокировка игрока по никнейму.
create or replace function public.admin_unban_player(p_nickname text)
returns table(player_nickname text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_user_id uuid;
  target_nickname text;
begin
  if auth.uid() is null or not exists (
    select 1 from public.game_admins a where a.user_id = auth.uid()
  ) then
    raise exception 'Недостаточно прав.';
  end if;

  select u.id,
         coalesce(nullif(trim(p.nickname), ''),
                  nullif(trim(u.raw_user_meta_data ->> 'nickname'), ''),
                  'Игрок')
    into target_user_id, target_nickname
  from auth.users u
  left join public.player_profiles p on p.user_id = u.id
  where lower(coalesce(nullif(trim(p.nickname), ''),
                       nullif(trim(u.raw_user_meta_data ->> 'nickname'), ''),
                       'Игрок')) = lower(trim(coalesce(p_nickname, '')))
  limit 1;

  if target_user_id is null then
    raise exception 'Игрок с таким ником не найден.';
  end if;

  delete from public.player_bans b
  where b.user_id = target_user_id;

  if not found then
    raise exception 'У этого игрока нет активной блокировки.';
  end if;

  player_nickname := target_nickname;
  return next;
end;
$$;

revoke all on function public.admin_unban_player(text) from public, anon;
grant execute on function public.admin_unban_player(text) to authenticated;

notify pgrst, 'reload schema';
