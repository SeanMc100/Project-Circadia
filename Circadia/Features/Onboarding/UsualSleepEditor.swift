import SwiftUI

/// Four time pickers: usual sleep on workdays and on days off (the core MCTQ questions).
struct UsualSleepEditor: View {
    @Binding var usual: UsualSleep

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            group("Workdays", systemImage: "briefcase",
                  onset: $usual.workdayOnset, wake: $usual.workdayWake)
            Divider()
            group("Days off", systemImage: "sun.max",
                  onset: $usual.freeDayOnset, wake: $usual.freeDayWake)
        }
    }

    private func group(_ title: String, systemImage: String, onset: Binding<Double>, wake: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage).font(.headline)
            DatePicker("Fall asleep", selection: .minutes({ onset.wrappedValue }, { onset.wrappedValue = $0 }),
                       displayedComponents: .hourAndMinute)
            DatePicker("Wake up", selection: .minutes({ wake.wrappedValue }, { wake.wrappedValue = $0 }),
                       displayedComponents: .hourAndMinute)
        }
    }
}

/// Settings → Sleep tracking → Usual sleep times.
struct UsualSleepSettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var usual: UsualSleep

    init(initial: UsualSleep) {
        _usual = State(initialValue: initial)
    }

    var body: some View {
        Form {
            Section {
                UsualSleepEditor(usual: $usual)
            } footer: {
                Text("Until you've logged \(CircadianConfig.baselineMinimumNights + 1) nights, these stand in for the missing ones so you get an estimate straight away. They also pre-fill each morning's question. Based on the Munich ChronoType Questionnaire.")
            }
        }
        .navigationTitle("Usual sleep")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: usual) { _, value in app.settings.usualSleep = value }
    }
}
