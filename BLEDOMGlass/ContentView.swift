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
    @State private var temperature = 4200.0
    @State private var sensitivity = 0.65
    @State private var musicMode = "Rhythm"
    @State private var selectedCategory = "All"
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
                timersPage.tabItem { Label("Timers",systemImage:"timer") }.tag(3)
            }
            .tint(accent)
            .modifier(MinimizeTabBar())
        }
        .preferredColorScheme(.dark)
        .animation(reduceMotion ? nil : .spring(response:0.42,dampingFraction:0.82),value:tab)
        .sheet(isPresented:$showingDevices) { deviceSheet }
        .sheet(isPresented:$showDIY) { diySheet.presentationDetents([.large]) }
        .sheet(isPresented:$showScenePlayer) { scenePlayerSheet.presentationDetents([.medium]) }
        .sheet(isPresented:$showingInfo) { infoSheet.presentationDetents([.medium,.large]) }
        .onAppear { restoreState() }
        .onOpenURL { handleAutomationURL($0) }
        .onChange(of:lights.currentColor) { _, color in
            addRecent(color)
        }
        .onChange(of:temperature) { _, kelvin in
            let t=(kelvin-2000)/4500
            apply(Color(red:1.0-t*0.32,green:0.52+t*0.46,blue:0.58+t*0.42))
        }
        .onChange(of:sceneSpeed) { _, value in if selectedScene != nil { restartScene() } }
        .onChange(of:sceneBrightness) { _, value in lights.setBrightness(value) }
    }

    private var driftingBackground: some View {
        TimelineView(.animation(minimumInterval:reduceMotion ? 1 : 0.08,paused:reduceMotion)) { timeline in
            let t=timeline.date.timeIntervalSinceReferenceDate
            let c=lights.isOn ? accent : Color(red:0.025,green:0.03,blue:0.055)
            MeshGradient(width:3,height:3,points:[
                .init(0,0),.init(0.5,0),.init(1,0),
                .init(0,0.5),.init(Float(0.5+0.11*sin(t*0.10)),Float(0.5+0.10*cos(t*0.09))),.init(1,0.5),
                .init(0,1),.init(0.5,1),.init(1,1)
            ],colors:[
                Color(red:0.012,green:0.016,blue:0.035),c.opacity(0.26),Color(red:0.025,green:0.016,blue:0.05),
                c.opacity(0.16),Color(red:0.018,green:0.025,blue:0.052),Color(red:0.045,green:0.018,blue:0.065),
                Color(red:0.018,green:0.025,blue:0.05),c.opacity(0.20),Color(red:0.012,green:0.018,blue:0.04)
            ])
        }.ignoresSafeArea()
    }

    private func screen<Content:View>(_ title:String,@ViewBuilder content:()->Content)->some View {
        ScrollView(showsIndicators:false) {
            VStack(alignment:.leading,spacing:16) {
                HStack(alignment:.center) {
                    Text(title).font(.system(size:30,weight:.bold,design:.rounded)).tracking(-0.8)
                    Spacer(minLength:8)
                    statusPill
                }.padding(.top,8)
                content()
            }
            .padding(.horizontal,20)
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
            HStack(spacing:8) {
                Circle().fill(lights.connectedName == nil ? (lights.status.localizedCaseInsensitiveContains("connect") ? .orange : .gray) : .green).frame(width:7,height:7)
                Text(lights.connectedName ?? (lights.status.localizedCaseInsensitiveContains("connect") ? "Connecting" : "Not connected"))
                    .font(.system(size:12,weight:.semibold,design:.rounded)).lineLimit(1)
                Image(systemName:"chevron.down").font(.system(size:9,weight:.bold)).opacity(0.65)
            }
            .padding(.horizontal,12).padding(.vertical,9)
            .controlGlass(id:"device",tint:lights.connectedName == nil ? .white.opacity(0.05) : .green.opacity(0.14))
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
        GeometryReader { geo in
            let side=min(geo.size.width,340.0)
            ZStack {
                Circle().stroke(.white.opacity(0.08),style:StrokeStyle(lineWidth:28,lineCap:.round)).padding(10)
                Circle().trim(from:0,to:1).stroke(AngularGradient(colors:[.red,.orange,.yellow,.green,.cyan,.blue,.purple,.pink,.red],center:.center),style:StrokeStyle(lineWidth:28,lineCap:.round))
                    .rotationEffect(.degrees(-90)).padding(10)
                    Circle().stroke(.white.opacity(0.14),lineWidth:1).padding(34)
                Circle().fill(lights.currentColor.gradient).frame(width:side*0.38,height:side*0.38)
                    .overlay(Circle().fill(.white.opacity(0.18)).blur(radius:12).padding(14))
                    .shadow(color:lights.isOn ? accent.opacity(bloom ? 0.9 : 0.48) : .clear,radius:bloom ? 38 : 22)
                    .scaleEffect(bloom ? 1.08 : 1)
                    .onTapGesture {
                        withAnimation(.spring(response:0.34,dampingFraction:0.58)) { bloom.toggle(); lights.togglePower() }
                        UIImpactFeedbackGenerator(style:.medium).impactOccurred()
                    }
                    .accessibilityLabel(lights.isOn ? "Turn lights off" : "Turn lights on")
                    .accessibilityAddTraits(.isButton)
                Circle().fill(.white).frame(width:18,height:18).overlay(Circle().stroke(accent,lineWidth:4))
                    .shadow(color:.white.opacity(0.75),radius:9)
                    .offset(x:CGFloat(cos(hue*2*Double.pi))*(side*0.5-14),y:CGFloat(sin(hue*2*Double.pi))*(side*0.5-14))
                    .allowsHitTesting(false)
                Circle().stroke(.clear,lineWidth:0).contentShape(Circle())
                    .gesture(DragGesture(minimumDistance:0).onChanged { value in
                        let center=CGPoint(x:side/2,y:side/2)
                        let dx=value.location.x-center.x,dy=value.location.y-center.y
                        hue=(atan2(dy,dx)/(2*Double.pi)+1).truncatingRemainder(dividingBy:1)
                        apply(Color(hue:hue,saturation:0.94,brightness:1))
                        UISelectionFeedbackGenerator().selectionChanged()
                    })
                VStack(spacing:3) {
                    Text(lights.isOn ? "ON" : "OFF").font(.system(size:12,weight:.bold,design:.rounded)).tracking(2)
                    Text("TAP TO POWER").font(.system(size:9,weight:.medium,design:.rounded)).tracking(1.2).foregroundStyle(.white.opacity(0.56))
                }.allowsHitTesting(false)
            }
            .frame(width:side,height:side)
            .frame(maxWidth:.infinity,maxHeight:.infinity)
        }
        .frame(height:min(max(UIScreen.main.bounds.width-40,260),340))
        .overlay(alignment:.bottom) {
            Button {
                UIPasteboard.general.string="#\(lights.rgbHex)"
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } label: {
                HStack(spacing:7) { RoundedRectangle(cornerRadius:3).fill(lights.currentColor).frame(width:11,height:11); Text("#\(lights.rgbHex)").font(.system(size:12,weight:.semibold,design:.rounded)).monospacedDigit(); Image(systemName:"doc.on.doc").font(.system(size:10)) }
                    .padding(.horizontal,12).padding(.vertical,7).controlGlass(id:"hex-chip")
            }.buttonStyle(.plain).offset(y:14)
        }
    }

    private var controlPanel: some View {
        VStack(spacing:16) {
            HStack(spacing:12) {
                Image(systemName:"sun.min").font(.system(size:14)).foregroundStyle(.white.opacity(0.65))
                Slider(value:Binding(get:{lights.brightness},set:{lights.setBrightness($0)}),in:1...100)
                    .tint(accent)
                Image(systemName:"sun.max.fill").font(.system(size:14)).foregroundStyle(.white.opacity(0.85))
                Text("\(Int(lights.brightness))%").font(.system(size:13,weight:.bold,design:.rounded)).monospacedDigit().frame(width:38,alignment:.trailing)
            }
            Rectangle().fill(.white.opacity(0.12)).frame(height:1)
            VStack(spacing:8) {
                HStack { Text("Temperature").font(.system(size:14,weight:.semibold,design:.rounded)); Spacer(); Text("\(Int(temperature))K").font(.system(size:12,weight:.semibold,design:.rounded)).monospacedDigit().foregroundStyle(.white.opacity(0.7)) }
                TemperatureTrack(value:$temperature,thumb:accent)
                HStack { Text("Warm").foregroundStyle(.orange); Spacer(); Text("Cool").foregroundStyle(.cyan) }.font(.system(size:10,weight:.medium,design:.rounded))
            }
        }
        .padding(17)
        .panelGlass()
    }

    private var colorsSection: some View {
        let palette=uniquePalette(Array(favorites+recent))
        return Group {
            if !palette.isEmpty || !favorites.isEmpty {
                VStack(alignment:.leading,spacing:11) {
                    HStack {
                        Text("Colors").font(.system(size:19,weight:.bold,design:.rounded))
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
                                    .onTapGesture { apply(color) }
                            }
                        }.padding(.vertical,3)
                    }
                }
            }
        }
    }

    private var scenes: some View {
        screen("Scenes") {
            ScrollView(.horizontal,showsIndicators:false) {
                HStack(spacing:8) {
                    ForEach(categories,id:\.self) { category in
                        Button(category) { selectedCategory=category }
                            .font(.system(size:12,weight:.semibold,design:.rounded))
                            .padding(.horizontal,13).padding(.vertical,8)
                            .controlGlass(id:"category-\(category)",tint:selectedCategory == category ? accent.opacity(0.32) : .clear)
                    }
                }
            }
            LazyVGrid(columns:[GridItem(.flexible(),spacing:12),GridItem(.flexible(),spacing:12)],spacing:12) {
                ForEach(visibleScenes) { scene in
                    sceneCard(scene)
                }
            }
            Button { showDIY=true } label: {
                Label("Create a scene",systemImage:"plus").font(.system(size:14,weight:.semibold,design:.rounded))
                    .frame(maxWidth:.infinity).padding(.vertical,14).controlGlass(id:"create-scene",tint:accent.opacity(0.15))
            }.buttonStyle(.plain)
        }
    }

    private func sceneCard(_ scene:LEDScene)->some View {
        let active=selectedScene?.id == scene.id
        return Button {
            selectedScene=scene
            sceneSpeed=scene.speed
            startScene(scene)
            UIImpactFeedbackGenerator(style:.light).impactOccurred()
        } label: {
            ZStack(alignment:.topLeading) {
                TimelineView(.animation(minimumInterval:reduceMotion ? 1 : 0.08,paused:reduceMotion)) { timeline in
                    let phase=timeline.date.timeIntervalSinceReferenceDate*(0.18+scene.speed*0.28)
                    let colors=scene.colors.isEmpty ? [.black] : scene.colors
                    let rotated=colors.enumerated().sorted{($0.offset+Int(phase*10))%colors.count < ($1.offset+Int(phase*10))%colors.count}.map{$0.element}
                    LinearGradient(colors:rotated+Array(rotated.reversed()),startPoint:.topLeading,endPoint:.bottomTrailing)
                        .overlay(alignment:.bottomTrailing) {
                            Circle().fill(.white.opacity(0.22)).frame(width:70,height:70).blur(radius:24).offset(x:15,y:20)
                        }
                }
                Image(systemName:scene.symbol).font(.system(size:15,weight:.semibold)).foregroundStyle(.white).padding(11)
                    .shadow(color:.black.opacity(0.45),radius:5)
                VStack { Spacer(); HStack {
                    Text(scene.name).font(.system(size:13,weight:.semibold,design:.rounded)).lineLimit(1)
                    Spacer(minLength:2)
                    if active { Image(systemName:"waveform").font(.system(size:11,weight:.bold)) }
                }.padding(.horizontal,11).padding(.vertical,9).background(.ultraThinMaterial,in:Capsule()).padding(8) }
            }
            .aspectRatio(1.3,contentMode:.fit)
            .clipShape(RoundedRectangle(cornerRadius:20,style:.continuous))
            .overlay(RoundedRectangle(cornerRadius:20,style:.continuous).stroke(active ? accent : .white.opacity(0.13),lineWidth:active ? 2.5 : 1))
            .shadow(color:active ? accent.opacity(0.45) : .clear,radius:14)
        }.buttonStyle(.plain)
    }

    private var sceneDock: some View {
        HStack(spacing:12) {
            Image(systemName:selectedScene?.symbol ?? "sparkles").font(.system(size:16,weight:.semibold)).foregroundStyle(accent)
            VStack(alignment:.leading,spacing:2) {
                Text(selectedScene?.name ?? "Scene").font(.system(size:13,weight:.semibold,design:.rounded)).lineLimit(1)
                Text("WHOLE STRIP").font(.system(size:9,weight:.medium,design:.rounded)).tracking(1).foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            Button { showScenePlayer=true } label: { Image(systemName:"slider.horizontal.3").frame(width:34,height:34).controlGlass(id:"scene-settings") }.buttonStyle(.plain)
            Button { stopScene() } label: { Image(systemName:"stop.fill").frame(width:34,height:34).controlGlass(id:"scene-stop") }.buttonStyle(.plain)
        }.padding(10).panelGlass()
    }

    private var scenePlayerSheet: some View {
        VStack(alignment:.leading,spacing:20) {
            HStack { Text(selectedScene?.name ?? "Scene").font(.system(size:24,weight:.bold,design:.rounded)); Spacer(); Button("Done"){showScenePlayer=false} }
            HStack { Text("Speed"); Spacer(); Text("\(Int(sceneSpeed*100))%").monospacedDigit() }
            Slider(value:$sceneSpeed,in:0.05...1).tint(accent)
            HStack { Text("Brightness"); Spacer(); Text("\(Int(sceneBrightness))%").monospacedDigit() }
            Slider(value:$sceneBrightness,in:1...100).tint(accent)
            Button("Stop scene",systemImage:"stop.fill",role:.destructive) { stopScene(); showScenePlayer=false }
                .buttonStyle(.glass)
        }.padding(24).presentationBackground(.ultraThinMaterial)
    }

    private var music: some View {
        screen("Music") {
            VStack(spacing:20) {
                visualizer
                Button {
                    if audio.isRunning { audio.stop(); stopScene() }
                    else { audio.start() }
                } label: {
                    Label(audio.isRunning ? "Stop listening" : "Start listening",systemImage:audio.isRunning ? "stop.fill" : "mic.fill")
                        .font(.system(size:16,weight:.bold,design:.rounded))
                        .frame(maxWidth:.infinity).padding(.vertical,17)
                        .controlGlass(id:"music-primary",tint:accent.opacity(0.42))
                }.buttonStyle(.plain)
                VStack(alignment:.leading,spacing:14) {
                    Text("Mode").font(.system(size:14,weight:.semibold,design:.rounded))
                    GlassEffectContainer(spacing:4) {
                        HStack(spacing:4) {
                            ForEach(["Rhythm","Energic","Spectrum","Rolling"],id:\.self) { mode in
                                Button(mode) { musicMode=mode; UISelectionFeedbackGenerator().selectionChanged() }
                                    .font(.system(size:11,weight:.semibold,design:.rounded))
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
                        .font(.system(size:13,weight:.medium,design:.rounded))
                    Slider(value:$sensitivity,in:0.1...1).tint(accent)
                }.padding(17).panelGlass()
                Text(audio.message).font(.system(size:12,weight:.medium,design:.rounded)).foregroundStyle(.white.opacity(0.58)).frame(maxWidth:.infinity,alignment:.leading)
            }
        }
        .onChange(of:audio.bass) { _, _ in updateMusicColor() }
        .onChange(of:audio.mid) { _, _ in updateMusicColor() }
        .onChange(of:audio.high) { _, _ in updateMusicColor() }
        .onDisappear { audio.stop() }
    }

    private var visualizer: some View {
        TimelineView(.animation(minimumInterval:0.05,paused:reduceMotion && !audio.isRunning)) { timeline in
            let phase=timeline.date.timeIntervalSinceReferenceDate
            let levels=(0..<32).map { i -> CGFloat in
                let idle=0.12+0.07*sin(phase*1.7+Double(i)*0.55)
                let active=audio.isRunning ? 0.08+audio.bass*CGFloat(0.75)+audio.mid*CGFloat(0.55)*CGFloat(abs(sin(Double(i)*0.4)))+audio.high*CGFloat(0.4)*CGFloat(abs(cos(Double(i)*0.8))) : idle
                return max(0.08,min(1,active))
            }
            HStack(alignment:.center,spacing:4) {
                ForEach(0..<32,id:\.self) { i in
                    Capsule().fill(LinearGradient(colors:[accent.opacity(0.55),accent,.white.opacity(0.88)],startPoint:.bottom,endPoint:.top))
                        .frame(maxWidth:.infinity).frame(height:max(8,150*levels[i]))
                        .shadow(color:accent.opacity(0.35),radius:4)
                }
            }.frame(height:156).padding(.horizontal,5)
        }
        .padding(18).frame(maxWidth:.infinity)
        .panelGlass()
    }

    private var timersPage: some View {
        screen("Timers") {
            VStack(spacing:14) {
                VStack(alignment:.leading,spacing:16) {
                    HStack { Text("Next routine").font(.system(size:14,weight:.semibold,design:.rounded)); Spacer(); Text(timers.enabled ? "ACTIVE" : "READY").font(.system(size:10,weight:.bold,design:.rounded)).tracking(1).foregroundStyle(timers.enabled ? accent : .white.opacity(0.5)) }
                    DatePicker("Time",selection:$timerDate,displayedComponents:.hourAndMinute)
                        .datePickerStyle(.compact).font(.system(size:17,weight:.semibold,design:.rounded))
                    HStack(spacing:10) {
                        timerTile("Sunrise","sunrise.fill",.orange) {
                            timers.scheduleWake(at:timerDate,brightness:{lights.setBrightness($0)},powerOn:{if !lights.isOn {lights.togglePower()}})
                        }
                        timerTile("Sunset","sunset.fill",.purple) {
                            timers.sleepFade(brightness:{lights.setBrightness($0)},powerOff:{if lights.isOn {lights.togglePower()}})
                        }
                        timerTile("Sleep","moon.zzz.fill",.indigo) {
                            timers.sleepFade(brightness:{lights.setBrightness($0)},powerOff:{if lights.isOn {lights.togglePower()}})
                        }
                    }
                    HStack { Text("Fade duration"); Spacer(); Text("\(Int(timers.sleepMinutes)) min").monospacedDigit() }
                    Slider(value:$timers.sleepMinutes,in:5...180,step:5).tint(accent)
                    HStack { Text("Wake ramp"); Spacer(); Text("\(Int(timers.wakeMinutes)) min").monospacedDigit() }
                    Slider(value:$timers.wakeMinutes,in:5...60,step:1).tint(accent)
                    if timers.enabled { Button("Cancel active timer",role:.destructive) { timers.cancel() }.buttonStyle(.glass) }
                    Text(timers.message).font(.system(size:11,weight:.medium,design:.rounded)).foregroundStyle(.white.opacity(0.55))
                }.padding(18).panelGlass()
            }
        }
    }

    private func timerTile(_ title:String,_ symbol:String,_ tint:Color,_ action:@escaping()->Void)->some View {
        Button {
            guard lights.connectedName != nil else { showingDevices=true; return }
            action()
            UIImpactFeedbackGenerator(style:.medium).impactOccurred()
        } label: {
            VStack(spacing:8) {
                Image(systemName:symbol).font(.system(size:19,weight:.semibold))
                Text(title).font(.system(size:11,weight:.semibold,design:.rounded))
            }.frame(maxWidth:.infinity).padding(.vertical,13)
                .controlGlass(id:"timer-\(title)",tint:tint.opacity(0.28))
        }.buttonStyle(.plain)
    }

    private var infoSheet: some View {
        NavigationStack {
            List {
                Section("Your LED strip") {
                    Text("This controller sends whole-strip RGB and brightness commands. It does not address independent segments or pixels.")
                    Text("Temperature is an RGB approximation. The hardware protocol exposed by this strip does not provide a separate white-temperature channel.")
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
                Section {
                    HStack { Circle().fill(lights.isPoweredOn ? .green : .orange).frame(width:8,height:8); Text(lights.status).font(.system(size:13,weight:.medium,design:.rounded)) }
                }
                ForEach(lights.devices,id:\.identifier) { device in
                    Button { lights.connect(device); showingDevices=false } label: {
                        HStack {
                            Image(systemName:"lightbulb.led").foregroundStyle(accent)
                            VStack(alignment:.leading,spacing:3) {
                                Text(device.name ?? "Bluetooth LED").font(.system(size:14,weight:.semibold,design:.rounded))
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

    private var scenePlayerSheet: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack { Text(selectedScene?.name ?? "Scene").font(.system(size:24,weight:.bold,design:.rounded)); Spacer(); Button("Done"){showScenePlayer=false} }
            HStack { Text("Speed"); Spacer(); Text("\(Int(sceneSpeed*100))%").monospacedDigit() }
            Slider(value:$sceneSpeed,in:0.05...1).tint(accent)
            HStack { Text("Brightness"); Spacer(); Text("\(Int(sceneBrightness))%").monospacedDigit() }
            Slider(value:$sceneBrightness,in:1...100).tint(accent)
            Button("Stop scene",systemImage:"stop.fill",role:.destructive){stopScene();showScenePlayer=false}.buttonStyle(.glass)
        }.padding(24).presentationBackground(.ultraThinMaterial)
    }

    private var visibleScenes:[LEDScene] {
        let all=LEDScene.library+diySaved
        return selectedCategory == "All" ? all : all.filter{$0.category == selectedCategory}
    }

    private func controlGlass(id:String,tint:Color = .clear)->some View {
        Group {
            if #available(iOS 26.0, *), !reduceTransparency {
                Capsule().fill(.clear).overlay(Capsule().fill(tint.opacity(0.18))).glassEffect(.regular.tint(tint).interactive()).glassEffectID(id,in:glassSpace)
            } else {
                Capsule().fill(Color.white.opacity(0.12)).overlay(Capsule().stroke(.white.opacity(0.18),lineWidth:1))
            }
        }
    }

    private func panelGlass()->some View {
        Group {
            if #available(iOS 26.0, *), !reduceTransparency {
                RoundedRectangle(cornerRadius:24,style:.continuous).fill(.clear)
                    .glassEffect(.regular,in:.rect(cornerRadius:24))
                    .overlay(RoundedRectangle(cornerRadius:24,style:.continuous).stroke(.white.opacity(0.12),lineWidth:0.7))
            } else {
                RoundedRectangle(cornerRadius:24,style:.continuous).fill(.black.opacity(0.58))
                    .overlay(RoundedRectangle(cornerRadius:24,style:.continuous).stroke(.white.opacity(0.18),lineWidth:1))
            }
        }
    }

    private func apply(_ color:Color) {
        let rgb=color.rgb
        lights.setColor(red:rgb.x,green:rgb.y,blue:rgb.z)
        addRecent(color)
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

    private func startScene(_ scene:LEDScene) {
        sceneTask?.cancel()
        guard !scene.colors.isEmpty else { return }
        lights.setBrightness(sceneBrightness)
        let speed=scene.category == "DIY" ? scene.speed : sceneSpeed
        let interval=max(0.14,2.0-speed*1.75)
        sceneTask=Task { @MainActor in
            var index=0
            while !Task.isCancelled {
                let base=scene.colors[index%scene.colors.count]
                let next=scene.colors[(index+1)%scene.colors.count]
                let color:Color
                switch scene.motion {
                case "Rainbow": color=Color(hue:Double(index%24)/24,saturation:0.95,brightness:1)
                case "Strobe": color=index%2 == 0 ? base : .black
                case "Candle flicker": color=index%4 == 0 ? base.opacity(0.55) : base
                case "Pulse","Breathe": color=base.opacity(index%2 == 0 ? 1 : 0.42)
                case "Aurora": color=ColorScience.mixColor(base,next,t:0.5)
                default: color=ColorScience.mixColor(base,next,t:0.5)
                }
                apply(color)
                index += 1
                do { try await Task.sleep(for:.seconds(scene.motion == "Strobe" ? max(0.12,interval/3) : interval)) } catch { return }
            }
        }
    }

    private func restartScene() { if let scene=selectedScene { startScene(scene) } }
    private func stopScene() { sceneTask?.cancel(); sceneTask=nil; selectedScene=nil }

    private func updateMusicColor() {
        guard audio.isRunning,lights.connectedName != nil else { return }
        let bass=min(1,audio.bass*sensitivity*3.0)
        let mid=min(1,audio.mid*sensitivity*3.0)
        let high=min(1,audio.high*sensitivity*3.0)
        let h:Double
        switch musicMode {
        case "Energic": h=(0.02+bass*0.42).truncatingRemainder(dividingBy:1)
        case "Spectrum": h=(0.56+mid*0.34+high*0.1).truncatingRemainder(dividingBy:1)
        case "Rolling": h=(0.72+bass*0.18+mid*0.1).truncatingRemainder(dividingBy:1)
        default: h=0.56
        }
        let brightness=0.18+bass*0.58+mid*0.18+high*0.06
        applyThrottled(Color(hue:h,saturation:0.94,brightness:brightness))
    }

    private var lastAudioWrite=0.0
    private func applyThrottled(_ color:Color) {
        let now=Date().timeIntervalSinceReferenceDate
        guard now-lastAudioWrite>=0.04 else { return }
        lastAudioWrite=now; apply(color)
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
    var rgb:SIMD3<Double> {
        let c=UIColor(self).resolvedColor(with:UITraitCollection(userInterfaceStyle:.dark))
        var r:CGFloat=0,g:CGFloat=0,b:CGFloat=0,a:CGFloat=0
        c.getRed(&r,green:&g,blue:&b,alpha:&a)
        return SIMD3(Double(r),Double(g),Double(b))
    }
    var oklab:SIMD3<Double> {
        let v=rgb
        let l=pow(0.4122214708*v.x+0.5363325363*v.y+0.0514459929*v.z,1.0/3)
        let m=pow(0.2119034982*v.x+0.6806995451*v.y+0.1073969566*v.z,1.0/3)
        let s=pow(0.0883024619*v.x+0.2817188376*v.y+0.6299787005*v.z,1.0/3)
        return SIMD3(0.2104542553*l+0.7936177850*m-0.0040720468*s,1.9779984951*l-2.4285922050*m+0.4505937099* s,0.0259040371*l+0.7827717662*m-0.8086757660*s)
    }
    func saturated(_ factor:Double)->Color {
        let c=UIColor(self);var h:CGFloat=0,s:CGFloat=0,b:CGFloat=0,a:CGFloat=0
        c.getHue(&h,saturation:&s,brightness:&b,alpha:&a)
        return Color(hue:Double(h),saturation:min(1,Double(s)*factor),brightness:Double(b))
    }
}

private extension View {
    func panelGlass()->some View {
        modifier(PanelGlassModifier())
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
