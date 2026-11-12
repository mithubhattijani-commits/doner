// DONER 1.0.0 — fork of the Aman Blood Donor app 1.3.4 source, plus the
// social home feed (SocialFeedTab below). App label "Doner", package
// com.doner.app. The society itself is unchanged: same directory,
// same society facts, same public central contact number.
// AMAN BLOOD DONOR SOCIETY OF PAKISTAN — Android app (V1.2).
// Mirrors the society website (aman-blood/dist/index.html): same directory
// structure, same society facts, same public central contact number.
// V1.1 adds the in-app updater (same mechanism as TJ Editor V1.2):
// silent launch check of nigraantv.xyz/apps/doner-version.json
// plus a manual check button; the updater stays silent until the
// manifest + stable APK link are published by the parent.
// V1.2 adds AdMob ads (Jaani 26 Oct 2026, all formats):
// interstitial on every directory list-item tap, every donor-card
// WhatsApp tap, and every Call Now tap (uncapped); banner at the
// bottom of the home + directory screens; native cards inside the
// directory lists; app-open once per cold start. Rewarded is
// intentionally unwired (no unlockable feature in Doner).
// The original action always runs after an interstitial closes,
// or immediately if no ad is loaded.
// Honest limitation: the website's live donor records live in its
// Cloudflare KV store and are NOT bundled here, so the directory shows its
// full structure with honest empty states plus a local registration flow —
// no donor is ever invented.
// V1.3 adds the live society API (services/api_service.dart): the
// directory shows LIVE public donors (name + group + address only,
// never phones), registration also posts to the server, the home tab
// shows a newest-first feed with member-code photo posts, and an
// admin PIN screen shows the phone list (admin endpoint only, PIN
// session-only). Camera support needs a full release (native plugin),
// so 1.3.0+7 is NOT a Shorebird patch. The update nag is fixed:
// a dismissed version never re-prompts on launch, and the launch
// download now runs in the background with a single install prompt.
// V1.2.2 adds server-driven remote config (services/config_service.dart):
// home contacts, announcement banner, all InfoTab texts and the
// donorCard/compatibility/directory feature flags come from
// nigraantv.xyz/apps/doner-config.json, cached locally, fail-soft.
// The manifest updater above stays as the full-release path.
// V1.3.x adds progress visibility (Jaani 27 Oct 2026 standing rule):
// every user-visible process shows live progress — real % for the APK
// download and photo uploads, live Urdu status text for server waits.
// No silent screens, no fake timer percentages.
// V1.0.5 adds unified Remote Config v1
// (services/remote_config_service.dart): server-driven display name,
// logo, announcement bar, sponsored ads and a force-update kill-switch,
// all from nigraantv.xyz/apps/config/doner.json — changeable without an
// app update. The older config_service.dart (doner-config.json) stays
// untouched.
// Daily upgrade 3 Nov 2026: (1) "report wrong donor info" on each live
// directory row — opens the society WhatsApp with a prefilled
// name+group+area message (public data only); (2) donation prep tips
// card (before/after) in the Info tab. No new dependencies, no API
// changes, no ad changes.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data.dart';
import 'services/ad_service.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/config_service.dart';
import 'services/remote_config_service.dart';
import 'services/unity_ads_service.dart';
import 'services/update_service.dart';
import 'incharge_donor_page.dart';
import 'office_bearers_page.dart';
import 'services/app_language.dart';
import 'package:flutter/services.dart';

// ---- Society's public contact (published on the website itself) ----
const String centralDisplay = '0300 4927940';
const String centralTel = '+923004927940';
const String centralWa = '923004927940';
const String spokesmanDisplay = '0309 0808180';
const String spokesmanTel = '+923090808180';
const String spokesmanWa = '923090808180';
String get societyName => remoteConfigService.config.societyNameUr.trim().isNotEmpty ? remoteConfigService.config.societyNameUr : 'امن بلڈ ڈونر سوسائٹی آف پاکستان';
String get societyNameEn => remoteConfigService.config.societyNameEn.trim().isNotEmpty ? remoteConfigService.config.societyNameEn : 'AMAN BLOOD DONOR SOCIETY OF PAKISTAN';

Future<void> callNumber(String tel) async {
  final uri = Uri(scheme: 'tel', path: tel);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri);
  }
}

Future<void> callCentral() => callNumber(centralTel);

Future<void> whatsappNumber(String wa, [String? message]) async {
  final text = message ??
      'السلام علیکم! مجھے خون کے حوالے سے مدد چاہیے۔';
  final uri = Uri.parse(
      'https://wa.me/$wa?text=${Uri.encodeComponent(text)}');
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

Future<void> whatsappCentral([String? message]) =>
    whatsappNumber(centralWa, message);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AdService.init();
  // Unity Ads (revenue): best-effort, never blocks startup.
  // Rewarded = voluntary "support the society" in the Info tab;
  // Interstitial = frequency-capped on non-critical tab switches.
  unawaited(UnityAdsService.init());
  await ConfigService.loadFromCache();
  // Unified Remote Config v1: returns fast (cache load only); the
  // network refresh runs in the background. Never blocks startup.
  await remoteConfigService.init();
  // Featured Donor boost state (7-day reward) — fast local read.
  await FeaturedBoost.refresh();
  await AppLanguage.load();
  runApp(const DonerApp());
  // Launch fetch: refreshes content in the background. On any failure
  // the cached/default config stays in place (fail-soft, silent).
  ConfigService.refresh();
}

class DonerApp extends StatelessWidget {
  const DonerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // Updater's global key (Jaani, 3 Nov 2026): the install prompt
      // must appear even if the user navigated away mid-download.
      navigatorKey: UpdateService.navigatorKey,
      title: 'Doner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFC8102E),
          primary: const Color(0xFFC8102E),
        ),
        useMaterial3: true,
        fontFamily: null,
      ),
      home: ValueListenableBuilder<String>(
        valueListenable: AppLanguage.notifier,
        builder: (BuildContext context, String lang, _) { return Directionality(textDirection: lang == 'ur' ? TextDirection.rtl : TextDirection.ltr, child: const HomeShell()); },
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;

  /// Set the first time the force-update dialog shows: it appears at
  /// most once per app launch.
  bool _forceUpdateShown = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    AdService.showAppOpenOnce();
    WidgetsBinding.instance.addObserver(this);
    AppLanguage.notifier.addListener(_onLanguageChanged);
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) => _refreshWebsiteData());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) UpdateService.checkOnLaunch(context);
    });
    // Remote-config force-update kill-switch: check once after the first
    // frame, and again whenever a fresh config lands in the background.
    remoteConfigService.notifier.addListener(_maybeShowForceUpdate);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeShowForceUpdate();
    });
  }

  @override
  void dispose() {
    remoteConfigService.notifier.removeListener(_maybeShowForceUpdate);
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    AppLanguage.notifier.removeListener(_onLanguageChanged);
    super.dispose();
  }

  /// Non-dismissible "update required" dialog when the server says this
  /// build is below the minimum. The Update button triggers the existing
  /// in-app update flow (UpdateService.checkManually). Fail-soft: any
  /// error just skips the dialog — the app keeps working.
  Future<void> _maybeShowForceUpdate() async {
    if (_forceUpdateShown || !mounted) return;
    final RemoteConfig cfg = remoteConfigService.config;
    if (!cfg.forceUpdate.enabled || cfg.forceUpdate.minVersionCode <= 0) {
      return;
    }
    _forceUpdateShown = true;
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      final int installed = int.tryParse(info.buildNumber) ?? 0;
      if (installed >= cfg.forceUpdate.minVersionCode) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          return PopScope(
            canPop: false,
            child: AlertDialog(
              title: const Text('اپ ڈیٹ ضروری ہے'),
              content: const Text(
                'اس ایپ کا نیا ورژن دستیاب ہے۔ جاری رکھنے کے لیے براہ کرم ابھی اپ ڈیٹ کریں۔',
              ),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    UpdateService.checkManually(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC8102E),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('اپ ڈیٹ کریں'),
                ),
              ],
            ),
          );
        },
      );
    } catch (_) {
      // Fail-soft: never crash on a version/config hiccup.
    }
  }
  /// Instant refresh (website control): re-fetch both remote configs every
  /// 60 seconds and whenever the app comes back to the foreground, so the
  /// website admin-panel changes reach the app within a minute. Both
  /// refreshes are fail-soft - a network failure just keeps the last config.
  void _refreshWebsiteData() {
        remoteConfigService.refresh();
    ConfigService.refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
      if (state == AppLifecycleState.resumed) _refreshWebsiteData();
  }

  void _onLanguageChanged() {
      if (mounted) setState(() {});
  }

  // Tabs are built dynamically in build() so features.directory=false
  // hides the Directory tab instead of leaving a dead section.

  /// Bottom-nav tab tap with a frequency-capped Unity interstitial.
  /// Directory (donor search) and Register (donor registration) are
  /// critical flows — never interrupted by an ad. Navigation always
  /// completes, immediately when no ad qualifies.
  void _onTabTap(int i, List<Widget> tabs) {
    final target = i < tabs.length ? tabs[i] : null;
    final critical =
        target is DirectoryTab || target is RegisterTab;
    UnityAdsService.maybeShowInterstitial(
      targetIsCritical: critical,
      onDone: () {
        if (mounted) setState(() => _tab = i);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RemoteConfig>(
      valueListenable: remoteConfigService.notifier,
      builder: (BuildContext context, RemoteConfig remote, _) {
        return ValueListenableBuilder<DonerConfig>(
          valueListenable: ConfigService.notifier,
          builder: (context, config, _) {
            final tabs = <Widget>[const HomeTab()];
        final items = <BottomNavigationBarItem>[
          const BottomNavigationBarItem(icon: Icon(Icons.home), label: 'ہوم'),
        ];
        tabs.add(const SocialFeedTab());
        items.add(const BottomNavigationBarItem(
            icon: Icon(Icons.dynamic_feed), label: 'سوشل فیڈ'));
        if (config.directory) {
          tabs.add(const DirectoryTab());
          items.add(const BottomNavigationBarItem(
              icon: Icon(Icons.search), label: 'ڈائریکٹری'));
        }
        tabs.add(const RegisterTab());
        items.add(const BottomNavigationBarItem(
            icon: Icon(Icons.person_add), label: 'ڈونر بنیں'));
        tabs.add(const InfoTab());
        items.add(const BottomNavigationBarItem(
            icon: Icon(Icons.info), label: 'معلومات'));
        final index = _tab < tabs.length ? _tab : 0;
        final showBanner =
            tabs[index] is HomeTab || tabs[index] is DirectoryTab;
        return Scaffold(
      appBar: AppBar(
        title: Text(
            remote.displayName.isNotEmpty ? remote.displayName : 'Doner'),
        backgroundColor: const Color(0xFFC8102E),
        foregroundColor: Colors.white,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.admin_panel_settings),
            tooltip: 'ایڈمن',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.system_update),
            tooltip: 'اپ ڈیٹ چیک کریں',
            onPressed: () => UpdateService.checkManually(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // Announcement banner: in layout flow above the tabs, never
          // an overlay, so it can never cover an action button. Shown
          // only when enabled AND text is non-empty (see showAnnouncement).
          if (config.showAnnouncement)
            announcementBanner(config.announcementText),
          const UpdateProgressBanner(),
          Expanded(child: tabs[index]),
          if (showBanner) const UnityBannerAdWidget(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: index,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFFC8102E),
        onTap: (i) => _onTabTap(i, tabs),
        items: items,
          ),
        );
          },
        );
      },
    );
  }
}

Widget sectionTitle(String text) {
  return Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w900,
        color: Color(0xFF8F0B21),
      ),
    ),
  );
}

Widget contactRow({String tel = centralTel, String wa = centralWa}) {
  return Row(
    children: [
      Expanded(
        child: ElevatedButton.icon(
          onPressed: () => AdService.runWithAd(() => callNumber(tel)),
          icon: const Icon(Icons.phone),
          label: const Text('کال کریں'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFC8102E),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: ElevatedButton.icon(
          onPressed: () => whatsappNumber(wa),
          icon: const Icon(Icons.chat),
          label: const Text('WhatsApp کریں'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF25D366),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    ],
  );
}

/// Server announcement banner. A plain in-flow strip (never a Stack
/// overlay) so it can never cover the Call/WhatsApp buttons below it.
Widget announcementBanner(String text) {
  return Container(
    width: double.infinity,
    color: const Color(0xFFFFF0F0),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Text(
      '📢 $text',
      textAlign: TextAlign.center,
      style: const TextStyle(
          fontWeight: FontWeight.w800, color: Color(0xFF8F0B21)),
    ),
  );
}

/// Unified Remote Config v1 banner slot (home screen top): server-driven
/// announcement bar + sponsored ad card. Both fail-soft to nothing.
Widget remoteHomeBanner() {
  return ValueListenableBuilder<RemoteConfig>(
    valueListenable: remoteConfigService.notifier,
    builder: (BuildContext context, RemoteConfig cfg, _) {
      final List<Widget> items = <Widget>[];
      if (cfg.announcement.show) {
        items.add(remoteAnnouncementBar(cfg.announcement.text));
      }
      if (cfg.sponsoredAd.show) {
        items.add(remoteSponsoredAdCard(cfg.sponsoredAd));
      }
      if (items.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: items,
      );
    },
  );
}

/// Server announcement bar: a slim in-flow strip (never a Stack overlay)
/// so it can never cover an action button. Shown only when enabled AND
/// the text is non-empty.
Widget remoteAnnouncementBar(String text) {
  return Container(
    width: double.infinity,
    color: const Color(0xFF1B5E20),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    margin: const EdgeInsets.only(bottom: 12),
    child: Text(
      '📢 $text',
      textAlign: TextAlign.center,
      style:
          const TextStyle(fontWeight: FontWeight.w800, color: Colors.white),
    ),
  );
}

/// Opens the sponsored ad's action URL in the external browser.
/// Never auto-opens; a bad URL just does nothing.
Future<void> _openSponsoredAd(String url) async {
  final Uri? uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Sponsored ad card: clearly labeled as an ad. The image is optional —
/// the card shows the title even when the image fails to load. Tap opens
/// the action URL in the external browser. Never blocks the app.
Widget remoteSponsoredAdCard(SponsoredAdConfig ad) {
  return Card(
    margin: const EdgeInsets.only(bottom: 12),
    color: const Color(0xFFFFF8E1),
    child: InkWell(
      onTap: () => _openSponsoredAd(ad.actionUrl),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '📣 اسپانسرڈ اشتہار',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.black54),
            ),
            const SizedBox(height: 6),
            if (ad.imageUrl.trim().isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  ad.imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (BuildContext context, Object error,
                      StackTrace? stackTrace) {
                    return const SizedBox.shrink();
                  },
                ),
              ),
            if (ad.imageUrl.trim().isNotEmpty) const SizedBox(height: 8),
            Text(
              ad.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Server logo when the config sets logo_url (with a fail-soft fallback
/// to the bundled asset on any load error); bundled logo otherwise.
Widget remoteLogo({double size = 110}) {
  return ValueListenableBuilder<RemoteConfig>(
    valueListenable: remoteConfigService.notifier,
    builder: (BuildContext context, RemoteConfig cfg, _) {
      if (cfg.logoUrl.trim().isEmpty) {
        return Image.asset('assets/logo.jpg',
            width: size, height: size, fit: BoxFit.cover);
      }
      return Image.network(
        cfg.logoUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder:
            (BuildContext context, Object error, StackTrace? stackTrace) {
          return Image.asset('assets/logo.jpg',
              width: size, height: size, fit: BoxFit.cover);
        },
      );
    },
  );
}

/// Live progress banner for the launch APK download (Jaani 27 Oct 2026
/// standing rule: no silent processes). In layout flow above the tabs,
/// never an overlay, so it can never cover an action button. Shows REAL
/// % (bytes/total) when the server reports a size, otherwise live
/// status text. Cleared automatically when the download ends.
class UpdateProgressBanner extends StatelessWidget {
  const UpdateProgressBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UpdateDownloadProgress?>(
      valueListenable: UpdateService.launchProgress,
      builder: (context, progress, _) {
        if (progress == null) return const SizedBox.shrink();
        final known = progress.known;
        return Container(
          width: double.infinity,
          color: const Color(0xFFFFF0F0),
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                known
                    ? 'اپ ڈیٹ ڈاؤن لوڈ ہو رہا ہے… '
                        '${progress.percentDone}٪ مکمل — '
                        '${progress.percentLeft}٪ باقی'
                    : 'اپ ڈیٹ ڈاؤن لوڈ ہو رہا ہے…',
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF8F0B21)),
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                  value: known ? progress.fraction : null),
              if (known) ...[
                const SizedBox(height: 4),
                Text(progress.mbLine,
                    style: const TextStyle(
                        color: Colors.black54, fontSize: 12)),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Inserts a native ad card after every 6 list entries. The card is
/// clearly an ad (AdMob native template) — never a fake donor entry.
List<Widget> withNativeAds(List<Widget> items) {
  if (items.length < 6) return items;
  final out = <Widget>[];
  for (var i = 0; i < items.length; i++) {
    out.add(items[i]);
    if ((i + 1) % 6 == 0) out.add(const NativeAdWidget());
  }
  return out;
}

// ============================ HOME TAB ============================

// ===================== SOS URGENT BLOOD REQUEST =====================
/// Urgent blood request created ON THE DEVICE (offline-first, no server):
/// the user fills a short form, Doner builds a shareable Urdu request
/// card (WhatsApp / copy), and the request stays listed as ACTIVE for
/// exactly 72 hours, then auto-expires. Storage is SharedPreferences —
/// nothing leaves the phone except what the user shares themselves.
class SosRequest {
  /// How long a request stays ACTIVE after creation.
  static const Duration lifetime = Duration(hours: 72);

  final String id;
  final String group;
  final String hospital;
  final String city;
  final int units;
  final String name;
  final String phone;
  final int createdAtMs;

  const SosRequest({
    required this.id,
    required this.group,
    required this.hospital,
    required this.city,
    required this.units,
    required this.name,
    required this.phone,
    required this.createdAtMs,
  });

  bool get isActive =>
      DateTime.now().millisecondsSinceEpoch - createdAtMs <
      lifetime.inMilliseconds;

  Duration get remaining {
    final int left = createdAtMs +
        lifetime.inMilliseconds -
        DateTime.now().millisecondsSinceEpoch;
    return Duration(milliseconds: left < 0 ? 0 : left);
  }

  String get remainingText {
    if (!isActive) return 'ختم شدہ';
    final Duration r = remaining;
    final int h = r.inHours;
    final int m = r.inMinutes % 60;
    return h > 0 ? '$h گھنٹے $m منٹ باقی' : '$m منٹ باقی';
  }

  /// A fresh copy of this request with a new 72-hour window.
  SosRequest renewed() => SosRequest(
        id: id,
        group: group,
        hospital: hospital,
        city: city,
        units: units,
        name: name,
        phone: phone,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      );

  /// Shareable Urdu request card — the user sends this themselves.
  String get shareText =>
      '🚨 *فوری خون کی ضرورت ہے* 🚨\n'
      '🩸 بلڈ گروپ: $group\n'
      '🏥 اسپتال: $hospital\n'
      '📍 شہر: $city\n'
      '🧧 یونٹس: $units\n'
      '👤 رابطہ: $name\n'
      '📞 $phone\n'
      '⏰ یہ درخواست 72 گھنٹے تک فعال رہتی ہے۔\n'
      '📲 ڈونر ایپ کے ذریعے بھیجی گئی — Aman Blood Donor Society of Pakistan';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'group': group,
        'hospital': hospital,
        'city': city,
        'units': units,
        'name': name,
        'phone': phone,
        'createdAtMs': createdAtMs,
      };

  factory SosRequest.fromJson(Map<String, dynamic> j) => SosRequest(
        id: (j['id'] ?? '') as String,
        group: (j['group'] ?? '') as String,
        hospital: (j['hospital'] ?? '') as String,
        city: (j['city'] ?? '') as String,
        units: (j['units'] ?? 1) as int,
        name: (j['name'] ?? '') as String,
        phone: (j['phone'] ?? '') as String,
        createdAtMs: (j['createdAtMs'] ?? 0) as int,
      );
}

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  String? _patientGroup;
  List<FeedPost> _feed = [];
  bool _feedLoading = false;
  String? _feedError;

  /// SOS urgent requests, stored on-device in SharedPreferences.
  List<SosRequest> _sos = [];
  bool _sosLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadFeed();
    _loadSos();
  }

  Future<void> _loadSos() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String> raw =
        prefs.getStringList('abd_sos_requests') ?? const <String>[];
    final List<SosRequest> parsed = <SosRequest>[];
    for (final String s in raw) {
      try {
        parsed.add(SosRequest.fromJson(jsonDecode(s) as Map<String, dynamic>));
      } catch (_) {
        // Ignore corrupt entries; keep the rest.
      }
    }
    if (!mounted) return;
    setState(() {
      _sos = parsed;
      _sosLoaded = true;
    });
  }

  Future<void> _saveSos() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('abd_sos_requests',
        _sos.map((SosRequest r) => jsonEncode(r.toJson())).toList());
  }

  Future<void> _openSosSheet() async {
    // Prefill contact details from the most recent request: in an
    // emergency every second counts, so the hospital/city/contact
    // fields carry over and the user only changes what is different.
    final List<SosRequest> sorted = List<SosRequest>.from(_sos)
      ..sort((SosRequest a, SosRequest b) =>
          b.createdAtMs.compareTo(a.createdAtMs));
    final SosRequest? created = await showModalBottomSheet<SosRequest>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          SosRequestSheet(prefill: sorted.isEmpty ? null : sorted.first),
    );
    if (created != null) {
      setState(() => _sos = <SosRequest>[..._sos, created]);
      await _saveSos();
    }
  }

  Future<void> _shareSos(SosRequest r) async {
    final Uri uri = Uri.parse(
        'https://wa.me/?text=${Uri.encodeComponent(r.shareText)}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _copySos(SosRequest r) async {
    await Clipboard.setData(ClipboardData(text: r.shareText));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('درخواست کارڈ کاپی ہو گیا۔')),
    );
  }

  Future<void> _renewSos(SosRequest r) async {
    setState(() {
      _sos = _sos
          .map((SosRequest x) => x.id == r.id ? x.renewed() : x)
          .toList();
    });
    await _saveSos();
  }

  Future<void> _deleteSos(SosRequest r) async {
    setState(() => _sos = _sos.where((SosRequest x) => x.id != r.id).toList());
    await _saveSos();
  }

  /// The SOS section: one button to create, then the request cards.
  Widget _sosSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sectionTitle('🚨 فوری خون کی درخواست (SOS)'),
        const Text(
          'ایمرجنسی میں فوری خون چاہیے؟ مختصر فارم بھریں — تیار کارڈ WhatsApp پر شیئر کریں۔ ہر درخواست 72 گھنٹے تک فعال رہتی ہے، پھر خود بخود ختم ہو جاتی ہے۔',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _openSosSheet,
            icon: const Icon(Icons.emergency),
            label: const Text('نئی درخواست بنائیں'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC8102E),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _sosBody(),
      ],
    );
  }

  Widget _sosBody() {
    if (!_sosLoaded) return const SizedBox.shrink();
    if (_sos.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'ابھی کوئی درخواست نہیں ہے۔',
            style: TextStyle(color: Colors.black54),
          ),
        ),
      );
    }
    final List<SosRequest> sorted = List<SosRequest>.from(_sos)
      ..sort((SosRequest a, SosRequest b) =>
          b.createdAtMs.compareTo(a.createdAtMs));
    return Column(
      children: sorted.map(_sosCard).toList(),
    );
  }

  Widget _sosCard(SosRequest r) {
    final bool active = r.isActive;
    return Card(
      color: active ? const Color(0xFFFFF0F0) : null,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: active ? const Color(0xFFC8102E) : Colors.black45,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      r.group,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${r.hospital} — ${r.city}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Chip(
                  label: Text(
                    active ? 'فعال' : 'ختم شدہ',
                    style: const TextStyle(fontSize: 12),
                  ),
                  backgroundColor: active
                      ? const Color(0xFFE8F5E9)
                      : const Color(0xFFF0F0F0),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('🧧 ${r.units} یونٹس • 👤 ${r.name} • 📞 ${r.phone}'),
            const SizedBox(height: 2),
            Text(
              active
                  ? '⏳ ${r.remainingText}'
                  : '⏳ مدت ختم — دوبارہ فعال کر کے دوبارہ شیئر کریں۔',
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _shareSos(r),
                  icon: const Icon(Icons.chat, size: 18),
                  label: const Text('WhatsApp پر شیئر کریں'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _copySos(r),
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('کاپی کریں'),
                ),
                if (!active)
                  OutlinedButton.icon(
                    onPressed: () => _renewSos(r),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('دوبارہ فعال کریں'),
                  ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'حذف کریں',
                  onPressed: () => _deleteSos(r),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadFeed() async {
    if (_feedLoading) return;
    setState(() {
      _feedLoading = true;
      _feedError = null;
    });
    final result = await ApiService.fetchFeed();
    if (!mounted) return;
    setState(() {
      _feedLoading = false;
      if (result.ok) {
        _feed = result.data ?? [];
      } else {
        _feedError = result.error;
      }
    });
  }

  Future<void> _openPostSheet() async {
    if (!await AuthService.isLoggedIn()) {
      if (!mounted) return;
      final bool? ok = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const AuthScreen(),
      );
      if (ok != true || !mounted) return;
    }
    if (!mounted) return;
    final posted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const FeedPostSheet(),
    );
    if (posted == true && mounted) _loadFeed();
  }

  @override
  Widget build(BuildContext context) {
    final donors = _patientGroup == null
        ? null
        : canReceiveFrom[_patientGroup!]!;
    return ValueListenableBuilder<DonerConfig>(
      valueListenable: ConfigService.notifier,
      builder: (context, config, _) {
        return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Unified Remote Config v1: server-driven announcement bar and
        // sponsored ad card. Shown only when the server enables them;
        // fail-soft to nothing on any fetch failure.
        remoteHomeBanner(),
        Center(
          child: ClipOval(
            child: remoteLogo(),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          remoteConfigService.config.homeTaglineUr.trim().isNotEmpty ? remoteConfigService.config.homeTaglineUr : 'آپ کا ایک قطرہ خون — کسی کی پوری زندگی',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          remoteConfigService.config.homeTaglineEn.trim().isNotEmpty ? remoteConfigService.config.homeTaglineEn : '🩸 خون عطیہ کریں، زندگیاں بچائیں 🩸',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFFC8102E)),
        ),
        const SizedBox(height: 8),
        const Text(
          'اپنا صوبہ، ضلع اور علاقہ منتخب کریں اور اپنے قریب ترین بلڈ ڈونر تک پہنچیں — یا فوری ضرورت میں سوسائٹی کے مرکزی نمبر پر رابطہ کریں۔',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 16),
        Card(
          color: const Color(0xFFFFF0F0),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text(
                  '📞 سوسائٹی کا مرکزی رابطہ نمبر (24 گھنٹے)',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    config.chairman.phone,
                    style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF8F0B21)),
                  ),
                ),
                Text(
                  config.chairman.displayLine,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF8F0B21)),
                ),
                const SizedBox(height: 10),
                contactRow(tel: config.chairman.tel, wa: config.chairman.wa),
                const SizedBox(height: 14),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    config.spokesperson.phone,
                    style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF8F0B21)),
                  ),
                ),
                Text(
                  config.spokesperson.displayLine,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF8F0B21)),
                ),
                const SizedBox(height: 10),
                contactRow(tel: config.spokesperson.tel, wa: config.spokesperson.wa),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _sosSection(),
        if (config.compatibility) ...[
          sectionTitle('🩸 مریض کا بلڈ گروپ — کون عطیہ دے سکتا ہے؟'),
        const Text(
          'مریض کا گروپ منتخب کریں، دیکھیں کن گروپس کے ڈونر خون دے سکتے ہیں:',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: bloodGroups.map((g) {
            final selected = _patientGroup == g;
            return ChoiceChip(
              label: Directionality(
                textDirection: TextDirection.ltr,
                child: Text(g),
              ),
              selected: selected,
              selectedColor: const Color(0xFFC8102E),
              labelStyle: TextStyle(
                  color: selected ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w700),
              onSelected: (_) => setState(() => _patientGroup = g),
            );
          }).toList(),
        ),
        ],
        if (config.compatibility && donors != null) ...[
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'مریض ($_patientGroup) کو یہ گروپس خون دے سکتے ہیں: ${donors.join('، ')}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
        if (config.directory) ...[
          sectionTitle('ڈائریکٹری'),
          const Text(
            'پورے پاکستان کے صوبے اور اضلاع شامل ہیں۔ ڈائریکٹری ٹیب سے اپنا صوبہ، ضلع اور علاقہ منتخب کریں۔ ڈونر رجسٹریشن جاری ہے — اپنے علاقے کے ڈونرز کے لیے مرکزی نمبر پر رابطہ کریں یا خود ڈونر بنیں۔',
            style: TextStyle(color: Colors.black54),
          ),
        ],
        sectionTitle('تازہ اپ ڈیٹس'),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _openPostSheet,
                icon: const Icon(Icons.photo_camera),
                label: const Text('اپ ڈیٹ پوسٹ کریں'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC8102E),
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'اپ ڈیٹس دوبارہ لوڈ کریں',
              onPressed: _loadFeed,
            ),
          ],
        ),
        const SizedBox(height: 8),
        _feedBody(),
      ],
        );
      },
    );
  }
  Widget _feedBody() {
    if (_feedLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 10),
              Text('تازہ اپ ڈیٹس لوڈ ہو رہی ہیں…',
                  style: TextStyle(color: Colors.black54)),
            ],
          ),
        ),
      );
    }
    if (_feedError != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_feedError!),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _loadFeed,
                child: const Text('دوبارہ کوشش کریں'),
              ),
            ],
          ),
        ),
      );
    }
    if (_feed.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'ابھی کوئی اپ ڈیٹ نہیں ہے۔ نئی اپ ڈیٹس یہاں سب سے پہلے نظر آئیں گی۔',
            style: TextStyle(color: Colors.black54),
          ),
        ),
      );
    }
    return Column(
      children: _feed.map((post) {
        Widget? photoWidget;
        if (post.photo.isNotEmpty) {
          try {
            final raw = post.photo.contains(',')
                ? post.photo.split(',').last
                : post.photo;
            final bytes = base64Decode(raw);
            photoWidget = ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.memory(bytes,
                  width: double.infinity, fit: BoxFit.cover),
            );
          } catch (_) {
            photoWidget = null;
          }
        }
        final date = displayDate(post.ts);
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (photoWidget != null) ...[
                  photoWidget,
                  const SizedBox(height: 8),
                ],
                if (post.caption.isNotEmpty)
                  Text(post.caption,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('👤 ${post.name}'
                    '${post.area.isNotEmpty ? ' — ${post.area}' : ''}'),
                if (post.group.isNotEmpty)
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text('🩸 ${post.group}'),
                  ),
                if (post.patient.isNotEmpty)
                  Text('مریض: ${post.patient}'),
                if (post.place.isNotEmpty) Text('جگہ: ${post.place}'),
                if (date.isNotEmpty)
                  Text(date, style: const TextStyle(color: Colors.black54)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}


// ============================ SOS REQUEST SHEET ============================

/// Bottom-sheet composer for an urgent blood request. Returns the created
/// SosRequest (not yet saved — the caller stores it) or null on cancel.
class SosRequestSheet extends StatefulWidget {
  /// Optional previous request: its hospital/city/contact details are
  /// prefilled so a repeat emergency request takes seconds, not minutes.
  final SosRequest? prefill;

  const SosRequestSheet({super.key, this.prefill});

  @override
  State<SosRequestSheet> createState() => _SosRequestSheetState();
}

class _SosRequestSheetState extends State<SosRequestSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _hospital = TextEditingController();
  final TextEditingController _city = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  String _group = bloodGroups.first;
  int _units = 1;

  @override
  void initState() {
    super.initState();
    final SosRequest? p = widget.prefill;
    if (p != null) {
      _hospital.text = p.hospital;
      _city.text = p.city;
      _name.text = p.name;
      _phone.text = p.phone;
      if (bloodGroups.contains(p.group)) _group = p.group;
      _units = p.units;
    }
  }

  @override
  void dispose() {
    _hospital.dispose();
    _city.dispose();
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final int now = DateTime.now().millisecondsSinceEpoch;
    final SosRequest r = SosRequest(
      id: now.toString(),
      group: _group,
      hospital: _hospital.text.trim(),
      city: _city.text.trim(),
      units: _units,
      name: _name.text.trim(),
      phone: _phone.text.trim(),
      createdAtMs: now,
    );
    Navigator.pop(context, r);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '🚨 نئی فوری درخواست',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              const Text(
                'درخواست آپ کے فون میں محفوظ رہے گی اور 72 گھنٹے بعد خود ختم ہو جائے گی۔',
                style: TextStyle(color: Colors.black54),
              ),
              if (widget.prefill != null) ...[
                const SizedBox(height: 6),
                const Text(
                  '📝 پچھلی درخواست کی تفصیل پہلے سے بھری گئی ہے — ضرورت ہو تو بدلیں۔',
                  style: TextStyle(
                      color: Colors.black54, fontWeight: FontWeight.w700),
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _group,
                decoration: const InputDecoration(
                    labelText: 'بلڈ گروپ *', border: OutlineInputBorder()),
                items: bloodGroups
                    .map((String g) => DropdownMenuItem<String>(
                          value: g,
                          child: Directionality(
                            textDirection: TextDirection.ltr,
                            child: Text(g),
                          ),
                        ))
                    .toList(),
                onChanged: (String? v) {
                  if (v != null) setState(() => _group = v);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _hospital,
                decoration: const InputDecoration(
                    labelText: 'اسپتال *', border: OutlineInputBorder()),
                validator: (String? v) => (v == null || v.trim().isEmpty)
                    ? 'اسپتال کا نام ضروری ہے'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _city,
                decoration: const InputDecoration(
                    labelText: 'شہر *', border: OutlineInputBorder()),
                validator: (String? v) => (v == null || v.trim().isEmpty)
                    ? 'شہر ضروری ہے'
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _units,
                decoration: const InputDecoration(
                    labelText: 'یونٹس', border: OutlineInputBorder()),
                items: List<int>.generate(10, (int i) => i + 1)
                    .map((int n) => DropdownMenuItem<int>(
                          value: n,
                          child: Text('$n'),
                        ))
                    .toList(),
                onChanged: (int? v) {
                  if (v != null) setState(() => _units = v);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                    labelText: 'رابطہ کا نام *', border: OutlineInputBorder()),
                validator: (String? v) => (v == null || v.trim().isEmpty)
                    ? 'نام ضروری ہے'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                    labelText: 'فون نمبر * (مثلاً 03xx-xxxxxxx)',
                    border: OutlineInputBorder()),
                validator: (String? v) {
                  final String digits =
                      (v ?? '').replaceAll(RegExp(r'[^0-9]'), '');
                  if (digits.length < 10) return 'درست فون نمبر لکھیں';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.save),
                  label: const Text('درخواست محفوظ کریں'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC8102E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// ============================ SOCIAL HOME FEED ============================
//
// Doner's social home feed (NEW in Doner 1.0.0): society members post
// daily-work updates with a camera photo + text. Displayed newest
// first, each card shows photo + text + author name + time ONLY —
// NEVER a phone number (phones stay admin-only, as in the directory).
// Posting, liking and commenting are gated by the SAME member-code
// mechanism as the existing home feed: the code is entered per
// session, held only in widget state, and never stored. The feed
// starts EMPTY: no post, like or comment is ever seeded or faked.
// If the backend is unavailable, the tab shows an honest error card
// with a retry button — never a crash, never fake data.

/// Facebook-style post photo: full-bleed, edge to edge, no rounding.
/// (Jaani, 30 Oct 2026: post format = picture on top, details below, simple.)
Widget? socialPhotoWidget(String photo) {
  if (photo.isEmpty) return null;
  try {
    final raw = photo.contains(',') ? photo.split(',').last : photo;
    final bytes = base64Decode(raw);
    return Image.memory(bytes, width: double.infinity, fit: BoxFit.cover);
  } catch (_) {
    return null;
  }
}

class SocialFeedTab extends StatefulWidget {
  const SocialFeedTab({super.key});

  @override
  State<SocialFeedTab> createState() => _SocialFeedTabState();
}

class _SocialFeedTabState extends State<SocialFeedTab> {
  List<SocialPost> _posts = [];
  bool _loading = false;
  String? _error;
  String? _likingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await ApiService.fetchSocialPosts();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result.ok) {
        _posts = result.data ?? [];
      } else {
        _error = result.error;
      }
    });
  }

  /// Opens the login/signup sheet when the user is not logged in.
  /// Returns true when the user is logged in afterwards (either was
  /// already logged in, or just completed login/signup).
  Future<bool> _requireLogin() async {
    if (await AuthService.isLoggedIn()) return true;
    if (!mounted) return false;
    final bool? ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const AuthScreen(),
    );
    return ok == true;
  }

  Future<void> _toggleLike(SocialPost post) async {
    if (_likingId != null) return;
    if (!await _requireLogin()) return;
    if (!mounted) return;
    setState(() => _likingId = post.id);
    final result = await ApiService.toggleSocialLike(postId: post.id);
    if (!mounted) return;
    setState(() {
      _likingId = null;
      if (result.ok && result.data != null) {
        final (liked, count) = result.data!;
        _posts = _posts
            .map((p) => p.id == post.id
                ? p.copyWith(liked: liked, likeCount: count)
                : p)
            .toList();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.error ?? 'دوبارہ کوشش کریں')),
        );
      }
    });
  }

  Future<void> _openPostSheet() async {
    if (!await _requireLogin()) return;
    if (!mounted) return;
    final posted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const SocialPostSheet(),
    );
    if (posted == true && mounted) _load();
  }

  Future<void> _openComments(SocialPost post) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SocialCommentsSheet(post: post),
    );
    if (changed == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        sectionTitle('سوشل فیڈ'),
        const Text(
          'سوسائٹی کا روزانہ کا کام — ممبرز کی تصویری اپ ڈیٹس، نئی سے پرانی ترتیب میں۔ پوسٹ، لائک اور کمنٹ کے لیے لاگ اِن کریں۔',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _openPostSheet,
                icon: const Icon(Icons.photo_camera),
                label: const Text('پوسٹ کریں'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC8102E),
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'فیڈ دوبارہ لوڈ کریں',
              onPressed: _load,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 10),
                  Text('سوشل فیڈ لوڈ ہو رہی ہے…',
                      style: TextStyle(color: Colors.black54)),
                ],
              ),
            ),
          )
        else if (_error != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_error!),
                  const SizedBox(height: 8),
                  const Text(
                    'سوشل فیڈ دستیاب نہیں — بیک اینڈ ابھی سیٹ نہیں ہوا '
                    'یا انٹرنیٹ دستیاب نہیں۔',
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _load,
                    child: const Text('دوبارہ کوشش کریں'),
                  ),
                ],
              ),
            ),
          )
        else if (_posts.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'ابھی کوئی پوسٹ نہیں ہے۔ سوشل فیڈ خالی شروع ہوتی ہے — '
                'پہلی پوسٹ آپ کریں!',
                style: TextStyle(color: Colors.black54),
              ),
            ),
          )
        else
          ..._posts.map((post) {
            final Widget? photo = socialPhotoWidget(post.photo);
            final bool busy = _likingId == post.id;
            /* Facebook-simple post layout (Jaani, 30 Oct 2026):
               header (author + time) -> full-bleed picture -> details text
               -> like/comment. No designed overlays or badges. */
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          post.author,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                        if (post.ts.isNotEmpty)
                          Text(
                            displayDateTime(post.ts),
                            style: const TextStyle(
                                color: Colors.black54, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                  if (photo is Widget) photo,
                  if (post.text.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      child: Text(
                        post.text,
                        style: const TextStyle(fontSize: 15),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: <Widget>[
                        TextButton.icon(
                          onPressed: busy ? null : () => _toggleLike(post),
                          icon: Icon(
                            post.liked
                                ? Icons.favorite
                                : Icons.favorite_border,
                            color: post.liked
                                ? const Color(0xFFC8102E)
                                : null,
                          ),
                          label: Text(
                              '${post.likeCount} لائک${post.liked ? ' ✓' : ''}'),
                        ),
                        TextButton.icon(
                          onPressed: () => _openComments(post),
                          icon: const Icon(Icons.comment_outlined),
                          label: Text('${post.commentCount} کمنٹ'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}

/// Post-creation sheet: camera photo + text. Requires login (the
/// parent opens AuthScreen first); the author name comes from the
/// logged-in account — the server sets it, never the client.
/// Returns true when the post succeeded (parent refreshes the feed).
class SocialPostSheet extends StatefulWidget {
  const SocialPostSheet({super.key});

  @override
  State<SocialPostSheet> createState() => _SocialPostSheetState();
}

class _SocialPostSheetState extends State<SocialPostSheet> {
  final _formKey = GlobalKey<FormState>();
  final _text = TextEditingController();
  String _userName = '';
  String? _photoBase64;
  bool _busy = false;
  bool _picking = false;
  int? _uploadPct;
  String? _error;

  @override
  void initState() {
    super.initState();
    AuthService.currentUser().then((AuthUser? u) {
      if (!mounted) return;
      setState(() => _userName = u?.name ?? '');
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    setState(() {
      _picking = true;
      _error = null;
    });
    final result = await ApiService.pickPhoto(source);
    if (!mounted) return;
    setState(() {
      _picking = false;
      if (result.cancelled) {
        // User backed out of the picker: no error, no change.
      } else if (result.error != null) {
        _error = result.error;
      } else {
        _photoBase64 = result.base64;
        _error = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('📸 سوشل پوسٹ کریں',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pick(ImageSource.camera),
                        icon: const Icon(Icons.photo_camera),
                        label: const Text('کیمرہ'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pick(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library),
                        label: const Text('گیلری'),
                      ),
                    ),
                  ],
                ),
                if (_picking)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('تصویر تیار ہو رہی ہے…',
                        style: TextStyle(color: Colors.black54)),
                  ),
                if (_photoBase64 != null)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('✔ تصویر منتخب ہو گئی ہے۔',
                        style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.w700)),
                  ),
                const SizedBox(height: 12),
                Card(
                  color: const Color(0xFFFFF3E0),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.person,
                            color: Color(0xFFC8102E)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _userName.isEmpty
                                ? 'پوسٹ بطور: …'
                                : 'پوسٹ بطور: $_userName',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _text,
                  maxLines: 4,
                  decoration: const InputDecoration(
                      labelText: 'پوسٹ کی تحریر *',
                      border: OutlineInputBorder()),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'تحریر ضروری ہے'
                      : null,
                ),
                if (_error != null)
                  Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(_error!,
                        style: const TextStyle(
                            color: Colors.red, fontWeight: FontWeight.w700)),
                  ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            if (!_formKey.currentState!.validate()) return;
                            setState(() {
                              _busy = true;
                              _error = null;
                              _uploadPct = null;
                            });
                            final result =
                                await ApiService.createSocialPost(
                              text: _text.text.trim(),
                              photoBase64: _photoBase64,
                              onUploadProgress: (sent, total) {
                                if (!mounted) return;
                                setState(() => _uploadPct = total > 0
                                    ? (sent / total * 100).round()
                                    : null);
                              },
                            );
                            if (!mounted) return;
                            setState(() => _busy = false);
                            if (result.ok) {
                              if (!context.mounted) return;
                              Navigator.pop(context, true);
                            } else {
                              setState(() => _error = result.error);
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFC8102E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(_busy
                        ? (_photoBase64 != null && _uploadPct != null
                            ? 'اپ لوڈ ہو رہا ہے… $_uploadPct٪ مکمل — ${100 - _uploadPct!}٪ باقی'
                            : 'پوسٹ ہو رہا ہے…')
                        : 'پوسٹ کریں'),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Comments sheet for one social post: lists comments (author + time),
/// sends a text comment. Sending requires login — the sheet opens the
/// AuthScreen itself when the user is logged out. The author name comes
/// from the logged-in account (the server sets it). Returns true when
/// a comment was added (parent refreshes counts).
class SocialCommentsSheet extends StatefulWidget {
  const SocialCommentsSheet({
    super.key,
    required this.post,
  });

  final SocialPost post;

  @override
  State<SocialCommentsSheet> createState() => _SocialCommentsSheetState();
}

class _SocialCommentsSheetState extends State<SocialCommentsSheet> {
  final _text = TextEditingController();
  List<SocialComment> _comments = [];
  bool _loading = false;
  bool _busy = false;
  String? _error;
  String _userName = '';

  @override
  void initState() {
    super.initState();
    _load();
    AuthService.currentUser().then((AuthUser? u) {
      if (!mounted) return;
      setState(() => _userName = u?.name ?? '');
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result =
        await ApiService.fetchSocialComments(widget.post.id);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result.ok) {
        _comments = result.data ?? [];
      } else {
        _error = result.error;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('💬 کمنٹس — ${widget.post.author}',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_error!),
                      TextButton(
                        onPressed: _load,
                        child: const Text('دوبارہ کوشش کریں'),
                      ),
                    ],
                  ),
                ),
              )
            else if (_comments.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('ابھی کوئی کمنٹ نہیں ہے۔',
                      style: TextStyle(color: Colors.black54)),
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: _comments.map((c) {
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.text,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text('👤 ${c.author}'
                                '${c.ts.isNotEmpty ? ' — ${displayDateTime(c.ts)}' : ''}',
                                style: const TextStyle(
                                    color: Colors.black54, fontSize: 12)),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            const SizedBox(height: 12),
            if (_userName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('کمنٹ بطور: $_userName',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFC8102E))),
              ),
            TextField(
              controller: _text,
              maxLines: 3,
              decoration: const InputDecoration(
                  labelText: 'کمنٹ لکھیں *', border: OutlineInputBorder()),
            ),
            if (_error != null && !_loading)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!,
                    style: const TextStyle(
                        color: Colors.red, fontWeight: FontWeight.w700)),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _busy
                    ? null
                    : () async {
                        final text = _text.text.trim();
                        if (text.isEmpty) {
                          setState(() => _error = 'کمنٹ لکھیں');
                          return;
                        }
                        if (!await AuthService.isLoggedIn()) {
                          if (!context.mounted) return;
                          final bool? ok =
                              await showModalBottomSheet<bool>(
                            context: context,
                            isScrollControlled: true,
                            builder: (_) => const AuthScreen(),
                          );
                          if (ok != true || !mounted) return;
                          final AuthUser? u =
                              await AuthService.currentUser();
                          if (!mounted) return;
                          setState(() => _userName = u?.name ?? '');
                        }
                        setState(() {
                          _busy = true;
                          _error = null;
                        });
                        final result =
                            await ApiService.addSocialComment(
                          postId: widget.post.id,
                          text: text,
                        );
                        if (!mounted) return;
                        setState(() => _busy = false);
                        if (result.ok) {
                          _text.clear();
                          if (!context.mounted) return;
                          Navigator.pop(context, true);
                        } else {
                          setState(() => _error = result.error);
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC8102E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(_busy ? 'بھیجا جا رہا ہے…' : 'کمنٹ کریں'),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ============================ AUTH SCREEN ============================

/// Login / signup sheet (email + password). Replaces the old
/// MEMBER_CODE dialog system (Jaani, 31 Oct 2026). The session is
/// saved by AuthService (SharedPreferences, survives restarts); pops
/// `true` on success so the caller can continue the gated action
/// (post / like / comment).
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _loginForm = GlobalKey<FormState>();
  final _signupForm = GlobalKey<FormState>();
  final _loginEmail = TextEditingController();
  final _loginPassword = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  final _city = TextEditingController();
  String _group = bloodGroups.first;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _loginEmail.dispose();
    _loginPassword.dispose();
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _phone.dispose();
    _city.dispose();
    super.dispose();
  }

  String? _required(String? v, String msg) =>
      (v == null || v.trim().isEmpty) ? msg : null;

  String? _emailCheck(String? v) {
    if (v == null || v.trim().isEmpty) return 'ای میل ضروری ہے';
    if (!v.contains('@')) return 'درست ای میل لکھیں';
    return null;
  }

  Future<void> _doLogin() async {
    if (!_loginForm.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await AuthService.login(
      email: _loginEmail.text.trim(),
      password: _loginPassword.text,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.ok) {
      if (!context.mounted) return;
      Navigator.pop(context, true);
    } else {
      setState(() => _error = result.error);
    }
  }

  Future<void> _doSignup() async {
    if (!_signupForm.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await AuthService.register(
      name: _name.text.trim(),
      email: _email.text.trim(),
      password: _password.text,
      phone: _phone.text.trim(),
      group: _group,
      city: _city.text.trim(),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.ok) {
      if (!context.mounted) return;
      Navigator.pop(context, true);
    } else {
      setState(() => _error = result.error);
    }
  }

  Widget _submitButton(String label, Future<void> Function() onTap) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _busy ? null : () => onTap(),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFC8102E),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: Text(_busy ? 'براہ کرم انتظار کریں…' : label),
      ),
    );
  }

  Widget _errorLine() {
    if (_error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(_error!,
          style: const TextStyle(
              color: Colors.red, fontWeight: FontWeight.w700)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('👤 ممبر لاگ اِن',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              const Text(
                'پوسٹ، لائک اور کمنٹ کے لیے اپنا اکاؤنٹ استعمال کریں۔',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 12),
              TabBar(
                controller: _tabs,
                labelColor: const Color(0xFFC8102E),
                unselectedLabelColor: Colors.black54,
                indicatorColor: const Color(0xFFC8102E),
                tabs: const [
                  Tab(text: 'لاگ اِن'),
                  Tab(text: 'نیا اکاؤنٹ'),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 430,
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    // ---------- LOGIN ----------
                    Form(
                      key: _loginForm,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFormField(
                            controller: _loginEmail,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                                labelText: 'ای میل *',
                                border: OutlineInputBorder()),
                            validator: _emailCheck,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _loginPassword,
                            obscureText: true,
                            decoration: const InputDecoration(
                                labelText: 'پاس ورڈ *',
                                border: OutlineInputBorder()),
                            validator: (v) =>
                                _required(v, 'پاس ورڈ ضروری ہے'),
                          ),
                          _errorLine(),
                          const SizedBox(height: 16),
                          _submitButton('لاگ اِن', _doLogin),
                        ],
                      ),
                    ),
                    // ---------- SIGNUP ----------
                    Form(
                      key: _signupForm,
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            TextFormField(
                              controller: _name,
                              decoration: const InputDecoration(
                                  labelText: 'نام *',
                                  border: OutlineInputBorder()),
                              validator: (v) =>
                                  _required(v, 'نام ضروری ہے'),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _email,
                              keyboardType:
                                  TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                  labelText: 'ای میل *',
                                  border: OutlineInputBorder()),
                              validator: _emailCheck,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _password,
                              obscureText: true,
                              decoration: const InputDecoration(
                                  labelText:
                                      'پاس ورڈ * (کم از کم 6 حروف)',
                                  border: OutlineInputBorder()),
                              validator: (v) {
                                final req =
                                    _required(v, 'پاس ورڈ ضروری ہے');
                                if (req != null) return req;
                                if (v!.length < 6) {
                                  return 'پاس ورڈ کم از کم 6 حروف کا ہو';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _phone,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                  labelText: 'فون نمبر *',
                                  border: OutlineInputBorder()),
                              validator: (v) =>
                                  _required(v, 'فون نمبر ضروری ہے'),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              initialValue: _group,
                              decoration: const InputDecoration(
                                  labelText: 'بلڈ گروپ *',
                                  border: OutlineInputBorder()),
                              items: bloodGroups
                                  .map((String g) =>
                                      DropdownMenuItem(
                                        value: g,
                                        child: Directionality(
                                          textDirection:
                                              TextDirection.ltr,
                                          child: Text(g),
                                        ),
                                      ))
                                  .toList(),
                              onChanged: (String? v) =>
                                  setState(() => _group = v!),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _city,
                              decoration: const InputDecoration(
                                  labelText: 'شہر *',
                                  border: OutlineInputBorder()),
                              validator: (v) =>
                                  _required(v, 'شہر ضروری ہے'),
                            ),
                            _errorLine(),
                            const SizedBox(height: 16),
                            _submitButton(
                                'اکاؤنٹ بنائیں', _doSignup),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================ DIRECTORY TAB ============================

class DirectoryTab extends StatefulWidget {
  const DirectoryTab({super.key});

  @override
  State<DirectoryTab> createState() => _DirectoryTabState();
}

class _DirectoryTabState extends State<DirectoryTab> {
  String _level = 'provinces'; // provinces | districts | areas | donors
  String? _province;
  String? _district;
  String? _area;
  String _query = '';

  /// Blood-group filter for the donor list. Emergencies are about the
  /// RIGHT group, not the whole list — null means "all groups".
  String? _groupFilter;

  // Live public donors, cached per area selection (in-memory only).
  // The cache holds FILTERED rows (name + group + address only);
  // phones never enter this state — the public endpoint has none.
  final Map<String, List<PublicDonor>> _liveCache = {};
  final Map<String, String> _liveErrors = {};
  final Set<String> _liveLoading = {};
  final Set<String> _liveRequested = {};

  String get _areaKey => '$_province|$_district|$_area';

  Future<void> _loadLive(String key, String province, String district,
      String area) async {
    if (_liveLoading.contains(key)) return;
    setState(() {
      _liveLoading.add(key);
      _liveErrors.remove(key);
    });
    final result = await ApiService.fetchPublicDonors();
    if (!mounted) return;
    setState(() {
      _liveLoading.remove(key);
      if (result.ok) {
        _liveCache[key] = (result.data ?? [])
            .where((d) =>
                d.province == province &&
                d.district == district &&
                d.area == area)
            .toList();
      } else {
        _liveErrors[key] = result.error ?? 'سرور سے جواب نہیں ملا۔';
      }
    });
  }

  void _reset() {
    setState(() {
      _level = 'provinces';
      _province = null;
      _district = null;
      _area = null;
    });
  }

  /// "Report wrong info": opens the society's WhatsApp with a prefilled
  /// message identifying the directory row (name + blood group + area
  /// ONLY — the public list has no phones, and none are sent). Lets
  /// the society fix stale or incorrect donor entries (category-standard
  /// "report invalid donor" feature). Fully client-side, no new API.
  Future<void> _reportDonor(
    PublicDonor donor,
    String area,
    String district,
  ) async {
    final String message = 'السلام علیکم!\n'
        'ڈونر ڈائریکٹری میں درج اس معلومات میں غلطی معلوم ہوتی ہے:\n'
        'نام: ${donor.name}\n'
        'بلڈ گروپ: ${donor.group}\n'
        'علاقہ: $area، $district\n'
        '\nبراہ کرم درست کریں۔ جزاک اللہ!';
    await whatsappCentral(message);
  }


  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            decoration: const InputDecoration(
              hintText: '🔍 تلاش کریں: شہر، علاقہ یا ضلع',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(999))),
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
        ),
        if (_query.isNotEmpty) _searchResults() else Expanded(child: _levelView()),
      ],
    );
  }

  Widget _searchResults() {
    final List<Widget> hits = [];
    for (final p in districts.keys) {
      for (final d in districts[p]!) {
        if (d.contains(_query)) {
          hits.add(ListTile(
            leading: const Icon(Icons.location_on),
            title: Text('📍 ضلع: $d — $p'),
            onTap: () => AdService.runWithAd(() {
              if (!mounted) return;
              setState(() {
                _province = p;
                _district = d;
                _area = null;
                _level = 'areas';
                _query = '';
              });
            }),
          ));
        }
        for (final a in areas[d] ?? const <String>[]) {
          if (a.contains(_query)) {
            hits.add(ListTile(
              leading: const Icon(Icons.location_city),
              title: Text('🏘️ علاقہ: $a — $d، $p'),
              onTap: () => AdService.runWithAd(() {
                if (!mounted) return;
                setState(() {
                  _province = p;
                  _district = d;
                  _area = a;
                  _level = 'donors';
                  _query = '';
                });
              }),
            ));
          }
        }
      }
    }
    if (hits.isEmpty) {
      return const Expanded(
        child: Center(child: Text('کوئی نتیجہ نہیں ملا۔ ہجے درست کر کے دوبارہ کوشش کریں۔')),
      );
    }
    return Expanded(
        child: ListView(children: withNativeAds(hits.take(25).toList())));
  }

  Widget _crumbs() {
    final List<Widget> parts = [
      ChoiceChip(
        label: const Text('🇵🇰 پاکستان (صوبے)'),
        selected: _level == 'provinces',
        onSelected: (_) => _reset(),
      ),
    ];
    if (_province != null) {
      parts.add(ChoiceChip(
        label: Text(_province!),
        selected: _level == 'districts',
        onSelected: (_) => setState(() {
          _level = 'districts';
          _district = null;
          _area = null;
        }),
      ));
    }
    if (_district != null) {
      parts.add(ChoiceChip(
        label: Text(_district!),
        selected: _level == 'areas',
        onSelected: (_) => setState(() {
          _level = 'areas';
          _area = null;
        }),
      ));
    }
    if (_area != null) {
      parts.add(Chip(label: Text(_area!)));
    }
    return Wrap(spacing: 8, children: parts);
  }

  Widget _levelView() {
    Widget body;
    if (_level == 'provinces') {
      body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'صوبہ منتخب کریں:',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          ...withNativeAds(districts.entries.map((e) => Card(
                child: ListTile(
                  title: Text(e.key,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text('${e.value.length} اضلاع'),
                  trailing: const Icon(Icons.arrow_back_ios, size: 16),
                  onTap: () => AdService.runWithAd(() {
                    if (!mounted) return;
                    setState(() {
                      _province = e.key;
                      _level = 'districts';
                    });
                  }),
                ),
              )).toList()),
        ],
      );
    } else if (_level == 'districts') {
      final list = districts[_province!]!;
      body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _crumbs(),
          const SizedBox(height: 12),
          Text('$_province — ضلع / شہر منتخب کریں:',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          ...withNativeAds(list.map((d) => Card(
                child: ListTile(
                  title: Text(d,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text((areas[d] ?? const <String>[]).isEmpty
                      ? 'ڈونرز دیکھیں'
                      : '${areas[d]!.length} علاقے'),
                  trailing: const Icon(Icons.arrow_back_ios, size: 16),
                  onTap: () => AdService.runWithAd(() {
                    if (!mounted) return;
                    setState(() {
                      _district = d;
                      _area = null;
                      _level = 'areas';
                    });
                  }),
                ),
              )).toList()),
        ],
      );
    } else if (_level == 'areas') {
      final known = areas[_district!] ?? const <String>[];
      body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _crumbs(),
          const SizedBox(height: 12),
          Text('$_district — علاقہ منتخب کریں:',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          if (known.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                    'اس ضلع کے علاقے ابھی شامل نہیں ہوئے۔ نیا ڈونر شامل ہوتے ہی علاقہ خود بخود بن جائے گا۔'),
              ),
            )
          else
            ...withNativeAds(known.map((a) => Card(
                  child: ListTile(
                    title: Text(a,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    trailing: const Icon(Icons.arrow_back_ios, size: 16),
                    onTap: () => AdService.runWithAd(() {
                      if (!mounted) return;
                      setState(() {
                        _area = a;
                        _level = 'donors';
                      });
                    }),
                  ),
                )).toList()),
          const SizedBox(height: 16),
          _donorEmptyState(),
        ],
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _crumbs(),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text('$_area ($_district) کے ڈونرز',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w900)),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'ڈونرز دوبارہ لوڈ کریں',
                onPressed: () {
                  final key = _areaKey;
                  setState(() {
                    _liveCache.remove(key);
                    _liveErrors.remove(key);
                    _liveRequested.remove(key);
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          _liveDonorsSection(),
        ],
      );
    }
    return body;
  }

  /// Live donors for the selected area. The existing empty-state text
  /// shows ONLY when the live list is empty for that area; a fetch
  /// failure shows an honest Urdu message + retry, never fake data.
  /// Donor rows show name + blood group + address ONLY — no phone,
  /// no call button (the public endpoint returns no phones at all).
  Widget _liveDonorsSection() {
    if (_area == null || _district == null || _province == null) {
      return _donorEmptyState();
    }
    final key = _areaKey;
    final province = _province!;
    final district = _district!;
    final area = _area!;
    if (_liveCache.containsKey(key)) {
      final donors = _liveCache[key]!;
      if (donors.isEmpty) return _donorEmptyState();
      final List<PublicDonor> base = _groupFilter == null
          ? donors
          : donors.where((d) => d.group == _groupFilter).toList();
      // Featured Donor boost (Jaani, 2 Nov 2026): the user's own profile
      // pins to the top with a badge while the 7-day boost is active.
      final List<PublicDonor> shown;
      if (FeaturedBoost.active) {
        final List<PublicDonor> feat =
            base.where(FeaturedBoost.isOwn).toList();
        if (feat.isEmpty) {
          shown = base;
        } else {
          final List<PublicDonor> rest =
              base.where((d) => !FeaturedBoost.isOwn(d)).toList();
          shown = [...feat, ...rest];
        }
      } else {
        shown = base;
      }
      return Column(
        children: [
          _groupFilterRow(donors),
          if (shown.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'اس گروپ کا کوئی ڈونر اس علاقے میں نہیں ملا۔ فلٹر تبدیل کریں یا مرکزی نمبر پر رابطہ کریں۔',
                  style: TextStyle(color: Colors.black54),
                ),
              ),
            )
          else
            ...withNativeAds(shown.map((d) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        backgroundColor: const Color(0xFFC8102E),
                        foregroundColor: Colors.white,
                        child: Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(d.group,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900, fontSize: 13)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(d.name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 17)),
                                ),
                                if (FeaturedBoost.isFeatured(d))
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFD76A),
                                      borderRadius:
                                          BorderRadius.circular(999),
                                    ),
                                    child: const Text('⭐ Featured',
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.black87)),
                                  ),
                              ],
                            ),
                            if (d.address.isNotEmpty)
                              Text('📍 ${d.address}',
                                  style: const TextStyle(
                                      color: Colors.black54)),
                            Text('$area، $district',
                                style: const TextStyle(
                                    color: Colors.black54)),
                            // Report a wrong/stale directory entry: the
                            // row only carries public data, so nothing
                            // private ever leaves the phone.
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: TextButton.icon(
                                onPressed: () =>
                                    _reportDonor(d, area, district),
                                icon: const Icon(Icons.report_outlined,
                                    size: 16),
                                label: const Text('غلط اطلاع رپورٹ کریں',
                                    style: TextStyle(fontSize: 12)),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.black45,
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(0, 32),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              )).toList()),
          const SizedBox(height: 12),
          const Text(
            'ڈونر سے رابطے کے لیے سوسائٹی کے مرکزی نمبر پر کال کریں۔',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<DonerConfig>(
            valueListenable: ConfigService.notifier,
            builder: (context, config, _) => contactRow(
              tel: config.chairman.tel,
              wa: config.chairman.wa,
            ),
          ),
        ],
      );
    }
    if (_liveErrors.containsKey(key)) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_liveErrors[key]!),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  setState(() {
                    _liveErrors.remove(key);
                    _liveRequested.remove(key);
                  });
                },
                child: const Text('دوبارہ کوشش کریں'),
              ),
            ],
          ),
        ),
      );
    }
    if (_liveLoading.contains(key)) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 10),
              Text('ڈونرز لوڈ ہو رہے ہیں…',
                  style: TextStyle(color: Colors.black54)),
            ],
          ),
        ),
      );
    }
    // First visit to this area: schedule one fetch after this frame.
    // Guarded by _liveRequested so rebuilds never duplicate the call.
    if (!_liveRequested.contains(key)) {
      _liveRequested.add(key);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadLive(key, province, district, area);
      });
    }
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 10),
            Text('ڈونرز لوڈ ہو رہے ہیں…',
                style: TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  Widget _donorEmptyState() {
    return Card(
      color: const Color(0xFFFFF8F8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'اس علاقے میں ابھی کوئی ڈونر رجسٹر نہیں۔',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              'ڈونر رجسٹریشن جاری ہے۔ فوری ضرورت ہو تو سوسائٹی کے مرکزی نمبر پر رابطہ کریں، یا پہلے ڈونر بنیں!',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<DonerConfig>(
              valueListenable: ConfigService.notifier,
              builder: (context, config, _) => contactRow(
                tel: config.chairman.tel,
                wa: config.chairman.wa,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Blood-group filter chips for the donor list (directory donors
  /// level). Chips appear only when the loaded list spans more than one
  /// group; tapping filters the visible donor cards client-side.
  Widget _groupFilterRow(List<PublicDonor> donors) {
    final Set<String> present = <String>{for (final d in donors) d.group};
    final List<String> order = <String>[
      for (final g in bloodGroups)
        if (present.contains(g)) g
    ];
    if (order.length <= 1) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('سب گروپس'),
              selected: _groupFilter == null,
              onSelected: (_) => setState(() => _groupFilter = null),
            ),
            for (final g in order)
              ChoiceChip(
                label: Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(g),
                ),
                selected: _groupFilter == g,
                onSelected: (_) => setState(
                    () => _groupFilter = _groupFilter == g ? null : g),
              ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ============================ REGISTER TAB ============================

class DonorEntry {
  final String name;
  final String phone;
  final String province;
  final String district;
  final String area;
  final String group;
  final String address;

  /// Availability scheduling (local-only): the donor marks whether they
  /// are currently available to donate, and — when not available — the
  /// next date they expect to be available. Persisted with the entry,
  /// so older saved entries (without these keys) still load cleanly.
  final bool available;
  final int availableFromMs;

  DonorEntry({
    required this.name,
    required this.phone,
    required this.province,
    required this.district,
    required this.area,
    required this.group,
    required this.address,
    this.available = true,
    this.availableFromMs = 0,
  });

  DonorEntry copyWith({bool? available, int? availableFromMs}) => DonorEntry(
        name: name,
        phone: phone,
        province: province,
        district: district,
        area: area,
        group: group,
        address: address,
        available: available ?? this.available,
        availableFromMs: availableFromMs ?? this.availableFromMs,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'phone': phone,
        'province': province,
        'district': district,
        'area': area,
        'group': group,
        'address': address,
        'available': available,
        'availableFromMs': availableFromMs,
      };

  factory DonorEntry.fromJson(Map<String, dynamic> j) => DonorEntry(
        name: j['name'] as String? ?? '',
        phone: j['phone'] as String? ?? '',
        province: j['province'] as String? ?? '',
        district: j['district'] as String? ?? '',
        area: j['area'] as String? ?? '',
        group: j['group'] as String? ?? '',
        address: j['address'] as String? ?? '',
        available: j['available'] as bool? ?? true,
        availableFromMs: (j['availableFromMs'] as num?)?.toInt() ?? 0,
      );

  /// Next-availability date as d/m/yyyy, or '' when unset.
  String get availabilityDateText {
    if (availableFromMs <= 0) return '';
    final DateTime d = DateTime.fromMillisecondsSinceEpoch(availableFromMs);
    return '${d.day}/${d.month}/${d.year}';
  }

  /// Human-readable availability status for messages and UI.
  String get availabilityText {
    if (available) return 'فی الحال دستیاب ✅';
    final String when = availabilityDateText;
    return when.isEmpty
        ? 'فی الحال دستیاب نہیں'
        : 'فی الحال دستیاب نہیں (اگلی دستیابی: $when)';
  }

  String whatsappMessage() {
    return 'السلام علیکم! میں امن بلڈ ڈونر سوسائٹی میں ڈونر کے طور پر رجسٹر ہونا چاہتا ہوں۔\n'
        'نام: $name\nفون: $phone\nصوبہ: $province\nضلع: $district\nعلاقہ: $area\nبلڈ گروپ: $group\nپتہ: $address\n'
        'دستیابی: $availabilityText';
  }

  /// Public share card — NEVER includes the phone number (phones stay
  /// admin-only, as in the social feed and directory). The donor sends
  /// this themselves via WhatsApp or any other app.
  String get shareText =>
      '🩸 *ڈونر کارڈ* 🩸\n'
      '👤 نام: $name\n'
      '🩸 بلڈ گروپ: $group\n'
      '📍 $address — $area، $district، $province\n'
      '✅ دستیابی: $availabilityText\n'
      '📲 ڈونر ایپ کے ذریعے بھیجا گیا — Aman Blood Donor Society of Pakistan';
}

class RegisterTab extends StatefulWidget {
  const RegisterTab({super.key});

  @override
  State<RegisterTab> createState() => _RegisterTabState();
}

class _RegisterTabState extends State<RegisterTab> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _area = TextEditingController();
  final _address = TextEditingController();
  String _province = districts.keys.first;
  String _district = districts.values.first.first;
  String _group = bloodGroups.first;
  List<DonorEntry> _mine = [];
  bool _saved = false;
  bool _serverBusy = false;
  bool? _serverOk;
  String? _serverMessage;

  /// Posts the local entry to the server directory. Local-card success
  /// is never affected by the server result (and vice versa) — the
  /// message always says which side succeeded.
  Future<void> _submitToServer(DonorEntry entry) async {
    setState(() {
      _serverBusy = true;
      _serverOk = null;
      _serverMessage = null;
    });
    final result = await ApiService.submitDonor(
      name: entry.name,
      phone: entry.phone,
      province: entry.province,
      district: entry.district,
      area: entry.area,
      address: entry.address,
      group: entry.group,
    );
    if (!mounted) return;
    setState(() {
      _serverBusy = false;
      if (result.ok) {
        _serverOk = true;
        _serverMessage = '✔ سرور ڈائریکٹری میں بھی اندراج ہو گیا ہے۔';
      } else {
        _serverOk = false;
        _serverMessage =
            '⚠ سرور پر اندراج نہیں ہو سکا (${result.error}) — آپ کا کارڈ اس فون میں محفوظ ہے۔';
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('abd_my_registrations') ?? [];
    setState(() {
      _mine = raw
          .map((s) => DonorEntry.fromJson(jsonDecode(s) as Map<String, dynamic>))
          .toList();
    });
  }

  Future<void> _saveList() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        'abd_my_registrations', _mine.map((e) => jsonEncode(e.toJson())).toList());
  }

  /// Replaces one donor entry (identity-based) and persists the list.
  Future<void> _updateEntry(DonorEntry old, DonorEntry updated) async {
    final int i = _mine.indexOf(old);
    if (i < 0) return;
    setState(() => _mine[i] = updated);
    await _saveList();
  }

  /// Date picker for "next available date" when the donor is unavailable.
  Future<void> _pickAvailabilityDate(DonorEntry e) async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 2)),
    );
    if (picked == null) return;
    await _updateEntry(
        e, e.copyWith(available: false, availableFromMs: picked.millisecondsSinceEpoch));
  }

  Future<void> _shareDonorCard(DonorEntry e) async {
    final Uri uri =
        Uri.parse('https://wa.me/?text=${Uri.encodeComponent(e.shareText)}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _copyDonorCard(DonorEntry e) async {
    await Clipboard.setData(ClipboardData(text: e.shareText));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ڈونر کارڈ کاپی ہو گیا۔')),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _area.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final districtList = districts[_province]!;
    if (!districtList.contains(_district)) {
      _district = districtList.first;
    }
    return ValueListenableBuilder<DonerConfig>(
      valueListenable: ConfigService.notifier,
      builder: (context, config, _) {
        return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          '➕ نیا ڈونر شامل کریں',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        const Text(
          'اپنی تفصیل درج کریں۔ اندراج آپ کے فون میں محفوظ ہوگا؛ سوسائٹی کی مرکزی ڈائریکٹری میں شامل ہونے کے لیے WhatsApp پر تفصیل بھیجیں۔',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 12),
        Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                    labelText: 'ڈونر کا نام *', border: OutlineInputBorder()),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'نام ضروری ہے' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                    labelText: 'فون نمبر * (مثلاً 03xx-xxxxxxx)',
                    border: OutlineInputBorder()),
                validator: (v) {
                  final digits = (v ?? '').replaceAll(RegExp(r'[^0-9]'), '');
                  if (digits.length < 10) return 'درست فون نمبر لکھیں';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _province,
                decoration: const InputDecoration(
                    labelText: 'صوبہ *', border: OutlineInputBorder()),
                items: districts.keys
                    .map((p) =>
                        DropdownMenuItem(value: p, child: Text(p)))
                    .toList(),
                onChanged: (v) => setState(() {
                  _province = v!;
                  _district = districts[_province]!.first;
                }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _district,
                decoration: const InputDecoration(
                    labelText: 'ضلع / شہر *', border: OutlineInputBorder()),
                items: districtList
                    .map((d) =>
                        DropdownMenuItem(value: d, child: Text(d)))
                    .toList(),
                onChanged: (v) => setState(() => _district = v!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _area,
                decoration: const InputDecoration(
                    labelText: 'علاقہ * (علاقے / محلے / تحصیل کا نام)',
                    border: OutlineInputBorder()),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'علاقہ ضروری ہے' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _group,
                decoration: const InputDecoration(
                    labelText: 'بلڈ گروپ *', border: OutlineInputBorder()),
                items: bloodGroups
                    .map((g) => DropdownMenuItem(
                          value: g,
                          child: Directionality(
                            textDirection: TextDirection.ltr,
                            child: Text(g),
                          ),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _group = v!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _address,
                decoration: const InputDecoration(
                    labelText: 'مکمل پتہ * (گلی / محلہ، شہر، ضلع)',
                    border: OutlineInputBorder()),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'پتہ ضروری ہے' : null,
              ),
              const SizedBox(height: 16),
              const Text(
                'آپ کا نام، بلڈ گروپ اور پتہ ڈائریکٹری میں سب کو نظر آئے گا؛ فون نمبر صرف ایڈمن کو نظر آئے گا۔',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _serverBusy
                      ? null
                      : () async {
                    if (!_formKey.currentState!.validate()) return;
                    final entry = DonorEntry(
                      name: _name.text.trim(),
                      phone: _phone.text.trim(),
                      province: _province,
                      district: _district,
                      area: _area.text.trim(),
                      group: _group,
                      address: _address.text.trim(),
                    );
                    setState(() {
                      _mine.add(entry);
                      _saved = true;
                    });
                    await _saveList();
                    _name.clear();
                    _phone.clear();
                    _area.clear();
                    _address.clear();
                    // Local card is already saved; server result is
                    // reported separately and never rewrites it.
                    await _submitToServer(entry);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC8102E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('ڈونر شامل کریں 🩸',
                      style: TextStyle(fontSize: 17)),
                ),
              ),
              if (_saved)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    '✔ شکریہ! آپ کی رجسٹریشن اس فون میں محفوظ ہو گئی ہے۔',
                    style: TextStyle(
                        color: Colors.green, fontWeight: FontWeight.w700),
                  ),
                ),
              if (_serverBusy)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('سرور پر اندراج ہو رہا ہے…',
                          style: TextStyle(color: Colors.black54)),
                    ],
                  ),
                ),
              if (_serverMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _serverMessage!,
                    style: TextStyle(
                        color: _serverOk == true
                            ? Colors.green
                            : Colors.red,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              if (_serverOk == false && _mine.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: TextButton(
                    onPressed:
                        _serverBusy ? null : () => _submitToServer(_mine.last),
                    child: const Text('سرور پر دوبارہ بھیجیں'),
                  ),
                ),
            ],
          ),
        ),
        if (_mine.isNotEmpty) ...[
          const _FeaturedBoostCard(),
          const SizedBox(height: 8),
        ],
        if (config.donorCard && _mine.isNotEmpty) ...[
          sectionTitle('🪪 میرا ڈونر کارڈ'),
          const Text(
            'یہ اندراجات صرف اس فون میں محفوظ ہیں — سوسائٹی کی مرکزی ڈائریکٹری میں شامل ہونے کے لیے ہر کارڈ سے WhatsApp پر تفصیل بھیجیں۔',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 8),
          ..._mine.map((e) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: const Color(0xFFC8102E),
                            foregroundColor: Colors.white,
                            child: Directionality(
                              textDirection: TextDirection.ltr,
                              child: Text(e.group,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(e.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 17)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () async {
                              setState(() => _mine.remove(e));
                              await _saveList();
                            },
                          ),
                        ],
                      ),
                      Text('📍 ${e.address} — ${e.area}، ${e.district}'),
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text('📞 ${e.phone}',
                            textAlign: TextAlign.left),
                      ),
                      const SizedBox(height: 6),
                      // Availability scheduling: status chip + toggle +
                      // optional next-available date (local-only).
                      Row(
                        children: [
                          Chip(
                            label: Text(
                              e.available ? 'دستیاب' : 'غیر دستیاب',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700),
                            ),
                            backgroundColor: e.available
                                ? const Color(0xFF2E7D32)
                                : const Color(0xFFEF6C00),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                          if (!e.available &&
                              e.availabilityDateText.isNotEmpty)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Text(
                                  'اگلی دستیابی: ${e.availabilityDateText}',
                                  style: const TextStyle(
                                      color: Colors.black54, fontSize: 13),
                                ),
                              ),
                            ),
                          const Spacer(),
                          const Text('میں دستیاب ہوں',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          Switch(
                            value: e.available,
                            activeThumbColor: const Color(0xFF2E7D32),
                            onChanged: (bool v) =>
                                _updateEntry(e, e.copyWith(available: v)),
                          ),
                        ],
                      ),
                      if (!e.available)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () => _pickAvailabilityDate(e),
                            icon: const Icon(Icons.calendar_today, size: 18),
                            label: Text(e.availabilityDateText.isEmpty
                                ? 'اگلی دستیابی کی تاریخ منتخب کریں'
                                : 'تاریخ بدلیں'),
                          ),
                        ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => AdService.runWithAd(() =>
                              whatsappNumber(config.chairman.wa,
                                  e.whatsappMessage())),
                          icon: const Icon(Icons.chat),
                          label: Text(
                              '${config.chairman.displayLine} کو WhatsApp پر بھیجیں'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF25D366),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _shareDonorCard(e),
                            icon: const Icon(Icons.share, size: 18),
                            label: const Text('کارڈ شیئر کریں'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _copyDonorCard(e),
                            icon: const Icon(Icons.copy, size: 18),
                            label: const Text('کاپی کریں'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              )),
        ],
      ],
        );
      },
    );
  }
}

// ============================ FEED POST SHEET ============================

/// "اپ ڈیٹ پوسٹ کریں" sheet: photo via camera OR gallery, fields
/// name / area / blood-group dropdown / patient / place / caption.
/// Requires login (the parent opens AuthScreen first); the bearer
/// token goes in the Authorization header.
/// Returns true when the post succeeded (parent refreshes the feed).
class FeedPostSheet extends StatefulWidget {
  const FeedPostSheet({super.key});

  @override
  State<FeedPostSheet> createState() => _FeedPostSheetState();
}

class _FeedPostSheetState extends State<FeedPostSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _area = TextEditingController();
  final _patient = TextEditingController();
  final _place = TextEditingController();
  final _caption = TextEditingController();
  String _group = bloodGroups.first;
  String? _photoBase64;
  bool _busy = false;
  bool _picking = false;
  int? _uploadPct;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _area.dispose();
    _patient.dispose();
    _place.dispose();
    _caption.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    setState(() {
      _picking = true;
      _error = null;
    });
    final result = await ApiService.pickPhoto(source);
    if (!mounted) return;
    setState(() {
      _picking = false;
      if (result.cancelled) {
        // User backed out of the picker: no error, no change.
      } else if (result.error != null) {
        _error = result.error;
      } else {
        _photoBase64 = result.base64;
        _error = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('📸 اپ ڈیٹ پوسٹ کریں',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pick(ImageSource.camera),
                        icon: const Icon(Icons.photo_camera),
                        label: const Text('کیمرہ'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pick(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library),
                        label: const Text('گیلری'),
                      ),
                    ),
                  ],
                ),
                if (_picking)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('تصویر تیار ہو رہی ہے…',
                        style: TextStyle(color: Colors.black54)),
                  ),
                if (_photoBase64 != null)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('✔ تصویر منتخب ہو گئی ہے۔',
                        style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.w700)),
                  ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                      labelText: 'نام *', border: OutlineInputBorder()),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'نام ضروری ہے' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _area,
                  decoration: const InputDecoration(
                      labelText: 'علاقہ *', border: OutlineInputBorder()),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'علاقہ ضروری ہے' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _group,
                  decoration: const InputDecoration(
                      labelText: 'بلڈ گروپ *', border: OutlineInputBorder()),
                  items: bloodGroups
                      .map((g) => DropdownMenuItem(
                            value: g,
                            child: Directionality(
                              textDirection: TextDirection.ltr,
                              child: Text(g),
                            ),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _group = v!),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _patient,
                  decoration: const InputDecoration(
                      labelText: 'مریض کا نام (اختیاری)',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _place,
                  decoration: const InputDecoration(
                      labelText: 'ہسپتال / جگہ (اختیاری)',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _caption,
                  maxLines: 3,
                  decoration: const InputDecoration(
                      labelText: 'اپ ڈیٹ کی تفصیل *',
                      border: OutlineInputBorder()),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'تفصیل ضروری ہے'
                      : null,
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_error!,
                        style: const TextStyle(
                            color: Colors.red, fontWeight: FontWeight.w700)),
                  ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            if (!_formKey.currentState!.validate()) return;
                            setState(() {
                              _busy = true;
                              _error = null;
                              _uploadPct = null;
                            });
                            final result =
                                await ApiService.submitFeedPost(
                              name: _name.text.trim(),
                              area: _area.text.trim(),
                              group: _group,
                              patient: _patient.text.trim(),
                              place: _place.text.trim(),
                              caption: _caption.text.trim(),
                              photoBase64: _photoBase64,
                              onUploadProgress: (sent, total) {
                                if (!mounted) return;
                                setState(() => _uploadPct = total > 0
                                    ? (sent / total * 100).round()
                                    : null);
                              },
                            );
                            if (!mounted) return;
                            setState(() => _busy = false);
                            if (result.ok) {
                              if (!context.mounted) return;
                              Navigator.pop(context, true);
                            } else {
                              setState(() => _error = result.error);
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFC8102E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(_busy
                        ? (_photoBase64 != null && _uploadPct != null
                            ? 'اپ لوڈ ہو رہا ہے… $_uploadPct٪ مکمل — ${100 - _uploadPct!}٪ باقی'
                            : 'پوسٹ ہو رہا ہے…')
                        : 'پوسٹ کریں'),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================ ADMIN SCREEN ============================

/// Admin PIN screen. The PIN is held ONLY in this widget's state for
/// this one session — never in SharedPreferences, never in code.
/// On success it shows the admin donor list (the ONLY view in the app
/// that renders phone numbers, with call + WhatsApp buttons). On 401
/// it shows a generic message that never hints at the real PIN.
/// Admins are Jaani + Sami Ullah Watto; the app does not hardcode
/// who they are — the PIN is the gate.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _pin = TextEditingController();
  bool _busy = false;
  String? _error;
  List<AdminDonor>? _donors;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  /// Normalizes a stored phone into tel:/wa.me forms. Only used here,
  /// in the admin view — nowhere else in the app handles donor phones.
  String _tel(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('0')) return '+92${digits.substring(1)}';
    if (digits.startsWith('92')) return '+$digits';
    return digits.isEmpty ? '' : '+$digits';
  }

  String _wa(String phone) {
    final tel = _tel(phone);
    return tel.startsWith('+') ? tel.substring(1) : tel;
  }

  Future<void> _load() async {
    if (_pin.text.trim().isEmpty) {
      setState(() => _error = 'PIN لکھیں۔');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _donors = null;
    });
    // Session-only: the PIN goes out as one header and is never stored.
    final result = await ApiService.fetchAdminDonors(_pin.text.trim());
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result.ok) {
        _donors = result.data ?? [];
      } else {
        _error = result.error;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ایڈمن — ڈونرز لسٹ'),
          backgroundColor: const Color(0xFFC8102E),
          foregroundColor: Colors.white,
          centerTitle: true,
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _pin,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'ایڈمن PIN', border: OutlineInputBorder()),
                onSubmitted: (_) => _load(),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _busy ? null : _load,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC8102E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(_busy ? 'لوڈ ہو رہا ہے…' : 'ایڈمن لسٹ دیکھیں'),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!,
                      style: const TextStyle(
                          color: Colors.red, fontWeight: FontWeight.w700)),
                ),
              const SizedBox(height: 12),
              if (_donors != null)
                Expanded(
                  child: _donors!.isEmpty
                      ? const Center(
                          child: Text('ابھی کوئی ڈونر رجسٹر نہیں۔'))
                      : ListView(
                          children: _donors!.map((d) {
                            final tel = _tel(d.phone);
                            final wa = _wa(d.phone);
                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          backgroundColor:
                                              const Color(0xFFC8102E),
                                          foregroundColor: Colors.white,
                                          child: Directionality(
                                            textDirection:
                                                TextDirection.ltr,
                                            child: Text(d.group,
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w900,
                                                    fontSize: 13)),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(d.name,
                                              style: const TextStyle(
                                                  fontWeight:
                                                      FontWeight.w800,
                                                  fontSize: 17)),
                                        ),
                                      ],
                                    ),
                                    if (d.address.isNotEmpty)
                                      Text('📍 ${d.address}'),
                                    Text(
                                        '${d.area}، ${d.district}، ${d.province}',
                                        style: const TextStyle(
                                            color: Colors.black54)),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: ElevatedButton.icon(
                                            onPressed: tel.isEmpty
                                                ? null
                                                : () => callNumber(tel),
                                            icon: const Icon(Icons.phone),
                                            label: const Text('کال کریں'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  const Color(0xFFC8102E),
                                              foregroundColor: Colors.white,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: ElevatedButton.icon(
                                            onPressed: wa.isEmpty
                                                ? null
                                                : () => whatsappNumber(wa),
                                            icon: const Icon(Icons.chat),
                                            label: const Text('WhatsApp'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  const Color(0xFF25D366),
                                              foregroundColor: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Directionality(
                                      textDirection: TextDirection.ltr,
                                      child: Text(d.phone,
                                          style: const TextStyle(
                                              color: Colors.black54)),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================ INFO TAB ============================

class InfoTab extends StatefulWidget {
  const InfoTab({super.key});

  @override
  State<InfoTab> createState() => _InfoTabState();
}

class _InfoTabState extends State<InfoTab> {
  AuthUser? _user;
  bool _loadingUser = true;
  List<int> _donations = <int>[];
  bool _loadingDonations = true;

  @override
  void initState() {
    super.initState();
    _loadUser();
    _loadDonations();
  }

  Future<void> _loadUser() async {
    final AuthUser? u = await AuthService.currentUser();
    if (!mounted) return;
    setState(() {
      _user = u;
      _loadingUser = false;
    });
  }

  Future<void> _openAuth() async {
    final bool? ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const AuthScreen(),
    );
    if (ok == true) _loadUser();
  }

  Future<void> _logout() async {
    await AuthService.logout();
    if (!mounted) return;
    setState(() {
      _user = null;
      _loadingUser = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('لاگ آؤٹ ہو گیا')),
    );
  }

  /// Login state card: shows the logged-in member (name + group/city)
  /// with a logout button, or a login/signup button when logged out.
  Widget _accountCard() {
    if (_loadingUser) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    final AuthUser? user = _user;
    if (user == null) {
      return Card(
        color: const Color(0xFFFFF3E0),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('👤 میرا اکاؤنٹ',
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              const Text(
                'سوشل فیڈ میں پوسٹ، لائک اور کمنٹ کے لیے لاگ اِن کریں۔',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _openAuth,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC8102E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('لاگ اِن / نیا اکاؤنٹ بنائیں'),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Card(
      color: const Color(0xFFE8F5E9),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.account_circle,
                    color: Color(0xFFC8102E), size: 40),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.name,
                          style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900)),
                      Text(
                        '${user.group} • ${user.city}',
                        style:
                            const TextStyle(color: Colors.black54),
                      ),
                      Text(
                        user.email,
                        style: const TextStyle(
                            color: Colors.black54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _logout,
                child: const Text('لاگ آؤٹ'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DonerConfig>(
      valueListenable: ConfigService.notifier,
      builder: (context, config, _) {
        return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _accountCard(),
        const SizedBox(height: 8),
        sectionTitle('🩸 میرا عطیہ ریکارڈ'),
        _donationTrackerCard(),
        const SizedBox(height: 8),
        sectionTitle('ہمارے بارے میں'),
        Text(
          config.about,
          style: const TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 8),
        const AdvertisingBanner(),
        const SizedBox(height: 8),
        _infoCard('🎯', 'ہمارا مشن', config.mission),
        _infoCard('🤝', 'رضاکار ڈونرز', config.volunteers),
        _infoCard('📢', 'آگاہی', config.awareness),
        sectionTitle('خون عطیہ کیسے ہوتا ہے؟'),
        ...config.donationProcess.asMap().entries.map((e) => _infoCard(
              '${e.key + 1}', e.value.step, e.value.text)),
        _infoCard('✅', 'کون عطیہ دے سکتا ہے؟', config.eligibility),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'اپنی اہلیت خود جانچیں — چند سوالات، 2 منٹ۔',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const EligibilityScreen()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('اہلیت جانچیں'),
                ),
              ],
            ),
          ),
        ),
        _infoCard('⏸️', 'کب عطیہ مؤخر کریں؟', config.deferWhen),
        _prepCard(),
        if (config.compatibility) ...[
          sectionTitle('بلڈ گروپس — کون کس کو خون دے سکتا ہے؟'),
        Text(
          config.compatibilityNote,
          style: const TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Table(
              columnWidths: const {
                0: FlexColumnWidth(1),
                1: FlexColumnWidth(2),
              },
              children: [
                const TableRow(children: [
                  Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('ڈونر کا گروپ',
                          style: TextStyle(fontWeight: FontWeight.w900))),
                  Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('کن مریضوں کو دے سکتا ہے',
                          style: TextStyle(fontWeight: FontWeight.w900))),
                ]),
                ...canDonateTo.entries.map((e) => TableRow(children: [
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(e.key,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800)),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(
                              e.value.join(', ') == bloodGroups.join(', ')
                                  ? 'تمام گروپس'
                                  : e.value.join(', ')),
                        ),
                      ),
                    ])),
              ],
            ),
          ),
        ),
        ],
        sectionTitle('ہماری قیادت'),
        _leaderCard('assets/chairman.jpg', config.chairman.name,
            config.chairman.title, config.leadershipChairman),
        _leaderCard('assets/spokesman.png', config.spokesperson.name,
            config.spokesperson.title, config.leadershipSpokesperson),
        sectionTitle('عام سوالات'),
        ...config.faq.map((f) => _infoCard('؟', f.q, f.a)),
        const SizedBox(height: 20),
        // Voluntary Unity rewarded ad: "support the society". Purely
        // opt-in, never gates a feature, never blocks a critical flow.
        const UnitySupportCard(),
        const SizedBox(height: 20),
        // Help & Support: WhatsApp contact (Jaani Bhatti).
        Card(
          child: ListTile(
            leading: const Icon(Icons.support_agent),
            title: const Text('مدد اور سپورٹ'),
            subtitle: const Text('Jaani Bhatti — 03090808180'),
            trailing: const Icon(Icons.chat),
            onTap: () => whatsappNumber('923090808180',
                'السلام علیکم! مجھے مدد چاہیے۔'),
          ),
        ),
        const SizedBox(height: 20),
        Card(
          color: const Color(0xFF171D26),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                ClipOval(child: remoteLogo(size: 64),),
                const SizedBox(height: 8),
                Text(societyName,
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800)),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(societyNameEn,
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
                ),
                const SizedBox(height: 4),
                Text('${config.chairman.title}: ${config.chairman.name} • ${config.spokesperson.title}: ${config.spokesperson.name}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 10),
                contactRow(tel: config.chairman.tel, wa: config.chairman.wa),
                const SizedBox(height: 10),
                Text(
                  config.tagline,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 6),
                const Text('© 2026 AMAN BLOOD DONOR SOCIETY OF PAKISTAN',
                    style: TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
        );
      },
    );
  }

  // ================== Donation tracker (offline-first) ==================
  Future<void> _loadDonations() async {
    final List<int> list = await DonationLog.load();
    if (!mounted) return;
    setState(() {
      _donations = list;
      _loadingDonations = false;
    });
  }

  /// Whole blood: donors should wait ~90 days between donations (per
  /// Pakistan blood-bank guidance). Countdown to the next eligible date.
  DateTime? get _lastDonationDate {
    if (_donations.isEmpty) return null;
    return DateTime.fromMillisecondsSinceEpoch(_donations.last);
  }

  DateTime? get _nextEligibleDate {
    final DateTime? last = _lastDonationDate;
    if (last == null) return null;
    return last.add(const Duration(days: 90));
  }

  String _milestoneEmoji(int n) {
    if (n >= 100) return '👑';
    if (n >= 50) return '🏆';
    if (n >= 25) return '🥇';
    if (n >= 10) return '🥈';
    if (n >= 5) return '🥉';
    if (n >= 1) return '🩸';
    return '🌱';
  }

  String _milestoneLabel(int n) {
    if (n >= 100) return 'سو عطیات — زندہ لیجنڈ';
    if (n >= 50) return 'پچاس عطیات — چیمپئن';
    if (n >= 25) return 'پچیس عطیات — سونے کا تمغہ';
    if (n >= 10) return 'دس عطیات — چاندی کا تمغہ';
    if (n >= 5) return 'پانچ عطیات — کانسی کا تمغہ';
    if (n >= 1) return 'پہلا عطیہ — ہیرو';
    return 'ابھی آغاز نہیں ہوا';
  }

  Future<void> _logDonation() async {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final bool already = _donations.any((int ms) {
      final DateTime d = DateTime.fromMillisecondsSinceEpoch(ms);
      return d.year == today.year && d.month == today.month && d.day == today.day;
    });
    if (already) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('آج کا عطیہ پہلے سے درج ہے ✅')),
      );
      return;
    }
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('عطیہ ریکارڈ کریں'),
          content: const Text(
              'کیا آپ نے واقعی آج خون کا عطیہ دیا؟ یہ ریکارڈ صرف اسی فون میں رہے گا۔'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('نہیں'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('ہاں، درج کریں'),
            ),
          ],
        );
      },
    );
    if (ok != true) return;
    final List<int> list = List<int>.from(_donations)
      ..add(today.millisecondsSinceEpoch)
      ..sort();
    await DonationLog.save(list);
    if (!mounted) return;
    setState(() => _donations = list);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('جزاک اللہ! عطیہ ریکارڈ ہو گیا 🩸')),
    );
  }

  Future<void> _deleteDonation(int ms) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('ریکارڈ حذف کریں؟'),
          content: const Text('یہ عطیہ آپ کے ریکارڈ سے ہٹا دیا جائے گا۔'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('رہنے دیں'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('حذف کریں'),
            ),
          ],
        );
      },
    );
    if (ok != true) return;
    final List<int> list = List<int>.from(_donations)..remove(ms);
    await DonationLog.save(list);
    if (!mounted) return;
    setState(() => _donations = list);
  }

  /// Personal donation tracker card: total count + milestone badge,
  /// days until next eligible donation, and the history list. All
  /// data lives in SharedPreferences on this phone only.
  Widget _donationTrackerCard() {
    if (_loadingDonations) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    final int n = _donations.length;
    final DateTime? next = _nextEligibleDate;
    final DateTime today = DateTime.now();
    String statusText;
    Color statusColor;
    if (next == null) {
      statusText = 'ابھی کوئی عطیہ ریکارڈ نہیں — پہلا عطیہ دیں اور یہاں درج کریں۔';
      statusColor = Colors.black54;
    } else if (next.isAfter(today)) {
      final int days = next.difference(today).inDays + 1;
      statusText = 'اگلا عطیہ $days دن بعد (90 دن کے وقفے کے بعد)۔';
      statusColor = const Color(0xFFEF6C00);
    } else {
      statusText = 'آپ اب عطیے کے اہل ہیں — جزاک اللہ! 🎉';
      statusColor = const Color(0xFF2E7D32);
    }
    String dateFmt(int ms) {
      final DateTime d = DateTime.fromMillisecondsSinceEpoch(ms);
      return '${d.day}/${d.month}/${d.year}';
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(_milestoneEmoji(n),
                    style: const TextStyle(fontSize: 34)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('کل عطیات: $n',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w900)),
                      Text(_milestoneLabel(n),
                          style: const TextStyle(
                              color: Colors.black54, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(statusText,
                style: TextStyle(
                    color: statusColor, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _logDonation,
                icon: const Icon(Icons.add),
                label: const Text('آج کا عطیہ ریکارڈ کریں'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC8102E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            if (_donations.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('عطیات کی تاریخیں:',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              ..._donations.reversed.map((int ms) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.bloodtype,
                        color: Color(0xFFC8102E)),
                    title: Text('خون کا عطیہ — ${dateFmt(ms)}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _deleteDonation(ms),
                    ),
                  )),
            ],
            const SizedBox(height: 8),
            const Text(
              'یہ ریکارڈ صرف اس فون میں محفوظ ہے — کسی سرور کو نہیں بھیجا جاتا۔',
              style: TextStyle(color: Colors.black54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoCard(String icon, String title, String body) {
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(icon, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(body,
                      style: const TextStyle(color: Colors.black54)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Donation prep tips (category-standard "donation tips and prep"):
  /// general before/after guidance in one card. Hardcoded, honest and
  /// generic — the detailed eligibility self-screen and the server's
  /// donation-process steps stay untouched.
  Widget _prepCard() {
    const TextStyle headerStyle = TextStyle(fontWeight: FontWeight.w800);
    const TextStyle bodyStyle =
        TextStyle(color: Colors.black54, height: 1.6);
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: const Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('🩸 عطیے سے پہلے اور بعد کی احتیاطیں',
                style: TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 15)),
            SizedBox(height: 8),
            Text('عطیے سے پہلے:', style: headerStyle),
            Text(
              '• رات کو اچھی نیند لیں۔\n'
              '• عطیے سے 2 سے 3 گھنٹے پہلے اچھا کھانا کھائیں۔\n'
              '• کافی پانی پیئیں۔\n'
              '• ہلکے اور ڈھیلے کپڑے پہنیں۔',
              style: bodyStyle,
            ),
            SizedBox(height: 6),
            Text('عطیے کے بعد:', style: headerStyle),
            Text(
              '• کچھ دیر بیٹھ کر آرام کریں۔\n'
              '• پانی اور جوس زیادہ پیئیں۔\n'
              '• 24 گھنٹے تک بھاری وزن نہ اٹھائیں اور سخت مشقت سے پرہیز کریں۔\n'
              '• چکر آئیں تو فوری طور پر عملے کو بتائیں۔',
              style: bodyStyle,
            ),
          ],
        ),
      ),
    );
  }

  Widget _leaderCard(
      String image, String name, String role, String bio) {
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.asset(image,
                  width: 150, height: 190, fit: BoxFit.cover),
            ),
            const SizedBox(height: 10),
            Text(name,
                style: const TextStyle(
                    fontSize: 19, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFC8102E),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(role,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 6),
            Text(bio,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}

/// Personal donation history, stored ON THE DEVICE ONLY in
/// SharedPreferences (key 'doner_donation_dates_v1'): a JSON list of
/// epoch-millisecond timestamps. Powers the "My donation record"
/// tracker card in InfoTab — milestone badges + the 90-day
/// next-eligibility countdown. Nothing is ever sent to any server.
class DonationLog {
  static const String _key = 'doner_donation_dates_v1';

  static Future<List<int>> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <int>[];
    try {
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      final List<int> out = decoded.whereType<int>().toList()..sort();
      return out;
    } catch (_) {
      return <int>[];
    }
  }

  static Future<void> save(List<int> dates) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(dates));
  }
}

/// One yes/no question in the eligibility self-screen.
class EligibilityQuestion {
  final String text;
  final String blocker;
  const EligibilityQuestion({required this.text, required this.blocker});
}

/// Interactive blood-donation eligibility self-screen (SELF-SCREEN
/// ONLY — not medical advice). The donor answers yes/no questions;
/// if every answer is "yes" they are preliminarily eligible, otherwise
/// the blockers are listed. A disclaimer is shown top and bottom:
/// final eligibility is always decided by the hospital/blood bank.
class EligibilityScreen extends StatefulWidget {
  const EligibilityScreen({super.key});

  @override
  State<EligibilityScreen> createState() => _EligibilityScreenState();
}

class _EligibilityScreenState extends State<EligibilityScreen> {
  static const List<EligibilityQuestion> _questions = <EligibilityQuestion>[
    EligibilityQuestion(
      text: 'میری عمر 18 سے 65 سال کے درمیان ہے۔',
      blocker: 'عمر 18 سے 65 سال کے درمیان ہونی چاہیے۔',
    ),
    EligibilityQuestion(
      text: 'میرا وزن کم از کم 50 کلوگرام ہے۔',
      blocker: 'وزن کم از کم 50 کلوگرام ہونا چاہیے۔',
    ),
    EligibilityQuestion(
      text: 'میرے آخری خون کے عطیے کو کم از کم 3 ماہ ہو گئے ہیں۔',
      blocker: 'دو عطیات کے درمیان کم از کم 3 ماہ کا وقفہ ضروری ہے۔',
    ),
    EligibilityQuestion(
      text: 'آج مجھے بخار، نزلہ، زکام یا کوئی انفیکشن نہیں ہے۔',
      blocker: 'بخار/انفیکشن کی صورت میں عطیہ مؤخر کریں۔',
    ),
    EligibilityQuestion(
      text: 'میں فی الحال کوئی اینٹی بائیوٹک دوا استعمال نہیں کر رہا/رہی۔',
      blocker: 'اینٹی بائیوٹک کے دوران عطیہ مؤخر کریں۔',
    ),
    EligibilityQuestion(
      text: 'میں حاملہ نہیں ہوں اور نہ ہی بچے کو دودھ پلا رہی ہوں۔',
      blocker: 'حمل یا دودھ پلانے کے دوران عطیہ نہ دیں۔',
    ),
    EligibilityQuestion(
      text: 'پچھلے 6 ماہ میں میرا کوئی بڑا آپریشن یا سنگین بیماری نہیں ہوئی۔',
      blocker: 'بڑے آپریشن/بیماری کے بعد ڈاکٹر سے مشورہ کریں۔',
    ),
  ];

  final Map<int, bool> _answers = <int, bool>{};
  bool _showResult = false;

  List<String> get _blockers {
    final List<String> out = <String>[];
    for (int i = 0; i < _questions.length; i++) {
      if (_answers[i] == false) out.add(_questions[i].blocker);
    }
    return out;
  }

  bool get _allAnswered => _answers.length == _questions.length;

  void _checkResult() {
    if (!_allAnswered) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('براہ کرم تمام سوالات کے جواب دیں۔')),
      );
      return;
    }
    setState(() => _showResult = true);
  }

  Widget _answerButtons(int index) {
    final bool? answer = _answers[index];
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => setState(() {
              _answers[index] = true;
              _showResult = false;
            }),
            style: OutlinedButton.styleFrom(
              backgroundColor:
                  answer == true ? const Color(0xFF2E7D32) : null,
              foregroundColor: answer == true ? Colors.white : null,
            ),
            child: const Text('ہاں'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            onPressed: () => setState(() {
              _answers[index] = false;
              _showResult = false;
            }),
            style: OutlinedButton.styleFrom(
              backgroundColor:
                  answer == false ? const Color(0xFFC8102E) : null,
              foregroundColor: answer == false ? Colors.white : null,
            ),
            child: const Text('نہیں'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<String> blockers = _blockers;
    return Scaffold(
      appBar: AppBar(
        title: const Text('اہلیت خود جانچیں'),
        backgroundColor: const Color(0xFFC8102E),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            color: Color(0xFFFFF3E0),
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                '⚠️ یہ صرف ابتدائی خود جانچ ہے — حتمی اہلیت کا فیصلہ '
                'ہسپتال یا بلڈ بینک کرے گا۔',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 8),
          ...List<Widget>.generate(_questions.length, (int i) {
            return Card(
              margin: const EdgeInsets.only(top: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_questions[i].text,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 8),
                    _answerButtons(i),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _checkResult,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFC8102E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('نتیجہ دیکھیں'),
            ),
          ),
          if (_showResult) ...[
            const SizedBox(height: 12),
            Card(
              color: blockers.isEmpty
                  ? const Color(0xFFE8F5E9)
                  : const Color(0xFFFFEBEE),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      blockers.isEmpty
                          ? '🎉 مبارک! آپ ابتدائی طور پر اہل لگتے ہیں۔'
                          : '⏸️ فی الحال عطیہ مؤخر کریں:',
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w900),
                    ),
                    if (blockers.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ...blockers.map((String b) => Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('• $b',
                                style: const TextStyle(
                                    color: Colors.black87)),
                          )),
                    ],
                    const SizedBox(height: 10),
                    const Text(
                      'حتمی فیصلہ ہمیشہ ہسپتال/بلڈ بینک کی اسکریننگ کرے گی۔',
                      style: TextStyle(
                          color: Colors.black54, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

/// Voluntary Unity rewarded ad card: "watch an ad to support the
/// society". Purely opt-in — never gates a feature, never blocks a
/// critical flow. Tapping plays a rewarded video; completing it shows
/// a thank-you (the revenue goes to the society's Unity account).
class UnitySupportCard extends StatefulWidget {
  const UnitySupportCard({super.key});

  @override
  State<UnitySupportCard> createState() => _UnitySupportCardState();
}

class _UnitySupportCardState extends State<UnitySupportCard> {
  bool _busy = false;

  Future<void> _watchAd() async {
    if (_busy) return;
    if (!UnityAdsService.isInitialized) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('اشتہار ابھی تیار نہیں — تھوڑی دیر بعد کوشش کریں')),
      );
      return;
    }
    setState(() => _busy = true);
    final result = await UnityAdsService.showRewardedAd();
    if (!mounted) return;
    setState(() => _busy = false);
    final msg = switch (result) {
      UnityAdResult.completed =>
        'جزاک اللہ! آپ کے تعاون کا شکریہ 🩸',
      UnityAdResult.skipped =>
        'اشتہار ادھورا رہ گیا — مکمل دیکھنے پر تعاون شمار ہوگا',
      UnityAdResult.failed =>
        'اشتہار نہیں چل سکا — دوبارہ کوشش کریں',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFFFF8E7),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              '📺 سوسائٹی کی مدد کریں',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            const Text(
              'ایک مختصر اشتہار دیکھیں — اس سے حاصل ہونے والی آمدنی '
              'امن بلڈ ڈونر سوسائٹی کے کام میں استعمال ہوگی۔ '
              'یہ مکمل طور پر اختیاری ہے۔',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _watchAd,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.play_circle_outline),
                label: Text(_busy ? 'اشتہار چل رہا ہے…' : 'اشتہار دیکھیں'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC8102E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


// ===================== FEATURED DONOR BOOST (v1.0.3) =====================
/// "Featured Donor" reward (Jaani, 2 Nov 2026): the user watches a Unity
/// rewarded video (strictly opt-in, from their own donor card) and their own
/// registered donor profile is pinned to the top of the directory list with
/// a ⭐ Featured badge for 7 days. Expiry persists in SharedPreferences.
/// The reward is granted ONLY when the rewarded video completes fully —
/// skipped or failed shows grant nothing. Call, WhatsApp and navigation
/// flows are never gated by this.
class FeaturedBoost {
  static const String _key = 'doner_featured_boost_until_ms';
  static const Duration boostDuration = Duration(days: 7);

  static bool active = false;
  static int remainingDays = 0;
  static List<DonorEntry> myEntries = const [];

  /// Load state from SharedPreferences into the in-memory cache.
  /// Called once at startup and after every grant.
  static Future<void> refresh() async {
    try {
      final SharedPreferences prefs =
          await SharedPreferences.getInstance();
      final int until = prefs.getInt(_key) ?? 0;
      final int now = DateTime.now().millisecondsSinceEpoch;
      active = until > now;
      remainingDays =
          active ? ((until - now) / 86400000).ceil().clamp(1, 7) : 0;
      final List<String> raw =
          prefs.getStringList('abd_my_registrations') ?? const [];
      myEntries = raw
          .map((s) =>
              DonorEntry.fromJson(jsonDecode(s) as Map<String, dynamic>))
          .toList();
    } catch (_) {
      active = false;
      remainingDays = 0;
    }
  }

  /// Grant a fresh 7-day boost starting now.
  static Future<void> grant() async {
    try {
      final SharedPreferences prefs =
          await SharedPreferences.getInstance();
      await prefs.setInt(
          _key,
          DateTime.now()
              .add(boostDuration)
              .millisecondsSinceEpoch);
    } catch (_) {
      // A storage failure just means the boost won't persist; the
      // in-memory state still updates via refresh().
    }
    await refresh();
  }

  static String _norm(String s) => s.trim().toLowerCase();

  /// True when the public directory entry matches one of the user's own
  /// registered donor profiles (name + blood group + district + area).
  static bool isOwn(PublicDonor d) {
    final String n = _norm(d.name);
    if (n.isEmpty) return false;
    return myEntries.any((e) =>
        _norm(e.name) == n &&
        e.group == d.group &&
        _norm(e.district) == _norm(d.district) &&
        _norm(e.area) == _norm(d.area));
  }

  /// True when this entry should be pinned with the Featured badge.
  static bool isFeatured(PublicDonor d) => active && isOwn(d);
}

/// Opt-in "Featured Donor" card shown above the user's own donor card(s).
/// One rewarded video -> 7-day featured boost. Strictly voluntary.
class _FeaturedBoostCard extends StatefulWidget {
  const _FeaturedBoostCard();

  @override
  State<_FeaturedBoostCard> createState() => _FeaturedBoostCardState();
}

class _FeaturedBoostCardState extends State<_FeaturedBoostCard> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    FeaturedBoost.refresh().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _watchAd() async {
    if (_busy) return;
    if (!UnityAdsService.isInitialized) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('اشتہار ابھی تیار نہیں — تھوڑی دیر بعد کوشش کریں')),
      );
      return;
    }
    setState(() => _busy = true);
    final UnityAdResult result = await UnityAdsService.showRewardedAd();
    if (!mounted) return;
    setState(() => _busy = false);
    if (result == UnityAdResult.completed) {
      await FeaturedBoost.grant();
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                '⭐ مبارک! آپ کا ڈونر پروفائل 7 دن تک ڈائریکٹری میں سب سے اوپر نمایاں رہے گا')),
      );
    } else if (result == UnityAdResult.skipped) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('اشتہار ادھورا رہ گیا — مکمل دیکھنے پر Featured ملے گا')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('اشتہار نہیں چل سکا — دوبارہ کوشش کریں')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool active = FeaturedBoost.active;
    return Card(
      color: const Color(0xFFFFF3D6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '⭐ Featured Donor',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              active
                  ? 'آپ کا پروفائل ڈائریکٹری میں سب سے اوپر نمایاں ہے — ${FeaturedBoost.remainingDays} دن باقی ہیں۔'
                  : 'ایک مختصر اشتہار دیکھیں اور اپنا ڈونر پروفائل 7 دن تک ڈائریکٹری میں سب سے اوپر نمایاں کریں۔ یہ مکمل طور پر اختیاری ہے۔',
              style: const TextStyle(color: Colors.black54),
            ),
            if (!active) ...[
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: _busy ? null : _watchAd,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.play_circle_outline),
                label: Text(
                    _busy ? 'اشتہار چل رہا ہے…' : 'اشتہار دیکھیں اور Featured بنیں'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC8102E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ===================== ADVERTISING BANNER (v1.0.3) =====================
/// In-app advertising banner (Jaani, 2 Nov 2026): placed in the About
/// section. Tapping opens a WhatsApp chat with Nigraan TV for ad bookings.
class AdvertisingBanner extends StatelessWidget {
  const AdvertisingBanner({super.key});

  // WhatsApp URL comes from Remote Config (advertising_banner.whatsapp_url).

  Future<void> _openWhatsApp() async {
    final AdvertisingBannerConfig ad = remoteConfigService.config.advertisingBanner; final Uri uri = Uri.parse(ad.whatsappUrl.isNotEmpty ? ad.whatsappUrl : 'https://wa.me/923090808180');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
        return ValueListenableBuilder<RemoteConfig>(valueListenable: remoteConfigService.notifier, builder: (BuildContext context, RemoteConfig cfg, _) { final AdvertisingBannerConfig ad = cfg.advertisingBanner; if (!ad.enabled) return const SizedBox.shrink(); return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 3,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: _openWhatsApp,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFF0F2027),
                Color(0xFF203A43),
                Color(0xFF2C5364),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ad.imageUrl.trim().isEmpty
                  ? Image.asset('assets/jaani_ad_banner.jpg', width: 84, height: 112, fit: BoxFit.cover)
                  : Image.network(ad.imageUrl, width: 84, height: 112, fit: BoxFit.cover, errorBuilder: (_, _, _) => Image.asset('assets/jaani_ad_banner.jpg', width: 84, height: 112, fit: BoxFit.cover)),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      ad.title.isNotEmpty ? ad.title : 'For Advertising',
                      style: TextStyle(
                        color: Color(0xFFFFD76A),
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      ad.subtitle.isNotEmpty ? ad.subtitle : 'Contact Us on WhatsApp:',
                      style: TextStyle(
                          color: Colors.white70, fontSize: 13),
                    ),
                    SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.chat,
                            color: Color(0xFF25D366), size: 18),
                        SizedBox(width: 6),
                        Text(
                          ad.phoneDisplay.isNotEmpty ? ad.phoneDisplay : '03090808180',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

    ),  ),
    ); }, );
  }
}


