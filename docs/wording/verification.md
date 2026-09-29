# Vérification du dispositif WORDING.md (29 septembre 2026)

## Tâche fictive

Même consigne pour les deux tests, sans mentionner WORDING.md :

> Le PM propose ce texte pour la notification push envoyée le soir d'un nouveau match : « Ton match se
> transforme en plan ce soir ! 🔥 ». Améliore-le, et écris aussi la bannière in-app (titre + bouton) qui
> incite à proposer une séance à un match récent. EN et FR. Ne modifie aucun fichier.

## Test 1 : session Claude Code ouverte dans le dépôt (cas réel)

`claude -p` lancé depuis la racine de `drafft`, outils limités à la lecture.

- Chargement : CLAUDE.md (règle prioritaire) chargé automatiquement.
- Premier appel d'outil : le skill `wording`, puis lecture de `WORDING.md`, puis recherche des textes
  existants dans le catalogue.
- Résultat :
  - Push : titre = prénom (« Quelqu'un » si inconnu), corps « Nouveau match aujourd'hui : propose-lui
    une première séance tant que c'est frais. »
  - Bannière : « C'est réciproque avec {prénom}. » / bouton « Proposer une séance ».
- Règles citées : §5.1 (« plan » banni, le match ne se transforme pas), §6 (pas de « ! » ni d'emoji en
  push), §4 (verbe unique « proposer »), §10 (checklist). Il signale que les 5 autres langues restent à
  écrire.
- Verdict : **réussi**.

## Test 2 : sous-agent générique (sans CLAUDE.md chargé d'office)

Sous-agent lancé depuis une autre session, avec seulement le chemin du dépôt.

- Il a trouvé et lu `WORDING.md` en entier et `.agents/skills/wording/SKILL.md` en explorant la
  racine du dépôt, puis a vérifié les textes existants.
- Résultat : push « Match du jour : propose une première séance tant que c'est frais. », bannière
  « C'est réciproque avec %@. » / « Proposer une séance » (clé déjà existante).
- Il a relevé cinq infractions dans la proposition du PM : « plan », la promesse de transformation,
  « ce soir », « ! » et l'emoji 🔥, ce dernier au titre du double sens (§5.2).
- Verdict : **réussi**. Un premier lancement avait échoué sur une limite de débit de l'API (HTTP 429),
  sans lien avec le dispositif.

## Contrôles automatiques (filet de sécurité)

| Dépôt | Contrôle | Avant la refonte | Après |
|---|---|---|---|
| drafft | `python3 scripts/ci/i18n_lint.py` (bloc `wording-forbidden`) | 24 erreurs | 0 |
| drafft-backend | `deno test` (`_tests/wording_test.ts`) | nouveau | 99 tests OK |
| drafft-web | `pnpm wording` (étape CI) | 38 erreurs | 0 |

## Limites

- Un agent qui n'ouvre jamais le dépôt (texte rédigé dans une conversation sans fichier) ne voit ni
  CLAUDE.md ni le skill. Le hook `UserPromptSubmit` proposé couvre en partie ce cas.
- Les lints attrapent des mots, pas le sens : une promesse formulée sans mot interdit passe. La
  checklist §10 reste nécessaire.
