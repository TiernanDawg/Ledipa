import Foundation

/// Normalized snapshot of the light currently represented by the app.
struct LightState: Equatable {
    enum Status: Equatable {
        case disconnected
        case off
        case on
    }

    let name: String
    let red: Double
    let green: Double
    let blue: Double
    let brightness: Double
    let isOn: Bool
    let isConnected: Bool
    let statusMessage: String

    var status: Status {
        guard isConnected else { return .disconnected }
        return isOn ? .on : .off
    }

    var hex: String {
        String(format: "%02X%02X%02X",
               Int(min(1, max(0, red)) * 255),
               Int(min(1, max(0, green)) * 255),
               Int(min(1, max(0, blue)) * 255))
    }
}

/// Hardware boundary used by the UI. A BLE implementation can be replaced
/// later without making views depend on CoreBluetooth types.
protocol MorgsHardware: AnyObject {
    var lightState: LightState { get }
    func setColor(red: Double, green: Double, blue: Double)
    func setBrightness(_ value: Double)
    func togglePower()
}
