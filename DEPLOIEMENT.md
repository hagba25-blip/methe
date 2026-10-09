# Mise en ligne de methe

Trois morceaux à mettre en ligne, dans cet ordre :

| Morceau | Hébergeur | Adresse finale |
|---|---|---|
| Base de données, comptes, tirages | **Supabase** (déjà en place) | `https://wpudmineqmchekedvwof.supabase.co` |
| Serveur Python (API) | **Render** | `https://methe-api.onrender.com` (nom proposé par Render) |
| Application Web | **GitHub Pages** (gratuit) | `https://hagba25-blip.github.io/methe/` |
| Application Android | fichier APK produit par GitHub | onglet **Actions** du dépôt |

> **Règle d'or** : le mot de passe de la base de données et les clés secrètes ne se
> saisissent que dans Supabase et dans Render. Ne les envoyez jamais par message,
> e-mail ou capture d'écran, et ne les mettez jamais dans le code. En cas de fuite :
> Supabase > Project Settings > Database > **Reset database password**, puis mettez
> à jour `DATABASE_URL` dans Render.

---

## Étape 1 — Supabase

1. **Toutes les phases SQL sont exécutées** (SQL Editor > coller > Run), dans l'ordre :
   installation, phases 2 à 6, 10 et 11 (fichiers `methe-*.sql`).
2. **pg_cron est activé** : Database > Extensions > chercher `pg_cron` > activer.
   C'est lui qui lance les tirages chaque minute, même quand personne n'est connecté.
3. **Adresse de l'application** : Authentication > URL Configuration :
   - *Site URL* : `https://hagba25-blip.github.io/methe/`
   - *Redirect URLs* : ajouter `https://hagba25-blip.github.io/methe/**`
   (les e-mails de confirmation et de mot de passe oublié renverront vers l'application).
4. **Vérification** : SQL Editor > coller `supabase/verification_production.sql` > Run.
   Chaque ligne doit être **OK**. « À FAIRE » signale un réglage que vous n'avez pas
   encore choisi (par exemple le numéro WhatsApp du support). Ce contrôle ne modifie rien.

Préparez ensuite, **sans l'envoyer à personne**, la chaîne de connexion :
Project Settings > Database > **Connection string** > onglet *Session pooler* (port 5432).
Elle ressemble à `postgresql://postgres.wpudmineqmchekedvwof:[YOUR-PASSWORD]@aws-0-….pooler.supabase.com:5432/postgres`.
Remplacez `[YOUR-PASSWORD]` par le mot de passe de la base.

Regardez aussi Project Settings > **JWT Keys** : si la clé en service est la
*Legacy JWT secret*, copiez-la pour l'étape 2 ; si ce sont des clés « ECC / RSA »
(cas des projets récents), il n'y a rien à copier.

## Étape 2 — Render (serveur Python)

1. Créez un compte sur [render.com](https://render.com) avec votre compte GitHub.
2. **New > Blueprint** > choisissez le dépôt `hagba25-blip/methe`. Render lit le
   fichier `render.yaml` et propose le service **methe-api**.
3. Render demande deux valeurs :
   - `DATABASE_URL` : la chaîne de connexion préparée à l'étape 1 ;
   - `SUPABASE_JWT_SECRET` : la *Legacy JWT secret* si vous en avez une, sinon laisser vide.
4. **Apply**. La première construction prend quelques minutes.
5. Ouvrez `https://<votre-service>.onrender.com/health` : la page doit afficher
   `{"status":"ok"}`. Notez cette adresse (elle sert à l'étape 3).

Le plan *Starter* (payant, environ 7 $ par mois) garde le serveur toujours allumé.
Le plan *Free* suffit pour essayer, mais le serveur s'endort après 15 minutes sans
visite : la première action suivante prend alors près d'une minute. Les tirages ne
sont pas concernés (ils tournent dans Supabase).

## Étape 3 — GitHub (application Web et Android)

1. Dépôt > **Settings > Pages** > *Source* : **GitHub Actions**.
2. Dépôt > **Settings > Secrets and variables > Actions** > onglet *Variables* >
   **New repository variable** : nom `API_BASE_URL`, valeur l'adresse Render de
   l'étape 2 (par exemple `https://methe-api.onrender.com`, sans `/` à la fin).
3. Onglet **Actions** > *Mise en ligne* > **Run workflow** (branche `main`).
4. Quand le passage est vert, l'application est en ligne à
   `https://hagba25-blip.github.io/methe/`.

Si l'adresse Render n'est pas `methe-api.onrender.com`, ajoutez aussi l'adresse
de l'application dans Render > methe-api > Environment > `CORS_ORIGINS`
(elle y est déjà si vous gardez GitHub Pages).

**Android** : dans le même passage *Mise en ligne*, en bas de la page, section
*Artifacts* > **methe-android** : c'est un fichier zip contenant `app-release.apk`.
Copiez l'APK sur un téléphone et ouvrez-le (autorisez « installer des applications
inconnues »). Pour le Play Store, il faudra une clé de signature dédiée : ce sera
une étape à part.

## Connexion par code e-mail (ID client + mot de passe + code)

Le joueur saisit son **ID client** (ou son e-mail) et son mot de passe, puis le
**code à 6 chiffres** reçu sur l'e-mail du compte. Supabase génère, envoie et
vérifie ce code. Le serveur refuse toute session ouverte sans ce code.

À faire **dans cet ordre, avant de fusionner la PR** (sinon personne ne peut se connecter) :

1. **Envoi des e-mails (SMTP)** : l'envoi intégré de Supabase ne sert qu'aux essais
   (quelques e-mails par heure, uniquement vers les membres de l'équipe Supabase).
   Créez un compte gratuit chez un service d'envoi, par exemple **Brevo** (300 e-mails par jour),
   validez-y l'adresse d'expédition, puis dans Supabase > Authentication > **Emails** >
   *SMTP Settings* > **Enable custom SMTP** :
   - *Sender email* : l'adresse validée chez Brevo ; *Sender name* : `methe`
   - *Host* : `smtp-relay.brevo.com` ; *Port* : `587`
   - *Username* : l'identifiant SMTP Brevo ; *Password* : la clé SMTP Brevo
     (à saisir **uniquement dans Supabase**, jamais dans un message).
2. **Modèle de l'e-mail** : Authentication > Emails > *Templates* > **Magic Link** :
   - *Subject* : `Votre code de connexion methe`
   - *Body* (remplace tout le contenu) :

     ```html
     <h2>Votre code de connexion</h2>
     <p>Bonjour,</p>
     <p>Voici votre code pour vous connecter à methe :</p>
     <p style="font-size:28px;font-weight:bold;letter-spacing:6px">{{ .Token }}</p>
     <p>Ce code est valable 10 minutes. Si vous n'avez pas demandé à vous connecter,
     ignorez cet e-mail et changez votre mot de passe.</p>
     ```
   Ajoutez aussi `<p>Code : <b>{{ .Token }}</b></p>` au modèle **Confirm signup** :
   un joueur qui n'a pas encore cliqué sur le lien de confirmation reçoit cet
   e-mail-là quand il se connecte, et pourra utiliser le code.
3. **Durée du code** : Authentication > Sign In / Providers > **Email** >
   *Email OTP Expiration* : `600` secondes ; *Email OTP Length* : `6`.
4. **Limite d'envoi** : Authentication > **Rate Limits** > *Rate limit for sending emails* :
   au moins `100` par heure.
5. **Base** : SQL Editor > exécuter `supabase/migrations/20261009000015_login_code.sql`
   (fichier `methe-phase14-supabase.sql`).
6. **Test** : fusionnez la PR, attendez le redéploiement Render et la publication Web,
   puis connectez-vous avec votre ID client : le code doit arriver par e-mail.

Sécurité : 5 mots de passe faux en 15 minutes verrouillent le compte 15 minutes ;
5 codes faux obligent à recommencer ; un code n'est valable qu'une fois.
Si les codes n'arrivent pas : Supabase > Logs > **Auth** montre l'erreur d'envoi
(le plus souvent un réglage SMTP).

## Étape 4 — Contrôle final

1. Ouvrez l'application Web, connectez-vous avec votre compte administrateur.
2. Profil > **Administration — Tableau de bord** s'affiche avec les chiffres.
3. Jeux > Fruits : un tirage est ouvert avec un compte à rebours.
4. Relancez `verification_production.sql` dans Supabase : tout est **OK**.

## Mises à jour

Chaque PR fusionnée sur `main` :
- redéploie le serveur sur Render automatiquement ;
- republie l'application Web et produit un nouvel APK ;
- si la PR contient un fichier SQL, exécutez-le dans Supabase **avant** de fusionner.

Les tests automatiques (onglet Actions, *Tests*) doivent être verts avant toute fusion.

## En cas de problème

| Symptôme | Cause probable | Solution |
|---|---|---|
| `/health` ne répond pas | construction Render en échec | Render > methe-api > *Logs* |
| L'application affiche « Erreur 500 » | `DATABASE_URL` incorrecte | vérifier le mot de passe et le port 5432 (Session pooler) |
| « Jeton invalide ou expiré » à chaque action | clé JWT legacy non renseignée | saisir `SUPABASE_JWT_SECRET` dans Render (étape 1, JWT Keys) |
| Le navigateur bloque les appels (erreur CORS) | adresse de l'application absente de `CORS_ORIGINS` | l'ajouter dans Render > Environment |
| Aucun tirage ouvert | pg_cron inactif | activer pg_cron puis relancer `methe-phase5-supabase.sql` |
| Le lien de confirmation d'e-mail ouvre `localhost` | Site URL non réglée | étape 1, point 3 |
