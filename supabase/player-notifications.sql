-- SKEBOB GAME: private player notifications
-- Run this whole script in Supabase SQL Editor.

create table if not exists public.player_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  message text not null check (char_length(message) between 1 and 1000),
  created_at timestamptz not null default now(),
  seen_at timestamptz
);

create index if not exists player_notifications_user_pending_idx
  on public.player_notifications (user_id, created_at)
  where seen_at is null;

alter table public.player_notifications enable row level security;
revoke all on public.player_notifications from public, anon, authenticated;

create or replace function public.admin_send_player_notification(p_nickname text, p_message text)
returns table(notification_id uuid, recipient_nickname text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_user_id uuid;
  target_nickname text;
  clean_message text := trim(coalesce(p_message, ''));
begin
  if auth.uid() is null or not exists (
    select 1 from public.game_admins a where a.user_id = auth.uid()
  ) then
    raise exception 'Недостаточно прав.';
  end if;
  if clean_message = '' or char_length(clean_message) > 1000 then
    raise exception 'Сообщение должно содержать от 1 до 1000 символов.';
  end if;

  select u.id, coalesce(nullif(trim(p.nickname), ''), nullif(trim(u.raw_user_meta_data ->> 'nickname'), ''), 'Игрок')
    into target_user_id, target_nickname
  from auth.users u
  left join public.player_profiles p on p.user_id = u.id
  where lower(coalesce(nullif(trim(p.nickname), ''), nullif(trim(u.raw_user_meta_data ->> 'nickname'), ''), 'Игрок')) = lower(trim(coalesce(p_nickname, '')))
  limit 1;

  if target_user_id is null then
    raise exception 'Игрок с таким ником не найден.';
  end if;

  insert into public.player_notifications(user_id, message)
  values (target_user_id, clean_message)
  returning id into notification_id;
  recipient_nickname := target_nickname;
  return next;
end;
$$;

create or replace function public.get_my_player_notifications()
returns table(id uuid, message text, created_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Необходимо войти в аккаунт.';
  end if;

  return query
  update public.player_notifications n
  set seen_at = now()
  where n.user_id = auth.uid() and n.seen_at is null
  returning n.id, n.message, n.created_at;
end;
$$;

revoke all on function public.admin_send_player_notification(text, text) from public, anon;
revoke all on function public.get_my_player_notifications() from public, anon;
grant execute on function public.admin_send_player_notification(text, text) to authenticated;
grant execute on function public.get_my_player_notifications() to authenticated;

notify pgrst, 'reload schema';

-- SKEBOB GAME: global announcements delivered once to every account existing at publish time.
create table if not exists public.global_announcements (
  id uuid primary key default gen_random_uuid(),
  message text not null check (char_length(message) between 1 and 1000),
  created_at timestamptz not null default now()
);

create table if not exists public.global_announcement_deliveries (
  announcement_id uuid not null references public.global_announcements(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  seen_at timestamptz,
  primary key (announcement_id, user_id)
);

create index if not exists global_announcement_deliveries_pending_idx
  on public.global_announcement_deliveries (user_id, announcement_id)
  where seen_at is null;

alter table public.global_announcements enable row level security;
alter table public.global_announcement_deliveries enable row level security;
revoke all on public.global_announcements, public.global_announcement_deliveries from public, anon, authenticated;

create or replace function public.admin_publish_global_announcement(p_message text)
returns table(announcement_id uuid, recipients_count integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_announcement_id uuid;
  clean_message text := trim(coalesce(p_message, ''));
  inserted_count integer;
begin
  if auth.uid() is null or not exists (
    select 1 from public.game_admins a where a.user_id = auth.uid()
  ) then
    raise exception 'Недостаточно прав.';
  end if;
  if clean_message = '' or char_length(clean_message) > 1000 then
    raise exception 'Объявление должно содержать от 1 до 1000 символов.';
  end if;

  insert into public.global_announcements(message)
  values (clean_message)
  returning id into new_announcement_id;

  insert into public.global_announcement_deliveries(announcement_id, user_id)
  select new_announcement_id, u.id
  from auth.users u;

  get diagnostics inserted_count = row_count;
  announcement_id := new_announcement_id;
  recipients_count := inserted_count;
  return next;
end;
$$;

create or replace function public.get_my_global_announcements()
returns table(id uuid, message text, created_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Необходимо войти в аккаунт.';
  end if;

  return query
  update public.global_announcement_deliveries d
  set seen_at = now()
  from public.global_announcements a
  where d.announcement_id = a.id
    and d.user_id = auth.uid()
    and d.seen_at is null
  returning a.id, a.message, a.created_at;
end;
$$;

revoke all on function public.admin_publish_global_announcement(text) from public, anon;
revoke all on function public.get_my_global_announcements() from public, anon;
grant execute on function public.admin_publish_global_announcement(text) to authenticated;
grant execute on function public.get_my_global_announcements() to authenticated;

notify pgrst, 'reload schema';

