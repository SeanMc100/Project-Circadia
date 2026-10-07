import SwiftUI

struct SunWeatherStrip: View {
    let snapshot: SunWeatherSnapshot?
    let lightWindowText: String
    @Environment(\.skyPhase) private var phase
    @State private var attributionURL: URL?

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
                Label(lightWindowText, systemImage: "light.max")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(phase.palette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.source.label + (snapshot.locationIsEstimated ? " · Location estimated from time zone" : ""))
                    if snapshot.source == .localSolar {
                        Text("Cloud cover is unknown without weather data; suggestions assume average skies.")
                    }
                    if snapshot.source == .weatherKit {
                        HStack(spacing: 4) {
                            Text("Weather data from  Weather.")
                            if let attributionURL {
                                Link("Legal", destination: attributionURL)
                            }
                        }
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
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
