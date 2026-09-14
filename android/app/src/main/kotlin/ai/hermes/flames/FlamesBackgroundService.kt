package ai.hermes.flames

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.MethodChannel

class FlamesBackgroundService : Service() {

    companion object {
        const val CHANNEL_ID = "flames_agent_foreground"
        const val CHANNEL_NAME = "Flames Agent Background Service"
        const val NOTIFICATION_ID = 9001

        const val ACTION_START_SERVICE = "ai.hermes.flames.action.START_SERVICE"
        const val ACTION_STOP_SERVICE = "ai.hermes.flames.action.STOP_SERVICE"
        const val ACTION_UPDATE_NOTIFICATION = "ai.hermes.flames.action.UPDATE_NOTIFICATION"
        const val ACTION_VOICE_INPUT = "ai.hermes.flames.action.VOICE_INPUT"
        const val ACTION_QUICK_STATUS = "ai.hermes.flames.action.QUICK_STATUS"

        const val EXTRA_TITLE = "extra_title"
        const val EXTRA_CONTENT = "extra_content"
        const val EXTRA_ACTION = "extra_flames_action"

        private const val WAKELOCK_TAG = "Flames:SafeBackgroundWakeLock"
        const val MIN_WAKELOCK_TIMEOUT_MS = 1000L
        const val DEFAULT_WAKELOCK_TIMEOUT_MS = 30000L
        const val MAX_WAKELOCK_TIMEOUT_MS = 60000L

        @Volatile
        var isServiceRunning: Boolean = false
            private set

        private var wakeLock: PowerManager.WakeLock? = null

        fun startService(context: Context, title: String? = null, content: String? = null) {
            val intent = Intent(context, FlamesBackgroundService::class.java).apply {
                action = ACTION_START_SERVICE
                if (title != null) putExtra(EXTRA_TITLE, title)
                if (content != null) putExtra(EXTRA_CONTENT, content)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stopService(context: Context) {
            val intent = Intent(context, FlamesBackgroundService::class.java).apply {
                action = ACTION_STOP_SERVICE
            }
            context.startService(intent)
        }

        fun updateNotification(context: Context, title: String, content: String) {
            val intent = Intent(context, FlamesBackgroundService::class.java).apply {
                action = ACTION_UPDATE_NOTIFICATION
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_CONTENT, content)
            }
            context.startService(intent)
        }

        fun acquireWakeLock(context: Context, timeoutMs: Long = DEFAULT_WAKELOCK_TIMEOUT_MS): Boolean {
            return try {
                val safeTimeout = timeoutMs.coerceIn(MIN_WAKELOCK_TIMEOUT_MS, MAX_WAKELOCK_TIMEOUT_MS)
                val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return false
                if (wakeLock == null) {
                    wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKELOCK_TAG).apply {
                        setReferenceCounted(false)
                    }
                }
                wakeLock?.let {
                    if (!it.isHeld) {
                        it.acquire(safeTimeout)
                    }
                }
                true
            } catch (_: Exception) {
                false
            }
        }

        fun releaseWakeLock(): Boolean {
            return try {
                wakeLock?.let {
                    if (it.isHeld) {
                        it.release()
                    }
                }
                true
            } catch (_: Exception) {
                false
            }
        }

        fun isWakeLockHeld(): Boolean {
            return wakeLock?.isHeld == true
        }

        @Volatile
        private var dartChannel: MethodChannel? = null

        /** Called by MainActivity once the Flutter engine exists. */
        fun attachDartChannel(channel: MethodChannel?) {
            dartChannel = channel
        }

        /** Called when the activity (and therefore the engine) goes away. */
        fun detachDartChannel() {
            dartChannel = null
        }

        fun hasDartChannel(): Boolean = dartChannel != null
    }

    private var currentTitle: String = "Flames Agent Active"
    private var currentContent: String = "Listening and ready in background"

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_START_SERVICE

        when (action) {
            ACTION_STOP_SERVICE -> {
                stopForegroundServiceInternal()
                return START_NOT_STICKY
            }
            ACTION_UPDATE_NOTIFICATION -> {
                intent?.getStringExtra(EXTRA_TITLE)?.let { currentTitle = it }
                intent?.getStringExtra(EXTRA_CONTENT)?.let { currentContent = it }
                val notification = buildForegroundNotification(currentTitle, currentContent)
                val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                notificationManager?.notify(NOTIFICATION_ID, notification)
                return START_STICKY
            }
            ACTION_START_SERVICE -> {
                intent?.getStringExtra(EXTRA_TITLE)?.let { currentTitle = it }
                intent?.getStringExtra(EXTRA_CONTENT)?.let { currentContent = it }
                val notification = buildForegroundNotification(currentTitle, currentContent)
                startForeground(NOTIFICATION_ID, notification)
                isServiceRunning = true
                FlamesQuickTile.updateTileState(true)
                return START_STICKY
            }
            ACTION_VOICE_INPUT -> {
                // Runs the turn inside this service: no MainActivity, no ChatScreen.
                // The Dart seam only exists while a Flutter engine is alive, so an
                // engine-less tap is reported honestly instead of opening the app.
                val channel = dartChannel
                if (channel != null) {
                    Handler(Looper.getMainLooper()).post {
                        try {
                            channel.invokeMethod("onActionReceived", "voice_input")
                        } catch (_: Exception) {
                        }
                    }
                    currentContent = "Voice turn running"
                } else {
                    currentContent = "Flames is not running - open it once to enable voice turns"
                }
                val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                notificationManager?.notify(NOTIFICATION_ID, buildForegroundNotification(currentTitle, currentContent))
                return START_STICKY
            }
            else -> return START_STICKY
        }
    }

    override fun onDestroy() {
        releaseWakeLock()
        isServiceRunning = false
        FlamesQuickTile.updateTileState(false)
        super.onDestroy()
    }

    private fun stopForegroundServiceInternal() {
        releaseWakeLock()
        isServiceRunning = false
        FlamesQuickTile.updateTileState(false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps Flames Agent running with action controls"
                setShowBadge(false)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            manager?.createNotificationChannel(channel)
        }
    }

    private fun buildForegroundNotification(title: String, content: String): Notification {
        // Main tap intent -> opens MainActivity
        val openAppIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val openAppPendingIntent = PendingIntent.getActivity(
            this,
            0,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Voice Input is handled by this service and reaches the live Flutter
        // engine through the Dart channel; it must not launch the UI.
        val voiceIntent = Intent(this, FlamesBackgroundService::class.java).apply {
            action = ACTION_VOICE_INPUT
        }
        val voicePendingIntent = PendingIntent.getService(
            this,
            1,
            voiceIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Action 2: Quick Status Action
        val statusIntent = Intent(this, MainActivity::class.java).apply {
            action = ACTION_QUICK_STATUS
            putExtra(EXTRA_ACTION, "quick_status")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val statusPendingIntent = PendingIntent.getActivity(
            this,
            2,
            statusIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Action 3: Stop Action
        val stopIntent = Intent(this, FlamesBackgroundService::class.java).apply {
            action = ACTION_STOP_SERVICE
        }
        val stopPendingIntent = PendingIntent.getService(
            this,
            3,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val smallIcon = applicationInfo.icon.let { if (it != 0) it else android.R.drawable.ic_dialog_info }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(content)
            .setSmallIcon(smallIcon)
            .setContentIntent(openAppPendingIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .addAction(android.R.drawable.ic_btn_speak_now, "Voice Input", voicePendingIntent)
            .addAction(android.R.drawable.ic_menu_info_details, "Quick Status", statusPendingIntent)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", stopPendingIntent)
            .build()
    }
}
