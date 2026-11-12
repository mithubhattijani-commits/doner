/// Doner — in-app update checker for sideloaded builds.
///
/// The app fetches a small JSON manifest from the website and compares
/// its versionCode with the installed one. When a newer version exists,
/// the user is offered an update; the new APK downloads in the
/// BACKGROUND via Android DownloadManager (system process — survives
/// app background/kill, shows a persistent notification, auto-resumes
/// on network interruption, follows redirects natively) and the system
/// install prompt fires when it completes. A sideloaded app can NEVER
/// install silently — Android always requires the user's install tap,
/// and the UI says so honestly.
///
/// Manifest format (served from the website, published separately):
///   {"versionCode": 2, "versionName": "1.1.0",
///    "url": "https://.../doner-v1.0.7.apk", "notes": "What's new"}
///
/// The updater is inert until that manifest exists: a missing or
/// unreachable manifest simply means "no update prompt, no error".
///
/// V1.3 nag fix (Jaani's complaint): the launch check no longer nags
/// every launch. A version the user dismissed ("بعد میں") is recorded
/// under 'dismissed_update_code' and never prompts again on launch;
/// a future newer version prompts again. On launch the APK downloads
/// in the BACKGROUND and the install prompt is shown ONCE when it
/// completes. If that version's APK is already downloaded, the install
/// prompt is shown directly instead of re-downloading. The manual check
/// still shows its dialog regardless of dismissal, exactly as before.
///
/// v1.0.7 background-download rework (Jaani, 3 Nov 2026): the APK no
/// longer downloads through Dart HttpClient (dies with the app). It
/// goes through the native `doner/updater` MethodChannel into Android
/// DownloadManager. Tapping "اپ ڈیٹ" never locks the app behind a modal:
/// the download runs in the background, the user keeps using the app,
/// live progress shows in the in-flow banner, and the install prompt
/// appears when the APK is ready — even if the user navigated away
/// (via [navigatorKey]) or restarted the app (the pending download is
/// re-attached from SharedPreferences on launch).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One update entry parsed from the version manifest.
class UpdateInfo {
  const UpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.url,
    required this.notes,
  });

  final int versionCode;
  final String versionName;
  final String url;
  final String notes;
}

/// Distinguished outcome of a manual update check (Jaani 31 Oct 2026:
/// "no new version" vs "no internet" vs "update file not found" must
/// show different messages, not one shared message).
enum UpdateCheckResult {
  /// A newer version is available (details in [UpdateCheckOutcome.update]).
  available,

  /// Installed version is already the latest.
  upToDate,

  /// No network connectivity.
  noInternet,

  /// Manifest unreachable (404 / bad response / bad JSON).
  manifestNotFound,
}

/// Combined result of [UpdateService.checkForUpdate]: the distinguished
/// status plus the [UpdateInfo] when a newer version exists.
class UpdateCheckOutcome {
  const UpdateCheckOutcome(this.status, [this.update]);

  final UpdateCheckResult status;
  final UpdateInfo? update;
}

/// Live progress of the background APK download, shown in the in-flow
/// banner (never a modal). Null when no download is running.
/// [total] is -1 when the size is unknown (then the banner shows
/// live status text instead of a % — never a fake percentage).
class UpdateDownloadProgress {
  const UpdateDownloadProgress({required this.received, required this.total});

  final int received;
  final int total;

  bool get known => total > 0;
  double get fraction =>
      known ? (received / total).clamp(0.0, 1.0) : 0;
  int get percentDone => known ? (fraction * 100).round() : 0;
  int get percentLeft => known ? 100 - percentDone : 0;
  String get mbLine => known
      ? '${(received / 1000000).toStringAsFixed(1)} MB / '
          '${(total / 1000000).toStringAsFixed(1)} MB'
      : '';
}

/// A download handed to (or re-attached from) Android DownloadManager.
class _PendingDownload {
  const _PendingDownload({
    required this.downloadId,
    required this.update,
    required this.apkPath,
  });

  final int downloadId;
  final UpdateInfo update;
  final String apkPath;
}

class UpdateService {
  /// Fixed manifest URL. The file itself is published separately by the
  /// parent (with the stable APK download link); until then this
  /// checker stays silent. The manifest is a tiny JSON fetch — plain
  /// HttpClient with timeouts is fine here; only the APK itself goes
  /// through DownloadManager (background-safe).
  static const String manifestUrl =
      'https://nigraantv.xyz/apps/doner-version.json';

  /// VersionCode the user dismissed with "بعد میں" — never re-prompted
  /// on launch. A newer versionCode prompts again.
  static const String dismissedKey = 'dismissed_update_code';

  /// Global navigator key for the updater (Jaani, 3 Nov 2026): the
  /// install prompt must appear even if the user navigated away from
  /// the screen that started the download. Wired into MaterialApp in
  /// main.dart (`navigatorKey: UpdateService.navigatorKey`).
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  /// Live background-download progress for the in-flow banner. Global
  /// (not tied to any screen) so it survives navigation.
  static final ValueNotifier<UpdateDownloadProgress?> launchProgress =
      ValueNotifier<UpdateDownloadProgress?>(null);

  /// Alias for [launchProgress] (Jaani's order names it backgroundProgress).
  static ValueNotifier<UpdateDownloadProgress?> get backgroundProgress =>
      launchProgress;

  static const MethodChannel _channel = MethodChannel('doner/updater');

  /// SharedPreferences keys for the in-flight DownloadManager download,
  /// so a download started in a previous session is re-attached (or its
  /// finished APK offered for install) on the next launch.
  static const String _dlIdKey = 'doner_update_download_id';
  static const String _dlVersionKey = 'doner_update_version_code';
  static const String _dlNameKey = 'doner_update_version_name';
  static const String _dlNotesKey = 'doner_update_notes';
  static const String _dlUrlKey = 'doner_update_url';
  static const String _dlPathKey = 'doner_update_apk_path';

  /// Guards the poll loop: exactly one tracker per download id.
  static int? _trackedDownloadId;

  /// Per-version APK file name, so an already-downloaded APK for the
  /// same version is reused instead of re-downloaded.
  static String _apkFileName(int versionCode) =>
      'doner-update-$versionCode.apk';

  /// Where DownloadManager puts the file:
  /// `setDestinationInExternalFilesDir(DIRECTORY_DOWNLOADS, fileName)`.
  static Future<File> _expectedApkFile(int versionCode) async {
    try {
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        return File('${ext.path}/Download/${_apkFileName(versionCode)}');
      }
    } catch (_) {
      // Fall through to the temp-dir fallback below.
    }
    final tmp = await getTemporaryDirectory();
    return File('${tmp.path}/${_apkFileName(versionCode)}');
  }

  static Future<int?> _dismissedCode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(dismissedKey);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _recordDismissed(int versionCode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(dismissedKey, versionCode);
    } catch (_) {
      // Dismissal is best-effort; a missed write only re-prompts once.
    }
  }

  static Future<void> _saveDownload(_PendingDownload dl) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_dlIdKey, dl.downloadId);
      await prefs.setInt(_dlVersionKey, dl.update.versionCode);
      await prefs.setString(_dlNameKey, dl.update.versionName);
      await prefs.setString(_dlNotesKey, dl.update.notes);
      await prefs.setString(_dlUrlKey, dl.update.url);
      await prefs.setString(_dlPathKey, dl.apkPath);
    } catch (_) {
      // Best-effort: without the record the download still completes
      // in DownloadManager; only the re-attach is lost.
    }
  }

  static Future<_PendingDownload?> _loadDownload() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getInt(_dlIdKey);
      final code = prefs.getInt(_dlVersionKey);
      final url = prefs.getString(_dlUrlKey);
      if (id == null || code == null || url == null) return null;
      return _PendingDownload(
        downloadId: id,
        update: UpdateInfo(
          versionCode: code,
          versionName: prefs.getString(_dlNameKey) ?? 'v$code',
          url: url,
          notes: prefs.getString(_dlNotesKey) ?? '',
        ),
        apkPath: prefs.getString(_dlPathKey) ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> _clearDownload() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_dlIdKey);
      await prefs.remove(_dlVersionKey);
      await prefs.remove(_dlNameKey);
      await prefs.remove(_dlNotesKey);
      await prefs.remove(_dlUrlKey);
      await prefs.remove(_dlPathKey);
    } catch (_) {
      // Best-effort.
    }
  }

  /// Quick connectivity probe: resolves the update host. Used by the
  /// manual check to distinguish "no internet" from other failures.
  static Future<bool> _hasInternetConnection() async {
    try {
      final result = await InternetAddress.lookup('nigraantv.xyz')
          .timeout(const Duration(seconds: 5));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Manual-check entry point with distinguished failure modes.
  /// Returns the status plus [UpdateInfo] when a newer version exists.
  /// Never throws.
  static Future<UpdateCheckOutcome> checkForUpdate() async {
    if (!await _hasInternetConnection()) {
      return const UpdateCheckOutcome(UpdateCheckResult.noInternet);
    }
    HttpClient? client;
    try {
      client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15);
      final request = await client.getUrl(Uri.parse(manifestUrl));
      final response =
          await request.close().timeout(const Duration(seconds: 20));
      if (response.statusCode != HttpStatus.ok) {
        return const UpdateCheckOutcome(UpdateCheckResult.manifestNotFound);
      }
      final body = await response.transform(utf8.decoder).join();
      final data = jsonDecode(body);
      if (data is! Map<String, dynamic>) {
        return const UpdateCheckOutcome(UpdateCheckResult.manifestNotFound);
      }
      final remoteCode = data['versionCode'];
      final url = data['url'];
      if (remoteCode is! int || url is! String || url.isEmpty) {
        return const UpdateCheckOutcome(UpdateCheckResult.manifestNotFound);
      }
      final info = await PackageInfo.fromPlatform();
      final currentCode = int.tryParse(info.buildNumber) ?? 0;
      if (remoteCode <= currentCode) {
        return const UpdateCheckOutcome(UpdateCheckResult.upToDate);
      }
      return UpdateCheckOutcome(
        UpdateCheckResult.available,
        UpdateInfo(
          versionCode: remoteCode,
          versionName: (data['versionName'] as String?) ?? 'v$remoteCode',
          url: url,
          notes: (data['notes'] as String?) ?? '',
        ),
      );
    } on SocketException {
      return const UpdateCheckOutcome(UpdateCheckResult.noInternet);
    } catch (_) {
      return const UpdateCheckOutcome(UpdateCheckResult.manifestNotFound);
    } finally {
      client?.close(force: true);
    }
  }

  /// Returns update info only when a NEWER version exists.
  /// Never throws: any failure (no network, missing manifest, bad
  /// JSON, bad version) simply means "no update prompt".
  /// Used by the silent launch check.
  static Future<UpdateInfo?> fetchUpdate() async {
    final outcome = await checkForUpdate();
    return outcome.update;
  }

  /// Queries DownloadManager for one download id. Never throws; returns
  /// `{'status': 'unknown'}` when the channel is unreachable.
  static Future<Map<String, dynamic>> _downloadStatus(int downloadId) async {
    try {
      final res = await _channel
          .invokeMethod<Map>('downloadStatus', {'downloadId': downloadId})
          .timeout(const Duration(seconds: 10));
      return Map<String, dynamic>.from(res ?? <String, dynamic>{});
    } catch (_) {
      return const {'status': 'unknown'};
    }
  }

  /// Hands the APK to Android DownloadManager and records it for
  /// re-attach. Returns null when the enqueue fails (caller shows the
  /// failure message; the launch check stays silent).
  static Future<_PendingDownload?> _enqueueDownload(UpdateInfo update) async {
    try {
      final file = await _expectedApkFile(update.versionCode);
      final downloadId = await _channel
          .invokeMethod<int>('downloadApk', {
            'url': update.url,
            'fileName': _apkFileName(update.versionCode),
          })
          .timeout(const Duration(seconds: 15));
      if (downloadId == null) return null;
      final dl = _PendingDownload(
        downloadId: downloadId,
        update: update,
        apkPath: file.path,
      );
      await _saveDownload(dl);
      return dl;
    } catch (_) {
      return null;
    }
  }

  /// Resolves the APK file path from a DownloadManager local URI,
  /// falling back to the path recorded at enqueue time.
  static String? _resolveApkPath(String? localUri, String fallbackPath) {
    if (localUri != null && localUri.startsWith('file://')) {
      try {
        return Uri.parse(localUri).toFilePath();
      } catch (_) {
        // Fall through to the recorded path.
      }
    }
    if (fallbackPath.isNotEmpty) return fallbackPath;
    return null;
  }

  /// Polls DownloadManager for completion (up to ~10 minutes), driving
  /// the global [launchProgress] banner. On success the install prompt
  /// fires via [navigatorKey] (works even if the user navigated away).
  /// Fire-and-forget: the system download itself survives app
  /// background/kill regardless of this loop.
  static Future<void> _trackDownload(_PendingDownload dl) async {
    if (_trackedDownloadId == dl.downloadId) return;
    _trackedDownloadId = dl.downloadId;
    try {
      for (var i = 0; i < 300; i++) {
        await Future.delayed(const Duration(seconds: 2));
        final st = await _downloadStatus(dl.downloadId);
        final s = st['status'] as String?;
        final downloaded = (st['bytesDownloaded'] as num?)?.toInt() ?? 0;
        final total = (st['bytesTotal'] as num?)?.toInt() ?? -1;
        launchProgress.value =
            UpdateDownloadProgress(received: downloaded, total: total);
        if (s == 'success') {
          _trackedDownloadId = null;
          launchProgress.value = null;
          await _clearDownload();
          final path = _resolveApkPath(
            st['localUri'] as String?,
            dl.apkPath,
          );
          if (path == null) return;
          // Re-check dismissal: the user may have dismissed via a
          // manual check while this download was running.
          if (await _dismissedCode() == dl.update.versionCode) return;
          _showInstallPrompt(dl.update, File(path));
          return;
        }
        if (s == 'failed' || s == 'not_found') {
          _trackedDownloadId = null;
          launchProgress.value = null;
          await _clearDownload();
          _snackbar(
            'اپ ڈیٹ ڈاؤن لوڈ نہیں ہو سکا۔ انٹرنیٹ چیک کر کے دوبارہ کوشش کریں۔',
          );
          return;
        }
        // running / pending / paused / unknown -> keep polling; the
        // banner shows live progress and the system notification too.
      }
      // Poll window exhausted (very slow network): stop the banner but
      // leave the system download running — its notification keeps the
      // user informed, and the next launch re-attaches automatically.
      _trackedDownloadId = null;
      launchProgress.value = null;
    } catch (_) {
      _trackedDownloadId = null;
      launchProgress.value = null;
    }
  }

  static void _snackbar(String message) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Launch check: silent unless a newer, NOT-dismissed version exists.
  ///
  /// 1. Re-attaches to a DownloadManager download started in an earlier
  ///    session (or fires the install prompt if it already finished).
  /// 2. If the version's APK is already on disk, the install prompt is
  ///    shown directly instead of re-downloading.
  /// 3. Otherwise the APK downloads in the background via
  ///    DownloadManager (system notification + in-flow banner show real
  ///    progress) and the install prompt is shown ONCE on completion.
  /// A failed background download stays silent — no nag, no error popup.
  static Future<void> checkOnLaunch(BuildContext context) async {
    final saved = await _loadDownload();
    if (saved != null) {
      final st = await _downloadStatus(saved.downloadId);
      final s = st['status'] as String?;
      if (s == 'running' || s == 'pending' || s == 'paused') {
        launchProgress.value =
            const UpdateDownloadProgress(received: 0, total: -1);
        unawaited(_trackDownload(saved));
        return;
      }
      if (s == 'success') {
        await _clearDownload();
        final path = _resolveApkPath(
          st['localUri'] as String?,
          saved.apkPath,
        );
        if (path != null &&
            await _dismissedCode() != saved.update.versionCode) {
          _showInstallPrompt(saved.update, File(path));
        }
        return;
      }
      // failed / not_found / unknown -> drop the stale record and run
      // the normal check below (it will re-download if still newer).
      await _clearDownload();
    }

    final update = await fetchUpdate();
    if (update == null) return;
    if (await _dismissedCode() == update.versionCode) return;

    File? existing;
    try {
      final file = await _expectedApkFile(update.versionCode);
      if (await file.exists() && await file.length() > 0) existing = file;
    } catch (_) {
      existing = null;
    }
    if (existing == null) {
      // Backward compat: the pre-v1.0.7 HttpClient updater wrote to the
      // temp dir — reuse that file instead of re-downloading.
      try {
        final tmp = await getTemporaryDirectory();
        final legacy = File('${tmp.path}/${_apkFileName(update.versionCode)}');
        if (await legacy.exists() && await legacy.length() > 0) {
          existing = legacy;
        }
      } catch (_) {
        // Ignore; fall through to a fresh download.
      }
    }
    if (existing != null) {
      _showInstallPrompt(update, existing);
      return;
    }

    launchProgress.value =
        const UpdateDownloadProgress(received: 0, total: -1);
    final dl = await _enqueueDownload(update);
    if (dl == null) {
      launchProgress.value = null;
      return;
    }
    unawaited(_trackDownload(dl));
  }

  /// Manual check: shows a specific message for each outcome —
  /// up-to-date vs no internet vs update file not found (Jaani 31 Oct
  /// 2026: these must NOT share one message). Shows the update dialog
  /// regardless of dismissal, as before.
  static Future<void> checkManually(BuildContext context) async {
    final outcome = await checkForUpdate();
    if (!context.mounted) return;
    switch (outcome.status) {
      case UpdateCheckResult.available:
        if (outcome.update != null) {
          showUpdateDialog(context, outcome.update!);
        }
        break;
      case UpdateCheckResult.upToDate:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('آپ کا ایپ اپ ٹو ڈیٹ ہے۔'),
          ),
        );
        break;
      case UpdateCheckResult.noInternet:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'انٹرنیٹ کنکشن نہیں ہے — چیک کرنے کے لیے انٹرنیٹ آن کریں۔',
            ),
          ),
        );
        break;
      case UpdateCheckResult.manifestNotFound:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('اپ ڈیٹ فائل نہیں ملی — بعد میں کوشش کریں۔'),
          ),
        );
        break;
    }
  }

  /// Non-blocking update dialog (Jaani 2 Nov 2026: tapping "اپ ڈیٹ"
  /// must NOT lock the app behind a modal). The download runs in the
  /// background; the install prompt appears when the APK is ready.
  static void showUpdateDialog(BuildContext context, UpdateInfo update) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        title: Text('نیا ورژن: ${update.versionName}'),
        content: Text(
          [
            if (update.notes.isNotEmpty) update.notes,
            'انسٹال کرنے کے لیے آپ کو خود Install دبانا ہوگا — '
                'ایپ خود بخود انسٹال نہیں ہو سکتی۔',
          ].join('\n\n'),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _recordDismissed(update.versionCode);
            },
            child: const Text('بعد میں'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              downloadAndInstall(context, update);
            },
            child: const Text('اپ ڈیٹ'),
          ),
        ],
      ),
    );
  }

  /// Install prompt shown once a version's APK is ready (already
  /// downloaded, or just background-downloaded). Shown through the
  /// global [navigatorKey] so it appears even if the user navigated
  /// away from the starting screen. "بعد میں" dismisses this
  /// versionCode for good; "انسٹال کریں" fires the system prompt.
  static void _showInstallPrompt(UpdateInfo update, File apkFile) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return; // Next launch will offer the prompt again.
    showDialog<void>(
      context: ctx,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        title: Text('نیا ورژن تیار ہے: ${update.versionName}'),
        content: Text(
          [
            if (update.notes.isNotEmpty) update.notes,
            'اپ ڈیٹ ڈاؤن لوڈ ہو چکا ہے۔ انسٹال کرنے کے لیے آپ کو خود '
                'Install دبانا ہوگا — ایپ خود بخود انسٹال نہیں ہو سکتی۔',
          ].join('\n\n'),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _recordDismissed(update.versionCode);
            },
            child: const Text('بعد میں'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _fireInstall(apkFile);
            },
            child: const Text('انسٹال کریں'),
          ),
        ],
      ),
    );
  }

  /// Fires the system install prompt for the downloaded APK through the
  /// native channel (FileProvider). Never attempts a silent install.
  static Future<void> _fireInstall(File apkFile) async {
    try {
      await _channel
          .invokeMethod<void>('installApk', {'path': apkFile.path})
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      _snackbar(
        'انسٹال پرومپٹ نہیں کھلا۔ Settings میں Doner کے لیے '
        '"Install unknown apps" allow کریں، پھر دوبارہ اپ ڈیٹ دبائیں۔',
      );
    }
  }

  /// Downloads the APK in the BACKGROUND via Android DownloadManager and
  /// fires the system install prompt when ready. Never attempts a
  /// silent install. Used by the manual check's "اپ ڈیٹ" button.
  ///
  /// Jaani's order (2 Nov 2026, reworked 3 Nov 2026): tapping "اپ ڈیٹ"
  /// must NOT lock the app behind a modal progress dialog. The download
  /// runs in the background (system notification + in-flow banner show
  /// live progress), the user keeps using the app, and the install
  /// prompt appears only when the APK is ready.
  static Future<void> downloadAndInstall(
    BuildContext context,
    UpdateInfo update,
  ) async {
    bool canInstall = true;
    try {
      canInstall =
          await _channel.invokeMethod<bool>('canInstallPackages').timeout(
                const Duration(seconds: 10),
              ) ??
              true;
    } catch (_) {
      // A channel hiccup must not block the update; the system install
      // UI surfaces the permission itself when needed.
      canInstall = true;
    }
    if (!canInstall) {
      try {
        await _channel.invokeMethod<void>('openInstallSettings');
      } catch (_) {
        // Best-effort.
      }
      _snackbar(
        'انسٹال کی اجازت دیں، پھر دوبارہ اپ ڈیٹ دبائیں۔',
      );
      return;
    }
    if (_trackedDownloadId != null) return; // already downloading
    launchProgress.value =
        const UpdateDownloadProgress(received: 0, total: -1);
    _snackbar(
      'اپ ڈیٹ بیک گراؤنڈ میں ڈاؤن لوڈ ہو رہی ہے — آپ ایپ استعمال کرتے رہیں۔',
    );
    final dl = await _enqueueDownload(update);
    if (dl == null) {
      launchProgress.value = null;
      _snackbar('اپ ڈیٹ ڈاؤن لوڈ شروع نہیں ہو سکا۔ دوبارہ کوشش کریں۔');
      return;
    }
    // Fire-and-forget: the system download survives app background/kill;
    // the banner updates live and the install prompt fires on completion.
    unawaited(_trackDownload(dl));
  }
}
