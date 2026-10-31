import Foundation
import AVFoundation
import Combine
import Accelerate

/// Low-latency microphone level analyzer. The BLE controller accepts one RGB
/// value, so these broad sound bands drive a single whole-strip color.
@MainActor
final class AudioAnalyzer: ObservableObject {
    @Published private(set) var bass = 0.0
    @Published private(set) var mid = 0.0
    @Published private(set) var high = 0.0
    @Published private(set) var isRunning = false
    @Published private(set) var message = "Microphone is off"

    private let engine = AVAudioEngine()
    private var lastPublish = Date.distantPast
    private var generation = 0

    func start() {
        guard !isRunning else { return }
        message = "Requesting microphone access…"
        AVAudioApplication.requestRecordPermission { [weak self] allowed in
            Task { @MainActor in
                guard let self else { return }
                guard allowed else {
                    self.message = "Microphone permission denied. Enable it in Settings → Privacy & Security → Microphone."
                    return
                }
                self.configure()
            }
        }
    }

    private func configure() {
        stopEngineOnly()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers, .defaultToSpeaker])
            try session.setActive(true)

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.channelCount > 0, format.sampleRate > 0 else {
                message = "No microphone input is available"
                return
            }

            generation += 1
            let activeGeneration = generation
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                guard let channel = buffer.floatChannelData?[0] else { return }
                let count = Int(buffer.frameLength)
                guard count > 32 else { return }

                var rms: Float = 0
                vDSP_rmsqv(channel, 1, &rms, vDSP_Length(count))
                var crossings = 0
                if count > 1 {
                    for i in 1..<count where (channel[i - 1] < 0 && channel[i] >= 0) || (channel[i - 1] >= 0 && channel[i] < 0) {
                        crossings += 1
                    }
                }
                let crossingRate = Double(crossings) / Double(count)
                let level = min(1.0, max(0.0, (Double(rms) - 0.002) * 14.0))
                let highShare = min(1.0, crossingRate * 8.0)
                let low = level * (1.0 - highShare * 0.72)
                let high = level * highShare
                let mid = level * (0.35 + 0.45 * (1.0 - abs(highShare - 0.5) * 2.0))

                Task { @MainActor [weak self] in
                    guard let self, self.generation == activeGeneration else { return }
                    let now = Date()
                    guard now.timeIntervalSince(self.lastPublish) >= 0.05 else { return }
                    self.lastPublish = now
                    self.bass = self.bass * 0.55 + low * 0.45
                    self.mid = self.mid * 0.55 + mid * 0.45
                    self.high = self.high * 0.55 + high * 0.45
                    if !self.isRunning {
                        self.isRunning = true
                        self.message = "Microphone active · reacting to nearby sound"
                    }
                }
            }

            engine.prepare()
            try engine.start()
            isRunning = true
            message = "Listening for nearby sound…"
        } catch {
            stopEngineOnly()
            isRunning = false
            message = "Microphone unavailable: \(error.localizedDescription)"
        }
    }

    private func stopEngineOnly() {
        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        } else {
            engine.inputNode.removeTap(onBus: 0)
        }
    }

    func stop() {
        generation += 1
        stopEngineOnly()
        bass = 0
        mid = 0
        high = 0
        isRunning = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        message = "Microphone is off"
    }

    deinit {
        engine.stop()
    }
}
