import SwiftUI
import CoreBluetooth

struct ContentView: View {
    @EnvironmentObject private var lights: BLEController
    @State private var showingDevices = false
    @State private var showingSaveAlert = false
    @State private var presetName = ""

    private let quickColors: [(String, Color, Double, Double, Double)] = [
        ("Ice", Color(red: 0.05, green: 0.65, blue: 1), 0.05, 0.65, 1),
        ("Violet", Color(red: 0.55, green: 0.2, blue: 1), 0.55, 0.2, 1),
        ("Pink", Color(red: 1, green: 0.08, blue: 0.42), 1, 0.08, 0.42),
        ("Amber", Color(red: 1, green: 0.48, blue: 0.08), 1, 0.48, 0.08),
        ("Mint", Color(red: 0.05, green: 1, blue: 0.52), 0.05, 1, 0.52),
        ("White", .white, 1, 1, 1)
    ]

    var body: some View {
        ZStack {
            background
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    connectionCard
                    colorCard
                    brightnessCard
                    presetsCard
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
        }
        .sheet(isPresented: $showingDevices) { devicesSheet.presentationDetents([.medium, .large]) }
        .alert("Save color", isPresented: $showingSaveAlert) {
            TextField("Preset name", text: $presetName)
            Button("Cancel", role: .cancel) { }
            Button("Save") { lights.saveCurrentPreset(name: presetName) }
        } message: { Text("Save your current color for quick access.") }
    }

    private var background: some View {
        ZStack {
            Color(red: 0.035, green: 0.045, blue: 0.09).ignoresSafeArea()
            Circle().fill(Color.cyan.opacity(0.22)).frame(width: 310).blur(radius: 95).offset(x: 130, y: -310)
            Circle().fill(Color.purple.opacity(0.25)).frame(width: 280).blur(radius: 100).offset(x: -140, y: 20)
            Circle().fill(lights.currentColor.opacity(0.18)).frame(width: 250).blur(radius: 100).offset(x: 130, y: 390)
        }.ignoresSafeArea()
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text("LUMA").font(.system(size: 13, weight: .bold, design: .rounded)).tracking(3).foregroundStyle(.white.opacity(0.56))
                Text("Light, your way.").font(.system(size: 31, weight: .semibold, design: .rounded)).tracking(-0.8)
            }
            Spacer()
            Button { lights.togglePower() } label: {
                Image(systemName: "power").font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(lights.isOn ? .white : .white.opacity(0.55))
                    .frame(width: 52, height: 52)
                    .background(lights.isOn ? lights.currentColor.opacity(0.8) : .white.opacity(0.09), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 1))
            }.buttonStyle(.plain)
        }.foregroundStyle(.white)
    }

    private var connectionCard: some View {
        Button { showingDevices = true; if lights.devices.isEmpty { lights.scan() } } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(.white.opacity(0.10)).frame(width: 48, height: 48)
                    Image(systemName: lights.connectedName == nil ? "dot.radiowaves.left.and.right" : "lightbulb.led.fill")
                        .font(.system(size: 19, weight: .medium)).foregroundStyle(lights.connectedName == nil ? .cyan : lights.currentColor)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(lights.connectedName ?? "Connect your lights").font(.system(size: 16, weight: .semibold))
                    Text(lights.status).font(.system(size: 12)).foregroundStyle(.white.opacity(0.58)).lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
            }.padding(16).glassPanel()
        }.buttonStyle(.plain).foregroundStyle(.white)
    }

    private var colorCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeading("Color", subtitle: "Make the room feel different")
            HStack(spacing: 18) {
                ZStack {
                    Circle().fill(RadialGradient(colors: [lights.currentColor.opacity(0.85), lights.currentColor.opacity(0.12), .clear], center: .center, startRadius: 12, endRadius: 80)).frame(width: 142, height: 142).blur(radius: 6)
                    Circle().fill(lights.currentColor.gradient).frame(width: 82, height: 82)
                        .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 1.5))
                        .shadow(color: lights.currentColor.opacity(0.65), radius: 25, y: 3)
                }.frame(width: 142, height: 142)
                VStack(alignment: .leading, spacing: 10) {
                    Text("CURRENT COLOR").font(.system(size: 10, weight: .bold)).tracking(1.6).foregroundStyle(.white.opacity(0.48))
                    Text("#\(lights.rgbHex)").font(.system(size: 25, weight: .medium, design: .rounded)).monospaced().foregroundStyle(.white)
                    Text("RGB  \(Int(lights.red * 255)) · \(Int(lights.green * 255)) · \(Int(lights.blue * 255))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.55))
                    Button { showingSaveAlert = true; presetName = "" } label: {
                        Label("Save color", systemImage: "plus").font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 13).padding(.vertical, 9).background(.white.opacity(0.11), in: Capsule())
                    }.buttonStyle(.plain).foregroundStyle(.white)
                }
                Spacer(minLength: 0)
            }
            ColorPicker("Choose any color", selection: Binding(get: { lights.currentColor }, set: { color in
                let ui = UIColor(color)
                var r: CGFloat = 0; var g: CGFloat = 0; var b: CGFloat = 0; var a: CGFloat = 0
                ui.getRed(&r, green: &g, blue: &b, alpha: &a)
                lights.setColor(red: Double(r), green: Double(g), blue: Double(b))
            }), supportsOpacity: false)
            .font(.system(size: 14, weight: .medium)).tint(.white)
            Rectangle().fill(.white.opacity(0.10)).frame(height: 1)
            HStack {
                ForEach(Array(quickColors.enumerated()), id: \.offset) { pair in
                    let item = pair.element
                    Button { lights.setColor(red: item.2, green: item.3, blue: item.4) } label: {
                        Circle().fill(item.1.gradient).frame(width: 35, height: 35)
                            .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
                            .shadow(color: item.1.opacity(0.35), radius: 8, y: 2)
                    }.buttonStyle(.plain).frame(maxWidth: .infinity)
                }
            }
        }.padding(18).glassPanel()
    }

    private var brightnessCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                sectionHeading("Brightness", subtitle: "Set the right atmosphere")
                Spacer()
                Text("\(Int(lights.brightness))%").font(.system(size: 19, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            HStack(spacing: 12) {
                Image(systemName: "sun.min").foregroundStyle(.white.opacity(0.58))
                Slider(value: Binding(get: { lights.brightness }, set: { lights.setBrightness($0) }), in: 1...100)
                    .tint(lights.currentColor)
                Image(systemName: "sun.max.fill").foregroundStyle(.white)
            }
        }.padding(18).glassPanel()
    }

    private var presetsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeading("Your colors", subtitle: "Saved on this iPhone")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(lights.presets) { preset in
                    Button { lights.apply(preset) } label: {
                        HStack(spacing: 10) {
                            Circle().fill(preset.color.gradient).frame(width: 30, height: 30)
                                .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 1))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(preset.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                Text(String(format: "#%02X%02X%02X", Int(preset.red * 255), Int(preset.green * 255), Int(preset.blue * 255)))
                                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
                            }
                            Spacer(minLength: 0)
                        }.padding(10).background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.09), lineWidth: 1))
                    }.buttonStyle(.plain).foregroundStyle(.white)
                    .contextMenu { Button("Remove preset", role: .destructive) { lights.removePreset(preset) } }
                }
            }
        }.padding(18).glassPanel()
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Image(systemName: "lock.shield").font(.system(size: 11))
            Text("Direct Bluetooth · No account · No cloud").font(.system(size: 11, weight: .medium))
        }.foregroundStyle(.white.opacity(0.43)).frame(maxWidth: .infinity).padding(.top, 2)
    }

    private var devicesSheet: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.045, green: 0.055, blue: 0.1).ignoresSafeArea()
                List {
                    Section {
                        if lights.devices.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                ProgressView().tint(.cyan)
                                Text(lights.status).font(.subheadline).foregroundStyle(.secondary)
                            }.padding(.vertical, 12).listRowBackground(.white.opacity(0.04))
                        }
                        ForEach(lights.devices, id: \.identifier) { device in
                            Button { lights.connect(device); showingDevices = false } label: {
                                HStack {
                                    Image(systemName: "lightbulb.led").foregroundStyle(.cyan).frame(width: 32)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(device.name ?? "BLEDOM").foregroundStyle(.primary)
                                        Text(device.identifier.uuidString).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }
                            }.listRowBackground(.white.opacity(0.04))
                        }
                    } header: { Text("Nearby lights") }
                }.scrollContentBackground(.hidden)
            }
            .navigationTitle("Connect light")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { showingDevices = false } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { lights.scan() } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(lights.isScanning || !lights.isPoweredOn)
                }
            }
        }.preferredColorScheme(.dark)
    }

    private func sectionHeading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 19, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            Text(subtitle).font(.system(size: 12)).foregroundStyle(.white.opacity(0.48))
        }
    }
}

private struct GlassPanel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(LinearGradient(colors: [.white.opacity(0.23), .white.opacity(0.045)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
            .shadow(color: .black.opacity(0.16), radius: 22, y: 12)
    }
}

private extension View {
    func glassPanel() -> some View { modifier(GlassPanel()) }
}
