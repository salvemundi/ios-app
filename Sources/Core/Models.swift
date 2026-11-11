import Foundation

public struct Activity: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let description: String?
    public let startsAt: Date?
    public let endsAt: Date?
    public let location: String?
    public let imageURL: URL?
    public let memberPriceCents: Int
    public let guestPriceCents: Int
    public let membersOnly: Bool
    public let registrationDeadline: Date?
    public let capacity: Int?
    public let signupCount: Int?
    public let kind: String
    public let registrationViaWebsite: Bool?
    public let websiteURL: URL

    public func isPast(at date: Date = .now) -> Bool {
        (endsAt ?? startsAt).map { $0 <= date } ?? false
    }
    public var isFull: Bool { capacity.map { (signupCount ?? 0) >= $0 } ?? false }
    public func registrationClosed(at date: Date = .now) -> Bool {
        isPast(at: date) || isFull || (registrationDeadline.map { $0 <= date } ?? false)
    }
    public var price: String {
        memberPriceCents == 0 ? "Gratis" : (Decimal(memberPriceCents) / 100).formatted(.currency(code: "EUR"))
    }
}

public struct Ticket: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let startsAt: Date?
    public let location: String?
    public let qrToken: String?
    public let status: String
    public let kind: String
    public let activityID: String?

    public var isValid: Bool { ["paid", "confirmed", "completed", "free"].contains(status.lowercased()) }
    public var statusLabel: String {
        switch status.lowercased() {
        case "paid", "confirmed", "completed", "free": "Bevestigd"
        case "open", "pending": "Betaling in behandeling"
        case "canceled", "cancelled": "Geannuleerd"
        case "expired": "Verlopen"
        case "failed": "Betaling mislukt"
        default: "Status onbekend"
        }
    }
}

public struct MemberProfile: Codable, Sendable {
    public let id: String
    public let name: String
    public let email: String
    public let firstName: String
    public let lastName: String
    public let phoneNumber: String?
    public let membershipStatus: String?
    public let membershipExpiry: Date?
    public var isActiveMember: Bool { membershipStatus == "active" }
}

public struct ProfileUpdate: Codable, Sendable {
    public var phoneNumber: String
}

public struct Registration: Codable, Sendable {
    public let registrationID: String
    public let checkoutURL: URL?
    public let status: String
}

public struct NotificationPreferences: Codable, Equatable, Sendable {
    public var registrations: Bool = true
    public var payments: Bool = true
    public var eventChanges: Bool = true
    public var reminders: Bool = true
    public init() {}
}

public struct AppSession: Codable, Sendable {
    public let token: String
    public let expiresAt: Date
    public var isExpired: Bool { expiresAt <= .now }
}

public struct APIEnvelope<Value: Decodable & Sendable>: Decodable, Sendable {
    public let data: Value
}

public struct APIProblem: Codable, Error, LocalizedError, Sendable {
    public let code: String
    public let message: String
    public var errorDescription: String? { message }
    public init(code: String, message: String) { self.code = code; self.message = message }
}

public enum JSONCoding {
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value) { return date }
            // Membership records may be calendar dates rather than timestamps.
            let dateOnly = DateFormatter()
            dateOnly.locale = Locale(identifier: "en_US_POSIX")
            dateOnly.timeZone = TimeZone(secondsFromGMT: 0)
            dateOnly.dateFormat = "yyyy-MM-dd"
            if let date = dateOnly.date(from: value) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid ISO date"))
        }
        return decoder
    }
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
