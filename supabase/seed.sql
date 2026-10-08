-- =============================================================================
-- Données initiales (idempotentes autant que possible)
-- =============================================================================

insert into public.currencies (code, name, symbol, decimals) values
  ('XOF', 'Franc CFA (BCEAO)', 'F CFA', 0),
  ('XAF', 'Franc CFA (BEAC)',  'F CFA', 0),
  ('USD', 'Dollar américain',  '$',     2),
  ('EUR', 'Euro',              '€',     2),
  ('NGN', 'Naira',             '₦',     2),
  ('GHS', 'Cedi',              'GH₵',   2)
on conflict do nothing;

insert into public.languages (code, name) values
  ('fr', 'Français'),
  ('en', 'English')
on conflict do nothing;

insert into public.countries (code, name, dial_code, default_currency, default_language) values
  ('TG', 'Togo',           '+228', 'XOF', 'fr'),
  ('BJ', 'Bénin',          '+229', 'XOF', 'fr'),
  ('CI', 'Côte d''Ivoire', '+225', 'XOF', 'fr'),
  ('SN', 'Sénégal',        '+221', 'XOF', 'fr'),
  ('BF', 'Burkina Faso',   '+226', 'XOF', 'fr'),
  ('ML', 'Mali',           '+223', 'XOF', 'fr'),
  ('NE', 'Niger',          '+227', 'XOF', 'fr'),
  ('CM', 'Cameroun',       '+237', 'XAF', 'fr'),
  ('GA', 'Gabon',          '+241', 'XAF', 'fr'),
  ('NG', 'Nigeria',        '+234', 'NGN', 'en'),
  ('GH', 'Ghana',          '+233', 'GHS', 'en'),
  ('FR', 'France',         '+33',  'EUR', 'fr'),
  ('US', 'United States',  '+1',   'USD', 'en')
on conflict do nothing;

-- Agents de dépôt par défaut
insert into public.agents (display_name, whatsapp_number, country_code, sort_order) values
  ('Agent 1', '+22899315092', 'TG', 1),
  ('Agent 2', '+22891962246', 'TG', 2)
on conflict do nothing;

-- Paramètres -----------------------------------------------------------------
insert into public.app_settings (key, value, is_public, description) values
  ('betting.min_stake',          '50',      true,  'Mise minimum (unités de la devise)'),
  ('withdrawal.min_amount',      '1000',    true,  'Montant minimum de retrait — À CONFIRMER'),
  ('withdrawal.max_amount',      'null',    true,  'Montant maximum de retrait (null = illimité)'),
  ('withdrawal.fee_percent',     '0',       true,  'Frais de retrait en %'),
  ('withdrawal.require_kyc',     'false',   true,  'Vérification d''identité obligatoire avant retrait'),
  ('deposit.whatsapp_template',  '"Je veux faire dépôt sur mon compte avec ID du client : {client_id}"', true,
                                                    'Message WhatsApp pré-rempli'),
  ('deposit.preset_amounts',     '[500, 1000, 2000, 5000, 10000, 25000, 50000]', true, 'Montants proposés')
on conflict (key) do nothing;

-- Jeux -----------------------------------------------------------------------
insert into public.games (code, name, description, sort_order) values
  ('FRUITS', 'Jeu des Fruits', '20 fruits, un fruit gagnant toutes les heures', 1),
  ('LONATO', 'Lonato',         '5 numéros gagnants parmi 01–90 toutes les 3 heures', 2)
on conflict do nothing;

insert into public.game_types (code, game_code, name, min_selection, max_selection, min_stake, sort_order) values
  ('FRUITS', 'FRUITS', 'Fruits', 1, 20, 50, 1),
  ('PERME',  'LONATO', 'PERME',  2, 10, 50, 1),
  ('NAPE',   'LONATO', 'NAPE',   3, 5,  50, 2),
  ('CHOX',   'LONATO', 'CHOX',   1, 1,  50, 3)
on conflict do nothing;

insert into public.game_symbols (game_code, code, label, emoji, sort_order) values
  ('FRUITS','POMME','Pomme','🍎',1),        ('FRUITS','POIRE','Poire','🍐',2),
  ('FRUITS','ORANGE','Orange','🍊',3),      ('FRUITS','CITRON','Citron','🍋',4),
  ('FRUITS','BANANE','Banane','🍌',5),      ('FRUITS','PASTEQUE','Pastèque','🍉',6),
  ('FRUITS','RAISIN','Raisin','🍇',7),      ('FRUITS','FRAISE','Fraise','🍓',8),
  ('FRUITS','MYRTILLE','Myrtille','🫐',9),  ('FRUITS','MELON','Melon','🍈',10),
  ('FRUITS','CERISE','Cerise','🍒',11),     ('FRUITS','PECHE','Pêche','🍑',12),
  ('FRUITS','MANGUE','Mangue','🥭',13),     ('FRUITS','ANANAS','Ananas','🍍',14),
  ('FRUITS','COCO','Noix de coco','🥥',15), ('FRUITS','KIWI','Kiwi','🥝',16),
  ('FRUITS','TOMATE','Tomate','🍅',17),     ('FRUITS','AVOCAT','Avocat','🥑',18),
  ('FRUITS','OLIVE','Olive','🫒',19),       ('FRUITS','POMME_VERTE','Pomme verte','🍏',20)
on conflict do nothing;

insert into public.draw_schedules (game_code, interval_minutes, close_before_seconds) values
  ('FRUITS', 60,  60),
  ('LONATO', 180, 120)
on conflict do nothing;

-- Règles de paiement — version 1 (valeurs du cahier des charges) -------------
-- Les combinaisons absentes ne sont PAS jouables tant que l'administration ne les a
-- pas définies (le moteur refuse un pari sans règle applicable).
insert into public.payout_rules
  (game_type_code, version, selection_count, match_count, multiplier, condition, effective_from, note) values
  -- FRUITS : 1 fruit gagnant ; la cote dépend du nombre de fruits choisis
  ('FRUITS', 1, 1,  1, 50,   'winner_in_selection', '2026-01-01', '1 fruit → x50'),
  ('FRUITS', 1, 20, 1, 1,    'winner_in_selection', '2026-01-01', '20 fruits → x1'),
  -- PERME : multiplicateur selon (nombre choisi, nombre trouvé)
  ('PERME',  1, 2,  2, 300,  'exact_matches', '2026-01-01', '2 numéros, 2 trouvés → x300'),
  ('PERME',  1, 3,  3, 900,  'exact_matches', '2026-01-01', '3 numéros, 3 trouvés → x300 × 3'),
  ('PERME',  1, 3,  2, 100,  'exact_matches', '2026-01-01', '3 numéros, 2 trouvés → x100'),
  ('PERME',  1, 5,  2, 30,   'exact_matches', '2026-01-01', '5 numéros, 2 trouvés → x300 ÷ 10'),
  -- NAPE : tous les numéros misés doivent sortir ; x900 × nombre de numéros
  ('NAPE',   1, 3,  3, 2700, 'all_selected_in_result', '2026-01-01', 'x900 × 3'),
  ('NAPE',   1, 4,  4, 3600, 'all_selected_in_result', '2026-01-01', 'x900 × 4'),
  ('NAPE',   1, 5,  5, 4500, 'all_selected_in_result', '2026-01-01', 'x900 × 5'),
  -- CHOX : 1 numéro parmi les 5 gagnants → x10
  ('CHOX',   1, 1,  1, 10,   'exact_matches', '2026-01-01', 'x10')
on conflict do nothing;

-- FRUITS version 2 (choix de l'exploitant) : 50 ÷ nombre de fruits, 20 fruits x1.
-- Identique à la migration 0012, pour les bases installées après celle-ci.
insert into public.payout_rules (game_type_code, version, selection_count, match_count, multiplier, condition, effective_from, note)
select 'FRUITS', 2, k, 1, m, 'winner_in_selection', '2026-10-08', format('%s fruit(s) → x%s', k, m)
from (values (1, 50), (2, 25), (3, 16.67), (4, 12.5), (5, 10), (6, 8.33), (7, 7.14), (8, 6.25),
             (10, 5), (15, 3.33), (20, 1)) as t(k, m)
on conflict do nothing;

-- Portefeuilles système -------------------------------------------------------
-- EXTERNAL_FUNDING : contrepartie comptable des fonds entrant dans le système.
-- TREASURY         : trésorerie de démonstration/configuration (crédits admin).
-- HOUSE            : résultat de la maison (mises perdues / gains payés).
-- WITHDRAWAL_HOLD  : montants bloqués pendant le traitement d'un retrait.
insert into public.wallets (owner_type, system_code, currency_code, allow_negative) values
  ('system', 'EXTERNAL_FUNDING', 'USD', true),
  ('system', 'EXTERNAL_FUNDING', 'XOF', true),
  ('system', 'TREASURY',         'USD', false),
  ('system', 'TREASURY',         'XOF', false),
  ('system', 'HOUSE',            'XOF', true),
  ('system', 'WITHDRAWAL_HOLD',  'XOF', false)
on conflict do nothing;

-- Alimentation de démonstration de la trésorerie : 999 999 999 999 999 USD
-- (USD = 2 décimales → montant en centimes). Passe par le ledger, idempotent.
select private.post_journal(
  'treasury_funding', 'seed-treasury-usd-v1',
  jsonb_build_array(
    jsonb_build_object('wallet_id', (select id from public.wallets where system_code = 'EXTERNAL_FUNDING' and currency_code = 'USD'), 'amount', -99999999999999900),
    jsonb_build_object('wallet_id', (select id from public.wallets where system_code = 'TREASURY' and currency_code = 'USD'),         'amount',  99999999999999900)),
  'seed', null, null, 'Trésorerie de démonstration (cahier des charges §29)');

select private.post_journal(
  'treasury_funding', 'seed-treasury-xof-v1',
  jsonb_build_array(
    jsonb_build_object('wallet_id', (select id from public.wallets where system_code = 'EXTERNAL_FUNDING' and currency_code = 'XOF'), 'amount', -999999999999999),
    jsonb_build_object('wallet_id', (select id from public.wallets where system_code = 'TREASURY' and currency_code = 'XOF'),         'amount',  999999999999999)),
  'seed', null, null, 'Trésorerie de démonstration XOF');
