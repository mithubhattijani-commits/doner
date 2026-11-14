// Unity Ads service for Doner (revenue ads).
//
// - Game ID: 800418043 (Android, "Doner" project)
// - Rewarded placement: BP_Rewarded_Android (Active)
// - Interstitial placement: BP_Interstitial_Android (Active)
// - These are REVENUE ads, not coin rewards — Doner is a blood-donor
//   app, not an earning app. No ledger, no Supabase involvement.
//
// Respect rules (blood-donation purpose):
// - Rewarded is VOLUNTARY only: a "support the society" button in the
//   Info tab. Never gates any feature, never blocks a critical flow.
// - Interstitial is STRICTLY frequency-capped (Jaani, 3 Nov 2026):
//   MAX 1 ad per visitor per 2 hours, persisted in SharedPreferences
//   so it survives app restarts. NEVER when the user is heading to
//   the Directory (donor search) or Register (donor registration)
//   tabs — those are critical flows.
//   USER COMFORT > REVENUE: when in doubt, show fewer ads.
// - Every show is best-effort: a failed load/show is a silent no-op,
//   never an error dialog, never a blocked navigation.
//
// Production mode: [testMode] is false, so real ads are served.
// Nothing here touches payment/payout settings.

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unity_ads_plugin/unity_ads_plugin.dart';
import 'remote_config_service.dart';

class UnityAdsService {
  static const String gameId = '800418043';
  static const String rewardedPlacementId = 'BP_Rewarded_Android';
  static const String interstitialPlacementId = 'BP_Interstitial_Android';
  static const String bannerPlacementId = 'BP_Banner_Android';

  /// Production mode (testMode = false): real ads are served.
  static const bool testMode = false;

  /// MASTER AD SWITCH (Jaani, 3 Nov 2026; remote-driven 14 Nov 2026):
  /// Unity ads ON with STRICT frequency cap — max 1 interstitial per
  /// visitor per 2 hours. Read live from the website admin panel
  /// (doner.json "ads.ads_enabled", default true = fail-open): the user
  /// turns ALL Unity ads off from the panel with no new build. The
  /// per-zone switches gate individual screens on top of this.
  static bool get adsEnabled =>
      remoteConfigService.config.ads.adsEnabled;

  static bool _initialized = false;
  static bool _initFailed = false;
  static bool _initStarted = false;

  static bool _rewardedLoading = false;
  static bool _interstitialLoading = false;

  // ---- Interstitial frequency cap (Jaani, 3 Nov 2026) ----
  // STRICT: max 1 interstitial per visitor per 2 hours.
  // Persisted in SharedPreferences so the cap survives app restarts.
  // USER COMFORT > REVENUE: when in doubt, show fewer ads.
  static DateTime? _lastInterstitialAt;
  static const Duration _minGap = Duration(hours: 2);
  static const String _prefsKeyLastAd = 'unity_last_interstitial_at_ms';

  /// Load the persisted cap state (last ad timestamp). Called once at
  /// startup; never blocks, never throws.
  static Future<void> _loadCapState() async {
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 5));
      final millis = prefs.getInt(_prefsKeyLastAd);
      if (millis != null && millis > 0) {
        _lastInterstitialAt = DateTime.fromMillisecondsSinceEpoch(millis);
      }
    } catch (_) {
      // Prefs unavailable: _lastInterstitialAt stays null.
    }
  }

  /// Persist the last-ad timestamp. Fire-and-forget, never throws.
  static Future<void> _saveCapState() async {
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 5));
      final last = _lastInterstitialAt;
      if (last != null) {
        await prefs.setInt(_prefsKeyLastAd, last.millisecondsSinceEpoch);
      }
    } catch (_) {
      // Silent: cap persistence is best-effort.
    }
  }

  /// Whether the SDK initialized successfully.
  static bool get isInitialized => _initialized;

  /// Initialize the Unity Ads SDK. Safe to call once at app startup;
  /// subsequent calls are no-ops. Never throws, never blocks startup
  /// beyond 10 seconds.
  static Future<void> init() async {
    if (!adsEnabled) return;
    if (_initialized || _initFailed || _initStarted) return;
    _initStarted = true;
    // Load persisted frequency-cap state (never blocks init).
    unawaited(_loadCapState());
    try {
      final completer = Completer<void>();
      UnityAds.init(
        gameId: gameId,
        testMode: testMode,
        onComplete: () {
          _initialized = true;
          if (!completer.isCompleted) completer.complete();
        },
        onFailed: (error, message) {
          _initFailed = true;
          if (!completer.isCompleted) completer.complete();
        },
      );
      await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {},
      );
      if (_initialized) {
        // Preload both formats in the background.
        unawaited(_loadRewarded());
        unawaited(_loadInterstitial());
      }
    } catch (_) {
      _initFailed = true;
    }
  }

  // ================= REWARDED =================

  static Future<void> _loadRewarded() async {
    if (!_initialized || _rewardedLoading) return;
    _rewardedLoading = true;
    try {
      final completer = Completer<void>();
      UnityAds.load(
        placementId: rewardedPlacementId,
        onComplete: (placementId) {
          if (!completer.isCompleted) completer.complete();
        },
        onFailed: (placementId, error, message) {
          if (!completer.isCompleted) completer.complete();
        },
      );
      await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {},
      );
    } catch (_) {
      // Silent: a missing ad never breaks the UI.
    } finally {
      _rewardedLoading = false;
    }
  }

  /// Show the rewarded video ad (voluntary "support the society" flow).
  ///
  /// Returns [UnityAdResult.completed] when the user watched the full ad,
  /// [UnityAdResult.skipped] when they skipped early, [UnityAdResult.failed]
  /// on error. Never throws.
  static Future<UnityAdResult> showRewardedAd() async {
    if (!adsEnabled) return UnityAdResult.failed;
    if (!_initialized) return UnityAdResult.failed;
    try {
      final completer = Completer<UnityAdResult>();
      UnityAds.showVideoAd(
        placementId: rewardedPlacementId,
        onStart: (placementId) {},
        onClick: (placementId) {},
        onSkipped: (placementId) {
          if (!completer.isCompleted) {
            completer.complete(UnityAdResult.skipped);
          }
        },
        onComplete: (placementId) {
          if (!completer.isCompleted) {
            completer.complete(UnityAdResult.completed);
          }
        },
        onFailed: (placementId, error, message) {
          if (!completer.isCompleted) {
            completer.complete(UnityAdResult.failed);
          }
        },
      );
      final result = await completer.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () => UnityAdResult.failed,
      );
      // Preload the next ad in the background (never blocks the UI).
      unawaited(_loadRewarded());
      return result;
    } catch (_) {
      return UnityAdResult.failed;
    }
  }

  
  /// One simple opt-in rewarded helper any screen can call.
  ///
  /// Only offers/shows when the master ads_enabled switch is on AND the
  /// remote-config rewarded_enabled zone is true; otherwise it calls
  /// onFail/onDone immediately and shows
  /// nothing. onReward runs only when the user watched the full ad;
  /// onFail runs when the ad was skipped or failed; onDone always
  /// runs at the end. Never throws, never shows an error popup.
    static Future<void> showRewardedVideo({
          required void Function() onReward,
          void Function()? onFail,
          void Function()? onDone,
    }) async {
          if (!remoteConfigService.config.ads.rewardedEnabled) {
                  onFail?.call();
                  onDone?.call();
                  return;
          }
          final UnityAdResult result = await showRewardedAd();
          if (result == UnityAdResult.completed) {
                  onReward();
          } else {
                  onFail?.call();
          }
          onDone?.call();
    }
  // ================= INTERSTITIAL =================

  static Future<void> _loadInterstitial() async {
    if (!_initialized || _interstitialLoading) return;
    _interstitialLoading = true;
    try {
      final completer = Completer<void>();
      UnityAds.load(
        placementId: interstitialPlacementId,
        onComplete: (placementId) {
          if (!completer.isCompleted) completer.complete();
        },
        onFailed: (placementId, error, message) {
          if (!completer.isCompleted) completer.complete();
        },
      );
      await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {},
      );
    } catch (_) {
      // Silent.
    } finally {
      _interstitialLoading = false;
    }
  }

  /// Called on every bottom-nav tab switch. Shows a Unity interstitial
  /// only when the frequency cap allows it AND [targetIsCritical] is
  /// false (Directory = donor search, Register = donor registration
  /// are critical and never interrupted).
  ///
  /// The [onDone] callback always runs — immediately when no ad is
  /// shown, or after the ad is dismissed/failed. Navigation is never
  /// blocked on ad failure.
  static void maybeShowInterstitial({
    required bool targetIsCritical,
    required void Function() onDone,
  }) {
    if (!adsEnabled) {
      onDone();
      return;
    }
    if (targetIsCritical || !_capAllows()) {
      onDone();
      return;
    }
    _showInterstitialNow(onDone);
  }

  static bool _capAllows() {
    if (!_initialized) return false;
    final last = _lastInterstitialAt;
    if (last != null &&
        DateTime.now().difference(last) < _minGap) {
      return false;
    }
    return true;
  }

  static void _showInterstitialNow(void Function() onDone) {
    bool doneCalled = false;
    void finish() {
      if (!doneCalled) {
        doneCalled = true;
        onDone();
      }
    }

    try {
      UnityAds.showVideoAd(
        placementId: interstitialPlacementId,
        onStart: (placementId) {
          _lastInterstitialAt = DateTime.now();
          unawaited(_saveCapState());
        },
        onClick: (placementId) {},
        onSkipped: (placementId) {
          unawaited(_loadInterstitial());
          finish();
        },
        onComplete: (placementId) {
          unawaited(_loadInterstitial());
          finish();
        },
        onFailed: (placementId, error, message) {
          unawaited(_loadInterstitial());
          finish();
        },
      );
      // Safety net: if no callback fires within 2 minutes, unblock.
      Future.delayed(const Duration(minutes: 2), finish);
    } catch (_) {
      unawaited(_loadInterstitial());
      finish();
    }
  }
}

/// Outcome of showing a Unity ad.
enum UnityAdResult {
  /// User watched the full ad.
  completed,

  /// User skipped before the end.
  skipped,

  /// Ad failed to load or show.
  failed,
}

/// Unity banner at the bottom of home/directory (replaces the AdMob test banner).
/// Renders nothing while the banner is loading or if it fails to load,
/// so the page layout never leaves a permanent empty band.
class UnityBannerAdWidget extends StatefulWidget {
  const UnityBannerAdWidget({super.key});

  @override
  State<UnityBannerAdWidget> createState() => _UnityBannerAdWidgetState();
}

class _UnityBannerAdWidgetState extends State<UnityBannerAdWidget> {
  bool _loaded = false;

  @override
  Widget build(BuildContext context) {
    if (!UnityAdsService.adsEnabled) return const SizedBox.shrink();
    // Single UnityBannerAd instance kept mounted (maintainState) so it
    // loads once and never reloads on rebuild; Visibility only controls
    // whether the loaded 50px banner takes space.
    return Visibility(
      visible: _loaded,
      maintainState: true,
      child: SizedBox(
        height: 50,
        child: Center(
          child: UnityBannerAd(
            placementId: UnityAdsService.bannerPlacementId,
            onLoad: (placementId) {
              if (mounted) setState(() => _loaded = true);
            },
            onClick: (placementId) {},
            onShown: (placementId) {},
            onFailed: (placementId, error, message) {
              if (mounted) setState(() => _loaded = false);
            },
          ),
        ),
      ),
    );
  }
}


/// A Unity banner slot gated by one per-zone remote-config switch.
///
/// The [zone] selector reads the zone from the current remote config
/// (e.g. `(ads) => ads.bannerHome`). When the zone is off the slot
/// renders nothing (zero height); when it is on, the inner
/// [UnityBannerAdWidget] renders the banner and itself shrinks to
/// nothing while loading or on failure. Rebuilds automatically when
/// the remote config refreshes. Place it in a quiet bottom slot -
/// never over content, never blocking a button.
class ZonedUnityBanner extends StatelessWidget {
    const ZonedUnityBanner({super.key, required this.zone});
    final bool Function(AdsConfig) zone;
    @override
    Widget build(BuildContext context) {
          return ValueListenableBuilder<RemoteConfig>(
                  valueListenable: remoteConfigService.notifier,
                  builder: (BuildContext context, RemoteConfig config, _) {
                            if (!zone(config.ads)) return const SizedBox.shrink();
                            return const UnityBannerAdWidget();
                  },
                );
    }
}
