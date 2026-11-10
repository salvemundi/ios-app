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
