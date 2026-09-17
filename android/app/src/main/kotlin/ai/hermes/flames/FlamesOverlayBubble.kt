package ai.hermes.flames

import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.ImageView
import kotlin.math.hypot

/**
 * Programmatic floating bubble drawn over other apps (SYSTEM_ALERT_WINDOW).
 *
 * Owned by [FlamesBackgroundService] so it survives the activity being
 * destroyed and dies with the service. No layout or drawable resources:
 * the view is built entirely in code. Tap opens the app; long-press
 * starts/stops the voice turn. Every public entry point is exception-safe
 * and never throws.
 */
object FlamesOverlayBubble {
    private const val IDLE_FILL = 0xFF008080.toInt()
    private const val RECORDING_FILL = 0xFFDC2626.toInt()
    private const val BUBBLE_ALPHA = 0.95f
    private const val BUBBLE_SIZE_DP = 56
    private const val BUBBLE_TOP_DP = 120
    private const val DRAG_SLOP_PX = 10f
    private const val TAP_MAX_DURATION_MS = 250L

    private var windowManager: WindowManager? = null
    private var bubbleView: ImageView? = null

    fun show(context: Context, onTap: () -> Unit, onLongPress: () -> Unit): Boolean {
        return try {
            if (!Settings.canDrawOverlays(context)) {
                false
            } else if (isVisible()) {
                true
            } else {
                val manager = context.getSystemService(Context.WINDOW_SERVICE) as? WindowManager
                if (manager == null) {
                    false
                } else {
                    val size = dp(context, BUBBLE_SIZE_DP)
                    val view = ImageView(context).apply {
                        setImageResource(android.R.drawable.ic_btn_speak_now)
                        scaleType = ImageView.ScaleType.CENTER
                        alpha = BUBBLE_ALPHA
                        background = buildOval(context, IDLE_FILL, false)
                    }
                    val params = WindowManager.LayoutParams(
                        size,
                        size,
                        WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                        PixelFormat.TRANSLUCENT
                    ).apply {
                        gravity = Gravity.TOP or Gravity.START
                        x = 0
                        y = dp(context, BUBBLE_TOP_DP)
                    }
                    view.setOnTouchListener(
                        buildTouchListener(context, view, params, onTap, onLongPress)
                    )
                    manager.addView(view, params)
                    windowManager = manager
                    bubbleView = view
                    true
                }
            }
        } catch (_: Exception) {
            false
        }
    }

    fun hide(context: Context) {
        val view = bubbleView
        bubbleView = null
        try {
            if (view != null) {
                windowManager?.removeView(view)
            }
        } catch (_: Exception) {
        } finally {
            windowManager = null
        }
    }

    fun isVisible(): Boolean = bubbleView != null

    fun setRecording(recording: Boolean) {
        try {
            val view = bubbleView ?: return
            view.background = buildOval(
                view.context,
                if (recording) RECORDING_FILL else IDLE_FILL,
                recording
            )
        } catch (_: Exception) {
        }
    }

    private fun buildTouchListener(
        context: Context,
        view: View,
        params: WindowManager.LayoutParams,
        onTap: () -> Unit,
        onLongPress: () -> Unit
    ): View.OnTouchListener {
        var downRawX = 0f
        var downRawY = 0f
        var downX = 0
        var downY = 0
        var downTime = 0L
        var lastRawX = 0f
        var lastRawY = 0f
        var movedDistance = 0f

        return View.OnTouchListener { _, event ->
            try {
                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        downRawX = event.rawX
                        downRawY = event.rawY
                        lastRawX = downRawX
                        lastRawY = downRawY
                        downX = params.x
                        downY = params.y
                        downTime = System.currentTimeMillis()
                        movedDistance = 0f
                    }
                    MotionEvent.ACTION_MOVE -> {
                        movedDistance += hypot(
                            event.rawX - lastRawX,
                            event.rawY - lastRawY
                        )
                        lastRawX = event.rawX
                        lastRawY = event.rawY
                        params.x = downX + (event.rawX - downRawX).toInt()
                        params.y = downY + (event.rawY - downRawY).toInt()
                        clampY(context, params)
                        windowManager?.updateViewLayout(view, params)
                    }
                    MotionEvent.ACTION_UP -> {
                        val elapsed = System.currentTimeMillis() - downTime
                        if (movedDistance < DRAG_SLOP_PX) {
                            if (elapsed < TAP_MAX_DURATION_MS) {
                                try {
                                    onTap()
                                } catch (_: Exception) {
                                }
                            } else {
                                try {
                                    onLongPress()
                                } catch (_: Exception) {
                                }
                            }
                        } else {
                            snapToEdge(context, view, params)
                        }
                    }
                }
            } catch (_: Exception) {
            }
            true
        }
    }

    private fun snapToEdge(
        context: Context,
        view: View,
        params: WindowManager.LayoutParams
    ) {
        try {
            clampY(context, params)
            val screenWidth = context.resources.displayMetrics.widthPixels
            val leftDistance = params.x + params.width / 2
            params.x = if (leftDistance < screenWidth / 2) {
                0
            } else {
                screenWidth - params.width
            }
            windowManager?.updateViewLayout(view, params)
        } catch (_: Exception) {
        }
    }

    private fun clampY(context: Context, params: WindowManager.LayoutParams) {
        val screenHeight = context.resources.displayMetrics.heightPixels
        val maxY = maxOf(0, screenHeight - params.height)
        params.y = params.y.coerceIn(0, maxY)
    }

    private fun buildOval(context: Context, fill: Int, recording: Boolean): GradientDrawable {
        val oval = GradientDrawable()
        oval.shape = GradientDrawable.OVAL
        oval.setColor(fill)
        if (recording) {
            oval.setStroke(dp(context, 2), Color.WHITE)
        }
        return oval
    }

    private fun dp(context: Context, value: Int): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            value.toFloat(),
            context.resources.displayMetrics
        ).toInt()
    }
}
