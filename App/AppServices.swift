import AuthenticationServices
#if !targetEnvironment(macCatalyst)
import ActivityKit
#endif
import Observation
import CryptoKit
import Foundation
import Security
import UIKit
import UserNotifications

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
        try await api.checkAvailability()
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
    static func remove(_ name: String) { try? FileManager.default.removeItem(at: directory.appendingPathComponent(name)) }
    static func clearPrivate() {
        for name in ["tickets.json", "profile.json", "updated.json", "adminAccess.json", "adminActivities.json", "pendingScans.json"] { try? FileManager.default.removeItem(at: directory.appendingPathComponent(name)) }
    }
}

// Transfer only a Sendable Bool across the notification callback boundary.
// Older supported Apple SDKs do not mark UNNotificationSettings as Sendable.
enum NotificationAuthorization {
    static func isAllowed() async -> Bool {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
            }
        }
    }
}

#if targetEnvironment(macCatalyst)
@MainActor @Observable
final class LiveEventController {
    // Live Activities do not exist on the Mac; keep the same surface as a no-op.
    static let shared = LiveEventController()
    private(set) var activeTicketID: String?
    var available: Bool { false }
    func clear() {}
    func stop() async {}
    func refresh(tickets: [Ticket], activities: [Activity], sessionExpiry: Date) async {}
}
#else
@MainActor @Observable
final class LiveEventController {
    static let shared = LiveEventController()
    private(set) var activeTicketID: String?
    private var revision: UInt64 = 0
    private var starting = false
    var available: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }
    func clear() {
        revision &+= 1
        activeTicketID = nil
        Task { await Self.endAll() }
    }
    nonisolated private static func endAll() async {
        for activity in ActivityKit.Activity<SalveEventActivityAttributes>.activities { await activity.end(nil, dismissalPolicy: .immediate) }
    }
    nonisolated private static func end(id: String) async {
        if let activity = ActivityKit.Activity<SalveEventActivityAttributes>.activities.first(where: { $0.id == id }) { await activity.end(nil, dismissalPolicy: .immediate) }
    }
    nonisolated private static func update(id: String, state: SalveEventActivityAttributes.ContentState, staleDate: Date) async {
        if let activity = ActivityKit.Activity<SalveEventActivityAttributes>.activities.first(where: { $0.id == id }) { await activity.update(ActivityContent(state: state, staleDate: staleDate)) }
    }
    func stop() async {
        revision &+= 1
        activeTicketID = nil
        await Self.endAll()
    }
    func start(_ snapshot: EventLiveSnapshot, sessionExpiry: Date, authorized: @MainActor () -> Bool) async throws {
        guard !starting else { throw APIProblem(code: "live_busy", message: "De evenementkaart wordt nog gestart. Probeer het opnieuw.") }
        starting = true
        defer { starting = false }
        let currentRevision = revision
        activeTicketID = nil
        guard available else { throw APIProblem(code: "live_disabled", message: "Live activiteiten staan uit. Schakel ze in bij de iPhone-instellingen van deze app.") }
        await Self.endAll()
        guard revision == currentRevision, authorized(), sessionExpiry > .now else { throw CancellationError() }
        let deadline = min(snapshot.expiresAt, sessionExpiry)
        _ = try ActivityKit.Activity.request(attributes: SalveEventActivityAttributes(ticketID: snapshot.ticketID), content: ActivityContent(state: .init(event: snapshot), staleDate: deadline), pushType: nil)
        activeTicketID = snapshot.ticketID
    }
    func refresh(tickets: [Ticket], activities: [Activity], sessionExpiry: Date) async {
        let currentRevision = revision
        let existing = ActivityKit.Activity<SalveEventActivityAttributes>.activities
            .filter { $0.activityState == .active || $0.activityState == .stale }
            .map { (id: $0.id, ticketID: $0.attributes.ticketID, expiresAt: $0.content.state.event.expiresAt) }
        if !existing.contains(where: { $0.ticketID == activeTicketID }) { activeTicketID = nil }
        for item in existing {
            let ticketID = item.ticketID
            guard revision == currentRevision else { return }
            guard let ticket = tickets.first(where: { $0.id == ticketID }),
                  let activity = activities.first(where: { $0.id == ticket.activityID }),
                  let value = EventLiveSnapshot.make(ticket: ticket, activity: activity, expiresNoLaterThan: min(item.expiresAt, sessionExpiry)) else {
                await Self.end(id: item.id)
                if activeTicketID == ticketID { activeTicketID = nil }
                continue
            }
            await Self.update(id: item.id, state: .init(event: value), staleDate: value.expiresAt)
            guard revision == currentRevision else { return }
            activeTicketID = ticketID
        }
        guard revision == currentRevision, activeTicketID == nil, available else { return }
        let started = UserDefaults.standard.dictionary(forKey: Self.startedKey) as? [String: Double] ?? [:]
        let candidate = tickets.sorted { ($0.startsAt ?? .distantFuture) < ($1.startsAt ?? .distantFuture) }.compactMap { ticket -> EventLiveSnapshot? in
            guard let activity = activities.first(where: { $0.id == ticket.activityID }) else { return nil }
            return EventLiveSnapshot.make(ticket: ticket, activity: activity, expiresNoLaterThan: sessionExpiry)
        }.first
        // Without push, iOS only lets us start while the app is open; avoid re-adding a card the user just dismissed.
        guard let candidate, Date.now.timeIntervalSince1970 - (started[candidate.ticketID] ?? 0) > 8 * 3600 else { return }
        do {
            try await start(candidate, sessionExpiry: sessionExpiry, authorized: { true })
            var updated = started.filter { Date.now.timeIntervalSince1970 - $0.value < 7 * 86400 }
            updated[candidate.ticketID] = Date.now.timeIntervalSince1970
            UserDefaults.standard.set(updated, forKey: Self.startedKey)
        } catch { }
    }
    private static let startedKey = "liveEvent.autoStarted"
}
#endif

// MARK: - Diagnostics (on-device only; shared by the member, never uploaded automatically)
@preconcurrency import MetricKit

/// Collects Apple's crash/hang diagnostics and a short log of error *codes*. No tokens, names, emails or messages are stored.
final class Diagnostics: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = Diagnostics()
    private let queue = DispatchQueue(label: "nl.salvemundi.diagnostics")
    private var directory: URL {
        let url = URL.applicationSupportDirectory.appendingPathComponent("SalveMundi/diagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func start() { MXMetricManager.shared.add(self) }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        queue.async {
            for payload in payloads {
                let name = "diagnostic-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(6)).json"
                try? payload.jsonRepresentation().write(to: self.directory.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
            }
            self.prune()
        }
    }
    func didReceive(_ payloads: [MXMetricPayload]) {}

    /// Records what went wrong, not who it happened to.
    func log(_ event: String) {
        queue.async {
            let file = self.directory.appendingPathComponent("events.log")
            let line = "\(ISO8601DateFormatter().string(from: .now)) \(event)\n"
            var lines = ((try? String(contentsOf: file, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
            lines.append(String(line.dropLast()))
            try? (lines.suffix(100).joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
        }
    }
    private func prune() {
        let files = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []).filter { $0.lastPathComponent.hasPrefix("diagnostic-") }
            .sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
        for file in files.dropFirst(10) { try? FileManager.default.removeItem(at: file) }
    }
    /// Plain-text report the member can send to the association.
    func report() -> String {
        queue.sync {
            let info = Bundle.main.infoDictionary
            var text = "Salve Mundi app \(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))\n"
            text += "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion), \(UIDevice.current.model)\n\n"
            text += "Recente fouten:\n" + ((try? String(contentsOf: directory.appendingPathComponent("events.log"), encoding: .utf8)) ?? "geen") + "\n"
            let files = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []).filter { $0.lastPathComponent.hasPrefix("diagnostic-") }.sorted { $0.lastPathComponent > $1.lastPathComponent }
            text += "\nCrash- en hangrapporten van iOS: \(files.count)\n"
            for file in files.prefix(3) { text += "\n--- \(file.lastPathComponent)\n" + String(decoding: (try? Data(contentsOf: file).prefix(20_000)) ?? Data(), as: UTF8.self) + "\n" }
            return text
        }
    }
}


// MARK: - Launch milestones

import os

/// Where the time goes at start-up. Visible in the Xcode/device console (category "launch") and in the shared diagnostics report.
enum Launch {
    private static let logger = Logger(subsystem: "nl.salvemundi.ios", category: "launch")
    private static let begin = ProcessInfo.processInfo.systemUptime
    static func mark(_ event: String) {
        let ms = Int((ProcessInfo.processInfo.systemUptime - begin) * 1000)
        logger.notice("\(event, privacy: .public) +\(ms)ms")
        Diagnostics.shared.log("launch \(event) +\(ms)ms")
    }
}
