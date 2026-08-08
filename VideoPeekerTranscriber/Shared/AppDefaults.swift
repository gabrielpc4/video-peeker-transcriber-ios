//
//  AppDefaults.swift
//  VideoPeekerTranscriber
//

import Foundation

enum AppDefaults {
    static let backendBaseUrlKey = "backendBaseUrl"
    static let defaultBackendBaseUrl = "https://videopeeker-backend.onrender.com"
    static let backendBaseUrlEnvKey = "VIDEOPEEKERTRANSCRIBER_BACKEND_BASE_URL"
    static let forceBackendBaseUrlEnvKey = "VIDEOPEEKERTRANSCRIBER_FORCE_BACKEND_BASE_URL"

    static func ensureDefaultsRegistered() {
        // This avoids different @AppStorage sites having different default values.
        var defaults: [String: Any] = [
            backendBaseUrlKey: defaultBackendBaseUrl,
        ]

        let env = ProcessInfo.processInfo.environment
        if let envUrl = env[backendBaseUrlEnvKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           envUrl.isEmpty == false
        {
            defaults[backendBaseUrlKey] = envUrl

            let forceValue = (env[forceBackendBaseUrlEnvKey] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if forceValue == "1" || forceValue.lowercased() == "true" {
                // Override previously-saved value when using specific schemes.
                UserDefaults.standard.set(envUrl, forKey: backendBaseUrlKey)
            }
        }

        UserDefaults.standard.register(defaults: defaults)
    }
}

