import SwiftUI

struct RecommendationCard: View {
    let recommendation: Recommendation
    @Environment(AppModel.self) private var app
    @Environment(\.skyPhase) private var phase
    @State private var expanded = false

    private var mechanism: MechanismEntry { MechanismLibrary.entry(for: recommendation.mechanismKey) }

    var body: some View {
        Card {
            HStack(spacing: 8) {
                Image(systemName: recommendation.kind.systemImage)
                    .foregroundStyle(phase.palette.accent)
                    .accessibilityHidden(true)
                Text(recommendation.kind.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
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

            mechanismSection

            if recommendation.kind != .maintenance {
                HStack {
                    Text(recommendation.successCriteria.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Skip") { app.skip(recommendation) }
                        .buttonStyle(.bordered)
                        .accessibilityHint("Hides this suggestion for today")
                    Button("Done") { app.markDone(recommendation) }
                        .buttonStyle(.borderedProminent)
                        .accessibilityHint("Marks this suggestion as followed")
                }
                .controlSize(.small)
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
                    Text(mechanism.headline)
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
            .accessibilityLabel("Why this works: \(mechanism.headline)")
            .accessibilityHint(expanded ? "Collapses the explanation" : "Expands the explanation")

            if expanded {
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
