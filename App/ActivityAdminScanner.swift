import AVFoundation
import SwiftUI
import UIKit

struct ActivityAdminScannerSheet: View {
    let activityID: String
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var scannerID = UUID()
    @State private var processing = false
    @State private var result: AdminScanResult?
    @State private var error: String?
    var body: some View {
        VStack(spacing: 20) {
            if let result {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundStyle(.green)
                Text(result.registration.name).font(.title2.bold())
                Text(result.alreadyCheckedIn ? "Deze deelnemer was al ingecheckt." : "Deelnemer is ingecheckt.").foregroundStyle(.secondary)
                Button("Volgende QR-code scannen") { reset() }.buttonStyle(PrimaryButtonStyle())
            } else if let error {
                Image(systemName: "exclamationmark.shield").font(.system(size: 52)).foregroundStyle(Brand.purple)
                Text(error).multilineTextAlignment(.center)
                Button("Opnieuw scannen") { reset() }.buttonStyle(PrimaryButtonStyle())
                Button("Open iPhone-instellingen") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
            } else {
                CameraScannerView(onCode: { token in Task { await verify(token) } }, onError: { error = $0 })
                    .id(scannerID).clipShape(RoundedRectangle(cornerRadius: 24)).frame(maxHeight: 440)
                    .overlay { RoundedRectangle(cornerRadius: 20).stroke(Brand.gold, lineWidth: 3).frame(width: 230, height: 230).accessibilityHidden(true) }
                if processing { ProgressView("Ticket controleren…") }
                Text("Scan alleen tickets voor deze activiteit. De server controleert de betaling en voorkomt dubbel inchecken.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
        }
        .padding(20).navigationTitle("QR-ticket controleren").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Sluiten") { dismiss() } } }
        .privacySensitive()
    }
    private func reset() { result = nil; error = nil; processing = false; scannerID = UUID() }
    private func verify(_ token: String) async {
        guard !processing else { return }
        processing = true; defer { processing = false }
        do { result = try await model.adminMutation("admin/activities/\(activityID)/scan", value: AdminScanRequest(token: token)) }
        catch is CancellationError { } catch { self.error = error.localizedDescription }
    }
}

private struct CameraScannerView: UIViewControllerRepresentable {
    let onCode: @MainActor (String) -> Void
    let onError: @MainActor (String) -> Void
    func makeUIViewController(context: Context) -> CameraScannerController { CameraScannerController(onCode: onCode, onError: onError) }
    func updateUIViewController(_ controller: CameraScannerController, context: Context) { }
    static func dismantleUIViewController(_ controller: CameraScannerController, coordinator: ()) { controller.stop() }
}

private final class CaptureSessionBox: @unchecked Sendable { let session = AVCaptureSession() }

@MainActor
private final class CameraScannerController: UIViewController, @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
    private let box = CaptureSessionBox()
    private let captureQueue = DispatchQueue(label: "nl.salvemundi.ios.qr-camera")
    private var preview: AVCaptureVideoPreviewLayer?
    private var didScan = false
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
        guard !didScan, let token = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue, !token.isEmpty else { return }
        didScan = true; stop(); onCode(token)
    }
}
