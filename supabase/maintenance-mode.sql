-- SKEBOB GAME: global maintenance mode
-- Run this entire script in Supabase SQL Editor.
create table if not exists public.game_maintenance_settings (
 id integer primary key check (id = 1),
 enabled boolean not null default false,
 updated_at timestamptz not null default now()
);
insert into public.game_maintenance_settings (id,enabled) values (1,false) on conflict (id) do nothing;
alter table public.game_maintenance_settings enable row level security;
revoke all on public.game_maintenance_settings from public,anon,authenticated;
create or replace function public.get_game_maintenance_mode()
returns boolean language sql stable security definer set search_path = ''
as $$ select coalesce((select s.enabled from public.game_maintenance_settings s where s.id=1),false); $$;
create or replace function public.admin_set_game_maintenance_mode(p_enabled boolean)
returns boolean language plpgsql security definer set search_path = ''
as $$
begin
 if auth.uid() is null or not exists(select 1 from public.game_admins a where a.user_id=auth.uid()) then raise exception 'Недостаточно прав.'; end if;
 insert into public.game_maintenance_settings(id,enabled,updated_at) values(1,coalesce(p_enabled,false),now())
 on conflict(id) do update set enabled=excluded.enabled,updated_at=now();
 return coalesce(p_enabled,false);
end;
$$;
revoke all on function public.get_game_maintenance_mode() from public;
revoke all on function public.admin_set_game_maintenance_mode(boolean) from public,anon;
grant execute on function public.get_game_maintenance_mode() to anon,authenticated;
grant execute on function public.admin_set_game_maintenance_mode(boolean) to authenticated;
notify pgrst,'reload schema';
