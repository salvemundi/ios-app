import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ActivityAdminRootView: View {
    let initialActivityID: String?
    var embedded = false
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var path: [String] = []
    var body: some View {
        Group {
            if model.canAdminActivities {
                NavigationStack(path: $path) { ActivityAdminListView(initialActivityID: initialActivityID, embedded: embedded, path: $path) }
                    .id(model.adminRevision)
            } else {
                NavigationStack {
                    VStack(spacing: 20) {
                        if model.adminAccessLoading { ProgressView("Toegang controleren…") }
                        else {
                            EmptyState(icon: "lock.shield", title: "Geen toegang tot beheer", message: model.adminMessage ?? "Je rechten worden bij Salve Mundi gecontroleerd. Deelnemers zijn alleen online beschikbaar.")
                            Button("Toegang opnieuw controleren") { Task { await model.refreshActivityAdminAccess() } }.buttonStyle(PrimaryButtonStyle())
                        }
                    }.padding(20).navigationTitle("Activiteitenbeheer")
                        .toolbar { if !embedded { ToolbarItem(placement: .topBarTrailing) { Button("Sluiten") { dismiss() } } } }
                }
            }
        }.privacySensitive()
    }
}

private struct ActivityAdminListView: View {
    let initialActivityID: String?
    let embedded: Bool
    @Binding var path: [String]
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var period = "upcoming"
    @State private var committeeID: Int?
    @State private var loading = false
    @State private var error: String?
    @State private var showCreate = false
    @State private var showScannerPicker = false
    private var activities: [AdminActivity] {
        (model.adminCollection?.activities ?? []).filter {
            let time = $0.activity.endsAt ?? $0.activity.startsAt ?? .distantFuture
            return (search.isEmpty || $0.activity.title.localizedCaseInsensitiveContains(search) || ($0.activity.location?.localizedCaseInsensitiveContains(search) ?? false)) && (committeeID == nil || $0.committeeID == committeeID) && (period == "all" || (period == "upcoming" ? time >= .now : time < .now))
        }.sorted {
            if period == "upcoming" { return ($0.activity.startsAt ?? .distantFuture) < ($1.activity.startsAt ?? .distantFuture) }
            return ($0.activity.startsAt ?? .distantPast) > ($1.activity.startsAt ?? .distantPast)
        }
    }
    var body: some View {
        List {
            if let error { AdminErrorRow(message: error, retry: { Task { await load() } }) }
            Section {
                Button { showScannerPicker = true } label: { Label("Tickets scannen", systemImage: "qrcode.viewfinder").font(.headline).padding(.vertical, 6) }
            }
            Section {
                Picker("Periode", selection: $period) { Text("Binnenkort").tag("upcoming"); Text("Voorbij").tag("past"); Text("Alles").tag("all") }.pickerStyle(.segmented)
                if let committees = model.adminCollection?.committees, !committees.isEmpty {
                    Picker("Commissie", selection: $committeeID) {
                        Text("Alle commissies").tag(Int?.none)
                        ForEach(committees) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
                HStack { AdminCount(title: "Activiteiten", value: activities.count); Spacer(); AdminCount(title: "Aangemeld", value: activities.reduce(0) { $0 + $1.confirmedCount }); Spacer(); AdminCount(title: "Ingecheckt", value: activities.reduce(0) { $0 + $1.checkedInCount }) }.padding(.vertical, 8)
            }
            Section("Jouw activiteiten") {
                if loading && model.adminCollection == nil { ProgressView("Activiteiten laden…") }
                else if activities.isEmpty { Text("Geen activiteiten binnen deze selectie.").foregroundStyle(.secondary) }
                ForEach(activities) { item in
                    NavigationLink(value: item.id) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { Text(item.activity.title).font(.headline); Spacer(); Text(item.statusLabel).font(.caption).foregroundStyle(item.status == "draft" ? .secondary : Brand.purple) }
                            if let date = item.activity.startsAt { Text(date.formatted(.dateTime.day().month().year().hour().minute())).font(.caption).foregroundStyle(.secondary) }
                            if let committee = item.committeeName { Text(committee).font(.caption).foregroundStyle(.secondary) }
                            HStack(spacing: 16) { Label("\(item.confirmedCount) aangemeld", systemImage: "person.2"); Label(item.activity.capacity.map { "\(max(0, $0 - item.confirmedCount - item.pendingCount)) plekken vrij" } ?? "Geen limiet", systemImage: "person.badge.plus"); Label("\(item.checkedInCount)", systemImage: "checkmark.circle") }.font(.caption2).foregroundStyle(.secondary)
                        }.padding(.vertical, 6)
                    }
                }
            }
            Section { Text("Rechten en aantallen komen rechtstreeks van de server. Er worden geen deelnemerslijsten offline opgeslagen.").font(.caption).foregroundStyle(.secondary) }
        }
        .navigationTitle("Activiteitenbeheer").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Zoek een activiteit")
        .navigationDestination(for: String.self) { ActivityAdminDetailView(activityID: $0) }
        .toolbar {
            if !embedded { ToolbarItem(placement: .topBarLeading) { Button("Sluiten") { dismiss() } } }
            if model.adminCollection?.canCreate == true { ToolbarItem(placement: .topBarTrailing) { Button("Nieuw", systemImage: "plus") { showCreate = true } } }
        }
        .task { await load(); if let id = initialActivityID { path = [id] } }
        .sheet(isPresented: $showScannerPicker, onDismiss: { Task { await load() } }) { NavigationStack { ActivityAdminScannerPicker() } }
        .sheet(isPresented: $showCreate) { NavigationStack { ActivityAdminEditor(detail: nil) { _ in Task { await load() } } } }
        .refreshable { await load() }
    }
    private func load() async {
        loading = true; error = nil; defer { loading = false }
        do { try await model.loadAdminActivities() }
        catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
}

private struct AdminCount: View {
    let title: String; let value: Int
    var body: some View { VStack(alignment: .leading, spacing: 5) { Text(value.formatted()).font(.title2.bold()).foregroundStyle(Brand.purple); Text(title).font(.caption2).foregroundStyle(.secondary) } }
}

private struct AdminErrorRow: View {
    let message: String; var retry: (() -> Void)? = nil
    var body: some View { VStack(alignment: .leading, spacing: 8) { Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.subheadline); if let retry { Button("Opnieuw proberen", action: retry) } } }
}

private struct ActivityAdminDetailView: View {
    let activityID: String
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var detail: AdminActivityDetail?
    @State private var error: String?
    @State private var editing = false
    @State private var deleting = false
    @State private var confirmDelete = false
    var body: some View {
        List {
            if let error { AdminErrorRow(message: error, retry: { Task { await load() } }) }
            if let detail {
                Section {
                    Text(detail.summary.activity.title).font(.title2.bold())
                    LabeledContent("Status", value: detail.summary.statusLabel)
                    if let date = detail.summary.activity.startsAt { LabeledContent("Datum", value: date.formatted(.dateTime.day().month().year().hour().minute())) }
                    if let committee = detail.summary.committeeName { LabeledContent("Commissie", value: committee) }
                    HStack { AdminCount(title: "Aangemeld", value: detail.summary.confirmedCount); Spacer(); AdminCount(title: "Openstaand", value: detail.summary.pendingCount); Spacer(); AdminCount(title: "Aanwezig", value: detail.summary.checkedInCount) }.padding(.vertical, 8)
                }
                Section("Deelnemers") {
                    if detail.summary.canCheckIn {
                        NavigationLink { ActivityAdminScannerSheet(activityID: activityID) } label: { Label("Tickets scannen", systemImage: "qrcode.viewfinder") }
                    }
                    NavigationLink { ActivityAdminRegistrationsView(activityID: activityID) } label: { Label("Aanmeldingen en aanwezigheid", systemImage: "person.2") }
                }
                Section("Activiteit") {
                    if detail.summary.canEdit { Button { editing = true } label: { Label("Activiteit wijzigen", systemImage: "pencil") } }
                    Link(destination: detail.summary.activity.websiteURL) { Label("Open de website", systemImage: "arrow.up.right.square") }
                    if detail.summary.canDelete { Button(role: .destructive) { confirmDelete = true } label: { Label(deleting ? "Verwijderen…" : "Activiteit verwijderen", systemImage: "trash") }.disabled(deleting) }
                }
            } else if error == nil { ProgressView("Activiteit laden…") }
        }
        .navigationTitle("Activiteit beheren").navigationBarTitleDisplayMode(.inline).task { await load() }.refreshable { await load() }
        .sheet(isPresented: $editing) { if let detail { NavigationStack { ActivityAdminEditor(detail: detail) { updated in self.detail = updated } } } }
        .confirmationDialog("Deze activiteit definitief verwijderen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Definitief verwijderen", role: .destructive) { Task { await remove() } }
        } message: { Text("Dit verwijdert ook de inschrijvingen. Er wordt geen automatische terugbetaling uitgevoerd. Deze actie kan niet ongedaan worden gemaakt.") }
    }
    private func load() async { do { detail = try await model.adminRequest("admin/activities/\(activityID)"); error = nil } catch is CancellationError { } catch { self.error = error.localizedDescription } }
    private func remove() async {
        deleting = true; defer { deleting = false }
        do { let _: MutationAcknowledgement = try await model.adminRequest("admin/activities/\(activityID)", method: "DELETE"); try await model.loadAdminActivities(); dismiss() }
        catch is CancellationError { } catch { self.error = error.localizedDescription }
    }
}

private struct ActivityAdminEditor: View {
    let detail: AdminActivityDetail?
    let onSaved: (AdminActivityDetail) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var form: AdminActivityForm
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var mediaMime = "image/jpeg"
    @State private var mediaFilename = "activity.jpg"
    @State private var saving = false
    @State private var error: String?
    @State private var createdID: String?
    init(detail: AdminActivityDetail?, onSaved: @escaping (AdminActivityDetail) -> Void) { self.detail = detail; self.onSaved = onSaved; _form = State(initialValue: detail?.form ?? AdminActivityForm()) }
    var body: some View {
        Form {
            if let error { Section { AdminErrorRow(message: error) } }
            Section("Activiteit") {
                TextField("Naam", text: $form.title)
                TextField("Korte omschrijving", text: optionalText(\.shortDescription), axis: .vertical)
                VStack(alignment: .leading) { Text("Beschrijving").font(.caption).foregroundStyle(.secondary); TextEditor(text: $form.description).frame(minHeight: 140) }
                TextField("Extra informatie voor leden", text: optionalText(\.memberDescription), axis: .vertical)
                TextField("Locatie", text: optionalText(\.location))
            }
            Section("Datum en aanmelden") {
                DatePicker("Begindatum", selection: requiredDay(\.startsOn), displayedComponents: .date)
                Toggle("Begintijd instellen", isOn: optionalToggle(\.startTime, initial: "18:00"))
                if form.startTime != nil { DatePicker("Begintijd", selection: timeBinding(\.startTime), displayedComponents: .hourAndMinute) }
                Toggle("Einddatum instellen", isOn: optionalToggle(\.endsOn, initial: form.startsOn))
                if form.endsOn != nil { DatePicker("Einddatum", selection: optionalDay(\.endsOn), displayedComponents: .date) }
                Toggle("Eindtijd instellen", isOn: optionalToggle(\.endTime, initial: "22:00"))
                if form.endTime != nil { DatePicker("Eindtijd", selection: timeBinding(\.endTime), displayedComponents: .hourAndMinute) }
                Toggle("Inschrijfdeadline instellen", isOn: optionalToggle(\.registrationDeadline, initial: AdminCalendar.iso(.now)))
                if form.registrationDeadline != nil { DatePicker("Inschrijven tot", selection: isoBinding(\.registrationDeadline)) }
            }
            Section("Toegang en prijzen") {
                Toggle("Alleen actieve leden", isOn: $form.membersOnly)
                TextField("Ledenprijs (€)", value: centsBinding(\.memberPriceCents), format: .number.precision(.fractionLength(2))).keyboardType(.decimalPad)
                TextField("Niet-ledenprijs (€)", value: centsBinding(\.guestPriceCents), format: .number.precision(.fractionLength(2))).keyboardType(.decimalPad)
                Toggle("Maximum aantal deelnemers", isOn: Binding(get: { form.capacity != nil }, set: { form.capacity = $0 ? 100 : nil }))
                if form.capacity != nil { Stepper("Maximaal \(form.capacity ?? 0) deelnemers", value: Binding(get: { form.capacity ?? 100 }, set: { form.capacity = $0 }), in: 1...1000) }
            }
            Section("Commissie en contact") {
                Picker("Commissie", selection: $form.committeeID) {
                    if model.adminCollection?.canAssignNoCommittee == true { Text("Geen commissie").tag(Int?.none) }
                    ForEach(model.adminCollection?.committees ?? []) { Text($0.name).tag(Optional($0.id)) }
                }
                TextField("Contact e-mail", text: optionalText(\.contactEmail)).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                TextField("Externe inschrijflink", text: optionalText(\.externalSignupURL)).keyboardType(.URL).textInputAutocapitalization(.never)
            }
            Section("Publicatie") {
                Picker("Zichtbaarheid", selection: $form.status) { Text("Concept").tag("draft"); Text("Gepubliceerd").tag("published"); Text("Inplannen").tag("scheduled") }
                if form.status == "scheduled" { DatePicker("Publiceren op", selection: isoBinding(\.publishAt), in: Date.now...) }
            }
            Section {
                if let data = photoData, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 160) }
                else if photoData != nil { Label("Video geselecteerd voor upload", systemImage: "video.fill") }
                else if let imageURL = detail?.summary.activity.imageURL, form.removeImage != true { ActivityBanner(url: imageURL, fit: true).frame(maxHeight: 160) }
                PhotosPicker(selection: $selectedPhoto, matching: .any(of: [.images, .videos])) { Label("Kies een foto of video", systemImage: "photo") }
                if photoData != nil || detail?.summary.activity.imageURL != nil { Button("Afbeelding verwijderen", role: .destructive) { photoData = nil; selectedPhoto = nil; form.removeImage = true } }
            } header: { Text("Afbeelding of video") } footer: { Text("De activiteit wordt eerst opgeslagen; daarna wordt je gekozen foto geüpload. Bij een uploadfout kun je de foto opnieuw proberen zonder een dubbele activiteit te maken.") }
        }
        .environment(\.timeZone, AdminCalendar.timeZone)
        .navigationTitle(detail == nil ? "Nieuwe activiteit" : "Activiteit wijzigen").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annuleren") { dismiss() }.disabled(saving) }
            ToolbarItem(placement: .confirmationAction) { Button("Opslaan") { Task { await save() } }.disabled(saving || form.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || form.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }
        .interactiveDismissDisabled(saving)
        .onAppear { if detail == nil, form.committeeID == nil { form.committeeID = model.adminCollection?.committees.first?.id }; if form.status == "scheduled", form.publishAt == nil { form.publishAt = AdminCalendar.iso(.now.addingTimeInterval(3600)) } }
        .onChange(of: form.status) { _, status in if status == "scheduled", form.publishAt == nil { form.publishAt = AdminCalendar.iso(.now.addingTimeInterval(3600)) } }
        .onChange(of: selectedPhoto) { _, item in Task { await readPhoto(item) } }
        .overlay { if saving { ProgressView("Opslaan…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20)) } }
    }
    private func optionalText(_ key: WritableKeyPath<AdminActivityForm, String?>) -> Binding<String> { Binding(get: { form[keyPath: key] ?? "" }, set: { form[keyPath: key] = $0.isEmpty ? nil : $0 }) }
    private func optionalToggle(_ key: WritableKeyPath<AdminActivityForm, String?>, initial: String) -> Binding<Bool> { Binding(get: { form[keyPath: key] != nil }, set: { form[keyPath: key] = $0 ? initial : nil }) }
    private func requiredDay(_ key: WritableKeyPath<AdminActivityForm, String>) -> Binding<Date> { Binding(get: { AdminCalendar.date(day: form[keyPath: key]) ?? .now }, set: { form[keyPath: key] = AdminCalendar.day($0) }) }
    private func optionalDay(_ key: WritableKeyPath<AdminActivityForm, String?>) -> Binding<Date> { Binding(get: { AdminCalendar.date(day: form[keyPath: key] ?? form.startsOn) ?? .now }, set: { form[keyPath: key] = AdminCalendar.day($0) }) }
    private func timeBinding(_ key: WritableKeyPath<AdminActivityForm, String?>) -> Binding<Date> { Binding(get: { AdminCalendar.date(day: form.startsOn, time: form[keyPath: key]) ?? .now }, set: { form[keyPath: key] = AdminCalendar.time($0) }) }
    private func isoBinding(_ key: WritableKeyPath<AdminActivityForm, String?>) -> Binding<Date> { Binding(get: { AdminCalendar.fromISO(form[keyPath: key]) ?? .now.addingTimeInterval(3600) }, set: { form[keyPath: key] = AdminCalendar.iso($0) }) }
    private func centsBinding(_ key: WritableKeyPath<AdminActivityForm, Int>) -> Binding<Double> { Binding(get: { Double(form[keyPath: key]) / 100 }, set: {
        let cents = ($0 * 100).rounded()
        guard cents.isFinite, cents >= 0, cents < Double(Int.max) else { return }
        form[keyPath: key] = Int(cents)
    }) }
    private func readPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { throw APIProblem(code: "invalid_media", message: "Dit bestand kon niet worden geopend.") }
            if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
                guard data.count <= 10 * 1024 * 1024 else { throw APIProblem(code: "image_too_large", message: "De video mag maximaal 10 MB groot zijn.") }
                let quickTime = item.supportedContentTypes.contains(where: { $0.conforms(to: .quickTimeMovie) })
                mediaMime = quickTime ? "video/quicktime" : "video/mp4"; mediaFilename = quickTime ? "activity.mov" : "activity.mp4"
                photoData = data; form.removeImage = false; return
            }
            guard let original = UIImage(data: data) else { throw APIProblem(code: "invalid_photo", message: "Deze foto kon niet worden geopend.") }
            let scale = min(1, 2048 / max(original.size.width, original.size.height))
            let size = CGSize(width: original.size.width * scale, height: original.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: size)
            guard let jpeg = renderer.image(actions: { _ in original.draw(in: CGRect(origin: .zero, size: size)) }).jpegData(compressionQuality: 0.85), jpeg.count <= 10 * 1024 * 1024 else { throw APIProblem(code: "image_too_large", message: "De foto mag maximaal 10 MB groot zijn.") }
            photoData = jpeg; mediaMime = "image/jpeg"; mediaFilename = "activity.jpg"; form.removeImage = false
        } catch { self.error = error.localizedDescription }
    }
    private func save() async {
        saving = true; error = nil; defer { saving = false }
        do {
            if form.status == "published" { form.publishAt = nil }
            let id = detail?.summary.id ?? createdID
            var saved: AdminActivityDetail = try await model.adminMutation(id.map { "admin/activities/\($0)" } ?? "admin/activities", method: id == nil ? "POST" : "PATCH", value: form)
            createdID = saved.summary.id
            if let photoData { saved = try await model.uploadAdminImage(activityID: saved.summary.id, data: photoData, mimeType: mediaMime, filename: mediaFilename) }
            onSaved(saved)
            dismiss()
        } catch is CancellationError { } catch { self.error = error.localizedDescription }
    }
}

private struct ActivityAdminRegistrationsView: View {
    let activityID: String
    @Environment(AppModel.self) private var model
    @State private var data: AdminRegistrations?
    @State private var query = ""
    @State private var payment = "all"
    @State private var membership = "all"
    @State private var error: String?
    @State private var busy = false
    @State private var cancelRegistration: AdminRegistration?
    @State private var showAdd = false
    @State private var showMessage = false
    @State private var showScanner = false
    @State private var share: AdminShareItem?
    private var visible: [AdminRegistration] { filtered(data?.registrations ?? []) }
    var body: some View {
        List {
            if let error { AdminErrorRow(message: error, retry: { Task { await load() } }) }
            if let data {
                Section {
                    Text(data.activity.activity.title).font(.headline)
                    HStack { AdminCount(title: "Aangemeld", value: data.activity.confirmedCount); Spacer(); AdminCount(title: "Openstaand", value: data.activity.pendingCount); Spacer(); AdminCount(title: "Aanwezig", value: data.activity.checkedInCount) }
                    Picker("Betaling", selection: $payment) { Text("Iedereen").tag("all"); Text("Betaald").tag("paid"); Text("Niet betaald").tag("unpaid") }.pickerStyle(.segmented)
                    Picker("Lidmaatschap", selection: $membership) { Text("Iedereen").tag("all"); Text("Leden").tag("members"); Text("Gasten").tag("guests") }.pickerStyle(.segmented)
                }
                Section("\(visible.count) deelnemers") {
                    if visible.isEmpty { Text("Geen deelnemers binnen deze selectie.").foregroundStyle(.secondary) }
                    ForEach(visible) { registration in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(registration.name).font(.headline)
                                    Text(registration.email).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                    if let phone = registration.phone, !phone.isEmpty { Text(phone).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                                }
                                Spacer()
                                if data.activity.canCheckIn && registration.isPaid {
                                    Button { Task { await checkIn(registration) } } label: {
                                        Image(systemName: registration.checkedIn ? "checkmark.circle.fill" : "circle").font(.title2).foregroundStyle(registration.checkedIn ? .green : .secondary)
                                    }.buttonStyle(.borderless).disabled(busy).accessibilityLabel(registration.checkedIn ? "Aanwezigheid van \(registration.name) uitzetten" : "\(registration.name) inchecken")
                                }
                            }
                            HStack { Text(registration.statusLabel).foregroundStyle(registration.isPaid ? .green : .secondary); Text("·"); Text(registration.isMember ? "Lid" : "Gast"); if let cents = registration.amountPaidCents { Text("·"); Text((Decimal(cents) / 100).formatted(.currency(code: "EUR"))) } }.font(.caption)
                        }.padding(.vertical, 5)
                        .swipeActions(allowsFullSwipe: false) {
                            if data.activity.canManageSignups { Button("Annuleren", role: .destructive) { cancelRegistration = registration } }
                        }
                    }
                }
                Section {
                    Menu {
                        Button("Deel CSV") { Task { await export(pdf: false) } }
                        Button("Deel PDF") { Task { await export(pdf: true) } }
                    } label: { Label("Deel deze selectie", systemImage: "square.and.arrow.up") }
                    .disabled(visible.isEmpty || busy)
                } footer: { Text("Een export bevat persoonsgegevens. Deel het bestand alleen met mensen die het voor deze activiteit nodig hebben. Voor het delen worden je actuele rechten opnieuw gecontroleerd.") }
            } else if error == nil { ProgressView("Deelnemers laden…") }
        }
        .navigationTitle("Aanmeldingen").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Zoek naam of e-mail")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if data?.activity.canCheckIn == true { Button("QR scannen", systemImage: "qrcode.viewfinder") { showScanner = true }.labelStyle(.iconOnly) }
                if data?.activity.canManageSignups == true {
                    Menu { Button("Deelnemer toevoegen", systemImage: "person.badge.plus") { showAdd = true }; Button("Bericht sturen", systemImage: "envelope") { showMessage = true } } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .task { await load() }.refreshable { await load() }
        .sheet(isPresented: $showAdd) { NavigationStack { AdminManualSignupView(activityID: activityID) { Task { await load() } } } }
        .sheet(isPresented: $showMessage) { NavigationStack { AdminMessageView(activityID: activityID) } }
        .sheet(isPresented: $showScanner, onDismiss: { Task { await load() } }) { NavigationStack { ActivityAdminScannerSheet(activityID: activityID) } }
        .sheet(item: $share) { item in AdminShareSheet(url: item.url) { model.removeAdminExport(item.url); share = nil } }
        .confirmationDialog("Inschrijving annuleren?", isPresented: Binding(get: { cancelRegistration != nil }, set: { if !$0 { cancelRegistration = nil } }), titleVisibility: .visible) {
            if let registration = cancelRegistration { Button("Inschrijving annuleren", role: .destructive) { Task { await cancel(registration) } } }
        } message: { Text("De deelnemer ontvangt een annuleringsbericht. Er wordt geen automatische terugbetaling uitgevoerd.") }
        .disabled(busy)
    }
    private func filtered(_ values: [AdminRegistration]) -> [AdminRegistration] { values.filter { $0.matches(query) && (payment == "all" || (payment == "paid" ? $0.isPaid : !$0.isPaid)) && (membership == "all" || (membership == "members" ? $0.isMember : !$0.isMember)) } }
    private func load() async {
        do { data = try await model.adminRequest("admin/activities/\(activityID)/registrations"); error = nil }
        catch is CancellationError { } catch { self.error = error.localizedDescription }
    }
    private func checkIn(_ registration: AdminRegistration) async {
        busy = true; defer { busy = false }
        do { let _: AdminRegistration = try await model.adminMutation("admin/activities/\(activityID)/registrations/\(registration.id)/check-in", method: "PATCH", value: AdminCheckIn(checkedIn: !registration.checkedIn)); await load() }
        catch is CancellationError { } catch { self.error = error.localizedDescription }
    }
    private func cancel(_ registration: AdminRegistration) async {
        busy = true; defer { busy = false; cancelRegistration = nil }
        do { let _: MutationAcknowledgement = try await model.adminRequest("admin/activities/\(activityID)/registrations/\(registration.id)", method: "DELETE"); await load() }
        catch is CancellationError { } catch { self.error = error.localizedDescription }
    }
    private func export(pdf: Bool) async {
        busy = true; defer { busy = false }
        do {
            let latest: AdminRegistrations = try await model.adminRequest("admin/activities/\(activityID)/registrations")
            data = latest
            let rows = filtered(latest.registrations)
            guard !rows.isEmpty else { error = "Er zijn geen deelnemers binnen deze selectie."; return }
            let bytes = pdf ? AdminPDF.make(title: latest.activity.activity.title, registrations: rows) : AdminExport.csv(rows)
            share = AdminShareItem(url: try model.recordAdminExport(bytes, extension: pdf ? "pdf" : "csv"))
        } catch is CancellationError { } catch { self.error = error.localizedDescription }
    }
}

private struct AdminManualSignupView: View {
    let activityID: String; let onAdded: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var type = "member"
    @State private var query = ""
    @State private var members: [AdminMember] = []
    @State private var selectedMember: AdminMember?
    @State private var name = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var acknowledged = false
    @State private var confirm = false
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        Form {
            if let error { Section { AdminErrorRow(message: error) } }
            Section { Picker("Deelnemer", selection: $type) { Text("Bestaand lid").tag("member"); Text("Gast").tag("guest") }.pickerStyle(.segmented) }
            if type == "member" {
                Section("Lid zoeken") {
                    TextField("Naam of e-mailadres (minimaal 2 tekens)", text: $query).textInputAutocapitalization(.never).autocorrectionDisabled()
                    if let member = selectedMember { Label(member.name + " · " + member.email, systemImage: "checkmark.circle.fill"); Button("Andere deelnemer kiezen") { selectedMember = nil } }
                    else { ForEach(members) { member in Button { selectedMember = member } label: { VStack(alignment: .leading) { Text(member.name); Text(member.email).font(.caption).foregroundStyle(.secondary) } } } }
                }
            } else {
                Section("Gastgegevens") {
                    TextField("Naam", text: $name).textContentType(.name)
                    TextField("E-mailadres", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                    TextField("Telefoonnummer", text: $phone).textContentType(.telephoneNumber).keyboardType(.phonePad)
                }
            }
            Section {
                Toggle("Ik registreer deze deelnemer als betaald, zonder een betaling te innen", isOn: $acknowledged)
            } footer: { Text("Een handmatige inschrijving kan de normale capaciteit overschrijden, net als op de website. Controleer de naam en gegevens voor je doorgaat.") }
        }
        .navigationTitle("Deelnemer toevoegen").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annuleren") { dismiss() }.disabled(busy) }
            ToolbarItem(placement: .confirmationAction) { Button("Toevoegen") { confirm = true }.disabled(busy || !acknowledged || (type == "member" ? selectedMember == nil : name.trimmingCharacters(in: .whitespaces).isEmpty || !email.contains("@"))) }
        }
        .task(id: query) { await searchMembers() }
        .confirmationDialog("Deelnemer als betaald toevoegen?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Toevoegen zonder betaling te innen") { Task { await add() } }
        } message: { Text(type == "member" ? selectedMember?.name ?? "" : "\(name) · \(email)") }
        .interactiveDismissDisabled(busy)
    }
    private func searchMembers() async {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 2 else { members = []; return }
        do {
            try await Task.sleep(for: .milliseconds(300))
            let values: [AdminMember] = try await model.adminRequest("admin/members", query: [.init(name: "query", value: String(term.prefix(100)))])
            guard term == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            members = values; error = nil
        } catch is CancellationError { } catch { self.error = error.localizedDescription }
    }
    private func add() async {
        busy = true; error = nil; defer { busy = false }
        do {
            let value = AdminManualRegistration(type: type, memberID: type == "member" ? selectedMember?.id : nil, name: type == "guest" ? name : nil, email: type == "guest" ? email : nil, phone: type == "guest" && !phone.isEmpty ? phone : nil)
            let _: AdminRegistration = try await model.adminMutation("admin/activities/\(activityID)/registrations", value: value)
            onAdded(); dismiss()
        } catch is CancellationError { } catch { self.error = error.localizedDescription }
    }
}

private struct AdminMessageView: View {
    let activityID: String
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var subject = ""
    @State private var message = ""
    @State private var paidOnly = false
    @State private var recipientCount = 0
    @State private var confirm = false
    @State private var busy = false
    @State private var error: String?
    @State private var sentCount: Int?
    var body: some View {
        Form {
            if let error { Section { AdminErrorRow(message: error) } }
            if let sentCount { Section { Label("Bericht verzonden naar \(sentCount) ontvangers.", systemImage: "checkmark.circle.fill").foregroundStyle(.green) } }
            Section {
                TextField("Onderwerp", text: $subject)
                TextEditor(text: $message).frame(minHeight: 180).accessibilityLabel("Bericht")
                Toggle("Alleen betaalde inschrijvingen", isOn: $paidOnly)
                Button { Task { await prepare() } } label: { Label(busy ? "Ontvangers controleren…" : "Ontvangers controleren en versturen", systemImage: "paperplane") }.disabled(busy || subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: { Text("Bericht aan deelnemers") } footer: { Text("Voor verzending zie je het aantal unieke e-mailadressen en bevestig je de verzending. De server bepaalt de actuele ontvangers van deze activiteit.") }
        }
        .navigationTitle("Bericht sturen").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Sluiten") { dismiss() }.disabled(busy) } }
        .confirmationDialog("E-mail naar \(recipientCount) ontvangers versturen?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Verstuur naar \(recipientCount) ontvangers") { Task { await send() } }
            Button("Annuleren", role: .cancel) { }
        } message: { Text("Onderwerp: \(subject). Dit stuurt een echt bericht naar de deelnemers van deze activiteit.") }
        .interactiveDismissDisabled(busy)
    }
    private func prepare() async {
        busy = true; error = nil; defer { busy = false }
        do {
            let latest: AdminRegistrations = try await model.adminRequest("admin/activities/\(activityID)/registrations")
            recipientCount = latest.recipientCount(paidOnly: paidOnly)
            if recipientCount > 0 { confirm = true } else { error = "Er zijn geen ontvangers binnen deze selectie." }
        } catch is CancellationError { } catch { self.error = error.localizedDescription }
    }
    private func send() async {
        busy = true; error = nil; defer { busy = false }
        do {
            let result: AdminMessageResult = try await model.adminMutation("admin/activities/\(activityID)/message", value: AdminMessage(subject: subject, message: message, paidOnly: paidOnly))
            if result.success { sentCount = result.recipientCount; subject = ""; message = "" }
            else { error = "Het bericht kon niet worden verzonden." }
        } catch is CancellationError { } catch { self.error = error.localizedDescription }
    }
}

private struct AdminShareItem: Identifiable { let id = UUID(); let url: URL }
private struct AdminShareSheet: UIViewControllerRepresentable {
    let url: URL
    let completed: @MainActor @Sendable () -> Void
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in Task { @MainActor in completed() } }
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}

private enum AdminPDF {
    static func make(title: String, registrations: [AdminRegistration]) -> Data {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        return renderer.pdfData { context in
            var y: CGFloat = 0
            func newPage() {
                context.beginPage()
                (("Salve Mundi · " + title) as NSString).draw(in: CGRect(x: 36, y: 32, width: 523, height: 52), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 16)])
                ("Deelnemers · \(registrations.count) · \(Date.now.formatted(.dateTime.day().month().year()))" as NSString).draw(at: CGPoint(x: 36, y: 88), withAttributes: [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.secondaryLabel])
                y = 112
            }
            newPage()
            for registration in registrations {
                let value = "\(registration.name)\n\(registration.email)\(registration.phone.map { " · " + $0 } ?? "")\n\(registration.statusLabel) · \(registration.isMember ? "Lid" : "Gast") · \(registration.checkedIn ? "Aanwezig" : "Niet ingecheckt")"
                let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.black]
                let height = (value as NSString).boundingRect(with: CGSize(width: 523, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], attributes: attributes, context: nil).height + 18
                if y + height > 806 { newPage() }
                (value as NSString).draw(in: CGRect(x: 36, y: y, width: 523, height: height), withAttributes: attributes)
                y += height
            }
        }
    }
}

struct ActivityAdminScannerPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var loading = false
    @State private var error: String?
    private var activities: [AdminActivity] {
        (model.adminCollection?.activities ?? []).filter { $0.canCheckIn && (search.isEmpty || $0.activity.title.localizedCaseInsensitiveContains(search)) }.sorted {
            let aPast = $0.activity.isPast(), bPast = $1.activity.isPast()
            if aPast != bPast { return !aPast }
            if aPast { return ($0.activity.startsAt ?? .distantPast) > ($1.activity.startsAt ?? .distantPast) }
            return ($0.activity.startsAt ?? .distantFuture) < ($1.activity.startsAt ?? .distantFuture)
        }
    }
    var body: some View {
        Group {
            if model.canAdminActivities {
                List {
                    Section { Text("Kies de activiteit waarvoor je tickets wilt scannen.").foregroundStyle(.secondary) }
                    if loading { ProgressView("Activiteiten laden…") }
                    if let error { Text(error).foregroundStyle(.red) }
                    ForEach(activities) { item in
                        NavigationLink { ActivityAdminScannerSheet(activityID: item.id) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Label(item.activity.title, systemImage: "qrcode.viewfinder").font(.headline)
                                if let date = item.activity.startsAt { Text(date.formatted(.dateTime.day().month().year().hour().minute())).font(.caption).foregroundStyle(.secondary) }
                                if item.activity.isPast() { Text("Afgelopen activiteit").font(.caption).foregroundStyle(.secondary) }
                            }.padding(.vertical, 6)
                        }
                    }
                    if activities.isEmpty && !loading && error == nil { Text("Geen toegestane activiteiten gevonden.").foregroundStyle(.secondary) }
                }
            } else { EmptyState(icon: "lock.shield", title: "Geen toegang", message: "Je hebt geen toegang tot tickets scannen.") }
        }
        .navigationTitle("Tickets scannen").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Zoek een activiteit")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Sluiten") { dismiss() } } }
        .task { await load() }
        .refreshable { await load() }
        .privacySensitive()
    }
    private func load() async {
        loading = true; error = nil; defer { loading = false }
        do { try await model.loadAdminActivities() }
        catch is CancellationError { }
        catch { self.error = "Activiteiten konden niet worden geladen. Ververs om opnieuw te proberen." }
    }
}
