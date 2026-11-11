import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import SalveMundiCore

struct CoreTests {
    @Test func pastActivitiesCloseRegistrationAndRespectEndDate() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for (start, end, past) in [(-100.0, Optional(-1.0), true), (-100.0, Optional(100.0), false), (-1.0, nil, true), (100.0, nil, false)] {
            let activity = Activity(id: "event:1", title: "Test", description: nil, startsAt: now.addingTimeInterval(start), endsAt: end.map { now.addingTimeInterval($0) }, location: nil, imageURL: nil, memberPriceCents: 0, guestPriceCents: 0, membersOnly: false, registrationDeadline: nil, capacity: nil, signupCount: nil, kind: "event", registrationViaWebsite: false, websiteURL: URL(string: "https://acc.salvemundi.nl/activiteiten/1")!)
            #expect(activity.isPast(at: now) == past)
            #expect(activity.registrationClosed(at: now) == past)
        }
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
