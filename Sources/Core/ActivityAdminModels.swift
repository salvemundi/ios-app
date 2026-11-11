import Foundation

public struct ActivityAdminAccess: Codable, Sendable {
    public let canAccess: Bool
    public let canCreate: Bool
    public let scopeVersion: String?
}

public struct AdminCommittee: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public let email: String?
}

public struct AdminActivity: Codable, Identifiable, Hashable, Sendable {
    public let activity: Activity
    public let status: String
    public let committeeID: Int?
    public let committeeName: String?
    public let confirmedCount: Int
    public let pendingCount: Int
    public let checkedInCount: Int
    public let canEdit: Bool
    public let canDelete: Bool
    public let canManageSignups: Bool
    public let canCheckIn: Bool
    public var id: String { activity.id }
    public var statusLabel: String { switch status { case "draft": "Concept"; case "scheduled": "Ingepland"; default: "Gepubliceerd" } }
}

public struct AdminActivityCollection: Codable, Sendable {
    public let activities: [AdminActivity]
    public let committees: [AdminCommittee]
    public let canCreate: Bool
    public let canAssignNoCommittee: Bool?
}

public struct AdminActivityDetail: Codable, Sendable {
    public let summary: AdminActivity
    public let form: AdminActivityForm
}

public struct AdminActivityForm: Codable, Sendable {
    public var title = ""
    public var description = ""
    public var shortDescription: String?
    public var memberDescription: String?
    public var startsOn = AdminCalendar.day(.now)
    public var startTime: String?
    public var endsOn: String?
    public var endTime: String?
    public var location: String?
    public var capacity: Int?
    public var memberPriceCents = 0
    public var guestPriceCents = 0
    public var membersOnly = false
    public var committeeID: Int?
    public var contactEmail: String?
    public var registrationDeadline: String?
    public var publishAt: String?
    public var status = "draft"
    public var externalSignupURL: String?
    public var removeImage: Bool? = false
    public init() {}
}

public struct AdminRegistration: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let email: String
    public let phone: String?
    public let status: String
    public let amountPaidCents: Int?
    public let createdAt: String?
    public let checkedIn: Bool
    public let isMember: Bool
    public var isPaid: Bool { status == "paid" }
    public var statusLabel: String {
        switch status { case "paid": "Betaald"; case "open", "pending": "Openstaand"; case "failed": "Mislukt"; case "canceled", "cancelled": "Geannuleerd"; case "expired": "Verlopen"; default: status }
    }
    public func matches(_ query: String) -> Bool { query.isEmpty || name.localizedCaseInsensitiveContains(query) || email.localizedCaseInsensitiveContains(query) }
}

public struct AdminRegistrations: Codable, Sendable {
    public let activity: AdminActivity
    public let registrations: [AdminRegistration]
    public func recipientCount(paidOnly: Bool) -> Int {
        Set(registrations.filter { !paidOnly || $0.isPaid }.map { $0.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }).count
    }
}

public struct AdminMember: Codable, Identifiable, Sendable {
    public let id: String
    public let firstName: String
    public let lastName: String
    public let email: String
    public let membershipStatus: String?
    public var name: String { "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces) }
}

public struct AdminManualRegistration: Encodable, Sendable {
    public let type: String
    public let memberID: String?
    public let name: String?
    public let email: String?
    public let phone: String?
}

public struct AdminCheckIn: Codable, Sendable { public let checkedIn: Bool }
public struct AdminScanRequest: Codable, Sendable { public let token: String }
public struct AdminScanResult: Codable, Sendable {
    public let registration: AdminRegistration
    public let alreadyCheckedIn: Bool
}
public struct AdminMessage: Codable, Sendable { public let subject: String; public let message: String; public let paidOnly: Bool }
public struct AdminMessageResult: Codable, Sendable { public let success: Bool; public let recipientCount: Int }

public enum AdminCalendar {
    public static let timeZone = TimeZone(identifier: "Europe/Amsterdam")!
    public static func day(_ date: Date) -> String { formatter("yyyy-MM-dd").string(from: date) }
    public static func time(_ date: Date) -> String { formatter("HH:mm").string(from: date) }
    public static func date(day: String, time: String? = nil) -> Date? { formatter("yyyy-MM-dd HH:mm").date(from: "\(day) \(time ?? "12:00")") }
    public static func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    public static func fromISO(_ value: String?) -> Date? {
        guard let value else { return nil }
        let full = ISO8601DateFormatter(); full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return full.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = timeZone; formatter.dateFormat = format; formatter.isLenient = false
        return formatter
    }
}

public enum AdminExport {
    public static func csv(_ registrations: [AdminRegistration]) -> Data {
        let header = ["Naam", "E-mail", "Telefoon", "Status", "Aanwezig", "Lid", "Betaald (cent)"]
        let rows = registrations.map { [$0.name, $0.email, $0.phone ?? "", $0.statusLabel, $0.checkedIn ? "Ja" : "Nee", $0.isMember ? "Ja" : "Nee", $0.amountPaidCents.map(String.init) ?? ""] }
        return Data(("\u{feff}" + ([header] + rows).map { $0.map(csvCell).joined(separator: ";") }.joined(separator: "\r\n")).utf8)
    }
    private static func csvCell(_ value: String) -> String {
        let dangerous = value.first.map { "\t\r".contains($0) } == true || value.drop(while: { $0.isWhitespace }).first.map { "=+-@".contains($0) } == true
        let safe = dangerous ? "'" + value : value
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

// Suppress a code while it remains in view; don't consume the next ticket while a popup is visible.
public struct AdminScanGate: Sendable {
    private var lastToken: String?
    private var lastSeen = Date.distantPast
    public init() {}
    public mutating func accept(_ token: String, enabled: Bool, at now: Date = .now) -> Bool {
        let repeated = token == lastToken && now.timeIntervalSince(lastSeen) < 2
        if token == lastToken { lastSeen = now }
        guard enabled, !token.isEmpty, !repeated else { return false }
        lastToken = token; lastSeen = now
        return true
    }
}
