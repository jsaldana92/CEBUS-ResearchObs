import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'upload_models.dart';

class OfflineCacheService {
  static const _kLastFolderKey = 'dropbox_last_folder';
  static const _kFolderTreeKey = 'dropbox_folder_tree';
  static const _kUploadQueueKey = 'dropbox_upload_queue_v1';

  // ---- Last used folder ----
  static Future<void> saveLastFolder(CachedDropboxFolder folder) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastFolderKey, jsonEncode(folder.toJson()));
  }

  static Future<CachedDropboxFolder?> loadLastFolder() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kLastFolderKey);
    if (raw == null) return null;
    return CachedDropboxFolder.fromJson(jsonDecode(raw));
  }

  // ---- Folder tree snapshot (optional, shallow) ----
  static Future<void> saveFolderTree(CachedDropboxFolder root) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kFolderTreeKey, jsonEncode(root.toJson()));
  }

  static Future<CachedDropboxFolder?> loadFolderTree() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kFolderTreeKey);
    if (raw == null) return null;
    return CachedDropboxFolder.fromJson(jsonDecode(raw));
  }

  // ---- Upload queue ----
  static Future<List<UploadJob>> loadQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kUploadQueueKey);
    if (raw == null) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map((m) => UploadJob.fromJson(m)).toList();
  }

  static Future<void> saveQueue(List<UploadJob> jobs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kUploadQueueKey,
      jsonEncode(jobs.map((j) => j.toJson()).toList()),
    );
  }
}
