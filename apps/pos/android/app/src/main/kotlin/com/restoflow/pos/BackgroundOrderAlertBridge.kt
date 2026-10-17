package com.restoflow.pos

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

internal class BackgroundOrderAlertBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val coordinator = BackgroundOrderAlertCoordinator.get(activity)
    private var permissionResult: MethodChannel.Result? = null
    init {
        coordinator.attach(messenger)
        coordinator.bridge()?.setMethodCallHandler { call, result ->
            val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
            when (call.method) {
                "prepare" -> {
                    if (args["request_permission"] == true && BackgroundOrderAlertCoordinator.initializeFirebase(activity) && Build.VERSION.SDK_INT >= 33 &&
                        ContextCompat.checkSelfPermission(activity, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        if (permissionResult != null) { result.success(mapOf("available" to true, "enabled" to false)); return@setMethodCallHandler }
                        permissionResult = result
                        activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 381)
                    } else coordinator.prepare(activity, args["request_permission"] == true) { result.success(it) }
                }
                "bind" -> result.success(coordinator.bind(args))
                "pending" -> result.success(coordinator.pending(args))
                "suspend" -> { coordinator.clearAuthority(args["retain_opt_in"] == true); result.success(null) }
                "disable" -> { coordinator.disable(); result.success(null) }
                "consumeInboxTap" -> result.success(coordinator.consumeTap())
                else -> result.notImplemented()
            }
        }
    }

    fun permissionsResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != 381) return
        val result = permissionResult ?: return
        permissionResult = null
        if (grantResults.isEmpty() || grantResults[0] != PackageManager.PERMISSION_GRANTED) {
            result.success(mapOf("available" to true, "enabled" to false))
            return
        }
        coordinator.prepare(activity, true) { result.success(it) }
    }

    fun detach() {
        permissionResult?.success(mapOf("available" to true, "enabled" to false))
        permissionResult = null
        coordinator.detach()
    }
}
