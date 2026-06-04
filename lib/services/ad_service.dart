import 'package:cricpro_flutter/models/ad_config.dart';
import 'package:cricpro_flutter/services/ads/ads_manager.dart';

/// Thin compatibility facade over [AdsManager].
///
/// Historically screens called `AdService.instance` directly. The real work
/// now lives in the adapter-based [AdsManager]; this keeps the old entry point
/// working while routing everything through the waterfall.
class AdService {
  AdService._();

  static final AdService instance = AdService._();

  AdConfig get config => AdsManager.instance.config;

  Future<void> initialize(AdConfig config) => AdsManager.instance.initialize(config);

  Future<void> updateConfig(AdConfig config) =>
      AdsManager.instance.updateConfig(config);
}
