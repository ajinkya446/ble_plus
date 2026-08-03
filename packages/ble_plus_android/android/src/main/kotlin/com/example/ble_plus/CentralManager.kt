package com.example.ble_plus

import android.app.Activity
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.os.Build
import android.os.ParcelUuid
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel.Result
import java.util.*
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Semaphore

/**
 * Manages BLE Central role operations:
 * - Scanning for peripherals
 * - Connecting to devices
 * - GATT client operations (discover, read, write, notify)
 * - MTU negotiation
 * - RSSI reading
 * - Connection parameters
 * - L2CAP channels
 */
class CentralManager(
    private val context: Context,
    private val bluetoothAdapter: BluetoothAdapter?
) {
    private var activity: Activity? = null
    private var scanner: BluetoothLeScanner? = null

    // Active GATT connections keyed by device MAC address
    private val connections = ConcurrentHashMap<String, BluetoothGatt>()

    // Per-device operation mutex to serialize GATT operations
    private val deviceMutex = ConcurrentHashMap<String, Semaphore>()

    // Event sinks for streaming data to Dart
    private var scanEventSink: EventChannel.EventSink? = null
    private var connectionEventSink: EventChannel.EventSink? = null
    private var characteristicEventSink: EventChannel.EventSink? = null
    private var mtuEventSink: EventChannel.EventSink? = null

    // Pending results for async GATT operations
    private var pendingResults = ConcurrentHashMap<String, Result>()

    fun setActivity(activity: Activity?) {
        this.activity = activity
    }

    // ═══════════════════════════════════════════════════════════
    // STREAM HANDLERS
    // ═══════════════════════════════════════════════════════════

    val scanStreamHandler = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            scanEventSink = events
        }
        override fun onCancel(arguments: Any?) {
            scanEventSink = null
        }
    }

    val connectionStreamHandler = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            connectionEventSink = events
        }
        override fun onCancel(arguments: Any?) {
            connectionEventSink = null
        }
    }

    val characteristicStreamHandler = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            characteristicEventSink = events
        }
        override fun onCancel(arguments: Any?) {
            characteristicEventSink = null
        }
    }

    val mtuStreamHandler = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            mtuEventSink = events
        }
        override fun onCancel(arguments: Any?) {
            mtuEventSink = null
        }
    }

    // ═══════════════════════════════════════════════════════════
    // SCANNING
    // ═══════════════════════════════════════════════════════════

    private var scanCallback: ScanCallback? = null

    fun startScan(withServices: List<String>?, scanMode: Int, allowDuplicates: Boolean) {
        scanner = bluetoothAdapter?.bluetoothLeScanner ?: return

        val settings = ScanSettings.Builder()
            .setScanMode(scanMode)
            .build()

        val filters = withServices?.map { uuid ->
            ScanFilter.Builder()
                .setServiceUuid(ParcelUuid.fromString(uuid))
                .build()
        }

        scanCallback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                val device = result.device
                val record = result.scanRecord

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

                val eventData = mapOf(
                    "deviceId" to device.address,
                    "name" to (device.name ?: record?.deviceName),
                    "rssi" to result.rssi,
                    "timestampMs" to (result.timestampNanos / 1_000_000),
                    "connectable" to (result.isConnectable),
                    "serviceUuids" to serviceUuids,
                    "manufacturerData" to manufacturerData,
                    "serviceData" to serviceData,
                    "txPowerLevel" to (record?.txPowerLevel ?: Int.MIN_VALUE).let {
                        if (it == Int.MIN_VALUE) null else it
                    }
                )

                scanEventSink?.success(eventData)
            }

            override fun onScanFailed(errorCode: Int) {
                scanEventSink?.error("SCAN_FAILED", "Scan failed with error code: $errorCode", errorCode)
            }
        }

        if (filters != null) {
            scanner?.startScan(filters, settings, scanCallback)
        } else {
            scanner?.startScan(null, settings, scanCallback)
        }
    }

    fun stopScan() {
        scanCallback?.let { scanner?.stopScan(it) }
        scanCallback = null
    }

    // ═══════════════════════════════════════════════════════════
    // CONNECTION
    // ═══════════════════════════════════════════════════════════

    fun connect(deviceId: String, autoConnect: Boolean) {
        val device = bluetoothAdapter?.getRemoteDevice(deviceId) ?: return

        // Emit connecting state
        connectionEventSink?.success(mapOf(
            "deviceId" to deviceId,
            "state" to 1, // connecting
        ))

        val gattCallback = createGattCallback(deviceId)
        val gatt = device.connectGatt(context, autoConnect, gattCallback, BluetoothDevice.TRANSPORT_LE)
        connections[deviceId] = gatt
        deviceMutex[deviceId] = Semaphore(1)
    }

    fun disconnect(deviceId: String) {
        connectionEventSink?.success(mapOf(
            "deviceId" to deviceId,
            "state" to 3, // disconnecting
        ))
        connections[deviceId]?.disconnect()
    }

    fun getConnectedDeviceIds(): List<String> {
        return connections.keys.toList()
    }

    // ═══════════════════════════════════════════════════════════
    // GATT OPERATIONS
    // ═══════════════════════════════════════════════════════════

    fun discoverServices(deviceId: String, result: Result) {
        val gatt = connections[deviceId]
        if (gatt == null) {
            result.error("NOT_CONNECTED", "Device $deviceId is not connected", null)
            return
        }
        pendingResults["discoverServices:$deviceId"] = result
        gatt.discoverServices()
    }

    fun readCharacteristic(deviceId: String, serviceUuid: String, charUuid: String, result: Result) {
        val gatt = connections[deviceId]
        if (gatt == null) {
            result.error("NOT_CONNECTED", "Device $deviceId is not connected", null)
            return
        }
        val characteristic = findCharacteristic(gatt, serviceUuid, charUuid)
        if (characteristic == null) {
            result.error("NOT_FOUND", "Characteristic $charUuid not found", null)
            return
        }
        pendingResults["readCharacteristic:$deviceId:$charUuid"] = result
        gatt.readCharacteristic(characteristic)
    }

    fun writeCharacteristic(
        deviceId: String, serviceUuid: String, charUuid: String,
        value: ByteArray, withResponse: Boolean, result: Result
    ) {
        val gatt = connections[deviceId]
        if (gatt == null) {
            result.error("NOT_CONNECTED", "Device $deviceId is not connected", null)
            return
        }
        val characteristic = findCharacteristic(gatt, serviceUuid, charUuid)
        if (characteristic == null) {
            result.error("NOT_FOUND", "Characteristic $charUuid not found", null)
            return
        }

        val writeType = if (withResponse)
            BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        else
            BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pendingResults["writeCharacteristic:$deviceId:$charUuid"] = result
            gatt.writeCharacteristic(characteristic, value, writeType)
        } else {
            @Suppress("DEPRECATION")
            characteristic.writeType = writeType
            @Suppress("DEPRECATION")
            characteristic.value = value
            pendingResults["writeCharacteristic:$deviceId:$charUuid"] = result
            @Suppress("DEPRECATION")
            gatt.writeCharacteristic(characteristic)
        }
    }

    fun setNotification(
        deviceId: String, serviceUuid: String, charUuid: String,
        enable: Boolean, result: Result
    ) {
        val gatt = connections[deviceId]
        if (gatt == null) {
            result.error("NOT_CONNECTED", "Device $deviceId is not connected", null)
            return
        }
        val characteristic = findCharacteristic(gatt, serviceUuid, charUuid)
        if (characteristic == null) {
            result.error("NOT_FOUND", "Characteristic $charUuid not found", null)
            return
        }

        gatt.setCharacteristicNotification(characteristic, enable)

        // Write to the CCCD descriptor
        val cccdUuid = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
        val descriptor = characteristic.getDescriptor(cccdUuid)
        if (descriptor != null) {
            val descriptorValue = if (enable) {
                if (characteristic.properties and BluetoothGattCharacteristic.PROPERTY_INDICATE != 0) {
                    BluetoothGattDescriptor.ENABLE_INDICATION_VALUE
                } else {
                    BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                }
            } else {
                BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                gatt.writeDescriptor(descriptor, descriptorValue)
            } else {
                @Suppress("DEPRECATION")
                descriptor.value = descriptorValue
                @Suppress("DEPRECATION")
                gatt.writeDescriptor(descriptor)
            }
        }

        result.success(null)
    }

    fun readDescriptor(
        deviceId: String, serviceUuid: String, charUuid: String,
        descUuid: String, result: Result
    ) {
        val gatt = connections[deviceId]
        if (gatt == null) {
            result.error("NOT_CONNECTED", "Device $deviceId is not connected", null)
            return
        }
        val descriptor = findDescriptor(gatt, serviceUuid, charUuid, descUuid)
        if (descriptor == null) {
            result.error("NOT_FOUND", "Descriptor $descUuid not found", null)
            return
        }
        pendingResults["readDescriptor:$deviceId:$descUuid"] = result
        gatt.readDescriptor(descriptor)
    }

    fun writeDescriptor(
        deviceId: String, serviceUuid: String, charUuid: String,
        descUuid: String, value: ByteArray, result: Result
    ) {
        val gatt = connections[deviceId]
        if (gatt == null) {
            result.error("NOT_CONNECTED", "Device $deviceId is not connected", null)
            return
        }
        val descriptor = findDescriptor(gatt, serviceUuid, charUuid, descUuid)
        if (descriptor == null) {
            result.error("NOT_FOUND", "Descriptor $descUuid not found", null)
            return
        }
        pendingResults["writeDescriptor:$deviceId:$descUuid"] = result
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            gatt.writeDescriptor(descriptor, value)
        } else {
            @Suppress("DEPRECATION")
            descriptor.value = value
            @Suppress("DEPRECATION")
            gatt.writeDescriptor(descriptor)
        }
    }

    // ═══════════════════════════════════════════════════════════
    // MTU / RSSI / CONNECTION PARAMS
    // ═══════════════════════════════════════════════════════════

    fun requestMtu(deviceId: String, mtu: Int, result: Result) {
        val gatt = connections[deviceId]
        if (gatt == null) {
            result.error("NOT_CONNECTED", "Device $deviceId is not connected", null)
            return
        }
        pendingResults["requestMtu:$deviceId"] = result
        gatt.requestMtu(mtu)
    }

    fun readRssi(deviceId: String, result: Result) {
        val gatt = connections[deviceId]
        if (gatt == null) {
            result.error("NOT_CONNECTED", "Device $deviceId is not connected", null)
            return
        }
        pendingResults["readRssi:$deviceId"] = result
        gatt.readRemoteRssi()
    }

    fun requestConnectionPriority(deviceId: String, priority: Int, result: Result) {
        val gatt = connections[deviceId]
        if (gatt == null) {
            result.error("NOT_CONNECTED", "Device $deviceId is not connected", null)
            return
        }
        val androidPriority = when (priority) {
            0 -> BluetoothGatt.CONNECTION_PRIORITY_BALANCED
            1 -> BluetoothGatt.CONNECTION_PRIORITY_HIGH
            2 -> BluetoothGatt.CONNECTION_PRIORITY_LOW_POWER
            else -> BluetoothGatt.CONNECTION_PRIORITY_BALANCED
        }
        val success = gatt.requestConnectionPriority(androidPriority)
        result.success(if (success) mapOf<String, Any?>() else null)
    }

    // ═══════════════════════════════════════════════════════════
    // L2CAP
    // ═══════════════════════════════════════════════════════════

    fun openL2CapChannel(deviceId: String, psm: Int, secure: Boolean, result: Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.error("UNSUPPORTED", "L2CAP requires Android 10+ (API 29)", null)
            return
        }
        // TODO: Implement L2CAP channel opening on background thread
        result.error("NOT_IMPLEMENTED", "L2CAP not yet implemented", null)
    }

    fun closeL2CapChannel(channelId: Int) {
        // TODO: Close the L2CAP channel
    }

    fun writeL2Cap(channelId: Int, data: ByteArray, result: Result) {
        // TODO: Write to L2CAP channel
        result.error("NOT_IMPLEMENTED", "L2CAP not yet implemented", null)
    }

    // ═══════════════════════════════════════════════════════════
    // GATT CALLBACK
    // ═══════════════════════════════════════════════════════════

    private fun createGattCallback(deviceId: String) = object : BluetoothGattCallback() {

        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            val state = when (newState) {
                BluetoothProfile.STATE_CONNECTED -> 2     // connected
                BluetoothProfile.STATE_DISCONNECTED -> 0  // disconnected
                else -> 0
            }

            connectionEventSink?.success(mapOf(
                "deviceId" to deviceId,
                "state" to state,
                "errorCode" to if (status != BluetoothGatt.GATT_SUCCESS) status else null,
            ))

            if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                gatt.close()
                connections.remove(deviceId)
                deviceMutex.remove(deviceId)
            }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            val result = pendingResults.remove("discoverServices:$deviceId") ?: return

            if (status != BluetoothGatt.GATT_SUCCESS) {
                result.error("GATT_ERROR", "Service discovery failed", status)
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
                    "includedServices" to emptyList<Map<String, Any?>>()
                )
            }

            result.success(services)
        }

        override fun onCharacteristicRead(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
            status: Int
        ) {
            val charUuid = characteristic.uuid.toString()
            val result = pendingResults.remove("readCharacteristic:$deviceId:$charUuid")

            if (status != BluetoothGatt.GATT_SUCCESS) {
                result?.error("GATT_ERROR", "Read failed", status)
                return
            }

            val intList = value.map { it.toInt() and 0xFF }
            result?.success(intList)
        }

        override fun onCharacteristicWrite(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int
        ) {
            val charUuid = characteristic.uuid.toString()
            val result = pendingResults.remove("writeCharacteristic:$deviceId:$charUuid")

            if (status != BluetoothGatt.GATT_SUCCESS) {
                result?.error("GATT_ERROR", "Write failed", status)
                return
            }
            result?.success(null)
        }

        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray
        ) {
            characteristicEventSink?.success(mapOf(
                "deviceId" to deviceId,
                "serviceUuid" to characteristic.service.uuid.toString(),
                "characteristicUuid" to characteristic.uuid.toString(),
                "value" to value.map { it.toInt() and 0xFF },
            ))
        }

        override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
            val result = pendingResults.remove("requestMtu:$deviceId")

            if (status == BluetoothGatt.GATT_SUCCESS) {
                result?.success(mtu)
                mtuEventSink?.success(mapOf(
                    "deviceId" to deviceId,
                    "mtu" to mtu,
                ))
            } else {
                result?.error("GATT_ERROR", "MTU request failed", status)
            }
        }

        override fun onReadRemoteRssi(gatt: BluetoothGatt, rssi: Int, status: Int) {
            val result = pendingResults.remove("readRssi:$deviceId")
            if (status == BluetoothGatt.GATT_SUCCESS) {
                result?.success(rssi)
            } else {
                result?.error("GATT_ERROR", "RSSI read failed", status)
            }
        }

        override fun onDescriptorRead(
            gatt: BluetoothGatt,
            descriptor: BluetoothGattDescriptor,
            status: Int,
            value: ByteArray
        ) {
            val descUuid = descriptor.uuid.toString()
            val result = pendingResults.remove("readDescriptor:$deviceId:$descUuid")
            if (status == BluetoothGatt.GATT_SUCCESS) {
                result?.success(value.map { it.toInt() and 0xFF })
            } else {
                result?.error("GATT_ERROR", "Descriptor read failed", status)
            }
        }

        override fun onDescriptorWrite(
            gatt: BluetoothGatt,
            descriptor: BluetoothGattDescriptor,
            status: Int
        ) {
            val descUuid = descriptor.uuid.toString()
            val result = pendingResults.remove("writeDescriptor:$deviceId:$descUuid")
            if (status == BluetoothGatt.GATT_SUCCESS) {
                result?.success(null)
            } else {
                result?.error("GATT_ERROR", "Descriptor write failed", status)
            }
        }
    }

    // ═══════════════════════════════════════════════════════════
    // HELPERS
    // ═══════════════════════════════════════════════════════════

    private fun findCharacteristic(
        gatt: BluetoothGatt,
        serviceUuid: String,
        charUuid: String
    ): BluetoothGattCharacteristic? {
        val service = gatt.getService(UUID.fromString(serviceUuid)) ?: return null
        return service.getCharacteristic(UUID.fromString(charUuid))
    }

    private fun findDescriptor(
        gatt: BluetoothGatt,
        serviceUuid: String,
        charUuid: String,
        descUuid: String
    ): BluetoothGattDescriptor? {
        val characteristic = findCharacteristic(gatt, serviceUuid, charUuid) ?: return null
        return characteristic.getDescriptor(UUID.fromString(descUuid))
    }

    fun dispose() {
        stopScan()
        connections.values.forEach { gatt ->
            gatt.disconnect()
            gatt.close()
        }
        connections.clear()
        deviceMutex.clear()
        pendingResults.clear()
    }
}

