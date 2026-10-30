import Foundation

public enum SemanticSearchLocalization {
    /// Traductions de la langue choisie dans l'app ; `Bundle.main` (langue du lancement) par défaut.
    nonisolated(unsafe) public static var bundle: Bundle = .main
}

/// Texte traduit dans la langue choisie, même si elle a changé depuis le lancement.
func localized(_ value: String.LocalizationValue) -> String {
    String(localized: value, bundle: SemanticSearchLocalization.bundle)
}
