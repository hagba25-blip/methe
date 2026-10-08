-- =============================================================================
-- 0006 — Row Level Security et droits
-- =============================================================================
-- Principe : le client Flutter (rôles `anon` / `authenticated`) ne fait QUE LIRE
-- ses propres données et le catalogue public. Toute écriture métier (dépôt,
-- retrait, pari, règlement, administration) passe par le backend Python, qui se
-- connecte avec un rôle privilégié et applique ses propres contrôles.
-- =============================================================================

-- 1. Retirer les droits par défaut accordés par Supabase sur le schéma public
revoke insert, update, delete, truncate, references, trigger
  on all tables in schema public from anon, authenticated;
revoke all on all tables in schema private from anon, authenticated;
revoke execute on all functions in schema private from public, anon, authenticated;

alter default privileges in schema public revoke insert, update, delete, truncate on tables from anon, authenticated;
alter default privileges in schema private revoke execute on functions from public;

-- Les politiques RLS utilisent ces deux fonctions : seules exceptions exécutables.
grant usage on schema private to authenticated;
grant execute on function private.has_role(public.app_role[]) to authenticated;
grant execute on function private.is_staff() to authenticated;

-- 2. Activer RLS partout
do $$
declare t record;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', t.tablename);
  end loop;
end $$;

-- 3. Données de référence et catalogue : lecture publique ---------------------
create policy currencies_read on public.currencies for select to anon, authenticated using (is_active);
create policy languages_read  on public.languages  for select to anon, authenticated using (is_active);
create policy countries_read  on public.countries  for select to anon, authenticated using (is_active);
create policy agents_read     on public.agents     for select to anon, authenticated using (is_active);
create policy games_read      on public.games      for select to anon, authenticated using (is_active);
create policy game_types_read on public.game_types for select to anon, authenticated using (is_active);
create policy game_symbols_read   on public.game_symbols   for select to anon, authenticated using (true);
create policy draw_schedules_read on public.draw_schedules for select to anon, authenticated using (true);
create policy game_rounds_read    on public.game_rounds    for select to anon, authenticated using (true);
create policy payout_rules_read   on public.payout_rules   for select to anon, authenticated using (true);
create policy app_settings_read   on public.app_settings   for select to anon, authenticated
  using (is_public or private.is_staff());

-- 4. Données personnelles : uniquement les siennes (ou le personnel) ---------
create policy profiles_read on public.profiles for select to authenticated
  using (id = auth.uid() or private.is_staff());
-- Modification limitée aux champs non sensibles de son propre profil
create policy profiles_update_self on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());
grant update (first_name, last_name, language_code, avatar_url) on public.profiles to authenticated;

create policy wallets_read on public.wallets for select to authenticated
  using (user_id = auth.uid() or private.is_staff());
create policy wallet_tx_read on public.wallet_transactions for select to authenticated
  using (user_id = auth.uid() or private.is_staff());
create policy ledger_journals_read on public.ledger_journals for select to authenticated
  using (private.has_role(array['finance','admin','super_admin']::public.app_role[]));

create policy deposits_read on public.deposits for select to authenticated
  using (user_id = auth.uid() or private.is_staff());
create policy withdrawals_read on public.withdrawals for select to authenticated
  using (user_id = auth.uid() or private.is_staff());

create policy bets_read on public.bets for select to authenticated
  using (user_id = auth.uid() or private.is_staff());
create policy bet_items_read on public.bet_items for select to authenticated
  using (exists (select 1 from public.bets b where b.id = bet_id and (b.user_id = auth.uid() or private.is_staff())));
create policy bet_results_read on public.bet_results for select to authenticated
  using (exists (select 1 from public.bets b where b.id = bet_id and (b.user_id = auth.uid() or private.is_staff())));

create policy notifications_read on public.notifications for select to authenticated
  using (user_id = auth.uid());
create policy notifications_mark_read on public.notifications for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
grant update (read_at) on public.notifications to authenticated;

-- 5. Administration : lecture réservée au personnel ---------------------------
create policy admin_users_read on public.admin_users for select to authenticated
  using (user_id = auth.uid() or private.has_role(array['admin','super_admin']::public.app_role[]));
create policy admin_actions_read on public.admin_actions for select to authenticated
  using (private.has_role(array['admin','super_admin']::public.app_role[]));
create policy audit_logs_read on public.audit_logs for select to authenticated
  using (private.has_role(array['admin','super_admin']::public.app_role[]));
create policy risk_events_read on public.risk_events for select to authenticated
  using (private.has_role(array['admin','super_admin']::public.app_role[]));
