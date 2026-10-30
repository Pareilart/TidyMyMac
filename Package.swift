// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TidyMyMac",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "SemanticSearch", path: "Sources/SemanticSearch"),
        .executableTarget(name: "TidyMyMac", dependencies: ["SemanticSearch"], path: "Sources/TidyMyMac"),
        // Vérification de la recherche en ligne de commande : swift run search-check [dossier] [demande]
        .executableTarget(name: "search-check", dependencies: ["SemanticSearch"], path: "Sources/SearchCheck"),
    ]
)
