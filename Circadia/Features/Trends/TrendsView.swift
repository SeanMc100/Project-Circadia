import Charts
import SwiftUI

struct TrendsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.skyPhase) private var phase
    @State private var model = TrendsViewModel()
    @State private var selectedScoreDay: Date?

    var body: some View {
        let s = model.series(from: app.days)
        let score = model.scoreSeries(from: app.scoreHistory, weights: app.settings.weights)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("Range", selection: $model.range) {
                        ForEach(TrendsViewModel.Range.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if s.midpoints.isEmpty {
                        EmptyStateView(systemImage: "chart.xyaxis.line", title: "No trends yet",
                                       message: "Trends appear once Apple Health has a few nights of sleep data.")
                    } else {
                        if !score.daily.isEmpty { scoreChart(score) }
                        midpointChart(s)
                        consistencyChart(s)
                        lightChart(s)
                        jetlagChart(s)
                        secondaryChart(s)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(SkyBackground())
            .navigationTitle("Trends")
        }
    }

    // MARK: - Charts

    private func scoreChart(_ s: TrendsViewModel.ScoreSeries) -> some View {
        let selected = selectedScoreDay.flatMap { day in s.daily.first { Calendar.current.isDate($0.day, inSameDayAs: day) } }
        let selectedSmooth = selected.flatMap { p in s.smoothed.first { $0.day == p.day } }
        return Card {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Alignment estimate").font(.headline)
                    Text("Dots: each day. Line: \(CircadianConfig.scoreTrendWindowDays)-day average.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let selected {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(selected.value)").font(.title2.weight(.semibold).monospacedDigit())
                        Text(selected.day.formatted(.dateTime.month(.abbreviated).day())
                             + (selectedSmooth.map { " · avg \(Int($0.value.rounded()))" } ?? ""))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else if let end = s.end {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Int(end.value.rounded()))").font(.title2.weight(.semibold).monospacedDigit())
                        changeText(s)
                    }
                }
            }
            Chart {
                if let ext = s.extremes {
                    stretchMark(ext.best.period, label: "Best", color: Palette.favorable)
                    stretchMark(ext.worst.period, label: "Lowest", color: Palette.unfavorable)
                }
                ForEach(s.daily) { p in
                    PointMark(x: .value("Day", p.day, unit: .day), y: .value("Score", p.value))
                        .foregroundStyle(phase.palette.accent.opacity(0.35))
                        .symbolSize(s.daily.count > 60 ? 8 : 18)
                }
                ForEach(s.smoothed) { p in
                    LineMark(x: .value("Day", p.day, unit: .day), y: .value("Average", p.value))
                        .foregroundStyle(phase.palette.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .interpolationMethod(.monotone)
                }
                if let selected {
                    RuleMark(x: .value("Day", selected.day, unit: .day))
                        .foregroundStyle(.secondary.opacity(0.5))
                }
            }
            .chartYScale(domain: 0...100)
            .chartXSelection(value: $selectedScoreDay)
            .frame(height: 200)
            .accessibilityLabel("Alignment estimate chart. \(s.daily.count) days.")
            .accessibilityValue(s.end.map { "\(CircadianConfig.scoreTrendWindowDays)-day average \(Int($0.value.rounded())). " } ?? "")

            if let ext = s.extremes {
                Divider()
                stretchRow("Best stretch", ext.best, color: Palette.favorable)
                stretchRow("Lowest stretch", ext.worst, color: Palette.unfavorable)
            }
        }
    }

    @ViewBuilder
    private func changeText(_ s: TrendsViewModel.ScoreSeries) -> some View {
        if let change = s.change, let start = s.start {
            let since = start.day.formatted(.dateTime.month(.abbreviated).day())
            let rounded = Int(change.rounded())
            Group {
                if rounded == 0 {
                    Text("Steady since \(since)").foregroundStyle(.secondary)
                } else {
                    Text("\(rounded > 0 ? "▲" : "▼") \(abs(rounded)) since \(since)")
                        .foregroundStyle(rounded > 0 ? Palette.favorable : Palette.unfavorable)
                }
            }
            .font(.caption.weight(.medium))
        } else {
            Text("\(CircadianConfig.scoreTrendWindowDays)-day average").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func stretchMark(_ p: ScorePeriod, label: String, color: Color) -> some ChartContent {
        RectangleMark(xStart: .value("Start", p.start, unit: .day), xEnd: .value("End", p.end, unit: .day),
                      yStart: .value("Low", 0), yEnd: .value("High", 100))
            .foregroundStyle(color.opacity(0.12))
            .annotation(position: .top, alignment: .leading, spacing: 2) {
                Text(label).font(.caption2.weight(.semibold)).foregroundStyle(color)
            }
    }

    private func stretchRow(_ title: String, _ stretch: TrendsViewModel.ScoreExtremes.Stretch, color: Color) -> some View {
        let p = stretch.period
        let dates = "\(p.start.formatted(.dateTime.month(.abbreviated).day())) – \(p.end.formatted(.dateTime.month(.abbreviated).day()))"
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(color)
                Text(dates).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text("avg \(Int(p.average.rounded()))").font(.subheadline.monospacedDigit().weight(.semibold))
            }
            if let reason = stretch.reason {
                Text(reason).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func midpointChart(_ s: TrendsViewModel.Series) -> some View {
        Card {
            chartTitle("Sleep midpoint vs baseline", subtitle: "Shaded band: baseline ±\(Int(model.baselineBandMinutes)) min. Higher is later.")
            Chart {
                ForEach(s.baseline) { p in
                    AreaMark(x: .value("Day", p.day, unit: .day),
                             yStart: .value("Low", p.minutes - model.baselineBandMinutes),
                             yEnd: .value("High", p.minutes + model.baselineBandMinutes))
                        .foregroundStyle(phase.palette.accent.opacity(0.15))
                    LineMark(x: .value("Day", p.day, unit: .day), y: .value("Baseline", p.minutes), series: .value("Series", "Baseline"))
                        .foregroundStyle(phase.palette.accent.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
                ForEach(s.midpoints) { p in
                    LineMark(x: .value("Day", p.day, unit: .day), y: .value("Midpoint", p.minutes), series: .value("Series", "Midpoint"))
                        .foregroundStyle(Palette.sleep)
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Day", p.day, unit: .day), y: .value("Midpoint", p.minutes))
                        .foregroundStyle(Palette.sleep)
                        .symbolSize(s.midpoints.count > 40 ? 10 : 24)
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxis { clockAxis() }
            .frame(height: 200)
            .accessibilityLabel("Sleep midpoint chart. \(s.midpoints.count) nights.")
        }
    }

    private func consistencyChart(_ s: TrendsViewModel.Series) -> some View {
        Card {
            let sdText: String = {
                guard let o = s.onsetSD, let w = s.wakeSD else { return "Bars show sleep onset to wake." }
                return "Bedtime varied ±\(Int(o.rounded())) min, wake ±\(Int(w.rounded())) min."
            }()
            chartTitle("Bedtime and wake consistency", subtitle: sdText)
            Chart(s.sleepBars) { bar in
                BarMark(x: .value("Day", bar.day, unit: .day),
                        yStart: .value("Onset", bar.onset),
                        yEnd: .value("Wake", bar.wake),
                        width: .ratio(0.6))
                    .foregroundStyle(Palette.sleep.opacity(0.75))
                    .clipShape(Capsule())
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxis { clockAxis() }
            .frame(height: 200)
            .accessibilityLabel("Sleep timing chart. \(sdText)")
        }
    }

    private func lightChart(_ s: TrendsViewModel.Series) -> some View {
        Card {
            chartTitle("Outdoor light", subtitle: "Minutes per day. Line: the morning goal, \(Int(CircadianConfig.lightMinutesClear)) min on clear days up to \(Int(CircadianConfig.lightMinutesOvercast)) when overcast.")
            if s.hasLightData {
                Chart {
                    ForEach(s.light) { bar in
                        BarMark(x: .value("Day", bar.day, unit: .day), y: .value("Minutes", bar.minutes))
                            .foregroundStyle(by: .value("When", bar.segment))
                    }
                    ForEach(s.lightGoals) { goal in
                        LineMark(x: .value("Day", goal.day, unit: .day), y: .value("Goal", goal.value),
                                 series: .value("Series", "Goal"))
                            .interpolationMethod(.stepCenter)
                            .foregroundStyle(phase.palette.accent)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    }
                }
                .chartForegroundStyleScale(["Before noon": Palette.light, "After noon": Palette.light.opacity(0.4)])
                .frame(height: 180)
            } else {
                Text(app.settings.trackingMode == .phoneOnly
                     ? "Outdoor time is only measured by an Apple Watch. While you're logging sleep yourself, light suggestions rely on your Done taps."
                     : "Time in daylight needs an Apple Watch (watchOS 10 or later). Without it, light suggestions rely on your manual Done taps.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func jetlagChart(_ s: TrendsViewModel.Series) -> some View {
        Card {
            chartTitle("Social jetlag", subtitle: "Weekend minus weekday sleep midpoint, rolling 4 weeks.")
            if s.jetlag.isEmpty {
                Text("Needs at least two weekend and two weekday nights.").font(.footnote).foregroundStyle(.secondary)
            } else {
                Chart(s.jetlag) { p in
                    LineMark(x: .value("Day", p.day, unit: .day), y: .value("Minutes", p.value))
                        .foregroundStyle(phase.palette.accent)
                        .interpolationMethod(.monotone)
                    AreaMark(x: .value("Day", p.day, unit: .day), y: .value("Minutes", p.value))
                        .foregroundStyle(phase.palette.accent.opacity(0.12))
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel { if let v = value.as(Double.self) { Text(ClockMath.durationString(v)) } }
                    }
                }
                .frame(height: 150)
            }
        }
    }

    private func secondaryChart(_ s: TrendsViewModel.Series) -> some View {
        Card {
            Toggle(isOn: $model.showSecondary) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Secondary signals").font(.headline)
                    Text("Shown for context; not part of the estimate.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if model.showSecondary {
                Picker("Signal", selection: $model.secondaryMetric) {
                    ForEach(SecondaryMetric.allCases) { Text($0.shortTitle).tag($0) }
                }
                .pickerStyle(.segmented)
                if s.secondary.isEmpty {
                    Text("No \(model.secondaryMetric.title.lowercased()) data in this range.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    Chart(s.secondary) { p in
                        LineMark(x: .value("Day", p.day, unit: .day), y: .value(model.secondaryMetric.unit, p.value))
                            .foregroundStyle(Palette.sleep)
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Day", p.day, unit: .day), y: .value(model.secondaryMetric.unit, p.value))
                            .foregroundStyle(Palette.sleep)
                            .symbolSize(14)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 150)
                    Text("Unit: \(model.secondaryMetric.unit)").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Helpers

    private func chartTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func clockAxis() -> some AxisContent {
        AxisMarks(values: .stride(by: 120)) { value in
            AxisGridLine()
            AxisValueLabel {
                if let v = value.as(Double.self) { Text(ClockMath.clockString(v)) }
            }
        }
    }
}
