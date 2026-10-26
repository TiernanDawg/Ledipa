import Foundation
import CoreBluetooth
import SwiftUI

struct LEDPreset: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var red: Double
    var green: Double
    var blue: Double

    var color: Color { Color(red: red, green: green, blue: blue) }
}

final class BLEController: NSObject, ObservableObject {
    @Published var devices: [CBPeripheral] = []
    @Published var connectedName: String?
    @Published var status = "Ready to scan"
    @Published var isScanning = false
    @Published var isPoweredOn = false
    @Published var isOn = true
    @Published var red: Double = 0.0
    @Published var green: Double = 0.53
    @Published var blue: Double = 1.0
    @Published var brightness: Double = 80
    @Published var presets: [LEDPreset] = []

    private var central: CBCentralManager!
    private var activePeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var supportedServiceIDs: Set<CBUUID> = [
        CBUUID(string: "FFF0"), CBUUID(string: "FFE0"), CBUUID(string: "FFE5")
    ]
    private var supportedWriteIDs: Set<CBUUID> = [
        CBUUID(string: "FFF3"), CBUUID(string: "FFE1"), CBUUID(string: "FFE9")
    ]
    private let presetsKey = "luma.saved-presets.v1"
    private let rememberedDeviceIDKey = "morgs-led.remembered-device-id"
    private let rememberedDeviceNameKey = "morgs-led.remembered-device-name"
    private let autoConnectKey = "morgs-led.auto-connect"

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
        if let data = UserDefaults.standard.data(forKey: presetsKey),
           let saved = try? JSONDecoder().decode([LEDPreset].self, from: data) {
            presets = saved
        } else {
            presets = [
                LEDPreset(name: "Arctic", red: 0.0, green: 0.53, blue: 1.0),
                LEDPreset(name: "Violet", red: 0.48, green: 0.16, blue: 1.0),
                LEDPreset(name: "Rose", red: 1.0, green: 0.08, blue: 0.34),
                LEDPreset(name: "Warm", red: 1.0, green: 0.48, blue: 0.12),
                LEDPreset(name: "Mint", red: 0.05, green: 1.0, blue: 0.58),
                LEDPreset(name: "White", red: 1.0, green: 1.0, blue: 1.0)
            ]
        }
    }

    var autoConnectEnabled: Bool { UserDefaults.standard.object(forKey: autoConnectKey) as? Bool ?? true }
    var rememberedDeviceID: String? { UserDefaults.standard.string(forKey: rememberedDeviceIDKey) }
    var rememberedDeviceName: String? { UserDefaults.standard.string(forKey: rememberedDeviceNameKey) }

    var currentColor: Color { Color(red: red, green: green, blue: blue) }
    var rgbHex: String {
        String(format: "%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
    }

    func scan() {
        guard isPoweredOn else { status = "Turn on Bluetooth to continue"; return }
        devices.removeAll()
        status = "Searching nearby"
        isScanning = true
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self, self.isScanning else { return }
            self.central.stopScan()
            self.isScanning = false
            self.status = self.devices.isEmpty ? "No lights found — move closer and retry" : "Select your light"
        }
    }

    func connect(_ peripheral: CBPeripheral) {
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: rememberedDeviceIDKey)
        UserDefaults.standard.set(peripheral.name ?? "BLEDOM LED", forKey: rememberedDeviceNameKey)
        objectWillChange.send()
        central.stopScan()
        isScanning = false
        status = "Connecting…"
        activePeripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    func disconnect() {
        guard let activePeripheral else { return }
        central.cancelPeripheralConnection(activePeripheral)
    }

    func setAutoConnectEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: autoConnectKey)
        objectWillChange.send()
        if enabled { attemptAutoConnect() }
    }

    func forgetRememberedDevice() {
        UserDefaults.standard.removeObject(forKey: rememberedDeviceIDKey)
        UserDefaults.standard.removeObject(forKey: rememberedDeviceNameKey)
        UserDefaults.standard.set(false, forKey: autoConnectKey)
        objectWillChange.send()
    }

    private func attemptAutoConnect() {
        guard autoConnectEnabled, isPoweredOn, activePeripheral == nil,
              let idString = rememberedDeviceID, let identifier = UUID(uuidString: idString) else { return }
        guard let peripheral = central.retrievePeripherals(withIdentifiers: [identifier]).first else {
            status = "Saved LED not currently available — scan to find it"
            return
        }
        connect(peripheral)
    }

    func setColor(red r: Double, green g: Double, blue b: Double) {
        red = r; green = g; blue = b
        sendColor()
    }

    func sendColor() {
        guard let peripheral = activePeripheral, let characteristic = writeCharacteristic else { return }
        let frame: [UInt8] = [0x7E, 0x00, 0x05, 0x03,
                              UInt8((red * 255).rounded()),
                              UInt8((green * 255).rounded()),
                              UInt8((blue * 255).rounded()), 0x00, 0xEF]
        write(frame, to: peripheral, characteristic: characteristic)
    }

    func setBrightness(_ value: Double) {
        brightness = value
        guard let peripheral = activePeripheral, let characteristic = writeCharacteristic else { return }
        let amount = UInt8(min(100, max(0, Int(value.rounded()))))
        write([0x7E, 0x00, 0x01, amount, 0x00, 0x00, 0x00, 0x00, 0xEF], to: peripheral, characteristic: characteristic)
    }

    func togglePower() {
        isOn.toggle()
        guard let peripheral = activePeripheral, let characteristic = writeCharacteristic else {
            isOn.toggle(); status = "Connect to your light first"; return
        }
        let frame: [UInt8] = isOn
            ? [0x7E, 0x00, 0x04, 0xF0, 0x00, 0x01, 0xFF, 0x00, 0xEF]
            : [0x7E, 0x00, 0x04, 0x00, 0x00, 0x00, 0xFF, 0x00, 0xEF]
        write(frame, to: peripheral, characteristic: characteristic)
    }

    func saveCurrentPreset(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = LEDPreset(name: trimmed.isEmpty ? "#\(rgbHex)" : trimmed, red: red, green: green, blue: blue)
        presets.insert(item, at: 0)
        persistPresets()
    }

    func apply(_ preset: LEDPreset) {
        setColor(red: preset.red, green: preset.green, blue: preset.blue)
    }

    func removePreset(_ preset: LEDPreset) {
        presets.removeAll { $0.id == preset.id }
        persistPresets()
    }

    private func persistPresets() {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: presetsKey)
        }
    }

    private func write(_ bytes: [UInt8], to peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        let data = Data(bytes)
        let type: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(data, for: characteristic, type: type)
    }
}

extension BLEController: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        isPoweredOn = central.state == .poweredOn
        if !isPoweredOn {
            status = central.state == .unauthorized ? "Bluetooth permission required" : "Bluetooth is unavailable"
        } else if autoConnectEnabled, rememberedDeviceID != nil {
            attemptAutoConnect()
        } else if status == "Ready to scan" {
            status = "Ready to find your light"
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Bluetooth light"
        let matchesName = name.localizedCaseInsensitiveContains("bledom") || name.localizedCaseInsensitiveContains("ble") || name.localizedCaseInsensitiveContains("led")
        let advertised = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let matchesService = advertised.contains { supportedServiceIDs.contains($0) }
        guard matchesName || matchesService else { return }
        if !devices.contains(where: { $0.identifier == peripheral.identifier }) {
            devices.append(peripheral)
            devices.sort { ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending }
        }
        status = "\(devices.count) compatible-looking device\(devices.count == 1 ? "" : "s") found"
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedName = peripheral.name ?? "BLEDOM"
        status = "Connected · discovering controls"
        peripheral.discoverServices(Array(supportedServiceIDs))
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        status = "Connection failed — tap to retry"
        connectedName = nil
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectedName = nil
        activePeripheral = nil
        writeCharacteristic = nil
        status = error == nil ? "Disconnected" : "Connection lost — reconnect to continue"
    }
}

extension BLEController: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else { status = "Could not read controller services"; return }
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else { status = "Could not discover LED controls"; return }
        if let characteristic = service.characteristics?.first(where: { supportedWriteIDs.contains($0.uuid) && ($0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse)) }) {
            writeCharacteristic = characteristic
            status = "Connected and ready"
            if isOn { sendColor(); setBrightness(brightness) }
        }
        if writeCharacteristic == nil {
            status = "Connected, but no compatible write control was found"
        }
    }
}
