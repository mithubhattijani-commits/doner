/// Remote Config v1 — server-driven in-app content for Doner.
///
/// Display name, logo, announcement bar, sponsored ads and a force-update
/// kill-switch come from https://nigraantv.xyz/apps/config/doner.json and
/// can change WITHOUT an app update. (Android launcher icon / system app
/// name cannot change remotely — baked into the APK.)
///
/// Behavior: fetch at cold start with an 8-second timeout; cache last-good
/// JSON in SharedPreferences with a timestamp; re-fetch when the cache is
/// older than 6 hours (or missing). Order: network -> cache -> bundled
/// defaults. Never blocks startup, never an infinite spinner, never a
/// crash — on any failure the app just uses what it has.
///
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

class RemoteConfig {
  const RemoteConfig({
    this.displayName = '',
    this.logoUrl = '',
    this.announcement = const AnnouncementConfig(),
    this.sponsoredAd = const SponsoredAdConfig(),
    this.forceUpdate = const ForceUpdateConfig(),
  });
  final String displayName;
  final String logoUrl;
  final AnnouncementConfig announcement;
  final SponsoredAdConfig sponsoredAd;
  final ForceUpdateConfig forceUpdate;

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
      );
}

class RemoteConfigService {
  /// Doner config endpoint (published on the website; no APK needed).
  static const String configUrl =
      'https://nigraantv.xyz/apps/config/doner.json';

  static const Duration fetchTimeout = Duration(seconds: 8);
  static const Duration refreshInterval = Duration(hours: 6);
  static const String _cacheKey = 'remote_config_json_v1';
  static const String _cacheTimeKey = 'remote_config_time_v1';

  final ValueNotifier<RemoteConfig> notifier =
      ValueNotifier<RemoteConfig>(RemoteConfig.defaults);

  RemoteConfig get config => notifier.value;

  /// Call once at startup. Returns immediately after the cache load;
  /// the network refresh happens in the background and never blocks.
  Future<void> init() async {
    await _loadFromCache();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int ts = prefs.getInt(_cacheTimeKey) ?? 0;
    final int age = DateTime.now().millisecondsSinceEpoch - ts;
    if (ts == 0 || age > refreshInterval.inMilliseconds) {
      unawaited(_refresh()); // never block startup
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
      final HttpClientRequest req = await client.getUrl(Uri.parse(configUrl));
      final HttpClientResponse resp = await req.close().timeout(fetchTimeout);
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
      // Fail-soft: keep cache/defaults.
    } finally {
      client?.close(force: true);
    }
  }
}

/// App-wide singleton — one notifier for the whole app.
final RemoteConfigService remoteConfigService = RemoteConfigService();
