package com.example.ble_plus

import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Build
import android.os.ParcelUuid
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.UUID
import android.content.BroadcastReceiver
import android.content.IntentFilter
import java.util.concurrent.ConcurrentHashMap

class BlePlusPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {

    private lateinit var methodChannel: MethodChannel
    private lateinit var scanEventChannel: EventChannel
    private lateinit var connectionEventChannel: EventChannel
    private lateinit var characteristicEventChannel: EventChannel
    private lateinit var bondEventChannel: EventChannel
    private lateinit var peripheralEventChannel: EventChannel

    private lateinit var context: Context
    private var bluetoothManager: BluetoothManager? = null
    private var bluetoothAdapter: BluetoothAdapter? = null
    private var scanner: BluetoothLeScanner? = null
    private var activity: Activity? = null

    // Scan
    private var scanCallback: ScanCallback? = null
    private var scanEventSink: EventChannel.EventSink? = null

    // Connections
    private val connections = ConcurrentHashMap<String, BluetoothGatt>()
    private var connectionEventSink: EventChannel.EventSink? = null
    private var characteristicEventSink: EventChannel.EventSink? = null
    private val pendingResults = ConcurrentHashMap<String, Result>()

    // Bond
    private var bondEventSink: EventChannel.EventSink? = null
    private var bondReceiver: BroadcastReceiver? = null

    // Peripheral
    private lateinit var peripheralManager: PeripheralManager

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        bluetoothAdapter = bluetoothManager?.adapter
        scanner = bluetoothAdapter?.bluetoothLeScanner

        methodChannel = MethodChannel(binding.binaryMessenger, "ble_plus/methods")
        methodChannel.setMethodCallHandler(this)

        scanEventChannel = EventChannel(binding.binaryMessenger, "ble_plus/scan")
        scanEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { scanEventSink = events }
            override fun onCancel(arguments: Any?) { scanEventSink = null }
        })

        connectionEventChannel = EventChannel(binding.binaryMessenger, "ble_plus/connection")
        connectionEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { connectionEventSink = events }
            override fun onCancel(arguments: Any?) { connectionEventSink = null }
        })

        characteristicEventChannel = EventChannel(binding.binaryMessenger, "ble_plus/characteristic")
        characteristicEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { characteristicEventSink = events }
            override fun onCancel(arguments: Any?) { characteristicEventSink = null }
        })

        bondEventChannel = EventChannel(binding.binaryMessenger, "ble_plus/bond")
        bondEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { bondEventSink = events }
            override fun onCancel(arguments: Any?) { bondEventSink = null }
        })

        // Register bond state BroadcastReceiver
        bondReceiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context?, intent: android.content.Intent?) {
                if (intent?.action == BluetoothDevice.ACTION_BOND_STATE_CHANGED) {
                    val device = intent.getParcelableExtra<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE)
                    val bondState = intent.getIntExtra(BluetoothDevice.EXTRA_BOND_STATE, BluetoothDevice.BOND_NONE)
                    val state = when (bondState) {
                        BluetoothDevice.BOND_NONE -> 0
                        BluetoothDevice.BOND_BONDING -> 1
                        BluetoothDevice.BOND_BONDED -> 2
                        else -> 0
                    }
                    bondEventSink?.success(mapOf(
                        "deviceId" to (device?.address ?: ""),
                        "bondState" to state,
                    ))
                }
            }
        }
        val filter = IntentFilter(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
        context.registerReceiver(bondReceiver, filter)

        // Peripheral manager
        peripheralManager = PeripheralManager(context, bluetoothManager)
        peripheralEventChannel = EventChannel(binding.binaryMessenger, "ble_plus/peripheral")
        peripheralEventChannel.setStreamHandler(peripheralManager.eventStreamHandler)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getAdapterState" -> {
                val state = when (bluetoothAdapter?.state) {
                    BluetoothAdapter.STATE_OFF -> 6
                    BluetoothAdapter.STATE_TURNING_ON -> 3
                    BluetoothAdapter.STATE_ON -> 4
                    BluetoothAdapter.STATE_TURNING_OFF -> 5
                    else -> 0
                }
                result.success(state)
            }

            "startScan" -> {
                startScan(call, result)
            }

            "stopScan" -> {
                stopScan()
                result.success(null)
            }

            "connect" -> {
                val deviceId = call.argument<String>("deviceId")!!
                val autoConnect = call.argument<Boolean>("autoConnect") ?: false
                connectDevice(deviceId, autoConnect, result)
            }

            "disconnect" -> {
                val deviceId = call.argument<String>("deviceId")!!
                disconnectDevice(deviceId)
                result.success(null)
            }

            "discoverServices" -> {
                val deviceId = call.argument<String>("deviceId")!!
                discoverServices(deviceId, result)
            }

            "readCharacteristic" -> {
                val deviceId = call.argument<String>("deviceId")!!
                val serviceUuid = call.argument<String>("serviceUuid")!!
                val charUuid = call.argument<String>("characteristicUuid")!!
                readCharacteristic(deviceId, serviceUuid, charUuid, result)
            }

            "writeCharacteristic" -> {
                val deviceId = call.argument<String>("deviceId")!!
                val serviceUuid = call.argument<String>("serviceUuid")!!
                val charUuid = call.argument<String>("characteristicUuid")!!
                val value = (call.argument<List<Int>>("value") ?: emptyList()).map { it.toByte() }.toByteArray()
                val withResponse = call.argument<Boolean>("withResponse") ?: true
                writeCharacteristic(deviceId, serviceUuid, charUuid, value, withResponse, result)
            }

            "setNotification" -> {
                val deviceId = call.argument<String>("deviceId")!!
                val serviceUuid = call.argument<String>("serviceUuid")!!
                val charUuid = call.argument<String>("characteristicUuid")!!
                val enable = call.argument<Boolean>("enable") ?: true
                setNotification(deviceId, serviceUuid, charUuid, enable, result)
            }

            "requestMtu" -> {
                val deviceId = call.argument<String>("deviceId")!!
                val mtu = call.argument<Int>("mtu") ?: 512
                requestMtu(deviceId, mtu, result)
            }

            "readRssi" -> {
                val deviceId = call.argument<String>("deviceId")!!
                readRssi(deviceId, result)
            }

            "getConnectedDevices" -> {
                result.success(connections.keys.toList())
            }

            // ─── Bond / Pair ─────────────────────────────────
            "createBond" -> {
                val deviceId = call.argument<String>("deviceId")!!
                val device = bluetoothAdapter?.getRemoteDevice(deviceId)
                if (device != null) {
                    device.createBond()
                    result.success(null)
                } else {
                    result.error("NOT_FOUND", "Device $deviceId not found", null)
                }
            }

            "removeBond" -> {
                val deviceId = call.argument<String>("deviceId")!!
                val device = bluetoothAdapter?.getRemoteDevice(deviceId)
                if (device != null) {
                    try {
                        // removeBond is hidden API, use reflection
                        val method = device.javaClass.getMethod("removeBond")
                        method.invoke(device)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("BOND_ERROR", "Failed to remove bond: ${e.message}", null)
                    }
                } else {
                    result.error("NOT_FOUND", "Device $deviceId not found", null)
                }
            }

            "getBondState" -> {
                val deviceId = call.argument<String>("deviceId")!!
                val device = bluetoothAdapter?.getRemoteDevice(deviceId)
                val state = when (device?.bondState) {
                    BluetoothDevice.BOND_NONE -> 0
                    BluetoothDevice.BOND_BONDING -> 1
                    BluetoothDevice.BOND_BONDED -> 2
                    else -> 0
                }
                result.success(state)
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
                result.success(null)
            }
            "disableBackground" -> {
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    // ═══════════════════════════════════════════════════════════
    // SCANNING
    // ═══════════════════════════════════════════════════════════

    private fun startScan(call: MethodCall, result: Result) {
        val currentScanner = bluetoothAdapter?.bluetoothLeScanner
        if (currentScanner == null) {
            result.error("UNAVAILABLE", "Bluetooth is not available or turned off", null)
            return
        }
        scanner = currentScanner

        val withServices = call.argument<List<String>>("withServices")
        val scanMode = call.argument<Int>("scanMode") ?: 2

        val settingsBuilder = ScanSettings.Builder()
            .setScanMode(scanMode)

        val filters = withServices?.map { uuid ->
            ScanFilter.Builder()
                .setServiceUuid(ParcelUuid.fromString(uuid))
                .build()
        }

        scanCallback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, scanResult: ScanResult) {
                val device = scanResult.device
                val record = scanResult.scanRecord

                val manufacturerData = mutableMapOf<Int, List<Int>>()
                record?.manufacturerSpecificData?.let { data ->
                    for (i in 0 until data.size()) {
                        val key = data.keyAt(i)
                        val value = data.valueAt(i)
                        manufacturerData[key] = value.map { it.toInt() and 0xFF }
                    }
                }

                val serviceData = mutableMapOf<String, List<Int>>()
                record?.serviceData?.forEach { (uuid, bytes) ->
                    serviceData[uuid.toString()] = bytes.map { it.toInt() and 0xFF }
                }

                val serviceUuids = record?.serviceUuids?.map { it.toString() } ?: emptyList()

                val eventData = mapOf<String, Any?>(
                    "deviceId" to device.address,
                    "name" to (device.name ?: record?.deviceName),
                    "rssi" to scanResult.rssi,
                    "timestampMs" to (scanResult.timestampNanos / 1_000_000),
                    "connectable" to scanResult.isConnectable,
                    "serviceUuids" to serviceUuids,
                    "manufacturerData" to manufacturerData,
                    "serviceData" to serviceData,
                    "txPowerLevel" to record?.txPowerLevel?.let { if (it == Int.MIN_VALUE) null else it }
                )

                activity?.runOnUiThread {
                    scanEventSink?.success(eventData)
                }
            }

            override fun onScanFailed(errorCode: Int) {
                activity?.runOnUiThread {
                    scanEventSink?.error("SCAN_FAILED", "Scan failed with code: $errorCode", errorCode)
                }
            }
        }

        scanner?.startScan(filters, settingsBuilder.build(), scanCallback)
        result.success(null)
    }

    private fun stopScan() {
        scanCallback?.let { scanner?.stopScan(it) }
        scanCallback = null
    }

    // ═══════════════════════════════════════════════════════════
    // CONNECTION
    // ═══════════════════════════════════════════════════════════

    private fun connectDevice(deviceId: String, autoConnect: Boolean, result: Result) {
        val device = bluetoothAdapter?.getRemoteDevice(deviceId)
        if (device == null) {
            result.error("NOT_FOUND", "Device $deviceId not found", null)
            return
        }

        val gatt = device.connectGatt(context, autoConnect, gattCallback, BluetoothDevice.TRANSPORT_LE)
        connections[deviceId] = gatt
        result.success(null)
    }

    private fun disconnectDevice(deviceId: String) {
        connections[deviceId]?.let {
            it.disconnect()
            it.close()
        }
        connections.remove(deviceId)
    }

    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            val deviceId = gatt.device.address
            val state = when (newState) {
                BluetoothProfile.STATE_CONNECTED -> 2
                BluetoothProfile.STATE_DISCONNECTED -> 0
                else -> 0
            }

            activity?.runOnUiThread {
                connectionEventSink?.success(mapOf(
                    "deviceId" to deviceId,
                    "state" to state,
                    "errorCode" to if (status != BluetoothGatt.GATT_SUCCESS) status else null,
                    "errorMessage" to if (status != BluetoothGatt.GATT_SUCCESS) "GATT error: $status" else null,
                ))
            }

            if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                gatt.close()
                connections.remove(deviceId)
            }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            val deviceId = gatt.device.address
            val result = pendingResults.remove("discoverServices:$deviceId") ?: return

            if (status != BluetoothGatt.GATT_SUCCESS) {
                activity?.runOnUiThread { result.error("GATT_ERROR", "Service discovery failed: $status", null) }
                return
            }

            val services = gatt.services.map { service ->
                mapOf(
                    "uuid" to service.uuid.toString(),
                    "isPrimary" to (service.type == BluetoothGattService.SERVICE_TYPE_PRIMARY),
                    "characteristics" to service.characteristics.map { char ->
                        mapOf(
                            "uuid" to char.uuid.toString(),
                            "serviceUuid" to service.uuid.toString(),
                            "properties" to char.properties,
                            "descriptors" to char.descriptors.map { desc ->
                                mapOf(
                                    "uuid" to desc.uuid.toString(),
                                    "characteristicUuid" to char.uuid.toString(),
                                    "serviceUuid" to service.uuid.toString(),
                                )
                            }
                        )
                    },
                    "includedServices" to emptyList<Any>()
                )
            }
            activity?.runOnUiThread { result.success(services) }
        }

        override fun onCharacteristicRead(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, value: ByteArray, status: Int) {
            val deviceId = gatt.device.address
            val key = "readChar:$deviceId:${characteristic.uuid}"
            val result = pendingResults.remove(key)
            activity?.runOnUiThread {
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    result?.success(value.map { it.toInt() and 0xFF })
                } else {
                    result?.error("GATT_ERROR", "Read failed: $status", null)
                }
            }
        }

        override fun onCharacteristicWrite(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {
            val deviceId = gatt.device.address
            val key = "writeChar:$deviceId:${characteristic.uuid}"
            val result = pendingResults.remove(key)
            activity?.runOnUiThread {
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    result?.success(null)
                } else {
                    result?.error("GATT_ERROR", "Write failed: $status", null)
                }
            }
        }

        override fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, value: ByteArray) {
            val deviceId = gatt.device.address
            activity?.runOnUiThread {
                characteristicEventSink?.success(mapOf(
                    "deviceId" to deviceId,
                    "serviceUuid" to characteristic.service.uuid.toString(),
                    "characteristicUuid" to characteristic.uuid.toString(),
                    "value" to value.map { it.toInt() and 0xFF },
                ))
            }
        }

        override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
            val deviceId = gatt.device.address
            val result = pendingResults.remove("mtu:$deviceId")
            activity?.runOnUiThread {
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    result?.success(mtu)
                } else {
                    result?.success(23) // fallback
                }
            }
        }

        override fun onReadRemoteRssi(gatt: BluetoothGatt, rssi: Int, status: Int) {
            val deviceId = gatt.device.address
            val result = pendingResults.remove("rssi:$deviceId")
            activity?.runOnUiThread {
                result?.success(rssi)
            }
        }
    }

    // ═══════════════════════════════════════════════════════════
    // GATT OPERATIONS
    // ═══════════════════════════════════════════════════════════

    private fun discoverServices(deviceId: String, result: Result) {
        val gatt = connections[deviceId]
        if (gatt == null) { result.error("NOT_CONNECTED", "Not connected to $deviceId", null); return }
        pendingResults["discoverServices:$deviceId"] = result
        gatt.discoverServices()
    }

    private fun readCharacteristic(deviceId: String, serviceUuid: String, charUuid: String, result: Result) {
        val char = findCharacteristic(deviceId, serviceUuid, charUuid)
        if (char == null) { result.error("NOT_FOUND", "Characteristic $charUuid not found", null); return }
        pendingResults["readChar:$deviceId:${char.uuid}"] = result
        connections[deviceId]?.readCharacteristic(char)
    }

    private fun writeCharacteristic(deviceId: String, serviceUuid: String, charUuid: String, value: ByteArray, withResponse: Boolean, result: Result) {
        val gatt = connections[deviceId]
        val char = findCharacteristic(deviceId, serviceUuid, charUuid)
        if (gatt == null || char == null) { result.error("NOT_FOUND", "Not connected or char not found", null); return }

        val writeType = if (withResponse) BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT else BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
        pendingResults["writeChar:$deviceId:${char.uuid}"] = result

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            gatt.writeCharacteristic(char, value, writeType)
        } else {
            @Suppress("DEPRECATION")
            char.writeType = writeType
            @Suppress("DEPRECATION")
            char.value = value
            @Suppress("DEPRECATION")
            gatt.writeCharacteristic(char)
        }
    }

    private fun setNotification(deviceId: String, serviceUuid: String, charUuid: String, enable: Boolean, result: Result) {
        val gatt = connections[deviceId]
        val char = findCharacteristic(deviceId, serviceUuid, charUuid)
        if (gatt == null || char == null) { result.error("NOT_FOUND", "Not connected or char not found", null); return }

        gatt.setCharacteristicNotification(char, enable)

        // Write CCCD
        val cccd = char.getDescriptor(UUID.fromString("00002902-0000-1000-8000-00805f9b34fb"))
        if (cccd != null) {
            val value = if (enable) {
                if (char.properties and BluetoothGattCharacteristic.PROPERTY_INDICATE != 0)
                    BluetoothGattDescriptor.ENABLE_INDICATION_VALUE
                else
                    BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
            } else {
                BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                gatt.writeDescriptor(cccd, value)
            } else {
                @Suppress("DEPRECATION")
                cccd.value = value
                @Suppress("DEPRECATION")
                gatt.writeDescriptor(cccd)
            }
        }
        result.success(null)
    }

    private fun requestMtu(deviceId: String, mtu: Int, result: Result) {
        val gatt = connections[deviceId]
        if (gatt == null) { result.error("NOT_CONNECTED", "Not connected", null); return }
        pendingResults["mtu:$deviceId"] = result
        gatt.requestMtu(mtu)
    }

    private fun readRssi(deviceId: String, result: Result) {
        val gatt = connections[deviceId]
        if (gatt == null) { result.error("NOT_CONNECTED", "Not connected", null); return }
        pendingResults["rssi:$deviceId"] = result
        gatt.readRemoteRssi()
    }

    private fun findCharacteristic(deviceId: String, serviceUuid: String, charUuid: String): BluetoothGattCharacteristic? {
        val gatt = connections[deviceId] ?: return null
        val service = gatt.getService(UUID.fromString(serviceUuid)) ?: return null
        return service.getCharacteristic(UUID.fromString(charUuid))
    }

    // ═══════════════════════════════════════════════════════════
    // LIFECYCLE
    // ═══════════════════════════════════════════════════════════

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        stopScan()
        connections.values.forEach { it.disconnect(); it.close() }
        connections.clear()
        peripheralManager.dispose()
        try {
            bondReceiver?.let { context.unregisterReceiver(it) }
        } catch (_: Exception) {}
        bondReceiver = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivityForConfigChanges() { activity = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivity() { activity = null }
}
