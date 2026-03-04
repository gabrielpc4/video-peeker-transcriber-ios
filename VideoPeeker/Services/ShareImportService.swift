//
//  ShareImportService.swift
//  VideoPeeker
//
//  Created by Gabriel Pinheiro de Carvalho on 12/02/26.
//

import Foundation
import SwiftData

struct ShareImportService {
    struct ImportedItemMetadata: Codable {
        let importedItemIdentifier: String
        let createdAtIso8601: String

        let kind: String

        let originalFilename: String?
        let storedFilename: String?

        let sharedUrl: String?
    }

    func importPendingItems(modelContext: ModelContext) throws -> Int {
        guard let containerUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroupConstants.appGroupIdentifier) else {
            throw ShareImportError.missingAppGroupContainer
        }

        let metadataFolderUrl = containerUrl.appendingPathComponent(AppGroupConstants.metadataFolderName, isDirectory: true)
        if FileManager.default.fileExists(atPath: metadataFolderUrl.path) == false {
            return 0
        }

        let metadataFileUrls = try FileManager.default.contentsOfDirectory(
            at: metadataFolderUrl,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        let jsonDecoder = JSONDecoder()
        let iso8601Formatter = ISO8601DateFormatter()
        let audioTitleFormatter: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "dd MMM HH:mm"
            return f
        }()

        var importedCount = 0

        for metadataFileUrl in metadataFileUrls {
            if metadataFileUrl.pathExtension.lowercased() != "json" {
                continue
            }

            let jsonData = try Data(contentsOf: metadataFileUrl)
            let metadata = try jsonDecoder.decode(ImportedItemMetadata.self, from: jsonData)

            let createdAtDate = iso8601Formatter.date(from: metadata.createdAtIso8601) ?? Date()

            let existingDescriptor = FetchDescriptor<MediaItem>(
                predicate: #Predicate { item in
                    item.importedItemIdentifier == metadata.importedItemIdentifier
                }
            )

            let existingItems = try modelContext.fetch(existingDescriptor)

            if existingItems.isEmpty {
                let sourceType: MediaSourceType
                let sourceUrl = metadata.sharedUrl
                let titleText = metadata.originalFilename

                if metadata.kind == "audio" {
                    sourceType = .audioFile
                } else if metadata.kind == "url" {
                    sourceType = .url
                } else {
                    sourceType = .unknown
                }

                let mediaItem = MediaItem(
                    importedItemIdentifier: metadata.importedItemIdentifier,
                    createdAt: createdAtDate,
                    sourceType: sourceType,
                    sourceUrl: sourceUrl,
                    storedFilename: metadata.storedFilename
                )

                if sourceType == .audioFile {
                    // Friendly default title for WhatsApp voice notes.
                    mediaItem.titleText = "Audio \(audioTitleFormatter.string(from: createdAtDate))"
                } else if let titleText, titleText.isEmpty == false {
                    mediaItem.titleText = titleText
                }

                modelContext.insert(mediaItem)
                importedCount += 1
            }

            try FileManager.default.removeItem(at: metadataFileUrl)
        }

        if importedCount > 0 {
            try modelContext.save()
        }

        return importedCount
    }
}

enum ShareImportError: LocalizedError {
    case missingAppGroupContainer

    var errorDescription: String? {
        switch self {
        case .missingAppGroupContainer:
            return "O App Group não está configurado (container não encontrado)."
        }
    }
}

