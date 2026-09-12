package ai.hermes.flames

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val NOTIFICATION_CHANNEL = "ai.hermes.flames/notification_listener"
    private val BACKGROUND_CHANNEL = "ai.hermes.flames/background_service"
    private val CONTACTS_CHANNEL = "ai.hermes.flames/contacts"
    private val BATTERY_CHANNEL = "ai.hermes.flames/battery_optimization"
    private val INTENT_SETTINGS_CHANNEL = "ai.hermes.flames/intent_settings"

    private val CONTACTS_PERMISSION_REQUEST_CODE = 1001
    private var pendingContactsResult: MethodChannel.Result? = null

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
                            val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS).apply {
                                    val component = ComponentName(this@MainActivity, FlamesNotificationListenerService::class.java)
                                    putExtra(Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME, component.flattenToString())
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                            } else {
                                Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).apply {
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                            }
                            try {
                                startActivity(intent)
                            } catch (_: Exception) {
                                val fallback = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).apply {
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                startActivity(fallback)
                            }
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

        // Contacts Permission Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CONTACTS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isPermissionGranted" -> {
                        val isGranted = ContextCompat.checkSelfPermission(
                            this,
                            Manifest.permission.READ_CONTACTS
                        ) == PackageManager.PERMISSION_GRANTED
                        result.success(isGranted)
                    }
                    "requestPermission" -> {
                        val isGranted = ContextCompat.checkSelfPermission(
                            this,
                            Manifest.permission.READ_CONTACTS
                        ) == PackageManager.PERMISSION_GRANTED
                        if (isGranted) {
                            result.success(true)
                        } else {
                            pendingContactsResult = result
                            ActivityCompat.requestPermissions(
                                this,
                                arrayOf(Manifest.permission.READ_CONTACTS),
                                CONTACTS_PERMISSION_REQUEST_CODE
                            )
                        }
                    }
                    else -> {
                        result.notImplemented()
                    }
                }
            }

        // Battery Optimization Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BATTERY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isIgnoringBatteryOptimizations" -> {
                        val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
                        val isIgnoring = powerManager?.isIgnoringBatteryOptimizations(packageName) ?: false
                        result.success(isIgnoring)
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
                        val isIgnoring = powerManager?.isIgnoringBatteryOptimizations(packageName) ?: false
                        if (isIgnoring) {
                            result.success(true)
                        } else {
                            try {
                                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                    data = Uri.parse("package:$packageName")
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                startActivity(intent)
                            } catch (_: Exception) {
                                try {
                                    val fallback = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    }
                                    startActivity(fallback)
                                } catch (_: Exception) {}
                            }
                            result.success(true)
                        }
                    }
                    else -> {
                        result.notImplemented()
                    }
                }
            }

        // Intent Settings Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INTENT_SETTINGS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openSystemSettings" -> {
                        val type = call.argument<String>("type")
                        val action = when (type) {
                            "bluetooth" -> Settings.ACTION_BLUETOOTH_SETTINGS
                            "wifi" -> Settings.ACTION_WIFI_SETTINGS
                            "battery_saver" -> Settings.ACTION_BATTERY_SAVER_SETTINGS
                            "airplane_mode" -> Settings.ACTION_AIRPLANE_MODE_SETTINGS
                            "location" -> Settings.ACTION_LOCATION_SOURCE_SETTINGS
                            "display" -> Settings.ACTION_DISPLAY_SETTINGS
                            "sound" -> Settings.ACTION_SOUND_SETTINGS
                            "apps" -> Settings.ACTION_MANAGE_ALL_APPLICATIONS_SETTINGS
                            else -> null
                        }
                        if (action == null) {
                            result.success(false)
                        } else {
                            try {
                                startActivity(Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                                result.success(true)
                            } catch (_: Exception) {
                                if (type == "apps") {
                                    try {
                                        startActivity(
                                            Intent(Settings.ACTION_APPLICATION_SETTINGS)
                                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                        )
                                        result.success(true)
                                    } catch (_: Exception) {
                                        result.success(false)
                                    }
                                } else {
                                    result.success(false)
                                }
                            }
                        }
                    }
                    else -> {
                        result.notImplemented()
                    }
                }
            }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CONTACTS_PERMISSION_REQUEST_CODE) {
            val isGranted = grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingContactsResult?.success(isGranted)
            pendingContactsResult = null
        }
    }

    private fun isNotificationListenerPermissionGranted(): Boolean {
        if (FlamesNotificationListenerService.isConnected()) {
            return true
        }
        return try {
            val enabledListeners = NotificationManagerCompat.getEnabledListenerPackages(this)
            if (enabledListeners.contains(packageName)) {
                return true
            }
            val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
            if (flat != null && (flat.contains(packageName) || flat.contains("FlamesNotificationListenerService"))) {
                return true
            }
            false
        } catch (_: Exception) {
            false
        }
    }
}
