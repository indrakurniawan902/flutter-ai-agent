package ai.hermes.flames

import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

class FlamesQuickTile : TileService() {

    companion object {
        const val ACTION_QUICK_TILE_TRIGGER = "ai.hermes.flames.action.QUICK_TILE_TRIGGER"
        const val EXTRA_ACTION = "extra_flames_action"

        private val mirror = QuickTileStateMirror()

        var isTileActive: Boolean
            get() = mirror.isActive
            set(value) {
                mirror.setActive(value)
            }

        private var currentInstance: FlamesQuickTile? = null

        fun updateTileState(active: Boolean) {
            mirror.setActive(active)
            val service = currentInstance ?: return
            val tile = service.qsTile ?: return
            tile.state = if (active) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                tile.subtitle = if (active) "Listening" else "Tap for one voice turn"
            }
            tile.updateTile()
            mirror.markSyncedToTile()
        }

        fun getTileStateString(): String {
            return mirror.report()
        }

        private fun liveStateOf(service: FlamesQuickTile): Int? {
            return when (service.qsTile?.state) {
                Tile.STATE_ACTIVE -> QuickTileStateMirror.STATE_ACTIVE
                Tile.STATE_INACTIVE -> QuickTileStateMirror.STATE_INACTIVE
                Tile.STATE_UNAVAILABLE -> QuickTileStateMirror.STATE_UNAVAILABLE
                else -> null
            }
        }
    }

    override fun onTileAdded() {
        super.onTileAdded()
        currentInstance = this
        mirror.onBind(liveStateOf(this))
        syncTileAppearance()
    }

    override fun onStartListening() {
        super.onStartListening()
        currentInstance = this
        mirror.onBind(liveStateOf(this))
        syncTileAppearance()
    }

    override fun onStopListening() {
        super.onStopListening()
        mirror.onUnbind(liveStateOf(this))
        currentInstance = null
    }

    override fun onTileRemoved() {
        super.onTileRemoved()

        if (FlamesBackgroundService.isServiceRunning || isTileActive) {
            val intent = Intent(this, FlamesBackgroundService::class.java).apply {
                action = FlamesBackgroundService.ACTION_CANCEL_VOICE
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(intent)
                } else {
                    startService(intent)
                }
            } catch (_: Exception) {
            }
        }

        mirror.onUnbind(liveStateOf(this))
        currentInstance = null
        mirror.setActive(false)
    }

    override fun onClick() {
        super.onClick()
        if (qsTile == null) return

        val intent = Intent(this, FlamesBackgroundService::class.java).apply {
            action = FlamesBackgroundService.ACTION_VOICE_INPUT
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (_: Exception) {
            FlamesQuickTile.updateTileState(false)
        }
    }

    private fun syncTileAppearance() {
        val tile = qsTile ?: return
        val isActive = mirror.isActive
        tile.state = if (isActive) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = "Flames Agent"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = if (isActive) "Listening" else "Tap for one voice turn"
        }
        tile.updateTile()
        mirror.markSyncedToTile()
    }
}
