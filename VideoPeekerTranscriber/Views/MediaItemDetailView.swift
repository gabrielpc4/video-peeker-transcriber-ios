//
//  MediaItemDetailView.swift
//  VideoPeekerTranscriber
//
//  Created by Gabriel Pinheiro de Carvalho on 12/02/26.
//

import SwiftUI
import SwiftData

struct MediaItemDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var mediaItem: MediaItem

    let shouldStartTranscriptionOnAppear: Bool

    @State private var isActionInProgress = false
    @State private var currentActionTitle: String?
    @State private var actionErrorMessage: String?

    @State private var hasTriggeredAutoTranscription = false
    @State private var selectedTranscriptVersion = TranscriptVersion.enhanced
    @State private var isDeleteConfirmationPresented = false

    @AppStorage(AppDefaults.backendBaseUrlKey) private var backendBaseUrlText = AppDefaults.defaultBackendBaseUrl
    @AppStorage("useExtendedOutput") private var useExtendedOutput = false

    init(mediaItem: MediaItem, shouldStartTranscriptionOnAppear: Bool = false) {
        self.mediaItem = mediaItem
        self.shouldStartTranscriptionOnAppear = shouldStartTranscriptionOnAppear
    }

    var body: some View {
        List {
            Section {
                Button {
                    startTranscription()
                } label: {
                    if isActionInProgress, currentActionTitle == "Transcrever" {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Transcrevendo…")
                        }
                    } else {
                        Text("Transcrever")
                    }
                }
                .disabled(isActionInProgress)

                if mediaItem.sourceType == .url {
                    Button {
                        startSummary()
                    } label: {
                        if isActionInProgress, currentActionTitle == "Resumo" {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Gerando resumo…")
                            }
                        } else {
                            Text("Gerar resumo")
                        }
                    }
                    .disabled(isActionInProgress)
                }

                Button {
                    startBreakdown()
                } label: {
                    if isActionInProgress, currentActionTitle == "Breakdown" {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(secondStepInProgressText)
                        }
                    } else {
                        Text(secondStepButtonTitle)
                    }
                }
                .disabled(isActionInProgress)
            }

            if mediaItem.sourceType == .audioFile {
                Section("Recap") {
                    if recapBullets.isEmpty == false {
                        ForEach(recapBullets, id: \.self) { bulletText in
                            Text("• \(bulletText)")
                        }
                    } else {
                        Text("Ainda não gerado.")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Section("Resumo") {
                    if summaryBullets.isEmpty == false {
                        ForEach(summaryBullets, id: \.self) { bulletText in
                            Text("• \(bulletText)")
                        }
                    } else {
                        Text("Ainda não gerado.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Breakdown") {
                    if let breakdownViewModel = breakdownViewModel {
                        if breakdownViewModel.vibe.isEmpty == false {
                            BreakdownFieldView(titleText: "Vibe", valueText: breakdownViewModel.vibe)
                        }

                        if breakdownViewModel.whatHappened.isEmpty == false {
                            BreakdownFieldView(titleText: "Resumo", valueText: breakdownViewModel.whatHappened)
                        }

                        if breakdownViewModel.keyPoints.isEmpty == false {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Pontos principais")
                                    .font(.headline)

                                ForEach(breakdownViewModel.keyPoints, id: \.self) { keyPointText in
                                    Text("• \(keyPointText)")
                                }
                            }
                        }

                        if breakdownViewModel.howItWasSaid.isEmpty == false {
                            BreakdownFieldView(titleText: "Como foi dito", valueText: breakdownViewModel.howItWasSaid)
                        }

                        if breakdownViewModel.skippedAsFluff.isEmpty == false {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Pulado como enrolação")
                                    .font(.headline)

                                ForEach(breakdownViewModel.skippedAsFluff, id: \.self) { skippedText in
                                    Text("• \(skippedText)")
                                }
                            }
                        }
                    } else {
                        Text("Ainda não gerado.")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let lastErrorMessage = mediaItem.lastErrorMessage, lastErrorMessage.isEmpty == false {
                Section("Erro") {
                    Text(lastErrorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section("Transcript") {
                if mediaItem.sourceType == .url {
                    Picker("Versão", selection: $selectedTranscriptVersion) {
                        Text("Aprimorado").tag(TranscriptVersion.enhanced)
                        Text("Original").tag(TranscriptVersion.original)
                    }
                    .pickerStyle(.segmented)
                }

                if transcriptDisplayText.isEmpty == false {
                    Text(transcriptDisplayText)
                        .textSelection(.enabled)
                } else {
                    Text(transcriptPlaceholderText)
                        .foregroundStyle(.secondary)
                }

                if mediaItem.sourceType == .url, selectedTranscriptVersion == .enhanced {
                    if mediaItem.enhancedTranscriptStatus == .running {
                        Text("Aprimorando speakers…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if let errorText = mediaItem.enhancedTranscriptErrorMessage, errorText.isEmpty == false {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }

              Toggle("Vídeos longos (mais tokens)", isOn: $useExtendedOutput)
                    .help("Ativa limites maiores de saída para transcrição aprimorada, resumo e breakdown. Use para vídeos de ~1h.")
        }
        .navigationTitle(navigationTitleText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    isDeleteConfirmationPresented = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(isActionInProgress)
            }
        }
        .alert("Erro", isPresented: isActionErrorPresented) {
            Button("OK") {
                actionErrorMessage = nil
            }
        } message: {
            Text(actionErrorMessage ?? "")
        }
        .alert("Deletar item?", isPresented: $isDeleteConfirmationPresented) {
            Button("Cancelar", role: .cancel) {}
            Button("Deletar", role: .destructive) {
                deleteItem()
            }
        } message: {
            Text("Isso vai remover este item do app e também apagar os dados no servidor.")
        }
        .task(id: shouldStartTranscriptionOnAppear) {
            await autoStartTranscriptionIfNeeded()
        }
    }

    private var navigationTitleText: String {
        if mediaItem.sourceType == .audioFile {
            return "Áudio"
        }

        if mediaItem.sourceType == .url {
            let titleText = (mediaItem.titleText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if titleText.isEmpty == false {
                return titleText
            }

            return "Link"
        }

        return "Item"
    }

    private var secondStepButtonTitle: String {
        if mediaItem.sourceType == .audioFile {
            return "Gerar recap"
        }

        return "Gerar breakdown"
    }

    private var secondStepInProgressText: String {
        if mediaItem.sourceType == .audioFile {
            return "Gerando recap…"
        }

        return "Gerando breakdown…"
    }

    private var recapBullets: [String] {
        let rawJsonText = (mediaItem.breakdownJson ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if rawJsonText.isEmpty {
            return []
        }

        guard let rawJsonData = rawJsonText.data(using: .utf8) else {
            return []
        }

        guard
            let rawObject = try? JSONSerialization.jsonObject(with: rawJsonData, options: []),
            let rawDictionary = rawObject as? [String: Any]
        else {
            return []
        }

        guard let rawBullets = rawDictionary["recapBullets"] as? [Any] else {
            return []
        }

        let bulletTexts = rawBullets.compactMap { item -> String? in
            guard let textItem = item as? String else {
                return nil
            }

            let trimmedText = textItem.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedText.isEmpty {
                return nil
            }

            return trimmedText
        }

        return bulletTexts
    }

    private var summaryBullets: [String] {
        let rawJsonText = (mediaItem.summaryJson ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if rawJsonText.isEmpty {
            return []
        }

        guard let rawJsonData = rawJsonText.data(using: .utf8) else {
            return []
        }

        guard
            let rawObject = try? JSONSerialization.jsonObject(with: rawJsonData, options: []),
            let rawDictionary = rawObject as? [String: Any]
        else {
            return []
        }

        guard let rawBullets = rawDictionary["summaryBullets"] as? [Any] else {
            return []
        }

        let bulletTexts = rawBullets.compactMap { item -> String? in
            guard let textItem = item as? String else {
                return nil
            }

            let trimmedText = textItem.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedText.isEmpty {
                return nil
            }

            return trimmedText
        }

        return bulletTexts
    }

    private var breakdownViewModel: BreakdownViewModel? {
        let rawJsonText = (mediaItem.breakdownJson ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if rawJsonText.isEmpty {
            return nil
        }

        guard let rawJsonData = rawJsonText.data(using: .utf8) else {
            return nil
        }

        guard
            let rawObject = try? JSONSerialization.jsonObject(with: rawJsonData, options: []),
            let rawDictionary = rawObject as? [String: Any]
        else {
            return nil
        }

        let vibeText = (rawDictionary["vibe"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let whatHappenedText = (rawDictionary["whatHappened"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let howItWasSaidText = (rawDictionary["howItWasSaid"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        let keyPoints = (rawDictionary["keyPoints"] as? [Any] ?? []).compactMap { item -> String? in
            guard let textItem = item as? String else {
                return nil
            }

            let trimmedText = textItem.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedText.isEmpty {
                return nil
            }

            return trimmedText
        }

        let skippedAsFluff = (rawDictionary["skippedAsFluff"] as? [Any] ?? []).compactMap { item -> String? in
            guard let textItem = item as? String else {
                return nil
            }

            let trimmedText = textItem.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedText.isEmpty {
                return nil
            }

            return trimmedText
        }

        if vibeText.isEmpty, whatHappenedText.isEmpty, howItWasSaidText.isEmpty, keyPoints.isEmpty, skippedAsFluff.isEmpty {
            return nil
        }

        return BreakdownViewModel(
            vibe: vibeText,
            whatHappened: whatHappenedText,
            keyPoints: keyPoints,
            howItWasSaid: howItWasSaidText,
            skippedAsFluff: skippedAsFluff
        )
    }

    private var isActionErrorPresented: Binding<Bool> {
        Binding(
            get: {
                actionErrorMessage != nil
            },
            set: { isPresented in
                if isPresented == false {
                    actionErrorMessage = nil
                }
            }
        )
    }

    private var transcriptDisplayText: String {
        if mediaItem.sourceType == .url, selectedTranscriptVersion == .enhanced {
            return (mediaItem.enhancedTranscriptText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return (mediaItem.transcriptText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var transcriptPlaceholderText: String {
        if mediaItem.sourceType == .url, selectedTranscriptVersion == .enhanced {
            if mediaItem.transcriptionStatus != .completed {
                return "Ainda não transcrito."
            }

            return "Ainda não aprimorado."
        }

        return "Ainda não transcrito."
    }

    private func startTranscription() {
        if isActionInProgress {
            return
        }

        isActionInProgress = true
        currentActionTitle = "Transcrever"
        actionErrorMessage = nil

        Task { @MainActor in
            defer {
                isActionInProgress = false
                currentActionTitle = nil
            }

            do {
                try await transcribe()
            } catch {
                actionErrorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func autoStartTranscriptionIfNeeded() async {
        if shouldStartTranscriptionOnAppear == false {
            return
        }

        if hasTriggeredAutoTranscription {
            return
        }

        if mediaItem.transcriptionStatus == .running || mediaItem.transcriptionStatus == .completed {
            return
        }

        hasTriggeredAutoTranscription = true
        startTranscription()
    }

    private func startBreakdown() {
        if isActionInProgress {
            return
        }

        isActionInProgress = true
        currentActionTitle = "Breakdown"
        actionErrorMessage = nil

        Task { @MainActor in
            defer {
                isActionInProgress = false
                currentActionTitle = nil
            }

            do {
                try await breakdown()
            } catch {
                actionErrorMessage = error.localizedDescription
            }
        }
    }

    private func startSummary() {
        if isActionInProgress {
            return
        }

        isActionInProgress = true
        currentActionTitle = "Resumo"
        actionErrorMessage = nil

        Task { @MainActor in
            defer {
                isActionInProgress = false
                currentActionTitle = nil
            }

            do {
                try await summary()
            } catch {
                actionErrorMessage = error.localizedDescription
            }
        }
    }

    private func deleteItem() {
        if isActionInProgress {
            return
        }

        isActionInProgress = true
        currentActionTitle = "Delete"
        actionErrorMessage = nil

        Task { @MainActor in
            defer {
                isActionInProgress = false
                currentActionTitle = nil
            }

            do {
                try await deleteItemOnServerIfPossible()
                deleteLocalMediaFileIfPossible()
                modelContext.delete(mediaItem)
                try modelContext.save()
                dismiss()
            } catch {
                actionErrorMessage = error.localizedDescription
            }
        }
    }

    private func deleteLocalMediaFileIfPossible() {
        if mediaItem.sourceType != .audioFile {
            return
        }

        do {
            let fileUrl = try resolveLocalAudioFileUrl()
            try? FileManager.default.removeItem(at: fileUrl)
        } catch {
            // Best-effort local cleanup only.
        }
    }

    private func deleteItemOnServerIfPossible() async throws {
        guard let remoteId = mediaItem.remoteItemIdentifier, remoteId.isEmpty == false else {
            return
        }

        let client = BackendClient(baseUrl: try backendBaseUrl())
        try await client.deleteItem(itemId: remoteId)
    }

    private func backendBaseUrl() throws -> URL {
        let rawText = backendBaseUrlText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let url = URL(string: rawText) else {
            throw MediaItemActionError.invalidBackendUrl
        }

        return url
    }

    private func ensureRemoteItemExists(client: BackendClient) async throws -> String {
        if let remoteItemIdentifier = mediaItem.remoteItemIdentifier, remoteItemIdentifier.isEmpty == false {
            return remoteItemIdentifier
        }

        let remoteItemIdentifier: String

        if mediaItem.sourceType == .url {
            let sourceUrlText = (mediaItem.sourceUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if sourceUrlText.isEmpty {
                throw MediaItemActionError.missingSourceUrl
            }

            remoteItemIdentifier = try await client.createUrlItem(sourceUrl: sourceUrlText)
        } else if mediaItem.sourceType == .audioFile {
            let localFileUrl = try resolveLocalAudioFileUrl()
            remoteItemIdentifier = try await client.uploadAudioItem(fileUrl: localFileUrl)
        } else {
            throw MediaItemActionError.unsupportedSourceType
        }

        mediaItem.remoteItemIdentifier = remoteItemIdentifier
        try modelContext.save()

        return remoteItemIdentifier
    }

    @MainActor
    private func syncTitleFromBackendIfNeeded(client: BackendClient, itemId: String) async {
        if mediaItem.sourceType != .url {
            return
        }

        let existingTitleText = (mediaItem.titleText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if existingTitleText.isEmpty == false {
            return
        }

        do {
            let itemResponse = try await client.getItem(itemId: itemId)
            let backendTitleText = (itemResponse.title_text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if backendTitleText.isEmpty {
                return
            }

            mediaItem.titleText = backendTitleText
            try modelContext.save()
        } catch {
            // We don't block transcription for a title-only fetch.
        }
    }

    private func summary() async throws {
        let transcriptText = (mediaItem.transcriptText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if transcriptText.isEmpty {
            throw MediaItemActionError.missingTranscriptForSummary
        }

        let client = BackendClient(baseUrl: try backendBaseUrl())
        let itemId = try await ensureRemoteItemExists(client: client)

        let startResponse = try await client.startSummary(itemId: itemId, extendedOutput: useExtendedOutput)

        mediaItem.summaryStatus = .running
        mediaItem.lastErrorMessage = nil
        try modelContext.save()

        let finalResponse = try await pollUntilFinished(itemId: itemId, client: client, kind: "summary")

        mediaItem.summaryStatusRaw = finalResponse.summary_status
        mediaItem.summaryJson = finalResponse.summary_json
        mediaItem.lastErrorMessage = finalResponse.last_error
        try modelContext.save()
    }

    private func resolveLocalAudioFileUrl() throws -> URL {
        guard let storedFilename = mediaItem.storedFilename, storedFilename.isEmpty == false else {
            throw MediaItemActionError.missingStoredFilename
        }

        guard let containerUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroupConstants.appGroupIdentifier) else {
            throw ShareImportError.missingAppGroupContainer
        }

        let mediaFolderUrl = containerUrl.appendingPathComponent(AppGroupConstants.mediaFolderName, isDirectory: true)
        let fileUrl = mediaFolderUrl.appendingPathComponent(storedFilename, isDirectory: false)

        if FileManager.default.fileExists(atPath: fileUrl.path) == false {
            throw MediaItemActionError.missingLocalMediaFile(filename: storedFilename)
        }

        return fileUrl
    }

    private func transcribe() async throws {
        let startedAt = Date()
        func log(_ message: String) {
            let ms = Int(Date().timeIntervalSince(startedAt) * 1000)
            let remoteId = (mediaItem.remoteItemIdentifier ?? mediaItem.importedItemIdentifier)
            print("[VideoPeekerTranscriber][\(remoteId)] +\(ms)ms \(message)")
        }

        let client = BackendClient(baseUrl: try backendBaseUrl())
        log("transcribe: ensureRemoteItemExists start")
        let itemId = try await ensureRemoteItemExists(client: client)
        log("transcribe: ensureRemoteItemExists done itemId=\(itemId)")

        await syncTitleFromBackendIfNeeded(client: client, itemId: itemId)

        mediaItem.transcriptionStatus = .running
        mediaItem.enhancedTranscriptStatus = .pending
        mediaItem.enhancedTranscriptText = nil
        mediaItem.enhancedTranscriptErrorMessage = nil
        mediaItem.lastErrorMessage = nil
        try modelContext.save()

        log("transcribe: startTranscription request")
        _ = try await client.startTranscription(itemId: itemId, extendedOutput: useExtendedOutput)
        log("transcribe: polling transcription")
        let finalResponse = try await pollUntilFinished(itemId: itemId, client: client, kind: "transcription", log: log)

        mediaItem.transcriptionStatusRaw = finalResponse.transcription_status
        mediaItem.detectedLanguage = finalResponse.detected_language
        mediaItem.transcriptText = finalResponse.transcript_text
        mediaItem.lastErrorMessage = finalResponse.last_error
        try modelContext.save()

        log("transcribe: done transcription=\(finalResponse.transcription_status)")

        if mediaItem.sourceType == .url {
            // Do not block the "Transcrevendo..." UI on speaker enhancement.
            // We keep polling in the background and update the UI when ready.
            Task { @MainActor in
                do {
                    log("transcribe: background polling enhanced_transcript")
                    let enhancedResponse = try await pollUntilFinished(itemId: itemId, client: client, kind: "enhanced_transcript", log: log)
                    mediaItem.enhancedTranscriptStatusRaw = enhancedResponse.enhanced_transcript_status
                    mediaItem.enhancedTranscriptText = enhancedResponse.enhanced_transcript_text
                    mediaItem.enhancedTranscriptErrorMessage = enhancedResponse.enhanced_transcript_error
                    mediaItem.lastErrorMessage = enhancedResponse.last_error ?? mediaItem.lastErrorMessage
                    try modelContext.save()
                    log("transcribe: enhanced_transcript finished status=\(enhancedResponse.enhanced_transcript_status)")
                } catch {
                    // Best-effort only; UI already shows enhanced error when available.
                    log("transcribe: enhanced_transcript polling failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func breakdown() async throws {
        let transcriptText = (mediaItem.transcriptText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if transcriptText.isEmpty {
            throw MediaItemActionError.missingTranscriptForBreakdown
        }

        let client = BackendClient(baseUrl: try backendBaseUrl())
        let itemId = try await ensureRemoteItemExists(client: client)

        mediaItem.breakdownStatus = .running
        mediaItem.lastErrorMessage = nil
        try modelContext.save()

        _ = try await client.startBreakdown(itemId: itemId, extendedOutput: useExtendedOutput)
        let finalResponse = try await pollUntilFinished(itemId: itemId, client: client, kind: "breakdown")

        mediaItem.breakdownStatusRaw = finalResponse.breakdown_status
        mediaItem.breakdownJson = finalResponse.breakdown_json
        mediaItem.lastErrorMessage = finalResponse.last_error
        try modelContext.save()
    }

    private func pollUntilFinished(
        itemId: String,
        client: BackendClient,
        kind: String,
        log: ((String) -> Void)? = nil
    ) async throws -> BackendClient.ItemResponse {
        var remainingAttempts = 120
        let startedAt = Date()

        while remainingAttempts > 0 {
            let response = try await client.getItem(itemId: itemId)
            if remainingAttempts % 10 == 0 {
                let ms = Int(Date().timeIntervalSince(startedAt) * 1000)
                log?("poll[\(kind)] +\(ms)ms status t=\(response.transcription_status) e=\(response.enhanced_transcript_status) s=\(response.summary_status) b=\(response.breakdown_status)")
            }

            if kind == "transcription" {
                if response.transcription_status == JobStatus.completed.rawValue {
                    let ms = Int(Date().timeIntervalSince(startedAt) * 1000)
                    log?("poll[\(kind)] completed +\(ms)ms")
                    return response
                }

                if response.transcription_status == JobStatus.failed.rawValue {
                    let ms = Int(Date().timeIntervalSince(startedAt) * 1000)
                    log?("poll[\(kind)] failed +\(ms)ms")
                    return response
                }
            } else if kind == "enhanced_transcript" {
                if response.source_type != MediaSourceType.url.rawValue {
                    let ms = Int(Date().timeIntervalSince(startedAt) * 1000)
                    log?("poll[\(kind)] skipped (not url) +\(ms)ms")
                    return response
                }

                if response.transcription_status != JobStatus.completed.rawValue {
                    // Wait until transcription is done, then enhancement can start.
                } else {
                    if response.enhanced_transcript_status == JobStatus.completed.rawValue {
                        let ms = Int(Date().timeIntervalSince(startedAt) * 1000)
                        log?("poll[\(kind)] completed +\(ms)ms")
                        return response
                    }

                    if response.enhanced_transcript_status == JobStatus.failed.rawValue {
                        let ms = Int(Date().timeIntervalSince(startedAt) * 1000)
                        log?("poll[\(kind)] failed +\(ms)ms")
                        return response
                    }
                }
            } else if kind == "summary" {
                if response.summary_status == JobStatus.completed.rawValue {
                    return response
                }

                if response.summary_status == JobStatus.failed.rawValue {
                    return response
                }
            } else {
                if response.breakdown_status == JobStatus.completed.rawValue {
                    return response
                }

                if response.breakdown_status == JobStatus.failed.rawValue {
                    return response
                }
            }

            try await Task.sleep(nanoseconds: 1_000_000_000)
            remainingAttempts -= 1
        }

        throw MediaItemActionError.pollingTimedOut
    }
}

private enum TranscriptVersion: String, CaseIterable {
    case enhanced
    case original
}

private struct BreakdownViewModel {
    let vibe: String
    let whatHappened: String
    let keyPoints: [String]
    let howItWasSaid: String
    let skippedAsFluff: [String]
}

private struct BreakdownFieldView: View {
    let titleText: String
    let valueText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titleText)
                .font(.headline)

            Text(valueText)
                .textSelection(.enabled)
        }
    }
}

enum MediaItemActionError: LocalizedError {
    case invalidBackendUrl
    case missingSourceUrl
    case missingStoredFilename
    case missingLocalMediaFile(filename: String)
    case missingTranscriptForSummary
    case missingTranscriptForBreakdown
    case unsupportedSourceType
    case pollingTimedOut

    var errorDescription: String? {
        switch self {
        case .invalidBackendUrl:
            return "URL do backend inválida."
        case .missingSourceUrl:
            return "Esse item não tem link salvo."
        case .missingStoredFilename:
            return "Esse item não tem arquivo local salvo."
        case let .missingLocalMediaFile(filename):
            return "Não achei o arquivo local: \(filename)"
        case .missingTranscriptForSummary:
            return "Antes de gerar resumo, você precisa transcrever."
        case .missingTranscriptForBreakdown:
            return "Antes de gerar breakdown, você precisa transcrever."
        case .unsupportedSourceType:
            return "Tipo de item não suportado."
        case .pollingTimedOut:
            return "Demorou demais para finalizar. Tente de novo."
        }
    }
}

#Preview {
    NavigationStack {
        MediaItemDetailView(
            mediaItem: MediaItem(
                importedItemIdentifier: UUID().uuidString,
                createdAt: Date(),
                sourceType: .url,
                sourceUrl: "https://example.com",
                storedFilename: nil
            )
        )
    }
    .modelContainer(for: [MediaItem.self], inMemory: true)
}

