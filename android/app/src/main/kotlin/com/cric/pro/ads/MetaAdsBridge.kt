package com.cric.pro.ads

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.facebook.ads.Ad
import com.facebook.ads.AdError
import com.facebook.ads.AdSettings
import com.facebook.ads.AudienceNetworkAds
import com.facebook.ads.InterstitialAd
import com.facebook.ads.InterstitialAdListener
import com.facebook.ads.RewardedVideoAd
import com.facebook.ads.RewardedVideoAdListener
import io.flutter.plugin.common.MethodChannel

/**
 * Direct Meta / Facebook Audience Network SDK integration: interstitial +
 * rewarded video. Each Flutter call resolves exactly once, on the main thread.
 */
class MetaAdsBridge(
    private val context: Context,
    private val activityProvider: () -> Activity?,
) {
    private val main = Handler(Looper.getMainLooper())
    private var initialized = false

    private var interstitial: InterstitialAd? = null
    private var interstitialLoad: SafeResult? = null
    private var interstitialShow: SafeResult? = null

    private var rewarded: RewardedVideoAd? = null
    private var rewardedLoad: SafeResult? = null
    private var rewardedShow: SafeResult? = null
    private var rewardEarned = false

    private fun log(msg: String) = Log.d(TAG, msg)

    fun initialize(testMode: Boolean, result: MethodChannel.Result) {
        val reply = SafeResult(main, result)
        try {
            if (testMode) AdSettings.setTestMode(true)
            AudienceNetworkAds.initialize(context)
            initialized = true
            reply.success(true)
        } catch (e: Throwable) {
            initialized = false
            reply.success(false)
        }
    }

    // ---- Interstitial ----

    fun loadInterstitial(placementId: String, result: MethodChannel.Result) {
        val reply = SafeResult(main, result)
        if (!initialized || placementId.isEmpty()) {
            reply.success(false)
            return
        }
        main.post {
            val ad = InterstitialAd(context, placementId)
            interstitial = ad
            interstitialLoad = reply
            log("interstitial requested placement=$placementId")
            val config = ad.buildLoadAdConfig()
                .withAdListener(object : InterstitialAdListener {
                    override fun onError(a: Ad?, error: AdError?) {
                        log("interstitial failed placement=$placementId: ${error?.errorMessage}")
                        interstitialLoad?.success(false)
                        interstitialShow?.success(false)
                    }

                    override fun onAdLoaded(a: Ad?) {
                        log("interstitial loaded placement=$placementId")
                        interstitialLoad?.success(true)
                    }

                    override fun onInterstitialDisplayed(a: Ad?) {
                        log("interstitial shown placement=$placementId")
                    }

                    override fun onInterstitialDismissed(a: Ad?) {
                        log("interstitial dismissed placement=$placementId")
                        interstitialShow?.success(true)
                        ad.destroy()
                        interstitial = null
                    }

                    override fun onAdClicked(a: Ad?) {}

                    override fun onLoggingImpression(a: Ad?) {}
                })
                .build()
            ad.loadAd(config)
        }
    }

    fun showInterstitial(placementId: String, result: MethodChannel.Result) {
        val reply = SafeResult(main, result)
        main.post {
            val ad = interstitial
            if (ad == null || !ad.isAdLoaded || ad.isAdInvalidated) {
                reply.success(false)
                return@post
            }
            interstitialShow = reply
            ad.show()
        }
    }

    // ---- Rewarded video ----

    fun loadRewarded(placementId: String, result: MethodChannel.Result) {
        val reply = SafeResult(main, result)
        if (!initialized || placementId.isEmpty()) {
            reply.success(false)
            return
        }
        main.post {
            val ad = RewardedVideoAd(context, placementId)
            rewarded = ad
            rewardedLoad = reply
            rewardEarned = false
            log("rewarded requested placement=$placementId")
            val config = ad.buildLoadAdConfig()
                .withAdListener(object : RewardedVideoAdListener {
                    override fun onError(a: Ad?, error: AdError?) {
                        log("rewarded failed placement=$placementId: ${error?.errorMessage}")
                        rewardedLoad?.success(false)
                        rewardedShow?.success(false)
                    }

                    override fun onAdLoaded(a: Ad?) {
                        log("rewarded loaded placement=$placementId")
                        rewardedLoad?.success(true)
                    }

                    override fun onAdClicked(a: Ad?) {}

                    override fun onLoggingImpression(a: Ad?) {
                        log("rewarded shown placement=$placementId")
                    }

                    override fun onRewardedVideoCompleted() {
                        rewardEarned = true
                        log("rewarded completed placement=$placementId rewardGranted=true")
                    }

                    override fun onRewardedVideoClosed() {
                        log("rewarded closed placement=$placementId rewardGranted=$rewardEarned")
                        rewardedShow?.success(rewardEarned)
                        ad.destroy()
                        rewarded = null
                    }
                })
                .build()
            ad.loadAd(config)
        }
    }

    fun showRewarded(placementId: String, result: MethodChannel.Result) {
        val reply = SafeResult(main, result)
        main.post {
            val ad = rewarded
            if (ad == null || !ad.isAdLoaded || ad.isAdInvalidated) {
                reply.success(false)
                return@post
            }
            rewardedShow = reply
            ad.show()
        }
    }

    fun dispose() {
        interstitial?.destroy()
        interstitial = null
        rewarded?.destroy()
        rewarded = null
    }

    companion object {
        private const val TAG = "META_AD"
    }
}

