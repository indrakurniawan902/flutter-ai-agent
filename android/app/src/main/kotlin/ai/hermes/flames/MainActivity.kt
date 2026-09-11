package ai.hermes.flames

import android.content.Intent
import android.provider.Settings
import androidx.annotation.NonNull
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val NOTIFICATION_CHANNEL = "ai.hermes.flames/notification_listener"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIFICATION_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isPermissionGranted" -> {
                        val isGranted = isNotificationListenerPermissionGranted()
                        result.success(isGranted)
                    }
                    "requestPermission" -> {
                        try {
                            val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("PERMISSION_ERROR", e.message, null)
                        }
                    }
                    "getRecentNotifications" -> {
                        val limit = call.argument<Int>("limit") ?: 20
                        val notifications = FlamesNotificationListenerService.getRecentNotifications(limit)
                        result.success(notifications)
                    }
                    "clearNotifications" -> {
                        FlamesNotificationListenerService.clearBuffer()
                        result.success(true)
                    }
                    else -> {
                        result.notImplemented()
                    }
                }
            }
    }

    private fun isNotificationListenerPermissionGranted(): Boolean {
        return try {
            val enabledListeners = NotificationManagerCompat.getEnabledListenerPackages(this)
            enabledListeners.contains(packageName)
        } catch (_: Exception) {
            false
        }
    }
}
