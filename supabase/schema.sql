-- SKEBOB GAME: базовая схема аккаунтов и сохранений
-- Выполнить целиком в Supabase Dashboard -> SQL Editor -> New query.

create table if not exists public.player_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  nickname text not null,
  nickname_normalized text generated always as (lower(trim(nickname))) stored,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint player_profiles_nickname_length check (char_length(trim(nickname)) between 2 and 18)
);

create unique index if not exists player_profiles_nickname_unique
  on public.player_profiles (nickname_normalized);

create table if not exists public.player_saves (
  user_id uuid primary key references auth.users(id) on delete cascade,
  game_state jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.player_profiles enable row level security;
alter table public.player_saves enable row level security;

drop policy if exists "Players can read their own profile" on public.player_profiles;
create policy "Players can read their own profile"
  on public.player_profiles for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Players can create their own profile" on public.player_profiles;
create policy "Players can create their own profile"
  on public.player_profiles for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "Players can update their own profile" on public.player_profiles;
create policy "Players can update their own profile"
  on public.player_profiles for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Players can read their own save" on public.player_saves;
create policy "Players can read their own save"
  on public.player_saves for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Players can create their own save" on public.player_saves;
create policy "Players can create their own save"
  on public.player_saves for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "Players can update their own save" on public.player_saves;
create policy "Players can update their own save"
  on public.player_saves for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists player_profiles_updated_at on public.player_profiles;
create trigger player_profiles_updated_at
before update on public.player_profiles
for each row execute function public.set_updated_at();

drop trigger if exists player_saves_updated_at on public.player_saves;
create trigger player_saves_updated_at
before update on public.player_saves
for each row execute function public.set_updated_at();

-- Профиль создаётся при регистрации пользователя в Supabase Auth.
create or replace function public.create_player_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  chosen_nickname text;
begin
  chosen_nickname := trim(coalesce(new.raw_user_meta_data ->> 'nickname', ''));
  if char_length(chosen_nickname) < 2 or char_length(chosen_nickname) > 18 then
    raise exception 'Nickname must contain 2 to 18 characters';
  end if;

  insert into public.player_profiles (user_id, nickname)
  values (new.id, chosen_nickname);

  insert into public.player_saves (user_id, game_state)
  values (new.id, '{}'::jsonb);

  return new;
end;
$$;

drop trigger if exists on_auth_user_created_player on auth.users;
create trigger on_auth_user_created_player
after insert on auth.users
for each row execute function public.create_player_profile();

-- ВАЖНО: клиентское сохранение JSON под RLS защищает данные от других игроков,
-- но не делает баланс/награды неподделываемыми самим владельцем аккаунта.
-- Для честной экономики игровые операции далее переносим в серверные RPC.
