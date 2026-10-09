import SwiftUI

/// Shown once each morning after last night's sleep comes in: the score and what moved it,
/// the habit check-in, and how to do better tomorrow.
struct MorningRecapView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.skyPhase) private var phase

    var body: some View {
        NavigationStack {
            ScrollView {
                if let recap = app.recap {
                    VStack(alignment: .leading, spacing: 22) {
                        header(recap)
                        factors(recap)
                        if !app.checkIn.isEmpty {
                            SectionLabel("Last night's habits")
                            CheckInCard(items: app.checkIn)
                        }
                        if let forecast = app.forecast {
                            SectionLabel("To do better tomorrow")
                            ForecastCard(forecast: forecast)
                        }
                        Button {
                            dismiss()
                        } label: {
                            Text(Calendar.current.component(.hour, from: Date()) < 12 ? "Start my day" : "Done").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 4)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
            }
            .background(SkyBackground())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func header(_ recap: ScoreRecap) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(phase.greeting).font(.title2.weight(.semibold))
            Text(recap.day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.subheadline).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(recap.score)")
                    .font(.system(size: 72, weight: .semibold, design: .rounded).monospacedDigit())
                if let change = recap.change, let previous = recap.previous {
                    VStack(alignment: .leading, spacing: 2) {
                        ChangeBadge(change: change, suffix: "since yesterday")
                        Text("Yesterday \(previous)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 8)
            Text(summary(recap))
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func factors(_ recap: ScoreRecap) -> some View {
        if !recap.factors.isEmpty {
            SectionLabel("What moved your score")
            Card {
                ForEach(recap.factors) { factor in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: factor.systemImage)
                            .frame(width: 24)
                            .foregroundStyle(phase.palette.accent)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(factor.kind.title).font(.subheadline.weight(.semibold))
                            Text(factor.text)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        PointsLabel(points: factor.points, zeroText: "no change")
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    /// One sentence naming the biggest reason.
    private func summary(_ recap: ScoreRecap) -> String {
        guard let change = recap.change else {
            return "This is your first full alignment estimate. From tomorrow, this screen explains what moved it."
        }
        // The biggest factor pushing the same way as the overall change.
        guard change != 0, let top = recap.factors.first(where: { change > 0 ? $0.points > 0 : $0.points < 0 }) else {
            return "Steady: your score held overnight."
        }
        let reason: String
        switch (top.kind, top.points > 0) {
        case (.drift, true): reason = "you slept closer to your usual timing"
        case (.drift, false): reason = "last night ran off your usual timing"
        case (.consistency, true): reason = "your bed and wake times got more regular"
        case (.consistency, false): reason = "your bed and wake times were less regular"
        case (.morningLight, true): reason = "you got more morning light"
        case (.morningLight, false): reason = "you got less morning light"
        }
        return "\(change > 0 ? "Up" : "Down") \(abs(change)) point\(abs(change) == 1 ? "" : "s"), mostly because \(reason)."
    }
}

/// Compact entry point on Today for reopening this morning's recap.
struct RecapEntryCard: View {
    let recap: ScoreRecap
    @Environment(AppModel.self) private var app
    @Environment(\.skyPhase) private var phase

    var body: some View {
        Button { app.presentRecap() } label: {
            HStack(spacing: 12) {
                Image(systemName: "sun.horizon.fill")
                    .font(.title3)
                    .foregroundStyle(phase.palette.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Morning recap").font(.subheadline.weight(.semibold))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let change = recap.change {
            parts.append(change == 0 ? "Same as yesterday" : "\(change > 0 ? "Up" : "Down") \(abs(change)) since yesterday")
        }
        let pending = app.checkIn.filter { $0.followed == nil }.count
        if pending > 0 { parts.append("\(pending) habit\(pending == 1 ? "" : "s") to check in") }
        else if !app.checkIn.isEmpty { parts.append("Checked in") }
        return parts.isEmpty ? "What moved your score" : parts.joined(separator: " · ")
    }
}
