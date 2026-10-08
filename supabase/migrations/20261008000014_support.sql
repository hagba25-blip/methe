-- =============================================================================
-- 0014 — Support client : demandes d'aide (tickets), messages, questions fréquentes
-- =============================================================================
-- Un joueur ouvre une demande (catégorie, sujet, premier message, référence
-- éventuelle d'un dépôt / retrait / pari). L'équipe répond dans la même
-- conversation ; le joueur reçoit une notification. Un compte suspendu ou bloqué
-- peut toujours écrire au support. Les messages ne sont jamais modifiés.

insert into public.app_settings (key, value, is_public, description) values
  ('support.max_open_tickets',       '5',  false, 'Demandes d''aide ouvertes en même temps par joueur'),
  ('support.max_messages_per_hour',  '20', false, 'Messages au support par joueur et par heure (anti-spam)'),
  ('support.whatsapp_number',        'null', true, 'Numéro WhatsApp du support affiché dans l''aide (null = masqué)'),
  ('support.hours',                  '"Tous les jours, 8 h – 22 h"', true, 'Horaires du support affichés dans l''aide')
on conflict (key) do nothing;

-- Nouveau type de notification : réponse du support
alter table public.notifications drop constraint if exists notifications_type_check;
alter table public.notifications add constraint notifications_type_check check (type in (
  'deposit_approved','deposit_rejected','withdrawal_approved','withdrawal_paid',
  'withdrawal_rejected','bet_placed','result_available','bet_won','winnings_credited',
  'account_change','support_reply'));

-- Questions fréquentes -----------------------------------------------------------
create table if not exists public.faq_entries (
  id             bigint generated always as identity primary key,
  category       text not null check (category in ('account','deposit','withdrawal','games','security')),
  language_code  text not null default 'fr' references public.languages(code),
  question       text not null check (length(trim(question)) between 5 and 200),
  answer         text not null check (length(trim(answer)) between 5 and 4000),
  sort_order     int not null default 100,
  is_published   boolean not null default true,
  updated_by     uuid references public.profiles(id),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index if not exists faq_entries_list_idx on public.faq_entries(language_code, category, sort_order);
drop trigger if exists faq_entries_touch on public.faq_entries;
create trigger faq_entries_touch before update on public.faq_entries
  for each row execute function private.touch_updated_at();
drop trigger if exists faq_entries_audit on public.faq_entries;
create trigger faq_entries_audit after insert or update or delete on public.faq_entries
  for each row execute function private.audit_row();

-- Demandes d'aide ------------------------------------------------------------------
create table if not exists public.support_tickets (
  id                 uuid primary key default gen_random_uuid(),
  reference          text not null unique default private.next_reference('SUP'),
  user_id            uuid not null references public.profiles(id) on delete restrict,
  category           text not null check (category in ('deposit','withdrawal','bet','account','technical','other')),
  subject            text not null check (length(trim(subject)) between 3 and 120),
  related_reference  text check (related_reference is null or length(related_reference) <= 40),
  -- open : à traiter par l'équipe ; answered : l'équipe a répondu, on attend le joueur ;
  -- resolved : clos par l'équipe (le joueur peut le rouvrir en répondant) ; closed : définitif.
  status             text not null default 'open' check (status in ('open','answered','resolved','closed')),
  assigned_to        uuid references public.profiles(id),
  user_unread        int not null default 0,   -- réponses de l'équipe non lues par le joueur
  staff_unread       int not null default 0,   -- messages du joueur non lus par l'équipe
  last_message_at    timestamptz not null default now(),
  closed_at          timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create index if not exists support_tickets_user_idx  on public.support_tickets(user_id, last_message_at desc);
create index if not exists support_tickets_queue_idx on public.support_tickets(status, last_message_at desc);
drop trigger if exists support_tickets_touch on public.support_tickets;
create trigger support_tickets_touch before update on public.support_tickets
  for each row execute function private.touch_updated_at();

create table if not exists public.support_messages (
  id          bigint generated always as identity primary key,
  ticket_id   uuid not null references public.support_tickets(id) on delete restrict,
  author_id   uuid not null references public.profiles(id),
  is_staff    boolean not null,
  body        text not null check (length(trim(body)) between 1 and 2000),
  created_at  timestamptz not null default now()
);
create index if not exists support_messages_ticket_idx on public.support_messages(ticket_id, id);
drop trigger if exists support_messages_immutable on public.support_messages;
create trigger support_messages_immutable before update or delete on public.support_messages
  for each row execute function private.ledger_immutable();

-- Anti-spam : messages d'un joueur sur la dernière heure.
create or replace function private.check_support_rate(p_user_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if (select count(*) from public.support_messages
       where author_id = p_user_id and not is_staff and created_at > now() - interval '1 hour')
     >= private.setting_bigint('support.max_messages_per_hour', 20) then
    raise exception 'Trop de messages en peu de temps : réessayez plus tard' using errcode = 'P0001';
  end if;
end $$;

-- Ouverture d'une demande par le joueur.
create or replace function private.open_support_ticket(
  p_user_id uuid, p_category text, p_subject text, p_body text, p_related_reference text)
returns public.support_tickets language plpgsql security definer set search_path = '' as $$
declare v_ticket public.support_tickets%rowtype;
begin
  if not exists (select 1 from public.profiles where id = p_user_id and status <> 'closed') then
    raise exception 'Compte introuvable ou fermé' using errcode = 'P0001';
  end if;
  if (select count(*) from public.support_tickets where user_id = p_user_id and status in ('open','answered'))
     >= private.setting_bigint('support.max_open_tickets', 5) then
    raise exception 'Vous avez déjà plusieurs demandes en cours : répondez-y ou attendez notre réponse'
      using errcode = 'P0001';
  end if;
  perform private.check_support_rate(p_user_id);

  insert into public.support_tickets (user_id, category, subject, related_reference, staff_unread)
  values (p_user_id, p_category, trim(p_subject), nullif(upper(trim(coalesce(p_related_reference, ''))), ''), 1)
  returning * into v_ticket;
  insert into public.support_messages (ticket_id, author_id, is_staff, body)
  values (v_ticket.id, p_user_id, false, trim(p_body));
  return v_ticket;
end $$;

-- Nouveau message dans une demande (joueur ou équipe).
create or replace function private.post_support_message(
  p_ticket_id uuid, p_author_id uuid, p_as_staff boolean, p_body text)
returns public.support_tickets language plpgsql security definer set search_path = '' as $$
declare v_ticket public.support_tickets%rowtype;
begin
  select * into v_ticket from public.support_tickets where id = p_ticket_id for update;
  if not found or (not p_as_staff and v_ticket.user_id <> p_author_id) then
    raise exception 'Demande introuvable' using errcode = 'P0002';
  end if;
  if v_ticket.status = 'closed' then
    raise exception 'Cette demande est fermée : ouvrez-en une nouvelle' using errcode = 'P0001';
  end if;

  if p_as_staff then
    if v_ticket.user_id = p_author_id then
      raise exception 'Vous ne pouvez pas traiter votre propre demande' using errcode = 'P0001';
    end if;
    insert into public.support_messages (ticket_id, author_id, is_staff, body)
    values (p_ticket_id, p_author_id, true, trim(p_body));
    update public.support_tickets
       set status = 'answered', user_unread = user_unread + 1, staff_unread = 0,
           assigned_to = coalesce(assigned_to, p_author_id), last_message_at = now()
     where id = p_ticket_id returning * into v_ticket;
    insert into public.notifications (user_id, type, title, body, data) values (
      v_ticket.user_id, 'support_reply', 'Réponse du support',
      format('Nous avons répondu à votre demande « %s ».', v_ticket.subject),
      jsonb_build_object('ticket_id', v_ticket.id, 'reference', v_ticket.reference));
  else
    perform private.check_support_rate(p_author_id);
    insert into public.support_messages (ticket_id, author_id, is_staff, body)
    values (p_ticket_id, p_author_id, false, trim(p_body));
    -- Répondre à une demande résolue la rouvre.
    update public.support_tickets
       set status = 'open', staff_unread = staff_unread + 1, user_unread = 0, last_message_at = now()
     where id = p_ticket_id returning * into v_ticket;
  end if;
  return v_ticket;
end $$;

-- Changement de statut : l'équipe résout / ferme / rouvre ; le joueur peut fermer la sienne.
create or replace function private.set_support_status(
  p_ticket_id uuid, p_actor_id uuid, p_as_staff boolean, p_status text)
returns public.support_tickets language plpgsql security definer set search_path = '' as $$
declare
  v_ticket public.support_tickets%rowtype;
  v_old    text;
begin
  select * into v_ticket from public.support_tickets where id = p_ticket_id for update;
  if not found or (not p_as_staff and v_ticket.user_id <> p_actor_id) then
    raise exception 'Demande introuvable' using errcode = 'P0002';
  end if;
  if not p_as_staff and p_status <> 'closed' then
    raise exception 'Action non autorisée' using errcode = 'P0001';
  end if;
  if p_status not in ('open','resolved','closed') then
    raise exception 'Statut invalide' using errcode = 'P0001';
  end if;
  if v_ticket.status = 'closed' and p_status <> 'closed' then
    raise exception 'Cette demande est fermée définitivement' using errcode = 'P0001';
  end if;
  v_old := v_ticket.status;
  if v_old = p_status then
    return v_ticket;
  end if;
  update public.support_tickets
     set status = p_status,
         closed_at = case when p_status = 'closed' then now() end,
         staff_unread = case when p_as_staff then 0 else staff_unread end,
         user_unread = case when p_as_staff then user_unread else 0 end
   where id = p_ticket_id returning * into v_ticket;
  if p_as_staff then
    insert into public.admin_actions (admin_id, action, target_type, target_id, reason, payload)
    values (p_actor_id, 'set_support_status', 'support_ticket', v_ticket.reference, null,
            jsonb_build_object('from', v_old, 'to', p_status));
  end if;
  return v_ticket;
end $$;

-- Droits et RLS --------------------------------------------------------------------
alter table public.faq_entries      enable row level security;
alter table public.support_tickets  enable row level security;
alter table public.support_messages enable row level security;
revoke insert, update, delete, truncate on public.faq_entries, public.support_tickets, public.support_messages
  from anon, authenticated;

drop policy if exists faq_entries_read_anon on public.faq_entries;
create policy faq_entries_read_anon on public.faq_entries for select to anon using (is_published);
drop policy if exists faq_entries_read on public.faq_entries;
create policy faq_entries_read on public.faq_entries for select to authenticated
  using (is_published or private.is_staff());
drop policy if exists support_tickets_read on public.support_tickets;
create policy support_tickets_read on public.support_tickets for select to authenticated
  using (user_id = auth.uid() or private.is_staff());
drop policy if exists support_messages_read on public.support_messages;
create policy support_messages_read on public.support_messages for select to authenticated
  using (exists (select 1 from public.support_tickets t
                  where t.id = ticket_id and (t.user_id = auth.uid() or private.is_staff())));

revoke execute on all functions in schema private from public, anon, authenticated;
grant execute on function private.has_role(public.app_role[]) to authenticated;
grant execute on function private.is_staff() to authenticated;

-- Questions fréquentes de départ (modifiables depuis l'administration) ----------------
insert into public.languages (code, name) values ('fr', 'Français') on conflict do nothing;
insert into public.faq_entries (category, question, answer, sort_order)
select v.category, v.question, v.answer, v.sort_order
from (values
  ('account', 'Qu''est-ce que mon ID client ?',
   'C''est le numéro à 10 chiffres qui commence par 6, affiché sur l''accueil et dans Profil. Donnez-le au support ou à l''agent pour tout dépôt : il identifie votre compte. Il ne change jamais.', 10),
  ('account', 'Comment changer mon nom ou ma langue ?',
   'Ouvrez Profil puis Modifier profil. Votre numéro de téléphone et votre ID client ne peuvent pas être modifiés ; pour un changement de numéro, écrivez au support.', 20),
  ('account', 'Pourquoi mon compte est-il suspendu ?',
   'Un compte peut être suspendu pendant une vérification (identité, paiement, activité inhabituelle). Votre solde reste intact. Écrivez au support depuis l''aide : nous vous dirons quoi faire.', 30),
  ('deposit', 'Comment déposer de l''argent ?',
   'Touchez DÉPOSER, choisissez le montant puis un agent : WhatsApp s''ouvre avec le message déjà écrit, qui contient votre ID client. Envoyez-le et payez l''agent. Dès que le paiement est vérifié, votre solde est crédité et vous recevez une notification.', 10),
  ('deposit', 'Mon dépôt n''apparaît pas, que faire ?',
   'Vérifiez dans Profil > Historique que la demande est « En attente ». Si elle y est depuis longtemps, ouvrez une demande d''aide catégorie Dépôt en indiquant la référence (DEP-…) et l''identifiant de la transaction Mobile Money.', 20),
  ('withdrawal', 'Comment retirer mes gains ?',
   'Touchez RETIRER, saisissez le montant et le numéro Mobile Money qui recevra l''argent. Le montant est réservé sur votre solde jusqu''au paiement. Vous pouvez annuler tant que la demande est en attente.', 10),
  ('withdrawal', 'Pourquoi mon retrait prend-il du temps ?',
   'Chaque retrait est vérifié par l''équipe avant paiement, pour protéger votre compte. Un retrait vers un numéro qui n''est pas le vôtre, ou juste après un dépôt sans avoir joué, demande une vérification plus longue.', 20),
  ('games', 'Comment fonctionne le Jeu des Fruits ?',
   'Un fruit gagnant parmi 20 est tiré toutes les heures. Les mises sur le fruit gagnant se partagent la cagnotte, après la commission de la plateforme. Le gain estimé affiché change donc avec les mises des autres joueurs.', 10),
  ('games', 'Comment fonctionne le Lonato ?',
   '5 numéros gagnants parmi 01 à 90 sont tirés toutes les 3 heures. PERME : 2 à 10 numéros, le gain dépend du nombre de vos numéros qui sortent. NAPE : 3 à 5 numéros, gain si tous sortent. CHOX : un numéro, gain s''il sort. Les cotes sont affichées avant de valider.', 20),
  ('games', 'Les tirages sont-ils truqués ?',
   'Non. Chaque tirage utilise un nombre secret publié à l''avance sous forme d''empreinte, puis révélé après le tirage. Dans Mes paris, touchez un pari puis Vérifier pour contrôler vous-même le résultat.', 30),
  ('security', 'Comment protéger mon compte ?',
   'Ne communiquez jamais votre mot de passe, même au support : nous ne le demandons jamais. Déconnectez-vous sur un téléphone partagé. En cas de doute, changez votre mot de passe et écrivez-nous.', 10)
) as v(category, question, answer, sort_order)
where not exists (select 1 from public.faq_entries);

