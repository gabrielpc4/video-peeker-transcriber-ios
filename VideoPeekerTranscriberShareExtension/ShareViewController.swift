//
//  ShareViewController.swift
//  VideoPeekerTranscriberTranscriberShareExtension
//
//  Created by Gabriel Pinheiro de Carvalho on 12/02/26.
//

import UniformTypeIdentifiers
import UIKit

final class ShareViewController: UIViewController {
    private enum AppGroupConstants {
        static let appGroupIdentifier = "group.com.gabrielpc4.VideoPeekerTranscriber"

        static let mediaFolderName = "ImportedMedia"
        static let metadataFolderName = "ImportedMetadata"
    }

    private struct ImportedItemMetadata: Codable {
        let importedItemIdentifier: String
        let createdAtIso8601: String

        let kind: String

        let originalFilename: String?
        let storedFilename: String?

        let sharedUrl: String?
    }

    private let statusLabel = UILabel()
    private let progressIndicator = UIActivityIndicatorView(style: .medium)
    private let closeButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        setupLayout()

        statusLabel.text = "Importando…"
        progressIndicator.startAnimating()
        closeButton.isHidden = true

        Task {
            await importFirstAttachment()
        }
    }

    private func setupLayout() {
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.font = .preferredFont(forTextStyle: .body)

        progressIndicator.translatesAutoresizingMaskIntoConstraints = false

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setTitle("Fechar", for: .normal)
        closeButton.addTarget(self, action: #selector(didTapCloseButton), for: .touchUpInside)

        view.addSubview(statusLabel)
        view.addSubview(progressIndicator)
        view.addSubview(closeButton)

        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -12),

            progressIndicator.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 16),
            progressIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            closeButton.topAnchor.constraint(equalTo: progressIndicator.bottomAnchor, constant: 20),
            closeButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
    }

    @objc
    private func didTapCloseButton() {
        extensionContext?.cancelRequest(withError: ShareError.userCancelled)
    }

    private func importFirstAttachment() async {
        do {
            guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem else {
                throw ShareError.missingInputItem
            }

            guard let itemProvider = extensionItem.attachments?.first else {
                throw ShareError.missingAttachment
            }

            let importedItemIdentifier = UUID().uuidString

            if itemProvider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                let sharedUrl = try await loadSharedUrl(itemProvider: itemProvider)
                if sharedUrl.isFileURL {
                    try await storeAudioMetadata(importedItemIdentifier: importedItemIdentifier, importedFileUrl: sharedUrl)
                } else {
                    try await storeUrlMetadata(importedItemIdentifier: importedItemIdentifier, sharedUrl: sharedUrl.absoluteString)
                }
            } else if itemProvider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                let sharedText = try await loadSharedText(itemProvider: itemProvider)
                let trimmed = sharedText.trimmingCharacters(in: .whitespacesAndNewlines)
                if let urlValue = URL(string: trimmed), urlValue.isFileURL {
                    try await storeAudioMetadata(importedItemIdentifier: importedItemIdentifier, importedFileUrl: urlValue)
                } else {
                    try await storeUrlMetadata(importedItemIdentifier: importedItemIdentifier, sharedUrl: sharedText)
                }
            } else {
                let importedFileUrl = try await loadIncomingFileUrl(itemProvider: itemProvider)
                try await storeAudioMetadata(importedItemIdentifier: importedItemIdentifier, importedFileUrl: importedFileUrl)
            }

            await MainActor.run {
                progressIndicator.stopAnimating()
                statusLabel.text = "Importado. Agora abra o VideoPeekerTranscriber."
            }

            extensionContext?.completeRequest(returningItems: nil)
        } catch {
            await MainActor.run {
                progressIndicator.stopAnimating()
                statusLabel.text = "Não consegui importar.\n\nErro: \(error.localizedDescription)"
                closeButton.isHidden = false
            }
        }
    }

    private func loadSharedUrl(itemProvider: NSItemProvider) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            itemProvider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if let urlItem = item as? URL {
                    continuation.resume(returning: urlItem)
                    return
                }

                continuation.resume(throwing: ShareError.unsupportedAttachment)
            }
        }
    }

    private func loadSharedText(itemProvider: NSItemProvider) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            itemProvider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if let textItem = item as? String {
                    continuation.resume(returning: textItem)
                    return
                }

                continuation.resume(throwing: ShareError.unsupportedAttachment)
            }
        }
    }

    private func loadIncomingFileUrl(itemProvider: NSItemProvider) async throws -> URL {
        let typeIdentifiersToTry = [
            UTType.fileURL.identifier,
            UTType.audio.identifier,
            UTType.movie.identifier,
            UTType.data.identifier,
        ]

        for typeIdentifier in typeIdentifiersToTry {
            if itemProvider.hasItemConformingToTypeIdentifier(typeIdentifier) == false {
                continue
            }

            if typeIdentifier == UTType.fileURL.identifier {
                return try await loadFileUrl(itemProvider: itemProvider)
            }

            return try await loadFileRepresentation(itemProvider: itemProvider, typeIdentifier: typeIdentifier)
        }

        throw ShareError.unsupportedAttachment
    }

    private func loadFileUrl(itemProvider: NSItemProvider) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            itemProvider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if let dataItem = item as? Data, let fileUrl = URL(dataRepresentation: dataItem, relativeTo: nil) {
                    continuation.resume(returning: fileUrl)
                    return
                }

                if let fileUrl = item as? URL {
                    continuation.resume(returning: fileUrl)
                    return
                }

                continuation.resume(throwing: ShareError.unsupportedAttachment)
            }
        }
    }

    private func loadFileRepresentation(itemProvider: NSItemProvider, typeIdentifier: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            itemProvider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { fileUrl, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let fileUrl else {
                    continuation.resume(throwing: ShareError.unsupportedAttachment)
                    return
                }

                continuation.resume(returning: fileUrl)
            }
        }
    }

    private func storeUrlMetadata(importedItemIdentifier: String, sharedUrl: String) async throws {
        let trimmedUrlText = sharedUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedUrlText.isEmpty {
            throw ShareError.unsupportedAttachment
        }

        let metadata = ImportedItemMetadata(
            importedItemIdentifier: importedItemIdentifier,
            createdAtIso8601: ISO8601DateFormatter().string(from: Date()),
            kind: "url",
            originalFilename: nil,
            storedFilename: nil,
            sharedUrl: trimmedUrlText
        )

        try ShareViewController.writeMetadata(metadata: metadata, importedItemIdentifier: importedItemIdentifier)
    }

    private func storeAudioMetadata(importedItemIdentifier: String, importedFileUrl: URL) async throws {
        let storedFilename = try ShareViewController.copyImportedFile(importedFileUrl: importedFileUrl, importedItemIdentifier: importedItemIdentifier)

        let metadata = ImportedItemMetadata(
            importedItemIdentifier: importedItemIdentifier,
            createdAtIso8601: ISO8601DateFormatter().string(from: Date()),
            kind: "audio",
            originalFilename: importedFileUrl.lastPathComponent,
            storedFilename: storedFilename,
            sharedUrl: nil
        )

        try ShareViewController.writeMetadata(metadata: metadata, importedItemIdentifier: importedItemIdentifier)

        _ = storedFilename
    }

    private static func copyImportedFile(importedFileUrl: URL, importedItemIdentifier: String) throws -> String {
        guard let containerUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroupConstants.appGroupIdentifier) else {
            throw ShareError.missingAppGroupContainer
        }

        let mediaFolderUrl = containerUrl.appendingPathComponent(AppGroupConstants.mediaFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: mediaFolderUrl, withIntermediateDirectories: true)

        let filenameExtension = importedFileUrl.pathExtension.isEmpty ? "m4a" : importedFileUrl.pathExtension
        let storedFilename = "\(importedItemIdentifier).\(filenameExtension)"
        let storedFileUrl = mediaFolderUrl.appendingPathComponent(storedFilename, isDirectory: false)

        if FileManager.default.fileExists(atPath: storedFileUrl.path) {
            try FileManager.default.removeItem(at: storedFileUrl)
        }

        try FileManager.default.copyItem(at: importedFileUrl, to: storedFileUrl)
        return storedFilename
    }

    private static func writeMetadata(metadata: ImportedItemMetadata, importedItemIdentifier: String) throws {
        guard let containerUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroupConstants.appGroupIdentifier) else {
            throw ShareError.missingAppGroupContainer
        }

        let metadataFolderUrl = containerUrl.appendingPathComponent(AppGroupConstants.metadataFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: metadataFolderUrl, withIntermediateDirectories: true)

        let metadataUrl = metadataFolderUrl.appendingPathComponent("\(importedItemIdentifier).json", isDirectory: false)

        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let jsonData = try jsonEncoder.encode(metadata)
        try jsonData.write(to: metadataUrl, options: [.atomic])
    }
}

private enum ShareError: LocalizedError {
    case missingInputItem
    case missingAttachment
    case unsupportedAttachment
    case missingAppGroupContainer
    case userCancelled

    var errorDescription: String? {
        switch self {
        case .missingInputItem:
            return "Não veio nenhum item do Share Sheet."
        case .missingAttachment:
            return "Não veio nenhum anexo para importar."
        case .unsupportedAttachment:
            return "O anexo não é suportado."
        case .missingAppGroupContainer:
            return "O App Group não está configurado."
        case .userCancelled:
            return "Operação cancelada."
        }
    }
}

