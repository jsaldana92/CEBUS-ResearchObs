import 'dart:convert';
import 'dart:math';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';


class DropboxOAuthService {
  static const _kAccessTokenKey = 'dropbox_access_token';
  static const _kRefreshTokenKey = 'dropbox_refresh_token';
  static const _kExpiresAtMsKey = 'dropbox_access_expires_at_ms';
  static const FlutterSecureStorage _secure = FlutterSecureStorage();

  // Step 3: proactive refresh buffer (refresh if token expires within this window)
  static const Duration _expiryBuffer = Duration(minutes: 5);

  /// Step 8: non-sensitive auth state snapshot (NO tokens, NO bodies).
  static Future<Map<String, Object?>> authStateSnapshot() async {
    final access = await _secure.read(key: _kAccessTokenKey);
    final refresh = await _secure.read(key: _kRefreshTokenKey);
    final expiresAtStr = await _secure.read(key: _kExpiresAtMsKey);
    final expiresAtMs = int.tryParse(expiresAtStr ?? '');

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final msRemaining = (expiresAtMs == null) ? null : (expiresAtMs - nowMs);

    final needsRefresh = (refresh != null && refresh.isNotEmpty) && (
        (access == null || access.isEmpty) ||
            (expiresAtMs == null) ||
            (expiresAtMs <= nowMs + _expiryBuffer.inMilliseconds)
    );

    return <String, Object?>{
      'has_refresh': refresh != null && refresh.isNotEmpty,
      'has_access': access != null && access.isNotEmpty,
      'expires_at_ms_present': expiresAtMs != null,
      'ms_remaining': msRemaining,
      'needs_refresh': needsRefresh,
    };
  }


  // Step 6: offline behavior — do NOT attempt refresh while offline.
  static Future<bool> _hasInternet() async {
    try {
      final results = await InternetAddress.lookup('api.dropboxapi.com')
          .timeout(const Duration(seconds: 3));
      return results.isNotEmpty && results.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }


  // Call this after OAuth completes
  static Future<void> saveAccessToken(String token) async {
    await _secure.write(key: _kAccessTokenKey, value: token);
  }

  // Used by upload queue, etc.
  static Future<String?> getAccessToken() async {
    final token = await _secure.read(key: _kAccessTokenKey);
    if (token != null && token.isNotEmpty) return token;
    return null;
  }

  /// Step 3: Canonical access-token getter with expiry awareness.
  /// - If token is missing/expired/expiring soon, refresh using refresh_token.
  /// - Returns a usable access token when possible.
  static Future<String?> getValidAccessToken() async {
    final access = await _secure.read(key: _kAccessTokenKey);
    final refresh = await _secure.read(key: _kRefreshTokenKey);
    final expiresAtStr = await _secure.read(key: _kExpiresAtMsKey);
    final expiresAtMs = int.tryParse(expiresAtStr ?? '');

    // If we have no refresh token, we cannot renew silently.
    // Return current access token (may be null/expired); callers will handle failure.
    if (refresh == null || refresh.isEmpty) {
      if (access != null && access.isNotEmpty) return access;
      return null;
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // If we have a non-expiring token record missing expiry, treat it as "needs refresh soon"
    final needsRefresh = (access == null || access.isEmpty)
        || (expiresAtMs == null)
        || (expiresAtMs <= nowMs + _expiryBuffer.inMilliseconds);

    if (!needsRefresh) {
      return access;
    }

    // Step 6: Offline behavior — do not refresh while offline.
    // Return existing access token (even if expired); callers should queue/cache.
    if (!await _hasInternet()) {
      if (access != null && access.isNotEmpty) return access;
      return null;
    }

    // Refresh flow (updates secure storage on success)
    final refreshed = await _refreshAccessToken(refreshToken: refresh);

    if (refreshed != null && refreshed.isNotEmpty) return refreshed;

    // If refresh failed, fall back to existing access token (may still work briefly)
    if (access != null && access.isNotEmpty) return access;
    return null;
  }

  /// Internal: performs refresh_token grant and persists new access token + expires_at.
  static Future<String?> _refreshAccessToken({required String refreshToken}) async {
    try {
      final resp = await http.post(
        Uri.https('api.dropboxapi.com', '/oauth2/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'refresh_token',
          'refresh_token': refreshToken,
          'client_id': clientId,
        },
      );

      if (resp.statusCode != 200) {
        String category = 'http_${resp.statusCode}';
        try {
          final j = jsonDecode(resp.body);
          final err = (j is Map && j['error'] != null) ? j['error'].toString() : '';
          if (err.isNotEmpty) category = err; // e.g., invalid_grant
        } catch (_) {}
        print('[DBX][refresh] failed category=$category status=${resp.statusCode}');
        return null;
      }

      final json = jsonDecode(resp.body);
      final newAccess = json['access_token'];
      final expiresIn = json['expires_in'];

      if (newAccess is String && newAccess.isNotEmpty) {
        await _secure.write(key: _kAccessTokenKey, value: newAccess);

        if (expiresIn is num) {
          final expiresAtMs =
              DateTime.now().millisecondsSinceEpoch + (expiresIn.toInt() * 1000);
          await _secure.write(key: _kExpiresAtMsKey, value: expiresAtMs.toString());
        }

        print('✅ Dropbox access token refreshed');
        return newAccess;
      }

      return null;
    } catch (e) {
      print('❌ Dropbox refresh exception: $e');
      return null;
    }
  }



  static Future<void> clearSession() async {
    await _secure.delete(key: _kAccessTokenKey);
    await _secure.delete(key: _kRefreshTokenKey);
    await _secure.delete(key: _kExpiresAtMsKey);
  }

  /// Step 5 helper: clear only the access token to force refresh
  static Future<void> clearAccessToken() async {
    await _secure.delete(key: _kAccessTokenKey);
    await _secure.delete(key: _kExpiresAtMsKey);
  }

  static const String clientId = 'ss06fg1u0j8j1ad';
  static const String redirectUri = 'cebus-researchobs://auth';

  static Future<void> authenticate() async {
    final codeVerifier = _generateRandomString(64);
    final codeChallenge = _generateCodeChallenge(codeVerifier);

    final authUrl = Uri.https('www.dropbox.com', '/oauth2/authorize', {
      'client_id': clientId,
      'response_type': 'code',
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
      'redirect_uri': redirectUri,
      'token_access_type': 'offline',
    });

    final result = await FlutterWebAuth2.authenticate(
      url: authUrl.toString(),
      callbackUrlScheme: "cebus-researchobs",
    );

    print('[DBX][oauth] redirect received');

    final code = Uri.parse(result).queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw Exception('❌ No authorization code returned from Dropbox redirect: $result');
    }
    print('[DBX][oauth] authorization code received');

    final tokenResponse = await http.post(
      Uri.https('api.dropboxapi.com', '/oauth2/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'code': code,
        'grant_type': 'authorization_code',
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'code_verifier': codeVerifier,
      },
    );


    final tokenJson = jsonDecode(tokenResponse.body);

    final accessToken = tokenJson['access_token'];
    final refreshToken = tokenJson['refresh_token'];
    final expiresIn = tokenJson['expires_in'];

    if (accessToken is String && accessToken.isNotEmpty) {
      // Save access token
      await saveAccessToken(accessToken);

      // Save refresh token (session)
      if (refreshToken is String && refreshToken.isNotEmpty) {
        await _secure.write(key: _kRefreshTokenKey, value: refreshToken);
      }

      // Save expires_at (epoch ms)
      if (expiresIn is num) {
        final expiresAtMs =
            DateTime.now().millisecondsSinceEpoch + (expiresIn.toInt() * 1000);
        await _secure.write(key: _kExpiresAtMsKey, value: expiresAtMs.toString());
      }

      print('✅ Dropbox session saved (access + refresh + expiry)');
    } else {
      print('[DBX][oauth] token exchange failed: missing/invalid access_token');
      throw Exception('Dropbox access token was null or invalid');
    }
  }

  static String _generateRandomString(int length) {
    final rand = Random.secure();
    final chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~';
    return List.generate(length, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  static String _generateCodeChallenge(String verifier) {
    final bytes = ascii.encode(verifier);
    final digest = sha256.convert(bytes);
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }
}
