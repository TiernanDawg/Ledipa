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
    static func mixColor(_ first: Color, _ second: Color, t: Double) -> Color {
        let a=first.oklabComponents, b=second.oklabComponents
        let u=max(0,min(1,t))
        let L=a.x+(b.x-a.x)*u, A=a.y+(b.y-a.y)*u, B=a.z+(b.z-a.z)*u
        let l=L+0.3963377774*A+0.2158037573*B
        let m=L-0.1055613458*A-0.0638541728*B
        let ss=L-0.0894841775*A-1.2914855480*B
        let l3=l*l*l, m3=m*m*m, s3=ss*ss*ss
        func gamma(_ v:Double)->Double {
            let x=max(0,v)
            return x <= 0.0031308 ? 12.92*x : 1.055*pow(x,1/2.4)-0.055
        }
        return Color(red:min(1,gamma(4.0767416621*l3-3.3077115913*m3+0.2309699292*s3)),
                     green:min(1,gamma(-1.2684380046*l3+2.6097574011*m3-0.3413193965*s3)),
                     blue:min(1,gamma(-0.0041960863*l3-0.7034186147*m3+1.707614701*s3)))
    }
    static func mixOKLab(_ a: SIMD3<Double>, _ b: SIMD3<Double>, t: Double) -> SIMD3<Double> {
        let l = a.x + (b.x-a.x)*t, m = a.y + (b.y-a.y)*t, s = a.z + (b.z-a.z)*t
        let l3=l*l*l, m3=m*m*m, s3=s*s*s
        return SIMD3( max(0,min(1, 4.0767416621*l3 - 3.3077115913*m3 + 0.2309699292*s3)),
                      max(0,min(1, -1.2684380046*l3 + 2.6097574011*m3 - 0.3413193965*s3)),
                      max(0,min(1, -0.0041960863*l3 - 0.7034186147*m3 + 1.707614701*s3)) )
    }
    static func gamma(_ value: Double) -> Double { pow(max(0,min(1,value)), 2.2) }
}

private extension Color {
    var oklabComponents: SIMD3<Double> {
        let ui=UIColor(self); var r:CGFloat=0,g:CGFloat=0,b:CGFloat=0,a:CGFloat=0
        ui.getRed(&r,green:&g,blue:&b,alpha:&a)
        let rr=Double(r),gg=Double(g),bb=Double(b)
        let l=cbrt(0.4122214708*rr+0.5363325363*gg+0.0514459929*bb)
        let m=cbrt(0.2119034982*rr+0.6806995451*gg+0.1073969566*bb)
        let ss=cbrt(0.0883024619*rr+0.2817188376*gg+0.6299787005*bb)
        return SIMD3(0.2104542553*l+0.7936177850*m-0.0040720468*ss,
                     1.9779984951*l-2.4285922050*m+0.4505937099*ss,
                     0.0259040371*l+0.7827717662*m-0.8086757660*ss)
    }
}
