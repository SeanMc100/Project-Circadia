import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var confirmDelete = false
    @State private var showAdvanced = false
    @State private var showExplainer = false

    var body: some View {
        @Bindable var settings = app.settings
        NavigationStack {
            Form {
                scheduleSection(settings)
                habitsSection(settings)
                notificationSection(settings)
                trackingSection(settings)
                dataSection(settings)

                Section {
                    DisclosureGroup("Score weights (advanced)", isExpanded: $showAdvanced) {
                        weightSlider("Consistency", value: $settings.weights.consistency)
                        weightSlider("Morning light", value: $settings.weights.morningLight)
                        weightSlider("Timing drift", value: $settings.weights.drift)
                        Text("Weights are scaled to add up to 100%. Changes apply on the next refresh.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Reset to defaults") { settings.weights = CircadianConfig.defaultWeights }
                    }
                }

                Section("About") {
                    Button("How Circadia works") { showExplainer = true }
                    NavigationLink("How this is calculated") { HowCalculatedView() }
                    WellnessNote()
                }

                Section {
                    Button("Delete all local data", role: .destructive) { confirmDelete = true }
                } footer: {
                    Text("Removes Circadia's saved recommendations, history and settings from this device. Your Apple Health data is never changed.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        app.requestRefresh()
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Delete all Circadia data on this device?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Task {
                        await app.deleteAllData()
                        dismiss()
                    }
                }
            } message: {
                Text("This can't be undone. You'll go through setup again.")
            }
            .fullScreenCover(isPresented: $showExplainer) { ExplainerView() }
            .task { await app.refreshNotificationStatus() }
        }
    }

    // MARK: - Sections

    private func scheduleSection(_ settings: AppSettings) -> some View {
        Section {
            DatePicker("Target wake", selection: .minutes({ settings.targetWakeMinutes }, {
                settings.targetWakeMinutes = $0
                settings.targetsAreCustom = true
            }), displayedComponents: .hourAndMinute)
            DatePicker("Target bedtime", selection: .minutes({ settings.targetBedMinutes }, {
                settings.targetBedMinutes = $0
                settings.targetsAreCustom = true
            }), displayedComponents: .hourAndMinute)
            Stepper(value: Binding(get: { settings.caffeineCutoffHours }, set: { settings.caffeineCutoffHours = $0 }),
                    in: CircadianConfig.caffeineCutoffRange, step: 0.5) {
                VStack(alignment: .leading) {
                    Text("Caffeine cutoff: \(hoursText(settings.caffeineCutoffHours)) before bed")
                    Text("Last caffeine around \(ClockMath.clockString(settings.targetBedMinutes - settings.caffeineCutoffHours * 60))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if !settings.targetsAreCustom {
                Text("Targets currently follow your detected baseline. Change either one to set your own.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("Schedule")
        }
    }

    private func habitsSection(_ settings: AppSettings) -> some View {
        let starting = settings.habitStatuses.values.filter { $0 == .wantToStart }.count
        let doing = settings.habitStatuses.values.filter { $0 == .alreadyDo }.count
        return Section {
            NavigationLink {
                HabitsSettingsView()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Habits")
                    Text("\(starting) starting · \(doing) already doing")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text("Only habits you're starting get nudges and morning check-in questions.")
        }
    }

    private func notificationSection(_ settings: AppSettings) -> some View {
        Section {
            if !app.notificationsAuthorized {
                Button("Allow notifications") { Task { await app.requestNotificationPermission() } }
            }
            ForEach(RecommendationKind.notifiableKinds.filter(HabitCatalog.nudgeKinds(for: settings.habitStatuses).contains)) { kind in
                Toggle(isOn: Binding(
                    get: { settings.enabledNudgeKinds.contains(kind) },
                    set: { on in
                        if on { settings.enabledNudgeKinds.insert(kind) } else { settings.enabledNudgeKinds.remove(kind) }
                    })) {
                    Label(kind.title, systemImage: kind.systemImage)
                }
            }
            DatePicker("Quiet from", selection: .minutes({ settings.quietStartMinutes }, { settings.quietStartMinutes = $0 }), displayedComponents: .hourAndMinute)
            DatePicker("Quiet until", selection: .minutes({ settings.quietEndMinutes }, { settings.quietEndMinutes = $0 }), displayedComponents: .hourAndMinute)
            ForEach(settings.backedOffKinds) { kind in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(kind.title) nudges paused").font(.subheadline)
                        Text("You dismissed them \(CircadianConfig.dismissalsBeforeBackoff) times in a row, so Circadia backed off.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Resume") { settings.resetDismissals(kind) }
                        .buttonStyle(.bordered)
                }
            }
        } header: {
            Text("Nudges")
        } footer: {
            Text("At most \(CircadianConfig.maxNudgesPerDay) a day, never during quiet hours. \(app.scheduledNudgeCount) currently scheduled.")
        }
    }

    private func trackingSection(_ settings: AppSettings) -> some View {
        Section {
            Picker("Sleep data", selection: Binding(get: { settings.trackingMode }, set: { app.setTrackingMode($0) })) {
                ForEach(TrackingMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            if settings.trackingMode == .phoneOnly {
                NavigationLink("Usual sleep times") {
                    UsualSleepSettingsView(initial: settings.usualSleep
                        ?? .defaults(targetBedMinutes: settings.targetBedMinutes, targetWakeMinutes: settings.targetWakeMinutes))
                }
                Toggle(isOn: Binding(get: { settings.sleepLogReminderEnabled }, set: { settings.sleepLogReminderEnabled = $0 })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Morning reminder")
                        Text("\"Log last night?\" about 30 min after you usually wake. Confirm from the notification without opening the app.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Sleep tracking")
        } footer: {
            switch settings.trackingMode {
            case .wearable:
                Text("Sleep and outdoor light are read from Apple Health: an Apple Watch, another tracker or a sleep app.")
            case .phoneOnly:
                Text("Log each night on Today. Light suggestions rely on your Done taps. If Apple Health already has a night from a tracker or sleep app, that's used instead of your log.")
            }
        }
    }

    private func dataSection(_ settings: AppSettings) -> some View {
        Section {
            Toggle(isOn: Binding(get: { settings.useMockData }, set: { app.setMockData($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Demo data")
                    Text(settings.trackingMode == .phoneOnly
                         ? "\(CircadianConfig.mockDays) days of synthetic sleep-log entries"
                         : "\(CircadianConfig.mockDays) days of synthetic sleep and light data")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if settings.useMockData {
                Menu("Simulate travel (demo)") {
                    Button("6 h east (e.g. New York → Paris)") { app.simulateTravel(hours: 6) }
                    Button("9 h east (large jump)") { app.simulateTravel(hours: 9) }
                    Button("3 h west (e.g. New York → LA)") { app.simulateTravel(hours: -3) }
                    Button("Clear travel", role: .destructive) { app.simulateTravel(hours: nil) }
                }
            }
            if settings.travelState != nil {
                Button("I've adapted. Set current location as home") { app.markTravelAdapted() }
            }

            statusRow("Apple Health", healthStatus(settings))
            if !settings.useMockData && app.healthAuthorization == .notRequested {
                Button("Connect Apple Health") { Task { await app.connectHealth() } }
            }
            statusRow("Location", app.location.statusLabel)
            if app.location.authorization == .notDetermined {
                Button("Allow location") { Task { await app.requestLocation() } }
            }
            statusRow("Sun & weather", app.sunWeather?.source.label ?? "Not loaded")
            if let error = app.weatherError {
                Text("Apple Weather failed: \(error)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let goal = settings.morningLightGoal(for: app.activeDay) {
                statusRow("Today's light goal", "\(Int(goal.minutes)) min (\(goal.sky.label.lowercased()))")
            }
            if app.canSenseLight {
                DisclosureGroup("Today's Apple Watch light readings") {
                    if app.todayDaylight.isEmpty {
                        Text("None yet today").font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(app.todayDaylight, id: \.self) { sample in
                        LabeledContent("\(ClockMath.timeString(sample.start))–\(ClockMath.timeString(sample.end))",
                                       value: "\(String(format: "%.1f", sample.minutes)) min")
                            .font(.footnote)
                    }
                    if !app.todayDaylight.isEmpty {
                        LabeledContent("Total", value: "\(String(format: "%.1f", app.todayDaylight.reduce(0) { $0 + $1.minutes })) min")
                            .font(.footnote.weight(.semibold))
                    }
                }
            }
            statusRow("Notifications", app.notificationsAuthorized ? "Allowed" : "Off")

            Button("Open iOS Settings for Circadia") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            Button("Open the Health app") {
                if let url = URL(string: "x-apple-health://") { openURL(url) }
            }
        } header: {
            Text("Data & permissions")
        } footer: {
            Text("All data stays on this iPhone. There are no accounts and no servers.")
        }
    }

    // MARK: - Helpers

    private func healthStatus(_ settings: AppSettings) -> String {
        if settings.useMockData { return HealthAuthorizationState.demo.label }
        if settings.trackingMode == .phoneOnly && app.healthAuthorization == .notRequested {
            return "Optional. Connect it if a sleep app saves your nights to Health"
        }
        return app.healthAuthorization.label
    }

    private func statusRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(value).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func weightSlider(_ title: String, value: Binding<Double>) -> some View {
        let total = max(app.settings.weights.total, 0.0001)
        return VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int((value.wrappedValue / total * 100).rounded()))%").monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: 0...1, step: 0.05)
                .accessibilityLabel("\(title) weight")
        }
    }

    private func hoursText(_ hours: Double) -> String {
        hours == hours.rounded() ? "\(Int(hours)) h" : String(format: "%.1f h", hours)
    }
}
