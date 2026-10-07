import SwiftUI

/// Five steps. Each permission is requested only on the step that explains its value.
struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case welcome, health, location, schedule, notifications
    }

    @Environment(AppModel.self) private var app
    @Environment(\.skyPhase) private var phase
    @State private var step: Step = .welcome
    @State private var isWorking = false

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: Double(step.rawValue + 1), total: Double(Step.allCases.count))
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")

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
            hero("sun.horizon", "Circadia", "A coach for your body clock: not just a tracker.")
            point("waveform.path.ecg", "Sense", "Estimates where your rhythm sits from your sleep timing, daylight and consistency, compared with your own baseline.")
            point("clock.badge.checkmark", "Prescribe", "Suggests what to do and when: \"It's overcast and you have until 8:30. Go outside for about 20 minutes.\"")
            point("lightbulb", "Explain", "Every suggestion comes with the mechanism behind it, at the moment it matters.")
            Card { WellnessNote() }
        case .health:
            hero("heart.text.square", "Apple Health", "Circadia reads, never writes.")
            point("bed.double", "Sleep", "When you fall asleep and wake: the core of the estimate.")
            point("sun.max", "Time in daylight", "Outdoor light from Apple Watch, so light suggestions can confirm themselves.")
            point("waveform", "HRV, resting heart rate, wrist temperature", "Shown in Trends for context only.")
            Text("Everything stays on this iPhone. You can change access any time in the Health app.")
                .font(.footnote).foregroundStyle(.secondary)
            if app.settings.useMockData {
                Label("Demo data is on, so the app works without Health. You can still connect now.", systemImage: "testtube.2")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        case .location:
            hero("location", "Local sunrise and sky", "Approximate location gives local sunrise, sunset and cloud cover, so light suggestions match your actual sky.")
            point("airplane", "Travel", "It also notices time-zone changes and builds a gradual shift plan.")
            point("location.slash", "Prefer not to?", "Skip it. Circadia estimates sun times from your time zone and won't know cloud cover.")
        case .schedule:
            hero("alarm", "Your targets", "When do you want to wake and go to bed on a typical day?")
            scheduleCard
        case .notifications:
            hero("bell.badge", "Timely nudges", "Up to \(CircadianConfig.maxNudgesPerDay) a day: morning light, wind-down and caffeine cutoff. Never during quiet hours, and if you dismiss a kind twice in a row, Circadia backs off.")
            point("moon", "Quiet hours", "\(ClockMath.clockString(app.settings.quietStartMinutes)) to \(ClockMath.clockString(app.settings.quietEndMinutes)), adjustable in Settings.")
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
            Text("A steady wake time matters most. You can change these later.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    // MARK: - Buttons

    @ViewBuilder
    private var buttons: some View {
        VStack(spacing: 10) {
            switch step {
            case .welcome:
                primary("Get started") { advance() }
            case .health:
                primary("Connect Apple Health") {
                    await app.connectHealth()
                    advance()
                }
                secondary("Not now") { advance() }
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

    private func advance() {
        if let next = Step(rawValue: step.rawValue + 1) { step = next }
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
