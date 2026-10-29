// AdMob ad service for Doner (V1.2, all formats).
// Design (Jaani, 26 Oct 2026):
// - Interstitial: on EVERY directory list-item tap, every donor-card
//   WhatsApp tap, and every Call Now tap — no frequency cap. The
//   original action ALWAYS runs: after the ad closes, or immediately
//   when no ad is loaded or loading fails. A call or navigation is
//   never blocked on ad-load failure. The next interstitial is
//   preloaded after every show/dismiss so the next tap has one ready.
// - Banner: bottom of the home + directory screens (BannerAdWidget).
// - Native: cards inside the directory lists (NativeAdWidget, rendered
//   by the Android native-ad factory 'donerNative' — clearly an ad,
//   never a fake donor entry).
// - App Open: once per cold start, before the home screen is used.
// - Rewarded: INTENTIONALLY UNWIRED. The Rewarded unit exists in AdMob
//   but Aman has no unlockable feature to gate behind a reward (Jaani
//   confirmed 26 Oct 2026: revisit only if an unlock-worthy feature
//   appears). No reward is invented here.
// NOTE: the AdMob account is still under Google review; new units may
// take up to an hour to show ads. Nothing here touches payment/payout
// settings.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdService {
  static const String interstitialUnitId =
      'ca-app-pub-3940256099942544/1033173712';
  static const String bannerUnitId =
      'ca-app-pub-3940256099942544/6300978111';
  static const String nativeUnitId =
      'ca-app-pub-3940256099942544/2247696110';
  static const String appOpenUnitId =
      'ca-app-pub-3940256099942544/3419835294';

  static InterstitialAd? _ad;
  static bool _loading = false;

  static AppOpenAd? _appOpenAd;
  static bool _appOpenLoading = false;
  static bool _appOpenShownThisLaunch = false;

  static Future<void> init() async {
    await MobileAds.instance.initialize();
    _load();
    _loadAppOpen();
  }

  static void _load() {
    if (_loading || _ad != null) return;
    _loading = true;
    InterstitialAd.load(
      adUnitId: interstitialUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _ad = ad;
          _loading = false;
        },
        onAdFailedToLoad: (_) {
          _ad = null;
          _loading = false;
        },
      ),
    );
  }

  /// Runs [action] after an interstitial (if one is loaded), or immediately
  /// when none is loaded. Never blocks [action] on ad failure.
  static void runWithAd(FutureOr<void> Function() action) {
    final ad = _ad;
    if (ad == null) {
      _load();
      action();
      return;
    }
    _ad = null;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _load();
        action();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        _load();
        action();
      },
    );
    ad.show();
  }

  static void _loadAppOpen() {
    if (_appOpenLoading || _appOpenAd != null) return;
    _appOpenLoading = true;
    AppOpenAd.load(
      adUnitId: appOpenUnitId,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _appOpenAd = ad;
          _appOpenLoading = false;
        },
        onAdFailedToLoad: (_) {
          _appOpenAd = null;
          _appOpenLoading = false;
        },
      ),
    );
  }

  /// Shows the app-open ad once per cold start, if one is loaded.
  /// Never blocks the UI: if no ad is ready, this is a silent no-op.
  static void showAppOpenOnce() {
    if (_appOpenShownThisLaunch) return;
    _appOpenShownThisLaunch = true;
    final ad = _appOpenAd;
    if (ad == null) return;
    _appOpenAd = null;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) => ad.dispose(),
      onAdFailedToShowFullScreenContent: (ad, _) => ad.dispose(),
    );
    ad.show();
  }
}

/// Fixed banner slot for the bottom of the home + directory screens.
/// Renders nothing until an ad is actually loaded, so a failed load
/// never leaves a blank bar or covers any button.
class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({super.key});

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerAd? _bannerAd;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _bannerAd = BannerAd(
      adUnitId: AdService.bannerUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          if (mounted) setState(() => _bannerAd = null);
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _bannerAd;
    if (!_loaded || ad == null) return const SizedBox.shrink();
    return SizedBox(
      height: 50,
      child: Center(child: AdWidget(ad: ad)),
    );
  }
}

/// In-feed native ad card (directory lists). The Android factory
/// 'donerNative' renders the template; the card is visually an ad and
/// never pretends to be a donor entry.
class NativeAdWidget extends StatefulWidget {
  const NativeAdWidget({super.key});

  @override
  State<NativeAdWidget> createState() => _NativeAdWidgetState();
}

class _NativeAdWidgetState extends State<NativeAdWidget> {
  NativeAd? _nativeAd;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _nativeAd = NativeAd(
      adUnitId: AdService.nativeUnitId,
      factoryId: 'donerNative',
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, _) => ad.dispose(),
      ),
    )..load();
  }

  @override
  void dispose() {
    _nativeAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _nativeAd;
    if (!_loaded || ad == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SizedBox(height: 130, child: AdWidget(ad: ad)),
    );
  }
}
