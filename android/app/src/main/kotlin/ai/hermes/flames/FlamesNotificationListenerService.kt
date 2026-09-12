package ai.hermes.flames

import android.app.Notification
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import java.util.concurrent.ConcurrentLinkedDeque

class FlamesNotificationListenerService : NotificationListenerService() {
    companion object {
        private const val MAX_BUFFER_SIZE = 100
        private val notificationBuffer = ConcurrentLinkedDeque<Map<String, Any?>>()
        private var instance: FlamesNotificationListenerService? = null

        fun getRecentNotifications(limit: Int = 20): List<Map<String, Any?>> {
            val clampedLimit = if (limit <= 0) 1 else limit
            return notificationBuffer.take(clampedLimit)
        }

        fun clearBuffer() {
            notificationBuffer.clear()
        }

        fun isConnected(): Boolean = instance != null
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        instance = this
        try {
            activeNotifications?.forEach { sbn ->
                processNotification(sbn)
            }
        } catch (_: Exception) {}
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        instance = null
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        sbn?.let { processNotification(it) }
    }

    private fun processNotification(sbn: StatusBarNotification) {
        val notification = sbn.notification ?: return
        val extras: Bundle = notification.extras ?: Bundle()

        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
            ?: extras.getCharSequence(Notification.EXTRA_TITLE_BIG)?.toString()
            ?: ""

        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
            ?: extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
            ?: extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString()
            ?: ""

        if (title.isBlank() && text.isBlank()) return

        val packageName = sbn.packageName ?: ""
        val postTime = if (sbn.postTime > 0) sbn.postTime else System.currentTimeMillis()
        val id = "${sbn.id}_${sbn.key}"

        val entry = mapOf<String, Any?>(
            "id" to id,
            "packageName" to packageName,
            "title" to title,
            "text" to text,
            "timestamp" to postTime
        )

        notificationBuffer.removeIf { it["id"] == id }
        notificationBuffer.addFirst(entry)

        while (notificationBuffer.size > MAX_BUFFER_SIZE) {
            notificationBuffer.removeLast()
        }
    }
}
