-- Tests connexion en deux étapes (phase 14) : mot de passe, verrouillage, défi du code
\set ON_ERROR_STOP 1

begin;
insert into auth.users (id, email, encrypted_password, raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000091', 'Login-L@example.com', extensions.crypt('Bon-Mot-2026', extensions.gen_salt('bf')),
  '{"first_name":"Lina","last_name":"L","phone":"+22890000091","country_code":"TG","language_code":"fr","currency_code":"XOF","accept_terms":true,"accept_privacy":true}'),
 ('00000000-0000-0000-0000-000000000092', 'login-m@example.com', extensions.crypt('Autre-Mot-2026', extensions.gen_salt('bf')),
  '{"first_name":"Mawu","last_name":"L","phone":"+22890000092","country_code":"TG","language_code":"fr","currency_code":"XOF","accept_terms":true,"accept_privacy":true}');

do $$
declare
  v_pid  text := (select public_id from public.profiles where id = '00000000-0000-0000-0000-000000000091');
  r      record;
  v_chal uuid;
  i      int;
begin
  -- 1. Bon mot de passe avec l'ID client, puis avec l'e-mail (casse et espaces ignorés)
  select * into r from private.start_login(v_pid, 'Bon-Mot-2026', '1.2.3.4');
  assert r.status = 'ok' and r.challenge_id is not null and r.email = 'Login-L@example.com', 'connexion par ID';
  v_chal := r.challenge_id;
  select * into r from private.start_login('  login-l@EXAMPLE.com ', 'Bon-Mot-2026');
  assert r.status = 'ok', 'connexion par e-mail';
  assert (select consumed_at is not null from private.login_challenges where id = v_chal), 'ancien défi annulé';
  v_chal := r.challenge_id;
  raise notice 'OK  connexion par ID client ou e-mail';

  -- 2. Erreurs : mot de passe faux, ID inconnu, mot de passe d'un autre compte
  assert (select status from private.start_login(v_pid, 'mauvais')) = 'invalid', 'mot de passe faux';
  assert (select status from private.start_login('6000000000', 'Bon-Mot-2026')) = 'invalid', 'ID inconnu';
  assert (select status from private.start_login(v_pid, 'Autre-Mot-2026')) = 'invalid', 'mot de passe d''un autre';
  assert (select status from private.start_login('', '')) = 'invalid', 'champs vides';
  raise notice 'OK  identifiants faux refusés';

  -- 3. Défi : 5 essais de code au maximum, puis plus rien
  for i in 1..5 loop
    assert private.use_login_challenge(v_chal) = 'Login-L@example.com', 'essai ' || i;
  end loop;
  assert private.use_login_challenge(v_chal) is null, '6e essai refusé';
  assert private.use_login_challenge(gen_random_uuid()) is null, 'défi inconnu';
  raise notice 'OK  5 essais de code par défi';

  -- 4. Défi expiré ou déjà utilisé
  select challenge_id into v_chal from private.start_login(v_pid, 'Bon-Mot-2026');
  perform private.finish_login_challenge(v_chal);
  assert private.use_login_challenge(v_chal) is null, 'défi déjà utilisé';
  assert (select last_login_at is not null from public.profiles where id = '00000000-0000-0000-0000-000000000091'),
    'dernière connexion enregistrée';
  select challenge_id into v_chal from private.start_login(v_pid, 'Bon-Mot-2026');
  update private.login_challenges set expires_at = now() - interval '1 second' where id = v_chal;
  assert private.use_login_challenge(v_chal) is null, 'défi expiré';
  raise notice 'OK  défi expiré ou utilisé refusé';

  -- 5. Verrouillage : 5 échecs en 15 min bloquent même le bon mot de passe (2 échecs déjà faits)
  perform private.start_login(v_pid, 'faux-3');
  perform private.start_login(v_pid, 'faux-4');
  assert (select status from private.start_login(v_pid, 'Bon-Mot-2026')) = 'ok', 'encore ouvert après 4 échecs';
  perform private.start_login(v_pid, 'faux-5');
  assert (select status from private.start_login(v_pid, 'Bon-Mot-2026')) = 'locked', 'compte verrouillé';
  assert (select status from private.start_login('login-m@example.com', 'Autre-Mot-2026')) = 'ok', 'autre compte libre';
  update private.login_attempts set created_at = now() - interval '16 minutes'
   where user_id = '00000000-0000-0000-0000-000000000091';
  assert (select status from private.start_login(v_pid, 'Bon-Mot-2026')) = 'ok', 'déverrouillé après 15 min';
  raise notice 'OK  verrouillage après 5 échecs';

  -- 6. Compte bloqué ou banni : pas de code envoyé
  update public.profiles set status = 'blocked' where id = '00000000-0000-0000-0000-000000000092';
  assert (select status from private.start_login('login-m@example.com', 'Autre-Mot-2026')) = 'inactive', 'compte bloqué';
  update public.profiles set status = 'active' where id = '00000000-0000-0000-0000-000000000092';
  update auth.users set banned_until = now() + interval '1 day' where id = '00000000-0000-0000-0000-000000000092';
  assert (select status from private.start_login('login-m@example.com', 'Autre-Mot-2026')) = 'inactive', 'compte banni';
  raise notice 'OK  comptes bloqués refusés';
end $$;

-- 7. Rien n'est accessible depuis l'application
set local role authenticated;
do $$ begin
  begin
    perform private.start_login('x', 'y');
    raise exception 'ÉCHEC : start_login accessible';
  exception when insufficient_privilege then
    raise notice 'OK  fonctions de connexion inaccessibles depuis l''application';
  end;
end $$;
reset role;
rollback;

do $$ begin raise notice 'TESTS CONNEXION PASSÉS'; end $$;
