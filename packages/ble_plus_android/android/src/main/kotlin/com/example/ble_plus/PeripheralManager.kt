package com.example.ble_plus

import android.bluetooth.*
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.Context
import android.os.ParcelUuid
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel.Result
import java.util.*
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger

/**
 * Manages BLE Peripheral (Server) role operations:
 * - Advertising as a BLE peripheral
 * - GATT server with services/characteristics
 * - Handling read/write requests from centrals
 * - Sending notifications/indications
 */
class PeripheralManager(
    private val context: Context,
    private val bluetoothManager: BluetoothManager?
) {
    private var advertiser: BluetoothLeAdvertiser? = null
    private var gattServer: BluetoothGattServer? = null
    private var advertiseCallback: AdvertiseCallback? = null

    // Track connected centrals
    private val connectedCentrals = ConcurrentHashMap<String, BluetoothDevice>()

    // Track subscriptions: characteristicUuid -> set of device addresses
    private val subscriptions = ConcurrentHashMap<String, MutableSet<String>>()

    // Request ID counter for read/write requests
    private val requestIdCounter = AtomicInteger(0)

    // Pending requests (requestId -> device + offset info)
    private data class PendingRequest(
        val device: BluetoothDevice,
        val requestId: Int, // Native Android requestId
        val offset: Int
    )
    private val pendingRequests = ConcurrentHashMap<Int, PendingRequest>()

    // Event sink for peripheral events
    private var eventSink: EventChannel.EventSink? = null

    val eventStreamHandler = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            eventSink = events
        }
        override fun onCancel(arguments: Any?) {
            eventSink = null
        }
    }

    init {
        advertiser = bluetoothManager?.adapter?.bluetoothLeAdvertiser
    }

    // ═══════════════════════════════════════════════════════════
    // GATT SERVER
    // ═══════════════════════════════════════════════════════════

    private fun ensureGattServer() {
        if (gattServer != null) return
        gattServer = bluetoothManager?.openGattServer(context, gattServerCallback)
    }

    private val gattServerCallback = object : BluetoothGattServerCallback() {

        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            val connected = newState == BluetoothProfile.STATE_CONNECTED
            if (connected) {
                connectedCentrals[device.address] = device
            } else {
                connectedCentrals.remove(device.address)
                // Remove subscriptions for this device
                subscriptions.values.forEach { it.remove(device.address) }
            }

            eventSink?.success(mapOf(
                "type" to "connection",
                "deviceId" to device.address,
                "connected" to connected,
            ))
        }

        override fun onCharacteristicReadRequest(
            device: BluetoothDevice,
            requestId: Int,
            offset: Int,
            characteristic: BluetoothGattCharacteristic
        ) {
            val ourRequestId = requestIdCounter.incrementAndGet()
            pendingRequests[ourRequestId] = PendingRequest(device, requestId, offset)

            eventSink?.success(mapOf(
                "type" to "readRequest",
                "requestId" to ourRequestId,
                "deviceId" to device.address,
                "serviceUuid" to characteristic.service.uuid.toString(),
                "characteristicUuid" to characteristic.uuid.toString(),
                "offset" to offset,
            ))
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray?
        ) {
            val ourRequestId = requestIdCounter.incrementAndGet()
            pendingRequests[ourRequestId] = PendingRequest(device, requestId, offset)

            eventSink?.success(mapOf(
                "type" to "writeRequest",
                "requestId" to ourRequestId,
                "deviceId" to device.address,
                "serviceUuid" to characteristic.service.uuid.toString(),
                "characteristicUuid" to characteristic.uuid.toString(),
                "value" to (value?.map { it.toInt() and 0xFF } ?: emptyList<Int>()),
                "offset" to offset,
                "responseNeeded" to responseNeeded,
            ))
        }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray?
        ) {
            // Handle CCCD writes (notification subscription)
            val cccdUuid = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
            if (descriptor.uuid == cccdUuid) {
                val charUuid = descriptor.characteristic.uuid.toString()
                val isSubscribed = value != null && value.isNotEmpty() && value[0].toInt() != 0

                if (isSubscribed) {
                    subscriptions.getOrPut(charUuid) { mutableSetOf() }.add(device.address)
                } else {
                    subscriptions[charUuid]?.remove(device.address)
                }

                eventSink?.success(mapOf(
                    "type" to "subscriptionChange",
                    "deviceId" to device.address,
                    "serviceUuid" to descriptor.characteristic.service.uuid.toString(),
                    "characteristicUuid" to charUuid,
                    "isSubscribed" to isSubscribed,
                ))

                if (responseNeeded) {
                    gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, value)
                }
            }
        }

        override fun onNotificationSent(device: BluetoothDevice, status: Int) {
            // Notification was sent successfully or failed
        }
    }

    // ═══════════════════════════════════════════════════════════
    // ADVERTISING
    // ═══════════════════════════════════════════════════════════

    fun startAdvertising(args: Map<String, Any?>, result: Result) {
        if (advertiser == null) {
            result.error("UNSUPPORTED", "BLE advertising not supported", null)
            return
        }

        ensureGattServer()

        val localName = args["localName"] as? String
        val serviceUuids = (args["serviceUuids"] as? List<*>)?.mapNotNull { it as? String } ?: emptyList()
        val connectable = args["connectable"] as? Boolean ?: true
        val timeoutMs = args["timeoutMs"] as? Int ?: 0

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setConnectable(connectable)
            .setTimeout(timeoutMs)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
            .build()

        val dataBuilder = AdvertiseData.Builder()
            .setIncludeDeviceName(localName != null)

        serviceUuids.forEach { uuid ->
            dataBuilder.addServiceUuid(ParcelUuid.fromString(uuid))
        }

        advertiseCallback = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
                result.success(null)
            }

            override fun onStartFailure(errorCode: Int) {
                result.error("ADVERTISE_FAILED", "Advertising failed with code: $errorCode", errorCode)
            }
        }

        advertiser?.startAdvertising(settings, dataBuilder.build(), advertiseCallback)
    }

    fun stopAdvertising() {
        advertiseCallback?.let { advertiser?.stopAdvertising(it) }
        advertiseCallback = null
    }

    // ═══════════════════════════════════════════════════════════
    // SERVICE MANAGEMENT
    // ═══════════════════════════════════════════════════════════

    fun addService(args: Map<String, Any?>, result: Result) {
        ensureGattServer()

        val uuid = UUID.fromString(args["uuid"] as String)
        val isPrimary = args["isPrimary"] as? Boolean ?: true
        val serviceType = if (isPrimary)
            BluetoothGattService.SERVICE_TYPE_PRIMARY
        else
            BluetoothGattService.SERVICE_TYPE_SECONDARY

        val service = BluetoothGattService(uuid, serviceType)

        val characteristics = (args["characteristics"] as? List<*>) ?: emptyList<Any>()
        for (charMap in characteristics) {
            val charArgs = charMap as Map<String, Any?>
            val charUuid = UUID.fromString(charArgs["uuid"] as String)
            val properties = charArgs["properties"] as? Int ?: 0
            val permissions = charArgs["permissions"] as? Int ?: 0

            val characteristic = BluetoothGattCharacteristic(charUuid, properties, permissions)

            // Add initial value if provided
            (charArgs["initialValue"] as? List<*>)?.let { values ->
                characteristic.value = values.map { (it as Int).toByte() }.toByteArray()
            }

            // Add CCCD if notify or indicate is supported
            if (properties and (BluetoothGattCharacteristic.PROPERTY_NOTIFY or BluetoothGattCharacteristic.PROPERTY_INDICATE) != 0) {
                val cccd = BluetoothGattDescriptor(
                    UUID.fromString("00002902-0000-1000-8000-00805f9b34fb"),
                    BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE
                )
                characteristic.addDescriptor(cccd)
            }

            // Add custom descriptors
            val descriptors = (charArgs["descriptors"] as? List<*>) ?: emptyList<Any>()
            for (descMap in descriptors) {
                val descArgs = descMap as Map<String, Any?>
                val descUuid = UUID.fromString(descArgs["uuid"] as String)
                val descPermissions = descArgs["permissions"] as? Int ?: 0
                val descriptor = BluetoothGattDescriptor(descUuid, descPermissions)
                characteristic.addDescriptor(descriptor)
            }

            service.addCharacteristic(characteristic)
        }

        val added = gattServer?.addService(service) ?: false
        if (added) {
            result.success(null)
        } else {
            result.error("ADD_SERVICE_FAILED", "Failed to add service", null)
        }
    }

    fun removeService(uuid: String) {
        val service = gattServer?.services?.find { it.uuid.toString() == uuid }
        service?.let { gattServer?.removeService(it) }
    }

    fun removeAllServices() {
        gattServer?.clearServices()
    }

    // ═══════════════════════════════════════════════════════════
    // NOTIFICATIONS
    // ═══════════════════════════════════════════════════════════

    fun sendNotification(
        serviceUuid: String, charUuid: String,
        value: ByteArray, deviceId: String?, result: Result
    ) {
        val service = gattServer?.getService(UUID.fromString(serviceUuid))
        val characteristic = service?.getCharacteristic(UUID.fromString(charUuid))

        if (characteristic == null) {
            result.error("NOT_FOUND", "Characteristic not found", null)
            return
        }

        val confirm = (characteristic.properties and BluetoothGattCharacteristic.PROPERTY_INDICATE) != 0

        val targetDevices = if (deviceId != null) {
            connectedCentrals[deviceId]?.let { listOf(it) } ?: emptyList()
        } else {
            // Send to all subscribed devices
            val subscribedAddresses = subscriptions[charUuid] ?: emptySet()
            connectedCentrals.filterKeys { it in subscribedAddresses }.values.toList()
        }

        for (device in targetDevices) {
            gattServer?.notifyCharacteristicChanged(device, characteristic, confirm, value)
        }

        result.success(null)
    }

    // ═══════════════════════════════════════════════════════════
    // REQUEST RESPONSES
    // ═══════════════════════════════════════════════════════════

    fun respondToReadRequest(ourRequestId: Int, value: ByteArray) {
        val pending = pendingRequests.remove(ourRequestId) ?: return
        gattServer?.sendResponse(
            pending.device,
            pending.requestId,
            BluetoothGatt.GATT_SUCCESS,
            pending.offset,
            value
        )
    }

    fun respondToWriteRequest(ourRequestId: Int) {
        val pending = pendingRequests.remove(ourRequestId) ?: return
        gattServer?.sendResponse(
            pending.device,
            pending.requestId,
            BluetoothGatt.GATT_SUCCESS,
            pending.offset,
            null
        )
    }

    fun respondWithError(ourRequestId: Int, errorCode: Int) {
        val pending = pendingRequests.remove(ourRequestId) ?: return
        gattServer?.sendResponse(
            pending.device,
            pending.requestId,
            errorCode,
            pending.offset,
            null
        )
    }

    fun dispose() {
        stopAdvertising()
        gattServer?.close()
        gattServer = null
        connectedCentrals.clear()
        subscriptions.clear()
        pendingRequests.clear()
    }
}

