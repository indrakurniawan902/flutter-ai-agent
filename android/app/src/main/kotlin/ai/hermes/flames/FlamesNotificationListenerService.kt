package ai.hermes.flames

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

class FlamesNotificationListenerService : NotificationListenerService() {

    companion object {
        private const val MAX_BUFFER_SIZE = 100
        private val recentNotifications = ArrayDeque<Map<String, Any?>>()

        @Synchronized
        fun addNotification(entry: Map<String, Any?>) {
            recentNotifications.addLast(entry)
            while (recentNotifications.size > MAX_BUFFER_SIZE) {
                recentNotifications.removeFirst()
            }
        }

        @Synchronized
        fun getNotifications(): List<Map<String, Any?>> = recentNotifications.toList()

        @Synchronized
        fun clearAll() {
            recentNotifications.clear()
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        val extras = sbn.notification.extras
        val entry: Map<String, Any?> = mapOf(
            "packageName" to sbn.packageName,
            "id" to sbn.id,
            "postTime" to sbn.postTime,
            "title" to (extras.getCharSequence("android.title")?.toString()),
            "text" to (extras.getCharSequence("android.text")?.toString()),
        )
        addNotification(entry)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
    }
}
