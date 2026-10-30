import AppKit
import SwiftUI

struct SettingsView: View {
    @AppStorage("deletePermanently") private var deletePermanently = false
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
    @AppStorage(Stats.totalFreedKey) private var totalFreed = 0
    @AppStorage(UpdateChecker.automaticChecksKey) private var automaticUpdateChecks = true
    @StateObject private var fullDiskAccess = ViewState(Permissions.hasFullDiskAccess)
    @ObservedObject private var localization = AppLocalization.shared
    @EnvironmentObject var updates: UpdateChecker
    @Environment(\.openWindow) private var openWindow

    private var version: String { updates.current.raw }

    /// La fenêtre des nouveautés est rattachée à la fenêtre principale.
    private func showUpdateDetails() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
        updates.showDetails = true
    }

    private var updateStatus: (text: String, color: Color) {
        switch updates.state {
        case .idle:
            return (localized("Pas encore vérifié"), .secondary)
        case .notConfigured:
            return (localized("Dépôt GitHub non configuré (clé TMMReleasesRepository de Info.plist)"), Theme.amber)
        case .checking:
            return (localized("Vérification…"), .secondary)
        case .upToDate:
            let when = updates.lastCheck.map { localized(" · vérifié \($0.relativeDescription)") } ?? ""
            return (localized("TidyMyMac est à jour\(when)"), Theme.mint)
        case .available(let release):
            return (localized("La version \(release.version.raw) est disponible"), Theme.mint)
        case .failed(let message):
            return (message, Theme.coral)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                BrandMark(size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Réglages").font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text("TidyMyMac \(version) · logiciel libre sous licence MIT").font(.caption).foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 4)

            SettingsCard(icon: "globe", tint: Theme.sky, title: "Langue") {
                // La langue change tout de suite, sans relancer l'app.
                Picker("Langue de l'interface", selection: Binding(
                    get: { localization.language },
                    set: { localization.select($0) }
                )) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
            }

            SettingsCard(icon: "arrow.down.circle", tint: Theme.mint, title: "Mises à jour") {
                Toggle("Rechercher automatiquement les nouvelles versions", isOn: $automaticUpdateChecks)
                    .toggleStyle(.switch)
                HStack(spacing: 10) {
                    Text(updateStatus.text).font(.caption).foregroundColor(updateStatus.color)
                    Spacer()
                    if updates.availableRelease != nil {
                        Button("Voir") { showUpdateDetails() }
                            .buttonStyle(PrimaryButtonStyle(compact: true))
                    }
                    Button("Rechercher maintenant") {
                        Task {
                            await updates.check(userInitiated: true)
                            if updates.availableRelease != nil { showUpdateDetails() }
                        }
                    }
                    .disabled(updates.state == .checking)
                }
            }

            SettingsCard(icon: "trash", tint: Theme.aqua, title: "Suppression") {
                Toggle(isOn: $deletePermanently) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Supprimer définitivement les fichiers inutiles")
                        Text("Sinon ils passent par la Corbeille. Gros fichiers, doublons et apps y vont toujours.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }

            SettingsCard(icon: "lock.shield", tint: fullDiskAccess.value ? Theme.mint : Theme.amber, title: "Accès complet au disque") {
                HStack(spacing: 10) {
                    Text(fullDiskAccess.value ? localized("Accordé") : localized("Non accordé"))
                        .font(.caption.bold())
                        .foregroundColor(fullDiskAccess.value ? Theme.mint : Theme.amber)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill((fullDiskAccess.value ? Theme.mint : Theme.amber).opacity(0.15)))
                    Text("Nécessaire pour la Corbeille, Mail et les sauvegardes iOS.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                HStack {
                    Button("Ouvrir les Réglages Système") { Permissions.openFullDiskAccessSettings() }
                        .buttonStyle(PrimaryButtonStyle(tint: fullDiskAccess.value ? Theme.mint : Theme.amber, compact: true))
                    Button("Vérifier") { fullDiskAccess.value = Permissions.hasFullDiskAccess }
                    if !fullDiskAccess.value {
                        Button("Relancer TidyMyMac") { Permissions.relaunchApp() }
                    }
                }
                if !fullDiskAccess.value {
                    Text("Activez TidyMyMac dans la liste, puis relancez l'app : macOS n'applique l'accès qu'au lancement suivant.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SettingsCard(icon: "menubar.rectangle", tint: Theme.lavender, title: "Barre des menus") {
                Toggle(isOn: $showMenuBarExtra) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Afficher TidyMyMac dans la barre des menus")
                        Text("État du Mac, mémoire, réseau et raccourcis de nettoyage.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }

            SettingsCard(icon: "chart.line.uptrend.xyaxis", tint: Theme.mint, title: "Statistiques") {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Int64(totalFreed).formattedGain)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("libérés au total avec TidyMyMac").font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Remettre à zéro") { totalFreed = 0 }
                        .disabled(totalFreed == 0)
                }
            }
        }
        .padding(22)
        .frame(width: 540)
        .background(AppBackground(accent: Theme.mint).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .tint(Theme.mint)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            fullDiskAccess.value = Permissions.hasFullDiskAccess
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let icon: String
    let tint: Color
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            IconTile(symbol: icon, tint: tint, size: 36)
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.system(.headline, design: .rounded))
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.cardBorder))
    }
}
