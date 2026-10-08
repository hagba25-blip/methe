-- Tests d'intégrité du schéma (exécutés par tests/run_local.sh)
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

-- 1. Inscription ----------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data) values
 ('00000000-0000-0000-0000-00000000000a', 'hubert@example.com',
  '{"first_name":"Hubert","last_name":"K","phone":"+22890000001","country_code":"TG","language_code":"fr","currency_code":"XOF","accept_terms":true,"accept_privacy":true}'),
 ('00000000-0000-0000-0000-00000000000b', 'awa@example.com',
  '{"first_name":"Awa","last_name":"D","phone":"+22890000002","country_code":"TG","language_code":"fr","currency_code":"XOF","accept_terms":true,"accept_privacy":true}');

do $$
declare p record;
begin
  for p in select * from public.profiles loop
    assert p.public_id ~ '^6[0-9]{9}$', 'ID client invalide';
    assert exists (select 1 from public.wallets w where w.user_id = p.id and w.currency_code = 'XOF'), 'portefeuille manquant';
  end loop;
  raise notice 'OK  inscription : profils + ID 6xxxxxxxxx + portefeuilles';
end $$;

select pg_temp.expect_error($q$
  insert into auth.users (email, raw_user_meta_data) values ('x@example.com',
   '{"first_name":"X","last_name":"Y","phone":"+22890000003","country_code":"TG","language_code":"fr","currency_code":"XOF","accept_terms":false,"accept_privacy":true}')
$q$, 'inscription sans CGU');

select pg_temp.expect_error($q$
  insert into auth.users (email, raw_user_meta_data) values ('y@example.com',
   '{"first_name":"X","last_name":"Y","phone":"+22890000004","country_code":"ZZ","language_code":"fr","currency_code":"XOF","accept_terms":true,"accept_privacy":true}')
$q$, 'pays inconnu');

select pg_temp.expect_error($q$
  update public.profiles set public_id = '6000000000' where id = '00000000-0000-0000-0000-00000000000a'
$q$, 'modification de l''ID client');

-- 2. Ledger -----------------------------------------------------------------------
do $$
declare
  v_user  uuid := (select id from public.wallets where user_id = '00000000-0000-0000-0000-00000000000a');
  v_tres  uuid := (select id from public.wallets where system_code = 'TREASURY' and currency_code = 'XOF');
  j1 uuid; j2 uuid;
begin
  j1 := private.post_journal('deposit', 'test-deposit-0001',
          jsonb_build_array(jsonb_build_object('wallet_id', v_tres, 'amount', -10000),
                            jsonb_build_object('wallet_id', v_user, 'amount',  10000)), 'admin');
  j2 := private.post_journal('deposit', 'test-deposit-0001',
          jsonb_build_array(jsonb_build_object('wallet_id', v_tres, 'amount', -10000),
                            jsonb_build_object('wallet_id', v_user, 'amount',  10000)), 'admin');
  assert j1 = j2, 'idempotence';
  assert (select balance from public.wallets where id = v_user) = 10000, 'solde après dépôt';
  assert (select balance_before || '>' || balance_after from public.wallet_transactions
          where wallet_id = v_user) = '0>10000', 'avant/après';
  raise notice 'OK  ledger : crédit, idempotence, solde avant/après';
end $$;

select pg_temp.expect_error(format($q$
  select private.post_journal('bet_stake', 'test-overdraft-01', jsonb_build_array(
    jsonb_build_object('wallet_id', %L::uuid, 'amount', -999999),
    jsonb_build_object('wallet_id', (select id from public.wallets where system_code='HOUSE'), 'amount', 999999)), 'api')
$q$, (select id from public.wallets where user_id = '00000000-0000-0000-0000-00000000000a')), 'solde insuffisant');

select pg_temp.expect_error($q$
  select private.post_journal('adjustment', 'test-unbalanced-1', jsonb_build_array(
    jsonb_build_object('wallet_id', (select id from public.wallets where system_code='HOUSE'), 'amount', 5),
    jsonb_build_object('wallet_id', (select id from public.wallets where system_code='TREASURY' and currency_code='XOF'), 'amount', -4)), 'api')
$q$, 'journal déséquilibré');

select pg_temp.expect_error($q$ update public.wallets set balance = 1 where system_code = 'HOUSE' $q$,
  'modification directe du solde (rôle backend)');
select pg_temp.expect_error($q$ delete from public.wallet_transactions $q$, 'suppression du ledger');

-- 3. RLS côté application (rôle authenticated) -------------------------------------
begin;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
do $$
begin
  assert (select count(*) from public.profiles) = 1, 'voit seulement son profil';
  assert (select count(*) from public.wallets) = 1, 'voit seulement son portefeuille';
  assert (select count(*) from public.wallet_transactions) = 1, 'voit seulement ses transactions';
  assert (select count(*) from public.ledger_journals) = 0, 'pas d''accès aux journaux';
  assert (select count(*) from public.payout_rules) > 0, 'règles publiques';
  raise notice 'OK  RLS lecture';
end $$;
select pg_temp.expect_error($q$ update public.wallets set balance = 99999999 $q$, 'utilisateur modifie son solde');
select pg_temp.expect_error($q$ update public.profiles set status = 'active' $q$, 'utilisateur modifie son statut');
select pg_temp.expect_error($q$ insert into public.bets (user_id) values (auth.uid()) $q$, 'utilisateur crée un pari directement');
select pg_temp.expect_error($q$ update public.payout_rules set multiplier = 9999 $q$, 'utilisateur modifie une cote');
select pg_temp.expect_error($q$ select private.post_journal('deposit','hack-hack-1','[]'::jsonb,'x') $q$, 'utilisateur appelle post_journal');
update public.profiles set first_name = 'Hubert' where id = auth.uid();
rollback;

-- 4. Tirages et paris ------------------------------------------------------------
insert into public.game_rounds (id, game_code, round_number, opens_at, closes_at, draw_at, status, commitment_hash)
values ('00000000-0000-0000-0000-0000000000f1', 'FRUITS', 1, now() - interval '1 hour', now() - interval '1 minute', now(),
        'closed', repeat('a', 64));

select pg_temp.expect_error(format($q$
  insert into public.bets (user_id, wallet_id, round_id, game_code, game_type_code, selection_count, stake,
    currency_code, payout_rule_version, odds_snapshot, potential_payout, idempotency_key)
  values ('00000000-0000-0000-0000-00000000000a', %L, '00000000-0000-0000-0000-0000000000f1', 'FRUITS', 'FRUITS',
    1, 500, 'XOF', 1, '{}', 25000, 'k1')
$q$, (select id from public.wallets where user_id = '00000000-0000-0000-0000-00000000000a')), 'pari après fermeture');

update public.game_rounds set status = 'drawn', result = '{"fruit":"ORANGE"}', drawn_at = now()
 where id = '00000000-0000-0000-0000-0000000000f1';
select pg_temp.expect_error($q$
  update public.game_rounds set result = '{"fruit":"POMME"}' where id = '00000000-0000-0000-0000-0000000000f1'
$q$, 'modification d''un résultat');
select pg_temp.expect_error($q$
  update public.game_rounds set status = 'open' where id = '00000000-0000-0000-0000-0000000000f1'
$q$, 'retour arrière de statut');
select pg_temp.expect_error($q$
  update public.payout_rules set multiplier = 60 where game_type_code = 'FRUITS' and selection_count = 1
$q$, 'modification d''une règle publiée (backend)');

do $$ begin raise notice 'TOUS LES TESTS SONT PASSÉS'; end $$;
