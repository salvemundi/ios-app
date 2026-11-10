import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private struct FailureEnvelope: Decodable { let error: APIProblem }

public struct APIClient: Sendable {
    public let baseURL: URL
    private let session: URLSession
    private let timeout: TimeInterval
    public init(baseURL: URL, session: URLSession = .shared, timeout: TimeInterval = 25) { self.baseURL = baseURL; self.session = session; self.timeout = timeout }

    public func request<Value: Decodable & Sendable>(
        _ path: String, method: String = "GET", token: String? = nil, body: Data? = nil,
        as type: Value.Type = Value.self
    ) async throws -> Value {
        guard baseURL.scheme == "https", var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIProblem(code: "invalid_server", message: "De serverinstelling is ongeldig.")
        }
        components.path = "/api/mobile/v1/" + path
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = body; request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(response.statusCode) else {
            if let failure = try? JSONCoding.decoder().decode(FailureEnvelope.self, from: data) { throw failure.error }
            throw APIProblem(code: response.statusCode == 401 ? "unauthorized" : "server_error", message: response.statusCode == 401 ? "Log opnieuw in om verder te gaan." : "De server is tijdelijk niet bereikbaar. Probeer het later opnieuw.")
        }
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
    case activities, activity(String), ticket(String), tickets, paymentReturn
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
        case "tickets": self = pieces.count > 1 ? .ticket(pieces[1]) : .tickets
        case "profiel" where pieces.dropFirst().first == "tickets": self = .tickets
        case "payment": self = .paymentReturn
        default: return nil
        }
    }
}
