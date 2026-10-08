-- Tests du moteur de tirage (phase 5)
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

-- Le temps est simulé : on part du 1er janvier 2030 à 10h20 UTC.
do $$
declare
  t0 constant timestamptz := '2030-01-01 10:20:00+00';
  r  jsonb;
  f  public.game_rounds;
  l  public.game_rounds;
begin
  r := private.engine_tick(t0);
  assert (r->>'created')::int = 4, 'deux créneaux à l''avance par jeu : ' || r;
  assert (r->>'opened')::int = 2, 'le tour en cours de chaque jeu est ouvert : ' || r;

  select * into f from public.game_rounds where game_code = 'FRUITS' and draw_at = '2030-01-01 11:00:00+00';
  assert f.status = 'open' and f.opens_at = '2030-01-01 10:00:00+00' and f.closes_at = '2030-01-01 10:59:00+00', 'horaires Fruits';
  assert f.commitment_hash ~ '^[0-9a-f]{64}$' and f.revealed_seed is null and f.result is null, 'engagement publié, graine cachée';
  assert exists (select 1 from private.round_secrets where round_id = f.id), 'graine stockée en privé';

  select * into l from public.game_rounds where game_code = 'LONATO' and status = 'open';
  assert l.draw_at = '2030-01-01 12:00:00+00' and l.closes_at = '2030-01-01 11:58:00+00', 'Lonato toutes les 3 h (09h, 12h, 15h…)';
  assert (select count(*) from public.game_rounds where game_code = 'FRUITS' and status = 'scheduled'
            and draw_at = '2030-01-01 12:00:00+00') = 1, 'tour suivant programmé';

  r := private.engine_tick(t0);
  assert (r->>'created')::int = 0 and (r->>'opened')::int = 0, 'idempotent : ' || r;
  raise notice 'OK  planification, ouverture, engagement, idempotence';

  -- 10h59 : fermeture des mises Fruits
  r := private.engine_tick('2030-01-01 10:59:00+00');
  assert (select status from public.game_rounds where id = f.id) = 'closed', 'fermé à H-1 min';
  assert (select status from public.game_rounds where id = l.id) = 'open', 'Lonato toujours ouvert';

  -- 11h00 : tirage + publication, ouverture du tour suivant
  r := private.engine_tick('2030-01-01 11:00:00+00');
  select * into f from public.game_rounds where id = f.id;
  assert f.status = 'published' and f.result ? 'fruit' and f.revealed_seed is not null, 'tiré et publié : ' || r;
  assert exists (select 1 from public.game_symbols where game_code = 'FRUITS' and code = f.result->>'fruit'), 'fruit valide';
  assert encode(extensions.digest(decode(f.revealed_seed, 'hex'), 'sha256'), 'hex') = f.commitment_hash, 'graine conforme';
  assert f.result = private.compute_result('FRUITS', f.revealed_seed, f.id), 'résultat recalculable';
  assert (select status from public.game_rounds where game_code = 'FRUITS' and draw_at = '2030-01-01 12:00:00+00') = 'open',
         'tour suivant ouvert';
  raise notice 'OK  fermeture, tirage, publication, vérification';

  -- 12h00 : tirage Lonato
  perform private.engine_tick('2030-01-01 11:58:00+00');
  perform private.engine_tick('2030-01-01 12:00:00+00');
  select * into l from public.game_rounds where id = l.id;
  assert l.status = 'published', 'Lonato publié';
  assert jsonb_array_length(l.result->'numbers') = 5, '5 numéros';
  assert (select count(distinct n) from jsonb_array_elements_text(l.result->'numbers') n where n::int between 1 and 90) = 5,
         'distincts entre 01 et 90';
  raise notice 'OK  tirage Lonato : %', l.result;

  -- Moteur arrêté pendant 3 heures : les tours manqués sont annulés, pas tirés à l'aveugle
  r := private.engine_tick('2030-01-01 15:30:00+00');
  assert (r->>'cancelled_missed')::int >= 1, 'tours manqués annulés : ' || r;
  assert (select status from public.game_rounds where game_code = 'FRUITS' and draw_at = '2030-01-01 16:00:00+00') = 'open',
         'reprise sur le tour en cours';
  raise notice 'OK  reprise après arrêt du moteur : %', r;
end $$;

-- Verrous : rien ne peut réécrire un résultat publié ni la graine
select pg_temp.expect_error($q$
  update public.game_rounds set result = '{"fruit":"POMME"}'
   where game_code = 'FRUITS' and draw_at = '2030-01-01 11:00:00+00' $q$, 'réécriture du résultat');
select pg_temp.expect_error($q$
  update public.game_rounds set revealed_seed = repeat('0', 64)
   where game_code = 'FRUITS' and draw_at = '2030-01-01 11:00:00+00' $q$, 'réécriture de la graine');
select pg_temp.expect_error($q$
  update public.game_rounds set commitment_hash = repeat('0', 64)
   where game_code = 'FRUITS' and draw_at = '2030-01-01 16:00:00+00' $q$, 'changement d''engagement après ouverture');
select pg_temp.expect_error($q$
  select private.cancel_round((select id from public.game_rounds where game_code = 'FRUITS' and draw_at = '2030-01-01 11:00:00+00'),
                              '00000000-0000-0000-0000-00000000000d', 'test') $q$, 'annulation d''un tour publié');

do $$
declare v public.game_rounds;
begin
  v := private.cancel_round((select id from public.game_rounds where game_code = 'FRUITS' and draw_at = '2030-01-01 17:00:00+00'),
                            '00000000-0000-0000-0000-00000000000d', 'Maintenance');
  assert v.status = 'cancelled';
  assert exists (select 1 from public.admin_actions where action = 'cancel_round'), 'trace admin';
  raise notice 'OK  annulation d''un tour programmé';
end $$;

-- Distribution : 2 000 tirages de fruits, chaque fruit doit sortir (≈100 fois chacun)
do $$
declare v_min int; v_max int;
begin
  select min(c), max(c) into v_min, v_max from (
    select count(*) c from (
      select private.compute_result('FRUITS', encode(extensions.digest(i::text, 'sha256'), 'hex'), gen_random_uuid())->>'fruit' f
      from generate_series(1, 2000) i) s group by f) t;
  assert v_min >= 50 and v_max <= 160, format('distribution anormale : min %s max %s', v_min, v_max);
  raise notice 'OK  distribution des fruits (min %, max % sur 2000)', v_min, v_max;
end $$;

-- RLS : graines invisibles, tours lisibles
begin;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select pg_temp.expect_error($q$ select * from private.round_secrets $q$, 'joueur lit les graines secrètes');
select pg_temp.expect_error($q$ select private.engine_tick() $q$, 'joueur lance le moteur');
do $$ begin
  assert (select count(*) from public.game_rounds where status = 'published' and revealed_seed is not null) >= 2;
  assert (select count(*) from public.game_rounds where status = 'open' and revealed_seed is not null) = 0;
  raise notice 'OK  RLS tirages';
end $$;
rollback;

do $$ begin raise notice 'TESTS TIRAGES PASSÉS'; end $$;
