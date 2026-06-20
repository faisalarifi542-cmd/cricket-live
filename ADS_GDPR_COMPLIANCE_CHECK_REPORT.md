# Ads GDPR / UMP Compliance Check Report

Date: 2026-06-13

## Whether UMP existed before

Yes. The app already had `lib/services/ads/consent_manager.dart` using the UMP
APIs bundled in `google_mobile_ads`:

- `ConsentInformation.requestConsentInfoUpdate`
- `ConsentForm.loadAndShowConsentFormIfRequired`
- `ConsentInformation.canRequestAds`

## What was missing / unsafe

- UMP could be skipped entirely when Admin `consentRequired=false`.
- `canRequestAds()` failed open on errors.
- The app did not expose a privacy-options entry point when UMP required one.
- Consent diagnostics were incomplete.

## Files changed

- `lib/services/ads/consent_manager.dart`
- `lib/services/ads/ads_manager.dart`
- `lib/main.dart`
- `lib/screens/more/more_screen.dart`
- `ADS_GDPR_COMPLIANCE_CHECK_REPORT.md`

## How consent flow works now

1. Admin `/app/config` loads ads config.
2. `AdsManager.initialize(config)` starts only if ads are enabled.
3. Before any ad SDK initialization or ad load:
   - UMP requests consent info update on every ads-enabled launch.
   - UMP logs consent status, form availability, privacy-options requirement,
     and `canRequestAds`.
   - UMP loads/shows the consent form if required.
   - UMP refreshes status after the form is dismissed.
4. If `canRequestAds=false`, ad SDK initialization is skipped and no banner,
   interstitial, rewarded, app-open, or pre-roll ad loads.
5. If `canRequestAds=true`, AdMob initializes and normal admin-controlled ad
   loading begins.

The app does not manually force personalized ads. UMP and Google Mobile Ads SDK
apply the user's consent choices to ad requests. If consent is denied/unavailable
and UMP says ads cannot be requested, the app does not load ads.

## Privacy options entry

The More screen now shows `Privacy Choices` only when:

```dart
ConsentInformation.getPrivacyOptionsRequirementStatus() == required
```

Tapping it calls:

```dart
ConsentForm.showPrivacyOptionsForm(...)
```

## Logs to verify

Filter logs for:

- `ADS_CONSENT: requestConsentInfoUpdate start`
- `ADS_CONSENT: after_update status=... formAvailable=... privacyOptions=... canRequestAds=...`
- `ADS_CONSENT: form completed or not required`
- `ADS_CONSENT: complete status=... privacyOptions=... canRequestAds=...`
- `ADS_CONFIG: UMP complete; ad SDK initialization starting`
- `ADS_CONFIG: ad initialization skipped reason=ump_can_request_ads_false`

## Android checks

- Production AdMob App ID exists in `AndroidManifest.xml`:
  `ca-app-pub-5604905670303331~7374966285`
- `INTERNET` permission exists.
- `ACCESS_NETWORK_STATE` permission exists.
- No release/test-device privacy debug geography is forced. EEA debug geography
  is only used when `testMode=true` and debug device IDs are provided.
- `MobileAds.instance.initialize()` happens only after UMP consent completes and
  `canRequestAds=true`.

## How to test from Germany / EEA

1. In AdMob, create and publish a European regulations message for this app.
2. Install a fresh build or clear app data.
3. Launch from Germany/EEA, UK, or Switzerland.
4. Confirm logs show `requestConsentInfoUpdate`.
5. Confirm UMP form appears if required.
6. Make a consent choice.
7. Confirm logs show `canRequestAds=true` before `ADS_INIT: network=admob`.
8. Open More and confirm `Privacy Choices` appears if UMP reports it required.
9. Change choices through `Privacy Choices`.
10. Confirm ads load only after consent flow is complete.

## Manual AdMob step required

Create and publish the European regulations / GDPR message in AdMob Privacy &
Messaging for the production Android app. UMP can only show the form configured
for the AdMob application ID in the manifest.

## Commands run

- `flutter analyze lib/services/ads lib/widgets/ads lib/models/ad_config.dart lib/main.dart lib/screens/more/more_screen.dart` - passed.
- `flutter test` - 38 tests passed.
- `flutter build apk --debug` - passed.

## Notes

This change only touches ads/privacy flow and the required More-screen privacy
entry point. It does not change app design, ad placement design, backend/admin
ads settings, Unity/Meta adapters, or non-ads app behavior.
