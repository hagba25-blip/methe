# methe — Plateforme de jeux à mises

Flutter (Android + Web) · Backend Python (FastAPI) · Supabase (PostgreSQL, Auth, RLS)

État : **Phase 6 livrée** (jeu des Fruits : prise de paris, règlement automatique, Mes paris). Phase 5 : moteur de tirage vérifiable. Phase 4 : retraits avec blocage du montant et validation admin. Phase 3 : dépôts via agents WhatsApp. Phases 1–2 : architecture, authentification, profil, portefeuille.

## Arborescence

```text
methe/
├── supabase/
│   ├── migrations/          # schéma versionné, à appliquer dans l'ordre
│   │   ├── …0001_core_reference.sql          pays, langues, devises
│   │   ├── …0002_identity_wallet_ledger.sql  profils, ID 6xxxxxxxxx, rôles, portefeuilles, ledger
│   │   ├── …0003_payments.sql                agents WhatsApp, dépôts, retraits
│   │   ├── …0004_games_rounds_bets.sql       jeux, tirages, règles versionnées, paris
│   │   ├── …0005_admin_audit_notifications.sql
│   │   ├── …0006_rls_grants.sql              Row Level Security + droits
│   │   ├── …0007_admin_bootstrap.sql         nommer un administrateur
│   │   ├── …0008_deposits_flow.sql           demande, validation, refus, crédit manuel
│   │   ├── …0009_withdrawals_flow.sql        retrait : blocage, vérification, paiement, refus
│   │   ├── …0010_draw_engine.sql             moteur de tirage : tours, graines, résultats (pg_cron)
│   │   ├── …0011_betting.sql                 paris : prise, cotes figées, règlement, remboursement
│   │   └── …0012_fruits_odds_v2.sql          Fruits en pari mutuel, poids version 2
│   ├── seed.sql             # pays, agents, jeux, 20 fruits, règles v1, trésorerie
│   └── tests/               # tests SQL exécutables sur un PostgreSQL local
├── backend/                 # API Python (structure du cahier des charges §47)
│   ├── main.py
│   ├── app/{api,models,schemas,services,repositories,games,wallet,betting,draw,admin,security}
│   └── tests/
└── app/                     # Flutter (structure §47)
    └── lib/{core,config,models,services,repositories,providers,screens,widgets}
```

## Lancer en local

**Base de données** (projet Supabase existant) :
```bash
supabase link --project-ref <ref>
supabase db push                 # applique supabase/migrations
psql "$DATABASE_URL" -f supabase/seed.sql
```

**Tests SQL** sur un PostgreSQL jetable (simule le schéma `auth` de Supabase) :
```bash
PGHOST=localhost PGUSER=postgres bash supabase/tests/run_local.sh
```

**Backend** :
```bash
cd backend && pip install -r requirements.txt && cp .env.example .env   # remplir
uvicorn main:app --reload
pytest                                   # + TEST_DATABASE_URL=… pour les tests intégrés
```

**Flutter** :
```bash
cd app && flutter create . --platforms=android,web   # génère android/ et web/ une fois
flutter pub get
flutter run -d chrome --dart-define=SUPABASE_URL=… --dart-define=SUPABASE_PUBLISHABLE_KEY=… --dart-define=API_BASE_URL=http://localhost:8000
```

## Choix d'architecture

| Sujet | Décision |
|---|---|
| Montants | `BIGINT` en unités mineures de la devise (XOF : 1 = 1 F ; USD : 1 = 1 centime). Aucun flottant. |
| Solde | `wallets.balance` n'est qu'un cache. Il ne change que via `private.post_journal()`, qui écrit un journal **équilibré** (somme des lignes = 0), avec solde avant/après, de façon **idempotente** (clé unique → pas de double transaction). Un trigger refuse toute autre modification ; le ledger est en écriture seule. |
| Trésorerie admin | Les 999 999 999 999 999 USD sont un **portefeuille système `TREASURY`**, alimenté par une écriture du ledger depuis `EXTERNAL_FUNDING`. Pas de champ « solde admin » modifiable. Un équivalent XOF est créé car les joueurs sont en XOF (pas de conversion automatique). |
| ID client | `6` + 9 chiffres tirés par `gen_random_bytes` (CSPRNG), contrainte `UNIQUE` + `CHECK ^6[0-9]{9}$`, non modifiable (trigger). |
| Inscription | Supabase Auth. Un trigger sur `auth.users` crée profil + portefeuille et **revalide** pays, langue, devise, CGU : une donnée invalide fait échouer l'inscription. |
| Droits | Le client Flutter **lit** uniquement ses données (RLS) et le catalogue public. Toutes les écritures métier passent par le backend Python. Un utilisateur ne peut modifier que prénom, nom, langue, avatar, et marquer ses notifications comme lues. |
| Tirages | Protocole **commit-reveal** (`backend/app/draw/rng.py`) : graine 256 bits secrète, son empreinte SHA-256 est publiée avant l'ouverture des mises, le résultat est dérivé par HMAC-SHA256 sans biais, la graine est révélée à la publication → n'importe qui peut vérifier. La graine est stockée dans un schéma non exposé jusqu'à la publication. |
| Verrouillage | Statut du tirage uniquement vers l'avant ; résultat, engagement et graine figés une fois posés ; un pari n'est accepté que sur un tirage **ouvert** et avant `closes_at` (trigger SQL, pas seulement le backend). |
| Règles de gain | `payout_rules` versionnées et immuables (on crée une nouvelle version). Chaque pari garde `payout_rule_version` et un `odds_snapshot`. |
| Audit | Trigger d'audit automatique sur les tables sensibles → `audit_logs` (immuable) ; `admin_actions` pour les actes d'administration ; `risk_events` pour l'anti-fraude. |

Écarts volontaires avec la liste §43 : la table `users` est `auth.users` de Supabase (complétée par `profiles`) ; ajout de `ledger_journals`, `game_types`, `game_symbols`, `draw_schedules`, `countries`, `currencies`, `languages`, `risk_events`.

## Points à confirmer

1. **Fruits en pari mutuel** (choix de l'exploitant, 8 octobre 2026) : les mises d'un tirage forment une cagnotte ; la plateforme garde sa commission (`pool.commission_percent`, 10 %) et partage le reste entre les gagnants au prorata de mise × poids. Poids = 50 ÷ nombre de fruits (1 → 50, 2 → 25, 3 → 16,67, 4 → 12,5, 5 → 10, 6 → 8,33, 7 → 7,14, 8 → 6,25, 10 → 5, 15 → 3,33) et 20 fruits → 1 ; 9, 11 à 14 et 16 à 19 fruits ne sont pas jouables. La plateforme ne peut perdre sur aucun tirage (vérifié sur 200 tirages simulés). Le gain affiché avant la fermeture est une estimation.
2. **PERME** : seuls 2/2 (x300), 3/3 (x900), 3/2 (x100), 5/2 (x30) sont définis. Il manque les autres cas (4 numéros, 5 numéros avec 3/4/5 trouvés, 6 à 10 numéros). La règle « ÷10 » de l'exemple 5/2 est-elle générale ?
3. **NAPE** : saisi comme 3 → x2700, 4 → x3600, 5 → x4500 (900 × nombre de numéros), gagnant seulement si tous sortent.
4. **Retraits** : réglages provisoires dans `app_settings` : minimum 1 000 F, pas de maximum, 0 % de frais, pas de vérification d'identité obligatoire, 1 retrait en cours à la fois. À confirmer.
5. **Licence** : l'exploitation de jeux d'argent réels exige en général une autorisation dans chaque pays visé (au Togo, la Loterie Nationale Togolaise, LONATO, est l’opérateur national ; le nom « Lonato » pour le jeu mérite aussi une vérification). Cette démarche reste de la responsabilité de l'exploitant.

À titre indicatif, avec les valeurs fournies le taux de redistribution est d'environ 56 % pour CHOX, 75 % pour PERME 2/2, 80 % pour PERME à 3 numéros.

## API

| Route | Accès | Rôle |
|---|---|---|
| `GET /v1/me` · `PATCH /v1/me` | joueur | profil ; seuls prénom, nom, langue, avatar sont modifiables |
| `GET /v1/wallet` | joueur | solde et devise |
| `GET /v1/wallet/transactions?kind=&cursor=` | joueur | historique paginé (dépôts, retraits, paris, ajustements) |
| `GET /v1/settings/public` | public | mise minimum, retrait minimum/maximum… |
| `GET /v1/admin/users/{ID}` | personnel | fiche client §30 ; chaque consultation est tracée dans `admin_actions` |
| `GET /v1/agents` | public | agents de dépôt disponibles |
| `POST /v1/deposits` · `GET /v1/deposits` · `POST /v1/deposits/{id}/cancel` | joueur | demande EN ATTENTE + lien WhatsApp pré-rempli ; historique ; annulation |
| `GET /v1/admin/deposits?status=` | personnel | file des dépôts à valider |
| `POST /v1/admin/deposits/{id}/approve` · `/reject` | finance, admin | crédite via le ledger (montant corrigeable) ou refuse avec motif ; notification + trace |
| `POST /v1/admin/users/{ID}/credit` (en-tête `Idempotency-Key`) | finance, admin | crédit manuel §31 ; un double clic ne crédite qu'une fois |
| `GET /v1/rounds/upcoming?game=` | public | tour en cours (empreinte publiée, heures de fermeture et de tirage) et tours suivants |
| `GET /v1/rounds/results?game=&before=` | public | résultats publiés avec graine révélée, paginés |
| `GET /v1/rounds/{id}/verify` | public | recalcule le résultat depuis la graine (preuve d'équité) |
| `POST /v1/admin/engine/tick` · `POST /v1/admin/rounds/{id}/cancel` | admin | avance le moteur tout de suite ; annule un tour pas encore tiré (motif obligatoire) |
| `GET /v1/games` | public | jeux, types de pari, cotes jouables (version en vigueur), fruits |
| `GET /v1/rounds/{id}/pool` | public | cagnotte d'un tour mutuel (total misé, poids par fruit) pour le gain estimé |
| `POST /v1/bets` (en-tête `Idempotency-Key`) | joueur | pari : mise débitée, cotes figées ; un double envoi ne débite qu'une fois |
| `GET /v1/bets?status=&game=&before=` · `GET /v1/bets/{id}` | joueur | mes paris avec résultat du tirage et gain |
| `GET /v1/withdrawals/info` | joueur | solde, minimum, maximum, frais, raison d'un blocage, numéro par défaut |
| `POST /v1/withdrawals` (en-tête `Idempotency-Key`) · `GET /v1/withdrawals` · `POST /v1/withdrawals/{id}/cancel` | joueur | demande EN ATTENTE (montant bloqué aussitôt) ; historique ; annulation tant qu'elle est EN ATTENTE |
| `GET /v1/admin/withdrawals?status=` | personnel | file des retraits (plus anciens d'abord) avec solde du client |
| `POST /v1/admin/withdrawals/{id}/review` · `/approve` · `/pay` · `/reject` | finance, admin | EN VÉRIFICATION → APPROUVÉ → PAYÉ, ou REFUSÉ avec motif (montant rendu) ; notification + trace |

**Nommer un administrateur** : créer d'abord son compte dans l'application, puis dans Supabase > SQL Editor :
```sql
select private.grant_staff_role('vous@example.com', 'super_admin');
```

Règles de sécurité des dépôts : ouvrir WhatsApp ne crédite rien ; un dépôt ne peut être validé qu'une fois ; un administrateur ne peut ni valider son propre dépôt ni se créditer lui-même ; 3 demandes en attente maximum par joueur ; montants min./max. dans `app_settings` (`deposit.*`).

Règles de sécurité des retraits : le montant quitte le solde du joueur dès la demande (portefeuille `WITHDRAWAL_HOLD`), il ne peut donc pas être misé ni retiré deux fois ; refus ou annulation le rendent intégralement ; au paiement, le net sort du système et les frais vont à `HOUSE` ; un paiement ne peut être enregistré qu'une fois et seulement après approbation ; un administrateur ne peut pas traiter son propre retrait.

Moteur de tirage : `private.engine_tick()` crée les tours (2 créneaux à l'avance), les ouvre en tirant une graine secrète de 256 bits dont seule l'empreinte SHA-256 est publiée, ferme les mises (1 min avant pour les Fruits, 2 min pour le Lonato), tire le résultat par HMAC-SHA256 puis révèle la graine. Sur Supabase, la migration le programme chaque minute avec pg_cron ; à défaut, mettre `DRAW_ENGINE_ENABLED=true` dans le backend. Créneaux en heure UTC (= heure de Lomé) : Fruits à chaque heure, Lonato à 00h, 03h, 06h… Un tour que le moteur n'a pas pu ouvrir à temps est annulé plutôt que tiré. Le tirage fait dans la base et l'implémentation Python (`backend/app/draw/rng.py`) donnent le même résultat ; les tests le vérifient sur 200 graines.

Règles des paris : deux modes de gain, `fixed` (gain = mise × cote, connu d'avance : Lonato) et `pool` (pari mutuel : Fruits). La mise quitte le solde au moment du pari (vers `HOUSE`) ; les cotes sont celles en vigueur à cet instant et restent figées sur le ticket, même si une nouvelle version est publiée ; une combinaison sans cote publiée est refusée (Fruits : 1 à 8, 10, 15 et 20 fruits) ; au tirage, chaque pari est réglé une seule fois et le gain crédité aussitôt ; un tour annulé rembourse toutes ses mises. Le règlement couvre déjà les trois règles du Lonato (PERME, NAPE, CHOX), dont l'écran arrive en phase 7.

Android : pour que le lien WhatsApp s'ouvre, ajouter dans `android/app/src/main/AndroidManifest.xml` (généré par `flutter create`) un bloc `<queries>` avec une intention `VIEW` sur le schéma `https`.

## Prochaine étape

Phase 7 : écran Lonato (PERME, NAPE, CHOX).
