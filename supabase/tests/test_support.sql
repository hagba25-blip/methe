-- Tests support client (phase 11) : demandes, messages, statuts, anti-spam, RLS
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
-- S = joueur, T = autre joueur. D = membre de l'équipe (finance).
insert into auth.users (id, email, raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000081', 'sup-s@example.com',
  '{"first_name":"Sena","last_name":"S","phone":"+22890000081","country_code":"TG","language_code":"fr","currency_code":"XOF","accept_terms":true,"accept_privacy":true}'),
 ('00000000-0000-0000-0000-000000000082', 'sup-t@example.com',
  '{"first_name":"Tchilla","last_name":"S","phone":"+22890000082","country_code":"TG","language_code":"fr","currency_code":"XOF","accept_terms":true,"accept_privacy":true}');

do $$ begin
  assert (select count(*) from public.faq_entries where is_published) >= 10, 'questions fréquentes de départ';
  raise notice 'OK  questions fréquentes installées';
end $$;

-- 1. Ouverture : référence, premier message, compteur non lu côté équipe
create temp table t_ticket as
select * from private.open_support_ticket('00000000-0000-0000-0000-000000000081', 'deposit',
  '  Dépôt non crédité  ', 'J''ai payé 2000 F à l''agent hier.', ' dep-20261008-000001 ');
do $$ declare t record; begin
  select * into t from t_ticket;
  assert t.reference like 'SUP-%', 'référence SUP-…';
  assert t.subject = 'Dépôt non crédité' and t.related_reference = 'DEP-20261008-000001', 'sujet et référence nettoyés';
  assert t.status = 'open' and t.staff_unread = 1 and t.user_unread = 0;
  assert (select count(*) from public.support_messages where ticket_id = t.id and not is_staff) = 1;
  raise notice 'OK  demande ouverte %', t.reference;
end $$;

select pg_temp.expect_error($q$ select private.open_support_ticket('00000000-0000-0000-0000-000000000081', 'casino', 'Sujet', 'Message', null) $q$,
  'catégorie inconnue');
select pg_temp.expect_error($q$ select private.open_support_ticket('00000000-0000-0000-0000-000000000081', 'other', 'ab', 'Message', null) $q$,
  'sujet trop court');

-- 2. Un autre joueur ne peut pas écrire dans la demande
select pg_temp.expect_error(format($q$ select private.post_support_message(%L, '00000000-0000-0000-0000-000000000082', false, 'Coucou') $q$,
  (select id from t_ticket)), 'message dans la demande d''un autre');

-- 3. Réponse de l'équipe : statut « répondu », notification, prise en charge
select private.post_support_message((select id from t_ticket), '00000000-0000-0000-0000-00000000000d', true,
  'Nous vérifions avec l''agent.');
do $$ declare t record; begin
  select * into t from public.support_tickets where id = (select id from t_ticket);
  assert t.status = 'answered' and t.user_unread = 1 and t.staff_unread = 0;
  assert t.assigned_to = '00000000-0000-0000-0000-00000000000d', 'pris en charge par le premier qui répond';
  assert exists (select 1 from public.notifications where user_id = t.user_id and type = 'support_reply'
                   and data->>'reference' = t.reference), 'notification au joueur';
  raise notice 'OK  réponse de l''équipe notifiée';
end $$;

-- 4. Résolu par l'équipe, puis rouvert par une réponse du joueur
select private.set_support_status((select id from t_ticket), '00000000-0000-0000-0000-00000000000d', true, 'resolved');
select private.post_support_message((select id from t_ticket), '00000000-0000-0000-0000-000000000081', false,
  'Toujours rien sur mon solde.');
do $$ declare t record; begin
  select * into t from public.support_tickets where id = (select id from t_ticket);
  assert t.status = 'open' and t.staff_unread = 1, 'réponse du joueur : la demande est rouverte';
  assert exists (select 1 from public.admin_actions where action = 'set_support_status' and target_id = t.reference);
  raise notice 'OK  demande rouverte par le joueur';
end $$;

-- 5. Le joueur ne peut que fermer ; une demande fermée n'accepte plus de message
select pg_temp.expect_error(format($q$ select private.set_support_status(%L, '00000000-0000-0000-0000-000000000081', false, 'resolved') $q$,
  (select id from t_ticket)), 'joueur qui résout lui-même');
select private.set_support_status((select id from t_ticket), '00000000-0000-0000-0000-000000000081', false, 'closed');
select pg_temp.expect_error(format($q$ select private.post_support_message(%L, '00000000-0000-0000-0000-00000000000d', true, 'Re') $q$,
  (select id from t_ticket)), 'message dans une demande fermée');
select pg_temp.expect_error(format($q$ select private.set_support_status(%L, '00000000-0000-0000-0000-00000000000d', true, 'open') $q$,
  (select id from t_ticket)), 'rouvrir une demande fermée');
select pg_temp.expect_error($q$ update public.support_messages set body = 'modifié' $q$, 'modifier un message');

-- 6. Limites : demandes ouvertes et messages par heure
update public.app_settings set value = '2' where key = 'support.max_open_tickets';
select private.open_support_ticket('00000000-0000-0000-0000-000000000082', 'bet', 'Pari 1', 'Question 1', null);
select private.open_support_ticket('00000000-0000-0000-0000-000000000082', 'bet', 'Pari 2', 'Question 2', null);
select pg_temp.expect_error($q$ select private.open_support_ticket('00000000-0000-0000-0000-000000000082', 'bet', 'Pari 3', 'Question 3', null) $q$,
  '3e demande ouverte');
update public.app_settings set value = '2' where key = 'support.max_messages_per_hour';  -- T a déjà écrit 2 messages
select pg_temp.expect_error($q$ select private.post_support_message(
    (select id from public.support_tickets where user_id = '00000000-0000-0000-0000-000000000082' limit 1),
    '00000000-0000-0000-0000-000000000082', false, 'Encore') $q$, '3e message dans l''heure');

update public.app_settings set value = '20' where key = 'support.max_messages_per_hour';

-- 7. Compte suspendu : peut toujours écrire au support
update public.profiles set status = 'suspended' where id = '00000000-0000-0000-0000-000000000081';
select private.open_support_ticket('00000000-0000-0000-0000-000000000081', 'account', 'Compte suspendu', 'Pourquoi ?', null);
do $$ begin raise notice 'OK  un compte suspendu peut écrire au support'; end $$;

-- 8. RLS : chaque joueur ne voit que ses demandes ; FAQ publiée lisible sans compte
update public.faq_entries set is_published = false
 where id = (select min(id) from public.faq_entries);
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000082';
do $$ begin
  assert (select count(*) from public.support_tickets) = 2, 'T voit ses 2 demandes seulement';
  assert not exists (select 1 from public.support_messages m join public.support_tickets t on t.id = m.ticket_id
                      where t.user_id <> '00000000-0000-0000-0000-000000000082'), 'messages des autres invisibles';
  raise notice 'OK  demandes privées';
end $$;
select pg_temp.expect_error($q$ insert into public.support_messages (ticket_id, author_id, is_staff, body)
  select id, '00000000-0000-0000-0000-000000000082', true, 'faux support' from public.support_tickets limit 1 $q$,
  'écriture directe depuis l''application');
reset role;
set local role anon;
do $$ begin
  assert not exists (select 1 from public.faq_entries where not is_published), 'brouillon masqué';
  assert (select count(*) from public.faq_entries) >= 10;
  raise notice 'OK  FAQ publiée lisible sans compte, brouillons masqués';
end $$;
reset role;
rollback;

do $$ begin raise notice 'TESTS SUPPORT PASSÉS'; end $$;
