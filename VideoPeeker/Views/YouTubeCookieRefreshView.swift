//
//  YouTubeCookieRefreshView.swift
//  VideoPeeker
//
//  Created by Assistant on 04/03/26.
//

import SwiftUI
import WebKit
import Combine

@MainActor
final class YouTubeCookieRefreshSession: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    let dataStore: WKWebsiteDataStore
    let webView: WKWebView
    
    init() {
        let store = WKWebsiteDataStore.nonPersistent()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store
        
        self.dataStore = store
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        self.webView.allowsBackForwardNavigationGestures = true
    }
    
    func loadLogin() {
        guard let url = URL(string: "https://accounts.google.com/ServiceLogin?service=youtube&continue=https%3A%2F%2Fwww.youtube.com%2Frobots.txt") else {
            return
        }
        webView.load(URLRequest(url: url))
    }
    
    func loadRobots() {
        guard let url = URL(string: "https://www.youtube.com/robots.txt") else {
            return
        }
        webView.load(URLRequest(url: url))
    }
    
    func clearSession() async {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await withCheckedContinuation { continuation in
            dataStore.fetchDataRecords(ofTypes: types) { records in
                continuation.resume(returning: records)
            }
        }
        
        await withCheckedContinuation { continuation in
            dataStore.removeData(ofTypes: types, for: records) {
                continuation.resume(returning: ())
            }
        }
    }
    
    func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            dataStore.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }
}

struct YouTubeCookieRefreshWebView: UIViewRepresentable {
    @ObservedObject var session: YouTubeCookieRefreshSession
    
    func makeUIView(context: Context) -> WKWebView {
        session.webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Intentionally empty: the session drives navigation.
    }
}

struct YouTubeCookieRefreshView: View {
    let backendBaseUrlText: String
    let onUploadSuccess: (String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session = YouTubeCookieRefreshSession()
    
    @State private var statusText: String = "Faça login com a conta YouTube desejada (ex: gabrielgpk5@gmail.com). Depois toque em “Capturar e enviar”."
    @State private var isUploading = false
    @State private var isResettingSession = false
    
    var body: some View {
        VStack(spacing: 0) {
            Text(statusText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            
            Divider()
            
            YouTubeCookieRefreshWebView(session: session)
        }
        .navigationTitle("Atualizar cookies")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Fechar") {
                    dismiss()
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Resetar sessão") {
                    Task { @MainActor in
                        await resetSession()
                    }
                }
                .disabled(isUploading || isResettingSession)
                
                Button("Robots.txt") {
                    session.loadRobots()
                }
                .disabled(isUploading || isResettingSession)
                
                Button {
                    Task { @MainActor in
                        await captureAndUploadCookies()
                    }
                } label: {
                    if isUploading {
                        ProgressView()
                    } else {
                        Text("Capturar e enviar")
                    }
                }
                .disabled(isUploading || isResettingSession)
            }
        }
        .onAppear {
            session.loadLogin()
        }
    }
    
    @MainActor
    private func resetSession() async {
        isResettingSession = true
        defer { isResettingSession = false }
        
        statusText = "Limpando sessão local..."
        await session.clearSession()
        session.loadLogin()
        statusText = "Sessão limpa. Faça login novamente e depois toque em “Capturar e enviar”."
    }
    
    @MainActor
    private func captureAndUploadCookies() async {
        isUploading = true
        defer { isUploading = false }
        
        statusText = "Coletando cookies da sessão atual..."
        let cookies = await session.allCookies()
        
        let youtubeCookies = cookies.filter { cookie in
            let domain = cookie.domain.lowercased()
            return domain.contains("youtube.com")
                || domain.contains("google.com")
                || domain.contains("googlevideo.com")
                || domain.contains("ytimg.com")
        }
        
        guard youtubeCookies.isEmpty == false else {
            statusText = "Nenhum cookie relevante foi encontrado. Faça login, abra o robots.txt e tente novamente."
            return
        }
        
        do {
            let baseUrl = backendBaseUrlText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: baseUrl) else {
                statusText = "Base URL inválida."
                return
            }
            
            let client = BackendClient(baseUrl: url)
            let response = try await client.uploadYoutubeCookies(cookies: youtubeCookies)
            statusText = "Upload concluído. Cookies aceitos: \(response.kept_count), descartados: \(response.dropped_count)."
            onUploadSuccess("Cookies do YouTube atualizados no backend (\(response.kept_count) cookies).")
            dismiss()
        } catch {
            statusText = "Falha no upload: \(error.localizedDescription)"
        }
    }
}

#Preview {
    NavigationStack {
        YouTubeCookieRefreshView(backendBaseUrlText: "http://localhost:8000") { _ in }
    }
}
