import Flutter
import UIKit
import CoreBluetooth

/// Main plugin entry point for iOS.
/// Delegates to CentralManager and PeripheralManager.
public class BlePlusPlugin: NSObject, FlutterPlugin {

    private var centralManager: CentralManagerHandler?
    private var peripheralManager: PeripheralManagerHandler?
    private var methodChannel: FlutterMethodChannel?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = BlePlusPlugin()
        let messenger = registrar.messenger()

        // Method channel
        let methodChannel = FlutterMethodChannel(name: "com.example.ble_plus/methods", binaryMessenger: messenger)
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        instance.methodChannel = methodChannel

        // Event channels
        let adapterChannel = FlutterEventChannel(name: "com.example.ble_plus/events/adapter", binaryMessenger: messenger)
        let scanChannel = FlutterEventChannel(name: "com.example.ble_plus/events/scan", binaryMessenger: messenger)
        let connectionChannel = FlutterEventChannel(name: "com.example.ble_plus/events/connection", binaryMessenger: messenger)
        let characteristicChannel = FlutterEventChannel(name: "com.example.ble_plus/events/characteristic", binaryMessenger: messenger)
        let mtuChannel = FlutterEventChannel(name: "com.example.ble_plus/events/mtu", binaryMessenger: messenger)
        let peripheralChannel = FlutterEventChannel(name: "com.example.ble_plus/events/peripheral", binaryMessenger: messenger)
        let l2capChannel = FlutterEventChannel(name: "com.example.ble_plus/events/l2cap", binaryMessenger: messenger)

        // Initialize managers
        let central = CentralManagerHandler()
        let peripheral = PeripheralManagerHandler()
        instance.centralManager = central
        instance.peripheralManager = peripheral

        // Set stream handlers
        adapterChannel.setStreamHandler(central.adapterStreamHandler)
        scanChannel.setStreamHandler(central.scanStreamHandler)
        connectionChannel.setStreamHandler(central.connectionStreamHandler)
        characteristicChannel.setStreamHandler(central.characteristicStreamHandler)
        mtuChannel.setStreamHandler(central.mtuStreamHandler)
        peripheralChannel.setStreamHandler(peripheral.eventStreamHandler)
        l2capChannel.setStreamHandler(central.l2capStreamHandler)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]

        switch call.method {

        // ─── Central: Scanning ───────────────────────────
        case "startScan":
            let withServices = args?["withServices"] as? [String]
            let allowDuplicates = args?["allowDuplicates"] as? Bool ?? false
            centralManager?.startScan(withServices: withServices, allowDuplicates: allowDuplicates)
            result(nil)

        case "stopScan":
            centralManager?.stopScan()
            result(nil)

        // ─── Central: Connection ─────────────────────────
        case "connect":
            guard let deviceId = args?["deviceId"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "deviceId required", details: nil))
                return
            }
            centralManager?.connect(deviceId: deviceId)
            result(nil)

        case "disconnect":
            guard let deviceId = args?["deviceId"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "deviceId required", details: nil))
                return
            }
            centralManager?.disconnect(deviceId: deviceId)
            result(nil)

        case "getConnectedDevices":
            result(centralManager?.getConnectedDeviceIds() ?? [])

        // ─── Central: GATT ───────────────────────────────
        case "discoverServices":
            guard let deviceId = args?["deviceId"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "deviceId required", details: nil))
                return
            }
            centralManager?.discoverServices(deviceId: deviceId, result: result)

        case "readCharacteristic":
            guard let deviceId = args?["deviceId"] as? String,
                  let serviceUuid = args?["serviceUuid"] as? String,
                  let charUuid = args?["characteristicUuid"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing args", details: nil))
                return
            }
            centralManager?.readCharacteristic(deviceId: deviceId, serviceUuid: serviceUuid, charUuid: charUuid, result: result)

        case "writeCharacteristic":
            guard let deviceId = args?["deviceId"] as? String,
                  let serviceUuid = args?["serviceUuid"] as? String,
                  let charUuid = args?["characteristicUuid"] as? String,
                  let value = args?["value"] as? [Int],
                  let withResponse = args?["withResponse"] as? Bool else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing args", details: nil))
                return
            }
            let data = Data(value.map { UInt8($0 & 0xFF) })
            centralManager?.writeCharacteristic(deviceId: deviceId, serviceUuid: serviceUuid, charUuid: charUuid, value: data, withResponse: withResponse, result: result)

        case "setNotification":
            guard let deviceId = args?["deviceId"] as? String,
                  let serviceUuid = args?["serviceUuid"] as? String,
                  let charUuid = args?["characteristicUuid"] as? String,
                  let enable = args?["enable"] as? Bool else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing args", details: nil))
                return
            }
            centralManager?.setNotification(deviceId: deviceId, serviceUuid: serviceUuid, charUuid: charUuid, enable: enable, result: result)

        case "readDescriptor":
            guard let deviceId = args?["deviceId"] as? String,
                  let serviceUuid = args?["serviceUuid"] as? String,
                  let charUuid = args?["characteristicUuid"] as? String,
                  let descUuid = args?["descriptorUuid"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing args", details: nil))
                return
            }
            centralManager?.readDescriptor(deviceId: deviceId, serviceUuid: serviceUuid, charUuid: charUuid, descUuid: descUuid, result: result)

        case "writeDescriptor":
            guard let deviceId = args?["deviceId"] as? String,
                  let serviceUuid = args?["serviceUuid"] as? String,
                  let charUuid = args?["characteristicUuid"] as? String,
                  let descUuid = args?["descriptorUuid"] as? String,
                  let value = args?["value"] as? [Int] else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing args", details: nil))
                return
            }
            let data = Data(value.map { UInt8($0 & 0xFF) })
            centralManager?.writeDescriptor(deviceId: deviceId, serviceUuid: serviceUuid, charUuid: charUuid, descUuid: descUuid, value: data, result: result)

        // ─── MTU / RSSI ──────────────────────────────────
        case "getMtu":
            guard let deviceId = args?["deviceId"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "deviceId required", details: nil))
                return
            }
            result(centralManager?.getMtu(deviceId: deviceId) ?? 185)

        case "readRssi":
            guard let deviceId = args?["deviceId"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "deviceId required", details: nil))
                return
            }
            centralManager?.readRssi(deviceId: deviceId, result: result)

        // ─── L2CAP ───────────────────────────────────────
        case "openL2CapChannel":
            guard let deviceId = args?["deviceId"] as? String,
                  let psm = args?["psm"] as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing args", details: nil))
                return
            }
            centralManager?.openL2CapChannel(deviceId: deviceId, psm: UInt16(psm), result: result)

        case "closeL2CapChannel":
            let channelId = args?["channelId"] as? Int ?? -1
            centralManager?.closeL2CapChannel(channelId: channelId)
            result(nil)

        case "writeL2Cap":
            guard let channelId = args?["channelId"] as? Int,
                  let data = args?["data"] as? [Int] else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing args", details: nil))
                return
            }
            centralManager?.writeL2Cap(channelId: channelId, data: Data(data.map { UInt8($0 & 0xFF) }), result: result)

        // ─── Peripheral ──────────────────────────────────
        case "startAdvertising":
            peripheralManager?.startAdvertising(args: args ?? [:], result: result)

        case "stopAdvertising":
            peripheralManager?.stopAdvertising()
            result(nil)

        case "addService":
            peripheralManager?.addService(args: args ?? [:], result: result)

        case "removeService":
            guard let uuid = args?["uuid"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "uuid required", details: nil))
                return
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
                result(FlutterError(code: "INVALID_ARGS", message: "Missing args", details: nil))
                return
            }
            let deviceId = args?["deviceId"] as? String
            let data = Data(value.map { UInt8($0 & 0xFF) })
            peripheralManager?.sendNotification(serviceUuid: serviceUuid, charUuid: charUuid, value: data, deviceId: deviceId, result: result)

        case "respondToReadRequest":
            guard let requestId = args?["requestId"] as? Int,
                  let value = args?["value"] as? [Int] else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing args", details: nil))
                return
            }
            peripheralManager?.respondToReadRequest(requestId: requestId, value: Data(value.map { UInt8($0 & 0xFF) }))
            result(nil)

        case "respondToWriteRequest":
            guard let requestId = args?["requestId"] as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "requestId required", details: nil))
                return
            }
            peripheralManager?.respondToWriteRequest(requestId: requestId)
            result(nil)

        case "respondWithError":
            guard let requestId = args?["requestId"] as? Int,
                  let errorCode = args?["errorCode"] as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing args", details: nil))
                return
            }
            peripheralManager?.respondWithError(requestId: requestId, errorCode: errorCode)
            result(nil)

        // ─── L2CAP Server ────────────────────────────────
        case "publishL2CapChannel":
            let secure = args?["secure"] as? Bool ?? true
            peripheralManager?.publishL2CapChannel(secure: secure, result: result)

        case "unpublishL2CapChannel":
            peripheralManager?.unpublishL2CapChannel()
            result(nil)

        // ─── Background ──────────────────────────────────
        case "enableBackground":
            let identifier = args?["iosRestorationIdentifier"] as? String ?? "ble_plus_central"
            centralManager?.enableBackground(restorationIdentifier: identifier)
            result(nil)

        case "disableBackground":
            result(nil) // No-op on iOS; restoration is set at init time

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

