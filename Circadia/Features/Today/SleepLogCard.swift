import SwiftUI

/// "When did you sleep?", pre-filled so the usual answer is one tap. Used for last night in
/// phone-only mode, a missed night before it, and nights a wearable didn't record.
struct SleepLogCard: View {
    let prompt: SleepLogPrompt
    var title = "When did you sleep?"
    var subtitle = "A best guess is fine. If this looks about right, it's one tap."
    @Environment(AppModel.self) private var app
    @Environment(\.skyPhase) private var phase
    @State private var editing = false

    var body: some View {
        Card {
            if prompt.isLogged {
                logged
            } else {
                question
            }
        }
        .animation(.easeInOut(duration: 0.25), value: prompt)
        .sheet(isPresented: $editing) { SleepLogSheet(prompt: prompt) }
    }

    private var question: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.weight(.semibold))
                Text(subtitle)
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                time("Asleep around", prompt.onset, systemImage: "moon.fill")
                time("Up at", prompt.wake, systemImage: "sunrise.fill")
            }
            HStack(spacing: 10) {
                Button("Not sure") { app.skipSleepLog(wakeDay: prompt.wakeDay) }
                    .font(.footnote.weight(.medium))
                Spacer(minLength: 4)
                Button("Adjust") { editing = true }
                    .buttonStyle(.bordered)
                Button("Looks right") { app.logSleep(prompt.log) }
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
        }
    }

    private var logged: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Palette.favorable)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Last night logged").font(.subheadline.weight(.semibold))
                Text("Asleep \(ClockMath.timeString(prompt.onset)), up \(ClockMath.timeString(prompt.wake)) · \(ClockMath.durationString(prompt.log.asleepMinutes))")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button("Edit") { editing = true }
                .font(.footnote.weight(.medium))
                .accessibilityLabel("Edit last night's sleep")
        }
        .sensoryFeedback(.success, trigger: prompt.isLogged)
    }

    private func time(_ label: String, _ date: Date, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: systemImage)
                .font(.caption).foregroundStyle(.secondary)
            Text(ClockMath.timeString(date))
                .font(.title2.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(phase.palette.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Edit both times for one night.
struct SleepLogSheet: View {
    let prompt: SleepLogPrompt
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var onsetMinutes: Double
    @State private var wakeMinutes: Double
    @State private var confirmRemove = false

    init(prompt: SleepLogPrompt) {
        self.prompt = prompt
        _onsetMinutes = State(initialValue: ClockMath.minutesFromMidnight(prompt.onset))
        _wakeMinutes = State(initialValue: ClockMath.minutesFromMidnight(prompt.wake))
    }

    private var log: SleepLog {
        SleepLog.make(wakeDay: prompt.wakeDay, onsetClockMinutes: onsetMinutes, wakeClockMinutes: wakeMinutes)
    }

    private var problem: String? { log.problem(now: Date()) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Fell asleep around", selection: .minutes({ onsetMinutes }, { onsetMinutes = $0 }),
                               displayedComponents: .hourAndMinute)
                    DatePicker("Woke up", selection: .minutes({ wakeMinutes }, { wakeMinutes = $0 }),
                               displayedComponents: .hourAndMinute)
                } footer: {
                    if let problem {
                        Label(problem, systemImage: "exclamationmark.triangle")
                    } else {
                        Text("\(ClockMath.durationString(log.asleepMinutes)) of sleep, \(ClockMath.timeString(log.onset)) to \(ClockMath.timeString(log.wake)). Use the time you fell asleep, not when you got into bed.")
                    }
                }
                if prompt.isLogged {
                    Section {
                        Button("Remove this night", role: .destructive) { confirmRemove = true }
                    }
                }
            }
            .navigationTitle(prompt.wakeDay.formatted(.dateTime.weekday(.wide).month().day()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        app.logSleep(log)
                        dismiss()
                    }
                    .disabled(problem != nil)
                }
            }
            .confirmationDialog("Remove this night from your sleep log?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    app.deleteSleepLog(wakeDay: prompt.wakeDay)
                    dismiss()
                }
            }
        }
        .presentationDetents([.medium])
    }
}
