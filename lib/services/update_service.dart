/// Doner — in-app update checker for sideloaded builds.
///
/// Same mechanism as TJ Editor V1.2: the app fetches a small JSON
/// manifest from the website and compares its versionCode with the
/// installed one. When a newer version exists, the user is offered an
/// update; the new APK is downloaded and the system install prompt is
/// fired. A sideloaded app can NEVER install silently — Android always
/// requires the user's install tap, and the UI says so honestly.
///
/// Manifest format (served from the website, published separately):
///   {"versionCode": 2, "versionName": "1.1.0",
///    "url": "https://.../doner-donor.apk", "notes": "What's new"}
///
/// The updater is inert until that manifest exists: a missing or
/// unreachable manifest simply means "no update prompt, no error".
///
/// V1.3 nag fix (Jaani's complaint): the launch check no longer nags
/// every launch. A version the user dismissed ("بعد میں") is recorded
/// under 'dismissed_update_code' and never prompts again on launch;
/// a future newer version prompts again. On launch the APK downloads
/// in the BACKGROUND (no progress dialog) and the install prompt is
/// shown ONCE when it completes. If that version's APK is already
/// downloaded, the install prompt is shown directly instead of
/// re-downloading. The manual check still shows its dialog regardless
/// of dismissal, exactly as before.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
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

/// Live progress of the launch APK download, shown in the in-flow
/// banner (never a modal). Null when no launch download is running.
/// [total] is -1 when the server hides its size (then the banner shows
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

class UpdateService {
  /// Fixed manifest URL. The file itself is published later by the
  /// parent (with the stable APK download link); until then this
  /// checker stays silent.
  static const String manifestUrl =
      'https://nigraantv.xyz/apps/doner-version.json';

  /// VersionCode the user dismissed with "بعد میں" — never re-prompted
  /// on launch. A newer versionCode prompts again.
  static const String dismissedKey = 'dismissed_update_code';

  /// Live launch-download progress for the in-flow banner.
  static final ValueNotifier<UpdateDownloadProgress?> launchProgress =
      ValueNotifier<UpdateDownloadProgress?>(null);

  /// Per-version APK file name, so an already-downloaded APK for the
  /// same version is reused instead of re-downloaded.
  static String _apkFileName(int versionCode) =>
      'doner-update-$versionCode.apk';

  static Future<File> _apkFile(int versionCode) async {
    final dir = await getTemporaryDirectory();
    return File('${dir.path}/${_apkFileName(versionCode)}');
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

  /// Returns update info only when a NEWER version exists.
  /// Never throws: any failure (no network, missing manifest, bad
  /// JSON, bad version) simply means "no update prompt".
  static Future<UpdateInfo?> fetchUpdate() async {
    HttpClient? client;
    try {
      client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15);
      final request = await client.getUrl(Uri.parse(manifestUrl));
      final response =
          await request.close().timeout(const Duration(seconds: 20));
      if (response.statusCode != HttpStatus.ok) return null;
      final body = await response.transform(utf8.decoder).join();
      final data = jsonDecode(body);
      if (data is! Map<String, dynamic>) return null;
      final remoteCode = data['versionCode'];
      final url = data['url'];
      if (remoteCode is! int || url is! String || url.isEmpty) return null;
      final info = await PackageInfo.fromPlatform();
      final currentCode = int.tryParse(info.buildNumber) ?? 0;
      if (remoteCode <= currentCode) return null;
      return UpdateInfo(
        versionCode: remoteCode,
        versionName: (data['versionName'] as String?) ?? 'v$remoteCode',
        url: url,
        notes: (data['notes'] as String?) ?? '',
      );
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  /// Launch check: silent unless a newer, NOT-dismissed version exists.
  /// If its APK is already downloaded, the install prompt is shown
  /// directly; otherwise the APK downloads in the background and the
  /// install prompt is shown ONCE on completion. The background download
  /// is NOT silent any more (Jaani 27 Oct 2026 standing rule): its real
  /// byte progress shows in the in-flow [launchProgress] banner.
  /// A failed background download stays silent — no nag, no error popup.
  static Future<void> checkOnLaunch(BuildContext context) async {
    final update = await fetchUpdate();
    if (update == null || !context.mounted) return;
    if (await _dismissedCode() == update.versionCode) return;
    File? existing;
    try {
      final file = await _apkFile(update.versionCode);
      if (await file.exists() && await file.length() > 0) existing = file;
    } catch (_) {
      existing = null;
    }
    if (!context.mounted) return;
    if (existing != null) {
      _showInstallPrompt(context, update, existing);
      return;
    }
    // Background download: no modal dialog while it runs — progress
    // shows live in the in-flow banner (real % when size is known).
    launchProgress.value =
        const UpdateDownloadProgress(received: 0, total: -1);
    final file = await _downloadApk(update, onProgress: (r, t) {
      launchProgress.value = UpdateDownloadProgress(received: r, total: t);
    });
    launchProgress.value = null;
    if (file == null || !context.mounted) return;
    // Re-check dismissal: the user may have dismissed via a manual
    // check while this download was running.
    if (await _dismissedCode() == update.versionCode) return;
    if (!context.mounted) return;
    _showInstallPrompt(context, update, file);
  }

  /// Manual check: tells the user when nothing newer was found, and
  /// shows the update dialog regardless of dismissal, as before.
  static Future<void> checkManually(BuildContext context) async {
    final update = await fetchUpdate();
    if (!context.mounted) return;
    if (update == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'کوئی نیا ورژن نہیں ملا۔ انٹرنیٹ یا اپ ڈیٹ فائل '
            'نہ ملنے پر بھی یہی دکھتا ہے۔',
          ),
        ),
      );
      return;
    }
    showUpdateDialog(context, update);
  }

  static void showUpdateDialog(BuildContext context, UpdateInfo update) {
    showDialog<void>(
      context: context,
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
  /// downloaded, or just background-downloaded). "بعد میں" dismisses
  /// this versionCode for good; "انسٹال کریں" fires the system prompt.
  static void _showInstallPrompt(
    BuildContext context,
    UpdateInfo update,
    File apkFile,
  ) {
    showDialog<void>(
      context: context,
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
              _openInstaller(context, apkFile);
            },
            child: const Text('انسٹال کریں'),
          ),
        ],
      ),
    );
  }

  static Future<void> _openInstaller(BuildContext context, File apkFile) async {
    final result = await OpenFilex.open(apkFile.path);
    if (result.type != ResultType.done && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'انسٹال پرومپٹ نہیں کھلا۔ Settings میں Doner '
            'کے لیے "Install unknown apps" allow کریں، پھر دوبارہ '
            'اپ ڈیٹ دبائیں۔',
          ),
        ),
      );
    }
  }

  /// Downloads the APK, reporting real byte progress through
  /// [onProgress] (received, total; total is -1 when the server hides
  /// its size). Returns the file on success, null on any failure
  /// (caller stays silent).
  static Future<File?> _downloadApk(
    UpdateInfo update, {
    void Function(int received, int total)? onProgress,
  }) async {
    HttpClient? client;
    try {
      final file = await _apkFile(update.versionCode);
      client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
      final request = await client.getUrl(Uri.parse(update.url));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) return null;
      final total = response.contentLength;
      var received = 0;
      final sink = file.openWrite();
      await for (final chunk in response) {
        received += chunk.length;
        sink.add(chunk);
        onProgress?.call(received, total);
      }
      await sink.close();
      if (await file.length() == 0) return null;
      return file;
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  /// Downloads the APK (with a progress dialog) and fires the system
  /// install prompt. Never attempts a silent install. Used by the
  /// manual check's "اپ ڈیٹ" button. The dialog shows REAL progress:
  /// % done AND % remaining (+ MB done / MB total) while the size is
  /// known, live status text while it is not.
  static Future<void> downloadAndInstall(
    BuildContext context,
    UpdateInfo update,
  ) async {
    final progress = ValueNotifier<UpdateDownloadProgress?>(null);
    var dialogOpen = false;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ValueListenableBuilder<UpdateDownloadProgress?>(
        valueListenable: progress,
        builder: (_, value, _) {
          final known = value != null && value.known;
          return AlertDialog(
            title: const Text('اپ ڈیٹ ڈاؤن لوڈ ہو رہا ہے'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                    value: known ? value.fraction : null),
                const SizedBox(height: 12),
                Text(
                  known
                      ? '${value.percentDone}٪ مکمل — '
                          '${value.percentLeft}٪ باقی\n${value.mbLine}'
                      : 'ڈاؤن لوڈ ہو رہا ہے…',
                ),
              ],
            ),
          );
        },
      ),
    );
    dialogOpen = true;
    try {
      final file = await _apkFile(update.versionCode);
      if (await file.exists()) await file.delete();
      final downloaded = await _downloadApk(update, onProgress: (r, t) {
        progress.value = UpdateDownloadProgress(received: r, total: t);
      });
      if (!context.mounted) return;
      Navigator.pop(context);
      dialogOpen = false;
      if (downloaded == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'اپ ڈیٹ ڈاؤن لوڈ نہیں ہو سکا۔ انٹرنیٹ چیک کر کے '
              'دوبارہ کوشش کریں۔',
            ),
          ),
        );
        return;
      }
      await _openInstaller(context, downloaded);
    } catch (_) {
      if (context.mounted) {
        if (dialogOpen) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'اپ ڈیٹ ڈاؤن لوڈ نہیں ہو سکا۔ انٹرنیٹ چیک کر کے '
              'دوبارہ کوشش کریں۔',
            ),
          ),
        );
      }
    } finally {
      progress.dispose();
    }
  }
}

