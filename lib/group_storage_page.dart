// lib/group_storage_page.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';


import 'dropbox_folder_picker.dart';

import 'package:media_scanner/media_scanner.dart';
import 'dart:async';
import 'upload_queue_manager.dart';
import 'upload_models.dart';
import 'dropbox_oauth_service.dart';
import 'dropbox_upload_service.dart';





class GroupStoragePage extends StatefulWidget {
  final String groupName;
  const GroupStoragePage({super.key, required this.groupName});

  @override
  State<GroupStoragePage> createState() => _GroupStoragePageState();
}

class _GroupStoragePageState extends State<GroupStoragePage> {

  Future<bool> _hasInternet() async {
    try {
      final result = await InternetAddress.lookup('api.dropboxapi.com')
          .timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

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

  void _showDeleteConfirmationDialog(File file, String fileName, {bool isGroupDelete = false}) {
    Timer? progressTimer;
    double skullOpacity = 0.0;
    bool isBlinking = false;
    bool isHeld = true;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            content: SizedBox(
              width: MediaQuery.of(context).size.width * 0.8,
              height: MediaQuery.of(context).size.height * 0.3,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    isGroupDelete
                        ? 'ARE YOU SURE YOU WANT TO DELETE\nALL ${widget.groupName.toUpperCase()} OBSERVATIONS?'
                        : 'ARE YOU SURE YOU WANT TO DELETE\n$fileName?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.redAccent,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Image.asset('assets/icon/skull_icon.png', width: 100, height: 100),
                      AnimatedOpacity(
                        opacity: skullOpacity,
                        duration: Duration(milliseconds: 250),
                        child: Image.asset('assets/icon/skull_full_icon.png', width: 100, height: 100),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This action cannot be undone.',
                    style: TextStyle(color: Colors.black87),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  isHeld = false;
                  progressTimer?.cancel();
                  Navigator.pop(context);
                },
                child: const Text('Cancel'),
              ),
              GestureDetector(
                onLongPressStart: (_) {
                  isHeld = true;
                  skullOpacity = 0.0;
                  int tick = 0;

                  progressTimer = Timer.periodic(Duration(milliseconds: 100), (timer) {
                    tick++;

                    if (!isHeld) {
                      timer.cancel();
                      return;
                    }

                    setState(() {
                      if (tick <= 20) {
                        skullOpacity = tick / 20;
                      } else if (tick <= 50) {
                        isBlinking = tick % 5 < 2;
                        skullOpacity = isBlinking ? 1.0 : 0.0;
                      } else {
                        timer.cancel();
                        if (isGroupDelete) {
                          _deleteGroupObservations();
                        } else {
                          file.delete().then((_) => _loadMatchingFiles());
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('🗑️ Deleted $fileName')),
                          );
                        }
                        Navigator.pop(context);
                      }
                    });
                  });
                },
                onLongPressEnd: (_) {
                  isHeld = false;
                  progressTimer?.cancel();
                  setState(() => skullOpacity = 0.0);
                },
                child: Opacity(
                  opacity: 0.6,
                  child: TextButton(
                    onPressed: () {},
                    child: Text(
                      isGroupDelete ? 'Delete All Obs' : 'Delete',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
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
      builder: (_) => Dialog(
        insetPadding: EdgeInsets.zero,
        child: Center(
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            height: MediaQuery.of(context).size.height * 0.9,
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('View $fileName', style: Theme.of(context).textTheme.titleLarge),
                SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(content, style: TextStyle(fontSize: 16)),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  void _showDropboxUploadDialog(File file, String fileName) async {
    // 1) Ask for a Dropbox folder (same picker you already use)
    final selectedFolder = await showDialog<String>(
      context: context,
      builder: (_) => const DropboxFolderPicker(),
    );
    if (selectedFolder == null) return;

    // 2) Normalize the folder path (ensure exactly one leading slash, no trailing slash)
    String destFolder = selectedFolder.trim();
    destFolder = destFolder.replaceAll(RegExp(r'/+$'), '');
    if (destFolder.isEmpty) destFolder = '/';
    if (!destFolder.startsWith('/')) destFolder = '/$destFolder';

    final destPath = '$destFolder/$fileName';

    // 3) Single source of truth for token + online check
    final token = await DropboxOAuthService.getAccessToken();
    final online = await _hasInternet();

    if (online && token != null && token.isNotEmpty) {
      // Try immediate upload first (same chunked uploader used elsewhere)
      try {
        await DropboxUploadService.uploadFileChunked(
          accessToken: token,
          localFilePath: file.path,
          dropboxDestPath: destPath,
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Uploaded to $destFolder')),
        );
        return;
      } catch (e) {
        // Fall through to queue on any failure
      }
    }

    // 4) Offline or upload failed → enqueue for later
    final job = UploadJob(
      localFilePath: file.path,
      fileName: fileName,
      dropboxFolderId: 'id:unknown',
      pathLowerFallback: destFolder, // e.g., "/ResearchObs/Logan"
    );
    await UploadQueueManager.I.enqueue(job);

    if (!mounted) return;
    final msg = (token == null || token.isEmpty)
        ? 'No Dropbox session detected. Queued for later—please reconnect Dropbox.'
        : (online ? 'Upload problem; queued for later.' : 'Offline. Queued for upload when you’re online.');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('📤 $msg')));
  }







  Future<void> _exportGroupObservations(BuildContext context) async {
    final documentsDir = Directory('/storage/emulated/0/Documents');
    if (!documentsDir.existsSync()) documentsDir.createSync();

    for (final file in matchingFiles) {
      final fileName = file.path.split(Platform.pathSeparator).last;
      final newPath = '${documentsDir.path}/$fileName';
      await File(file.path).copy(newPath);
      await MediaScanner.loadMedia(path: newPath);
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('✅ Exported ${widget.groupName} files to Documents')),
    );
  }



  void _deleteGroupObservations() async {
    for (final file in matchingFiles) {
      await File(file.path).delete();
    }
    await _loadMatchingFiles();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('🗑️ All ${widget.groupName} observations deleted')),
      );
    }
  }

  Future<void> _exportSingleObservation(File file, String fileName) async {
    final documentsDir = Directory('/storage/emulated/0/Documents');
    if (!documentsDir.existsSync()) documentsDir.createSync();

    final newPath = '${documentsDir.path}/$fileName';
    await file.copy(newPath);
    await MediaScanner.loadMedia(path: newPath);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('✅ Exported $fileName to Documents')),
    );
  }




  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Files for ${widget.groupName}'),
      ),
      body: Column(
        children: [
          Expanded(
            child: matchingFiles.isEmpty
                ? const Center(child: Text('No files found.'))
                : ListView.builder(
              itemCount: matchingFiles.length,
              itemBuilder: (context, index) {
                final file = matchingFiles[index];
                final name = file.path.split(Platform.pathSeparator).last;
                return ListTile(
                  title: Text(name),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      final fileRef = File(file.path);
                      switch (value) {
                        case 'View':
                          _showViewDialog(fileRef, name);
                          break;
                        case 'Edit':
                          _showEditDialog(fileRef, name);
                          break;
                        case 'Upload':
                          _showDropboxUploadDialog(fileRef, name);
                          break;
                        case 'Delete':
                          _showDeleteConfirmationDialog(fileRef, name, isGroupDelete: false);
                          break;
                        case 'Export':
                          _exportSingleObservation(fileRef, name);
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'View', child: Text('View')),
                      const PopupMenuItem(value: 'Edit', child: Text('Edit')),
                      const PopupMenuItem(value: 'Upload', child: Text('Upload to Dropbox')),
                      const PopupMenuItem(value: 'Export', child: Text('Export to Documents')),
                      const PopupMenuItem(value: 'Delete', child: Text('Delete')),
                    ],
                  ),
                );
              },
            ),
          ),
          if (matchingFiles.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 24, bottom: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    icon: Icon(Icons.download),
                    label: Text('Export ${widget.groupName}\'s Obs'),
                    onPressed: () => _exportGroupObservations(context),
                  ),
                  ElevatedButton.icon(
                    icon: Icon(Icons.delete_forever, color: Colors.red),
                    label: Text('Delete ${widget.groupName}\'s Obs'),
                    style: ElevatedButton.styleFrom(foregroundColor: Colors.red),
                    onPressed: () => _showDeleteConfirmationDialog(File(''), '', isGroupDelete: true),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
