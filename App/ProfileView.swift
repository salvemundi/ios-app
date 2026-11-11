import SwiftUI

struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @State private var editing = false
    @State private var confirmLogout = false
    var body: some View {
        Group {
            if let profile = model.profile, model.signedIn {
                Form {
                    Section {
                        VStack(spacing: 12) {
                            Text(String(profile.firstName.prefix(1)) + String(profile.lastName.prefix(1))).font(.largeTitle.bold()).foregroundStyle(Brand.purple).frame(width: 86, height: 86).background(Brand.purple.opacity(0.1), in: Circle())
                            Text(profile.name).font(.title2.bold())
                            Text(profile.email).font(.subheadline).foregroundStyle(.secondary)
                            Label(profile.isActiveMember ? "Actief lid" : "Lidmaatschap", systemImage: "checkmark.seal.fill").font(.caption.bold()).padding(.horizontal, 14).padding(.vertical, 8).background(Brand.gold.opacity(0.3), in: Capsule()).foregroundStyle(Brand.purple)
                            if let expiry = profile.membershipExpiry { Text("Geldig tot \(expiry.formatted(.dateTime.day().month().year()))").font(.caption).foregroundStyle(.secondary) }
                        }.frame(maxWidth: .infinity).padding(.vertical, 16)
                        Button { editing = true } label: { Label("Mijn gegevens wijzigen", systemImage: "pencil") }
                    }
                    if model.canAdminActivities {
                        Section("Beheer") {
                            Button { Task { await model.openActivityAdministration() } } label: { Label("Activiteiten beheren", systemImage: "calendar.badge.gearshape") }
                        }
                    }
                    Section("Meldingen") {
                        Text(model.notificationStatus).font(.footnote).foregroundStyle(.secondary)
                        if !model.notificationPreferencesAvailable { Text("Meldingsvoorkeuren zijn nog niet geladen. Ververs de app en probeer het opnieuw.").font(.caption).foregroundStyle(.secondary) }
                        Button { Task { await model.enableNotifications() } } label: { Label("Meldingen op deze iPhone inschakelen", systemImage: "bell.badge") }
                        preference("Inschrijvingen", keyPath: \.registrations)
                        preference("Betalingen", keyPath: \.payments)
                        preference("Wijzigingen van activiteiten", keyPath: \.eventChanges)
                        preference("Herinnering 24 uur vooraf", keyPath: \.reminders)
                        Button("Open iPhone-instellingen") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }.font(.subheadline)
                    }
                    Section("Meer van Salve Mundi") {
                        webLink("Mijn lidmaatschap", icon: "person.crop.circle.badge.checkmark", path: "lidmaatschap")
                        webLink("Reizen", icon: "suitcase.rolling", path: "reis")
                        webLink("Intro", icon: "sun.max", path: "intro")
                        webLink("Merchandise", icon: "tshirt", path: "merch")
                        webLink("Pizza", icon: "fork.knife", path: "pizza")
                        webLink("Commissies en clubs", icon: "person.3", path: "commissies")
                    }
                    Section {
                        webLink("Privacy en contact", icon: "hand.raised", path: "contact")
                        Button("Uitloggen", role: .destructive) { confirmLogout = true }
                    } footer: { VStack(alignment: .leading, spacing: 8) { Text("Salve Mundi voor iPhone · \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")"); Text("Acceptatieomgeving · gegevens en functies kunnen nog veranderen.") } }
                }
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        Image("Brand").renderingMode(.template).resizable().scaledToFit().frame(width: 180).foregroundStyle(Brand.purple).padding(.vertical, 36)
                        EmptyState(icon: "person.crop.circle", title: "Welkom bij de club", message: "Met je bestaande Salve Mundi account heb je je activiteiten, tickets en lidmaatschap altijd bij je.")
                        Button { Task { await model.signIn() } } label: { HStack { if model.isSigningIn { ProgressView().tint(.white) }; Text("Inloggen met Microsoft") } }.buttonStyle(PrimaryButtonStyle()).disabled(model.isSigningIn)
                        Link("Nog geen lid? Bekijk het lidmaatschap", destination: model.server.appendingPathComponent("lidmaatschap")).font(.subheadline)
                    }.padding(20)
                }.background(Brand.background)
            }
        }
        .navigationTitle("Profiel")
        .sheet(isPresented: $editing) { if let profile = model.profile { NavigationStack { EditProfileView(profile: profile) } } }
        .confirmationDialog("Wil je uitloggen?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Uitloggen", role: .destructive) { Task { await model.logout() } }
        } message: { Text("Je persoonlijke tickets en widgetgegevens worden van deze iPhone verwijderd.") }
    }
    private func preference(_ title: String, keyPath: WritableKeyPath<NotificationPreferences, Bool>) -> some View {
        Toggle(title, isOn: Binding(get: { model.preferences[keyPath: keyPath] }, set: { value in var updated = model.preferences; updated[keyPath: keyPath] = value; Task { await model.savePreferences(updated) } })).disabled(!model.notificationPreferencesAvailable || model.notificationPreferencesSaving)
    }
    private func webLink(_ title: String, icon: String, path: String) -> some View { Link(destination: model.server.appendingPathComponent(path)) { Label(title, systemImage: icon) } }
}

private struct EditProfileView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var firstName: String
    @State private var lastName: String
    @State private var phone: String
    init(profile: MemberProfile) { _firstName = State(initialValue: profile.firstName); _lastName = State(initialValue: profile.lastName); _phone = State(initialValue: profile.phoneNumber ?? "") }
    var body: some View {
        Form {
            Section("Persoonlijke gegevens") {
                LabeledContent("Voornaam", value: firstName)
                LabeledContent("Achternaam", value: lastName)
                TextField("Telefoonnummer", text: $phone).textContentType(.telephoneNumber).keyboardType(.phonePad)
            }
            Section { Text("Je naam, e-mailadres en lidmaatschap worden via je Salve Mundi account beheerd.").font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle("Mijn gegevens").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annuleren") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button { Task { if await model.saveProfile(phone: phone) { dismiss() } } } label: { if model.isSaving { ProgressView() } else { Text("Opslaan") } }.disabled(model.isSaving) }
        }
    }
}
