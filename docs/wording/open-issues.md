# Points ouverts après la refonte du wording

Relevés pendant la réécriture, non corrigés parce qu'ils demandent une décision produit, juridique ou
un changement de code plus large. Une fois tranchés, les décisions éditoriales vont dans
[WORDING.md §11](../../WORDING.md#11-decision-log).

## Bloquant avant publication

- **Recherche de marque** « Meet me on the start line » / « Rendez-vous au départ » (INPI, EUIPO,
  classe 45) : seulement si la phrase sert en campagne. Depuis le 30/09/2026, la phrase principale est
  « Meet singles who train » / « Rencontre des célibataires qui s'entraînent » (WORDING §7.2).

## Décisions produit

- Valider les taglines (WORDING.md §7.2, statut « proposed »).
- Prompt « I'm looking for someone who » : proche de la question « looking for » que DESIGN.md exclut.
  Garder ou retirer ?
- « How often you train shapes who you meet » (onboarding) promet plus que ce que fait l'app.
- Paywall : « Most popular » est devenu « Recommended ». Mieux : afficher l'économie calculée sur 6 mois,
  comme sur 12 mois.
- Orthographe de « super like » par langue (ES/NL « superlike », DE « Super Like ») : en fixer une.
- ES/PT : « iniciar sesión / sessão » (connexion) utilise le même mot que la séance de sport.
- Emails sans preheader : à ajouter si le client email le permet.
- Cartes de séance dans le chat en anglais seulement (message unique pour deux personnes).

## Dette de code (sans effet visible, les textes affichés sont déjà corrigés)

- Des clés Swift gardent l'ancien texte anglais (« Plus », « Keep swiping », « Pitch it », « No pitch
  yet »). La valeur affichée vient de la
  localisation `en`. Renommer les clés dans le code et le catalogue.
- « Propose these times (2 times) » : le compteur est redondant dans la feuille de contre-proposition.
- « Get boosts » et « Get more super likes » : deux formes pour le même bouton.
- 111 clés orphelines et environ 70 phrases de `SportCatalog.swift` jamais lues.
- `Sport.inSentence` : pas d'élision en FR (« du escalade ») si un texte place le sport après « du ».
- `project.yml` : les textes de repli des permissions ne suivent pas le catalogue (localisation
  alignée, les autres à vérifier).

## Déploiement backend

- Ordre : `scripts/stream-push.ts` (modèle Stream), puis les fonctions, puis une resynchronisation des
  utilisateurs Stream (langue).
- Noms des achats intégrés : les noms des packs gardent leurs majuscules (« 1 Boost », « 3 Super Likes »), comme dans
  App Store Connect et Google Play. Rien à reporter.
- Fiches stores : `docs/wording/store.md`, checklist « à valider » en fin de fichier.
