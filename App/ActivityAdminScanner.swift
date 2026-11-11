import AVFoundation
import SwiftUI
import UIKit

struct ActivityAdminScannerSheet: View {
    let activityID: String
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var processing = false
    @State private var statusTitle: String?
    @State private var statusMessage = ""
    @State private var statusKind = "success"
    @State private var cameraError: String?
    @State private var resetTask: Task<Void, Never>?
    @State private var verificationTask: Task<Void, Never>?
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                CameraScannerView(enabled: !processing && statusTitle == nil && cameraError == nil, onCode: { token in
                    guard !processing, statusTitle == nil else { return }
                    processing = true
                    verificationTask = Task { await verify(token) }
                }, onError: { cameraError = $0 })
                RoundedRectangle(cornerRadius: 20).stroke(Brand.gold, lineWidth: 3).frame(width: 230, height: 230).accessibilityHidden(true)
                if processing { ProgressView("Ticket controleren…").padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) }
                if let title = statusTitle {
                    VStack(spacing: 12) {
                        Image(systemName: statusKind == "success" ? "checkmark.circle.fill" : statusKind == "warning" ? "exclamationmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 44)).foregroundStyle(statusKind == "success" ? .green : statusKind == "warning" ? .orange : .red)
                        Text(title).font(.title2.bold())
                        Text(statusMessage).multilineTextAlignment(.center)
                        Text("De scanner gaat automatisch verder.").font(.caption).foregroundStyle(.secondary)
                        Button("Volgende scannen") { clearStatus() }.font(.headline)
                    }.padding(24).frame(maxWidth: 320).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
                    .accessibilityElement(children: .combine)
                }
            }.frame(height: 440).clipShape(RoundedRectangle(cornerRadius: 24))
            if let cameraError {
                Text(cameraError).multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button("Open iPhone-instellingen") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
            } else {
                Text("Scan achter elkaar. Haal de gescande code uit beeld voordat je die opnieuw aanbiedt.").font(.subheadline).multilineTextAlignment(.center)
                Text("Alleen betaalde of bevestigde tickets voor deze activiteit worden door de server ingecheckt.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
        }
        .padding(20).navigationTitle("Tickets scannen").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Sluiten") { dismiss() } } }
        .onDisappear { verificationTask?.cancel(); resetTask?.cancel() }
        .privacySensitive()
    }
    private func clearStatus() { resetTask?.cancel(); statusTitle = nil; statusMessage = "" }
    private func showStatus(_ title: String, message: String, kind: String) {
        statusTitle = title; statusMessage = message; statusKind = kind
        UINotificationFeedbackGenerator().notificationOccurred(kind == "success" ? .success : kind == "warning" ? .warning : .error)
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
            showStatus(result.alreadyCheckedIn ? "Al ingecheckt" : "Ingecheckt", message: result.registration.name, kind: result.alreadyCheckedIn ? "warning" : "success")
        } catch is CancellationError { }
        catch {
            guard !Task.isCancelled else { return }
            if let problem = error as? APIProblem {
                switch problem.code {
                case "not_found": showStatus("Geen geldig ticket", message: "Deze QR-code hoort niet bij deze activiteit.", kind: "error")
                case "unpaid_registration": showStatus("Nog niet betaald", message: "Deze deelnemer is niet ingecheckt.", kind: "warning")
                default: showStatus("Niet ingecheckt", message: problem.message, kind: "error")
                }
            } else { showStatus("Controle niet gelukt", message: "Controleer de verbinding en scan opnieuw. De aanwezigheid kon niet worden bevestigd.", kind: "error") }
        }
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
