import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Security)
import Security
#endif

/// Only display-safe summaries cross the app/widget boundary. Never add a QR token or auth credential here.
public struct WidgetEvent: Codable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let startsAt: Date?
    public let location: String?
    public init(id: String, title: String, startsAt: Date?, location: String?) {
        self.id = id; self.title = title; self.startsAt = startsAt; self.location = location
    }
    public var deepLink: URL? {
        var components = URLComponents()
        components.scheme = "salvemundi"; components.host = "activities"; components.path = "/\(id)"
        return components.url
    }
}

public struct WidgetSnapshot: Codable, Sendable {
    public let updatedAt: Date
    public let events: [WidgetEvent]
    public let nextBooking: WidgetEvent?
    public let signedIn: Bool
    public let adminSummary: AdminWidgetSummary?
    public init(updatedAt: Date = .now, events: [WidgetEvent], nextBooking: WidgetEvent?, signedIn: Bool, adminSummary: AdminWidgetSummary? = nil) {
        self.updatedAt = updatedAt; self.events = events; self.nextBooking = nextBooking; self.signedIn = signedIn; self.adminSummary = adminSummary
    }
    public static let empty = WidgetSnapshot(events: [], nextBooking: nil, signedIn: false)
    public static let appGroup = "group.nl.salvemundi.ios"
    public static let fileName = "widget-summary.json"
}

/// Counts-only capability. This is never a normal app session and cannot read participants or mutate events.
public struct AdminWidgetCredential: Codable, Sendable {
    public let token: String
    public let expiresAt: Date
    public init(token: String, expiresAt: Date) { self.token = token; self.expiresAt = expiresAt }
    public var isValid: Bool {
        token.range(of: "^smw_[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil && expiresAt > .now
    }
}

public struct AdminWidgetActivity: Codable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let startsAt: Date?
    public let confirmedCount: Int
    public let pendingCount: Int
    public let checkedInCount: Int
    public let capacity: Int?
    public init(id: String, title: String, startsAt: Date?, confirmedCount: Int, pendingCount: Int, checkedInCount: Int, capacity: Int?) {
        self.id = id; self.title = title; self.startsAt = startsAt; self.confirmedCount = confirmedCount
        self.pendingCount = pendingCount; self.checkedInCount = checkedInCount; self.capacity = capacity
    }
    public var deepLink: URL? {
        var components = URLComponents()
        components.scheme = "salvemundi"; components.host = "admin"; components.path = "/activities/\(id)"
        return components.url
    }
}

public struct AdminWidgetSummary: Codable, Sendable {
    public let items: [AdminWidgetActivity]
    public let fetchedAt: Date
    public let expiresAt: Date
    public init(items: [AdminWidgetActivity], fetchedAt: Date = .now, expiresAt: Date) {
        self.items = Array(items.prefix(8)); self.fetchedAt = fetchedAt; self.expiresAt = expiresAt
    }
    /// Enforce a local upper bound even when a response accidentally advertises a longer lifetime.
    public var displayDeadline: Date { min(expiresAt, fetchedAt.addingTimeInterval(15 * 60)) }
    public func isFresh(at date: Date = .now) -> Bool { date >= fetchedAt.addingTimeInterval(-60) && date < displayDeadline }
}

public enum AdminWidgetCredentialStore {
    private static let service = "nl.salvemundi.ios.widget-counts"
    private static var accessGroup: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "KEYCHAIN_ACCESS_GROUP") as? String,
              !value.isEmpty, !value.contains("$("), value.hasSuffix(".nl.salvemundi.ios.shared") else { return nil }
        return value
    }
    public static func save(_ credential: AdminWidgetCredential) throws {
        guard credential.isValid else { throw APIProblem(code: "invalid_widget_session", message: "De widgetsessie is niet geldig.") }
        #if canImport(Security)
        guard let accessGroup else { throw APIProblem(code: "widget_keychain_unavailable", message: "De gedeelde widgetsleutelhanger is nog niet geconfigureerd.") }
        let data = try JSONCoding.encoder().encode(credential)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: "counts", kSecAttrAccessGroup as String: accessGroup]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        attributes[kSecAttrSynchronizable as String] = false
        guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else {
            throw APIProblem(code: "widget_keychain_unavailable", message: "De widgetsessie kon niet veilig worden opgeslagen.")
        }
        #else
        throw APIProblem(code: "widget_keychain_unavailable", message: "De gedeelde sleutelhanger is niet beschikbaar.")
        #endif
    }
    public static func read() -> AdminWidgetCredential? {
        #if canImport(Security)
        guard let accessGroup else { return nil }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: "counts", kSecAttrAccessGroup as String: accessGroup,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data,
              let credential = try? JSONCoding.decoder().decode(AdminWidgetCredential.self, from: data) else { return nil }
        guard credential.isValid else { clear(); return nil }
        return credential
        #else
        return nil
        #endif
    }
    public static func clear() {
        #if canImport(Security)
        guard let accessGroup else { return }
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: "counts", kSecAttrAccessGroup as String: accessGroup] as CFDictionary)
        #endif
    }
}

public enum AdminWidgetSnapshotStore {
    private static var fileURL: URL? {
        #if os(iOS) || os(macOS)
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.appGroup)?.appendingPathComponent("widget-admin-counts.json")
        #else
        return nil
        #endif
    }
    public static func save(_ summary: AdminWidgetSummary) {
        guard summary.isFresh(), let fileURL, let data = try? JSONCoding.encoder().encode(summary) else { return }
        #if os(iOS)
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try? data.write(to: fileURL, options: [.atomic])
        #endif
    }
    public static func read(at date: Date = .now) -> AdminWidgetSummary? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let summary = try? JSONCoding.decoder().decode(AdminWidgetSummary.self, from: data), summary.isFresh(at: date) else { return nil }
        return summary
    }
    public static func clear() { if let fileURL { try? FileManager.default.removeItem(at: fileURL) } }
}

public enum AdminWidgetRefresh {
    public static func fetch() async -> AdminWidgetSummary? {
        guard let credential = AdminWidgetCredentialStore.read() else { AdminWidgetSnapshotStore.clear(); return nil }
        let url = URL(string: "https://acc.salvemundi.nl/api/mobile/v1/admin/widget-activities")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        request.setValue("Bearer \(credential.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (data, rawResponse) = try await session.data(for: request)
            guard AdminWidgetCredentialStore.read()?.token == credential.token else { return nil }
            guard let response = rawResponse as? HTTPURLResponse else { return AdminWidgetSnapshotStore.read() }
            if response.statusCode == 401 || response.statusCode == 403 {
                AdminWidgetCredentialStore.clear(); AdminWidgetSnapshotStore.clear(); return nil
            }
            guard (200..<300).contains(response.statusCode),
                  let summary = try? JSONCoding.decoder().decode(APIEnvelope<AdminWidgetSummary>.self, from: data).data,
                  summary.isFresh() else { return AdminWidgetSnapshotStore.read() }
            // A simultaneous app logout/account switch must not restore old counts.
            guard AdminWidgetCredentialStore.read()?.token == credential.token else { return nil }
            AdminWidgetSnapshotStore.save(summary)
            return summary
        } catch { return AdminWidgetCredentialStore.read()?.token == credential.token ? AdminWidgetSnapshotStore.read() : nil }
    }
}
