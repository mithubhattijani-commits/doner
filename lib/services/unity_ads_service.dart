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
// - Interstitial is frequency-capped: at most once per 3 bottom-nav
//   tab switches AND at least 90 seconds apart, and NEVER when the
//   user is heading to the Directory (donor search) or Register
//   (donor registration) tabs — those are critical flows.
// - Every show is best-effort: a failed load/show is a silent no-op,
//   never an error dialog, never a blocked navigation.
//
// Test mode is ON for development. Flip [testMode] to false for
// production builds. Nothing here touches payment/payout settings.

import 'dart:async';

import 'package:unity_ads_plugin/unity_ads_plugin.dart';

class UnityAdsService {
  static const String gameId = '800418043';
  static const String rewardedPlacementId = 'BP_Rewarded_Android';
  static const String interstitialPlacementId = 'BP_Interstitial_Android';

  /// Keep true while testing. Production builds set this to false.
  static const bool testMode = false;

  static bool _initialized = false;
  static bool _initFailed = false;
  static bool _initStarted = false;

  static bool _rewardedLoading = false;
  static bool _interstitialLoading = false;

  // ---- Interstitial frequency cap ----
  static int _tabSwitchesSinceAd = 0;
  static DateTime? _lastInterstitialAt;
  static const int _switchesPerAd = 3;
  static const Duration _minGap = Duration(seconds: 90);

  /// Whether the SDK initialized successfully.
  static bool get isInitialized => _initialized;

  /// Initialize the Unity Ads SDK. Safe to call once at app startup;
  /// subsequent calls are no-ops. Never throws, never blocks startup
  /// beyond 10 seconds.
  static Future<void> init() async {
    if (_initialized || _initFailed || _initStarted) return;
    _initStarted = true;
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
    _tabSwitchesSinceAd++;
    if (targetIsCritical || !_capAllows()) {
      onDone();
      return;
    }
    _showInterstitialNow(onDone);
  }

  static bool _capAllows() {
    if (!_initialized) return false;
    if (_tabSwitchesSinceAd < _switchesPerAd) return false;
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
          _tabSwitchesSinceAd = 0;
          _lastInterstitialAt = DateTime.now();
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
