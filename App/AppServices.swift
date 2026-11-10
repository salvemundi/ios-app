import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

struct PendingRevocation: Codable {
    let token: String
    let expiresAt: Date
    let deviceToken: String?
}

@MainActor
enum SecureSessionStore {
    private static let service = "nl.salvemundi.ios.session"
    static func read() -> AppSession? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "member", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONCoding.decoder().decode(AppSession.self, from: data)
    }
    static func save(_ session: AppSession) throws {
        let data = try JSONCoding.encoder().encode(session)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "member"]
        SecItemDelete(query as CFDictionary)
        var value = query
        value[kSecValueData as String] = data
        value[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(value as CFDictionary, nil) == errSecSuccess else {
            throw APIProblem(code: "keychain", message: "Je aanmelding kon niet veilig worden opgeslagen.")
        }
    }
    static func clear() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "member"] as CFDictionary)
    }
    static func pendingRevocations() -> [PendingRevocation] {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "pending-revocations", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data,
              let pending = try? JSONCoding.decoder().decode([PendingRevocation].self, from: data) else { return [] }
        return pending.filter { $0.expiresAt > .now }
    }
    static func enqueueRevocation(_ pending: PendingRevocation) throws {
        var queue = pendingRevocations().filter { $0.token != pending.token }
        queue.append(pending)
        try saveRevocations(Array(queue.suffix(5)))
    }
    static func removeRevocation(token: String) throws { try saveRevocations(pendingRevocations().filter { $0.token != token }) }
    private static func saveRevocations(_ values: [PendingRevocation]) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "pending-revocations"]
        guard !values.isEmpty else { SecItemDelete(query as CFDictionary); return }
        let data = try JSONCoding.encoder().encode(values)
        let updated = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw APIProblem(code: "keychain", message: "De serverafmelding kon niet worden bewaard. Je bent lokaal uitgelogd.") }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw APIProblem(code: "keychain", message: "De serverafmelding kon niet worden bewaard. Je bent lokaal uitgelogd.") }
    }
}

@MainActor
final class MemberLogin: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var browser: ASWebAuthenticationSession?
    private let callbackURL = "salvemundi://auth/callback"

    func signIn(server: URL, api: APIClient) async throws -> AppSession {
        let verifier = try randomString()
        let state = try randomString()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
        var components = URLComponents(url: server.appendingPathComponent("api/mobile/v1/auth/start"), resolvingAgainstBaseURL: false)!
        components.queryItems = [.init(name: "code_challenge", value: challenge), .init(name: "state", value: state), .init(name: "redirect_uri", value: callbackURL)]
        guard let url = components.url else { throw URLError(.badURL) }
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            browser = ASWebAuthenticationSession(url: url, callbackURLScheme: "salvemundi") { callback, error in
                if let error { continuation.resume(throwing: error) }
                else if let callback { continuation.resume(returning: callback) }
                else { continuation.resume(throwing: URLError(.cancelled)) }
            }
            browser?.presentationContextProvider = self
            browser?.prefersEphemeralWebBrowserSession = false
            if browser?.start() != true { continuation.resume(throwing: URLError(.cannotConnectToHost)) }
        }
        browser = nil
        let result = URLComponents(url: callback, resolvingAgainstBaseURL: false)
        guard callback.scheme == "salvemundi", callback.host == "auth", callback.path == "/callback",
              result?.queryItems?.first(where: { $0.name == "state" })?.value == state,
              let code = result?.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw APIProblem(code: "login_failed", message: "De aanmelding is niet geldig. Probeer opnieuw.")
        }
        struct Exchange: Encodable, Sendable { let code: String; let code_verifier: String; let redirect_uri: String }
        return try await api.mutation("auth/exchange", value: Exchange(code: code, code_verifier: verifier, redirect_uri: callbackURL))
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
    private func randomString() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw URLError(.unknown) }
        return Data(bytes).base64URLEncoded
    }
}

private extension Data {
    var base64URLEncoded: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}

@MainActor
enum LocalCache {
    private static var directory: URL {
        let directory = URL.applicationSupportDirectory.appendingPathComponent("SalveMundi", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var mutable = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? mutable.setResourceValues(values)
        return directory
    }
    static func read<T: Decodable>(_ name: String, as type: T.Type) -> T? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
        return try? JSONCoding.decoder().decode(type, from: data)
    }
    static func save<T: Encodable>(_ value: T, name: String) {
        guard let data = try? JSONCoding.encoder().encode(value) else { return }
        try? data.write(to: directory.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
    }
    static func clearPrivate() {
        for name in ["tickets.json", "profile.json", "updated.json"] { try? FileManager.default.removeItem(at: directory.appendingPathComponent(name)) }
    }
}
