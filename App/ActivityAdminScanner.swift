import AudioToolbox
import AVFoundation
import SwiftUI
import UIKit

struct ActivityAdminScannerSheet: View {
    let activityID: String
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("door.sound") private var doorSoundOn = true
    @ScaledMetric(relativeTo: .largeTitle) private var statusIconSize = 44
    @ScaledMetric(relativeTo: .largeTitle) private var countSize = 32
    @State private var processing = false
    @State private var roster: AdminRegistrations?
    @State private var rosterError: String?
    @State private var rosterUpdatedAt: Date?
    @State private var loadingRoster = false
    @State private var showRoster = false
    @State private var requestVersion = 0
    @State private var visible = false
    private var offlineRejected: [String] { model.scanRejections[activityID] ?? [] }
    private var canCheckIn: Bool { roster?.activity.canCheckIn ?? model.adminCollection?.activities.first(where: { $0.id == activityID })?.canCheckIn ?? false }
    private var authorized: Bool { model.canAdminActivities && canCheckIn }
    private var pendingCount: Int { model.pendingScans.count(for: activityID) }
    private var totals: AdminDoorTotals { AdminDoorTotals(registrations: roster?.registrations ?? []) }
    @State private var statusTitle: String?
    @State private var statusMessage = ""
    @State private var statusKind = "success"
    @State private var cameraError: String?
    @State private var resetTask: Task<Void, Never>?
    @State private var verificationTask: Task<Void, Never>?
    var body: some View {
        ScrollView {
        VStack(spacing: 16) {
            if let roster {
                Text(roster.activity.activity.title).font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 12) {
                    doorCount("Aanwezig", value: totals.present, color: .green)
                    doorCount("Nog verwacht", value: totals.remaining, color: Brand.accent)
                    doorCount("Aangemeld", value: totals.expected, color: .primary)
                }
            } else if loadingRoster { ProgressView("Aanmeldingen laden…") }
            if let rosterError { Text(rosterError).font(.caption).foregroundStyle(.red); Button("Opnieuw laden") { Task { await loadRoster() } } }
            if pendingCount > 0 {
                Label("\(pendingCount) offline scan\(pendingCount == 1 ? "" : "s") wacht\(pendingCount == 1 ? "" : "en") op controle door de server", systemImage: "icloud.slash").font(.caption.weight(.semibold)).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading)
            }
            if !offlineRejected.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("\(offlineRejected.count) offline scan\(offlineRejected.count == 1 ? "" : "s") niet geldig", systemImage: "exclamationmark.triangle.fill").font(.caption.weight(.semibold))
                    Text(Array(Set(offlineRejected)).sorted().joined(separator: " · ")).font(.caption2)
                    Button("Begrepen") { model.scanRejections[activityID] = nil }.font(.caption2.weight(.semibold))
                }.foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
            }
            if let updated = rosterUpdatedAt { Text("Bijgewerkt \(updated.formatted(.dateTime.hour().minute())) · controle elke 20 seconden").font(.caption2).foregroundStyle(.secondary) }
            ZStack {
                CameraScannerView(enabled: authorized && scenePhase == .active && !showRoster && !processing && statusTitle == nil && cameraError == nil, onCode: { token in
                    guard authorized, !showRoster, !processing, statusTitle == nil else { return }
                    processing = true
                    verificationTask = Task { await verify(token) }
                }, onError: { cameraError = $0 })
                RoundedRectangle(cornerRadius: 20).stroke(Brand.gold, lineWidth: 3).frame(width: 230, height: 230).accessibilityHidden(true)
                if processing { ProgressView("Ticket controleren…").padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) }
                if let title = statusTitle {
                    VStack(spacing: 12) {
                        Image(systemName: statusKind == "success" ? "checkmark.circle.fill" : statusKind == "warning" ? "exclamationmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: statusIconSize)).foregroundStyle(statusKind == "success" ? .green : statusKind == "warning" ? .orange : .red)
                        Text(title).font(.title2.bold())
                        Text(statusMessage).multilineTextAlignment(.center)
                        Text("De scanner gaat automatisch verder.").font(.caption).foregroundStyle(.secondary)
                        Button("Volgende scannen") { clearStatus() }.font(.headline)
                    }.padding(24).frame(maxWidth: 320).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
                    .accessibilityElement(children: .combine)
                }
            }.frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 24))
            Button { showRoster = true } label: { Label("Zoek deelnemer of check handmatig in", systemImage: "magnifyingglass").frame(maxWidth: .infinity).padding(.vertical, 10) }
                .buttonStyle(.borderedProminent).tint(Brand.purple).disabled(!authorized || processing)
            if let cameraError {
                Text(cameraError).multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button("Open iPhone-instellingen") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
            } else {
                Text("Scan achter elkaar. Haal de gescande code uit beeld voordat je die opnieuw aanbiedt.").font(.subheadline).multilineTextAlignment(.center)
                Text("Alleen betaalde of bevestigde tickets voor deze activiteit worden door de server ingecheckt.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        }.navigationTitle("Deurmodus").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { doorSoundOn.toggle() } label: { Image(systemName: doorSoundOn ? "speaker.wave.2.fill" : "speaker.slash.fill") }
                    .accessibilityLabel(doorSoundOn ? "Geluid dempen" : "Geluid aanzetten")
            }
            ToolbarItem(placement: .topBarTrailing) { Button("Sluiten") { dismiss() } }
        }
        .task {
            visible = true
            await loadRoster()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(20)) } catch { return }
                guard visible else { return }
                if scenePhase == .active && !processing && !showRoster { await loadRoster() }
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await loadRoster() } } }
        .onChange(of: model.adminRevision) { _, _ in clearPrivateState() }
        .onChange(of: model.session?.token) { _, _ in clearPrivateState() }
        .sheet(isPresented: $showRoster, onDismiss: { Task { await loadRoster() } }) {
            NavigationStack {
                DoorRosterView(activityID: activityID, roster: roster, onUpdated: { registration in
                    apply(registration)
                    showStatus(registration.checkedIn ? "Ingecheckt" : "Niet ingecheckt", message: registration.name, kind: "success")
                    Task { await loadRoster() }
                })
            }
        }
        .onDisappear { visible = false; requestVersion += 1; verificationTask?.cancel(); resetTask?.cancel(); roster = nil; rosterUpdatedAt = nil }
        .privacySensitive()
    }
    private func doorCount(_ title: String, value: Int, color: Color) -> some View {
        VStack(spacing: 4) { Text(value, format: .number).font(.system(size: countSize, weight: .bold, design: .rounded)).foregroundStyle(color).monospacedDigit(); Text(title).font(.caption).foregroundStyle(.secondary) }
            .frame(maxWidth: .infinity).padding(.vertical, 12).background(Brand.card, in: RoundedRectangle(cornerRadius: 16))
    }
    private func clearPrivateState() {
        requestVersion += 1; roster = nil; rosterUpdatedAt = nil; rosterError = nil; loadingRoster = false; showRoster = false; clearStatus(); verificationTask?.cancel()
    }
    private func loadRoster() async {
        guard visible, model.canAdminActivities else { return }
        requestVersion += 1
        let version = requestVersion, revision = model.adminRevision, token = model.session?.token
        loadingRoster = true
        defer { if version == requestVersion { loadingRoster = false } }
        do {
            let value: AdminRegistrations = try await model.adminRequest("admin/activities/\(activityID)/registrations")
            guard !Task.isCancelled, visible, version == requestVersion, revision == model.adminRevision, token == model.session?.token, model.canAdminActivities else { return }
            guard value.activity.canCheckIn else { clearPrivateState(); rosterError = "Je hebt geen toegang tot inchecken voor deze activiteit."; return }
            roster = value; rosterUpdatedAt = .now; rosterError = nil
            await syncPending()
        } catch is CancellationError { }
        catch {
            guard visible, version == requestVersion, revision == model.adminRevision, token == model.session?.token else { return }
            rosterError = "Geen verbinding. Scans worden bewaard en gecontroleerd zodra je weer online bent."
        }
    }
    private func syncPending() async {
        let before = pendingCount
        guard before > 0 else { return }
        await model.syncAllPendingScans()
        if pendingCount < before { await loadRoster() }
    }
    private func apply(_ registration: AdminRegistration) {
        requestVersion += 1; loadingRoster = false
        guard let old = roster else { return }
        roster = AdminRegistrations(activity: old.activity, registrations: old.registrations.map { $0.id == registration.id ? registration : $0 })
    }
    private func clearStatus() { resetTask?.cancel(); statusTitle = nil; statusMessage = "" }
    private func showStatus(_ title: String, message: String, kind: String) {
        statusTitle = title; statusMessage = message; statusKind = kind
        DoorFeedback.play(kind: kind, sound: doorSoundOn)
        UIAccessibility.post(notification: .announcement, argument: title + ". " + message)
        resetTask?.cancel()
        resetTask = Task {
            try? await Task.sleep(for: .seconds(kind == "success" ? 1.5 : 2.5))
            guard !Task.isCancelled else { return }
            statusTitle = nil; statusMessage = ""
        }
    }
    private func verify(_ token: String) async {
        defer { processing = false }
        do {
            let result: AdminScanResult = try await model.adminMutation("admin/activities/\(activityID)/scan", value: AdminScanRequest(token: token))
            guard !Task.isCancelled else { return }
            apply(result.registration)
            showStatus(result.alreadyCheckedIn ? "Al ingecheckt" : "Ingecheckt", message: result.registration.name, kind: result.alreadyCheckedIn ? "warning" : "success")
            Task { await loadRoster() }
        } catch is CancellationError { }
        catch {
            guard !Task.isCancelled else { return }
            if let problem = error as? APIProblem {
                switch problem.code {
                case "not_found": showStatus("Geen geldig ticket", message: "Deze QR-code hoort niet bij deze activiteit.", kind: "error")
                case "unpaid_registration": showStatus("Nog niet betaald", message: "Deze deelnemer is niet ingecheckt.", kind: "warning")
                default: showStatus("Niet ingecheckt", message: problem.message, kind: "error")
                }
            } else if error is URLError {
                // Server stays the authority: this is a claim to be verified later, and the door decision is the volunteer's.
                if model.queueOfflineScan(activityID: activityID, token: token) {
                    showStatus("Offline opgeslagen", message: "Nog niet gecontroleerd. Laat alleen toe als het ticket klopt; de server controleert zodra er verbinding is.", kind: "warning")
                } else { showStatus("Al offline gescand", message: "Deze code staat al in de wachtrij.", kind: "warning") }
            } else { showStatus("Controle niet gelukt", message: "De aanwezigheid kon niet worden bevestigd. Scan opnieuw.", kind: "error") }
        }
    }
}

private struct DoorRosterView: View {
    let activityID: String
    @State var roster: AdminRegistrations?
    let onUpdated: (AdminRegistration) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @State private var requestVersion = 0
    @State private var loading = false
    @State private var query = ""
    @State private var busyID: String?
    @State private var error: String?
    private var registrations: [AdminRegistration] { (roster?.registrations ?? []).filter { $0.matches(query) }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }
    var body: some View {
        Group {
            if model.canAdminActivities && roster?.activity.canCheckIn == true {
                List {
                    if loading { ProgressView("Aanmeldingen vernieuwen…") }
                    if let error { Text(error).foregroundStyle(.red) }
                    if registrations.isEmpty { if query.isEmpty { Text("Nog geen deelnemers.").foregroundStyle(.secondary) } else { ContentUnavailableView.search(text: query) } }
                    ForEach(registrations) { registration in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(registration.name).font(.headline)
                                Text(!registration.isPaid ? "Niet betaald · niet incheckbaar" : registration.checkedIn ? "Aanwezig" : "Nog niet aanwezig").font(.caption).foregroundStyle(registration.isPaid && registration.checkedIn ? .green : .secondary)
                            }
                            Spacer()
                            if registration.isPaid && !registration.checkedIn {
                                Button("Inchecken") { Task { await checkIn(registration) } }.buttonStyle(.borderedProminent).tint(Brand.purple).disabled(busyID != nil)
                            } else { Image(systemName: registration.isPaid && registration.checkedIn ? "checkmark.circle.fill" : "exclamationmark.circle").foregroundStyle(registration.isPaid && registration.checkedIn ? .green : .orange) }
                        }.padding(.vertical, 6)
                    }
                }
            } else { EmptyState(icon: "lock.shield", title: "Geen toegang", message: "De deelnemerslijst is niet beschikbaar.") }
        }
        .navigationTitle("Zoek deelnemer").navigationBarTitleDisplayMode(.inline)
        .inlineSearch(text: $query, prompt: "Zoek naam of e-mail")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Terug naar scanner") { dismiss() } } }
        .task {
            visible = true
            await load()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(20)) } catch { return }
                if scenePhase == .active && busyID == nil { await load() }
            }
        }
        .refreshable { await load() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await load() } } }
        .onChange(of: model.adminRevision) { _, _ in requestVersion += 1; roster = nil; query = ""; dismiss() }
        .onChange(of: model.session?.token) { _, _ in requestVersion += 1; roster = nil; query = ""; dismiss() }
        .onDisappear { visible = false; requestVersion += 1; roster = nil }
        .privacySensitive()
    }
    private func load() async {
        guard visible, model.canAdminActivities else { return }
        requestVersion += 1
        let version = requestVersion, revision = model.adminRevision, token = model.session?.token
        loading = true
        defer { if version == requestVersion { loading = false } }
        do {
            let value: AdminRegistrations = try await model.adminRequest("admin/activities/\(activityID)/registrations")
            guard visible, !Task.isCancelled, version == requestVersion, revision == model.adminRevision, token == model.session?.token else { return }
            guard value.activity.canCheckIn else { roster = nil; dismiss(); return }
            roster = value; error = nil
        } catch is CancellationError { }
        catch { guard visible, version == requestVersion, revision == model.adminRevision, token == model.session?.token else { return }; self.error = "De lijst kon niet worden vernieuwd. Controleer je verbinding." }
    }
    private func checkIn(_ registration: AdminRegistration) async {
        guard registration.isPaid, !registration.checkedIn, busyID == nil, model.canAdminActivities else { return }
        busyID = registration.id; error = nil
        let revision = model.adminRevision, token = model.session?.token
        defer { busyID = nil }
        do {
            let value: AdminRegistration = try await model.adminMutation("admin/activities/\(activityID)/registrations/\(registration.id)/check-in", method: "PATCH", value: AdminCheckIn(checkedIn: true))
            guard revision == model.adminRevision, token == model.session?.token, model.canAdminActivities, let old = roster else { return }
            requestVersion += 1; loading = false
            roster = AdminRegistrations(activity: old.activity, registrations: old.registrations.map { $0.id == value.id ? value : $0 })
            onUpdated(value)
            Task { await load() }
        } catch is CancellationError { }
        catch { guard revision == model.adminRevision, token == model.session?.token else { return }; self.error = (error as? APIProblem)?.message ?? "Inchecken is niet bevestigd. Controleer de verbinding en probeer opnieuw."; Task { await load() } }
    }
}

private struct CameraScannerView: UIViewControllerRepresentable {
    let enabled: Bool
    let onCode: @MainActor (String) -> Void
    let onError: @MainActor (String) -> Void
    func makeUIViewController(context: Context) -> CameraScannerController { CameraScannerController(onCode: onCode, onError: onError) }
    func updateUIViewController(_ controller: CameraScannerController, context: Context) { controller.scanningEnabled = enabled }
    static func dismantleUIViewController(_ controller: CameraScannerController, coordinator: ()) { controller.stop() }
}

private final class CaptureSessionBox: @unchecked Sendable { let session = AVCaptureSession() }

@MainActor
private final class CameraScannerController: UIViewController, @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
    private let box = CaptureSessionBox()
    private let captureQueue = DispatchQueue(label: "nl.salvemundi.ios.qr-camera")
    private var preview: AVCaptureVideoPreviewLayer?
    var scanningEnabled = true
    private var gate = AdminScanGate()
    private var active = true
    private let onCode: @MainActor (String) -> Void
    private let onError: @MainActor (String) -> Void
    init(onCode: @escaping @MainActor (String) -> Void, onError: @escaping @MainActor (String) -> Void) {
        self.onCode = onCode; self.onError = onError
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .black
        Task {
            let allowed: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: allowed = true
            case .notDetermined: allowed = await withCheckedContinuation { continuation in AVCaptureDevice.requestAccess(for: .video) { continuation.resume(returning: $0) } }
            default: allowed = false
            }
            guard active else { return }
            if allowed { configure() } else { onError("Geef de app toegang tot je camera in de iPhone-instellingen om QR-tickets te scannen.") }
        }
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); preview?.frame = view.bounds }
    private func configure() {
        guard let camera = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: camera) else { onError("Er is geen geschikte camera beschikbaar op dit apparaat."); return }
        let session = box.session
        session.beginConfiguration()
        guard session.canAddInput(input) else { session.commitConfiguration(); onError("De camera kon niet worden gestart."); return }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { session.commitConfiguration(); onError("QR-codes worden niet ondersteund op dit apparaat."); return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        guard output.availableMetadataObjectTypes.contains(.qr) else { session.commitConfiguration(); onError("QR-codes worden niet ondersteund op dit apparaat."); return }
        output.metadataObjectTypes = [.qr]
        session.commitConfiguration()
        let preview = AVCaptureVideoPreviewLayer(session: session); preview.videoGravity = .resizeAspectFill; preview.frame = view.bounds
        view.layer.addSublayer(preview); self.preview = preview
        let box = box
        captureQueue.async { box.session.startRunning() }
    }
    func stop() {
        active = false
        let box = box
        captureQueue.async { if box.session.isRunning { box.session.stopRunning() } }
    }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard active, UIApplication.shared.applicationState == .active,
              let token = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue, !token.isEmpty else { return }
        guard gate.accept(token, enabled: scanningEnabled) else { return }
        scanningEnabled = false
        onCode(token)
    }
}

/// Distinct haptics and short system sounds per scan result. Haptics always play; sound can be muted.
enum DoorFeedback {
    @MainActor static func play(kind: String, sound: Bool) {
        switch kind {
        case "success":
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            if sound { AudioServicesPlaySystemSound(1057) }
        case "warning":
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { generator.impactOccurred() }
            if sound { AudioServicesPlaySystemSound(1105) }
        default:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            if sound { AudioServicesPlaySystemSound(1073) }
        }
    }
}
