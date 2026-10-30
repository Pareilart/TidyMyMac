import AppKit
import SwiftUI

struct ModuleSection: Identifiable {
    let title: String
    let modules: [Module]
    var id: String { title }

    static var all: [ModuleSection] { [
        ModuleSection(title: localized("Analyse"), modules: [.smartScan]),
        ModuleSection(title: localized("Recherche"), modules: [.search]),
        ModuleSection(title: localized("Nettoyage"), modules: [.junk]),
        ModuleSection(title: localized("Encombrement"), modules: [.largeFiles, .duplicates, .spaceExplorer]),
        ModuleSection(title: localized("Applications"), modules: [.uninstaller]),
        ModuleSection(title: localized("Performances"), modules: [.performance]),
    ] }
}

struct Sidebar: View {
    @EnvironmentObject var navigation: AppNavigation
    @StateObject private var fullDiskAccess = ViewState(Permissions.hasFullDiskAccess)
    @AppStorage(Stats.totalFreedKey) private var totalFreed = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            // Les modules défilent si la fenêtre est trop basse ; l'en-tête et la carte d'accès restent visibles.
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(ModuleSection.all) { section in
                        Text(section.title.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 12)
                            .padding(.bottom, 2)
                        ForEach(section.modules) { module in
                            SidebarItem(module: module, selected: (navigation.selection ?? .smartScan) == module) {
                                // Revenir sur Performances ramène à la vue d'ensemble.
                                if module == .performance { navigation.performanceRoute = .overview }
                                navigation.selection = module
                            }
                        }
                    }
                }
                .padding(.bottom, 10)
            }
            UpdateCard().padding(.top, 8)
            if !fullDiskAccess.value && !ScreenshotStudio.isActive {
                fullDiskAccessHint.padding(.top, 8)
            }
            // Toujours visible en bas, même quand la liste des modules défile.
            SidebarSettingsButton().padding(.top, 8)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
        .frame(width: 256)
        .frame(maxHeight: .infinity)
        .background(Color.black.opacity(0.18))
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            fullDiskAccess.value = Permissions.hasFullDiskAccess
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            BrandMark(size: 32)
            VStack(alignment: .leading, spacing: 0) {
                Text("TidyMyMac").font(.system(size: 20, weight: .bold, design: .rounded))
                if totalFreed > 0 {
                    Text("\(Int64(totalFreed).formattedBytes) libérés au total")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.mint)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 40)
        .padding(.bottom, 8)
    }

    private var fullDiskAccessHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Accès complet au disque", systemImage: "lock.shield")
                .font(.system(.caption, design: .rounded).bold())
                .foregroundColor(Theme.amber)
            Text("Pour la Corbeille, Mail et les sauvegardes iOS. Activez TidyMyMac dans la liste, puis relancez l'app.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Button("Autoriser…") { Permissions.openFullDiskAccessSettings() }
                    .buttonStyle(PrimaryButtonStyle(tint: Theme.amber, compact: true))
                Button("Relancer") { Permissions.relaunchApp() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.amber.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.amber.opacity(0.25)))
    }
}

/// Ouvre la fenêtre des Réglages (même effet que ⌘,).
private struct SidebarSettingsButton: View {
    var body: some View {
        if #available(macOS 14.0, *) {
            SettingsLink { label }
                .buttonStyle(.plain)
        } else {
            Button {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                label
            }
            .buttonStyle(.plain)
        }
    }

    private var label: some View {
        HStack(spacing: 11) {
            IconTile(symbol: "gearshape.fill", tint: Color(white: 0.75), size: 28)
            Text("Réglages")
                .font(.system(size: 13.5, weight: .medium, design: .rounded))
                .foregroundColor(.primary.opacity(0.8))
            Spacer(minLength: 0)
            Text("⌘,")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(0.04)))
        .contentShape(Rectangle())
    }
}

private struct SidebarItem: View {
    let module: Module
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                IconTile(symbol: module.icon, tint: module.info.accent, size: 28)
                Text(module.title)
                    .font(.system(size: 13.5, weight: selected ? .semibold : .medium, design: .rounded))
                    .foregroundColor(selected ? .primary : .primary.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(selected ? Color.white.opacity(0.10) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(selected ? Color.white.opacity(0.12) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
