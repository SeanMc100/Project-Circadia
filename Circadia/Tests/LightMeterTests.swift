import XCTest
@testable import Circadia

/// Light Check: exposure → brightness band → verdict. Camera-free.
final class LightMeterTests: XCTestCase {
    let cal = TestCal.calendar

    func testExposureValueFromCameraSettings() {
        // f/1.78, 1/100 s, ISO 100: log2(1.78² × 100) ≈ 8.31.
        XCTAssertEqual(LightMeter.ev100(aperture: 1.78, exposureSeconds: 0.01, iso: 100), 8.307, accuracy: 0.01)
        XCTAssertEqual(LightMeter.ev100(aperture: 1.78, exposureSeconds: 0.01, iso: 200), 7.307, accuracy: 0.01,
                       "double the ISO needed: one stop darker scene")
        XCTAssertEqual(LightMeter.ev100(aperture: 1.78, exposureSeconds: 0.01, iso: 100, targetOffset: 1), 9.307, accuracy: 0.01,
                       "image over target: the scene is brighter than the settings imply")
        XCTAssertEqual(LightMeter.lux(ev100: 10), 2.5 * 1024, accuracy: 0.001)
    }

    func testMelanopicRatioFollowsColourTemperature() {
        XCTAssertEqual(LightMeter.melanopicRatio(kelvin: 2_700), 0.45, accuracy: 0.001)
        XCTAssertEqual(LightMeter.melanopicRatio(kelvin: 6_500), 1.0, accuracy: 0.001)
        XCTAssertEqual(LightMeter.melanopicRatio(kelvin: 3_500), 0.575, accuracy: 0.001, "interpolated")
        XCTAssertEqual(LightMeter.melanopicRatio(kelvin: 1_500), 0.30, accuracy: 0.001, "clamped")
        XCTAssertEqual(LightMeter.melanopicRatio(kelvin: nil), CircadianConfig.melanopicRatioUnknown)
    }

    func testBandThresholds() {
        XCTAssertEqual(LightBand(melanopicEDI: 9.9), .veryDim)
        XCTAssertEqual(LightBand(melanopicEDI: 10), .indoor)
        XCTAssertEqual(LightBand(melanopicEDI: 249), .indoor)
        XCTAssertEqual(LightBand(melanopicEDI: 250), .brightIndoor)
        XCTAssertEqual(LightBand(melanopicEDI: 1_000), .outdoorShade)
        XCTAssertEqual(LightBand(melanopicEDI: 10_000), .sunlit)
    }

    private func reading(ev: Double, kelvin: Double?) -> LightReading {
        LightMeter.reading(from: Array(repeating: LightMeterSample(ev100: ev, kelvin: kelvin), count: 4))!
    }

    func testTypicalScenesLandInTheRightBands() {
        XCTAssertEqual(reading(ev: 1, kelvin: 2_700).band, .veryDim, "one warm lamp in a dim room")
        XCTAssertEqual(reading(ev: 6, kelvin: 2_700).band, .indoor, "an ordinary living room")
        XCTAssertEqual(reading(ev: 9, kelvin: 4_500).band, .brightIndoor, "a bright office")
        XCTAssertEqual(reading(ev: 11, kelvin: 7_000).band, .outdoorShade, "outside on an overcast day")
        XCTAssertEqual(reading(ev: 15, kelvin: 5_500).band, .sunlit)
    }

    func testVerdictDependsOnTimeOfDay() {
        XCTAssertEqual(LightMeter.verdict(for: .veryDim, at: .evening).tone, .good)
        XCTAssertEqual(LightMeter.verdict(for: .indoor, at: .evening).tone, .poor)
        XCTAssertEqual(LightMeter.verdict(for: .veryDim, at: .day).tone, .poor)
        XCTAssertEqual(LightMeter.verdict(for: .brightIndoor, at: .day).tone, .okay)
        XCTAssertEqual(LightMeter.verdict(for: .outdoorShade, at: .day).tone, .good)
    }

    func testEveningStartsThreeHoursBeforeBed() {
        func moment(_ h: Int, _ m: Int, bed: Double) -> LightCheckMoment {
            LightCheckMoment.at(TestCal.date(2026, 10, 6, h, m), targetBedMinutes: bed, calendar: cal)
        }
        XCTAssertEqual(moment(19, 59, bed: 23 * 60), .day)
        XCTAssertEqual(moment(20, 0, bed: 23 * 60), .evening)
        XCTAssertEqual(moment(1, 0, bed: 23 * 60), .evening, "after midnight is still the night before")
        XCTAssertEqual(moment(5, 0, bed: 23 * 60), .day)
        XCTAssertEqual(moment(21, 29, bed: 30), .day, "bed at 12:30 AM")
        XCTAssertEqual(moment(21, 30, bed: 30), .evening)
    }

    func testReadingIgnoresAJumpyFrameAndFlagsCameraLimits() {
        let samples = [8, 8, 8, 8, 20].map { LightMeterSample(ev100: $0, kelvin: 4_000) }
        XCTAssertEqual(LightMeter.reading(from: samples)?.ev100, 8)

        var clipped = LightMeterSample(ev100: 16, kelvin: 5_500)
        clipped.atBrightLimit = true
        let bright = LightMeter.reading(from: Array(repeating: clipped, count: 4))
        XCTAssertEqual(bright?.bound, .atLeast)
        XCTAssertTrue(bright?.rangeText.hasPrefix("At least") == true)
        XCTAssertNil(reading(ev: 8, kelvin: 4_000).bound)
    }

    func testComparisonAndRounding() {
        let inside = reading(ev: 6, kelvin: 3_000)
        XCTAssertEqual(LightMeter.comparisonText(current: reading(ev: 11.3, kelvin: 3_000), saved: inside),
                       "About 40× brighter than your saved reading.")
        XCTAssertEqual(LightMeter.comparisonText(current: reading(ev: 4.4, kelvin: 3_000), saved: inside),
                       "About 3× dimmer than your saved reading.")
        XCTAssertEqual(LightMeter.comparisonText(current: reading(ev: 6.5, kelvin: 3_000), saved: inside),
                       "About the same as your saved reading.")

        XCTAssertEqual(LightMeter.roundedLuxValue(5.4), 5)
        XCTAssertEqual(LightMeter.roundedLuxValue(64), 64)
        XCTAssertEqual(LightMeter.roundedLuxValue(163), 160)
        XCTAssertEqual(LightMeter.roundedLuxValue(2_560), 2_600)
    }

    func testScalePositionIsMonotonicAcrossBands() {
        XCTAssertEqual(LightMeter.scalePosition(melanopicEDI: 1), 0, accuracy: 0.001)
        XCTAssertEqual(LightMeter.scalePosition(melanopicEDI: 10), 0.2, accuracy: 0.001)
        XCTAssertEqual(LightMeter.scalePosition(melanopicEDI: 250), 0.4, accuracy: 0.001)
        XCTAssertEqual(LightMeter.scalePosition(melanopicEDI: 1_000_000), 1, accuracy: 0.001)
        let values = [3.0, 30, 300, 3_000, 30_000].map { LightMeter.scalePosition(melanopicEDI: $0) }
        XCTAssertEqual(values, values.sorted())
    }

    // MARK: - Colour

    private func colour(_ r: Double, _ g: Double, _ b: Double) -> LightColour { LightColour(rgb: LinearRGB(r: r, g: g, b: b))! }

    func testWhiteLightGetsAColourTemperature() {
        let daylight = colour(1, 1, 1)
        XCTAssertEqual(daylight.name, .coolWhite)
        XCTAssertEqual(daylight.kelvin ?? 0, 6_500, accuracy: 150)
        XCTAssertEqual(daylight.melanopicRatio, 1, accuracy: 0.001, "daylight-white is the reference")

        // A 3000 K blackbody as linear sRGB.
        let warm = colour(1, 0.484, 0.154)
        XCTAssertEqual(warm.name, .warmWhite)
        XCTAssertEqual(warm.kelvin ?? 0, 3_000, accuracy: 250)
        XCTAssertEqual(warm.melanopicRatio, 0.44, accuracy: 0.02)
        XCTAssertEqual(colour(0.5, 0.242, 0.077), warm, "brightness doesn't change the colour")
    }

    func testColouredLightIsNamedAndWeightedByItsColour() {
        let red = colour(1, 0, 0)
        XCTAssertEqual(red.name, .red)
        XCTAssertNil(red.kelvin)
        XCTAssertEqual(red.melanopicRatio, 0, accuracy: 0.001, "red light barely reaches the body clock")

        let amber = colour(1, 0.217, 0)
        XCTAssertEqual(amber.name, .amber)
        XCTAssertEqual(colour(1, 0.266, 0.008).name, .amber, "a 2000 K candle-like glow")
        XCTAssertLessThan(amber.melanopicRatio, 0.2)

        XCTAssertEqual(colour(0.6, 0, 1).name, .purple)
        XCTAssertGreaterThan(colour(0.6, 0, 1).melanopicRatio, 1.5, "blue in the mix makes it strong")
        XCTAssertEqual(colour(1, 0, 0.97).name, .pink)
        XCTAssertEqual(colour(0, 0.045, 1).name, .blue)
        XCTAssertGreaterThan(colour(0, 0.045, 1).melanopicRatio, 5)
        XCTAssertLessThanOrEqual(colour(0, 0.2, 1).melanopicRatio, CircadianConfig.melanopicRatioMax)
        XCTAssertEqual(colour(0.2, 1, 0.1).name, .green)
        XCTAssertEqual(colour(1, 0.001, 0.015).name, .red, "a smart bulb set to pure red")
        XCTAssertEqual(colour(1, 0.044, 0.015).name, .amber, "orange-red from the same bulb")
        XCTAssertEqual(colour(1, 0.045, 0.044).name, .amber, "coral: red with some white mixed in")
        XCTAssertEqual(colour(1, 0.35, 0.25).name, .amber, "pale peach is off the white line but isn't red")
        XCTAssertEqual(colour(1, 0.3, 0.4).name, .pink, "a soft pink isn't red")
        XCTAssertNil(LightColour(rgb: LinearRGB(r: 0, g: 0, b: 0)))
    }

    private func frameReading(ev: Double, rgb: LinearRGB, mode: LightCheckMode = .scene) -> LightReading {
        var sample = LightMeterSample(ev100: ev, kelvin: nil)
        sample.frame = FrameColour(rgb: rgb, variation: 0.1, clippedFraction: 0)
        return LightMeter.reading(from: Array(repeating: sample, count: 4), mode: mode)!
    }

    func testSameBrightnessScoresLowerWhenTheLightIsRed() {
        let white = frameReading(ev: 8, rgb: LinearRGB(r: 1, g: 1, b: 1))
        let red = frameReading(ev: 8, rgb: LinearRGB(r: 1, g: 0.001, b: 0.015))
        XCTAssertEqual(white.lux, red.lux)
        XCTAssertEqual(white.band, .brightIndoor)
        XCTAssertEqual(red.band, .veryDim)
        XCTAssertEqual(red.colourText, "red light")
        XCTAssertEqual(red.kelvin, nil, "no colour temperature for red light")
        XCTAssertTrue(red.colourIsUncertain, "a red scene could be red walls")
        XCTAssertFalse(white.colourIsUncertain)
        XCTAssertFalse(frameReading(ev: 9, rgb: LinearRGB(r: 1, g: 0.02, b: 0.01), mode: .whitePaper).colourIsUncertain,
                       "white paper shows the light's own colour")
    }

    func testPixelColourWinsOverWhiteBalanceButFallsBackToIt() {
        var sample = LightMeterSample(ev100: 8, kelvin: 6_500)
        sample.frame = FrameColour(rgb: LinearRGB(r: 1, g: 0.484, b: 0.154), variation: 0, clippedFraction: 0)
        let measured = LightMeter.reading(from: Array(repeating: sample, count: 4))!
        XCTAssertEqual(measured.colour?.name, .warmWhite)
        XCTAssertEqual(measured.melanopicRatio, 0.44, accuracy: 0.02)

        let fallback = reading(ev: 8, kelvin: 2_700)
        XCTAssertNil(fallback.colour)
        XCTAssertEqual(fallback.melanopicRatio, 0.45, accuracy: 0.001)
        XCTAssertEqual(fallback.colourText, "warm light")
    }

    func testWhitePaperReadsTheLightFallingOnYou() {
        let scene = frameReading(ev: 8, rgb: LinearRGB(r: 1, g: 1, b: 1))
        let paper = frameReading(ev: 8, rgb: LinearRGB(r: 1, g: 1, b: 1), mode: .whitePaper)
        XCTAssertEqual(paper.lux / scene.lux, 0.18 / 0.85, accuracy: 0.001, "paper reflects more, so the same exposure is less light")
        XCTAssertEqual(paper.mode, .whitePaper)
        XCTAssertFalse(paper.paperLooksMissing)

        var uneven = LightMeterSample(ev100: 8, kelvin: nil)
        uneven.frame = FrameColour(rgb: LinearRGB(r: 1, g: 1, b: 1), variation: 0.6, clippedFraction: 0)
        XCTAssertTrue(LightMeter.reading(from: Array(repeating: uneven, count: 4), mode: .whitePaper)!.paperLooksMissing)
        XCTAssertFalse(LightMeter.reading(from: Array(repeating: uneven, count: 4), mode: .scene)!.paperLooksMissing)

        XCTAssertEqual(LightMeter.comparisonText(current: scene, saved: paper), "About 5× brighter than your saved reading.",
                       "comparison uses lux, so it works across modes")
    }

    func testStrengthText() {
        XCTAssertEqual(frameReading(ev: 8, rgb: LinearRGB(r: 1, g: 1, b: 1)).strengthText,
                       "As strong for your body clock as daylight-white light this bright.")
        XCTAssertEqual(frameReading(ev: 8, rgb: LinearRGB(r: 1, g: 0.484, b: 0.154)).strengthText,
                       "Counts as about 40% of its brightness for your body clock.")
        XCTAssertEqual(frameReading(ev: 8, rgb: LinearRGB(r: 1, g: 0, b: 0)).strengthText,
                       "Almost no effect on your body clock at this brightness.")
    }

    func testFrameColourAveragesTheMiddleAndSkipsClippedPixels() {
        let width = 64, height = 64, rowBytes = width * 4
        var pixels = [UInt8](repeating: 0, count: rowBytes * height)
        for row in 0..<height {
            for col in 0..<width {
                let i = row * rowBytes + col * 4
                let blown = col == 32 // a column of clipped highlights
                pixels[i] = blown ? 255 : 128      // B
                pixels[i + 1] = blown ? 255 : 128  // G
                pixels[i + 2] = blown ? 255 : 200  // R
                pixels[i + 3] = 255
            }
        }
        let frame = pixels.withUnsafeBufferPointer {
            LightMeter.frameColour(bgra: $0, width: width, height: height, bytesPerRow: rowBytes)
        }
        XCTAssertEqual(frame?.rgb.r ?? 0, LightMeter.decodeSRGB(200 / 255), accuracy: 0.0001)
        XCTAssertEqual(frame?.rgb.g ?? 0, LightMeter.decodeSRGB(128 / 255), accuracy: 0.0001)
        XCTAssertEqual(frame?.variation ?? 1, 0, accuracy: 0.0001)
        XCTAssertEqual(frame?.clippedFraction ?? 0, 1.0 / 32, accuracy: 0.0001)
        XCTAssertNil([UInt8](repeating: 0, count: 8).withUnsafeBufferPointer {
            LightMeter.frameColour(bgra: $0, width: 64, height: 64, bytesPerRow: 256)
        })
    }
}
