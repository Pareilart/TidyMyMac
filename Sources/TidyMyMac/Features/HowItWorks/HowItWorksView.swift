import SwiftUI

/// « Comment ça marche » : ce que TidyMyMac fait, ce qu'il ne fait pas, et quand un nettoyage ne sert à rien.
struct HowItWorksView: View {
    @EnvironmentObject var navigation: AppNavigation

    private var repositoryURL: URL? {
        let repository = Bundle.main.object(forInfoDictionaryKey: "TMMReleasesRepository") as? String ?? ""
        guard repository.split(separator: "/").count == 2 else { return nil }
        return URL(string: "https://github.com/\(repository)")
    }

    var body: some View {
        VStack(spacing: 0) {
            ModuleHeader(module: .howItWorks)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ExplanationCard(icon: "checkmark.circle", tint: Theme.mint, title: "Ce que fait TidyMyMac", points: [
                        localized("Il supprime des fichiers désignés par des règles publiques : caches, journaux, restes de développement, installeurs. Chaque règle explique ce qu'elle supprime et ce qui se passe ensuite."),
                        localized("Il montre tout avant d'agir : le plan de nettoyage liste chaque élément, sa règle, son risque et sa destination, et attend votre confirmation."),
                        localized("Il garde une trace : l'historique note chaque élément supprimé, et ce qui est dans la Corbeille peut être remis en place."),
                        localized("Il mesure les gains de l'entretien avant et après, au lieu de les estimer."),
                    ])
                    ExplanationCard(icon: "xmark.circle", tint: Theme.coral, title: "Ce qu'il ne fait pas", points: [
                        localized("Il ne rend pas le Mac plus rapide par magie. Supprimer des caches libère de l'espace, pas de la vitesse : les apps les recréent, et sont parfois un peu plus lentes le temps de le faire."),
                        localized("Il ne touche pas aux fichiers protégés de macOS. Vos documents, photos et messages ne partent que si vous les choisissez vous-même, dans Gros fichiers, Doublons ou l'Explorateur d'espace."),
                        localized("Il n'envoie rien : ni vos fichiers, ni vos recherches, ni statistiques d'usage. Les seules connexions sont la vérification des mises à jour, que vous pouvez désactiver, le téléchargement d'un modèle pour la Recherche IA et le test de débit que vous lancez vous-même."),
                        localized("Il ne cherche pas à vous inquiéter : pas d'alerte alarmiste, pas de routine imposée, pas d'abonnement."),
                    ])
                    ExplanationCard(icon: "info.circle", tint: Theme.amber, title: "Quand nettoyer ne sert à rien", points: [
                        localized("Quand il reste beaucoup d'espace libre : au-delà de quelques dizaines de gigaoctets, nettoyer ne change rien de visible."),
                        localized("Pour la mémoire « utilisée » : macOS se sert de la mémoire libre comme cache, c'est voulu. La libérer n'aide que si macOS signale une mémoire sous tension, et TidyMyMac ne la conseille que dans ce cas."),
                        localized("Pour les caches d'une app que vous utilisez tous les jours : ils reviendront vite."),
                        localized("Pour le fichier d'échange, les caches système et une bonne partie des « Données système » : macOS les gère seul et libère de l'espace quand il en manque. TidyMyMac n'y touche pas."),
                    ])
                    ExplanationCard(icon: "magnifyingglass.circle", tint: Theme.sky, title: "Vérifier par vous-même", points: [
                        localized("Le code est public, sous licence MIT : n'importe qui peut lire ce que fait l'app."),
                        localized("Les règles sont des fichiers lisibles, expliquées une par une dans Règles et profils."),
                        localized("Le plan de nettoyage et l'historique s'exportent en CSV ou JSON."),
                        localized("Dans le Terminal, l'option --list-rules simule tout le nettoyage sans rien supprimer."),
                    ])
                    HStack(spacing: 12) {
                        if let repositoryURL {
                            Link(destination: repositoryURL) {
                                Label("Voir le code sur GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                        Button { navigation.selection = .rules } label: {
                            Label("Ouvrir Règles et profils", systemImage: "slider.horizontal.3")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        Button { navigation.selection = .history } label: {
                            Label("Ouvrir l'historique", systemImage: "clock.arrow.circlepath")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    .padding(.top, 4)
                }
                .padding(24)
            }
        }
    }
}

private struct ExplanationCard: View {
    let icon: String
    let tint: Color
    let title: LocalizedStringKey
    let points: [String]

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            IconTile(symbol: icon, tint: tint, size: 38)
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.system(.title3, design: .rounded).weight(.semibold))
                ForEach(points, id: \.self) { point in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(tint).frame(width: 5, height: 5).offset(y: -2)
                        Text(point).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.cardBorder))
    }
}
