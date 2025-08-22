import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kTokenKey = 'dropbox_access_token';

Future<String?> getDropboxToken() async {
  final storage = const FlutterSecureStorage();
  final fromSecure = await storage.read(key: _kTokenKey);
  if (fromSecure != null && fromSecure.isNotEmpty) {
    return fromSecure;
  }

  final prefs = await SharedPreferences.getInstance();
  final fromPrefs = prefs.getString(_kTokenKey);
  if (fromPrefs != null && fromPrefs.isNotEmpty) {
    return fromPrefs;
  }

  return null;
}
