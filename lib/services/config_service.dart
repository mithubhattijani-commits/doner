/// Doner — server-driven remote config (V1.2.2).
///
/// Fetches https://nigraantv.xyz/apps/doner-config.json on launch using
/// the SAME mechanism as the in-app updater (dart:io HttpClient, no new
/// dependency). Fail-soft by design: on ANY failure the last cached
/// config is used; offline the cache is used; on first launch with no
/// cache the hardcoded defaults below are used. The defaults are
/// IDENTICAL to the live config values, so nothing changes visually
/// when the server is unreachable.
///
/// The full-APK updater (services/update_service.dart, manifest
/// nigraantv.xyz/apps/doner-version.json) is untouched and stays
/// as the full-release path; this service only drives content, the
/// announcement banner, contacts and feature flags.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One public contact (chairman / spokesperson) from the config.
class ContactInfo {
  ContactInfo({
    required this.title,
    required this.name,
    required this.phone,
  })  : tel = _telOf(phone),
        wa = _waOf(phone);

  final String title;
  final String name;

  /// Display form, e.g. '0300 4927940' (verbatim from the config).
  final String phone;

  /// Dial form, e.g. '+923004927940'.
  final String tel;

  /// WhatsApp form, e.g. '923004927940'.
  final String wa;

  static String _digits(String phone) =>
      phone.replaceAll(RegExp(r'[^0-9]'), '');

  static String _telOf(String phone) {
    final digits = _digits(phone);
    if (digits.startsWith('92')) return '+$digits';
    if (digits.startsWith('0')) return '+92${digits.substring(1)}';
    return '+$digits';
  }

  static String _waOf(String phone) {
    final digits = _digits(phone);
    if (digits.startsWith('92')) return digits;
    if (digits.startsWith('0')) return '92${digits.substring(1)}';
    return digits;
  }

  /// Display line used on the home card, e.g. 'بانی و چیئرمین سمیع اللہ وٹو'.
  String get displayLine => '$title $name';
}

class DonationStep {
  const DonationStep({required this.step, required this.text});
  final String step;
  final String text;
}

class FaqItem {
  const FaqItem({required this.q, required this.a});
  final String q;
  final String a;
}

/// Whole remote config, flattened for simple wiring in main.dart.
class DonerConfig {
  const DonerConfig({
    required this.chairman,
    required this.spokesperson,
    required this.announcementEnabled,
    required this.announcementText,
    required this.about,
    required this.mission,
    required this.volunteers,
    required this.awareness,
    required this.donationProcess,
    required this.eligibility,
    required this.deferWhen,
    required this.compatibilityNote,
    required this.leadershipChairman,
    required this.leadershipSpokesperson,
    required this.faq,
    required this.tagline,
    required this.donorCard,
    required this.compatibility,
    required this.directory,
  });

  final ContactInfo chairman;
  final ContactInfo spokesperson;
  final bool announcementEnabled;
  final String announcementText;
  final String about;
  final String mission;
  final String volunteers;
  final String awareness;
  final List<DonationStep> donationProcess;
  final String eligibility;
  final String deferWhen;
  final String compatibilityNote;
  final String leadershipChairman;
  final String leadershipSpokesperson;
  final List<FaqItem> faq;
  final String tagline;

  /// Feature flags. Each defaults to true when its key is missing.
  final bool donorCard;
  final bool compatibility;
  final bool directory;

  /// True only when a banner may be shown: enabled AND non-empty text.
  bool get showAnnouncement =>
      announcementEnabled && announcementText.trim().isNotEmpty;

  /// Hardcoded defaults — byte-identical in meaning to the live config
  /// (generated from the live file, never hand-typed).
  static final DonerConfig defaults = DonerConfig(
    chairman: ContactInfo(title: 'بانی و چیئرمین', name: 'سمیع اللہ وٹو', phone: '0300 4927940'),
    spokesperson: ContactInfo(title: 'ترجمان', name: 'رائے غلام جیلانی بھٹی', phone: '0309 0808180'),
    announcementEnabled: false,
    announcementText: '',
    about: 'امن بلڈ ڈونر سوسائٹی آف پاکستان ایک غیر منافع بخش فلاحی تنظیم ہے — مقصد ایک ہی: کوئی مریض خون کی کمی کی وجہ سے زندگی کی بازی نہ ہارے۔',
    mission: 'مریضوں — خصوصاً تھیلیسیمیا کے بچوں، حادثات کے زخمیوں اور آپریشن کے مریضوں — کو بروقت خون کی فراہمی یقینی بنانا۔',
    volunteers: 'ہر صوبے، ضلع اور علاقے میں رضاکار ڈونرز کا منظم نیٹ ورک، تاکہ ایمرجنسی میں مطلوبہ بلڈ گروپ فوری دستیاب ہو۔',
    awareness: 'خون عطیہ کرنے کے بارے میں غلط فہمیاں دور کرنا اور آگاہی پھیلانا کہ عطیہ دینا محفوظ، آسان اور ثواب کا کام ہے۔',
    donationProcess: [DonationStep(step: 'رجسٹریشن', text: 'اپنی معلومات درج کرائیں اور مختصر صحت فارم پُر کریں۔'), DonationStep(step: 'طبی معائنہ', text: 'بلڈ پریشر، نبض، وزن اور ہیموگلوبن کی فوری جانچ — آپ کی صحت کا مکمل تحفظ۔'), DonationStep(step: 'عطیہ', text: 'جراثیم سے پاک آلات کے ساتھ صرف 8 سے 10 منٹ میں عطیہ مکمل۔'), DonationStep(step: 'آرام و تازگی', text: 'چند منٹ آرام، جوس یا بسکٹ — اور آپ ایک ہیرو بن کر گھر جائیں۔')],
    eligibility: 'عمر 18 سے 65 سال • وزن کم از کم 50 کلو • مجموعی طور پر صحت مند • پچھلے عطیے کو کم از کم 3 ماہ • عطیے سے پہلے ہلکا ناشتہ۔',
    deferWhen: 'بخار یا اینٹی بایوٹک جاری ہو • حالیہ بڑا آپریشن • حمل یا دودھ پلانے کا دور • بیماری کی صورت میں ڈاکٹر کے مشورے کے بغیر عطیہ نہ دیں۔',
    compatibilityNote: 'ریڈ سیلز کی مطابقت کی سادہ جدول — O نیگیٹو یونیورسل ڈونر ہے، AB پازیٹو یونیورسل وصول کنندہ۔',
    leadershipChairman: 'سوسائٹی کے بانی اور مرکزی چیئرمین — جن کی سرپرستی اور خدمتِ انسانیت کے جذبے نے اس کارواں کی بنیاد رکھی۔',
    leadershipSpokesperson: 'سوسائٹی کے ترجمان — میڈیا اور عوامی رابطے کی ذمہ داری سنبھالتے ہیں اور آگاہی مہمات کی آواز ہیں۔',
    faq: [FaqItem(q: 'کیا خون دینے سے کمزوری ہوتی ہے؟', a: 'نہیں۔ جسم عطیہ کیے گئے خون کی مقدار 24 سے 48 گھنٹوں میں پوری کر لیتا ہے۔ ہلکی تھکن آرام اور پانی سے ختم ہو جاتی ہے۔'), FaqItem(q: 'دوبارہ کب عطیہ دے سکتے ہیں؟', a: 'صحت مند فرد ہر 3 ماہ بعد محفوظ طریقے سے عطیہ کر سکتا ہے — سال میں 4 بار، ہر بار 3 زندگیاں بچانے کا موقع۔'), FaqItem(q: 'کیا عطیہ کیا گیا خون جانچا جاتا ہے؟', a: 'جی ہاں، ہر عطیے کی ہیپاٹائٹس، ایچ آئی وی اور دیگر اہم جانچیں کی جاتی ہیں تاکہ مریض کو مکمل محفوظ خون ملے۔'), FaqItem(q: 'عطیے سے پہلے کیا خیال رکھیں؟', a: 'اچھی نیند لیں، ہلکا ناشتہ کریں، پانی زیادہ پئیں اور شناختی کارڈ ساتھ لائیں۔')],
    tagline: 'خون عطیہ کرنا صدقہِ جاریہ ہے — آج آپ کا عطیہ، کل کسی کی زندگی۔',
    donorCard: true,
    compatibility: true,
    directory: true,
  );

  static String _s(Map<String, dynamic>? m, String key, String fallback) {
    final v = m?[key];
    return v is String && v.isNotEmpty ? v : fallback;
  }

  static bool _b(Map<String, dynamic>? m, String key, bool fallback) {
    final v = m?[key];
    return v is bool ? v : fallback;
  }

  static ContactInfo _contact(
      Map<String, dynamic>? m, ContactInfo fallback) {
    if (m == null) return fallback;
    return ContactInfo(
      title: _s(m, 'title', fallback.title),
      name: _s(m, 'name', fallback.name),
      phone: _s(m, 'phone', fallback.phone),
    );
  }

  /// Parses a decoded config document. Every field falls back to the
  /// matching default when missing or mistyped — a partial server
  /// document can never blank out a section.
  static DonerConfig fromJson(dynamic data) {
    final d = defaults;
    if (data is! Map<String, dynamic>) return d;
    final contacts = data['contacts'] as Map<String, dynamic>?;
    final announcement = data['announcement'] as Map<String, dynamic>?;
    final info = data['info'] as Map<String, dynamic>?;
    final features = data['features'] as Map<String, dynamic>?;
    final leadership = info?['leadership'] as Map<String, dynamic>?;

    var process = d.donationProcess;
    final rawProcess = info?['donationProcess'];
    if (rawProcess is List && rawProcess.isNotEmpty) {
      final parsed = <DonationStep>[];
      for (final e in rawProcess) {
        if (e is Map<String, dynamic>) {
          final step = _s(e, 'step', '');
          final text = _s(e, 'text', '');
          if (step.isNotEmpty || text.isNotEmpty) {
            parsed.add(DonationStep(step: step, text: text));
          }
        }
      }
      if (parsed.isNotEmpty) process = parsed;
    }

    var faq = d.faq;
    final rawFaq = info?['faq'];
    if (rawFaq is List && rawFaq.isNotEmpty) {
      final parsed = <FaqItem>[];
      for (final e in rawFaq) {
        if (e is Map<String, dynamic>) {
          final q = _s(e, 'q', '');
          final a = _s(e, 'a', '');
          if (q.isNotEmpty || a.isNotEmpty) {
            parsed.add(FaqItem(q: q, a: a));
          }
        }
      }
      if (parsed.isNotEmpty) faq = parsed;
    }

    return DonerConfig(
      chairman: _contact(
          contacts?['chairman'] as Map<String, dynamic>?, d.chairman),
      spokesperson: _contact(
          contacts?['spokesperson'] as Map<String, dynamic>?, d.spokesperson),
      announcementEnabled:
          _b(announcement, 'enabled', d.announcementEnabled),
      announcementText: announcement?['text'] is String
          ? (announcement!['text'] as String)
          : d.announcementText,
      about: _s(info, 'about', d.about),
      mission: _s(info, 'mission', d.mission),
      volunteers: _s(info, 'volunteers', d.volunteers),
      awareness: _s(info, 'awareness', d.awareness),
      donationProcess: process,
      eligibility: _s(info, 'eligibility', d.eligibility),
      deferWhen: _s(info, 'deferWhen', d.deferWhen),
      compatibilityNote: _s(info, 'compatibilityNote', d.compatibilityNote),
      leadershipChairman: _s(leadership, 'chairman', d.leadershipChairman),
      leadershipSpokesperson:
          _s(leadership, 'spokesperson', d.leadershipSpokesperson),
      faq: faq,
      tagline: _s(info, 'tagline', d.tagline),
      donorCard: _b(features, 'donorCard', true),
      compatibility: _b(features, 'compatibility', true),
      directory: _b(features, 'directory', true),
    );
  }
}

class ConfigService {
  /// Server config URL. This is content only — never an APK link.
  static const String configUrl =
      'https://nigraantv.xyz/apps/doner-config.json';

  static const String _cacheKey = 'doner_remote_config_json';

  /// Current config; widgets listen to this and rebuild on refresh.
  static final ValueNotifier<DonerConfig> notifier =
      ValueNotifier<DonerConfig>(DonerConfig.defaults);

  static DonerConfig get current => notifier.value;

  /// Loads the last-good cached config (if any) before first paint.
  /// Never throws.
  static Future<void> loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return;
      notifier.value = DonerConfig.fromJson(jsonDecode(raw));
    } catch (_) {
      // Corrupt cache: keep defaults.
    }
  }

  /// Fetches the live config and caches it on success. Fail-soft:
  /// ANY failure (offline, timeout, bad status, bad JSON) leaves the
  /// current config (cache or defaults) untouched. Never throws.
  static Future<void> refresh() async {
    HttpClient? client;
    try {
      client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8);
      final request = await client.getUrl(Uri.parse(configUrl));
      final response =
          await request.close().timeout(const Duration(seconds: 8));
      if (response.statusCode != HttpStatus.ok) return;
      final body = await response.transform(utf8.decoder).join();
      final parsed = DonerConfig.fromJson(jsonDecode(body));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, body);
      notifier.value = parsed;
    } catch (_) {
      // Fail-soft: keep cache/defaults, no error shown to the user.
    } finally {
      client?.close(force: true);
    }
  }
}
