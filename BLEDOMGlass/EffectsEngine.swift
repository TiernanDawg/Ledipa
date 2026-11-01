import SwiftUI
import Foundation

struct LEDScene: Identifiable, Hashable {
    let id: String
    let name: String
    let category: String
    let symbol: String
    let colors: [Color]
    var motion: String = "Fade"
    var speed: Double = 0.45
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
    /// Interpolate the actual sRGB values sent to inexpensive RGB controllers.
    /// Avoids converting through an incorrectly assumed color space.
    static func mixColor(_ first: Color, _ second: Color, t: Double) -> Color {
        let a=first.rgbComponents
        let b=second.rgbComponents
        let u=max(0,min(1,t))
        return Color(
            red:a.x+(b.x-a.x)*u,
            green:a.y+(b.y-a.y)*u,
            blue:a.z+(b.z-a.z)*u
        )
    }

    static func dim(_ color: Color, level: Double) -> Color {
        let value=color.rgbComponents
        let amount=max(0,min(1,level))
        return Color(red:value.x*amount,green:value.y*amount,blue:value.z*amount)
    }
}
private extension Color {
    var rgbComponents: SIMD3<Double> {
        var red:CGFloat=0,green:CGFloat=0,blue:CGFloat=0,alpha:CGFloat=0
        UIColor(self).resolvedColor(with:UITraitCollection(userInterfaceStyle:.dark))
            .getRed(&red,green:&green,blue:&blue,alpha:&alpha)
        return SIMD3(Double(red),Double(green),Double(blue))
    }
}
