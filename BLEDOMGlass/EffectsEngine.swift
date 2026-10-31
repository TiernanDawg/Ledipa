import SwiftUI
import Foundation

struct LEDScene: Identifiable, Hashable {
    let id: String
    let name: String
    let category: String
    let symbol: String
    let colors: [Color]
    var color: Color { colors.first ?? .white }

    static let library: [LEDScene] = [
        .init(id:"sunset",name:"Sunset",category:"Ambient",symbol:"sunset.fill",colors:[Color(red:1,green:0.32,blue:0.12)]),
        .init(id:"ocean",name:"Ocean",category:"Nature",symbol:"water.waves",colors:[Color(red:0.02,green:0.32,blue:0.9)]),
        .init(id:"aurora",name:"Aurora",category:"Nature",symbol:"sparkles",colors:[.cyan,.green,.purple]),
        .init(id:"candle",name:"Candlelight",category:"Cozy",symbol:"flame.fill",colors:[Color(red:1,green:0.36,blue:0.08)]),
        .init(id:"fireplace",name:"Fireplace",category:"Cozy",symbol:"fireplace.fill",colors:[Color(red:1,green:0.19,blue:0.025)]),
        .init(id:"forest",name:"Forest",category:"Nature",symbol:"tree.fill",colors:[Color(red:0.04,green:0.48,blue:0.22)]),
        .init(id:"neon",name:"Neon City",category:"Gaming",symbol:"building.2.crop.circle",colors:[.purple,.pink]),
        .init(id:"lava",name:"Lava",category:"Nature",symbol:"volcano.fill",colors:[.red,.orange]),
        .init(id:"cyber",name:"Cyberpunk",category:"Gaming",symbol:"cpu",colors:[.cyan,.purple]),
        .init(id:"movie",name:"Movie Night",category:"Ambient",symbol:"film",colors:[Color(red:0.08,green:0.08,blue:0.28)]),
        .init(id:"rainbow",name:"Rainbow",category:"Party",symbol:"rainbow",colors:[.red,.orange,.yellow,.green,.blue,.purple]),
        .init(id:"breathe",name:"Breathe",category:"Sleep",symbol:"wind",colors:[Color(red:0.22,green:0.32,blue:0.85)]),
        .init(id:"ice",name:"Arctic",category:"Ambient",symbol:"snowflake",colors:[.cyan,.white]),
        .init(id:"rose",name:"Rose",category:"Cozy",symbol:"heart.fill",colors:[.pink,.purple]),
        .init(id:"focus",name:"Focus",category:"Gaming",symbol:"scope",colors:[Color(red:0.1,green:0.35,blue:0.9)]),
        .init(id:"starlight",name:"Starlight",category:"Sleep",symbol:"star.fill",colors:[.indigo,.white]),
        .init(id:"dusk",name:"Dusk",category:"Ambient",symbol:"moon.stars.fill",colors:[.purple,.orange]),
        .init(id:"mint",name:"Mint",category:"Nature",symbol:"leaf.fill",colors:[.mint,.cyan]),
        .init(id:"party",name:"Party",category:"Party",symbol:"party.popper.fill",colors:[.pink,.yellow,.cyan]),
        .init(id:"arcade",name:"Arcade",category:"Gaming",symbol:"gamecontroller.fill",colors:[.green,.purple]),
        .init(id:"ember",name:"Ember",category:"Cozy",symbol:"sun.max.fill",colors:[.orange,.red]),
        .init(id:"cloud",name:"Cloud Nine",category:"Sleep",symbol:"cloud.fill",colors:[.cyan,.white]),
        .init(id:"deep",name:"Deep Space",category:"Sleep",symbol:"moon.fill",colors:[.indigo,.purple]),
        .init(id:"tropical",name:"Tropical",category:"Nature",symbol:"palm tree",colors:[.green,.orange]),
        .init(id:"laser",name:"Laser Grid",category:"Gaming",symbol:"laser.burst",colors:[.red,.cyan]),
        .init(id:"gold",name:"Golden Hour",category:"Ambient",symbol:"sun.horizon.fill",colors:[.yellow,.orange]),
        .init(id:"cotton",name:"Cotton Candy",category:"Party",symbol:"cloud.rainbow.half",colors:[.pink,.cyan]),
        .init(id:"calm",name:"Calm",category:"Sleep",symbol:"water.waves",colors:[.teal,.indigo]),
        .init(id:"warm",name:"Warm White",category:"Cozy",symbol:"lightbulb.fill",colors:[Color(red:1,green:0.72,blue:0.42)]),
        .init(id:"ultraviolet",name:"Ultraviolet",category:"Party",symbol:"light.beacon.max.fill",colors:[.purple,.indigo])
    ]
}

enum ColorScience {
    static func mixOKLab(_ a: SIMD3<Double>, _ b: SIMD3<Double>, t: Double) -> SIMD3<Double> {
        let l = a.x + (b.x-a.x)*t, m = a.y + (b.y-a.y)*t, s = a.z + (b.z-a.z)*t
        let l3=l*l*l, m3=m*m*m, s3=s*s*s
        return SIMD3( max(0,min(1, 4.0767416621*l3 - 3.3077115913*m3 + 0.2309699292*s3)),
                      max(0,min(1, -1.2684380046*l3 + 2.6097574011*m3 - 0.3413193965*s3)),
                      max(0,min(1, -0.0041960863*l3 - 0.7034186147*m3 + 1.707614701*s3)) )
    }
    static func gamma(_ value: Double) -> Double { pow(max(0,min(1,value)), 2.2) }
}
