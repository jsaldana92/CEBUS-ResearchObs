// lib/storage_page.dart
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'globals.dart';
import 'group_storage_page.dart';
import 'package:media_scanner/media_scanner.dart';

class StoragePage extends StatefulWidget {
  const StoragePage({super.key});

  @override
  State<StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends State<StoragePage> {

  Future<void> _exportAllObservations(BuildContext context) async {
    final appDir = await getApplicationDocumentsDirectory();
    final documentsDir = Directory('/storage/emulated/0/Documents');
    if (!documentsDir.existsSync()) documentsDir.createSync();

    final files = appDir
        .listSync()
        .where((f) => f is File && f.path.endsWith('.txt'))
        .cast<File>()
        .toList();

    for (final file in files) {
      final fileName = file.path.split(Platform.pathSeparator).last;
      final newPath = '${documentsDir.path}/$fileName';
      await file.copy(newPath);

      // 👇 Register file with Media Store
      await MediaScanner.loadMedia(path: newPath);
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('✅ All observations exported to Documents')),
    );
  }


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
                  Text(
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
                child: Text('Cancel'),
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
                        // 0–2 seconds: fill
                        skullOpacity = tick / 20;
                      } else if (tick <= 50) {
                        // 2–5 seconds: blink every 0.5s
                        isBlinking = tick % 5 < 2;
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
                    child: Text('Delete All Obs', style: TextStyle(color: Colors.grey)),
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
        .where((f) => f is File && f.path.endsWith('.txt'))
        .cast<File>()
        .toList();

    for (final file in files) {
      await file.delete();
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('🗑️ All observations deleted')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: true,
        title: Text(''),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          Text(
            'Storage',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 16),
          Text(
            'Select a group to view stored observations:',
            style: TextStyle(fontSize: 16),
          ),
          SizedBox(height: 16),
          ...groupNames.map(
                (group) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0),
              child: ElevatedButton.icon(
                icon: Icon(Icons.folder_open),
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
          SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                icon: Icon(Icons.download),
                label: Text('Export All Obs To Documents'),
                onPressed: () => _exportAllObservations(context),
              ),
              ElevatedButton.icon(
                icon: Icon(Icons.delete_forever, color: Colors.red),
                label: Text('Delete All Obs'),
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
