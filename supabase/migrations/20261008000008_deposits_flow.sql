-- =============================================================================
-- 0008 — Dépôts : demande, validation / refus par l'administration, crédit manuel
-- =============================================================================
-- Toutes les opérations sont atomiques : verrouillage de la ligne, écriture du
-- ledger (idempotente), mise à jour du statut, notification et trace admin dans
-- la même transaction. Appelées uniquement par le backend (rôle privilégié).

insert into public.app_settings (key, value, is_public, description) values
  ('deposit.min_amount',          '100',  true,  'Montant minimum d''une demande de dépôt'),
  ('deposit.max_amount',          '5000000', true, 'Montant maximum d''une demande de dépôt'),
  ('deposit.max_pending_per_user', '3',   false, 'Nombre maximum de demandes en attente par joueur')
on conflict (key) do nothing;

create or replace function private.setting_bigint(p_key text, p_default bigint)
returns bigint language sql stable security definer set search_path = '' as $$
  select coalesce((select (value #>> '{}')::bigint from public.app_settings
                   where key = p_key and jsonb_typeof(value) = 'number'), p_default);
$$;

create or replace function private.treasury_wallet(p_currency char(3))
returns uuid language plpgsql stable security definer set search_path = '' as $$
declare v_id uuid;
begin
  select id into v_id from public.wallets where system_code = 'TREASURY' and currency_code = p_currency;
  if v_id is null then
    raise exception 'Aucune trésorerie configurée pour la devise %', p_currency;
  end if;
  return v_id;
end $$;

-- Demande de dépôt (le joueur a choisi un agent et un montant) ---------------
create or replace function private.request_deposit(p_user_id uuid, p_agent_id uuid, p_amount bigint)
returns public.deposits language plpgsql security definer set search_path = '' as $$
declare
  v_profile public.profiles%rowtype;
  v_wallet  public.wallets%rowtype;
  v_dep     public.deposits%rowtype;
begin
  select * into v_profile from public.profiles where id = p_user_id;
  if not found or v_profile.status <> 'active' then
    raise exception 'Compte non actif' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.agents where id = p_agent_id and is_active and is_available) then
    raise exception 'Agent indisponible' using errcode = 'P0001';
  end if;
  if p_amount < private.setting_bigint('deposit.min_amount', 100)
     or p_amount > private.setting_bigint('deposit.max_amount', 5000000) then
    raise exception 'Montant de dépôt hors limites' using errcode = 'P0001';
  end if;
  -- Verrou sur le portefeuille : sérialise les demandes simultanées du même joueur
  select * into v_wallet from public.wallets
   where user_id = p_user_id and currency_code = v_profile.currency_code for update;
  if (select count(*) from public.deposits where user_id = p_user_id and status = 'pending')
     >= private.setting_bigint('deposit.max_pending_per_user', 3) then
    raise exception 'Trop de demandes de dépôt en attente' using errcode = 'P0001';
  end if;

  insert into public.deposits (user_id, wallet_id, agent_id, amount, currency_code)
  values (p_user_id, v_wallet.id, p_agent_id, p_amount, v_profile.currency_code)
  returning * into v_dep;
  return v_dep;
end $$;

-- Annulation par le joueur (tant que la demande est en attente) --------------
create or replace function private.cancel_deposit(p_deposit_id uuid, p_user_id uuid)
returns public.deposits language plpgsql security definer set search_path = '' as $$
declare v_dep public.deposits%rowtype;
begin
  select * into v_dep from public.deposits where id = p_deposit_id and user_id = p_user_id for update;
  if not found then
    raise exception 'Dépôt introuvable' using errcode = 'P0002';
  end if;
  if v_dep.status <> 'pending' then
    raise exception 'Ce dépôt ne peut plus être annulé' using errcode = 'P0001';
  end if;
  update public.deposits set status = 'cancelled' where id = p_deposit_id returning * into v_dep;
  return v_dep;
end $$;

-- Validation par l'administration -----------------------------------------------
-- p_amount permet de corriger le montant réellement reçu par l'agent (null = montant demandé).
create or replace function private.approve_deposit(
  p_deposit_id uuid, p_admin_id uuid, p_amount bigint default null, p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_dep      public.deposits%rowtype;
  v_amount   bigint;
  v_before   bigint;
  v_after    bigint;
  v_journal  uuid;
begin
  select * into v_dep from public.deposits where id = p_deposit_id for update;
  if not found then
    raise exception 'Dépôt introuvable' using errcode = 'P0002';
  end if;
  if v_dep.status <> 'pending' then
    raise exception 'Dépôt déjà traité (%)', v_dep.status using errcode = 'P0001';
  end if;
  if v_dep.user_id = p_admin_id then
    raise exception 'Un administrateur ne peut pas valider son propre dépôt' using errcode = 'P0001';
  end if;
  v_amount := coalesce(p_amount, v_dep.amount);
  if v_amount <= 0 then
    raise exception 'Montant invalide' using errcode = 'P0001';
  end if;

  v_journal := private.post_journal(
    'deposit', 'deposit:' || v_dep.id,
    jsonb_build_array(
      jsonb_build_object('wallet_id', private.treasury_wallet(v_dep.currency_code), 'amount', -v_amount),
      jsonb_build_object('wallet_id', v_dep.wallet_id, 'amount', v_amount)),
    'admin', v_dep.id, p_admin_id, 'Dépôt ' || v_dep.reference, v_dep.reference);
  select balance_before, balance_after into v_before, v_after
    from public.wallet_transactions where journal_id = v_journal and wallet_id = v_dep.wallet_id;

  update public.deposits
     set status = 'approved', amount = v_amount, journal_id = v_journal,
         reviewed_by = p_admin_id, reviewed_at = now()
   where id = v_dep.id;

  insert into public.notifications (user_id, type, title, body, data) values (
    v_dep.user_id, 'deposit_approved', 'Dépôt approuvé',
    format('Votre dépôt %s de %s %s a été crédité.', v_dep.reference, v_amount, v_dep.currency_code),
    jsonb_build_object('deposit_id', v_dep.id, 'amount', v_amount));

  insert into public.admin_actions (admin_id, action, target_type, target_id, reason, payload)
  values (p_admin_id, 'approve_deposit', 'deposit', v_dep.reference, p_note,
          jsonb_build_object('requested', v_dep.amount, 'credited', v_amount,
                             'balance_before', v_before, 'balance_after', v_after));

  return jsonb_build_object('reference', v_dep.reference, 'amount', v_amount,
                            'balance_before', v_before, 'balance_after', v_after);
end $$;

create or replace function private.reject_deposit(p_deposit_id uuid, p_admin_id uuid, p_reason text)
returns public.deposits language plpgsql security definer set search_path = '' as $$
declare v_dep public.deposits%rowtype;
begin
  if p_reason is null or length(trim(p_reason)) < 3 then
    raise exception 'Motif de refus obligatoire' using errcode = 'P0001';
  end if;
  select * into v_dep from public.deposits where id = p_deposit_id for update;
  if not found then
    raise exception 'Dépôt introuvable' using errcode = 'P0002';
  end if;
  if v_dep.status <> 'pending' then
    raise exception 'Dépôt déjà traité (%)', v_dep.status using errcode = 'P0001';
  end if;
  update public.deposits
     set status = 'rejected', rejection_reason = trim(p_reason), reviewed_by = p_admin_id, reviewed_at = now()
   where id = v_dep.id returning * into v_dep;

  insert into public.notifications (user_id, type, title, body, data) values (
    v_dep.user_id, 'deposit_rejected', 'Dépôt refusé',
    format('Votre dépôt %s a été refusé : %s', v_dep.reference, trim(p_reason)),
    jsonb_build_object('deposit_id', v_dep.id));
  insert into public.admin_actions (admin_id, action, target_type, target_id, reason)
  values (p_admin_id, 'reject_deposit', 'deposit', v_dep.reference, trim(p_reason));
  return v_dep;
end $$;

-- Crédit manuel autorisé (cahier des charges §31) ------------------------------
-- p_request_key : clé fournie par l'écran admin pour qu'un double clic ne crédite qu'une fois.
create or replace function private.admin_credit(
  p_public_id char(10), p_admin_id uuid, p_amount bigint, p_reason text, p_request_key text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_profile public.profiles%rowtype;
  v_wallet  uuid;
  v_before  bigint;
  v_after   bigint;
  v_journal uuid;
  v_ref     text;
begin
  if p_amount <= 0 then
    raise exception 'Montant invalide' using errcode = 'P0001';
  end if;
  if p_reason is null or length(trim(p_reason)) < 3 then
    raise exception 'Motif obligatoire' using errcode = 'P0001';
  end if;
  select * into v_profile from public.profiles where public_id = p_public_id;
  if not found then
    raise exception 'Aucun client avec cet ID' using errcode = 'P0002';
  end if;
  if v_profile.id = p_admin_id then
    raise exception 'Un administrateur ne peut pas se créditer lui-même' using errcode = 'P0001';
  end if;
  select id into v_wallet from public.wallets
   where user_id = v_profile.id and currency_code = v_profile.currency_code;

  v_journal := private.post_journal(
    'adjustment', 'admin-credit:' || p_request_key,
    jsonb_build_array(
      jsonb_build_object('wallet_id', private.treasury_wallet(v_profile.currency_code), 'amount', -p_amount),
      jsonb_build_object('wallet_id', v_wallet, 'amount', p_amount)),
    'admin', v_profile.id, p_admin_id, trim(p_reason));
  select reference into v_ref from public.ledger_journals where id = v_journal;

  -- Rejeu de la même demande : on renvoie le résultat déjà enregistré.
  if exists (select 1 from public.admin_actions
             where action = 'credit_user' and payload->>'journal_id' = v_journal::text) then
    return (select payload || jsonb_build_object('reference', v_ref, 'replayed', true)
              from public.admin_actions
             where action = 'credit_user' and payload->>'journal_id' = v_journal::text limit 1);
  end if;

  select balance into v_after from public.wallets where id = v_wallet;
  v_before := v_after - p_amount;
  begin
    insert into public.admin_actions (admin_id, action, target_type, target_id, reason, payload)
    values (p_admin_id, 'credit_user', 'profile', p_public_id, trim(p_reason),
            jsonb_build_object('amount', p_amount, 'journal_id', v_journal,
                               'balance_before', v_before, 'balance_after', v_after));
    insert into public.notifications (user_id, type, title, body, data) values (
      v_profile.id, 'account_change', 'Compte crédité',
      format('Votre compte a été crédité de %s %s.', p_amount, v_profile.currency_code),
      jsonb_build_object('reference', v_ref, 'amount', p_amount));
  end;

  return jsonb_build_object('reference', v_ref, 'amount', p_amount,
                            'balance_before', v_before, 'balance_after', v_after);
end $$;

revoke execute on all functions in schema private from public, anon, authenticated;
grant execute on function private.has_role(public.app_role[]) to authenticated;
grant execute on function private.is_staff() to authenticated;
