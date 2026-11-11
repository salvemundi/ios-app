import CoreImage.CIFilterBuiltins
import SwiftUI

struct TicketsView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if !model.signedIn {
                    EmptyState(icon: "ticket", title: "Jouw plek is gereserveerd", message: "Log in met je Salve Mundi account om je tickets en QR-codes te bekijken.")
                    Button { Task { await model.signIn() } } label: { Text("Inloggen") }.buttonStyle(PrimaryButtonStyle()).disabled(model.isSigningIn)
                } else if model.isLoading && model.tickets.isEmpty { ProgressView().padding(40) }
                else if model.tickets.isEmpty {
                    EmptyState(icon: "qrcode", title: "Nog geen tickets", message: "Meld je aan voor een activiteit. Je ticket verschijnt hier zodra je inschrijving is bevestigd.")
                    Button("Ontdek activiteiten") { model.selectedTab = .activities }.buttonStyle(PrimaryButtonStyle())
                } else {
                    Text("Je tickets, altijd bij de hand.").font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(model.tickets.sorted { ($0.startsAt ?? .distantPast) > ($1.startsAt ?? .distantPast) }) { ticket in
                        Button { model.selectedTicket = ticket } label: { TicketRow(ticket: ticket) }.buttonStyle(.plain)
                    }
                    if model.isOffline { Text("Een offline ticket kan sinds je laatste verbinding gewijzigd zijn. De scanner controleert je actuele toegang.").font(.caption).foregroundStyle(.secondary) }
                }
            }.padding(20)
        }.background(Brand.background).navigationTitle("Mijn tickets").refreshable { await model.refresh() }
    }
}

private struct TicketRow: View {
    let ticket: Ticket
    var body: some View {
        HStack(spacing: 16) {
            ZStack { RoundedRectangle(cornerRadius: 16).fill(Brand.purple.opacity(0.1)); Image(systemName: ticket.isValid ? "qrcode" : "ticket").font(.title).foregroundStyle(Brand.purple) }.frame(width: 64, height: 72)
            VStack(alignment: .leading, spacing: 6) {
                Text(ticket.title).font(.headline).foregroundStyle(.primary)
                if let date = ticket.startsAt { Text(date.formatted(.dateTime.day().month(.abbreviated).hour().minute())).font(.caption).foregroundStyle(.secondary) }
                Label(ticket.statusLabel, systemImage: ticket.isValid ? "checkmark.circle.fill" : "clock").font(.caption.weight(.medium)).foregroundStyle(ticket.isValid ? .green : .secondary)
            }
            Spacer(minLength: 0); Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }.padding(18).background(Brand.card, in: RoundedRectangle(cornerRadius: 24))
    }
}

struct TicketDetailView: View {
    let ticket: Ticket
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    private var current: Ticket { model.tickets.first(where: { $0.id == ticket.id }) ?? ticket }
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image(systemName: "ticket.fill").font(.largeTitle).foregroundStyle(Brand.gold)
                    Text(current.title).font(.title.bold()).multilineTextAlignment(.center).foregroundStyle(.white)
                    if let date = current.startsAt { Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute())).font(.subheadline).foregroundStyle(.white.opacity(0.8)) }
                    if let location = current.location { Label(location, systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(.white.opacity(0.8)) }
                }.frame(maxWidth: .infinity).padding(28).background(Brand.deepPurple, in: RoundedRectangle(cornerRadius: 26))
                if model.signedIn, model.tickets.contains(where: { $0.id == current.id }), current.isValid, let token = current.qrToken, !token.isEmpty, let image = qrImage(token) {
                    VStack(spacing: 18) {
                        Image(uiImage: image).interpolation(.none).resizable().scaledToFit().frame(maxWidth: 270).padding(22).background(.white, in: RoundedRectangle(cornerRadius: 22)).accessibilityLabel("QR-code voor toegang tot \(current.title)")
                        Text("Laat deze code scannen bij de ingang.").font(.subheadline).foregroundStyle(.secondary)
                        Label("Persoonlijk ticket · deel je QR-code niet", systemImage: "lock.fill").font(.caption).foregroundStyle(.secondary)
                    }
                } else { EmptyState(icon: "clock", title: current.statusLabel, message: "Een geldige QR-code verschijnt nadat je inschrijving en eventuele betaling zijn bevestigd.") }
                if model.isOffline { Label("Offline ticket · status kan gewijzigd zijn", systemImage: "wifi.slash").font(.caption).foregroundStyle(.secondary) }
            }.padding(20)
        }.background(Brand.background).navigationTitle("Ticket").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Sluiten", systemImage: "xmark", action: { dismiss() }).labelStyle(.iconOnly) } }
        .privacySensitive()
    }
    private func qrImage(_ token: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(token.utf8)
        filter.correctionLevel = "H"
        guard let output = filter.outputImage else { return nil }
        let margin: CGFloat = 4
        let extent = output.extent.insetBy(dx: -margin, dy: -margin)
        let white = CIImage(color: CIColor.white).cropped(to: extent)
        let bordered = output.composited(over: white).transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cg = CIContext().createCGImage(bordered, from: bordered.extent) else { return nil }
        let plain = UIImage(cgImage: cg)
        guard let logo = UIImage(named: "QRLogo"), let logoCG = logo.cgImage,
              let owl = logoCG.cropping(to: CGRect(x: 0, y: 0, width: logoCG.width, height: Int(Double(logoCG.height) * 0.74))) else { return plain }
        // Reuse the website's owl artwork. Keep payloads on-device and check the
        // final composed image rather than assuming error correction is sufficient.
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: CIContext(), options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        for fraction in [0.22, 0.18, 0.14] {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let result = UIGraphicsImageRenderer(size: plain.size, format: format).image { context in
                plain.draw(at: .zero)
                let width = plain.size.width * fraction
                let height = width * CGFloat(owl.height) / CGFloat(owl.width)
                let rect = CGRect(x: (plain.size.width - width) / 2, y: (plain.size.height - height) / 2, width: width, height: height)
                UIColor.white.setFill()
                context.fill(rect.insetBy(dx: -5, dy: -5))
                UIImage(cgImage: owl).draw(in: rect)
            }
            if let image = CIImage(image: result), detector?.features(in: image).contains(where: { ($0 as? CIQRCodeFeature)?.messageString == token }) == true { return result }
        }
        return plain
    }
}
