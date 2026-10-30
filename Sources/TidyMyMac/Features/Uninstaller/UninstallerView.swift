import AppKit
import SwiftUI

struct UninstallerView: View {
    @EnvironmentObject var model: AppsModel
    @StateObject private var search = ViewState("")
    @StateObject private var confirmUninstall = ViewState(false)

    private var filteredApps: [InstalledApp] {
        let query = search.value
        return query.isEmpty ? model.sortedApps : model.sortedApps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        if model.apps.isEmpty && !model.loading {
            ModuleIntro(module: .uninstaller) { Task { await model.load() } }
        } else {
            VStack(spacing: 0) {
                ModuleHeader(module: .uninstaller)
                Divider()
                if model.loading {
                    ProgressPrompt(text: "Recherche des applications et calcul de leur taille…")
                } else {
                    HSplitView {
                        appList.frame(minWidth: 260, idealWidth: 300)
                        detail.frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
    }

    private var appList: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Rechercher", text: $search.value).textFieldStyle(.roundedBorder)
                Picker("", selection: $model.sortBySize) {
                    Text("Nom").tag(false)
                    Text("Taille").tag(true)
                }
                .labelsHidden()
                .frame(width: 90)
            }
            .padding(8)
            List(filteredApps, selection: $model.selection) { app in
                HStack {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                        .resizable()
                        .frame(width: 24, height: 24)
                    Text(app.name).lineLimit(1)
                    Spacer()
                    Text(app.size.formattedBytes).monospacedDigit().foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if let app = model.selectedApp {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                        .resizable()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.name).font(.title2.bold())
                        Text("\(app.bundleID) · version \(app.version)").font(.caption).foregroundColor(.secondary)
                        Text("Application : \(app.size.formattedBytes) · Données : \(model.leftovers.totalSize.formattedBytes)")
                            .monospacedDigit()
                    }
                }
                Text("Fichiers associés").font(.headline)
                if model.leftovers.isEmpty {
                    Text("Aucun fichier associé trouvé dans ~/Library.").foregroundColor(.secondary)
                    Spacer()
                } else {
                    List {
                        ForEach($model.leftovers) { $item in
                            FileRow(url: item.url, size: item.size, selected: $item.selected)
                        }
                    }
                }
                if let message = model.message {
                    HStack {
                        Text(message).font(.callout).foregroundColor(.secondary)
                        Spacer()
                        UndoActionButton(entryID: model.lastEntryID, title: "Annuler") { model.loadLeftovers() }
                    }
                }
                HStack {
                    Button("Réinitialiser l'application") {
                        Task { await model.reset(app) }
                    }
                    .help("Supprime les données sélectionnées mais conserve l'application")
                    .disabled(model.leftovers.selectedSize == 0)
                    Spacer()
                    Button("Désinstaller…", role: .destructive) { confirmUninstall.value = true }
                        .buttonStyle(PrimaryButtonStyle(tint: Theme.coral))
                }
            }
            .padding(16)
            .confirmationDialog("Désinstaller \(app.name) ?", isPresented: $confirmUninstall.value) {
                Button("Désinstaller", role: .destructive) {
                    Task { await model.uninstall(app) }
                }
            } message: {
                Text("L'application et les fichiers associés cochés seront placés dans la Corbeille.")
            }
        } else {
            VStack(spacing: 8) {
                if let message = model.message {
                    Text(message).foregroundColor(.secondary)
                    UndoActionButton(entryID: model.lastEntryID, title: "Annuler la désinstallation") {
                        Task { await model.load() }
                    }
                }
                Text("Sélectionnez une application").foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
