# Captures store (App Store et Google Play)

Comment produire les captures des stores de drafft, et pourquoi elles sont faites ainsi. Le jeu validé le
30 septembre 2026 se régénère à l'identique avec une commande : pas besoin de le refaire, ni de redemander
à une IA d'itérer.

## Régénérer

Prérequis : Xcode et xcodegen, Google Chrome dans `/Applications`, Python 3 avec Pillow et numpy,
et `Local.private.xcconfig` à la racine du repo (`scripts/local-backend.sh`).

```sh
docs/store-screenshots/run.sh            # tout : build, captures, détourage, composition (environ 20 min)
docs/store-screenshots/run.sh compose    # seulement la composition, après un changement de texte ou de mise en page (quelques secondes par langue)
docs/store-screenshots/run.sh feature    # seulement l'image de présentation Google Play
```

- `STORE_WORK` (par défaut `~/Library/Caches/drafft-store-shots`) garde le build, les captures brutes et les
  éléments détourés. `STORE_OUT` (par défaut `~/Projets/drafft/store-screenshots`) reçoit les PNG.
- Aperçu : chaque composition existe aussi en HTML dans `STORE_WORK/html/<format>/<langue>.html`, à ouvrir
  dans un navigateur. Les planches `STORE_WORK/lib-<langue>.jpg` montrent les éléments détourés de chaque langue.
- Les images ne sont pas versionnées (plus de 200 Mo). Tout se recalcule depuis le code de l'app, ce patch
  et ces scripts.

### Ce qui sort

5 captures par langue, en PNG RGB sans transparence.

| Dossier | Store | Taille | Règle officielle |
|---|---|---|---|
| `app-store/iphone-6.9` | App Store Connect | 1320 × 2868 | Taille iPhone exigée ; Apple en tire les autres tailles d'iPhone |
| `app-store/ipad-13` | App Store Connect | 2064 × 2752 | Exigée seulement si l'app tourne sur iPad (drafft est iPhone seul : `TARGETED_DEVICE_FAMILY: "1"`) |
| `google-play/phone` | Play Console | 1080 × 1920 | 9:16, 1080 px minimum pour être éligible aux mises en avant, 4 captures au moins |
| `google-play/tablet-7` | Play Console | 1080 × 1920 | 9:16, de 1080 à 7680 px |
| `google-play/tablet-10` | Play Console | 1620 × 2880 | 9:16, de 1080 à 7680 px |

Langues : `en-GB`, `fr-FR`, `es-ES`, `de-DE`, `it-IT`, `pt-PT`, `nl-NL`.

Google Play demande aussi une **image de présentation** : `google-play/feature-graphic/<langue>/<version>.png`,
1024 × 500, sans transparence (voir plus bas).

Sources : [Apple, Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/),
[Google Play, Add preview assets](https://support.google.com/googleplay/android-developer/answer/9866151).

## Comment ça marche

1. **Capture** (`store-shots.patch`, `run.sh capture`). Le patch ajoute à l'app un module de capture,
   `Drafft/App/StoreShots.swift`, compilé seulement avec le drapeau `STORE_SHOTS` : il ne part jamais dans un
   build publié. Le module remplit les vrais écrans avec les profils fictifs de démo, sans backend, et ouvre la
   scène demandée par `STORE_SCENE` dans la langue `STORE_LANG` (`STORE_TOP` isole un profil sur Découvrir,
   `STORE_SCROLL` fait défiler un profil ou une feuille). `run.sh` l'applique dans un worktree temporaire,
   compile en configuration Local, et capture 9 écrans par langue sur un simulateur iPhone 6,9" dédié
   (« drafft store 6.9 », barre d'état à 9:41).
2. **Détourage** (`extract.py`). Chaque élément est retrouvé à ses couleurs réelles (bloc sombre, bloc gris,
   cartes blanches sur fond gris, étiquettes grises), puis découpé au pixel natif avec son fond retiré et ses
   bords adoucis. C'est ce qui permet aux textes plus longs, en allemand ou en néerlandais, de déplacer les
   blocs sans rien casser.
3. **Composition** (`compose.py`). Les 5 captures forment un seul visuel continu. Il est conçu sur une largeur de
   1320 et une hauteur propre à chaque format (iPhone 2868, 9:16 2347, iPad 1760), puis rendu par Chrome à la
   taille du store. Avant chaque rendu, un contrôle automatique bloque la composition si :
   - quelque chose sort par le haut, le bas ou les bords extérieurs ;
   - un élément coupé entre deux captures dépasse de moins de 80 px d'un côté ;
   - un cœur se trouve sur une couture.

## Image de présentation Google Play (1024 × 500)

`feature.py` la compose à partir des mêmes éléments détourés, dessinée en 2048 × 1000 puis réduite pour plus de
netteté. Dix versions sont prêtes, chacune dans les 7 langues, avec un slogan de WORDING.md §7.2 :

| Version | Idée | Slogan |
|---|---|---|
| **`01-deck` (retenue)** | Logo sans sillage et slogan à gauche, vraies cartes Découvrir et like à droite | Rencontre des célibataires qui partagent ton rythme. |
| `02-creneaux` | Trois cartes de créneaux sur graphite | Des rencontres avec une heure de départ. |
| `03-photo` | Coureur au coucher du soleil en plein cadre, texte blanc sur voile | Rendez-vous au départ. |
| `04-logo` | Le logo en très grand avec son sillage | Rendez-vous au départ. |
| `05-voix` | Nuit : l'icône de l'app, l'intro vocale et l'éclatement de cœurs | Rendez-vous au départ. |
| `06-bande` | Quatre vrais éléments en ligne sous le slogan | Transforme tes matchs en séances. |
| `07-ticket` | « Samedi, 9:00. » en titre, la carte de Maya et son créneau | Rendez-vous au départ. |
| `08-chiffre` | « 9:00 » géant, une carte et son créneau | Rendez-vous au départ. |
| `09-commun` | Le bloc sports sur un « 3× » ton sur ton | Transforme tes matchs en séances. |
| `10-depart` | Une ligne de départ blanche sur graphite, le créneau posé dessus | Rendez-vous au départ. |

Règles de Google Play, vérifiées à chaque rendu :
- le nom, le slogan et le visuel principal restent dans la zone sûre de 924 × 400, centrée, car Google peut
  rogner les bords ou arrondir les coins ;
- aucun élément de l'app n'est coupé par un bord ;
- texte court, sans prix, classement ni « nouveau ».

La version retenue est dans `CHOSEN` (`feature.py`) : `run.sh feature` ne produit qu'elle, sous le nom
`feature-graphic.png`. Pour revoir les dix : `python3 feature.py WORK OUT 01-deck 02-creneaux …`.

Son slogan est écrit pour la bannière : « Rendez-vous au départ » sonnait étrange et ne disait pas qu'il s'agit de
rencontres sportives. Formulation neutre dans les langues qui marquent le genre (« gente soltera »,
« pessoas solteiras »). Écartés : « le premier rendez-vous est une séance » (territoire de bpm), « et plus si
affinités » (double sens), « tout commence par… » (Tinder), « célibataire et sportif » (masculin par défaut).

Source : [Google Play, Add preview assets](https://support.google.com/googleplay/android-developer/answer/9866151).

## Modifier

- **Un texte** : `C` dans `compose.py` (7 langues, `\n` pour un retour à la ligne, espace insécable pour lier
  deux mots). Les titres réduisent leur taille d'eux-mêmes pour tenir sur leur nombre de lignes. Puis
  `run.sh compose`.
- **Une position, une taille, un angle** : `items()` dans `compose.py` (coordonnées de l'iPhone, adaptées
  automatiquement aux autres formats). Puis `run.sh compose`.
- **Un profil, un prénom, un quartier, un contenu de profil** : dans `StoreShots.swift`. Appliquer le patch sur
  une copie, modifier, régénérer le patch (`git diff -- . ':(exclude)Drafft.xcodeproj/project.pbxproj' > store-shots.patch`,
  après `git add -N Drafft/App/StoreShots.swift`), puis `run.sh`.
- **Une langue** : ajouter ses textes dans `C`, `HOUR` et `LOCALE` (`compose.py`), ses prénoms et contenus
  dans `StoreShots.swift`, et l'ajouter à `LANGS` dans `run.sh`.
- **Après une évolution de l'app** : `run.sh` refait tout depuis l'app actuelle. Si le patch ne s'applique
  plus, le reporter sur les fichiers concernés : les points d'accroche sont peu nombreux et marqués
  `#if STORE_SHOTS`.

## Le jeu validé

| # | Fond | Ce qu'on voit | Texte (FR / EN) |
|---|---|---|---|
| 1 | Gris | Les vraies cartes Découvrir en éventail : une femme blanche devant (tennis), Maya dessous, un homme derrière ; le like | **Samedi, 9:00.** Ta prochaine séance a de la compagnie. / **Saturday, 9:00.** Your next session has company. |
| 2 | Graphite | Les trois cartes de créneaux qui tombent ; la carte de l'homme en VTT arrive de la 1 | **Propose une séance.** Trouvez ensemble le moment qui vous convient. / **Propose a session.** Find the time that suits you both. |
| 3 | Blanc | Le bloc sports de l'homme Hyrox (« Tu en fais aussi »), un « 3× » géant ton sur ton, 3 étiquettes de mode de vie ; sa photo Hyrox passe dans la 4 | **Un sport en commun ?** Ça se voit tout de suite. / **A sport in common?** You see it straight away. |
| 4 | Gris | Le bloc « Deux vérités, un mensonge », une question avec sa réponse, l'étiquette « Couche-tard » | **L'icebreaker fait le premier pas.** / **Icebreakers make the first move.** |
| 5 | Nuit | L'intro vocale de Maya, sa question, et l'éclatement de cœurs de l'app qui jaillit du bouton like ; le logo | **Écoute sa voix. Like ce qui te parle.** / **Hear their voice. Like what speaks to you.** |

Prénoms et quartiers par langue (femme devant, Maya, homme dessous, homme en VTT, homme Hyrox) :

| Langue | Ville | Prénoms |
|---|---|---|
| fr | Paris | Léa, Maya, Thomas, Julien, Antoine |
| en | Londres | Emily, Maya, Jack, Daniel, Ryan |
| es | Madrid | Lucía, Maya, Pablo, Javier, Álvaro |
| de | Berlin | Lena, Maya, Jonas, Lukas, Felix |
| it | Milan | Giulia, Maya, Marco, Luca, Matteo |
| pt | Lisbonne | Beatriz, Maya, Tiago, Miguel, Duarte |
| nl | Amsterdam | Sanne, Maya, Daan, Bram, Thijs |

## Les règles tirées des itérations

Chaque règle ci-dessous corrige quelque chose qui a été montré et refusé.

**Ce qui compte vraiment**
- La 1 et la 2 font le travail. Peu de gens font défiler. Dans la recherche, la 1 s'affiche à côté de l'icône,
  à environ 120 px de large : seuls 3 à 5 mots énormes s'y lisent. Les 3 premières captures s'affichent côte à
  côte et doivent chacune tenir seules.
- La 1 accroche avec un visage et le concret (« Samedi, 9:00. ») ; la 2 montre le mécanisme (proposer une
  séance avec des créneaux). Aucune app de rencontre sportive ne montre une proposition avec des horaires :
  c'est ce qui distingue drafft.
- Ne pas répéter le sous-titre du store (« Célibataires à ton rythme », WORDING §7.4) en 1ʳᵉ capture : il est
  déjà affiché à côté.
- Pas de capture sur les filtres ni sur la vérification : tous les concurrents y consacrent des captures, sans
  que ça les distingue.

**Pas de téléphone, de vrais éléments**
- On ne dessine jamais l'interface : chaque élément est un vrai morceau de l'app, capturé puis détouré. Si une
  idée demande quelque chose que l'app ne fait pas, on ne l'ajoute pas. Exemple : l'intro vocale n'a pas de
  bouton like dans l'app, donc pas de cœur sur elle.
- L'éclatement de cœurs de la 5 reproduit `HeartBurst`, l'animation du like de l'app (7 cœurs, le vert du like
  et sa teinte claire), figée et agrandie.
- Agrandissement limité (1,45 au plus) pour rester net.

**Composition**
- Chaque capture a son fond, sa place de titre, son échelle et ses angles : un jeu où tout se ressemble paraît
  « classique ». Mais un seul objet fort par capture, plus un ou deux accents : trop d'éléments paraissent
  fouillis.
- Ce qui est coupé par un bord doit continuer, visible, sur la capture voisine (80 px au moins de chaque côté).
  Rien n'est coupé en haut, en bas, ni aux deux bouts du jeu.
- Jamais un cœur sur une couture : coupé en deux, c'est un cœur brisé.
- L'ombre de sillage (le motif du logo) est réservée à quelques éléments : ni sur la carte de la 1, ni sur
  l'icebreaker.
- Des photos aux couleurs bien distinctes les unes des autres.

**Personnes et texte**
- Pas d'effet « collectionneur » : pas de « premier rendez-vous » à côté d'une pile de profils ; le texte parle
  d'une séance, au singulier.
- Diversité des personnes : la carte de devant montre une femme blanche, un homme est sous Maya. Prénoms courants
  dans chaque marché, sans consonance maghrébine, avec des quartiers de la capitale du marché.
- Chaque titre dit exactement ce que montre la capture, avec les mots de l'app (« Tu en fais aussi » pour la 3,
  « Like ce qui te parle » pour la 5 ; pas « like ses questions », ni « like sa réponse »).
- Un titre ne doit pas pouvoir se lire comme « à toi de t'adapter » : « Son sport. Son rythme. » a été écarté
  pour cette raison.
- Tout le texte suit [WORDING.md](../../WORDING.md) : tutoiement, pluriel quand on s'adresse aux deux (« Trouvez
  ensemble », vosotros, ihr), rien d'inventé, aucun mot interdit, pas de « · », de « … » ni de « ! ». Les textes
  des 7 langues passent la liste interdite de WORDING.md §5.6.

## À faire avant publication

- Les photos de profil de synthèse sont en 600 × 900 : les régénérer en haute définition
  (`scripts/generate-pack-photos.py`).
- Vérifier les droits des photos plein cadre `hero_1` (tennis) et `hero_2` (Hyrox) de l'app.
- Les dates (sam. 3 oct.) sont calculées au moment de la capture : lancer `run.sh` juste avant la sortie.
- Tester la 1ʳᵉ capture avec Product Page Optimization.

## Historique

Recherche concurrence : Hinge, Bumble, Breeze, Timeleft, Tinder, happn, Raya, bpm et les apps de sport
(Strava, Runna, Playtomic…). Il en ressort : une idée par capture, un système typographique fixe, un objet
signature, et le vrai rendez-vous montré tôt.

Directions essayées avant ce jeu : écran entier dans un téléphone, zoom sur un élément, éléments seuls
(éventail, sillage, chiffres géants, terrain), jeu épuré. Galerie privée des essais :
<https://claude.ai/artifact/Wutc2jVgvR8tk3SfnBXrqE>.
