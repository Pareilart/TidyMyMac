import Foundation

/// Une famille de fichiers inutiles et la façon de les localiser.
struct JunkCategory: Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    var selectedByDefault = true
    /// La Corbeille est toujours vidée définitivement, quel que soit le réglage.
    var alwaysPermanent = false
    let locate: @Sendable () -> [URL]
}

private func homePath(_ path: String) -> URL {
    FS.home.appendingPathComponent(path)
}

private func junkItems(in paths: String..., hidden: Bool = false, excluding excluded: Set<String> = []) -> [URL] {
    paths
        .flatMap { FS.children(of: homePath($0), includeHidden: hidden) }
        .filter { !excluded.contains($0.lastPathComponent) }
}

/// Caches que l'on préfère ne pas toucher (synchronisation iCloud, domotique, état de l'app elle-même).
private let protectedCaches: Set<String> = [
    "io.github.tidymymac.TidyMyMac",
    "CloudKit",
    "FamilyCircle",
    "com.apple.HomeKit",
    "com.apple.homed",
    "com.apple.akd",
    "com.apple.containermanagerd",
    "com.apple.ap.adprivacyd",
    "com.apple.Safari.SafeBrowsing",
]

extension JunkCategory {
    static var all: [JunkCategory] { [
        JunkCategory(
            id: "user-caches", title: localized("Caches des applications"),
            detail: localized("Fichiers temporaires recréés automatiquement par les applications."), icon: "archivebox"
        ) {
            junkItems(in: "Library/Caches", excluding: protectedCaches)
        },
        JunkCategory(
            id: "user-logs", title: localized("Journaux"),
            detail: localized("Fichiers de log et rapports de diagnostic."), icon: "doc.plaintext"
        ) {
            junkItems(in: "Library/Logs")
        },
        JunkCategory(
            id: "xcode-derived", title: localized("Xcode – DerivedData"),
            detail: localized("Produits de compilation intermédiaires, régénérés au prochain build."), icon: "hammer"
        ) {
            junkItems(in: "Library/Developer/Xcode/DerivedData")
        },
        JunkCategory(
            id: "device-support", title: localized("Xcode – Support des appareils"),
            detail: localized("Symboles d'anciennes versions d'iOS, watchOS, tvOS, retéléchargés au besoin."), icon: "iphone"
        ) {
            junkItems(
                in: "Library/Developer/Xcode/iOS DeviceSupport",
                "Library/Developer/Xcode/watchOS DeviceSupport",
                "Library/Developer/Xcode/tvOS DeviceSupport",
                "Library/Developer/Xcode/visionOS DeviceSupport"
            )
        },
        JunkCategory(
            id: "simulator-caches", title: localized("Caches du simulateur"),
            detail: localized("Caches des simulateurs iOS."), icon: "ipad"
        ) {
            junkItems(in: "Library/Developer/CoreSimulator/Caches")
        },
        JunkCategory(
            id: "xcode-archives", title: localized("Xcode – Archives"),
            detail: localized("Builds archivés. À garder si vous devez symboliser des rapports de plantage."), icon: "shippingbox",
            selectedByDefault: false
        ) {
            junkItems(in: "Library/Developer/Xcode/Archives")
        },
        JunkCategory(
            id: "dev-caches", title: localized("Caches de développement"),
            detail: localized("Caches de npm, Gradle et Cargo."), icon: "terminal"
        ) {
            [".npm/_cacache", ".gradle/caches", ".cargo/registry/cache"].map(homePath).filter(FS.exists)
        },
        JunkCategory(
            id: "mail-downloads", title: localized("Pièces jointes de Mail"),
            detail: localized("Copies locales des pièces jointes ouvertes ; elles restent dans les e-mails."), icon: "paperclip"
        ) {
            junkItems(in: "Library/Containers/com.apple.mail/Data/Library/Mail Downloads")
        },
        JunkCategory(
            id: "installers", title: localized("Images disque et installeurs"),
            detail: localized("Fichiers .dmg, .pkg, .iso et .xip du dossier Téléchargements."), icon: "opticaldiscdrive",
            selectedByDefault: false
        ) {
            junkItems(in: "Downloads").filter { ["dmg", "pkg", "iso", "xip"].contains($0.pathExtension.lowercased()) }
        },
        JunkCategory(
            id: "ios-backups", title: localized("Sauvegardes iPhone et iPad"),
            detail: localized("Sauvegardes locales d'appareils iOS."), icon: "externaldrive",
            selectedByDefault: false
        ) {
            junkItems(in: "Library/Application Support/MobileSync/Backup")
        },
        JunkCategory(
            id: "trash", title: localized("Corbeille"),
            detail: localized("Éléments déjà dans la Corbeille. Suppression définitive."), icon: "trash",
            alwaysPermanent: true
        ) {
            junkItems(in: ".Trash", hidden: true).filter { $0.lastPathComponent != ".DS_Store" }
        },
    ] }
}
