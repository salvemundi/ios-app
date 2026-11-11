import SwiftUI
import ImageIO
import AVFoundation
import UIKit

extension Color {
    init(hex: UInt32) { self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1) }
}

enum Brand {
    static let purple = Color(hex: 0x65406F)
    static let deepPurple = Color(hex: 0x33213D)
    static let gold = Color(hex: 0xF4D466)
    static let background = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
}

struct PrimaryButtonStyle: ButtonStyle {
    var gold = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(gold ? Brand.gold : Brand.purple, in: RoundedRectangle(cornerRadius: 18))
            .foregroundStyle(gold ? Brand.deepPurple : .white)
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct SectionHeading: View {
    let title: String
    var body: some View { Text(title).font(.title2.bold()).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading) }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 40, weight: .light)).foregroundStyle(Brand.purple)
            Text(title).font(.title3.bold())
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(32)
        .background(Brand.card, in: RoundedRectangle(cornerRadius: 24))
    }
}

struct ActivityCard: View {
    @Environment(AppModel.self) private var model
    let activity: Activity
    var featured = false
    private var registrationTicket: Ticket? {
        guard model.signedIn else { return nil }
        let matching = model.tickets.filter { $0.activityID == activity.id }
        return matching.first(where: { $0.isValid }) ?? matching.first(where: { ["open", "pending"].contains($0.status.lowercased()) })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [Brand.purple, Brand.deepPurple], startPoint: .topLeading, endPoint: .bottomTrailing)
                if let url = activity.imageURL {
                    ActivityBanner(url: url)
                    LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                } else {
                    Image(systemName: activity.kind == "pub_crawl" ? "sparkles" : "calendar")
                        .font(.system(size: 85, weight: .ultraLight)).rotationEffect(.degrees(-12))
                        .foregroundStyle(.white.opacity(0.12)).frame(maxWidth: .infinity, alignment: .trailing).padding(20)
                }
                HStack {
                    if let date = activity.startsAt { Text(date.formatted(.dateTime.day().month(.abbreviated)).uppercased()).font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 8).background(.ultraThinMaterial, in: Capsule()) }
                    Spacer()
                    Text(activity.price).font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 8).background(Brand.gold, in: Capsule()).foregroundStyle(Brand.deepPurple)
                }.padding(16)
            }
            .frame(height: featured ? 185 : 145).clipped()
            .saturation(activity.isPast() ? 0 : 1)
            VStack(alignment: .leading, spacing: 10) {
                if let ticket = registrationTicket {
                    Label(ticket.isValid ? "Aangemeld" : "Betaling in behandeling", systemImage: ticket.isValid ? "checkmark.circle.fill" : "clock")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ticket.isValid ? Color.green : Color.orange)
                    if model.isOffline { Text("Status bij laatste verbinding").font(.caption2).foregroundStyle(.secondary) }
                }
                Text(activity.title).font(featured ? .title3.bold() : .headline).foregroundStyle(.primary).lineLimit(2)
                HStack(spacing: 12) {
                    if let date = activity.startsAt { Label(date.formatted(.dateTime.hour().minute()), systemImage: "clock") }
                    if let location = activity.location, !location.isEmpty { Label(location, systemImage: "mappin.and.ellipse").lineLimit(1) }
                }.font(.caption).foregroundStyle(.secondary)
                if activity.membersOnly { Label("Voor leden", systemImage: "person.crop.circle.badge.checkmark").font(.caption.weight(.medium)).foregroundStyle(Brand.purple) }
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Brand.card, in: RoundedRectangle(cornerRadius: 24))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.primary.opacity(0.04), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 24))
    }
}

// UIImageView animates GIF frames; AsyncImage only displays their first frame.
struct ActivityBanner: View {
    let url: URL
    var fit = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: UIImage?
    @State private var videoURL: URL?
    var body: some View {
        Group {
            if let videoURL, !reduceMotion {
                LoopingActivityVideo(url: videoURL, fit: fit, animate: !reduceMotion)
            } else {
                AnimatedBannerImage(image: image, fit: fit, animate: !reduceMotion)
            }
        }
            .accessibilityHidden(true)
            .task(id: url) {
                image = nil
                videoURL = nil
                do {
                    let (data, response) = try await URLSession.shared.data(from: url)
                    guard !Task.isCancelled, (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 20_000_000 else { return }
                    // Website banners can be video assets, even when described as GIFs.
                    // Asset URLs contain IDs, so detect the response rather than the suffix.
                    if response.mimeType?.hasPrefix("video/") == true {
                        videoURL = url
                        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
                        generator.appliesPreferredTrackTransform = true
                        generator.maximumSize = CGSize(width: 900, height: 900)
                        if let frame = try? await generator.image(at: .zero), !Task.isCancelled {
                            image = UIImage(cgImage: frame.image)
                        }
                        return
                    }
                    let decoded = await Task.detached(priority: .utility) { Self.decode(data) }.value
                    guard !Task.isCancelled else { return }
                    image = decoded
                } catch { /* Keep the card's gradient when the image is unavailable. */ }
            }
    }
    nonisolated private static func decode(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }
        // Bound decoded memory, including long animated banners.
        let frameCount = min(count, 200)
        let dimension = min(900, Int(sqrt(12_000_000.0 / Double(frameCount))))
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: dimension, kCGImageSourceCreateThumbnailWithTransform: true]
        var frames: [UIImage] = []
        var duration = 0.0
        for i in 0..<frameCount {
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, i, options as CFDictionary) else { continue }
            let frame = UIImage(cgImage: cg)
            let properties = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
            let ticks = min(100, max(2, Int((delay * 50).rounded())))
            frames.append(contentsOf: repeatElement(frame, count: ticks))
            duration += Double(ticks) / 50
        }
        guard let first = frames.first else { return nil }
        return count == 1 ? first : UIImage.animatedImage(with: frames, duration: duration)
    }
}

private struct AnimatedBannerImage: UIViewRepresentable {
    let image: UIImage?
    let fit: Bool
    let animate: Bool
    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.clipsToBounds = true
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }
    func updateUIView(_ view: UIImageView, context: Context) {
        view.contentMode = fit ? .scaleAspectFit : .scaleAspectFill
        view.stopAnimating()
        view.animationImages = nil
        view.image = image?.images?.first ?? image
        if animate, let frames = image?.images, !frames.isEmpty {
            view.animationImages = frames
            view.animationDuration = image?.duration ?? 0
            view.animationRepeatCount = 0
            view.startAnimating()
        }
    }
    static func dismantleUIView(_ view: UIImageView, coordinator: ()) { view.stopAnimating(); view.animationImages = nil; view.image = nil }
}

// Keep media silent and looping; no full-screen playback controls in a banner.
private struct LoopingActivityVideo: UIViewRepresentable {
    let url: URL
    let fit: Bool
    let animate: Bool
    func makeUIView(context: Context) -> ActivityVideoSurface { ActivityVideoSurface() }
    func updateUIView(_ view: ActivityVideoSurface, context: Context) {
        view.configure(url: url, fit: fit, animate: animate)
    }
    static func dismantleUIView(_ view: ActivityVideoSurface, coordinator: ()) { view.clear() }
}

private final class ActivityVideoSurface: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    private var queue: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var sourceURL: URL?
    private var shouldAnimate = false
    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        NotificationCenter.default.addObserver(self, selector: #selector(pauseForBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resumeAfterBackground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(url: URL, fit: Bool, animate: Bool) {
        shouldAnimate = animate
        playerLayer.videoGravity = fit ? .resizeAspect : .resizeAspectFill
        if sourceURL != url {
            clear()
            sourceURL = url
            let player = AVQueuePlayer()
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            queue = player
            playerLayer.player = player
        }
        if animate && window != nil { queue?.play() } else { queue?.pause() }
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil && shouldAnimate { queue?.play() } else { queue?.pause() }
    }
    @objc private func pauseForBackground() { queue?.pause() }
    @objc private func resumeAfterBackground() { if window != nil && shouldAnimate { queue?.play() } }
    func clear() {
        queue?.pause()
        looper?.disableLooping()
        looper = nil
        queue?.removeAllItems()
        queue = nil
        playerLayer.player = nil
        sourceURL = nil
    }
    deinit { NotificationCenter.default.removeObserver(self) }
}
