package com.cric.pro.ads

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.unity3d.ads.IUnityAdsInitializationListener
import com.unity3d.ads.IUnityAdsLoadListener
import com.unity3d.ads.IUnityAdsShowListener
import com.unity3d.ads.UnityAds
import com.unity3d.ads.UnityAdsShowOptions
import io.flutter.plugin.common.MethodChannel

/**
 * Direct Unity Ads SDK integration: interstitial + rewarded full-screen ads.
 * Each Flutter call resolves exactly once, on the main thread.
 */
class UnityAdsBridge(
    private val context: Context,
    private val activityProvider: () -> Activity?,
) {
    private val main = Handler(Looper.getMainLooper())
    private var initialized = false

    private fun log(msg: String) = Log.d(TAG, msg)

    fun initialize(gameId: String, testMode: Boolean, result: MethodChannel.Result) {
        val reply = SafeResult(main, result)
        if (gameId.isEmpty()) {
            reply.success(false)
            return
        }
        if (initialized) {
            reply.success(true)
            return
        }
        UnityAds.initialize(
            context,
            gameId,
            testMode,
            object : IUnityAdsInitializationListener {
                override fun onInitializationComplete() {
                    initialized = true
                    log("init complete (test=$testMode)")
                    reply.success(true)
                }

                override fun onInitializationFailed(
                    error: UnityAds.UnityAdsInitializationError?,
                    message: String?,
                ) {
                    initialized = false
                    log("init FAILED: $error $message")
                    reply.success(false)
                }
            },
        )
    }

    fun loadInterstitial(placementId: String, result: MethodChannel.Result) =
        load(placementId, result)

    fun showInterstitial(placementId: String, result: MethodChannel.Result) =
        show(placementId, result, rewarded = false)

    fun loadRewarded(placementId: String, result: MethodChannel.Result) =
        load(placementId, result)

    fun showRewarded(placementId: String, result: MethodChannel.Result) =
        show(placementId, result, rewarded = true)

    private fun load(placementId: String, result: MethodChannel.Result) {
        val reply = SafeResult(main, result)
        if (!initialized || placementId.isEmpty()) {
            reply.success(false)
            return
        }
        UnityAds.load(
            placementId,
            object : IUnityAdsLoadListener {
                override fun onUnityAdsAdLoaded(id: String?) {
                    log("loaded placement=$placementId")
                    reply.success(true)
                }

                override fun onUnityAdsFailedToLoad(
                    id: String?,
                    error: UnityAds.UnityAdsLoadError?,
                    message: String?,
                ) {
                    log("failed placement=$placementId: $error $message")
                    reply.success(false)
                }
            },
        )
    }

    private fun show(
        placementId: String,
        result: MethodChannel.Result,
        rewarded: Boolean,
    ) {
        val reply = SafeResult(main, result)
        val activity = activityProvider()
        if (!initialized || placementId.isEmpty() || activity == null) {
            reply.success(false)
            return
        }
        log("requested show placement=$placementId rewarded=$rewarded")
        UnityAds.show(
            activity,
            placementId,
            UnityAdsShowOptions(),
            object : IUnityAdsShowListener {
                override fun onUnityAdsShowFailure(
                    id: String?,
                    error: UnityAds.UnityAdsShowError?,
                    message: String?,
                ) {
                    log("show FAILED placement=$placementId: $error $message")
                    reply.success(false)
                }

                override fun onUnityAdsShowStart(id: String?) {
                    log("shown placement=$placementId")
                }

                override fun onUnityAdsShowClick(id: String?) {}

                override fun onUnityAdsShowComplete(
                    id: String?,
                    state: UnityAds.UnityAdsShowCompletionState?,
                ) {
                    val completed =
                        state == UnityAds.UnityAdsShowCompletionState.COMPLETED
                    log("completed placement=$placementId state=$state " +
                        "rewardGranted=${if (rewarded) completed else false}")
                    // Interstitial: shown == true once dismissed.
                    // Rewarded: earned only when fully completed.
                    reply.success(if (rewarded) completed else true)
                }
            },
        )
    }

    fun dispose() {
        // Unity Ads has no per-ad teardown for full-screen formats.
    }

    companion object {
        private const val TAG = "UNITY_AD"
    }
}

