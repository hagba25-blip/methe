-- Tests du parcours de dépôt (phase 3)
\set ON_ERROR_STOP 1

create or replace function pg_temp.expect_error(p_sql text, p_label text) returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    raise notice 'OK  (refusé) %: %', p_label, sqlerrm;
    return;
  end;
  raise exception 'ÉCHEC : % aurait dû être refusé', p_label;
end $$;

-- C = joueur, D = administrateur finance
insert into auth.users (id, email, raw_user_meta_data) values
 ('00000000-0000-0000-0000-00000000000c', 'kofi@example.com',
  '{"first_name":"Kofi","last_name":"A","phone":"+22890000010","country_code":"TG","language_code":"fr","currency_code":"XOF","accept_terms":true,"accept_privacy":true}'),
 ('00000000-0000-0000-0000-00000000000d', 'admin@example.com',
  '{"first_name":"Ama","last_name":"Admin","phone":"+22890000011","country_code":"TG","language_code":"fr","currency_code":"XOF","accept_terms":true,"accept_privacy":true}');
select private.grant_staff_role('admin@example.com', 'finance');

do $$
declare
  v_agent uuid := (select id from public.agents where whatsapp_number = '+22899315092');
  d public.deposits;
  r jsonb;
begin
  d := private.request_deposit('00000000-0000-0000-0000-00000000000c', v_agent, 10000);
  assert d.status = 'pending' and d.reference ~ '^DEP-[0-9]{8}-[0-9]{6}$', 'demande';
  r := private.approve_deposit(d.id, '00000000-0000-0000-0000-00000000000d');
  assert (r->>'balance_before')::bigint = 0 and (r->>'balance_after')::bigint = 10000, 'soldes';
  assert (select status from public.deposits where id = d.id) = 'approved';
  assert exists (select 1 from public.notifications where user_id = d.user_id and type = 'deposit_approved');
  assert exists (select 1 from public.admin_actions where action = 'approve_deposit' and target_id = d.reference);
  raise notice 'OK  dépôt demandé, approuvé, crédité, notifié, tracé';

  begin
    perform private.approve_deposit(d.id, '00000000-0000-0000-0000-00000000000d');
    raise exception 'ÉCHEC double validation';
  exception when others then
    if sqlerrm like 'ÉCHEC%' then raise; end if;
  end;
  assert (select balance from public.wallets where user_id = d.user_id) = 10000, 'pas de double crédit';
  raise notice 'OK  (refusé) double validation, solde inchangé';

  -- montant corrigé par l'admin
  d := private.request_deposit('00000000-0000-0000-0000-00000000000c', v_agent, 5000);
  r := private.approve_deposit(d.id, '00000000-0000-0000-0000-00000000000d', 4000, 'reçu 4000 seulement');
  assert (r->>'balance_after')::bigint = 14000, 'montant corrigé';

  -- refus
  d := private.request_deposit('00000000-0000-0000-0000-00000000000c', v_agent, 2000);
  perform private.reject_deposit(d.id, '00000000-0000-0000-0000-00000000000d', 'Paiement non reçu');
  assert (select status from public.deposits where id = d.id) = 'rejected';
  assert (select balance from public.wallets where user_id = d.user_id) = 14000, 'refus sans crédit';

  -- annulation par le joueur
  d := private.request_deposit('00000000-0000-0000-0000-00000000000c', v_agent, 2000);
  perform private.cancel_deposit(d.id, '00000000-0000-0000-0000-00000000000c');
  assert (select status from public.deposits where id = d.id) = 'cancelled';
  raise notice 'OK  montant corrigé, refus, annulation';

  -- crédit manuel idempotent
  r := private.admin_credit((select public_id from public.profiles where id = d.user_id),
        '00000000-0000-0000-0000-00000000000d', 10000, 'Validation dépôt', 'req-0001');
  assert (r->>'balance_before')::bigint = 14000 and (r->>'balance_after')::bigint = 24000, 'crédit manuel';
  r := private.admin_credit((select public_id from public.profiles where id = d.user_id),
        '00000000-0000-0000-0000-00000000000d', 10000, 'Validation dépôt', 'req-0001');
  assert (r->>'replayed')::boolean and (r->>'balance_after')::bigint = 24000, 'rejeu';
  assert (select balance from public.wallets where user_id = d.user_id) = 24000, 'crédit unique';
  raise notice 'OK  crédit manuel (double clic = un seul crédit)';
end $$;

select pg_temp.expect_error($q$
  select private.request_deposit('00000000-0000-0000-0000-00000000000c',
    (select id from public.agents limit 1), 20)
$q$, 'dépôt sous le minimum');
select pg_temp.expect_error($q$
  select private.approve_deposit(
    (select id from public.deposits where user_id = '00000000-0000-0000-0000-00000000000c' and status='rejected'),
    '00000000-0000-0000-0000-00000000000d')
$q$, 'valider un dépôt refusé');
select pg_temp.expect_error($q$
  select private.reject_deposit(private_id, '00000000-0000-0000-0000-00000000000d', '')
  from (select (private.request_deposit('00000000-0000-0000-0000-00000000000c',
          (select id from public.agents limit 1), 1000)).id as private_id) s
$q$, 'refus sans motif');
select pg_temp.expect_error($q$
  select private.admin_credit((select public_id from public.profiles where email='admin@example.com'),
    '00000000-0000-0000-0000-00000000000d', 1000, 'test', 'req-self')
$q$, 'admin qui se crédite lui-même');

-- Limite de demandes en attente : 3
do $$
declare v_agent uuid := (select id from public.agents limit 1);
begin
  perform private.request_deposit('00000000-0000-0000-0000-00000000000c', v_agent, 1000);
  perform private.request_deposit('00000000-0000-0000-0000-00000000000c', v_agent, 1000);
  perform private.request_deposit('00000000-0000-0000-0000-00000000000c', v_agent, 1000);
  begin
    perform private.request_deposit('00000000-0000-0000-0000-00000000000c', v_agent, 1000);
    raise exception 'ÉCHEC limite';
  exception when others then
    if sqlerrm like 'ÉCHEC%' then raise; end if;
    raise notice 'OK  (refusé) 4e demande en attente: %', sqlerrm;
  end;
end $$;

-- Le joueur ne peut pas appeler ces fonctions lui-même
begin;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000c';
select pg_temp.expect_error($q$ select private.admin_credit('6000000000', auth.uid(), 1, 'xxx', 'k') $q$,
  'joueur appelle admin_credit');
do $$ begin
  assert (select count(*) from public.deposits) = (select count(*) from public.deposits where user_id = auth.uid()),
    'le joueur ne voit que ses dépôts';
  raise notice 'OK  RLS dépôts';
end $$;
rollback;

do $$ begin raise notice 'TESTS DÉPÔTS PASSÉS'; end $$;
