import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _kAccessTokenKey = 'dropbox_access_token';
const _kRefreshTokenKey = 'dropbox_refresh_token';
const _kExpiresAtMsKey = 'dropbox_access_expires_at_ms';

class DropboxSession {
  final String? accessToken;
  final String? refreshToken;
  final int? expiresAtMs;

  const DropboxSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAtMs,
  });
}

Future<DropboxSession> readDropboxSession() async {
  const storage = FlutterSecureStorage();

  final accessToken = await storage.read(key: _kAccessTokenKey);
  final refreshToken = await storage.read(key: _kRefreshTokenKey);
  final expiresAtStr = await storage.read(key: _kExpiresAtMsKey);

  final expiresAtMs = int.tryParse(expiresAtStr ?? '');

  return DropboxSession(
    accessToken: (accessToken != null && accessToken.isNotEmpty) ? accessToken : null,
    refreshToken: (refreshToken != null && refreshToken.isNotEmpty) ? refreshToken : null,
    expiresAtMs: expiresAtMs,
  );
}

/// Step 2 rule lock:
/// Logged in = refresh_token exists.
Future<bool> hasDropboxSession() async {
  final session = await readDropboxSession();
  return session.refreshToken != null && session.refreshToken!.isNotEmpty;
}

/// Backwards-compatible helper (access token only).
Future<String?> getDropboxToken() async {
  final session = await readDropboxSession();
  return session.accessToken;
}
