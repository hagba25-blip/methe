-- =============================================================================
-- methe — Vérification de la base de production (LECTURE SEULE)
-- Supabase > SQL Editor > coller ce fichier > Run. Rien n'est modifié dans vos
-- données : le résultat est un tableau « contrôle / état / détail ».
-- À relancer après chaque mise en ligne. Tout doit être « OK » (ou « À FAIRE »
-- pour un réglage que vous n'avez pas encore choisi).
-- =============================================================================

create temp table if not exists methe_checks (n serial, controle text, etat text, detail text) on commit preserve rows;
truncate methe_checks;

-- 1. Toutes les phases installées
do $$
declare
  v_missing text[];
begin
  select array_agg(t) into v_missing from unnest(array[
    'profiles','wallets','ledger_journals','wallet_transactions','deposits','withdrawals','agents',
    'games','game_types','game_rounds','bets','payout_rules','risk_events','admin_actions','audit_logs',
    'notifications','app_settings','support_tickets','support_messages','faq_entries']) t
  where to_regclass('public.' || t) is null;
  insert into methe_checks (controle, etat, detail) values ('Tables (phases 1 à 11)',
    case when v_missing is null then 'OK' else 'ERREUR' end,
    coalesce('Manquantes : ' || array_to_string(v_missing, ', ') || ' → exécuter les fichiers SQL des phases', '20 tables présentes'));
  insert into methe_checks (controle, etat, detail)
  select 'Sécurité RLS', case when count(*) = 0 then 'OK' else 'ERREUR' end,
         coalesce('Sans RLS : ' || string_agg(tablename, ', '), 'activée sur toutes les tables publiques')
  from pg_tables where schemaname = 'public' and not rowsecurity;
end $$;

insert into methe_checks (controle, etat, detail)
select 'Connexion par code (phase 14)',
       case when to_regprocedure('private.start_login(text,text,text)') is not null then 'OK' else 'ERREUR' end,
       case when to_regprocedure('private.start_login(text,text,text)') is not null
            then 'mot de passe + code e-mail installés'
            else 'exécuter methe-phase14-supabase.sql' end;

-- 2. Moteur de tirage (pg_cron) et tirages récents
do $$
declare
  v_job record;
  v_fail int;
begin
  if to_regclass('cron.job') is null then
    insert into methe_checks (controle, etat, detail) values ('Moteur de tirage (pg_cron)', 'ERREUR',
      'pg_cron non activé : Database > Extensions > pg_cron, puis relancer methe-phase5-supabase.sql');
  else
    execute 'select jobname, schedule, active from cron.job where jobname = ''methe-engine''' into v_job;
    if v_job is null then
      insert into methe_checks (controle, etat, detail) values ('Moteur de tirage (pg_cron)', 'ERREUR',
        'tâche methe-engine absente : relancer methe-phase5-supabase.sql');
    else
      execute 'select count(*) from cron.job_run_details d join cron.job j on j.jobid = d.jobid
               where j.jobname = ''methe-engine'' and d.status = ''failed'' and d.start_time > now() - interval ''1 day'''
        into v_fail;
      insert into methe_checks (controle, etat, detail) values ('Moteur de tirage (pg_cron)',
        case when v_job.active and v_fail = 0 then 'OK' else 'ERREUR' end,
        format('planifié « %s », %s, %s échec(s) sur 24 h', v_job.schedule,
               case when v_job.active then 'actif' else 'INACTIF' end, v_fail));
    end if;
  end if;
end $$;

insert into methe_checks (controle, etat, detail)
select 'Tirage ouvert : ' || g.code,
       case when r.id is not null then 'OK' else 'ERREUR' end,
       coalesce(format('n° %s, fin des mises %s (UTC)', r.round_number, to_char(r.closes_at, 'DD/MM HH24:MI')),
                'aucun tirage ouvert : vérifier le moteur de tirage')
from public.games g
left join lateral (select * from public.game_rounds x
                    where x.game_code = g.code and x.status = 'open' order by x.draw_at limit 1) r on true
where g.is_active;

insert into methe_checks (controle, etat, detail)
select 'Tirages en retard', case when count(*) = 0 then 'OK' else 'ERREUR' end,
       case when count(*) = 0 then 'aucun tirage passé non publié'
            else count(*) || ' tirage(s) passé(s) depuis plus de 5 min sans résultat' end
from public.game_rounds where status in ('open', 'closed', 'drawn') and draw_at < now() - interval '5 minutes';

-- 3. Administration
insert into methe_checks (controle, etat, detail)
select 'Comptes administrateurs', case when count(*) filter (where a.role = 'super_admin') > 0 then 'OK' else 'ERREUR' end,
       coalesce(string_agg(p.first_name || ' ' || p.last_name || ' (' || a.role || ')', ', '), 'aucun')
from public.admin_users a join public.profiles p on p.id = a.user_id where a.is_active;

insert into methe_checks (controle, etat, detail)
select 'Comptes système', case when count(*) >= 4 then 'OK' else 'ERREUR' end,
       string_agg(system_code || ' ' || currency_code || ' = ' || balance, ', ' order by system_code, currency_code)
from public.wallets where owner_type = 'system';

-- 4. Réglages à confirmer par l'exploitant
insert into methe_checks (controle, etat, detail)
select 'Réglage ' || key,
       case when key = 'support.whatsapp_number' and value = 'null'::jsonb then 'À FAIRE' else 'OK' end,
       value::text || ' — ' || coalesce(description, '')
from public.app_settings
where key in ('withdrawal.min_amount', 'withdrawal.max_amount', 'withdrawal.fee_percent', 'deposit.min_amount',
              'deposit.max_amount', 'pool.commission_percent', 'support.whatsapp_number', 'support.hours')
order by key;

-- 5. Intégrité de l'argent (mêmes règles que les tests automatiques)
do $$
declare
  v_errors text[] := '{}';
  r record;
begin
  for r in select j.reference from public.ledger_journals j join public.wallet_transactions t on t.journal_id = j.id
            group by j.reference having sum(t.amount) <> 0 loop
    v_errors := v_errors || ('journal déséquilibré ' || r.reference);
  end loop;
  for r in select coalesce(w.system_code, w.user_id::text) as owner from public.wallets w
            left join public.wallet_transactions t on t.wallet_id = w.id
            group by w.id having w.balance <> coalesce(sum(t.amount), 0) loop
    v_errors := v_errors || ('solde ≠ mouvements : ' || r.owner);
  end loop;
  for r in select user_id from public.wallets where owner_type = 'user' and balance < 0 loop
    v_errors := v_errors || ('joueur en négatif : ' || r.user_id);
  end loop;
  for r in select w.currency_code from public.wallets w where w.system_code = 'WITHDRAWAL_HOLD'
            and w.balance <> coalesce((select sum(d.amount) from public.withdrawals d where d.currency_code = w.currency_code
                                        and d.hold_journal_id is not null
                                        and d.status in ('pending', 'under_review', 'approved')), 0) loop
    v_errors := v_errors || ('montant bloqué ≠ retraits en cours (' || r.currency_code || ')');
  end loop;
  for r in select b.reference from public.bets b join public.game_rounds g on g.id = b.round_id
            where b.status = 'pending' and g.status in ('settled', 'cancelled') loop
    v_errors := v_errors || ('pari non réglé ' || r.reference);
  end loop;
  insert into methe_checks (controle, etat, detail) values ('Intégrité de l''argent',
    case when cardinality(v_errors) = 0 then 'OK' else 'ERREUR' end,
    case when cardinality(v_errors) = 0
         then format('%s écritures, %s portefeuilles, %s paris contrôlés',
                     (select count(*) from public.ledger_journals), (select count(*) from public.wallets),
                     (select count(*) from public.bets))
         else array_to_string(v_errors[1:10], ' ; ') end);
end $$;

select controle, etat, detail from methe_checks order by n;
