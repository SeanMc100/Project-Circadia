import SwiftUI

/// Every habit grouped by tier, each with "I do this" / "Start" / "Skip".
/// "Start" is capped at `CircadianConfig.maxFocusHabits` so the user focuses on a few at a time.
struct HabitPickerList: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            focusNote
            ForEach(HabitTier.allCases) { tier in
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        SectionLabel(tier.title)
                        Text(tier.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(HabitCatalog.ranked.filter { $0.tier == tier }) { habit in
                        HabitRow(habit: habit)
                    }
                }
            }
        }
    }

    private var focusNote: some View {
        let count = app.settings.focusHabitCount
        let max = CircadianConfig.maxFocusHabits
        return Label(count >= max
                     ? "You're focusing on \(count). Finish one or switch it to \"I do this\" to start another."
                     : "Pick up to \(max) to start. Habits you already do won't get reminders.",
                     systemImage: "target")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct HabitRow: View {
    let habit: HabitKey
    @Environment(AppModel.self) private var app
    @Environment(\.skyPhase) private var phase
    @State private var expanded = false

    private var status: HabitStatus? { app.settings.status(for: habit) }

    var body: some View {
        Card(padding: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: habit.systemImage)
                    .font(.title3)
                    .frame(width: 28)
                    .foregroundStyle(phase.palette.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(habit.title).font(.headline)
                    Text(habit.rule(app.settings.timing))
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button {
                    expanded.toggle()
                } label: {
                    Image(systemName: expanded ? "info.circle.fill" : "info.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded ? "Hide the evidence" : "Show the evidence")
            }

            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    Text(habit.why).font(.footnote).fixedSize(horizontal: false, vertical: true)
                    ForEach(habit.sources, id: \.self) { source in
                        Text(source).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack(spacing: 8) {
                ForEach(HabitStatus.allCases, id: \.self) { option in
                    choice(option)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: expanded)
    }

    private func choice(_ option: HabitStatus) -> some View {
        let selected = status == option
        let atCap = app.settings.focusHabitCount >= CircadianConfig.maxFocusHabits
        let disabled = option == .wantToStart && !selected && atCap
        return Button {
            app.setHabit(habit, selected ? nil : option)
        } label: {
            Text(option.label)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(selected ? phase.palette.accent : Color.primary.opacity(0.07), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .accessibilityLabel("\(habit.title): \(option.label)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Settings page for changing habit choices later.
struct HabitsSettingsView: View {
    var body: some View {
        ScrollView {
            HabitPickerList()
                .padding()
        }
        .navigationTitle("Habits")
        .navigationBarTitleDisplayMode(.inline)
    }
}
