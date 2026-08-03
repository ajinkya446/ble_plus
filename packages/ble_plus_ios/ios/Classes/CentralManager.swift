import Foundation
import CoreBluetooth

/// Manages BLE Central role on iOS via CoreBluetooth.
class CentralManagerHandler: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {

    private var centralManager: CBCentralManager!
    private let queue = DispatchQueue(label: "com.example.ble_plus.central", qos: .userInitiated)

    // Connected peripherals keyed by UUID string
    private var peripherals: [String: CBPeripheral] = [:]

    // Event sinks
    private var adapterSink: FlutterEventSink?
    private var scanSink: FlutterEventSink?
    private var connectionSink: FlutterEventSink?
    private var characteristicSink: FlutterEventSink?
    private var mtuSink: FlutterEventSink?
    private var l2capSink: FlutterEventSink?

    // Pending results for async operations
    private var pendingResults: [String: FlutterResult] = [:]

    // L2CAP channels
    private var l2capChannels: [Int: CBL2CAPChannel] = [:]
    private var nextL2CapId = 0

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: queue)
    }

    // ═══════════════════════════════════════════════════════════
    // STREAM HANDLERS
    // ═══════════════════════════════════════════════════════════

    lazy var adapterStreamHandler = SimpleStreamHandler { [weak self] sink in
        self?.adapterSink = sink
        // Emit current state
        if let state = self?.mapState(self?.centralManager.state ?? .unknown) {
            sink?(state)
        }
    } onCancel: { [weak self] in
        self?.adapterSink = nil
    }

    lazy var scanStreamHandler = SimpleStreamHandler { [weak self] sink in
        self?.scanSink = sink
    } onCancel: { [weak self] in
        self?.scanSink = nil
    }

    lazy var connectionStreamHandler = SimpleStreamHandler { [weak self] sink in
        self?.connectionSink = sink
    } onCancel: { [weak self] in
        self?.connectionSink = nil
    }

    lazy var characteristicStreamHandler = SimpleStreamHandler { [weak self] sink in
        self?.characteristicSink = sink
    } onCancel: { [weak self] in
        self?.characteristicSink = nil
    }

    lazy var mtuStreamHandler = SimpleStreamHandler { [weak self] sink in
        self?.mtuSink = sink
    } onCancel: { [weak self] in
        self?.mtuSink = nil
    }

    lazy var l2capStreamHandler = SimpleStreamHandler { [weak self] sink in
        self?.l2capSink = sink
    } onCancel: { [weak self] in
        self?.l2capSink = nil
    }

    // ═══════════════════════════════════════════════════════════
    // CBCentralManagerDelegate
    // ═══════════════════════════════════════════════════════════

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DispatchQueue.main.async {
            self.adapterSink?(self.mapState(central.state))
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                         advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let serviceUuids = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.map { $0.uuidString.lowercased() } ?? []
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let connectable = advertisementData[CBAdvertisementDataIsConnectable] as? Bool ?? true
        let txPower = advertisementData[CBAdvertisementDataTxPowerLevelKey] as? Int

        var manufacturerData: [Int: [Int]] = [:]
        if let mfgData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data, mfgData.count >= 2 {
            let companyId = Int(mfgData[0]) | (Int(mfgData[1]) << 8)
            manufacturerData[companyId] = Array(mfgData.dropFirst(2)).map { Int($0) }
        }

        var serviceData: [String: [Int]] = [:]
        if let svcData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] {
            for (uuid, data) in svcData {
                serviceData[uuid.uuidString.lowercased()] = data.map { Int($0) }
            }
        }

        let result: [String: Any?] = [
            "deviceId": peripheral.identifier.uuidString,
            "name": localName ?? peripheral.name,
            "rssi": RSSI.intValue,
            "timestampMs": Int(Date().timeIntervalSince1970 * 1000),
            "connectable": connectable,
            "serviceUuids": serviceUuids,
            "manufacturerData": manufacturerData,
            "serviceData": serviceData,
            "txPowerLevel": txPower,
        ]

        DispatchQueue.main.async {
            self.scanSink?(result)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        DispatchQueue.main.async {
            self.connectionSink?([
                "deviceId": peripheral.identifier.uuidString,
                "state": 2, // connected
            ])
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        peripherals.removeValue(forKey: peripheral.identifier.uuidString)
        DispatchQueue.main.async {
            self.connectionSink?([
                "deviceId": peripheral.identifier.uuidString,
                "state": 0, // disconnected
                "errorMessage": error?.localizedDescription,
            ])
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        DispatchQueue.main.async {
            self.connectionSink?([
                "deviceId": peripheral.identifier.uuidString,
                "state": 0, // disconnected
                "errorMessage": error?.localizedDescription ?? "Connection failed",
            ])
        }
    }

    // ═══════════════════════════════════════════════════════════
    // CBPeripheralDelegate
    // ═══════════════════════════════════════════════════════════

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let key = "discoverServices:\(peripheral.identifier.uuidString)"
        let result = pendingResults.removeValue(forKey: key)

        if let error = error {
            DispatchQueue.main.async { result?(FlutterError(code: "GATT_ERROR", message: error.localizedDescription, details: nil)) }
            return
        }

        // Discover characteristics for each service
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics(nil, for: service)
        }

        // We need to wait for all characteristics to be discovered
        // For simplicity, collect services after a small delay or track discovery completion
        // Here we'll respond immediately with what we have and let characteristics come via updates
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let services = peripheral.services?.map { service -> [String: Any] in
                let chars = service.characteristics?.map { char -> [String: Any] in
                    let descriptors = char.descriptors?.map { desc -> [String: Any] in
                        return [
                            "uuid": desc.uuid.uuidString.lowercased(),
                            "characteristicUuid": char.uuid.uuidString.lowercased(),
                            "serviceUuid": service.uuid.uuidString.lowercased(),
                        ]
                    } ?? []

                    return [
                        "uuid": char.uuid.uuidString.lowercased(),
                        "serviceUuid": service.uuid.uuidString.lowercased(),
                        "properties": Int(char.properties.rawValue),
                        "descriptors": descriptors,
                    ]
                } ?? []

                return [
                    "uuid": service.uuid.uuidString.lowercased(),
                    "isPrimary": service.isPrimary,
                    "characteristics": chars,
                    "includedServices": [],
                ]
            } ?? []

            result?(services)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        // Discover descriptors for each characteristic
        for characteristic in service.characteristics ?? [] {
            peripheral.discoverDescriptors(for: characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let deviceId = peripheral.identifier.uuidString
        let charUuid = characteristic.uuid.uuidString.lowercased()
        let serviceUuid = characteristic.service?.uuid.uuidString.lowercased() ?? ""

        // Check if this is a pending read result
        let key = "readCharacteristic:\(deviceId):\(charUuid)"
        if let result = pendingResults.removeValue(forKey: key) {
            if let error = error {
                DispatchQueue.main.async { result(FlutterError(code: "GATT_ERROR", message: error.localizedDescription, details: nil)) }
            } else {
                let value = characteristic.value.map { Array($0).map { Int($0) } } ?? []
                DispatchQueue.main.async { result(value) }
            }
            return
        }

        // Otherwise it's a notification
        let value = characteristic.value.map { Array($0).map { Int($0) } } ?? []
        DispatchQueue.main.async {
            self.characteristicSink?([
                "deviceId": deviceId,
                "serviceUuid": serviceUuid,
                "characteristicUuid": charUuid,
                "value": value,
            ])
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        let deviceId = peripheral.identifier.uuidString
        let charUuid = characteristic.uuid.uuidString.lowercased()
        let key = "writeCharacteristic:\(deviceId):\(charUuid)"
        if let result = pendingResults.removeValue(forKey: key) {
            if let error = error {
                DispatchQueue.main.async { result(FlutterError(code: "GATT_ERROR", message: error.localizedDescription, details: nil)) }
            } else {
                DispatchQueue.main.async { result(nil) }
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
        let deviceId = peripheral.identifier.uuidString
        let descUuid = descriptor.uuid.uuidString.lowercased()
        let key = "readDescriptor:\(deviceId):\(descUuid)"
        if let result = pendingResults.removeValue(forKey: key) {
            if let error = error {
                DispatchQueue.main.async { result(FlutterError(code: "GATT_ERROR", message: error.localizedDescription, details: nil)) }
            } else {
                let value: [Int]
                if let data = descriptor.value as? Data {
                    value = Array(data).map { Int($0) }
                } else {
                    value = []
                }
                DispatchQueue.main.async { result(value) }
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        let key = "readRssi:\(peripheral.identifier.uuidString)"
        if let result = pendingResults.removeValue(forKey: key) {
            if let error = error {
                DispatchQueue.main.async { result(FlutterError(code: "GATT_ERROR", message: error.localizedDescription, details: nil)) }
            } else {
                DispatchQueue.main.async { result(RSSI.intValue) }
            }
        }
    }

    @available(iOS 11.0, *)
    func peripheral(_ peripheral: CBPeripheral, didOpen channel: CBL2CAPChannel?, error: Error?) {
        let key = "openL2Cap:\(peripheral.identifier.uuidString)"
        if let result = pendingResults.removeValue(forKey: key) {
            if let error = error {
                DispatchQueue.main.async { result(FlutterError(code: "L2CAP_ERROR", message: error.localizedDescription, details: nil)) }
            } else if let channel = channel {
                let channelId = nextL2CapId
                nextL2CapId += 1
                l2capChannels[channelId] = channel
                // TODO: Set up stream delegate for reading
                DispatchQueue.main.async { result(channelId) }
            } else {
                DispatchQueue.main.async { result(FlutterError(code: "L2CAP_ERROR", message: "Channel is nil", details: nil)) }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════
    // PUBLIC METHODS (called from plugin)
    // ═══════════════════════════════════════════════════════════

    func startScan(withServices: [String]?, allowDuplicates: Bool) {
        var serviceUuids: [CBUUID]? = nil
        if let services = withServices {
            serviceUuids = services.map { CBUUID(string: $0) }
        }
        let options: [String: Any] = [
            CBCentralManagerScanOptionAllowDuplicatesKey: allowDuplicates
        ]
        centralManager.scanForPeripherals(withServices: serviceUuids, options: options)
    }

    func stopScan() {
        centralManager.stopScan()
    }

    func connect(deviceId: String) {
        guard let uuid = UUID(uuidString: deviceId) else { return }
        let peripheralList = centralManager.retrievePeripherals(withIdentifiers: [uuid])
        guard let peripheral = peripheralList.first else { return }
        peripherals[deviceId] = peripheral
        centralManager.connect(peripheral, options: nil)
    }

    func disconnect(deviceId: String) {
        guard let peripheral = peripherals[deviceId] else { return }
        centralManager.cancelPeripheralConnection(peripheral)
    }

    func getConnectedDeviceIds() -> [String] {
        return Array(peripherals.keys)
    }

    func discoverServices(deviceId: String, result: @escaping FlutterResult) {
        guard let peripheral = peripherals[deviceId] else {
            result(FlutterError(code: "NOT_CONNECTED", message: "Device not connected", details: nil))
            return
        }
        pendingResults["discoverServices:\(deviceId)"] = result
        peripheral.discoverServices(nil)
    }

    func readCharacteristic(deviceId: String, serviceUuid: String, charUuid: String, result: @escaping FlutterResult) {
        guard let characteristic = findCharacteristic(deviceId: deviceId, serviceUuid: serviceUuid, charUuid: charUuid) else {
            result(FlutterError(code: "NOT_FOUND", message: "Characteristic not found", details: nil))
            return
        }
        pendingResults["readCharacteristic:\(deviceId):\(charUuid.lowercased())"] = result
        peripherals[deviceId]?.readValue(for: characteristic)
    }

    func writeCharacteristic(deviceId: String, serviceUuid: String, charUuid: String, value: Data, withResponse: Bool, result: @escaping FlutterResult) {
        guard let characteristic = findCharacteristic(deviceId: deviceId, serviceUuid: serviceUuid, charUuid: charUuid) else {
            result(FlutterError(code: "NOT_FOUND", message: "Characteristic not found", details: nil))
            return
        }
        let type: CBCharacteristicWriteType = withResponse ? .withResponse : .withoutResponse
        if withResponse {
            pendingResults["writeCharacteristic:\(deviceId):\(charUuid.lowercased())"] = result
        }
        peripherals[deviceId]?.writeValue(value, for: characteristic, type: type)
        if !withResponse {
            result(nil)
        }
    }

    func setNotification(deviceId: String, serviceUuid: String, charUuid: String, enable: Bool, result: @escaping FlutterResult) {
        guard let characteristic = findCharacteristic(deviceId: deviceId, serviceUuid: serviceUuid, charUuid: charUuid) else {
            result(FlutterError(code: "NOT_FOUND", message: "Characteristic not found", details: nil))
            return
        }
        peripherals[deviceId]?.setNotifyValue(enable, for: characteristic)
        result(nil)
    }

    func readDescriptor(deviceId: String, serviceUuid: String, charUuid: String, descUuid: String, result: @escaping FlutterResult) {
        guard let descriptor = findDescriptor(deviceId: deviceId, serviceUuid: serviceUuid, charUuid: charUuid, descUuid: descUuid) else {
            result(FlutterError(code: "NOT_FOUND", message: "Descriptor not found", details: nil))
            return
        }
        pendingResults["readDescriptor:\(deviceId):\(descUuid.lowercased())"] = result
        peripherals[deviceId]?.readValue(for: descriptor)
    }

    func writeDescriptor(deviceId: String, serviceUuid: String, charUuid: String, descUuid: String, value: Data, result: @escaping FlutterResult) {
        guard let descriptor = findDescriptor(deviceId: deviceId, serviceUuid: serviceUuid, charUuid: charUuid, descUuid: descUuid) else {
            result(FlutterError(code: "NOT_FOUND", message: "Descriptor not found", details: nil))
            return
        }
        peripherals[deviceId]?.writeValue(value, for: descriptor)
        result(nil)
    }

    func getMtu(deviceId: String) -> Int {
        guard let peripheral = peripherals[deviceId] else { return 23 }
        return peripheral.maximumWriteValueLength(for: .withResponse) + 3
    }

    func readRssi(deviceId: String, result: @escaping FlutterResult) {
        guard let peripheral = peripherals[deviceId] else {
            result(FlutterError(code: "NOT_CONNECTED", message: "Device not connected", details: nil))
            return
        }
        pendingResults["readRssi:\(deviceId)"] = result
        peripheral.readRSSI()
    }

    @available(iOS 11.0, *)
    func openL2CapChannel(deviceId: String, psm: UInt16, result: @escaping FlutterResult) {
        guard let peripheral = peripherals[deviceId] else {
            result(FlutterError(code: "NOT_CONNECTED", message: "Device not connected", details: nil))
            return
        }
        pendingResults["openL2Cap:\(deviceId)"] = result
        peripheral.openL2CAPChannel(CBL2CAPPSM(psm))
    }

    func closeL2CapChannel(channelId: Int) {
        if let channel = l2capChannels.removeValue(forKey: channelId) {
            channel.inputStream.close()
            channel.outputStream.close()
        }
    }

    func writeL2Cap(channelId: Int, data: Data, result: @escaping FlutterResult) {
        guard let channel = l2capChannels[channelId] else {
            result(FlutterError(code: "NOT_FOUND", message: "L2CAP channel not found", details: nil))
            return
        }
        data.withUnsafeBytes { buffer in
            let bytes = buffer.bindMemory(to: UInt8.self).baseAddress!
            channel.outputStream.write(bytes, maxLength: data.count)
        }
        result(nil)
    }

    func enableBackground(restorationIdentifier: String) {
        // Reinitialize with restoration identifier
        centralManager = CBCentralManager(
            delegate: self,
            queue: queue,
            options: [CBCentralManagerOptionRestoreIdentifierKey: restorationIdentifier]
        )
    }

    // ═══════════════════════════════════════════════════════════
    // HELPERS
    // ═══════════════════════════════════════════════════════════

    private func findCharacteristic(deviceId: String, serviceUuid: String, charUuid: String) -> CBCharacteristic? {
        guard let peripheral = peripherals[deviceId] else { return nil }
        let service = peripheral.services?.first { $0.uuid.uuidString.lowercased() == serviceUuid.lowercased() }
        return service?.characteristics?.first { $0.uuid.uuidString.lowercased() == charUuid.lowercased() }
    }

    private func findDescriptor(deviceId: String, serviceUuid: String, charUuid: String, descUuid: String) -> CBDescriptor? {
        let characteristic = findCharacteristic(deviceId: deviceId, serviceUuid: serviceUuid, charUuid: charUuid)
        return characteristic?.descriptors?.first { $0.uuid.uuidString.lowercased() == descUuid.lowercased() }
    }

    private func mapState(_ state: CBManagerState) -> Int {
        switch state {
        case .unknown: return 0
        case .resetting: return 0
        case .unsupported: return 1
        case .unauthorized: return 2
        case .poweredOff: return 6
        case .poweredOn: return 4
        @unknown default: return 0
        }
    }
}

// ═══════════════════════════════════════════════════════════
// SIMPLE STREAM HANDLER HELPER
// ═══════════════════════════════════════════════════════════

class SimpleStreamHandler: NSObject, FlutterStreamHandler {
    private let onListenHandler: (FlutterEventSink?) -> Void
    private let onCancelHandler: () -> Void

    init(onListen: @escaping (FlutterEventSink?) -> Void, onCancel: @escaping () -> Void) {
        self.onListenHandler = onListen
        self.onCancelHandler = onCancel
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        onListenHandler(events)
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        onCancelHandler()
        return nil
    }
}

