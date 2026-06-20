import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Google UMP consent gate for ads.
///
/// This runs before any ad SDK initialization or ad load. UMP determines
/// whether the user is in a regulated region, whether a form is required, and
/// whether ads may be requested after the flow completes.
class ConsentManager {
  ConsentManager._();

  static final ConsentManager instance = ConsentManager._();

  // ---- DEBUG-ONLY consent testing controls ----
  // These NEVER take effect in a release build (every use is guarded by
  // kDebugMode). They exist so the GDPR/UMP form can be exercised from a
  // non-EEA test device.
  //
  // To test the consent form locally (debug build only):
  //   1. Run the app once and copy the test-device hash printed in logcat as
  //      `ADS_CONSENT: add this device as a debug test device id=<HASH>`.
  //   2. Add that hash to [kDebugTestDeviceIds] below.
  //   3. Set [kForceEeaGeographyForTesting] = true and hot-restart.
  //   4. Optionally call ConsentManager.instance.resetForTesting() to clear a
  //      prior choice so the form shows again.
  // Revert both before committing / shipping.
  static const bool kForceEeaGeographyForTesting = false;
  static const List<String> kDebugTestDeviceIds = <String>[];

  final ValueNotifier<bool> privacyOptionsRequired = ValueNotifier<bool>(false);

  bool _completed = false;
  bool _canRequestAds = false;
  ConsentStatus _status = ConsentStatus.unknown;
  PrivacyOptionsRequirementStatus _privacyStatus =
      PrivacyOptionsRequirementStatus.unknown;

  bool get completed => _completed;
  bool get canRequestAdsNow => _canRequestAds;
  ConsentStatus get status => _status;
  PrivacyOptionsRequirementStatus get privacyStatus => _privacyStatus;

  Future<bool> canRequestAds() async {
    if (kIsWeb) return false;
    try {
      _canRequestAds = await ConsentInformation.instance.canRequestAds();
      _log('canRequestAds=$_canRequestAds');
      return _canRequestAds;
    } catch (e) {
      _canRequestAds = false;
      _log('canRequestAds failed: $e');
      return false;
    }
  }

  Future<void> gatherConsent({
    bool testMode = false,
    List<String> debugDeviceIds = const [],
  }) async {
    if (kIsWeb) {
      _completed = true;
      _canRequestAds = false;
      _log('skipped on web');
      return;
    }

    _completed = false;
    _canRequestAds = false;

    // Debug-only: force EEA geography so the consent form can be exercised from
    // a non-EEA test device. Compiled out of release builds via kDebugMode.
    ConsentDebugSettings? debugSettings;
    if (kDebugMode &&
        kForceEeaGeographyForTesting &&
        kDebugTestDeviceIds.isNotEmpty) {
      debugSettings = ConsentDebugSettings(
        debugGeography: DebugGeography.debugGeographyEea,
        testIdentifiers: kDebugTestDeviceIds,
      );
      _log('DEBUG forcing EEA geography for ${kDebugTestDeviceIds.length} '
          'test device(s)');
    } else if (testMode && debugDeviceIds.isNotEmpty) {
      debugSettings = ConsentDebugSettings(
        debugGeography: DebugGeography.debugGeographyEea,
        testIdentifiers: debugDeviceIds,
      );
    }

    _log('requestConsentInfoUpdate start testMode=$testMode '
        'debugIds=${debugDeviceIds.length} '
        'forceEea=${debugSettings != null}');

    final params = ConsentRequestParameters(
      consentDebugSettings: debugSettings,
    );

    final completer = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      params,
      () async {
        _log('consent info update success');
        await _refreshConsentState('after_update');
        await _loadAndShowFormIfRequired();
        await _refreshConsentState('after_form');
        if (!completer.isCompleted) completer.complete();
      },
      (error) async {
        _log('consent info update failed code=${error.errorCode} '
            'message="${error.message}"');
        await _refreshConsentState('after_update_error');
        if (!completer.isCompleted) completer.complete();
      },
    );

    await completer.future.timeout(const Duration(seconds: 12), onTimeout: () {
      _log('consent flow timeout');
    });

    _canRequestAds = await canRequestAds();
    _completed = true;
    _log('complete status=${_status.name} '
        'privacyOptions=${_privacyStatus.name} canRequestAds=$_canRequestAds');
  }

  Future<void> _refreshConsentState(String phase) async {
    try {
      _status = await ConsentInformation.instance.getConsentStatus();
    } catch (e) {
      _status = ConsentStatus.unknown;
      _log('$phase status read failed: $e');
    }

    var formAvailable = false;
    try {
      formAvailable =
          await ConsentInformation.instance.isConsentFormAvailable();
    } catch (e) {
      _log('$phase form availability read failed: $e');
    }

    try {
      _privacyStatus = await ConsentInformation.instance
          .getPrivacyOptionsRequirementStatus();
    } catch (e) {
      _privacyStatus = PrivacyOptionsRequirementStatus.unknown;
      _log('$phase privacy options read failed: $e');
    }

    privacyOptionsRequired.value =
        _privacyStatus == PrivacyOptionsRequirementStatus.required;

    try {
      _canRequestAds = await ConsentInformation.instance.canRequestAds();
    } catch (_) {
      _canRequestAds = false;
    }

    _log('$phase status=${_status.name} formAvailable=$formAvailable '
        'privacyOptions=${_privacyStatus.name} canRequestAds=$_canRequestAds');
  }

  Future<void> _loadAndShowFormIfRequired() {
    final completer = Completer<void>();
    ConsentForm.loadAndShowConsentFormIfRequired((formError) {
      if (formError != null) {
        _log('form dismissed with error code=${formError.errorCode} '
            'message="${formError.message}"');
      } else {
        _log('form completed or not required');
      }
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future;
  }

  Future<void> showPrivacyOptionsForm() async {
    if (kIsWeb) return;
    final completer = Completer<void>();
    _log('showPrivacyOptionsForm start');
    await ConsentForm.showPrivacyOptionsForm((formError) async {
      if (formError != null) {
        _log('privacy options error code=${formError.errorCode} '
            'message="${formError.message}"');
      } else {
        _log('privacy options dismissed');
      }
      await _refreshConsentState('after_privacy_options');
      if (!completer.isCompleted) completer.complete();
    });
    await completer.future.timeout(const Duration(seconds: 12), onTimeout: () {
      _log('privacy options timeout');
    });
  }

  /// DEBUG-ONLY: clears the stored consent decision so the form shows again on
  /// the next [gatherConsent]. No-op in release builds.
  Future<void> resetForTesting() async {
    if (!kDebugMode) return;
    try {
      ConsentInformation.instance.reset();
      _completed = false;
      _canRequestAds = false;
      _status = ConsentStatus.unknown;
      _log('DEBUG consent reset');
    } catch (e) {
      _log('DEBUG consent reset failed: $e');
    }
  }

  void _log(String message) => debugPrint('ADS_CONSENT: $message');
}
