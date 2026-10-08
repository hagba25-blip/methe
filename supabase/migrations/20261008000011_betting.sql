-- =============================================================================
-- 0011 — Prise de paris, règlement automatique, remboursement
-- =============================================================================
-- Commun à tous les jeux (Fruits maintenant, Lonato ensuite) :
--  * la mise quitte le solde au moment du pari (journal bet_stake → HOUSE) ;
--  * les cotes appliquées sont celles en vigueur au moment du pari, figées dans
--    bets.odds_snapshot : une nouvelle version des règles ne change pas un pari placé ;
--  * une combinaison sans règle de paiement publiée n'est pas jouable ;
--  * au tirage, chaque pari est réglé une seule fois (journal bet_win si gagnant) ;
--  * un tour annulé rembourse intégralement ses paris (journal bet_refund).

insert into public.app_settings (key, value, is_public, description) values
  ('betting.max_stake', 'null', true, 'Mise maximum par pari (null = illimitée)')
on conflict (key) do nothing;

-- Version des règles en vigueur pour un type de jeu ------------------------------
create or replace function private.current_rule_version(p_game_type text, p_at timestamptz default now())
returns int language sql stable security definer set search_path = '' as $$
  select max(version) from public.payout_rules
   where game_type_code = p_game_type and effective_from <= p_at
     and (effective_to is null or effective_to > p_at);
$$;

-- Cotes jouables, pour l'affichage (nombre choisi → {nombre trouvé → multiplicateur})
create or replace function private.playable_odds(p_game_type text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_object_agg(selection_count::text, odds), '{}'::jsonb) from (
    select selection_count, jsonb_object_agg(match_count::text, multiplier) as odds
      from public.payout_rules
     where game_type_code = p_game_type and version = private.current_rule_version(p_game_type)
     group by selection_count) s;
$$;

-- Prise de pari ---------------------------------------------------------------------
create or replace function private.place_bet(
  p_user_id uuid, p_round_id uuid, p_game_type text, p_selections text[], p_stake bigint, p_idempotency_key text)
returns public.bets language plpgsql security definer set search_path = '' as $$
declare
  v_bet      public.bets%rowtype;
  v_profile  public.profiles%rowtype;
  v_wallet   public.wallets%rowtype;
  v_round    public.game_rounds%rowtype;
  v_type     public.game_types%rowtype;
  v_sel      text[];
  v_count    int;
  v_version  int;
  v_odds     jsonb;
  v_best     numeric;
  v_min      bigint;
  v_max      bigint;
  v_journal  uuid;
begin
  select * into v_bet from public.bets where user_id = p_user_id and idempotency_key = p_idempotency_key;
  if found then
    return v_bet;  -- double envoi du même ticket
  end if;

  select * into v_profile from public.profiles where id = p_user_id;
  if not found or v_profile.status <> 'active' then
    raise exception 'Compte bloqué : pari impossible' using errcode = 'P0001';
  end if;

  -- Verrou partagé : le moteur ne peut pas fermer le tour pendant la prise du pari
  select * into v_round from public.game_rounds where id = p_round_id for share;
  if not found then
    raise exception 'Tirage introuvable' using errcode = 'P0002';
  end if;
  if v_round.status <> 'open' or now() >= v_round.closes_at then
    raise exception 'Les mises sont fermées pour ce tirage' using errcode = 'P0001';
  end if;

  select * into v_type from public.game_types where code = p_game_type and is_active;
  if not found or v_type.game_code <> v_round.game_code then
    raise exception 'Type de jeu invalide pour ce tirage' using errcode = 'P0001';
  end if;

  -- Sélections : normalisées (majuscules, numéros sur 2 chiffres), sans doublon, valides
  select array_agg(distinct s order by s) into v_sel from (
    select case when v_round.game_code = 'LONATO' then lpad(trim(x), 2, '0') else upper(trim(x)) end as s
      from unnest(p_selections) x) t;
  v_count := coalesce(array_length(v_sel, 1), 0);
  if v_count <> coalesce(array_length(p_selections, 1), 0) then
    raise exception 'Sélection en double' using errcode = 'P0001';
  end if;
  if v_count not between v_type.min_selection and v_type.max_selection then
    raise exception 'Choisissez entre % et % éléments', v_type.min_selection, v_type.max_selection using errcode = 'P0001';
  end if;
  if v_round.game_code = 'FRUITS' and exists (
       select 1 from unnest(v_sel) s
        where not exists (select 1 from public.game_symbols g where g.game_code = 'FRUITS' and g.code = s)) then
    raise exception 'Fruit inconnu' using errcode = 'P0001';
  end if;
  if v_round.game_code = 'LONATO' and exists (
       select 1 from unnest(v_sel) s where s !~ '^[0-9]{2}$' or s::int not between 1 and 90) then
    raise exception 'Les numéros vont de 01 à 90' using errcode = 'P0001';
  end if;

  -- Cotes figées au moment du pari
  v_version := private.current_rule_version(p_game_type);
  select jsonb_object_agg(match_count::text, multiplier), max(multiplier) into v_odds, v_best
    from public.payout_rules
   where game_type_code = p_game_type and version = v_version and selection_count = v_count;
  if v_odds is null then
    raise exception 'Combinaison non disponible : aucune cote publiée pour % sélection(s)', v_count using errcode = 'P0001';
  end if;

  v_min := greatest(v_type.min_stake, private.setting_bigint('betting.min_stake', 50));
  v_max := least(v_type.max_stake, (select (value #>> '{}')::bigint from public.app_settings
                                     where key = 'betting.max_stake' and jsonb_typeof(value) = 'number'));
  if p_stake < v_min then
    raise exception 'La mise minimum est de %', v_min using errcode = 'P0001';
  end if;
  if v_max is not null and p_stake > v_max then
    raise exception 'La mise maximum est de %', v_max using errcode = 'P0001';
  end if;

  select * into v_wallet from public.wallets
   where user_id = p_user_id and currency_code = v_profile.currency_code for update;
  if v_wallet.is_frozen then
    raise exception 'Portefeuille bloqué' using errcode = 'P0001';
  end if;
  if v_wallet.balance < p_stake then
    raise exception 'Solde insuffisant' using errcode = 'P0001';
  end if;

  insert into public.bets (user_id, wallet_id, round_id, game_code, game_type_code, selection_count, stake,
                           currency_code, payout_rule_version, odds_snapshot, potential_payout, idempotency_key)
  values (p_user_id, v_wallet.id, p_round_id, v_round.game_code, p_game_type, v_count, p_stake,
          v_wallet.currency_code, v_version, v_odds, floor(p_stake * v_best)::bigint, p_idempotency_key)
  returning * into v_bet;
  insert into public.bet_items (bet_id, value) select v_bet.id, unnest(v_sel);

  v_journal := private.post_journal(
    'bet_stake', 'bet-stake:' || v_bet.id,
    jsonb_build_array(
      jsonb_build_object('wallet_id', v_wallet.id, 'amount', -p_stake),
      jsonb_build_object('wallet_id', private.system_wallet('HOUSE', v_wallet.currency_code), 'amount', p_stake)),
    'api', v_bet.id, null, 'Pari ' || v_bet.reference, v_bet.reference);
  update public.bets set stake_journal_id = v_journal where id = v_bet.id returning * into v_bet;

  insert into public.notifications (user_id, type, title, body, data)
  values (p_user_id, 'bet_placed', 'Pari enregistré',
          format('Pari %s : %s %s sur le tirage n° %s.', v_bet.reference, p_stake, v_bet.currency_code, v_round.round_number),
          jsonb_build_object('bet_id', v_bet.id, 'round_id', p_round_id));
  return v_bet;
end $$;

-- Règlement d'un pari ----------------------------------------------------------------
-- Retourne le nombre d'éléments trouvés et le multiplicateur gagné selon les cotes figées.
create or replace function private.evaluate_bet(p_bet public.bets, p_result jsonb, out matched text[], out multiplier numeric)
language plpgsql stable set search_path = '' as $$
declare
  v_winning text[];
  v_cond    text;
  v_count   int;
begin
  v_winning := case
    when p_result ? 'fruit' then array[p_result->>'fruit']
    else array(select lpad(n, 2, '0') from jsonb_array_elements_text(p_result->'numbers') n) end;
  matched := array(select value from public.bet_items where bet_id = p_bet.id and value = any(v_winning) order by value);
  v_count := coalesce(array_length(matched, 1), 0);
  select condition into v_cond from public.payout_rules
   where game_type_code = p_bet.game_type_code and version = p_bet.payout_rule_version
     and selection_count = p_bet.selection_count limit 1;

  multiplier := case
    -- FRUITS : gagnant si le fruit tiré est parmi ceux choisis
    when v_cond = 'winner_in_selection' then
      case when v_count >= 1 then coalesce((p_bet.odds_snapshot->>'1')::numeric, 0) else 0 end
    -- NAPE : tous les numéros choisis doivent sortir
    when v_cond = 'all_selected_in_result' then
      case when v_count = p_bet.selection_count
           then coalesce((p_bet.odds_snapshot->>v_count::text)::numeric, 0) else 0 end
    -- PERME / CHOX : cote selon le nombre exact de numéros trouvés
    else coalesce((p_bet.odds_snapshot->>v_count::text)::numeric, 0)
  end;
end $$;

create or replace function private.settle_round(p_round_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_round  public.game_rounds%rowtype;
  b        public.bets%rowtype;
  e        record;
  v_payout bigint;
  v_rule   uuid;
  v_journal uuid;
  v_won    int := 0;
  v_lost   int := 0;
  v_paid   bigint := 0;
begin
  select * into v_round from public.game_rounds where id = p_round_id for update;
  if v_round.status <> 'published' then
    return jsonb_build_object('skipped', v_round.status);
  end if;

  for b in select * from public.bets where round_id = p_round_id and status = 'pending' order by placed_at for update loop
    e := private.evaluate_bet(b, v_round.result);
    v_payout := floor(b.stake * e.multiplier)::bigint;
    select id into v_rule from public.payout_rules
     where game_type_code = b.game_type_code and version = b.payout_rule_version
       and selection_count = b.selection_count
       and match_count = case when b.game_code = 'FRUITS' then 1 else coalesce(array_length(e.matched, 1), 0) end;
    insert into public.bet_results (bet_id, round_id, match_count, matched_values, rule_id, multiplier, payout)
    values (b.id, p_round_id, coalesce(array_length(e.matched, 1), 0), e.matched,
            case when v_payout > 0 then v_rule end, e.multiplier, v_payout);

    if v_payout > 0 then
      v_journal := private.post_journal(
        'bet_win', 'bet-win:' || b.id,
        jsonb_build_array(
          jsonb_build_object('wallet_id', private.system_wallet('HOUSE', b.currency_code), 'amount', -v_payout),
          jsonb_build_object('wallet_id', b.wallet_id, 'amount', v_payout)),
        'draw_engine', b.id, null, 'Gain pari ' || b.reference);
      update public.bets set status = 'won', actual_payout = v_payout, payout_journal_id = v_journal, settled_at = now()
       where id = b.id;
      insert into public.notifications (user_id, type, title, body, data)
      values (b.user_id, 'bet_won', 'Pari gagnant 🎉',
              format('Votre pari %s gagne %s %s, déjà crédités sur votre solde.', b.reference, v_payout, b.currency_code),
              jsonb_build_object('bet_id', b.id, 'round_id', p_round_id, 'payout', v_payout));
      v_won := v_won + 1;
      v_paid := v_paid + v_payout;
    else
      update public.bets set status = 'lost', settled_at = now() where id = b.id;
      v_lost := v_lost + 1;
    end if;
  end loop;

  update public.game_rounds set status = 'settled', settled_at = now() where id = p_round_id;
  return jsonb_build_object('won', v_won, 'lost', v_lost, 'paid', v_paid);
end $$;

-- Remboursement des paris d'un tour annulé ---------------------------------------------
create or replace function private.refund_round_bets(p_round_id uuid)
returns int language plpgsql security definer set search_path = '' as $$
declare
  b       public.bets%rowtype;
  v_count int := 0;
begin
  for b in select * from public.bets where round_id = p_round_id and status = 'pending' for update loop
    perform private.post_journal(
      'bet_refund', 'bet-refund:' || b.id,
      jsonb_build_array(
        jsonb_build_object('wallet_id', private.system_wallet('HOUSE', b.currency_code), 'amount', -b.stake),
        jsonb_build_object('wallet_id', b.wallet_id, 'amount', b.stake)),
      'draw_engine', b.id, null, 'Remboursement pari ' || b.reference || ' (tirage annulé)');
    update public.bets set status = 'refunded', settled_at = now() where id = b.id;
    insert into public.notifications (user_id, type, title, body, data)
    values (b.user_id, 'account_change', 'Pari remboursé',
            format('Le tirage de votre pari %s a été annulé : %s %s vous ont été remboursés.', b.reference, b.stake, b.currency_code),
            jsonb_build_object('bet_id', b.id, 'round_id', p_round_id));
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;

-- Annulation admin : rembourse désormais les paris au lieu de refuser
create or replace function private.cancel_round(p_round_id uuid, p_admin_id uuid, p_reason text)
returns public.game_rounds language plpgsql security definer set search_path = '' as $$
declare
  v_round    public.game_rounds%rowtype;
  v_refunded int;
begin
  if p_reason is null or length(trim(p_reason)) < 3 then
    raise exception 'Motif obligatoire' using errcode = 'P0001';
  end if;
  select * into v_round from public.game_rounds where id = p_round_id for update;
  if not found then
    raise exception 'Tirage introuvable' using errcode = 'P0002';
  end if;
  if v_round.status not in ('scheduled', 'open', 'closed') then
    raise exception 'Ce tirage est déjà tiré ou clôturé : annulation impossible' using errcode = 'P0001';
  end if;
  v_refunded := private.refund_round_bets(p_round_id);
  update public.game_rounds set status = 'cancelled' where id = p_round_id returning * into v_round;
  insert into public.admin_actions (admin_id, action, target_type, target_id, reason, payload)
  values (p_admin_id, 'cancel_round', 'game_round', v_round.game_code || '#' || v_round.round_number, trim(p_reason),
          jsonb_build_object('round_id', v_round.id, 'draw_at', v_round.draw_at, 'refunded_bets', v_refunded));
  return v_round;
end $$;

-- Tirage → publication → règlement, dans la même transaction
create or replace function private.draw_round(p_round_id uuid)
returns public.game_rounds language plpgsql security definer set search_path = '' as $$
declare
  v_round public.game_rounds%rowtype;
  v_seed  text;
begin
  select * into v_round from public.game_rounds where id = p_round_id for update;
  if v_round.status <> 'closed' then
    return v_round;
  end if;
  select server_seed into v_seed from private.round_secrets where round_id = p_round_id;
  if encode(extensions.digest(decode(v_seed, 'hex'), 'sha256'), 'hex') <> v_round.commitment_hash then
    raise exception 'Graine incohérente avec l''engagement du tour %', v_round.round_number;
  end if;
  update public.game_rounds
     set status = 'drawn', result = private.compute_result(v_round.game_code, v_seed, p_round_id), drawn_at = now()
   where id = p_round_id;
  update public.game_rounds
     set status = 'published', revealed_seed = v_seed, published_at = now()
   where id = p_round_id;
  perform private.settle_round(p_round_id);
  select * into v_round from public.game_rounds where id = p_round_id;
  return v_round;
end $$;

-- Le battement règle aussi les tours publiés avant cette migration
create or replace function private.engine_tick(p_now timestamptz default now())
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  r         public.game_rounds%rowtype;
  v_created int;
  v_opened  int := 0;
  v_closed  int := 0;
  v_drawn   int := 0;
  v_missed  int := 0;
  v_settled int := 0;
begin
  if not pg_try_advisory_xact_lock(hashtext('methe.engine_tick')) then
    return jsonb_build_object('skipped', true);
  end if;

  v_created := private.schedule_rounds(p_now);

  update public.game_rounds set status = 'cancelled'
   where status = 'scheduled' and closes_at <= p_now;
  get diagnostics v_missed = row_count;

  for r in select * from public.game_rounds where status = 'scheduled' and opens_at <= p_now order by draw_at loop
    perform private.open_round(r.id);
    v_opened := v_opened + 1;
  end loop;

  update public.game_rounds set status = 'closed' where status = 'open' and closes_at <= p_now;
  get diagnostics v_closed = row_count;

  for r in select * from public.game_rounds where status = 'closed' and draw_at <= p_now order by draw_at loop
    perform private.draw_round(r.id);
    v_drawn := v_drawn + 1;
  end loop;

  for r in select * from public.game_rounds where status = 'published' order by draw_at loop
    perform private.settle_round(r.id);
    v_settled := v_settled + 1;
  end loop;

  return jsonb_build_object('created', v_created, 'opened', v_opened, 'closed', v_closed,
                            'drawn', v_drawn, 'settled_late', v_settled, 'cancelled_missed', v_missed);
end $$;

revoke execute on all functions in schema private from public, anon, authenticated;
grant execute on function private.has_role(public.app_role[]) to authenticated;
grant execute on function private.is_staff() to authenticated;
