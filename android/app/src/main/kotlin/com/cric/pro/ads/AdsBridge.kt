package com.cric.pro.ads

import android.app.Activity
import android.content.Context
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Routes ad-bridge MethodChannel calls from Flutter to the Unity Ads and Meta
 * Audience Network native SDKs.
 *
 * AdMob is handled by the official Flutter plugin; this bridge exists only for
 * the networks that lack a maintained Flutter plugin. The Flutter side
 * ([NativeAdsBridge]) calls these methods and the [AdsManager] waterfall
 * decides which network is tried for each placement.
 */
class AdsBridge(
    context: Context,
    private val activityProvider: () -> Activity?,
) {
    private val appContext: Context = context.applicationContext
    private val unity = UnityAdsBridge(appContext, activityProvider)
    private val meta = MetaAdsBridge(appContext, activityProvider)

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // ---- Unity ----
            "unityInitialize" -> unity.initialize(
                gameId = call.argument<String>("gameId").orEmpty(),
                testMode = call.argument<Boolean>("testMode") ?: false,
                result = result,
            )
            "unityLoadInterstitial" ->
                unity.loadInterstitial(placementId(call), result)
            "unityShowInterstitial" ->
                unity.showInterstitial(placementId(call), result)
            "unityLoadRewarded" ->
                unity.loadRewarded(placementId(call), result)
            "unityShowRewarded" ->
                unity.showRewarded(placementId(call), result)

            // ---- Meta ----
            "metaInitialize" -> meta.initialize(
                testMode = call.argument<Boolean>("testMode") ?: false,
                result = result,
            )
            "metaLoadInterstitial" ->
                meta.loadInterstitial(placementId(call), result)
            "metaShowInterstitial" ->
                meta.showInterstitial(placementId(call), result)
            "metaLoadRewarded" ->
                meta.loadRewarded(placementId(call), result)
            "metaShowRewarded" ->
                meta.showRewarded(placementId(call), result)

            else -> result.notImplemented()
        }
    }

    fun dispose() {
        unity.dispose()
        meta.dispose()
    }

    private fun placementId(call: MethodCall): String =
        call.argument<String>("placementId").orEmpty()
}

