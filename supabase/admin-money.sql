-- SKEBOB GAME: защищённая выдача рублей игрокам
-- Выполнить в Supabase SQL Editor после регистрации аккаунта SKEBOB.

create table if not exists public.game_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.game_admins enable row level security;
revoke all on public.game_admins from anon, authenticated;

-- Администратором назначается именно Supabase-аккаунт с ником SKEBOB.
insert into public.game_admins (user_id)
select user_id
from public.player_profiles
where lower(trim(nickname)) = 'skebob'
on conflict (user_id) do nothing;

create or replace function public.admin_grant_player_money(
  p_nickname text,
  p_amount numeric
)
returns table(player_nickname text, new_balance numeric)
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_id uuid;
  target_nickname text;
  current_balance numeric;
begin
  if auth.uid() is null or not exists (
    select 1 from public.game_admins a where a.user_id = auth.uid()
  ) then
    raise exception 'Нет доступа к выдаче денег';
  end if;

  if p_amount is null or p_amount <= 0 or p_amount > 1000000000 or p_amount <> round(p_amount, 2) then
    raise exception 'Укажи сумму от 0.01 до 1 000 000 000 рублей';
  end if;

  select p.user_id, p.nickname
    into target_id, target_nickname
  from public.player_profiles p
  where lower(trim(p.nickname)) = lower(trim(p_nickname))
  limit 1;

  if target_id is null then
    raise exception 'Игрок с таким никнеймом не найден';
  end if;

  select coalesce((s.game_state ->> 'balance')::numeric, 20)
    into current_balance
  from public.player_saves s
  where s.user_id = target_id
  for update;

  if current_balance is null then
    raise exception 'Сохранение игрока не найдено';
  end if;

  update public.player_saves
  set game_state = jsonb_set(
    game_state,
    '{balance}',
    to_jsonb(current_balance + p_amount),
    true
  ),
  updated_at = now()
  where user_id = target_id;

  return query select target_nickname, current_balance + p_amount;
end;
$$;

revoke all on function public.admin_grant_player_money(text, numeric) from public;
grant execute on function public.admin_grant_player_money(text, numeric) to authenticated;
