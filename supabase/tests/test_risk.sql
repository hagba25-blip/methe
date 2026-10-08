-- Tests anti-fraude (phase 10) : rafale de paris, alertes, statut des comptes
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

begin;
-- G = joueur testé, H = autre joueur (puis membre support). D = admin finance.
insert into auth.users (id, email, raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000071', 'risk-g@example.com',
  '{"first_name":"Gédéon","last_name":"R","phone":"+22890000071","country_code":"TG","language_code":"fr","currency_code":"XOF","accept_terms":true,"accept_privacy":true}'),
 ('00000000-0000-0000-0000-000000000072', 'risk-h@example.com',
  '{"first_name":"Hawa","last_name":"R","phone":"+22890000072","country_code":"TG","language_code":"fr","currency_code":"XOF","accept_terms":true,"accept_privacy":true}');
select private.admin_credit('' || (select public_id from public.profiles where id = '00000000-0000-0000-0000-000000000071'),
  '00000000-0000-0000-0000-00000000000d', 5000, 'Crédit de test anti-fraude', 'risk-credit-g');
insert into public.game_rounds (id, game_code, round_number, opens_at, closes_at, draw_at) values
 ('00000000-0000-0000-0000-0000000000b1', 'FRUITS', 9101, now() - interval '10 min', now() + interval '50 min', now() + interval '1 day 2 min');
select private.open_round('00000000-0000-0000-0000-0000000000b1');

-- 1. Rafale de paris refusée au-delà de la limite
update public.app_settings set value = '3' where key = 'betting.max_bets_per_minute';
select private.place_bet('00000000-0000-0000-0000-000000000071', '00000000-0000-0000-0000-0000000000b1', 'FRUITS', array['POMME'], 50, 'risk-b1');
select private.place_bet('00000000-0000-0000-0000-000000000071', '00000000-0000-0000-0000-0000000000b1', 'FRUITS', array['POIRE'], 50, 'risk-b2');
select private.place_bet('00000000-0000-0000-0000-000000000071', '00000000-0000-0000-0000-0000000000b1', 'FRUITS',
  array(select code from public.game_symbols where game_code = 'FRUITS'), 100, 'risk-b3');
select pg_temp.expect_error($q$ select private.place_bet('00000000-0000-0000-0000-000000000071', '00000000-0000-0000-0000-0000000000b1', 'FRUITS', array['KIWI'], 50, 'risk-b4') $q$,
  '4e pari dans la minute');

-- 2. Gros gain : alerte levée au règlement (seuil abaissé pour le test)
update public.app_settings set value = '1' where key = 'risk.big_win_amount';
update public.game_rounds set status = 'closed' where id = '00000000-0000-0000-0000-0000000000b1';
select private.draw_round('00000000-0000-0000-0000-0000000000b1');
do $$ begin
  assert (select count(*) from public.risk_events
           where user_id = '00000000-0000-0000-0000-000000000071' and kind = 'big_win') >= 1,
         'au moins une alerte gros gain (le pari sur 20 fruits gagne toujours)';
  raise notice 'OK  alerte gros gain';
end $$;

-- 3. Retrait juste après un dépôt, sans jouer, vers le numéro d'un autre compte
do $$
declare v_dep public.deposits; v_wdr public.withdrawals;
begin
  v_dep := private.request_deposit('00000000-0000-0000-0000-000000000071',
             (select id from public.agents where is_active and is_available limit 1), 20000);
  perform private.approve_deposit(v_dep.id, '00000000-0000-0000-0000-00000000000d');
  v_wdr := private.request_withdrawal('00000000-0000-0000-0000-000000000071', 15000, 'mobile_money', '+228 9000 0072', 'risk-w1');
  assert (select array_agg(kind order by kind) from public.risk_events
           where reference = v_wdr.reference) = array['low_turnover', 'quick_withdrawal', 'shared_payout_account'],
         'trois alertes sur le retrait';
  assert (select details->'other_accounts' from public.risk_events
           where reference = v_wdr.reference and kind = 'shared_payout_account')
         = to_jsonb(array[(select public_id::text from public.profiles where id = '00000000-0000-0000-0000-000000000072')]),
         'le compte qui possède ce numéro est cité';
  assert v_wdr.status = 'pending', 'le retrait reste à traiter par un humain';
  perform private.raise_risk('00000000-0000-0000-0000-000000000071', 'quick_withdrawal', 2, v_wdr.reference, '{}');
  assert (select count(*) from public.risk_events where reference = v_wdr.reference and kind = 'quick_withdrawal') = 1,
         'pas de doublon tant que l''alerte est ouverte';
  raise notice 'OK  alertes retrait (numéro partagé, mises trop faibles, retrait rapide)';
end $$;

-- Un joueur qui a misé au moins ses dépôts ne déclenche pas « mises trop faibles »
do $$
declare v_wdr public.withdrawals;
begin
  update public.app_settings set value = '1' where key = 'risk.min_turnover_percent';
  perform private.cancel_withdrawal((select id from public.withdrawals where idempotency_key = 'risk-w1'),
                                    '00000000-0000-0000-0000-000000000071');
  v_wdr := private.request_withdrawal('00000000-0000-0000-0000-000000000071', 1000, 'mobile_money', '+22890000071', 'risk-w2');
  assert not exists (select 1 from public.risk_events where reference = v_wdr.reference
                       and kind in ('low_turnover', 'shared_payout_account')), 'son propre numéro, mises suffisantes';
  raise notice 'OK  aucune alerte injustifiée';
end $$;

-- 4. Statut du compte
select pg_temp.expect_error($q$ select private.set_account_status('' || (select public_id from public.profiles where id = '00000000-0000-0000-0000-000000000071'), '00000000-0000-0000-0000-00000000000d', 'suspended', '') $q$,
  'motif obligatoire');
select pg_temp.expect_error($q$ select private.set_account_status('' || (select public_id from public.profiles where id = '00000000-0000-0000-0000-00000000000d'), '00000000-0000-0000-0000-00000000000d', 'blocked', 'test') $q$,
  'son propre compte');
select private.grant_staff_role('risk-h@example.com', 'support');
select pg_temp.expect_error($q$ select private.set_account_status('' || (select public_id from public.profiles where id = '00000000-0000-0000-0000-000000000072'), '00000000-0000-0000-0000-00000000000d', 'blocked', 'test') $q$,
  'membre de l''équipe sans être super admin');
do $$
declare v_pid text := (select public_id from public.profiles where id = '00000000-0000-0000-0000-000000000071');
begin
  perform private.set_account_status(v_pid, '00000000-0000-0000-0000-00000000000d', 'suspended', 'Vérification en cours');
  assert (select status from public.profiles where public_id = v_pid) = 'suspended';
  assert not (select is_frozen from public.wallets where user_id = '00000000-0000-0000-0000-000000000071');
  perform private.set_account_status(v_pid, '00000000-0000-0000-0000-00000000000d', 'blocked', 'Fraude confirmée');
  assert (select is_frozen from public.wallets where user_id = '00000000-0000-0000-0000-000000000071'), 'portefeuille gelé';
  assert (select count(*) from public.notifications
           where user_id = '00000000-0000-0000-0000-000000000071' and title = 'Compte bloqué') = 1;
  assert (select count(*) from public.admin_actions where action = 'set_account_status' and target_id = v_pid) = 2;
  raise notice 'OK  suspension puis blocage (portefeuille gelé, joueur prévenu, action tracée)';
end $$;
insert into public.game_rounds (id, game_code, round_number, opens_at, closes_at, draw_at) values
 ('00000000-0000-0000-0000-0000000000b2', 'FRUITS', 9102, now() - interval '10 min', now() + interval '50 min', now() + interval '1 day 3 min');
select private.open_round('00000000-0000-0000-0000-0000000000b2');
update public.app_settings set value = '30' where key = 'betting.max_bets_per_minute';
select pg_temp.expect_error($q$ select private.place_bet('00000000-0000-0000-0000-000000000071', '00000000-0000-0000-0000-0000000000b2', 'FRUITS', array['KIWI'], 50, 'risk-b5') $q$,
  'pari d''un compte bloqué');
do $$ begin
  perform private.set_account_status((select public_id from public.profiles where id = '00000000-0000-0000-0000-000000000071'),
    '00000000-0000-0000-0000-00000000000d', 'active', 'Contrôle terminé');
  assert not (select is_frozen from public.wallets where user_id = '00000000-0000-0000-0000-000000000071'), 'dégelé';
  perform private.place_bet('00000000-0000-0000-0000-000000000071', '00000000-0000-0000-0000-0000000000b2', 'FRUITS', array['KIWI'], 50, 'risk-b6');
  raise notice 'OK  réactivation : le joueur peut de nouveau parier';
end $$;

-- 5. Clôture d'une alerte
select pg_temp.expect_error($q$ select private.resolve_risk_event((select min(id) from public.risk_events where user_id = '00000000-0000-0000-0000-000000000071'), '00000000-0000-0000-0000-00000000000d', '') $q$,
  'clôture sans explication');
do $$
declare v_id bigint := (select min(id) from public.risk_events where user_id = '00000000-0000-0000-0000-000000000071');
begin
  perform private.resolve_risk_event(v_id, '00000000-0000-0000-0000-00000000000d', 'Gain vérifié, tirage conforme');
  assert (select resolved_by from public.risk_events where id = v_id) = '00000000-0000-0000-0000-00000000000d';
  assert exists (select 1 from public.admin_actions where action = 'resolve_risk' and target_id = v_id::text);
  raise notice 'OK  alerte close avec explication et tracée';
end $$;

-- RLS : un joueur ne lit pas les alertes
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000071';
do $$ begin
  assert (select count(*) from public.risk_events) = 0, 'alertes invisibles pour un joueur';
  raise notice 'OK  alertes invisibles pour les joueurs';
end $$;
reset role;
rollback;

do $$ begin raise notice 'TESTS ANTI-FRAUDE PASSÉS'; end $$;
