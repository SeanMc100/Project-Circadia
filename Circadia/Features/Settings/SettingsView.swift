import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var confirmDelete = false
    @State private var showAdvanced = false

    var body: some View {
        @Bindable var settings = app.settings
        NavigationStack {
            Form {
                scheduleSection(settings)
                notificationSection(settings)
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

    private func notificationSection(_ settings: AppSettings) -> some View {
        Section {
            if !app.notificationsAuthorized {
                Button("Allow notifications") { Task { await app.requestNotificationPermission() } }
            }
            ForEach(RecommendationKind.notifiableKinds) { kind in
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

    private func dataSection(_ settings: AppSettings) -> some View {
        Section {
            Toggle(isOn: Binding(get: { settings.useMockData }, set: { app.setMockData($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Demo data")
                    Text("\(CircadianConfig.mockDays) days of synthetic sleep and light data").font(.caption).foregroundStyle(.secondary)
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

            statusRow("Apple Health", app.settings.useMockData ? HealthAuthorizationState.demo.label : app.healthAuthorization.label)
            if !settings.useMockData && app.healthAuthorization == .notRequested {
                Button("Connect Apple Health") { Task { await app.connectHealth() } }
            }
            statusRow("Location", app.location.statusLabel)
            if app.location.authorization == .notDetermined {
                Button("Allow location") { Task { await app.requestLocation() } }
            }
            statusRow("Sun & weather", app.sunWeather?.source.label ?? "Not loaded")
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
