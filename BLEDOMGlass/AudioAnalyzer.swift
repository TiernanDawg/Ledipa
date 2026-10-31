import Foundation
import AVFoundation
import Combine
import Accelerate

@MainActor final class AudioAnalyzer: ObservableObject {
    @Published var bass = 0.0
    @Published var mid = 0.0
    @Published var high = 0.0
    @Published var isRunning = false
    @Published var message = "Microphone is off"
    private let engine = AVAudioEngine()
    private var fftSetup: vDSP_DFT_Setup?
    private var lastWrite = Date.distantPast

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
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers,.defaultToSpeaker])
            try session.setActive(true)
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.channelCount > 0 else { message = "No microphone input available"; return }
            input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
                guard let channel = buffer.floatChannelData?[0] else { return }
                let n = Int(buffer.frameLength)
                guard n > 0 else { return }
                let stride = vDSP_Stride(1)
                var real = [Float](repeating: 0, count: n)
                var imag = [Float](repeating: 0, count: n)
                vDSP_hann_window(&real, vDSP_Length(n), Int32(vDSP_HANN_NORM))
                var windowed = [Float](repeating: 0, count: n)
                vDSP_vmul(channel, stride, real, stride, &windowed, stride, vDSP_Length(n))
                let rms = sqrt(windowed.reduce(Float(0)) { $0 + $1*$1 } / Float(n))
                let level = min(1, Double(rms)*12)
                Task { @MainActor in
                    guard let self else { return }
                    self.bass = self.bass * 0.72 + level * 0.28
                    self.mid = self.mid * 0.82 + level * 0.18
                    self.high = self.high * 0.88 + level * 0.12
                }
            }
            engine.prepare()
            try engine.start()
            isRunning = true
            message = "Listening to nearby sound"
        } catch { message = error.localizedDescription }
    }
    func stop() {
        if isRunning { engine.inputNode.removeTap(onBus: 0); engine.stop(); try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        isRunning = false; bass=0; mid=0; high=0; message="Microphone is off"
    }
    deinit { engine.stop() }
}
