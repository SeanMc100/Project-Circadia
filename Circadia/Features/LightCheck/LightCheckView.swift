import AVFoundation
import SwiftUI
import UIKit

/// Light Check: point the camera where you'd normally look (or at white paper) and see roughly how
/// strong the light is for the body clock, from its brightness and colour. An estimate from the
/// camera; it never feeds the alignment estimate.
struct LightCheckView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.skyPhase) private var phase
    @State private var camera = LightMeterCamera()
    @State private var moment: LightCheckMoment
    @State private var saved: LightReading?
    #if DEBUG
    @State private var showsDebug = true
    #endif

    /// - Parameter moment: what "good" means; nil picks day or evening from the clock and bedtime.
    init(moment: LightCheckMoment? = nil) {
        _moment = State(initialValue: moment ?? .day)
        self.fixedMoment = moment
    }

    private let fixedMoment: LightCheckMoment?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Judge for", selection: $moment) {
                        Text("Daytime").tag(LightCheckMoment.day)
                        Text("Evening").tag(LightCheckMoment.evening)
                    }
                    .pickerStyle(.segmented)

                    Text(moment == .evening ? "Is your room dim enough for the evening?" : "How bright is it where you are?")
                        .font(.title3.weight(.semibold))

                    if camera.state == .idle || camera.state == .running {
                        modePicker
                        preview
                    }

                    switch camera.state {
                    case .unauthorized:
                        EmptyStateView(systemImage: "camera", title: "Camera access is off",
                                       message: "Light Check needs the camera to estimate brightness and colour. Nothing is recorded or saved.",
                                       actionTitle: "Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    case .unavailable:
                        EmptyStateView(systemImage: "camera", title: "No camera available",
                                       message: "Light Check needs the back camera, which isn't available on this device.")
                    case .idle, .running:
                        if let reading = camera.reading {
                            result(reading)
                            scale(reading)
                            compare(reading)
                            #if DEBUG
                            calibration(reading)
                            #endif
                        } else if camera.state == .running {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Measuring. Hold steady for a moment.").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }

                    Text("This is an estimate from the camera, good to about 2× either way, so you see a range rather than an exact number. It counts the light's colour as well as its brightness: blue-white light affects your body clock most, warm light less, and red light hardly at all. Pointed at a scene, the camera measures light bouncing off it, so a dark or coloured wall can throw it off; white paper avoids that. The preview isn't colour-corrected, so it shows the light's real tint. Frames are averaged on your phone and never recorded or saved, and readings don't change your alignment estimate.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
            }
            .background(SkyBackground())
            .navigationTitle("Light Check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            if fixedMoment == nil { moment = .at(Date(), targetBedMinutes: app.settings.targetBedMinutes) }
        }
        .task { await camera.start() }
        .onDisappear { camera.stop() }
    }

    // MARK: - Pieces

    private var preview: some View {
        CameraPreview(session: camera.session)
            .frame(height: 220)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                Label(camera.mode == .whitePaper ? "Fill the frame with the paper" : "Point where you'd normally look",
                      systemImage: camera.mode == .whitePaper ? "doc" : "viewfinder")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(10)
            }
            .accessibilityHidden(true)
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(get: { camera.mode == .whitePaper }, set: { camera.mode = $0 ? .whitePaper : .scene })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("White-paper check").font(.subheadline.weight(.semibold))
                    Text("More accurate for colour and brightness").font(.caption).foregroundStyle(.secondary)
                }
            }
            if camera.mode == .whitePaper {
                Text("Hold a sheet of plain white paper at eye level, angled toward the main light. Point the camera at it from close up so it fills the frame, without casting a shadow on it.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func result(_ reading: LightReading) -> some View {
        let verdict = LightMeter.verdict(for: reading.band, at: moment)
        return Card {
            HStack(spacing: 14) {
                Image(systemName: reading.band.systemImage)
                    .font(.title2)
                    .foregroundStyle(tint(verdict.tone))
                    .frame(width: 48, height: 48)
                    .background(tint(verdict.tone).opacity(0.14), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(reading.band.title).font(.title2.weight(.semibold))
                    Text([reading.rangeText, reading.colourText].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Text(reading.strengthText)
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if reading.colourIsUncertain {
                hint("This scene is strongly coloured, which could be the light or what you're pointing at.",
                     action: "Use the white-paper check") { camera.mode = .whitePaper }
            } else if reading.paperLooksMissing {
                hint("The frame looks uneven. Move closer so the paper fills it, without shadows.")
            }
            Label(verdict.text, systemImage: verdict.tone == .good ? "checkmark.circle.fill"
                  : (verdict.tone == .okay ? "circle.lefthalf.filled" : "exclamationmark.circle"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(tint(verdict.tone))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .animation(.easeInOut(duration: 0.3), value: reading.band)
    }

    private func hint(_ text: String, action: String? = nil, perform: @escaping () -> Void = {}) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(text, systemImage: "info.circle")
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                Button(action, action: perform)
                    .font(.footnote.weight(.medium))
            }
        }
    }

    /// The five bands on a log scale, with a marker for this reading.
    private func scale(_ reading: LightReading) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    HStack(spacing: 2) {
                        ForEach(LightBand.allCases, id: \.self) { band in
                            Rectangle()
                                .fill(Palette.light.opacity(0.15 + 0.17 * Double(band.rawValue)))
                        }
                    }
                    .clipShape(Capsule())
                    Circle()
                        .fill(phase.palette.accent)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .frame(width: 16, height: 16)
                        .offset(x: geo.size.width * LightMeter.scalePosition(melanopicEDI: reading.melanopicEDI) - 8)
                        .animation(.easeInOut(duration: 0.4), value: reading.melanopicEDI)
                }
            }
            .frame(height: 16)
            HStack(spacing: 2) {
                ForEach(LightBand.allCases, id: \.self) { band in
                    Text(band.shortTitle)
                        .font(.caption2.weight(band == reading.band ? .bold : .regular))
                        .foregroundStyle(band == reading.band ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func compare(_ reading: LightReading) -> some View {
        Card {
            if let saved {
                Text(LightMeter.comparisonText(current: reading, saved: saved))
                    .font(.headline)
                Text("Saved: \(saved.band.title.lowercased()), \(saved.rangeText.lowercased()).")
                    .font(.footnote).foregroundStyle(.secondary)
                HStack {
                    Button("Save this one instead") { self.saved = reading }
                    Spacer()
                    Button("Clear", role: .destructive) { self.saved = nil }
                }
                .font(.footnote.weight(.medium))
            } else {
                Text("Compare two places").font(.headline)
                Text("Save a reading indoors, then step outside (or by a window) to see how much brighter it is.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Save this reading") { saved = reading }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    #if DEBUG
    /// What the camera sees, for checking against a reference meter (docs/light-check-validation.md).
    private func calibration(_ reading: LightReading) -> some View {
        DisclosureGroup("What the camera sees (debug builds)", isExpanded: $showsDebug) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Mode: \(reading.mode == .whitePaper ? "white paper" : "scene") · colour from \(reading.colour != nil ? "pixels (WB locked)" : (camera.whiteBalanceLocked ? "waiting for frames" : "auto white balance"))")
                if let colour = reading.colour {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.sRGB, red: LightMeter.encodeSRGB(colour.rgb.r), green: LightMeter.encodeSRGB(colour.rgb.g),
                                        blue: LightMeter.encodeSRGB(colour.rgb.b)))
                            .frame(width: 28, height: 18)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary.opacity(0.4)))
                        Text("Colour: \(colour.name.title)\(colour.isWhite ? "" : " (not white)")")
                    }
                    Text(String(format: "Linear RGB %.3f / %.3f / %.3f", colour.rgb.r, colour.rgb.g, colour.rgb.b))
                    Text(String(format: "xy %.4f, %.4f · Δuv %+.4f", colour.x, colour.y, colour.duv))
                    if let (hue, saturation) = LightColour.hueSaturation(colour.rgb) {
                        Text(String(format: "Hue %.0f° · saturation %.2f", hue, saturation))
                    }
                }
                Text("CCT \(reading.kelvin.map { String(format: "%.0f K", $0) } ?? "– (not white)") · melanopic ratio \(String(format: "%.2f", reading.melanopicRatio))")
                Text(String(format: "Lux %.0f · melanopic EDI %.0f · band %@", reading.lux, reading.melanopicEDI, reading.band.title))
                Text(String(format: "EV100 %.2f · constant %.2f", reading.ev100, LightMeter.calibration(for: reading.mode)))
                if let raw = camera.raw {
                    Text(String(format: "ISO %.0f · 1/%.0f s · f/%.2f · offset %+.2f EV", raw.iso, 1 / raw.seconds, raw.aperture, raw.offset))
                }
                Text("Clipped \(reading.clippedFraction.map { String(format: "%.0f%%", $0 * 100) } ?? "–") · variation \(reading.variation.map { String(format: "%.2f", $0) } ?? "–") · bound \(reading.bound.map { "\($0)" } ?? "none")")
            }
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
        .font(.footnote)
    }
    #endif

    private func tint(_ tone: LightVerdict.Tone) -> Color {
        switch tone {
        case .good: Palette.favorable
        case .okay: phase.palette.accent
        case .poor: Palette.unfavorable
        }
    }
}

/// The camera feed, so the user can aim.
private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

/// A row that opens Light Check, for cards and sheets.
struct LightCheckButton: View {
    let title: String
    var moment: LightCheckMoment?
    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            Label(title, systemImage: "camera.metering.center.weighted")
                .font(.footnote.weight(.medium))
        }
        .sheet(isPresented: $showing) { LightCheckView(moment: moment) }
    }
}
