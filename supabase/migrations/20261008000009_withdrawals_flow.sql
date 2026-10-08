-- =============================================================================
-- 0009 — Retraits : demande, blocage du montant, vérification, paiement, refus
-- =============================================================================
-- Cycle : EN ATTENTE → EN VÉRIFICATION → APPROUVÉ → PAYÉ
--         (REFUSÉ par l'administration ou ANNULÉ par le joueur avant paiement)
-- Dès la demande, le montant quitte le solde du joueur vers WITHDRAWAL_HOLD :
-- il ne peut donc pas être misé ou retiré deux fois. Refus / annulation → le
-- montant revient au joueur. Paiement → le net sort du système, les frais vont à HOUSE.

alter table public.withdrawals add column if not exists idempotency_key text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'withdrawals_idem_uq') then
    alter table public.withdrawals add constraint withdrawals_idem_uq unique (user_id, idempotency_key);
  end if;
end $$;

insert into public.app_settings (key, value, is_public, description) values
  ('withdrawal.max_open_per_user', '1', false, 'Retraits non terminés autorisés en même temps par joueur')
on conflict (key) do nothing;

create or replace function private.setting_numeric(p_key text, p_default numeric)
returns numeric language sql stable security definer set search_path = '' as $$
  select coalesce((select (value #>> '{}')::numeric from public.app_settings
                   where key = p_key and jsonb_typeof(value) = 'number'), p_default);
$$;

create or replace function private.system_wallet(p_code text, p_currency char(3))
returns uuid language plpgsql stable security definer set search_path = '' as $$
declare v_id uuid;
begin
  select id into v_id from public.wallets where system_code = p_code and currency_code = p_currency;
  if v_id is null then
    raise exception 'Portefeuille système % absent pour la devise %', p_code, p_currency;
  end if;
  return v_id;
end $$;

-- Portefeuilles système manquants pour les devises actives (idempotent)
insert into public.wallets (owner_type, system_code, currency_code, allow_negative)
select 'system', s.code, c.code, s.neg
from public.currencies c
cross join (values ('EXTERNAL_FUNDING', true), ('TREASURY', false), ('HOUSE', true), ('WITHDRAWAL_HOLD', false))
     as s(code, neg)
where c.is_active
on conflict do nothing;

-- Frais de retrait (arrondi à l'unité inférieure) ----------------------------
create or replace function private.withdrawal_fee(p_amount bigint)
returns bigint language sql stable security definer set search_path = '' as $$
  select floor(p_amount * private.setting_numeric('withdrawal.fee_percent', 0) / 100)::bigint;
$$;

-- Ce que l'écran Retrait affiche, calculé côté serveur ------------------------
create or replace function private.withdrawal_info(p_user_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_profile public.profiles%rowtype;
  v_wallet  public.wallets%rowtype;
  v_min     bigint := private.setting_bigint('withdrawal.min_amount', 1000);
  v_max     bigint := (select (value #>> '{}')::bigint from public.app_settings
                       where key = 'withdrawal.max_amount' and jsonb_typeof(value) = 'number');
  v_open    int;
  v_reason  text;
begin
  select * into v_profile from public.profiles where id = p_user_id;
  select * into v_wallet from public.wallets where user_id = p_user_id and currency_code = v_profile.currency_code;
  select count(*) into v_open from public.withdrawals
   where user_id = p_user_id and status in ('pending', 'under_review', 'approved');

  v_reason := case
    when v_profile.status <> 'active' or v_wallet.is_frozen then 'Compte bloqué'
    when (select value = 'true'::jsonb from public.app_settings where key = 'withdrawal.require_kyc')
         and v_profile.kyc_status <> 'verified' then 'Vérification d''identité requise'
    when v_open >= private.setting_bigint('withdrawal.max_open_per_user', 1) then 'Un retrait est déjà en cours'
    when v_wallet.balance < v_min then 'Solde inférieur au minimum de retrait'
  end;

  return jsonb_build_object(
    'balance', v_wallet.balance, 'currency_code', v_wallet.currency_code,
    'min_amount', v_min, 'max_amount', v_max,
    'fee_percent', private.setting_numeric('withdrawal.fee_percent', 0),
    'can_withdraw', v_reason is null, 'blocked_reason', v_reason,
    'default_payout_account', v_profile.phone);
end $$;

-- Demande de retrait ------------------------------------------------------------
create or replace function private.request_withdrawal(
  p_user_id uuid, p_amount bigint, p_method text, p_payout_account text, p_idempotency_key text)
returns public.withdrawals language plpgsql security definer set search_path = '' as $$
declare
  v_info    jsonb;
  v_profile public.profiles%rowtype;
  v_wallet  public.wallets%rowtype;
  v_wdr     public.withdrawals%rowtype;
  v_journal uuid;
  v_account text := regexp_replace(coalesce(p_payout_account, ''), '\s', '', 'g');
begin
  select * into v_wdr from public.withdrawals where user_id = p_user_id and idempotency_key = p_idempotency_key;
  if found then
    return v_wdr;  -- double envoi du même formulaire
  end if;

  select * into v_profile from public.profiles where id = p_user_id;
  -- Verrou du portefeuille : deux demandes simultanées sont traitées l'une après l'autre
  select * into v_wallet from public.wallets
   where user_id = p_user_id and currency_code = v_profile.currency_code for update;

  v_info := private.withdrawal_info(p_user_id);
  if not (v_info->>'can_withdraw')::boolean and v_info->>'blocked_reason' <> 'Solde inférieur au minimum de retrait' then
    raise exception '%', v_info->>'blocked_reason' using errcode = 'P0001';
  end if;
  if p_amount < (v_info->>'min_amount')::bigint then
    raise exception 'Le montant minimum de retrait est de %', v_info->>'min_amount' using errcode = 'P0001';
  end if;
  if v_info->>'max_amount' is not null and p_amount > (v_info->>'max_amount')::bigint then
    raise exception 'Le montant maximum de retrait est de %', v_info->>'max_amount' using errcode = 'P0001';
  end if;
  if p_amount > v_wallet.balance then
    raise exception 'Solde insuffisant' using errcode = 'P0001';
  end if;
  if p_method not in ('mobile_money', 'agent', 'bank') then
    raise exception 'Méthode de retrait inconnue' using errcode = 'P0001';
  end if;
  if p_method in ('mobile_money', 'agent') and v_account !~ '^\+[1-9][0-9]{6,14}$' then
    raise exception 'Numéro de paiement invalide (format international, ex. +22890000000)' using errcode = 'P0001';
  end if;
  if p_method = 'bank' and length(v_account) < 8 then
    raise exception 'Coordonnées bancaires invalides' using errcode = 'P0001';
  end if;

  insert into public.withdrawals (user_id, wallet_id, amount, fee, currency_code, method, payout_account, idempotency_key)
  values (p_user_id, v_wallet.id, p_amount, private.withdrawal_fee(p_amount), v_wallet.currency_code,
          p_method, v_account, p_idempotency_key)
  returning * into v_wdr;

  v_journal := private.post_journal(
    'withdrawal_hold', 'withdrawal-hold:' || v_wdr.id,
    jsonb_build_array(
      jsonb_build_object('wallet_id', v_wallet.id, 'amount', -p_amount),
      jsonb_build_object('wallet_id', private.system_wallet('WITHDRAWAL_HOLD', v_wallet.currency_code), 'amount', p_amount)),
    'api', v_wdr.id, null, 'Retrait ' || v_wdr.reference, v_wdr.reference);

  update public.withdrawals set hold_journal_id = v_journal where id = v_wdr.id returning * into v_wdr;
  return v_wdr;
end $$;

-- Restitution du montant bloqué (refus ou annulation) -------------------------
create or replace function private.release_withdrawal(v_wdr public.withdrawals, p_admin_id uuid)
returns uuid language sql security definer set search_path = '' as $$
  select private.post_journal(
    'withdrawal_release', 'withdrawal-release:' || v_wdr.id,
    jsonb_build_array(
      jsonb_build_object('wallet_id', private.system_wallet('WITHDRAWAL_HOLD', v_wdr.currency_code), 'amount', -v_wdr.amount),
      jsonb_build_object('wallet_id', v_wdr.wallet_id, 'amount', v_wdr.amount)),
    case when p_admin_id is null then 'api' else 'admin' end,
    v_wdr.id, p_admin_id, 'Retrait ' || v_wdr.reference || ' remboursé');
$$;

create or replace function private.cancel_withdrawal(p_withdrawal_id uuid, p_user_id uuid)
returns public.withdrawals language plpgsql security definer set search_path = '' as $$
declare v_wdr public.withdrawals%rowtype;
begin
  select * into v_wdr from public.withdrawals where id = p_withdrawal_id and user_id = p_user_id for update;
  if not found then
    raise exception 'Retrait introuvable' using errcode = 'P0002';
  end if;
  if v_wdr.status <> 'pending' then
    raise exception 'Ce retrait est déjà en traitement et ne peut plus être annulé' using errcode = 'P0001';
  end if;
  update public.withdrawals
     set status = 'cancelled', release_journal_id = private.release_withdrawal(v_wdr, null)
   where id = v_wdr.id returning * into v_wdr;
  return v_wdr;
end $$;

-- Traitement par l'administration --------------------------------------------
-- p_action : 'review' | 'approve' | 'pay' | 'reject'
create or replace function private.process_withdrawal(
  p_withdrawal_id uuid, p_admin_id uuid, p_action text, p_reason text default null)
returns public.withdrawals language plpgsql security definer set search_path = '' as $$
declare
  v_wdr     public.withdrawals%rowtype;
  v_journal uuid;
  v_notif   text;
  v_title   text;
  v_body    text;
begin
  select * into v_wdr from public.withdrawals where id = p_withdrawal_id for update;
  if not found then
    raise exception 'Retrait introuvable' using errcode = 'P0002';
  end if;
  if v_wdr.user_id = p_admin_id then
    raise exception 'Un administrateur ne peut pas traiter son propre retrait' using errcode = 'P0001';
  end if;

  if p_action = 'review' and v_wdr.status = 'pending' then
    update public.withdrawals set status = 'under_review', reviewed_by = p_admin_id, reviewed_at = now()
     where id = v_wdr.id returning * into v_wdr;

  elsif p_action = 'approve' and v_wdr.status in ('pending', 'under_review') then
    update public.withdrawals set status = 'approved', reviewed_by = p_admin_id, reviewed_at = now()
     where id = v_wdr.id returning * into v_wdr;
    v_notif := 'withdrawal_approved';
    v_title := 'Retrait approuvé';
    v_body  := format('Votre retrait %s est approuvé, le paiement est en cours.', v_wdr.reference);

  elsif p_action = 'pay' and v_wdr.status = 'approved' then
    v_journal := private.post_journal(
      'withdrawal_payout', 'withdrawal-payout:' || v_wdr.id,
      jsonb_build_array(
        jsonb_build_object('wallet_id', private.system_wallet('WITHDRAWAL_HOLD', v_wdr.currency_code), 'amount', -v_wdr.amount),
        jsonb_build_object('wallet_id', private.system_wallet('EXTERNAL_FUNDING', v_wdr.currency_code), 'amount', v_wdr.net_amount),
        jsonb_build_object('wallet_id', private.system_wallet('HOUSE', v_wdr.currency_code), 'amount', v_wdr.fee)),
      'admin', v_wdr.id, p_admin_id, 'Paiement retrait ' || v_wdr.reference);
    update public.withdrawals set status = 'paid', paid_at = now(), payout_journal_id = v_journal
     where id = v_wdr.id returning * into v_wdr;
    v_notif := 'withdrawal_paid';
    v_title := 'Retrait payé';
    v_body  := format('Votre retrait %s de %s %s a été payé sur %s.',
                      v_wdr.reference, v_wdr.net_amount, v_wdr.currency_code, v_wdr.payout_account);

  elsif p_action = 'reject' and v_wdr.status in ('pending', 'under_review', 'approved') then
    if p_reason is null or length(trim(p_reason)) < 3 then
      raise exception 'Motif de refus obligatoire' using errcode = 'P0001';
    end if;
    update public.withdrawals
       set status = 'rejected', rejection_reason = trim(p_reason), reviewed_by = p_admin_id, reviewed_at = now(),
           release_journal_id = private.release_withdrawal(v_wdr, p_admin_id)
     where id = v_wdr.id returning * into v_wdr;
    v_notif := 'withdrawal_rejected';
    v_title := 'Retrait refusé';
    v_body  := format('Votre retrait %s a été refusé (%s). Le montant a été remis sur votre solde.',
                      v_wdr.reference, trim(p_reason));

  else
    raise exception 'Action « % » impossible pour un retrait %', p_action, v_wdr.status using errcode = 'P0001';
  end if;

  if v_notif is not null then
    insert into public.notifications (user_id, type, title, body, data)
    values (v_wdr.user_id, v_notif, v_title, v_body, jsonb_build_object('withdrawal_id', v_wdr.id));
  end if;
  insert into public.admin_actions (admin_id, action, target_type, target_id, reason, payload)
  values (p_admin_id, p_action || '_withdrawal', 'withdrawal', v_wdr.reference, p_reason,
          jsonb_build_object('amount', v_wdr.amount, 'net_amount', v_wdr.net_amount, 'status', v_wdr.status));
  return v_wdr;
end $$;

revoke execute on all functions in schema private from public, anon, authenticated;
grant execute on function private.has_role(public.app_role[]) to authenticated;
grant execute on function private.is_staff() to authenticated;
