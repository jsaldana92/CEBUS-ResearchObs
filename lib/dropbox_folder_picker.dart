// lib/dropbox_folder_picker.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class DropboxFolderPicker extends StatefulWidget {
  const DropboxFolderPicker({super.key});

  @override
  State<DropboxFolderPicker> createState() => _DropboxFolderPickerState();
}

class _DropboxFolderPickerState extends State<DropboxFolderPicker> {
  String currentPath = '';
  List<String> folderNames = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    setState(() => isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('dropbox_access_token');
    if (token == null) return;

    final response = await http.post(
      Uri.parse('https://api.dropboxapi.com/2/files/list_folder'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({"path": currentPath}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final entries = data['entries'] as List;
      setState(() {
        folderNames = entries
            .where((e) => e['.tag'] == 'folder')
            .map<String>((e) => e['name'] as String)
            .toList();
        isLoading = false;
      });
    } else {
      debugPrint('Failed to fetch folders: ${response.body}');
      setState(() => isLoading = false);
    }
  }

  void _navigateToSubfolder(String subfolderName) {
    setState(() {
      currentPath = '$currentPath/$subfolderName'.replaceAll('//', '/');
    });
    _loadFolders();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Select Dropbox Folder'),
      content: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.5,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current path: /${currentPath.trim()}'),
            const SizedBox(height: 8),

            // 👇 Back button appears only if not in root
            if (currentPath.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    final lastSlash = currentPath.lastIndexOf('/');
                    setState(() {
                      currentPath = lastSlash > 0
                          ? currentPath.substring(0, lastSlash)
                          : '';
                    });
                    _loadFolders();
                  },
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back'),
                ),
              ),

            const SizedBox(height: 4),

            // 👇 Folder list
            Expanded(
              child: ListView.builder(
                itemCount: folderNames.length,
                itemBuilder: (_, index) {
                  return ListTile(
                    leading: const Icon(Icons.folder),
                    title: Text(folderNames[index]),
                    onTap: () => _navigateToSubfolder(folderNames[index]),
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
          onPressed: currentPath.trim().isEmpty ? null : () => Navigator.pop(context, currentPath),
          child: const Text('Select This Folder'),
        ),
      ],
    );
  }
}
