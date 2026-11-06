-- SKEBOB GAME: рейтинг игроков по количеству побед
-- Выполнить весь файл один раз в Supabase SQL Editor.
-- Счётчик totalWins начинает накапливаться после установки обновления игры.

create or replace function public.get_top_winners()
returns table (
  player_rank bigint,
  player_nickname text,
  total_wins bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.player_profiles p
    where p.user_id = auth.uid()
      and lower(trim(p.nickname)) = 'skebob'
  ) then
    raise exception 'Admin access required';
  end if;

  return query
  with players as (
    select
      coalesce(
        nullif(trim(p.nickname), ''),
        nullif(trim(u.raw_user_meta_data ->> 'nickname'), ''),
        'Игрок'
      ) as nickname,
      case
        when coalesce(s.game_state #>> '{stats,totalWins}', '') ~ '^[0-9]+$'
          then (s.game_state #>> '{stats,totalWins}')::bigint
        else 0::bigint
      end as wins
    from auth.users u
    left join public.player_profiles p on p.user_id = u.id
    left join public.player_saves s on s.user_id = u.id
  ),
  ranked as (
    select
      row_number() over (order by wins desc, lower(nickname) asc) as place,
      nickname,
      wins
    from players
    where wins > 0
  )
  select r.place, r.nickname, r.wins
  from ranked r
  order by r.place
  limit 50;
end;
$$;

revoke all on function public.get_top_winners() from public, anon;
grant execute on function public.get_top_winners() to authenticated;
notify pgrst, 'reload schema';
