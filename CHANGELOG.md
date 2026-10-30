# Journal des versions

Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) et les numéros suivent le
[versionnage sémantique](https://semver.org/lang/fr/). Notez les nouveautés sous « Non publié » au fil de l'eau :
`scripts/release.sh` les rattache à la version publiée et s'en sert comme notes de release.

## [Non publié]

### Ajouté

- Recherche IA : retrouver un document en le décrivant en langage naturel, avec un modèle Hugging Face
  (intfloat/multilingual-e5-small) exécuté sur le Mac et l'OCR des scans et images. Indexation et recherche
  100 % locales : aucune donnée n'est envoyée à un serveur.
- Barre de recherche dans le panneau de la barre des menus, avec les résultats affichés sur place.
- Choix du modèle de la Recherche IA parmi cinq modèles open source vérifiés, ou n'importe quel modèle Hugging Face
  compatible (BERT, RoBERTa, XLM-RoBERTa, CamemBERT ; tokenizers Unigram et WordPiece ; poids F32, BF16 et F16).
- `scripts/setup-signing.sh` : signature locale stable, pour que macOS garde les autorisations entre deux compilations.
- Traductions en anglais, espagnol et allemand (l'app suit la langue de macOS) ; `scripts/check-translations.sh`
  liste les textes restant à traduire.
- Choix de la langue dans les Réglages, appliqué immédiatement sans relancer l'app, et accès direct aux Réglages
  depuis le bas de la barre latérale.
- Icône de l'app (Dock, Finder, barre des menus) : un balai et deux étincelles, dessinés en SwiftUI ;
  `scripts/make-icon.sh` régénère `Resources/AppIcon.icns`.
- README en anglais pour GitHub, avec des captures d'écran générées par l'app (`--screenshots`, données fictives).

### Corrigé

- L'alerte « Accès complet au disque » restait affichée alors que l'accès était accordé : la vérification lisait un
  fichier absent des versions récentes de macOS. Un bouton « Relancer » applique aussi l'accès sans quitter l'app à la main.

### Modifié

- Performances : un parcours en deux temps, avec des cartes de recommandations puis des gestionnaires détaillés
  (entretien, apps au démarrage, éléments d'arrière-plan) avec recherche, tri et sélection groupée.

## [0.1.0] - 2026-10-29

### Ajouté

- Analyse intelligente : fichiers inutiles, éléments de démarrage cassés et état du disque en un clic.
- Nettoyage des fichiers inutiles : caches, journaux, données Xcode et outils de développement, pièces jointes Mail,
  installeurs, sauvegardes iOS, Corbeille.
- Gros fichiers, doublons (empreinte SHA-256) et explorateur d'espace en bulles ou en liste, avec sélection multiple.
- Désinstallateur avec recherche des fichiers associés et réinitialisation d'app.
- Maintenance (mémoire, DNS, instantanés locaux, Spotlight, Mail, Launch Services) avec mesure des gains.
- Éléments de démarrage avec détection des agents cassés.
- Panneau de la barre des menus : disque, mémoire, processeur, batterie, réseau, volumes connectés.
- Total de l'espace libéré et vérification des nouvelles versions publiées sur GitHub.
