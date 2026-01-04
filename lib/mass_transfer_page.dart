// lib/mass_transfer_page.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:media_scanner/media_scanner.dart';

import 'globals.dart' show groupNames;
import 'dropbox_folder_picker.dart';
import 'upload_queue_manager.dart';
import 'upload_models.dart';
import 'dropbox_oauth_service.dart';
import 'dropbox_upload_service.dart';

/// Private file model for this page (top-level — Dart doesn't support nested classes)
class _MfFileItem {
  final File file;
  final String name;
  final DateTime modified;
  final String group;

  _MfFileItem({
    required this.file,
    required this.name,
    required this.modified,
    required this.group,
  });
}

class MassTransferPage extends StatefulWidget {
  const MassTransferPage({super.key});

  @override
  State<MassTransferPage> createState() => _MassTransferPageState();
}

class _MassTransferPageState extends State<MassTransferPage> {
  // Data
  final List<_MfFileItem> _all = [];
  final Set<String> _selectedPaths = {}; // absolute file paths

  // Filters
  DateTime? _startDate;
  DateTime? _endDate;
  final Set<String> _selectedGroups = {};

  // Derived
  List<_MfFileItem> get _filtered {
    Iterable<_MfFileItem> items = _all;

    // Group filter
    if (_selectedGroups.isNotEmpty) {
      items = items.where((f) => _selectedGroups.contains(f.group));
    }

    // Date range (inclusive)
    if (_startDate != null) {
      final s = DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
      items = items.where((f) => !f.modified.isBefore(s));
    }
    if (_endDate != null) {
      final e = DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59, 999);
      items = items.where((f) => !f.modified.isAfter(e));
    }

    final list = items.toList();
    list.sort((a, b) => b.modified.compareTo(a.modified)); // newest first
    return list;
  }

  bool get _anythingSelected => _selectedPaths.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    final dir = await getApplicationDocumentsDirectory();
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.txt'))
        .toList();

    String inferGroup(String name) {
      final lower = name.toLowerCase();
      for (final g in groupNames) {
        if (lower.contains(g.toLowerCase())) return g;
      }
      return 'Unknown';
    }

    final items = <_MfFileItem>[];
    for (final f in files) {
      final name = f.path.split(Platform.pathSeparator).last;
      final modified = await f.lastModified();
      items.add(_MfFileItem(
        file: f,
        name: name,
        modified: modified,
        group: inferGroup(name),
      ));
    }

    if (!mounted) return;
    setState(() {
      _all
        ..clear()
        ..addAll(items);
    });
  }

  // ------ Net check ------
  Future<bool> _hasInternet() async {
    try {
      final result = await InternetAddress.lookup('api.dropboxapi.com')
          .timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ------ Selection helpers ------
  void _toggleSelectAllVisible() {
    final visible = _filtered;
    final allSelected = visible.isNotEmpty &&
        visible.every((f) => _selectedPaths.contains(f.file.path));

    setState(() {
      if (allSelected) {
        for (final f in visible) {
          _selectedPaths.remove(f.file.path);
        }
      } else {
        for (final f in visible) {
          _selectedPaths.add(f.file.path);
        }
      }
    });
  }

  void _clearSelection() {
    setState(() => _selectedPaths.clear());
  }

  // ------ Actions ------
  Future<void> _sendSelectedToDropbox() async {
    if (_selectedPaths.isEmpty) return;

    // Pick dest folder (picker supports offline w/ last-used path)
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

    final online = await _hasInternet();

    int uploaded = 0;
    int queued = 0;
    int failed = 0;

    for (final path in _selectedPaths) {
      final item = _all.firstWhere((e) => e.file.path == path, orElse: () => _MfFileItem(
        file: File(path),
        name: path.split(Platform.pathSeparator).last,
        modified: DateTime.fromMillisecondsSinceEpoch(0),
        group: 'Unknown',
      ));
      final destPath = '$destFolder/${item.name}';

      if (online) {
        try {
          await DropboxUploadService.uploadFileChunkedWithValidToken(
            localFilePath: item.file.path,
            dropboxDestPath: destPath,
          );
          uploaded += 1;
          continue;
        } catch (_) {
          // fall through to queue
        }
      }


      try {
        final job = UploadJob(
          localFilePath: item.file.path,
          fileName: item.name,
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
      SnackBar(content: Text('Dropbox: $uploaded uploaded, $queued queued, $failed failed.')),
    );
  }

  Future<void> _exportSelectedToDocuments() async {
    if (_selectedPaths.isEmpty) return;

    final documentsDir = Directory('/storage/emulated/0/Documents');
    if (!documentsDir.existsSync()) documentsDir.createSync();

    int copied = 0;
    int failed = 0;

    for (final path in _selectedPaths) {
      try {
        final item = _all.firstWhere((e) => e.file.path == path);
        final newPath = '${documentsDir.path}/${item.name}';
        await item.file.copy(newPath);
        await MediaScanner.loadMedia(path: newPath);
        copied += 1;
      } catch (_) {
        failed += 1;
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Documents: $copied copied, $failed failed.')),
    );
  }

  // ------ Filter UI helpers ------
  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final initial = _startDate ?? now;
    final res = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1),
      initialDate: initial,
    );
    if (res != null && mounted) {
      setState(() => _startDate = res);
    }
  }

  Future<void> _pickEndDate() async {
    final now = DateTime.now();
    final initial = _endDate ?? now;
    final res = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1),
      initialDate: initial,
    );
    if (res != null && mounted) {
      setState(() => _endDate = res);
    }
  }

  void _resetFilters() {
    setState(() {
      _startDate = null;
      _endDate = null;
      _selectedGroups.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color chipFill = scheme.secondaryContainer;
    final Color chipOnFill = scheme.onSecondaryContainer;
    final visible = _filtered;
    final allSelected = visible.isNotEmpty &&
        visible.every((f) => _selectedPaths.contains(f.file.path));

    final dateBtnStyle = OutlinedButton.styleFrom(
      backgroundColor: chipFill,
      foregroundColor: chipOnFill,
      side: BorderSide(color: chipOnFill.withOpacity(0.4)),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mass Transfer'),
      ),
      body: Column(
        children: [
          // ------- Filters -------
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date range row
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: dateBtnStyle,
                        icon: const Icon(Icons.date_range),
                        label: Text(
                          _startDate == null
                              ? 'Start date'
                              : '${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}',
                        ),
                        onPressed: _pickStartDate,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: dateBtnStyle,
                        icon: const Icon(Icons.event),
                        label: Text(
                          _endDate == null
                              ? 'End date'
                              : '${_endDate!.year}-${_endDate!.month.toString().padLeft(2, '0')}-${_endDate!.day.toString().padLeft(2, '0')}',
                        ),
                        onPressed: _pickEndDate,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Reset filters',
                      onPressed: _resetFilters,
                      icon: const Icon(Icons.restart_alt),
                    ),
                  ],
                ),


                const SizedBox(height: 8),

                // Group multi-select chips
                Row(
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(right: 8.0),
                      child: Text('Groups:'),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: groupNames.map((g) {
                            final selected = _selectedGroups.contains(g);
                            return Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: FilterChip(
                                label: Text(g),
                                selected: selected,
                                onSelected: (val) {
                                  setState(() {
                                    if (val) {
                                      _selectedGroups.add(g);
                                    } else {
                                      _selectedGroups.remove(g);
                                    }
                                  });
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),

          const Divider(height: 1),

          // ------- Bulk actions -------
          Container(
            width: double.infinity,             // take full width
            color: Colors.grey.shade200,        // 👈 background color for whole strip
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Tooltip(
                    message: allSelected ? 'Unselect all' : 'Select all',
                    child: IconButton(
                      onPressed: visible.isEmpty ? null : _toggleSelectAllVisible,
                      icon: Icon(allSelected ? Icons.remove_done : Icons.select_all),
                    ),
                  ),
                  const SizedBox(width: 8),

                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: chipFill,
                      foregroundColor: chipOnFill,
                    ),
                    icon: const Icon(Icons.clear_all_outlined),
                    label: const Text('Clear All'),
                    onPressed: _anythingSelected ? _clearSelection : null,
                  ),
                  const SizedBox(width: 8),

                  FilledButton.icon(
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: const Text('Send to Dropbox'),
                    onPressed: _anythingSelected ? _sendSelectedToDropbox : null,
                  ),
                  const SizedBox(width: 8),

                  FilledButton.icon(
                    icon: const Icon(Icons.folder_copy_outlined),
                    label: const Text('Send to Documents'),
                    onPressed: _anythingSelected ? _exportSelectedToDocuments : null,
                  ),
                ],
              ),
            ),
          ),


          const Divider(height: 1),

          // ------- File list -------
          Expanded(
            child: visible.isEmpty
                ? const Center(child: Text('No files match your filters.'))
                : ListView.builder(
              itemCount: visible.length,
              itemBuilder: (_, i) {
                final it = visible[i];
                final selected = _selectedPaths.contains(it.file.path);
                final dateStr =
                    '${it.modified.year}-${it.modified.month.toString().padLeft(2, '0')}-${it.modified.day.toString().padLeft(2, '0')} '
                    '${it.modified.hour.toString().padLeft(2, '0')}:${it.modified.minute.toString().padLeft(2, '0')}';

                return CheckboxListTile(
                  value: selected,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _selectedPaths.add(it.file.path);
                      } else {
                        _selectedPaths.remove(it.file.path);
                      }
                    });
                  },
                  title: Text(it.name),
                  subtitle: Text('${it.group} • $dateStr'),
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
