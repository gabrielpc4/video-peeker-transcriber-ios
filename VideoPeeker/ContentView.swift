//
//  ContentView.swift
//  myprojectname
//
//  Created by Gabriel Carvalho on 12/02/26.
//

import SwiftUI
import SwiftData
import UIKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var consoleLogStore: ConsoleLogStore

    @Query(sort: \MediaItem.createdAt, order: .reverse)
    private var mediaItems: [MediaItem]

    @State private var selectedMediaItem: MediaItem?
    @State private var autoTranscribeImportedIdentifier: String?

    @State private var isImportInProgress = false
    @State private var importErrorMessage: String?

    @State private var isSettingsPresented = false

    @AppStorage(AppDefaults.backendBaseUrlKey) private var backendBaseUrlText = AppDefaults.defaultBackendBaseUrl

    @State private var backendStatus: BackendStatusState = .unknown

    var body: some View {
        NavigationStack {
            List {
                Section("Video a ser trabalhado") {
                    Button {
                        addClipboardUrlItem(shouldNavigateAndAutoTranscribe: true)
                    } label: {
                        Text("Usar link do clipboard")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                if isImportInProgress {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Importando do Share…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Itens") {
                    if mediaItems.isEmpty {
                        Text("Nada ainda. Compartilhe um áudio/link ou cole um link acima.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(mediaItems) { item in
                            Button {
                                autoTranscribeImportedIdentifier = nil
                                selectedMediaItem = item
                            } label: {
                                MediaItemRowView(mediaItem: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Backend") {
                    backendStatusView
                }

                Section("Logs") {
                    consoleLogsView
                }
            }
            .navigationTitle("Video Peek")
            .navigationDestination(item: $selectedMediaItem) { item in
                let shouldAutoTranscribe = autoTranscribeImportedIdentifier == item.importedItemIdentifier
                MediaItemDetailView(
                    mediaItem: item,
                    shouldStartTranscriptionOnAppear: shouldAutoTranscribe
                )
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings") {
                        isSettingsPresented = true
                    }
                }
            }
            .task {
                await importPendingItems()
            }
            .task(id: backendBaseUrlText) {
                await refreshBackendStatus()
            }
            .onChange(of: scenePhase) { newScenePhase in
                if newScenePhase == .active {
                    Task {
                        await importPendingItems()
                        await refreshBackendStatus()
                    }
                }
            }
            .refreshable {
                await importPendingItems()
                await refreshBackendStatus()
            }
            .alert("Erro", isPresented: isImportErrorPresented) {
                Button("OK") {
                    importErrorMessage = nil
                }
            } message: {
                Text(importErrorMessage ?? "")
            }
        }
        .sheet(isPresented: $isSettingsPresented) {
            NavigationStack {
                SettingsView()
            }
        }
    }

    private var isImportErrorPresented: Binding<Bool> {
        Binding(
            get: {
                importErrorMessage != nil
            },
            set: { isPresented in
                if isPresented == false {
                    importErrorMessage = nil
                }
            }
        )
    }

    @ViewBuilder
    private var backendStatusView: some View {
        let baseUrlText = backendBaseUrlText.trimmingCharacters(in: .whitespacesAndNewlines)

        VStack(alignment: .leading, spacing: 8) {
            Text(baseUrlText.isEmpty ? "Base URL não configurada." : baseUrlText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 10) {
                Group {
                    switch backendStatus {
                    case .unknown:
                        Text("Status: desconhecido")
                            .foregroundStyle(.secondary)
                    case .checking:
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Verificando…")
                                .foregroundStyle(.secondary)
                        }
                    case let .reachable(latencyMs):
                        Text("Status: ok (\(latencyMs) ms)")
                            .foregroundStyle(.green)
                    case let .unreachable(message):
                        Text("Status: indisponível")
                            .foregroundStyle(.red)
                            .accessibilityLabel("Status: indisponível. \(message)")
                    }
                }

                Spacer()

                Button("Testar") {
                    Task { await refreshBackendStatus() }
                }
                .buttonStyle(.bordered)
            }

            if case let .unreachable(message) = backendStatus {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
    }

    private var consoleLogsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(consoleLogStore.lines.count) linhas")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Limpar") {
                    consoleLogStore.clear()
                }
                .buttonStyle(.bordered)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(consoleLogStore.lines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .id(index)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 220, maxHeight: 420)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onChange(of: consoleLogStore.lines.count) { _, newValue in
                    guard newValue > 0 else { return }
                    proxy.scrollTo(newValue - 1, anchor: .bottom)
                }
            }
        }
    }

    private func importPendingItems() async {
        if isImportInProgress {
            return
        }

        isImportInProgress = true
        defer {
            isImportInProgress = false
        }

        do {
            let shareImportService = ShareImportService()
            let importedCount = try shareImportService.importPendingItems(modelContext: modelContext)
            _ = importedCount
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func refreshBackendStatus() async {
        let baseUrlText = backendBaseUrlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseUrl = URL(string: baseUrlText), baseUrlText.isEmpty == false else {
            backendStatus = .unreachable("Base URL inválida.")
            return
        }

        backendStatus = .checking

        let startedAt = Date()
        do {
            let client = BackendClient(baseUrl: baseUrl)
            _ = try await client.health()
            let latencyMs = Int(Date().timeIntervalSince(startedAt) * 1000.0)
            backendStatus = .reachable(latencyMs: max(0, latencyMs))
        } catch {
            backendStatus = .unreachable(error.localizedDescription)
        }
    }

    private func addClipboardUrlItem(shouldNavigateAndAutoTranscribe: Bool) {
        let trimmedUrlText = (UIPasteboard.general.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedUrlText.isEmpty {
            importErrorMessage = "Seu clipboard está vazio."
            return
        }

        if looksLikeUrl(text: trimmedUrlText) == false {
            importErrorMessage = "Não parece um link válido:\n\n\(trimmedUrlText)"
            return
        }

        let importedItemIdentifier = UUID().uuidString

        let newItem = MediaItem(
            importedItemIdentifier: importedItemIdentifier,
            createdAt: Date(),
            sourceType: .url,
            sourceUrl: trimmedUrlText,
            storedFilename: nil
        )

        modelContext.insert(newItem)

        do {
            try modelContext.save()

            if shouldNavigateAndAutoTranscribe {
                autoTranscribeImportedIdentifier = importedItemIdentifier
                selectedMediaItem = newItem
            }

            Task { @MainActor in
                await resolveTitleIfPossible(mediaItem: newItem)
            }
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }

    private func looksLikeUrl(text: String) -> Bool {
        if text.hasPrefix("http://") == false && text.hasPrefix("https://") == false {
            return false
        }

        guard let urlValue = URL(string: text) else {
            return false
        }

        let hostText = (urlValue.host ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if hostText.isEmpty {
            return false
        }

        return true
    }

    @MainActor
    private func resolveTitleIfPossible(mediaItem: MediaItem) async {
        if mediaItem.sourceType != .url {
            return
        }

        let sourceUrlText = (mediaItem.sourceUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if sourceUrlText.isEmpty {
            return
        }

        guard let remoteItemIdentifier = mediaItem.remoteItemIdentifier, remoteItemIdentifier.isEmpty == false else {
            // Do not create remote items just to resolve a title; creation happens on transcribe/summary.
            return
        }

        let baseUrlText = backendBaseUrlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseUrl = URL(string: baseUrlText) else {
            return
        }

        do {
            let client = BackendClient(baseUrl: baseUrl)

            let itemResponse = try await client.getItem(itemId: remoteItemIdentifier)
            if let titleText = itemResponse.title_text, titleText.isEmpty == false {
                mediaItem.titleText = titleText
                try modelContext.save()
            }
        } catch {
            // Keep host fallback if title lookup fails.
        }
    }
}

private enum BackendStatusState: Equatable {
    case unknown
    case checking
    case reachable(latencyMs: Int)
    case unreachable(String)
}

#Preview {
    ContentView()
        .modelContainer(for: [MediaItem.self], inMemory: true)
}
