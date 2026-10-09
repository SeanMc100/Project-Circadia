import SwiftUI

/// "Tomorrow could be 84": the plan for today and tonight, and what each step is worth.
struct ForecastCard: View {
    let forecast: ScoreForecast
    @Environment(\.skyPhase) private var phase

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tomorrow could be").font(.subheadline).foregroundStyle(.secondary)
                    Text("\(forecast.projected)")
                        .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                }
                Spacer()
                ChangeBadge(change: forecast.change, suffix: "vs today")
            }
            .accessibilityElement(children: .combine)

            VStack(spacing: 10) {
                ForEach(forecast.steps) { step in
                    HStack(spacing: 12) {
                        Image(systemName: step.kind.systemImage)
                            .frame(width: 24)
                            .foregroundStyle(phase.palette.accent)
                            .accessibilityHidden(true)
                        Text(step.text)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        PointsLabel(points: step.points, zeroText: "keep")
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            Text(footnote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footnote: String {
        let gain = forecast.projected - forecast.withoutPlan
        if gain <= 0 {
            return "Last night's timing already scores well. Repeat it to hold your score."
        }
        let light = forecast.steps.contains { $0.kind == .morningLight } ? " with no more outdoor light today" : ""
        return "Repeating last night's timing\(light) would give about \(forecast.withoutPlan)."
    }
}

/// "+3" in green, "−2" in orange, or a word for zero.
struct PointsLabel: View {
    let points: Int
    var zeroText = "±0"

    var body: some View {
        Text(points == 0 ? zeroText : points > 0 ? "+\(points)" : "−\(abs(points))")
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .foregroundStyle(points > 0 ? Palette.favorable : points < 0 ? Palette.unfavorable : .secondary)
            .accessibilityLabel(points == 0 ? zeroText : "\(points > 0 ? "plus" : "minus") \(abs(points)) points")
    }
}

/// "▲ 6 vs today" pill.
struct ChangeBadge: View {
    let change: Int
    let suffix: String

    var body: some View {
        let tint: Color = change > 0 ? Palette.favorable : change < 0 ? Palette.unfavorable : .secondary
        Pill(text: change == 0 ? "Same as today" : "\(change > 0 ? "▲" : "▼") \(abs(change)) \(suffix)", tint: tint)
    }
}

/// A suggestion already checked off today: kept on screen, marked done.
struct CompletedRecommendationRow: View {
    let item: CompletedRecommendation
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(Palette.favorable)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.kind.title)
                    .font(.subheadline.weight(.semibold))
                    .strikethrough(true, color: .secondary)
                Text(item.detectedAutomatically
                     ? "Done at \(ClockMath.timeString(item.completedAt)) · seen by Apple Watch"
                     : "Done at \(ClockMath.timeString(item.completedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !item.detectedAutomatically {
                Button("Undo") { withAnimation { app.undoDone(item) } }
                    .font(.caption.weight(.medium))
                    .buttonStyle(.borderless)
                    .accessibilityHint("Marks this suggestion as not done")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.regularMaterial.opacity(0.7), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
