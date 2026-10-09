import SwiftUI

/// Seven steps either way: wearable users connect Apple Health, phone-only users answer
/// "Your usual sleep" instead. Each permission is requested only on the step that explains its value.
struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case welcome, tracker, health, usualSleep, location, schedule, habits, notifications
    }

    @Environment(AppModel.self) private var app
    @Environment(\.skyPhase) private var phase
    @State private var step: Step = .welcome
    @State private var isWorking = false
    @State private var usual: UsualSleep?

    /// The steps this user sees: phone-only users skip Health; wearable users skip usual sleep.
    private var steps: [Step] {
        Step.allCases.filter { step in
            switch step {
            case .health: app.settings.trackingMode == .wearable
            case .usualSleep: app.settings.trackingMode == .phoneOnly
            default: true
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            let index = (steps.firstIndex(of: step) ?? 0) + 1
            ProgressView(value: Double(index), total: Double(steps.count))
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .accessibilityLabel("Step \(index) of \(steps.count)")

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    content
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            buttons
                .padding(24)
        }
        .background(SkyBackground())
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    // MARK: - Steps

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            hero("sun.horizon", "Circadia", "A coach for your body clock.")
            point("waveform.path.ecg", "Sense", "Estimates your rhythm from sleep timing and daylight, using a wearable or a quick morning log.")
            point("clock.badge.checkmark", "Prescribe", "Tells you what to do and when.")
            point("lightbulb", "Explain", "Shows the reason behind each suggestion.")
        case .tracker:
            hero("applewatch.and.arrow.forward", "Do you track your sleep?", "Circadia works either way.")
            point("applewatch", "With a wearable or sleep app", "Sleep and outdoor light are read from Apple Health automatically.")
            point("square.and.pencil", "Without one", "Each morning, confirm roughly when you slept. It's pre-filled, so it usually takes one tap.")
        case .health:
            hero("heart.text.square", "Apple Health", "Circadia reads, never writes.")
            point("bed.double", "Sleep", "When you fall asleep and wake.")
            point("sun.max", "Time in daylight", "Outdoor light from Apple Watch.")
            point("waveform", "Heart and temperature", "Shown in Trends for context.")
            Text("Everything stays on this iPhone.")
                .font(.footnote).foregroundStyle(.secondary)
            if app.settings.useMockData {
                Label("Demo data is on. You can still connect.", systemImage: "testtube.2")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        case .usualSleep:
            hero("moon.zzz", "Your usual sleep", "Roughly when do you fall asleep and wake up? Your estimate can start from day one instead of after a week of logging.")
            Card {
                UsualSleepEditor(usual: usualBinding)
            }
            Text("These are the core questions of the Munich ChronoType Questionnaire, a standard research survey.")
                .font(.footnote).foregroundStyle(.secondary)
        case .location:
            hero("location", "Local sunrise and sky", "Approximate location gives your local sun times and sky.")
            point("airplane", "Travel", "Also spots time-zone changes.")
            point("location.slash", "Prefer not to?", "Skip it and Circadia uses your time zone.")
        case .schedule:
            hero("alarm", "Your targets", "When do you want to wake and go to bed on a typical day?")
            scheduleCard
        case .habits:
            hero("checklist", "Which of these do you already do?", "Ranked by evidence, with times based on your schedule. Tap \u{24D8} to see the science.")
            HabitPickerList()
        case .notifications:
            hero("bell.badge", "Timely nudges", "Up to \(CircadianConfig.maxNudgesPerDay) a day, never during quiet hours.")
            point("moon", "Quiet hours", "\(ClockMath.clockString(app.settings.quietStartMinutes)) to \(ClockMath.clockString(app.settings.quietEndMinutes)).")
        }
    }

    private var scheduleCard: some View {
        @Bindable var settings = app.settings
        return Card {
            DatePicker("Wake", selection: .minutes({ settings.targetWakeMinutes }, {
                settings.targetWakeMinutes = $0
                settings.targetsAreCustom = true
            }), displayedComponents: .hourAndMinute)
            DatePicker("Bedtime", selection: .minutes({ settings.targetBedMinutes }, {
                settings.targetBedMinutes = $0
                settings.targetsAreCustom = true
            }), displayedComponents: .hourAndMinute)
            if app.snapshot.baselineWake != nil && !settings.targetsAreCustom {
                Label("Suggested from your recent sleep", systemImage: "sparkles")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Buttons

    @ViewBuilder
    private var buttons: some View {
        VStack(spacing: 10) {
            switch step {
            case .welcome:
                primary("Get started") { advance() }
            case .tracker:
                choice("Apple Watch", systemImage: "applewatch") { chooseTracking(.wearable) }
                choice("Another tracker or sleep app", systemImage: "circle.dashed") { chooseTracking(.wearable) }
                choice("No, I'll log my sleep", systemImage: "square.and.pencil") { chooseTracking(.phoneOnly) }
            case .health:
                primary("Connect Apple Health") {
                    await app.connectHealth()
                    advance()
                }
                secondary("Not now") { advance() }
            case .usualSleep:
                primary("Continue") {
                    saveUsualSleep()
                    advance()
                }
                secondary("Skip") { advance() }
            case .location:
                primary("Allow approximate location") {
                    await app.requestLocation()
                    advance()
                }
                secondary("Skip, use my time zone") {
                    app.settings.locationSkipped = true
                    advance()
                }
            case .schedule:
                primary("Continue") {
                    app.settings.targetsAreCustom = true
                    advance()
                }
            case .habits:
                primary("Continue") {
                    if app.settings.habitsChosenAt == nil { app.settings.habitsChosenAt = Date() }
                    advance()
                }
            case .notifications:
                primary("Allow notifications") {
                    await app.requestNotificationPermission()
                    finish()
                }
                secondary("Not now") { finish() }
            }
        }
        .disabled(isWorking)
    }

    private func primary(_ title: String, action: @escaping () async -> Void) -> some View {
        Button {
            run(action)
        } label: {
            Text(title).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
    }

    private func secondary(_ title: String, action: @escaping () async -> Void) -> some View {
        Button(title) { run(action) }
            .font(.subheadline.weight(.medium))
    }

    private func run(_ action: @escaping () async -> Void) {
        isWorking = true
        Task {
            await action()
            isWorking = false
        }
    }

    private func choice(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
    }

    /// Phone-only users skip the Health step; they can still connect later in Settings.
    private func chooseTracking(_ mode: TrackingMode) {
        app.setTrackingMode(mode)
        advance()
    }

    private func advance() {
        if let index = steps.firstIndex(of: step), index + 1 < steps.count { step = steps[index + 1] }
    }

    private var usualBinding: Binding<UsualSleep> {
        Binding(get: {
            usual ?? app.settings.usualSleep
                ?? .defaults(targetBedMinutes: app.settings.targetBedMinutes, targetWakeMinutes: app.settings.targetWakeMinutes)
        }, set: { usual = $0 })
    }

    /// Saves the answers and starts the targets from the workday times (the next step shows them).
    private func saveUsualSleep() {
        let answers = usualBinding.wrappedValue
        app.settings.usualSleep = answers
        app.settings.targetBedMinutes = answers.workdayOnset
        app.settings.targetWakeMinutes = answers.workdayWake
    }

    private func finish() {
        app.settings.hasCompletedOnboarding = true
        app.requestRefresh()
    }

    // MARK: - Building blocks

    private func hero(_ icon: String, _ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(phase.palette.accent)
                .accessibilityHidden(true)
            Text(title).font(.largeTitle.weight(.semibold))
            Text(subtitle).font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 6)
    }

    private func point(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(phase.palette.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
