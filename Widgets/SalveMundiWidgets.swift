import SwiftUI
import WidgetKit
import AppIntents
#if !targetEnvironment(macCatalyst)
import ActivityKit
#endif


// Widgets cannot be swiped, so paging uses interactive buttons. Only a page number is shared via the app group.
enum WidgetPaging {
    static let upcomingKind = "UpcomingActivities"
    static let adminKind = "AdminActivitySignups"
    static func key(_ kind: String) -> String { "widget.page.\(kind)" }
    static func page(_ kind: String) -> Int { UserDefaults(suiteName: WidgetSnapshot.appGroup)?.integer(forKey: key(kind)) ?? 0 }
    static func index(_ page: Int, count: Int) -> Int { count > 0 ? ((page % count) + count) % count : 0 }
}

struct WidgetPageIntent: AppIntent {
    static let title: LocalizedStringResource = "Andere activiteit"
    static let isDiscoverable = false
    @Parameter(title: "Widget") var kind: String
    @Parameter(title: "Stap") var delta: Int
    init() {}
    init(kind: String, delta: Int) { self.kind = kind; self.delta = delta }
    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: WidgetSnapshot.appGroup)
        let current = defaults?.integer(forKey: WidgetPaging.key(kind)) ?? 0
        defaults?.set((current + delta) % 1000, forKey: WidgetPaging.key(kind))
        return .result()
    }
}

private struct PagerControls: View {
    let kind: String, index: Int, count: Int
    var body: some View {
        HStack(spacing: 10) {
            Button(intent: WidgetPageIntent(kind: kind, delta: -1)) { Image(systemName: "chevron.left").frame(minWidth: 28, minHeight: 28).contentShape(Rectangle()) }.accessibilityLabel("Vorige activiteit")
            Text("\(index + 1)/\(count)").font(.caption2.monospacedDigit()).opacity(0.8)
            Button(intent: WidgetPageIntent(kind: kind, delta: 1)) { Image(systemName: "chevron.right").frame(minWidth: 28, minHeight: 28).contentShape(Rectangle()) }.accessibilityLabel("Volgende activiteit")
        }.buttonStyle(.plain).font(.caption.bold())
    }
}

/// Brand purple for widget backgrounds: donker paars #5A3761 in light, a deeper #3D2442 in Dark Mode (white on it: 13:1).
private enum WidgetColors {
    static let purple = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.239, green: 0.141, blue: 0.259, alpha: 1) : UIColor(red: 0.353, green: 0.216, blue: 0.380, alpha: 1) })
}

private struct SalveEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    var page = 0
}

private struct SalveProvider: TimelineProvider {
    func placeholder(in context: Context) -> SalveEntry { .init(date: .now, snapshot: .empty) }
    func getSnapshot(in context: Context, completion: @escaping (SalveEntry) -> Void) { completion(.init(date: .now, snapshot: read(), page: WidgetPaging.page(WidgetPaging.upcomingKind))) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SalveEntry>) -> Void) {
        let snapshot = read()
        let now = Date.now
        let page = WidgetPaging.page(WidgetPaging.upcomingKind)
        var entries = [SalveEntry(date: now, snapshot: snapshot, page: page)]
        // Drop past events at their start time even when the app hasn't opened again.
        for date in snapshot.events.compactMap(\.startsAt).filter({ $0 > now }) {
            entries.append(SalveEntry(date: date, snapshot: snapshot, page: page))
        }
        completion(Timeline(entries: entries.sorted { $0.date < $1.date }, policy: .after(now.addingTimeInterval(1800))))
    }
    private func read() -> WidgetSnapshot {
        guard let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.appGroup),
              let data = try? Data(contentsOf: directory.appendingPathComponent(WidgetSnapshot.fileName)),
              let snapshot = try? JSONCoding.decoder().decode(WidgetSnapshot.self, from: data) else { return .empty }
        return snapshot
    }
}

private struct UpcomingWidgetView: View {
    let entry: SalveEntry
    @Environment(\.widgetFamily) private var family
    private var events: [WidgetEvent] { entry.snapshot.events.filter { ($0.startsAt ?? .distantFuture) > entry.date } }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("SALVE MUNDI").font(.caption2.bold()).tracking(1); Spacer(); Image(systemName: "calendar") }.foregroundStyle(Color(red: 0.973, green: 0.812, blue: 0.271)).widgetAccentable()
            if events.isEmpty {
                Spacer(); Text("Binnenkort meer").font(.headline); Text("Open de app voor de agenda.").font(.caption).opacity(0.8); Spacer()
            } else {
                let perPage = family == .systemMedium ? 2 : 1
                let start = WidgetPaging.index(entry.page, count: events.count)
                let visible = (0..<min(perPage, events.count)).map { events[(start + $0) % events.count] }
                ForEach(visible) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.title).font(.headline).lineLimit(family == .systemSmall ? 3 : 2).minimumScaleFactor(0.8)
                        if let date = event.startsAt { Text(date.formatted(.dateTime.day().month(.abbreviated).hour().minute())).font(.caption).opacity(0.8) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if family == .systemMedium && event.id != visible.last?.id { Divider().overlay(.white.opacity(0.2)) }
                }
                Spacer(minLength: 0)
                if events.count > perPage { PagerControls(kind: WidgetPaging.upcomingKind, index: start, count: events.count) }
            }
            if entry.date.timeIntervalSince(entry.snapshot.updatedAt) > 86400 { Text("Open de app om bij te werken").font(.caption2).opacity(0.65) }
        }
        .foregroundStyle(.white)
        .containerBackground(WidgetColors.purple, for: .widget)
        .widgetURL(events.isEmpty ? URL(string: "salvemundi://activities") : events[WidgetPaging.index(entry.page, count: events.count)].deepLink)
    }
}

private struct NextBookingWidgetView: View {
    let entry: SalveEntry
    private var booking: WidgetEvent? { guard entry.date.timeIntervalSince(entry.snapshot.updatedAt) < 86400, let event = entry.snapshot.nextBooking, (event.startsAt ?? .distantFuture) > entry.date else { return nil }; return event }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("JIJ BENT ERBIJ", systemImage: "ticket.fill").font(.caption2.bold()).foregroundStyle(Color(red: 0.973, green: 0.812, blue: 0.271)).widgetAccentable()
            Spacer(minLength: 0)
            if let booking {
                Text(booking.title).font(.headline).lineLimit(2).privacySensitive()
                if let date = booking.startsAt { Text(date.formatted(.dateTime.day().month(.abbreviated).hour().minute())).font(.caption).privacySensitive() }
                Label("Open je ticket", systemImage: "qrcode").font(.caption2).opacity(0.8)
            } else {
                Text(entry.snapshot.signedIn ? "Nog niets gepland" : "Log in op de app").font(.headline)
                Text("Je volgende activiteit verschijnt hier.").font(.caption).opacity(0.8)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .containerBackground(Color(red: 0.075, green: 0.165, blue: 0.251), for: .widget)
        .widgetURL(URL(string: "salvemundi://tickets"))
    }
}

struct UpcomingActivitiesWidget: Widget {
    let kind = WidgetPaging.upcomingKind
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SalveProvider()) { UpcomingWidgetView(entry: $0) }
            .configurationDisplayName("Binnenkort bij Salve Mundi")
            .description("De eerstvolgende activiteiten op je beginscherm.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct NextBookedEventWidget: Widget {
    let kind = "NextBookedEvent"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SalveProvider()) { NextBookingWidgetView(entry: $0) }
            .configurationDisplayName("Mijn volgende activiteit")
            .description("Jouw eerstvolgende bevestigde activiteit, met een link naar je tickets.")
            .supportedFamilies([.systemSmall])
    }
}

private struct AdminCountsEntry: TimelineEntry {
    let date: Date
    let summary: AdminWidgetSummary?
    var page = 0
}

// WidgetKit's legacy callback is not annotated Sendable. Transfer the immutable
// callback to one task and invoke it exactly once; it is never used by the caller again.
private struct AdminTimelineCompletion: @unchecked Sendable {
    let complete: (Timeline<AdminCountsEntry>) -> Void
}

private struct AdminCountsProvider: TimelineProvider {
    func placeholder(in context: Context) -> AdminCountsEntry { .init(date: .now, summary: nil) }
    func getSnapshot(in context: Context, completion: @escaping (AdminCountsEntry) -> Void) {
        // Gallery previews never reveal committee information.
        completion(.init(date: .now, summary: context.isPreview ? nil : AdminWidgetSnapshotStore.read(), page: WidgetPaging.page(WidgetPaging.adminKind)))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<AdminCountsEntry>) -> Void) {
        let callback = AdminTimelineCompletion(complete: completion)
        Task {
            let summary = await AdminWidgetRefresh.fetch()
            let now = Date.now
            let page = WidgetPaging.page(WidgetPaging.adminKind)
            var entries = [AdminCountsEntry(date: now, summary: summary, page: page)]
            if let summary, summary.isFresh(at: now) {
                // Redact at a fixed deadline even if iOS postpones the next network refresh.
                entries.append(AdminCountsEntry(date: summary.displayDeadline, summary: nil, page: page))
            }
            callback.complete(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
        }
    }
}

private struct AdminCountsView: View {
    let entry: AdminCountsEntry
    @Environment(\.widgetFamily) private var family
    private var summary: AdminWidgetSummary? {
        guard let summary = entry.summary, summary.isFresh(at: entry.date) else { return nil }
        return summary
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("AANMELDINGEN", systemImage: "person.2.fill").font(.caption2.bold())
                Spacer(minLength: 0)
                Image(systemName: "lock.fill").font(.caption2)
            }.foregroundStyle(Color(red: 0.973, green: 0.812, blue: 0.271)).widgetAccentable()
            if let summary, !summary.items.isEmpty {
                let perPage = family == .systemMedium ? 2 : 1
                let start = WidgetPaging.index(entry.page, count: summary.items.count)
                let visible = (0..<min(perPage, summary.items.count)).map { summary.items[(start + $0) % summary.items.count] }
                ForEach(visible) { activity in
                    if family == .systemSmall {
                        // One activity, full name first; the count gets the space it needs below.
                        VStack(alignment: .leading, spacing: 2) {
                            Text(activity.title).font(.subheadline.weight(.semibold)).lineLimit(3).minimumScaleFactor(0.8).fixedSize(horizontal: false, vertical: true)
                            if let date = activity.startsAt { Text(date.formatted(.dateTime.day().month(.abbreviated))).font(.caption2).opacity(0.8) }
                            Spacer(minLength: 0)
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(activity.capacity.map { "\(activity.confirmedCount)/\($0)" } ?? "\(activity.confirmedCount)").font(.title.bold().monospacedDigit()).minimumScaleFactor(0.7).widgetAccentable().lineLimit(1)
                                Text("bevestigd").font(.caption2).opacity(0.8)
                            }
                            Text(activity.pendingCount > 0 ? "\(activity.checkedInCount) ingecheckt · \(activity.pendingCount) open" : "\(activity.checkedInCount) ingecheckt").font(.caption2).opacity(0.8).lineLimit(1).minimumScaleFactor(0.8)
                        }.privacySensitive()
                    } else {
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(activity.title).font(.caption.weight(.semibold)).lineLimit(2)
                                if activity.pendingCount > 0 { Text("\(activity.pendingCount) wacht op betaling").font(.caption2).opacity(0.8) }
                                Text("\(activity.checkedInCount) ingecheckt").font(.caption2).opacity(0.8)
                            }
                            Spacer(minLength: 0)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(activity.capacity.map { "\(activity.confirmedCount)/\($0)" } ?? "\(activity.confirmedCount)").font(.headline.monospacedDigit()).widgetAccentable()
                                Text("bevestigd").font(.caption2).opacity(0.8)
                            }
                        }.privacySensitive()
                    }
                }
                if family != .systemSmall { Spacer(minLength: 0) }
                HStack {
                    if summary.items.count > perPage { PagerControls(kind: WidgetPaging.adminKind, index: start, count: summary.items.count) }
                    Spacer(minLength: 0)
                    if family == .systemMedium { Text("Bijgewerkt \(summary.fetchedAt.formatted(.dateTime.hour().minute()))").font(.caption2).opacity(0.65) }
                }
            } else {
                Spacer(minLength: 0)
                Text(summary == nil ? "Open de app" : "Geen activiteiten").font(.headline)
                Text(summary == nil ? "Log in of vernieuw je beheerrechten." : "Je toegankelijke activiteiten verschijnen hier.").font(.caption).opacity(0.8)
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(.white)
        .containerBackground(WidgetColors.purple, for: .widget)
        .widgetURL(family == .systemSmall && summary != nil && !(summary?.items.isEmpty ?? true) ? summary?.items[WidgetPaging.index(entry.page, count: summary?.items.count ?? 0)].deepLink : URL(string: "salvemundi://admin/activities"))
    }
}

struct AdminActivitySignupsWidget: Widget {
    let kind = WidgetPaging.adminKind
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AdminCountsProvider()) { AdminCountsView(entry: $0) }
            .configurationDisplayName("Activiteiten: aanmeldingen")
            .description("Bevestigde aanmeldingen voor activiteiten die je mag beheren. Geen deelnemersgegevens.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct SalveMundiWidgets: WidgetBundle {
    var body: some Widget {
        UpcomingActivitiesWidget(); NextBookedEventWidget(); AdminActivitySignupsWidget()
        #if !targetEnvironment(macCatalyst)
        SalveEventLiveActivity()
        #endif
    }
}

#if !targetEnvironment(macCatalyst)
private struct SalveEventLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SalveEventActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                if context.isStale || context.state.event.expiresAt <= .now {
                    Label("Open de app om je activiteit te controleren", systemImage: "clock").font(.headline)
                } else {
                    HStack { Text("SALVE MUNDI").font(.caption.bold()); Spacer(); Image(systemName: "ticket.fill") }.foregroundStyle(.yellow)
                    Text(context.state.event.title).font(.headline).lineLimit(2)
                    Label(context.state.event.startsAt.formatted(.dateTime.hour().minute()), systemImage: "clock")
                    if let location = context.state.event.location, !location.isEmpty { Label(location, systemImage: "mappin.and.ellipse").lineLimit(1) }
                    if let url = context.state.event.deepLink { Link("Open mijn ticket", destination: url).font(.subheadline.bold()).foregroundStyle(.yellow) }
                }
            }.padding(16).activityBackgroundTint(WidgetColors.purple).activitySystemActionForegroundColor(.white).foregroundStyle(.white)
            .widgetURL(context.state.event.deepLink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: "ticket.fill").foregroundStyle(.yellow) }
                DynamicIslandExpandedRegion(.trailing) { Text(context.state.event.startsAt.formatted(.dateTime.hour().minute())).font(.headline) }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.isStale || context.state.event.expiresAt <= .now { Text("Open de app om je activiteit te controleren") }
                    else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(context.state.event.title).font(.headline).lineLimit(1)
                            if let location = context.state.event.location { Text(location).font(.caption).lineLimit(1) }
                            if let url = context.state.event.deepLink { Link("Open mijn ticket", destination: url).foregroundStyle(.yellow) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } compactLeading: { Image(systemName: "ticket.fill").foregroundStyle(.yellow) }
            compactTrailing: { Text(context.isStale ? "—" : context.state.event.startsAt.formatted(.dateTime.hour().minute())).font(.caption) }
            minimal: { Image(systemName: context.isStale ? "clock" : "ticket.fill").foregroundStyle(.yellow) }
            .widgetURL(context.state.event.deepLink)
            .keylineTint(.yellow)
        }
    }
}
#endif
