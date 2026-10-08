-- =============================================================================
-- 0002 — Identité (profils, ID client à 10 chiffres, rôles) + portefeuilles + ledger
-- =============================================================================

-- Types -----------------------------------------------------------------------
create type public.account_status as enum ('active', 'suspended', 'blocked', 'closed');
create type public.kyc_status     as enum ('none', 'pending', 'verified', 'rejected');
create type public.app_role       as enum ('support', 'finance', 'admin', 'super_admin');
create type public.wallet_owner   as enum ('user', 'system');
create type public.tx_type as enum (
  'deposit',             -- dépôt validé par l'administration
  'withdrawal_hold',     -- blocage du montant à la demande de retrait
  'withdrawal_release',  -- déblocage (retrait refusé / annulé)
  'withdrawal_payout',   -- retrait payé (sortie définitive)
  'bet_stake',           -- mise
  'bet_win',             -- gain
  'bet_refund',          -- remboursement de mise
  'adjustment',          -- ajustement manuel autorisé
  'treasury_funding'     -- alimentation de la trésorerie (configuration)
);
create type public.tx_status as enum ('posted', 'reversed');

-- Compteurs de références lisibles (BET-20261007-000001, DEP-…, WDR-…) ----------
create table private.daily_counters (
  prefix  text not null,
  day     date not null,
  value   bigint not null,
  primary key (prefix, day)
);

create or replace function private.next_reference(p_prefix text)
returns text language plpgsql as $$
declare
  v_day date := (now() at time zone 'UTC')::date;
  v_val bigint;
begin
  insert into private.daily_counters as c (prefix, day, value)
  values (p_prefix, v_day, 1)
  on conflict (prefix, day) do update set value = c.value + 1
  returning c.value into v_val;
  return p_prefix || '-' || to_char(v_day, 'YYYYMMDD') || '-' || lpad(v_val::text, 6, '0');
end $$;

-- ID client : 10 chiffres, commence par 6 ------------------------------------
create or replace function private.generate_public_id()
returns char(10) language plpgsql volatile as $$
declare
  v_candidate char(10);
  v_attempt   int := 0;
begin
  loop
    -- 9 chiffres aléatoires issus d'un générateur cryptographique (pgcrypto)
    v_candidate := '6' || lpad(
      ((('x' || encode(extensions.gen_random_bytes(4), 'hex'))::bit(32)::bigint) % 1000000000)::text,
      9, '0');
    exit when not exists (select 1 from public.profiles where public_id = v_candidate);
    v_attempt := v_attempt + 1;
    if v_attempt > 20 then
      raise exception 'Impossible de générer un ID client unique';
    end if;
  end loop;
  return v_candidate;
end $$;

-- Profils ---------------------------------------------------------------------
create table public.profiles (
  id                    uuid primary key references auth.users(id) on delete restrict,
  public_id             char(10) not null unique check (public_id ~ '^6[0-9]{9}$'),
  first_name            text not null check (length(trim(first_name)) between 1 and 80),
  last_name             text not null check (length(trim(last_name)) between 1 and 80),
  phone                 text not null unique check (phone ~ '^\+[1-9][0-9]{6,14}$'),
  email                 text unique check (email is null or email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  country_code          char(2) not null references public.countries(code),
  language_code         varchar(5) not null references public.languages(code),
  currency_code         char(3) not null references public.currencies(code),
  birth_date            date check (birth_date is null or birth_date <= current_date - interval '18 years'),
  avatar_url            text,
  status                public.account_status not null default 'active',
  kyc_status            public.kyc_status not null default 'none',
  terms_accepted_at     timestamptz not null,
  privacy_accepted_at   timestamptz not null,
  last_login_at         timestamptz,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);
create index profiles_country_idx on public.profiles(country_code);

create trigger profiles_touch before update on public.profiles
  for each row execute function private.touch_updated_at();

-- L'ID client et les champs sensibles ne peuvent jamais changer côté utilisateur.
create or replace function private.protect_profile_fields()
returns trigger language plpgsql as $$
begin
  if new.public_id is distinct from old.public_id then
    raise exception 'L''ID client est définitif et ne peut pas être modifié';
  end if;
  if new.id is distinct from old.id or new.created_at is distinct from old.created_at then
    raise exception 'Champ non modifiable';
  end if;
  return new;
end $$;
create trigger profiles_protect before update on public.profiles
  for each row execute function private.protect_profile_fields();

-- Administrateurs -------------------------------------------------------------
create table public.admin_users (
  user_id     uuid primary key references public.profiles(id) on delete restrict,
  role        public.app_role not null,
  is_active   boolean not null default true,
  created_by  uuid references public.profiles(id),
  created_at  timestamptz not null default now()
);

create or replace function private.has_role(p_roles public.app_role[])
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.admin_users a
    where a.user_id = auth.uid() and a.is_active and a.role = any(p_roles)
  );
$$;

create or replace function private.is_staff()
returns boolean language sql stable security definer set search_path = '' as $$
  select private.has_role(array['support','finance','admin','super_admin']::public.app_role[]);
$$;

-- Portefeuilles ---------------------------------------------------------------
-- Le champ `balance` n'est qu'un cache : il est modifié UNIQUEMENT par
-- private.post_journal(), qui écrit en même temps les lignes du ledger.
create table public.wallets (
  id               uuid primary key default gen_random_uuid(),
  owner_type       public.wallet_owner not null,
  user_id          uuid references public.profiles(id) on delete restrict,
  system_code      text check (system_code is null or system_code ~ '^[A-Z_]{3,40}$'),
  currency_code    char(3) not null references public.currencies(code),
  balance          bigint not null default 0,
  allow_negative   boolean not null default false,
  is_frozen        boolean not null default false,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint wallets_owner_ck check (
    (owner_type = 'user'   and user_id is not null and system_code is null and not allow_negative) or
    (owner_type = 'system' and user_id is null and system_code is not null)
  ),
  constraint wallets_balance_ck check (allow_negative or balance >= 0),
  constraint wallets_user_currency_uq unique (user_id, currency_code),
  constraint wallets_system_currency_uq unique (system_code, currency_code)
);
create trigger wallets_touch before update on public.wallets
  for each row execute function private.touch_updated_at();

-- Journaux (une opération financière = un journal équilibré) -----------------
create table public.ledger_journals (
  id                uuid primary key default gen_random_uuid(),
  reference         text not null unique,
  idempotency_key   text not null unique,
  tx_type           public.tx_type not null,
  description       text,
  source            text not null,            -- 'admin', 'system', 'draw_engine', 'api'…
  source_id         uuid,                     -- id du dépôt / retrait / pari concerné
  admin_id          uuid references public.profiles(id),
  created_at        timestamptz not null default now()
);

-- Mouvements par portefeuille (lignes du journal) -------------------------------
create table public.wallet_transactions (
  id               bigint generated always as identity primary key,
  journal_id       uuid not null references public.ledger_journals(id) on delete restrict,
  wallet_id        uuid not null references public.wallets(id) on delete restrict,
  user_id          uuid references public.profiles(id),
  amount           bigint not null check (amount <> 0),
  balance_before   bigint not null,
  balance_after    bigint not null,
  tx_type          public.tx_type not null,
  status           public.tx_status not null default 'posted',
  reference        text not null,
  source           text not null,
  admin_id         uuid references public.profiles(id),
  created_at       timestamptz not null default now(),
  constraint wallet_tx_math_ck check (balance_after = balance_before + amount)
);
create index wallet_tx_wallet_idx on public.wallet_transactions(wallet_id, created_at desc);
create index wallet_tx_user_idx   on public.wallet_transactions(user_id, created_at desc);

-- Le ledger est en écriture seule : aucune modification, aucune suppression.
create or replace function private.ledger_immutable()
returns trigger language plpgsql as $$
begin
  raise exception 'Le ledger est immuable (% interdit sur %)', tg_op, tg_table_name;
end $$;
create trigger wallet_tx_immutable before update or delete on public.wallet_transactions
  for each row execute function private.ledger_immutable();
create trigger ledger_journals_immutable before update or delete on public.ledger_journals
  for each row execute function private.ledger_immutable();

-- Écriture comptable atomique, équilibrée et idempotente -----------------------
-- p_lines : [{"wallet_id": "...", "amount": 1000}, {"wallet_id": "...", "amount": -1000}]
create or replace function private.post_journal(
  p_tx_type          public.tx_type,
  p_idempotency_key  text,
  p_lines            jsonb,
  p_source           text,
  p_source_id        uuid default null,
  p_admin_id         uuid default null,
  p_description      text default null,
  p_reference        text default null
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_journal_id  uuid;
  v_reference   text;
  v_sum         numeric := 0;
  v_currency    char(3);
  v_line        record;
  v_wallet      public.wallets%rowtype;
begin
  if p_idempotency_key is null or length(p_idempotency_key) < 8 then
    raise exception 'Clé d''idempotence obligatoire';
  end if;

  -- Rejeu : on renvoie le journal déjà écrit (protection contre les doubles transactions)
  select id into v_journal_id from public.ledger_journals where idempotency_key = p_idempotency_key;
  if found then
    return v_journal_id;
  end if;

  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) < 2 then
    raise exception 'Un journal comporte au moins deux lignes';
  end if;

  select sum((l->>'amount')::bigint) into v_sum from jsonb_array_elements(p_lines) l;
  if v_sum <> 0 then
    raise exception 'Journal déséquilibré (somme = %)', v_sum;
  end if;

  v_reference := coalesce(p_reference, private.next_reference('TRX'));
  insert into public.ledger_journals (reference, idempotency_key, tx_type, description, source, source_id, admin_id)
  values (v_reference, p_idempotency_key, p_tx_type, p_description, p_source, p_source_id, p_admin_id)
  returning id into v_journal_id;

  -- Verrouillage des portefeuilles dans un ordre stable (évite les interblocages)
  for v_line in
    select (l->>'wallet_id')::uuid as wallet_id, sum((l->>'amount')::bigint) as amount
    from jsonb_array_elements(p_lines) l
    group by 1 order by 1
  loop
    select * into v_wallet from public.wallets where id = v_line.wallet_id for update;
    if not found then
      raise exception 'Portefeuille introuvable';
    end if;
    if v_wallet.is_frozen then
      raise exception 'Portefeuille gelé';
    end if;
    if v_currency is null then
      v_currency := v_wallet.currency_code;
    elsif v_currency <> v_wallet.currency_code then
      raise exception 'Devises différentes dans un même journal';
    end if;
    if v_line.amount = 0 then
      continue;
    end if;
    if not v_wallet.allow_negative and v_wallet.balance + v_line.amount < 0 then
      raise exception 'Solde insuffisant' using errcode = 'P0001';
    end if;

    insert into public.wallet_transactions
      (journal_id, wallet_id, user_id, amount, balance_before, balance_after,
       tx_type, reference, source, admin_id)
    values
      (v_journal_id, v_wallet.id, v_wallet.user_id, v_line.amount, v_wallet.balance,
       v_wallet.balance + v_line.amount, p_tx_type, v_reference, p_source, p_admin_id);

    perform set_config('methe.ledger_write', 'on', true);
    update public.wallets set balance = balance + v_line.amount where id = v_wallet.id;
    perform set_config('methe.ledger_write', 'off', true);
  end loop;

  return v_journal_id;
end $$;

-- Toute modification de `balance` hors post_journal est refusée. -------------
-- post_journal active un drapeau local à la transaction juste avant sa mise à jour.
-- Le rôle `authenticated` n'a de toute façon aucun droit UPDATE sur wallets : ce
-- garde-fou protège aussi contre une écriture directe accidentelle du backend.
create or replace function private.guard_wallet_balance()
returns trigger language plpgsql as $$
begin
  if (new.balance is distinct from old.balance)
     and coalesce(current_setting('methe.ledger_write', true), '') <> 'on' then
    raise exception 'Le solde ne peut être modifié que par une écriture du ledger';
  end if;
  return new;
end $$;
create trigger wallets_guard_balance before update on public.wallets
  for each row execute function private.guard_wallet_balance();

-- Création automatique du profil + portefeuille à l'inscription (Supabase Auth)
-- Les métadonnées envoyées par l'application sont VALIDÉES ici : une donnée
-- invalide fait échouer l'inscription.
create or replace function private.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  m        jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  v_country  char(2) := upper(m->>'country_code');
  v_currency char(3) := upper(m->>'currency_code');
  v_language text    := m->>'language_code';
  v_phone    text    := coalesce(m->>'phone', new.phone);
begin
  if coalesce((m->>'accept_terms')::boolean, false) is not true
     or coalesce((m->>'accept_privacy')::boolean, false) is not true then
    raise exception 'Les conditions d''utilisation et la politique de confidentialité doivent être acceptées';
  end if;
  if not exists (select 1 from public.countries where code = v_country and is_active) then
    raise exception 'Pays non pris en charge';
  end if;
  if not exists (select 1 from public.currencies where code = v_currency and is_active) then
    raise exception 'Devise non prise en charge';
  end if;
  if not exists (select 1 from public.languages where code = v_language and is_active) then
    raise exception 'Langue non prise en charge';
  end if;
  if v_phone is not null and left(v_phone, 1) <> '+' then
    v_phone := '+' || v_phone;
  end if;

  insert into public.profiles (
    id, public_id, first_name, last_name, phone, email, country_code, language_code,
    currency_code, birth_date, terms_accepted_at, privacy_accepted_at)
  values (
    new.id, private.generate_public_id(), trim(m->>'first_name'), trim(m->>'last_name'),
    v_phone, lower(new.email), v_country, v_language, v_currency,
    nullif(m->>'birth_date', '')::date, now(), now());

  insert into public.wallets (owner_type, user_id, currency_code)
  values ('user', new.id, v_currency);

  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function private.handle_new_user();
