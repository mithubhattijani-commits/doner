/// Doner — email+password auth (replaces the old MEMBER_CODE system,
/// Jaani 31 Oct 2026).
///
/// Backend (live, verified 31 Oct 2026):
/// https://aman-blood-donor-society.mithubhattijani.workers.dev
///   POST /api/auth/register {name,email,password,phone,group,city}
///   POST /api/auth/login    {email,password}
///   POST /api/auth/logout   (Authorization: Bearer `<token>`)
///   GET  /api/auth/me       (Authorization: Bearer `<token>`)
///
/// The token + user profile persist in SharedPreferences
/// (doner_auth_token / doner_auth_user) so the session survives app
/// restarts. Every method returns errors as Urdu strings and never
/// throws to the UI.
library;

import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

/// Auth API base (live, verified 31 Oct 2026).
const String authApiBase =
    'https://aman-blood-donor-society.mithubhattijani.workers.dev';

/// Storage keys. ApiService reads `doner_auth_token` directly (private
/// constant there, documented) so this file can import ApiResult from
/// api_service.dart without creating an import cycle.
const String _kToken = 'doner_auth_token';
const String _kUser = 'doner_auth_user';

/// The logged-in member's profile, exactly as the backend returns it.
class AuthUser {
  const AuthUser({
    required this.name,
    required this.email,
    required this.phone,
    required this.group,
    required this.city,
      this.role = '',
      this.district = '',
  });

  final String name;
  final String email;
  final String phone;
  final String group;
  final String city;
    final String role;
    final String district;

  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
        name: _s(j['name']),
        email: _s(j['email']),
        phone: _s(j['phone']),
        group: _s(j['group']),
        city: _s(j['city']),
      role: _s(j['role']),
      district: _s(j['district'] ?? j['city']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'email': email,
        'phone': phone,
        'group': group,
        'city': city,
      'role': role,
      'district': district,
      };
}

String _s(Object? v) => v == null ? '' : v.toString();

class AuthService {
  static const String _offline =
      'انٹرنیٹ نہیں ملا۔ کنکشن چیک کر کے دوبارہ کوشش کریں۔';
  static const String _serverBusy =
      'سرور سے جواب نہیں ملا۔ تھوڑی دیر بعد دوبارہ کوشش کریں۔';

  /// POSTs to an auth endpoint and parses the contract shape
  /// {ok:true, token, user} on 200. On any other status the server's
  /// own Urdu `error` string is surfaced when present, so the user
  /// sees the backend's exact reason (e.g. duplicate email).
  static Future<ApiResult<(String, AuthUser)>> _postAuth(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
      final HttpClientRequest request =
          await client.postUrl(Uri.parse('$authApiBase$path'));
      request.headers.contentType = ContentType.json;
      if (token != null && token.isNotEmpty) {
        request.headers.set('Authorization', 'Bearer $token');
      }
      request.add(utf8.encode(jsonEncode(body)));
      final HttpClientResponse response =
          await request.close().timeout(const Duration(seconds: 25));
      final String raw = await response.transform(utf8.decoder).join();
      final Map<String, dynamic> data = <String, dynamic>{};
      try {
        final Object? decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) data.addAll(decoded);
      } catch (_) {
        // Non-JSON body: fall through to the generic error below.
      }
      if (response.statusCode == HttpStatus.ok && data['ok'] == true) {
        final String tok = _s(data['token']);
        final Object? userRaw = data['user'];
        if (tok.isEmpty || userRaw is! Map<String, dynamic>) {
          return const ApiResult.err(_serverBusy);
        }
        final AuthUser user = AuthUser.fromJson(userRaw);
        await _saveSession(tok, user);
        return ApiResult.ok((tok, user));
      }
      final Object? serverError = data['error'];
      if (serverError is String && serverError.isNotEmpty) {
        return ApiResult.err(serverError);
      }
      return const ApiResult.err(_serverBusy);
    } on SocketException {
      return const ApiResult.err(_offline);
    } catch (_) {
      return const ApiResult.err(_serverBusy);
    } finally {
      client?.close(force: true);
    }
  }

  static Future<void> _saveSession(String token, AuthUser user) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kToken, token);
      await prefs.setString(_kUser, jsonEncode(user.toJson()));
    } catch (_) {
      // Storage failure: the in-memory result still reaches the UI.
    }
  }

  /// Creates an account and logs in. [group] must be one of the
  /// bloodGroups values (the signup form only offers those, and the
  /// backend validates). A duplicate email surfaces the backend's
  /// Urdu 409 message.
  static Future<ApiResult<(String, AuthUser)>> register({
    required String name,
    required String email,
    required String password,
    required String phone,
    required String group,
    required String city,
  }) {
    return _postAuth('/api/auth/register', <String, dynamic>{
      'name': name,
      'email': email,
      'password': password,
      'phone': phone,
      'group': group,
      'city': city,
    });
  }

  /// Logs in with email + password. A wrong pair surfaces the
  /// backend's Urdu 401 message ('ای میل یا پاس ورڈ درست نہیں').
  static Future<ApiResult<(String, AuthUser)>> login({
    required String email,
    required String password,
  }) {
    return _postAuth('/api/auth/login', <String, dynamic>{
      'email': email,
      'password': password,
    });
  }

  /// Logs out: clears the local session first, then tells the backend
  /// (best-effort — a failed call never blocks the logout).
  static Future<void> logout() async {
    String? token;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      token = prefs.getString(_kToken);
      await prefs.remove(_kToken);
      await prefs.remove(_kUser);
    } catch (_) {
      // Storage failure: still try the backend call below.
    }
    if (token == null || token.isEmpty) return;
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      final HttpClientRequest request = await client
          .postUrl(Uri.parse('$authApiBase/api/auth/logout'));
      request.headers.set('Authorization', 'Bearer $token');
      final HttpClientResponse response =
          await request.close().timeout(const Duration(seconds: 15));
      await response.transform(utf8.decoder).join();
    } catch (_) {
      // Best-effort only.
    } finally {
      client?.close(force: true);
    }
  }

  /// The logged-in user, or null when logged out.
  static Future<AuthUser?> currentUser() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_kUser);
      if (raw == null || raw.isEmpty) return null;
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return AuthUser.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  /// The stored bearer token, or null when logged out.
  static Future<String?> authToken() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString(_kToken);
      return (token == null || token.isEmpty) ? null : token;
    } catch (_) {
      return null;
    }
  }

  /// True when a token is stored. The backend is the final judge on
  /// each call; an expired token surfaces there as 'لاگ اِن ضروری ہے'.
  static Future<bool> isLoggedIn() async => await authToken() != null;
}

/// Loads the signed-in account's role + district from GET /api/auth/me
/// (Authorization: Bearer <token>). Returns null when there is no token or
/// the call fails. Accepts both `{ok:true, user:{...}}` and a bare user
/// object, and role/district at the top level or inside `user`. On success
/// the saved session is refreshed (token unchanged) so the in-charge
/// screens can read the district without another call. Never throws.
Future<AuthUser?> fetchAuthMe() async {
  final String? token = await AuthService.authToken();
  if (token == null || token.isEmpty) return null;
  HttpClient? client;
  try {
    client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    final HttpClientRequest request =
        await client.getUrl(Uri.parse('$authApiBase/api/auth/me'));
    request.headers
      ..set('Authorization', 'Bearer $token')
      ..set('Accept', 'application/json');
    final HttpClientResponse response =
        await request.close().timeout(const Duration(seconds: 20));
    final String body = await response.transform(utf8.decoder).join();
    if (response.statusCode != HttpStatus.ok) return null;
    final Map<String, dynamic> data =
        jsonDecode(body) as Map<String, dynamic>;
    final Map<String, dynamic> user =
        (data['user'] as Map?)?.cast<String, dynamic>() ?? data;
    final Map<String, dynamic> merged = Map<String, dynamic>.of(user);
    merged['role'] ??= data['role'];
    merged['district'] ??= data['district'];
    final AuthUser me = AuthUser.fromJson(merged);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUser, jsonEncode(me.toJson()));
    return me;
  } catch (_) {
    return null;
  } finally {
    client?.close(force: true);
  }
}
