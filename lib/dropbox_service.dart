import 'package:flutter_web_auth/flutter_web_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class DropboxService {
  static const _appKey = '7trhu6wr795ibp5';
  static const _redirectUri = 'db-$_appKey://auth'; // 🔑 Don't add 'db-' twice
  static const _tokenKey = 'dropboxAccessToken';

  static Future<void> login() async {
    final authUrl =
        'https://www.dropbox.com/oauth2/authorize?response_type=code&client_id=$_appKey&redirect_uri=$_redirectUri';

    final result = await FlutterWebAuth.authenticate(
      url: authUrl,
      callbackUrlScheme: 'db-$_appKey',
    );

    final code = Uri.parse(result).queryParameters['code'];
    if (code == null) throw Exception("No code returned from Dropbox");

    final response = await http.post(
      Uri.parse('https://api.dropboxapi.com/oauth2/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'code': code,
        'grant_type': 'authorization_code',
        'client_id': _appKey,
        'redirect_uri': _redirectUri,
      },
    );

    if (response.statusCode == 200) {
      final token = json.decode(response.body)['access_token'];
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
    } else {
      throw Exception('Failed to retrieve access token: ${response.body}');
    }
  }

  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_tokenKey);
  }

  static Future<void> uploadFile(String filePath, String dropboxPath) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    if (token == null) throw Exception('Not logged in to Dropbox');

    final bytes = await http.MultipartFile.fromPath('file', filePath);
    final fileContent = await bytes.finalize().toBytes();

    final response = await http.post(
      Uri.parse('https://content.dropboxapi.com/2/files/upload'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/octet-stream',
        'Dropbox-API-Arg': json.encode({
          'path': dropboxPath,
          'mode': 'overwrite',
          'autorename': false,
          'mute': false,
        }),
      },
      body: fileContent,
    );

    if (response.statusCode != 200) {
      throw Exception('Upload failed: ${response.body}');
    }
  }
}
