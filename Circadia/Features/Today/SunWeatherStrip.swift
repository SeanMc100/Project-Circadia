import SwiftUI

struct SunWeatherStrip: View {
    let snapshot: SunWeatherSnapshot?
    let lightWindowText: String
    @Environment(\.skyPhase) private var phase
    @State private var attributionURL: URL?
    @State private var showSourceInfo = false

    var body: some View {
        Card {
            if let snapshot {
                HStack(alignment: .top, spacing: 0) {
                    item(icon: "sunrise", title: "Sunrise", value: snapshot.sun.sunrise.map(ClockMath.timeString) ?? "None today")
                    item(icon: "sunset", title: "Sunset", value: snapshot.sun.sunset.map(ClockMath.timeString) ?? "None today")
                    item(icon: snapshot.weather?.symbolName ?? "cloud", title: "Sky", value: skyText(snapshot))
                    if let uv = snapshot.weather?.uvIndex {
                        item(icon: "sun.max", title: "UV", value: "\(uv)")
                    }
                }
                Divider()
                HStack {
                    Label(lightWindowText, systemImage: "light.max")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(phase.palette.accent)
                    Spacer()
                    Button { showSourceInfo = true } label: { Image(systemName: "info.circle") }
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("About this data")
                        .popover(isPresented: $showSourceInfo) {
                            Text(sourceInfo(snapshot))
                                .font(.footnote)
                                .padding()
                                .frame(maxWidth: 280, alignment: .leading)
                                .presentationCompactAdaptation(.popover)
                        }
                }
                if snapshot.source == .weatherKit {
                    HStack(spacing: 4) {
                        Text("Weather data from  Weather.")
                        if let attributionURL {
                            Link("Legal", destination: attributionURL)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            } else {
                HStack {
                    ProgressView()
                    Text("Finding sun times…").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .task(id: snapshot?.source) {
            if snapshot?.source == .weatherKit { attributionURL = await WeatherKitProvider.attributionLegalURL() }
        }
    }

    private func sourceInfo(_ s: SunWeatherSnapshot) -> String {
        var parts = [s.source.label + (s.locationIsEstimated ? ", location estimated from time zone." : ".")]
        if s.source == .localSolar {
            parts.append("Cloud cover is unknown without weather data; suggestions assume average skies.")
        }
        return parts.joined(separator: " ")
    }

    private func skyText(_ s: SunWeatherSnapshot) -> String {
        guard let cloud = s.weather?.cloudCover else { return "Unknown" }
        return "\(s.sky.label) (\(Int((cloud * 100).rounded()))%)"
    }

    private func item(icon: String, title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.title3).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.footnote.weight(.semibold)).multilineTextAlignment(.center).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
