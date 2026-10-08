-- =============================================================================
-- 0013 — Anti-fraude : alertes automatiques, limite de paris, statut des comptes
-- =============================================================================
-- Les règles ci-dessous ne bloquent que ce qui est clairement abusif (rafale de
-- paris). Le reste lève une ALERTE (public.risk_events) que l'administration
-- examine avant de payer un retrait ; aucun argent n'est retenu automatiquement.

insert into public.app_settings (key, value, is_public, description) values
  ('betting.max_bets_per_minute',  '30',     false, 'Nombre maximum de paris par joueur et par minute (anti-robot)'),
  ('risk.big_win_amount',          '500000', false, 'Gain à partir duquel une alerte « gros gain » est levée'),
  ('risk.min_turnover_percent',    '100',    false, 'Mises minimales (en % des dépôts des 30 derniers jours) avant un retrait sans alerte'),
  ('risk.quick_withdrawal_minutes', '60',    false, 'Retrait demandé moins de N minutes après un dépôt : alerte')
on conflict (key) do nothing;

alter table public.risk_events add column if not exists resolution_note text;
alter table public.risk_events add column if not exists reference text;  -- objet concerné (retrait, pari…)
create index if not exists risk_events_open_idx on public.risk_events(created_at desc) where resolved_at is null;
create index if not exists risk_events_user_idx on public.risk_events(user_id, created_at desc);

-- Lève une alerte, sans doublon tant qu'une alerte identique est ouverte.
create or replace function private.raise_risk(
  p_user_id uuid, p_kind text, p_severity int, p_reference text, p_details jsonb)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if exists (select 1 from public.risk_events
              where user_id is not distinct from p_user_id and kind = p_kind
                and reference is not distinct from p_reference and resolved_at is null) then
    return;
  end if;
  insert into public.risk_events (user_id, kind, severity, reference, details)
  values (p_user_id, p_kind, p_severity, p_reference, coalesce(p_details, '{}'::jsonb));
end $$;

-- 1. Rafale de paris : refusée (robot ou script) --------------------------------
create or replace function private.check_bet_velocity()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_max bigint := private.setting_bigint('betting.max_bets_per_minute', 30);
begin
  if (select count(*) from public.bets
       where user_id = new.user_id and placed_at > now() - interval '1 minute') >= v_max then
    raise exception 'Trop de paris en peu de temps : réessayez dans une minute' using errcode = 'P0001';
  end if;
  return new;
end $$;

drop trigger if exists bets_velocity on public.bets;
create trigger bets_velocity before insert on public.bets
  for each row execute function private.check_bet_velocity();

-- 2. Gros gain : alerte (vérifier avant de payer un retrait) ---------------------
create or replace function private.check_big_win()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.status = 'won' and old.status is distinct from 'won'
     and new.actual_payout >= private.setting_bigint('risk.big_win_amount', 500000) then
    perform private.raise_risk(new.user_id, 'big_win', 2, new.reference,
      jsonb_build_object('bet_id', new.id, 'stake', new.stake, 'payout', new.actual_payout,
                         'game_type', new.game_type_code, 'round_id', new.round_id));
  end if;
  return new;
end $$;

drop trigger if exists bets_big_win on public.bets;
create trigger bets_big_win after update of status on public.bets
  for each row execute function private.check_big_win();

-- 3. Demande de retrait : trois contrôles ------------------------------------------
--  * numéro de paiement déjà utilisé par un autre compte (comptes multiples) ;
--  * mises trop faibles par rapport aux dépôts (dépôt puis retrait sans jouer) ;
--  * retrait demandé juste après un dépôt.
create or replace function private.check_withdrawal_risk()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_others     text[];
  v_deposits   bigint;
  v_staked     bigint;
  v_pct        numeric := private.setting_numeric('risk.min_turnover_percent', 100);
  v_last_dep   timestamptz;
  v_quick_min  bigint := private.setting_bigint('risk.quick_withdrawal_minutes', 60);
begin
  select array_agg(distinct p.public_id) into v_others
    from public.profiles p
   where p.id <> new.user_id
     and (p.phone = new.payout_account
          or exists (select 1 from public.withdrawals w
                      where w.user_id = p.id and w.payout_account = new.payout_account));
  if v_others is not null then
    perform private.raise_risk(new.user_id, 'shared_payout_account', 4, new.reference,
      jsonb_build_object('withdrawal_id', new.id, 'payout_account', new.payout_account, 'other_accounts', v_others));
  end if;

  select coalesce(sum(amount), 0), max(reviewed_at) into v_deposits, v_last_dep
    from public.deposits
   where user_id = new.user_id and status = 'approved' and reviewed_at > now() - interval '30 days';
  select coalesce(sum(stake), 0) into v_staked
    from public.bets
   where user_id = new.user_id and status in ('pending', 'won', 'lost') and placed_at > now() - interval '30 days';
  if v_deposits > 0 and v_staked * 100 < v_deposits * v_pct then
    perform private.raise_risk(new.user_id, 'low_turnover', 3, new.reference,
      jsonb_build_object('withdrawal_id', new.id, 'amount', new.amount,
                         'deposits_30d', v_deposits, 'staked_30d', v_staked, 'required_percent', v_pct));
  end if;

  if v_last_dep is not null and v_last_dep > now() - make_interval(mins => v_quick_min::int) then
    perform private.raise_risk(new.user_id, 'quick_withdrawal', 2, new.reference,
      jsonb_build_object('withdrawal_id', new.id, 'amount', new.amount, 'last_deposit_at', v_last_dep));
  end if;
  return new;
end $$;

drop trigger if exists withdrawals_risk on public.withdrawals;
create trigger withdrawals_risk after insert on public.withdrawals
  for each row execute function private.check_withdrawal_risk();

-- Statut d'un compte (admin) ---------------------------------------------------------
-- suspendu : ne peut plus parier, déposer ni retirer ; bloqué / fermé : en plus,
-- le portefeuille est gelé. Réactiver remet le compte et le portefeuille en service.
create or replace function private.set_account_status(
  p_public_id char(10), p_admin_id uuid, p_status public.account_status, p_reason text)
returns public.profiles language plpgsql security definer set search_path = '' as $$
declare
  v_profile public.profiles%rowtype;
  v_old     public.account_status;
begin
  if p_reason is null or length(trim(p_reason)) < 3 then
    raise exception 'Motif obligatoire' using errcode = 'P0001';
  end if;
  select * into v_profile from public.profiles where public_id = p_public_id for update;
  if not found then
    raise exception 'Aucun client avec cet ID' using errcode = 'P0002';
  end if;
  if v_profile.id = p_admin_id then
    raise exception 'Vous ne pouvez pas changer le statut de votre propre compte' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.admin_users where user_id = v_profile.id and is_active)
     and not exists (select 1 from public.admin_users
                      where user_id = p_admin_id and is_active and role = 'super_admin') then
    raise exception 'Seul un super administrateur peut changer le statut d''un membre de l''équipe' using errcode = 'P0001';
  end if;
  v_old := v_profile.status;
  if v_old = p_status then
    return v_profile;
  end if;

  update public.profiles set status = p_status where id = v_profile.id returning * into v_profile;
  update public.wallets set is_frozen = p_status in ('blocked', 'closed') where user_id = v_profile.id;

  insert into public.notifications (user_id, type, title, body, data) values (
    v_profile.id, 'account_change',
    case p_status when 'active' then 'Compte réactivé' when 'suspended' then 'Compte suspendu'
                  when 'blocked' then 'Compte bloqué' else 'Compte fermé' end,
    case p_status when 'active' then 'Votre compte est de nouveau actif.'
                  else 'Contactez le support pour en savoir plus.' end,
    jsonb_build_object('status', p_status));
  insert into public.admin_actions (admin_id, action, target_type, target_id, reason, payload)
  values (p_admin_id, 'set_account_status', 'profile', p_public_id, trim(p_reason),
          jsonb_build_object('from', v_old, 'to', p_status));
  return v_profile;
end $$;

-- Clôture d'une alerte (admin) --------------------------------------------------------
create or replace function private.resolve_risk_event(p_event_id bigint, p_admin_id uuid, p_note text)
returns public.risk_events language plpgsql security definer set search_path = '' as $$
declare v_event public.risk_events%rowtype;
begin
  if p_note is null or length(trim(p_note)) < 3 then
    raise exception 'Expliquez en quelques mots la décision' using errcode = 'P0001';
  end if;
  select * into v_event from public.risk_events where id = p_event_id for update;
  if not found then
    raise exception 'Alerte introuvable' using errcode = 'P0002';
  end if;
  if v_event.resolved_at is not null then
    return v_event;
  end if;
  if v_event.user_id = p_admin_id then
    raise exception 'Vous ne pouvez pas clore une alerte qui vous concerne' using errcode = 'P0001';
  end if;
  update public.risk_events set resolved_by = p_admin_id, resolved_at = now(), resolution_note = trim(p_note)
   where id = p_event_id returning * into v_event;
  insert into public.admin_actions (admin_id, action, target_type, target_id, reason, payload)
  values (p_admin_id, 'resolve_risk', 'risk_event', p_event_id::text, trim(p_note),
          jsonb_build_object('kind', v_event.kind, 'reference', v_event.reference));
  return v_event;
end $$;

revoke execute on all functions in schema private from public, anon, authenticated;
grant execute on function private.has_role(public.app_role[]) to authenticated;
grant execute on function private.is_staff() to authenticated;
