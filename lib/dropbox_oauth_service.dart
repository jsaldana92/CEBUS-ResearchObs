import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';


class DropboxOAuthService {
  static const String clientId = '7trhu6wr795ibp5';
  static const String redirectUri = 'researchobs://auth';

  static Future<void> authenticate() async {
    final codeVerifier = _generateRandomString(64);
    final codeChallenge = _generateCodeChallenge(codeVerifier); // ✅ Use SHA256 challenge

    final authUrl = Uri.https('www.dropbox.com', '/oauth2/authorize', {
      'client_id': clientId,
      'response_type': 'code',
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256', // ✅ Correct method for hashed challenge
      'redirect_uri': redirectUri,
      'token_access_type': 'offline',
    });

    final result = await FlutterWebAuth2.authenticate(
      url: authUrl.toString(),
      callbackUrlScheme: "researchobs",
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
      final secureStorage = FlutterSecureStorage();
      await secureStorage.write(key: 'dropbox_access_token', value: accessToken);
      print('✅ Dropbox access token securely saved');
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
