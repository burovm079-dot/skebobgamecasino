-- SKEBOB GAME: audit log of every persisted player balance change.
-- Run the complete script in Supabase SQL Editor.

create table if not exists public.player_balance_history (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  amount_delta numeric(20,2) not null,
  balance_after numeric(20,2) not null,
  entry_type text not null check (entry_type in ('credit','debit')),
  created_at timestamptz not null default now()
);

create index if not exists player_balance_history_user_created_idx
  on public.player_balance_history (user_id, created_at desc, id desc);

alter table public.player_balance_history enable row level security;
revoke all on public.player_balance_history from anon, authenticated;

create or replace function public.log_player_balance_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  old_balance numeric;
  new_balance numeric;
  delta numeric;
begin
  old_balance := coalesce(nullif(old.game_state ->> 'balance', '')::numeric, 20);
  new_balance := coalesce(nullif(new.game_state ->> 'balance', '')::numeric, 20);
  delta := round(new_balance - old_balance, 2);

  if delta <> 0 then
    insert into public.player_balance_history
      (user_id, amount_delta, balance_after, entry_type)
    values
      (new.user_id, delta, new_balance,
       case when delta > 0 then 'credit' else 'debit' end);
  end if;

  return new;
end;
$$;

drop trigger if exists player_saves_balance_history on public.player_saves;
create trigger player_saves_balance_history
after update of game_state on public.player_saves
for each row
when ((old.game_state ->> 'balance') is distinct from (new.game_state ->> 'balance'))
execute function public.log_player_balance_change();

create or replace function public.admin_get_balance_history(p_nickname text)
returns table(
  player_nickname text,
  amount_delta numeric,
  balance_after numeric,
  entry_type text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  target_id uuid;
begin
  if auth.uid() is null or not exists (
    select 1 from public.game_admins a where a.user_id = auth.uid()
  ) then
    raise exception 'Нет доступа к истории баланса';
  end if;

  select p.user_id into target_id
  from public.player_profiles p
  where lower(trim(p.nickname)) = lower(trim(p_nickname))
  limit 1;

  if target_id is null then
    raise exception 'Игрок с таким никнеймом не найден';
  end if;

  return query
  select p.nickname, h.amount_delta, h.balance_after, h.entry_type, h.created_at
  from public.player_balance_history h
  join public.player_profiles p on p.user_id = h.user_id
  where h.user_id = target_id
  order by h.created_at desc, h.id desc
  limit 200;
end;
$$;

revoke all on function public.admin_get_balance_history(text) from public, anon;
grant execute on function public.admin_get_balance_history(text) to authenticated;

notify pgrst, 'reload schema';
