package ai.hermes.flames

import android.app.Activity
import android.content.Intent
import android.os.Bundle

class RationaleActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            startActivity(Intent("androidx.health.ACTION_HEALTH_CONNECT_SETTINGS"))
        } catch (_: Throwable) {
        } finally {
            finish()
        }
    }
}
