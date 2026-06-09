import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Handles Google's User Messaging Platform (UMP) consent flow before any ad
/// is requested.
///
/// AdMob policy (GDPR / EEA, UK, and similar regions) requires gathering user
/// consent BEFORE loading personalized ads. The UMP SDK ships inside the
/// `google_mobile_ads` plugin, so no extra dependency is needed.
///
/// Flow:
///   1. [gatherConsent] requests a consent-info update.
///   2. If a consent form is required/available, it is loaded and shown.
///   3. We only report ready once the form interaction completes (or no form
///      is needed). The caller then initializes the ad SDKs.
///
/// When [consentRequired] is false (admin `consentRequired = false`) we skip
/// the gate entirely — useful for regions / builds where consent is not
/// mandated.
class ConsentManager {
  ConsentManager._();

  static final ConsentManager instance = ConsentManager._();

  bool _completed = false;

  /// Whether the consent flow has finished (form shown/dismissed or not
  /// needed). Ads should only initialize after this is true when consent is
  /// required.
  bool get completed => _completed;

  /// Whether the SDK currently reports that requesting ads is allowed. On error
  /// we fail open (return true) so ads are not permanently blocked by a UMP
  /// hiccup — AdMob itself still serves non-personalized ads when consent is
  /// absent.
  Future<bool> canRequestAds() async {
    try {
      return await ConsentInformation.instance.canRequestAds();
    } catch (_) {
      return true;
    }
  }

  /// Runs the consent flow. Safe to call repeatedly; the UMP SDK caches state.
  ///
  /// [consentRequired] mirrors the admin `consentRequired` flag. When false,
  /// this is a no-op that immediately reports complete.
  /// [testMode]/[debugDeviceIds] let QA force the EEA geography so the form can
  /// be verified on a test device.
  Future<void> gatherConsent({
    required bool consentRequired,
    bool testMode = false,
    List<String> debugDeviceIds = const [],
  }) async {
    if (kIsWeb) {
      _completed = true;
      return;
    }
    if (!consentRequired) {
      _completed = true;
      if (kDebugMode) {
        debugPrint('[Ads][consent] not required by admin config; skipping form');
      }
      return;
    }

    final params = ConsentRequestParameters(
      consentDebugSettings: (testMode && debugDeviceIds.isNotEmpty)
          ? ConsentDebugSettings(
              debugGeography: DebugGeography.debugGeographyEea,
              testIdentifiers: debugDeviceIds,
            )
          : null,
    );

    final completer = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      params,
      () async {
        try {
          await _loadAndShowFormIfRequired();
        } finally {
          if (!completer.isCompleted) completer.complete();
        }
      },
      (error) {
        if (kDebugMode) {
          debugPrint('[Ads][consent] info update failed: ${error.message}');
        }
        if (!completer.isCompleted) completer.complete();
      },
    );

    // Never let consent hang ad init forever.
    await completer.future
        .timeout(const Duration(seconds: 12), onTimeout: () {});
    _completed = true;
  }

  Future<void> _loadAndShowFormIfRequired() {
    final completer = Completer<void>();
    ConsentForm.loadAndShowConsentFormIfRequired((formError) {
      if (kDebugMode && formError != null) {
        debugPrint('[Ads][consent] form error: ${formError.message}');
      }
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future;
  }
}
