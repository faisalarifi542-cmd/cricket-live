import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Dart side of the native Unity Ads / Meta Audience Network bridge.
///
/// AdMob has a first-class Flutter plugin, but Unity Ads and Meta Audience
/// Network do not have maintained, reliable Flutter plugins. Rather than use
/// AdMob mediation (explicitly out of scope), we talk to the native SDKs
/// directly over a single [MethodChannel]. The Kotlin/Swift side owns the SDK
/// objects; this class is a thin, typed, crash-safe wrapper.
///
/// Every call is defensive: if the platform side is missing (e.g. iOS before
/// its Swift bridge ships, or web), calls resolve to a safe `false`/no-op so
/// the [AdsManager] waterfall simply skips the network.
class NativeAdsBridge {
  NativeAdsBridge._();

  static final NativeAdsBridge instance = NativeAdsBridge._();

  static const MethodChannel _channel = MethodChannel('cricpro/ads_bridge');

  bool get _platformSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<T?> _invoke<T>(String method, [Map<String, dynamic>? args]) async {
    if (!_platformSupported) return null;
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      // Native bridge not registered on this platform/build — skip silently.
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('[Ads][bridge] $method failed: $e');
      return null;
    }
  }

  // ---- Unity Ads ----

  Future<bool> unityInitialize({
    required String gameId,
    required bool testMode,
  }) async {
    final ok = await _invoke<bool>('unityInitialize', {
      'gameId': gameId,
      'testMode': testMode,
    });
    return ok ?? false;
  }

  Future<bool> unityLoadInterstitial(String placementId) async =>
      await _invoke<bool>('unityLoadInterstitial', {'placementId': placementId}) ??
      false;

  Future<bool> unityShowInterstitial(String placementId) async =>
      await _invoke<bool>('unityShowInterstitial', {'placementId': placementId}) ??
      false;

  Future<bool> unityLoadRewarded(String placementId) async =>
      await _invoke<bool>('unityLoadRewarded', {'placementId': placementId}) ??
      false;

  /// Returns true ONLY when the reward was earned (ad completed).
  Future<bool> unityShowRewarded(String placementId) async =>
      await _invoke<bool>('unityShowRewarded', {'placementId': placementId}) ??
      false;

  // ---- Meta Audience Network ----

  Future<bool> metaInitialize({required bool testMode}) async {
    final ok = await _invoke<bool>('metaInitialize', {'testMode': testMode});
    return ok ?? false;
  }

  Future<bool> metaLoadInterstitial(String placementId) async =>
      await _invoke<bool>('metaLoadInterstitial', {'placementId': placementId}) ??
      false;

  Future<bool> metaShowInterstitial(String placementId) async =>
      await _invoke<bool>('metaShowInterstitial', {'placementId': placementId}) ??
      false;

  Future<bool> metaLoadRewarded(String placementId) async =>
      await _invoke<bool>('metaLoadRewarded', {'placementId': placementId}) ??
      false;

  /// Returns true ONLY when the reward was earned (video completed).
  Future<bool> metaShowRewarded(String placementId) async =>
      await _invoke<bool>('metaShowRewarded', {'placementId': placementId}) ??
      false;
}
