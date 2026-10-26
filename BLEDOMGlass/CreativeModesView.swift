import SwiftUI
import AVFoundation
import Combine

private enum CreativeMode: String, CaseIterable, Identifiable {
    case off = "Off"
    case rainbow = "Rainbow"
    case breathing = "Breathing"
    case candle = "Candle"
    case party = "Party"
    case musicPulse = "Music Pulse"
    case musicColor = "Music Color"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .off: return "stop.fill"
        case .rainbow: return "rainbow"
        case .breathing: return "wind"
        case .candle: return "flame.fill"
        case .party: return "sparkles"
        case .musicPulse: return "waveform"
        case .musicColor: return "music.note"
        }
    }
    var needsMic: Bool { self == .musicPulse || self == .musicColor }
}

private final class AudioMeter: ObservableObject {
    @Published var level: Double = 0
    @Published var available = false
    @Published var message = "Microphone is off"
    private let engine = AVAudioEngine()
    private var running = false

    func start() {
        guard !running else { return }
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                guard granted else { self.message = "Microphone permission denied"; return }
                self.configure()
            }
        }
    }

    private func configure() {
        guard !running else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .mixWithOthers])
            try session.setActive(true)
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.channelCount > 0 else { message = "No microphone input available"; return }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                guard let data = buffer.floatChannelData?[0] else { return }
                let count = Int(buffer.frameLength)
                guard count > 0 else { return }
                var sum: Float = 0
                for i in 0..<count { sum += data[i] * data[i] }
                let rms = sqrt(sum / Float(count))
                let scaled = min(1.0, max(0.0, (Double(rms) - 0.008) * 12.0))
                DispatchQueue.main.async {
                    self?.level = (self?.level ?? 0) * 0.55 + scaled * 0.45
                }
            }
            engine.prepare()
            try engine.start()
            running = true
            available = true
            message = "Listening to nearby sound"
        } catch {
            message = "Could not start microphone: \(error.localizedDescription)"
        }
    }

    func stop() {
        if running {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        running = false
        available = false
        level = 0
        message = "Microphone is off"
    }

    deinit { stop() }
}

struct CreativeModesView: View {
    @EnvironmentObject private var lights: BLEController
    @StateObject private var audio = AudioMeter()
    @State private var mode: CreativeMode = .off
    @State private var speed = 0.45
    @State private var intensity = 0.8
    @State private var hue = 0.55
    @State private var phase = 0.0
    @State private var showRepairDetails = false
    @State private var repairResult: String?
    @State private var isTesting = false

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("Effects lab", subtitle: "Live looks, custom motion, sound-reactive light")
            animationPreview
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(CreativeMode.allCases) { item in
                    Button {
                        select(item)
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: item.icon).font(.system(size: 15, weight: .semibold))
                                .frame(width: 34, height: 34)
                                .background(mode == item ? Color.cyan.opacity(0.22) : .white.opacity(0.07), in: RoundedRectangle(cornerRadius: 11))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.rawValue).font(.system(size: 12, weight: .semibold))
                                Text(item.needsMic ? "Uses microphone" : (item == .off ? "Manual color" : "Animated effect"))
                                    .font(.system(size: 9)).foregroundStyle(.white.opacity(0.48))
                            }
                            Spacer(minLength: 0)
                        }.padding(10).background(mode == item ? Color.cyan.opacity(0.10) : .white.opacity(0.035), in: RoundedRectangle(cornerRadius: 15))
                            .overlay(RoundedRectangle(cornerRadius: 15).stroke(mode == item ? .cyan.opacity(0.45) : .white.opacity(0.08), lineWidth: 1))
                    }.buttonStyle(.plain).foregroundStyle(.white)
                }
            }
            if mode.needsMic {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Sound input", systemImage: "mic.fill").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text(audio.available ? "LIVE" : "OFF").font(.system(size: 9, weight: .bold)).tracking(1.2)
                            .foregroundStyle(audio.available ? .green : .white.opacity(0.45))
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.08))
                            Capsule().fill(LinearGradient(colors: [.cyan, .purple, .pink], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(4, geo.size.width * audio.level))
                        }
                    }.frame(height: 9)
                    HStack {
                        Text(audio.message).font(.system(size: 10)).foregroundStyle(.white.opacity(0.52))
                        Spacer()
                        Button(audio.available ? "Stop mic" : "Enable mic") {
                            if audio.available { audio.stop() } else { audio.start() }
                        }.font(.system(size: 11, weight: .semibold)).padding(.horizontal, 12).padding(.vertical, 8)
                            .background(.white.opacity(0.1), in: Capsule()).buttonStyle(.plain)
                    }
                    Text(mode == .musicPulse ? "Brightness pulses with the volume detected by your iPhone microphone." : "Sound level steers the color through a shifting spectrum. This uses ambient audio, not a direct music-player feed.")
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.42)).fixedSize(horizontal: false, vertical: true)
                }.padding(14).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 17))
            }
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Label("Motion speed", systemImage: "speedometer").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(speedLabel).font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.58))
                }
                Slider(value: $speed, in: 0.05...1).tint(.cyan)
                HStack {
                    Label("Effect intensity", systemImage: "sun.max").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("\(Int(intensity * 100))%").font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.58))
                }
                Slider(value: $intensity, in: 0.1...1).tint(.purple)
                HStack {
                    Label("DIY base hue", systemImage: "paintpalette").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("\(Int(hue * 360))°").font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.58))
                }
                Slider(value: $hue, in: 0...1).tint(Color(hue: hue, saturation: 0.85, brightness: 1))
            }
            Text("DIY controls let you combine a base hue, speed, and intensity. Save the resulting shade with Color Studio. These are software-generated color animations, not individually addressable LED animations.")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.43)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(19).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 27, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 27, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 1))
        .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { _ in tick() }
        .onDisappear { audio.stop(); mode = .off }
    }

    private var animationPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 21).fill(LinearGradient(colors: [Color(hue: hue, saturation: 0.82, brightness: 0.65), Color(hue: (hue + 0.22).truncatingRemainder(dividingBy: 1), saturation: 0.9, brightness: 0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().fill(.white.opacity(0.22)).frame(width: 95).blur(radius: 32).offset(x: -80, y: -20)
            Circle().fill(Color(hue: (hue + 0.45).truncatingRemainder(dividingBy: 1), saturation: 0.9, brightness: 1).opacity(0.5)).frame(width: 120).blur(radius: 30).offset(x: 95, y: 22)
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("DIY PREVIEW").font(.system(size: 9, weight: .bold)).tracking(2)
                    Text(mode.rawValue == "Off" ? "Build your own look" : mode.rawValue).font(.system(size: 21, weight: .semibold, design: .rounded))
                    Text(mode.needsMic ? "Sound-reactive" : "Color motion preview").font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                Image(systemName: mode.icon).font(.system(size: 28, weight: .light)).symbolEffect(.pulse, isActive: mode != .off)
            }.foregroundStyle(.white).padding(18)
        }.frame(height: 120).clipShape(RoundedRectangle(cornerRadius: 21))
            .overlay(RoundedRectangle(cornerRadius: 21).stroke(.white.opacity(0.2), lineWidth: 1))
    }

    private var speedLabel: String {
        speed < 0.33 ? "Slow" : (speed < 0.70 ? "Medium" : "Fast")
    }

    private func select(_ newMode: CreativeMode) {
        mode = newMode
        phase = 0
        if newMode.needsMic { audio.start() } else { audio.stop() }
    }

    private func tick() {
        guard mode != .off else { return }
        phase += speed * 0.10
        let beat = min(1, audio.level * 2.8)
        var r = 0.0, g = 0.0, b = 0.0
        switch mode {
        case .off: return
        case .rainbow, .musicColor:
            let h = (hue + phase + (mode == .musicColor ? beat * 0.18 : 0)).truncatingRemainder(dividingBy: 1)
            let c = Color(hue: h, saturation: 0.95, brightness: max(0.15, intensity))
            let ui = UIColor(c)
            var rr: CGFloat = 0, gg: CGFloat = 0, bb: CGFloat = 0, aa: CGFloat = 0
            ui.getRed(&rr, green: &gg, blue: &bb, alpha: &aa)
            r = Double(rr); g = Double(gg); b = Double(bb)
        case .breathing:
            let brightness = 0.12 + (0.88 * (0.5 + 0.5 * sin(phase * 2 * .pi))) * intensity
            let ui = UIColor(Color(hue: hue, saturation: 0.82, brightness: brightness))
            var rr: CGFloat = 0, gg: CGFloat = 0, bb: CGFloat = 0, aa: CGFloat = 0
            ui.getRed(&rr, green: &gg, blue: &bb, alpha: &aa)
            r = Double(rr); g = Double(gg); b = Double(bb)
        case .candle:
            let flicker = max(0.35, min(1, 0.78 + sin(phase * 19) * 0.09 + sin(phase * 37) * 0.05))
            r = 1 * intensity; g = 0.38 * flicker * intensity; b = 0.07 * intensity
        case .party:
            let h = Double(Int(phase * 5) % 6) / 6
            let ui = UIColor(Color(hue: h, saturation: 1, brightness: intensity))
            var rr: CGFloat = 0, gg: CGFloat = 0, bb: CGFloat = 0, aa: CGFloat = 0
            ui.getRed(&rr, green: &gg, blue: &bb, alpha: &aa)
            r = Double(rr); g = Double(gg); b = Double(bb)
        case .musicPulse:
            let brightness = max(0.05, min(1, 0.15 + beat * intensity))
            let ui = UIColor(Color(hue: hue, saturation: 0.88, brightness: brightness))
            var rr: CGFloat = 0, gg: CGFloat = 0, bb: CGFloat = 0, aa: CGFloat = 0
            ui.getRed(&rr, green: &gg, blue: &bb, alpha: &aa)
            r = Double(rr); g = Double(gg); b = Double(bb)
        }
        lights.setColor(red: r, green: g, blue: b)
    }

    private func heading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 19, weight: .semibold, design: .rounded))
            Text(subtitle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.48))
        }.foregroundStyle(.white)
    }
}

struct RepairDiagnosticsView: View {
    @EnvironmentObject private var lights: BLEController
    @State private var lastCheck: Date?
    @State private var result = "Run a check to review the Bluetooth connection."
    @State private var isChecking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Repair & diagnostics").font(.system(size: 19, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                Text("Safe checks for common connection issues").font(.system(size: 11)).foregroundStyle(.white.opacity(0.48))
            }
            diagnosticRow("Bluetooth", value: lights.isPoweredOn ? "Available" : "Unavailable", good: lights.isPoweredOn)
            diagnosticRow("LED connection", value: lights.connectedName ?? "Not connected", good: lights.connectedName != nil)
            diagnosticRow("Controller response", value: lights.connectedName == nil ? "Connect to test" : "BLE link established", good: lights.connectedName != nil)
            Text(result).font(.system(size: 11)).foregroundStyle(.white.opacity(0.62)).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 9) {
                Button {
                    isChecking = true
                    lights.scan()
                    result = "Scanning for compatible LED controllers. Keep the strip powered on and nearby."
                    DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
                        isChecking = false
                        lastCheck = Date()
                        result = lights.devices.isEmpty ? "No compatible-looking device found. Check power, distance, and Bluetooth permission, then scan again." : "Found \(lights.devices.count) device(s). Open Connect your LED strip to select one."
                    }
                } label: {
                    Label(isChecking ? "Scanning…" : "Rescan devices", systemImage: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(.white.opacity(0.1), in: Capsule())
                }.disabled(isChecking || !lights.isPoweredOn).buttonStyle(.plain)
                Button {
                    if lights.connectedName != nil {
                        lights.disconnect()
                        result = "Disconnect requested. Reconnect to refresh the BLE session."
                    } else {
                        result = "Connect to the strip first. A BLE app cannot directly rewrite physical LED-strip wiring or repair a damaged LED segment."
                    }
                } label: {
                    Label("Reconnect", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(.white.opacity(0.07), in: Capsule())
                }.buttonStyle(.plain)
            }
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What this mode can do").font(.system(size: 12, weight: .semibold))
                    Text("Rescan nearby BLE devices, refresh a connection, and help identify whether the phone can see the controller.")
                    Text("What it cannot do").font(.system(size: 12, weight: .semibold))
                    Text("The current BLEDOM protocol does not expose physical data-pin mapping, individual pixel addresses, or a reliable chain-repair command. A BLE app cannot fix a cut trace, failed LED, bad connector, or miswired data line. Those require controller-specific documentation and, for hardware faults, physical inspection.")
                    Text("If the strip supports individually addressable pixels, a future version could add a pixel test pattern after its exact controller protocol is identified.")
                }.font(.system(size: 10)).foregroundStyle(.white.opacity(0.58)).padding(.top, 8)
            } label: {
                Label("Pin mapping and chain repair limits", systemImage: "wrench.and.screwdriver").font(.system(size: 12, weight: .medium))
            }.tint(.white.opacity(0.85))
            if let lastCheck {
                Text("Last check: \(lastCheck.formatted(date: .omitted, time: .shortened))").font(.system(size: 9)).foregroundStyle(.white.opacity(0.35))
            }
        }
        .padding(19).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 27, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 27, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 1))
    }

    private func diagnosticRow(_ title: String, value: String, good: Bool) -> some View {
        HStack {
            Image(systemName: good ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(good ? .green : .orange)
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.82))
            Spacer()
            Text(value).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
        }.padding(.vertical, 3)
    }
}
