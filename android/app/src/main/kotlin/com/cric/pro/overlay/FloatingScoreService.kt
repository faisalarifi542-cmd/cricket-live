package com.cric.pro.overlay

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.GestureDetector
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import com.cric.pro.MainActivity
import com.cric.pro.R
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Foreground service that renders the optional "Floating Score over other apps"
 * bubble and polls the fast live-score endpoint while it is visible.
 *
 * Lifecycle: started by [OverlayBridge] only after the user has granted overlay
 * permission and tapped Enable. Stops itself when the user closes the bubble,
 * the match completes, or Flutter sends ACTION_STOP. No work survives that.
 *
 * Privacy: shows score only. Reads no screen content. Polls a single match id.
 */
class FloatingScoreService : Service() {

    private lateinit var windowManager: WindowManager
    private var bubbleView: View? = null
    private var layoutParams: WindowManager.LayoutParams? = null

    private var poller: ScheduledExecutorService? = null
    private val main = Handler(Looper.getMainLooper())

    private var matchId: String = ""
    private var baseUrl: String = ""
    private var apiKey: String = ""
    private var clientType: String = "android"
    private var appVersion: String = ""
    private var packageNameHeader: String = ""

    // Last-known display values so a failed fetch keeps the previous score.
    private var teamALine: String = ""
    private var teamBLine: String = ""
    private var statusLine: String = ""
    private var isLive: Boolean = true

    // User-chosen bubble size. Double-tapping cycles compact -> normal -> large
    // and wraps back. Persisted so the choice survives the next overlay start.
    private var sizeIndex: Int = SIZE_NORMAL

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        sizeIndex = prefs().getInt(KEY_SIZE_INDEX, SIZE_NORMAL)
            .coerceIn(SIZE_COMPACT, SIZE_LARGE)
        createNotificationChannel()
    }

    private fun prefs(): SharedPreferences =
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            Log.d(TAG, "service stop (action)")
            stopSelfClean()
            return START_NOT_STICKY
        }

        // Overlay uses TYPE_APPLICATION_OVERLAY + channel notifications (API 26+).
        // Pre-O devices are reported unsupported by the bridge, but guard here too
        // so the service is a clean no-op if ever started on an older device.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            Log.w(TAG, "overlay requires Android O+ — stopping")
            stopSelf()
            return START_NOT_STICKY
        }

        // Pull config + seed data from the bridge. No secrets are logged.
        matchId = intent?.getStringExtra(EXTRA_MATCH_ID).orEmpty()
        baseUrl = intent?.getStringExtra(EXTRA_BASE_URL).orEmpty().trimEnd('/')
        apiKey = intent?.getStringExtra(EXTRA_API_KEY).orEmpty()
        clientType = intent?.getStringExtra(EXTRA_CLIENT_TYPE) ?: "android"
        appVersion = intent?.getStringExtra(EXTRA_APP_VERSION).orEmpty()
        packageNameHeader = intent?.getStringExtra(EXTRA_PACKAGE_NAME).orEmpty()
        teamALine = intent?.getStringExtra(EXTRA_TEAM_A).orEmpty()
        teamBLine = intent?.getStringExtra(EXTRA_TEAM_B).orEmpty()
        statusLine = intent?.getStringExtra(EXTRA_STATUS).orEmpty()
        isLive = intent?.getBooleanExtra(EXTRA_IS_LIVE, true) ?: true

        if (matchId.isEmpty()) {
            Log.w(TAG, "service start without matchId — aborting")
            stopSelfClean()
            return START_NOT_STICKY
        }

        Log.d(TAG, "service start")
        startForegroundSafely()
        showBubble()
        // Live match → poll every 5s. Completed/finished match → never poll; the
        // seed already carries the final score/result. Either way the bubble stays
        // visible until the user closes it.
        if (isLive) {
            startPolling()
        } else {
            Log.d(TAG, "completed -> stop polling, keep bubble visible")
            updateNotification()
        }
        return START_NOT_STICKY
    }

    // ── Foreground notification ──────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Live Score",
                NotificationManager.IMPORTANCE_LOW,
            ).apply { description = "Ongoing live cricket score in the status bar." }
            val nm = getSystemService(NotificationManager::class.java)
            nm?.createNotificationChannel(channel)
        }
    }

    /**
     * Builds the ongoing live-score notification from the current display fields.
     * Title flips Live/Final; collapsed line is compact, expanded shows both team
     * lines + status. Tapping opens Match Details; the Stop action stops the
     * service. Uses team codes + normalized overs already baked into the lines.
     */
    private fun buildNotification(): Notification {
        val title = if (isLive) "CricPro Live Score" else "CricPro Final Score"
        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(notificationCollapsed())
            .setStyle(Notification.BigTextStyle().bigText(notificationExpanded()))
            .setSmallIcon(applicationInfo.icon)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(openAppPendingIntent())
            .addAction(
                Notification.Action.Builder(
                    null as android.graphics.drawable.Icon?,
                    "Stop",
                    stopPendingIntent(),
                ).build(),
            )
            .build()
    }

    /** One compact line for the collapsed notification. */
    private fun notificationCollapsed(): String {
        val parts = if (statusLine.isNotBlank()) {
            listOf(teamALine, statusLine)
        } else {
            listOf(teamALine, teamBLine)
        }
        val line = parts.filter { it.isNotBlank() }.joinToString("   ")
        return if (line.isNotBlank()) {
            line
        } else if (isLive) {
            "Floating score is active"
        } else {
            "Final score is visible"
        }
    }

    /** Full multi-line body for the expanded notification. */
    private fun notificationExpanded(): String =
        listOf(teamALine, teamBLine, statusLine)
            .filter { it.isNotBlank() }
            .joinToString("\n")

    private fun stopPendingIntent(): PendingIntent {
        val intent = Intent(this, FloatingScoreService::class.java).apply {
            action = ACTION_STOP
        }
        return PendingIntent.getService(
            this,
            1,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun startForegroundSafely() {
        val notification = buildNotification()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (t: Throwable) {
            // Some Go / restricted devices refuse the FGS — degrade gracefully by
            // stopping cleanly so Flutter can fall back to the in-app bar.
            Log.w(TAG, "foreground start refused — stopping")
            stopSelfClean()
        }
    }

    /** Refresh the ongoing notification from the current fields without tearing
     *  down the service — called every poll, and when a match completes. No-op /
     *  silent on devices where the notification can't post (e.g. perm denied). */
    private fun updateNotification() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            getSystemService(NotificationManager::class.java)
                ?.notify(NOTIFICATION_ID, buildNotification())
        } catch (_: Throwable) {
        }
    }

    private fun openAppPendingIntent(): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            putExtra(MainActivity.EXTRA_OPEN_MATCH_ID, matchId)
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getActivity(this, 0, intent, flags)
    }

    // ── Overlay bubble ───────────────────────────────────────────────────────

    private fun showBubble() {
        if (bubbleView != null) return
        // O+ only — we never use the deprecated TYPE_PHONE / TYPE_SYSTEM_ALERT
        // window types. Pre-O devices are reported unsupported by the bridge.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            Log.w(TAG, "overlay requires Android O+ — stopping")
            stopSelfClean()
            return
        }
        val type = WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            // Not focusable so we never steal keyboard/touch from the app behind.
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            // Default near the right edge, upper-middle area.
            x = dp(12)
            y = dp(120)
        }

        val view = LayoutInflater.from(this)
            .inflate(R.layout.floating_score_bubble, null)
        attachDrag(view, params)

        // Close has its own click listener; it sits in its own small area so it
        // never blocks dragging the rest of the bubble. Tap-to-open and
        // double-tap-to-resize are handled by the root drag listener's gesture
        // detector — NOT a child click listener, which would otherwise swallow
        // touches and break dragging.
        view.findViewById<TextView>(R.id.floating_close)?.setOnClickListener {
            Log.d(TAG, "close")
            stopSelfClean()
        }

        try {
            windowManager.addView(view, params)
            bubbleView = view
            layoutParams = params
            Log.d(TAG, "show bubble")
            applySize() // honour the persisted size before first paint.
            render()
        } catch (t: Throwable) {
            Log.w(TAG, "addView refused — stopping")
            stopSelfClean()
        }
    }

    /**
     * Drag + tap + double-tap on the whole bubble. A [GestureDetector] resolves
     * single-tap (open Match Details) vs double-tap (cycle bubble size) so the
     * two never fight. Dragging is handled directly off the raw MOVE events and
     * suppresses the tap when the finger travelled past touchSlop. The close
     * button keeps its own click listener, so it isn't affected.
     */
    private fun attachDrag(view: View, params: WindowManager.LayoutParams) {
        val touchSlop = ViewConfiguration.get(this).scaledTouchSlop
        var initialX = 0
        var initialY = 0
        var touchX = 0f
        var touchY = 0f
        var dragging = false

        val tapDetector = GestureDetector(
            this,
            object : GestureDetector.SimpleOnGestureListener() {
                override fun onSingleTapConfirmed(e: MotionEvent): Boolean {
                    if (!dragging) {
                        Log.d(TAG, "tap open")
                        openApp()
                    }
                    return true
                }

                override fun onDoubleTap(e: MotionEvent): Boolean {
                    if (!dragging) cycleSize()
                    return true
                }
            },
        )

        view.setOnTouchListener { v, event ->
            // Feed the detector first so tap/double-tap timing is accurate.
            tapDetector.onTouchEvent(event)
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = params.x
                    initialY = params.y
                    touchX = event.rawX
                    touchY = event.rawY
                    dragging = false
                    Log.d(TAG, "drag start")
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = (event.rawX - touchX).toInt()
                    val dy = (event.rawY - touchY).toInt()
                    if (!dragging && (abs(dx) > touchSlop || abs(dy) > touchSlop)) {
                        dragging = true
                    }
                    if (dragging) {
                        params.x = clampX(initialX + dx, v)
                        params.y = clampY(initialY + dy, v)
                        try {
                            windowManager.updateViewLayout(v, params)
                            Log.d(TAG, "drag move x=${params.x} y=${params.y}")
                        } catch (_: Throwable) {
                            // View already removed mid-gesture — ignore.
                        }
                    }
                    true
                }
                MotionEvent.ACTION_UP -> true
                MotionEvent.ACTION_CANCEL -> true
                else -> false
            }
        }
    }

    /**
     * Advances the bubble size compact -> normal -> large -> compact, persists
     * the choice, re-applies the scaled dimensions, and re-clamps so a grown
     * bubble can never end up partly off-screen.
     */
    private fun cycleSize() {
        sizeIndex = (sizeIndex + 1) % SIZE_COUNT
        prefs().edit().putInt(KEY_SIZE_INDEX, sizeIndex).apply()
        Log.d(TAG, "resize -> ${sizeName(sizeIndex)}")
        applySize()
    }

    /**
     * Applies the current [sizeIndex] to the bubble. Scales BOTH the text AND
     * the structural chrome (root paddings, the close button, inter-line
     * margins, the LIVE pill, content min-width) so compact is visibly smaller
     * and large is visibly bigger — previously only text + one min-width scaled,
     * so the fixed chrome dominated and compact barely shrank. Then nudges the
     * window back fully on screen. Safe to call before the first frame.
     */
    private fun applySize() {
        val view = bubbleView ?: return
        val params = layoutParams ?: return
        val scale = sizeScale(sizeIndex)

        val teamA = view.findViewById<TextView>(R.id.floating_team_a)
        val teamB = view.findViewById<TextView>(R.id.floating_team_b)
        val status = view.findViewById<TextView>(R.id.floating_status)
        val live = view.findViewById<TextView>(R.id.floating_live)
        val close = view.findViewById<TextView>(R.id.floating_close)
        val content = view.findViewById<View>(R.id.floating_content)

        teamA?.setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f * scale)
        teamB?.setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f * scale)
        status?.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f * scale)
        live?.setTextSize(TypedValue.COMPLEX_UNIT_SP, 9f * scale)

        // Inter-line margins scale so the vertical bulk tracks the size too.
        (teamA?.layoutParams as? LinearLayout.LayoutParams)?.topMargin =
            dp(7f * scale)
        (teamB?.layoutParams as? LinearLayout.LayoutParams)?.topMargin =
            dp(2f * scale)
        (status?.layoutParams as? LinearLayout.LayoutParams)?.topMargin =
            dp(6f * scale)

        // LIVE/FINAL pill padding scales.
        live?.setPadding(dp(9f * scale), dp(2f * scale), dp(9f * scale), dp(2f * scale))

        // Close button: shrink the touch target + glyph + its left margin.
        close?.let {
            val side = dp(28f * scale)
            it.layoutParams = it.layoutParams.apply {
                width = side
                height = side
                (this as? LinearLayout.LayoutParams)?.marginStart = dp(8f * scale)
            }
            it.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f * scale)
        }

        // Root paddings scale — the single biggest contributor to the bubble's
        // footprint, and the reason compact looked unchanged before.
        view.setPadding(
            dp(14f * scale),
            dp(11f * scale),
            dp(10f * scale),
            dp(12f * scale),
        )

        // Content column min width.
        content?.minimumWidth = dp(196f * scale)

        // Let the view re-measure, then clamp it back on-screen.
        view.requestLayout()
        main.post {
            val v = bubbleView ?: return@post
            params.x = clampX(params.x, v)
            params.y = clampY(params.y, v)
            try {
                windowManager.updateViewLayout(v, params)
            } catch (_: Throwable) {
            }
        }
    }

    private fun sizeScale(index: Int): Float = when (index) {
        SIZE_COMPACT -> 0.7f
        SIZE_LARGE -> 1.3f
        else -> 1.0f
    }

    private fun sizeName(index: Int): String = when (index) {
        SIZE_COMPACT -> "compact"
        SIZE_LARGE -> "large"
        else -> "normal"
    }

    /** Clamp the window x so the bubble stays fully on screen (TOP|START frame). */
    private fun clampX(x: Int, view: View): Int {
        val max = resources.displayMetrics.widthPixels - view.width
        return if (max <= 0) x.coerceAtLeast(0) else x.coerceIn(0, max)
    }

    /** Clamp the window y so the bubble stays fully on screen (TOP|START frame). */
    private fun clampY(y: Int, view: View): Int {
        val max = resources.displayMetrics.heightPixels - view.height
        return if (max <= 0) y.coerceAtLeast(0) else y.coerceIn(0, max)
    }

    private fun openApp() {
        Log.d(TAG, "open match")
        try {
            startActivity(
                Intent(this, MainActivity::class.java).apply {
                    action = Intent.ACTION_VIEW
                    addFlags(
                        Intent.FLAG_ACTIVITY_NEW_TASK or
                            Intent.FLAG_ACTIVITY_SINGLE_TOP,
                    )
                    putExtra(MainActivity.EXTRA_OPEN_MATCH_ID, matchId)
                },
            )
        } catch (_: Throwable) {
        }
    }

    private fun render() {
        val view = bubbleView ?: return
        // LIVE (red) while polling, FINAL (green) once the match is done.
        val pill = view.findViewById<TextView>(R.id.floating_live)
        if (isLive) {
            pill?.text = "LIVE"
            pill?.setBackgroundResource(R.drawable.floating_live_pill)
            pill?.setTextColor(0xFFEF4444.toInt())
        } else {
            pill?.text = "FINAL"
            pill?.setBackgroundResource(R.drawable.floating_final_pill)
            pill?.setTextColor(0xFF34D399.toInt())
        }
        view.findViewById<TextView>(R.id.floating_team_a)?.text = teamALine
        view.findViewById<TextView>(R.id.floating_team_b)?.text = teamBLine
        val status = view.findViewById<TextView>(R.id.floating_status)
        status?.text = statusLine
        status?.visibility = if (statusLine.isBlank()) View.GONE else View.VISIBLE
        // Cyan for live equation, green for the final result.
        status?.setTextColor(if (isLive) 0xFF22D3EE.toInt() else 0xFF34D399.toInt())
        Log.d(TAG, "render state=${if (isLive) "live" else "final"} score=$teamALine / $teamBLine")
    }

    // ── Polling ──────────────────────────────────────────────────────────────

    private fun startPolling() {
        if (poller != null) return
        val exec = Executors.newSingleThreadScheduledExecutor()
        poller = exec
        // Wrap in a catch-all: scheduleWithFixedDelay silently cancels ALL future
        // runs if the task throws an uncaught exception. pollOnce already guards
        // its own body, but this is the belt-and-braces so the bubble never goes
        // permanently stale from one unexpected error.
        exec.scheduleWithFixedDelay({
            try {
                pollOnce()
            } catch (t: Throwable) {
                Log.w(TAG, "poll tick failed — will retry next interval")
            }
        }, 0, 5, TimeUnit.SECONDS)
    }

    private fun pollOnce() {
        if (matchId.isEmpty() || baseUrl.isEmpty()) return
        var conn: HttpURLConnection? = null
        try {
            val url = URL("$baseUrl/app/live-scores?ids=$matchId")
            conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = 8000
                readTimeout = 8000
                setRequestProperty("Accept", "application/json")
                if (apiKey.isNotEmpty()) setRequestProperty("X-API-Key", apiKey)
                setRequestProperty("X-Client-Type", clientType)
                if (appVersion.isNotEmpty()) setRequestProperty("X-App-Version", appVersion)
                if (packageNameHeader.isNotEmpty()) {
                    setRequestProperty("X-Package-Name", packageNameHeader)
                }
            }
            if (conn.responseCode != 200) return // keep last good score
            val body = conn.inputStream.bufferedReader().use { it.readText() }
            applyResponse(body)
        } catch (_: Throwable) {
            // Network blip — keep last good score, retry next tick.
        } finally {
            conn?.disconnect()
        }
    }

    private fun applyResponse(body: String) {
        val root = JSONObject(body)
        val data = root.optJSONArray("data") ?: return
        if (data.length() == 0) return
        val match = data.optJSONObject(0) ?: return

        val status = match.optString("status", "")
        val statusText = match.optString("status_text", "")
        val result = match.optString("result", "")
        val live = isLiveStatus(status)
        val finished = isFinishedStatus(status)

        val t1 = match.optJSONObject("team1")
        val t2 = match.optJSONObject("team2")
        val aCode = formatCode(t1?.optString("short_name", "") ?: "")
        val bCode = formatCode(t2?.optString("short_name", "") ?: "")
        val aScore = inningsText(t1)
        val bScore = inningsText(t2)

        val newA = listOf(aCode, aScore).filter { it.isNotBlank() }.joinToString("  ")
        val newB = listOf(bCode, bScore).filter { it.isNotBlank() }.joinToString("  ")
        val newStatus = shortStatus(result, statusText)

        main.post {
            if (newA.isNotBlank()) teamALine = newA
            if (newB.isNotBlank()) teamBLine = newB
            if (newStatus.isNotBlank()) statusLine = newStatus
            isLive = live
            render()
            // Mirror the live score into the status-bar notification every poll.
            updateNotification()
            // Match finished — show the final state and STOP POLLING, but keep the
            // bubble + notification up. Only the user (X / Stop) closes the overlay.
            if (finished) stopPollingKeepBubble()
        }
    }

    /** Halt the 5s scheduler but leave the overlay view + foreground notification
     *  intact. Distinct from [stopSelfClean], which tears the whole service down. */
    private fun stopPollingKeepBubble() {
        if (poller == null) return
        poller?.shutdownNow()
        poller = null
        Log.d(TAG, "completed -> stop polling, keep bubble visible")
        updateNotification()
    }

    // ── Formatting (mirrors Flutter rules) ───────────────────────────────────

    /** "INDA" -> "IND A", "SLA" -> "SL A", "INDU19" -> "IND U19". */
    private fun formatCode(raw: String): String {
        val c = raw.trim().uppercase()
        if (c.isEmpty() || c == "TBC" || c == "TBD" || c.contains(' ')) return c
        Regex("^([A-Z]{2,})U19$").find(c)?.let { return "${it.groupValues[1]} U19" }
        Regex("^([A-Z]{2,})W$").find(c)?.let { return "${it.groupValues[1]} W" }
        Regex("^([A-Z]{2,})A$").find(c)?.let { return "${it.groupValues[1]} A" }
        return c
    }

    /** Latest innings as "145/3 (16.2 ov)" with overs normalized (49.6 -> 50.0). */
    private fun inningsText(team: JSONObject?): String {
        val list = team?.optJSONArray("innings") ?: return ""
        if (list.length() == 0) return ""
        val inn = list.optJSONObject(list.length() - 1) ?: return ""
        if (inn.isNull("runs")) return ""
        val runs = inn.opt("runs")?.toString() ?: return ""
        val wkts = if (inn.isNull("wickets")) null else inn.opt("wickets")?.toString()
        val overs = if (inn.isNull("overs")) "" else normalizeOvers(inn.opt("overs")?.toString() ?: "")
        val score = if (wkts == null) runs else "$runs/$wkts"
        return if (overs.isBlank()) score else "$score ($overs ov)"
    }

    private fun normalizeOvers(value: String): String {
        val parsed = value.trim().toDoubleOrNull() ?: return value.trim()
        val overs = parsed.toInt()
        val balls = ((parsed - overs) * 10).roundToInt()
        if (balls >= 6) {
            val norm = overs + balls / 6
            val rem = balls % 6
            return if (rem == 0) "$norm.0" else "$norm.$rem"
        }
        return if (balls == 0) "$overs.0" else "$overs.$balls"
    }

    private fun shortStatus(result: String, statusText: String): String {
        val s = if (result.isNotBlank()) result else statusText
        return shortenResult(s.trim())
    }

    /**
     * Light cleanup for long result text so it fits the compact bubble. Prefers a
     * parenthetical detail and drops filler ("the"). The status TextView still
     * ellipsizes anything that remains too long.
     * "Match tied (Sri Lanka A won the Super Over)" -> "Sri Lanka A won Super Over".
     */
    private fun shortenResult(raw: String): String {
        if (raw.isEmpty()) return raw
        var s = raw
        Regex("\\(([^)]+)\\)").find(s)?.let {
            if (it.groupValues[1].length >= 6) s = it.groupValues[1].trim()
        }
        return s.replace(Regex("\\bthe\\b", RegexOption.IGNORE_CASE), " ")
            .replace(Regex("\\s+"), " ")
            .trim()
    }

    private fun isLiveStatus(status: String): Boolean {
        val s = status.lowercase()
        return s == "live" || s == "in_progress" || s == "inprogress" ||
            s == "progress" || s == "innings_break" || s == "inningsbreak" ||
            s == "break" || s == "rain_delay" || s == "delay" || s == "tea" ||
            s == "lunch" || s == "drinks" || s == "stumps"
    }

    private fun isFinishedStatus(status: String): Boolean {
        val s = status.lowercase()
        return s == "completed" || s == "recent" || s == "finished" ||
            s == "result" || s == "abandoned"
    }

    // ── Teardown ─────────────────────────────────────────────────────────────

    private fun stopSelfClean() {
        poller?.shutdownNow()
        poller = null
        removeBubble()
        try {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } catch (_: Throwable) {
        }
        stopSelf()
    }

    private fun removeBubble() {
        val view = bubbleView ?: return
        try {
            windowManager.removeView(view)
        } catch (_: Throwable) {
        }
        bubbleView = null
        layoutParams = null
    }

    override fun onDestroy() {
        poller?.shutdownNow()
        poller = null
        removeBubble()
        super.onDestroy()
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    private fun dp(value: Float): Int =
        (value * resources.displayMetrics.density).roundToInt()

    companion object {
        private const val TAG = "CricProOverlay"
        private const val CHANNEL_ID = "cricpro_floating_score"
        private const val NOTIFICATION_ID = 4242

        // Bubble size cycle (double-tap). Persisted across overlay starts.
        private const val PREFS_NAME = "cricpro_overlay"
        private const val KEY_SIZE_INDEX = "bubble_size_index"
        private const val SIZE_COMPACT = 0
        private const val SIZE_NORMAL = 1
        private const val SIZE_LARGE = 2
        private const val SIZE_COUNT = 3

        const val ACTION_STOP = "com.cric.pro.overlay.STOP"

        const val EXTRA_MATCH_ID = "matchId"
        const val EXTRA_BASE_URL = "baseUrl"
        const val EXTRA_API_KEY = "apiKey"
        const val EXTRA_CLIENT_TYPE = "clientType"
        const val EXTRA_APP_VERSION = "appVersion"
        const val EXTRA_PACKAGE_NAME = "packageName"
        const val EXTRA_TEAM_A = "teamA"
        const val EXTRA_TEAM_B = "teamB"
        const val EXTRA_STATUS = "status"
        const val EXTRA_IS_LIVE = "isLive"
    }
}
