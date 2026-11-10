import EventKit
import EventKitUI
import SafariServices
import SwiftUI

struct ActivityDetailView: View {
    let activity: Activity
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var showCalendar = false
    @State private var calendarEvent: EKEvent?
    @State private var eventStore = EKEventStore()
    @State private var confirmRegistration = false
    private var current: Activity { model.activities.first(where: { $0.id == activity.id }) ?? activity }
    private var ticket: Ticket? { model.tickets.first { $0.activityID == current.id && $0.isValid } }
    private var price: String { let cents = model.profile?.isActiveMember == true ? current.memberPriceCents : current.guestPriceCents; return cents == 0 ? "Gratis" : (Decimal(cents) / 100).formatted(.currency(code: "EUR")) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ActivityCard(activity: current, featured: true)
                VStack(alignment: .leading, spacing: 16) {
                    if let date = current.startsAt { Label(date.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()), systemImage: "calendar").font(.subheadline) }
                    if let location = current.location { Label(location, systemImage: "mappin.and.ellipse").font(.subheadline) }
                    if let deadline = current.registrationDeadline { Label("Aanmelden tot \(deadline.formatted(.dateTime.day().month().hour().minute()))", systemImage: "hourglass").font(.subheadline) }
                    if let capacity = current.capacity, let count = current.signupCount { Label("\(max(0, capacity - count)) plekken beschikbaar", systemImage: "person.2").font(.subheadline) }
                }.foregroundStyle(.secondary)
                if let description = current.description, !description.isEmpty {
                    VStack(alignment: .leading, spacing: 12) { SectionHeading(title: "Over deze activiteit"); Text(description).font(.body).textSelection(.enabled) }
                }
                HStack {
                    VStack(alignment: .leading, spacing: 5) { Text("Voor jou").font(.caption).foregroundStyle(.secondary); Text(price).font(.title2.bold()).foregroundStyle(Brand.purple) }
                    Spacer()
                    if current.membersOnly { Label("Alleen leden", systemImage: "person.crop.circle.badge.checkmark").font(.caption.bold()).foregroundStyle(Brand.purple) }
                }.padding(20).background(Brand.card, in: RoundedRectangle(cornerRadius: 20))
                if current.startsAt != nil {
                    Button { Task { await addToCalendar() } } label: { Label("Zet in mijn agenda", systemImage: "calendar.badge.plus").frame(maxWidth: .infinity).padding(14) }.buttonStyle(.bordered)
                }
                Link(destination: current.websiteURL) { Label("Bekijk op de website", systemImage: "arrow.up.right.square").font(.subheadline).frame(maxWidth: .infinity) }
            }.padding(20)
        }
        .background(Brand.background)
        .navigationTitle("Activiteit").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Sluiten", systemImage: "xmark", action: { dismiss() }).labelStyle(.iconOnly).disabled(model.registrationInProgress == current.id) } }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if ticket != nil {
                    Button { dismiss(); model.selectedTab = .tickets } label: { Label("Bekijk mijn ticket", systemImage: "qrcode") }.buttonStyle(PrimaryButtonStyle())
                } else if current.kind != "event" || current.registrationViaWebsite == true {
                    Link(destination: current.websiteURL) { Label("Aanmelden op de website", systemImage: "arrow.up.right.square") }.buttonStyle(PrimaryButtonStyle())
                } else {
                    Button {
                        if model.signedIn { confirmRegistration = true } else { Task { await model.signIn() } }
                    } label: {
                        HStack { if model.registrationInProgress == current.id { ProgressView().tint(.white) }; Text(current.isFull ? "Deze activiteit is vol" : current.registrationClosed() ? "Aanmelden gesloten" : model.signedIn ? "Aanmelden · \(price)" : "Log in om je aan te melden") }
                    }.buttonStyle(PrimaryButtonStyle()).disabled(current.registrationClosed() || model.registrationInProgress != nil || model.isSigningIn)
                }
            }.padding(.horizontal, 20).padding(.vertical, 12).background(.bar)
        }
        .confirmationDialog("Aanmelden voor \(current.title)?", isPresented: $confirmRegistration, titleVisibility: .visible) {
            Button(price == "Gratis" ? "Bevestig mijn inschrijving" : "Aanmelden en betalen · \(price)") { Task { await model.register(for: current) } }
            Button("Annuleren", role: .cancel) { }
        } message: { Text("Je inschrijving volgt dezelfde voorwaarden als op de Salve Mundi website.") }
        .interactiveDismissDisabled(model.registrationInProgress == current.id)
        .sheet(isPresented: Binding(get: { model.checkoutURL != nil }, set: { if !$0 { model.checkoutURL = nil; Task { await model.refresh() } } })) {
            if let url = model.checkoutURL { SafariView(url: url).ignoresSafeArea() }
        }
        .sheet(isPresented: $showCalendar) { if let calendarEvent { CalendarEditor(event: calendarEvent, store: eventStore) } }
    }

    private func addToCalendar() async {
        do {
            let granted = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                eventStore.requestWriteOnlyAccessToEvents { granted, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: granted) }
                }
            }
            guard granted, let start = current.startsAt else {
                model.notice = "Geef toegang tot je agenda via de instellingen van je iPhone."; return
            }
            let event = EKEvent(eventStore: eventStore)
            event.title = current.title; event.startDate = start; event.endDate = current.endsAt ?? start.addingTimeInterval(7200)
            event.location = current.location; event.url = current.websiteURL; event.notes = current.description
            event.calendar = eventStore.defaultCalendarForNewEvents
            calendarEvent = event; showCalendar = true
        } catch { model.errorMessage = "De activiteit kon niet aan je agenda worden toegevoegd." }
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) { }
}

private struct CalendarEditor: UIViewControllerRepresentable {
    let event: EKEvent; let store: EKEventStore
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }
    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let controller = EKEventEditViewController(); controller.event = event; controller.eventStore = store; controller.editViewDelegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) { }
    @MainActor final class Coordinator: NSObject, @preconcurrency EKEventEditViewDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) { dismiss() }
    }
}
