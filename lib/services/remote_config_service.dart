/// Remote Config v1 — server-driven in-app content for Doner.
///
/// Display name, logo, announcement bar, sponsored ads and a force-update
/// kill-switch come from https://nigraantv.xyz/apps/config/doner.json and
/// can change WITHOUT an app update. (Android launcher icon / system app
/// name cannot change remotely — baked into the APK.)
/// Behavior: fetch at cold start with an 8-second timeout; cache last-good
/// JSON in SharedPreferences with a timestamp; re-fetch when the cache is
/// older than 60 seconds (or missing). Order: network -> cache -> bundled
/// defaults. Never blocks startup, never an infinite spinner, never a
/// crash — on any failure the app just uses what it has.
/// This is SEPARATE from the older lib/services/config_service.dart
/// (doner-config.json) — that file is untouched.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AnnouncementConfig {
  const AnnouncementConfig({this.enabled = false, this.text = ''});
  final bool enabled;
  final String text;
  bool get show => enabled && text.trim().isNotEmpty;
  factory AnnouncementConfig.fromJson(Map<String, dynamic> j) =>
      AnnouncementConfig(
        enabled: j['enabled'] == true,
        text: (j['text'] ?? '').toString(),
      );
}

class SponsoredAdConfig {
  const SponsoredAdConfig({
    this.enabled = false,
    this.title = '',
    this.imageUrl = '',
    this.actionUrl = '',
  });
  final bool enabled;
  final String title;
  final String imageUrl;
  final String actionUrl;
  bool get show =>
      enabled && title.trim().isNotEmpty && actionUrl.trim().isNotEmpty;
  factory SponsoredAdConfig.fromJson(Map<String, dynamic> j) =>
      SponsoredAdConfig(
        enabled: j['enabled'] == true,
        title: (j['title'] ?? '').toString(),
        imageUrl: (j['image_url'] ?? '').toString(),
        actionUrl: (j['action_url'] ?? '').toString(),
      );
}

class ForceUpdateConfig {
  const ForceUpdateConfig({this.enabled = false, this.minVersionCode = 0});
  final bool enabled;
  final int minVersionCode;
  factory ForceUpdateConfig.fromJson(Map<String, dynamic> j) =>
      ForceUpdateConfig(
        enabled: j['enabled'] == true,
        minVersionCode: (j['min_version_code'] is int)
            ? j['min_version_code'] as int
            : int.tryParse('${j['min_version_code']}') ?? 0,
      );
}

/// Advertising banner (Info tab): an optional, server-driven "For
/// Advertising" card. `enabled` defaults to true so the banner keeps
/// showing exactly as today when the key is missing; set it to false in
/// the remote config to hide it without a new build. When `image_url` is
/// empty the app keeps using the bundled banner image.
class AdvertisingBannerConfig {
  const AdvertisingBannerConfig({
    this.enabled = true,
    this.imageUrl = '',
    this.title = 'For Advertising',
    this.subtitle = 'Contact Us on WhatsApp:',
    this.whatsappUrl = 'https://wa.me/923090808180',
    this.phoneDisplay = '03090808180',
  });
  final bool enabled;
  final String imageUrl;
  final String title;
  final String subtitle;
  final String whatsappUrl;
  final String phoneDisplay;
  factory AdvertisingBannerConfig.fromJson(Map<String, dynamic> j) =>
      AdvertisingBannerConfig(
        enabled: j['enabled'] is bool ? j['enabled'] as bool : true,
        imageUrl: (j['image_url'] ?? '').toString(),
        title: (j['title'] ?? 'For Advertising').toString(),
        subtitle: (j['subtitle'] ?? 'Contact Us on WhatsApp:').toString(),
        whatsappUrl: (j['whatsapp_url'] ?? 'https://wa.me/923090808180')
            .toString(),
        phoneDisplay: (j['phone_display'] ?? '03090808180').toString(),
      );
}

class RemoteConfig {
  const RemoteConfig({
    this.displayName = '',
    this.logoUrl = '',
    this.announcement = const AnnouncementConfig(),
    this.sponsoredAd = const SponsoredAdConfig(),
    this.forceUpdate = const ForceUpdateConfig(),
    this.advertisingBanner = const AdvertisingBannerConfig(),
    this.societyNameUr = 'امن بلڈ ڈونر سوسائٹی آف پاکستان',
    this.societyNameEn = 'AMAN BLOOD DONOR SOCIETY OF PAKISTAN',
    this.homeTaglineUr = 'آپ کا ایک قطرہ خون — کسی کی پوری زندگی',
    this.homeTaglineEn = '🩸 خون عطیہ کریں، زندگیاں بچائیں 🩸',
  });
  final String displayName;
  final String logoUrl;
  final AnnouncementConfig announcement;
  final SponsoredAdConfig sponsoredAd;
  final ForceUpdateConfig forceUpdate;
  final AdvertisingBannerConfig advertisingBanner;
  final String societyNameUr;
  final String societyNameEn;
  final String homeTaglineUr;
  final String homeTaglineEn;
  static const RemoteConfig defaults = RemoteConfig();
  factory RemoteConfig.fromJson(Map<String, dynamic> j) => RemoteConfig(
        displayName: (j['display_name'] ?? '').toString(),
        logoUrl: (j['logo_url'] ?? '').toString(),
        announcement: AnnouncementConfig.fromJson(
            (j['announcement'] as Map?)?.cast<String, dynamic>() ??
                const <String, dynamic>{}),
        sponsoredAd: SponsoredAdConfig.fromJson(
            (j['sponsored_ad'] as Map?)?.cast<String, dynamic>() ??
                const <String, dynamic>{}),
        forceUpdate: ForceUpdateConfig.fromJson(
            (j['force_update'] as Map?)?.cast<String, dynamic>() ??
                const <String, dynamic>{}),
        advertisingBanner: AdvertisingBannerConfig.fromJson(
            (j['advertising_banner'] as Map?)?.cast<String, dynamic>() ??
                const <String, dynamic>{}),
        societyNameUr:
            (j['society_name_ur'] ?? 'امن بلڈ ڈونر سوسائٹی آف پاکستان')
                .toString(),
        societyNameEn:
            (j['society_name_en'] ?? 'AMAN BLOOD DONOR SOCIETY OF PAKISTAN')
                .toString(),
        homeTaglineUr: (j['home_tagline_ur'] ??
                'آپ کا ایک قطرہ خون — کسی کی پوری زندگی')
            .toString(),
        homeTaglineEn:
            (j['home_tagline_en'] ?? '🩸 خون عطیہ کریں، زندگیاں بچائیں 🩸')
                .toString(),
      );
}

class RemoteConfigService {
  static const String configUrl =
      'https://nigraantv.xyz/apps/config/doner.json';
  static const Duration fetchTimeout = Duration(seconds: 8);
  static const Duration refreshInterval = Duration(seconds: 60);
  static const String _cacheKey = 'remote_config_json_v1';
  static const String _cacheTimeKey = 'remote_config_time_v1';

  final ValueNotifier<RemoteConfig> notifier =
      ValueNotifier<RemoteConfig>(RemoteConfig.defaults);

  RemoteConfig get config => notifier.value;

  /// Loads the last-good cached config (if any), then refreshes from the
  /// server when it is missing/stale. Never throws.
  Future<void> init() async {
    await _loadFromCache();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int ts = prefs.getInt(_cacheTimeKey) ?? 0;
    final int age = DateTime.now().millisecondsSinceEpoch - ts;
    if (ts == 0 || age > refreshInterval.inMilliseconds) {
      unawaited(_refresh());
    }
  }

  Future<void> _loadFromCache() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_cacheKey);
      if (raw != null && raw.isNotEmpty) {
        notifier.value =
            RemoteConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {
      notifier.value = RemoteConfig.defaults;
    }
  }

  Future<void> _refresh() async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = fetchTimeout;
      final HttpClientRequest req =
          await client.getUrl(Uri.parse(configUrl));
      final HttpClientResponse resp =
          await req.close().timeout(fetchTimeout);
      if (resp.statusCode != HttpStatus.ok) return;
      final String body = await resp.transform(utf8.decoder).join();
      final RemoteConfig parsed =
          RemoteConfig.fromJson(jsonDecode(body) as Map<String, dynamic>);
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, body);
      await prefs.setInt(
          _cacheTimeKey, DateTime.now().millisecondsSinceEpoch);
      notifier.value = parsed;
    } catch (_) {
      // Keep whatever config we already have — defaults, cache, or last-good.
    } finally {
      client?.close(force: true);
    }
  }
}

/// Singleton used across the app (same pattern as ConfigService).
final RemoteConfigService remoteConfigService = RemoteConfigService();

/// Refresh handle for callers outside [RemoteConfigService]: launch,
/// resume, reconnect and the short (~60s) poll all use [refresh]. A fetch
/// already in flight is skipped instead of duplicated. Never throws.
bool _rcRefreshing = false;

extension RemoteConfigServiceRefresh on RemoteConfigService {
  Future<void> refresh() async {
    if (_rcRefreshing) return;
    _rcRefreshing = true;
    try {
      await _refresh();
    } finally {
      _rcRefreshing = false;
    }
  }
}
