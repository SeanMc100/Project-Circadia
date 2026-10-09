import SwiftUI

/// Opened from a pin on the Today ring: when the habit applies for you, why it matters,
/// and the evidence behind it.
struct HabitDetailSheet: View {
    let habit: HabitKey
    let timeText: String?
    @Environment(AppModel.self) private var app
    @Environment(\.skyPhase) private var phase
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    Card {
                        Label("When", systemImage: "clock").font(.subheadline.weight(.semibold))
                        Text(habit.rule(app.settings.timing))
                            .fixedSize(horizontal: false, vertical: true)
                        if let status = statusText {
                            Text(status).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    switch habit {
                    case .morningLight, .daytimeLight:
                        LightCheckButton(title: "Check how bright it is with Light Check", moment: .day)
                    case .eveningDim, .screensDown:
                        LightCheckButton(title: "Check your evening light with Light Check", moment: .evening)
                    default:
                        EmptyView()
                    }
                    Card {
                        Label("Why it matters", systemImage: "lightbulb").font(.subheadline.weight(.semibold))
                        Text(habit.why)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel("Sources")
                        ForEach(habit.sources, id: \.self) { source in
                            Text(source).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding()
            }
            .background(SkyBackground())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: habit.systemImage)
                .font(.title2)
                .foregroundStyle(phase.palette.accent)
                .frame(width: 52, height: 52)
                .background(phase.palette.accent.opacity(0.14), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.title).font(.title3.weight(.semibold))
                if let timeText {
                    Text(timeText.prefix(1).uppercased() + timeText.dropFirst())
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var statusText: String? {
        switch app.settings.status(for: habit) {
        case .alreadyDo: "You already do this."
        case .wantToStart: "You're working on this one."
        case .notForMe: "You've skipped this habit. You can change that in Settings › Habits."
        case nil: nil
        }
    }
}
