import SwiftUI

struct ModuleFeature: Hashable {
    let icon: String
    let text: String
}

/// Textes et couleurs de la page d'accueil de chaque module.
struct ModuleInfo {
    let tagline: String
    let accent: Color
    let heroSymbol: String
    let actionTitle: String
    let features: [ModuleFeature]
}

extension Module {
    var info: ModuleInfo {
        switch self {
        case .smartScan:
            return ModuleInfo(
                tagline: localized("Un seul clic pour faire le tour de votre Mac."),
                accent: Theme.mint, heroSymbol: "sparkles", actionTitle: localized("Analyser"),
                features: [
                    ModuleFeature(icon: "trash", text: localized("Fichiers inutiles à supprimer")),
                    ModuleFeature(icon: "power", text: localized("Éléments de démarrage cassés")),
                    ModuleFeature(icon: "internaldrive", text: localized("Espace disque disponible")),
                ]
            )
        case .search:
            return ModuleInfo(
                tagline: localized("Décrivez un document avec vos mots, l'IA le retrouve sur votre Mac."),
                accent: Theme.peach, heroSymbol: "text.magnifyingglass", actionTitle: localized("Activer"),
                features: [
                    ModuleFeature(icon: "cpu", text: localized("Modèle Hugging Face exécuté sur votre Mac")),
                    ModuleFeature(icon: "doc.viewfinder", text: localized("PDF, documents Word et scans (OCR)")),
                    ModuleFeature(icon: "lock.shield", text: localized("Aucun fichier ne quitte votre Mac")),
                ]
            )
        case .junk:
            return ModuleInfo(
                tagline: localized("Caches, journaux et restes de développement qui s'accumulent."),
                accent: Theme.aqua, heroSymbol: "trash", actionTitle: localized("Analyser"),
                features: [
                    ModuleFeature(icon: "archivebox", text: localized("Caches et journaux des applications")),
                    ModuleFeature(icon: "hammer", text: localized("Données Xcode, npm, Gradle et Cargo")),
                    ModuleFeature(icon: "paperclip", text: localized("Pièces jointes Mail et installeurs")),
                ]
            )
        case .rules:
            return ModuleInfo(
                tagline: localized("Choisissez ce que TidyMyMac nettoie, selon votre façon de travailler."),
                accent: Theme.peach, heroSymbol: "slider.horizontal.3", actionTitle: localized("Ouvrir"),
                features: [
                    ModuleFeature(icon: "person.2", text: localized("Profils prêts à l'emploi")),
                    ModuleFeature(icon: "plus.rectangle.on.folder", text: localized("Vos propres règles, sans code")),
                    ModuleFeature(icon: "checkmark.shield", text: localized("Un niveau de risque pour chaque règle")),
                ]
            )
        case .largeFiles:
            return ModuleInfo(
                tagline: localized("Retrouvez ce qui prend de la place sans que vous le sachiez."),
                accent: Theme.amber, heroSymbol: "doc.text.magnifyingglass", actionTitle: localized("Analyser"),
                features: [
                    ModuleFeature(icon: "scalemass", text: localized("Fichiers et paquets au-delà d'un seuil")),
                    ModuleFeature(icon: "clock", text: localized("Date de dernier accès")),
                    ModuleFeature(icon: "arrow.uturn.backward", text: localized("Envoi à la Corbeille, jamais de suppression directe")),
                ]
            )
        case .duplicates:
            return ModuleInfo(
                tagline: localized("Les copies identiques, comparées octet par octet."),
                accent: Theme.rose, heroSymbol: "doc.on.doc", actionTitle: localized("Analyser"),
                features: [
                    ModuleFeature(icon: "number", text: localized("Comparaison par empreinte SHA-256")),
                    ModuleFeature(icon: "square.stack.3d.up", text: localized("Regroupement par contenu, pas par nom")),
                    ModuleFeature(icon: "checkmark.shield", text: localized("Toujours un exemplaire conservé")),
                ]
            )
        case .spaceExplorer:
            return ModuleInfo(
                tagline: localized("Voyez d'un coup d'œil quels dossiers remplissent le disque."),
                accent: Theme.sky, heroSymbol: "chart.bar.doc.horizontal", actionTitle: localized("Explorer"),
                features: [
                    ModuleFeature(icon: "chart.bar.xaxis", text: localized("Taille réelle de chaque dossier")),
                    ModuleFeature(icon: "cursorarrow.click.2", text: localized("Navigation par double-clic")),
                    ModuleFeature(icon: "folder", text: localized("N'importe quel dossier ou disque")),
                ]
            )
        case .uninstaller:
            return ModuleInfo(
                tagline: localized("Supprimez une application sans laisser de traces."),
                accent: Theme.coral, heroSymbol: "xmark.app", actionTitle: localized("Lister"),
                features: [
                    ModuleFeature(icon: "square.grid.2x2", text: localized("Toutes vos apps et leur taille")),
                    ModuleFeature(icon: "folder.badge.minus", text: localized("Données associées dans ~/Library")),
                    ModuleFeature(icon: "arrow.counterclockwise", text: localized("Réinitialisation sans désinstaller")),
                ]
            )
        case .performance:
            return ModuleInfo(
                tagline: localized("Des recommandations et des outils pour un Mac plus réactif."),
                accent: Theme.lime, heroSymbol: "speedometer", actionTitle: localized("Analyser"),
                features: [
                    ModuleFeature(icon: "wrench.and.screwdriver", text: localized("Tâches d'entretien en un clic")),
                    ModuleFeature(icon: "person.crop.circle.badge.clock", text: localized("Apps lancées au démarrage")),
                    ModuleFeature(icon: "gearshape.2", text: localized("Agents et services d'arrière-plan")),
                ]
            )
        }
    }
}
