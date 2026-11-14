# Changelog

[English](CHANGELOG.md) · **Français**

## 1.5.0

Passe de sécurité et de robustesse :

- Installateur Homebrew figé sur un commit révisé avec vérification SHA-256, lancé depuis Terminal en utilisateur (plus d'invite admin dans l'app).
- Mises à jour atomiques (`.new`/`.old` avec restauration), contrôle du bundle ID, arguments shell positionnels, téléchargements limités à GitHub.
- Scripts de release : confirmation avant commit, plus de tag ni de push forcé, pas d'écrasement de release, clé privée via stdin, `chmod 600`.
- Identifiants IGDB dans le corps de la requête, erreurs Keychain remontées, limites de type et de taille des images.
- Processus : arbre complet à la fermeture, drainage parallèle des pipes, journal plafonné à 2 Mo, annulation via `Process.isRunning`.
- Commandes git neutralisant hooks et fsmonitor ; détection automatique du dépôt dans `~` supprimée.
- Python résolu en chemin absolu ; staging qui conserve l'extraction et vérifie l'espace sur son volume.
- Launcher limité aux bundles `org.nxnative.<16 hex>`, icônes chargées sur le thread principal.
- Flags de développement compilés uniquement en debug.

## 1.4.0

- Interface entièrement en anglais (par défaut), français commutable dans Apparence ; textes variables et états de PR suivent la langue.
- README anglais, dépôt internationalisé.
- Derniers textes français traduits dans Construire, Nouveautés, Réglages et Launcher.

## 1.3.0

- Onglet **Launcher** : jeux déjà construits sur le Mac, avec artwork, lancement direct et ajout depuis un dossier.
- Scan automatique des bundles `org.nxnative.*` (Bureau, Téléchargements, Applications, dossiers de build).

## 1.2.0

- Installation guidée : Homebrew et clone de nxnative depuis le client.
- Choix manuel des contenus du build (base, mises à jour, DLC).
- Thèmes Nuit / OLED / Jour, cinq couleurs d'accent, dock de navigation flottant.
- Mises à jour de l'app signées Ed25519, avec vérification SHA-256.
- Diagnostic : Homebrew et git, copie du rapport, relance à chaque ouverture.
- IGDB : jaquettes et bannières, cache local, attribution.
- Bandeau d'artwork dans la fiche de build, fenêtre de build en temps réel.
- Annulation qui arrête toute la descendance des processus.
- Tests automatisés (`swift test`).

## 1.1.0

- Mise à jour de nxnative depuis le client, page Nouveautés, changelog après un pull.
- Versioning unique (`VERSION`), DMG, dSYM, licence MIT.
