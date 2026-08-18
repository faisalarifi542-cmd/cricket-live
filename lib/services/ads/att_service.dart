import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';

/// iOS App Tracking Transparency (ATT) gate.
///
/// Apple requires an ATT prompt before a mobile app accesses the advertising
/// identifier (IDFA). google_mobile_ads requests IDFA by default, so on iOS
/// the ATT authorization must be resolved before the AdMob SDK loads ads —
/// otherwise personalized ads cannot be served and the app is not compliant
/// with the App Store Tracking rule.
///
/// This is separate from the UMP/GDPR consent flow in [ConsentManager], which
/// handles regulated-region (EEA/UK) consent. ATT is the Apple-platform
/// IDFA prompt and applies globally on iOS. The recommended order is UMP
/// first (so EEA users see the GDPR form), then ATT — which is exactly where
/// [AttService.requestIfNeeded] is called in [AdsManager.initialize].
///
/// Fail-open by design: a plugin/Platform error never throws and never blocks
/// ad SDK initialization — the worst case is no IDFA (non-personalized ads),
/// not a crashed launch. Calling [requestTrackingAuthorization] is idempotent:
/// iOS shows the system prompt only while the status is `notDetermined` and
/// returns the stored decision thereafter, so repeat calls within a process
/// (e.g. on a config refresh) are safe and guarded by [_requested].
class AttService {
  AttService._();

  static final AttService instance = AttService._();

  bool _requested = false;
  TrackingStatus _status = TrackingStatus.notDetermined;

  /// The latest ATT authorization status known to this process.
  TrackingStatus get status => _status;

  /// True only when the user explicitly granted tracking authorization.
  bool get granted => _status == TrackingStatus.authorized;

  /// Requests ATT authorization on iOS. No-op on Android/web (status becomes
  /// `notSupported`). Safe to call repeatedly; only acts once per process.
  Future<void> requestIfNeeded() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      _status = TrackingStatus.notSupported;
      return;
    }
    if (_requested) return;
    _requested = true;
    try {
      // Prompts the first time; returns the existing decision on later calls.
      _status = await AppTrackingTransparency.requestTrackingAuthorization();
      debugPrint('ADS_ATT: status=${_status.name}');
    } on PlatformException catch (e) {
      _status = TrackingStatus.notDetermined;
      debugPrint('ADS_ATT: request failed ${e.code} ${e.message}');
    } catch (e) {
      _status = TrackingStatus.notDetermined;
      debugPrint('ADS_ATT: error $e');
    }
  }
}
