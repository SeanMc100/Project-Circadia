import SwiftUI

struct InsightsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch app.insights.status {
                    case .notEnoughData(let have, let need):
                        EmptyStateView(systemImage: "hourglass",
                                       title: "Not enough data yet",
                                       message: "Insights need at least \(need) nights of data. You have \(have).",
                                       progress: min(1, Double(have) / Double(need)))
                    case .ready where app.insights.insights.isEmpty:
                        EmptyStateView(systemImage: "magnifyingglass",
                                       title: "No clear comparisons yet",
                                       message: "Keep logging; comparisons appear once there are enough days on both sides.")
                    case .ready:
                        ForEach(app.insights.insights) { insight in
                            InsightCard(insight: insight)
                        }
                    }

                    Text("Patterns in your own data, not proof of cause.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(SkyBackground())
            .navigationTitle("Insights")
        }
    }
}

struct InsightCard: View {
    let insight: Insight

    private var icon: (String, Color) {
        switch insight.tone {
        case .favorable: ("arrow.down.right.circle.fill", Palette.favorable)
        case .unfavorable: ("arrow.up.right.circle.fill", Palette.unfavorable)
        case .neutral: ("equal.circle.fill", .secondary)
        }
    }

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon.0).font(.title2).foregroundStyle(icon.1).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(insight.headline).font(.headline)
                    Text(insight.detail).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    Text(insight.sampleNote).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let key = insight.mechanismKey {
                        NavigationLink {
                            MechanismDetailView(entry: MechanismLibrary.entry(for: key))
                        } label: {
                            Text("Why this might be").font(.footnote.weight(.semibold))
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}
