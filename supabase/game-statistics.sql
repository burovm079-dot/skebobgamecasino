-- SKEBOB GAME: admin game statistics
-- Run this entire script in Supabase SQL Editor.
-- Counts registered accounts, players seen in the last 24 hours,
-- and recorded game launches (all time / last 24 hours).

create or replace function public.admin_get_game_statistics()
returns table(
 total_registered bigint,
 active_last_24h bigint,
 launches_all_time bigint,
 launches_last_24h bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
 if auth.uid() is null or not exists (
  select 1 from public.game_admins a where a.user_id = auth.uid()
 ) then
  raise exception 'Недостаточно прав.';
 end if;

 return query
 select
  (select count(*)::bigint from auth.users),
  (select count(*)::bigint from public.player_presence p
   where p.last_seen >= now() - interval '24 hours'),
  (select count(*)::bigint from public.game_launch_events e),
  (select count(*)::bigint from public.game_launch_events e
   where e.created_at >= now() - interval '24 hours');
end;
$$;

revoke all on function public.admin_get_game_statistics() from public, anon;
grant execute on function public.admin_get_game_statistics() to authenticated;

notify pgrst, 'reload schema';
