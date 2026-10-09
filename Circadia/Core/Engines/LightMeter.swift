import Foundation

/// How bright the scene is, in the bands that matter for the body clock. Thresholds are melanopic
/// EDI (lux weighted for the light-sensing cells that set the clock), from Brown et al. 2022:
/// at least 250 during the day, at most 10 in the 3 hours before bed.
enum LightBand: Int, CaseIterable, Comparable, Sendable {
    case veryDim, indoor, brightIndoor, outdoorShade, sunlit

    static func < (lhs: LightBand, rhs: LightBand) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Lower bound in melanopic EDI.
    var lowerBound: Double {
        switch self {
        case .veryDim: 0
        case .indoor: CircadianConfig.lightBandIndoor
        case .brightIndoor: CircadianConfig.lightBandBrightIndoor
        case .outdoorShade: CircadianConfig.lightBandOutdoor
        case .sunlit: CircadianConfig.lightBandSunlit
        }
    }

    init(melanopicEDI: Double) {
        self = Self.allCases.last { melanopicEDI >= $0.lowerBound } ?? .veryDim
    }

    var title: String {
        switch self {
        case .veryDim: "Very dim"
        case .indoor: "Indoor light"
        case .brightIndoor: "Bright indoor light"
        case .outdoorShade: "Outdoor light"
        case .sunlit: "Sunlight"
        }
    }

    var shortTitle: String {
        switch self {
        case .veryDim: "Dim"
        case .indoor: "Indoor"
        case .brightIndoor: "Bright"
        case .outdoorShade: "Outdoor"
        case .sunlit: "Sun"
        }
    }

    var systemImage: String {
        switch self {
        case .veryDim: "moon.fill"
        case .indoor: "lamp.desk.fill"
        case .brightIndoor: "lightbulb.max.fill"
        case .outdoorShade: "cloud.sun.fill"
        case .sunlit: "sun.max.fill"
        }
    }
}

/// When the reading is taken, which decides what "good" means.
enum LightCheckMoment: Sendable {
    /// Daytime: brighter is better for the clock.
    case day
    /// The 3 hours before bed (and overnight): dimmer is better.
    case evening

    static func at(_ now: Date, targetBedMinutes: Double, calendar: Calendar = .current) -> LightCheckMoment {
        var minutes = ClockMath.minutesFromMidnight(now, calendar: calendar)
        if minutes < Double(CircadianConfig.dayRolloverHour * 60) { minutes += 1440 }
        let bed = ClockMath.bedtimeMinutes(targetBedMinutes)
        return minutes >= bed - CircadianConfig.windDownLeadMinutes ? .evening : .day
    }
}

struct LightVerdict: Equatable, Sendable {
    enum Tone: Sendable { case good, okay, poor }
    let tone: Tone
    let text: String
}

/// What the camera is pointed at.
enum LightCheckMode: Sendable {
    /// Wherever you'd normally look. Measures light bouncing off the scene, so surfaces matter.
    case scene
    /// A sheet of white paper filling the frame. Paper reflects the light's own colour and a known
    /// share of its brightness, so this reads the light falling on you rather than the scene.
    case whitePaper
}

/// A colour as linear sRGB, with daylight white (D65) at equal values.
struct LinearRGB: Equatable, Sendable {
    var r: Double
    var g: Double
    var b: Double

    var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }
    /// Scaled so the brightest channel is 1.
    var normalized: LinearRGB? {
        let top = max(r, g, b)
        guard top > 0 else { return nil }
        return LinearRGB(r: r / top, g: g / top, b: b / top)
    }
}

/// The colour of the light, from the camera's average colour with white balance locked to daylight.
struct LightColour: Equatable, Sendable {
    enum Name: Sendable {
        case warmWhite, neutralWhite, coolWhite
        case red, amber, yellow, green, cyan, blue, purple, pink

        var title: String {
            switch self {
            case .warmWhite: "warm white"
            case .neutralWhite: "neutral white"
            case .coolWhite: "cool, daylight-like"
            case .red: "red"
            case .amber: "amber"
            case .yellow: "yellow"
            case .green: "green"
            case .cyan: "cyan"
            case .blue: "blue"
            case .purple: "purple"
            case .pink: "pink"
            }
        }
    }

    /// Normalised so the brightest channel is 1.
    let rgb: LinearRGB
    /// CIE 1931 chromaticity.
    let x: Double
    let y: Double
    /// Correlated colour temperature, if the light is close enough to white for one to mean anything.
    let kelvin: Double?
    /// Distance from the white (blackbody) line in CIE 1960 uv; positive is greenish, negative pinkish.
    let duv: Double
    let name: Name
    /// Melanopic daylight efficacy ratio (1 = daylight-white of the same brightness).
    let melanopicRatio: Double

    var isWhite: Bool { kelvin != nil }

    init?(rgb raw: LinearRGB) {
        guard let rgb = raw.normalized, rgb.luminance > 0 else { return nil }
        self.rgb = rgb
        let X = 0.4124 * rgb.r + 0.3576 * rgb.g + 0.1805 * rgb.b
        let Y = rgb.luminance
        let Z = 0.0193 * rgb.r + 0.1192 * rgb.g + 0.9505 * rgb.b
        x = X / (X + Y + Z)
        y = Y / (X + Y + Z)

        let cct = LightColour.mcCamyKelvin(x: x, y: y)
        let (u, v) = LightColour.uv(x: x, y: y)
        let locus = LightColour.planckianUV(kelvin: min(max(cct, 1_000), 15_000))
        duv = (v >= locus.v ? 1 : -1) * hypot(u - locus.u, v - locus.v)
        let white = (1_500...12_000).contains(cct) && abs(duv) < CircadianConfig.lightColourWhiteDuv
        kelvin = white ? cct : nil

        if let kelvin {
            name = kelvin < 2_200 ? .amber : kelvin < 3_500 ? .warmWhite : (kelvin < 5_000 ? .neutralWhite : .coolWhite)
        } else {
            name = LightColour.hueName(rgb)
        }

        let w = CircadianConfig.melanopicRGBWeights
        let melanopic = max(0, w.r * rgb.r + w.g * rgb.g + w.b * rgb.b)
        melanopicRatio = min(CircadianConfig.melanopicRatioMax, melanopic / Y)
    }

    /// McCamy's approximation of correlated colour temperature.
    static func mcCamyKelvin(x: Double, y: Double) -> Double {
        let n = (x - 0.3320) / (0.1858 - y)
        return 449 * n * n * n + 3_525 * n * n + 6_823.3 * n + 5_520.33
    }

    static func uv(x: Double, y: Double) -> (u: Double, v: Double) {
        let d = -2 * x + 12 * y + 3
        return (4 * x / d, 6 * y / d)
    }

    /// The blackbody line in CIE 1960 uv (Krystek 1985, 1000–15000 K).
    static func planckianUV(kelvin t: Double) -> (u: Double, v: Double) {
        let u = (0.860117757 + 1.54118254e-4 * t + 1.28641212e-7 * t * t) / (1 + 8.42420235e-4 * t + 7.08145163e-7 * t * t)
        let v = (0.317398726 + 4.22806245e-5 * t + 4.20481691e-8 * t * t) / (1 - 2.89741816e-5 * t + 1.61456053e-7 * t * t)
        return (u, v)
    }

    /// Hue (degrees) and saturation (0–1) on gamma-encoded sRGB, which tracks how the colour looks.
    static func hueSaturation(_ rgb: LinearRGB) -> (hue: Double, saturation: Double)? {
        let (r, g, b) = (LightMeter.encodeSRGB(rgb.r), LightMeter.encodeSRGB(rgb.g), LightMeter.encodeSRGB(rgb.b))
        let top = max(r, g, b), span = top - min(r, g, b)
        guard top > 0, span > 0 else { return nil }
        var hue: Double
        if top == r { hue = 60 * ((g - b) / span) } else if top == g { hue = 60 * ((b - r) / span + 2) } else { hue = 60 * ((r - g) / span + 4) }
        if hue < 0 { hue += 360 }
        return (hue, span / top)
    }

    /// A plain colour name from the hue, for light that isn't white.
    static func hueName(_ rgb: LinearRGB) -> Name {
        guard let (hue, saturation) = hueSaturation(rgb) else { return .neutralWhite }
        let notRed = saturation < CircadianConfig.lightColourRedMinSaturation
        switch hue {
        case ..<10: return notRed ? .amber : .red
        case ..<45: return .amber
        case ..<70: return .yellow
        case ..<160: return .green
        case ..<200: return .cyan
        case ..<250: return .blue
        case ..<300: return .purple
        case ..<335: return .pink
        case ..<355: return notRed ? .pink : .red
        default: return notRed ? .amber : .red
        }
    }
}

/// The average colour of the middle of one camera frame.
struct FrameColour: Equatable, Sendable {
    let rgb: LinearRGB
    /// How much brightness varies across the patch (standard deviation ÷ mean).
    let variation: Double
    /// Share of pixels left out because they were clipped.
    let clippedFraction: Double
}

/// One raw measurement from the camera.
struct LightMeterSample: Equatable, Sendable {
    /// Scene brightness as exposure value at ISO 100.
    let ev100: Double
    /// Correlated colour temperature from auto white balance, if known (used when the colour can't be
    /// measured from the pixels).
    let kelvin: Double?
    /// Average colour from the pixels, with white balance locked to daylight.
    var frame: FrameColour?
    /// Exposure is at its shortest and lowest ISO and still too bright: the scene is at least this bright.
    var atBrightLimit = false
    /// Exposure is at its longest and highest ISO and still too dark: the scene is at most this bright.
    var atDarkLimit = false
}

/// A smoothed reading, ready to show.
struct LightReading: Equatable, Sendable {
    enum Bound: Sendable { case atLeast, atMost }

    var mode: LightCheckMode = .scene
    let ev100: Double
    /// Approximate photopic illuminance.
    let lux: Double
    let kelvin: Double?
    /// Measured from the pixels; nil when only auto white balance's colour temperature was available.
    var colour: LightColour?
    /// Melanopic daylight efficacy ratio (1 = daylight), from the measured colour or the colour temperature.
    let melanopicRatio: Double
    let melanopicEDI: Double
    let band: LightBand
    /// Set when the camera hit its limit, so the true value is beyond this one.
    let bound: Bound?
    /// Brightness variation across the frame (see `FrameColour.variation`).
    var variation: Double?
    var clippedFraction: Double?

    /// "Roughly 150–600 lux": the reading's ±1 EV uncertainty, rounded so it doesn't look precise.
    var rangeText: String {
        let factor = CircadianConfig.lightMeterUncertaintyFactor
        switch bound {
        case .atLeast: return "At least \(LightMeter.roundedLux(lux)) lux"
        case .atMost: return "Below about \(LightMeter.roundedLux(max(lux, 1))) lux"
        case nil: return "Roughly \(LightMeter.roundedLux(lux / factor))–\(LightMeter.roundedLux(lux * factor)) lux"
        }
    }

    var colourText: String? {
        if let colour { return "\(colour.name.title) light" }
        guard let kelvin else { return nil }
        if kelvin < 3500 { return "warm light" }
        if kelvin < 5000 { return "neutral light" }
        return "cool, daylight-like light"
    }

    /// How the colour changes the brightness's effect: "Counts as about 30% of its brightness for your body clock."
    var strengthText: String {
        let r = melanopicRatio
        if r >= 1.15 { return "About \(String(format: "%.1f", r))× as strong for your body clock as daylight-white light this bright." }
        if r >= 0.9 { return "As strong for your body clock as daylight-white light this bright." }
        if r < 0.05 { return "Almost no effect on your body clock at this brightness." }
        let percent = r < 0.2 ? (r * 20).rounded() * 5 : (r * 10).rounded() * 10
        return "Counts as about \(Int(percent))% of its brightness for your body clock."
    }

    /// The scene is strongly coloured, so it could be the light or what the camera is pointed at.
    var colourIsUncertain: Bool {
        mode == .scene && colour.map { !$0.isWhite } == true
    }

    /// White-paper mode, but brightness varies a lot across the frame: the paper probably isn't filling it.
    var paperLooksMissing: Bool {
        mode == .whitePaper && (variation ?? 0) > CircadianConfig.lightMeterPaperMaxVariation
    }
}

/// Turns camera exposure settings into an approximate light level. Pure, so it's unit-testable.
///
/// A camera measures light reflected from the scene, not the light falling on it, so a dark wall
/// reads darker than a white one under the same lamp. Results are good to roughly a factor of 2,
/// which is enough to tell the bands apart (they're about 10× apart) but not to give exact lux.
enum LightMeter {

    /// Exposure value at ISO 100 for the camera's current settings, corrected by how far the
    /// auto-exposure says the image is from its target (positive offset = scene brighter).
    static func ev100(aperture: Double, exposureSeconds: Double, iso: Double, targetOffset: Double = 0) -> Double {
        guard aperture > 0, exposureSeconds > 0, iso > 0 else { return 0 }
        return log2(aperture * aperture / exposureSeconds) - log2(iso / 100) + targetOffset
    }

    /// Approximate illuminance (lux) for an exposure value. Scene mode assumes an average (18% grey)
    /// scene; white-paper mode knows the surface is paper.
    static func lux(ev100: Double, mode: LightCheckMode = .scene) -> Double {
        calibration(for: mode) * pow(2, ev100)
    }

    static func calibration(for mode: LightCheckMode) -> Double {
        switch mode {
        case .scene: CircadianConfig.lightMeterCalibration
        case .whitePaper: CircadianConfig.lightMeterCalibration
            * CircadianConfig.lightMeterSceneReflectance / CircadianConfig.lightMeterPaperReflectance
        }
    }

    static func decodeSRGB(_ v: Double) -> Double {
        v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    static func encodeSRGB(_ v: Double) -> Double {
        v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
    }

    private static let linearLUT: [Double] = (0..<256).map { decodeSRGB(Double($0) / 255) }

    /// Average linear colour of the middle half of a BGRA frame, sampling a grid of about 64×64
    /// pixels and leaving out clipped ones. The pixels are only read, never kept.
    static func frameColour(bgra: UnsafeBufferPointer<UInt8>, width: Int, height: Int, bytesPerRow: Int) -> FrameColour? {
        guard width > 3, height > 3, bytesPerRow >= width * 4, bgra.count >= bytesPerRow * height else { return nil }
        let step = max(1, min(width, height) / 2 / 64)
        let clip = CircadianConfig.lightMeterClippedPixelLevel
        var sum = LinearRGB(r: 0, g: 0, b: 0)
        var sumL = 0.0, sumL2 = 0.0
        var used = 0, clipped = 0
        for row in stride(from: height / 4, to: height * 3 / 4, by: step) {
            for col in stride(from: width / 4, to: width * 3 / 4, by: step) {
                let i = row * bytesPerRow + col * 4
                let b = bgra[i], g = bgra[i + 1], r = bgra[i + 2]
                if max(r, g, b) >= clip { clipped += 1; continue }
                let lr = linearLUT[Int(r)], lg = linearLUT[Int(g)], lb = linearLUT[Int(b)]
                sum.r += lr; sum.g += lg; sum.b += lb
                let l = 0.2126 * lr + 0.7152 * lg + 0.0722 * lb
                sumL += l; sumL2 += l * l
                used += 1
            }
        }
        guard used > 0 else { return nil }
        let n = Double(used)
        let mean = sumL / n
        let sd = sqrt(max(0, sumL2 / n - mean * mean))
        return FrameColour(rgb: LinearRGB(r: sum.r / n, g: sum.g / n, b: sum.b / n),
                           variation: mean > 0 ? sd / mean : 0,
                           clippedFraction: Double(clipped) / Double(used + clipped))
    }

    /// Melanopic daylight efficacy ratio for a colour temperature, interpolated from typical
    /// sources (warm LED/incandescent about 0.45, neutral about 0.65, daylight 1.0).
    static func melanopicRatio(kelvin: Double?) -> Double {
        guard let kelvin else { return CircadianConfig.melanopicRatioUnknown }
        let table = CircadianConfig.melanopicRatioByKelvin
        guard let first = table.first, let last = table.last else { return 1 }
        if kelvin <= first.kelvin { return first.ratio }
        if kelvin >= last.kelvin { return last.ratio }
        for (a, b) in zip(table, table.dropFirst()) where kelvin <= b.kelvin {
            let t = (kelvin - a.kelvin) / (b.kelvin - a.kelvin)
            return a.ratio + t * (b.ratio - a.ratio)
        }
        return last.ratio
    }

    /// Median of recent samples, so one jumpy frame doesn't change the answer. The colour comes from
    /// the pixels when they're available, otherwise from auto white balance's colour temperature.
    static func reading(from samples: [LightMeterSample], mode: LightCheckMode = .scene) -> LightReading? {
        let recent = samples.suffix(CircadianConfig.lightMeterSmoothingSamples)
        guard let ev = ClockMath.median(recent.map(\.ev100)) else { return nil }
        let frames = recent.compactMap(\.frame)
        let colour: LightColour? = frames.count > recent.count / 2
            ? ClockMath.median(frames.map(\.rgb.r)).flatMap { r in
                ClockMath.median(frames.map(\.rgb.g)).flatMap { g in
                    ClockMath.median(frames.map(\.rgb.b)).flatMap { b in LightColour(rgb: LinearRGB(r: r, g: g, b: b)) }
                }
            }
            : nil
        let kelvin = colour.map(\.kelvin) ?? ClockMath.median(recent.compactMap(\.kelvin))
        let lux = lux(ev100: ev, mode: mode)
        let ratio = colour?.melanopicRatio ?? melanopicRatio(kelvin: kelvin)
        let edi = lux * ratio
        let majority = recent.count / 2
        let bound: LightReading.Bound? = recent.filter(\.atBrightLimit).count > majority ? .atLeast
            : (recent.filter(\.atDarkLimit).count > majority ? .atMost : nil)
        return LightReading(mode: mode, ev100: ev, lux: lux, kelvin: kelvin, colour: colour, melanopicRatio: ratio,
                            melanopicEDI: edi, band: LightBand(melanopicEDI: edi), bound: bound,
                            variation: ClockMath.median(frames.map(\.variation)),
                            clippedFraction: ClockMath.median(frames.map(\.clippedFraction)))
    }

    static func verdict(for band: LightBand, at moment: LightCheckMoment) -> LightVerdict {
        switch (moment, band) {
        case (.day, .veryDim):
            LightVerdict(tone: .poor, text: "Too dim to give your body clock a daytime signal.")
        case (.day, .indoor):
            LightVerdict(tone: .poor, text: "Typical room light. Outside is many times brighter, even when it's cloudy.")
        case (.day, .brightIndoor):
            LightVerdict(tone: .okay, text: "Meets the daytime minimum. Going outside is still a much stronger signal.")
        case (.day, .outdoorShade):
            LightVerdict(tone: .good, text: "A strong signal for your body clock.")
        case (.day, .sunlit):
            LightVerdict(tone: .good, text: "The strongest signal there is. You need less time out here.")
        case (.evening, .veryDim):
            LightVerdict(tone: .good, text: "Dim enough for the 3 hours before bed.")
        case (.evening, .indoor):
            LightVerdict(tone: .poor, text: "Brighter than ideal for the evening. Turn overhead lights off and use warm, low lamps.")
        case (.evening, _):
            LightVerdict(tone: .poor, text: "Too bright for the evening. This light can delay your body clock.")
        }
    }

    /// "About 40× brighter than your saved reading." Compares lux, so a scene reading and a
    /// white-paper reading can be compared.
    static func comparisonText(current: LightReading, saved: LightReading) -> String {
        let stops = log2(max(current.lux, 1e-6) / max(saved.lux, 1e-6))
        let ratio = pow(2, abs(stops))
        guard ratio >= 2 else { return "About the same as your saved reading." }
        let shown = ratio >= 10 ? Int((ratio / 5).rounded() * 5) : Int(ratio.rounded())
        return "About \(shown)× \(stops > 0 ? "brighter" : "dimmer") than your saved reading."
    }

    /// Where a reading sits on the five-band scale (0...1): each band gets an equal share, and the
    /// position within a band is logarithmic.
    static func scalePosition(melanopicEDI: Double) -> Double {
        let bands = LightBand.allCases
        let band = LightBand(melanopicEDI: melanopicEDI)
        let lower = max(band.lowerBound, 1)
        let upper = band == .sunlit ? CircadianConfig.lightBandSunlit * 10 : bands[band.rawValue + 1].lowerBound
        let within = min(1, max(0, log10(max(melanopicEDI, 1) / lower) / log10(upper / lower)))
        return (Double(band.rawValue) + within) / Double(bands.count)
    }

    /// Rounds to two significant figures (whole numbers) so readings don't look falsely precise.
    static func roundedLux(_ lux: Double) -> String {
        roundedLuxValue(lux).formatted(.number.grouping(.automatic).precision(.fractionLength(0)))
    }

    static func roundedLuxValue(_ lux: Double) -> Double {
        guard lux >= 1 else { return 1 }
        let digits = floor(log10(lux))
        let step = pow(10, max(0, digits - 1))
        return (lux / step).rounded() * step
    }
}
