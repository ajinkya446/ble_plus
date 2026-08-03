package com.example.ble_plus

import android.bluetooth.BluetoothAdapter
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import io.flutter.plugin.common.EventChannel

/**
 * Stream handler for Bluetooth adapter state changes.
 */
class AdapterStateStreamHandler(private val context: Context) : EventChannel.StreamHandler {

    private var eventSink: EventChannel.EventSink? = null
    private var receiver: BroadcastReceiver? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events

        // Emit current state immediately
        val currentState = mapAdapterState(BluetoothAdapter.getDefaultAdapter()?.state ?: BluetoothAdapter.STATE_OFF)
        eventSink?.success(currentState)

        // Register for state changes
        receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context?, intent: Intent?) {
                if (intent?.action == BluetoothAdapter.ACTION_STATE_CHANGED) {
                    val state = intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.STATE_OFF)
                    eventSink?.success(mapAdapterState(state))
                }
            }
        }

        context.registerReceiver(receiver, IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED))
    }

    override fun onCancel(arguments: Any?) {
        receiver?.let { context.unregisterReceiver(it) }
        receiver = null
        eventSink = null
    }

    /**
     * Maps Android BluetoothAdapter state to our BleAdapterState enum index.
     *
     * BleAdapterState enum order:
     * 0 = unknown, 1 = unsupported, 2 = unauthorized,
     * 3 = turningOn, 4 = on, 5 = turningOff, 6 = off
     */
    private fun mapAdapterState(androidState: Int): Int {
        return when (androidState) {
            BluetoothAdapter.STATE_OFF -> 6       // off
            BluetoothAdapter.STATE_TURNING_ON -> 3 // turningOn
            BluetoothAdapter.STATE_ON -> 4         // on
            BluetoothAdapter.STATE_TURNING_OFF -> 5 // turningOff
            else -> 0                              // unknown
        }
    }
}

