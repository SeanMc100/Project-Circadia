import SwiftUI

struct RecommendationCard: View {
    let recommendation: Recommendation
    @Environment(AppModel.self) private var app
    @Environment(\.skyPhase) private var phase
    @State private var expanded = false
    @State private var askMinutes = false

    /// Done on a light card asks how long so the score can use it. With a Watch, the answer tops up
    /// what the Watch saw, since it misses time outside (a sleeve over it, an arm in a pocket).
    private var asksForMinutes: Bool { recommendation.kind.isLightKind }

    /// The usual choices plus the card's own goal, e.g. 10, 20, 25, 30 on an overcast morning.
    private var minuteChoices: [Double] {
        var choices = Set(CircadianConfig.reportedLightChoices)
        if case .outdoorLight(let goal, _) = recommendation.successCriteria { choices.insert(goal) }
        return choices.sorted()
    }

    private var mechanism: MechanismEntry { MechanismLibrary.entry(for: recommendation.mechanismKey) }

    var body: some View {
        Card {
            HStack(spacing: 8) {
                Image(systemName: recommendation.kind.systemImage)
                    .foregroundStyle(phase.palette.accent)
                    .accessibilityLabel(recommendation.kind.title)
                Spacer()
                Pill(text: recommendation.urgency.label,
                     tint: recommendation.urgency == .now ? phase.palette.accent : .secondary)
            }

            Text(recommendation.title)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            Text(recommendation.body)
                .font(.subheadline)
                .foregroundStyle(.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            if !recommendation.steps.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(recommendation.steps, id: \.self) { step in
                        Label(step, systemImage: step.contains("(today)") ? "circle.inset.filled" : "circle")
                            .font(.footnote)
                            .foregroundStyle(step.contains("(today)") ? .primary : .secondary)
                    }
                }
            }

            switch recommendation.kind {
            case .morningLight, .lateDayLight, .travelShift:
                LightCheckButton(title: "Check how bright it is", moment: .day)
            case .windDown:
                LightCheckButton(title: "Is your room dim enough?", moment: .evening)
            default:
                EmptyView()
            }

            mechanismSection

            if recommendation.kind != .maintenance {
                HStack {
                    Text(recommendation.successCriteria.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Skip") { withAnimation { app.skip(recommendation) } }
                        .buttonStyle(.bordered)
                        .accessibilityHint("Hides this suggestion for today")
                    Button("Done") {
                        if asksForMinutes {
                            askMinutes = true
                        } else {
                            withAnimation(.easeInOut(duration: 0.3)) { app.markDone(recommendation) }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint("Marks this suggestion as followed")
                }
                .controlSize(.small)
                .confirmationDialog("About how long were you outside?", isPresented: $askMinutes, titleVisibility: .visible) {
                    ForEach(minuteChoices, id: \.self) { minutes in
                        Button(minutes >= minuteChoices.last! ? "\(Int(minutes)) min or more" : "About \(Int(minutes)) min") {
                            withAnimation(.easeInOut(duration: 0.3)) { app.markDone(recommendation, minutes: minutes) }
                        }
                    }
                } message: {
                    Text(app.canSenseLight
                         ? "A rough guess is fine. Your Watch can miss time outside, so if you were out longer than it saw, your answer counts instead."
                         : "A rough guess is fine. It counts toward the morning-light part of your estimate.")
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: expanded)
    }

    private var mechanismSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                expanded.toggle()
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb").foregroundStyle(phase.palette.accent).accessibilityHidden(true)
                    Text("Why this works")
                        .font(.footnote.weight(.medium))
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Why this works")
            .accessibilityHint(expanded ? "Collapses the explanation" : "Expands the explanation")

            if expanded {
                Text(mechanism.headline)
                    .font(.footnote.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(mechanism.why)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                NavigationLink {
                    MechanismDetailView(entry: mechanism)
                } label: {
                    Text("Go deeper").font(.footnote.weight(.semibold))
                }
            }
        }
        .padding(12)
        .background(phase.palette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
