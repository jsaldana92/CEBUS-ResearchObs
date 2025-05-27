import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dropbox_folder_picker.dart';
import 'dart:convert';



class GroupStoragePage extends StatefulWidget {
  final String groupName;
  const GroupStoragePage({super.key, required this.groupName});

  @override
  State<GroupStoragePage> createState() => _GroupStoragePageState();
}

class _GroupStoragePageState extends State<GroupStoragePage> {
  List<FileSystemEntity> matchingFiles = [];

  @override
  void initState() {
    super.initState();
    _loadMatchingFiles();
  }

  Future<void> _loadMatchingFiles() async {
    final directory = await getApplicationDocumentsDirectory();
    final allFiles = directory.listSync();
    final groupFiles = allFiles.where((f) {
      final name = f.path.split(Platform.pathSeparator).last.toLowerCase();
      return name.endsWith('.txt') && name.contains(widget.groupName.toLowerCase());
    }).toList();

    setState(() {
      matchingFiles = groupFiles;
    });
  }

  void _showDeleteConfirmationDialog(File file, String fileName) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Are you sure you want to delete this observation?"),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.20,
          ),
          child: const SizedBox.shrink(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Do Not Delete Observation"),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.grey.withAlpha(192)), //192/255 = ~75% oppacity
            onPressed: () async {
              await file.delete();
              Navigator.pop(context);
              _loadMatchingFiles();
            },
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(File file, String fileName) async {
    final content = await file.readAsString();
    final controller = TextEditingController(text: content);

    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: EdgeInsets.zero, // remove extra constraints
        child: Center(
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            height: MediaQuery.of(context).size.height * 0.9,
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Edit $fileName', style: Theme.of(context).textTheme.titleLarge),
                SizedBox(height: 12),
                Expanded(
                  child: TextField(
                    controller: controller,
                    maxLines: null,
                    expands: true,
                    keyboardType: TextInputType.multiline,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () async {
                        await file.writeAsString(controller.text);
                        Navigator.pop(context);
                      },
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showViewDialog(File file, String fileName) async {
    final content = await file.readAsString();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(fileName),
        content: SingleChildScrollView(child: Text(content)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          )
        ],
      ),
    );
  }

  void _showDropboxUploadDialog(File file, String fileName) async {
    final selectedFolder = await showDialog<String>(
      context: context,
      builder: (_) => const DropboxFolderPicker(),
    );

    if (selectedFolder == null) return;

    // Normalize path: remove trailing slashes and ensure one leading slash
    String cleanedFolder = selectedFolder.replaceAll(RegExp(r'^/+'), '').replaceAll(RegExp(r'/+$'), '');
    final dropboxPath = '/$cleanedFolder/$fileName';

    final success = await _uploadFileToDropbox(file.path, dropboxPath);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(success ? '✅ Uploaded to $cleanedFolder!' : '❌ Upload failed.')),
    );
  }



  Future<bool> _uploadFileToDropbox(String filePath, String dropboxPath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('dropbox_access_token');
      if (token == null) return false;

      final fileBytes = await File(filePath).readAsBytes();
      final response = await http.post(
        Uri.parse('https://content.dropboxapi.com/2/files/upload'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/octet-stream',
          'Dropbox-API-Arg': jsonEncode({
            'path': dropboxPath,
            'mode': 'overwrite',
            'autorename': false,
            'mute': false,
          }),
        },
        body: fileBytes,
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Dropbox upload error: $e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Files for ${widget.groupName}'),
      ),
      body: matchingFiles.isEmpty
          ? const Center(child: Text('No files found.'))
          : ListView.builder(
        itemCount: matchingFiles.length,
        itemBuilder: (context, index) {
          final file = matchingFiles[index];
          final name = file.path.split(Platform.pathSeparator).last;
          return ListTile(
            title: Text(name),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.description, color: Colors.white),
                  tooltip: 'View',
                  onPressed: () => _showViewDialog(File(file.path), name),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blue),
                  tooltip: 'Edit',
                  onPressed: () => _showEditDialog(File(file.path), name),
                ),
                IconButton(
                  icon: const Icon(Icons.cloud_upload, color: Colors.lightBlueAccent),
                  tooltip: 'Upload to Dropbox',
                  onPressed: () => _showDropboxUploadDialog(File(file.path), name),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  tooltip: 'Delete',
                  onPressed: () => _showDeleteConfirmationDialog(File(file.path), name),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
