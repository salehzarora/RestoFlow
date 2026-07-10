package com.restoflow.kds

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * RestoFlow in-house Bluetooth Classic (SPP) thermal-printer channel
 * (PRINT-BLUETOOTH-RECOVERY-001), mirrored byte-for-byte in the KDS app.
 *
 * Replaces the `print_bluetooth_thermal` plugin, whose Android side broke real
 * printing: it prepended a rogue `\n` byte to EVERY write (corrupting the
 * chunked ESC/POS raster stream every Arabic/Hebrew receipt uses), kept broken
 * global socket state across calls, never answered the channel when the
 * permission was missing, only ever tried the SECURE RFCOMM socket, and ran
 * connect without any native timeout.
 *
 * Design: each `printBytes` call is ONE self-contained, stateless job —
 * permission/adapter/bond checks -> cancel discovery -> connect (secure RFCOMM
 * first, insecure fallback; each attempt bounded by a watchdog that closes the
 * socket) -> write the bytes EXACTLY as received (no framing, no injected
 * bytes) in small flushed chunks with a pacing delay -> a short drain pause so
 * the printer empties its buffer before the socket closes -> close. Jobs
 * serialize on a single-thread executor (no shared socket state, no concurrent
 * connects). Every outcome is a typed result map; the channel ALWAYS answers.
 */
class MainActivity : FlutterActivity() {
    private companion object {
        const val CHANNEL = "restoflow.native_printing/bluetooth"

        /** The standard Bluetooth Serial Port Profile UUID. */
        val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    }

    /** Print jobs run here one at a time — never two concurrent RFCOMM connects. */
    private val jobExecutor = Executors.newSingleThreadExecutor()

    /** Watchdog that closes a socket stuck in connect() so a job can never hang. */
    private val watchdog = Executors.newSingleThreadScheduledExecutor()

    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "permissionsGranted" -> result.success(hasConnectPermission())
                    "isEnabled" -> result.success(bluetoothAdapter()?.isEnabled == true)
                    "pairedDevices" -> result.success(pairedDevices())
                    "printBytes" -> {
                        val args = call.arguments as? Map<*, *>
                        if (args == null) {
                            result.success(jobResult(false, "unknown", "missing arguments"))
                        } else {
                            jobExecutor.execute {
                                val outcome = try {
                                    runPrintJob(args)
                                } catch (e: Exception) {
                                    jobResult(false, "unknown", "unexpected: ${e.message}")
                                }
                                mainHandler.post { result.success(outcome) }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        jobExecutor.shutdownNow()
        watchdog.shutdownNow()
        super.onDestroy()
    }

    private fun bluetoothAdapter(): BluetoothAdapter? =
        (getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    /** BLUETOOTH_CONNECT is runtime-gated only on Android 12+ (API 31). */
    private fun hasConnectPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) ==
            PackageManager.PERMISSION_GRANTED

    private fun jobResult(
        ok: Boolean,
        code: String,
        detail: String,
        bytesSent: Int = 0,
        chunks: Int = 0,
    ): Map<String, Any> = mapOf(
        "ok" to ok,
        "code" to code,
        "detail" to detail,
        "bytesSent" to bytesSent,
        "chunks" to chunks,
    )

    private fun pairedDevices(): Map<String, Any> {
        val none = emptyList<Map<String, Any>>()
        if (!hasConnectPermission()) {
            return mapOf("ok" to false, "code" to "permission", "devices" to none)
        }
        val adapter = bluetoothAdapter()
            ?: return mapOf("ok" to false, "code" to "bluetoothOff", "devices" to none)
        if (!adapter.isEnabled) {
            return mapOf("ok" to false, "code" to "bluetoothOff", "devices" to none)
        }
        return try {
            val devices = adapter.bondedDevices.map { device ->
                mapOf(
                    "name" to (device.name ?: ""),
                    "address" to device.address,
                    // The major class (imaging = 0x600) is a UI sort hint only.
                    "majorClass" to (device.bluetoothClass?.majorDeviceClass ?: -1),
                )
            }
            mapOf("ok" to true, "code" to "ok", "devices" to devices)
        } catch (e: SecurityException) {
            mapOf("ok" to false, "code" to "permission", "devices" to none)
        }
    }

    /** One self-contained print job: connect (secure->insecure) -> write -> drain -> close. */
    private fun runPrintJob(args: Map<*, *>): Map<String, Any> {
        val address = args["address"] as? String
            ?: return jobResult(false, "unknown", "missing address")
        val bytes = args["bytes"] as? ByteArray
            ?: return jobResult(false, "unknown", "missing bytes")
        val timeoutMs = ((args["timeoutMs"] as? Number)?.toLong() ?: 10_000L).coerceAtLeast(1_000L)
        val chunkBytes = ((args["chunkBytes"] as? Number)?.toInt() ?: 512).coerceAtLeast(1)
        val chunkDelayMs = ((args["chunkDelayMs"] as? Number)?.toLong() ?: 20L).coerceAtLeast(0L)
        val drainMs = ((args["drainMs"] as? Number)?.toLong() ?: 300L).coerceAtLeast(0L)

        if (!hasConnectPermission()) {
            return jobResult(false, "permission", "BLUETOOTH_CONNECT is not granted")
        }
        val adapter = bluetoothAdapter()
            ?: return jobResult(false, "bluetoothOff", "this device has no bluetooth adapter")
        if (!adapter.isEnabled) {
            return jobResult(false, "bluetoothOff", "the bluetooth adapter is off")
        }
        val device: BluetoothDevice = try {
            adapter.getRemoteDevice(address)
        } catch (e: IllegalArgumentException) {
            return jobResult(false, "connectFailed", "invalid bluetooth address: $address")
        }
        try {
            if (device.bondState != BluetoothDevice.BOND_BONDED) {
                return jobResult(false, "notBonded", "device $address is not paired/bonded in Android settings")
            }
        } catch (e: SecurityException) {
            return jobResult(false, "permission", "bond state check denied: ${e.message}")
        }
        // Active discovery makes RFCOMM connects fail. We never start discovery
        // ourselves; cancel best-effort (needs BLUETOOTH_SCAN on 12+, which we
        // deliberately do not request — a SecurityException is safely ignored).
        try {
            adapter.cancelDiscovery()
        } catch (_: SecurityException) {
            // scan permission not held; nothing to cancel in this app anyway
        }

        // Connect: secure RFCOMM first, insecure fallback (many cheap SPP
        // thermal printers only connect reliably over the insecure variant).
        // Each attempt gets a fresh socket bounded by a watchdog close.
        val lastTimedOut = AtomicBoolean(false)
        var socket: BluetoothSocket? = null
        val attemptDetails = StringBuilder()
        for (secure in booleanArrayOf(true, false)) {
            val label = if (secure) "secure" else "insecure"
            val candidate = try {
                if (secure) {
                    device.createRfcommSocketToServiceRecord(SPP_UUID)
                } else {
                    device.createInsecureRfcommSocketToServiceRecord(SPP_UUID)
                }
            } catch (e: Exception) {
                attemptDetails.append("$label socket: ${e.message}; ")
                continue
            }
            lastTimedOut.set(false)
            val guard = watchdog.schedule({
                lastTimedOut.set(true)
                try {
                    candidate.close()
                } catch (_: IOException) {
                }
            }, timeoutMs, TimeUnit.MILLISECONDS)
            try {
                candidate.connect() // blocking; aborted by the watchdog close
                guard.cancel(false)
                socket = candidate
                attemptDetails.append("$label: connected; ")
                break
            } catch (e: Exception) {
                guard.cancel(false)
                try {
                    candidate.close()
                } catch (_: IOException) {
                }
                attemptDetails.append(
                    "$label: " +
                        (if (lastTimedOut.get()) "timed out after ${timeoutMs}ms"
                        else (e.message ?: e.javaClass.simpleName)) + "; ",
                )
            }
        }
        val connected = socket
            ?: return jobResult(
                false,
                if (lastTimedOut.get()) "timeout" else "connectFailed",
                attemptDetails.toString().trim(),
            )

        // Write the bytes EXACTLY as received — chunked + flushed, with pacing,
        // then a drain pause so the tail is on paper before the socket closes.
        var sent = 0
        var chunks = 0
        try {
            val out = connected.outputStream
            while (sent < bytes.size) {
                val end = minOf(sent + chunkBytes, bytes.size)
                out.write(bytes, sent, end - sent)
                out.flush()
                sent = end
                chunks++
                if (end < bytes.size && chunkDelayMs > 0) Thread.sleep(chunkDelayMs)
            }
            if (drainMs > 0) Thread.sleep(drainMs)
            return jobResult(
                true,
                "ok",
                "${attemptDetails.toString().trim()} sent $sent bytes in $chunks chunks",
                sent,
                chunks,
            )
        } catch (e: Exception) {
            return jobResult(
                false,
                "writeFailed",
                "write failed after $sent/${bytes.size} bytes: ${e.message}",
                sent,
                chunks,
            )
        } finally {
            try {
                connected.close()
            } catch (_: IOException) {
            }
        }
    }
}
