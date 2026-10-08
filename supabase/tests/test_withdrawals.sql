-- Tests du parcours de retrait (phase 4)
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

-- E = joueur (crédité de 20 000 F), D = admin finance (créé par test_deposits.sql)
insert into auth.users (id, email, raw_user_meta_data) values
 ('00000000-0000-0000-0000-00000000000e', 'yao@example.com',
  '{"first_name":"Yao","last_name":"B","phone":"+22890000020","country_code":"TG","language_code":"fr","currency_code":"XOF","accept_terms":true,"accept_privacy":true}');
select private.admin_credit((select public_id from public.profiles where id = '00000000-0000-0000-0000-00000000000e'),
  '00000000-0000-0000-0000-00000000000d', 20000, 'Crédit de test retraits', 'test-wdr-credit-1');

do $$
declare
  v_user constant uuid := '00000000-0000-0000-0000-00000000000e';
  v_adm  constant uuid := '00000000-0000-0000-0000-00000000000d';
  v_hold uuid := private.system_wallet('WITHDRAWAL_HOLD', 'XOF');
  v_hold_before bigint := (select balance from public.wallets where id = private.system_wallet('WITHDRAWAL_HOLD', 'XOF'));
  w public.withdrawals;
  w2 public.withdrawals;
  i jsonb;
begin
  i := private.withdrawal_info(v_user);
  assert (i->>'balance')::bigint = 20000 and (i->>'can_withdraw')::boolean, 'info initiale';
  assert i->>'default_payout_account' = '+22890000020', 'numéro par défaut';

  -- Demande : le montant est bloqué tout de suite
  w := private.request_withdrawal(v_user, 5000, 'mobile_money', '+228 90 00 00 20', 'wdr-key-1');
  assert w.status = 'pending' and w.reference ~ '^WDR-[0-9]{8}-[0-9]{6}$', 'demande';
  assert w.payout_account = '+22890000020', 'espaces retirés du numéro';
  assert w.hold_journal_id is not null, 'journal de blocage';
  assert (select balance from public.wallets where user_id = v_user) = 15000, 'solde débité à la demande';
  assert (select balance from public.wallets where id = v_hold) = v_hold_before + 5000, 'montant bloqué';

  -- Double envoi du même formulaire : même retrait, pas de second débit
  w2 := private.request_withdrawal(v_user, 5000, 'mobile_money', '+22890000020', 'wdr-key-1');
  assert w2.id = w.id, 'idempotence';
  assert (select balance from public.wallets where user_id = v_user) = 15000, 'pas de double débit';

  i := private.withdrawal_info(v_user);
  assert not (i->>'can_withdraw')::boolean and i->>'blocked_reason' = 'Un retrait est déjà en cours', 'un seul retrait ouvert';

  -- Annulation par le joueur : remboursement
  w := private.cancel_withdrawal(w.id, v_user);
  assert w.status = 'cancelled' and w.release_journal_id is not null, 'annulé';
  assert (select balance from public.wallets where user_id = v_user) = 20000, 'remboursé après annulation';
  raise notice 'OK  demande, blocage, idempotence, annulation, remboursement';

  -- Cycle complet : vérification → approbation → paiement
  w := private.request_withdrawal(v_user, 8000, 'mobile_money', '+22890000020', 'wdr-key-2');
  w := private.process_withdrawal(w.id, v_adm, 'review');
  assert w.status = 'under_review' and w.reviewed_by = v_adm, 'en vérification';
  w := private.process_withdrawal(w.id, v_adm, 'approve');
  assert w.status = 'approved', 'approuvé';
  w := private.process_withdrawal(w.id, v_adm, 'pay');
  assert w.status = 'paid' and w.payout_journal_id is not null and w.paid_at is not null, 'payé';
  assert (select balance from public.wallets where user_id = v_user) = 12000, 'solde final';
  assert (select balance from public.wallets where id = v_hold) = v_hold_before, 'blocage soldé';
  assert exists (select 1 from public.notifications where user_id = v_user and type = 'withdrawal_paid'), 'notif payé';
  assert exists (select 1 from public.admin_actions where action = 'pay_withdrawal' and target_id = w.reference), 'trace admin';
  raise notice 'OK  vérification, approbation, paiement, notification, trace';

  begin
    perform private.process_withdrawal(w.id, v_adm, 'pay');
    raise exception 'ÉCHEC double paiement';
  exception when sqlstate 'P0001' then raise notice 'OK  (refusé) double paiement';
  end;

  -- Refus : motif obligatoire, puis remboursement
  w := private.request_withdrawal(v_user, 3000, 'agent', '+22890000020', 'wdr-key-3');
  begin
    perform private.process_withdrawal(w.id, v_adm, 'reject', '');
    raise exception 'ÉCHEC refus sans motif';
  exception when sqlstate 'P0001' then raise notice 'OK  (refusé) refus sans motif';
  end;
  w := private.process_withdrawal(w.id, v_adm, 'reject', 'Numéro injoignable');
  assert w.status = 'rejected' and w.rejection_reason = 'Numéro injoignable', 'refusé';
  assert (select balance from public.wallets where user_id = v_user) = 12000, 'remboursé après refus';
  assert exists (select 1 from public.notifications where user_id = v_user and type = 'withdrawal_rejected'), 'notif refus';
  raise notice 'OK  refus avec motif et remboursement';

  -- Le joueur ne peut plus annuler une fois le retrait pris en charge
  w := private.request_withdrawal(v_user, 2000, 'mobile_money', '+22890000020', 'wdr-key-4');
  w := private.process_withdrawal(w.id, v_adm, 'review');
  begin
    perform private.cancel_withdrawal(w.id, v_user);
    raise exception 'ÉCHEC annulation en vérification';
  exception when sqlstate 'P0001' then raise notice 'OK  (refusé) annulation d''un retrait en vérification';
  end;
  perform private.process_withdrawal(w.id, v_adm, 'reject', 'Test nettoyage');
end $$;

select pg_temp.expect_error($q$ select private.request_withdrawal('00000000-0000-0000-0000-00000000000e', 500, 'mobile_money', '+22890000020', 'k-min') $q$, 'sous le minimum');
select pg_temp.expect_error($q$ select private.request_withdrawal('00000000-0000-0000-0000-00000000000e', 999999, 'mobile_money', '+22890000020', 'k-big') $q$, 'solde insuffisant');
select pg_temp.expect_error($q$ select private.request_withdrawal('00000000-0000-0000-0000-00000000000e', 1000, 'mobile_money', '90000020', 'k-num') $q$, 'numéro sans indicatif');
select pg_temp.expect_error($q$ select private.request_withdrawal('00000000-0000-0000-0000-00000000000e', 1000, 'crypto', '+22890000020', 'k-meth') $q$, 'méthode inconnue');
select pg_temp.expect_error($q$
  select private.process_withdrawal((select id from public.withdrawals where user_id = '00000000-0000-0000-0000-00000000000e' limit 1),
                                    '00000000-0000-0000-0000-00000000000e', 'approve') $q$, 'joueur traite son propre retrait');

-- Frais : 2 % → 1 000 demandés, 20 de frais, 980 versés ; les frais vont à HOUSE
update public.app_settings set value = '2' where key = 'withdrawal.fee_percent';
do $$
declare
  w public.withdrawals;
  v_house_before bigint := (select balance from public.wallets where id = private.system_wallet('HOUSE', 'XOF'));
begin
  w := private.request_withdrawal('00000000-0000-0000-0000-00000000000e', 1000, 'mobile_money', '+22890000020', 'wdr-key-fee');
  assert w.fee = 20 and w.net_amount = 980, 'calcul des frais';
  perform private.process_withdrawal(w.id, '00000000-0000-0000-0000-00000000000d', 'approve');
  perform private.process_withdrawal(w.id, '00000000-0000-0000-0000-00000000000d', 'pay');
  assert (select balance from public.wallets where id = private.system_wallet('HOUSE', 'XOF')) = v_house_before + 20, 'frais à HOUSE';
  raise notice 'OK  frais de retrait';
end $$;
update public.app_settings set value = '0' where key = 'withdrawal.fee_percent';

-- RLS : le joueur voit ses retraits, ne peut rien écrire ni appeler les fonctions
begin;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000e';
do $$
begin
  assert (select count(*) from public.withdrawals) = 5, 'voit ses 5 retraits';
  assert (select count(*) from public.withdrawals where user_id <> auth.uid()) = 0, 'seulement les siens';
  raise notice 'OK  RLS retraits';
end $$;
select pg_temp.expect_error($q$ update public.withdrawals set status = 'paid' $q$, 'joueur modifie un retrait');
select pg_temp.expect_error($q$ select private.request_withdrawal(auth.uid(), 1000, 'mobile_money', '+22890000020', 'x') $q$, 'joueur appelle request_withdrawal');
rollback;

do $$ begin raise notice 'TESTS RETRAITS PASSÉS'; end $$;
