-- =============================================================================
-- 0003 — Agents WhatsApp, dépôts, retraits
-- =============================================================================

create type public.deposit_status    as enum ('pending', 'approved', 'rejected', 'cancelled');
create type public.withdrawal_status as enum ('pending', 'under_review', 'approved', 'paid', 'rejected', 'cancelled');

-- Agents ----------------------------------------------------------------------
create table public.agents (
  id               uuid primary key default gen_random_uuid(),
  display_name     text not null check (length(trim(display_name)) between 1 and 60),
  whatsapp_number  text not null unique check (whatsapp_number ~ '^\+[1-9][0-9]{6,14}$'),
  avatar_url       text,
  country_code     char(2) references public.countries(code),
  is_available     boolean not null default true,
  is_active        boolean not null default true,
  sort_order       int not null default 0,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create trigger agents_touch before update on public.agents
  for each row execute function private.touch_updated_at();

-- Dépôts ----------------------------------------------------------------------
-- Une demande est créée quand l'utilisateur contacte un agent ; elle n'est créditée
-- qu'après validation par un administrateur (journal 'deposit').
create table public.deposits (
  id                 uuid primary key default gen_random_uuid(),
  reference          text not null unique default private.next_reference('DEP'),
  user_id            uuid not null references public.profiles(id) on delete restrict,
  wallet_id          uuid not null references public.wallets(id) on delete restrict,
  agent_id           uuid references public.agents(id),
  amount             bigint not null check (amount > 0),
  currency_code      char(3) not null references public.currencies(code),
  status             public.deposit_status not null default 'pending',
  user_note          text,
  reviewed_by        uuid references public.profiles(id),
  reviewed_at        timestamptz,
  rejection_reason   text,
  journal_id         uuid unique references public.ledger_journals(id),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  constraint deposits_approved_ck check (
    status <> 'approved' or (journal_id is not null and reviewed_by is not null and reviewed_at is not null)),
  constraint deposits_rejected_ck check (
    status <> 'rejected' or (reviewed_by is not null and rejection_reason is not null))
);
create index deposits_status_idx on public.deposits(status, created_at);
create index deposits_user_idx   on public.deposits(user_id, created_at desc);
create trigger deposits_touch before update on public.deposits
  for each row execute function private.touch_updated_at();

-- Retraits --------------------------------------------------------------------
-- À la demande, le montant est déplacé vers le portefeuille système
-- WITHDRAWAL_HOLD (journal 'withdrawal_hold'). Paiement → 'withdrawal_payout' ;
-- refus / annulation → 'withdrawal_release' (retour au joueur).
create table public.withdrawals (
  id                   uuid primary key default gen_random_uuid(),
  reference            text not null unique default private.next_reference('WDR'),
  user_id              uuid not null references public.profiles(id) on delete restrict,
  wallet_id            uuid not null references public.wallets(id) on delete restrict,
  amount               bigint not null check (amount > 0),
  fee                  bigint not null default 0 check (fee >= 0),
  net_amount           bigint generated always as (amount - fee) stored,
  currency_code        char(3) not null references public.currencies(code),
  method               text not null check (method in ('mobile_money', 'agent', 'bank')),
  payout_account       text not null,
  status               public.withdrawal_status not null default 'pending',
  reviewed_by          uuid references public.profiles(id),
  reviewed_at          timestamptz,
  paid_at              timestamptz,
  rejection_reason     text,
  hold_journal_id      uuid unique references public.ledger_journals(id),
  payout_journal_id    uuid unique references public.ledger_journals(id),
  release_journal_id   uuid unique references public.ledger_journals(id),
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  constraint withdrawals_fee_ck check (fee < amount),
  constraint withdrawals_paid_ck check (status <> 'paid' or (payout_journal_id is not null and paid_at is not null)),
  constraint withdrawals_release_ck check (status not in ('rejected', 'cancelled') or release_journal_id is not null or hold_journal_id is null)
);
create index withdrawals_status_idx on public.withdrawals(status, created_at);
create index withdrawals_user_idx   on public.withdrawals(user_id, created_at desc);
create trigger withdrawals_touch before update on public.withdrawals
  for each row execute function private.touch_updated_at();
