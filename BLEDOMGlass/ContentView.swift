import SwiftUI
import CoreBluetooth
import UIKit

struct ContentView: View {
    @EnvironmentObject private var lights: BLEController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var audio = AudioAnalyzer()
    @StateObject private var timers = TimerCenter()
    @Namespace private var glassSpace

    @State private var tab = 0
    @State private var hue = 0.57
    @State private var wheelSaturation = 1.0
    @State private var temperature = 4200.0
    @State private var sensitivity = 0.65
    @State private var musicMode = "Rhythm"
    @State private var selectedCategory = "All"
    @State private var sceneShelf = "All scenes"
    @State private var favoriteSceneIDs = Set(UserDefaults.standard.stringArray(forKey: "morgs.scene-favorites") ?? [])
    @State private var recentSceneIDs = UserDefaults.standard.stringArray(forKey: "morgs.scene-recent") ?? []
    @State private var scenePaused = false
    @State private var sceneSpeed = 0.45
    @State private var sceneBrightness = 80.0
    @State private var selectedScene: LEDScene?
    @State private var showingDevices = false
    @State private var showingInfo = false
    @State private var diyName = ""
    @State private var diyColors: [Color] = [.cyan,.purple]
    @State private var diyMode = "Breathe"
    @State private var diySpeed = 0.45
    @State private var diySaved: [LEDScene] = []
    @State private var sceneTask: Task<Void, Never>?
    @State private var recent: [Color] = []
    @State private var favorites: [Color] = []
    @State private var showDIY = false
    @State private var timerDate = Date()
    @State private var showScenePlayer = false
    @State private var bloom = false

    private let categories = ["All","Ambient","Nature","Party","Gaming","Cozy","Sleep"]
    private let modes = ["Fade","Pulse","Breathe","Strobe","Rainbow","Candle flicker","Aurora"]

    private var accent: Color {
        let color = lights.isOn ? lights.currentColor : Color(red:0.28,green:0.30,blue:0.38)
        return color.saturated(1.35)
    }

    var body: some View {
        ZStack {
            driftingBackground
            TabView(selection:$tab) {
                home.tabItem { Label("Home",systemImage:"house.fill") }.tag(0)
                scenes.tabItem { Label("Scenes",systemImage:"sparkles") }.tag(1)
                music.tabItem { Label("Music",systemImage:"waveform") }.tag(2)
                timersPage.tabItem {
                    Label {
                        HStack(spacing: 3) {
                            Text("Timers")
                            if timers.enabled {
                                Image(systemName: "clock.badge.checkmark")
                                    .font(.system(size: 9, weight: .bold))
                            }
                        }
                    } icon: {
                        Image(systemName: "timer")
                    }
                }.tag(3)
            }
            .tint(accent)
            .modifier(MinimizeTabBar())
        }
        .preferredColorScheme(.dark)
        .animation(reduceMotion ? nil : MorgDesign.spring, value: tab)
        .sheet(isPresented:$showingDevices) { deviceSheet }
        .sheet(isPresented:$showDIY) { diySheet.presentationDetents([.large]) }
        .fullScreenCover(isPresented:$showScenePlayer) { scenePlayerSheet }
        .sheet(isPresented:$showingInfo) { infoSheet.presentationDetents([.medium,.large]) }
        .onAppear { restoreState() }
        .onOpenURL { handleAutomationURL($0) }
        .onChange(of: lights.currentColor) { _, color in
            syncWheel(to: color)
        }
        .onChange(of:temperature) { _, kelvin in
            apply(approximateWhitePoint(kelvin: kelvin))
        }
        .onChange(of:sceneSpeed) { _, value in if selectedScene != nil { restartScene() } }
        .onChange(of:sceneBrightness) { _, value in lights.setBrightness(value) }
    }

    private var driftingBackground: some View {
        ZStack {
            Color(red: 0.018, green: 0.022, blue: 0.040)
            RadialGradient(
                colors: [accent.opacity(lights.isOn ? 0.20 : 0.055), .clear],
                center: .topTrailing,
                startRadius: 8,
                endRadius: 520
            )
            RadialGradient(
                colors: [Color.indigo.opacity(0.10), .clear],
                center: .bottomLeading,
                startRadius: 0,
                endRadius: 430
            )
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.45), value: lights.currentColor)
        .animation(.easeInOut(duration: 0.35), value: lights.isOn)
    }

    private func screen<Content:View>(_ title:String,@ViewBuilder content:()->Content)->some View {
        ScrollView(showsIndicators:false) {
            VStack(alignment:.leading,spacing:16) {
                HStack(alignment:.center) {
                    Text(title).font(.system(size:30,weight:.bold)).tracking(-0.8)
                    Spacer(minLength:8)
                    GlassEffectContainer(spacing:8) {
                        HStack(spacing:8) {
                            Button { showingInfo=true } label: {
                                Image(systemName:"info").font(.system(size:12,weight:.bold)).frame(width:34,height:34)
                                    .glassEffect(.regular.interactive(),in:Circle()).glassEffectID("info-button",in:glassSpace)
                            }.buttonStyle(.plain).accessibilityLabel("Information")
                            statusPill
                        }
                    }
                }.padding(.top,8)
                content()
            }
            .padding(.horizontal, MorgDesign.pageInset)
            .padding(.top,4)
            .padding(.bottom,24)
            .frame(maxWidth:620)
            .frame(maxWidth:.infinity)
        }
        .safeAreaInset(edge:.bottom,spacing:0) {
            if tab == 1, selectedScene != nil { sceneDock.padding(.horizontal,16).padding(.top,8).padding(.bottom,4) }
        }
    }

    private var statusPill: some View {
        Button {
            showingDevices=true
            if lights.devices.isEmpty { lights.scan() }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(lights.connectedName == nil ? (lights.status.localizedCaseInsensitiveContains("connect") ? .orange : .gray) : .green)
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lights.connectedName ?? (lights.status.localizedCaseInsensitiveContains("connect") ? "Connecting" : "Not connected"))
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Text(lights.connectedName == nil ? "Bluetooth" : "\(lights.signalQualityLabel) · \(lights.signalRSSI.map { "\($0) dBm" } ?? "checking")")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }
                Image(systemName: lights.connectedName == nil ? "antenna.radiowaves.left.and.right.slash" : "antenna.radiowaves.left.and.right")
                    .font(.system(size: 12, weight: .medium))
                    .opacity(0.82)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).opacity(0.65)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .glassControl(id:"device",namespace:glassSpace,tint:lights.connectedName == nil ? .white.opacity(0.05) : .green.opacity(0.14))
        }.buttonStyle(.plain).accessibilityLabel("Bluetooth device, \(lights.connectedName ?? "not connected")")
    }

    private var home: some View {
        screen("Home") {
            VStack(spacing:18) {
                colorHero
                controlPanel
                colorsSection
            }
        }
    }

    private var colorHero: some View {
        VStack(spacing: 18) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("LIGHT CONTROL")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.8)
                        .foregroundStyle(.white.opacity(0.52))
                    Text(lights.isOn ? "Set the mood." : "Your light is off.")
                        .font(.system(size: 25, weight: .bold))
                        .tracking(-0.6)
                    Text("#\(lights.rgbHex)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.58))
                }
                Spacer()
                Button {
                    UIPasteboard.general.string = "#\(lights.rgbHex)"
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 42, height: 42)
                        .background(.white.opacity(0.075), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy HEX color")
            }

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [lights.currentColor.opacity(lights.isOn ? 0.42 : 0.12), .clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 146
                        )
                    )
                    .frame(width: 292, height: 292)
                    .blur(radius: 18)
                ColorWheel(
                    hue: $hue,
                    saturation: $wheelSaturation,
                    selection: { selected in apply(selected, persist: false) },
                    onCommit: {
                        addRecent(lights.currentColor)
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                )
                .frame(width: 224, height: 224)
                .accessibilityLabel("Color selector")
                .accessibilityHint("Drag around the wheel to choose hue and saturation.")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)

            HStack(spacing: 11) {
                Circle()
                    .fill(lights.currentColor)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(.white.opacity(0.45), lineWidth: 1))
                    .shadow(color: lights.currentColor.opacity(0.7), radius: 9)
                Text(lights.isOn ? "Selected color" : "Color selection")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("Drag to adjust")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.48))
            }

            Button {
                lights.togglePower()
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "power")
                        .font(.system(size: 15, weight: .bold))
                    Text(lights.isOn ? "Turn light off" : "Turn light on")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .bold))
                        .opacity(0.7)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(
                    LinearGradient(
                        colors: lights.isOn
                            ? [accent.opacity(0.78), accent.opacity(0.38)]
                            : [Color.white.opacity(0.13), Color.white.opacity(0.07)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.18), lineWidth: 1))
                .shadow(color: lights.isOn ? accent.opacity(0.20) : .clear, radius: 18, y: 5)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Toggles the connected LED strip.")
        }
        .padding(20)
        .panelGlass()
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(accent.opacity(lights.isOn ? 0.18 : 0.08), lineWidth: 1))
        .animation(.spring(response: 0.42, dampingFraction: 0.88), value: lights.isOn)
    }

    private var controlPanel: some View {
        VStack(alignment: .leading, spacing: 19) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Brightness", systemImage: "sun.max.fill")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text("\(Int(lights.brightness))%")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.82))
                }
                brightnessGauge
            }

            Rectangle().fill(.white.opacity(0.11)).frame(height: 1)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Warm–Cool balance", systemImage: "thermometer.medium")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text("≈ \(Int(temperature))K")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.68))
                }
                TemperatureTrack(value: $temperature, thumb: accent)
                    .frame(height: 30)
                HStack {
                    Label("Warm", systemImage: "sun.max.fill").foregroundStyle(.orange)
                    Spacer()
                    Label("Cool", systemImage: "snowflake").foregroundStyle(.cyan)
                }
                .font(.system(size: 10, weight: .medium))
            }
            Text("Simulated with RGB color. Your strip does not have a separate white channel.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.43))
        }
        .padding(18)
        .panelGlass()
    }

    private var brightnessGauge: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width)
            let level = CGFloat(lights.brightness) / 100
            let fillWidth = width * level
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.11))
                Capsule()
                    .fill(LinearGradient(colors: [accent.opacity(0.42), accent, .white.opacity(0.88)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(10, fillWidth))
                    .shadow(color: accent.opacity(0.32), radius: 8)
                Circle()
                    .fill(.white)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().stroke(accent.opacity(0.8), lineWidth: 2))
                    .shadow(color: accent.opacity(0.55), radius: 7)
                    .offset(x: max(0, min(width - 18, fillWidth - 9)))
            }
            .frame(height: 24)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                lights.setBrightness(Double(max(0, min(1, value.location.x / width)) * 100))
            })
        }
        .frame(height: 28)
        .accessibilityElement()
        .accessibilityLabel("Brightness")
        .accessibilityValue("\(Int(lights.brightness)) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: lights.setBrightness(min(100, lights.brightness + 5))
            case .decrement: lights.setBrightness(max(1, lights.brightness - 5))
            @unknown default: break
            }
        }
    }

    private var colorsSection: some View {
        let palette=uniquePalette(Array(favorites+recent))
        return Group {
            if !palette.isEmpty || !favorites.isEmpty {
                VStack(alignment:.leading,spacing:11) {
                    HStack {
                        Text("Colors").font(.system(size:19,weight:.bold))
                        Spacer()
                        Button {
                            let color=lights.currentColor
                            if !favorites.contains(where:{perceptuallyClose($0,color)}) { favorites.insert(color,at:0); favorites=Array(favorites.prefix(8)); persistState() }
                            UIImpactFeedbackGenerator(style:.light).impactOccurred()
                        } label: { Image(systemName:"plus").font(.system(size:14,weight:.bold)).frame(width:32,height:32).controlGlass(id:"save-color") }.buttonStyle(.plain)
                    }
                    ScrollView(.horizontal,showsIndicators:false) {
                        HStack(spacing:12) {
                            ForEach(Array(palette.enumerated()),id:\.offset) { index,color in
                                Circle().fill(color.gradient).frame(width:38,height:38)
                                    .overlay(Circle().stroke(.white.opacity(0.34),lineWidth:1))
                                    .shadow(color:color.opacity(0.38),radius:8)
                                    .contextMenu {
                                        Button("Set as favorite",systemImage:"star.fill") { addFavorite(color) }
                                        Button("Remove from favorites",systemImage:"star.slash") { favorites.removeAll{perceptuallyClose($0,color)}; persistState() }
                                    }
                                    .onTapGesture { apply(color); addRecent(color); UISelectionFeedbackGenerator().selectionChanged() }
                            }
                        }.padding(.vertical,3)
                    }
                }
            }
        }
    }

    private var scenes: some View {
        screen("Scenes") {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Scene collection", selection: $sceneShelf) {
                    Text("All scenes").tag("All scenes")
                    Text("Favorites").tag("Favorites")
                    Text("Recently used").tag("Recently used")
                }
                .pickerStyle(.segmented)
                .tint(accent)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories, id: \.self) { category in
                            Button(category) {
                                withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                                    selectedCategory = category
                                }
                                UISelectionFeedbackGenerator().selectionChanged()
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                            .foregroundStyle(selectedCategory == category ? .white : .white.opacity(0.7))
                            .controlGlass(id: "category-\(category)", tint: selectedCategory == category ? accent.opacity(0.34) : .clear)
                        }
                    }
                }

                HStack(alignment: .firstTextBaseline) {
                    Text(sceneShelf == "Favorites" ? "Your favorites" : (sceneShelf == "Recently used" ? "Recently played" : "Made for your space"))
                        .font(.system(size: 20, weight: .bold))
                    Spacer()
                    Text("\(visibleScenes.count) scenes")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                }

                if visibleScenes.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: sceneShelf == "Favorites" ? "star" : "clock.arrow.circlepath")
                            .font(.system(size: 27, weight: .light))
                            .foregroundStyle(accent)
                        Text(sceneShelf == "Favorites" ? "No favorites yet" : "No recent scenes")
                            .font(.system(size: 15, weight: .semibold))
                        Text(sceneShelf == "Favorites" ? "Tap the star on a scene to save it here." : "Scenes you play will appear here.")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.52))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .panelGlass()
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 13) {
                        ForEach(visibleScenes) { scene in
                            sceneCard(scene)
                        }
                    }
                }

                Button { showDIY = true } label: {
                    Label("Create your own scene", systemImage: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .controlGlass(id: "create-scene", tint: accent.opacity(0.18))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sceneCard(_ scene: LEDScene) -> some View {
        let active = selectedScene?.id == scene.id
        let favorite = favoriteSceneIDs.contains(scene.id)
        let colors = scene.colors.isEmpty ? [Color.black] : scene.colors
        return ZStack(alignment: .topTrailing) {
            Button {
                selectedScene = scene
                sceneSpeed = scene.speed
                scenePaused = false
                recentSceneIDs.removeAll { $0 == scene.id }
                recentSceneIDs.insert(scene.id, at: 0)
                recentSceneIDs = Array(recentSceneIDs.prefix(12))
                UserDefaults.standard.set(recentSceneIDs, forKey: "morgs.scene-recent")
                startScene(scene)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    ZStack(alignment: .bottomLeading) {
                        LinearGradient(colors: colors + Array(colors.reversed()), startPoint: .topLeading, endPoint: .bottomTrailing)
                        Circle()
                            .fill(colors.first?.opacity(0.78) ?? .white.opacity(0.3))
                            .frame(width: 112, height: 112)
                            .blur(radius: 34)
                            .offset(x: 75, y: -28)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        Image(systemName: scene.symbol)
                            .font(.system(size: 23, weight: .light))
                            .foregroundStyle(.white.opacity(0.95))
                            .padding(15)
                        HStack(spacing: 5) {
                            Circle().fill(active ? .green : .white.opacity(0.7)).frame(width: 6, height: 6)
                            Text(active ? (scenePaused ? "PAUSED" : "PLAYING") : scene.category.uppercased())
                                .font(.system(size: 8, weight: .bold))
                                .tracking(1)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.24), in: Capsule())
                        .padding(10)
                    }
                    .frame(height: 104)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(scene.name)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        Text(scene.motion == "Fade" ? "Color atmosphere" : scene.motion)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.48))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(.black.opacity(0.16))
                }
                .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).stroke(active ? accent.opacity(0.95) : .white.opacity(0.12), lineWidth: active ? 2 : 1))
                .shadow(color: active ? accent.opacity(0.22) : .clear, radius: 14, y: 4)
                .contentShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                if favorite { favoriteSceneIDs.remove(scene.id) }
                else { favoriteSceneIDs.insert(scene.id) }
                UserDefaults.standard.set(Array(favoriteSceneIDs), forKey: "morgs.scene-favorites")
                UISelectionFeedbackGenerator().selectionChanged()
            } label: {
                Image(systemName: favorite ? "star.fill" : "star")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(favorite ? .yellow : .white)
                    .frame(width: 32, height: 32)
                    .background(.black.opacity(0.38), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.24), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(9)
            .accessibilityLabel(favorite ? "Remove \(scene.name) from favorites" : "Add \(scene.name) to favorites")
        }
        .accessibilityElement(children: .contain)
    }

    private var sceneDock: some View {
        HStack(spacing:12) {
            Image(systemName:selectedScene?.symbol ?? "sparkles").font(.system(size:16,weight:.semibold)).foregroundStyle(accent)
            VStack(alignment:.leading,spacing:2) {
                Text(selectedScene?.name ?? "Scene").font(.system(size:13,weight:.semibold)).lineLimit(1)
                Text("WHOLE STRIP").font(.system(size:9,weight:.medium)).tracking(1).foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            Button { showScenePlayer = true } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 38, height: 38).controlGlass(id: "scene-focus") }
                .buttonStyle(.plain)
                .accessibilityLabel("Open scene focus mode")
            Button { stopScene() } label: { Image(systemName: "stop.fill").frame(width: 38, height: 38).controlGlass(id: "scene-stop") }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop scene")
        }.padding(10).panelGlass()
    }

    private var scenePlayerSheet: some View {
        ZStack {
            LinearGradient(
                colors: (selectedScene?.colors ?? [accent]) + Array((selectedScene?.colors ?? [accent]).reversed()),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(Color.black.opacity(0.48))
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button {
                        showScenePlayer = false
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 42, height: 42)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close scene player")
                    Spacer()
                    Text("SCENE FOCUS")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Button {
                        stopScene()
                        showScenePlayer = false
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 42, height: 42)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Stop scene")
                }
                .padding(.top, 14)

                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: selectedScene?.symbol ?? "sparkles")
                        .font(.system(size: 38, weight: .ultraLight))
                        .symbolRenderingMode(.hierarchical)
                    Text(selectedScene?.name ?? "Scene")
                        .font(.system(size: 32, weight: .bold))
                        .tracking(-0.8)
                        .multilineTextAlignment(.center)
                    Text(scenePaused ? "Paused" : "Lighting the room")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                }
                .shadow(color: .black.opacity(0.3), radius: 16)
                Spacer()

                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Label("Loop duration", systemImage: "arrow.triangle.2.circlepath")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text(sceneDurationLabel)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .monospacedDigit()
                    }
                    Slider(value: $sceneSpeed, in: 0...1)
                        .tint(.white)
                        .accessibilityLabel("Scene loop duration")
                        .accessibilityValue(sceneDurationLabel)

                    HStack {
                        Text("30 min").font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.62))
                        Spacer()
                        Text("10 sec").font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.62))
                    }

                    HStack {
                        Label("Brightness", systemImage: "sun.max.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text("\(Int(sceneBrightness))%")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                    }
                    Slider(value: $sceneBrightness, in: 1...100)
                        .tint(.white)

                    Button {
                        scenePaused.toggle()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Label(scenePaused ? "Resume scene" : "Pause scene", systemImage: scenePaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(.white.opacity(0.2), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 25, style: .continuous).stroke(.white.opacity(0.18), lineWidth: 1))
                .padding(.bottom, 18)
            }
            .padding(.horizontal, 22)
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
    }

    private var sceneDurationLabel: String {
        let seconds = 10 * pow(180, 1 - sceneSpeed)
        if seconds < 60 { return "\(Int(seconds.rounded())) sec" }
        let minutes = seconds / 60
        return minutes >= 10 ? "\(Int(minutes.rounded())) min" : String(format: "%.1f min", minutes)
    }

    private var music: some View {
        screen("Music") {
            VStack(spacing:20) {
                visualizer
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Microphone input").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text(audio.isRunning ? "\(Int(audio.inputLevel * 100))%" : "Off")
                            .font(.system(size: 12, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    ProgressView(value: audio.inputLevel)
                        .tint(accent)
                        .scaleEffect(x: 1, y: 1.25, anchor: .center)
                        .accessibilityLabel("Microphone input level")
                        .accessibilityValue("\(Int(audio.inputLevel * 100)) percent")
                }
                .padding(15)
                .panelGlass()
                Button {
                    if audio.isRunning { audio.stop(); stopScene() }
                    else { audio.start() }
                } label: {
                    Label(audio.isRunning ? "Stop listening" : "Start listening",systemImage:audio.isRunning ? "stop.fill" : "mic.fill")
                        .font(.system(size:16,weight:.bold))
                        .frame(maxWidth:.infinity).padding(.vertical,17)
                        .controlGlass(id:"music-primary",tint:accent.opacity(0.42))
                }.buttonStyle(.plain)
                VStack(alignment:.leading,spacing:14) {
                    Text("Mode").font(.system(size:14,weight:.semibold))
                    GlassEffectContainer(spacing:4) {
                        HStack(spacing:4) {
                            ForEach(["Rhythm","Energy","Spectrum","Rolling"],id:\.self) { mode in
                                Button(mode) { musicMode=mode; UISelectionFeedbackGenerator().selectionChanged() }
                                    .font(.system(size:11,weight:.semibold))
                                    .frame(maxWidth:.infinity).padding(.vertical,11)
                                    .background {
                                        if musicMode == mode {
                                            Capsule().fill(accent.opacity(0.35)).glassEffect(.regular.tint(accent.opacity(0.35)).interactive()).glassEffectID("music-\(mode)",in:glassSpace)
                                        }
                                    }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    HStack { Text("Sensitivity"); Spacer(); Text("\(Int(sensitivity*100))%").monospacedDigit() }
                        .font(.system(size:13,weight:.medium))
                    Slider(value:$sensitivity,in:0.1...1).tint(accent)
                }.padding(17).panelGlass()
                Text(lights.connectedName == nil ? "Microphone: \(audio.message) · Connect your LED to see color changes." : audio.message).font(.system(size:12,weight:.medium)).foregroundStyle(.white.opacity(0.58)).frame(maxWidth:.infinity,alignment:.leading)
            }
        }
        .onChange(of:audio.inputLevel) { _, _ in updateMusicColor() }
        .onChange(of:audio.bass) { _, _ in updateMusicColor() }
        .onChange(of:audio.mid) { _, _ in updateMusicColor() }
        .onChange(of:audio.high) { _, _ in updateMusicColor() }
        .onChange(of:sensitivity) { _, _ in updateMusicColor() }
        .onChange(of:musicMode) { _, _ in updateMusicColor() }
        .onDisappear { audio.stop() }
    }

    private var visualizer: some View {
        let soundDetected = audio.isRunning && audio.inputLevel >= 0.20
        return VStack(spacing: 12) {
            if soundDetected {
                TimelineView(.animation(minimumInterval: 0.08, paused: reduceMotion)) { _ in
                    audioBars
                }
                .frame(height: 142)
            } else {
                HStack(alignment: .center, spacing: 4) {
                    ForEach(0..<32, id: \.self) { _ in
                        Capsule()
                            .fill(.white.opacity(0.18))
                            .frame(maxWidth: .infinity)
                            .frame(height: 8)
                    }
                }
                .frame(height: 142)
                .padding(.horizontal, 5)
            }

            HStack(spacing: 7) {
                Circle()
                    .fill(soundDetected ? .green : .orange.opacity(0.85))
                    .frame(width: 7, height: 7)
                Text(soundDetected ? "Sound detected" : (audio.isRunning ? "Waiting for sound" : "Microphone off"))
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(soundDetected ? "\(Int(audio.inputLevel * 100))% input" : "Idle")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.48))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .panelGlass()
        .accessibilityElement(children: .combine)
    }

    private var audioBars: some View {
        let bands = [audio.bass, audio.mid, audio.high]
        let levels = (0..<32).map { index -> CGFloat in
            let band = index < 10 ? bands[0] : (index < 22 ? bands[1] : bands[2])
            let distance = abs(Double(index) - 15.5) / 15.5
            let shaped = max(0.04, min(1, band * (1.25 - distance * 0.52)))
            return CGFloat(shaped)
        }
        return HStack(alignment: .center, spacing: 4) {
            ForEach(0..<32, id: \.self) { index in
                Capsule()
                    .fill(LinearGradient(colors: [accent.opacity(0.58), accent, .white.opacity(0.88)], startPoint: .bottom, endPoint: .top))
                    .frame(maxWidth: .infinity)
                    .frame(height: max(8, 142 * levels[index]))
                    .shadow(color: accent.opacity(0.26), radius: 4)
            }
        }
        .frame(height: 142)
        .padding(.horizontal, 5)
    }

    private var timersPage: some View {
        screen("Timers") {
            VStack(spacing:14) {
                VStack(alignment:.leading,spacing:16) {
                    HStack { Text("Next routine").font(.system(size:14,weight:.semibold)); Spacer(); Text(timers.enabled ? "ACTIVE" : "READY").font(.system(size:10,weight:.bold)).tracking(1).foregroundStyle(timers.enabled ? accent : .white.opacity(0.5)) }
                    DatePicker("Time",selection:$timerDate,displayedComponents:.hourAndMinute)
                        .datePickerStyle(.compact).font(.system(size:17,weight:.semibold))
                    HStack(spacing:10) {
                        timerTile("Sunrise","sunrise.fill",.orange) {
                            timers.scheduleWake(at:timerDate,brightness:{lights.setBrightness($0)},powerOn:{if !lights.isOn {lights.togglePower()}})
                        }
                        timerTile("Evening","sunset.fill",.purple) {
                            timers.fadeToBrightness(25, startingAt: lights.brightness, brightness: { lights.setBrightness($0) })
                        }
                        timerTile("Sleep","moon.zzz.fill",.indigo) {
                            timers.sleepFade(startingAt: lights.brightness,brightness:{lights.setBrightness($0)},powerOff:{if lights.isOn {lights.togglePower()}})
                        }
                    }
                    HStack { Text("Fade duration"); Spacer(); Text("\(Int(timers.sleepMinutes)) min").monospacedDigit() }
                    Slider(value:$timers.sleepMinutes,in:5...180,step:5).tint(accent)
                    HStack { Text("Wake ramp"); Spacer(); Text("\(Int(timers.wakeMinutes)) min").monospacedDigit() }
                    Slider(value:$timers.wakeMinutes,in:5...60,step:1).tint(accent)
                    if timers.enabled { Button("Cancel active timer",role:.destructive) { timers.cancel() }.buttonStyle(.glass) }
                    Text(timers.message).font(.system(size:11,weight:.medium)).foregroundStyle(.white.opacity(0.55))
                }.padding(18).panelGlass()
            }
        }
    }

    private func timerTile(_ title: String, _ symbol: String, _ tint: Color, _ action: @escaping () -> Void) -> some View {
        Button {
            guard lights.connectedName != nil else { showingDevices = true; return }
            action()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: symbol)
                        .font(.system(size: 19, weight: .semibold))
                    Spacer()
                    if timers.enabled {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .opacity(0.78)
                    }
                }
                Spacer(minLength: 0)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(title == "Sunrise" ? "Gentle wake-up" : (title == "Evening" ? "Dim to 25%" : "Fade fully off"))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
            .padding(12)
            .background(
                LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.09)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(tint.opacity(0.36), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityHint(title == "Sunrise" ? "Schedule a gradual wake-up." : (title == "Evening" ? "Fade the light down to twenty-five percent." : "Fade the light out and turn it off."))
    }

    private var infoSheet: some View {
        NavigationStack {
            List {
                Section("Your LED strip") {
                    Text("This controller sends whole-strip RGB and brightness commands. It does not address independent segments or pixels.")
                    Text("Warm–Cool balance is an RGB approximation. The hardware protocol exposed by this strip does not provide a separate white-temperature channel.")
                }
                Section("Music") {
                    Text("Music mode listens through the iPhone microphone. It cannot capture protected audio directly from Apple Music or other apps. Frequency bands are mapped into one whole-strip color.")
                }
                Section("Timers") {
                    Text("iOS may suspend the app in the background. Sunrise, sunset, and sleep routines need Morg’s LED to remain open and Bluetooth connected; a closed app cannot reliably send scheduled BLE commands.")
                }
                Section("Accessibility") {
                    Text("Reduce Motion pauses decorative animation. Reduce Transparency uses a higher-contrast fallback surface. Layouts scroll vertically and respect Dynamic Type.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black.opacity(0.72))
            .navigationTitle("About controls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.topBarTrailing) { Button("Done"){showingInfo=false} } }
        }.preferredColorScheme(.dark)
    }

    private var diySheet: some View {
        NavigationStack {
            Form {
                Section("Scene") {
                    TextField("Scene name",text:$diyName)
                    Picker("Motion",selection:$diyMode) { ForEach(modes,id:\.self){Text($0)} }
                    HStack { Text("Speed"); Slider(value:$diySpeed,in:0.05...1) }
                }
                Section("Colors · 2 to 6") {
                    ForEach(diyColors.indices,id:\.self) { i in ColorPicker("Color \(i+1)",selection:$diyColors[i],supportsOpacity:false) }
                    if diyColors.count < 6 { Button("Add color"){diyColors.append(.pink)} }
                    if diyColors.count > 2 { Button("Remove last color",role:.destructive){diyColors.removeLast()} }
                }
                Section { Button("Save scene") {
                    let scene=LEDScene(id:UUID().uuidString,name:diyName.isEmpty ? "My scene" : diyName,category:"DIY",symbol:"wand.and.stars",colors:diyColors,motion:diyMode,speed:diySpeed)
                    diySaved.append(scene); selectedScene=scene; persistScenes(); startScene(scene); showDIY=false
                } }
            }.scrollContentBackground(.hidden).background(Color.black.opacity(0.88))
                .navigationTitle("Create scene").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.topBarTrailing){Button("Done"){showDIY=false}} }
        }.preferredColorScheme(.dark)
    }

    private var deviceSheet: some View {
        NavigationStack {
            List {
                Section("Connection quality") {
                    HStack {
                        Label("Signal", systemImage: "antenna.radiowaves.left.and.right")
                        Spacer()
                        Text(lights.signalRSSI.map { "\(lights.signalQualityLabel) · \($0) dBm" } ?? lights.signalQualityLabel)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 5) {
                        ForEach(0..<4, id: \.self) { index in
                            Capsule()
                                .fill(index < lights.signalBars ? accent : Color.white.opacity(0.10))
                                .frame(height: 6)
                        }
                    }
                    .frame(height: 10)
                    signalHistoryGraph
                        .frame(height: 54)
                    Text("Signal history is sampled from CoreBluetooth every 10 seconds while connected. It reflects radio strength, not a guarantee of controller response.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Section {
                    HStack {
                        Circle().fill(lights.isPoweredOn ? .green : .orange).frame(width: 8, height: 8)
                        Text(lights.status).font(.system(size: 13, weight: .medium))
                    }
                    Toggle("Reconnect automatically", isOn: Binding(
                        get: { lights.autoConnectEnabled },
                        set: { lights.setAutoConnectEnabled($0) }
                    ))
                }
                Section("Color compatibility") {
                    Picker("Frame format", selection: Binding(
                        get: { lights.colorFrameFormat },
                        set: { lights.setColorFrameFormat($0) }
                    )) {
                        ForEach(LEDColorFrameFormat.allCases) { format in
                            Text(format.title).tag(format)
                        }
                    }
                    Picker("RGB channel order", selection: Binding(
                        get: { lights.channelOrder },
                        set: { lights.setChannelOrder($0) }
                    )) {
                        ForEach(LEDChannelOrder.allCases) { order in
                            Text(order.title).tag(order)
                        }
                    }
                    Button {
                        lights.runColorTest()
                    } label: {
                        Label(lights.isColorTestRunning ? "Testing colors…" : "Run RGB test", systemImage: "testtube.2")
                    }
                    .disabled(lights.connectedName == nil || !lights.isOn || lights.isColorTestRunning)
                    Text("If colors are swapped or inaccurate, try another channel order or frame format. The test displays red, green, and blue, then restores your previous color. Supported formats vary by controller firmware.")
                        .font(.system(size:11))
                        .foregroundStyle(.secondary)
                }
                Section("Troubleshooting") {
                    RepairDiagnosticsView()
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                        .listRowBackground(Color.clear)
                }
                ForEach(lights.devices,id:\.identifier) { device in
                    Button { lights.connect(device); showingDevices=false } label: {
                        HStack {
                            Image(systemName:"lightbulb.led").foregroundStyle(accent)
                            VStack(alignment:.leading,spacing:3) {
                                Text(device.name ?? "Bluetooth LED").font(.system(size:14,weight:.semibold))
                                Text(device.identifier.uuidString).font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if device.identifier.uuidString == lights.rememberedDeviceID { Image(systemName:"checkmark.circle.fill").foregroundStyle(.green) }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden).background(Color.black.opacity(0.78))
            .navigationTitle("LED device").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.topBarLeading){Button("Done"){showingDevices=false}}
                ToolbarItem(placement:.topBarTrailing){Button("Scan",systemImage:"arrow.clockwise"){lights.scan()}}
            }
        }.preferredColorScheme(.dark)
    }

    private var signalHistoryGraph: some View {
        GeometryReader { geometry in
            let values = lights.signalHistory
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.045))
                if values.count > 1 {
                    Path { path in
                        for index in values.indices {
                            let x = CGFloat(index) / CGFloat(max(1, values.count - 1)) * geometry.size.width
                            let normalized = CGFloat(max(0, min(1, Double(values[index] + 100) / 50)))
                            let y = geometry.size.height - normalized * (geometry.size.height - 8) - 4
                            if index == values.startIndex { path.move(to: CGPoint(x: x, y: y)) }
                            else { path.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }
                    .stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                } else {
                    Text("Collecting signal samples…")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityLabel("Bluetooth signal history graph")
    }

    private var visibleScenes: [LEDScene] {
        var all = LEDScene.library + diySaved
        if selectedCategory != "All" {
            all = all.filter { $0.category == selectedCategory }
        }
        switch sceneShelf {
        case "Favorites":
            all = all.filter { favoriteSceneIDs.contains($0.id) }
        case "Recently used":
            let lookup = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
            all = recentSceneIDs.compactMap { lookup[$0] }
        default:
            break
        }
        return all
    }

    private func panelGlass()->some View {
        Group {
            if #available(iOS 26.0, *), !reduceTransparency {
                RoundedRectangle(cornerRadius:MorgDesign.cardRadius,style:.continuous).fill(.clear)
                    .glassEffect(.regular,in:.rect(cornerRadius:MorgDesign.cardRadius))
                    .overlay(RoundedRectangle(cornerRadius:MorgDesign.cardRadius,style:.continuous).stroke(MorgDesign.hairline,lineWidth:0.7))
            } else {
                RoundedRectangle(cornerRadius:MorgDesign.cardRadius,style:.continuous).fill(.black.opacity(0.58))
                    .overlay(RoundedRectangle(cornerRadius:MorgDesign.cardRadius,style:.continuous).stroke(.white.opacity(0.18),lineWidth:1))
            }
        }
    }

    private func syncWheel(to color: Color) {
        var selectedHue: CGFloat = 0
        var selectedSaturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        UIColor(color).getHue(&selectedHue, saturation: &selectedSaturation, brightness: &brightness, alpha: &alpha)
        hue = Double(selectedHue)
        wheelSaturation = Double(selectedSaturation)
    }

    private func apply(_ color:Color, persist:Bool = true) {
        // Keep the selected sRGB channels unchanged for the hardware command.
        let rgb=color.rgb
        lights.setColor(red:rgb.x,green:rgb.y,blue:rgb.z,persist:persist)
    }

    private func addRecent(_ color:Color) {
        if !recent.contains(where:{perceptuallyClose($0,color)}) {
            recent.insert(color,at:0); recent=Array(recent.prefix(8)); persistState()
        }
    }

    private func addFavorite(_ color:Color) {
        favorites.removeAll{perceptuallyClose($0,color)}
        favorites.insert(color,at:0); favorites=Array(favorites.prefix(8)); persistState()
    }

    private func uniquePalette(_ input:[Color])->[Color] {
        var result:[Color]=[]
        for color in input where !result.contains(where:{perceptuallyClose($0,color)}) {
            result.append(color)
            if result.count == 8 { break }
        }
        return result
    }

    private func perceptuallyClose(_ a:Color,_ b:Color)->Bool {
        let x=a.oklab,y=b.oklab
        let dl=x.x-y.x,da=x.y-y.y,db=x.z-y.z
        return sqrt(dl*dl+da*da+db*db)<0.075
    }

    private func startScene(_ scene: LEDScene) {
        sceneTask?.cancel()
        guard !scene.colors.isEmpty else { return }
        guard lights.connectedName != nil else {
            lights.status = "Connect your LED before starting a scene"
            return
        }
        lights.setBrightness(sceneBrightness)
        let loopDuration = 10 * pow(180, 1 - max(0, min(1, sceneSpeed)))
        let interval = min(1.0, max(0.18, loopDuration / 180.0))
        sceneTask = Task { @MainActor in
            var elapsed = 0.0
            var frame = 0
            while !Task.isCancelled {
                if scenePaused {
                    do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
                    continue
                }

                let count = scene.colors.count
                let progress = (elapsed / loopDuration).truncatingRemainder(dividingBy: 1)
                let position = progress * Double(count)
                let segment = Int(position) % count
                let phase = position - floor(position)
                let smooth = phase * phase * (3.0 - 2.0 * phase)
                let base = scene.colors[segment]
                let next = scene.colors[(segment + 1) % count]
                let wave = 0.5 - 0.5 * cos(progress * 2.0 * Double.pi)
                let color: Color

                switch scene.motion {
                case "Rainbow":
                    color = Color(hue: progress, saturation: 0.94, brightness: 1.0)
                case "Strobe":
                    let pulse = frame % 8 < 4 ? 1.0 : 0.48
                    color = ColorScience.dim(base, level: pulse)
                case "Candle flicker":
                    let levels: [Double] = [0.78,0.93,0.84,1.0,0.74,0.91,0.82,0.97,0.70,0.89,0.80,0.95]
                    color = ColorScience.dim(base, level: levels[frame % levels.count])
                case "Pulse":
                    color = ColorScience.dim(base, level: 0.22 + 0.78 * wave)
                case "Breathe":
                    color = ColorScience.dim(base, level: 0.10 + 0.90 * wave)
                case "Aurora", "Fade":
                    let blended = ColorScience.mixColor(base, next, t: smooth)
                    let level = count == 1 ? 0.48 + 0.52 * wave : 0.92 + 0.08 * wave
                    color = ColorScience.dim(blended, level: level)
                default:
                    color = ColorScience.mixColor(base, next, t: smooth)
                }

                apply(color, persist: false)
                elapsed += interval
                frame += 1
                do { try await Task.sleep(for: .seconds(interval)) } catch { return }
            }
        }
    }

    private func restartScene() {
        if let scene = selectedScene { startScene(scene) }
    }

    private func stopScene() {
        sceneTask?.cancel()
        sceneTask = nil
        selectedScene = nil
        scenePaused = false
        lights.persistCurrentState()
    }

    private func updateMusicColor() {
        guard audio.isRunning, audio.inputLevel >= 0.20 else { return }
        let level = min(1.0, audio.inputLevel * (0.65 + sensitivity * 3.2))
        let bass = min(1.0, audio.bass * sensitivity * 4.0)
        let mid = min(1.0, audio.mid * sensitivity * 4.0)
        let high = min(1.0, audio.high * sensitivity * 4.0)
        let hue: Double
        switch musicMode {
        case "Energy":
            hue = (0.02 + bass * 0.42 + level * 0.10).truncatingRemainder(dividingBy: 1)
        case "Spectrum":
            hue = (0.56 + mid * 0.30 + high * 0.14).truncatingRemainder(dividingBy: 1)
        case "Rolling":
            hue = (0.72 + bass * 0.18 + mid * 0.10 + level * 0.08).truncatingRemainder(dividingBy: 1)
        default:
            hue = (0.54 + level * 0.12).truncatingRemainder(dividingBy: 1)
        }
        let outputBrightness = min(1.0, 0.08 + level * 0.78 + bass * 0.10 + mid * 0.04)
        applyThrottled(Color(hue: hue, saturation: 0.94, brightness: outputBrightness))
    }

    @State private var lastAudioWrite=0.0
    private func applyThrottled(_ color:Color) {
        let now=Date().timeIntervalSinceReferenceDate
        guard now-lastAudioWrite>=0.12 else { return }
        lastAudioWrite=now; apply(color,persist:false)
    }

    private func handleAutomationURL(_ url:URL) {
        guard url.scheme == "morgsled" else { return }
        switch url.host?.lowercased() {
        case "power":
            if url.path.lowercased() == "/on",!lights.isOn { lights.togglePower() }
            if url.path.lowercased() == "/off",lights.isOn { lights.togglePower() }
        case "brightness":
            if let value=URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems?.first(where:{$0.name=="value"})?.value,let amount=Double(value),(0...100).contains(amount) { lights.setBrightness(amount) }
        case "color":
            if let hex=URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems?.first(where:{$0.name=="hex"})?.value {
                let clean=hex.trimmingCharacters(in:CharacterSet(charactersIn:"#"))
                if clean.count==6,let value=UInt32(clean,radix:16) { lights.setColor(red:Double((value>>16)&255)/255,green:Double((value>>8)&255)/255,blue:Double(value&255)/255) }
            }
        default: break
        }
    }

    /// Approximate black-body white point mapped to RGB for RGB-only strips.
    /// This is a color tint simulation, not a true tunable-white channel.
    private func approximateWhitePoint(kelvin: Double) -> Color {
        let temperature = min(6500.0, max(2000.0, kelvin)) / 100.0
        let red: Double
        let green: Double
        let blue: Double

        if temperature <= 66 {
            red = 255
            green = 99.4708025861 * log(temperature) - 161.1195681661
            blue = temperature <= 19 ? 0 : 138.5177312231 * log(temperature - 10) - 305.0447927307
        } else {
            red = 329.698727446 * pow(temperature - 60, -0.1332047592)
            green = 288.1221695283 * pow(temperature - 60, -0.0755148492)
            blue = 255
        }

        return Color(red: min(1, max(0, red / 255)),
                     green: min(1, max(0, green / 255)),
                     blue: min(1, max(0, blue / 255)))
    }

    private func restoreState() {
        if let data=UserDefaults.standard.data(forKey:"morgs.recent"),let values=try? JSONDecoder().decode([RGBA].self,from:data) { recent=values.map{$0.color} }
        if let data=UserDefaults.standard.data(forKey:"morgs.favorites"),let values=try? JSONDecoder().decode([RGBA].self,from:data) { favorites=values.map{$0.color} }
        if let data=UserDefaults.standard.data(forKey:"morgs.diy-scenes"),let values=try? JSONDecoder().decode([SavedScene].self,from:data) {
            diySaved=values.map{LEDScene(id:$0.id,name:$0.name,category:"DIY",symbol:"wand.and.stars",colors:$0.colors.map{$0.color},motion:$0.motion,speed:$0.speed)}
        }
    }

    private func persistScenes() {
        let values=diySaved.map{SavedScene(id:$0.id,name:$0.name,colors:$0.colors.map{RGBA(color:$0)},motion:$0.motion,speed:$0.speed)}
        UserDefaults.standard.set(try? JSONEncoder().encode(values),forKey:"morgs.diy-scenes")
    }

    private func persistState() {
        UserDefaults.standard.set(try? JSONEncoder().encode(recent.map{RGBA(color:$0)}),forKey:"morgs.recent")
        UserDefaults.standard.set(try? JSONEncoder().encode(favorites.map{RGBA(color:$0)}),forKey:"morgs.favorites")
    }
}

private struct SavedScene: Codable {
    var id: String
    var name: String
    var colors: [RGBA]
    var motion: String
    var speed: Double
}

private struct ColorWheel: View {
    @Binding var hue: Double
    @Binding var saturation: Double
    let selection: (Color) -> Void
    let onCommit: () -> Void
    @State private var pinchBaseSaturation = 1.0
    @State private var pinchInProgress = false

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                Circle()
                    .fill(AngularGradient(
                        colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red],
                        center: .center
                    ))
                Circle()
                    .fill(RadialGradient(colors: [.white, .white.opacity(0)], center: .center, startRadius: 0, endRadius: side * 0.5))
                Circle().stroke(.white.opacity(0.75), lineWidth: 1)
                Circle()
                    .fill(Color(hue: hue, saturation: saturation, brightness: 1))
                    .frame(width: 13, height: 13)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.35), radius: 3)
                    .offset(
                        x: cos(hue * 2 * .pi - .pi / 2) * saturation * side * 0.40,
                        y: sin(hue * 2 * .pi - .pi / 2) * saturation * side * 0.40
                    )
                Button(action: onCommit) {
                    Circle()
                        .fill(Color(hue: hue, saturation: saturation, brightness: 1))
                        .frame(width: 42, height: 42)
                        .overlay(Circle().stroke(.white.opacity(0.95), lineWidth: 3))
                        .overlay(Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white).shadow(color: .black.opacity(0.6), radius: 3))
                        .shadow(color: Color(hue: hue, saturation: saturation, brightness: 1).opacity(0.65), radius: 12)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Confirm selected color")
            }
            .frame(width: side, height: side)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let center = CGPoint(x: side / 2, y: side / 2)
                    let dx = value.location.x - center.x
                    let dy = value.location.y - center.y
                    let distance = min(1, hypot(dx, dy) / (side * 0.40))
                    var angle = atan2(dy, dx) + .pi / 2
                    if angle < 0 { angle += 2 * .pi }
                    hue = angle / (2 * .pi)
                    saturation = distance
                    selection(Color(hue: hue, saturation: saturation, brightness: 1))
                }
                .onEnded { _ in onCommit() })
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { scale in
                        if !pinchInProgress {
                            pinchBaseSaturation = saturation
                            pinchInProgress = true
                        }
                        saturation = min(1, max(0, pinchBaseSaturation * Double(scale)))
                        selection(Color(hue: hue, saturation: saturation, brightness: 1))
                    }
                    .onEnded { _ in
                        pinchInProgress = false
                        onCommit()
                    }
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Hue and saturation")
        .accessibilityValue("Hue \(Int(hue * 360)) degrees, saturation \(Int(saturation * 100)) percent")
        .accessibilityHint("Drag to change hue and saturation. Pinch with two fingers to adjust saturation, or tap the center to confirm the selected color.")
    }
}

private struct TemperatureTrack:View {
    @Binding var value:Double
    let thumb:Color
    var body:some View {
        GeometryReader { geo in
            ZStack(alignment:.leading) {
                Capsule().fill(LinearGradient(colors:[Color(red:1,green:0.38,blue:0.12),.orange,.white,.cyan,Color(red:0.15,green:0.42,blue:1)],startPoint:.leading,endPoint:.trailing)).frame(height:8)
                Circle().fill(thumb).frame(width:22,height:22).overlay(Circle().stroke(.white.opacity(0.85),lineWidth:2)).shadow(color:thumb.opacity(0.6),radius:8)
                    .offset(x:max(0,min(geo.size.width-22,(value-2000)/4500*(geo.size.width-22))))
            }
            .frame(maxHeight:.infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance:0).onChanged{valuePoint in value=2000+max(0,min(1,(valuePoint.location.x-11)/(geo.size.width-22)))*4500})
        }.frame(height:28)
    }
}

private struct MinimizeTabBar:ViewModifier {
    @ViewBuilder func body(content:Content)->some View {
        if #available(iOS 26.0, *) { content.tabBarMinimizeBehavior(.onScrollDown) }
        else { content }
    }
}

private struct RGBA:Codable {
    var red:Double;var green:Double;var blue:Double
    init(color:Color) { let rgb=color.rgb;red=rgb.x;green=rgb.y;blue=rgb.z }
    var color:Color { Color(red:red,green:green,blue:blue) }
}

private extension Color {
    var rgb: SIMD3<Double> {
        let resolved = UIColor(self).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let cgColor = resolved.cgColor.converted(to: colorSpace, intent: .defaultIntent, options: nil) ?? resolved.cgColor
        let components = cgColor.components ?? []
        if components.count >= 3 {
            return SIMD3<Double>(Double(components[0]), Double(components[1]), Double(components[2]))
        }
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return SIMD3<Double>(Double(red), Double(green), Double(blue))
    }

    var oklab: SIMD3<Double> {
        let value = rgb
        let r = value.x
        let g = value.y
        let b = value.z
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let smallS = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        let lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * smallS
        let axisA = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * smallS
        let axisB = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * smallS
        return SIMD3<Double>(lightness, axisA, axisB)
    }

    func saturated(_ factor: Double) -> Color {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        UIColor(self).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return Color(hue: Double(hue), saturation: min(1, Double(saturation) * factor), brightness: Double(brightness))
    }
}

private extension View {
    func glassControl(id: String, namespace: Namespace.ID, tint: Color) -> some View {
        modifier(GlassControlModifier(id: id, namespace: namespace, tint: tint))
    }

    func controlGlass(id: String, tint: Color = .white.opacity(0.08)) -> some View {
        modifier(SimpleControlGlassModifier(tint: tint))
    }

    func panelGlass()->some View {
        modifier(PanelGlassModifier())
    }
}

private struct SimpleControlGlassModifier: ViewModifier {
    let tint: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            content
                .background(tint.opacity(0.14), in: Capsule())
                .glassEffect(.regular.tint(tint).interactive(), in: Capsule())
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
        }
    }
}

private struct GlassControlModifier:ViewModifier {
    let id:String
    let namespace:Namespace.ID
    let tint:Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content:Content)->some View {
        if #available(iOS 26.0,*),!reduceTransparency {
            content.padding(.horizontal,12).padding(.vertical,8)
                .background(tint.opacity(0.12),in:Capsule())
                .glassEffect(.regular.tint(tint).interactive(),in:Capsule())
                .glassEffectID(id,in:namespace)
        } else {
            content.padding(.horizontal,12).padding(.vertical,8)
                .background(.black.opacity(0.6),in:Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.2),lineWidth:1))
        }
    }
}

private struct PanelGlassModifier:ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content:Content)->some View {
        if #available(iOS 26.0,*),!reduceTransparency {
            content.background(.clear,in:RoundedRectangle(cornerRadius:24,style:.continuous))
                .glassEffect(.regular,in:.rect(cornerRadius:24))
                .overlay(RoundedRectangle(cornerRadius:24,style:.continuous).stroke(.white.opacity(0.12),lineWidth:0.7))
        } else {
            content.background(.black.opacity(0.62),in:RoundedRectangle(cornerRadius:24,style:.continuous))
                .overlay(RoundedRectangle(cornerRadius:24,style:.continuous).stroke(.white.opacity(0.2),lineWidth:1))
        }
    }
}
