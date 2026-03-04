//
//  BackendClient.swift
//  VideoPeeker
//
//  Created by Gabriel Pinheiro de Carvalho on 12/02/26.
//

import Foundation

struct BackendClient {
    struct CreateItemResponse: Decodable {
        let item_id: String
    }

    struct HealthResponse: Decodable {
        let status: String
    }

    struct YoutubeCookiesDebugResponse: Decodable {
        let path: String
        let exists: Bool
        let size_bytes: Int?
        let mtime_iso: String?
        let storage_dir: String?
        let content: String?
        let error: String?
    }
    
    struct YtDlpDebugResponse: Decodable {
        let yt_dlp_path: String?
        let yt_dlp_version: String?
        let deno_path: String?
        let deno_version: String?
        let node_path: String?
        let node_version: String?
    }
    
    struct UploadYoutubeCookiesResponse: Decodable {
        let path: String
        let written_count: Int
        let kept_count: Int
        let dropped_count: Int
        let mtime_iso: String
    }
    
    private struct DeviceCookiePayload: Encodable {
        let name: String
        let value: String
        let domain: String
        let path: String
        let secure: Bool
        let http_only: Bool
        let session_only: Bool
        let expires_epoch: Int?
    }
    
    private struct UploadYoutubeCookiesRequestPayload: Encodable {
        let cookies: [DeviceCookiePayload]
    }

    struct ItemResponse: Decodable {
        let item_id: String
        let created_at_iso: String
        let source_type: String
        let source_url: String?

        let title_text: String?

        let transcription_status: String
        let enhanced_transcript_status: String
        let summary_status: String
        let breakdown_status: String

        let detected_language: String?
        let transcript_text: String?
        let enhanced_transcript_text: String?
        let enhanced_transcript_error: String?
        let summary_json: String?
        let breakdown_json: String?

        let last_error: String?
    }

    let baseUrl: URL
    let urlSession: URLSession

    init(baseUrl: URL, urlSession: URLSession = .shared) {
        self.baseUrl = baseUrl
        self.urlSession = urlSession
    }

    func health() async throws -> HealthResponse {
        let url = baseUrl.appendingPathComponent("health")
        let (data, response) = try await urlSession.data(from: url)
        try validateHttpResponse(response: response, data: data)
        return try JSONDecoder().decode(HealthResponse.self, from: data)
    }

    func debugYoutubeCookies() async throws -> YoutubeCookiesDebugResponse {
        let url = baseUrl.appendingPathComponent("debug/youtube-cookies")
        let (data, response) = try await urlSession.data(from: url)
        try validateHttpResponse(response: response, data: data)
        return try JSONDecoder().decode(YoutubeCookiesDebugResponse.self, from: data)
    }
    
    func debugYtDlp() async throws -> YtDlpDebugResponse {
        let url = baseUrl.appendingPathComponent("debug/ytdlp")
        let (data, response) = try await urlSession.data(from: url)
        try validateHttpResponse(response: response, data: data)
        return try JSONDecoder().decode(YtDlpDebugResponse.self, from: data)
    }
    
    func uploadYoutubeCookies(cookies: [HTTPCookie]) async throws -> UploadYoutubeCookiesResponse {
        let url = baseUrl.appendingPathComponent("youtube-cookies/upload")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        
        let payloadCookies = cookies.map { cookie in
            DeviceCookiePayload(
                name: cookie.name,
                value: cookie.value,
                domain: cookie.domain,
                path: cookie.path,
                secure: cookie.isSecure,
                http_only: isHttpOnly(cookie),
                session_only: cookie.isSessionOnly,
                expires_epoch: cookie.expiresDate.map { Int($0.timeIntervalSince1970.rounded()) }
            )
        }
        let payload = UploadYoutubeCookiesRequestPayload(cookies: payloadCookies)
        request.httpBody = try JSONEncoder().encode(payload)
        
        let (data, response) = try await urlSession.data(for: request)
        try validateHttpResponse(response: response, data: data)
        return try JSONDecoder().decode(UploadYoutubeCookiesResponse.self, from: data)
    }

    func createUrlItem(sourceUrl: String) async throws -> String {
        let url = baseUrl.appendingPathComponent("items")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let requestBody = ["source_url": sourceUrl]
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])

        let (data, response) = try await urlSession.data(for: request)
        try validateHttpResponse(response: response, data: data)

        let decoded = try JSONDecoder().decode(CreateItemResponse.self, from: data)
        return decoded.item_id
    }

    func uploadAudioItem(fileUrl: URL) async throws -> String {
        let url = baseUrl.appendingPathComponent("items/upload")

        let boundaryText = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundaryText)", forHTTPHeaderField: "content-type")

        let fileData = try Data(contentsOf: fileUrl)
        let filenameText = fileUrl.lastPathComponent

        var bodyData = Data()

        bodyData.append("--\(boundaryText)\r\n".data(using: .utf8)!)
        bodyData.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filenameText)\"\r\n".data(using: .utf8)!)
        bodyData.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        bodyData.append(fileData)
        bodyData.append("\r\n".data(using: .utf8)!)
        bodyData.append("--\(boundaryText)--\r\n".data(using: .utf8)!)

        let (data, response) = try await urlSession.upload(for: request, from: bodyData)
        try validateHttpResponse(response: response, data: data)

        let decoded = try JSONDecoder().decode(CreateItemResponse.self, from: data)
        return decoded.item_id
    }

    func startTranscription(itemId: String, extendedOutput: Bool = false) async throws -> ItemResponse {
        let url = urlForItemAction(itemId: itemId, path: "transcribe", extendedOutput: extendedOutput)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let (data, response) = try await urlSession.data(for: request)
        try validateHttpResponse(response: response, data: data)

        return try JSONDecoder().decode(ItemResponse.self, from: data)
    }

    func startBreakdown(itemId: String, extendedOutput: Bool = false) async throws -> ItemResponse {
        let url = urlForItemAction(itemId: itemId, path: "breakdown", extendedOutput: extendedOutput)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let (data, response) = try await urlSession.data(for: request)
        try validateHttpResponse(response: response, data: data)

        return try JSONDecoder().decode(ItemResponse.self, from: data)
    }

    func startSummary(itemId: String, extendedOutput: Bool = false) async throws -> ItemResponse {
        let url = urlForItemAction(itemId: itemId, path: "summary", extendedOutput: extendedOutput)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let (data, response) = try await urlSession.data(for: request)
        try validateHttpResponse(response: response, data: data)

        return try JSONDecoder().decode(ItemResponse.self, from: data)
    }

    private func urlForItemAction(itemId: String, path: String, extendedOutput: Bool) -> URL {
        var components = URLComponents(url: baseUrl.appendingPathComponent("items/\(itemId)/\(path)"), resolvingAgainstBaseURL: false)!
        if extendedOutput {
            components.queryItems = [URLQueryItem(name: "extended_output", value: "true")]
        }
        return components.url!
    }

    func getItem(itemId: String) async throws -> ItemResponse {
        let url = baseUrl.appendingPathComponent("items/\(itemId)")
        let (data, response) = try await urlSession.data(from: url)
        try validateHttpResponse(response: response, data: data)
        return try JSONDecoder().decode(ItemResponse.self, from: data)
    }

    func deleteItem(itemId: String) async throws {
        let url = baseUrl.appendingPathComponent("items/\(itemId)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        let (data, response) = try await urlSession.data(for: request)
        try validateHttpResponse(response: response, data: data)
    }

    private func validateHttpResponse(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendClientError.invalidResponse
        }

        if (200 ... 299).contains(httpResponse.statusCode) {
            return
        }

        let responseBody = String(decoding: data, as: UTF8.self)
        throw BackendClientError.httpError(statusCode: httpResponse.statusCode, responseBody: responseBody)
    }
    
    private func isHttpOnly(_ cookie: HTTPCookie) -> Bool {
        let httpOnlyKey = HTTPCookiePropertyKey("HttpOnly")
        if let value = cookie.properties?[httpOnlyKey] {
            if let boolValue = value as? Bool {
                return boolValue
            }
            if let stringValue = value as? String {
                return stringValue.caseInsensitiveCompare("true") == .orderedSame
            }
        }
        return false
    }
}

enum BackendClientError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, responseBody: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Resposta inválida do backend."
        case let .httpError(statusCode, responseBody):
            return "Backend retornou HTTP \(statusCode).\n\n\(responseBody)"
        }
    }
}

