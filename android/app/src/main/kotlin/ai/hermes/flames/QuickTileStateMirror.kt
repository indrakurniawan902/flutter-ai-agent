package ai.hermes.flames

/**
 * Framework-free mirror of the QuickTile reporting state.
 *
 * The static flag is the ONE source of truth for reporting. The live tile
 * state is reconciled into it at every bind/unbind and is never the read
 * source that can contradict the last write.
 */
class QuickTileStateMirror {

    companion object {
        const val STATE_UNAVAILABLE = 0
        const val STATE_INACTIVE = 1
        const val STATE_ACTIVE = 2
    }

    var isActive: Boolean = false
        private set

    var bound: Boolean = false
        private set

    private var lastLiveState: Int? = null

    fun onBind(liveState: Int?) {
        reconcile(liveState)
        bound = true
    }

    fun onUnbind(liveState: Int?) {
        reconcile(liveState)
        bound = false
    }

    fun setActive(active: Boolean): Boolean {
        val changed = isActive != active
        isActive = active
        lastLiveState = null
        return changed
    }

    fun report(): String {
        if (!bound && lastLiveState == STATE_UNAVAILABLE) return "unavailable"
        return if (isActive) "active" else "inactive"
    }

    private fun reconcile(liveState: Int?) {
        lastLiveState = liveState
        when (liveState) {
            STATE_ACTIVE -> isActive = true
            STATE_INACTIVE -> isActive = false
        }
    }
}
