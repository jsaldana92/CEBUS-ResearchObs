// lib/dropbox_folder_picker.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dropbox_token.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';


class DropboxFolderPicker extends StatefulWidget {
  const DropboxFolderPicker({super.key});

  @override
  State<DropboxFolderPicker> createState() => _DropboxFolderPickerState();
}

class _DropboxFolderPickerState extends State<DropboxFolderPicker> {
  String currentPath = ''; // '' == app root
  List<String> folderNames = [];
  bool isLoading = true;
  String? _error;

  // Keys for caching
  static const _kLastFolderPathKey = 'dropbox_last_folder_path';
  static const _kCachePrefix = 'dropbox_cache_for_path:'; // + normalized path

  DateTime? _cacheFetchedAt;
  bool _usingCache = false;
  String? _lastUsedPath;

  String _normalizePath(String p) => p.isEmpty ? '/' : p;

// Cache helpers
  Future<void> _saveCacheForPath(String path, List<String> names) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_kCachePrefix${_normalizePath(path)}';
    final payload = jsonEncode({
      'ts': DateTime.now().toIso8601String(),
      'entries': names,
    });
    await prefs.setString(key, payload);
  }

  Future<(List<String> names, DateTime ts)?> _loadCacheForPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_kCachePrefix${_normalizePath(path)}';
    final raw = prefs.getString(key);
    if (raw == null) return null;
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final ts = DateTime.tryParse(j['ts'] as String? ?? '');
    final entries = (j['entries'] as List?)?.cast<String>() ?? const <String>[];
    if (ts == null) return null;
    return (entries, ts);
  }

// Last-used path
  Future<void> _saveLastUsedPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastFolderPathKey, _normalizePath(path));
    setState(() => _lastUsedPath = _normalizePath(path));
  }

  Future<void> _loadLastUsedPath() async {
    final prefs = await SharedPreferences.getInstance();
    final p = prefs.getString(_kLastFolderPathKey);
    if (!mounted) return;
    setState(() => _lastUsedPath = p);
  }


  @override
  void initState() {
    super.initState();
    _loadLastUsedPath();
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    if (!mounted) return;
    setState(() {
      isLoading = true;
      _error = null;
      _usingCache = false;
      _cacheFetchedAt = null;
    });

    try {
      // 1) Get token
      final token = await getDropboxToken();
      if (token == null || token.isEmpty) {
        // Fall back to cache if available
        final cached = await _loadCacheForPath(currentPath);
        if (cached != null) {
          if (!mounted) return;
          setState(() {
            folderNames = cached.$1;
            _usingCache = true;
            _cacheFetchedAt = cached.$2;
          });
          return;
        }
        if (!mounted) return;
        setState(() {
          _error = 'Not connected to Dropbox. Please log in.';
        });
        return;
      }

      // 2) Build request body – '' means root
      final body = jsonEncode({
        'path': currentPath.isEmpty ? '' : currentPath,
        'recursive': false,
        'include_deleted': false,
        'include_non_downloadable_files': true,
      });

      // 3) Call API with a timeout
      final res = await http
          .post(
        Uri.parse('https://api.dropboxapi.com/2/files/list_folder'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: body,
      )
          .timeout(const Duration(seconds: 20));

      // 4) Non-200 → try cache
      if (res.statusCode != 200) {
        final msg = res.body;
        debugPrint('list_folder error ${res.statusCode}: $msg');

        // Try cache before surfacing error
        final cached = await _loadCacheForPath(currentPath);
        if (cached != null) {
          if (!mounted) return;
          setState(() {
            folderNames = cached.$1;
            _usingCache = true;
            _cacheFetchedAt = cached.$2;
          });
          return;
        }

        String friendly = 'Could not load folders (${res.statusCode}).';
        if (msg.contains('invalid_access_token')) {
          friendly = 'Session expired. Please re-connect Dropbox.';
        } else if (msg.contains('missing_scope')) {
          friendly = 'Missing permission. Re-authenticate this app in Dropbox.';
        }

        if (!mounted) return;
        setState(() {
          _error = friendly;
        });
        return;
      }

      // 5) Parse response
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final entries = (data['entries'] as List).cast<Map<String, dynamic>>();

      final names = entries
          .where((e) => e['.tag'] == 'folder')
          .map<String>((e) => e['name'] as String)
          .toList();

      // 6) Save cache on success
      await _saveCacheForPath(currentPath, names);

      // 7) Update UI
      if (!mounted) return;
      setState(() {
        folderNames = names;
        _usingCache = false;
        _cacheFetchedAt = DateTime.now();
      });
    } on TimeoutException {
      debugPrint('list_folder timeout');
      // Try cache on timeout
      final cached = await _loadCacheForPath(currentPath);
      if (cached != null) {
        if (!mounted) return;
        setState(() {
          folderNames = cached.$1;
          _usingCache = true;
          _cacheFetchedAt = cached.$2;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _error = 'Timed out contacting Dropbox. Check your connection.';
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch folders: $e');
      // Try cache on any unexpected error
      final cached = await _loadCacheForPath(currentPath);
      if (cached != null) {
        if (!mounted) return;
        setState(() {
          folderNames = cached.$1;
          _usingCache = true;
          _cacheFetchedAt = cached.$2;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _error = 'Unexpected error loading folders.';
        });
      }
    } finally {
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }



  void _navigateToSubfolder(String subfolderName) {
    setState(() {
      // build the next path safely
      currentPath = currentPath.isEmpty
          ? '/$subfolderName'
          : '$currentPath/$subfolderName';
    });
    _loadFolders();
  }

  void _goBackOneLevel() {
    final lastSlash = currentPath.lastIndexOf('/');
    setState(() {
      currentPath = lastSlash > 0 ? currentPath.substring(0, lastSlash) : '';
    });
    _loadFolders();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Dropbox Folder'),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.5,
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _loadFolders,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ),
          ],
        )
            : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current path: ${currentPath.isEmpty ? '/' : currentPath}'),
            const SizedBox(height: 8),

            if (currentPath.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _goBackOneLevel,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back'),
                ),
              ),

            if (_usingCache && _cacheFetchedAt != null)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(8),
                color: Colors.amber.withOpacity(0.2),
                child: Text(
                  'Offline mode – showing cached folders from '
                      '${_cacheFetchedAt!.toLocal().toString().split(".").first}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),


            const SizedBox(height: 4),

            Expanded(
              child: ListView.builder(
                itemCount: folderNames.length,
                itemBuilder: (_, index) {
                  final name = folderNames[index];
                  return ListTile(
                    leading: const Icon(Icons.folder),
                    title: Text(name),
                    onTap: () => _navigateToSubfolder(name),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: isLoading
              ? null
              : () async {
            // allow selecting root too
            final path = currentPath.isEmpty ? '/' : currentPath;
            await _saveLastUsedPath(path);
            Navigator.pop(context, _normalizePath(path));
          },
          child: const Text('Select This Folder'),
        ),
      ],
    );
  }
}
