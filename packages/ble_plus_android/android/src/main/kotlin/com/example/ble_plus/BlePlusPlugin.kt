package com.example.ble_plus

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * BlePlusPlugin - Main entry point for the Android BLE plugin.
 *
 * Delegates to specialized managers:
 * - CentralManager: scanning, connecting, GATT client operations
 * - PeripheralManager: advertising, GATT server operations
 * - ConnectionManager: connection lifecycle, parameters
 * - L2CapManager: L2CAP channel management
 * - BackgroundManager: foreground service for background BLE
 */
class BlePlusPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {

    private lateinit var methodChannel: MethodChannel
    private lateinit var adapterEventChannel: EventChannel
    private lateinit var scanEventChannel: EventChannel
    private lateinit var connectionEventChannel: EventChannel
    private lateinit var characteristicEventChannel: EventChannel
    private lateinit var mtuEventChannel: EventChannel
    private lateinit var peripheralEventChannel: EventChannel
    private lateinit var l2capEventChannel: EventChannel

    private lateinit var context: Context
    private var bluetoothManager: BluetoothManager? = null
    private var bluetoothAdapter: BluetoothAdapter? = null

    private lateinit var centralManager: CentralManager
    private lateinit var peripheralManager: PeripheralManager

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        bluetoothAdapter = bluetoothManager?.adapter

        // Method channel for request/response
        methodChannel = MethodChannel(binding.binaryMessenger, "com.example.ble_plus/methods")
        methodChannel.setMethodCallHandler(this)

        // Event channels for streaming
        adapterEventChannel = EventChannel(binding.binaryMessenger, "com.example.ble_plus/events/adapter")
        scanEventChannel = EventChannel(binding.binaryMessenger, "com.example.ble_plus/events/scan")
        connectionEventChannel = EventChannel(binding.binaryMessenger, "com.example.ble_plus/events/connection")
        characteristicEventChannel = EventChannel(binding.binaryMessenger, "com.example.ble_plus/events/characteristic")
        mtuEventChannel = EventChannel(binding.binaryMessenger, "com.example.ble_plus/events/mtu")
        peripheralEventChannel = EventChannel(binding.binaryMessenger, "com.example.ble_plus/events/peripheral")
        l2capEventChannel = EventChannel(binding.binaryMessenger, "com.example.ble_plus/events/l2cap")

        // Initialize managers
        centralManager = CentralManager(context, bluetoothAdapter)
        peripheralManager = PeripheralManager(context, bluetoothManager)

        // Set up event channel stream handlers
        scanEventChannel.setStreamHandler(centralManager.scanStreamHandler)
        connectionEventChannel.setStreamHandler(centralManager.connectionStreamHandler)
        characteristicEventChannel.setStreamHandler(centralManager.characteristicStreamHandler)
        mtuEventChannel.setStreamHandler(centralManager.mtuStreamHandler)
        peripheralEventChannel.setStreamHandler(peripheralManager.eventStreamHandler)
        adapterEventChannel.setStreamHandler(AdapterStateStreamHandler(context))
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            // ─── Adapter ─────────────────────────────────────
            "requestEnable" -> result.success(bluetoothAdapter?.isEnabled ?: false)

            // ─── Central: Scanning ───────────────────────────
            "startScan" -> {
                val withServices = call.argument<List<String>>("withServices")
                val scanMode = call.argument<Int>("scanMode") ?: 2
                val allowDuplicates = call.argument<Boolean>("allowDuplicates") ?: false
                centralManager.startScan(withServices, scanMode, allowDuplicates)
                result.success(null)
            }
            "stopScan" -> {
                centralManager.stopScan()
                result.success(null)
            }

            // ─── Central: Connection ─────────────────────────
            "connect" -> {
                val deviceId = call.argument<String>("deviceId")!!
                val autoConnect = call.argument<Boolean>("autoConnect") ?: false
                centralManager.connect(deviceId, autoConnect)
                result.success(null)
            }
            "disconnect" -> {
                val deviceId = call.argument<String>("deviceId")!!
                centralManager.disconnect(deviceId)
                result.success(null)
            }
            "getConnectedDevices" -> {
                result.success(centralManager.getConnectedDeviceIds())
            }

            // ─── Central: GATT Operations ────────────────────
            "discoverServices" -> {
                val deviceId = call.argument<String>("deviceId")!!
                centralManager.discoverServices(deviceId, result)
            }
            "readCharacteristic" -> {
                val deviceId = call.argument<String>("deviceId")!!
                val serviceUuid = call.argument<String>("serviceUuid")!!
                val charUuid = call.argument<String>("characteristicUuid")!!
                centralManager.readCharacteristic(deviceId, serviceUuid, charUuid, result)
            }
            "writeCharacteristic" -> {
                val deviceId = call.argument<String>("deviceId")!!
                val serviceUuid = call.argument<String>("serviceUuid")!!
                val charUuid = call.argument<String>("characteristicUuid")!!
                val value = call.argument<List<Int>>("value")!!.map { it.toByte() }.toByteArray()
                val withResponse = call.argument<Boolean>("withResponse") ?: true
                centralManager.writeCharacteristic(deviceId, serviceUuid, charUuid, value, withResponse, result)
            }
            "setNotification" -> {
                val deviceId = call.argument<String>("deviceId")!!
                val serviceUuid = call.argument<String>("serviceUuid")!!
                val charUuid = call.argument<String>("characteristicUuid")!!
                val enable = call.argument<Boolean>("enable") ?: true
                centralManager.setNotification(deviceId, serviceUuid, charUuid, enable, result)
            }
            "readDescriptor" -> {
                val deviceId = call.argument<String>("deviceId")!!
                val serviceUuid = call.argument<String>("serviceUuid")!!
                val charUuid = call.argument<String>("characteristicUuid")!!
                val descUuid = call.argument<String>("descriptorUuid")!!
                centralManager.readDescriptor(deviceId, serviceUuid, charUuid, descUuid, result)
            }
            "writeDescriptor" -> {
                val deviceId = call.argument<String>("deviceId")!!
                val serviceUuid = call.argument<String>("serviceUuid")!!
                val charUuid = call.argument<String>("characteristicUuid")!!
                val descUuid = call.argument<String>("descriptorUuid")!!
                val value = call.argument<List<Int>>("value")!!.map { it.toByte() }.toByteArray()
                centralManager.writeDescriptor(deviceId, serviceUuid, charUuid, descUuid, value, result)
            }

            // ─── Central: MTU ────────────────────────────────
            "requestMtu" -> {
                val deviceId = call.argument<String>("deviceId")!!
                val mtu = call.argument<Int>("mtu")!!
                centralManager.requestMtu(deviceId, mtu, result)
            }

            // ─── Central: RSSI ───────────────────────────────
            "readRssi" -> {
                val deviceId = call.argument<String>("deviceId")!!
                centralManager.readRssi(deviceId, result)
            }

            // ─── Central: Connection Parameters ──────────────
            "requestConnectionPriority" -> {
                val deviceId = call.argument<String>("deviceId")!!
                val priority = call.argument<Int>("priority") ?: 0
                centralManager.requestConnectionPriority(deviceId, priority, result)
            }

            // ─── Central: L2CAP ──────────────────────────────
            "openL2CapChannel" -> {
                val deviceId = call.argument<String>("deviceId")!!
                val psm = call.argument<Int>("psm")!!
                val secure = call.argument<Boolean>("secure") ?: true
                centralManager.openL2CapChannel(deviceId, psm, secure, result)
            }
            "closeL2CapChannel" -> {
                val channelId = call.argument<Int>("channelId")!!
                centralManager.closeL2CapChannel(channelId)
                result.success(null)
            }
            "writeL2Cap" -> {
                val channelId = call.argument<Int>("channelId")!!
                val data = call.argument<List<Int>>("data")!!.map { it.toByte() }.toByteArray()
                centralManager.writeL2Cap(channelId, data, result)
            }

            // ─── Peripheral: Advertising ─────────────────────
            "startAdvertising" -> {
                peripheralManager.startAdvertising(call.arguments as Map<String, Any?>, result)
            }
            "stopAdvertising" -> {
                peripheralManager.stopAdvertising()
                result.success(null)
            }

            // ─── Peripheral: GATT Server ─────────────────────
            "addService" -> {
                peripheralManager.addService(call.arguments as Map<String, Any?>, result)
            }
            "removeService" -> {
                val uuid = call.argument<String>("uuid")!!
                peripheralManager.removeService(uuid)
                result.success(null)
            }
            "removeAllServices" -> {
                peripheralManager.removeAllServices()
                result.success(null)
            }
            "sendNotification" -> {
                val serviceUuid = call.argument<String>("serviceUuid")!!
                val charUuid = call.argument<String>("characteristicUuid")!!
                val value = call.argument<List<Int>>("value")!!.map { it.toByte() }.toByteArray()
                val deviceId = call.argument<String>("deviceId")
                peripheralManager.sendNotification(serviceUuid, charUuid, value, deviceId, result)
            }
            "respondToReadRequest" -> {
                val requestId = call.argument<Int>("requestId")!!
                val value = call.argument<List<Int>>("value")!!.map { it.toByte() }.toByteArray()
                peripheralManager.respondToReadRequest(requestId, value)
                result.success(null)
            }
            "respondToWriteRequest" -> {
                val requestId = call.argument<Int>("requestId")!!
                peripheralManager.respondToWriteRequest(requestId)
                result.success(null)
            }
            "respondWithError" -> {
                val requestId = call.argument<Int>("requestId")!!
                val errorCode = call.argument<Int>("errorCode")!!
                peripheralManager.respondWithError(requestId, errorCode)
                result.success(null)
            }

            // ─── Background ──────────────────────────────────
            "enableBackground" -> {
                // TODO: Start foreground service
                result.success(null)
            }
            "disableBackground" -> {
                // TODO: Stop foreground service
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        centralManager.dispose()
        peripheralManager.dispose()
    }

    // ─── ActivityAware ─────────────────────────────────────────

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        centralManager.setActivity(binding.activity)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        centralManager.setActivity(null)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        centralManager.setActivity(binding.activity)
    }

    override fun onDetachedFromActivity() {
        centralManager.setActivity(null)
    }
}

