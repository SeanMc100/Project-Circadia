import SwiftUI
import WidgetKit

// MARK: - Timeline

struct AlignmentEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    /// The app hasn't refreshed in a long time; the score may be out of date.
    var isStale = false
}

/// One entry, plus a "stale" entry when the snapshot runs out. Never schedules its own refreshes:
/// the app reloads this widget only when the score actually changes.
struct AlignmentProvider: TimelineProvider {
    func placeholder(in context: Context) -> AlignmentEntry {
        AlignmentEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (AlignmentEntry) -> Void) {
        let stored = WidgetShared.loadSnapshot()
        let snapshot = context.isPreview && stored?.alignment == nil ? .preview : (stored ?? .empty)
        completion(AlignmentEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AlignmentEntry>) -> Void) {
        let snapshot = WidgetShared.loadSnapshot() ?? .empty
        let now = Date.now
        var entries = [AlignmentEntry(date: now, snapshot: snapshot, isStale: snapshot.validUntil <= now)]
        if snapshot.validUntil > now {
            entries.append(AlignmentEntry(date: snapshot.validUntil, snapshot: snapshot, isStale: true))
        }
        completion(Timeline(entries: entries, policy: .never))
    }
}

// MARK: - Widget

struct AlignmentWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.alignmentKind, provider: AlignmentProvider()) { entry in
            AlignmentWidgetView(entry: entry)
        }
        .configurationDisplayName("Alignment")
        .description("Your body-clock alignment estimate and what's driving it.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct AlignmentWidgetView: View {
    let entry: AlignmentEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .circadiaBackground(family)
    }

    @ViewBuilder
    private var content: some View {
        let alignment = entry.snapshot.alignment
        switch family {
        case .accessoryCircular: AlignmentCircular(alignment: alignment)
        case .accessoryRectangular: AlignmentRectangular(alignment: alignment, status: entry.snapshot.statusText)
        case .accessoryInline: AlignmentInline(alignment: alignment)
        case .systemMedium: AlignmentMedium(entry: entry)
        default: AlignmentSmall(entry: entry)
        }
    }
}

// MARK: - Home Screen

/// The score inside a ring that fills with the sky band from the Today screen.
struct ScoreRing: View {
    let alignment: WidgetSnapshot.Alignment?
    var lineWidth: CGFloat = 9
    var valueSize: CGFloat = 38

    var body: some View {
        ZStack {
            Circle().stroke(WidgetPalette.track, lineWidth: lineWidth)
            if let alignment {
                Circle()
                    .trim(from: 0, to: alignment.fraction)
                    .stroke(AngularGradient(colors: WidgetPalette.ring, center: .center,
                                            startAngle: .degrees(0), endAngle: .degrees(360 * alignment.fraction)),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .widgetAccentable()
            }
            VStack(spacing: 0) {
                Text(alignment.map { "\($0.value)" } ?? "–")
                    .font(.system(size: valueSize, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if let band = alignment?.band {
                    Text(band)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WidgetPalette.sleep)
                }
            }
            .padding(lineWidth + 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Alignment estimate")
        .accessibilityValue(alignment.map { "\($0.value) out of 100, \($0.band)" } ?? "Not available yet")
    }
}

private struct AlignmentSmall: View {
    let entry: AlignmentEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(text: "Alignment")
            ScoreRing(alignment: entry.snapshot.alignment)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let footnote {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var footnote: String? {
        if entry.isStale { return "Open Circadia to update" }
        return entry.snapshot.alignment == nil ? entry.snapshot.statusText : nil
    }
}

private struct AlignmentMedium: View {
    let entry: AlignmentEntry

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                WidgetHeader(text: "Alignment")
                ScoreRing(alignment: entry.snapshot.alignment, lineWidth: 10, valueSize: 40)
            }
            .frame(width: 118)

            VStack(alignment: .leading, spacing: 9) {
                if let alignment = entry.snapshot.alignment {
                    ForEach(alignment.components, id: \.kind) { component in
                        ComponentRow(component: component)
                    }
                } else {
                    Text(entry.snapshot.statusText ?? "Not enough data yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if entry.isStale {
                    Text("Open Circadia to update")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ComponentRow: View {
    let component: WidgetSnapshot.Component

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(component.title).font(.caption.weight(.medium))
                Spacer(minLength: 4)
                Text(component.value.map { "\(Int(($0 * 100).rounded()))" } ?? "n/a")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(component.value == nil ? .secondary : .primary)
            }
            WidgetBar(value: component.value)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(component.title)
        .accessibilityValue(component.value.map { "\(Int(($0 * 100).rounded())) out of 100" } ?? "Not available")
    }
}

// MARK: - Lock Screen

private struct AlignmentCircular: View {
    let alignment: WidgetSnapshot.Alignment?

    var body: some View {
        Gauge(value: alignment?.fraction ?? 0) {
            Image(systemName: "sun.horizon.fill")
        } currentValueLabel: {
            Text(alignment.map { "\($0.value)" } ?? "–")
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccentable()
    }
}

private struct AlignmentRectangular: View {
    let alignment: WidgetSnapshot.Alignment?
    let status: String?

    var body: some View {
        if let alignment {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(alignment.value)")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .widgetAccentable()
                    Text(alignment.band)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                }
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(alignment.components, id: \.kind) { component in
                        HStack(spacing: 5) {
                            Text(shortTitle(component.kind))
                                .font(.system(size: 10, weight: .medium))
                                .frame(width: 58, alignment: .leading)
                            WidgetBar(value: component.value, tint: .primary, height: 4)
                        }
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("Alignment").font(.headline).widgetAccentable()
                Text(status ?? "Not enough data yet").font(.caption).lineLimit(2)
            }
        }
    }

    private func shortTitle(_ kind: String) -> String {
        switch kind {
        case "consistency": "Consistency"
        case "morningLight": "Light"
        default: "Drift"
        }
    }
}

private struct AlignmentInline: View {
    let alignment: WidgetSnapshot.Alignment?

    var body: some View {
        if let alignment {
            Label("Alignment \(alignment.value) · \(alignment.band)", systemImage: "sun.horizon.fill")
        } else {
            Label("Alignment calibrating", systemImage: "sun.horizon.fill")
        }
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    AlignmentWidget()
} timeline: {
    AlignmentEntry(date: .now, snapshot: .preview)
}

#Preview("Medium", as: .systemMedium) {
    AlignmentWidget()
} timeline: {
    AlignmentEntry(date: .now, snapshot: .preview)
    AlignmentEntry(date: .now, snapshot: .calibratingPreview)
}

#Preview("Lock Screen", as: .accessoryRectangular) {
    AlignmentWidget()
} timeline: {
    AlignmentEntry(date: .now, snapshot: .preview)
}

#Preview("Circular", as: .accessoryCircular) {
    AlignmentWidget()
} timeline: {
    AlignmentEntry(date: .now, snapshot: .preview)
}
