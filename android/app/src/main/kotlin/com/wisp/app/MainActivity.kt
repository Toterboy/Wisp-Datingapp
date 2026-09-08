package com.wisp.app

import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.content.Context
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * MainActivity mit zwei Zusatzaufgaben:
 *  1. FLAG_SECURE verhindert Screenshots und Screen-Recording (Privatsphäre:
 *     Keine Fotos/Chats anderer Nutzer via Screenshot teilbar).
 *  2. Transit Spark (v0.9.0): BLE-Advertising über einen nativen
 *     Platform-Channel ("wisp/transit_ble"). Bewusst KEIN Plugin:
 *     flutter_ble_peripheral 3.1.0 kompiliert mit dem aktuellen
 *     Kotlin-Setup nicht (Argument-Type-Mismatch im Plugin-Code) - der
 *     eigene Channel ist minimal, wartbar und dependency-frei.
 *     Scanning läuft separat über flutter_blue_plus.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "wisp/transit_ble"
    private var advertiser: android.bluetooth.le.BluetoothLeAdvertiser? = null
    private var advertiseCallback: AdvertiseCallback? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // FLAG_SECURE verhindert Screenshots und Screen-Recording.
        // Schützt die Privatsphäre: Keine Fotos/Chats anderer Nutzer
        // können via Screenshot unkontrolliert weitergegeben werden.
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startAdvertise" -> {
                    val token = call.argument<String>("token") ?: ""
                    result.success(startAdvertise(token))
                }
                "stopAdvertise" -> {
                    stopAdvertise()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Startet das BLE-Advertising ("WST1" + token, Hersteller-ID 0xFFFF). */
    private fun startAdvertise(token: String): Boolean {
        return try {
            stopAdvertise()
            val manager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
            advertiser = manager.adapter?.bluetoothLeAdvertiser
            val adv = advertiser
            if (adv == null || token.length < 8) return false

            val data = AdvertiseData.Builder()
                .setIncludeDeviceName(false)
                .setIncludeTxPowerLevel(false)
                .addManufacturerData(0xFFFF, "WST1$token".toByteArray(Charsets.UTF_8))
                .build()
            val settings = AdvertiseSettings.Builder()
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                .setConnectable(false)
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
                .build()

            val callback = object : AdvertiseCallback() {}
            advertiseCallback = callback
            adv.startAdvertising(settings, data, callback)
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun stopAdvertise() {
        try {
            val cb = advertiseCallback
            val adv = advertiser
            if (adv != null && cb != null) {
                adv.stopAdvertising(cb)
            }
        } catch (e: Exception) {
            // Best effort.
        } finally {
            advertiseCallback = null
        }
    }
}
