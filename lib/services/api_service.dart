/// Doner — society API client (live directory + feed + admin + auth).
///
/// Base: https://aman-blood-donor-society.mithubhattijani.workers.dev
/// (moved 31 Oct 2026; the old doner-donor-society host is retired.)
/// Contract (owned by the Worker, not this app):
///   GET  /api/donors        public: name/group/province/district/area/
///                          address/ts + photo (Worker v2) — NO phone.
///   POST /api/donors        name/phone/province/district/area/address/group
///                          (immediately public, phone never shown publicly).
///   GET  /api/feed          public, newest first.
///   POST /api/feed          Authorization: Bearer `<token>`.
///   GET  /api/admin/donors  header X-Admin-Key; the ONLY endpoint that
///                          returns phone numbers, shown only in the admin view.
///   Auth + social feed live in AuthService (services/auth_service.dart):
///   login/register/logout/me and /api/feed/posts* (posts, likes,
///   comments), all gated by the Authorization: Bearer header. The
///   old MEMBER_CODE system is gone (Jaani, 31 Oct 2026).
///
/// PRIVACY: phone numbers are never logged and never rendered outside the
/// admin view. Every method returns errors as Urdu strings and never
/// throws to the UI. The login token lives in SharedPreferences
/// (doner_auth_token); the admin PIN stays session-only in the UI layer —
/// this service never stores it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data.dart';

/// Society API base (live, verified 31 Oct 2026).
const String societyApiBase =
    'https://aman-blood-donor-society.mithubhattijani.workers.dev';

/// A result that never throws: [data] on success, [error] (Urdu) on failure.
class ApiResult<T> {
  const ApiResult.ok(this.data) : error = null;
  const ApiResult.err(this.error) : data = null;

  final T? data;
  final String? error;

  bool get ok => error == null;
}

/// One public donor row. Deliberately has NO phone field — the public
/// endpoint never returns one, and the UI must never show one here.
class PublicDonor {
  const PublicDonor({
    required this.name,
    required this.group,
    required this.province,
    required this.district,
    required this.area,
    required this.address,
      this.photo = '',
    required this.ts,
  });

  final String name;
  final String group;
  final String province;
  final String district;
  final String area;
  final String address;
    final String photo;
  final String ts;

  factory PublicDonor.fromJson(Map<String, dynamic> j) => PublicDonor(
        name: _s(j['name']),
        group: _s(j['group']),
        province: _s(j['province']),
        district: _s(j['district']),
        area: _s(j['area']),
        address: _s(j['address']),
        ts: _s(j['ts'] ?? j['createdAt'] ?? j['date']),
      photo: _s(j['photo'] ?? j['photoUrl'] ?? j['image']),
      );
}

/// Admin-only donor row (phone included). Rendered ONLY in the admin view.
class AdminDonor extends PublicDonor {
  const AdminDonor({
    required super.name,
    required super.group,
    required super.province,
    required super.district,
    required super.area,
    required super.address,
    required super.ts,
      super.photo,
    required this.phone,
  });

  final String phone;

  factory AdminDonor.fromJson(Map<String, dynamic> j) => AdminDonor(
        name: _s(j['name']),
        group: _s(j['group']),
        province: _s(j['province']),
        district: _s(j['district']),
        area: _s(j['area']),
        address: _s(j['address']),
        ts: _s(j['ts'] ?? j['createdAt'] ?? j['date']),
      photo: _s(j['photo'] ?? j['photoUrl'] ?? j['image']),
        phone: _s(j['phone']),
      );
}

/// One feed post (newest first from the server).
class FeedPost {
  const FeedPost({
    required this.name,
    required this.area,
    required this.group,
    required this.patient,
    required this.place,
    required this.caption,
    required this.photo,
    required this.ts,
  });

  final String name;
  final String area;
  final String group;
  final String patient;
  final String place;
  final String caption;
  final String photo;
  final String ts;

  factory FeedPost.fromJson(Map<String, dynamic> j) => FeedPost(
        name: _s(j['name']),
        area: _s(j['area']),
        group: _s(j['group']),
        patient: _s(j['patient']),
        place: _s(j['place']),
        caption: _s(j['caption']),
        photo: _s(j['photo'] ?? j['photoUrl'] ?? j['image']),
        ts: _s(j['ts'] ?? j['createdAt'] ?? j['date']),
      );
}

String _s(Object? v) => v == null ? '' : v.toString();

/// Display a server timestamp honestly: ISO dates keep their date part,
/// anything else is shown as-is (never invented).
String displayDate(String ts) {
  if (ts.isEmpty) return '';
  final parsed = DateTime.tryParse(ts);
  if (parsed != null) {
    return '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-'
        '${parsed.day.toString().padLeft(2, '0')}';
  }
  if (ts.length >= 10 && ts[4] == '-' && ts[7] == '-') {
    return ts.substring(0, 10);
  }
  return ts;
}

class ApiService {
  static const _offline =
      'انٹرنیٹ نہیں ملا۔ کنکشن چیک کر کے دوبارہ کوشش کریں۔';
  static const _serverBusy =
      'سرور سے جواب نہیں ملا۔ تھوڑی دیر بعد دوبارہ کوشش کریں۔';

  /// Authorization header for the logged-in member, or null when logged
  /// out. Reads `doner_auth_token` directly from SharedPreferences —
  /// the key is canonical in AuthService; this private duplicate keeps
  /// the dependency one-directional (auth_service.dart imports
  /// ApiResult from this file, so this file must not import it back).
  static Future<Map<String, String>?> _authHeaders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('doner_auth_token');
      if (token == null || token.isEmpty) return null;
      return {'Authorization': 'Bearer $token'};
    } catch (_) {
      return null;
    }
  }

  static Future<ApiResult<Map<String, dynamic>?>> _get(
    String path, {
    Map<String, String>? headers,
  }) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
      final request = await client.getUrl(Uri.parse('$societyApiBase$path'));
      headers?.forEach(request.headers.set);
      final response =
          await request.close().timeout(const Duration(seconds: 20));
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode == HttpStatus.unauthorized) {
        return const ApiResult.err('__UNAUTHORIZED__');
      }
      if (response.statusCode != HttpStatus.ok) {
        return const ApiResult.err(_serverBusy);
      }
      final data = jsonDecode(body);
      if (data is List) return ApiResult.ok({'_list': data});
      if (data is Map<String, dynamic>) return ApiResult.ok(data);
      return const ApiResult.err(_serverBusy);
    } on SocketException {
      return const ApiResult.err(_offline);
    } catch (_) {
      return const ApiResult.err(_serverBusy);
    } finally {
      client?.close(force: true);
    }
  }

  static Future<ApiResult<void>> _post(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
    String unauthorizedMessage = _serverBusy,
    // Real upload progress (sent, total) — only wired where the UI
    // shows it (feed photo posts). Never a timer-based fake %.
    void Function(int sent, int total)? onUploadProgress,
  }) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
      final request = await client.postUrl(Uri.parse('$societyApiBase$path'));
      request.headers.contentType = ContentType.json;
      headers?.forEach(request.headers.set);
      final bytes = utf8.encode(jsonEncode(body));
      request.contentLength = bytes.length;
      if (onUploadProgress == null) {
        request.add(bytes);
      } else {
        // Chunked stream so each slice reports real bytes sent.
        const chunkSize = 16 * 1024;
        var sent = 0;
        final stream = Stream<List<int>>.fromIterable(
          [
            for (var off = 0; off < bytes.length; off += chunkSize)
              bytes.sublist(
                  off,
                  (off + chunkSize).clamp(0, bytes.length)),
          ],
        ).map((chunk) {
          sent += chunk.length;
          onUploadProgress(sent, bytes.length);
          return chunk;
        });
        await request.addStream(stream);
      }
      final response =
          await request.close().timeout(const Duration(seconds: 25));
      await response.transform(utf8.decoder).join();
      if (response.statusCode == HttpStatus.unauthorized) {
        return ApiResult.err(unauthorizedMessage);
      }
      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.created) {
        return const ApiResult.err(_serverBusy);
      }
      return const ApiResult.ok(null);
    } on SocketException {
      return const ApiResult.err(_offline);
    } catch (_) {
      return const ApiResult.err(_serverBusy);
    } finally {
      client?.close(force: true);
    }
  }

  static List<T> _listOf<T>(
    ApiResult<Map<String, dynamic>?> r,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    // Bare array is the expected shape; the named-envelope fallbacks
    // cost nothing and keep the app working if the Worker wraps it.
    final data = r.data;
    Object? raw = data?['_list'];
    if (raw is! List) {
      for (final key in ['donors', 'posts', 'feed', 'data', 'items']) {
        if (data?[key] is List) {
          raw = data![key];
          break;
        }
      }
    }
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(fromJson)
        .toList();
  }

  /// Public donors (no phones). Returns newest-first as the server sends.
  static Future<ApiResult<List<PublicDonor>>> fetchPublicDonors() async {
    final r = await _get('/api/donors');
    if (!r.ok) return ApiResult.err(r.error);
    return ApiResult.ok(_listOf(r, PublicDonor.fromJson));
  }

  /// Registers a donor on the server. Phone is sent (admin-only there)
  /// but never logged and never returned to any public view.
  static Future<ApiResult<void>> submitDonor({
    required String name,
    required String phone,
    required String province,
    required String district,
    required String area,
    required String address,
    required String group,
  }) {
    return _post('/api/donors', {
      'name': name,
      'phone': phone,
      'province': province,
      'district': district,
      'area': area,
      'address': address,
      'group': group,
    });
  }

  /// Feed posts, newest first.
  static Future<ApiResult<List<FeedPost>>> fetchFeed() async {
    final r = await _get('/api/feed');
    if (!r.ok) return ApiResult.err(r.error);
    return ApiResult.ok(_listOf(r, FeedPost.fromJson));
  }

  /// Posts a feed update. Requires login: the bearer token goes in
  /// the Authorization header (the old X-Member-Code system is gone).
  /// On 401 the message never hints at any secret.
  static Future<ApiResult<void>> submitFeedPost({
    required String name,
    required String area,
    required String group,
    required String patient,
    required String place,
    required String caption,
    String? photoBase64,
    void Function(int sent, int total)? onUploadProgress,
  }) async {
    if (photoBase64 != null && photoBase64.length * 3 ~/ 4 > 800 * 1024) {
      return Future.value(
        const ApiResult.err('تصویر بہت بڑی ہے — چھوٹی تصویر منتخب کریں۔'),
      );
    }
    final body = <String, dynamic>{
      'name': name,
      'area': area,
      'group': group,
      'patient': patient,
      'place': place,
      'caption': caption,
    };
    if (photoBase64 != null && photoBase64.isNotEmpty) {
      body['photo'] = 'data:image/jpeg;base64,$photoBase64';
    }
    return _post(
      '/api/feed',
      body,
      headers: await _authHeaders(),
      unauthorizedMessage: 'لاگ اِن ضروری ہے',
      onUploadProgress: onUploadProgress,
    );
  }

  /// Admin donor list (WITH phones). The [pin] is session-only and is
  /// sent only as the X-Admin-Key header, never stored or logged.
  /// On 401 the message never hints at the real PIN.
  static Future<ApiResult<List<AdminDonor>>> fetchAdminDonors(
    String pin,
  ) async {
    final r = await _get(
      '/api/admin/donors',
      headers: {'X-Admin-Key': pin},
    );
    if (!r.ok) {
      if (r.error == '__UNAUTHORIZED__') {
        return const ApiResult.err(
          'غلط PIN، یا ایڈمن رسائی ابھی سیٹ نہیں ہوئی',
        );
      }
      return ApiResult.err(r.error);
    }
    return ApiResult.ok(_listOf(r, AdminDonor.fromJson));
  }


  /// Per-device anonymous member identity. LEGACY: the like toggle is
  /// now per logged-in account (bearer token), so nothing calls this
  /// anymore. Kept only so older stored values don't break anything
  /// that might still read the key. It was never a login, never a
  /// phone number, and is never shown in the UI.
  static Future<String> memberId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var id = prefs.getString('doner_member_id');
      if (id == null || id.isEmpty) {
        id = 'doner-${DateTime.now().millisecondsSinceEpoch}-'
            '${(DateTime.now().microsecond % 900000) + 100000}';
        await prefs.setString('doner_member_id', id);
      }
      return id;
    } catch (_) {
      return 'doner-${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  /// POST that returns the decoded JSON body (for like-toggle replies).
  /// Same never-throw, Urdu-error contract as [_post].
  static Future<ApiResult<Map<String, dynamic>?>> _postJson(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
    String unauthorizedMessage = _serverBusy,
  }) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
      final request = await client.postUrl(Uri.parse('$societyApiBase$path'));
      request.headers.contentType = ContentType.json;
      headers?.forEach(request.headers.set);
      request.add(utf8.encode(jsonEncode(body)));
      final response =
          await request.close().timeout(const Duration(seconds: 25));
      final raw = await response.transform(utf8.decoder).join();
      if (response.statusCode == HttpStatus.unauthorized) {
        return ApiResult.err(unauthorizedMessage);
      }
      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.created) {
        return const ApiResult.err(_serverBusy);
      }
      final data = jsonDecode(raw);
      if (data is Map<String, dynamic>) return ApiResult.ok(data);
      return const ApiResult.err(_serverBusy);
    } on SocketException {
      return const ApiResult.err(_offline);
    } catch (_) {
      return const ApiResult.err(_serverBusy);
    } finally {
      client?.close(force: true);
    }
  }

  /// Social home-feed posts, newest first. Public read: no login
  /// needed to VIEW. The bearer token is sent when logged in so the
  /// server can mark each post's `liked` state for this member.
  /// An empty list is honest (the feed starts empty); a backend that
  /// does not serve these endpoints yet surfaces as an error, never
  /// as fake posts.
  static Future<ApiResult<List<SocialPost>>> fetchSocialPosts() async {
    final r = await _get(
      '/api/feed/posts',
      headers: await _authHeaders(),
    );
    if (!r.ok) return ApiResult.err(r.error);
    return ApiResult.ok(_listOf(r, SocialPost.fromJson));
  }

  /// Creates a social post (camera photo + text). Requires login: the
  /// bearer token goes in the Authorization header, and the server
  /// sets the author from the logged-in account — no author or member
  /// code is sent. No phone number is ever sent with a post.
  static Future<ApiResult<void>> createSocialPost({
    required String text,
    String? photoBase64,
    void Function(int sent, int total)? onUploadProgress,
  }) async {
    if (photoBase64 != null && photoBase64.length * 3 ~/ 4 > 800 * 1024) {
      return Future.value(
        const ApiResult.err('تصویر بہت بڑی ہے — چھوٹی تصویر منتخب کریں۔'),
      );
    }
    final body = <String, dynamic>{'text': text};
    if (photoBase64 != null && photoBase64.isNotEmpty) {
      body['photo'] = 'data:image/jpeg;base64,$photoBase64';
    }
    return _post(
      '/api/feed/posts',
      body,
      headers: await _authHeaders(),
      unauthorizedMessage: 'لاگ اِن ضروری ہے',
      onUploadProgress: onUploadProgress,
    );
  }

  /// Toggles the logged-in member's like on a post. Returns
  /// (liked, likeCount) from the server; the UI trusts the server
  /// reply, never a local guess. Requires login (bearer header).
  static Future<ApiResult<(bool, int)>> toggleSocialLike({
    required String postId,
  }) async {
    final r = await _postJson(
      '/api/feed/posts/${Uri.encodeComponent(postId)}/like',
      const {},
      headers: await _authHeaders(),
      unauthorizedMessage: 'لاگ اِن ضروری ہے',
    );
    if (!r.ok) return ApiResult.err(r.error);
    final data = r.data ?? {};
    final liked = data['liked'] == true;
    final count = (data['likeCount'] is int)
        ? data['likeCount'] as int
        : int.tryParse(_s(data['likeCount'])) ?? 0;
    return ApiResult.ok((liked, count));
  }

  /// Comments on a post, oldest first as the server sends them.
  static Future<ApiResult<List<SocialComment>>> fetchSocialComments(
    String postId,
  ) async {
    final r = await _get(
      '/api/feed/posts/${Uri.encodeComponent(postId)}/comments',
    );
    if (!r.ok) return ApiResult.err(r.error);
    return ApiResult.ok(_listOf(r, SocialComment.fromJson));
  }

  /// Adds a text comment. Requires login: the bearer token goes in
  /// the Authorization header, and the server sets the author from
  /// the logged-in account — never a phone number.
  static Future<ApiResult<void>> addSocialComment({
    required String postId,
    required String text,
  }) async {
    return _post(
      '/api/feed/posts/${Uri.encodeComponent(postId)}/comments',
      {'text': text},
      headers: await _authHeaders(),
      unauthorizedMessage: 'لاگ اِن ضروری ہے',
    );
  }

  /// Picks a photo (camera or gallery), compressed by the plugin to
  /// max width 1024 at JPEG quality ~70. Returns base64 on success, or
  /// an Urdu error (including the over-~800KB rejection). Never throws.
  static Future<PickedPhoto> pickPhoto(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        imageQuality: 70,
      );
      if (file == null) return const PickedPhoto.cancelled();
      final bytes = await file.readAsBytes();
      if (bytes.length > 800 * 1024) {
        return const PickedPhoto.err(
          'تصویر بہت بڑی ہے — چھوٹی تصویر منتخب کریں۔',
        );
      }
      return PickedPhoto.ok(base64Encode(bytes));
    } catch (_) {
      return const PickedPhoto.err(
        'تصویر نہیں لی جا سکی۔ کیمرہ/گیلری کی اجازت چیک کریں۔',
      );
    }
  }
}


/// One social home-feed post. Deliberately has NO phone field — feed
/// posts show name + photo + text ONLY, exactly like the public donor
/// rows. Phone numbers stay admin-only (see fetchAdminDonors) and are
/// never part of a feed payload in either direction.
class SocialPost {
  const SocialPost({
    required this.id,
    required this.author,
    required this.text,
    required this.photo,
    required this.ts,
    required this.likeCount,
    required this.commentCount,
    required this.liked,
  });

  final String id;
  final String author;
  final String text;
  final String photo;
  final String ts;
  final int likeCount;
  final int commentCount;
  final bool liked;

  factory SocialPost.fromJson(Map<String, dynamic> j) => SocialPost(
        id: _s(j['id'] ?? j['key']),
        author: _s(j['author'] ?? j['name']),
        text: _s(j['text'] ?? j['caption']),
        photo: _s(j['photo'] ?? j['photoUrl'] ?? j['image']),
        ts: _s(j['ts'] ?? j['createdAt'] ?? j['date']),
        likeCount: (j['likeCount'] is int)
            ? j['likeCount'] as int
            : int.tryParse(_s(j['likeCount'])) ?? 0,
        commentCount: (j['commentCount'] is int)
            ? j['commentCount'] as int
            : int.tryParse(_s(j['commentCount'])) ?? 0,
        liked: j['liked'] == true,
      );

  SocialPost copyWith({bool? liked, int? likeCount, int? commentCount}) =>
      SocialPost(
        id: id,
        author: author,
        text: text,
        photo: photo,
        ts: ts,
        likeCount: likeCount ?? this.likeCount,
        commentCount: commentCount ?? this.commentCount,
        liked: liked ?? this.liked,
      );
}

/// One text comment on a social post. Author + text + time ONLY —
// no phone numbers, ever.
class SocialComment {
  const SocialComment({
    required this.id,
    required this.author,
    required this.text,
    required this.ts,
  });

  final String id;
  final String author;
  final String text;
  final String ts;

  factory SocialComment.fromJson(Map<String, dynamic> j) => SocialComment(
        id: _s(j['id'] ?? j['key']),
        author: _s(j['author'] ?? j['name']),
        text: _s(j['text'] ?? j['comment']),
        ts: _s(j['ts'] ?? j['createdAt'] ?? j['date']),
      );
}

/// Display a social timestamp honestly: epoch milliseconds from the
/// server render as a local date + time; ISO dates keep their date
/// part; anything else is shown as-is (never invented).
String displayDateTime(String ts) {
  if (ts.isEmpty) return '';
  final ms = int.tryParse(ts);
  if (ms != null && ms > 0) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }
  return displayDate(ts);
}

/// Result of a photo pick: base64 data, an Urdu error, or a cancellation.
class PickedPhoto {
  const PickedPhoto.ok(this.base64) : error = null, cancelled = false;
  const PickedPhoto.err(this.error) : base64 = null, cancelled = false;
  const PickedPhoto.cancelled()
      : base64 = null,
        error = null,
        cancelled = true;

  final String? base64;
  final String? error;
  final bool cancelled;
}


/// A district in-charge, as returned by GET /api/incharges/:district.
/// Public card data only — name + designation + photo. NEVER a phone
/// number: in-charge phone numbers are admin-only.
class DistrictIncharge {
  const DistrictIncharge({
    required this.district,
    required this.name,
    required this.designation,
    this.photo = '',
  });
  final String district;
  final String name;
  final String designation;
  final String photo;
  factory DistrictIncharge.fromJson(
    Map<String, dynamic> j, {
    String district = '',
  }) =>
      DistrictIncharge(
        district: _s(j['district'] ?? j['city'] ?? district),
        name: _s(j['name']),
        designation:
            _s(j['designation'] ?? j['post'] ?? j['title'] ?? j['role']),
        photo: _s(j['photo'] ?? j['photoUrl'] ?? j['image']),
      );
}

/// One office-bearer, as returned by GET /api/office-bearers. Posts are
/// data-driven from the API — never hardcoded here or in the UI.
class OfficeBearer {
  const OfficeBearer({
    required this.post,
    required this.name,
    this.photo = '',
    this.phone = '',
  });
  final String post;
  final String name;
  final String photo;
  final String phone;
  factory OfficeBearer.fromJson(Map<String, dynamic> j) => OfficeBearer(
        post: _s(j['post'] ?? j['designation'] ?? j['title'] ?? j['role']),
        name: _s(j['name']),
        photo: _s(j['photo'] ?? j['photoUrl'] ?? j['image']),
        phone: _s(j['phone']),
      );
  /// Only the founder's phone number is public — never any other post's.
  bool get showPhone =>
      phone.isNotEmpty && post.toLowerCase().contains('founder');
}

/// In-charge + office-bearers endpoints (Worker v2). Same timeouts as
/// [ApiService]: connect 15s, GET 20s, POST 25s.
class InchargeApi {
  /// GET /api/incharges/:district — public, no phone. The Urdu district
  /// name is translated to the Worker's English district name first.
  /// Returns null when the district has no in-charge or is offline.
  static Future<DistrictIncharge?> fetchIncharge(String districtUrdu) async {
    final String district = districtEnglishName(districtUrdu);
    final ApiResult<Map<String, dynamic>?> r = await ApiService._get(
      '/api/incharges/${Uri.encodeComponent(district)}',
    );
    if (!r.ok || r.data == null) return null;
    Object? raw = r.data!['incharge'] ?? r.data!['data'];
    if (raw is! Map<String, dynamic>) raw = r.data;
    final DistrictIncharge incharge = DistrictIncharge.fromJson(
      raw as Map<String, dynamic>,
      district: district,
    );
    return incharge.name.isEmpty ? null : incharge;
  }

  /// GET /api/office-bearers — public list of ALL posts, data-driven.
  /// Called WITHOUT showPhone, so the server sends no phone numbers.
  static Future<List<OfficeBearer>> fetchOfficeBearers() async {
    final ApiResult<Map<String, dynamic>?> r =
        await ApiService._get('/api/office-bearers');
    if (!r.ok || r.data == null) return const [];
    final Map<String, dynamic> data = r.data!;
    Object? raw = data['_list'];
    if (raw is! List) {
      for (final String key in const [
        'officeBearers',
        'office_bearers',
        'bearers',
        'data',
        'items',
      ]) {
        if (data[key] is List) {
          raw = data[key];
          break;
        }
      }
    }
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(OfficeBearer.fromJson)
        .where((OfficeBearer b) => b.name.isNotEmpty)
        .toList();
  }

  /// GET /api/incharge/donors — the logged-in in-charge's own district.
  static Future<ApiResult<List<PublicDonor>>> fetchMyDonors() async {
    final ApiResult<Map<String, dynamic>?> r = await ApiService._get(
      '/api/incharge/donors',
      headers: await ApiService._authHeaders(),
    );
    if (!r.ok) return ApiResult.err(r.error);
    return ApiResult.ok(ApiService._listOf(r, PublicDonor.fromJson));
  }

  /// POST /api/incharge/donors — the district is FORCED server-side to
  /// the in-charge's own district; the client sends it only so the
  /// request stays readable. [photoBase64] is the raw base64 of a ~120px
  /// JPEG (1-10 KB); the server cap is 30k chars, enforced here too.
  static Future<ApiResult<void>> submitDonor({
    required String name,
    required String phone,
    required String province,
    required String district,
    required String area,
    required String address,
    required String group,
    String? photoBase64,
  }) async {
    if (photoBase64 != null && photoBase64.length > 28000) {
      return const ApiResult.err(
        'تصویر بہت بڑی ہے — چھوٹی تصویر منتخب کریں۔',
      );
    }
    final Map<String, dynamic> body = <String, dynamic>{
      'name': name,
      'phone': phone,
      'province': province,
      'district': district,
      'area': area,
      'address': address,
      'group': group,
    };
    if (photoBase64 != null && photoBase64.isNotEmpty) {
      body['photo'] = 'data:image/jpeg;base64,$photoBase64';
    }
    return ApiService._post(
      '/api/incharge/donors',
      body,
      headers: await ApiService._authHeaders(),
      unauthorizedMessage: 'لاگ اِن ضروری ہے',
    );
  }

  /// Picks a TINY donor photo: ~120px JPEG, quality ~50 — typically
  /// 1-10 KB, always well under the server's 30k-char cap. Same
  /// [PickedPhoto] result type as [ApiService.pickPhoto].
  static Future<PickedPhoto> pickTinyPhoto(ImageSource source) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? file = await picker.pickImage(
        source: source,
        maxWidth: 120,
        maxHeight: 120,
        imageQuality: 50,
      );
      if (file == null) return const PickedPhoto.cancelled();
      final Uint8List bytes = await file.readAsBytes();
      final String b64 = base64Encode(bytes);
      if (b64.length > 28000) {
        return const PickedPhoto.err(
          'تصویر بہت بڑی ہے — چھوٹی تصویر منتخب کریں۔',
        );
      }
      return PickedPhoto.ok(b64);
    } catch (_) {
      return const PickedPhoto.err(
        'تصویر نہیں لی جا سکی۔ کیمرہ/گیلری کی اجازت چیک کریں۔',
      );
    }
  }
}
