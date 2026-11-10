import Foundation

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
    public init(updatedAt: Date = .now, events: [WidgetEvent], nextBooking: WidgetEvent?, signedIn: Bool) {
        self.updatedAt = updatedAt; self.events = events; self.nextBooking = nextBooking; self.signedIn = signedIn
    }
    public static let empty = WidgetSnapshot(events: [], nextBooking: nil, signedIn: false)
    public static let appGroup = "group.nl.salvemundi.ios"
    public static let fileName = "widget-summary.json"
}
