import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            Tab("Home", systemImage: "house.fill", value: .home) { NavigationStack { HomeView() } }
            Tab("Activiteiten", systemImage: "calendar", value: .activities) { NavigationStack { ActivitiesView() } }
            Tab("Tickets", systemImage: "qrcode", value: .tickets) { NavigationStack { TicketsView() } }
            if model.canAdminActivities {
                Tab("Beheer", systemImage: "slider.horizontal.3", value: .admin) { ActivityAdminRootView(initialActivityID: nil, embedded: true) }
            }
            Tab("Profiel", systemImage: "person.crop.circle", value: .profile) { NavigationStack { ProfileView() } }
        }
        .onChange(of: model.canAdminActivities) { _, allowed in
            if !allowed && model.selectedTab == .admin { model.selectedTab = .home }
        }
        .sheet(item: $model.adminPresentation) { presentation in
            ActivityAdminRootView(initialActivityID: presentation.activityID)
        }
        .sheet(item: $model.selectedActivity) { activity in NavigationStack { ActivityDetailView(activity: activity) } }
        .sheet(item: $model.selectedTicket) { ticket in NavigationStack { TicketDetailView(ticket: ticket) } }
        .alert("Er ging iets mis", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .alert("Salve Mundi", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("OK", role: .cancel) { model.notice = nil }
        } message: { Text(model.notice ?? "") }
        .safeAreaInset(edge: .top, spacing: 0) {
            if model.isDemo {
                Text("DEMONSTRATIE · GEEN ECHTE GEGEVENS").font(.caption2.bold()).frame(maxWidth: .infinity).padding(8).background(Brand.gold).foregroundStyle(Brand.deepPurple)
            }
            if let message = model.backendUnavailableMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Appverbinding nog niet actief", systemImage: "antenna.radiowaves.left.and.right.slash").font(.subheadline.bold())
                    Text(message).font(.caption)
                    Button { Task { await model.refresh() } } label: {
                        HStack(spacing: 6) {
                            if model.isLoading { ProgressView().controlSize(.small) }
                            Text("Opnieuw proberen")
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .disabled(model.isLoading || model.isSigningIn)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .foregroundStyle(Brand.deepPurple)
                .background(Brand.gold.opacity(0.95))
                .accessibilityElement(children: .contain)
            }
            if model.isOffline {
                HStack(spacing: 8) { Image(systemName: "wifi.slash"); Text("Offline · eerder geladen gegevens") }.font(.caption).frame(maxWidth: .infinity).padding(8).background(Brand.gold).foregroundStyle(Brand.deepPurple)
            }
        }
    }
}

struct HomeView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(model.nextTicket == nil ? "BINNENKORT BIJ SALVE MUNDI" : (model.nextTicket?.startsAt.map { $0 < .now } == true ? "JOUW ACTIVITEIT" : "JE VOLGENDE ACTIVITEIT"))
                                .font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(Brand.gold)
                            Text(model.nextTicket?.title ?? (model.isLoading ? "Agenda laden…" : model.upcoming.first?.title ?? "Ontdek de agenda"))
                                .font(.title.bold()).foregroundStyle(.white)
                        }
                        Spacer(minLength: 8)
                        Image("Brand").renderingMode(.template).resizable().scaledToFit().frame(width: 72).foregroundStyle(Brand.gold).accessibilityHidden(true)
                    }
                    if let ticket = model.nextTicket {
                        if let date = ticket.startsAt { Label(date.formatted(.dateTime.weekday(.wide).day().month().hour().minute()), systemImage: "calendar").foregroundStyle(.white) }
                        if let location = ticket.location, !location.isEmpty { Label(location, systemImage: "mappin.and.ellipse").foregroundStyle(.white.opacity(0.8)) }
                        Button { model.selectedTicket = ticket } label: { Label("Bekijk mijn ticket", systemImage: "qrcode") }.buttonStyle(PrimaryButtonStyle(gold: true))
                    } else if model.isLoading {
                        ProgressView("Je activiteiten ophalen…").tint(.white).foregroundStyle(.white)
                    } else {
                        if let next = model.upcoming.first {
                            Text(model.signedIn ? "Je bent nog niet aangemeld voor een komende activiteit." : "De eerstvolgende activiteit uit de agenda.").font(.subheadline).foregroundStyle(.white.opacity(0.8))
                            if let date = next.startsAt { Label(date.formatted(.dateTime.weekday(.wide).day().month().hour().minute()), systemImage: "calendar").foregroundStyle(.white) }
                            if let location = next.location, !location.isEmpty { Label(location, systemImage: "mappin.and.ellipse").foregroundStyle(.white.opacity(0.8)) }
                            Button { model.selectedActivity = next } label: { Text("Bekijk activiteit") }.buttonStyle(PrimaryButtonStyle(gold: true))
                        } else {
                            Text("Nieuwe activiteiten verschijnen hier zodra ze bekend zijn.").foregroundStyle(.white.opacity(0.8))
                            Button("Open de agenda") { model.selectedTab = .activities }.buttonStyle(PrimaryButtonStyle(gold: true))
                        }
                        if !model.signedIn {
                            Button { Task { await model.signIn() } } label: { HStack { if model.isSigningIn { ProgressView().tint(.white) }; Text("Inloggen als lid"); Image(systemName: "arrow.right") } }.font(.subheadline.bold()).foregroundStyle(.white).disabled(model.isSigningIn)
                        }
                    }
                }
                .padding(24).frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [Brand.purple, Brand.deepPurple], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 28))
                if model.signedIn {
                    HStack {
                        SectionHeading(title: "Jouw tickets")
                        Button("Bekijk alles") { model.selectedTab = .tickets }
                            .font(.subheadline.weight(.semibold)).fixedSize()
                            .accessibilityLabel("Bekijk al mijn tickets")
                    }
                }
                VStack(spacing: 16) {
                    HStack { SectionHeading(title: "Binnenkort"); Button("Alles") { model.selectedTab = .activities }.font(.subheadline.weight(.semibold)) }
                    if model.isLoading && model.activities.isEmpty { ProgressView().padding(30) }
                    else if model.backendUnavailableMessage != nil && model.activities.isEmpty { EmptyState(icon: "calendar.badge.exclamationmark", title: "Agenda tijdelijk niet beschikbaar", message: "Je kunt opnieuw laden zodra de appverbinding actief is.") }
                    else if model.upcoming.isEmpty { EmptyState(icon: "calendar.badge.clock", title: "Even rustig op de agenda", message: "Nieuwe activiteiten verschijnen hier zodra ze bekend zijn.") }
                    else { ForEach(model.upcoming.prefix(3)) { activity in Button { model.selectedActivity = activity } label: { ActivityCard(activity: activity, featured: true) }.buttonStyle(.plain) } }
                }
                HStack(spacing: 14) {
                    QuickLink(title: "Vereniging", icon: "person.3.fill", url: model.server.appendingPathComponent("commissies"))
                    QuickLink(title: "Contact", icon: "bubble.left.and.bubble.right.fill", url: model.server.appendingPathComponent("contact"))
                }
                if let updated = model.lastUpdated { Text("Bijgewerkt \(updated.formatted(.relative(presentation: .named)))").font(.caption2).foregroundStyle(.tertiary).frame(maxWidth: .infinity) }
            }.padding(20)
        }
        .background(Brand.background).navigationTitle("Salve Mundi").navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refresh() }
    }
}

private struct QuickLink: View {
    let title: String; let icon: String; let url: URL
    var body: some View { Link(destination: url) { VStack(alignment: .leading, spacing: 12) { Image(systemName: icon).font(.title2).foregroundStyle(Brand.purple); Text(title).font(.subheadline.bold()).foregroundStyle(.primary) }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(Brand.card, in: RoundedRectangle(cornerRadius: 22)) } }
}

struct ActivitiesView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var upcomingOnly = true
    private var visible: [Activity] {
        let matching = model.activities.filter {
            (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || ($0.location?.localizedCaseInsensitiveContains(search) ?? false)) && (!upcomingOnly || !$0.isPast())
        }
        return matching.sorted {
            if upcomingOnly { return ($0.startsAt ?? .distantFuture) < ($1.startsAt ?? .distantFuture) }
            return ($0.startsAt ?? .distantPast) > ($1.startsAt ?? .distantPast)
        }
    }
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                Picker("Periode", selection: $upcomingOnly) { Text("Binnenkort").tag(true); Text("Alle activiteiten").tag(false) }.pickerStyle(.segmented)
                if model.isLoading && model.activities.isEmpty { ProgressView().padding(40) }
                else if model.backendUnavailableMessage != nil && model.activities.isEmpty { EmptyState(icon: "calendar.badge.exclamationmark", title: "Agenda tijdelijk niet beschikbaar", message: "Je kunt opnieuw laden zodra de appverbinding actief is.") }
                else if visible.isEmpty { EmptyState(icon: "magnifyingglass", title: search.isEmpty ? "Nog geen activiteiten" : "Niets gevonden", message: "Probeer later opnieuw of pas je zoekopdracht aan.") }
                else { ForEach(visible) { activity in Button { model.selectedActivity = activity } label: { ActivityCard(activity: activity) }.buttonStyle(.plain) } }
            }.padding(20)
        }.id(upcomingOnly).background(Brand.background).navigationTitle("Activiteiten")
        .searchable(text: $search, prompt: "Zoek een activiteit")
        .refreshable { await model.refresh() }
    }
}
