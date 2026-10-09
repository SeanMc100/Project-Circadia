import AVFoundation
import Observation

/// Runs the back camera with auto-exposure and reads its exposure settings a few times a second.
/// White balance is locked to daylight so the frames show the light's real colour; the middle of each
/// frame is averaged in memory and dropped. Nothing is recorded or saved; the preview is only so the
/// user can aim.
@MainActor
@Observable
final class LightMeterCamera {
    enum State: Equatable {
        case idle, running, unauthorized, unavailable
    }

    private(set) var state: State = .idle
    private(set) var reading: LightReading?
    /// Changing the mode starts a fresh reading.
    var mode: LightCheckMode = .scene {
        didSet {
            guard mode != oldValue else { return }
            samples.removeAll()
            reading = nil
        }
    }
    /// The latest raw values, for the calibration readout in debug builds.
    private(set) var raw: (iso: Double, seconds: Double, aperture: Double, offset: Double)?
    /// Whether white balance is locked, so colour comes from the pixels rather than auto white balance.
    private(set) var whiteBalanceLocked = false

    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored private var device: AVCaptureDevice?
    @ObservationIgnored private var samples: [LightMeterSample] = []
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let queue = DispatchQueue(label: "circadia.lightmeter")
    @ObservationIgnored private let frames = FrameAnalyser()
    @ObservationIgnored private let frameQueue = DispatchQueue(label: "circadia.lightmeter.frames")

    func start() async {
        guard state != .running else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { state = .unauthorized; return }
        default:
            state = .unauthorized
            return
        }
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            state = .unavailable
            return
        }
        device = camera
        session.beginConfiguration()
        session.sessionPreset = .medium
        if session.inputs.isEmpty, session.canAddInput(input) { session.addInput(input) }
        if session.outputs.isEmpty {
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(frames, queue: frameQueue)
            if session.canAddOutput(output) { session.addOutput(output) }
        }
        session.commitConfiguration()
        whiteBalanceLocked = Self.lockWhiteBalanceToDaylight(camera)
        let session = session
        queue.async { session.startRunning() }
        state = .running
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let device, whiteBalanceLocked, device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance),
           (try? device.lockForConfiguration()) != nil {
            device.whiteBalanceMode = .continuousAutoWhiteBalance
            device.unlockForConfiguration()
        }
        whiteBalanceLocked = false
        let session = session
        queue.async { session.stopRunning() }
        if state == .running { state = .idle }
    }

    /// Fixed daylight white balance, so a warm lamp looks orange instead of being corrected to white.
    private static func lockWhiteBalanceToDaylight(_ device: AVCaptureDevice) -> Bool {
        guard device.isWhiteBalanceModeSupported(.locked), (try? device.lockForConfiguration()) != nil else { return false }
        defer { device.unlockForConfiguration() }
        let daylight = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
            temperature: CircadianConfig.lightMeterLockedWhiteBalanceKelvin, tint: 0)
        var gains = device.deviceWhiteBalanceGains(for: daylight)
        let top = device.maxWhiteBalanceGain
        gains.redGain = min(max(gains.redGain, 1), top)
        gains.greenGain = min(max(gains.greenGain, 1), top)
        gains.blueGain = min(max(gains.blueGain, 1), top)
        device.setWhiteBalanceModeLocked(with: gains)
        return true
    }

    private func sample() {
        guard let device, session.isRunning else { return }
        let iso = Double(device.iso)
        let seconds = device.exposureDuration.seconds
        let aperture = Double(device.lensAperture)
        let offset = Double(device.exposureTargetOffset)
        guard seconds.isFinite, seconds > 0, iso > 0 else { return }
        raw = (iso, seconds, aperture, offset)

        // With white balance locked its kelvin is just the lock setting, so only use it when unlocked.
        var kelvin: Double?
        if !whiteBalanceLocked {
            let value = Double(device.temperatureAndTintValues(for: device.deviceWhiteBalanceGains).temperature)
            kelvin = value.isFinite && value > 1_000 ? value : nil
        }
        let format = device.activeFormat
        let limit = CircadianConfig.lightMeterLimitTolerance
        var sample = LightMeterSample(ev100: LightMeter.ev100(aperture: aperture, exposureSeconds: seconds, iso: iso, targetOffset: offset),
                                      kelvin: kelvin)
        if whiteBalanceLocked { sample.frame = frames.latest }
        sample.atBrightLimit = offset > 0.5 && iso <= Double(format.minISO) * (1 + limit)
            && seconds <= format.minExposureDuration.seconds * (1 + limit)
        sample.atDarkLimit = offset < -0.5 && iso >= Double(format.maxISO) * (1 - limit)
            && seconds >= device.activeMaxExposureDuration.seconds * (1 - limit)

        samples.append(sample)
        if samples.count > CircadianConfig.lightMeterSmoothingSamples * 2 { samples.removeFirst(samples.count - CircadianConfig.lightMeterSmoothingSamples) }
        // Wait for auto-exposure to settle before showing anything.
        if !device.isAdjustingExposure || reading != nil {
            reading = LightMeter.reading(from: samples, mode: mode)
        }
    }
}

/// Averages the middle of each video frame into one colour. Runs on the frame queue; the frame is
/// read in place and released straight away.
private final class FrameAnalyser: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _latest: FrameColour?

    var latest: FrameColour? {
        lock.lock()
        defer { lock.unlock() }
        return _latest
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let pixels = UnsafeBufferPointer(start: base.assumingMemoryBound(to: UInt8.self), count: bytesPerRow * height)
        let colour = LightMeter.frameColour(bgra: pixels, width: CVPixelBufferGetWidth(buffer), height: height, bytesPerRow: bytesPerRow)
        lock.lock()
        _latest = colour
        lock.unlock()
    }
}
