# Journal des versions

Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) et les numéros suivent le
[versionnage sémantique](https://semver.org/lang/fr/). Notez les nouveautés sous « Non publié » au fil de l'eau :
`scripts/release.sh` les rattache à la version publiée et s'en sert comme notes de release.

## [Non publié]

## [0.2.0] - 2026-10-30

### Ajouté

- Règles de nettoyage déclaratives en JSON (`Resources/Rules`) : chaque catégorie de fichiers inutiles affiche son
  niveau de risque (sans danger, à vérifier, irréversible) et explique, via le bouton ⓘ, ce qu'elle supprime, ce qui se
  passe ensuite et où elle cherche.
- Écran « Règles et profils » : profils Développeur, Photographe et Vidéaste (node_modules, Gradle, Cargo, Maven,
  aperçus Lightroom, rendus Final Cut Pro, caches Adobe et DaVinci Resolve), avec détection des outils présents sur le
  Mac ; chaque règle peut être désactivée.
- Création de règles personnelles dans un formulaire (dossiers, recherche par nom, extensions, ancienneté, niveau de
  risque), avec un bouton « Tester la règle » qui montre ce qu'elle trouverait sans rien supprimer. Garde-fous : jamais de
  dossier système ni de dossier personnel entier, jamais de suppression définitive imposée.
- Numéro de version affiché sous le nom de l'app, en haut de la barre latérale.
- `TidyMyMac --list-rules` affiche ce que chaque règle active trouverait, sans rien supprimer ; `scripts/check-translations.sh`
  vérifie aussi les règles intégrées.
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

- Captures d'écran : le sélecteur de langue montrait la langue enregistrée sur le Mac au lieu de celle des captures.
- L'alerte « Accès complet au disque » restait affichée alors que l'accès était accordé : la vérification lisait un
  fichier absent des versions récentes de macOS. Un bouton « Relancer » applique aussi l'accès sans quitter l'app à la main.

### Modifié

- Les pièces jointes de Mail ne sont plus cochées par défaut : une pièce jointe modifiée depuis Mail n'existe parfois
  que là.
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
