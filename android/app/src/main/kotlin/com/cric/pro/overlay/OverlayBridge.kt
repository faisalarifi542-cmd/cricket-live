package com.cric.pro.overlay

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges the Flutter "Floating Score" feature to the native overlay service.
 *
 * Methods (called from [FloatingScoreOverlay] on the Dart side):
 *  - isSupported           -> Boolean (false on devices that can't draw overlays)
 *  - hasPermission         -> Boolean (Settings.canDrawOverlays)
 *  - requestPermission     -> opens ACTION_MANAGE_OVERLAY_PERMISSION for us
 *  - start{...}            -> starts the foreground overlay service for a match
 *  - update{...}          -> not used (service self-polls); reserved
 *  - stop                  -> stops the service
 *  - isRunning             -> Boolean
 *
 * Permission is NEVER requested implicitly — only when Flutter calls
 * requestPermission after the user taps Enable.
 */
class OverlayBridge(
    context: Context,
    private val activityProvider: () -> Activity?,
) {
    private val appContext: Context = context.applicationContext
    private var running = false

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(isSupported())
            "hasPermission" -> result.success(canDrawOverlays())
            "requestPermission" -> {
                requestPermission()
                result.success(canDrawOverlays())
            }
            "start" -> {
                val ok = start(call)
                result.success(ok)
            }
            "stop" -> {
                stop()
                result.success(true)
            }
            "isRunning" -> result.success(running)
            else -> result.notImplemented()
        }
    }

    private fun isSupported(): Boolean {
        // TYPE_APPLICATION_OVERLAY exists on Android O+ only; we never fall back
        // to the deprecated window types, so pre-O devices are unsupported and
        // the app uses its in-app minimized score bar instead.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return try {
            appContext.packageManager != null
        } catch (_: Throwable) {
            false
        }
    }

    private fun canDrawOverlays(): Boolean {
        val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(appContext)
        } else {
            true
        }
        Log.d(TAG, "permission status=$granted")
        return granted
    }

    private fun requestPermission() {
        Log.d(TAG, "request permission")
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || canDrawOverlays()) return
        try {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:${appContext.packageName}"),
            )
            val activity = activityProvider()
            if (activity != null) {
                activity.startActivity(intent)
            } else {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                appContext.startActivity(intent)
            }
        } catch (t: Throwable) {
            Log.w(TAG, "could not open overlay settings")
        }
    }

    private fun start(call: MethodCall): Boolean {
        if (!canDrawOverlays()) {
            Log.w(TAG, "permission missing")
            return false
        }
        val matchId = call.argument<String>("matchId").orEmpty()
        if (matchId.isEmpty()) return false
        return try {
            val intent = Intent(appContext, FloatingScoreService::class.java).apply {
                putExtra(FloatingScoreService.EXTRA_MATCH_ID, matchId)
                putExtra(FloatingScoreService.EXTRA_BASE_URL, call.argument<String>("baseUrl").orEmpty())
                putExtra(FloatingScoreService.EXTRA_API_KEY, call.argument<String>("apiKey").orEmpty())
                putExtra(FloatingScoreService.EXTRA_CLIENT_TYPE, call.argument<String>("clientType") ?: "android")
                putExtra(FloatingScoreService.EXTRA_APP_VERSION, call.argument<String>("appVersion").orEmpty())
                putExtra(FloatingScoreService.EXTRA_PACKAGE_NAME, call.argument<String>("packageName").orEmpty())
                putExtra(FloatingScoreService.EXTRA_TEAM_A, call.argument<String>("teamA").orEmpty())
                putExtra(FloatingScoreService.EXTRA_TEAM_B, call.argument<String>("teamB").orEmpty())
                putExtra(FloatingScoreService.EXTRA_STATUS, call.argument<String>("status").orEmpty())
                putExtra(FloatingScoreService.EXTRA_IS_LIVE, call.argument<Boolean>("isLive") ?: true)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                appContext.startForegroundService(intent)
            } else {
                appContext.startService(intent)
            }
            running = true
            true
        } catch (t: Throwable) {
            Log.w(TAG, "service start failed")
            running = false
            false
        }
    }

    private fun stop() {
        Log.d(TAG, "stop")
        try {
            val intent = Intent(appContext, FloatingScoreService::class.java).apply {
                action = FloatingScoreService.ACTION_STOP
            }
            appContext.startService(intent)
        } catch (_: Throwable) {
            // If we can't message it, force-stop.
            try {
                appContext.stopService(Intent(appContext, FloatingScoreService::class.java))
            } catch (_: Throwable) {
            }
        }
        running = false
    }

    companion object {
        private const val TAG = "CricProOverlay"
        const val CHANNEL = "cricpro/overlay_bridge"
    }
}
