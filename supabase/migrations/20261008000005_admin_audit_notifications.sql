-- =============================================================================
-- 0005 — Paramètres, notifications, actions admin, journal d'audit, anti-fraude
-- =============================================================================

create table public.app_settings (
  key          text primary key check (key ~ '^[a-z0-9_.]{2,80}$'),
  value        jsonb not null,
  is_public    boolean not null default false,   -- lisible par l'application cliente
  description  text,
  updated_by   uuid references public.profiles(id),
  updated_at   timestamptz not null default now()
);
create trigger app_settings_touch before update on public.app_settings
  for each row execute function private.touch_updated_at();

create table public.notifications (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  type        text not null check (type in (
                'deposit_approved','deposit_rejected','withdrawal_approved','withdrawal_paid',
                'withdrawal_rejected','bet_placed','result_available','bet_won','winnings_credited',
                'account_change')),
  title       text not null,
  body        text not null,
  data        jsonb not null default '{}'::jsonb,
  read_at     timestamptz,
  created_at  timestamptz not null default now()
);
create index notifications_user_idx on public.notifications(user_id, created_at desc);

create table public.admin_actions (
  id            bigint generated always as identity primary key,
  admin_id      uuid not null references public.profiles(id),
  action        text not null,                 -- 'credit_user', 'approve_deposit', …
  target_type   text not null,
  target_id     text not null,
  reason        text,
  payload       jsonb not null default '{}'::jsonb,
  ip_address    inet,
  created_at    timestamptz not null default now()
);
create index admin_actions_admin_idx on public.admin_actions(admin_id, created_at desc);

create table public.audit_logs (
  id            bigint generated always as identity primary key,
  actor_id      uuid,
  actor_role    text not null default current_user,
  action        text not null,                 -- INSERT / UPDATE / DELETE ou action métier
  entity        text not null,
  entity_id     text,
  old_data      jsonb,
  new_data      jsonb,
  ip_address    inet,
  user_agent    text,
  created_at    timestamptz not null default now()
);
create index audit_logs_entity_idx on public.audit_logs(entity, entity_id, created_at desc);

create trigger admin_actions_immutable before update or delete on public.admin_actions
  for each row execute function private.ledger_immutable();
create trigger audit_logs_immutable before update or delete on public.audit_logs
  for each row execute function private.ledger_immutable();

-- Signaux anti-fraude (alimentés par le backend en phase 13)
create table public.risk_events (
  id           bigint generated always as identity primary key,
  user_id      uuid references public.profiles(id),
  kind         text not null,       -- 'multi_account', 'velocity', 'admin_anomaly', …
  severity     smallint not null check (severity between 1 and 5),
  details      jsonb not null default '{}'::jsonb,
  resolved_by  uuid references public.profiles(id),
  resolved_at  timestamptz,
  created_at   timestamptz not null default now()
);

-- Audit automatique des tables sensibles ------------------------------------
-- L'acteur est l'utilisateur JWT si présent, sinon `methe.actor_id` positionné
-- par le backend dans la transaction.
create or replace function private.audit_row()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := coalesce(
    auth.uid(),
    nullif(current_setting('methe.actor_id', true), '')::uuid);
  v_id text;
begin
  v_id := case when tg_op = 'DELETE' then to_jsonb(old)->>'id' else to_jsonb(new)->>'id' end;
  insert into public.audit_logs (actor_id, action, entity, entity_id, old_data, new_data)
  values (
    v_actor, tg_op, tg_table_name,
    coalesce(v_id, case when tg_op = 'DELETE' then to_jsonb(old)->>'key' else to_jsonb(new)->>'key' end),
    case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end);
  return coalesce(new, old);
end $$;

do $$
declare t text;
begin
  foreach t in array array[
    'profiles','admin_users','agents','deposits','withdrawals','games','game_types',
    'draw_schedules','game_rounds','payout_rules','app_settings']
  loop
    execute format(
      'create trigger %I after insert or update or delete on public.%I
         for each row execute function private.audit_row()', t || '_audit', t);
  end loop;
end $$;
