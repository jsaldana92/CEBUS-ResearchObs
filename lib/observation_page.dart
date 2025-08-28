// lib/observation_page.dart
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:async';

import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'globals.dart' as globals;
import 'main.dart';
import 'dropbox_folder_picker.dart';

import 'package:flutter/services.dart' show rootBundle;
import 'dart:typed_data';
import 'upload_queue_manager.dart';
import 'upload_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dropbox_upload_service.dart';
import 'dropbox_oauth_service.dart';


class ObservationPage extends StatefulWidget {
  final String groupName;
  const ObservationPage({Key? key, required this.groupName}) : super(key: key);



  @override
  _ObservationPageState createState() => _ObservationPageState();
}

Future<String?> _loadLastUsedDropboxPath() async {
  final prefs = await SharedPreferences.getInstance();
  // Same key your picker uses
  return prefs.getString('dropbox_last_folder_path');
}

class _ObservationPageState extends State<ObservationPage> {
  Future<bool> _isOnline() async {
    final r = await Connectivity().checkConnectivity();
    return r != ConnectivityResult.none;
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

  Future<bool> _uploadNow({
    required String localFilePath,
    required String dropboxDestPath,
  }) async {
    final token = await DropboxOAuthService.getAccessToken();
    if (token == null || token.isEmpty) return false;

    final dest = dropboxDestPath.startsWith('/') ? dropboxDestPath : '/$dropboxDestPath';
    try {
      await DropboxUploadService.uploadFileChunked(
        accessToken: token,
        localFilePath: localFilePath,
        dropboxDestPath: dest,
      );
      return true;
    } catch (_) {
      return false;
    }
  }


  final AudioPlayer _audioPlayer = AudioPlayer();
  // NEW low-latency SFX player + buffers
  final AudioPlayer _sfxPlayer = AudioPlayer(playerId: 'sfx');

  final Map<String, Uint8List> _sfxBytes = {};
  final Map<String, String> _sfxPaths = const {
    'ding':  'sounds/completed_ding.mp3',
    'yay':   'sounds/completed_yay.mp3',
    'press': 'sounds/button_press.mp3',
    'fail':  'sounds/trumpet_fail.mp3',
    'enter': 'sounds/enter_sound.mp3',
  };

  bool isCurrentAdLib = false;

  List<List<T>> _makeColumns<T>(List<T> items, int columnCount) {
    if (items.isEmpty) return List.generate(columnCount, (_) => <T>[]);
    final cols = List.generate(columnCount, (_) => <T>[]);
    // Distribute items to keep columns balanced top-to-bottom
    for (var i = 0; i < items.length; i++) {
      cols[i % columnCount].add(items[i]);
    }
    return cols;
  }

  Widget _smallAction({
    required BuildContext context,
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 36,
        height: 36,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: enabled ? color.withOpacity(0.12) : Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(
            color: enabled ? color.withOpacity(0.40) : Colors.black12,
          ),
        ),
        child: IconButton(
          splashRadius: 18,
          padding: EdgeInsets.zero,
          iconSize: 30,
          onPressed: onPressed, // null => disabled look
          icon: Icon(
            icon,
            color: enabled ? color : Theme.of(context).disabledColor,
          ),
        ),
      ),
    );
  }


// Spacing
  static const double kOuterGap = 12.0;   // gap between Subjects and Behaviors (the 12px)
  static const double kBehaviorColGutter = 8.0; // gap between behavior subcolumns

// Layout hint: minimum width you'd like for each behavior subcolumn
  static const double kMinBehaviorColWidth = 160.0;

  bool _isRunning = false;

  // scroll control for the top log view
  final ScrollController _logScrollController = ScrollController();

  String currentLine = '';
  List<String> displayLog = []; // For combined visual preview only
  List<String> observationLog = [];
  List<String> adLibitumLog = [];
  String? currentTimestamp;

  Timer? _periodicTimer;
  int _playCount = 0;

  Duration _elapsedTime = Duration.zero;
  Timer? _elapsedTimer;

  String? recordedDateAndTime;

  String _formatDateAndTime(DateTime dateTime) {
    return "${_monthName(dateTime.month)} ${dateTime.day}, ${dateTime.year} "
        "${_formatHour(dateTime)}:${_twoDigits(dateTime.minute)}:${_twoDigits(dateTime.second)} "
        "${dateTime.hour >= 12 ? 'PM' : 'AM'}";
  }

  String _twoDigits(int n) => n.toString().padLeft(2, '0');

  String _formatHour(DateTime dt) {
    final h = dt.hour % 12;
    return (h == 0 ? 12 : h).toString();
  }

  String _monthName(int month) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return months[month - 1];
  }


  late final List<String> subjects;


  @override
  void initState() {
    super.initState();
    UploadQueueManager.I.init();
    subjects = [...(globals.groupMembers[widget.groupName] ?? []), 'Inter-G'];
    _preloadSfx();
  }

  Future<void> _preloadSfx() async {
    try {
      for (final entry in _sfxPaths.entries) {
        final data = await rootBundle.load(entry.value);
        _sfxBytes[entry.key] = data.buffer.asUint8List();
      }
      await _sfxPlayer.setReleaseMode(ReleaseMode.stop);
    } catch (e) {
      debugPrint('SFX preload error: $e');
    }
  }

  Future<void> _playSfx(String key) async {
    try {
      final bytes = _sfxBytes[key];
      if (bytes != null) {
        await _sfxPlayer.play(BytesSource(bytes));
        return;
      }
    } catch (e) {
      // fall through to fallback
    }

    // Fallback: in case preload hasn't finished yet
    final path = _sfxPaths[key];
    if (path != null) {
      await _audioPlayer.play(AssetSource(path));
    }
  }

  Map<String, dynamic> behaviors = {
    'Abnormal': null,
    'Groom': null,
    'Manipulate': null,
    'Play': null,
    'Contact': null,
    'Sexual': null,
    'Share+': ['Active-Share', 'Passive-Share', 'Cofeed', 'Beg'],
    'Proximity': null,
    'Feed+': ['Solo-Feed', 'Proximity-Feed', 'Contact-Feed', 'Forage'],
    'Ab Lib+': {
      'Non-Contact Aggression': 'NC-Aggress*',
      'Contact Aggression': 'C-Aggress*',
      'Intergroup Aggression': 'Aggress* Inter-G',
      'Submissive': 'Submissive*',
      'Solicit': 'Solicit*',
      'Supplant': 'Supplant*',
      'Intervene': 'Intervene*',
      'Post-Conflict Affiliation': 'PC-Affil*',
      'Sexual': 'Sexual*',
      'Intergroup Sexual': 'Sexual* Inter-G',
      'Beg': 'Beg*',
      'Food Share': 'Food-Share*',
    },
    'Inactive': null,
    'Aggress+': ['Aggress', 'Supplant'],
    'Note+': 'text',
    'Locomote': null
  };

  void updateBehaviors(Map<String, dynamic> newBehaviors) {
    setState(() {
      behaviors = newBehaviors;
    });
  }

  void startObservationTimer() {
    _playCount = 0;
    _periodicTimer = Timer.periodic(Duration(minutes: 3), (timer) {
      _playCount += 1;
      if (_playCount >= 10) {
        timer.cancel();
      } else {
        _playSfx('ding');
      }
    });
  }

  void startVisualTimer() {
    _elapsedTime = Duration.zero;
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        _elapsedTime += Duration(seconds: 1);
        if (_elapsedTime >= Duration(minutes: 40)) {
          timer.cancel();
        }
      });
    });
  }

  void _handleStart() {
    _playSfx('ding');

    final now = DateTime.now();
    setState(() {
      observationLog.clear();
      adLibitumLog.clear();
      displayLog.clear();
      currentLine = '';
      currentTimestamp = null;
      isCurrentAdLib = false;
      _elapsedTime = Duration.zero;
      globals.recordedDateAndTime = _formatDateAndTime(now);
      _isRunning = true; // mark running
    });

    startObservationTimer();
    startVisualTimer();
  }

  Future<void> _handleComplete() async {
    if (!_isRunning) return;

    _playSfx('yay');
    _periodicTimer?.cancel();
    _elapsedTimer?.cancel();

    // ---------- Build filename ----------
    final String fileGroup = widget.groupName;
    final String fileGroupHeader = widget.groupName.toUpperCase();
    final String fileDate =
        "${globals.selectedYear ?? 'YYYY'}${(globals.selectedMonth ?? 'MM').padLeft(2, '0')}${(globals.selectedDay ?? 'DD').padLeft(2, '0')}";
    final String fileTimeSuffix = (globals.selectedTimeOfDay ?? 'TIME').toUpperCase();
    final filename = "$fileGroup $fileDate $fileTimeSuffix.txt";

    // ---------- Write to local storage ----------
    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/$filename';
    final file = File(filePath);

    final header = [
      '# Group: $fileGroupHeader',
      '# Date and Time: ${globals.recordedDateAndTime ?? ''}',
      '# Observer: ${globals.selectedExperimenter ?? ''}',
      '# Estrous: ${globals.selectedEstrous ?? ''}',
      '# Location: ${globals.selectedLocation ?? ''}',
      '# Temperature: ${globals.selectedTemperature ?? ''}',
      '# Weather Condition: ${globals.selectedWeather ?? ''}',
      '# Fed: ${globals.selectedFed ?? ''}',
      '# Food in Enclosure: ${globals.selectedFoodPresent ?? ''}',
      '# Comments: ${globals.selectedComments ?? ''}',
      '# Data:',
      '#',
      'Timestamp IndividualA Behavior IndividualB IndividualC IndividualD'
    ];

    final dataLines = observationLog.map((line) => line).toList();
    final ablibLines = ["#", "# Ablib Data:", ...adLibitumLog];
    final allContent = [...header, ...dataLines, ...ablibLines].join('\n');
    await file.writeAsString(allContent);

    // ---------- Ask user for Dropbox folder ----------
    final selectedFolder = await showDialog<String>(
      context: context,
      builder: (_) => const DropboxFolderPicker(),
    );
    if (selectedFolder == null) {
      if (!mounted) return;
      setState(() => _isRunning = false);
      return;
    }

    // Normalize folder path
    String destFolder = selectedFolder.trim();
    destFolder = destFolder.replaceAll(RegExp(r'/+$'), '');
    if (destFolder.isEmpty) destFolder = '/';
    if (!destFolder.startsWith('/')) destFolder = '/$destFolder';

    final destPath = (destFolder == '/')
        ? '/$filename'
        : '$destFolder/$filename';

    // ---------- Single source of truth for token ----------
    final token = await DropboxOAuthService.getAccessToken();
    final online = await _hasInternet();

    // Try immediate upload if we can, else queue
    if (online && token != null && token.isNotEmpty) {
      try {
        await DropboxUploadService.uploadFileChunked(
          accessToken: token,
          localFilePath: filePath,
          dropboxDestPath: destPath,
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Uploaded to Dropbox!')),
        );
      } catch (e) {
        // Fall back to queue on any failure
        final job = UploadJob(
          localFilePath: filePath,
          fileName: filename,
          dropboxFolderId: 'id:unknown',
          pathLowerFallback: destFolder, // e.g. "/ResearchObs/Logan"
        );
        await UploadQueueManager.I.enqueue(job);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('📤 Upload problem; queued for later.')),
        );
      }
    } else {
      // Offline or no token -> queue (and tell the user why)
      final job = UploadJob(
        localFilePath: filePath,
        fileName: filename,
        dropboxFolderId: 'id:unknown',
        pathLowerFallback: destFolder,
      );
      await UploadQueueManager.I.enqueue(job);

      if (!mounted) return;
      final msg = (token == null || token.isEmpty)
          ? 'No Dropbox session detected. Queued for later—please reconnect Dropbox.'
          : 'Offline. Queued for upload when you’re online.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }

    if (!mounted) return;
    setState(() => _isRunning = false);
  }



  void _confirmCancel() {
    if (!_isRunning) return;

    _playSfx('press');

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Cancel Observation?"),
          content: const Text("Are you sure you want to cancel this observation and delete this data?"),
          actions: [
            TextButton(
              child: const Text("No"),
              onPressed: () => Navigator.pop(context),
            ),
            TextButton(
              child: const Text("Yes"),
              onPressed: () {
                _playSfx('fail');
                setState(() {
                  observationLog.clear();
                  adLibitumLog.clear();
                  displayLog.clear();
                  currentLine = '';
                  currentTimestamp = null;
                  isCurrentAdLib = false;
                  _elapsedTime = Duration.zero;
                  _isRunning = false;
                });
                _elapsedTimer?.cancel();
                _periodicTimer?.cancel();
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }


  void addBehavior(String behavior) async {
    if (behavior.endsWith('+')) {
      final nestedOptions = behaviors[behavior];

      if (nestedOptions == 'text') {
        final controller = TextEditingController();
        final result = await showDialog<String>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text('Enter a note'),
            content: TextField(controller: controller, maxLines: 3),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, controller.text),
                child: Text('Save'),
              ),
            ],
          ),
        );
        if (result != null && result.trim().isNotEmpty) {
          addToCurrentLine(result.trim());  // <- already scrolls
        }
      } else if (nestedOptions is List<String> || nestedOptions is Map<String, String>) {
        final isAdLib = behavior == 'Ab Lib+';

        String? selected;
        if (nestedOptions is List<String>) {
          selected = await showDialog<String>(
            context: context,
            builder: (_) => SimpleDialog(
              title: Text('Select ${behavior.replaceAll('+', '')} Behavior'),
              children: nestedOptions.map((b) => SimpleDialogOption(
                child: Text(b),
                onPressed: () => Navigator.pop(context, b),
              )).toList(),
            ),
          );
        } else if (nestedOptions is Map<String, String>) {
          selected = await showDialog<String>(
            context: context,
            builder: (_) => SimpleDialog(
              title: Text('Select ${behavior.replaceAll('+', '')} Behavior'),
              children: nestedOptions.entries.map((entry) => SimpleDialogOption(
                child: Text(entry.key),
                onPressed: () => Navigator.pop(context, entry.key),
              )).toList(),
            ),
          );
        }

        if (selected != null) {
          final valueToInsert = (nestedOptions is Map<String, String>)
              ? nestedOptions[selected]!
              : selected;

          setState(() {
            isCurrentAdLib = isAdLib;
            if (currentLine.isEmpty) {
              currentTimestamp = _formatTime(_elapsedTime);
              currentLine = valueToInsert;
            } else {
              currentLine += ' $valueToInsert';
            }
          });
          _scheduleScrollToEnd(); // <- keep the preview visible
        }
      }
    } else {
      addToCurrentLine(behavior); // <- already scrolls
    }
  }


  void addToCurrentLine(String word) {
    setState(() {
      if (currentLine.isEmpty) {
        currentTimestamp = _formatTime(_elapsedTime);
        currentLine = word;
      } else {
        currentLine += ' $word';
      }
    });
    _scheduleScrollToEnd();
  }

  void finalizeCurrentLine() {
    if (currentLine.trim().isEmpty || currentTimestamp == null) return;
    final line = '[$currentTimestamp] $currentLine';

    setState(() {
      if (isCurrentAdLib) {
        adLibitumLog.add(line);
      } else {
        observationLog.add(line);
      }
      displayLog.add(line);
      currentLine = '';
      currentTimestamp = null;
      isCurrentAdLib = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollLogToEnd());
  }


  void clearCurrentEntry() {
    setState(() {
      currentLine = '';
      currentTimestamp = null;
      isCurrentAdLib = false; // make sure we’re not stuck in ad-lib mode
    });
  }

  void undoLastLine() {
    setState(() {
      if (displayLog.isNotEmpty) {
        final removed = displayLog.removeLast();
        if (observationLog.contains(removed)) {
          observationLog.remove(removed);
        } else if (adLibitumLog.contains(removed)) {
          adLibitumLog.remove(removed);
        }
      }
    });
  }

  void _scrollLogToEnd() {
    if (!_logScrollController.hasClients) return;
    _logScrollController.animateTo(
      _logScrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _scheduleScrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollLogToEnd());
  }


  String _formatTime(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  String get fullTextLog {
    final previewLine = currentLine.isNotEmpty && currentTimestamp != null
        ? '[$currentTimestamp] $currentLine'
        : null;

    return [...displayLog, if (previewLine != null) previewLine].join('\n');
  }




  Future<void> saveAdLibitumLog() async {
    if (adLibitumLog.isEmpty) return;

    // 1) Write the CSV to app documents
    final now = DateTime.now();
    final filename = '${widget.groupName}_${now.toIso8601String().replaceAll(":", "-")}_adlibitum.csv';
    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/$filename';
    final file = File(filePath);
    final content = adLibitumLog.map((line) => '"$line"').join('\n');
    await file.writeAsString(content);

    // 2) Pick a destination: prefer last-used folder; otherwise ask user
    String? path = await _loadLastUsedDropboxPath();
    if (path == null) {
      path = await showDialog<String>(
        context: context,
        builder: (_) => const DropboxFolderPicker(),
      );
      if (path == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Save cancelled (no Dropbox folder selected).')),
        );
        return;
      }
    }

    // Normalize to leading slash (picker already does this, but just in case)
    if (!path.startsWith('/')) path = '/$path';

    // 3) Enqueue the upload (offline-safe)
    final job = UploadJob(
      localFilePath: filePath,
      fileName: filename,
      dropboxFolderId: 'id:unknown',   // forces resolveFolderPath to use fallback if needed
      pathLowerFallback: path,         // e.g., "/ResearchObs/Logan"
    );
    await UploadQueueManager.I.enqueue(job);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('📤 Ad-lib log queued for Dropbox. I’ll send it when you’re online.')),
    );
  }




  @override
  void dispose() {
    _logScrollController.dispose();
    _sfxPlayer.dispose();   // NEW
    _audioPlayer.dispose(); // recommended
    super.dispose();
    final homeState = context.findAncestorStateOfType<HomeScreenState>();
    homeState?.resetObservationInputs();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Group Scan Obs"),
        actions: [
          // progress ring (unchanged)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 40, height: 40,
                  child: CircularProgressIndicator(
                    value: _elapsedTime.inSeconds / (30 * 60),
                    strokeWidth: 5,
                    backgroundColor: Colors.grey,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                  ),
                ),
                if (_elapsedTime >= const Duration(minutes: 30))
                  const Icon(Icons.check, color: Colors.white),
              ],
            ),
          ),

          // timer (unchanged)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Text(
              _formatTime(_elapsedTime),
              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
            ),
          ),
          // compact icon actions
          Builder(builder: (context) {
            return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _smallAction(
                    context: context,
                    icon: Icons.play_arrow,
                    tooltip: 'Start',
                    color: Colors.green,
                    onPressed: _isRunning ? null : _handleStart,
                  ),
                  _smallAction(
                    context: context,
                    icon: Icons.check_circle,
                    tooltip: 'Complete',
                    color: Colors.indigo,
                    onPressed: _isRunning ? () => _handleComplete() : null,
                  ),
                  _smallAction(
                    context: context,
                    icon: Icons.cancel,
                    tooltip: 'Cancel',
                    color: Colors.red,
                    onPressed: _isRunning ? _confirmCancel : null,
                  ),
                  const SizedBox(width: 6),
                ]);
          }),

        ],
      ),





      body: Column(
        children: [
          Container(
            height: MediaQuery.of(context).size.height * 0.4,
            color: Colors.grey[200],
            padding: EdgeInsets.all(12),
            alignment: Alignment.topLeft,
            child: SingleChildScrollView(
              controller: _logScrollController,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // committed lines (unchanged)
                  ...displayLog.map(
                        (line) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(line, style: const TextStyle(fontSize: 16)), // default color
                    ),
                  ),

                  // temporary in-progress line (black bg + white text)
                  if (currentLine.isNotEmpty && currentTimestamp != null)
                    Container(
                      width: double.infinity,
                      color: Colors.grey.shade900, // black background
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        '[$currentTimestamp] $currentLine',
                        style: const TextStyle(fontSize: 16, color: Colors.white), // white text
                      ),
                    ),
                ],
              ),
            ),

          ),
          Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      // --- Big-column widths (with gap subtraction to avoid overflow) ---
                      const int subjectCols = 2;
                      final double leftWidth  = constraints.maxWidth * 0.35;
                      final double rightWidth = constraints.maxWidth * 0.65 - kOuterGap;

                      // --- Behavior subcolumn count (dynamic, based on a min column width) ---
                      // Include gutter in the calculation so we don't over-allocate columns.
                      final int behaviorCols = ((rightWidth + kBehaviorColGutter) /
                          (kMinBehaviorColWidth + kBehaviorColGutter))
                          .floor()
                          .clamp(3, 10);

                      // --- Prepare data in columns ---
                      final subjectColumns  = _makeColumns<String>(subjects, subjectCols);
                      final behaviorKeys    = behaviors.keys.toList();
                      final behaviorColumns = _makeColumns<String>(behaviorKeys, behaviorCols);

                      // --- Builders ---
                      Widget buildSubjectColumn(List<String> col) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: col.map((s) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: ElevatedButton(
                                onPressed: () => addToCurrentLine(s),
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(double.infinity, 44),
                                  alignment: Alignment.center,
                                ),
                                child: Text(s),
                              ),
                            );
                          }).toList(),
                        );
                      }

                      Widget buildBehaviorColumn(List<String> col) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch, // stretch buttons to column width
                          children: col.map((b) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: ElevatedButton(
                                onPressed: () => addBehavior(b),
                                style: ElevatedButton.styleFrom(
                                  // dynamic width via stretch; give a comfy height
                                  minimumSize: const Size(double.infinity, 44),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(b, textAlign: TextAlign.center),
                                ),
                              ),
                            );
                          }).toList(),
                        );
                      }


                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ===== LEFT: SUBJECTS (35%) =====
                          SizedBox(
                            width: leftWidth,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("Subjects", style: TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: List.generate(subjectCols, (i) {
                                    return Expanded(
                                      child: Padding(
                                        padding: EdgeInsets.only(right: i == subjectCols - 1 ? 0 : 8),
                                        child: buildSubjectColumn(subjectColumns[i]),
                                      ),
                                    );
                                  }),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(width: kOuterGap), // the fixed 12px gap

                          // ===== RIGHT: BEHAVIORS (65% minus gap) =====
                          SizedBox(
                            width: rightWidth,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("Behaviors", style: TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),

                                // Each behavior subcolumn is Expanded so it takes an equal share of rightWidth.
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: List.generate(behaviorCols, (i) {
                                    return Expanded(
                                      child: Padding(
                                        padding: EdgeInsets.only(
                                          right: i == behaviorCols - 1 ? 0 : kBehaviorColGutter,
                                        ),
                                        child: buildBehaviorColumn(behaviorColumns[i]),
                                      ),
                                    );
                                  }),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );


                    },
                  ),

                  const SizedBox(height: 12),

                  // ===== Undo / Clear / Enter row =====
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Clear current (only clears the temporary, not the saved log)
                      ElevatedButton.icon(
                        onPressed: currentLine.isEmpty
                            ? null
                            : () {
                          _playSfx('press');
                          clearCurrentEntry();
                        },
                        icon: const Icon(Icons.clear),
                        label: const Text("Clear"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                        ),
                      ),

                      // Undo
                      ElevatedButton.icon(
                        onPressed: undoLastLine,
                        icon: const Icon(Icons.undo),
                        label: const Text("Undo"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                      ),


                      // Enter (finalize current line)
                      ElevatedButton.icon(
                        onPressed: () {
                          _playSfx('enter');
                          finalizeCurrentLine();
                        },
                        icon: const Icon(Icons.keyboard_return),
                        label: const Text("Enter"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  )

                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}
