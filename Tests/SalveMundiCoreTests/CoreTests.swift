import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import SalveMundiCore

struct CoreTests {
    @Test func legacyNotificationPreferencesKeepNewSubscriptionsOptIn() throws {
        let old = Data(#"{"registrations":true,"payments":false,"eventChanges":true,"reminders":false}"#.utf8)
        let value = try JSONCoding.decoder().decode(NotificationPreferences.self, from: old)
        #expect(!value.payments)
        #expect(!value.reminders)
        #expect(!value.activityAnnouncements)
        #expect(value.activityCommitteeIDs.isEmpty)
        #expect(!value.organizerAlmostFull)
        #expect(value.organizerCapacityPercent == 90)
        #expect(value.organizerSignupThresholds.isEmpty)
    }

    @Test func notificationCommitteeAndOrganizerChoicesRoundTrip() throws {
        var value = NotificationPreferences()
        value.activityAnnouncements = true
        value.activityCommitteeIDs = [2, 7]
        value.organizerAlmostFull = true
        value.organizerCapacityPercent = 85
        value.organizerSignupThresholds = [10, 25, 50]
        let decoded = try JSONCoding.decoder().decode(NotificationPreferences.self, from: JSONCoding.encoder().encode(value))
        #expect(decoded == value)
        let options = try JSONCoding.decoder().decode(NotificationOptions.self, from: Data(#"{"committees":[{"id":2,"name":"Feest"}],"organizerCommittees":[],"canReceiveOrganizerAlerts":false}"#.utf8))
        #expect(options.committees.first?.id == 2)
        #expect(!options.canReceiveOrganizerAlerts)
        #expect(options.organizerCommittees.isEmpty)
    }

    @Test func pastActivitiesCloseRegistrationAndRespectEndDate() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for (start, end, past) in [(-100.0, Optional(-1.0), true), (-100.0, Optional(100.0), false), (-1.0, nil, true), (100.0, nil, false)] {
            let activity = Activity(id: "event:1", title: "Test", description: nil, startsAt: now.addingTimeInterval(start), endsAt: end.map { now.addingTimeInterval($0) }, location: nil, imageURL: nil, memberPriceCents: 0, guestPriceCents: 0, membersOnly: false, registrationDeadline: nil, capacity: nil, signupCount: nil, kind: "event", registrationViaWebsite: false, websiteURL: URL(string: "https://acc.salvemundi.nl/activiteiten/1")!)
            #expect(activity.isPast(at: now) == past)
            #expect(activity.registrationClosed(at: now) == past)
        }
    }

    @Test func doorModeTreatsTodayAsNotPast() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 23, minute: 30))!
        func make(_ start: Date, _ end: Date?) -> Activity {
            Activity(id: "event:1", title: "Test", description: nil, startsAt: start, endsAt: end, location: nil, imageURL: nil, memberPriceCents: 0, guestPriceCents: 0, membersOnly: false, registrationDeadline: nil, capacity: nil, signupCount: nil, kind: "event", registrationViaWebsite: false, websiteURL: URL(string: "https://acc.salvemundi.nl/activiteiten/1")!)
        }
        let tonight = make(calendar.date(byAdding: .hour, value: -4, to: now)!, nil)
        #expect(tonight.isPast(at: now) && !tonight.endedBeforeToday(at: now, calendar: calendar) && tonight.isToday(at: now, calendar: calendar))
        let yesterday = make(calendar.date(byAdding: .day, value: -1, to: now)!, nil)
        #expect(yesterday.endedBeforeToday(at: now, calendar: calendar) && !yesterday.isToday(at: now, calendar: calendar))
        let multiDay = make(calendar.date(byAdding: .day, value: -2, to: now)!, calendar.date(byAdding: .day, value: 1, to: now)!)
        #expect(multiDay.isToday(at: now, calendar: calendar) && !multiDay.endedBeforeToday(at: now, calendar: calendar))
    }

    @Test func dateFormatsAndActivityAvailability() throws {
        let json = """
        {"id":"event:12","title":"Borrel","startsAt":"2027-01-10T12:00:00.123Z","memberPriceCents":0,"guestPriceCents":250,"membersOnly":true,"registrationDeadline":"2027-01-09T12:00:00Z","capacity":20,"signupCount":20,"kind":"event","websiteURL":"https://acc.salvemundi.nl/activiteiten/12"}
        """
        let activity = try JSONCoding.decoder().decode(Activity.self, from: Data(json.utf8))
        #expect(activity.startsAt != nil)
        #expect(activity.isFull)
        #expect(activity.registrationClosed(at: .distantPast))
        #expect(activity.price == "Gratis")
    }

    @Test func ticketPaymentRulesDoNotShowUnconfirmedQR() throws {
        for status in ["open", "failed", "expired", "canceled", "unknown"] {
            let json = "{\"id\":\"event:1\",\"title\":\"Test\",\"qrToken\":\"secret\",\"status\":\"\(status)\",\"kind\":\"event\"}"
            #expect(try !JSONCoding.decoder().decode(Ticket.self, from: Data(json.utf8)).isValid)
        }
    }

    @Test func deepLinksOnlyAcceptTrustedOrigins() {
        #expect(DeepLink(url: URL(string: "https://evil.example/activities/event:123")!) == nil)
        #expect(DeepLink(url: URL(string: "https://salvemundi.nl/activiteiten/123")!) == nil)
        #expect(DeepLink(url: URL(string: "https://acc.salvemundi.nl/activiteiten/123-borrel")!) == .activity("event:123"))
        #expect(DeepLink(url: URL(string: "salvemundi://activities/event:123")!) == .activity("event:123"))
        #expect(DeepLink(url: URL(string: "salvemundi://tickets")!) == .tickets)
        #expect(DeepLink(url: URL(string: "salvemundi://activities")!) == .activities)
        #expect(DeepLink(url: URL(string: "https://acc.salvemundi.nl/activiteiten")!) == .activities)
        #expect(DeepLink(url: URL(string: "https://acc.salvemundi.nl/activiteiten/bevestiging?id=2")!) == .paymentReturn)
    }

    @Test func widgetSnapshotNeverContainsTicketOrAuthSecrets() throws {
        let snapshot = WidgetSnapshot(events: [.init(id: "event:12", title: "Borrel", startsAt: .now, location: "Eindhoven")], nextBooking: nil, signedIn: false)
        let encoded = try JSONCoding.encoder().encode(snapshot)
        let text = String(decoding: encoded, as: UTF8.self)
        #expect(!text.contains("qrToken"))
        #expect(!text.contains("token"))
        let decoded = try JSONCoding.decoder().decode(WidgetSnapshot.self, from: encoded)
        #expect(decoded.nextBooking == nil)
        #expect(!decoded.signedIn)
    }

    @Test func membershipDateOnlyDecode() throws {
        let json = "{\"id\":\"1\",\"name\":\"Test Lid\",\"email\":\"test@example.invalid\",\"firstName\":\"Test\",\"lastName\":\"Lid\",\"membershipExpiry\":\"2027-08-31\"}"
        let member = try JSONCoding.decoder().decode(MemberProfile.self, from: Data(json.utf8))
        #expect(member.membershipExpiry != nil)
        #expect(!member.isActiveMember)
    }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let unauthorized = request.value(forHTTPHeaderField: "Authorization") == "Bearer expired"
        let unavailable = url.host == "disabled.example.invalid"
        let missingActivity = url.path == "/api/mobile/v1/activities/event:404"
        let status = unauthorized ? 401 : unavailable || missingActivity ? 404 : 200
        let json: String
        if request.httpMethod == "HEAD" {
            json = "" // HEAD must not depend on JSON response bodies.
        } else if unauthorized {
            json = "{\"error\":{\"code\":\"unauthorized\",\"message\":\"Log opnieuw in.\"}}"
        } else if unavailable || missingActivity {
            json = "{\"error\":{\"code\":\"not_found\",\"message\":\"Niet gevonden.\"}}"
        } else {
            json = "{\"data\":{\"success\":true}}"
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

struct APIClientTests {
    private func client(scheme: String = "https", host: String = "acc.salvemundi.nl") -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return APIClient(baseURL: URL(string: "\(scheme)://\(host)")!, session: URLSession(configuration: config))
    }
    @Test func decodesUnauthorizedProblem() async throws {
        do {
            let _: MutationAcknowledgement = try await client().request("me", token: "expired")
            Issue.record("Expired credentials must be rejected")
        } catch let problem as APIProblem { #expect(problem.code == "unauthorized"); #expect(problem.message == "Log opnieuw in.") }
    }
    @Test func rejectsPlainHTTP() async throws {
        do {
            let _: MutationAcknowledgement = try await client(scheme: "http").request("activities")
            Issue.record("HTTP is forbidden")
        } catch let problem as APIProblem { #expect(problem.code == "invalid_server") }
    }
    @Test func supportsCompositeActivityIDs() async throws {
        let response: MutationAcknowledgement = try await client().mutation("activities/event:123/registrations", token: "valid", value: EmptyPayload())
        #expect(response.success)
    }
    @Test func unavailableCollectionHasHelpfulConnectionError() async throws {
        do {
            let _: [Activity] = try await client(host: "disabled.example.invalid").request("activities")
            Issue.record("A disabled collection endpoint must explain backend availability")
        } catch let problem as APIProblem {
            #expect(problem.code == "backend_unavailable")
            #expect(problem.message.contains("acceptatieomgeving"))
        }
    }
    @Test func availabilityPreflightRecognizesBodyless404() async throws {
        do {
            try await client(host: "disabled.example.invalid").checkAvailability()
            Issue.record("The authentication browser must not open for a disabled API")
        } catch let problem as APIProblem { #expect(problem.code == "backend_unavailable") }
    }
    @Test func availabilityPreflightAcceptsBodylessSuccess() async throws {
        try await client().checkAvailability()
    }
    @Test func missingActivityRetainsNotFound() async throws {
        do {
            let _: Activity = try await client().request("activities/event:404")
            Issue.record("A missing activity should fail")
        } catch let problem as APIProblem {
            #expect(problem.code == "not_found")
            #expect(problem.message == "Niet gevonden.")
        }
    }

}

@Suite struct DoorAndRoutingTests {
    private func activity(_ id: String, start: Date, end: Date? = nil) -> Activity {
        Activity(id: id, title: "Act \(id)", description: nil, startsAt: start, endsAt: end, location: nil, imageURL: nil, memberPriceCents: 0, guestPriceCents: 0, membersOnly: false, registrationDeadline: nil, capacity: nil, signupCount: nil, kind: "event", registrationViaWebsite: false, websiteURL: URL(string: "https://acc.salvemundi.nl/activiteiten/1")!)
    }
    private func admin(_ activity: Activity, canCheckIn: Bool = true) throws -> AdminActivity {
        let data = try JSONCoding.encoder().encode(activity)
        let json = #"{"activity":"# + String(decoding: data, as: UTF8.self) + #","status":"published","committeeID":null,"committeeName":null,"confirmedCount":10,"pendingCount":0,"checkedInCount":4,"canEdit":false,"canDelete":false,"canManageSignups":false,"canCheckIn":\#(canCheckIn)}"#
        return try JSONCoding.decoder().decode(AdminActivity.self, from: Data(json.utf8))
    }

    @Test func doorGroupsSplitTodayUpcomingAndRecentPast() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 22))!
        let day: (Int) -> Date = { calendar.date(byAdding: .day, value: $0, to: now)! }
        let items = try [admin(activity("event:1", start: day(0).addingTimeInterval(-7200))), admin(activity("event:2", start: day(3))),
                         admin(activity("event:3", start: day(-3))), admin(activity("event:4", start: day(-40))), admin(activity("event:5", start: day(0)), canCheckIn: false)]
        let groups = DoorGroups(items, now: now, calendar: calendar)
        #expect(groups.today.map(\.id) == ["event:1"])
        #expect(groups.autoSelected?.id == "event:1")
        #expect(groups.upcoming.map(\.id) == ["event:2"])
        #expect(groups.past.map(\.id) == ["event:3"])
        #expect(DoorGroups(items, search: "event:4", now: now, calendar: calendar).past.map(\.id) == ["event:4"])
    }

    @Test func pendingScanQueueDedupesAndCounts() throws {
        var queue = PendingScanQueue()
        let first = queue.enqueue(PendingScan(activityID: "event:1", token: "a"))
        let duplicate = queue.enqueue(PendingScan(activityID: "event:1", token: "a"))
        let otherActivity = queue.enqueue(PendingScan(activityID: "event:2", token: "a"))
        #expect(first && !duplicate && otherActivity)
        #expect(queue.count(for: "event:1") == 1)
        let id = queue.items(for: "event:1")[0].id
        queue.remove(id)
        #expect(queue.items.count == 1)
        let decoded = try JSONCoding.decoder().decode(PendingScanQueue.self, from: JSONCoding.encoder().encode(queue))
        // Dates are stored with second precision, so compare identity rather than exact timestamps.
        #expect(decoded.items.map(\.id) == queue.items.map(\.id) && decoded.items.map(\.token) == queue.items.map(\.token))
    }

    @Test func notificationRoutesByKind() {
        func route(_ payload: [AnyHashable: Any]) -> DeepLink? { NotificationRoute.destination(payload).flatMap { DeepLink(url: $0) } }
        #expect(route(["activityID": "event:7", "kind": "organizerAlmostFull"]) == .adminActivities("event:7"))
        #expect(route(["activityID": "event:7", "kind": "payments"]) == .ticketForActivity("event:7"))
        #expect(route(["activityID": "event:7", "kind": "activityAnnouncements"]) == .activity("event:7"))
        #expect(route(["activityID": "event:7"]) == .activity("event:7"))
        #expect(route(["url": "salvemundi://tickets"]) == .tickets)
        #expect(route(["activityID": "../evil", "kind": "payments"]) == nil)
        #expect(route(["url": "https://evil.example/x"]) == nil)
    }

    @Test func ticketWindowCoversBeforeAndAfterStart() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(TicketWindow.isNear(start: start, now: start.addingTimeInterval(-3600)))
        #expect(TicketWindow.isNear(start: start, now: start.addingTimeInterval(7200)))
        #expect(!TicketWindow.isNear(start: start, now: start.addingTimeInterval(-3 * 3600)))
        #expect(!TicketWindow.isNear(start: start, now: start.addingTimeInterval(4 * 3600)))
        #expect(!TicketWindow.isNear(start: nil))
    }
}
