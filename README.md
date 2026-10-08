# methe — Plateforme de jeux à mises

Flutter (Android + Web) · Backend Python (FastAPI) · Supabase (PostgreSQL, Auth, RLS)

État : **Phase 3 livrée** (dépôts via agents WhatsApp, validation admin, crédit manuel). Phases 1–2 : architecture, authentification, profil, portefeuille.

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
│   │   └── …0008_deposits_flow.sql           demande, validation, refus, crédit manuel
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

1. **Cotes Fruits 2 à 19 fruits** : non fournies, donc **non jouables** pour l'instant. ⚠️ Avec 1 fruit à x50 alors qu'il y a 1 chance sur 20, la plateforme reverse **250 %** des mises en moyenne (perte certaine) ; 20 fruits à x1 reverse 100 % (aucune marge). Une cote équitable pour *k* fruits est 20/*k* ; par exemple avec 10 % de marge : 1 fruit → x18, 2 → x9, 4 → x4,5, 10 → x1,8.
2. **PERME** : seuls 2/2 (x300), 3/3 (x900), 3/2 (x100), 5/2 (x30) sont définis. Il manque les autres cas (4 numéros, 5 numéros avec 3/4/5 trouvés, 6 à 10 numéros). La règle « ÷10 » de l'exemple 5/2 est-elle générale ?
3. **NAPE** : saisi comme 3 → x2700, 4 → x3600, 5 → x4500 (900 × nombre de numéros), gagnant seulement si tous sortent.
4. **Retraits** : montant minimum (1 000 F provisoire), maximum, frais, vérification d'identité obligatoire ou non.
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

**Nommer un administrateur** : créer d'abord son compte dans l'application, puis dans Supabase > SQL Editor :
```sql
select private.grant_staff_role('vous@example.com', 'super_admin');
```

Règles de sécurité des dépôts : ouvrir WhatsApp ne crédite rien ; un dépôt ne peut être validé qu'une fois ; un administrateur ne peut ni valider son propre dépôt ni se créditer lui-même ; 3 demandes en attente maximum par joueur ; montants min./max. dans `app_settings` (`deposit.*`).

Android : pour que le lien WhatsApp s'ouvre, ajouter dans `android/app/src/main/AndroidManifest.xml` (généré par `flutter create`) un bloc `<queries>` avec une intention `VIEW` sur le schéma `https`.

## Prochaine étape

Phase 4 : retraits et validation par l'administration.
