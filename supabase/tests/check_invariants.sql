-- Contrôles d'intégrité de l'argent et des jeux, sur TOUTES les données présentes.
-- Lancé à la fin des tests SQL, puis à nouveau après les tests du backend
-- (backend/tests/test_zz_invariants.py). Peut aussi être lancé en lecture seule
-- sur la vraie base Supabase pour un audit : il ne modifie rien.
\set ON_ERROR_STOP 1

do $$
declare
  v_errors text[] := '{}';
  r record;
begin
  -- 1. Chaque journal est équilibré (somme des lignes = 0, par devise)
  for r in
    select j.reference, w.currency_code, sum(t.amount) as total
    from public.ledger_journals j
    join public.wallet_transactions t on t.journal_id = j.id
    join public.wallets w on w.id = t.wallet_id
    group by j.reference, w.currency_code having sum(t.amount) <> 0
  loop
    v_errors := v_errors || format('journal %s déséquilibré en %s : %s', r.reference, r.currency_code, r.total);
  end loop;

  -- 2. Un journal sans ligne n'a pas de sens
  for r in select j.reference from public.ledger_journals j
            where not exists (select 1 from public.wallet_transactions t where t.journal_id = j.id) loop
    v_errors := v_errors || format('journal %s sans mouvement', r.reference);
  end loop;

  -- 3. Le solde (cache) de chaque portefeuille = somme de ses mouvements
  for r in
    select w.id, coalesce(w.system_code, w.user_id::text) as owner, w.balance, coalesce(sum(t.amount), 0) as ledger
    from public.wallets w left join public.wallet_transactions t on t.wallet_id = w.id
    group by w.id having w.balance <> coalesce(sum(t.amount), 0)
  loop
    v_errors := v_errors || format('portefeuille %s : solde %s, ledger %s', r.owner, r.balance, r.ledger);
  end loop;

  -- 4. Les mouvements d'un portefeuille s'enchaînent sans trou (solde avant = solde après précédent)
  for r in
    select wallet_id, id, balance_before, prev_after from (
      select wallet_id, id, balance_before,
             lag(balance_after, 1, 0::bigint) over (partition by wallet_id order by id) as prev_after
      from public.wallet_transactions) s
    where balance_before <> prev_after limit 20
  loop
    v_errors := v_errors || format('mouvement %s : solde avant %s ≠ %s', r.id, r.balance_before, r.prev_after);
  end loop;

  -- 5. Aucun joueur en négatif
  for r in select user_id, balance from public.wallets where owner_type = 'user' and balance < 0 loop
    v_errors := v_errors || format('joueur %s en négatif : %s', r.user_id, r.balance);
  end loop;

  -- 6. Les montants des retraits en cours sont exactement ceux bloqués
  for r in
    select w.currency_code, w.balance,
           coalesce((select sum(d.amount) from public.withdrawals d
                      where d.currency_code = w.currency_code and d.hold_journal_id is not null
                        and d.status in ('pending', 'under_review', 'approved')), 0) as open_amount
    from public.wallets w where w.system_code = 'WITHDRAWAL_HOLD'
  loop
    if r.balance <> r.open_amount then
      v_errors := v_errors || format('WITHDRAWAL_HOLD %s : %s bloqués pour %s de retraits en cours',
                                     r.currency_code, r.balance, r.open_amount);
    end if;
  end loop;

  -- 7. Paris : mise débitée, gain cohérent, pas de pari en attente sur un tirage terminé
  for r in select reference from public.bets where stake_journal_id is null loop
    v_errors := v_errors || format('pari %s sans débit de mise', r.reference);
  end loop;
  for r in select reference from public.bets
            where (status = 'won') <> (payout_journal_id is not null) or (status <> 'won' and actual_payout <> 0) loop
    v_errors := v_errors || format('pari %s : statut et gain incohérents', r.reference);
  end loop;
  for r in select b.reference, g.status from public.bets b join public.game_rounds g on g.id = b.round_id
            where b.status = 'pending' and g.status in ('settled', 'cancelled') loop
    v_errors := v_errors || format('pari %s en attente sur un tirage %s', r.reference, r.status);
  end loop;
  for r in select b.reference from public.bets b join public.game_rounds g on g.id = b.round_id
            where b.status in ('won', 'lost') and g.result is null loop
    v_errors := v_errors || format('pari %s réglé sans résultat de tirage', r.reference);
  end loop;

  -- 8. Pari mutuel : la plateforme ne redistribue jamais plus que la cagnotte
  for r in
    select g.id, sum(b.stake) as stakes, sum(b.actual_payout) as paid
    from public.bets b join public.game_rounds g on g.id = b.round_id
    where b.game_type_code = 'FRUITS' and g.status = 'settled'
    group by g.id having sum(b.actual_payout) > sum(b.stake)
  loop
    v_errors := v_errors || format('tirage Fruits %s : %s versés pour %s misés', r.id, r.paid, r.stakes);
  end loop;

  -- 9. Tirages publiés : graine révélée et résultat présent
  for r in select id from public.game_rounds
            where status in ('published', 'settled') and (result is null or revealed_seed is null) loop
    v_errors := v_errors || format('tirage %s publié sans résultat ou sans graine révélée', r.id);
  end loop;

  -- 10. Dépôts validés crédités une fois ; retraits payés sortis une fois
  for r in select reference from public.deposits where status = 'approved' and journal_id is null loop
    v_errors := v_errors || format('dépôt %s validé sans écriture', r.reference);
  end loop;
  for r in select reference from public.withdrawals where status = 'paid' and payout_journal_id is null loop
    v_errors := v_errors || format('retrait %s payé sans écriture', r.reference);
  end loop;

  if cardinality(v_errors) > 0 then
    raise exception 'INTÉGRITÉ : % anomalie(s)%', cardinality(v_errors), E'\n  ' || array_to_string(v_errors, E'\n  ');
  end if;
  raise notice 'INTÉGRITÉ OK : % journaux, % portefeuilles, % paris, % tirages contrôlés',
    (select count(*) from public.ledger_journals), (select count(*) from public.wallets),
    (select count(*) from public.bets), (select count(*) from public.game_rounds);
end $$;
