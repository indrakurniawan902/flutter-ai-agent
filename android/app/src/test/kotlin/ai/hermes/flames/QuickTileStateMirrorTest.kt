package ai.hermes.flames

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class QuickTileStateMirrorTest {

    /**
     * Verbatim port of the state semantics in FlamesQuickTile as of T26.3:
     * the bound-instance flag is never cleared by onStopListening, the last live
     * tile state survives the unbind as a stale value, a write is silently
     * dropped while the tile is detached, and report() prefers the live state
     * whenever the bound flag is set.
     */
    private class LegacyTileStateMirror {
        companion object {
            const val STATE_UNAVAILABLE = 0
            const val STATE_INACTIVE = 1
            const val STATE_ACTIVE = 2
        }

        private var isActive: Boolean = false
        private var instanceBound: Boolean = false
        private var tileAttached: Boolean = false
        private var liveTileState: Int? = null

        fun onBind(liveState: Int?) {
            instanceBound = true
            tileAttached = true
            liveTileState = liveState
        }

        fun onUnbind(liveState: Int?) {
            liveTileState = liveState
            tileAttached = false
            // onStopListening() never clears currentInstance
        }

        fun setActive(active: Boolean) {
            isActive = active
            if (tileAttached) {
                liveTileState = if (active) STATE_ACTIVE else STATE_INACTIVE
            }
            // detached: the push is silently dropped
        }

        fun report(): String {
            return if (!instanceBound) {
                if (isActive) "active" else "inactive"
            } else {
                when (liveTileState) {
                    STATE_ACTIVE -> "active"
                    STATE_INACTIVE -> "inactive"
                    STATE_UNAVAILABLE -> "unavailable"
                    else -> if (isActive) "active" else "inactive"
                }
            }
        }
    }

    @Test
    fun unbound_setActiveTrueThenFalse_reportAgreesWithEachWrite() {
        val mirror = QuickTileStateMirror()
        assertFalse(mirror.bound)
        assertTrue(mirror.setActive(true))
        assertEquals("active", mirror.report())
        assertTrue(mirror.setActive(false))
        assertEquals("inactive", mirror.report())
    }

    @Test
    fun unbound_sixConsecutiveToggles_alternateEveryTime() {
        val mirror = QuickTileStateMirror()
        var expected = true
        for (toggle in 0 until 6) {
            assertTrue("toggle $toggle must report a change", mirror.setActive(expected))
            assertEquals(
                if (expected) "active" else "inactive",
                mirror.report()
            )
            expected = !expected
        }
    }

    @Test
    fun bind_activeState_reportsActive() {
        val mirror = QuickTileStateMirror()
        mirror.onBind(QuickTileStateMirror.STATE_ACTIVE)
        assertTrue(mirror.isActive)
        assertEquals("active", mirror.report())
    }

    @Test
    fun bind_inactiveState_reportsInactive() {
        val mirror = QuickTileStateMirror()
        mirror.onBind(QuickTileStateMirror.STATE_INACTIVE)
        assertFalse(mirror.isActive)
        assertEquals("inactive", mirror.report())
    }

    @Test
    fun bind_unavailableState_leavesIsActiveUntouched() {
        val mirror = QuickTileStateMirror()
        assertFalse(mirror.isActive)
        mirror.onBind(QuickTileStateMirror.STATE_UNAVAILABLE)
        assertFalse(mirror.isActive)

        val activeMirror = QuickTileStateMirror()
        assertTrue(activeMirror.setActive(true))
        activeMirror.onBind(QuickTileStateMirror.STATE_UNAVAILABLE)
        assertTrue(activeMirror.isActive)
        assertEquals("active", activeMirror.report())
    }

    @Test
    fun bind_nullState_leavesIsActiveUntouched() {
        val mirror = QuickTileStateMirror()
        assertTrue(mirror.setActive(true))
        mirror.onBind(null)
        assertTrue(mirror.bound)
        assertTrue(mirror.isActive)
        assertEquals("active", mirror.report())
    }

    @Test
    fun unbind_inactiveAfterActive_reconcilesThenUnbinds() {
        val mirror = QuickTileStateMirror()
        mirror.onBind(QuickTileStateMirror.STATE_ACTIVE)
        assertEquals("active", mirror.report())
        mirror.onUnbind(QuickTileStateMirror.STATE_INACTIVE)
        assertFalse(mirror.bound)
        assertFalse(mirror.isActive)
        assertEquals("inactive", mirror.report())
    }

    @Test
    fun unbindStaleActive_thenTwoTogglesAlternateInsteadOfRepeating() {
        val mirror = QuickTileStateMirror()
        mirror.onBind(QuickTileStateMirror.STATE_INACTIVE)
        assertFalse(mirror.isActive)
        assertTrue(mirror.setActive(true))
        assertEquals("active", mirror.report())

        mirror.onUnbind(QuickTileStateMirror.STATE_ACTIVE)
        assertFalse(mirror.bound)

        assertTrue(mirror.setActive(false))
        assertEquals("inactive", mirror.report())
        assertTrue(mirror.setActive(true))
        assertEquals("active", mirror.report())
        assertTrue(mirror.setActive(false))
        assertEquals("inactive", mirror.report())
    }

    @Test
    fun unboundUnavailable_reportsUnavailable_untilSetActive() {
        val mirror = QuickTileStateMirror()
        mirror.onBind(QuickTileStateMirror.STATE_UNAVAILABLE)
        mirror.onUnbind(QuickTileStateMirror.STATE_UNAVAILABLE)
        assertFalse(mirror.bound)
        assertEquals("unavailable", mirror.report())
        assertTrue(mirror.setActive(true))
        assertNotEquals("unavailable", mirror.report())
        assertEquals("active", mirror.report())
    }

    @Test
    fun setActive_returnsWhetherIsActiveChanged() {
        val mirror = QuickTileStateMirror()
        assertTrue(mirror.setActive(true))
        assertFalse(mirror.setActive(true))
        assertTrue(mirror.setActive(false))
        assertFalse(mirror.setActive(false))
    }

    @Test
    fun bound_tracksBindAndUnbind() {
        val mirror = QuickTileStateMirror()
        assertFalse(mirror.bound)
        mirror.onBind(QuickTileStateMirror.STATE_INACTIVE)
        assertTrue(mirror.bound)
        mirror.onUnbind(QuickTileStateMirror.STATE_INACTIVE)
        assertFalse(mirror.bound)
    }

    @Test
    fun pendingLocalWrite_survivesBindWithStaleLiveState() {
        val mirror = QuickTileStateMirror()
        assertTrue(mirror.setActive(true))
        assertTrue(mirror.hasPendingLocalWrite)
        mirror.onBind(QuickTileStateMirror.STATE_INACTIVE)
        assertTrue(mirror.isActive)
        assertEquals("active", mirror.report())
    }

    @Test
    fun onBind_adoptsLiveState_whenNoPendingWrite() {
        val mirror = QuickTileStateMirror()
        mirror.setActive(false)
        mirror.markSyncedToTile()
        mirror.onBind(QuickTileStateMirror.STATE_ACTIVE)
        assertTrue(mirror.isActive)
        assertEquals("active", mirror.report())
    }

    @Test
    fun markSyncedToTile_clearsPending_andBindAdoptsAgain() {
        val mirror = QuickTileStateMirror()
        assertTrue(mirror.setActive(true))
        assertTrue(mirror.hasPendingLocalWrite)
        mirror.markSyncedToTile()
        assertFalse(mirror.hasPendingLocalWrite)
        mirror.onBind(QuickTileStateMirror.STATE_INACTIVE)
        assertFalse(mirror.isActive)
        assertEquals("inactive", mirror.report())
    }

    @Test
    fun onUnbind_withPendingWrite_doesNotRevertLocalValue() {
        val mirror = QuickTileStateMirror()
        assertTrue(mirror.setActive(true))
        mirror.onUnbind(QuickTileStateMirror.STATE_INACTIVE)
        assertFalse(mirror.bound)
        assertTrue(mirror.isActive)
        assertEquals("active", mirror.report())
    }

    @Test
    fun markSyncedToTile_isNoOpForIsActive() {
        val mirror = QuickTileStateMirror()
        mirror.setActive(true)
        mirror.markSyncedToTile()
        assertTrue(mirror.isActive)
        assertEquals("active", mirror.report())
    }

    @Test
    fun legacyPort_reproducesReportDisagreeingWithLastWrite() {
        val legacy = LegacyTileStateMirror()
        legacy.onBind(LegacyTileStateMirror.STATE_INACTIVE)
        legacy.setActive(true)
        assertEquals("active", legacy.report())

        legacy.onUnbind(LegacyTileStateMirror.STATE_ACTIVE)
        legacy.setActive(false)
        assertNotEquals("legacy report must disagree with the last write", "inactive", legacy.report())
        assertEquals("active", legacy.report())

        legacy.setActive(true)
        assertEquals("active", legacy.report())
        legacy.setActive(false)
        assertEquals("both post-unbind toggles must report active", "active", legacy.report())
    }
}
