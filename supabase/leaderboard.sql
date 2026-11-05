-- SKEBOB GAME: общий топ-20 игроков по балансу.
-- Выполнить один раз в Supabase Dashboard -> SQL Editor -> New query.

create or replace function public.get_player_leaderboard()
returns table (
  player_rank bigint,
  player_nickname text,
  player_balance numeric
)
language sql
stable
security definer
set search_path = ''
as $$
  with balances as (
    select
      p.nickname,
      greatest(
        0::numeric,
        case
          when coalesce(s.game_state ->> 'balance', '') ~ '^-?[0-9]+([.][0-9]+)?$'
            then (s.game_state ->> 'balance')::numeric
          else 20::numeric
        end
      ) as balance
    from public.player_profiles p
    left join public.player_saves s on s.user_id = p.user_id
  ),
  ranked as (
    select
      row_number() over (order by b.balance desc, lower(b.nickname) asc) as place,
      b.nickname,
      b.balance
    from balances b
  )
  select r.place, r.nickname, r.balance
  from ranked r
  order by r.place
  limit 20;
$$;

revoke all on function public.get_player_leaderboard() from public;
revoke all on function public.get_player_leaderboard() from anon;
grant execute on function public.get_player_leaderboard() to authenticated;
