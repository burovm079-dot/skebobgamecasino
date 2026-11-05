-- SKEBOB GAME: badges + global top-20 leaderboard
-- Run the entire file in Supabase SQL Editor.

create table if not exists public.player_badges (
  user_id uuid primary key references public.player_profiles(user_id) on delete cascade,
  badge_type text not null check (badge_type in ('green','blue','gold')),
  updated_at timestamptz not null default now()
);

alter table public.player_badges enable row level security;
revoke all on public.player_badges from anon, authenticated;

drop function if exists public.get_player_leaderboard();
create function public.get_player_leaderboard()
returns table (
  player_rank bigint,
  player_nickname text,
  player_balance numeric,
  player_badge text
)
language sql
stable
security definer
set search_path = ''
as $$
  with balances as (
    select
      u.id as user_id,
      coalesce(
        nullif(trim(p.nickname), ''),
        nullif(trim(u.raw_user_meta_data ->> 'nickname'), ''),
        'Игрок'
      ) as nickname,
      greatest(
        0::numeric,
        case
          when coalesce(s.game_state ->> 'balance', '') ~ '^-?[0-9]+([.][0-9]+)?$'
            then (s.game_state ->> 'balance')::numeric
          else 20::numeric
        end
      ) as balance,
      b.badge_type
    from auth.users u
    left join public.player_profiles p on p.user_id = u.id
    left join public.player_saves s on s.user_id = u.id
    left join public.player_badges b on b.user_id = u.id
  ),
  ranked as (
    select
      row_number() over (order by balance desc, lower(nickname) asc) as place,
      nickname,
      balance,
      badge_type
    from balances
  )
  select r.place, r.nickname, r.balance, r.badge_type
  from ranked r
  order by r.place
  limit 20;
$$;

create or replace function public.get_my_player_badge()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select b.badge_type
  from public.player_badges b
  where b.user_id = auth.uid();
$$;

create or replace function public.admin_set_player_badge(p_nickname text, p_badge text)
returns table(player_nickname text, badge_type text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_id uuid;
  target_nickname text;
begin
  if not exists (
    select 1 from public.game_admins a where a.user_id = auth.uid()
  ) then
    raise exception 'Недостаточно прав.';
  end if;

  if p_badge not in ('green', 'blue', 'gold') then
    raise exception 'Неизвестный тип галочки.';
  end if;

  select p.user_id, p.nickname
    into target_id, target_nickname
  from public.player_profiles p
  where lower(trim(p.nickname)) = lower(trim(p_nickname))
  limit 1;

  if target_id is null then
    raise exception 'Игрок с таким nickname не найден.';
  end if;

  insert into public.player_badges(user_id, badge_type, updated_at)
  values (target_id, p_badge, now())
  on conflict (user_id) do update
    set badge_type = excluded.badge_type,
        updated_at = now();

  return query select target_nickname, p_badge;
end;
$$;

create or replace function public.admin_remove_player_badge(p_nickname text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_id uuid;
  target_nickname text;
begin
  if not exists (
    select 1 from public.game_admins a where a.user_id = auth.uid()
  ) then
    raise exception 'Недостаточно прав.';
  end if;

  select p.user_id, p.nickname
    into target_id, target_nickname
  from public.player_profiles p
  where lower(trim(p.nickname)) = lower(trim(p_nickname))
  limit 1;

  if target_id is null then
    raise exception 'Игрок с таким nickname не найден.';
  end if;

  delete from public.player_badges where user_id = target_id;
  return target_nickname;
end;
$$;

revoke all on function public.get_player_leaderboard() from public, anon;
revoke all on function public.get_my_player_badge() from public, anon;
revoke all on function public.admin_set_player_badge(text, text) from public, anon;
revoke all on function public.admin_remove_player_badge(text) from public, anon;

grant execute on function public.get_player_leaderboard() to authenticated;
grant execute on function public.get_my_player_badge() to authenticated;
grant execute on function public.admin_set_player_badge(text, text) to authenticated;
grant execute on function public.admin_remove_player_badge(text) to authenticated;

notify pgrst, 'reload schema';
