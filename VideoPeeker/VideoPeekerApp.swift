//
//  VideoPeekerApp.swift
//  VideoPeeker
//
//  Created by Gabriel Pinheiro de Carvalho on 12/02/26.
//

import SwiftUI
import SwiftData

@main
struct VideoPeekerApp: App {
    private let modelContainer: ModelContainer

    init() {
        AppDefaults.ensureDefaultsRegistered()
        Task { @MainActor in
            ConsoleLogStore.shared.startCaptureIfNeeded()
        }

        // Use a deterministic store location inside the App Group container so the
        // main app and the share extension can both access the same store if needed.
        // Also, proactively create the parent directory to avoid noisy CoreData logs.
        do {
            guard let containerUrl = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: AppGroupConstants.appGroupIdentifier
            ) else {
                throw NSError(domain: "VideoPeekerApp", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing App Group container URL."])
            }

            let appSupportUrl = containerUrl.appendingPathComponent("Library/Application Support", isDirectory: true)
            try FileManager.default.createDirectory(at: appSupportUrl, withIntermediateDirectories: true)

            let storeUrl = appSupportUrl.appendingPathComponent("default.store")
            let configuration = ModelConfiguration(url: storeUrl)
            modelContainer = try ModelContainer(for: MediaItem.self, configurations: configuration)
        } catch {
            // Fallback to default container if App Group is misconfigured.
            // This should be rare, but avoids a hard crash.
            modelContainer = try! ModelContainer(for: MediaItem.self)
            print("[VideoPeeker] Failed to create AppGroup SwiftData store: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ConsoleLogStore.shared)
        }
        .modelContainer(modelContainer)
    }
}
