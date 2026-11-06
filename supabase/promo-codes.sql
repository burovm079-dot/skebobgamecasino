-- SKEBOB GAME: admin-created promo codes with server-enforced activation limits.
-- Run this complete script once in Supabase SQL Editor.

create table if not exists public.promo_codes (
 id bigint generated always as identity primary key,
 code text not null,
 reward numeric(12,2) not null check (reward > 0 and reward <= 1000000),
 activation_limit integer not null check (activation_limit between 1 and 1000000),
 activations_used integer not null default 0 check (activations_used >= 0),
 created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),
 is_active boolean not null default true,
 constraint promo_codes_code_unique unique (code),
 constraint promo_codes_usage_limit check (activations_used <= activation_limit)
);
create table if not exists public.promo_redemptions (
 id bigint generated always as identity primary key,
 promo_id bigint not null references public.promo_codes(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 reward numeric(12,2) not null,
 redeemed_at timestamptz not null default now(),
 constraint promo_redemptions_one_per_user unique (promo_id,user_id)
);
alter table public.promo_codes enable row level security;
alter table public.promo_redemptions enable row level security;
revoke all on public.promo_codes from anon,authenticated;
revoke all on public.promo_redemptions from anon,authenticated;

create or replace function public.admin_create_promo_code(p_code text,p_reward numeric,p_activation_limit integer)
returns table(promo_code text,reward numeric,activation_limit integer,activations_used integer)
language plpgsql security definer set search_path=''
as $$
declare normalized_code text:=upper(trim(coalesce(p_code,'')));
begin
 if auth.uid() is null or not exists(select 1 from public.game_admins a where a.user_id=auth.uid()) then
  raise exception 'Недостаточно прав для создания промокодов.';
 end if;
 if normalized_code !~ '^[A-Z0-9_-]{3,32}$' then raise exception 'Код должен содержать 3–32 символа: латинские буквы, цифры, дефис или подчёркивание.'; end if;
 if p_reward is null or p_reward<=0 or p_reward>1000000 or p_reward<>round(p_reward,2) then raise exception 'Награда должна быть от 0.01 до 1 000 000 ₽.'; end if;
 if p_activation_limit is null or p_activation_limit<1 or p_activation_limit>1000000 then raise exception 'Лимит должен быть от 1 до 1 000 000 активаций.'; end if;
 return query insert into public.promo_codes(code,reward,activation_limit,created_by)
 values(normalized_code,p_reward,p_activation_limit,auth.uid())
 returning code,promo_codes.reward,promo_codes.activation_limit,promo_codes.activations_used;
exception when unique_violation then raise exception 'Промокод с таким кодом уже существует.';
end;
$$;

create or replace function public.redeem_promo_code(p_code text)
returns table(promo_code text,reward numeric,new_balance numeric,activations_used integer,activation_limit integer)
language plpgsql security definer set search_path=''
as $$
declare
 target_id bigint; target_reward numeric; target_limit integer; used_count integer; current_balance numeric;
 normalized_code text:=upper(trim(coalesce(p_code,'')));
begin
 if auth.uid() is null then raise exception 'Сначала войди в аккаунт.'; end if;
 if normalized_code='' then raise exception 'Введи промокод.'; end if;
 select pc.id,pc.reward,pc.activation_limit into target_id,target_reward,target_limit
 from public.promo_codes pc where pc.code=normalized_code and pc.is_active=true;
 if target_id is null then raise exception 'Промокод не найден или отключён.'; end if;
 if exists(select 1 from public.promo_redemptions pr where pr.promo_id=target_id and pr.user_id=auth.uid()) then
  raise exception 'Ты уже активировал этот промокод.';
 end if;
 update public.promo_codes pc set activations_used=pc.activations_used+1
 where pc.id=target_id and pc.is_active=true and pc.activations_used<pc.activation_limit
 returning pc.activations_used into used_count;
 if used_count is null then raise exception 'Лимит активаций этого промокода исчерпан.'; end if;
 insert into public.promo_redemptions(promo_id,user_id,reward) values(target_id,auth.uid(),target_reward);
 select coalesce((ps.game_state->>'balance')::numeric,20) into current_balance
 from public.player_saves ps where ps.user_id=auth.uid() for update;
 if current_balance is null then raise exception 'Игровое сохранение не найдено.'; end if;
 update public.player_saves ps set game_state=jsonb_set(coalesce(ps.game_state,'{}'::jsonb),'{balance}',to_jsonb(current_balance+target_reward),true),updated_at=now()
 where ps.user_id=auth.uid();
 return query select normalized_code,target_reward,current_balance+target_reward,used_count,target_limit;
end;
$$;
revoke all on function public.admin_create_promo_code(text,numeric,integer) from public,anon;
revoke all on function public.redeem_promo_code(text) from public,anon;
grant execute on function public.admin_create_promo_code(text,numeric,integer) to authenticated;
grant execute on function public.redeem_promo_code(text) to authenticated;
notify pgrst,'reload schema';
