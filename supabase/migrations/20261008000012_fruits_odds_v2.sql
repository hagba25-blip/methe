-- =============================================================================
-- 0012 — Jeu des Fruits en pari mutuel, poids version 2 (choix de l'exploitant, 8 octobre 2026)
-- =============================================================================
-- Les mises d'un tirage forment une cagnotte. La plateforme prend sa commission
-- (pool.commission_percent, 10 %), le reste est partagé entre les gagnants au
-- prorata de mise × poids. Poids = 50 ÷ nombre de fruits choisis (20 fruits : 1).
-- Les nombres absents (9, 11 à 14, 16 à 19) ne sont pas jouables.
-- La plateforme ne peut perdre sur aucun tirage.
update public.game_types set settlement_mode = 'pool' where code = 'FRUITS';

insert into public.payout_rules (game_type_code, version, selection_count, match_count, multiplier, condition, effective_from, note)
select 'FRUITS', 2, k, 1, m, 'winner_in_selection', now(), format('%s fruit(s) → poids %s', k, m)
from (values (1, 50), (2, 25), (3, 16.67), (4, 12.5), (5, 10), (6, 8.33), (7, 7.14), (8, 6.25),
             (10, 5), (15, 3.33), (20, 1)) as t(k, m)
where exists (select 1 from public.game_types where code = 'FRUITS')  -- base neuve : voir seed.sql
on conflict do nothing;
