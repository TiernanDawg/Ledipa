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

enum LEDColorFrameFormat: String, CaseIterable, Identifiable {
    case standard
    case bledom07

    var id: String { rawValue }
    var title: String {
        switch self {
        case .standard: return "Standard (00 / 00)"
        case .bledom07: return "BLEDOM (07 / 10)"
        }
    }
    var variantByte: UInt8 { self == .standard ? 0x00 : 0x07 }
    var trailingByte: UInt8 { self == .standard ? 0x00 : 0x10 }
}

enum LEDChannelOrder: String, CaseIterable, Identifiable {
    case rgb, rbg, grb, gbr, brg, bgr

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
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
    @Published var colorFrameFormat: LEDColorFrameFormat = .standard
    @Published var channelOrder: LEDChannelOrder = .rgb
    @Published private(set) var isColorTestRunning = false
    @Published private(set) var signalRSSI: Int?
    @Published private(set) var signalHistory: [Int] = []

    private var rssiTimer: Timer?
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
    private let stateKey = "morgs-led.last-state"
    private var manualDisconnect = false
    private var reconnectAttempts = 0
    private var pendingWrites: [Data] = []
    private var responseWriteInFlight = false
    private var scanGeneration = 0
    private var reconnectGeneration = 0
    private var colorTestTask: Task<Void, Never>?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
        if let state = UserDefaults.standard.dictionary(forKey: stateKey) {
            red = state["red"] as? Double ?? red
            green = state["green"] as? Double ?? green
            blue = state["blue"] as? Double ?? blue
            brightness = state["brightness"] as? Double ?? brightness
            isOn = state["isOn"] as? Bool ?? isOn
        }
        if let raw = UserDefaults.standard.string(forKey: "morgs-led.color-frame-format"),
           let saved = LEDColorFrameFormat(rawValue: raw) { colorFrameFormat = saved }
        if let raw = UserDefaults.standard.string(forKey: "morgs-led.channel-order"),
           let saved = LEDChannelOrder(rawValue: raw) { channelOrder = saved }
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
    var lightState: LightState {
        LightState(
            name: connectedName ?? rememberedDeviceName ?? "LED Strip",
            red: red, green: green, blue: blue,
            brightness: brightness, isOn: isOn,
            isConnected: connectedName != nil,
            statusMessage: status
        )
    }
    var rgbHex: String {
        String(format: "%02X%02X%02X",
               Int(normalizedChannel(red) * 255),
               Int(normalizedChannel(green) * 255),
               Int(normalizedChannel(blue) * 255))
    }

    /// BLE RGB frames require finite, normalized 8-bit channel values.
    private func normalizedChannel(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }

    func scan() {
        guard isPoweredOn else { status = "Turn on Bluetooth to continue"; return }
        scanGeneration += 1
        let generation = scanGeneration
        central.stopScan()
        devices.removeAll()
        status = "Searching nearby"
        isScanning = true
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self, self.scanGeneration == generation, self.isScanning else { return }
            self.central.stopScan()
            self.isScanning = false
            self.status = self.devices.isEmpty ? "No lights found — move closer and retry" : "Select your light"
        }
    }

    func connect(_ peripheral: CBPeripheral) {
        reconnectGeneration += 1
        reconnectAttempts = 0
        connectPeripheral(peripheral)
    }

    private func connectPeripheral(_ peripheral: CBPeripheral) {
        guard central.state == .poweredOn else {
            status = "Turn on Bluetooth to connect"
            return
        }
        if activePeripheral?.identifier == peripheral.identifier,
           connectedName != nil {
            status = "Already connected"
            return
        }
        manualDisconnect = false
        pendingWrites.removeAll()
        responseWriteInFlight = false
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: rememberedDeviceIDKey)
        UserDefaults.standard.set(peripheral.name ?? "BLEDOM LED", forKey: rememberedDeviceNameKey)
        objectWillChange.send()
        central.stopScan()
        scanGeneration += 1
        isScanning = false
        status = "Connecting…"
        if let previous = activePeripheral, previous.identifier != peripheral.identifier {
            colorTestTask?.cancel()
            central.cancelPeripheralConnection(previous)
        }
        activePeripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    func disconnect() {
        colorTestTask?.cancel()
        stopRSSIMonitoring()
        reconnectGeneration += 1
        manualDisconnect = true
        guard let activePeripheral else {
            connectedName = nil
            status = "Disconnected"
            return
        }
        status = "Disconnecting…"
        central.cancelPeripheralConnection(activePeripheral)
    }

    func setAutoConnectEnabled(_ enabled: Bool) {
        if !enabled { reconnectGeneration += 1 }
        UserDefaults.standard.set(enabled, forKey: autoConnectKey)
        objectWillChange.send()
        if enabled { attemptAutoConnect() }
    }

    func forgetRememberedDevice() {
        reconnectGeneration += 1
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
        connectPeripheral(peripheral)
    }

    private func startRSSIMonitoring(_ peripheral: CBPeripheral) {
        stopRSSIMonitoring()
        signalRSSI = nil
        signalHistory.removeAll()
        peripheral.readRSSI()
        rssiTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self, weak peripheral] _ in
            guard let self, let peripheral,
                  self.activePeripheral?.identifier == peripheral.identifier else { return }
            peripheral.readRSSI()
        }
    }

    private func stopRSSIMonitoring() {
        rssiTimer?.invalidate()
        rssiTimer = nil
        signalRSSI = nil
    }

    var signalQualityLabel: String {
        guard let rssi = signalRSSI else { return connectedName == nil ? "Unavailable" : "Measuring" }
        if rssi >= -55 { return "Excellent" }
        if rssi >= -67 { return "Strong" }
        if rssi >= -78 { return "Fair" }
        return "Weak"
    }

    var signalBars: Int {
        guard let rssi = signalRSSI else { return 0 }
        if rssi >= -55 { return 4 }
        if rssi >= -67 { return 3 }
        if rssi >= -78 { return 2 }
        return 1
    }

    private func scheduleReconnect() {
        guard autoConnectEnabled, !manualDisconnect, reconnectAttempts < 5, isPoweredOn else {
            if manualDisconnect { manualDisconnect = false }
            return
        }
        reconnectAttempts += 1
        reconnectGeneration += 1
        let generation = reconnectGeneration
        let delay = min(30.0, pow(2.0, Double(reconnectAttempts)))
        status = "Connection lost — retrying in \(Int(delay))s"
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.reconnectGeneration == generation,
                  self.activePeripheral == nil, self.autoConnectEnabled,
                  !self.manualDisconnect else { return }
            self.attemptAutoConnect()
        }
    }

    func setColor(red r: Double, green g: Double, blue b: Double) {
        setColor(red: r, green: g, blue: b, persist: true)
    }

    func setColor(red r: Double, green g: Double, blue b: Double, persist: Bool) {
        red = normalizedChannel(r)
        green = normalizedChannel(g)
        blue = normalizedChannel(b)
        if persist { persistState() }
        sendColor()
    }

    func persistCurrentState() { persistState() }

    func setColorFrameFormat(_ format: LEDColorFrameFormat) {
        colorFrameFormat = format
        UserDefaults.standard.set(format.rawValue, forKey: "morgs-led.color-frame-format")
        sendColor()
    }

    func setChannelOrder(_ order: LEDChannelOrder) {
        channelOrder = order
        UserDefaults.standard.set(order.rawValue, forKey: "morgs-led.channel-order")
        sendColor()
    }

    private func orderedChannels() -> (UInt8, UInt8, UInt8) {
        let r = UInt8((normalizedChannel(red) * 255).rounded())
        let g = UInt8((normalizedChannel(green) * 255).rounded())
        let b = UInt8((normalizedChannel(blue) * 255).rounded())
        switch channelOrder {
        case .rgb: return (r, g, b)
        case .rbg: return (r, b, g)
        case .grb: return (g, r, b)
        case .gbr: return (g, b, r)
        case .brg: return (b, r, g)
        case .bgr: return (b, g, r)
        }
    }

    func runColorTest() {
        guard activePeripheral != nil, writeCharacteristic != nil, isOn else {
            status = isOn ? "Connect to your light before testing colors" : "Turn your light on before testing colors"
            return
        }
        colorTestTask?.cancel()
        let original = (red, green, blue)
        isColorTestRunning = true
        colorTestTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let testColors: [(Double, Double, Double)] = [
                (1, 0, 0), (0, 1, 0), (0, 0, 1)
            ]
            for color in testColors {
                guard !Task.isCancelled else { break }
                self.setColor(red: color.0, green: color.1, blue: color.2, persist: false)
                do { try await Task.sleep(for: .milliseconds(700)) }
                catch { break }
            }
            self.setColor(red: original.0, green: original.1, blue: original.2, persist: false)
            self.persistCurrentState()
            self.isColorTestRunning = false
            self.colorTestTask = nil
        }
    }

    func sendColor() {
        guard let peripheral = activePeripheral, let characteristic = writeCharacteristic else { return }
        let channels = orderedChannels()
        let frame: [UInt8] = [
            0x7E, colorFrameFormat.variantByte, 0x05, 0x03,
            channels.0, channels.1, channels.2,
            colorFrameFormat.trailingByte, 0xEF
        ]
        write(frame, to: peripheral, characteristic: characteristic)
    }

    func setBrightness(_ value: Double) {
        brightness = value.isFinite ? min(100, max(0, value)) : 0
        persistState()
        guard let peripheral = activePeripheral, let characteristic = writeCharacteristic else { return }
        let amount = UInt8(brightness.rounded())
        write([0x7E, 0x00, 0x01, amount, 0x00, 0x00, 0x00, 0x00, 0xEF], to: peripheral, characteristic: characteristic)
    }

    func togglePower() {
        // Do not persist a power-state change unless a controller is ready to
        // receive it. This keeps the displayed and restored state truthful.
        guard let peripheral = activePeripheral, let characteristic = writeCharacteristic else {
            status = "Connect to your light first"
            return
        }
        isOn.toggle()
        persistState()
        let frame: [UInt8] = isOn
            ? [0x7E, 0x00, 0x04, 0xF0, 0x00, 0x01, 0xFF, 0x00, 0xEF]
            : [0x7E, 0x00, 0x04, 0x00, 0x00, 0x00, 0xFF, 0x00, 0xEF]
        write(frame, to: peripheral, characteristic: characteristic)
    }

    private func persistState() {
        UserDefaults.standard.set(["red": red, "green": green, "blue": blue, "brightness": brightness, "isOn": isOn], forKey: stateKey)
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
        // Color and brightness are state updates: when BLE is congested, only
        // the newest pending value matters. Preserve ordering for power commands.
        if bytes.count > 2, bytes[2] == 0x05 || bytes[2] == 0x01 {
            pendingWrites.removeAll { queued in
                queued.count > 2 && queued[2] == bytes[2]
            }
        }
        pendingWrites.append(data)
        drainWriteQueue(for: peripheral, characteristic: characteristic)
    }

    /// Respect CoreBluetooth's back-pressure instead of flooding inexpensive LED controllers.
    private func drainWriteQueue(for peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        if characteristic.properties.contains(.writeWithoutResponse) {
            while !pendingWrites.isEmpty && peripheral.canSendWriteWithoutResponse {
                let data = pendingWrites.removeFirst()
                peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
            }
            return
        }

        guard !responseWriteInFlight, !pendingWrites.isEmpty,
              characteristic.properties.contains(.write) else { return }
        responseWriteInFlight = true
        let data = pendingWrites.removeFirst()
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }
}

extension BLEController: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        isPoweredOn = central.state == .poweredOn
        if !isPoweredOn {
            stopRSSIMonitoring()
            signalHistory.removeAll()
            scanGeneration += 1
            central.stopScan()
            isScanning = false
            connectedName = nil
            activePeripheral = nil
            colorTestTask?.cancel()
            writeCharacteristic = nil
            pendingWrites.removeAll()
            responseWriteInFlight = false
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
        guard activePeripheral?.identifier == peripheral.identifier else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        reconnectAttempts = 0
        peripheral.delegate = self
        writeCharacteristic = nil
        pendingWrites.removeAll()
        responseWriteInFlight = false
        connectedName = peripheral.name ?? "BLEDOM"
        startRSSIMonitoring(peripheral)
        status = "Connected · discovering controls"
        peripheral.discoverServices(Array(supportedServiceIDs))
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard activePeripheral?.identifier == peripheral.identifier else { return }
        stopRSSIMonitoring()
        activePeripheral = nil
        writeCharacteristic = nil
        pendingWrites.removeAll()
        responseWriteInFlight = false
        connectedName = nil
        status = error.map { "Connection failed: \($0.localizedDescription)" } ?? "Connection failed — retrying"
        scheduleReconnect()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard activePeripheral?.identifier == peripheral.identifier else { return }
        stopRSSIMonitoring()
        connectedName = nil
        activePeripheral = nil
        colorTestTask?.cancel()
        writeCharacteristic = nil
        pendingWrites.removeAll()
        responseWriteInFlight = false
        status = error == nil ? "Disconnected" : "Connection lost"
        scheduleReconnect()
    }
}

extension BLEController: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard activePeripheral?.identifier == peripheral.identifier, error == nil else { return }
        let value = RSSI.intValue
        signalRSSI = value
        signalHistory.append(value)
        if signalHistory.count > 30 { signalHistory.removeFirst(signalHistory.count - 30) }
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        guard let characteristic = writeCharacteristic else { return }
        drainWriteQueue(for: peripheral, characteristic: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        responseWriteInFlight = false
        if let error {
            status = "LED command failed: \(error.localizedDescription)"
        }
        drainWriteQueue(for: peripheral, characteristic: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else { status = "Could not read controller services"; return }
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else { status = "Could not discover LED controls"; return }
        if writeCharacteristic == nil,
           let characteristic = service.characteristics?.first(where: {
               supportedWriteIDs.contains($0.uuid) &&
               ($0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse))
           }) {
            writeCharacteristic = characteristic
            status = "Connected and ready"
            if isOn {
                sendColor()
                setBrightness(brightness)
            }
        }
    }
}

extension BLEController: MorgsHardware {}
