import AppIntents
import SwiftUI
import UserNotifications
import WidgetKit

// MARK: - Timeline

struct FocusEntry: TimelineEntry {
    struct UpNext {
        let start: Date
        let item: WidgetSnapshot.FocusItem
    }

    let date: Date
    /// The most important thing to do right now, if anything.
    let item: WidgetSnapshot.FocusItem?
    /// The next change later today, so the widget can say what's coming.
    let upNext: UpNext?
    let score: Int?
    var isStale = false
}

/// Replays the day the app already planned: one entry per change, swapped in by WidgetKit at the
/// right time. No refresh policy, so the widget only does work when the app or a check-off asks.
struct FocusProvider: TimelineProvider {
    func placeholder(in context: Context) -> FocusEntry {
        Self.entries(from: .preview, done: [], now: .now).first!
    }

    func getSnapshot(in context: Context, completion: @escaping (FocusEntry) -> Void) {
        let stored = WidgetShared.loadSnapshot()
        let snapshot = context.isPreview && (stored?.focus.isEmpty ?? true) ? .preview : (stored ?? .empty)
        let done = Set(WidgetShared.loadCompletions().map(\.id))
        completion(Self.entries(from: snapshot, done: done, now: .now).first!)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FocusEntry>) -> Void) {
        let snapshot = WidgetShared.loadSnapshot() ?? .empty
        let done = Set(WidgetShared.loadCompletions().map(\.id))
        completion(Timeline(entries: Self.entries(from: snapshot, done: done, now: .now), policy: .never))
    }

    /// Entries from now until the snapshot runs out, skipping anything already checked off.
    /// Never empty.
    static func entries(from snapshot: WidgetSnapshot, done: Set<String>, now: Date) -> [FocusEntry] {
        let focus = snapshot.focus
        let score = snapshot.alignment?.value
        guard now < snapshot.validUntil else {
            return [FocusEntry(date: now, item: nil, upNext: nil, score: score, isStale: true)]
        }

        func visible(_ index: Int) -> [WidgetSnapshot.FocusItem] {
            focus[index].items.filter { !done.contains($0.id) }
        }

        let current = focus.lastIndex { $0.start <= now }
        var entries: [FocusEntry] = []
        for index in (current ?? 0)..<focus.count where focus[index].start < snapshot.validUntil {
            let showing = visible(index)
            let item = showing.first
            let shown = Set(showing.map(\.id))
            var upNext: FocusEntry.UpNext?
            for later in focus.indices where later > index {
                if let next = visible(later).first, !shown.contains(next.id) {
                    upNext = .init(start: focus[later].start, item: next)
                    break
                }
            }
            let entry = FocusEntry(date: index == current ? now : focus[index].start,
                                   item: item, upNext: upNext, score: score)
            if let last = entries.last, last.item == entry.item, last.upNext?.item == entry.upNext?.item { continue }
            entries.append(entry)
        }
        if entries.isEmpty {
            entries.append(FocusEntry(date: now, item: nil, upNext: nil, score: score))
        }
        entries.append(FocusEntry(date: snapshot.validUntil, item: nil, upNext: nil, score: score, isStale: true))
        return entries
    }
}

// MARK: - Check-off

/// "Done" on the Focus widget. Runs in the widget extension: it queues the check-off for the app
/// (which records it on its next refresh) and cancels that recommendation's pending nudge.
struct CompleteFocusIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark recommendation done"
    static var isDiscoverable = false

    @Parameter(title: "Recommendation") var recommendationID: String
    @Parameter(title: "Kind") var kind: String
    /// Set for a "Last night" question: the times being confirmed.
    @Parameter(title: "Asleep") var sleepOnset: Date?
    @Parameter(title: "Up") var sleepWake: Date?

    init() {}

    init(item: WidgetSnapshot.FocusItem) {
        recommendationID = item.id
        kind = item.kind
        sleepOnset = item.sleepOnset
        sleepWake = item.sleepWake
    }

    func perform() async throws -> some IntentResult {
        WidgetShared.addCompletion(WidgetCompletion(id: recommendationID, kind: kind, completedAt: .now,
                                                    sleepOnset: sleepOnset, sleepWake: sleepWake))
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [WidgetShared.nudgeIdentifierPrefix + recommendationID])
        return .result()
    }
}

// MARK: - Widget

struct FocusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.focusKind, provider: FocusProvider()) { entry in
            FocusWidgetView(entry: entry)
        }
        .configurationDisplayName("Today's Focus")
        .description("The one thing that helps your rhythm most right now. Tap the check when it's done.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct FocusWidgetView: View {
    let entry: FocusEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .circadiaBackground(family)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryRectangular: FocusRectangular(entry: entry)
        case .accessoryInline: FocusInline(entry: entry)
        case .systemMedium: FocusMedium(entry: entry)
        default: FocusSmall(entry: entry)
        }
    }
}

extension WidgetSnapshot.FocusItem {
    var tint: Color { isLight ? WidgetPalette.light : WidgetPalette.sleep }
}

private struct DoneButton: View {
    let item: WidgetSnapshot.FocusItem
    var labeled = false

    var body: some View {
        Button(intent: CompleteFocusIntent(item: item)) {
            if labeled {
                Label(item.isSleepLog ? "Yes" : "Done", systemImage: "checkmark")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(item.tint.opacity(0.18)))
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(item.tint.opacity(0.18)))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(item.tint)
        .accessibilityLabel(item.isSleepLog ? "Confirm last night's sleep times" : "Mark \(item.label.lowercased()) done")
    }
}

/// Shown when nothing needs doing right now, or the plan has run out.
private struct FocusIdle: View {
    let entry: FocusEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: entry.isStale ? "arrow.clockwise" : "checkmark.seal.fill")
                .font(.title3)
                .foregroundStyle(WidgetPalette.sleep)
            Text(entry.isStale ? "Open Circadia to plan today" : "Nothing pressing right now")
                .font(.headline)
                .lineLimit(3)
        }
    }
}

private struct UpNextLine: View {
    let upNext: FocusEntry.UpNext

    var body: some View {
        HStack(spacing: 6) {
            // Most titles already name their time ("Wind-down starts at 8:15 PM"); don't repeat it.
            Text(upNext.item.title.contains(where: \.isNumber)
                 ? "NEXT" : "NEXT \(upNext.start.formatted(date: .omitted, time: .shortened))")
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Text(upNext.item.title)
                .font(.caption)
                .lineLimit(1)
        }
    }
}

// MARK: - Home Screen

private struct FocusSmall: View {
    let entry: FocusEntry

    var body: some View {
        if let item = entry.item {
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(text: item.label, systemImage: item.systemImage, tint: item.tint)
                Text(item.title)
                    .font(.headline)
                    .lineLimit(4)
                    .minimumScaleFactor(0.8)
                    .invalidatableContent()
                Spacer(minLength: 0)
                HStack(alignment: .bottom) {
                    if let detail = item.detail {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    if item.canComplete { DoneButton(item: item) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(text: "Today's focus")
                Spacer(minLength: 0)
                FocusIdle(entry: entry)
                if let upNext = entry.upNext {
                    Text("Next at \(upNext.start.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct FocusMedium: View {
    let entry: FocusEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                WidgetHeader(text: "Today's focus")
                Spacer()
                if let score = entry.score {
                    Label("\(score)", systemImage: "sun.horizon.fill")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Alignment \(score)")
                }
            }
            if let item = entry.item {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: item.systemImage)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(item.tint)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(item.tint.opacity(0.15)))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.headline)
                            .lineLimit(2)
                            .invalidatableContent()
                        if let detail = item.detail {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                    if item.canComplete { DoneButton(item: item, labeled: true) }
                }
            } else {
                FocusIdle(entry: entry)
            }
            Spacer(minLength: 0)
            if let upNext = entry.upNext {
                UpNextLine(upNext: upNext)
            }
        }
    }
}

// MARK: - Lock Screen

private struct FocusRectangular: View {
    let entry: FocusEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let item = entry.item {
                Label(item.label, systemImage: item.systemImage)
                    .font(.caption2.weight(.semibold))
                    .widgetAccentable()
                Text(item.title)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(2)
            } else {
                Label("Today's focus", systemImage: "sun.horizon.fill")
                    .font(.caption2.weight(.semibold))
                    .widgetAccentable()
                Text(entry.isStale ? "Open Circadia to plan today" : "Nothing pressing right now")
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FocusInline: View {
    let entry: FocusEntry

    var body: some View {
        if let item = entry.item {
            Label(item.title, systemImage: item.systemImage)
        } else {
            Label("Nothing pressing", systemImage: "checkmark.seal")
        }
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    FocusWidget()
} timeline: {
    FocusProvider.entries(from: .preview, done: [], now: .now)[0]
}

#Preview("Medium", as: .systemMedium) {
    FocusWidget()
} timeline: {
    FocusProvider.entries(from: .preview, done: [], now: .now)[0]
}

#Preview("Lock Screen", as: .accessoryRectangular) {
    FocusWidget()
} timeline: {
    FocusProvider.entries(from: .preview, done: [], now: .now)[0]
}
