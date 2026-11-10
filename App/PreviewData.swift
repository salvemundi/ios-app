#if DEBUG
import Foundation

enum PreviewData {
    static let activities: [Activity] = {
        let json = """
        [
          {"id":"event:90001","title":"Donderdagborrel","description":"Samen de week afsluiten met je studiegenoten. Kom langs voor een gezellige avond bij Salve Mundi.","startsAt":"2027-01-14T16:00:00Z","endsAt":"2027-01-14T20:00:00Z","location":"De Salve Mundi ruimte","memberPriceCents":0,"guestPriceCents":250,"membersOnly":false,"capacity":80,"signupCount":32,"kind":"event","websiteURL":"https://acc.salvemundi.nl/activiteiten"},
          {"id":"event:90002","title":"Game night","description":"Van bordspellen tot je favoriete partygame: er is voor iedereen een plek aan tafel.","startsAt":"2027-01-21T18:00:00Z","location":"Fontys ICT, Eindhoven","memberPriceCents":250,"guestPriceCents":500,"membersOnly":false,"kind":"event","websiteURL":"https://acc.salvemundi.nl/activiteiten"},
          {"id":"event:90003","title":"Samen op avontuur","description":"Een middag vol verrassingen met de vereniging.","startsAt":"2027-02-04T12:00:00Z","location":"Eindhoven","memberPriceCents":1200,"guestPriceCents":1800,"membersOnly":true,"kind":"event","websiteURL":"https://acc.salvemundi.nl/activiteiten"}
        ]
        """
        return (try? JSONCoding.decoder().decode([Activity].self, from: Data(json.utf8))) ?? []
    }()
    static let profile: MemberProfile = try! JSONCoding.decoder().decode(MemberProfile.self, from: Data("""
        {"id":"demo-member","name":"Robin Salve","email":"robin@example.invalid","firstName":"Robin","lastName":"Salve","phoneNumber":"","membershipStatus":"active","membershipExpiry":"2027-08-31"}
        """.utf8))
    static let tickets: [Ticket] = try! JSONCoding.decoder().decode([Ticket].self, from: Data("""
        [{"id":"event:demo","title":"Donderdagborrel","startsAt":"2027-01-14T16:00:00Z","location":"De Salve Mundi ruimte","qrToken":"SALVE-MUNDI-DEMO-NOT-VALID","status":"confirmed","kind":"event","activityID":"event:90001"}]
        """.utf8))
}
#endif
