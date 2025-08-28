import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';


class DropboxOAuthService {
  static const _kAccessTokenKey = 'dropbox_access_token';

  // Call this after OAuth completes
  static Future<void> saveAccessToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccessTokenKey, token);
  }

  // Used by upload queue, etc.
  static Future<String?> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();

    // 1) Preferred: SharedPreferences (canonical cache the app reads)
    var token = prefs.getString(_kAccessTokenKey);
    if (token != null && token.isNotEmpty) return token;

    // 2) Fallback: Secure storage (where authenticate() currently writes)
    final secureStorage = const FlutterSecureStorage();
    token = await secureStorage.read(key: _kAccessTokenKey);
    if (token != null && token.isNotEmpty) {
      // Migrate into SharedPreferences so the rest of the app can see it
      await prefs.setString(_kAccessTokenKey, token);
      return token;
    }

    return null;
  }

  static Future<void> clearAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccessTokenKey);
    final secureStorage = const FlutterSecureStorage();
    await secureStorage.delete(key: _kAccessTokenKey);
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

    print("🔁 Received redirect result: $result");

    final code = Uri.parse(result).queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw Exception('❌ No authorization code returned from Dropbox redirect: $result');
    }
    print('🔁 Got authorization code: $code');

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

    print('🔍 Raw token response: ${tokenResponse.body}');

    final tokenJson = jsonDecode(tokenResponse.body);
    final accessToken = tokenJson['access_token'];

    if (accessToken is String && accessToken.isNotEmpty) {
      final secureStorage = const FlutterSecureStorage();
      await secureStorage.write(key: _kAccessTokenKey, value: accessToken); // keep secure copy
      await saveAccessToken(accessToken); // also cache in SharedPreferences for the queue
      print('✅ Dropbox access token securely saved & cached');
    } else {
      print('❌ Failed to obtain access token. Full response:');
      print(jsonEncode(tokenJson));
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
