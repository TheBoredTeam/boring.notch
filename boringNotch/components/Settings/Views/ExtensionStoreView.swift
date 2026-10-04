// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

import SwiftUI

/// Network requests begin when this pane appears. Installation continues through
/// the app-owned manager if the user navigates away during a download.
@MainActor
struct ExtensionStoreView: View {
    @ObservedObject private var store = ExtensionStore.shared
    @ObservedObject private var extensions = ExtensionManager.shared
    @State private var search = ""
    @State private var selectedItem: ExtensionCatalogItem?
    @State private var installingID: String?
    let onManageInstalled: () -> Void

    private var installed: [String: ExtensionStoreInstalledInfo] {
        Dictionary(uniqueKeysWithValues: extensions.installed.map {
            ($0.id, ExtensionStoreInstalledInfo(version: $0.version, isEnabled: extensions.enabledIDs.contains($0.id)))
        })
    }

    var body: some View {
        ExtensionStoreContent(
            items: store.items,
            isLoading: store.isLoading,
            errorMessage: store.errorMessage,
            installed: installed,
            activeDownloadID: store.activeDownloadID,
            downloadProgress: store.downloadProgress,
            isInstalling: extensions.isInstalling,
            installingID: installingID,
            statusMessage: extensions.message,
            needsRestart: extensions.needsRestart,
            search: $search,
            onRefresh: { Task { await store.refresh(force: true) } },
            onInstall: install,
            onDetails: { selectedItem = $0 },
            onManageInstalled: onManageInstalled,
            onRestart: { ApplicationRelauncher.restart() }
        )
        .task { await store.refresh() }
        .sheet(item: $selectedItem) { item in
            ExtensionStoreDetailView(
                item: item,
                installed: installed[item.id],
                isBusy: store.activeDownloadID != nil || extensions.isInstalling,
                onInstall: { install(item) },
                onManageInstalled: {
                    selectedItem = nil
                    onManageInstalled()
                }
            )
        }
        .onChange(of: store.items) { _, items in
            if let selection = selectedItem {
                selectedItem = items.first { $0.id == selection.id }
            }
        }
    }

    private func install(_ item: ExtensionCatalogItem) {
        guard item.installableArtifact != nil,
              store.activeDownloadID == nil, !extensions.isInstalling else { return }
        selectedItem = nil
        extensions.message = nil
        Task {
            do {
                let downloaded = try await store.download(item)
                installingID = item.id
                extensions.install(from: downloaded.url, expected: downloaded.expected) {
                    downloaded.cleanup()
                    installingID = nil
                }
            } catch is CancellationError {
                // A cancelled request has no package to install.
            } catch {
                extensions.message = error.localizedDescription
            }
        }
    }
}

struct ExtensionStoreInstalledInfo: Equatable {
    let version: String
    let isEnabled: Bool
}

/// Value-driven presentation keeps catalog previews and UI verification free of
/// networking, installation, or developer code execution.
struct ExtensionStoreContent: View {
    let items: [ExtensionCatalogItem]
    let isLoading: Bool
    let errorMessage: String?
    let installed: [String: ExtensionStoreInstalledInfo]
    let activeDownloadID: String?
    let downloadProgress: Double?
    let isInstalling: Bool
    let installingID: String?
    let statusMessage: String?
    let needsRestart: Bool
    @Binding var search: String
    let onRefresh: () -> Void
    let onInstall: (ExtensionCatalogItem) -> Void
    let onDetails: (ExtensionCatalogItem) -> Void
    let onManageInstalled: () -> Void
    let onRestart: () -> Void

    private var matches: [ExtensionCatalogItem] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        return items.filter { item in
            ([item.name, item.developer.name] + item.categories)
                .contains { $0.localizedStandardContains(query) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Search name, developer, or category", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search extensions")
                Button("Refresh store", systemImage: "arrow.clockwise", action: onRefresh)
                    .labelStyle(.iconOnly)
                    .disabled(isLoading)
                    .help("Refresh store")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)

            Form {
                Section {
                    Text("Add more to your notch")
                        .font(.headline)
                    Text("Browse extensions from independent developers. Purchases and licenses are managed by each developer.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if isLoading && items.isEmpty {
                    Section {
                        ProgressView("Loading extensions…")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    }
                } else if let errorMessage, items.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("Couldn’t load the store", systemImage: "wifi.exclamationmark")
                        } description: {
                            Text(errorMessage)
                        } actions: {
                            Button("Try again", action: onRefresh)
                        }
                    }
                } else {
                    if let errorMessage {
                        Section {
                            Label("The store couldn’t refresh", systemImage: "exclamationmark.triangle")
                            Text(errorMessage).foregroundStyle(.secondary)
                        }
                    }
                    if isLoading {
                        Section {
                            ProgressView("Refreshing extensions…").controlSize(.small)
                        }
                    }
                    if matches.isEmpty {
                        Section {
                            ContentUnavailableView {
                                Label(search.isEmpty ? "No extensions yet" : "No matching extensions", systemImage: "puzzlepiece.extension")
                            } description: {
                                Text(search.isEmpty ? "Check back for new extensions." : "Try a different name, developer, or category.")
                            }
                        }
                    }
                    ForEach(matches) { item in
                        Section {
                            catalogRow(item)
                        }
                    }
                }

                if let statusMessage {
                    Section {
                        Text(statusMessage).font(.callout)
                        if needsRestart {
                            Button("Restart Boring Notch", action: onRestart)
                        }
                    }
                }
            }
        }
    }

    private func catalogRow(_ item: ExtensionCatalogItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ExtensionStoreIcon()
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name).font(.headline)
                    Text(item.developer.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if activeDownloadID == item.id {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel("Downloading extension")
                } else if isInstalling && installingID == item.id {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel("Installing extension")
                } else if installed[item.id] != nil {
                    Button("Manage", action: onManageInstalled).controlSize(.small)
                } else if item.installableArtifact != nil {
                    Button("Install") { onInstall(item) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(activeDownloadID != nil || isInstalling)
                }
            }

            Text(item.tagline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if activeDownloadID == item.id {
                if let downloadProgress {
                    ProgressView("Downloading…", value: downloadProgress)
                } else {
                    Text("Downloading…").font(.caption).foregroundStyle(.secondary)
                }
            } else if isInstalling && installingID == item.id {
                Text("Installing…").font(.caption).foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let state = installed[item.id] {
                    Label(state.isEnabled ? "Enabled" : "Installed", systemImage: "checkmark.circle")
                        .font(.caption)
                } else {
                    Text(item.storeStatusLabel).font(.caption.weight(.medium))
                }
                Text("·").foregroundStyle(.tertiary)
                Text(item.storePriceLabel).font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Details") { onDetails(item) }.controlSize(.small)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }
}

struct ExtensionStoreDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let item: ExtensionCatalogItem
    let installed: ExtensionStoreInstalledInfo?
    let isBusy: Bool
    let onInstall: () -> Void
    let onManageInstalled: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    HStack(spacing: 12) {
                        ExtensionStoreIcon()
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name).font(.title2.weight(.semibold))
                            Text(item.tagline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    Text(item.description)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section {
                    LabeledContent("Developer") {
                        Link(item.developer.name, destination: item.developer.url)
                    }
                    LabeledContent("Version", value: item.version)
                    LabeledContent("Status", value: item.storeStatusLabel)
                    LabeledContent("Price", value: item.storePriceLabel)
                    if !item.categories.isEmpty {
                        LabeledContent("Categories", value: item.categories.joined(separator: ", "))
                    }
                    if let installed {
                        LabeledContent("Installed version", value: installed.version)
                        LabeledContent("In Boring Notch", value: installed.isEnabled ? "Enabled" : "Disabled")
                    }
                } footer: {
                    Text("The developer manages purchases, licenses, and access within their extension.")
                }

                if let note = item.statusNote {
                    Section {
                        Text(note).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !item.requirements.isEmpty {
                    Section("Requirements") {
                        ForEach(Array(item.requirements.enumerated()), id: \.offset) { _, requirement in
                            Text(requirement).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Section {
                    if let website = item.websiteURL { Link("View on website", destination: website) }
                    if let support = item.supportURL { Link("Developer support", destination: support) }
                    if let source = item.sourceURL { Link("Source code", destination: source) }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if installed != nil {
                    Button("Manage", action: onManageInstalled)
                }
                if let artifact = item.installableArtifact, artifact.version != installed?.version {
                    Button(installed == nil ? "Install extension" : "Install this version", action: onInstall)
                        .buttonStyle(.borderedProminent)
                        .disabled(isBusy)
                } else if installed == nil {
                    Text(item.storeStatusLabel).foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .frame(width: 480, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct ExtensionStoreIcon: View {
    var body: some View {
        Image(systemName: "puzzlepiece.extension.fill")
            .font(.system(size: 22))
            .foregroundStyle(.secondary)
            .frame(width: 44, height: 44)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityHidden(true)
    }
}

private extension ExtensionCatalogItem {
    var storeStatusLabel: String {
        switch status {
        case .comingSoon: String(localized: "Coming soon")
        case .preview: String(localized: "Preview")
        case .available:
            installableArtifact == nil ? String(localized: "Download unavailable") : String(localized: "Available")
        }
    }

    var storePriceLabel: String {
        guard price.amount > 0 else { return String(localized: "Free") }
        let amount = price.amount.formatted(.currency(code: price.currency))
        switch price.billing {
        case "monthly": return String(localized: "\(amount) / month")
        case "yearly": return String(localized: "\(amount) / year")
        default: return String(localized: "\(amount) one-time")
        }
    }
}
