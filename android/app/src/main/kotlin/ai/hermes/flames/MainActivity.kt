package ai.hermes.flames

import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import androidx.annotation.NonNull
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val NOTIFICATION_CHANNEL = "ai.hermes.flames/notification_listener"
    private val BACKGROUND_CHANNEL = "ai.hermes.flames/background_service"

    private var backgroundMethodChannel: MethodChannel? = null
    private var pendingAction: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        extractActionFromIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val action = extractActionFromIntent(intent)
        if (action != null) {
            backgroundMethodChannel?.invokeMethod("onActionReceived", action)
        }
    }

    private fun extractActionFromIntent(intent: Intent?): String? {
        val actionExtra = intent?.getStringExtra("extra_flames_action")
        if (!actionExtra.isNullOrBlank()) {
            pendingAction = actionExtra
            return actionExtra
        }
        if (intent?.action == FlamesQuickTile.ACTION_QUICK_TILE_TRIGGER) {
            val fallbackAction = "voice_input"
            pendingAction = fallbackAction
            return fallbackAction
        }
        return null
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Notification Listener Channel
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

        // Background Service & Quick Settings Tile Channel
        val bgChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BACKGROUND_CHANNEL)
        backgroundMethodChannel = bgChannel
        bgChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startForegroundService" -> {
                    val title = call.argument<String>("title")
                    val content = call.argument<String>("content")
                    FlamesBackgroundService.startService(this, title, content)
                    result.success(true)
                }
                "stopForegroundService" -> {
                    FlamesBackgroundService.stopService(this)
                    result.success(true)
                }
                "isServiceRunning" -> {
                    result.success(FlamesBackgroundService.isServiceRunning)
                }
                "updateNotification" -> {
                    val title = call.argument<String>("title") ?: "Flames Agent Active"
                    val content = call.argument<String>("content") ?: "Listening in background"
                    FlamesBackgroundService.updateNotification(this, title, content)
                    result.success(true)
                }
                "acquireWakeLock" -> {
                    val timeoutMs = call.argument<Int>("timeoutMs")?.toLong()
                        ?: FlamesBackgroundService.DEFAULT_WAKELOCK_TIMEOUT_MS
                    val acquired = FlamesBackgroundService.acquireWakeLock(this, timeoutMs)
                    result.success(acquired)
                }
                "releaseWakeLock" -> {
                    val released = FlamesBackgroundService.releaseWakeLock()
                    result.success(released)
                }
                "isWakeLockHeld" -> {
                    result.success(FlamesBackgroundService.isWakeLockHeld())
                }
                "getQuickTileState" -> {
                    val state = FlamesQuickTile.getTileStateString()
                    result.success(state)
                }
                "setQuickTileState" -> {
                    val active = call.argument<Boolean>("active") ?: false
                    FlamesQuickTile.updateTileState(active)
                    result.success(true)
                }
                "getPendingAction" -> {
                    result.success(pendingAction)
                }
                "clearPendingAction" -> {
                    pendingAction = null
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
