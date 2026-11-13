import Foundation

// MARK: - Language

enum AppLanguage: String, CaseIterable, Codable, Identifiable {
    case fr, en
    var id: String { rawValue }
    var title: String { self == .fr ? "Français" : "English" }
    var short: String { rawValue.uppercased() }
}

/// Lightweight localization: French strings are the keys, English lives in the
/// table below. Anything missing falls back to French.
enum L {
    static var language: AppLanguage = .fr

    static func t(_ french: String) -> String {
        guard language == .en else { return french }
        return english[french] ?? englishExtra[french] ?? french
    }

    static func t(_ french: String, _ englishText: String) -> String {
        language == .fr ? french : englishText
    }

    private static let english: [String: String] = [
        // Navigation
        "Bibliothèque": "Library",
        "Launcher": "Launcher",
        "Construire": "Build",
        "Nouveautés": "What's new",
        "Réglages": "Settings",
        "Aller": "Go",
        "ESPACE DE TRAVAIL": "WORKSPACE",

        // Actions
        "Nouvelle build": "New build",
        "Actualiser": "Refresh",
        "Vérifier": "Check",
        "Copier": "Copy",
        "Fermer": "Close",
        "Annuler": "Cancel",
        "Enregistrer": "Save",
        "Choisir…": "Choose…",
        "Re-scan": "Rescan",
        "Rescanner": "Rescan",
        "Ouvrir un dossier": "Open a folder",
        "Récupérer": "Fetch",
        "Vider": "Clear",
        "Tester": "Test",
        "Installer": "Install",
        "Interrompre": "Stop",
        "Tout installer": "Install all",
        "Mettre à jour": "Update",
        "Cloner nxnative": "Clone nxnative",
        "Parcourir": "Browse",
        "Reprendre": "Resume",
        "Effacer": "Clear",
        "Comparer": "Compare",
        "GitHub": "GitHub",
        "Lancer": "Play",
        "Jouer": "Play",
        "Afficher dans le Finder": "Show in Finder",
        "Copier le chemin": "Copy path",
        "Lancer le build": "Start build",
        "Arrêter": "Stop",

        // Headers
        "Environnement, mises à jour et diagnostic": "Environment, updates and diagnostics",
        "Pull requests et fonctionnalités récentes de nxnative": "Recent pull requests and features in nxnative",
        "Packagez un jeu en app native": "Package a game as a native app",
        "Recherche des jeux construits sur ce Mac…": "Scanning games built on this Mac…",
        "Aucun jeu construit détecté": "No built game found",

        // Library
        "Tous": "All",
        "Switch 2": "Switch 2",
        "Installés": "Installed",
        "Nom ou title ID": "Name or title ID",
        "Aucun jeu trouvé": "No game found",

        // Settings
        "Apparence": "Appearance",
        "Environnement": "Environment",
        "Visuels des jeux": "Game artwork",
        "Diagnostic": "Diagnostics",
        "Historique des builds": "Build history",
        "Thème et couleur d'accent, appliqués immédiatement": "Theme and accent colour, applied instantly",
        "Accent": "Accent",
        "Navigation": "Navigation",
        "Barre latérale": "Sidebar",
        "Dock flottant": "Floating dock",
        "Nuit": "Night",
        "Jour": "Day",
        "Le thème d'origine": "The original theme",
        "Noir absolu, pour les dalles OLED": "True black, for OLED panels",
        "Surfaces claires": "Light surfaces",
        "Mise à jour nxnative": "nxnative update",
        "Cible par défaut": "Default target",
        "Non configuré": "Not configured",
        "Utilisée quand vous ouvrez un jeu": "Used when you open a game",
        "Vérifiez si le checkout local est à jour": "Check whether the local checkout is up to date",
        "Aucun dossier sélectionné": "No folder selected",
        "À jour": "Up to date",
        "pas un dépôt git": "not a git repository",
        "non vérifié": "not checked",
        "Vérification…": "Checking…",
        "Vérification impossible": "Check failed",
        "Aucun build enregistrée": "No build recorded",
        "Client non officiel": "Unofficial client",
        "Client macOS non officiel pour nxnative, sans affiliation avec Nintendo. Les jeux et leurs données restent sur votre Mac ; rien n'est envoyé.":
            "Unofficial macOS client for nxnative, not affiliated with Nintendo. Games and their data stay on your Mac; nothing is sent.",

        // Build
        "Source du jeu": "Game source",
        "Empaquetage": "Packaging",
        "Options avancées": "Advanced options",
        "Contenus du build": "Build contents",
        "Cible": "Target",
        "App Mac": "Mac app",
        "Développement": "Development",
        "iPhone & iPad": "iPhone & iPad",
        "Mise à jour": "Update",
        "Base": "Base",
        "DLC": "DLC",
        "Autre": "Other",
        "Tout sélectionner": "Select all",
        "Tout désélectionner": "Deselect all",

        // Launcher
        "Aucun jeu installé": "No game installed",

        // News
        "Tout": "All",
        "Ouvertes": "Open",
        "Terminées": "Done",
        "Pull requests ouvertes": "Open pull requests",
        "Terminées · 14 jours": "Done · 14 days",
        "Contributeurs dans le flux": "Contributors in the feed",
        "Travail ouvert, du plus récemment modifié au plus ancien": "Open work, most recently updated first",
        "Pull requests fusionnées ou fermées": "Merged or closed pull requests",
        "Récemment terminées": "Recently done",
        "En cours": "In progress",
        "hors ligne": "offline",
        "Synchronisation…": "Syncing…",
        "Aucune activité à afficher": "Nothing to show",
        "Réessayer": "Retry",

        // Updates
        "Mises à jour": "Updates",
        "Vérifier les mises à jour…": "Check for updates…",
        "Recherche de mise à jour…": "Checking for updates…",
        "Vous êtes à jour": "You're up to date",
        "Télécharger le DMG": "Download DMG",
        "Installer maintenant": "Install now",
        "Mise à jour impossible": "Update failed",

        // Setup
        "Installation de Homebrew": "Installing Homebrew",
        "Clone de nxnative": "Cloning nxnative",
        "Installation": "Installation",

        // Console
        "Journal": "Log",
        "Détails": "Details",
        "Prêt": "Ready",
        "Échec": "Failed",
        "Annulé": "Cancelled",
        "global": "overall",
    ]
}
