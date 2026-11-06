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
    private var dutyPermission: Map<*, *>? = null
    init {
        coordinator.attach(messenger)
        coordinator.bridge()?.setMethodCallHandler { call, result ->
            val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
            when (call.method) {
                "dutyState" -> result.success(coordinator.dutyState(args))
                "suspendDutyEffects" -> result.success(coordinator.suspendDutyEffects(args))
                "revalidateDuty" -> coordinator.revalidateDuty(args) { result.success(it) }
                "prepareDutyPreview" -> result.success(try { coordinator.prepareDutyPreview(args) } catch (_: Exception) { emptyMap<String, Any?>() })
                "requestDutyPermission" -> {
                    if (!coordinator.stagedDuty(args) || permissionResult != null) result.success(false)
                    else if (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(activity,
                            Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        permissionResult = result
                        dutyPermission = args
                        try { activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS),381) }
                        catch (_: Exception) { permissionResult = null; dutyPermission = null; result.success(false) }
                    } else result.success(true)
                }
                "prepareDuty" -> coordinator.prepareDuty(args) { result.success(it) }
                "bindDuty" -> result.success(try { coordinator.bindDuty(args) } catch (_: Exception) { false })
                "cancelDuty" -> result.success(try { coordinator.cancelDuty(args) } catch (_: Exception) { false })
                "activationStatus" -> result.success(BackgroundOrderAlertActivationStatus.snapshot(activity))
                "openNotificationSettings" -> result.success(BackgroundOrderAlertActivationStatus.openSettings(activity, args["channel"] == true))
                "prepare" -> {
                    if (args["request_permission"] == true && BackgroundOrderAlertCoordinator.initializeFirebase(activity) && Build.VERSION.SDK_INT >= 33 &&
                        ContextCompat.checkSelfPermission(activity, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        if (permissionResult != null) { result.success(mapOf("available" to true, "enabled" to false, "failure_reason" to "preparation_pending")); return@setMethodCallHandler }
                        permissionResult = result
                        activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 381)
                    } else coordinator.prepare(activity, args["request_permission"] == true) { result.success(it) }
                }
                "bind" -> result.success(coordinator.bind(args))
                "pending" -> result.success(coordinator.pending(args))
                "retainInactivity" -> result.success(coordinator.retainInactivity(args))
                "suspend" -> if (coordinator.clearAuthority(args["retain_opt_in"] == true,
                        BackgroundOrderAlertRevocationReason.parse(args["reason"]))) result.success(null)
                    else result.error("local_stop_unconfirmed",null,null)
                "disable" -> if (coordinator.disable(if (args.containsKey("reason")) BackgroundOrderAlertRevocationReason.parse(args["reason"])
                        else BackgroundOrderAlertRevocationReason.EXPLICIT_SIGN_OUT)) result.success(null)
                    else result.error("local_stop_unconfirmed",null,null)
                "consumeInboxTap" -> result.success(coordinator.consumeTap())
                else -> result.notImplemented()
            }
        }
    }

    fun permissionsResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != 381) return
        val result = permissionResult ?: return
        permissionResult = null
        val duty = dutyPermission
        dutyPermission = null
        if (duty != null) {
            // Permission dialog may report the result before Activity.onResume. Do not arm,
            // initialize FCM or enroll here; a subsequent foreground call must still match.
            result.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED &&
                coordinator.stagedDuty(duty, requireForeground = false))
            return
        }
        if (grantResults.isEmpty() || grantResults[0] != PackageManager.PERMISSION_GRANTED) {
            result.success(coordinator.permissionRefused())
            return
        }
        coordinator.prepare(activity, true) { result.success(it) }
    }

    fun detach() {
        permissionResult?.success(if (dutyPermission != null) false else mapOf("available" to true, "enabled" to false, "failure_reason" to "preparation_cancelled"))
        permissionResult = null
        dutyPermission = null
        coordinator.detach()
    }
}
