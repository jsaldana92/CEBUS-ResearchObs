// lib/dropbox_folder_picker.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dropbox_token.dart';
import 'dart:async';

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

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    if (!mounted) return;
    setState(() {
      isLoading = true;
      _error = null;
    });

    try {
      // 1) Get token
      final token = await getDropboxToken();
      if (token == null || token.isEmpty) {
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
      });

      // 3) Call API with a timeout (prevents infinite spinner if network stalls)
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

      // 4) Handle non-200s explicitly
      if (res.statusCode != 200) {
        // Show a more helpful message
        final msg = res.body;
        debugPrint('list_folder error ${res.statusCode}: $msg');

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

      // 6) Update UI
      if (!mounted) return;
      setState(() {
        folderNames = entries
            .where((e) => e['.tag'] == 'folder')
            .map<String>((e) => e['name'] as String)
            .toList();
      });
    } on TimeoutException {
      debugPrint('list_folder timeout');
      if (!mounted) return;
      setState(() {
        _error = 'Timed out contacting Dropbox. Check your connection.';
      });
    } catch (e) {
      debugPrint('Failed to fetch folders: $e');
      if (!mounted) return;
      setState(() {
        _error = 'Unexpected error loading folders.';
      });
    } finally {
      // 7) ALWAYS end the spinner
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
            Text('Current path: /${currentPath.trim()}'),
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
          onPressed: (isLoading || _error != null || currentPath.trim().isEmpty)
              ? null
              : () => Navigator.pop(context, currentPath),
          child: const Text('Select This Folder'),
        ),
      ],
    );
  }
}
