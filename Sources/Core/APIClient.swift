import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private struct FailureEnvelope: Decodable { let error: APIProblem }

public struct APIClient: Sendable {
    public let baseURL: URL
    private let session: URLSession
    private let timeout: TimeInterval
    public init(baseURL: URL, session: URLSession? = nil, timeout: TimeInterval = 25) {
        self.baseURL = baseURL; self.timeout = timeout
        if let session { self.session = session }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil; configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
            self.session = URLSession(configuration: configuration)
        }
    }

    public func request<Value: Decodable & Sendable>(
        _ path: String, method: String = "GET", token: String? = nil, body: Data? = nil,
        query: [URLQueryItem] = [], as type: Value.Type = Value.self
    ) async throws -> Value {
        let data = try await send(path, method: method, token: token, body: body, query: query)
        return try JSONCoding.decoder().decode(APIEnvelope<Value>.self, from: data).data
    }

    /// Verify the mobile service is enabled before opening the Microsoft authentication browser.
    /// Next.js supplies HEAD for its GET route, so no activities payload needs to be downloaded.
    public func checkAvailability() async throws {
        _ = try await send("activities", method: "HEAD")
    }

    private func send(_ path: String, method: String, token: String? = nil, body: Data? = nil, query: [URLQueryItem] = [], contentType: String = "application/json") async throws -> Data {
        guard baseURL.scheme == "https", var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIProblem(code: "invalid_server", message: "De serverinstelling is ongeldig.")
        }
        components.path = "/api/mobile/v1/" + path
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = body; request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(response.statusCode) else {
            let serviceEndpoints: Set<String> = ["activities", "auth/start", "auth/exchange", "me", "me/tickets", "notification-preferences", "devices"]
            if response.statusCode == 404, serviceEndpoints.contains(path) {
                throw APIProblem(code: "backend_unavailable", message: "De appverbinding met de acceptatieomgeving is nog niet actief. Probeer het over een paar minuten opnieuw.")
            }
            let failure = try? JSONCoding.decoder().decode(FailureEnvelope.self, from: data)
            if response.statusCode == 401 {
                throw APIProblem(code: "unauthorized", message: failure?.error.message ?? "Log opnieuw in om verder te gaan.")
            }
            if response.statusCode == 403, path.hasPrefix("admin/") {
                throw APIProblem(code: "forbidden", message: failure?.error.message ?? "Je hebt geen toegang tot deze activiteit.")
            }
            if let failure { throw failure.error }
            throw APIProblem(code: "server_error", message: "De server is tijdelijk niet bereikbaar. Probeer het later opnieuw.")
        }
        return data
    }

    public func upload<Value: Decodable & Sendable>(_ path: String, image: Data, token: String, mimeType: String = "image/jpeg", filename: String = "activity.jpg", as type: Value.Type = Value.self) async throws -> Value {
        guard image.count <= 10 * 1024 * 1024 else { throw APIProblem(code: "image_too_large", message: "De afbeelding mag maximaal 10 MB groot zijn.") }
        let safeFilename = filename.filter { $0.isASCII && ($0.isLetter || $0.isNumber || ".-_".contains($0)) }
        guard !safeFilename.isEmpty, ["image/jpeg", "image/png", "video/mp4", "video/quicktime"].contains(mimeType) else { throw APIProblem(code: "invalid_media", message: "Dit bestandstype wordt niet ondersteund.") }
        let boundary = "SalveMundi-" + UUID().uuidString
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(safeFilename)\"\r\nContent-Type: \(mimeType)\r\n\r\n".utf8)
        body.append(image)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        let data = try await send(path, method: "POST", token: token, body: body, contentType: "multipart/form-data; boundary=\(boundary)")
        return try JSONCoding.decoder().decode(APIEnvelope<Value>.self, from: data).data
    }

    public func mutation<Input: Encodable & Sendable, Output: Decodable & Sendable>(
        _ path: String, method: String = "POST", token: String? = nil, value: Input, as type: Output.Type = Output.self
    ) async throws -> Output {
        try await request(path, method: method, token: token, body: JSONCoding.encoder().encode(value), as: type)
    }
}

public struct MutationAcknowledgement: Decodable, Sendable { public let success: Bool }
public struct EmptyPayload: Encodable, Sendable { public init() {} }

public enum DeepLink: Equatable, Sendable {
    case activities, activity(String), ticket(String), tickets, paymentReturn, adminActivities(String?)
    public init?(url: URL) {
        let isCustom = url.scheme == "salvemundi"
        guard isCustom || (url.scheme == "https" && ["acc.salvemundi.nl"].contains(url.host ?? "")) else { return nil }
        var pieces = url.pathComponents.filter { $0 != "/" }
        if isCustom, let host = url.host { pieces.insert(host, at: 0) }
        switch pieces.first {
        case "activities", "activiteiten":
            guard pieces.count > 1 else { self = .activities; return }
            if pieces[1] == "bevestiging" { self = .paymentReturn }
            else { self = .activity(pieces[1].contains(":") ? pieces[1] : "event:\(pieces[1].split(separator: "-").first ?? "")") }
        case "admin" where pieces.dropFirst().first == "activities":
            if pieces.count > 2 {
                let id = pieces[2].hasPrefix("event:") ? pieces[2] : "event:" + pieces[2]
                guard id.dropFirst(6).allSatisfy({ "0123456789".contains($0) }), id.count > 6 else { return nil }
                self = .adminActivities(id)
            } else { self = .adminActivities(nil) }
        case "tickets": self = pieces.count > 1 ? .ticket(pieces[1]) : .tickets
        case "profiel" where pieces.dropFirst().first == "tickets": self = .tickets
        case "payment": self = .paymentReturn
        default: return nil
        }
    }
}
