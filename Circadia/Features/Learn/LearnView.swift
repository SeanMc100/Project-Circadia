import SwiftUI

struct LearnView: View {
    @State private var showLightCheck = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("A short sequence on how your body clock works and why each suggestion is timed the way it is. Read in order, about five minutes.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Button {
                        showLightCheck = true
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "camera.metering.center.weighted")
                                .font(.title3)
                                .foregroundStyle(.tint)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Light Check").font(.headline).foregroundStyle(.primary)
                                Text("Point your camera around you to see whether it's bright enough by day, or dim enough at night.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Tools")
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
            .sheet(isPresented: $showLightCheck) { LightCheckView() }
        }
    }
}

struct MechanismDetailView: View {
    let entry: MechanismEntry

    private var next: MechanismEntry? {
        guard let i = MechanismLibrary.sequence.firstIndex(of: entry.key), i + 1 < MechanismLibrary.sequence.count else { return nil }
        return MechanismLibrary.entry(for: MechanismLibrary.sequence[i + 1])
    }

    /// Breaks long copy into short paragraphs of up to two sentences each.
    private func paragraphs(_ text: String) -> some View {
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { s, _, _, _ in
            if let s { sentences.append(s.trimmingCharacters(in: .whitespaces)) }
        }
        let groups = stride(from: 0, to: sentences.count, by: 2).map {
            sentences[$0..<min($0 + 2, sentences.count)].joined(separator: " ")
        }
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(groups, id: \.self) { Text($0).fixedSize(horizontal: false, vertical: true) }
        }
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
                    paragraphs(entry.why)
                }
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("Go deeper")
                    paragraphs(entry.deeper)
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
    /// When opened from Today, the current breakdown is shown first.
    var score: AlignmentScore?
    var socialJetlag: Double?

    var body: some View {
        List {
            if let score {
                Section("Today's breakdown") {
                    ForEach(score.components) { ComponentBar(component: $0) }
                    if let socialJetlag {
                        HStack {
                            Text("Social jetlag (4 weeks)").font(.subheadline)
                            Spacer()
                            Text("\(ClockMath.durationString(socialJetlag)) \(socialJetlag >= 0 ? "later" : "earlier") on weekends")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            Section {
                Text("The alignment number is an **estimate**. Circadia can't see your body clock directly. The gold-standard measurement is dim-light melatonin onset (DLMO), which requires repeated saliva or blood samples in dim light. Circadia uses your sleep timing and outdoor light as a proxy, which is useful for spotting patterns but is not a measurement.")
            }
            Section("How far back it looks") {
                Text("There's no single window. Consistency uses your last \(CircadianConfig.consistencyWindowNights) nights. Timing drift compares **last night only** with your \(CircadianConfig.baselineWindowNights)-night baseline. Morning light uses a **single morning** (today's once it's past noon, otherwise yesterday's). Because drift and light are one-day values, the daily number can move several points from one day to the next. Trends shows the \(CircadianConfig.scoreTrendWindowDays)-day average, which is steadier.")
                    .font(.subheadline)
            }
            Section("Building blocks") {
                row("Sleep midpoint", "Halfway between falling asleep and final wake for your main sleep each night. Overlapping data from different sources is merged, and Apple Watch data is preferred when present. Without a wearable, it comes from your sleep log; a night Apple Health already has always wins over a logged one.")
                row("Baseline", "The median midpoint of your previous \(CircadianConfig.baselineWindowNights) nights. It needs at least \(CircadianConfig.baselineMinimumNights). The median keeps one late night from skewing it.")
                row("Timing drift", "Last night's midpoint minus your baseline. Full credit within \(Int(CircadianConfig.driftPerfectMinutes)) min, falling to zero at \(Int(CircadianConfig.driftZeroMinutes)) min.")
                row("Consistency", "The spread (standard deviation) of bedtime and wake time over the last \(CircadianConfig.consistencyWindowNights) nights. Full credit at ±\(Int(CircadianConfig.consistencyPerfectSDMinutes)) min or less, zero at ±\(Int(CircadianConfig.consistencyZeroSDMinutes)) min.")
                row("Morning light", "Half from timing (full credit if your first outdoor light comes within \(Int(CircadianConfig.morningLightFullCreditMinutes)) min of waking, falling to zero by \(Int(CircadianConfig.morningLightZeroCreditMinutes)) min) and half from amount: minutes outdoors before noon against the morning's goal, which depends on the sky (\(Int(CircadianConfig.lightMinutesClear)) min clear, \(Int(CircadianConfig.lightMinutesPartlyCloudy)) partly cloudy, \(Int(CircadianConfig.lightMinutesOvercast)) overcast, \(Int(CircadianConfig.lightMinutesUnknownSky)) if unknown). Minutes are rounded to the nearest 5, and the first minutes count most: half the goal earns about 70% of the amount credit. Uses Apple Watch 'time in daylight', topped up by what you report when you tap Done. Without it, this part is left out and the other weights are scaled up.")
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
                Text("• Sleep timing reflects your schedule as well as your clock: alarms, kids and shifts all shape it.\n• Wearables estimate sleep; they don't measure it the way a sleep lab does.\n• A sleep log is your own recall. Sleep diaries are a standard research method, but times are approximate, especially when falling asleep.\n• 'Time in daylight' is estimated by the watch's light sensor and can be blocked by sleeves.\n• The weights and thresholds are reasonable defaults, not clinically validated values.\n• Individual responses to light and caffeine vary widely.")
                    .font(.subheadline)
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
