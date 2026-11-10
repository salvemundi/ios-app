import SwiftUI
import WidgetKit

private struct SalveEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

private struct SalveProvider: TimelineProvider {
    func placeholder(in context: Context) -> SalveEntry { .init(date: .now, snapshot: .empty) }
    func getSnapshot(in context: Context, completion: @escaping (SalveEntry) -> Void) { completion(.init(date: .now, snapshot: read())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SalveEntry>) -> Void) {
        let snapshot = read()
        let now = Date.now
        var entries = [SalveEntry(date: now, snapshot: snapshot)]
        // Drop past events at their start time even when the app hasn't opened again.
        for date in snapshot.events.compactMap(\.startsAt).filter({ $0 > now }) {
            entries.append(SalveEntry(date: date, snapshot: snapshot))
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
            HStack { Text("SALVE MUNDI").font(.caption2.bold()).tracking(1); Spacer(); Image(systemName: "calendar") }.foregroundStyle(Color(red: 0.95, green: 0.83, blue: 0.4))
            if events.isEmpty {
                Spacer(); Text("Binnenkort meer").font(.headline); Text("Open de app voor de agenda.").font(.caption).opacity(0.8); Spacer()
            } else {
                ForEach(events.prefix(family == .systemMedium ? 2 : 1)) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.title).font(.headline).lineLimit(2)
                        if let date = event.startsAt { Text(date.formatted(.dateTime.day().month(.abbreviated).hour().minute())).font(.caption).opacity(0.8) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if family == .systemMedium && event.id != events.prefix(2).last?.id { Divider().overlay(.white.opacity(0.2)) }
                }
                Spacer(minLength: 0)
            }
            if entry.date.timeIntervalSince(entry.snapshot.updatedAt) > 86400 { Text("Open de app om bij te werken").font(.caption2).opacity(0.65) }
        }
        .foregroundStyle(.white)
        .containerBackground(Color(red: 0.20, green: 0.13, blue: 0.24), for: .widget)
        .widgetURL(events.first?.deepLink ?? URL(string: "salvemundi://activities"))
    }
}

private struct NextBookingWidgetView: View {
    let entry: SalveEntry
    private var booking: WidgetEvent? { guard entry.date.timeIntervalSince(entry.snapshot.updatedAt) < 86400, let event = entry.snapshot.nextBooking, (event.startsAt ?? .distantFuture) > entry.date else { return nil }; return event }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("JIJ BENT ERBIJ", systemImage: "ticket.fill").font(.caption2.bold()).foregroundStyle(Color(red: 0.95, green: 0.83, blue: 0.4))
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
        .containerBackground(Color(red: 0.40, green: 0.25, blue: 0.44), for: .widget)
        .widgetURL(URL(string: "salvemundi://tickets"))
    }
}

struct UpcomingActivitiesWidget: Widget {
    let kind = "UpcomingActivities"
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

@main
struct SalveMundiWidgets: WidgetBundle {
    var body: some Widget { UpcomingActivitiesWidget(); NextBookedEventWidget() }
}
