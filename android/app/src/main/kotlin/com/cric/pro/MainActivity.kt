package com.cric.pro

import android.content.Intent
import com.cric.pro.ads.AdsBridge
import com.cric.pro.overlay.OverlayBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var adsBridge: AdsBridge? = null
    private var overlayChannel: MethodChannel? = null

    // Match id captured from an overlay-bubble tap before the Flutter side has
    // registered its handler; flushed once the channel is ready / on resume.
    private var pendingMatchId: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val bridge = AdsBridge(applicationContext) { this }
        adsBridge = bridge
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ADS_CHANNEL)
            .setMethodCallHandler { call, result -> bridge.handle(call, result) }

        val overlay = OverlayBridge(applicationContext) { this }
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, OverlayBridge.CHANNEL)
        channel.setMethodCallHandler { call, result -> overlay.handle(call, result) }
        overlayChannel = channel

        // Deliver any match id captured from the launching intent.
        consumeMatchIdExtra(intent)
        flushPendingMatchId()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        consumeMatchIdExtra(intent)
        flushPendingMatchId()
    }

    override fun onResume() {
        super.onResume()
        flushPendingMatchId()
    }

    private fun consumeMatchIdExtra(intent: Intent?) {
        val id = intent?.getStringExtra(EXTRA_OPEN_MATCH_ID)
        if (!id.isNullOrEmpty()) {
            pendingMatchId = id
            intent.removeExtra(EXTRA_OPEN_MATCH_ID)
        }
    }

    private fun flushPendingMatchId() {
        val id = pendingMatchId ?: return
        val channel = overlayChannel ?: return
        channel.invokeMethod("openMatch", id)
        pendingMatchId = null
    }

    override fun onDestroy() {
        adsBridge?.dispose()
        adsBridge = null
        overlayChannel = null
        super.onDestroy()
    }

    companion object {
        private const val ADS_CHANNEL = "cricpro/ads_bridge"
        const val EXTRA_OPEN_MATCH_ID = "cricpro_open_match_id"
    }
}
