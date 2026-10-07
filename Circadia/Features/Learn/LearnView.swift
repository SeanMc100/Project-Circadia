import SwiftUI

struct LearnView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("A short sequence on how your body clock works and why each suggestion is timed the way it is. Read in order, about five minutes.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Section("The sequence") {
                    ForEach(Array(MechanismLibrary.all.enumerated()), id: \.element.key) { index, entry in
                        NavigationLink {
                            MechanismDetailView(entry: entry)
                        } label: {
                            HStack(spacing: 14) {
                                Text("\(index + 1)")
                                    .font(.subheadline.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.title).font(.headline)
                                    Text(entry.headline).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                Section("About the estimate") {
                    NavigationLink("How this is calculated") { HowCalculatedView() }
                }
                Section {
                    WellnessNote()
                }
            }
            .scrollContentBackground(.hidden)
            .background(SkyBackground())
            .navigationTitle("Learn")
        }
    }
}

struct MechanismDetailView: View {
    let entry: MechanismEntry

    private var next: MechanismEntry? {
        guard let i = MechanismLibrary.sequence.firstIndex(of: entry.key), i + 1 < MechanismLibrary.sequence.count else { return nil }
        return MechanismLibrary.entry(for: MechanismLibrary.sequence[i + 1])
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: entry.systemImage)
                    .font(.system(size: 36))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(entry.headline)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("Why this works")
                    Text(entry.why).fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("Go deeper")
                    Text(entry.deeper).fixedSize(horizontal: false, vertical: true)
                }
                if let next {
                    NavigationLink {
                        MechanismDetailView(entry: next)
                    } label: {
                        Label("Next: \(next.title)", systemImage: "arrow.right")
                            .font(.headline)
                    }
                    .padding(.top, 8)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(SkyBackground())
        .navigationTitle(entry.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct HowCalculatedView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings

    var body: some View {
        List {
            Section {
                Text("The alignment number is an **estimate**. Circadia can't see your body clock directly. The gold-standard measurement is dim-light melatonin onset (DLMO), which requires repeated saliva or blood samples in dim light. Circadia uses your sleep timing and outdoor light as a proxy, which is useful for spotting patterns but is not a measurement.")
            }
            Section("Building blocks") {
                row("Sleep midpoint", "Halfway between falling asleep and final wake for your main sleep each night. Overlapping data from different sources is merged, and Apple Watch data is preferred when present.")
                row("Baseline", "The median midpoint of your previous \(CircadianConfig.baselineWindowNights) nights. It needs at least \(CircadianConfig.baselineMinimumNights). The median keeps one late night from skewing it.")
                row("Timing drift", "Last night's midpoint minus your baseline. Full credit within \(Int(CircadianConfig.driftPerfectMinutes)) min, falling to zero at \(Int(CircadianConfig.driftZeroMinutes)) min.")
                row("Consistency", "The spread (standard deviation) of bedtime and wake time over the last \(CircadianConfig.consistencyWindowNights) nights. Full credit at ±\(Int(CircadianConfig.consistencyPerfectSDMinutes)) min or less, zero at ±\(Int(CircadianConfig.consistencyZeroSDMinutes)) min.")
                row("Morning light", "Half from timing (full credit if your first outdoor light comes within \(Int(CircadianConfig.morningLightFullCreditMinutes)) min of waking, falling to zero by \(Int(CircadianConfig.morningLightZeroCreditMinutes)) min) and half from amount (\(Int(CircadianConfig.morningLightTargetMinutes))+ min outdoors before noon). Uses Apple Watch 'time in daylight'. Without it, this part is left out and the other weights are scaled up.")
                row("Social jetlag", "Average weekend midpoint minus average weekday midpoint over 4 weeks. Shown alongside the estimate, not scored.")
            }
            Section("Current weights") {
                let w = settings.weights
                let total = max(w.total, 0.0001)
                row("Consistency", "\(Int((w.consistency / total * 100).rounded()))%")
                row("Morning light", "\(Int((w.morningLight / total * 100).rounded()))%")
                row("Timing drift", "\(Int((w.drift / total * 100).rounded()))%")
            }
            Section("Limitations") {
                Text("• Sleep timing reflects your schedule as well as your clock: alarms, kids and shifts all shape it.\n• Wearables estimate sleep; they don't measure it the way a sleep lab does.\n• 'Time in daylight' is estimated by the watch's light sensor and can be blocked by sleeves.\n• The weights and thresholds are reasonable defaults, not clinically validated values.\n• Individual responses to light and caffeine vary widely.")
                    .font(.subheadline)
            }
            Section {
                WellnessNote()
            }
        }
        .navigationTitle("How this is calculated")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(text).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
