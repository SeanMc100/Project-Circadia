import SwiftUI
import WidgetKit

/// The app's colours, as the widgets use them.
enum WidgetPalette {
    static let sleep = Color(light: 0x4A4EA6, dark: 0x8F93EA)
    static let light = Color(light: 0xC77A12, dark: 0xF4B860)
    static let track = Color.primary.opacity(0.1)
    static let backgroundTop = Color(light: 0xEDEBF7, dark: 0x1A1B33)
    static let backgroundBottom = Color(light: 0xF8F6F3, dark: 0x0D0E1B)
    /// Night → dawn → morning, the sky band from the Today ring.
    static let ring = [Color(light: 0x4A4EA6, dark: 0x8F93EA), Color(light: 0x7363AE, dark: 0x8A7BC4),
                       Color(light: 0xEE9A74, dark: 0xE08C68), Color(light: 0xF5B94F, dark: 0xF0B04A)]
}

extension View {
    /// The soft sky gradient on the Home Screen; nothing on the Lock Screen.
    func circadiaBackground(_ family: WidgetFamily) -> some View {
        containerBackground(for: .widget) {
            if family.isAccessory {
                Color.clear
            } else {
                LinearGradient(colors: [WidgetPalette.backgroundTop, WidgetPalette.backgroundBottom],
                               startPoint: .top, endPoint: .bottom)
            }
        }
    }
}

extension WidgetFamily {
    var isAccessory: Bool {
        switch self {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline: true
        default: false
        }
    }
}

/// Small caps label used at the top of each widget.
struct WidgetHeader: View {
    let text: String
    var systemImage: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).foregroundStyle(tint)
            }
            Text(text.uppercased())
                .tracking(0.8)
                .foregroundStyle(.secondary)
        }
        .font(.caption2.weight(.semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

/// A thin 0...1 bar.
struct WidgetBar: View {
    let value: Double?
    var tint: Color = WidgetPalette.sleep
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(WidgetPalette.track)
                Capsule().fill(tint)
                    .frame(width: max(height, geo.size.width * CGFloat(min(max(value ?? 0, 0), 1))))
                    .opacity(value == nil ? 0 : 1)
                    .widgetAccentable()
            }
        }
        .frame(height: height)
    }
}

extension WidgetSnapshot.Alignment {
    var fraction: Double { Double(min(max(value, 0), 100)) / 100 }
}
