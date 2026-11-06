-- SKEBOB GAME: safely reset a player's saved game progress by nickname.
-- Run this complete script in the Supabase SQL Editor.

create or replace function public.admin_reset_player_progress(p_nickname text)
returns table(player_nickname text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_user_id uuid;
  target_nickname text;
  fresh_game_state jsonb;
begin
  if auth.uid() is null or not exists (
    select 1 from public.game_admins a where a.user_id = auth.uid()
  ) then
    raise exception 'Недостаточно прав.';
  end if;

  if trim(coalesce(p_nickname, '')) = '' then
    raise exception 'Введи никнейм игрока.';
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
                       'Игрок')) = lower(trim(p_nickname))
  limit 1;

  if target_user_id is null then
    raise exception 'Игрок с таким ником не найден.';
  end if;

  if exists (select 1 from public.game_admins a where a.user_id = target_user_id) then
    raise exception 'Нельзя сбросить прогресс аккаунта администратора.';
  end if;

  fresh_game_state := jsonb_build_object(
    'balance', 20,
    'tapGame', jsonb_build_object(
      'hourStartedAt', 0,
      'earnedCents', 0,
      'pendingCents', 0,
      'cooldownUntil', 0
    ),
    'inventory', '[]'::jsonb,
    'stats', jsonb_build_object(
      'totalWon', 0,
      'bestWin', 0,
      'itemsSold', 0,
      'soldValue', 0,
      'casesOpened', 0,
      'upgrades', 0,
      'upgradeWins', 0,
      'minesGames', 0,
      'minesWins', 0,
      'planeGames', 0,
      'planeWins', 0,
      'plinkoGames', 0,
      'plinkoWins', 0,
      'raceGames', 0,
      'raceWins', 0,
      'turnover', 0
    ),
    'createdAt', floor(extract(epoch from clock_timestamp()) * 1000)::bigint,
    'profileStyle', jsonb_build_object(
      'frame', 'classic',
      'background', 'default',
      'accent', 'gold',
      'collapsed', false
    )
  );

  insert into public.player_saves(user_id, game_state)
  values (target_user_id, fresh_game_state)
  on conflict (user_id) do update
    set game_state = excluded.game_state;

  player_nickname := target_nickname;
  return next;
end;
$$;

revoke all on function public.admin_reset_player_progress(text) from public, anon;
grant execute on function public.admin_reset_player_progress(text) to authenticated;

notify pgrst, 'reload schema';
