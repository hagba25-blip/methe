-- =============================================================================
-- 0015 — Connexion en deux étapes : ID client + mot de passe, puis code par e-mail
-- =============================================================================
-- 1. Le joueur saisit son ID client (ou son e-mail) et son mot de passe.
--    private.start_login vérifie le mot de passe en base (sans ouvrir de session),
--    compte les échecs (5 en 15 min → compte verrouillé 15 min) et crée un
--    « défi » valable 10 minutes.
-- 2. Le serveur demande à Supabase Auth d'envoyer un code à usage unique à
--    l'e-mail du compte ; le joueur le saisit, Supabase le vérifie et ouvre la
--    session. 5 codes faux par défi au maximum.
-- Le backend refuse ensuite toute session ouverte avec le mot de passe seul.
-- Rien ici n'est accessible depuis l'application : tout est dans le schéma private.

create table if not exists private.login_attempts (
  id          bigint generated always as identity primary key,
  user_id     uuid references auth.users(id) on delete cascade,
  succeeded   boolean not null,
  ip          text,
  created_at  timestamptz not null default now()
);
create index if not exists login_attempts_user_idx on private.login_attempts (user_id, created_at desc);

create table if not exists private.login_challenges (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  email        text not null,
  attempts     int not null default 0,
  ip           text,
  created_at   timestamptz not null default now(),
  expires_at   timestamptz not null default now() + interval '10 minutes',
  consumed_at  timestamptz
);
create index if not exists login_challenges_user_idx on private.login_challenges (user_id, created_at desc);

-- Statuts : ok | invalid (identifiant ou mot de passe faux) | locked | inactive
create or replace function private.start_login(p_identifier text, p_password text, p_ip text default null)
returns table (status text, challenge_id uuid, user_id uuid, email text)
language plpgsql security definer set search_path = '' as $$
declare
  v_id     text := lower(trim(coalesce(p_identifier, '')));
  v_user   uuid;
  v_hash   text;
  v_email  text;
  v_banned timestamptz;
  v_state  public.account_status;
  v_fails  int;
  v_chal   uuid;
begin
  if v_id ~ '^6[0-9]{9}$' then
    select p.id into v_user from public.profiles p where p.public_id = v_id;
  elsif position('@' in v_id) > 1 then
    select u.id into v_user from auth.users u where lower(u.email) = v_id;
  end if;

  if v_user is null then
    return query select 'invalid'::text, null::uuid, null::uuid, null::text;
    return;
  end if;

  select count(*) into v_fails from private.login_attempts a
   where a.user_id = v_user and not a.succeeded and a.created_at > now() - interval '15 minutes';
  if v_fails >= 5 then
    return query select 'locked'::text, null::uuid, v_user, null::text;
    return;
  end if;

  select u.encrypted_password, u.email, u.banned_until into v_hash, v_email, v_banned
    from auth.users u where u.id = v_user;
  if v_hash is null or v_hash = '' or extensions.crypt(coalesce(p_password, ''), v_hash) <> v_hash then
    insert into private.login_attempts (user_id, succeeded, ip) values (v_user, false, p_ip);
    return query select 'invalid'::text, null::uuid, v_user, null::text;
    return;
  end if;

  select p.status into v_state from public.profiles p where p.id = v_user;
  if v_email is null or (v_banned is not null and v_banned > now()) or v_state in ('blocked', 'closed') then
    return query select 'inactive'::text, null::uuid, v_user, null::text;
    return;
  end if;

  insert into private.login_attempts (user_id, succeeded, ip) values (v_user, true, p_ip);
  -- Un seul défi actif par compte : les précédents ne servent plus.
  update private.login_challenges c set consumed_at = now()
   where c.user_id = v_user and c.consumed_at is null;
  insert into private.login_challenges (user_id, email, ip) values (v_user, v_email, p_ip)
  returning id into v_chal;
  return query select 'ok'::text, v_chal, v_user, v_email;
end $$;

-- Réserve un essai de code sur un défi encore valable ; renvoie l'e-mail (ou rien).
create or replace function private.use_login_challenge(p_challenge uuid)
returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_email text;
begin
  update private.login_challenges c set attempts = c.attempts + 1
   where c.id = p_challenge and c.consumed_at is null and c.expires_at > now() and c.attempts < 5
  returning c.email into v_email;
  return v_email;
end $$;

create or replace function private.finish_login_challenge(p_challenge uuid)
returns void
language plpgsql security definer set search_path = '' as $$
begin
  update private.login_challenges c set consumed_at = now() where c.id = p_challenge;
  update public.profiles p set last_login_at = now()
   where p.id = (select c.user_id from private.login_challenges c where c.id = p_challenge);
end $$;

-- Ménage : on garde 30 jours d'historique de connexion.
create or replace function private.purge_login_history()
returns void
language sql security definer set search_path = '' as $$
  delete from private.login_attempts where created_at < now() - interval '30 days';
  delete from private.login_challenges where created_at < now() - interval '1 day';
$$;

revoke all on function private.start_login(text, text, text) from public, anon, authenticated;
revoke all on function private.use_login_challenge(uuid) from public, anon, authenticated;
revoke all on function private.finish_login_challenge(uuid) from public, anon, authenticated;
revoke all on function private.purge_login_history() from public, anon, authenticated;

do $$
begin
  if to_regclass('cron.job') is not null then
    perform cron.unschedule(jobid) from cron.job where jobname = 'methe-login-purge';
    perform cron.schedule('methe-login-purge', '17 3 * * *', 'select private.purge_login_history()');
  end if;
end $$;
