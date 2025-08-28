// lib/storage_page.dart
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'globals.dart';
import 'group_storage_page.dart';
import 'package:media_scanner/media_scanner.dart';
import 'mass_transfer_page.dart';

// NEW: Dropbox + queue imports
import 'dropbox_folder_picker.dart';
import 'upload_queue_manager.dart';
import 'upload_models.dart';
import 'dropbox_oauth_service.dart';
import 'dropbox_upload_service.dart';

class StoragePage extends StatefulWidget {
  const StoragePage({super.key});

  @override
  State<StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends State<StoragePage> {
  // ---------- Helpers ----------
  Future<List<File>> _collectAllTxtFiles() async {
    final appDir = await getApplicationDocumentsDirectory();
    return appDir
        .listSync()
        .where((f) => f is File && f.path.toLowerCase().endsWith('.txt'))
        .cast<File>()
        .toList();
  }

  Future<bool> _hasInternet() async {
    try {
      final result = await InternetAddress.lookup('api.dropboxapi.com')
          .timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ---------- Existing: Export all to Documents ----------
  Future<void> _exportAllObservations(BuildContext context) async {
    final files = await _collectAllTxtFiles();
    if (files.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No observations to export.')),
      );
      return;
    }

    final documentsDir = Directory('/storage/emulated/0/Documents');
    if (!documentsDir.existsSync()) documentsDir.createSync();

    for (final file in files) {
      final fileName = file.path.split(Platform.pathSeparator).last;
      final newPath = '${documentsDir.path}/$fileName';
      await file.copy(newPath);
      await MediaScanner.loadMedia(path: newPath); // register with Media Store
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ All observations exported to Documents')),
    );
  }

  // ---------- NEW: Export all to Dropbox (immediate if possible, else queue) ----------
  Future<void> _exportAllObservationsToDropbox(BuildContext context) async {
    final files = await _collectAllTxtFiles();
    if (files.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No observations to upload.')),
      );
      return;
    }

    // Pick a destination folder (same picker UX across the app)
    final selectedFolder = await showDialog<String>(
      context: context,
      builder: (_) => const DropboxFolderPicker(),
    );
    if (selectedFolder == null) return;

    // Normalize folder
    String destFolder = selectedFolder.trim();
    destFolder = destFolder.replaceAll(RegExp(r'/+$'), '');
    if (destFolder.isEmpty) destFolder = '/';
    if (!destFolder.startsWith('/')) destFolder = '/$destFolder';

    final token = await DropboxOAuthService.getAccessToken();
    final online = await _hasInternet();

    int uploaded = 0;
    int queued = 0;
    int failed = 0;

    for (final file in files) {
      final name = file.path.split(Platform.pathSeparator).last;
      final destPath = '$destFolder/$name';

      if (online && token != null && token.isNotEmpty) {
        try {
          await DropboxUploadService.uploadFileChunked(
            accessToken: token,
            localFilePath: file.path,
            dropboxDestPath: destPath,
          );
          uploaded += 1;
          continue;
        } catch (_) {
          // fall through to queue on any error
        }
      }

      try {
        final job = UploadJob(
          localFilePath: file.path,
          fileName: name,
          dropboxFolderId: 'id:unknown',
          pathLowerFallback: destFolder,
        );
        await UploadQueueManager.I.enqueue(job);
        queued += 1;
      } catch (_) {
        failed += 1;
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Dropbox: $uploaded uploaded, $queued queued, $failed failed.'),
      ),
    );
  }

  // ---------- Delete All (unchanged logic) ----------
  void _confirmDeleteAll(BuildContext context) {
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
                  const Text(
                    'ARE YOU SURE YOU WANT TO DELETE\nALL OF THE OBSERVATIONS?',
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
                        duration: const Duration(milliseconds: 250),
                        child: Image.asset('assets/icon/skull_full_icon.png', width: 100, height: 100),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
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

                  progressTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
                    tick++;

                    if (!isHeld) {
                      timer.cancel();
                      return;
                    }

                    setState(() {
                      if (tick <= 20) {
                        skullOpacity = tick / 20; // fill 0–2s
                      } else if (tick <= 50) {
                        isBlinking = tick % 5 < 2; // blink 2–5s
                        skullOpacity = isBlinking ? 1.0 : 0.0;
                      } else {
                        timer.cancel();
                        _deleteAllObservations(context);
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
                    child: const Text('Delete All Obs', style: TextStyle(color: Colors.grey)),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static Future<void> _deleteAllObservations(BuildContext context) async {
    final appDir = await getApplicationDocumentsDirectory();
    final files = appDir
        .listSync()
        .where((f) => f is File && f.path.toLowerCase().endsWith('.txt'))
        .cast<File>()
        .toList();

    for (final file in files) {
      await file.delete();
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🗑️ All observations deleted')),
      );
    }
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: true,
        title: const Text(''),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          const Text(
            'Storage',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          const Text(
            'Select a group to view stored observations:',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 16),
          ...groupNames.map(
                (group) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.folder_open),
                label: Text(group),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => GroupStoragePage(groupName: group),
                    ),
                  );
                },
              ),
            ),
          ),

          const SizedBox(height: 32),

          // Row 1: Export to Documents + Export to Dropbox
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.download),
                label: const Text('Export All Obs to Documents'),
                onPressed: () => _exportAllObservations(context),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('Export All Obs to Dropbox'),
                onPressed: () => _exportAllObservationsToDropbox(context),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Row 2: Mass Transfer + Delete All
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.unarchive_outlined),
                label: const Text('Mass Transfer'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MassTransferPage()),
                  );
                },
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.delete_forever, color: Colors.red),
                label: const Text('Delete All Obs'),
                style: ElevatedButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () => _confirmDeleteAll(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
