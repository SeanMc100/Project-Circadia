import SwiftUI

/// Morning check-in: one tap per habit that Health data can't confirm. Answers stay on the card.
struct CheckInCard: View {
    let items: [CheckInItem]
    @Environment(AppModel.self) private var app
    @Environment(\.skyPhase) private var phase

    private var pending: Int { items.filter { $0.followed == nil }.count }
    private var kept: Int { items.filter { $0.followed == true }.count }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 2) {
                Text("How did last night go?").font(.title3.weight(.semibold))
                Text(pending > 0 ? "A quick check on the habits you're working on."
                                 : "All checked in: \(kept) of \(items.count) kept.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
            ForEach(items) { item in
                row(item)
            }
            if pending > 0 {
                Button("Skip the rest") { app.skipCheckIn() }
                    .font(.footnote.weight(.medium))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: items)
    }

    private func row(_ item: CheckInItem) -> some View {
        let habit = item.habit
        let prompt = habit.checkInPrompt(app.settings.timing, canSenseLight: app.canSenseLight) ?? habit.title
        return HStack(spacing: 10) {
            Image(systemName: item.followed == true ? "checkmark.circle.fill" : habit.systemImage)
                .frame(width: 24)
                .foregroundStyle(item.followed == true ? Palette.favorable : phase.palette.accent)
                .symbolEffect(.bounce, value: item.followed == true)
                .accessibilityHidden(true)
            Text(prompt)
                .font(.subheadline)
                .foregroundStyle(item.followed == false ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            answerButton("No", item: item, selected: item.followed == false) {
                app.answerCheckIn(habit, followed: false)
            }
            answerButton("Yes", item: item, selected: item.followed == true) {
                app.answerCheckIn(habit, followed: true)
            }
        }
        .controlSize(.small)
        .sensoryFeedback(.success, trigger: item.followed == true) { _, new in new }
    }

    /// Unanswered: both buttons as before. Answered: the chosen one stays filled, the other fades
    /// but can still be tapped to change the answer.
    private func answerButton(_ title: String, item: CheckInItem, selected: Bool, action: @escaping () -> Void) -> some View {
        let isYes = title == "Yes"
        return Button(title, action: action)
            .buttonStyle(SelectableButtonStyle(selected: selected,
                                               tint: isYes ? (selected ? Palette.favorable : phase.palette.accent) : .secondary,
                                               prominentWhenUnanswered: isYes && item.followed == nil))
            .opacity(item.followed != nil && !selected ? 0.5 : 1)
            .accessibilityLabel("\(title), \(item.habit.title)")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Filled when selected (or for the primary action before anything is chosen), outlined otherwise.
private struct SelectableButtonStyle: ButtonStyle {
    let selected: Bool
    let tint: Color
    let prominentWhenUnanswered: Bool

    func makeBody(configuration: Configuration) -> some View {
        let filled = selected || prominentWhenUnanswered
        configuration.label
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(filled ? AnyShapeStyle(.white) : AnyShapeStyle(tint))
            .background(filled ? tint : tint.opacity(0.14), in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
