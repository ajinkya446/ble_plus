import Cocoa
import FlutterMacOS
import CoreBluetooth

/// Main plugin entry point for macOS.
public class BlePlusPlugin: NSObject, FlutterPlugin {

    private var centralManager: CentralManagerHandler?
    private var peripheralManager: PeripheralManagerHandler?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = BlePlusPlugin()
        let messenger = registrar.messenger

        let methodChannel = FlutterMethodChannel(name: "ble_plus/methods", binaryMessenger: messenger)
        registrar.addMethodCallDelegate(instance, channel: methodChannel)

        let scanChannel = FlutterEventChannel(name: "ble_plus/scan", binaryMessenger: messenger)
        let connectionChannel = FlutterEventChannel(name: "ble_plus/connection", binaryMessenger: messenger)
        let characteristicChannel = FlutterEventChannel(name: "ble_plus/characteristic", binaryMessenger: messenger)
        let peripheralChannel = FlutterEventChannel(name: "ble_plus/peripheral", binaryMessenger: messenger)

        let central = CentralManagerHandler()
        let peripheral = PeripheralManagerHandler()
        instance.centralManager = central
        instance.peripheralManager = peripheral

        scanChannel.setStreamHandler(central.scanStreamHandler)
        connectionChannel.setStreamHandler(central.connectionStreamHandler)
        characteristicChannel.setStreamHandler(central.characteristicStreamHandler)
        peripheralChannel.setStreamHandler(peripheral.eventStreamHandler)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]

        switch call.method {

        case "getAdapterState":
            result(centralManager?.currentAdapterState() ?? 0)

        case "startScan":
            let withServices = args?["withServices"] as? [String]
            let allowDuplicates = args?["allowDuplicates"] as? Bool ?? false
            centralManager?.startScan(withServices: withServices, allowDuplicates: allowDuplicates)
            result(nil)

        case "stopScan":
            centralManager?.stopScan()
            result(nil)

        case "connect":
            guard let deviceId = args?["deviceId"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "deviceId required", details: nil)); return
            }
            centralManager?.connect(deviceId: deviceId)
            result(nil)

        case "disconnect":
            guard let deviceId = args?["deviceId"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "deviceId required", details: nil)); return
            }
            centralManager?.disconnect(deviceId: deviceId)
            result(nil)

        case "getConnectedDevices":
            result(centralManager?.getConnectedDeviceIds() ?? [])

        // ─── Central: Bond / Pair ────────────────────────
        case "createBond":
            result(nil) // macOS handles pairing automatically

        case "removeBond":
            result(FlutterError(code: "UNSUPPORTED", message: "macOS does not support programmatic bond removal", details: nil))

        case "getBondState":
            result(0) // macOS auto-manages bonding

        case "discoverServices":
            guard let deviceId = args?["deviceId"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "deviceId required", details: nil)); return
            }
            centralManager?.discoverServices(deviceId: deviceId, result: result)

        case "readCharacteristic":
            guard let deviceId = args?["deviceId"] as? String,
                  let serviceUuid = args?["serviceUuid"] as? String,
                  let charUuid = args?["characteristicUuid"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing args", details: nil)); return
            }
            centralManager?.readCharacteristic(deviceId: deviceId, serviceUuid: serviceUuid, charUuid: charUuid, result: result)

        case "writeCharacteristic":
            guard let deviceId = args?["deviceId"] as? String,
                  let serviceUuid = args?["serviceUuid"] as? String,
                  let charUuid = args?["characteristicUuid"] as? String,
                  let value = args?["value"] as? [Int],
                  let withResponse = args?["withResponse"] as? Bool else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing args", details: nil)); return
            }
            centralManager?.writeCharacteristic(deviceId: deviceId, serviceUuid: serviceUuid, charUuid: charUuid, value: Data(value.map { UInt8($0 & 0xFF) }), withResponse: withResponse, result: result)

        case "setNotification":
            guard let deviceId = args?["deviceId"] as? String,
                  let serviceUuid = args?["serviceUuid"] as? String,
                  let charUuid = args?["characteristicUuid"] as? String,
                  let enable = args?["enable"] as? Bool else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing args", details: nil)); return
            }
            centralManager?.setNotification(deviceId: deviceId, serviceUuid: serviceUuid, charUuid: charUuid, enable: enable, result: result)

        case "readDescriptor":
            guard let deviceId = args?["deviceId"] as? String,
                  let serviceUuid = args?["serviceUuid"] as? String,
                  let charUuid = args?["characteristicUuid"] as? String,
                  let descUuid = args?["descriptorUuid"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing args", details: nil)); return
            }
            centralManager?.readDescriptor(deviceId: deviceId, serviceUuid: serviceUuid, charUuid: charUuid, descUuid: descUuid, result: result)

        case "writeDescriptor":
            guard let deviceId = args?["deviceId"] as? String,
                  let serviceUuid = args?["serviceUuid"] as? String,
                  let charUuid = args?["characteristicUuid"] as? String,
                  let descUuid = args?["descriptorUuid"] as? String,
                  let value = args?["value"] as? [Int] else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing args", details: nil)); return
            }
            centralManager?.writeDescriptor(deviceId: deviceId, serviceUuid: serviceUuid, charUuid: charUuid, descUuid: descUuid, value: Data(value.map { UInt8($0 & 0xFF) }), result: result)

        case "requestMtu":
            guard let deviceId = args?["deviceId"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "deviceId required", details: nil)); return
            }
            result(centralManager?.getMtu(deviceId: deviceId) ?? 185)

        case "readRssi":
            guard let deviceId = args?["deviceId"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "deviceId required", details: nil)); return
            }
            centralManager?.readRssi(deviceId: deviceId, result: result)

        case "openL2CapChannel":
            guard let deviceId = args?["deviceId"] as? String,
                  let psm = args?["psm"] as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing args", details: nil)); return
            }
            if #available(macOS 10.14, *) {
                centralManager?.openL2CapChannel(deviceId: deviceId, psm: UInt16(psm), result: result)
            } else {
                result(FlutterError(code: "UNSUPPORTED", message: "L2CAP requires macOS 10.14+", details: nil))
            }

        case "closeL2CapChannel":
            centralManager?.closeL2CapChannel(channelId: args?["channelId"] as? Int ?? -1)
            result(nil)

        case "writeL2Cap":
            guard let channelId = args?["channelId"] as? Int,
                  let data = args?["data"] as? [Int] else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing args", details: nil)); return
            }
            centralManager?.writeL2Cap(channelId: channelId, data: Data(data.map { UInt8($0 & 0xFF) }), result: result)

        case "startAdvertising":
            peripheralManager?.startAdvertising(args: args ?? [:], result: result)

        case "stopAdvertising":
            peripheralManager?.stopAdvertising()
            result(nil)

        case "addService":
            peripheralManager?.addService(args: args ?? [:], result: result)

        case "removeService":
            guard let uuid = args?["uuid"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "uuid required", details: nil)); return
            }
            peripheralManager?.removeService(uuid: uuid)
            result(nil)

        case "removeAllServices":
            peripheralManager?.removeAllServices()
            result(nil)

        case "sendNotification":
            guard let serviceUuid = args?["serviceUuid"] as? String,
                  let charUuid = args?["characteristicUuid"] as? String,
                  let value = args?["value"] as? [Int] else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing args", details: nil)); return
            }
            peripheralManager?.sendNotification(serviceUuid: serviceUuid, charUuid: charUuid, value: Data(value.map { UInt8($0 & 0xFF) }), deviceId: args?["deviceId"] as? String, result: result)

        case "respondToReadRequest":
            guard let requestId = args?["requestId"] as? Int,
                  let value = args?["value"] as? [Int] else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing args", details: nil)); return
            }
            peripheralManager?.respondToReadRequest(requestId: requestId, value: Data(value.map { UInt8($0 & 0xFF) }))
            result(nil)

        case "respondToWriteRequest":
            guard let requestId = args?["requestId"] as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "requestId required", details: nil)); return
            }
            peripheralManager?.respondToWriteRequest(requestId: requestId)
            result(nil)

        case "respondWithError":
            guard let requestId = args?["requestId"] as? Int,
                  let errorCode = args?["errorCode"] as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing args", details: nil)); return
            }
            peripheralManager?.respondWithError(requestId: requestId, errorCode: errorCode)
            result(nil)

        case "publishL2CapChannel":
            let secure = args?["secure"] as? Bool ?? true
            if #available(macOS 10.14, *) {
                peripheralManager?.publishL2CapChannel(secure: secure, result: result)
            } else {
                result(FlutterError(code: "UNSUPPORTED", message: "L2CAP requires macOS 10.14+", details: nil))
            }

        case "unpublishL2CapChannel":
            peripheralManager?.unpublishL2CapChannel()
            result(nil)

        case "enableBackground":
            result(nil) // macOS doesn't support background restoration the same way

        case "disableBackground":
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
