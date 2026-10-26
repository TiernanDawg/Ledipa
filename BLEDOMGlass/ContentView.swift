import SwiftUI
import CoreBluetooth

struct ContentView: View {
    @EnvironmentObject private var lights: BLEController
    @State private var showingDevices = false
    @State private var showingSaveAlert = false
    @State private var presetName = ""
    @State private var showRGBControls = false

    private let quickColors: [(String, Color, Double, Double, Double)] = [
        ("Arctic", Color(red: 0.10, green: 0.68, blue: 1), 0.10, 0.68, 1),
        ("Aurora", Color(red: 0.38, green: 0.96, blue: 0.72), 0.38, 0.96, 0.72),
        ("Violet", Color(red: 0.58, green: 0.31, blue: 1), 0.58, 0.31, 1),
        ("Rose", Color(red: 1, green: 0.18, blue: 0.42), 1, 0.18, 0.42),
        ("Amber", Color(red: 1, green: 0.53, blue: 0.16), 1, 0.53, 0.16),
        ("White", .white, 1, 1, 1)
    ]

    private let scenes: [(String, String, Color, Double, Double, Double)] = [
        ("Cozy", "Warm and relaxed", Color(red: 1, green: 0.48, blue: 0.20), 1, 0.48, 0.20),
        ("Focus", "Clear, cool light", Color(red: 0.72, green: 0.84, blue: 1), 0.72, 0.84, 1),
        ("Ocean", "Deep blue calm", Color(red: 0.05, green: 0.34, blue: 1), 0.05, 0.34, 1),
        ("Dream", "Soft lavender", Color(red: 0.63, green: 0.40, blue: 1), 0.63, 0.40, 1),
        ("Sunset", "Golden hour", Color(red: 1, green: 0.24, blue: 0.16), 1, 0.24, 0.16),
        ("Forest", "Fresh green", Color(red: 0.12, green: 0.82, blue: 0.46), 0.12, 0.82, 0.46)
    ]

    var body: some View {
        ZStack {
            ambientBackground
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    connectionCard
                    colorCard
                    brightnessCard
                    scenesCard
                    presetsCard
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 34)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingDevices) { devicesSheet.presentationDetents([.medium, .large]) }
        .alert("Save this color", isPresented: $showingSaveAlert) {
            TextField("Preset name", text: $presetName)
            Button("Cancel", role: .cancel) { }
            Button("Save") { lights.saveCurrentPreset(name: presetName) }
        } message: { Text("Your color will be saved on this iPhone.") }
    }

    private var ambientBackground: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.025, green: 0.035, blue: 0.075), Color(red: 0.055, green: 0.045, blue: 0.105), Color(red: 0.025, green: 0.035, blue: 0.07)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(Color.cyan.opacity(0.18)).frame(width: 290).blur(radius: 100).offset(x: 145, y: -340)
            Circle().fill(Color.purple.opacity(0.18)).frame(width: 280).blur(radius: 105).offset(x: -145, y: 10)
            Circle().fill(lights.currentColor.opacity(0.17)).frame(width: 250).blur(radius: 100).offset(x: 120, y: 420)
        }.ignoresSafeArea()
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Image(systemName: "sparkles").font(.system(size: 12, weight: .bold))
                    Text("MORG’S LED").font(.system(size: 12, weight: .bold, design: .rounded)).tracking(2.8)
                }.foregroundStyle(.white.opacity(0.62))
                Text("Set the mood.").font(.system(size: 32, weight: .semibold, design: .rounded)).tracking(-1.1)
                Text("Your lights, your atmosphere.").font(.system(size: 13)).foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
            Button { lights.togglePower() } label: {
                ZStack {
                    Circle().fill(lights.isOn ? lights.currentColor.opacity(0.22) : .white.opacity(0.07))
                    Circle().stroke(.white.opacity(0.24), lineWidth: 1)
                    Image(systemName: "power").font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(lights.isOn ? .white : .white.opacity(0.48))
                }.frame(width: 54, height: 54)
                    .shadow(color: lights.isOn ? lights.currentColor.opacity(0.25) : .clear, radius: 18)
            }.buttonStyle(.plain).accessibilityLabel(lights.isOn ? "Turn lights off" : "Turn lights on")
        }.foregroundStyle(.white)
    }

    private var connectionCard: some View {
        Button {
            showingDevices = true
            if lights.devices.isEmpty { lights.scan() }
        } label: {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 17).fill(lights.connectedName == nil ? Color.cyan.opacity(0.13) : lights.currentColor.opacity(0.17))
                    Image(systemName: lights.connectedName == nil ? "dot.radiowaves.left.and.right" : "lightbulb.led.fill")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(lights.connectedName == nil ? Color.cyan : lights.currentColor)
                }.frame(width: 50, height: 50)
                VStack(alignment: .leading, spacing: 5) {
                    Text(lights.connectedName ?? "Connect your LED strip").font(.system(size: 15, weight: .semibold))
                    HStack(spacing: 6) {
                        Circle().fill(lights.connectedName == nil ? (lights.isPoweredOn ? Color.orange : Color.gray) : Color.green).frame(width: 6, height: 6)
                        Text(lights.connectedName == nil ? lights.status : "Connected · Bluetooth").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.58)).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.45))
            }.padding(15).glassPanel()
        }.buttonStyle(.plain).foregroundStyle(.white)
    }

    private var colorCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeading("Color studio", subtitle: "Dial in the exact shade")
            HStack(spacing: 17) {
                ZStack {
                    Circle().fill(RadialGradient(colors: [lights.currentColor.opacity(0.85), lights.currentColor.opacity(0.12), .clear], center: .center, startRadius: 5, endRadius: 78)).frame(width: 142, height: 142).blur(radius: 7)
                    Circle().fill(LinearGradient(colors: [lights.currentColor.opacity(0.78), lights.currentColor], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 88, height: 88)
                        .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 1.3))
                        .overlay(Circle().stroke(.white.opacity(0.16), lineWidth: 6).padding(5))
                        .shadow(color: lights.currentColor.opacity(0.55), radius: 24, y: 4)
                }.frame(width: 132, height: 132)
                VStack(alignment: .leading, spacing: 9) {
                    Text("LIVE COLOR").font(.system(size: 10, weight: .bold)).tracking(1.7).foregroundStyle(.white.opacity(0.48))
                    Text("#\(lights.rgbHex)").font(.system(size: 25, weight: .semibold, design: .rounded)).monospaced().foregroundStyle(.white)
                    Text("R \(Int(lights.red * 255))   G \(Int(lights.green * 255))   B \(Int(lights.blue * 255))")
                        .font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.55))
                    Button { presetName = ""; showingSaveAlert = true } label: {
                        Label("Save shade", systemImage: "bookmark").font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 13).padding(.vertical, 9)
                            .background(.white.opacity(0.10), in: Capsule())
                            .overlay(Capsule().stroke(.white.opacity(0.13), lineWidth: 1))
                    }.buttonStyle(.plain).foregroundStyle(.white)
                }
                Spacer(minLength: 0)
            }
            ColorPicker("Full color picker", selection: Binding(get: { lights.currentColor }, set: { color in
                let ui = UIColor(color)
                var r: CGFloat = 0; var g: CGFloat = 0; var b: CGFloat = 0; var a: CGFloat = 0
                ui.getRed(&r, green: &g, blue: &b, alpha: &a)
                lights.setColor(red: Double(r), green: Double(g), blue: Double(b))
            }), supportsOpacity: false)
            .font(.system(size: 13, weight: .medium)).tint(.white)
            Rectangle().fill(.white.opacity(0.10)).frame(height: 1)
            HStack {
                ForEach(Array(quickColors.enumerated()), id: \.offset) { pair in
                    let item = pair.element
                    Button { lights.setColor(red: item.2, green: item.3, blue: item.4) } label: {
                        VStack(spacing: 7) {
                            Circle().fill(item.1.gradient).frame(width: 34, height: 34)
                                .overlay(Circle().stroke(.white.opacity(0.45), lineWidth: 1))
                                .shadow(color: item.1.opacity(0.32), radius: 8, y: 2)
                            Text(item.0).font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.62))
                        }.frame(maxWidth: .infinity)
                    }.buttonStyle(.plain)
                }
            }
            DisclosureGroup(isExpanded: $showRGBControls) {
                VStack(spacing: 12) {
                    rgbSlider("Red", value: Binding(get: { lights.red }, set: { lights.setColor(red: $0, green: lights.green, blue: lights.blue) }), color: .red)
                    rgbSlider("Green", value: Binding(get: { lights.green }, set: { lights.setColor(red: lights.red, green: $0, blue: lights.blue) }), color: .green)
                    rgbSlider("Blue", value: Binding(get: { lights.blue }, set: { lights.setColor(red: lights.red, green: lights.green, blue: $0) }), color: .blue)
                }.padding(.top, 12)
            } label: {
                Label("Fine-tune RGB values", systemImage: "slider.horizontal.3").font(.system(size: 12, weight: .medium))
            }.tint(.white.opacity(0.85))
        }.padding(19).glassPanel()
    }

    private var brightnessCard: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .top) {
                sectionHeading("Brightness", subtitle: "From subtle glow to full power")
                Spacer()
                Text("\(Int(lights.brightness))%").font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            Slider(value: Binding(get: { lights.brightness }, set: { lights.setBrightness($0) }), in: 1...100)
                .tint(lights.currentColor)
            HStack {
                Label("Low glow", systemImage: "sun.min")
                Spacer()
                Label("Full glow", systemImage: "sun.max.fill")
            }.font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.48))
            HStack(spacing: 8) {
                brightnessChip("25%", value: 25)
                brightnessChip("50%", value: 50)
                brightnessChip("75%", value: 75)
                brightnessChip("100%", value: 100)
            }
        }.padding(19).glassPanel()
    }

    private var scenesCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            sectionHeading("Atmospheres", subtitle: "One tap to change the room")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(Array(scenes.enumerated()), id: \.offset) { item in
                    let scene = item.element
                    Button { lights.setColor(red: scene.3, green: scene.4, blue: scene.5) } label: {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 10).fill(scene.2.gradient).frame(width: 39, height: 43)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.25), lineWidth: 1))
                                .shadow(color: scene.2.opacity(0.3), radius: 9, y: 2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(scene.0).font(.system(size: 13, weight: .semibold))
                                Text(scene.1).font(.system(size: 9)).foregroundStyle(.white.opacity(0.52)).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.09), lineWidth: 1))
                    }.buttonStyle(.plain).foregroundStyle(.white)
                }
            }
            Text("Atmospheres apply a solid color. Animated effects depend on the LED controller’s supported protocol.")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4)).fixedSize(horizontal: false, vertical: true)
        }.padding(19).glassPanel()
    }

    private var presetsCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top) {
                sectionHeading("Saved colors", subtitle: "Your personal palette")
                Spacer()
                Text("\(lights.presets.count)").font(.system(size: 11, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 9).padding(.vertical, 5).background(.white.opacity(0.08), in: Capsule())
            }
            if lights.presets.isEmpty {
                Text("Save a color from Color Studio and it will appear here.")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5)).padding(.vertical, 8)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(lights.presets) { preset in
                        Button { lights.apply(preset) } label: {
                            HStack(spacing: 9) {
                                Circle().fill(preset.color.gradient).frame(width: 31, height: 31)
                                    .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 1))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(preset.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                    Text(String(format: "#%02X%02X%02X", Int(preset.red * 255), Int(preset.green * 255), Int(preset.blue * 255)))
                                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(.white.opacity(0.47))
                                }
                                Spacer(minLength: 0)
                            }.padding(10).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 15))
                                .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.08), lineWidth: 1))
                        }.buttonStyle(.plain).foregroundStyle(.white)
                            .contextMenu { Button("Remove saved color", role: .destructive) { lights.removePreset(preset) } }
                    }
                }
            }
        }.padding(19).glassPanel()
    }

    private var footer: some View {
        VStack(spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                Text("Direct Bluetooth control")
                Circle().frame(width: 3, height: 3)
                Text("No account")
                Circle().frame(width: 3, height: 3)
                Text("No cloud")
            }.font(.system(size: 10, weight: .medium))
            Text("MORG’S LED  ·  PERSONAL LIGHT CONTROL").font(.system(size: 8, weight: .bold)).tracking(1.4)
        }.foregroundStyle(.white.opacity(0.38)).frame(maxWidth: .infinity).padding(.top, 2)
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
                                Text("Keep the strip powered on and your iPhone nearby.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 12).listRowBackground(Color.white.opacity(0.04))
                        }
                        ForEach(lights.devices, id: \.identifier) { device in
                            Button { lights.connect(device); showingDevices = false } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "lightbulb.led.fill").foregroundStyle(.cyan).frame(width: 30, height: 30)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(device.name ?? "Bluetooth LED").foregroundStyle(.primary)
                                        Text(device.identifier.uuidString).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }
                            }.listRowBackground(Color.white.opacity(0.04))
                        }
                    } header: { Text("Nearby LED devices") }
                }.scrollContentBackground(.hidden)
            }
            .navigationTitle("Connect a light")
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
            Text(subtitle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.48))
        }
    }

    private func brightnessChip(_ title: String, value: Double) -> some View {
        Button { lights.setBrightness(value) } label: {
            Text(title).font(.system(size: 11, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 9)
                .background(abs(lights.brightness - value) < 1 ? lights.currentColor.opacity(0.22) : .white.opacity(0.06), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(abs(lights.brightness - value) < 1 ? 0.28 : 0.08), lineWidth: 1))
        }.buttonStyle(.plain).foregroundStyle(.white)
    }

    private func rgbSlider(_ title: String, value: Binding<Double>, color: Color) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.65)).frame(width: 43, alignment: .leading)
            Slider(value: value, in: 0...1).tint(color)
            Text(String(format: "%03d", Int(value.wrappedValue * 255))).font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55)).frame(width: 27, alignment: .trailing)
        }
    }
}

private struct GlassPanel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 27, style: .continuous))
            .background(LinearGradient(colors: [.white.opacity(0.065), .white.opacity(0.018)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 27, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 27, style: .continuous).stroke(LinearGradient(colors: [.white.opacity(0.26), .white.opacity(0.035), .white.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
            .shadow(color: .black.opacity(0.19), radius: 24, y: 12)
    }
}

private extension View {
    func glassPanel() -> some View { modifier(GlassPanel()) }
}
