-- =============================================================================
-- 0010 — Moteur de tirage : création des tours, ouverture, fermeture, tirage
-- =============================================================================
-- Tout se passe dans la base, ce qui permet de faire tourner le moteur avec
-- pg_cron (inclus dans Supabase) sans serveur : `select private.engine_tick()`
-- chaque minute. L'appel est idempotent et peut être relancé à tout moment.
--
-- Cycle d'un tour : PROGRAMMÉ → OUVERT → FERMÉ → TIRÉ → PUBLIÉ (→ RÉGLÉ en phase 8)
--  * ouverture : une graine secrète de 256 bits est tirée (CSPRNG) et seule son
--    empreinte SHA-256 est publiée, AVANT toute mise ;
--  * tirage : le résultat est dérivé de la graine par HMAC-SHA256 avec rejet
--    (aucun biais), exactement comme backend/app/draw/rng.py ;
--  * publication : la graine est révélée, chacun peut recalculer le résultat.
-- Les créneaux sont alignés sur l'heure UTC (= heure de Lomé) : toutes les heures
-- pour les Fruits, toutes les 3 heures (00h, 03h, 06h…) pour le Lonato.

-- Générateur déterministe -------------------------------------------------------
-- p-ième entier 32 bits de la suite HMAC-SHA256(graine, "<tour>:<bloc>").
create or replace function private.rng_u32(p_seed text, p_round_id uuid, p_pos int)
returns bigint language sql immutable strict set search_path = '' as $$
  with b as (
    select extensions.hmac(convert_to(p_round_id::text || ':' || (p_pos / 8)::text, 'UTF8'),
                           decode(p_seed, 'hex'), 'sha256') as d, (p_pos % 8) * 4 as o)
  select (get_byte(d, o)::bigint << 24) | (get_byte(d, o + 1)::bigint << 16)
       | (get_byte(d, o + 2)::bigint << 8) | get_byte(d, o + 3)::bigint
  from b;
$$;

-- Entier uniforme dans [0, n) par rejet ; avance la position dans la suite.
create or replace function private.rng_uniform(p_seed text, p_round_id uuid, inout p_pos int, p_n int, out v int)
language plpgsql immutable set search_path = '' as $$
declare
  v_limit bigint := (4294967296 / p_n) * p_n;
  v_u     bigint;
begin
  loop
    v_u := private.rng_u32(p_seed, p_round_id, p_pos);
    p_pos := p_pos + 1;
    if v_u < v_limit then
      v := (v_u % p_n)::int;
      return;
    end if;
  end loop;
end $$;

-- Résultat d'un tour à partir de sa graine (algorithme hmac-sha256-v1).
create or replace function private.compute_result(p_game_code text, p_seed text, p_round_id uuid)
returns jsonb language plpgsql stable set search_path = '' as $$
declare
  v_symbols text[];
  v_pool    int[];
  v_pos     int := 0;
  v_j       int;
  v_tmp     int;
  r         record;
begin
  if p_game_code = 'FRUITS' then
    -- Ordre canonique (octets), indépendant de l'ordre d'affichage
    select array_agg(code order by code collate "C") into v_symbols
      from public.game_symbols where game_code = 'FRUITS';
    r := private.rng_uniform(p_seed, p_round_id, v_pos, array_length(v_symbols, 1));
    return jsonb_build_object('fruit', v_symbols[r.v + 1]);

  elsif p_game_code = 'LONATO' then
    -- 5 numéros distincts parmi 01–90 (Fisher-Yates partiel)
    v_pool := array(select generate_series(1, 90));
    for i in 0..4 loop
      r := private.rng_uniform(p_seed, p_round_id, v_pos, 90 - i);
      v_pos := r.p_pos;
      v_j := i + r.v;
      v_tmp := v_pool[i + 1]; v_pool[i + 1] := v_pool[v_j + 1]; v_pool[v_j + 1] := v_tmp;
    end loop;
    return jsonb_build_object('numbers',
      (select jsonb_agg(n order by n) from unnest(v_pool[1:5]) as n));
  end if;
  raise exception 'Jeu inconnu : %', p_game_code;
end $$;

-- Planification -----------------------------------------------------------------
-- Crée les tours manquants jusqu'à p_horizon créneaux à l'avance.
create or replace function private.schedule_rounds(p_now timestamptz default now(), p_horizon int default 2)
returns int language plpgsql security definer set search_path = '' as $$
declare
  s        public.draw_schedules%rowtype;
  v_secs   bigint;
  v_slot   timestamptz;
  v_number bigint;
  v_count  int := 0;
begin
  for s in select ds.* from public.draw_schedules ds join public.games g on g.code = ds.game_code
            where ds.is_active and g.is_active loop
    v_secs := s.interval_minutes * 60;
    -- premier créneau strictement après maintenant
    v_slot := to_timestamp((floor(extract(epoch from p_now) / v_secs) + 1) * v_secs);
    for i in 0..p_horizon - 1 loop
      if not exists (select 1 from public.game_rounds where game_code = s.game_code
                                                   and draw_at = v_slot + make_interval(secs => i * v_secs)) then
        select coalesce(max(round_number), 0) + 1 into v_number from public.game_rounds where game_code = s.game_code;
        insert into public.game_rounds (game_code, round_number, opens_at, closes_at, draw_at)
        values (s.game_code, v_number,
                v_slot + make_interval(secs => (i - 1) * v_secs),
                v_slot + make_interval(secs => i * v_secs - s.close_before_seconds),
                v_slot + make_interval(secs => i * v_secs));
        v_count := v_count + 1;
      end if;
    end loop;
  end loop;
  return v_count;
end $$;

-- Ouverture : graine secrète + engagement publié --------------------------------
create or replace function private.open_round(p_round_id uuid)
returns public.game_rounds language plpgsql security definer set search_path = '' as $$
declare
  v_round public.game_rounds%rowtype;
  v_seed  text := encode(extensions.gen_random_bytes(32), 'hex');
begin
  select * into v_round from public.game_rounds where id = p_round_id for update;
  if v_round.status <> 'scheduled' then
    return v_round;
  end if;
  insert into private.round_secrets (round_id, server_seed) values (p_round_id, v_seed);
  update public.game_rounds
     set status = 'open',
         commitment_hash = encode(extensions.digest(decode(v_seed, 'hex'), 'sha256'), 'hex'),
         algorithm_version = 'hmac-sha256-v1'
   where id = p_round_id returning * into v_round;
  return v_round;
end $$;

-- Tirage puis publication (graine révélée) ----------------------------------------
create or replace function private.draw_round(p_round_id uuid)
returns public.game_rounds language plpgsql security definer set search_path = '' as $$
declare
  v_round public.game_rounds%rowtype;
  v_seed  text;
begin
  select * into v_round from public.game_rounds where id = p_round_id for update;
  if v_round.status <> 'closed' then
    return v_round;
  end if;
  select server_seed into v_seed from private.round_secrets where round_id = p_round_id;
  if encode(extensions.digest(decode(v_seed, 'hex'), 'sha256'), 'hex') <> v_round.commitment_hash then
    raise exception 'Graine incohérente avec l''engagement du tour %', v_round.round_number;
  end if;
  update public.game_rounds
     set status = 'drawn', result = private.compute_result(v_round.game_code, v_seed, p_round_id), drawn_at = now()
   where id = p_round_id;
  -- Publication immédiate. Le règlement des paris (phase 8) s'insérera ici.
  update public.game_rounds
     set status = 'published', revealed_seed = v_seed, published_at = now()
   where id = p_round_id returning * into v_round;
  return v_round;
end $$;

-- Annulation d'un tour (admin) : uniquement avant le tirage ----------------------
create or replace function private.cancel_round(p_round_id uuid, p_admin_id uuid, p_reason text)
returns public.game_rounds language plpgsql security definer set search_path = '' as $$
declare v_round public.game_rounds%rowtype;
begin
  if p_reason is null or length(trim(p_reason)) < 3 then
    raise exception 'Motif obligatoire' using errcode = 'P0001';
  end if;
  select * into v_round from public.game_rounds where id = p_round_id for update;
  if not found then
    raise exception 'Tirage introuvable' using errcode = 'P0002';
  end if;
  if v_round.status not in ('scheduled', 'open', 'closed') then
    raise exception 'Ce tirage est déjà tiré ou clôturé : annulation impossible' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.bets where round_id = p_round_id and status = 'pending') then
    -- Le remboursement automatique des mises arrive avec la prise de paris (phase 6).
    raise exception 'Ce tirage a des paris en cours' using errcode = 'P0001';
  end if;
  update public.game_rounds set status = 'cancelled' where id = p_round_id returning * into v_round;
  insert into public.admin_actions (admin_id, action, target_type, target_id, reason, payload)
  values (p_admin_id, 'cancel_round', 'game_round', v_round.game_code || '#' || v_round.round_number, trim(p_reason),
          jsonb_build_object('round_id', v_round.id, 'draw_at', v_round.draw_at));
  return v_round;
end $$;

-- Battement du moteur ---------------------------------------------------------------
-- Fait avancer chaque tour selon l'heure. Un seul battement à la fois.
create or replace function private.engine_tick(p_now timestamptz default now())
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  r         public.game_rounds%rowtype;
  v_created int;
  v_opened  int := 0;
  v_closed  int := 0;
  v_drawn   int := 0;
  v_missed  int := 0;
begin
  if not pg_try_advisory_xact_lock(hashtext('methe.engine_tick')) then
    return jsonb_build_object('skipped', true);
  end if;

  v_created := private.schedule_rounds(p_now);

  -- Tours dont la fenêtre de mise est passée sans avoir été ouverts (moteur arrêté) :
  -- annulés, aucune mise n'a pu y être placée.
  update public.game_rounds set status = 'cancelled'
   where status = 'scheduled' and closes_at <= p_now;
  get diagnostics v_missed = row_count;

  for r in select * from public.game_rounds where status = 'scheduled' and opens_at <= p_now order by draw_at loop
    perform private.open_round(r.id);
    v_opened := v_opened + 1;
  end loop;

  update public.game_rounds set status = 'closed' where status = 'open' and closes_at <= p_now;
  get diagnostics v_closed = row_count;

  for r in select * from public.game_rounds where status = 'closed' and draw_at <= p_now order by draw_at loop
    perform private.draw_round(r.id);
    v_drawn := v_drawn + 1;
  end loop;

  return jsonb_build_object('created', v_created, 'opened', v_opened, 'closed', v_closed,
                            'drawn', v_drawn, 'cancelled_missed', v_missed);
end $$;

revoke execute on all functions in schema private from public, anon, authenticated;
grant execute on function private.has_role(public.app_role[]) to authenticated;
grant execute on function private.is_staff() to authenticated;

-- Lancement automatique chaque minute avec pg_cron (Supabase) ---------------------
-- Ignoré sans erreur si pg_cron n'est pas disponible (base locale de test).
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.unschedule(jobid) from cron.job where jobname = 'methe-engine';
    perform cron.schedule('methe-engine', '* * * * *', 'select private.engine_tick()');
    raise notice 'Moteur de tirage programmé chaque minute (pg_cron)';
  else
    raise notice 'pg_cron indisponible : appeler private.engine_tick() chaque minute depuis le backend';
  end if;
exception when others then
  raise notice 'pg_cron non activé (%) : activez-le dans Database > Extensions puis relancez ce fichier', sqlerrm;
end $$;

select private.engine_tick();
