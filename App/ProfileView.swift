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
                        NavigationLink("Activiteiten en commissiemeldingen") { ActivityNotificationSettingsView() }
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


private struct ActivityNotificationSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var draft = NotificationPreferences()
    @State private var selectedCommitteesOnly = false
    @State private var thresholds = ""
    @State private var loaded = false
    @State private var saved = false
    private var parsedThresholds: [Int]? {
        if thresholds.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [] }
        let parts = thresholds.split(separator: ",", omittingEmptySubsequences: false)
        let values = parts.compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == values.count, values.allSatisfy({ (1...10000).contains($0) }), Set(values).count <= 10 else { return nil }
        return Set(values).sorted()
    }
    private var valid: Bool {
        loaded && model.notificationPreferencesAvailable && model.notificationOptions != nil && parsedThresholds != nil && (!draft.activityAnnouncements || !selectedCommitteesOnly || !draft.activityCommitteeIDs.isEmpty)
    }
    var body: some View {
        Form {
            Section {
                Text("Kies welke activiteiten je wilt volgen en wanneer je als organisator een seintje wilt krijgen.").font(.subheadline)
                if model.notificationOptionsLoading { ProgressView("Instellingen laden…") }
                if let error = model.notificationOptionsError { Text(error).foregroundStyle(.red); Button("Opnieuw proberen") { Task { await load() } } }
                if !model.notificationPreferencesAvailable && !model.notificationOptionsLoading { Text("Meldingsvoorkeuren zijn nog niet beschikbaar. Je keuzes zijn nog niet opgeslagen.").foregroundStyle(.secondary) }
            }
            if loaded, let options = model.notificationOptions {
                Section {
                    Toggle("Nieuwe activiteiten", isOn: $draft.activityAnnouncements)
                    if draft.activityAnnouncements {
                        Picker("Van welke commissies?", selection: $selectedCommitteesOnly) {
                            Text("Alle commissies").tag(false)
                            Text("Zelf kiezen").tag(true)
                        }
                        if selectedCommitteesOnly {
                            if options.committees.isEmpty { Text("Er zijn nog geen commissies beschikbaar.").foregroundStyle(.secondary) }
                            ForEach(options.committees) { committee in
                                Toggle(committee.name, isOn: Binding(get: { draft.activityCommitteeIDs.contains(committee.id) }, set: { selected in
                                    if selected { draft.activityCommitteeIDs = Array(Set(draft.activityCommitteeIDs + [committee.id])).sorted() }
                                    else { draft.activityCommitteeIDs.removeAll { $0 == committee.id } }
                                }))
                            }
                            if draft.activityCommitteeIDs.isEmpty { Text("Kies minimaal één commissie.").font(.caption).foregroundStyle(.orange) }
                        }
                    }
                } header: { Text("Activiteiten volgen") } footer: { Text("Je ontvangt een melding wanneer een nieuwe activiteit van je selectie wordt gepubliceerd. Dit staat los van meldingen over je eigen inschrijvingen.") }
                if options.canReceiveOrganizerAlerts {
                    Section {
                        Toggle("Bijna vol", isOn: $draft.organizerAlmostFull)
                        if draft.organizerAlmostFull {
                            Stepper("Vanaf \(draft.organizerCapacityPercent)% bezet", value: $draft.organizerCapacityPercent, in: 50...100, step: 5)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Melden bij aantallen aanmeldingen")
                            TextField("Bijvoorbeeld 10, 25, 50", text: $thresholds).keyboardType(.numbersAndPunctuation).accessibilityLabel("Melden bij aantallen aanmeldingen")
                        }
                        if parsedThresholds == nil { Text("Gebruik maximaal tien hele aantallen van 1 tot 10.000, gescheiden door komma’s.").font(.caption).foregroundStyle(.red) }
                        if !options.organizerCommittees.isEmpty { Text("Voor: " + options.organizerCommittees.map(\.name).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary) }
                    } header: { Text("Als organisator") } footer: { Text("Meldingen tellen bevestigde aanmeldingen. ‘Bijna vol’ geldt voor activiteiten met een maximumaantal deelnemers. Laat de aantallen leeg om die meldingen uit te zetten. Je ontvangt alleen meldingen voor activiteiten die je volgens je actuele beheerrechten mag zien.") }
                }
                Section {
                    Button {
                        Task {
                            var value = draft
                            value.activityCommitteeIDs = selectedCommitteesOnly ? draft.activityCommitteeIDs : []
                            value.organizerSignupThresholds = parsedThresholds ?? []
                            if !options.canReceiveOrganizerAlerts {
                                value.organizerAlmostFull = false
                                value.organizerSignupThresholds = []
                            }
                            // Keep the other four settings at their current server-backed values.
                            value.registrations = model.preferences.registrations
                            value.payments = model.preferences.payments
                            value.eventChanges = model.preferences.eventChanges
                            value.reminders = model.preferences.reminders
                            if await model.savePreferences(value) { draft = model.preferences; saved = true }
                        }
                    } label: {
                        HStack { Text("Voorkeuren opslaan"); Spacer(); if model.notificationPreferencesSaving { ProgressView() } }
                    }.disabled(!valid || model.notificationPreferencesSaving)
                    if saved { Label("Je voorkeuren zijn opgeslagen", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                }
            }
        }
        .navigationTitle("Activiteitsmeldingen").navigationBarTitleDisplayMode(.inline)
        .disabled(model.notificationPreferencesSaving)
        .task { await load() }
        .onChange(of: draft) { _, _ in saved = false }
        .onChange(of: thresholds) { _, _ in saved = false }
        .onChange(of: selectedCommitteesOnly) { _, _ in saved = false }
    }
    private func load() async {
        loaded = false
        await model.loadNotificationOptions()
        guard model.notificationPreferencesAvailable, model.notificationOptions != nil else { return }
        draft = model.preferences
        selectedCommitteesOnly = !draft.activityCommitteeIDs.isEmpty
        thresholds = draft.organizerSignupThresholds.map(String.init).joined(separator: ", ")
        loaded = true
    }
}
