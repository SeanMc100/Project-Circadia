import SwiftUI

/// The standard surface for content blocks.
struct Card<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(1.2)
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

struct Pill: View {
    let text: String
    var tint: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(tint)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

/// A labelled 0...1 bar for one score component.
struct ComponentBar: View {
    let component: ScoreComponent
    @Environment(\.skyPhase) private var phase

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(component.kind.title).font(.subheadline.weight(.medium))
                Spacer()
                if let value = component.value {
                    Text("\(Int((value * 100).rounded()))").font(.subheadline.monospacedDigit().weight(.semibold))
                    Text("· \(Int((component.weight * 100).rounded()))% weight").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("n/a").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.track)
                    Capsule().fill(phase.palette.accent)
                        .frame(width: geo.size.width * CGFloat(component.value ?? 0))
                }
            }
            .frame(height: 6)
            Text(component.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(component.kind.title)
        .accessibilityValue(component.value.map { "\(Int(($0 * 100).rounded())) out of 100. \(component.detail)" } ?? "Not available. \(component.detail)")
    }
}

struct WellnessNote: View {
    var compact = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "heart.text.square").foregroundStyle(.secondary).accessibilityHidden(true)
            Text(compact
                 ? "Wellness tool, not medical advice."
                 : "Circadia is a wellness tool, not medical advice, and it doesn't diagnose anything. If sleep problems persist or affect your daytime life, talk with a clinician.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var progress: Double?

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: systemImage).font(.title2).foregroundStyle(.secondary).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.headline)
                    Text(message).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let progress {
                        ProgressView(value: progress).padding(.top, 4)
                    }
                }
            }
        }
    }
}

extension Binding where Value == Date {
    /// Binds a DatePicker (hour + minute) to minutes-after-midnight.
    static func minutes(_ get: @escaping () -> Double, _ set: @escaping (Double) -> Void) -> Binding<Date> {
        Binding<Date>(
            get: { ClockMath.date(on: Date(), minutes: ClockMath.wrapPositive(get())) },
            set: { set(ClockMath.minutesFromMidnight($0).rounded()) })
    }
}
