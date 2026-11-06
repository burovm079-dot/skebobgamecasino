-- SKEBOB GAME: secure account directory for SKEBOB admin profile
-- Run this whole script in Supabase SQL Editor.

create or replace function public.admin_get_all_player_accounts()
returns table(nickname text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.game_admins a
    where a.user_id = auth.uid()
  ) then
    raise exception 'Недостаточно прав.';
  end if;

  return query
  select coalesce(
    nullif(trim(p.nickname), ''),
    nullif(trim(u.raw_user_meta_data ->> 'nickname'), ''),
    'Игрок'
  )::text as nickname
  from auth.users u
  left join public.player_profiles p on p.user_id = u.id
  order by lower(coalesce(
    nullif(trim(p.nickname), ''),
    nullif(trim(u.raw_user_meta_data ->> 'nickname'), ''),
    'Игрок'
  ));
end;
$$;

revoke all on function public.admin_get_all_player_accounts() from public, anon;
grant execute on function public.admin_get_all_player_accounts() to authenticated;

notify pgrst, 'reload schema';
