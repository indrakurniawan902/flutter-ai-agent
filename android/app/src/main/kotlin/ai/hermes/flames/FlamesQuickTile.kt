package ai.hermes.flames

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

class FlamesQuickTile : TileService() {

    companion object {
        const val ACTION_QUICK_TILE_TRIGGER = "ai.hermes.flames.action.QUICK_TILE_TRIGGER"
        const val EXTRA_ACTION = "extra_flames_action"

        private var _isTileActive: Boolean = false
        var isTileActive: Boolean
            get() = _isTileActive
            set(value) {
                _isTileActive = value
            }

        private var currentInstance: FlamesQuickTile? = null

        fun updateTileState(active: Boolean) {
            _isTileActive = active
            currentInstance?.let { service ->
                val tile = service.qsTile ?: return@let
                tile.state = if (active) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
                tile.updateTile()
            }
        }

        fun getTileStateString(): String {
            return if (currentInstance == null) {
                if (_isTileActive) "active" else "inactive"
            } else {
                val tile = currentInstance?.qsTile
                when (tile?.state) {
                    Tile.STATE_ACTIVE -> "active"
                    Tile.STATE_INACTIVE -> "inactive"
                    Tile.STATE_UNAVAILABLE -> "unavailable"
                    else -> if (_isTileActive) "active" else "inactive"
                }
            }
        }
    }

    override fun onTileAdded() {
        super.onTileAdded()
        currentInstance = this
        syncTileAppearance()
    }

    override fun onStartListening() {
        super.onStartListening()
        currentInstance = this
        syncTileAppearance()
    }

    override fun onStopListening() {
        super.onStopListening()
    }

    override fun onTileRemoved() {
        super.onTileRemoved()
        currentInstance = null
    }

    override fun onDestroy() {
        if (currentInstance == this) {
            currentInstance = null
        }
        super.onDestroy()
    }

    override fun onClick() {
        super.onClick()
        val tile = qsTile ?: return

        // Toggle state
        val willBeActive = tile.state != Tile.STATE_ACTIVE
        _isTileActive = willBeActive
        tile.state = if (willBeActive) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.updateTile()

        // 1-Tap Activation: Bring Flames Agent to foreground or start voice interaction
        val intent = Intent(this, MainActivity::class.java).apply {
            action = ACTION_QUICK_TILE_TRIGGER
            putExtra(EXTRA_ACTION, "voice_input")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val pendingIntent = PendingIntent.getActivity(
                this,
                1001,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            startActivityAndCollapse(pendingIntent)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }

        // Keep background service in sync if active
        if (willBeActive && !FlamesBackgroundService.isServiceRunning) {
            FlamesBackgroundService.startService(this, "Flames Agent Active", "Activated via Quick Settings Tile")
        }
    }

    private fun syncTileAppearance() {
        val tile = qsTile ?: return
        val isActive = _isTileActive || FlamesBackgroundService.isServiceRunning
        tile.state = if (isActive) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = "Flames Agent"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = if (isActive) "Ready / Active" else "Tap to Activate"
        }
        tile.updateTile()
    }
}
