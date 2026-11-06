-- SKEBOB GAME: накопительный учёт выданной и потраченной игровой валюты
-- Выполнить один раз в Supabase SQL Editor после публикации обновления.

create table if not exists public.economy_balance_ledger (
  id bigserial primary key,
  player_id uuid not null references auth.users(id) on delete cascade,
  balance_delta numeric(20,2) not null,
  created_at timestamptz not null default now()
);

create index if not exists economy_balance_ledger_created_at_idx
  on public.economy_balance_ledger (created_at);
alter table public.economy_balance_ledger enable row level security;
revoke all on public.economy_balance_ledger from anon, authenticated;

create or replace function public.track_player_balance_turnover()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  old_balance numeric := 0;
  new_balance numeric := 0;
  difference numeric := 0;
begin
  if tg_op = 'UPDATE' then
    old_balance := coalesce(nullif(old.game_state ->> 'balance', '')::numeric, 0);
  end if;
  new_balance := coalesce(nullif(new.game_state ->> 'balance', '')::numeric, 0);
  difference := new_balance - old_balance;

  if difference <> 0 then
    insert into public.economy_balance_ledger(player_id, balance_delta)
    values (new.user_id, difference);
  end if;
  return new;
end;
$$;

drop trigger if exists player_saves_track_economy_turnover on public.player_saves;
create trigger player_saves_track_economy_turnover
after insert or update of game_state on public.player_saves
for each row execute function public.track_player_balance_turnover();

create or replace function public.admin_get_economy_turnover()
returns table(total_issued numeric, total_spent numeric, operations bigint)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not exists (
    select 1 from public.game_admins a where a.user_id = auth.uid()
  ) then
    raise exception 'Нет доступа к обороту экономики';
  end if;

  return query
  select
    coalesce(sum(case when l.balance_delta > 0 then l.balance_delta else 0 end), 0),
    coalesce(sum(case when l.balance_delta < 0 then -l.balance_delta else 0 end), 0),
    count(*)::bigint
  from public.economy_balance_ledger l;
end;
$$;

revoke all on function public.admin_get_economy_turnover() from public;
grant execute on function public.admin_get_economy_turnover() to authenticated;
notify pgrst, 'reload schema';
