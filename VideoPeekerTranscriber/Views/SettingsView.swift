//
//  SettingsView.swift
//  VideoPeekerTranscriber
//
//  Created by Gabriel Pinheiro de Carvalho on 12/02/26.
//

import SwiftUI
import UIKit

struct SettingsView: View {
    @AppStorage(AppDefaults.backendBaseUrlKey) private var backendBaseUrlText = AppDefaults.defaultBackendBaseUrl
    @State private var isYoutubeCookieRefreshPresented = false
    @State private var youtubeCookieRefreshMessage: String?
    @State private var youtubeCookiesDebugText: String?
    @State private var youtubeCookiesDebugError: String?
    @State private var isFetchingYoutubeCookies = false
    @State private var isYoutubeCookiesSheetPresented = false
    
    @State private var ytDlpDebugText: String?
    @State private var ytDlpDebugError: String?
    @State private var isFetchingYtDlpDebug = false
    @State private var isYtDlpSheetPresented = false

    var body: some View {
        Form {
            Section("Backend") {
                TextField("Base URL", text: $backendBaseUrlText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Text("Para testar no device físico, use o IP da sua máquina na mesma rede.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Debug") {
                Button("Atualizar cookies do YouTube (login no iPhone)") {
                    isYoutubeCookieRefreshPresented = true
                }
                
                if let message = youtubeCookieRefreshMessage, message.isEmpty == false {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
                
                Button {
                    Task { @MainActor in
                        await fetchYoutubeCookiesDebug()
                    }
                } label: {
                    if isFetchingYoutubeCookies {
                        HStack {
                            ProgressView()
                            Text("Carregando cookies do YouTube…")
                        }
                    } else {
                        Text("Ver cookies do YouTube (backend)")
                    }
                }
                .disabled(isFetchingYoutubeCookies)
                
                Button {
                    Task { @MainActor in
                        await fetchYtDlpDebug()
                    }
                } label: {
                    if isFetchingYtDlpDebug {
                        HStack {
                            ProgressView()
                            Text("Carregando status do yt-dlp…")
                        }
                    } else {
                        Text("Ver status do yt-dlp (Deno/EJS)")
                    }
                }
                .disabled(isFetchingYtDlpDebug)

                if let youtubeCookiesDebugError, youtubeCookiesDebugError.isEmpty == false {
                    Text(youtubeCookiesDebugError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
                
                if let ytDlpDebugError, ytDlpDebugError.isEmpty == false {
                    Text(ytDlpDebugError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $isYoutubeCookieRefreshPresented) {
            NavigationStack {
                YouTubeCookieRefreshView(backendBaseUrlText: backendBaseUrlText) { message in
                    youtubeCookieRefreshMessage = message
                }
            }
        }
        .sheet(isPresented: $isYoutubeCookiesSheetPresented) {
            NavigationStack {
                ScrollView {
                    Text(youtubeCookiesDebugText ?? "")
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .navigationTitle("YouTube cookies")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Fechar") {
                            isYoutubeCookiesSheetPresented = false
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Copiar") {
                            UIPasteboard.general.string = youtubeCookiesDebugText ?? ""
                        }
                        .disabled((youtubeCookiesDebugText ?? "").isEmpty)
                    }
                }
            }
        }
        .sheet(isPresented: $isYtDlpSheetPresented) {
            NavigationStack {
                ScrollView {
                    Text(ytDlpDebugText ?? "")
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .navigationTitle("yt-dlp debug")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Fechar") {
                            isYtDlpSheetPresented = false
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Copiar") {
                            UIPasteboard.general.string = ytDlpDebugText ?? ""
                        }
                        .disabled((ytDlpDebugText ?? "").isEmpty)
                    }
                }
            }
        }
    }

    @MainActor
    private func fetchYoutubeCookiesDebug() async {
        youtubeCookiesDebugError = nil
        youtubeCookiesDebugText = nil
        isFetchingYoutubeCookies = true
        defer { isFetchingYoutubeCookies = false }

        do {
            let baseUrl = backendBaseUrlText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: baseUrl) else {
                youtubeCookiesDebugError = "Base URL inválida."
                return
            }

            let client = BackendClient(baseUrl: url)
            let response = try await client.debugYoutubeCookies()

            var lines: [String] = []
            lines.append("path: \(response.path)")
            lines.append("exists: \(response.exists)")
            if let size = response.size_bytes {
                lines.append("size_bytes: \(size)")
            }
            if let mtime = response.mtime_iso {
                lines.append("mtime_iso: \(mtime)")
            }
            if let storage = response.storage_dir {
                lines.append("storage_dir: \(storage)")
            }
            if let error = response.error, error.isEmpty == false {
                lines.append("error: \(error)")
            }
            lines.append("")
            lines.append(response.content ?? "")

            youtubeCookiesDebugText = lines.joined(separator: "\n")
            isYoutubeCookiesSheetPresented = true
        } catch {
            youtubeCookiesDebugError = error.localizedDescription
        }
    }
    
    @MainActor
    private func fetchYtDlpDebug() async {
        ytDlpDebugError = nil
        ytDlpDebugText = nil
        isFetchingYtDlpDebug = true
        defer { isFetchingYtDlpDebug = false }
        
        do {
            let baseUrl = backendBaseUrlText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: baseUrl) else {
                ytDlpDebugError = "Base URL inválida."
                return
            }
            
            let client = BackendClient(baseUrl: url)
            let response = try await client.debugYtDlp()
            
            var lines: [String] = []
            lines.append("yt_dlp_path: \(response.yt_dlp_path ?? "nil")")
            lines.append("yt_dlp_version: \(response.yt_dlp_version ?? "nil")")
            lines.append("deno_path: \(response.deno_path ?? "nil")")
            lines.append("deno_version: \(response.deno_version ?? "nil")")
            lines.append("node_path: \(response.node_path ?? "nil")")
            lines.append("node_version: \(response.node_version ?? "nil")")
            
            ytDlpDebugText = lines.joined(separator: "\n")
            isYtDlpSheetPresented = true
        } catch {
            ytDlpDebugError = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}

