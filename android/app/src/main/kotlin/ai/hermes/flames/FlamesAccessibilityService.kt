package ai.hermes.flames

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.graphics.Rect
import android.provider.Settings
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * READ-ONLY accessibility-tree reader.
 *
 * Permission fact vs liveness are separate, exactly like
 * [FlamesNotificationListenerService]: [isEnabledInSettings] is the user's
 * Settings choice and may be true while the service instance is dead;
 * [isConnected] is whether the instance is actually alive right now.
 */
class FlamesAccessibilityService : AccessibilityService() {
    private var lastEventPackage: String? = null

    companion object {
        private var instance: FlamesAccessibilityService? = null

        fun isConnected(): Boolean = instance != null

        /**
         * PERMISSION fact only: true when this package is listed as an enabled
         * accessibility service. A stale entry can survive the user disabling
         * the service, so this never implies liveness — see [isConnected].
         */
        fun isEnabledInSettings(context: Context): Boolean {
            return try {
                val enabled = Settings.Secure.getInt(
                    context.contentResolver,
                    Settings.Secure.ACCESSIBILITY_ENABLED
                )
                if (enabled != 1) {
                    return false
                }
                val flat = Settings.Secure.getString(
                    context.contentResolver,
                    Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
                ) ?: return false
                val prefix = "${context.packageName}/"
                flat.split(':').any { it.startsWith(prefix) }
            } catch (_: Exception) {
                false
            }
        }

        fun captureTree(maxNodes: Int, maxDepth: Int): Map<String, Any?>? {
            val service = instance ?: return null
            val root = try {
                service.rootInActiveWindow
            } catch (_: Exception) {
                null
            } ?: return null

            val nodes = mutableListOf<Map<String, Any?>>()
            val queue = ArrayDeque<Pair<AccessibilityNodeInfo, Int>>()
            queue.addLast(root to 0)
            var truncated = false

            while (queue.isNotEmpty()) {
                if (nodes.size >= maxNodes) {
                    truncated = true
                    break
                }
                val (node, depth) = queue.removeFirst()
                try {
                    // Secure fields: drop the node AND its whole subtree so
                    // password text is never collected, even when the platform
                    // or OEM does not redact it. Skipping the children too
                    // avoids leaking the field's hint/label descendants.
                    if (node.isPassword) {
                        continue
                    }
                    val rect = Rect()
                    node.getBoundsInScreen(rect)
                    nodes.add(
                        mapOf<String, Any?>(
                            "role" to (node.className?.toString()?.substringAfterLast('.') ?: ""),
                            "text" to (node.text?.toString() ?: ""),
                            "contentDescription" to (node.contentDescription?.toString() ?: ""),
                            "packageName" to (node.packageName?.toString() ?: ""),
                            "clickable" to node.isClickable,
                            "focusable" to node.isFocusable,
                            "editable" to node.isEditable,
                            "scrollable" to node.isScrollable,
                            "depth" to depth,
                            "bounds" to "${rect.left},${rect.top},${rect.right},${rect.bottom}"
                        )
                    )

                    if (depth < maxDepth) {
                        for (i in 0 until node.childCount) {
                            try {
                                val child = node.getChild(i) ?: continue
                                queue.addLast(child to (depth + 1))
                            } catch (_: Exception) {
                            }
                        }
                    }
                } catch (_: Exception) {
                }
            }

            val packageName = try {
                root.packageName?.toString() ?: ""
            } catch (_: Exception) {
                ""
            }

            return mapOf<String, Any?>(
                "packageName" to packageName,
                "nodes" to nodes,
                "truncated" to truncated
            )
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        lastEventPackage = event?.packageName?.toString()
    }

    override fun onInterrupt() {
        // Required override: there is no in-flight feedback to interrupt.
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }
}
