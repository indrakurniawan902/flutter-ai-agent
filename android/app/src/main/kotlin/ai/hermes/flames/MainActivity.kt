package ai.hermes.flames

import android.content.ComponentName
import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "ai.hermes.flames/notification_listener"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isPermissionGranted" -> result.success(isListenerEnabled())
                "requestPermission" -> {
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                    result.success(null)
                }
                "getRecentNotifications" ->
                    result.success(FlamesNotificationListenerService.getNotifications())
                "clearNotifications" -> {
                    FlamesNotificationListenerService.clearAll()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isListenerEnabled(): Boolean {
        val component = ComponentName(this, FlamesNotificationListenerService::class.java)
        val enabled = Settings.Secure.getString(
            contentResolver,
            "enabled_notification_listeners",
        ) ?: return false
        return enabled.contains(component.flattenToString()) ||
            enabled.contains(packageName)
    }
}
