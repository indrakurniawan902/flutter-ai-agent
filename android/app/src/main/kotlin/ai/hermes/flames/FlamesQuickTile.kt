package ai.hermes.flames

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
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    tile.subtitle = if (active) "Listening" else "Tap for one voice turn"
                }
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

        _isTileActive = false
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
        val isActive = _isTileActive
        tile.state = if (isActive) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = "Flames Agent"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = if (isActive) "Listening" else "Tap for one voice turn"
        }
        tile.updateTile()
    }
}
