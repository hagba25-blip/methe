-- =============================================================================
-- 0004 — Jeux, tirages, règles de paiement versionnées, paris
-- =============================================================================

create type public.round_status as enum ('scheduled', 'open', 'closed', 'drawn', 'published', 'settled', 'cancelled');
create type public.bet_status   as enum ('pending', 'won', 'lost', 'cancelled', 'refunded');

-- Catalogue -------------------------------------------------------------------
create table public.games (
  code         text primary key check (code ~ '^[A-Z_]{2,30}$'),
  name         text not null,
  description  text,
  is_active    boolean not null default true,
  sort_order   int not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create trigger games_touch before update on public.games
  for each row execute function private.touch_updated_at();

-- Type de jeu = mode de mise (FRUITS, PERME, NAPE, CHOX…)
create table public.game_types (
  code            text primary key check (code ~ '^[A-Z_]{2,30}$'),
  game_code       text not null references public.games(code),
  name            text not null,
  min_selection   smallint not null check (min_selection >= 1),
  max_selection   smallint not null,
  min_stake       bigint not null default 50 check (min_stake >= 50),
  max_stake       bigint,
  is_active       boolean not null default true,
  sort_order      int not null default 0,
  updated_at      timestamptz not null default now(),
  constraint game_types_sel_ck check (max_selection >= min_selection),
  constraint game_types_stake_ck check (max_stake is null or max_stake >= min_stake)
);
create trigger game_types_touch before update on public.game_types
  for each row execute function private.touch_updated_at();

-- Symboles jouables (les 20 fruits ; les nombres 1–90 de Lonato sont implicites)
create table public.game_symbols (
  game_code   text not null references public.games(code),
  code        text not null check (code ~ '^[A-Z_]{2,30}$'),
  label       text not null,
  emoji       text,
  image_url   text,
  sort_order  int not null default 0,
  primary key (game_code, code)
);

-- Planification des tirages -------------------------------------------------
create table public.draw_schedules (
  game_code               text primary key references public.games(code),
  interval_minutes        int not null check (interval_minutes between 5 and 1440),
  close_before_seconds    int not null default 60 check (close_before_seconds >= 0),
  is_active               boolean not null default true,
  updated_at              timestamptz not null default now()
);

-- Tirages ---------------------------------------------------------------------
-- Protocole « commit-reveal » : le hash SHA-256 de la graine secrète est publié
-- avant la fermeture des mises ; la graine est révélée à la publication, ce qui
-- permet à quiconque de recalculer le résultat.
create table public.game_rounds (
  id                  uuid primary key default gen_random_uuid(),
  game_code           text not null references public.games(code),
  round_number        bigint not null,
  opens_at            timestamptz not null,
  closes_at           timestamptz not null,
  draw_at             timestamptz not null,
  status              public.round_status not null default 'scheduled',
  commitment_hash     text check (commitment_hash ~ '^[0-9a-f]{64}$'),
  revealed_seed       text check (revealed_seed ~ '^[0-9a-f]{64}$'),
  algorithm_version   text,
  result              jsonb,
  drawn_at            timestamptz,
  published_at        timestamptz,
  settled_at          timestamptz,
  created_at          timestamptz not null default now(),
  constraint game_rounds_number_uq unique (game_code, round_number),
  constraint game_rounds_slot_uq   unique (game_code, draw_at),
  constraint game_rounds_time_ck   check (opens_at < closes_at and closes_at <= draw_at),
  constraint game_rounds_open_ck   check (status in ('scheduled', 'cancelled') or commitment_hash is not null),
  constraint game_rounds_drawn_ck  check (status not in ('drawn', 'published', 'settled') or (result is not null and drawn_at is not null)),
  constraint game_rounds_pub_ck    check (status not in ('published', 'settled') or (revealed_seed is not null and published_at is not null))
);
create index game_rounds_status_idx on public.game_rounds(game_code, status, draw_at);

-- Graines secrètes : jamais exposées avant publication.
create table private.round_secrets (
  round_id     uuid primary key references public.game_rounds(id) on delete restrict,
  server_seed  text not null check (server_seed ~ '^[0-9a-f]{64}$'),
  created_at   timestamptz not null default now()
);

-- Verrouillage : statut uniquement vers l'avant ; résultat, engagement et graine
-- non modifiables une fois fixés.
create or replace function private.guard_round()
returns trigger language plpgsql as $$
declare
  v_order constant text[] := array['scheduled','open','closed','drawn','published','settled'];
begin
  if tg_op = 'DELETE' then
    raise exception 'Un tirage ne peut pas être supprimé';
  end if;
  if old.status in ('settled', 'cancelled') and new is distinct from old then
    raise exception 'Tirage % clôturé : modification interdite', old.round_number;
  end if;
  if new.status <> 'cancelled'
     and array_position(v_order, new.status::text) < array_position(v_order, old.status::text) then
    raise exception 'Retour arrière de statut interdit (% → %)', old.status, new.status;
  end if;
  if new.status = 'cancelled' and old.status in ('drawn', 'published') then
    raise exception 'Un tirage déjà tiré ne peut pas être annulé';
  end if;
  if old.result is not null and new.result is distinct from old.result then
    raise exception 'Résultat verrouillé : modification interdite';
  end if;
  if old.commitment_hash is not null and new.commitment_hash is distinct from old.commitment_hash then
    raise exception 'Engagement cryptographique verrouillé';
  end if;
  if old.revealed_seed is not null and new.revealed_seed is distinct from old.revealed_seed then
    raise exception 'Graine révélée verrouillée';
  end if;
  if (new.game_code, new.round_number, new.opens_at, new.closes_at, new.draw_at)
     is distinct from (old.game_code, old.round_number, old.opens_at, old.closes_at, old.draw_at)
     and old.status <> 'scheduled' then
    raise exception 'Horaires figés une fois le tirage ouvert';
  end if;
  return new;
end $$;
create trigger game_rounds_guard before update or delete on public.game_rounds
  for each row execute function private.guard_round();

-- Règles de paiement versionnées ---------------------------------------------
-- Une règle publiée n'est jamais modifiée : on crée une nouvelle version.
-- Les paris conservent la version et le multiplicateur appliqués.
create table public.payout_rules (
  id                 uuid primary key default gen_random_uuid(),
  game_type_code     text not null references public.game_types(code),
  version            int not null check (version >= 1),
  selection_count    smallint not null check (selection_count >= 1),
  match_count        smallint not null check (match_count >= 0),
  multiplier         numeric(14,4) not null check (multiplier >= 0),
  condition          text not null default 'exact_matches'
                     check (condition in ('exact_matches', 'all_selected_in_result', 'winner_in_selection')),
  min_stake          bigint not null default 50 check (min_stake >= 50),
  effective_from     timestamptz not null,
  effective_to       timestamptz,
  note               text,
  created_by         uuid references public.profiles(id),
  created_at         timestamptz not null default now(),
  constraint payout_rules_uq unique (game_type_code, version, selection_count, match_count),
  constraint payout_rules_match_ck check (match_count <= selection_count),
  constraint payout_rules_period_ck check (effective_to is null or effective_to > effective_from)
);
create index payout_rules_lookup_idx on public.payout_rules(game_type_code, selection_count, effective_from desc);

create or replace function private.guard_payout_rule()
returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Une règle de paiement ne se supprime pas : clôturez-la (effective_to)';
  end if;
  if (new.game_type_code, new.version, new.selection_count, new.match_count, new.multiplier,
      new.condition, new.min_stake, new.effective_from)
     is distinct from
     (old.game_type_code, old.version, old.selection_count, old.match_count, old.multiplier,
      old.condition, old.min_stake, old.effective_from) then
    raise exception 'Règle de paiement immuable : créez une nouvelle version';
  end if;
  return new;
end $$;
create trigger payout_rules_guard before update or delete on public.payout_rules
  for each row execute function private.guard_payout_rule();

-- Paris -----------------------------------------------------------------------
create table public.bets (
  id                    uuid primary key default gen_random_uuid(),
  reference             text not null unique default private.next_reference('BET'),
  user_id               uuid not null references public.profiles(id) on delete restrict,
  wallet_id             uuid not null references public.wallets(id) on delete restrict,
  round_id              uuid not null references public.game_rounds(id) on delete restrict,
  game_code             text not null references public.games(code),
  game_type_code        text not null references public.game_types(code),
  selection_count       smallint not null check (selection_count >= 1),
  stake                 bigint not null check (stake >= 50),
  currency_code         char(3) not null references public.currencies(code),
  payout_rule_version   int not null,
  odds_snapshot         jsonb not null,           -- multiplicateurs applicables au moment du pari
  potential_payout      bigint not null check (potential_payout >= 0),
  status                public.bet_status not null default 'pending',
  actual_payout         bigint not null default 0 check (actual_payout >= 0),
  idempotency_key       text not null,
  stake_journal_id      uuid unique references public.ledger_journals(id),
  payout_journal_id     uuid unique references public.ledger_journals(id),
  placed_at             timestamptz not null default now(),
  settled_at            timestamptz,
  constraint bets_idem_uq unique (user_id, idempotency_key),
  constraint bets_settled_ck check (status = 'pending' or settled_at is not null),
  constraint bets_won_ck check (status <> 'won' or (actual_payout > 0 and payout_journal_id is not null))
);
create index bets_user_idx  on public.bets(user_id, placed_at desc);
create index bets_round_idx on public.bets(round_id, status);

-- Un pari ne peut être rattaché qu'à un tirage OUVERT et avant sa fermeture.
create or replace function private.guard_bet_insert()
returns trigger language plpgsql as $$
declare
  r public.game_rounds%rowtype;
  t public.game_types%rowtype;
begin
  select * into r from public.game_rounds where id = new.round_id for share;
  if r.status <> 'open' or now() >= r.closes_at then
    raise exception 'Les mises sont fermées pour ce tirage';
  end if;
  select * into t from public.game_types where code = new.game_type_code;
  if not t.is_active or t.game_code <> r.game_code or new.game_code <> r.game_code then
    raise exception 'Type de jeu invalide pour ce tirage';
  end if;
  if new.stake < t.min_stake or (t.max_stake is not null and new.stake > t.max_stake) then
    raise exception 'Mise hors limites (minimum % )', t.min_stake;
  end if;
  if new.selection_count not between t.min_selection and t.max_selection then
    raise exception 'Nombre de sélections invalide';
  end if;
  new.placed_at := now();
  return new;
end $$;
create trigger bets_guard_insert before insert on public.bets
  for each row execute function private.guard_bet_insert();

-- Après création : seuls le statut, le gain et les journaux évoluent (une fois).
create or replace function private.guard_bet_update()
returns trigger language plpgsql as $$
begin
  if old.status <> 'pending' then
    raise exception 'Pari % déjà réglé', old.reference;
  end if;
  if (new.user_id, new.wallet_id, new.round_id, new.game_type_code, new.stake, new.odds_snapshot,
      new.payout_rule_version, new.potential_payout, new.placed_at, new.reference)
     is distinct from
     (old.user_id, old.wallet_id, old.round_id, old.game_type_code, old.stake, old.odds_snapshot,
      old.payout_rule_version, old.potential_payout, old.placed_at, old.reference) then
    raise exception 'Les données du pari sont figées';
  end if;
  return new;
end $$;
create trigger bets_guard_update before update on public.bets
  for each row execute function private.guard_bet_update();
create trigger bets_no_delete before delete on public.bets
  for each row execute function private.ledger_immutable();

create table public.bet_items (
  bet_id      uuid not null references public.bets(id) on delete restrict,
  value       text not null check (value ~ '^([0-9]{2}|[A-Z_]{2,30})$'),  -- '07' ou 'POMME'
  primary key (bet_id, value)
);

create table public.bet_results (
  bet_id          uuid primary key references public.bets(id) on delete restrict,
  round_id        uuid not null references public.game_rounds(id),
  match_count     smallint not null,
  matched_values  text[] not null default '{}',
  rule_id         uuid references public.payout_rules(id),
  multiplier      numeric(14,4) not null default 0,
  payout          bigint not null default 0 check (payout >= 0),
  computed_at     timestamptz not null default now()
);
create trigger bet_results_immutable before update or delete on public.bet_results
  for each row execute function private.ledger_immutable();
