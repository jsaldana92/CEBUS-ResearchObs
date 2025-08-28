import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

class DropboxMetadata {
  final String pathLower; // normalized, lower-case path (e.g., "/researchobs/griffin")

  DropboxMetadata({required this.pathLower});

  factory DropboxMetadata.fromJson(Map<String, dynamic> j) {
    // Dropbox returns "path_lower" and "path_display". Root can be null.
    final lower = (j['path_lower'] ?? j['path_display'] ?? '/') as String;
    return DropboxMetadata(pathLower: lower.isEmpty ? '/' : lower);
  }
}

class DropboxUploadService {

  // Convert folderId to path; fall back to provided path if needed.
  static Future<String> resolveFolderPath({
    required String folderId,
    String? pathLowerFallback,
  }) async {
    // Try metadata by ID (robust to renames/moves).
    try {
      final meta = await getMetadataById(folderId); // implement via /files/get_metadata
      // meta.pathLower is reliable
      return meta.pathLower;
    } catch (_) {
      if (pathLowerFallback != null) return pathLowerFallback;
      rethrow;
    }
  }

  // Use chunked upload for resilience.
  static Future<void> uploadFileChunked({
    required String accessToken,
    required String localFilePath,
    required String dropboxDestPath, // should include the filename, e.g., "/folder/file.txt"
    int chunkSize = 8 * 1024 * 1024, // 8 MB
  }) async {
    final file = File(localFilePath);
    if (!await file.exists()) {
      throw Exception('File not found: $localFilePath');
    }

    // Normalize path to start with "/"
    final String destPath = dropboxDestPath.startsWith('/')
        ? dropboxDestPath
        : '/$dropboxDestPath';

    final length = await file.length();

    // Small files → simple upload endpoint
    if (length <= chunkSize) {
      final bytes = await file.readAsBytes();
      final resp = await http.post(
        Uri.parse('https://content.dropboxapi.com/2/files/upload'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/octet-stream',
          'Dropbox-API-Arg': jsonEncode({
            'path': destPath,
            'mode': 'add',
            'autorename': true,
            'mute': false,
            'strict_conflict': false,
          }),
        },
        body: bytes,
      );
      if (resp.statusCode != 200) {
        throw Exception('Upload failed: ${resp.statusCode} ${resp.body}');
      }
      return;
    }

    // Large files → session upload
    final raf = await file.open(mode: FileMode.read);
    try {
      // 1) start
      final firstChunk = await raf.read(chunkSize);
      final startResp = await http.post(
        Uri.parse('https://content.dropboxapi.com/2/files/upload_session/start'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/octet-stream',
          'Dropbox-API-Arg': jsonEncode({'close': false}),
        },
        body: firstChunk,
      );
      if (startResp.statusCode != 200) {
        throw Exception('Session start failed: ${startResp.statusCode} ${startResp.body}');
      }
      final sessionId = (jsonDecode(startResp.body) as Map)['session_id'] as String;

      int offset = firstChunk.length;

      // 2) append chunks until the last one
      while (offset < length) {
        final remaining = length - offset;
        final toRead = remaining < chunkSize ? remaining : chunkSize;
        final chunk = await raf.read(toRead);

        final isLast = (offset + chunk.length) >= length;
        if (!isLast) {
          final appendResp = await http.post(
            Uri.parse('https://content.dropboxapi.com/2/files/upload_session/append_v2'),
            headers: {
              'Authorization': 'Bearer $accessToken',
              'Content-Type': 'application/octet-stream',
              'Dropbox-API-Arg': jsonEncode({
                'cursor': {'session_id': sessionId, 'offset': offset},
                'close': false,
              }),
            },
            body: chunk,
          );
          if (appendResp.statusCode != 200) {
            throw Exception('Session append failed: ${appendResp.statusCode} ${appendResp.body}');
          }
          offset += chunk.length;
        } else {
          // 3) finish with the last chunk as the body
          final finishResp = await http.post(
            Uri.parse('https://content.dropboxapi.com/2/files/upload_session/finish'),
            headers: {
              'Authorization': 'Bearer $accessToken',
              'Content-Type': 'application/octet-stream',
              'Dropbox-API-Arg': jsonEncode({
                'cursor': {'session_id': sessionId, 'offset': offset},
                'commit': {
                  'path': destPath,
                  'mode': 'add',
                  'autorename': true,
                  'mute': false,
                  'strict_conflict': false,
                },
              }),
            },
            body: chunk,
          );
          if (finishResp.statusCode != 200) {
            throw Exception('Session finish failed: ${finishResp.statusCode} ${finishResp.body}');
          }
          offset += chunk.length; // not strictly needed after finish
        }
      }
    } finally {
      await raf.close();
    }
  }


  static Future<DropboxMetadata> getMetadataById(String id) async {
    // We read the token from SharedPreferences (same key you use elsewhere)
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('dropbox_access_token');
    if (token == null || token.isEmpty) {
      throw Exception('No Dropbox access token');
    }

    // Dropbox allows "id:xxxx" in the 'path' field to query by file/folder ID.
    final pathArg = id.startsWith('id:') ? id : 'id:$id';

    final resp = await http.post(
      Uri.parse('https://api.dropboxapi.com/2/files/get_metadata'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'path': pathArg,
        'include_property_groups': false,
      }),
    );

    if (resp.statusCode != 200) {
      throw Exception('get_metadata failed: ${resp.statusCode} ${resp.body}');
    }

    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return DropboxMetadata.fromJson(json);
  }


  static Future<bool> uploadFile(String filename, String dropboxPath) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('dropbox_access_token');


    if (token == null || token.isEmpty) {
      print('❌ No access token found.');
      return false;
    }

    // Get the file
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$filename');

    if (!await file.exists()) {
      print('❌ File does not exist: ${file.path}');
      return false;
    }

    final bytes = await file.readAsBytes();

    final uri = Uri.parse('https://content.dropboxapi.com/2/files/upload');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Dropbox-API-Arg': jsonEncode({
          'path': '/$dropboxPath/$filename',
          'mode': 'add',
          'autorename': true,
          'mute': false,
        }),
        'Content-Type': 'application/octet-stream',
      },
      body: bytes,
    );

    if (response.statusCode == 200) {
      print('✅ File uploaded to Dropbox!');
      return true;
    } else {
      print('❌ Dropbox upload failed: ${response.body}');
      return false;
    }
  }
}
