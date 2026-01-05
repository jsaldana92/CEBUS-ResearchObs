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
import 'achievements_service.dart';
import 'achievement_toast.dart';

import 'package:wakelock_plus/wakelock_plus.dart';


class ObservationPage extends StatefulWidget {
  final String groupName;
  const ObservationPage({Key? key, required this.groupName}) : super(key: key);



  @override
  _ObservationPageState createState() => _ObservationPageState();
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
    final dest =
    dropboxDestPath.startsWith('/') ? dropboxDestPath : '/$dropboxDestPath';

    // Step 4: canonical token pipeline (don’t refresh while offline)
    final online = await _hasInternet();
    if (!online) return false;

    final token = await DropboxOAuthService.getValidAccessToken();
    if (token == null || token.isEmpty) return false;

    bool looksLike401(Object e) {
      final s = e.toString().toLowerCase();
      return s.contains(' 401') ||
          s.contains('status=401') ||
          s.contains('invalid_access_token') ||
          s.contains('expired_access_token');
    }

    Future<void> attemptUpload(String tkn) async {
      await DropboxUploadService.uploadFileChunked(
        accessToken: tkn,
        localFilePath: localFilePath,
        dropboxDestPath: dest,
      );
    }

    try {
      await attemptUpload(token);
      return true;
    } catch (e) {
      // Step 5: 401/expired -> clear access token, refresh once, retry once
      if (looksLike401(e)) {
        try {
          await DropboxOAuthService.clearAccessToken();
          final token2 = await DropboxOAuthService.getValidAccessToken();
          if (token2 != null && token2.isNotEmpty) {
            await attemptUpload(token2);
            return true;
          }
        } catch (_) {
          // fall through
        }
      }
      return false;
    }
  }



  final AudioPlayer _audioPlayer = AudioPlayer();
  // NEW low-latency SFX player + buffers
  final AudioPlayer _sfxPlayer = AudioPlayer(playerId: 'sfx');

  final Map<String, Uint8List> _sfxBytes = {};
  final Map<String, String> _sfxPaths = const {
    'ding':   'sounds/completed_ding.mp3',
    'yay':    'sounds/completed_yay.mp3',
    'press':  'sounds/button_press.mp3',
    'fail':   'sounds/trumpet_fail.mp3',
    'enter':  'sounds/enter_sound.mp3',
    'achv':   'sounds/achievement_unlocked.mp3',
  };

  bool isCurrentAdLib = false;

  List<List<T>> _columnsByRows<T>(List<T> items, int rowsPerCol) {
    if (rowsPerCol <= 0) return [items];
    final cols = <List<T>>[];
    for (int i = 0; i < items.length; i += rowsPerCol) {
      final end = (i + rowsPerCol < items.length) ? i + rowsPerCol : items.length;
      cols.add(items.sublist(i, end));
    }
    return cols;
  }

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

    // Achievements toast sound uses our already-initialized SFX player
    AchievementToast.setSoundPlayer(_sfxPlayer, _sfxPaths['achv']!);

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
    _periodicTimer = Timer.periodic(const Duration(minutes: 3), (timer) {
      _playSfx('ding');          // play first, including tick 10
      if (timer.tick >= 10) {
        timer.cancel();          // stop after the 10th (30:00) ding
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
    WakelockPlus.enable();

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
    WakelockPlus.disable();

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

  // ---------- Achievements: award ONLY if valid complete (must contain a 30:00 timestamp) ----------
  final observer = (globals.selectedExperimenter ?? '').trim();
  final groupName = widget.groupName.trim();

  // Valid complete = reached 30:00+ on the visual timer OR recorded any 30:XX line.
  // Using _elapsedTime is the most reliable because logs only get timestamps when Enter is pressed.
  final has30ByTimer = _elapsedTime >= const Duration(minutes: 30);

  final has30ByLog = observationLog.any((l) => l.startsWith('30:')) ||
      adLibitumLog.any((l) => l.startsWith('30:'));

  final has30 = has30ByTimer || has30ByLog;


    // Rule lock: only award if pressed Complete AND 30:00 was actually recorded in the log
  if (observer.isNotEmpty && has30) {
    final tempRaw = globals.selectedTemperature; // likely String
    final tempF = num.tryParse((tempRaw ?? '').toString().trim());

    final unlocked = await AchievementsService.awardIfCompleted(
      observerName: observer,
      groupName: groupName,
      isValidComplete: true,
      completedAt: DateTime.now(),
      temperatureF: tempF,
      location: globals.selectedLocation,
      timeOfDay: globals.selectedTimeOfDay, // "AM" / "PM"
    );

    // Show Halo/Xbox-style toasts (queued)
    AchievementToast.enqueue(context, unlocked);
  }


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

    // ---------- Step 4: canonical token pipeline ----------
    final online = await _hasInternet();
    final token = online ? await DropboxOAuthService.getValidAccessToken() : null;

    // Try immediate upload if we can, else queue
    if (online && token != null && token.isNotEmpty) {
      Future<void> attemptUpload(String tkn) async {
        await DropboxUploadService.uploadFileChunked(
          accessToken: tkn,
          localFilePath: filePath,
          dropboxDestPath: destPath,
        );
      }

      bool looksLike401(Object e) {
        final s = e.toString().toLowerCase();
        return s.contains(' 401') ||
            s.contains('status=401') ||
            s.contains('invalid_access_token') ||
            s.contains('expired_access_token');
      }

      bool uploaded = false;

      try {
        await attemptUpload(token);
        uploaded = true;
      } catch (e) {
        // Step 5: if 401/expired token, clear access token, refresh, retry once
        if (looksLike401(e)) {
          try {
            await DropboxOAuthService.clearAccessToken();
            final token2 = await DropboxOAuthService.getValidAccessToken();
            if (token2 != null && token2.isNotEmpty) {
              await attemptUpload(token2);
              uploaded = true;
            }
          } catch (_) {
            // fall through to queue
          }
        }

        if (!uploaded) {
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
      }

      if (uploaded) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Uploaded to Dropbox!')),
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
          ? 'Dropbox upload deferred. Queued for later.'
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
              onPressed: () async {
                _playSfx('fail');

                // ---------- Achievements: CANCEL EXCEPTION (27:XX near-complete cancels only) ----------
                final observer = (globals.selectedExperimenter ?? '').trim();
                final has27 = observationLog.any((l) => l.startsWith('27:')) ||
                    adLibitumLog.any((l) => l.startsWith('27:'));

                if (observer.isNotEmpty && has27) {
                  final unlockedFail = await AchievementsService.awardIfCancelledNearComplete(
                    observerName: observer,
                    isCancelledNearComplete: true,
                    cancelledAt: DateTime.now(),
                  );

                  // Show toasts (queued)
                  if (mounted && unlockedFail.isNotEmpty) {
                    AchievementToast.enqueue(context, unlockedFail);
                  }
                }

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
                WakelockPlus.disable();
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
    final line = '$currentTimestamp $currentLine';

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
        ? '$currentTimestamp $currentLine'
        : null;

    return [...displayLog, if (previewLine != null) previewLine].join('\n');
  }




  @override
  void dispose() {
    _logScrollController.dispose();
    _sfxPlayer.dispose();
    _audioPlayer.dispose();

    final homeState = context.findAncestorStateOfType<HomeScreenState>();
    homeState?.resetObservationInputs();

    super.dispose();
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
                        '$currentTimestamp $currentLine',
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
                      final double leftWidth  = constraints.maxWidth * 0.35;
                      final double rightWidth = constraints.maxWidth * 0.65 - kOuterGap;

                      // *** SUBJECTS: make columns with at most 5 items each (column-first) ***
                      final subjectColumns = _columnsByRows<String>(subjects, 5);
                      final int subjectCols = subjectColumns.length;

                      // --- Behavior subcolumn count (dynamic, based on a min column width) ---
                      final int behaviorCols = ((rightWidth + kBehaviorColGutter) /
                          (kMinBehaviorColWidth + kBehaviorColGutter))
                          .floor()
                          .clamp(3, 10);

                      // --- Prepare data in columns ---
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
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    s,
                                    maxLines: 1,
                                    softWrap: false,
                                    overflow: TextOverflow.visible,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
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

                                // Make the vertical divider span the full height of the tallest column
                                IntrinsicHeight(
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      for (int i = 0; i < subjectCols; i++) ...[
                                        Expanded(
                                          child: Padding(
                                            // keep a little horizontal space but no per-button lines
                                            padding: EdgeInsets.only(right: i == subjectCols - 1 ? 0 : 8),
                                            child: buildSubjectColumn(subjectColumns[i]),
                                          ),
                                        ),
                                        if (i != subjectCols - 1)
                                        // a continuous vertical line between the two columns
                                          const SizedBox(
                                            width: 12, // spacing between columns (tweak as you like)
                                            child: VerticalDivider(
                                              thickness: 1,
                                              color: Colors.black26, // or Colors.black12 for lighter
                                            ),
                                          ),
                                      ],
                                    ],
                                  ),
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
