-- Tests de la prise de paris et du règlement (phase 6)
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

-- F = joueur crédité de 10 000 F
insert into auth.users (id, email, raw_user_meta_data) values
 ('00000000-0000-0000-0000-00000000000f', 'esi@example.com',
  '{"first_name":"Esi","last_name":"M","phone":"+22890000030","country_code":"TG","language_code":"fr","currency_code":"XOF","accept_terms":true,"accept_privacy":true}');
select private.admin_credit((select public_id from public.profiles where id = '00000000-0000-0000-0000-00000000000f'),
  '00000000-0000-0000-0000-00000000000d', 10000, 'Crédit de test paris', 'test-bet-credit-1');

-- Tours de test ouverts (horaires réels, pour que les mises soient acceptées)
insert into public.game_rounds (id, game_code, round_number, opens_at, closes_at, draw_at) values
 ('00000000-0000-0000-0000-0000000000a1', 'FRUITS', 9001, now() - interval '10 min', now() + interval '50 min', now() + interval '51 min'),
 ('00000000-0000-0000-0000-0000000000a2', 'LONATO', 9002, now() - interval '10 min', now() + interval '50 min', now() + interval '52 min'),
 ('00000000-0000-0000-0000-0000000000a3', 'LONATO', 9003, now() - interval '10 min', now() + interval '50 min', now() + interval '53 min');
select private.open_round(id) from public.game_rounds where round_number in (9001, 9002, 9003);

create or replace function pg_temp.balance() returns bigint language sql as
  $$ select balance from public.wallets where user_id = '00000000-0000-0000-0000-00000000000f' $$;

do $$
declare
  v_user  constant uuid := '00000000-0000-0000-0000-00000000000f';
  v_round constant uuid := '00000000-0000-0000-0000-0000000000a1';
  v_house_before bigint := (select balance from public.wallets where id = private.system_wallet('HOUSE', 'XOF'));
  b  public.bets;
  b2 public.bets;
  f  text;
  i  int := 0;
  s  jsonb;
begin
  -- 1 pari « 1 fruit » sur chacun des 20 fruits : exactement un gagne (x50)
  for f in select code from public.game_symbols where game_code = 'FRUITS' order by code loop
    i := i + 1;
    b := private.place_bet(v_user, v_round, 'FRUITS', array[lower(f)], 50, 'fruit-' || f);
    assert b.status = 'pending' and b.potential_payout = 0 and b.odds_snapshot = '{"1": 50.0000}', 'poids figé 50, gain inconnu (mutuel) : ' || b.odds_snapshot;
  end loop;
  assert pg_temp.balance() = 10000 - 20 * 50, 'mises débitées';

  -- Double envoi du même ticket : pas de second débit
  b2 := private.place_bet(v_user, v_round, 'FRUITS', array['POMME'], 50, 'fruit-POMME');
  assert b2.id = (select id from public.bets where idempotency_key = 'fruit-POMME'), 'idempotence';
  assert pg_temp.balance() = 9000, 'pas de double débit';

  -- 20 fruits → x1 (toujours gagnant, mise rendue)
  b := private.place_bet(v_user, v_round, 'FRUITS',
         array(select code from public.game_symbols where game_code = 'FRUITS'), 100, 'fruit-all');
  assert b.selection_count = 20 and b.odds_snapshot = '{"1": 1.0000}', '20 fruits poids 1';
  s := private.pool_state(v_round);
  assert (s->>'total_stakes')::bigint = 1100 and (s->>'bet_count')::int = 21, 'cagnotte : ' || s;
  assert (s->'weights'->>'KIWI')::numeric = 2500 + 100, 'poids engagé sur un fruit : ' || s;
  assert (select count(*) from public.bet_items where bet_id = b.id) = 20, 'sélections enregistrées';
  assert exists (select 1 from public.notifications where user_id = v_user and type = 'bet_placed'), 'notification pari';
  raise notice 'OK  prise de paris Fruits (mutuel), poids figés, cagnotte, idempotence';

  -- Tirage et règlement
  update public.game_rounds set status = 'closed' where id = v_round;
  perform private.draw_round(v_round);
  assert (select status from public.game_rounds where id = v_round) = 'settled', 'tour réglé';
  assert (select count(*) from public.bets where round_id = v_round and status = 'won') = 2, '1 fruit gagnant + 20 fruits';
  assert (select count(*) from public.bets where round_id = v_round and status = 'lost') = 19, '19 perdants';
  -- Cagnotte 1 100 F, 10 % de commission → 990 F partagés au prorata mise × poids :
  -- gagnant 1 fruit 50 × 50 = 2 500, gagnant 20 fruits 100 × 1 = 100.
  assert (select bool_and(x.actual_payout = 951 and (select value from public.bet_items where bet_id = x.id)
                          = (select result->>'fruit' from public.game_rounds where id = v_round))
            from public.bets x where x.round_id = v_round and x.status = 'won' and x.selection_count = 1), 'le bon fruit gagne';
  assert (select actual_payout from public.bets where idempotency_key = 'fruit-all') = 38, 'part du 20 fruits';
  assert pg_temp.balance() = 10000 - 1100 + 951 + 38, 'gains crédités : ' || pg_temp.balance();
  assert (select balance from public.wallets where id = private.system_wallet('HOUSE', 'XOF')) = v_house_before + 1100 - 989,
         'HOUSE : jamais de perte, commission + arrondis gardés';
  assert (select count(*) from public.bet_results where round_id = v_round) = 21, 'résultat par pari';
  assert exists (select 1 from public.notifications where user_id = v_user and type = 'bet_won'), 'notification gain';

  -- Rejouer le règlement ne paie pas deux fois
  s := private.settle_round(v_round);
  assert s ? 'skipped' and pg_temp.balance() = 9889, 'règlement unique';
  raise notice 'OK  tirage, règlement, gains, aucun double paiement';
end $$;

-- Refus ------------------------------------------------------------------------------------
select pg_temp.expect_error($q$ select private.place_bet('00000000-0000-0000-0000-00000000000f', '00000000-0000-0000-0000-0000000000a1', 'FRUITS', array['POMME'], 50, 'k-closed') $q$, 'pari sur un tour réglé');
select pg_temp.expect_error($q$ select private.place_bet('00000000-0000-0000-0000-00000000000f', '00000000-0000-0000-0000-0000000000a2', 'FRUITS', array['POMME'], 50, 'k-type') $q$, 'Fruits sur un tour Lonato');
select pg_temp.expect_error($q$ select private.place_bet('00000000-0000-0000-0000-00000000000f', '00000000-0000-0000-0000-0000000000a2', 'CHOX', array['07'], 49, 'k-min') $q$, 'mise sous 50 F');
select pg_temp.expect_error($q$ select private.place_bet('00000000-0000-0000-0000-00000000000f', '00000000-0000-0000-0000-0000000000a2', 'CHOX', array['07'], 999999, 'k-bal') $q$, 'solde insuffisant');
select pg_temp.expect_error($q$ select private.place_bet('00000000-0000-0000-0000-00000000000f', '00000000-0000-0000-0000-0000000000a2', 'PERME', array['01','02','03','04'], 50, 'k-norule') $q$, 'PERME 4 numéros sans cote publiée');
select pg_temp.expect_error($q$ select private.place_bet('00000000-0000-0000-0000-00000000000f', '00000000-0000-0000-0000-0000000000a2', 'PERME', array['01','1'], 50, 'k-dup') $q$, 'numéro en double');
select pg_temp.expect_error($q$ select private.place_bet('00000000-0000-0000-0000-00000000000f', '00000000-0000-0000-0000-0000000000a2', 'CHOX', array['91'], 50, 'k-range') $q$, 'numéro hors 01–90');

-- Lonato : calcul des gains pour chaque type (résultats imposés) ---------------------------
do $$
declare
  v_user constant uuid := '00000000-0000-0000-0000-00000000000f';
  r2 constant uuid := '00000000-0000-0000-0000-0000000000a2';
  perme public.bets; nape public.bets; chox public.bets; perme2 public.bets;
begin
  perme  := private.place_bet(v_user, r2, 'PERME', array['1','2','3'], 100, 'lon-perme3');
  perme2 := private.place_bet(v_user, r2, 'PERME', array['01','02'], 100, 'lon-perme2');
  nape   := private.place_bet(v_user, r2, 'NAPE',  array['01','02','03'], 100, 'lon-nape3');
  chox   := private.place_bet(v_user, r2, 'CHOX',  array['07'], 100, 'lon-chox');
  assert perme.potential_payout = 90000 and nape.potential_payout = 270000 and chox.potential_payout = 1000, 'gains potentiels';
  assert (select array_agg(value order by value) from public.bet_items where bet_id = perme.id) = array['01','02','03'], 'numéros normalisés';

  assert (private.evaluate_bet(perme, '{"numbers":[1,2,3,40,50]}')).multiplier = 900, 'PERME 3/3 x900';
  assert (private.evaluate_bet(perme, '{"numbers":[1,2,30,40,50]}')).multiplier = 100, 'PERME 3/2 x100';
  assert (private.evaluate_bet(perme, '{"numbers":[1,20,30,40,50]}')).multiplier = 0, 'PERME 3/1 perdu';
  assert (private.evaluate_bet(perme2, '{"numbers":[2,1,30,40,50]}')).multiplier = 300, 'PERME 2/2 x300';
  assert (private.evaluate_bet(nape, '{"numbers":[3,2,1,40,50]}')).multiplier = 2700, 'NAPE 3 x2700';
  assert (private.evaluate_bet(nape, '{"numbers":[1,2,30,40,50]}')).multiplier = 0, 'NAPE incomplet perdu';
  assert (private.evaluate_bet(chox, '{"numbers":[7,20,30,40,50]}')).multiplier = 10, 'CHOX x10';
  assert (private.evaluate_bet(chox, '{"numbers":[8,20,30,40,50]}')).multiplier = 0, 'CHOX perdu';
  raise notice 'OK  gains PERME, NAPE, CHOX';
end $$;

-- Annulation d'un tour avec paris : remboursement intégral ----------------------------------
do $$
declare
  v_user constant uuid := '00000000-0000-0000-0000-00000000000f';
  r3 constant uuid := '00000000-0000-0000-0000-0000000000a3';
  v_before bigint;
begin
  perform private.place_bet(v_user, r3, 'CHOX', array['10'], 200, 'lon-cancel-1');
  perform private.place_bet(v_user, r3, 'PERME', array['10','11'], 300, 'lon-cancel-2');
  v_before := pg_temp.balance();
  perform private.cancel_round(r3, '00000000-0000-0000-0000-00000000000d', 'Incident technique');
  assert pg_temp.balance() = v_before + 500, 'mises remboursées';
  assert (select count(*) from public.bets where round_id = r3 and status = 'refunded') = 2, 'paris remboursés';
  raise notice 'OK  annulation d''un tour avec paris : remboursement';
end $$;

-- Nouvelle version des cotes : les paris déjà placés gardent les leurs ------------------------
begin;
insert into public.game_rounds (id, game_code, round_number, opens_at, closes_at, draw_at) values
 ('00000000-0000-0000-0000-0000000000a4', 'FRUITS', 9004, now() - interval '10 min', now() + interval '50 min', now() + interval '54 min');
select private.open_round('00000000-0000-0000-0000-0000000000a4');
do $$
declare old_bet public.bets; new_bet public.bets;
begin
  old_bet := private.place_bet('00000000-0000-0000-0000-00000000000f', '00000000-0000-0000-0000-0000000000a4', 'FRUITS', array['KIWI'], 50, 'v-old');
  insert into public.payout_rules (game_type_code, version, selection_count, match_count, multiplier, condition, effective_from)
  values ('FRUITS', 3, 1, 1, 18, 'winner_in_selection', now() - interval '1 second');
  new_bet := private.place_bet('00000000-0000-0000-0000-00000000000f', '00000000-0000-0000-0000-0000000000a4', 'FRUITS', array['KIWI'], 50, 'v-new');
  assert old_bet.payout_rule_version = 2 and old_bet.odds_snapshot = '{"1": 50.0000}', 'ancien pari au poids 50';
  assert new_bet.payout_rule_version = 3 and new_bet.odds_snapshot = '{"1": 18}', 'nouveau pari au poids 18';
  assert private.playable_odds('FRUITS') = '{"1": {"1": 18}}', 'cotes affichées : ' || private.playable_odds('FRUITS');
  raise notice 'OK  versions de cotes : un pari placé garde ses cotes';
end $$;
rollback;

-- Pari mutuel : sur 200 tours aléatoires avec des paris variés, la plateforme ne perd jamais
begin;
do $$
declare
  v_user constant uuid := '00000000-0000-0000-0000-00000000000f';
  v_counts constant int[] := array[1, 2, 3, 4, 5, 6, 7, 8, 10, 15, 20];
  v_rid uuid; v_stakes bigint; v_min_margin numeric := 1e9; k int; n int;
begin
  perform private.admin_credit((select public_id from public.profiles where id = v_user),
    '00000000-0000-0000-0000-00000000000d', 50000000, 'Simulation', 'sim-credit');
  for t in 1..200 loop
    v_rid := gen_random_uuid();
    insert into public.game_rounds (id, game_code, round_number, opens_at, closes_at, draw_at)
    values (v_rid, 'FRUITS', 10000 + t, now() - interval '1 min', now() + make_interval(days => 400 + t),
            now() + make_interval(days => 400 + t, mins => 1));
    perform private.open_round(v_rid);
    v_stakes := 0;
    for j in 1..(1 + floor(random() * 12))::int loop
      k := v_counts[1 + floor(random() * 11)::int];
      n := (50 + floor(random() * 2000))::int;
      perform private.place_bet(v_user, v_rid, 'FRUITS',
        array(select code from public.game_symbols where game_code = 'FRUITS' order by random() limit k), n, 'sim-' || t || '-' || j);
      v_stakes := v_stakes + n;
    end loop;
    update public.game_rounds set status = 'closed' where id = v_rid;
    perform private.draw_round(v_rid);
    assert (select coalesce(sum(actual_payout), 0) from public.bets where round_id = v_rid) <= v_stakes * 0.9,
           format('tour %s : plus de 90 %% reversés', t);
    v_min_margin := least(v_min_margin,
      v_stakes - (select coalesce(sum(actual_payout), 0) from public.bets where round_id = v_rid));
  end loop;
  assert v_min_margin >= 0, 'jamais de perte';
  raise notice 'OK  pari mutuel : 200 tours simulés, aucune perte (marge minimale % F)', v_min_margin;
end $$;
rollback;

-- RLS : le joueur voit ses paris, pas ceux des autres, ne peut rien écrire
begin;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
do $$ begin
  assert (select count(*) from public.bets) = 0, 'A ne voit pas les paris de F';
  assert (select count(*) from public.bet_items) = 0 and (select count(*) from public.bet_results) = 0;
  raise notice 'OK  RLS paris';
end $$;
select pg_temp.expect_error($q$ select private.place_bet(auth.uid(), '00000000-0000-0000-0000-0000000000a2', 'CHOX', array['07'], 50, 'x') $q$, 'joueur appelle place_bet');
rollback;

do $$ begin raise notice 'TESTS PARIS PASSÉS'; end $$;
