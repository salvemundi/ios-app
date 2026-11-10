import Foundation
import Testing
@testable import SalveMundiCore

struct ActivityAdminTests {
    @Test func adminLinksValidateActivityIDAndAcceptanceOrigin() {
        #expect(DeepLink(url: URL(string: "salvemundi://admin/activities")!) == .adminActivities(nil))
        #expect(DeepLink(url: URL(string: "salvemundi://admin/activities/event:123")!) == .adminActivities("event:123"))
        #expect(DeepLink(url: URL(string: "salvemundi://admin/activities/123")!) == .adminActivities("event:123"))
        #expect(DeepLink(url: URL(string: "salvemundi://admin/activities/event:abc")!) == nil)
        #expect(DeepLink(url: URL(string: "salvemundi://admin/activities/event:")!) == nil)
        #expect(DeepLink(url: URL(string: "https://salvemundi.nl/admin/activities/event:123")!) == nil)
    }
    @Test func amsterdamCalendarMaintainsLocalDateAcrossDST() throws {
        let summer = try #require(ISO8601DateFormatter().date(from: "2026-07-01T18:30:00Z"))
        let winter = try #require(ISO8601DateFormatter().date(from: "2026-01-01T18:30:00Z"))
        #expect(AdminCalendar.time(summer) == "20:30")
        #expect(AdminCalendar.time(winter) == "19:30")
        #expect(AdminCalendar.day(try #require(AdminCalendar.date(day: "2026-03-29", time: "12:00"))) == "2026-03-29")
    }
    @Test func mailRecipientCountDeduplicatesWithoutExpandingBeyondActivity() throws {
        let registration = """
        {"activity":{"activity":{"id":"event:1","title":"Test","memberPriceCents":0,"guestPriceCents":0,"membersOnly":false,"kind":"event","websiteURL":"https://acc.salvemundi.nl/activiteiten/1"},"status":"published","confirmedCount":2,"pendingCount":1,"checkedInCount":0,"canEdit":false,"canDelete":false,"canManageSignups":false,"canCheckIn":true},"registrations":[{"id":"1","name":"Robin","email":"Robin@example.invalid","status":"paid","checkedIn":false,"isMember":true},{"id":"2","name":"Robin","email":" robin@example.invalid ","status":"paid","checkedIn":false,"isMember":true},{"id":"3","name":"Gast","email":"guest@example.invalid","status":"open","checkedIn":false,"isMember":false}]}
        """
        let value = try JSONCoding.decoder().decode(AdminRegistrations.self, from: Data(registration.utf8))
        #expect(value.recipientCount(paidOnly: true) == 1)
        #expect(value.recipientCount(paidOnly: false) == 2)
        #expect(!value.activity.canManageSignups)
        #expect(value.activity.canCheckIn)
    }
    @Test func csvNeutralizesUntrustedSpreadsheetCellsAndQuotes() throws {
        let registrations = [AdminRegistration(id: "1", name: #"=HYPERLINK("bad")"#, email: "test@example.invalid", phone: "+31612345678", status: "paid", amountPaidCents: nil, createdAt: nil, checkedIn: true, isMember: true)]
        let csv = String(decoding: AdminExport.csv(registrations), as: UTF8.self)
        #expect(csv.contains(#""'=HYPERLINK(""bad"")""#))
        #expect(csv.contains(#""'+31612345678""#))
        #expect(csv.hasPrefix("\u{feff}"))
    }
    @Test func draftCreationPreservesOptionalCapacityAndPublication() throws {
        var form = AdminActivityForm(); form.title = "Concept"; form.description = "Test"
        let encoded = try JSONCoding.encoder().encode(form)
        let decoded = try JSONCoding.decoder().decode(AdminActivityForm.self, from: encoded)
        #expect(decoded.status == "draft")
        #expect(decoded.publishAt == nil)
        #expect(decoded.capacity == nil)
        #expect(decoded.memberPriceCents == 0)
    }
}
