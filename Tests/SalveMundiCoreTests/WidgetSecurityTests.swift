import Foundation
import Testing
@testable import SalveMundiCore

struct WidgetSecurityTests {
    @Test func oldWidgetSnapshotStillDecodesWithoutAdminFields() throws {
        let json = "{\"updatedAt\":\"2026-11-10T12:00:00Z\",\"events\":[],\"signedIn\":false}"
        let snapshot = try JSONCoding.decoder().decode(WidgetSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.adminSummary == nil)
        #expect(snapshot.nextBooking == nil)
    }
    @Test func countsExpireAfterFifteenMinutesEvenWithLongerServerDeadline() {
        let now = Date(timeIntervalSince1970: 1800000000)
        let summary = AdminWidgetSummary(items: [], fetchedAt: now, expiresAt: now.addingTimeInterval(86400))
        #expect(summary.isFresh(at: now.addingTimeInterval(899)))
        #expect(!summary.isFresh(at: now.addingTimeInterval(900)))
        #expect(summary.displayDeadline == now.addingTimeInterval(900))
        #expect(!summary.isFresh(at: now.addingTimeInterval(-120)))
    }
    @Test func countsNeverContainParticipantOrAuthenticationFields() throws {
        let summary = AdminWidgetSummary(items: [.init(id: "event:12", title: "Testactiviteit", startsAt: nil,
            confirmedCount: 14, pendingCount: 2, checkedInCount: 5, capacity: 30)], expiresAt: .now.addingTimeInterval(900))
        let json = try #require(JSONSerialization.jsonObject(with: JSONCoding.encoder().encode(summary)) as? [String: Any])
        let items = try #require(json["items"] as? [[String: Any]])
        #expect(Set(items[0].keys) == Set(["id", "title", "confirmedCount", "pendingCount", "checkedInCount", "capacity"]))
        let text = String(decoding: try JSONCoding.encoder().encode(summary), as: UTF8.self)
        for forbidden in ["token", "email", "phone", "qrToken", "participants", "registrations"] { #expect(!text.contains(forbidden)) }
    }
    @Test func fullNativeCredentialsCannotBeStoredAsWidgetCredentials() {
        #expect(!AdminWidgetCredential(token: "smi_" + String(repeating: "A", count: 43), expiresAt: .now.addingTimeInterval(900)).isValid)
        #expect(AdminWidgetCredential(token: "smw_" + String(repeating: "A", count: 43), expiresAt: .now.addingTimeInterval(900)).isValid)
        #expect(!AdminWidgetCredential(token: "smw_" + String(repeating: "A", count: 43), expiresAt: .distantPast).isValid)
    }
    @Test func privateDefaultKeychainGroupPrecedesSharedCountsGroup() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for target in ["App", "Widgets"] {
            let data = try Data(contentsOf: root.appendingPathComponent("Configuration/\(target).entitlements"))
            let plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
            let groups = try #require(plist["keychain-access-groups"] as? [String])
            #expect(groups == ["$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)", "$(AppIdentifierPrefix)nl.salvemundi.ios.shared"])
        }
    }
    @Test func adminWidgetLinksOnlyOpenAuthorizedAppScreens() {
        let activity = AdminWidgetActivity(id: "event:12", title: "Test", startsAt: nil, confirmedCount: 0, pendingCount: 0, checkedInCount: 0, capacity: nil)
        #expect(activity.deepLink?.absoluteString == "salvemundi://admin/activities/event:12")
    }
}

@Test func liveEventCardLimitsTimeAndContainsNoTicketSecrets() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let event = Activity(id: "event:42", title: "Borrel", description: nil, startsAt: now.addingTimeInterval(3600), endsAt: now.addingTimeInterval(7200), location: "Fontys", imageURL: nil, memberPriceCents: 0, guestPriceCents: 0, membersOnly: true, registrationDeadline: nil, capacity: nil, signupCount: nil, kind: "event", registrationViaWebsite: false, websiteURL: URL(string: "https://acc.salvemundi.nl/activiteiten/42")!)
    let ticket = Ticket(id: "event:12", title: "Borrel", startsAt: event.startsAt, location: "Fontys", qrToken: "NEVER-SHARE-THIS-SECRET", status: "paid", kind: "event", activityID: event.id)
    let value = try #require(EventLiveSnapshot.make(ticket: ticket, activity: event, at: now))
    #expect(value.expiresAt == event.endsAt)
    #expect(DeepLink(url: try #require(value.deepLink)) == .ticket(ticket.id))
    let data = try JSONCoding.encoder().encode(value)
    #expect(!String(decoding: data, as: UTF8.self).contains("NEVER-SHARE"))
    #expect(EventLiveSnapshot.make(ticket: ticket, activity: event, at: now.addingTimeInterval(-5 * 3600)) == nil)
    #expect(EventLiveSnapshot.make(ticket: ticket, activity: event, at: now.addingTimeInterval(7200)) == nil)
    #expect(EventLiveSnapshot.make(ticket: ticket, activity: event, at: now, expiresNoLaterThan: now) == nil)
    let unpaid = Ticket(id: ticket.id, title: ticket.title, startsAt: ticket.startsAt, location: ticket.location, qrToken: nil, status: "open", kind: "event", activityID: event.id)
    #expect(EventLiveSnapshot.make(ticket: unpaid, activity: event, at: now) == nil)
}
