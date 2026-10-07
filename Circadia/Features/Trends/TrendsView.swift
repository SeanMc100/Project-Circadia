import Charts
import SwiftUI

struct TrendsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.skyPhase) private var phase
    @State private var model = TrendsViewModel()

    var body: some View {
        let s = model.series(from: app.days)
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
            chartTitle("Outdoor light", subtitle: "Minutes per day. Line: \(Int(CircadianConfig.morningLightTargetMinutes)) min morning target.")
            if s.hasLightData {
                Chart {
                    ForEach(s.light) { bar in
                        BarMark(x: .value("Day", bar.day, unit: .day), y: .value("Minutes", bar.minutes))
                            .foregroundStyle(by: .value("When", bar.segment))
                    }
                    RuleMark(y: .value("Target", CircadianConfig.morningLightTargetMinutes))
                        .foregroundStyle(phase.palette.accent)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                }
                .chartForegroundStyleScale(["Before noon": Palette.light, "After noon": Palette.light.opacity(0.4)])
                .frame(height: 180)
            } else {
                Text("Time in daylight needs an Apple Watch (watchOS 10 or later). Without it, light suggestions rely on your manual Done taps.")
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
