-- SKEBOB GAME: popular mini-games statistics
-- Run this entire script in Supabase SQL Editor.
create table if not exists public.game_launch_events (
 id bigserial primary key,
 user_id uuid not null references auth.users(id) on delete cascade,
 game_id text not null check (game_id in (
  'skebobTap','tictactoe','billiards','cases','secretDrop','battles',
  'upgrade','mines','plane','plinko','race','slots','dice'
 )),
 created_at timestamptz not null default now()
);

create index if not exists game_launch_events_game_created_idx
 on public.game_launch_events(game_id, created_at desc);
create index if not exists game_launch_events_user_idx
 on public.game_launch_events(user_id);

alter table public.game_launch_events enable row level security;
revoke all on public.game_launch_events from anon, authenticated, public;

create or replace function public.track_game_launch(p_game_id text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
 if auth.uid() is null then
  raise exception 'Authentication required';
 end if;
 if p_game_id not in (
  'skebobTap','tictactoe','billiards','cases','secretDrop','battles',
  'upgrade','mines','plane','plinko','race','slots','dice'
 ) then
  raise exception 'Unknown game';
 end if;
 insert into public.game_launch_events(user_id, game_id)
 values (auth.uid(), p_game_id);
end;
$$;

create or replace function public.get_popular_games()
returns table(game_id text, launch_count bigint, unique_players bigint)
language plpgsql
security definer
set search_path = ''
as $$
begin
 if not exists (
  select 1 from public.player_profiles p
  where p.user_id = auth.uid()
    and lower(trim(p.nickname)) = 'skebob'
 ) then
  raise exception 'Admin access required';
 end if;
 return query
 select e.game_id, count(*)::bigint, count(distinct e.user_id)::bigint
 from public.game_launch_events e
 group by e.game_id
 order by count(*) desc, e.game_id asc;
end;
$$;

revoke all on function public.track_game_launch(text) from public, anon;
revoke all on function public.get_popular_games() from public, anon;
grant execute on function public.track_game_launch(text) to authenticated;
grant execute on function public.get_popular_games() to authenticated;
