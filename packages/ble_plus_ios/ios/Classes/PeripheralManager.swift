import Foundation
import CoreBluetooth

/// Manages BLE Peripheral (Server) role on iOS via CoreBluetooth.
class PeripheralManagerHandler: NSObject, CBPeripheralManagerDelegate {

    private var peripheralManager: CBPeripheralManager!
    private let queue = DispatchQueue(label: "com.example.ble_plus.peripheral", qos: .userInitiated)

    // Event sink
    private var eventSink: FlutterEventSink?

    // Services and characteristics we've added
    private var services: [CBUUID: CBMutableService] = [:]
    private var characteristics: [CBUUID: CBMutableCharacteristic] = [:]

    // Subscribed centrals per characteristic
    private var subscribedCentrals: [CBUUID: [CBCentral]] = [:]

    // Pending requests
    private var pendingATTRequests: [Int: CBATTRequest] = [:]
    private var nextRequestId = 0

    lazy var eventStreamHandler = SimpleStreamHandler { [weak self] sink in
        self?.eventSink = sink
    } onCancel: { [weak self] in
        self?.eventSink = nil
    }

    override init() {
        super.init()
        peripheralManager = CBPeripheralManager(delegate: self, queue: queue)
    }

    // ═══════════════════════════════════════════════════════════
    // CBPeripheralManagerDelegate
    // ═══════════════════════════════════════════════════════════

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        // Peripheral manager state updated
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        // Advertising started/failed — handled via result callback
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        let requestId = nextRequestId
        nextRequestId += 1
        pendingATTRequests[requestId] = request

        DispatchQueue.main.async {
            self.eventSink?([
                "type": "readRequest",
                "requestId": requestId,
                "deviceId": request.central.identifier.uuidString,
                "serviceUuid": request.characteristic.service?.uuid.uuidString.lowercased() ?? "",
                "characteristicUuid": request.characteristic.uuid.uuidString.lowercased(),
                "offset": request.offset,
            ])
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            let requestId = nextRequestId
            nextRequestId += 1
            pendingATTRequests[requestId] = request

            DispatchQueue.main.async {
                self.eventSink?([
                    "type": "writeRequest",
                    "requestId": requestId,
                    "deviceId": request.central.identifier.uuidString,
                    "serviceUuid": request.characteristic.service?.uuid.uuidString.lowercased() ?? "",
                    "characteristicUuid": request.characteristic.uuid.uuidString.lowercased(),
                    "value": request.value.map { Array($0).map { Int($0) } } ?? [],
                    "offset": request.offset,
                    "responseNeeded": true,
                ])
            }
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        let uuid = characteristic.uuid
        if subscribedCentrals[uuid] == nil {
            subscribedCentrals[uuid] = []
        }
        subscribedCentrals[uuid]?.append(central)

        DispatchQueue.main.async {
            self.eventSink?([
                "type": "subscriptionChange",
                "deviceId": central.identifier.uuidString,
                "serviceUuid": characteristic.service?.uuid.uuidString.lowercased() ?? "",
                "characteristicUuid": uuid.uuidString.lowercased(),
                "isSubscribed": true,
            ])
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        let uuid = characteristic.uuid
        subscribedCentrals[uuid]?.removeAll { $0.identifier == central.identifier }

        DispatchQueue.main.async {
            self.eventSink?([
                "type": "subscriptionChange",
                "deviceId": central.identifier.uuidString,
                "serviceUuid": characteristic.service?.uuid.uuidString.lowercased() ?? "",
                "characteristicUuid": uuid.uuidString.lowercased(),
                "isSubscribed": false,
            ])
        }
    }

    @available(iOS 11.0, *)
    func peripheralManager(_ peripheral: CBPeripheralManager, didPublishL2CAPChannel PSM: CBL2CAPPSM, error: Error?) {
        // L2CAP channel published
    }

    // ═══════════════════════════════════════════════════════════
    // PUBLIC METHODS
    // ═══════════════════════════════════════════════════════════

    func startAdvertising(args: [String: Any], result: @escaping FlutterResult) {
        var advertisementData: [String: Any] = [:]

        if let localName = args["localName"] as? String {
            advertisementData[CBAdvertisementDataLocalNameKey] = localName
        }

        if let serviceUuids = args["serviceUuids"] as? [String], !serviceUuids.isEmpty {
            advertisementData[CBAdvertisementDataServiceUUIDsKey] = serviceUuids.map { CBUUID(string: $0) }
        }

        peripheralManager.startAdvertising(advertisementData)
        result(nil)
    }

    func stopAdvertising() {
        peripheralManager.stopAdvertising()
    }

    func addService(args: [String: Any], result: @escaping FlutterResult) {
        guard let uuidStr = args["uuid"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "uuid required", details: nil))
            return
        }

        let isPrimary = args["isPrimary"] as? Bool ?? true
        let uuid = CBUUID(string: uuidStr)
        let service = CBMutableService(type: uuid, primary: isPrimary)

        var mutableChars: [CBMutableCharacteristic] = []

        if let chars = args["characteristics"] as? [[String: Any]] {
            for charArgs in chars {
                guard let charUuidStr = charArgs["uuid"] as? String else { continue }
                let charUuid = CBUUID(string: charUuidStr)
                let properties = CBCharacteristicProperties(rawValue: UInt(charArgs["properties"] as? Int ?? 0))
                let permissions = CBAttributePermissions(rawValue: UInt(charArgs["permissions"] as? Int ?? 0))

                var initialValue: Data? = nil
                if let values = charArgs["initialValue"] as? [Int] {
                    initialValue = Data(values.map { UInt8($0 & 0xFF) })
                }

                // If characteristic has notify/indicate, value must be nil (dynamic)
                let hasNotify = properties.contains(.notify) || properties.contains(.indicate)
                let characteristic = CBMutableCharacteristic(
                    type: charUuid,
                    properties: properties,
                    value: hasNotify ? nil : initialValue,
                    permissions: permissions
                )

                characteristics[charUuid] = characteristic
                mutableChars.append(characteristic)
            }
        }

        service.characteristics = mutableChars
        services[uuid] = service
        peripheralManager.add(service)
        result(nil)
    }

    func removeService(uuid: String) {
        let cbUuid = CBUUID(string: uuid)
        if let service = services.removeValue(forKey: cbUuid) {
            peripheralManager.remove(service)
        }
    }

    func removeAllServices() {
        peripheralManager.removeAllServices()
        services.removeAll()
        characteristics.removeAll()
    }

    func sendNotification(serviceUuid: String, charUuid: String, value: Data, deviceId: String?, result: @escaping FlutterResult) {
        let uuid = CBUUID(string: charUuid)
        guard let characteristic = characteristics[uuid] else {
            result(FlutterError(code: "NOT_FOUND", message: "Characteristic not found", details: nil))
            return
        }

        var centrals: [CBCentral]?
        if let deviceId = deviceId {
            centrals = subscribedCentrals[uuid]?.filter { $0.identifier.uuidString == deviceId }
        }

        let success = peripheralManager.updateValue(value, for: characteristic, onSubscribedCentrals: centrals)
        if success {
            result(nil)
        } else {
            // Queue is full, need to wait for peripheralManagerIsReady(toUpdateSubscribers:)
            result(FlutterError(code: "QUEUE_FULL", message: "Notification queue is full", details: nil))
        }
    }

    func respondToReadRequest(requestId: Int, value: Data) {
        guard let request = pendingATTRequests.removeValue(forKey: requestId) else { return }
        request.value = value
        peripheralManager.respond(to: request, withResult: .success)
    }

    func respondToWriteRequest(requestId: Int) {
        guard let request = pendingATTRequests.removeValue(forKey: requestId) else { return }
        peripheralManager.respond(to: request, withResult: .success)
    }

    func respondWithError(requestId: Int, errorCode: Int) {
        guard let request = pendingATTRequests.removeValue(forKey: requestId) else { return }
        let attError = CBATTError.Code(rawValue: errorCode) ?? .unlikelyError
        peripheralManager.respond(to: request, withResult: attError)
    }

    @available(iOS 11.0, *)
    func publishL2CapChannel(secure: Bool, result: @escaping FlutterResult) {
        peripheralManager.publishL2CAPChannel(withEncryption: secure)
        result(nil) // PSM will come via delegate callback
    }

    func unpublishL2CapChannel() {
        if #available(iOS 11.0, *) {
            // Would need to track PSM to unpublish
        }
    }
}

