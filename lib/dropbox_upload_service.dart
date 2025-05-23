import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

class DropboxUploadService {
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
