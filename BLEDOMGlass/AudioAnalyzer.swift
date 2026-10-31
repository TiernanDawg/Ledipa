import Foundation
import AVFoundation
import Combine
import Accelerate

/// Microphone spectrum analyzer. The strip accepts one RGB value, so the three
/// frequency bands are mapped into whole-strip color rather than fake segments.
@MainActor final class AudioAnalyzer: ObservableObject {
    @Published private(set) var bass = 0.0
    @Published private(set) var mid = 0.0
    @Published private(set) var high = 0.0
    @Published private(set) var isRunning = false
    @Published private(set) var message = "Microphone is off"

    private let engine = AVAudioEngine()
    private let frameCount = 2048
    private var fftSetup: vDSP_DFT_Setup?
    private var sampleRate = 44_100.0
    private var lastPublish = Date.distantPast

    func start() {
        guard !isRunning else { return }
        AVAudioApplication.requestRecordPermission { [weak self] allowed in
            Task { @MainActor in
                guard let self else { return }
                guard allowed else { self.message = "Microphone permission denied"; return }
                self.configure()
            }
        }
    }

    private func configure() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers, .defaultToSpeaker])
            try session.setActive(true)
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.channelCount > 0, format.sampleRate > 0 else {
                message = "No microphone input available"
                return
            }
            sampleRate = format.sampleRate
            fftSetup = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(frameCount), .FORWARD)
            guard fftSetup != nil else { message = "Audio analyzer could not initialize"; return }

            input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(frameCount), format: format) { [weak self] buffer, _ in
                guard let self, let channel = buffer.floatChannelData?[0] else { return }
                let count = Int(buffer.frameLength)
                guard count == self.frameCount else { return }

                var window = [Float](repeating: 0, count: count)
                vDSP_hann_window(&window, vDSP_Length(count), Int32(vDSP_HANN_NORM))
                var realInput = [Float](repeating: 0, count: count)
                vDSP_vmul(channel, 1, window, 1, &realInput, 1, vDSP_Length(count))
                var imaginaryInput = [Float](repeating: 0, count: count)
                var realOutput = [Float](repeating: 0, count: count / 2)
                var imaginaryOutput = [Float](repeating: 0, count: count / 2)

                guard let setup = self.fftSetup else { return }
                vDSP_DFT_Execute(setup, &realInput, &imaginaryInput, &realOutput, &imaginaryOutput)

                let binWidth = self.sampleRate / Double(count)
                func band(_ low: Double, _ high: Double) -> Double {
                    let first = max(1, Int(low / binWidth))
                    let last = min(realOutput.count - 1, Int(high / binWidth))
                    guard last >= first else { return 0 }
                    var sum = 0.0
                    for index in first...last {
                        let re = Double(realOutput[index])
                        let im = Double(imaginaryOutput[index])
                        sum += re * re + im * im
                    }
                    let mean = sqrt(sum / Double(last - first + 1))
                    return min(1, mean * 0.055)
                }

                let values = (band(60, 250), band(250, 2_000), band(2_000, min(8_000, self.sampleRate / 2)))
                Task { @MainActor in
                    let now = Date()
                    guard now.timeIntervalSince(self.lastPublish) >= 0.035 else { return }
                    self.lastPublish = now
                    self.bass = self.bass * 0.58 + values.0 * 0.42
                    self.mid = self.mid * 0.58 + values.1 * 0.42
                    self.high = self.high * 0.58 + values.2 * 0.42
                }
            }
            engine.prepare()
            try engine.start()
            isRunning = true
            message = "Listening · bass, mids and highs"
        } catch {
            message = "Audio unavailable: \(error.localizedDescription)"
            stop()
        }
    }

    func stop() {
        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        fftSetup = nil
        bass = 0; mid = 0; high = 0
        isRunning = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        message = "Microphone is off"
    }

    deinit { engine.stop() }
}
