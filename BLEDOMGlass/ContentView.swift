import SwiftUI
import CoreBluetooth
import UIKit

struct ContentView: View {
    @EnvironmentObject private var lights: BLEController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var typeSize
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
    @State private var selectedTimer = "Sleep fade"

    private let categories = ["All","Ambient","Nature","Party","Gaming","Cozy","Sleep"]
    private let modes = ["Fade","Pulse","Breathe","Strobe","Rainbow","Candle flicker","Aurora"]

    var body: some View {
        ZStack {
            driftingBackground
            TabView(selection: $tab) {
                home.tabItem { Label("Home", systemImage:"house.fill") }.tag(0)
                scenes.tabItem { Label("Scenes", systemImage:"sparkles") }.tag(1)
                music.tabItem { Label("Music", systemImage:"waveform") }.tag(2)
                timersPage.tabItem { Label("Timers", systemImage:"timer") }.tag(3)
            }
            .tint(.white)
        }
        .preferredColorScheme(.dark)
        .animation(reduceMotion ? nil : .spring(response:0.42,dampingFraction:0.82), value:tab)
        .sheet(isPresented:$showingDevices) { deviceSheet }
        .sheet(isPresented:$showDIY) { diySheet.presentationDetents([.large]) }
        .onAppear { restoreState() }
        .onChange(of: temperature) { _, kelvin in
            let t = (kelvin - 2000) / 4500
            let warm = 1.0 - t * 0.32
            let cool = 0.58 + t * 0.42
            lights.setColor(red: min(1,warm), green: min(1,0.52 + t * 0.46), blue: min(1,cool))
        }
        .onChange(of: lights.currentColor) { _, color in
            recent.insert(color, at:0); recent = Array(recent.prefix(8))
        }
    }

    private var driftingBackground: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 0.08, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let c = lights.isOn ? lights.currentColor : Color(red:0.035,green:0.045,blue:0.08)
            MeshGradient(width:3,height:3,points:[
                .init(0,0),.init(0.5,0),.init(1,0),
                .init(0,0.5),.init(Float(0.5+0.12*sin(t*0.12)),Float(0.5+0.1*cos(t*0.1))),.init(1,0.5),
                .init(0,1),.init(0.5,1),.init(1,1)
            ],colors:[
                Color(red:0.018,green:0.024,blue:0.05),c.opacity(0.28),Color(red:0.025,green:0.02,blue:0.07),
                c.opacity(0.18),Color(red:0.035,green:0.04,blue:0.085),Color(red:0.08,green:0.035,blue:0.11),
                Color(red:0.025,green:0.035,blue:0.07),c.opacity(0.22),Color(red:0.018,green:0.025,blue:0.055)
            ])
        }.ignoresSafeArea()
    }

    private var statusPill: some View {
        Button { showingDevices = true; if lights.devices.isEmpty { lights.scan() } } label: {
            HStack(spacing:8) {
                Circle().fill(lights.connectedName == nil ? (lights.status.contains("Connecting") ? .orange : .gray) : .green).frame(width:7,height:7)
                Text(lights.connectedName ?? (lights.status.contains("Connecting") ? "Connecting" : "Offline"))
                    .font(.system(size:12,weight:.semibold,design:.rounded)).lineLimit(1)
                Image(systemName:"chevron.down").font(.system(size:9,weight:.bold)).opacity(0.6)
            }.padding(.horizontal,14).padding(.vertical,10)
                .glassSurface(corner:22,tint:lights.connectedName == nil ? .white.opacity(0.05) : .green.opacity(0.12), reduce:reduceTransparency)
        }.buttonStyle(.plain)
    }

    private var home: some View {
        ScrollView(showsIndicators:false) {
            VStack(spacing:22) {
                HStack(alignment:.center) {
                    VStack(alignment:.leading,spacing:4) {
                        Text("MORG’S LED").font(.system(size:11,weight:.bold,design:.rounded)).tracking(2.4).foregroundStyle(.white.opacity(0.58))
                        Text("Lighting").font(.system(size:34,weight:.bold,design:.rounded)).tracking(-1)
                    }
                    Spacer()
                    statusPill
                }.padding(.top,12)
                HStack(spacing:20) {
                    colorWheel.frame(width:235,height:235)
                    VStack(spacing:14) {
                        Text("BRIGHTNESS").font(.system(size:9,weight:.bold)).tracking(1.4).foregroundStyle(.white.opacity(0.55))
                        Slider(value:Binding(get:{lights.brightness},set:{lights.setBrightness($0)}),in:1...100)
                            .tint(lights.currentColor).rotationEffect(.degrees(-90)).frame(width:170,height:32)
                            .frame(width:44,height:170)
                        Text("\(Int(lights.brightness))%").font(.system(size:20,weight:.bold,design:.rounded)).monospacedDigit()
                    }.glassSurface(corner:24,reduce:reduceTransparency).frame(maxHeight:210)
                }
                glassCard {
                    VStack(alignment:.leading,spacing:13) {
                        HStack { Text("White temperature").font(.system(size:15,weight:.semibold)); Spacer(); Text("\(Int(temperature))K").font(.system(size:13,weight:.semibold,design:.rounded)).monospacedDigit().foregroundStyle(.white.opacity(0.65)) }
                        Slider(value:$temperature,in:2000...6500,step:50).tint(LinearGradient(colors:[.orange,.white,.cyan],startPoint:.leading,endPoint:.trailing))
                        HStack { Text("Warm"); Spacer(); Text("Cool") }.font(.system(size:10)).foregroundStyle(.white.opacity(0.48))
                    }
                }
                HStack(spacing:12) {
                    Button { withAnimation(.spring(response:0.35)){ lights.togglePower() }; UIImpactFeedbackGenerator(style:.medium).impactOccurred() } label: {
                        Label(lights.isOn ? "Power off" : "Power on",systemImage:"power").font(.system(size:16,weight:.semibold,design:.rounded))
                            .frame(maxWidth:.infinity).padding(.vertical,17).foregroundStyle(.white)
                            .glassSurface(corner:22,tint:lights.currentColor.opacity(0.34),reduce:reduceTransparency)
                    }.buttonStyle(.plain)
                    Button { showingDevices=true; lights.scan() } label: {
                        Image(systemName:"dot.radiowaves.left.and.right").font(.system(size:17,weight:.semibold)).frame(width:58,height:56)
                            .glassSurface(corner:20,reduce:reduceTransparency)
                    }.buttonStyle(.plain)
                }
                colorStrip(title:"Recent",colors:recent)
                colorStrip(title:"Favorites · long-press a color to remove",colors:favorites)
                Text("Color temperature is approximated with RGB because this controller exposes only a standard RGB color command.")
                    .font(.system(size:10)).foregroundStyle(.white.opacity(0.4)).frame(maxWidth:.infinity,alignment:.leading)
            }.padding(.horizontal,20).padding(.bottom,110)
        }
    }

    private var colorWheel: some View {
        ZStack {
            Circle().stroke(AngularGradient(colors:[.red,.orange,.yellow,.green,.cyan,.blue,.purple,.pink,.red],center:.center),style:StrokeStyle(lineWidth:20,lineCap:.round))
                .shadow(color:lights.currentColor.opacity(0.5),radius:18)
            Circle().stroke(.white.opacity(0.12),lineWidth:1).padding(24)
            Circle().fill(lights.currentColor.gradient).frame(width:115,height:115).shadow(color:lights.currentColor.opacity(0.65),radius:25)
            VStack(spacing:2) {
                Text(lights.rgbHex).font(.system(size:16,weight:.bold,design:.rounded)).monospacedDigit()
                Text("CURRENT").font(.system(size:8,weight:.bold)).tracking(1.5).opacity(0.62)
            }
            Circle().fill(.white).frame(width:19,height:19).overlay(Circle().stroke(lights.currentColor,lineWidth:4))
                .offset(x:CGFloat(cos(hue*2*Double.pi))*103,y:CGFloat(sin(hue*2*Double.pi))*103)
                .shadow(color:.white.opacity(0.7),radius:8)
        }
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance:0).onChanged { v in
            let dx=v.location.x-117.5,dy=v.location.y-117.5
            let angle=atan2(dy,dx)/(2*Double.pi)
            hue=(angle+1).truncatingRemainder(dividingBy:1)
            let color=Color(hue:hue,saturation:0.92,brightness:1)
            apply(color)
            UISelectionFeedbackGenerator().selectionChanged()
        })
        .accessibilityLabel("Color wheel")
    }

    private var scenes: some View {
        ScrollView(showsIndicators:false) {
            VStack(alignment:.leading,spacing:18) {
                pageHeader("Scenes","Thirty whole-strip looks, tuned to your room.")
                ScrollView(.horizontal,showsIndicators:false) {
                    HStack(spacing:8) { ForEach(categories,id:\.self) { category in
                        Button(category) { selectedCategory=category }.font(.system(size:12,weight:.semibold))
                            .padding(.horizontal,13).padding(.vertical,9)
                            .glassSurface(corner:20,tint:selectedCategory == category ? .white.opacity(0.18) : .white.opacity(0.04),reduce:reduceTransparency)
                    } }
                }
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:13) {
                    ForEach(visibleScenes) { scene in
                        Button {
                            selectedScene=scene
                            startScene(scene)
                            UIImpactFeedbackGenerator(style:.light).impactOccurred()
                        } label: {
                            VStack(alignment:.leading,spacing:10) {
                                ZStack {
                                    LinearGradient(colors:scene.colors + Array(scene.colors.reversed()),startPoint:.topLeading,endPoint:.bottomTrailing)
                                    Circle().fill(.white.opacity(0.28)).frame(width:70).blur(radius:22).offset(x:35,y:-18)
                                    Image(systemName:scene.symbol).font(.system(size:30,weight:.light)).foregroundStyle(.white).shadow(radius:12)
                                }.frame(height:104).clipShape(RoundedRectangle(cornerRadius:18))
                                HStack { Text(scene.name).font(.system(size:14,weight:.semibold)); Spacer(); if selectedScene?.id == scene.id { Image(systemName:"checkmark.circle.fill").foregroundStyle(.green) } }
                                Text(scene.category.uppercased()).font(.system(size:9,weight:.bold)).tracking(1.2).foregroundStyle(.white.opacity(0.45))
                            }.padding(10).glassSurface(corner:22,reduce:reduceTransparency)
                        }.buttonStyle(.plain)
                    }
                }
                glassCard {
                    VStack(alignment:.leading,spacing:12) {
                        Text("Scene tuning").font(.system(size:17,weight:.semibold))
                        HStack { Text("Speed"); Spacer(); Text("\(Int(sceneSpeed*100))%").monospacedDigit() }
                        Slider(value:$sceneSpeed,in:0.05...1).tint(.cyan)
                        HStack { Text("Brightness"); Spacer(); Text("\(Int(sceneBrightness))%").monospacedDigit() }
                        Slider(value:$sceneBrightness,in:1...100).tint(.cyan)
                        Text("These settings are stored for scene tuning. The current controller accepts whole-strip color and brightness commands; its documented BLE interface does not expose segments.")
                            .font(.system(size:10)).foregroundStyle(.white.opacity(0.42))
                    }
                }
                Button { showDIY=true } label: { Label("Build a DIY scene",systemImage:"plus").frame(maxWidth:.infinity).padding(16).glassSurface(corner:20,tint:.cyan.opacity(0.16),reduce:reduceTransparency) }.buttonStyle(.plain)
            }.padding(.horizontal,20).padding(.top,18).padding(.bottom,110)
        }
    }

    private var music: some View {
        ScrollView(showsIndicators:false) {
            VStack(alignment:.leading,spacing:18) {
                pageHeader("Music","Let nearby sound move your lights.")
                glassCard {
                    VStack(alignment:.leading,spacing:15) {
                        HStack { Label("Microphone input",systemImage:"mic.fill").font(.system(size:16,weight:.semibold)); Spacer(); Circle().fill(audio.isRunning ? .green : .gray).frame(width:8,height:8) }
                        Text(audio.message).font(.system(size:12)).foregroundStyle(.white.opacity(0.58))
                        HStack(spacing:8) {
                            bandBar("BASS",value:audio.bass,color:.orange)
                            bandBar("MID",value:audio.mid,color:.cyan)
                            bandBar("HIGH",value:audio.high,color:.purple)
                        }.frame(height:115)
                        Button { audio.isRunning ? audio.stop() : audio.start() } label: {
                            Label(audio.isRunning ? "Stop listening" : "Enable microphone",systemImage:audio.isRunning ? "stop.fill" : "mic.fill")
                                .frame(maxWidth:.infinity).padding(14).glassSurface(corner:18,tint:.cyan.opacity(0.18),reduce:reduceTransparency)
                        }.buttonStyle(.plain)
                    }
                }
                VStack(alignment:.leading,spacing:10) {
                    Text("Mode").font(.system(size:16,weight:.semibold))
                    LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:9) {
                        ForEach(["Rhythm","Energic","Spectrum","Rolling"],id:\.self) { m in
                            Button(m) { musicMode=m; UIImpactFeedbackGenerator(style:.light).impactOccurred() }
                                .padding(14).frame(maxWidth:.infinity).glassSurface(corner:18,tint:musicMode == m ? .cyan.opacity(0.22) : .white.opacity(0.05),reduce:reduceTransparency).buttonStyle(.plain)
                        }
                    }
                    HStack { Text("Sensitivity"); Spacer(); Text("\(Int(sensitivity*100))%") }
                    Slider(value:$sensitivity,in:0.1...1).tint(.cyan)
                }.padding(18).glassSurface(corner:24,reduce:reduceTransparency)
                Text("Audio is analyzed from the phone microphone, not captured directly from Apple Music or other apps. This controller has one whole-strip RGB command. Music effects are throttled and cannot create true per-pixel spectrum output.")
                    .font(.system(size:11)).foregroundStyle(.white.opacity(0.43))
            }.padding(.horizontal,20).padding(.top,18).padding(.bottom,110)
        }.onChange(of:audio.bass) { _, level in
            guard audio.isRunning, lights.connectedName != nil else { return }
            let v=min(1,level*sensitivity*2.8)
            let color:Color
            switch musicMode {
            case "Energic": color=Color(hue:(0.02+v*0.45).truncatingRemainder(dividingBy:1),saturation:1,brightness:0.35+v*0.65)
            case "Spectrum": color=Color(hue:(0.58+v*0.38).truncatingRemainder(dividingBy:1),saturation:0.95,brightness:0.3+v*0.7)
            case "Rolling": color=Color(hue:(0.7+v*0.22).truncatingRemainder(dividingBy:1),saturation:0.8,brightness:0.35+v*0.65)
            default: color=Color(hue:0.56,saturation:0.9,brightness:0.12+v*0.88)
            }
            applyThrottled(color)
        }.onDisappear { audio.stop() }
    }

    private var timersPage: some View {
        ScrollView(showsIndicators:false) {
            VStack(alignment:.leading,spacing:18) {
                pageHeader("Timers","Schedules need the app awake unless your controller has native timer support.")
                glassCard {
                    VStack(alignment:.leading,spacing:14) {
                        Label("Sleep fade",systemImage:"moon.zzz.fill").font(.system(size:17,weight:.semibold))
                        HStack { Text("Fade duration"); Spacer(); Text("\(Int(timers.sleepMinutes)) min") }
                        Slider(value:$timers.sleepMinutes,in:15...180,step:5).tint(.indigo)
                        Button("Start sleep fade") {
                            timers.sleepFade(brightness:{lights.setBrightness($0)},powerOff:{ if lights.isOn { lights.togglePower() } })
                        }.buttonStyle(.glass).disabled(lights.connectedName == nil)
                        if timers.enabled { Button("Cancel timer",role:.destructive) { timers.cancel() } }
                    }
                }
                glassCard {
                    VStack(alignment:.leading,spacing:14) {
                        Label("Sunrise wake-up",systemImage:"sunrise.fill").font(.system(size:17,weight:.semibold))
                        HStack { Text("Gradual brighten"); Spacer(); Text("\(Int(timers.wakeMinutes)) min") }
                        Slider(value:$timers.wakeMinutes,in:15...30,step:1).tint(.orange)
                        DatePicker("Wake time",selection:$timerDate,displayedComponents:.hourAndMinute).tint(.orange)
                        Button("Schedule sunrise") {
                            timers.scheduleWake(at: timerDate, brightness:{lights.setBrightness($0)}, powerOn:{ if !lights.isOn { lights.togglePower() } })
                        }.buttonStyle(.glass).disabled(lights.connectedName == nil)
                        if timers.enabled { Button("Cancel timer",role:.destructive) { timers.cancel() } }
                    }
                }
                glassCard {
                    VStack(alignment:.leading,spacing:12) {
                        Label("Weekly schedules",systemImage:"calendar").font(.system(size:17,weight:.semibold))
                        Text("A saved time cannot wake a suspended app to send Bluetooth commands. For recurring days, create a personal Shortcut automation that opens Morg’s LED at the chosen time; start the routine here after it opens. Notifications can remind you, but cannot directly control this strip.")
                            .font(.system(size:12)).foregroundStyle(.white.opacity(0.55))
                        Text(timers.message).font(.system(size:11)).foregroundStyle(.orange.opacity(0.85))
                    }
                }
            }.padding(.horizontal,20).padding(.top,18).padding(.bottom,110)
        }
    }

    private var diySheet: some View {
        NavigationStack {
            Form {
                Section("Scene") { TextField("Scene name",text:$diyName); Picker("Motion",selection:$diyMode) { ForEach(modes,id:\.self){Text($0)} }; HStack { Text("Speed"); Slider(value:$diySpeed,in:0.05...1) } }
                Section("Colors · 2 to 6") {
                    ForEach(diyColors.indices,id:\.self) { i in ColorPicker("Color \(i+1)",selection:$diyColors[i],supportsOpacity:false) }
                    if diyColors.count < 6 { Button("Add color") { diyColors.append(.pink) } }
                    if diyColors.count > 2 { Button("Remove last color",role:.destructive) { diyColors.removeLast() } }
                }
                Section { Button("Save DIY scene") {
                    let scene=LEDScene(id:UUID().uuidString,name:diyName.isEmpty ? "My scene" : diyName,category:"DIY",symbol:"wand.and.stars",colors:diyColors,motion:diyMode,speed:diySpeed)
                    diySaved.append(scene); selectedScene=scene; persistScenes(); startScene(scene); showDIY=false
                } }
            }.scrollContentBackground(.hidden).background(Color.black.opacity(0.86)).navigationTitle("Scene builder").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.topBarTrailing){Button("Done"){showDIY=false}} }
        }.preferredColorScheme(.dark)
    }

    private var deviceSheet: some View {
        NavigationStack {
            List {
                if lights.devices.isEmpty { Text(lights.status).foregroundStyle(.secondary); Text("Power on the strip and keep it nearby.").font(.caption).foregroundStyle(.secondary) }
                ForEach(lights.devices,id:\.identifier) { device in
                    Button { lights.connect(device); showingDevices=false } label: {
                        VStack(alignment:.leading) { Text(device.name ?? "Bluetooth LED"); Text(device.identifier.uuidString).font(.caption2).foregroundStyle(.secondary) }
                    }
                }
            }.navigationTitle("Choose LED").toolbar {
                ToolbarItem(placement:.topBarLeading){Button("Done"){showingDevices=false}}
                ToolbarItem(placement:.topBarTrailing){Button("Scan"){lights.scan()}}
            }
        }.preferredColorScheme(.dark)
    }

    private var visibleScenes: [LEDScene] { (selectedCategory == "All" ? LEDScene.library : LEDScene.library.filter{$0.category == selectedCategory}) + diySaved }
    private func pageHeader(_ title:String,_ subtitle:String)->some View {
        VStack(alignment:.leading,spacing:5) { HStack { Text("MORG’S LED").font(.system(size:10,weight:.bold)).tracking(2).foregroundStyle(.white.opacity(0.5)); Spacer(); statusPill }; Text(title).font(.system(size:32,weight:.bold,design:.rounded)); Text(subtitle).font(.system(size:12)).foregroundStyle(.white.opacity(0.5)) }.frame(maxWidth:.infinity,alignment:.leading)
    }
    private func glassCard<Content:View>(@ViewBuilder _ content:()->Content)->some View { content().padding(18).glassSurface(corner:26,reduce:reduceTransparency) }
    private func colorStrip(title:String,colors:[Color])->some View {
        VStack(alignment:.leading,spacing:10) { Text(title).font(.system(size:13,weight:.semibold)).foregroundStyle(.white.opacity(0.7)); ScrollView(.horizontal,showsIndicators:false) { HStack(spacing:12) { ForEach(Array(colors.enumerated()),id:\.offset) { _,color in Circle().fill(color.gradient).frame(width:36,height:36).overlay(Circle().stroke(.white.opacity(0.28),lineWidth:1)).onTapGesture { apply(color) }.onLongPressGesture { if favorites.contains(color) { favorites.removeAll{$0 == color} } else { favorites.insert(color,at:0) }; persistState() } } } } }
    }
    private func bandBar(_ title:String,value:Double,color:Color)->some View {
        VStack(spacing:8) { GeometryReader { geo in VStack { Spacer(minLength:0); Capsule().fill(color.gradient).frame(height:max(4,geo.size.height*min(1,value*2.8))) } }.frame(maxWidth:.infinity); Text(title).font(.system(size:9,weight:.bold)).tracking(1).foregroundStyle(.white.opacity(0.55)) }.frame(maxWidth:.infinity).padding(10).glassSurface(corner:16,reduce:reduceTransparency)
    }
    private func apply(_ color:Color) {
        let ui=UIColor(color); var r:CGFloat=0,g:CGFloat=0,b:CGFloat=0,a:CGFloat=0
        ui.getRed(&r,green:&g,blue:&b,alpha:&a)
        lights.setColor(red:Double(r),green:Double(g),blue:Double(b))
        if !recent.contains(color) { recent.insert(color,at:0); recent=Array(recent.prefix(8)) }
        persistState()
    }
    private func applyThrottled(_ color:Color) {
        guard Date().timeIntervalSinceReferenceDate - lastAudioWrite >= 0.04 else { return }
        lastAudioWrite=Date().timeIntervalSinceReferenceDate; apply(color)
    }
    @State private var lastAudioWrite = 0.0
    private func restoreState() {
        if let data=UserDefaults.standard.data(forKey:"morgs.recent"),let values=try? JSONDecoder().decode([RGBA].self,from:data) { recent=values.map{$0.color} }
        if let data=UserDefaults.standard.data(forKey:"morgs.favorites"),let values=try? JSONDecoder().decode([RGBA].self,from:data) { favorites=values.map{$0.color} }
        if let data=UserDefaults.standard.data(forKey:"morgs.diy-scenes"),let values=try? JSONDecoder().decode([SavedScene].self,from:data) {
            diySaved=values.map { LEDScene(id:$0.id,name:$0.name,category:"DIY",symbol:"wand.and.stars",colors:$0.colors.map{$0.color},motion:$0.motion,speed:$0.speed) }
        }
    }
    private func persistScenes() {
        let values=diySaved.map { SavedScene(id:$0.id,name:$0.name,colors:$0.colors.map{RGBA(color:$0)},motion:$0.motion,speed:$0.speed) }
        UserDefaults.standard.set(try? JSONEncoder().encode(values),forKey:"morgs.diy-scenes")
    }
    private func startScene(_ scene:LEDScene) {
        sceneTask?.cancel()
        guard !scene.colors.isEmpty else { apply(.white); return }
        lights.setBrightness(sceneBrightness)
        let interval=max(0.12,2.2-(scene.speed*1.9))
        sceneTask=Task { @MainActor in
            var index=0
            while !Task.isCancelled {
                let color:Color
                switch scene.motion {
                case "Rainbow":
                    color=Color(hue:Double(index % 24)/24.0,saturation:0.95,brightness:1)
                case "Strobe":
                    color=index % 2 == 0 ? scene.colors[index % scene.colors.count] : .black
                case "Candle flicker":
                    color=index % 4 == 0 ? scene.colors[index % scene.colors.count].opacity(0.58) : scene.colors[index % scene.colors.count]
                case "Pulse","Breathe":
                    color=scene.colors[index % scene.colors.count].opacity(index % 2 == 0 ? 1 : 0.48)
                default:
                    color=scene.colors[index % scene.colors.count]
                }
                apply(color)
                index += 1
                do { try await Task.sleep(for:.seconds(scene.motion == "Strobe" ? max(0.12,interval/3) : interval)) }
                catch { return }
            }
        }
    }
    private func persistState() {
        let r=recent.map{RGBA(color:$0)},f=favorites.map{RGBA(color:$0)}
        UserDefaults.standard.set(try? JSONEncoder().encode(r),forKey:"morgs.recent")
        UserDefaults.standard.set(try? JSONEncoder().encode(f),forKey:"morgs.favorites")
    }
}

private struct SavedScene: Codable {
    var id:String
    var name:String
    var colors:[RGBA]
    var motion:String
    var speed:Double
}

private struct RGBA: Codable {
    var red:Double; var green:Double; var blue:Double
    init(color:Color) { let c=UIColor(color); var r:CGFloat=0,g:CGFloat=0,b:CGFloat=0,a:CGFloat=0; c.getRed(&r,green:&g,blue:&b,alpha:&a); red=Double(r);green=Double(g);blue=Double(b) }
    var color:Color { Color(red:red,green:green,blue:blue) }
}

private extension View {
    func glassSurface(corner:CGFloat,tint:Color = .clear,reduce:Bool)->some View {
        self.padding(1).background {
            if #available(iOS 26.0, *), !reduce {
                RoundedRectangle(cornerRadius:corner,style:.continuous).fill(tint.opacity(0.25))
            } else { RoundedRectangle(cornerRadius:corner,style:.continuous).fill(Color.white.opacity(0.09)) }
        }
        .modifier(NativeGlass(corner:corner,reduce:reduce,tint:tint))
    }
}
private struct NativeGlass: ViewModifier {
    let corner:CGFloat; let reduce:Bool; let tint:Color
    @ViewBuilder func body(content:Content)->some View {
        if #available(iOS 26.0, *), !reduce {
            content.glassEffect(.regular.tint(tint).interactive(),in:.rect(cornerRadius:corner))
        } else {
            content.background(.black.opacity(0.58),in:RoundedRectangle(cornerRadius:corner))
                .overlay(RoundedRectangle(cornerRadius:corner).stroke(.white.opacity(0.2),lineWidth:1))
        }
    }
}
